//
//  KKPlayerInterface.m
//  KKPlayer
//
//  Created by finger on 16/6/28.
//  Copyright © 2016年 finger. All rights reserved.
//

#import "KKPlayerInterface.h"
#import "KKRenderView.h"
#import "KKAVPlayer.h"
#import "KKFFPlayer.h"
#import <objc/runtime.h>
#import "KKAudioManager.h"

@interface KKPlayerInterface ()

@property(nonatomic,strong)KKAVPlayer *avPlayer;
@property(nonatomic,strong)KKFFPlayer *ffPlayer;

@property(nonatomic,copy)NSURL *contentURL;
@property(nonatomic,strong)NSMutableDictionary *formatContextOptions;
@property(nonatomic,strong)NSMutableDictionary *codecContextOptions;
@property(nonatomic,assign)KKVideoType videoType;
@property(nonatomic,assign)KKDecoderType decoderType;
@property(nonatomic,assign)KKDisplayType displayType;
@property(nonatomic,assign)KKGravityMode viewGravityMode;
@property(nonatomic,assign)KKPlayerBackgroundMode backgroundMode;
@property(nonatomic,assign)KKMediaFormat mediaFormat;
@property(nonatomic,strong)KKRenderView *renderView;

@property(nonatomic,assign)BOOL needAutoPlay;
@property(nonatomic,assign)NSTimeInterval lastForegroundTimeInterval;

@end

@implementation KKPlayerInterface

+ (instancetype)player{
    return [[self alloc] init];
}

- (instancetype)init{
    if (self = [super init]) {
        [self setupNotification];
        [self configFFmpegOptions];
        self.contentURL = nil;
        self.videoType = KKVideoTypeNormal;
        self.backgroundMode = KKPlayerBackgroundModeAutoPlayAndPause;
        self.displayType = KKDisplayTypeNormal;
        self.viewGravityMode = KKGravityModeResizeAspect;
        self.decoderType = KKDecoderTypeFFmpeg;
        self.mediaFormat = KKMediaFormatError;
        self.playableBufferInterval = 2.f;
        self.volume = 1;
        self.renderView = [KKRenderView renderViewWithPlayerInterface:self];
    }
    return self;
}

- (void)dealloc{
    [self cleanPlayer];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[KKAudioManager manager] removeHandlerTarget:self];
    KKPlayerLog(@"KKPlayer release");
}

- (void)cleanPlayer{
    [self.avPlayer stop];
    self.avPlayer = nil;
    
    [self.ffPlayer stop];
    self.ffPlayer = nil;
    
    [self cleanPlayerView];
    
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    
    self.needAutoPlay = NO;
}

- (void)cleanPlayerView{
    [self.renderView.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [obj removeFromSuperview];
    }];
}

#pragma mark -- 播放器初始化

- (void)preparePlayerWithURL:(nullable NSURL *)contentURL
                   videoType:(KKVideoType)videoType
                 displayType:(KKDisplayType)displayType{
    self.videoType = videoType;
    self.displayType = displayType;
    self.contentURL = contentURL;
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:{
            [self.ffPlayer stop];
            [self.avPlayer prepareVideoForceRenderWithGL:NO];
        }
            break;
        case KKDecoderTypeFFmpeg:{
            [self.avPlayer stop];
            [self.ffPlayer prepareVideo];
        }
            break;
        case KKDecoderTypeError:{
            [self.avPlayer stop];
            [self.ffPlayer stop];
        }
            break;
        case KKDecoderTypeEmpty:{
            
        }
            break;
    }
}

#pragma mark -- 如果使用avplayer播放失败，则使用ffmpeg解码

- (void)switchDecoderToFFmpeg{
    self.decoderType = KKDecoderTypeFFmpeg;
    [self.avPlayer stop];
    [self.ffPlayer prepareVideo];
}

#pragma mark -- 播放控制

- (void)play{
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            [self.avPlayer play];
            break;
        case KKDecoderTypeFFmpeg:
            [self.ffPlayer play];
            break;
        case KKDecoderTypeError:
            break;
        case KKDecoderTypeEmpty:
            break ;
    }
}

