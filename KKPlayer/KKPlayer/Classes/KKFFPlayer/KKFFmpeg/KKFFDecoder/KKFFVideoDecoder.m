//
//  KKFFVideoDecoder.m
//  KKPlayer
//
//  Created by finger on 2017/2/17.
//  Copyright © 2017年 finger. All rights reserved.
//

#import "KKFFVideoDecoder.h"
#import "KKFFPacketQueue.h"
#import "KKFFFrameQueue.h"
#import "KKFFFramePool.h"
#import "KKTools.h"
#import "KKFFVideoToolBox.h"
#import "KKWaterMarkTool.h"

//当解码遇到这AVPacket时，需要清理AVCodecContext的缓冲
static AVPacket flushPacket;

@interface KKFFVideoDecoder (){
    AVCodecContext *_codecContext;
    AVFrame *_decodeFrame;
}
@property(nonatomic,assign)BOOL canceled;
@property(nonatomic,assign)NSTimeInterval fps;
@property(nonatomic,assign)NSTimeInterval timebase;
@property(nonatomic,assign)BOOL enableVideoToolbox;//是否允许videoToolbox解码
@property(nonatomic,assign)BOOL videoToolBoxDidOpen;//videoToolbox初始化成功
@property(nonatomic,assign)BOOL ffmpegDecodeAsync;//ffmpeg异步解码

@property(nonatomic,assign)NSInteger videoToolBoxMaxDecodeFrameCount;
@property(nonatomic,assign)NSInteger codecContextMaxDecodeFrameCount;

@property(nonatomic,strong)KKFFPacketQueue *packetQueue;//原始数据队列
@property(nonatomic,strong)KKFFFrameQueue *frameQueue;//已解码队列
@property(nonatomic,strong)KKFFFramePool *framePool;//重用池，避免重复创建帧浪费性能资源，程序从重用池中获取帧并初始化并加入到frameQueue中
@property(nonatomic,strong)KKFFVideoToolBox *videoToolBox;
@property(nonatomic,strong)KKWaterMarkTool *waterMarkTool;
@end

@implementation KKFFVideoDecoder

+ (instancetype)decoderWithCodecContext:(AVCodecContext *)codecContext
                               timebase:(NSTimeInterval)timebase
                                    fps:(NSTimeInterval)fps
                      ffmpegDecodeAsync:(BOOL)ffmpegDecodeAsync
                     enableVideoToolbox:(BOOL)enableVideoToolbox
                             rotateType:(KKFFVideoFrameRotateType)rotateType
                               delegate:(id<KKFFVideoDecoderDlegate>)delegate{
    return [[self alloc] initWithCodecContext:codecContext
                                     timebase:timebase
                                          fps:fps
                            ffmpegDecodeAsync:ffmpegDecodeAsync
                           enableVideoToolbox:enableVideoToolbox
                                   rotateType:rotateType
                                     delegate:delegate];
}

- (instancetype)initWithCodecContext:(AVCodecContext *)codecContext
                            timebase:(NSTimeInterval)timebase
                                 fps:(NSTimeInterval)fps
                   ffmpegDecodeAsync:(BOOL)ffmpegDecodeAsync
                  enableVideoToolbox:(BOOL)enableVideoToolbox
                          rotateType:(KKFFVideoFrameRotateType)rotateType
                            delegate:(id<KKFFVideoDecoderDlegate>)delegate{
    if (self = [super init]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            av_init_packet(&flushPacket);
            flushPacket.data = (uint8_t *)&flushPacket;
            flushPacket.duration = 0;
        });
        self.delegate = delegate;
        self->_codecContext = codecContext;
        self->_timebase = timebase;
        self->_fps = fps;
        self->_ffmpegDecodeAsync = ffmpegDecodeAsync;
        self->_enableVideoToolbox = enableVideoToolbox;
        self->_rotateType = rotateType;
        [self.waterMarkTool setupFilters:@"drawtext=Helvetica:fontcolor=green:fontsize=30:text='KKFinger'" videoCodecCtx:codecContext];
        [self setupFrameQueue];
    }
    return self;
}

- (void)dealloc{
    if (_decodeFrame) {
        av_free(_decodeFrame);
        _decodeFrame = NULL;
    }
    [self destroy];
    KKPlayerLog(@"KKFFVideoDecoder release");
}

#pragma mark -- 初始化数据队列相关数据

