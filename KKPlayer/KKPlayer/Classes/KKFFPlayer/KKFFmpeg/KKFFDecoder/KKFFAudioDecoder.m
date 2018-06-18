//
//  KKFFAudioDecoder.m
//  KKPlayer
//
//  Created by finger on 2017/2/17.
//  Copyright © 2017年 single. All rights reserved.
//

#import "KKFFAudioDecoder.h"
#import "KKFFFrameQueue.h"
#import "KKFFFramePool.h"
#import "KKTools.h"
#import <Accelerate/Accelerate.h>
#import "swscale.h"
#import "swresample.h"

@interface KKFFAudioDecoder (){
    AVCodecContext *_codecContext;
    AVFrame *_decodedFrame;
    
    SwrContext *_audioSwrContext;
    void *_audioSwrBuffer;
}
@property(nonatomic,strong)KKFFFrameQueue *frameQueue;//已解码帧队列
@property(nonatomic,strong)KKFFFramePool *framePool;//重用池，避免重复创建帧浪费性能资源，程序从重用池中获取帧并初始化并加入到frameQueue中
@property(nonatomic,assign)NSTimeInterval timebase;
@property(nonatomic,assign)Float64 samplingRate;
@property(nonatomic,assign)UInt32 channelCount;
@property(nonatomic,assign)NSInteger audioSwrBufferSize;
@end

@implementation KKFFAudioDecoder

+ (instancetype)decoderWithCodecContext:(AVCodecContext *)codecContext timebase:(NSTimeInterval)timebase sampleRate:(Float64)samplingRate channelCount:(UInt32)channelCount{
    return [[self alloc] initWithCodecContext:codecContext timebase:timebase sampleRate:samplingRate channelCount:channelCount];
}

- (instancetype)initWithCodecContext:(AVCodecContext *)codecContext timebase:(NSTimeInterval)timebase sampleRate:(Float64)samplingRate channelCount:(UInt32)channelCount{
    if (self = [super init]) {
        self.samplingRate = samplingRate;
        self.channelCount = channelCount;
        self->_codecContext = codecContext;
        self->_decodedFrame = av_frame_alloc();
        self->_timebase = timebase;
        [self setup];
    }
    return self;
}

- (void)dealloc{
    if (_audioSwrBuffer) {
        free(_audioSwrBuffer);
        _audioSwrBuffer = NULL;
        _audioSwrBufferSize = 0;
    }
    if (_audioSwrContext) {
        swr_free(&_audioSwrContext);
        _audioSwrContext = NULL;
    }
    if (_decodedFrame) {
        av_free(_decodedFrame);
        _decodedFrame = NULL;
    }
    KKPlayerLog(@"KKFFAudioDecoder release");
}

#pragma mark -- 初始化

- (void)setup{
    self.frameQueue = [KKFFFrameQueue frameQueue];
    self.framePool = [KKFFFramePool audioPool];
    
    _audioSwrContext = swr_alloc_set_opts(NULL, av_get_default_channel_layout(_channelCount), AV_SAMPLE_FMT_S16, _samplingRate, av_get_default_channel_layout(_codecContext->channels), _codecContext->sample_fmt, _codecContext->sample_rate, 0, NULL);
    
    int result = swr_init(_audioSwrContext);
    NSError *error = KKFFCheckError(result);
    if (error || !_audioSwrContext) {
        if (_audioSwrContext) {
            swr_free(&_audioSwrContext);
            _audioSwrContext = NULL;
        }
    }
}

#pragma mark -- 获取解码后的音频数据

- (KKFFAudioFrame *)frameWithBlocking{
    return [self.frameQueue headFrameWithBlocking];
}

#pragma mark -- 将原始的音频帧数据加到队列中

