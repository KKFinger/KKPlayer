//
//  KKFFDecoder.m
//  KKPlayer
//
//  Created by finger on 05/01/2017.
//  Copyright © 2017 finger. All rights reserved.
//

#import "KKFFDecoder.h"
#import "KKFFFormatContext.h"
#import "KKFFAudioDecoder.h"
#import "KKFFVideoDecoder.h"
#import "KKTools.h"
#import "KKFFPlayer.h"

static NSInteger maxPacketBufferSize = 15 * 1024 * 1024;
static NSTimeInterval maxPacketSleepFullTimeInterval = 0.1;
static NSTimeInterval maxPacketSleepFullAndPauseTimeInterval = 0.5;

@interface KKFFDecoder()<KKFFFormatContextDelegate,KKFFVideoDecoderDlegate>
@property(nonatomic,weak)id<KKFFDecoderDelegate>delegate;
@property(nonatomic,weak)id<KKFFDecoderVideoConfigDelegate>videoDecodeConfigDelegate;
@property(nonatomic,weak)id<KKFFDecoderAudioConfigDelegate>audioDecodeConfigDelegate;

@property(nonatomic,strong)NSOperationQueue *ffmpegOperationQueue;
@property(nonatomic,strong)NSInvocationOperation *openFormatContextOperation;
@property(nonatomic,strong)NSInvocationOperation *readPacketOperation;
@property(nonatomic,strong)NSInvocationOperation *decodeFrameOperation;

@property(nonatomic,copy)NSDictionary *formatContextOptions;
@property(nonatomic,copy)NSDictionary *codecContextOptions;

@property(nonatomic,strong)KKFFFormatContext *formatContext;
@property(nonatomic,strong)KKFFAudioDecoder *audioDecoder;
@property(nonatomic,strong)KKFFVideoDecoder *videoDecoder;

@property(nonatomic,strong)NSError *error;
@property(nonatomic,copy)NSURL *contentURL;
@property(nonatomic,assign)NSTimeInterval progress;
@property(nonatomic,assign)NSTimeInterval bufferedDuration;
@property(nonatomic,assign)NSTimeInterval seekToTime;

@property(nonatomic,assign)BOOL buffering;
@property(nonatomic,assign)BOOL decodeFinished;
@property(nonatomic,assign)BOOL stopDecode;
@property(nonatomic,assign)BOOL readPacketFinish;
@property(nonatomic,assign)BOOL paused;
@property(nonatomic,assign)BOOL seeking;
@property(nonatomic,assign)BOOL prepareToDecode;

@property(nonatomic,copy)void(^seekCompleteHandler)(BOOL finished);

@property(nonatomic,assign)NSTimeInterval audioFrameUpdateTime;
@property(nonatomic,assign)NSTimeInterval audioFramePosition;
@property(nonatomic,assign)NSTimeInterval audioFrameDuration;

@property(nonatomic,assign)NSTimeInterval videoFrameUpdateTime;
@property(nonatomic,assign)NSTimeInterval videoFramePosition;
@property(nonatomic,assign)NSTimeInterval videoFrameDuration;

@end

@implementation KKFFDecoder

+ (instancetype)decoderWithContentURL:(NSURL *)contentURL
                 formatContextOptions:(NSDictionary *)formatContextOptions
                  codecContextOptions:(NSDictionary *)codecContextOptions
                             delegate:(id<KKFFDecoderDelegate>)delegate
           videoDecoderConfigDelegate:(id<KKFFDecoderVideoConfigDelegate>)videoDecoderConfigDelegate
           audioDecoderConfigDelegate:(id<KKFFDecoderAudioConfigDelegate>)audioDecoderConfigDelegate{
    return [[self alloc] initWithContentURL:contentURL
                       formatContextOptions:formatContextOptions
                        codecContextOptions:codecContextOptions
                                   delegate:delegate
                 videoDecoderConfigDelegate:videoDecoderConfigDelegate
                 audioDecoderConfigDelegate:audioDecoderConfigDelegate];
}