- (void)setupFrameQueue{
    self->_decodeFrame = av_frame_alloc();
    self.videoToolBoxMaxDecodeFrameCount = 20;
    self.codecContextMaxDecodeFrameCount = 3;
    if (self.enableVideoToolbox && _codecContext->codec_id == AV_CODEC_ID_H264) {
        //h264,使用videotoolbox硬件加速
        self.videoToolBox = [KKFFVideoToolBox videoToolBoxWithCodecContext:self->_codecContext];
        if ([self.videoToolBox trySetupVTSession]) {
            self->_videoToolBoxDidOpen = YES;
        } else {
            [self.videoToolBox clean];
            self.videoToolBox = nil;
        }
    }
    self.packetQueue = [KKFFPacketQueue packetQueueWithTimebase:self.timebase];
    if (self.videoToolBoxDidOpen) {
        self.framePool = [KKFFFramePool poolWithCapacity:10 frameClass:[KKFFCVYUVVideoFrame class]];
        self.frameQueue = [KKFFFrameQueue frameQueue];
        self.frameQueue.minFrameCountThreshold = 4;
    } else if (self.ffmpegDecodeAsync) {
        self.framePool = [KKFFFramePool videoPool];
        self.frameQueue = [KKFFFrameQueue frameQueue];
    } else {
        self.framePool = [KKFFFramePool videoPool];
        self->_decodeOnMainThread = YES;
    }
}

#pragma mark -- 获取音视频帧

- (KKFFVideoFrame *)headFrame{
    if (self.videoToolBoxDidOpen || self.ffmpegDecodeAsync) {
        return [self.frameQueue headFrameWithNoBlocking];
    } else {
        return [self ffmpegDecodeImmediately];
    }
}

- (KKFFVideoFrame *)frameAtPosition:(NSTimeInterval)position{
    if (self.videoToolBoxDidOpen || self.ffmpegDecodeAsync) {
        NSMutableArray <KKFFFrame *> *discardFrames = nil;
        KKFFVideoFrame *videoFrame = [self.frameQueue frameWithNoBlockingAtPosistion:position discardFrames:&discardFrames];
        for (KKFFVideoFrame *obj in discardFrames) {
            [obj cancel];
        }
        return videoFrame;
    } else {
        return [self ffmpegDecodeImmediately];
    }
}

#pragma mark -- 丢弃帧

- (void)discardFrameBeforPosition:(NSTimeInterval)position{
    if (self.videoToolBoxDidOpen || self.ffmpegDecodeAsync) {
        NSMutableArray <KKFFFrame *> *discardFrames = [self.frameQueue discardFrameBeforePosition:position];
        for (KKFFVideoFrame *obj in discardFrames) {
            [obj cancel];
        }
    }
}

#pragma mark -- 添加音视频原始帧数据到队列中

- (void)putPacket:(AVPacket)packet{
    NSTimeInterval duration = 0;
    if (packet.duration <= 0 && packet.size > 0 && packet.data != flushPacket.data) {
        duration = 1.0 / self.fps;
    }
    [self.packetQueue putPacket:packet duration:duration];
}

#pragma mark -- 解码线程

- (void)startDecodeThread{
    if (self.videoToolBoxDidOpen) {
        [self videoToolBoxDecodeWaitIfNeed];
    } else if (self.ffmpegDecodeAsync) {
        [self ffmpegDecodeWaitIfNeed];
    }
}

#pragma mark -- ffmpeg解码，当packet队列为空时堵塞等待