- (NSInteger)putPacket:(AVPacket)packet{
    if (packet.data == NULL) return 0;
    
    int result = avcodec_send_packet(_codecContext, &packet);
    if (result < 0 && result != AVERROR(EAGAIN) && result != AVERROR_EOF) {
        return -1;
    }
    
    while (result >= 0) {
        result = avcodec_receive_frame(_codecContext, _decodedFrame);
        if (result < 0) {
            if (result != AVERROR(EAGAIN) && result != AVERROR_EOF) {
                return -1;
            }
            break;
        }
        @autoreleasepool{
            KKFFAudioFrame *frame = [self decodeAudioFrame:packet.size];
            if (frame) {
                [self.frameQueue putFrame:frame];
            }
        }
    }
    av_packet_unref(&packet);
    
    return 0;
}

#pragma mark -- 解码音频数据

- (KKFFAudioFrame *)decodeAudioFrame:(int)packetSize{
    if (!_decodedFrame->data[0]) return nil;
    
    int numberOfFrames;
    void *audioDataBuffer;
    
    if (_audioSwrContext) {
        const int ratio = MAX(1, _samplingRate / _codecContext->sample_rate) * MAX(1, _channelCount / _codecContext->channels) * 2;
        const int bufferSize = av_samples_get_buffer_size(NULL, _channelCount, _decodedFrame->nb_samples * ratio, AV_SAMPLE_FMT_S16, 1);
        
        if (!_audioSwrBuffer || _audioSwrBufferSize < bufferSize) {
            _audioSwrBufferSize = bufferSize;
            _audioSwrBuffer = realloc(_audioSwrBuffer, _audioSwrBufferSize);
        }
        
        Byte *outyput_buffer[2] = {_audioSwrBuffer, 0};
        numberOfFrames = swr_convert(_audioSwrContext, outyput_buffer, _decodedFrame->nb_samples * ratio, (const uint8_t **)_decodedFrame->data, _decodedFrame->nb_samples);
        NSError * error = KKFFCheckError(numberOfFrames);
        if (error) {
            KKPlayerLog(@"audio codec error : %@", error);
            return nil;
        }
        audioDataBuffer = _audioSwrBuffer;
    } else {
        if (_codecContext->sample_fmt != AV_SAMPLE_FMT_S16) {
            KKPlayerLog(@"audio format error");
            return nil;
        }
        audioDataBuffer = _decodedFrame->data[0];
        numberOfFrames = _decodedFrame->nb_samples;
    }
    
    const NSUInteger numberOfElements = numberOfFrames * self->_channelCount;
    
    //根据time_base获得音频帧的真实的位置和时长,这一步很重要，会直接影响播放时的音视频同步问题
    KKFFAudioFrame *audioFrame = [self.framePool getUnuseFrame];
    audioFrame.packetSize = packetSize;
    audioFrame.position = av_frame_get_best_effort_timestamp(_decodedFrame) * _timebase;
    audioFrame.duration = av_frame_get_pkt_duration(_decodedFrame) * _timebase;
    audioFrame.samplesLength = numberOfElements * sizeof(float);
    if (audioFrame.duration == 0) {
        audioFrame.duration = audioFrame.samplesLength / (sizeof(float) * _channelCount * _samplingRate);
    }
    
    float scale = 1.0 / (float)INT16_MAX ;
    vDSP_vflt16((SInt16 *)audioDataBuffer, 1, audioFrame->samples, 1, numberOfElements);
    vDSP_vsmul(audioFrame->samples, 1, &scale, audioFrame->samples, 1, numberOfElements);
    
    return audioFrame;
}

#pragma mark -- 清理

- (void)clean{
    [self.frameQueue clean];
    [self.framePool clean];
    if (_codecContext) {
        avcodec_flush_buffers(_codecContext);
    }
}

- (void)destroy{
    [self.frameQueue destroy];
    [self.framePool clean];
}

#pragma mark -- @property getter&setter

- (NSInteger)packetSize{
    return self.frameQueue.packetSize;
}

- (BOOL)frameQueueEmpty{
    return self.frameQueue.count <= 0;
}

- (NSTimeInterval)duration{
    return self.frameQueue.duration;
}

@end