- (instancetype)initWithContentURL:(NSURL *)contentURL
              formatContextOptions:(NSDictionary *)formatContextOptions
               codecContextOptions:(NSDictionary *)codecContextOptions
                          delegate:(id<KKFFDecoderDelegate>)delegate
        videoDecoderConfigDelegate:(id<KKFFDecoderVideoConfigDelegate>)videoDecoderConfigDelegate
        audioDecoderConfigDelegate:(id<KKFFDecoderAudioConfigDelegate>)audioDecoderConfigDelegate{
    if (self = [super init]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            av_log_set_callback(KKFFLog);
            av_register_all();
            avformat_network_init();
        });
        self.contentURL = contentURL;
        self.delegate = delegate;
        self.videoDecodeConfigDelegate = videoDecoderConfigDelegate;
        self.audioDecodeConfigDelegate = audioDecoderConfigDelegate;
        self.formatContextOptions = formatContextOptions;
        self.codecContextOptions = codecContextOptions;
    }
    return self;
}

- (void)dealloc{
    [self stopDecoder:NO];
    KKPlayerLog(@"KKFFDecoder release");
}

#pragma mark -- 结束解码

- (void)stopDecoder{
    [self stopDecoder:YES];
}

- (void)stopDecoder:(BOOL)async{
    if (!self.stopDecode) {
        self.stopDecode = YES;
        [self.videoDecoder destroy];
        [self.audioDecoder destroy];
        if (async) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                [self.ffmpegOperationQueue cancelAllOperations];
                [self.ffmpegOperationQueue waitUntilAllOperationsAreFinished];
                [self.formatContext destroy];
                [self closeOperation];
                [self closePropertyValue];
            });
        } else {
            [self.ffmpegOperationQueue cancelAllOperations];
            [self.ffmpegOperationQueue waitUntilAllOperationsAreFinished];
            [self.formatContext destroy];
            [self closeOperation];
            [self closePropertyValue];
        }
    }
}

- (void)closePropertyValue{
    self.seeking = NO;
    self.buffering = NO;
    self.paused = NO;
    self.prepareToDecode = NO;
    self.readPacketFinish = NO;
    self.decodeFinished = NO;
    self.videoDecoder.paused = NO;
    self.videoDecoder.readPacketFinish = NO;
    [self cleanAudioFrame];
    [self cleanVideoFrame];
}

- (void)closeOperation{
    self.readPacketOperation = nil;
    self.openFormatContextOperation = nil;
    self.decodeFrameOperation = nil;
    self.ffmpegOperationQueue = nil;
}

- (void)cleanAudioFrame{
    self.audioFrameUpdateTime = -1;
    self.audioFramePosition = -1;
    self.audioFrameDuration = -1;
}

- (void)cleanVideoFrame{
    self.videoFrameUpdateTime = -1;
    self.videoFramePosition = -1;
    self.videoFrameDuration = -1;
}

#pragma mark -- 开始解码

- (void)startDecoder{
    self.ffmpegOperationQueue = [[NSOperationQueue alloc] init];
    self.ffmpegOperationQueue.maxConcurrentOperationCount = 2;
    self.ffmpegOperationQueue.qualityOfService = NSQualityOfServiceUserInteractive;
    
    [self setupFormatContextOperation];
    [self setupReadPacketOperation];//启动读取音视频帧线程
}

#pragma mark -- 初始化formatContext

- (void)setupFormatContextOperation{
    self.openFormatContextOperation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(setupFormatContext) object:nil];
    self.openFormatContextOperation.queuePriority = NSOperationQueuePriorityVeryHigh;
    self.openFormatContextOperation.qualityOfService = NSQualityOfServiceUserInteractive;
    [self.ffmpegOperationQueue addOperation:self.openFormatContextOperation];
}

- (void)setupFormatContext{
    if ([self.delegate respondsToSelector:@selector(decoderWillOpenInputStream:)]) {
        [self.delegate decoderWillOpenInputStream:self];
    }
    
    self.formatContext = [KKFFFormatContext formatContextWithContentURL:self.contentURL formatContextOptions:self.formatContextOptions codecContextOptions:self.codecContextOptions delegate:self];
    
    [self.formatContext openFileStream];
    
    if (self.formatContext.error) {
        self.error = self.formatContext.error;
        [self decodeError];
        return;
    }
    
    self.prepareToDecode = YES;
    
    if ([self.delegate respondsToSelector:@selector(decoderDidPrepareToDecodeFrames:)]) {
        [self.delegate decoderDidPrepareToDecodeFrames:self];
    }
    
    //注意,音视频的解码器的创建依赖于AVFormatContext，必须等AVFormatContext创建完成之后才能进行
    [self setupFFVideoDecoder];
    [self setupFFAudioDecoder];
}

#pragma mark -- 音视频解码器

