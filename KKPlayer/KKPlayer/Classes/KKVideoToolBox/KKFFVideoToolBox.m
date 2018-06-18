//
//  KKFFVideoToolBox.m
//  KKPlayer
//
//  Created by finger on 2017/2/21.
//  Copyright © 2017年 finger. All rights reserved.
//

#import "KKFFVideoToolBox.h"
#import "KKTools.h"

typedef NS_ENUM(NSUInteger, KKFFVideoToolBoxErrorCode) {
    KKFFVideoToolBoxErrorCodeExtradataSize,
    KKFFVideoToolBoxErrorCodeExtradataData,
    KKFFVideoToolBoxErrorCodeCreateFormatDescription,
    KKFFVideoToolBoxErrorCodeCreateSession,
    KKFFVideoToolBoxErrorCodeNotH264,
};

@interface KKFFVideoToolBox (){
    AVCodecContext *_codecContext;
}
@property(nonatomic)CMFormatDescriptionRef formatDescription ;
@property(nonatomic)VTDecompressionSessionRef decodeSession ;
@property(nonatomic)CVImageBufferRef decodedBuffer ;
@property(nonatomic,assign)OSStatus decodeStatus ;
@property(nonatomic,assign)BOOL sessionEnable;
@property(nonatomic,assign)BOOL needConvertNALSize3To4;
@end

@implementation KKFFVideoToolBox

+ (instancetype)videoToolBoxWithCodecContext:(AVCodecContext *)codecContext{
    return [[self alloc] initWithCodecContext:codecContext];
}

- (instancetype)initWithCodecContext:(AVCodecContext *)codecContext{
    if (self = [super init]) {
        self->_codecContext = codecContext;
    }
    return self;
}

- (void)dealloc{
    [self clean];
    NSLog(@"%@ dealloc-----",NSStringFromClass([self class]));
}

#pragma mark -- 初始化

- (BOOL)trySetupVTSession{
    if (!self.sessionEnable) {
        NSError *error = [self setupVTSession];
        if (!error) {
            self.sessionEnable = YES;
        }
    }
    return self.sessionEnable;
}