- (void)ffmpegDecodeWaitIfNeed{
    while (YES) {
        if (self.canceled || self.error) {
            KKPlayerLog(@"decode video thread quit");
            break;
        }
        if (self.readPacketFinish && self.packetQueue.count <= 0) {
            KKPlayerLog(@"decode video finished");
            break;
        }
        if (self.paused) {
            KKPlayerLog(@"decode video thread pause sleep");
            [NSThread sleepForTimeInterval:0.03];
            continue;
        }
        if (self.frameQueue.count >= self.codecContextMaxDecodeFrameCount) {
            //KKPlayerLog(@"decode video thread sleep");
            [NSThread sleepForTimeInterval:0.03];
            continue;
        }
        
        AVPacket packet = [self.packetQueue getPacketWithBlocking];
        if (packet.data == flushPacket.data) {
            KKPlayerLog(@"video codec flush");
            avcodec_flush_buffers(_codecContext);
            [self.frameQueue clean];
            continue;
        }
        
        if (packet.stream_index < 0 || packet.data == NULL) continue;
        
        KKFFVideoFrame *videoFrame = nil;
        int result = avcodec_send_packet(_codecContext, &packet);
        if (result < 0) {
            if (result != AVERROR(EAGAIN) && result != AVERROR_EOF) {
                self->_error = KKFFCheckError(result);
                [self delegateErrorCallback];
            }
        } else {
            while (result >= 0) {
                result = avcodec_receive_frame(_codecContext, _decodeFrame);
                if (result < 0) {
                    if (result != AVERROR(EAGAIN) && result != AVERROR_EOF) {
                        self->_error = KKFFCheckError(result);
                        [self delegateErrorCallback];
                    }
                } else {
                    videoFrame = [self videoFrameFromDecodedFrame:packet.size];
                    if (videoFrame) {
                        [self.frameQueue putSortFrame:videoFrame];
                    }
                }
            }
        }
        av_packet_unref(&packet);
    }
}

#pragma mark -- ffmpeg解码，当packet队列为空时不等待，直接返回

- (KKFFVideoFrame *)ffmpegDecodeImmediately{
    if (self.canceled || self.error) {
        return nil;
    }
    if (self.paused) {
        return nil;
    }
    if (self.readPacketFinish && self.packetQueue.count <= 0) {
        return nil;
    }
    
    AVPacket packet = [self.packetQueue getPacketWithNoBlocking];
    if (packet.data == flushPacket.data) {
        avcodec_flush_buffers(_codecContext);
        return nil;
    }
    if (packet.stream_index < 0 || packet.data == NULL) {
        return nil;
    }
    
    KKFFVideoFrame *videoFrame = nil;
    int result = avcodec_send_packet(_codecContext, &packet);
    if (result < 0) {
        if (result != AVERROR(EAGAIN) && result != AVERROR_EOF) {
            self->_error = KKFFCheckError(result);
            [self delegateErrorCallback];
        }
    } else {
        while (result >= 0) {
            result = avcodec_receive_frame(_codecContext, _decodeFrame);
            if (result < 0) {
                if (result != AVERROR(EAGAIN) && result != AVERROR_EOF) {
                    self->_error = KKFFCheckError(result);
                    [self delegateErrorCallback];
                }
            } else {
                videoFrame = [self videoFrameFromDecodedFrame:packet.size];
            }
        }
    }
    av_packet_unref(&packet);
    
    return videoFrame;
}

- (KKFFAVYUVVideoFrame *)videoFrameFromDecodedFrame:(int)packetSize{
    if (!_decodeFrame->data[0] || !_decodeFrame->data[1] || !_decodeFrame->data[2]){
        return nil;
    }
    
    //    if (av_buffersrc_add_frame(self.waterMarkTool->buffersrcCtx, _tempFrame) < 0) {
    //        NSLog(@"Error while feeding the filtergraph\n");
    //    }
    //
    //    int ret = av_buffersink_get_frame(self.waterMarkTool->buffersinkCtx, _tempFrame);
    //    if (ret < 0){
    //        NSLog(@"Error while feeding the filtergraph\n");
    //    }
    
    KKFFAVYUVVideoFrame *videoFrame = [self.framePool getUnuseFrame];
    [videoFrame setFrameData:_decodeFrame width:_codecContext->width height:_codecContext->height];
    videoFrame.packetSize = packetSize;
    videoFrame.rotateType = self.rotateType;
    
    //根据time_base获得音频帧的真实的位置和时长，这一步很重要，会直接影响播放时的音视频同步问题
    const int64_t frame_duration = av_frame_get_pkt_duration(_decodeFrame);
    if (frame_duration) {
        videoFrame.duration = frame_duration * self.timebase;
        videoFrame.duration += _decodeFrame->repeat_pict * self.timebase * 0.5;
    } else {
        videoFrame.duration = 1.0 / self.fps;
    }
    videoFrame.position = av_frame_get_best_effort_timestamp(_decodeFrame) * self.timebase;
    
    return videoFrame;
}

#pragma mark -- VideoToolBox，硬件加速

