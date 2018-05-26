//
//  KKFFVideoFrame.m
//  KKPlayer
//
//  Created by finger on 2017/2/17.
//  Copyright © 2017年 finger. All rights reserved.
//

#import "KKFFVideoFrame.h"
#import "KKTools.h"

@implementation KKFFVideoFrame

- (KKFFFrameType)type{
    return KKFFFrameTypeVideo;
}

@end


@interface KKFFAVYUVVideoFrame (){
    enum AVPixelFormat pixelFormat;
    size_t channelPixelsBufferSize[KKYUVChannelCount];
    int channelLinesize[KKYUVChannelCount];
}
@property(nonatomic,strong)NSLock *lock;
@end

@implementation KKFFAVYUVVideoFrame

+ (instancetype)videoFrame{
    return [[self alloc] init];
}

- (KKFFFrameType)type{
    return KKFFFrameTypeAVYUVVideo;
}

- (instancetype)init{
    if (self = [super init]) {
        channelLinesize[KKYUVChannelLuma] = 0;
        channelLinesize[KKYUVChannelChromaB] = 0;
        channelLinesize[KKYUVChannelChromaR] = 0;

        channelPixelsBufferSize[KKYUVChannelLuma] = 0;
        channelPixelsBufferSize[KKYUVChannelChromaB] = 0;
        channelPixelsBufferSize[KKYUVChannelChromaR] = 0;

        channelPixelBuffer[KKYUVChannelLuma] = NULL;
        channelPixelBuffer[KKYUVChannelChromaB] = NULL;
        channelPixelBuffer[KKYUVChannelChromaR] = NULL;

        self.lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)setFrameData:(AVFrame *)frame width:(int)width height:(int)height{
    pixelFormat = frame->format;

    self->_width = width;
    self->_height = height;

    int lineSizeY = frame->linesize[KKYUVChannelLuma];
    int lineSizeU = frame->linesize[KKYUVChannelChromaB];
    int lineSizeV = frame->linesize[KKYUVChannelChromaR];

    channelLinesize[KKYUVChannelLuma] = lineSizeY;
    channelLinesize[KKYUVChannelChromaB] = lineSizeU;
    channelLinesize[KKYUVChannelChromaR] = lineSizeV;

    UInt8 *bufferY = channelPixelBuffer[KKYUVChannelLuma];
    UInt8 *bufferU = channelPixelBuffer[KKYUVChannelChromaB];
    UInt8 *bufferV = channelPixelBuffer[KKYUVChannelChromaR];

    size_t bufferSizeY = channelPixelsBufferSize[KKYUVChannelLuma];
    size_t bufferSizeU = channelPixelsBufferSize[KKYUVChannelChromaB];
    size_t bufferSizeV = channelPixelsBufferSize[KKYUVChannelChromaR];

    NSInteger needSizeY = KKYUVChannelFilterNeedSize(lineSizeY, width, height, 1);
    if (bufferSizeY != needSizeY) {
        if (bufferSizeY > 0 && bufferY != NULL) {
            free(bufferY);
        }
        channelPixelsBufferSize[KKYUVChannelLuma] = needSizeY;
        channelPixelBuffer[KKYUVChannelLuma] = malloc(needSizeY);
    }

    int needSizeU = KKYUVChannelFilterNeedSize(lineSizeU, width / 2, height / 2, 1);
    if (bufferSizeU != needSizeU) {
        if (bufferSizeU > 0 && bufferU != NULL) {
            free(bufferU);
        }
        channelPixelsBufferSize[KKYUVChannelChromaB] = needSizeU;
        channelPixelBuffer[KKYUVChannelChromaB] = malloc(needSizeU);
    }

    int needSizeV = KKYUVChannelFilterNeedSize(lineSizeV, width / 2, height / 2, 1);
    if (bufferSizeV != needSizeV) {
        if (bufferSizeV > 0 && bufferV != NULL) {
            free(bufferV);
        }
        channelPixelsBufferSize[KKYUVChannelChromaR] = needSizeV;
        channelPixelBuffer[KKYUVChannelChromaR] = malloc(needSizeV);
    }

    KKYUVChannelFilter(frame->data[KKYUVChannelLuma],
            lineSizeY,
            width,
            height,
            channelPixelBuffer[KKYUVChannelLuma],
            channelPixelsBufferSize[KKYUVChannelLuma],
            1);
    KKYUVChannelFilter(frame->data[KKYUVChannelChromaB],
            lineSizeU,
            width / 2,
            height / 2,
            channelPixelBuffer[KKYUVChannelChromaB],
            channelPixelsBufferSize[KKYUVChannelChromaB],
            1);
    KKYUVChannelFilter(frame->data[KKYUVChannelChromaR],
            lineSizeV,
            width / 2,
            height / 2,
            channelPixelBuffer[KKYUVChannelChromaR],
            channelPixelsBufferSize[KKYUVChannelChromaR],
            1);
}

- (void)flush{
    self->_width = 0;
    self->_height = 0;
    
    channelLinesize[KKYUVChannelLuma] = 0;
    channelLinesize[KKYUVChannelChromaB] = 0;
    channelLinesize[KKYUVChannelChromaR] = 0;
    if (channelPixelBuffer[KKYUVChannelLuma] != NULL &&
        channelPixelsBufferSize[KKYUVChannelLuma] > 0) {
        memset(channelPixelBuffer[KKYUVChannelLuma], 0, channelPixelsBufferSize[KKYUVChannelLuma]);
    }
    if (channelPixelBuffer[KKYUVChannelChromaB] != NULL && channelPixelsBufferSize[KKYUVChannelChromaB] > 0) {
        memset(channelPixelBuffer[KKYUVChannelChromaB], 0, channelPixelsBufferSize[KKYUVChannelChromaB]);
    }
    if (channelPixelBuffer[KKYUVChannelChromaR] != NULL && channelPixelsBufferSize[KKYUVChannelChromaR] > 0) {
        memset(channelPixelBuffer[KKYUVChannelChromaR], 0, channelPixelsBufferSize[KKYUVChannelChromaR]);
    }
}

- (void)stopPlaying{
    [self.lock lock];
    [super stopPlaying];
    [self.lock unlock];
}

- (UIImage *)snapshot{
    [self.lock lock];
    UIImage *image = KKYUVConvertToImage(channelPixelBuffer, channelLinesize, self.width, self.height, pixelFormat);
    [self.lock unlock];
    return image;
}

- (NSInteger)decodedSize{
    return (NSInteger)(channelPixelsBufferSize[KKYUVChannelLuma] + channelPixelsBufferSize[KKYUVChannelChromaB] + channelPixelsBufferSize[KKYUVChannelChromaR]);
}

- (void)dealloc{
    if (channelPixelBuffer[KKYUVChannelLuma] != NULL && channelPixelsBufferSize[KKYUVChannelLuma] > 0) {
        free(channelPixelBuffer[KKYUVChannelLuma]);
        channelPixelBuffer[KKYUVChannelLuma] = NULL;
    }
    if (channelPixelBuffer[KKYUVChannelChromaB] != NULL && channelPixelsBufferSize[KKYUVChannelChromaB] > 0) {
        free(channelPixelBuffer[KKYUVChannelChromaB]);
        channelPixelBuffer[KKYUVChannelChromaB] = NULL;
    }
    if (channelPixelBuffer[KKYUVChannelChromaR] != NULL && channelPixelsBufferSize[KKYUVChannelChromaR] > 0) {
        free(channelPixelBuffer[KKYUVChannelChromaR]);
        channelPixelBuffer[KKYUVChannelChromaR] = NULL;
    }
}

@end



//VideoToolBox YUV frame

@interface KKFFCVYUVVideoFrame()
@end

@implementation KKFFCVYUVVideoFrame

- (void)dealloc{
    if (self->_pixelBuffer) {
        CVPixelBufferRelease(self->_pixelBuffer);
        self->_pixelBuffer = NULL;
    }
}

- (instancetype)initWithAVPixelBuffer:(CVPixelBufferRef)pixelBuffer{
    if (self = [super init]) {
        self->_pixelBuffer = pixelBuffer;
    }
    return self;
}

- (void)setPixelBuffer:(CVPixelBufferRef)pixelBuffer{
    if(pixelBuffer){
        self->_pixelBuffer = pixelBuffer;
    }
}

- (KKFFFrameType)type{
    return KKFFFrameTypeCVYUVVideo;
}

@end