- (void)setupFFVideoDecoder{
    if (self.formatContext.videoEnable) {
        self.videoDecoder = [KKFFVideoDecoder decoderWithCodecContext:self.formatContext->videoCodecContext timebase:self.formatContext.videoTimebase fps:self.formatContext.videoFPS ffmpegDecodeAsync:[self.videoDecodeConfigDelegate decoderVideoConfigAVCodecContextDecodeAsync] enableVideoToolbox:YES rotateType:self.formatContext.videoFrameRotateType delegate:self];
    }
    [self startVideoDecoderOperation];
}

- (void)setupFFAudioDecoder{
    if (self.formatContext.audioEnable) {
        self.audioDecoder = [KKFFAudioDecoder decoderWithCodecContext:self.formatContext->audioCodecContext timebase:self.formatContext.audioTimebase sampleRate:[self.audioDecodeConfigDelegate decoderAudioConfigGetSamplingRate] channelCount:[self.audioDecodeConfigDelegate decoderAudioConfigGetNumberOfChannels]];
    }
}

#pragma mark -- 启动视频的解码线程

- (void)startVideoDecoderOperation{
    if(!self.formatContext.videoEnable){
        return ;
    }
    if (!self.decodeFrameOperation || self.decodeFrameOperation.isFinished) {
        self.decodeFrameOperation = [[NSInvocationOperation alloc] initWithTarget:self.videoDecoder
                                                                         selector:@selector(startDecodeThread)
                                                                           object:nil];
        self.decodeFrameOperation.queuePriority = NSOperationQueuePriorityVeryHigh;
        self.decodeFrameOperation.qualityOfService = NSQualityOfServiceUserInteractive;
        [self.decodeFrameOperation addDependency:self.openFormatContextOperation];
        [self.ffmpegOperationQueue addOperation:self.decodeFrameOperation];
    }
}

#pragma mark -- 读取原始音视频帧线程

- (void)setupReadPacketOperation{
    if (self.error) {
        [self decodeError];
        return;
    }
    
    if (!self.readPacketOperation || self.readPacketOperation.isFinished) {
        self.readPacketOperation = [[NSInvocationOperation alloc] initWithTarget:self
                                                                        selector:@selector(readPacketOperator)
                                                                          object:nil];
        self.readPacketOperation.queuePriority = NSOperationQueuePriorityVeryHigh;
        self.readPacketOperation.qualityOfService = NSQualityOfServiceUserInteractive;
        [self.readPacketOperation addDependency:self.openFormatContextOperation];
        [self.ffmpegOperationQueue addOperation:self.readPacketOperation];
    }
}

- (void)readPacketOperator{
    [self cleanAudioFrame];
    [self cleanVideoFrame];
    
    [self.videoDecoder clean];
    [self.audioDecoder clean];
    
    AVPacket packet;
    BOOL readFinish = NO;
    while (!readFinish) {
        if (self.stopDecode || self.error) {
            KKPlayerLog(@"read packet thread quit");
            break;
        }
        if (self.seeking) {
            
            [self.formatContext seekFileWithSecond:self.seekToTime];
            
            [self.audioDecoder clean];
            [self.videoDecoder clean];
            [self.videoDecoder setPaused:NO];
            [self.videoDecoder setReadPacketFinish:NO];
            
            self.readPacketFinish = NO;
            self.decodeFinished = NO;
            self.buffering = YES;
            self.seeking = NO;
            self.seekToTime = 0;
            
            if (self.seekCompleteHandler) {
                self.seekCompleteHandler(YES);
                self.seekCompleteHandler = nil;
            }
            
            [self cleanAudioFrame];
            [self cleanVideoFrame];
            [self updateBufferedDuration];
            [self updateProgress];
            
            continue;
        }

        if (self.audioDecoder.packetSize + self.videoDecoder.packetSize >= maxPacketBufferSize) {
            NSTimeInterval interval = 0;
            if (self.paused) {
                interval = maxPacketSleepFullAndPauseTimeInterval;
            } else {
                interval = maxPacketSleepFullTimeInterval;
            }
            //KKPlayerLog(@"read thread sleep : %f", interval);
            [NSThread sleepForTimeInterval:interval];
            continue;
        }
        
        // read frame
        int result = [self.formatContext readFrame:&packet];
        if (result < 0){
            KKPlayerLog(@"read packet finished");
            self.readPacketFinish = YES;
            self.videoDecoder.readPacketFinish = YES;
            readFinish = YES;
            if ([self.delegate respondsToSelector:@selector(decoderDidEndOfFile:)]) {
                [self.delegate decoderDidEndOfFile:self];
            }
            break;
        }
        
        if (packet.stream_index == self.formatContext.videoTrack.index &&
            self.formatContext.videoEnable){
            [self.videoDecoder putPacket:packet];
            [self updateBufferedDuration];
        }else if (packet.stream_index == self.formatContext.audioTrack.index &&
                  self.formatContext.audioEnable){
            NSInteger result = [self.audioDecoder putPacket:packet];
            if (result < 0) {
                self.error = KKFFCheckErrorCode(result, KKFFDecoderErrorCodeCodecAudioSendPacket);
                [self decodeError];
                continue;
            }
            [self updateBufferedDuration];
        }
    }
    
    [self checkBufferingStatus];
}