- (void)pause{
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            [self.avPlayer pause];
            break;
        case KKDecoderTypeFFmpeg:
            [self.ffPlayer pause];
            break;
        case KKDecoderTypeError:
            break;
        case KKDecoderTypeEmpty:
            break ;
    }
}

- (void)stop{
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [self preparePlayerWithURL:nil videoType:KKVideoTypeNormal displayType:KKDisplayTypeNormal];
}

- (void)seekToTime:(NSTimeInterval)time{
    [self seekToTime:time completeHandler:nil];
}

- (void)seekToTime:(NSTimeInterval)time completeHandler:(nullable void (^)(BOOL))completeHandler{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            [self.avPlayer seekToTime:time completeHandler:completeHandler];
            break;
        case KKDecoderTypeFFmpeg:
            [self.ffPlayer seekToTime:time completeHandler:completeHandler];
            break;
        case KKDecoderTypeError:
            break;
        case KKDecoderTypeEmpty:
            break ;
    }
}

#pragma mark -- 监听前后台 & 中断处理

- (void)setupNotification{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    @weakify(self);
    KKAudioManager *manager = [KKAudioManager manager];
    [manager setHandlerTarget:self interruption:^(id handlerTarget, KKAudioManager *audioManager, KKAudioManagerInterruptionType type, KKAudioManagerInterruptionOption option) {
        @strongify(self);
        if (type == KKAudioManagerInterruptionTypeBegin) {
            switch (self.state) {
                case KKPlayerStatePlaying:
                case KKPlayerStateBuffering:{
                    NSTimeInterval timeInterval = [[NSDate date] timeIntervalSince1970];
                    if (timeInterval - self.lastForegroundTimeInterval > 1.5) {
                        [self pause];
                    }
                }
                    break;
                default:
                    break;
            }
        }
    } routeChange:^(id handlerTarget, KKAudioManager *audioManager, KKAudioManagerRouteChangeReason reason) {
        @strongify(self);
        if (reason == KKAudioManagerRouteChangeReasonOldDeviceUnavailable) {
            switch (self.state) {
                case KKPlayerStatePlaying:
                case KKPlayerStateBuffering:{
                    [self pause];
                }
                    break;
                default:
                    break;
            }
        }
    }];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification{
    switch (self.backgroundMode) {
        case KKPlayerBackgroundModeNothing:
        case KKPlayerBackgroundModeContinue:
            break;
        case KKPlayerBackgroundModeAutoPlayAndPause:{
            switch (self.state) {
                case KKPlayerStatePlaying:
                case KKPlayerStateBuffering:{
                    self.needAutoPlay = YES;
                    [self pause];
                }
                    break;
                default:
                    break;
            }
        }
            break;
    }
}

- (void)applicationWillEnterForeground:(NSNotification *)notification{
    switch (self.backgroundMode) {
        case KKPlayerBackgroundModeNothing:
        case KKPlayerBackgroundModeContinue:
            break;
        case KKPlayerBackgroundModeAutoPlayAndPause:{
            switch (self.state) {
                case KKPlayerStateSuspend:{
                    if (self.needAutoPlay) {
                        self.needAutoPlay = NO;
                        [self play];
                        self.lastForegroundTimeInterval = [NSDate date].timeIntervalSince1970;
                    }
                }
                    break;
                default:
                    break;
            }
        }
            break;
    }
}

#pragma mark -- ffmpeg配置

- (void)configFFmpegOptions{
    self.formatContextOptions = [NSMutableDictionary dictionary];
    self.codecContextOptions = [NSMutableDictionary dictionary];
    
    [self setFFmpegFormatContextOptionStringValue:@"KKPlayer" forKey:@"user-agent"];
    [self setFFmpegFormatContextOptionIntValue:20 * 1000 * 1000 forKey:@"timeout"];
    [self setFFmpegFormatContextOptionIntValue:1 forKey:@"reconnect"];
}

- (NSDictionary *)ffmpegFormatContextOptions{
    return [self.formatContextOptions copy];
}

- (void)setFFmpegFormatContextOptionIntValue:(int64_t)value forKey:(NSString *)key{
    [self.formatContextOptions setValue:@(value) forKey:key];
}

- (void)setFFmpegFormatContextOptionStringValue:(NSString *)value forKey:(NSString *)key{
    [self.formatContextOptions setValue:value forKey:key];
}

- (void)removeFFmpegFormatContextOptionForKey:(NSString *)key{
    [self.formatContextOptions removeObjectForKey:key];
}

- (NSDictionary *)ffmpegCodecContextOptions{
    return [self.codecContextOptions copy];
}

- (void)setFFmpegCodecContextOptionIntValue:(int64_t)value forKey:(NSString *)key{
    [self.codecContextOptions setValue:@(value) forKey:key];
}

- (void)setFFmpegCodecContextOptionStringValue:(NSString *)value forKey:(NSString *)key{
    [self.codecContextOptions setValue:value forKey:key];
}

- (void)removeFFmpegCodecContextOptionForKey:(NSString *)key{
    [self.codecContextOptions removeObjectForKey:key];
}

#pragma mark -- @property getter & setter

- (KKAVPlayer *)avPlayer{
    if(!_avPlayer){
        _avPlayer = [KKAVPlayer playerWithPlayerInterface:self];
    }
    return _avPlayer;
}

- (KKFFPlayer *)ffPlayer{
    if(!_ffPlayer){
        _ffPlayer = [KKFFPlayer playerWithPlayerInterface:self];
    }
    return _ffPlayer;
}

- (BOOL)seekEnable{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.seekEnable;
            break;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.seekEnable;
        case KKDecoderTypeError:
            return NO;
        case KKDecoderTypeEmpty:
            return NO;
    }
}