- (NSError *)setupVTSession{
    NSError * error;
    enum AVCodecID codecId = self->_codecContext->codec_id;
    uint8_t *extradata = self->_codecContext->extradata;
    NSInteger extradataSize = self->_codecContext->extradata_size;
    
    if (codecId == AV_CODEC_ID_H264) {
        if (extradataSize < 7 || extradata == NULL) {
            error = [NSError errorWithDomain:@"extradata error" code:KKFFVideoToolBoxErrorCodeExtradataSize userInfo:nil];
            return error;
        }
        
        if (extradata[0] == 1) {
            if (extradata[4] == 0xFE) {
                extradata[4] = 0xFF;
                self.needConvertNALSize3To4 = YES;
            }
            self->_formatDescription = CreateFormatDescription(kCMVideoCodecType_H264, (int)(_codecContext->width), (int)(_codecContext->height), extradata, (int)extradataSize);
            if (self->_formatDescription == NULL) {
                error = [NSError errorWithDomain:@"create format description error" code:KKFFVideoToolBoxErrorCodeCreateFormatDescription userInfo:nil];
                return error;
            }
            
            CFMutableDictionaryRef destinationPixelBufferAttributes = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFDictSetInt32(destinationPixelBufferAttributes, kCVPixelBufferPixelFormatTypeKey, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
            CFDictSetInt32(destinationPixelBufferAttributes, kCVPixelBufferWidthKey, _codecContext->width);
            CFDictSetInt32(destinationPixelBufferAttributes, kCVPixelBufferHeightKey, _codecContext->height);
            
            VTDecompressionOutputCallbackRecord outputCallbackRecord;
            outputCallbackRecord.decompressionOutputCallback = outputCallback;
            outputCallbackRecord.decompressionOutputRefCon = (__bridge void *)self;
            
            OSStatus status = VTDecompressionSessionCreate(kCFAllocatorDefault, self->_formatDescription, NULL, destinationPixelBufferAttributes, &outputCallbackRecord, &self->_decodeSession);
            if (status != noErr) {
                error = [NSError errorWithDomain:@"create session error" code:KKFFVideoToolBoxErrorCodeCreateSession userInfo:nil];
                return error;
            }
            CFRelease(destinationPixelBufferAttributes);
            return nil;
        } else {
            error = [NSError errorWithDomain:@"deal extradata error" code:KKFFVideoToolBoxErrorCodeExtradataData userInfo:nil];
            return error;
        }
    } else {
        error = [NSError errorWithDomain:@"not h264 error" code:KKFFVideoToolBoxErrorCodeNotH264 userInfo:nil];
        return error;
    }
    
    return error;
}

#pragma mark -- 将原始的音视频数据加入到数据队列

- (BOOL)sendPacket:(AVPacket)packet {
    
    BOOL setupResult = [self trySetupVTSession];
    
    if (!setupResult) return NO;
    
    [self cleanDecodeInfo];
    
    BOOL result = NO;
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = noErr;
    
    if (self.needConvertNALSize3To4) {
        AVIOContext *ioContext = NULL;
        if (avio_open_dyn_buf(&ioContext) < 0) {
            status = -1900;
        } else {
            uint32_t nalSize;
            uint8_t *end = packet.data + packet.size;
            uint8_t *nalStart = packet.data;
            while (nalStart < end) {
                nalSize = (nalStart[0] << 16) | (nalStart[1] << 8) | nalStart[2];
                avio_wb32(ioContext, nalSize);
                nalStart += 3;
                avio_write(ioContext, nalStart, nalSize);
                nalStart += nalSize;
            }
            uint8_t *demux_buffer = NULL;
            int demux_size = avio_close_dyn_buf(ioContext, &demux_buffer);
            status = CMBlockBufferCreateWithMemoryBlock(NULL, demux_buffer, demux_size, kCFAllocatorNull, NULL, 0, packet.size, FALSE, &blockBuffer);
        }
    } else {
        status = CMBlockBufferCreateWithMemoryBlock(NULL, packet.data, packet.size, kCFAllocatorNull, NULL, 0, packet.size, FALSE, &blockBuffer);
    }
    
    if (status == noErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        status = CMSampleBufferCreate( NULL, blockBuffer, TRUE, 0, 0, self->_formatDescription, 1, 0, NULL, 0, NULL, &sampleBuffer);
        if (status == noErr) {
            //解码成功之后，会触发回调,注意，只有执行完回调后才会执行VTDecompressionSessionDecodeFrame后的代码
            status = VTDecompressionSessionDecodeFrame(self->_decodeSession, sampleBuffer, 0, NULL, 0);
            if (status == noErr) {
                if (self->_decodeStatus == noErr && self->_decodedBuffer != NULL) {
                    result = YES;
                }
            } else if (status == kVTInvalidSessionErr) {
                [self clean];
            }
        }
        if (sampleBuffer) {
            CFRelease(sampleBuffer);
        }
    }
    if (blockBuffer) {
        CFRelease(blockBuffer);
    }
    return result;
}

- (CVImageBufferRef)imageBuffer{
    if (self->_decodeStatus == noErr && self->_decodedBuffer != NULL) {
        return self->_decodedBuffer;
    }
    return NULL;
}

#pragma mark -- 清理

- (void)cleanVTSession{
    if (self->_formatDescription) {
        CFRelease(self->_formatDescription);
        self->_formatDescription = NULL;
    }
    if (self->_decodeSession) {
        VTDecompressionSessionWaitForAsynchronousFrames(self->_decodeSession);
        VTDecompressionSessionInvalidate(self->_decodeSession);
        CFRelease(self->_decodeSession);
        self->_decodeSession = NULL;
    }
    self.needConvertNALSize3To4 = NO;
    self.sessionEnable = NO;
}

- (void)cleanDecodeInfo{
    self->_decodeStatus = noErr;
    //if(self->_decodedBuffer){
        //CVPixelBufferRelease(self->_decodedBuffer);
        self->_decodedBuffer = NULL;
    //}
}

- (void)clean{
    [self cleanVTSession];
    [self cleanDecodeInfo];
}

#pragma mark -- 解码回调

static void outputCallback(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration){
    @autoreleasepool{
        KKFFVideoToolBox *videoToolBox = (__bridge KKFFVideoToolBox *)decompressionOutputRefCon;
        videoToolBox->_decodeStatus = status;
        videoToolBox->_decodedBuffer = imageBuffer;
        if (imageBuffer != NULL) {
            CVPixelBufferRetain(imageBuffer);
        }
    }
}

#pragma mark --

CMFormatDescriptionRef CreateFormatDescription(CMVideoCodecType codecType, int width, int height, const uint8_t *extradata, int extradataSize){
    CMFormatDescriptionRef format_description = NULL;
    OSStatus status;
    
    CFMutableDictionaryRef par = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef atoms = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef extensions = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    // CVPixelAspectRatio
    CFDictSetInt32(par, CFSTR("HorizontalSpacing"), 0);
    CFDictSetInt32(par, CFSTR("VerticalSpacing"), 0);
    
    // SampleDescriptionExtensionAtoms
    CFDictSetData(atoms, CFSTR("avcC"), (uint8_t *)extradata, extradataSize);
    
    // Extensions
    CFDictSetString(extensions, CFSTR ("CVImageBufferChromaLocationBottomField"), "left");
    CFDictSetString(extensions, CFSTR ("CVImageBufferChromaLocationTopField"), "left");
    CFDictSetBoolean(extensions, CFSTR("FullRangeVideo"), FALSE);
    CFDictSetObject(extensions, CFSTR ("CVPixelAspectRatio"), (CFTypeRef *)par);
    CFDictSetObject(extensions, CFSTR ("SampleDescriptionExtensionAtoms"), (CFTypeRef *)atoms);
    
    status = CMVideoFormatDescriptionCreate(NULL, codecType, width, height, extensions, &format_description);
    
    CFRelease(extensions);
    CFRelease(atoms);
    CFRelease(par);
    
    if (status != noErr) {
        return NULL;
    }
    return format_description;
}

@end