#pragma mark -- 解码控制

- (void)pause{
    self.paused = YES;
}

- (void)resume{
    self.paused = NO;
    if (self.decodeFinished) {
        [self seekToTime:0];
    }
}

- (void)seekToTime:(NSTimeInterval)time{
    [self seekToTime:time completeHandler:nil];
}

- (void)seekToTime:(NSTimeInterval)time completeHandler:(void (^)(BOOL finished))completeHandler{
    if (!self.seekEnable || self.error) {
        if (completeHandler) {
            completeHandler(NO);
        }
        return;
    }

    self.progress = time;
    self.seekToTime = time;
    self.seekCompleteHandler = completeHandler;
    self.seeking = YES;
    self.videoDecoder.paused = YES;
    
    //正常播放结束，重新开始读取媒体数据和解码
    if (self.readPacketFinish) {
        [self setupReadPacketOperation];
        [self startVideoDecoderOperation];
    }
}

#pragma mark -- 获取解码的音频帧

- (KKFFAudioFrame *)fetchAudioFrame{
    BOOL check = self.stopDecode || self.seeking || self.buffering || self.paused || self.decodeFinished || !self.formatContext.audioEnable;
    if (check){
        return nil;
    }
    if (self.audioDecoder.frameQueueEmpty) {
        return nil;
    }
    KKFFAudioFrame *audioFrame = [self.audioDecoder frameWithBlocking];
    if (!audioFrame) return nil;
    self.audioFramePosition = audioFrame.position;
    self.audioFrameDuration = audioFrame.duration;
    self.audioFrameUpdateTime = [NSDate date].timeIntervalSince1970;

    [self updateBufferedDuration];
    [self updateProgress];
    
    return audioFrame;
}

#pragma mark -- 获取解码的视频帧

- (KKFFVideoFrame *)fetchVideoFrameWithCurrentPostion:(NSTimeInterval)currentPostion currentDuration:(NSTimeInterval)currentDuration{
    if (self.stopDecode || self.error) {
        return nil;
    }
    if (self.seeking || self.buffering) {
        return nil;
    }
    //防止暂停时，拖动进度条视频画面不更新的问题
    if (self.paused && self.videoFrameUpdateTime > 0) {
        return nil;
    }
    if (self.videoDecoder.frameQueueEmpty) {
        return nil;
    }
    
    NSTimeInterval nowTime = [NSDate date].timeIntervalSince1970;
    KKFFVideoFrame *videoFrame = nil;
    if (self.formatContext.audioEnable){
        //优先使用音频的时间来同步音视频的播放
        if (self.videoFrameUpdateTime < 0) {
            videoFrame = [self.videoDecoder headFrame];
        } else {
            NSTimeInterval audioUpdateTime = self.audioFrameUpdateTime;
            NSTimeInterval audioTimeOffset = nowTime - audioUpdateTime;
            NSTimeInterval audioPositionNow = self.audioFramePosition + audioTimeOffset;
            NSTimeInterval currentNow = currentPostion + currentDuration;
            if (currentNow <= audioPositionNow) {
                videoFrame = [self.videoDecoder frameAtPosition:currentPostion];
            }
        }
    }else if (self.formatContext.videoEnable){
        if (self.videoFrameUpdateTime < 0 || nowTime >= self.videoFrameUpdateTime + self.videoFrameDuration) {
            videoFrame = [self.videoDecoder headFrame];
        }
    }
    if (videoFrame) {
        self.videoFrameUpdateTime = nowTime;
        self.videoFramePosition = videoFrame.position;
        self.videoFrameDuration = videoFrame.duration;

        [self updateBufferedDuration];
        [self updateProgress];
    }
    return videoFrame;
}

#pragma mark -- KKFFFormatContextDelegate