- (BOOL)seeking{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.seeking;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.seeking;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return NO;
    }
}

- (void)setVolume:(CGFloat)volume{
    _volume = volume;
    [self.avPlayer reloadVolume];
    [self.ffPlayer reloadVolume];
}

- (void)setPlayableBufferInterval:(NSTimeInterval)playableBufferInterval{
    _playableBufferInterval = playableBufferInterval;
    [self.ffPlayer reloadPlayableBufferInterval];
}

- (void)setViewGravityMode:(KKGravityMode)viewGravityMode{
    _viewGravityMode = viewGravityMode;
    [self.renderView resetAVPlayerVideoGravity];
}

- (void)setContentURL:(NSURL *)contentURL{
    _contentURL = contentURL ;
    
    if (!_contentURL){
        _mediaFormat = KKMediaFormatError;
    }
    NSString * path = nil;
    if (self.contentURL.isFileURL) {
        path = self.contentURL.path;
    } else {
        path = self.contentURL.absoluteString;
    }
    path = [path lowercaseString];
    
    if ([path hasPrefix:@"rtmp:"]){
        _mediaFormat = KKMediaFormatRTMP;
    }else if ([path hasPrefix:@"rtsp:"]){
        _mediaFormat = KKMediaFormatRTSP;
    }else if ([path containsString:@".flv"]){
        _mediaFormat = KKMediaFormatFLV;
    }else if ([path containsString:@".mp4"]){
        _mediaFormat = KKMediaFormatMPEG4;
    }else if ([path containsString:@".mp3"]){
        _mediaFormat = KKMediaFormatMP3;
    }else if ([path containsString:@".m3u8"]){
        _mediaFormat = KKMediaFormatM3U8;
    }else if ([path containsString:@".mov"]){
        _mediaFormat = KKMediaFormatMOV;
    }else{
        _mediaFormat = KKMediaFormatUnknown;
    }
    
    switch (_mediaFormat) {
        case KKMediaFormatError:
        case KKMediaFormatUnknown:
        case KKMediaFormatFLV:
        case KKMediaFormatM3U8:
        case KKMediaFormatRTMP:
        case KKMediaFormatRTSP:{
            _decoderType = KKDecoderTypeFFmpeg;
        }
            break;
        case KKMediaFormatMP3:
        case KKMediaFormatMPEG4:
        case KKMediaFormatMOV:{
            _decoderType = KKDecoderTypeAVPlayer;
        }
            break;
        default:{
            _decoderType = KKDecoderTypeFFmpeg;
        }
            break;
    }
}