- (void)videoToolBoxDecodeWaitIfNeed{
    while (YES) {
        if (!self.videoToolBoxDidOpen) {
            break;
        }
        if (self.canceled || self.error) {
            KKPlayerLog(@"decode video thread quit");
            break;
        }
        if (self.readPacketFinish && self.packetQueue.count <= 0) {
            KKPlayerLog(@"decode video finished");
            break;
        }
        if (self.paused) {
            KKPlayerLog(@"decode video thread pause sleep");
            [NSThread sleepForTimeInterval:0.01];
            continue;
        }
        if (self.frameQueue.count >= self.videoToolBoxMaxDecodeFrameCount) {
            //KKPlayerLog(@"decode video thread sleep");
            [NSThread sleepForTimeInterval:0.03];
            continue;
        }
        
        AVPacket packet = [self.packetQueue getPacketWithBlocking];
        if (packet.data == flushPacket.data) {
            KKPlayerLog(@"video codec flush");
            [self.frameQueue clean];
            [self.videoToolBox clean];
            continue;
        }
        
        if (packet.stream_index < 0 || packet.data == NULL) continue;
        
        KKFFVideoFrame *videoFrame = nil;
        BOOL result = [self.videoToolBox sendPacket:packet];
        if (result) {
            videoFrame = [self videoFrameFromVideoToolBox:packet];
        }
        if (videoFrame) {
            [self.frameQueue putSortFrame:videoFrame];
        }
        av_packet_unref(&packet);
    }
}

- (KKFFVideoFrame *)videoFrameFromVideoToolBox:(AVPacket)packet{
    CVImageBufferRef imageBuffer = [self.videoToolBox imageBuffer];
    if (imageBuffer == NULL){
        return nil;
    }
    
    KKFFCVYUVVideoFrame *videoFrame = [[KKFFCVYUVVideoFrame alloc]initWithAVPixelBuffer:imageBuffer];
    //内存泄漏，待解决
    //KKFFCVYUVVideoFrame *videoFrame = (KKFFCVYUVVideoFrame *)[self.framePool getUnuseFrame];
    //[videoFrame setPixelBuffer:imageBuffer];
    if (packet.pts != AV_NOPTS_VALUE) {
        videoFrame.position = packet.pts * self.timebase;
    } else {
        videoFrame.position = packet.dts;
    }
    videoFrame.packetSize = packet.size;
    videoFrame.rotateType = self.rotateType;
    
    const int64_t frameDuration = packet.duration;
    if (frameDuration) {
        videoFrame.duration = frameDuration * self.timebase;
    } else {
        videoFrame.duration = 1.0 / self.fps;
    }
    return videoFrame;
}

#pragma mark -- 解码错误

- (void)delegateErrorCallback{
    if (self.error) {
        [self.delegate videoDecoder:self didError:self.error];
    }
}

#pragma mark -- 清理

/*
 注意,在seek时，需要将所有的数据队列及AVCodecContext的缓冲清空，清空AVCodecContext缓冲的策略是:
 在AVPacket队列中加入flushPacket，解码线程将AVPacket队列中的数据取出时，如果是flushPacket，则将
 AVCodecContext的缓冲清理，不清理AVCodecContext的缓冲会造成播放画面卡主不动的问题
 */
- (void)clean{
    [self.packetQueue clean];
    [self.frameQueue clean];
    [self.framePool clean];
    [self putPacket:flushPacket];
}

- (void)destroy{
    self.canceled = YES;
    [self.frameQueue destroy];
    [self.packetQueue destroy];
    [self.framePool destory];
}

#pragma mark -- @property getter && setter

- (KKWaterMarkTool *)waterMarkTool{
    if(!_waterMarkTool){
        _waterMarkTool = [KKWaterMarkTool new];
    }
    return _waterMarkTool;
}

- (NSInteger)packetSize{
    if (self.videoToolBoxDidOpen || self.ffmpegDecodeAsync) {
        return self.packetQueue.size + self.frameQueue.packetSize;
    } else {
        return self.packetQueue.size;
    }
}

- (BOOL)frameQueueEmpty{
    if (self.videoToolBoxDidOpen || self.ffmpegDecodeAsync) {
        return self.packetQueue.count <= 0 && self.frameQueue.count <= 0;
    } else {
        return self.packetQueue.count <= 0;
    }
}

- (NSTimeInterval)duration{
    if (self.videoToolBoxDidOpen || self.ffmpegDecodeAsync) {
        return self.packetQueue.duration + self.frameQueue.duration;
    } else {
        return self.packetQueue.duration;
    }
}

@end