- (BOOL)formatContextNeedInterrupt:(KKFFFormatContext *)formatContext{
    return self.stopDecode;
}

#pragma mark -- KKFFVideoDecoderDlegate

- (void)videoDecoder:(KKFFVideoDecoder *)videoDecoder didError:(NSError *)error{
    self.error = error;
    [self decodeError];
}

#pragma mark -- 更新解码相关状态

- (void)checkBufferingStatus{
    if (self.buffering) {
        if (self.bufferedDuration >= self.minBufferedDruation || self.readPacketFinish) {
            self.buffering = NO;
        }
    } else {
        if (self.bufferedDuration <= 0.2 && !self.readPacketFinish) {
            self.buffering = YES;
        }
    }
}

/*
 *优先使用声音更新缓冲进度
 */
- (void)updateBufferedDuration{
    if (!self.formatContext.audioEnable) {
        self.bufferedDuration = self.videoDecoder.duration;
    }else{
        self.bufferedDuration = self.audioDecoder.duration;
    }
}

/*
 *优先使用声音更新播放进度
 */
- (void)updateProgress{
    if (self.formatContext.audioEnable) {
        if (self.audioFramePosition >= 0) {
            self.progress = self.audioFramePosition;
        }
    }else{
        if (self.videoFramePosition >= 0) {
            self.progress = self.videoFramePosition;
        }
    }
}

#pragma mark -- 解码错误

- (void)decodeError{
    if (self.error) {
        if ([self.delegate respondsToSelector:@selector(decoder:didError:)]) {
            [self.delegate decoder:self didError:self.error];
        }
    }
}

#pragma mark -- 轨道信息

- (BOOL)videoEnable{
    return self.formatContext.videoEnable;
}

- (BOOL)audioEnable{
    return self.formatContext.audioEnable;
}

- (KKFFTrack *)videoTrack{
    return self.formatContext.videoTrack;
}

- (KKFFTrack *)audioTrack{
    return self.formatContext.audioTrack;
}

- (NSArray<KKFFTrack *> *)videoTracks{
    return self.formatContext.videoTracks;
}

- (NSArray<KKFFTrack *> *)audioTracks{
    return self.formatContext.audioTracks;
}

#pragma mark - setter/getter

- (void)setProgress:(NSTimeInterval)progress{
    if (_progress != progress) {
        _progress = progress;
        if ([self.delegate respondsToSelector:@selector(decoder:didChangeValueOfProgress:)]) {
            [self.delegate decoder:self didChangeValueOfProgress:_progress];
        }
    }
}

- (void)setBuffering:(BOOL)buffering{
    if (_buffering != buffering) {
        _buffering = buffering;
        if ([self.delegate respondsToSelector:@selector(decoder:didChangeValueOfBuffering:)]) {
            [self.delegate decoder:self didChangeValueOfBuffering:_buffering];
        }
    }
}

- (void)setDecodeFinished:(BOOL)decodeFinished{
    if (_decodeFinished != decodeFinished) {
        _decodeFinished = decodeFinished;
        if (_decodeFinished) {
            self.progress = self.duration;
            if ([self.delegate respondsToSelector:@selector(decoderDidFinished:)]) {
                [self.delegate decoderDidFinished:self];
            }
        }
    }
}

- (void)setBufferedDuration:(NSTimeInterval)bufferedDuration{
    if (_bufferedDuration != bufferedDuration) {
        _bufferedDuration = bufferedDuration;
        if (_bufferedDuration <= 0.000001) {
            _bufferedDuration = 0;
        }
        if ([self.delegate respondsToSelector:@selector(decoder:didChangeValueOfBufferedDuration:)]) {
            [self.delegate decoder:self didChangeValueOfBufferedDuration:_bufferedDuration];
        }
        if (_bufferedDuration <= 0 && self.readPacketFinish) {
            self.decodeFinished = YES;
        }
        [self checkBufferingStatus];
    }
}

- (NSDictionary *)metadata{
    return self.formatContext.metadata;
}

- (NSTimeInterval)duration{
    return self.formatContext.duration;
}

- (NSTimeInterval)bitrate{
    return self.formatContext.bitrate;
}

- (BOOL)seekEnable{
    return self.formatContext.seekEnable;
}

- (CGSize)presentationSize{
    return self.formatContext.videoPresentationSize;
}

- (CGFloat)aspect{
    return self.formatContext.videoAspect;
}

- (BOOL)videoDecodeOnMainThread{
    return self.videoDecoder.decodeOnMainThread;
}

@end