- (KKPlayerState)state{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.state;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.state;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return KKPlayerStateNone;
    }
}

- (CGSize)presentationSize{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.presentationSize;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.presentationSize;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return CGSizeZero;
    }
}

- (NSTimeInterval)bitrate{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.bitrate;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.bitrate;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return 0;
    }
}

- (NSTimeInterval)progress{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.progress;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.progress;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return 0;
    }
}

- (NSTimeInterval)duration{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.duration;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.duration;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return 0;
    }
}

- (NSTimeInterval)playableTime{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.playableTime;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.playableTime;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return 0;
    }
}

- (UIImage *)snapshot{
    return self.renderView.snapshot;
}

- (UIView *)videoRenderView{
    return self.renderView;
}

@end


#pragma mark -- 音视频轨 Category

@implementation KKPlayerInterface(Tracks)

- (BOOL)videoEnable{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.videoEnable;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.videoEnable;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return NO;
    }
}

- (BOOL)audioEnable{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.audioEnable;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.audioEnable;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return NO;
    }
}

- (KKPlayerTrack *)videoTrack{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.videoTrack;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.videoTrack;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return nil;
    }
}

- (KKPlayerTrack *)audioTrack{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.audioTrack;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.audioTrack;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return nil;
    }
}

- (NSArray<KKPlayerTrack *> *)videoTracks{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.videoTracks;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.videoTracks;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return nil;
    }
}

- (NSArray<KKPlayerTrack *> *)audioTracks{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return self.avPlayer.audioTracks;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.audioTracks;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return nil;
    }
}

@end


#pragma mark -- Thread Category

@implementation KKPlayerInterface(Thread)

- (BOOL)videoDecodeOnMainThread{
    switch (self.decoderType){
        case KKDecoderTypeAVPlayer:
            return NO;
        case KKDecoderTypeFFmpeg:
            return self.ffPlayer.videoDecodeOnMainThread;
        case KKDecoderTypeError:
        case KKDecoderTypeEmpty:
            return NO;
    }
}

- (BOOL)audioDecodeOnMainThread{
    return NO;
}

@end

#pragma mark -- 播放器状态回调

@implementation KKPlayerInterface(KKPlayerState)

- (void)playerStateChangeBlock:(stateChangeBlock)stateChangeBlock progressChangeBlock:(progressChangeBlock)progressChangeBlock playableChangeBlock:(playableChangeBlock)playableChangeBlock errorBlock:(errorBlock)errorBlock{
    self.stateChangeBlock = stateChangeBlock;
    self.progressChangeBlock = progressChangeBlock;
    self.playableChangeBlock = playableChangeBlock ;
    self.errorBlock = errorBlock;
}

- (stateChangeBlock)stateChangeBlock{
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setStateChangeBlock:(stateChangeBlock)stateChangeBlock{
    objc_setAssociatedObject(self, @selector(stateChangeBlock), stateChangeBlock, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (progressChangeBlock)progressChangeBlock{
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setProgressChangeBlock:(progressChangeBlock)progressChangeBlock{
    objc_setAssociatedObject(self, @selector(progressChangeBlock), progressChangeBlock, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (playableChangeBlock)playableChangeBlock{
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setPlayableChangeBlock:(playableChangeBlock)playableChangeBlock{
    objc_setAssociatedObject(self, @selector(playableChangeBlock), playableChangeBlock, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (errorBlock)errorBlock{
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setErrorBlock:(errorBlock)errorBlock{
    objc_setAssociatedObject(self, @selector(errorBlock), errorBlock, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (id<KKPlayerStateDelegate>)playerStateDelegate{
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setPlayerStateDelegate:(id<KKPlayerStateDelegate>)playerStateDelegate{
    objc_setAssociatedObject(self, @selector(playerStateDelegate), playerStateDelegate, OBJC_ASSOCIATION_ASSIGN);
}

@end
