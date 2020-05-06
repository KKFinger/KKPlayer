//
//  KKAVPlayer.m
//  KKPlayer
//
//  Created by finger on 16/6/28.
//  Copyright © 2016年 single. All rights reserved.
//

#import "KKAVPlayer.h"
#import "KKRenderView.h"
#import <AVFoundation/AVFoundation.h>
#import "KKPlayerEventCenter.h"

static CGFloat const PixelBufferRequestInterval = 0.03f;
static NSString *const AVMediaSelectionOptionTrackIDKey = @"MediaSelectionOptionsPersistentID";

@interface KKAVPlayer()<KKRenderAVPlayerDelegate>

@property(nonatomic,weak)KKPlayerInterface *playerInterface;

@property(nonatomic,assign)KKPlayerState state;
@property(nonatomic,assign)KKPlayerState stateBeforBuffering;//缓冲时，有可能正在播放，也有可能暂停播放
@property(nonatomic,assign)NSTimeInterval playableTime;//可播放的长度
@property(nonatomic,assign)NSTimeInterval readyToPlayTime;
@property(nonatomic,assign)BOOL forceRenderWithOpenGL;//NO ,使用AVPlayer渲染，YES , 使用opengl渲染

//播放器相关
@property(nonatomic,strong)id playBackTimeObserver;//监听播放进度
@property(nonatomic,strong)AVPlayer *player;//渲染图层
@property(nonatomic,strong)AVPlayerItem *playerItem;//播放对象
@property(nonatomic,strong)AVURLAsset *asset;//播放资源
@property(nonatomic,strong)AVPlayerItemVideoOutput *pixelBufOutput;//获取视频帧的数据，用于GLKView的渲染
@property(nonatomic,strong)NSArray<NSString *> *assetloadKeys;

//音视频轨道信息
@property(nonatomic,assign)BOOL videoEnable;
@property(nonatomic,assign)BOOL audioEnable;
@property(nonatomic,strong)KKPlayerTrack *videoTrack;
@property(nonatomic,strong)KKPlayerTrack *audioTrack;
@property(nonatomic,strong)NSArray<KKPlayerTrack *> *videoTracks;
@property(nonatomic,strong)NSArray<KKPlayerTrack *> *audioTracks;

@end

@implementation KKAVPlayer

+ (instancetype)playerWithPlayerInterface:(KKPlayerInterface *)playerInterface{
    return [[self alloc] initWithPlayerInterface:playerInterface];
}

- (instancetype)initWithPlayerInterface:(KKPlayerInterface *)playerInterface{
    if (self = [super init]) {
        self.playerInterface = playerInterface;
        self.assetloadKeys = @[@"tracks", @"playable"] ;
        
        // 监听耳机插入和拔掉通知
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListenerCallback:) name:AVAudioSessionRouteChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self clear];
}

#pragma mark -- 准备操作

/**
 prepareVideo
 @param forceRenderWithOpenGL -- NO ,使用AVPlayer渲染，YES , 使用opengl渲染
 */
- (void)prepareVideoForceRenderWithGL:(BOOL)forceRenderWithOpenGL{
    
    [self clear];
    
    if (!self.playerInterface.contentURL){
        return;
    }
    
    self.forceRenderWithOpenGL = forceRenderWithOpenGL;
    
    [((KKRenderView *)(self.playerInterface.videoRenderView)) setRenderAVPlayerDelegate:self];
    [((KKRenderView *)(self.playerInterface.videoRenderView)) setDecodeType:KKDecoderTypeAVPlayer];
    
    self.asset = [AVURLAsset assetWithURL:self.playerInterface.contentURL];
    
    [self startBuffering];
    [self setupPlayerItem];
    [self setupPlayerWithPlayItem:self.playerItem];
    
    switch (self.playerInterface.videoType) {
        case KKVideoTypeNormal:
            if(self.forceRenderWithOpenGL){
                [((KKRenderView *)(self.playerInterface.videoRenderView)) setRenderViewType:KKRenderViewTypeGLKView];
            }else{
                [((KKRenderView *)(self.playerInterface.videoRenderView)) setRenderViewType:KKRenderViewTypeAVPlayerLayer];
            }
            break;
        case KKVideoTypeVR:{//VR使用opengl渲染,视频帧数据从AVPlayerItemVideoOutput中获取
            [((KKRenderView *)(self.playerInterface.videoRenderView)) setRenderViewType:KKRenderViewTypeGLKView];
        }
            break;
    }
}

#pragma mark -- 初始化AVPlayerItem

- (void)setupPlayerItem{
    self.playerItem = [AVPlayerItem playerItemWithAsset:self.asset automaticallyLoadedAssetKeys:self.assetloadKeys];
    [self.playerItem addObserver:self forKeyPath:@"status" options:0 context:NULL];//播放状态
    [self.playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:NULL];//缓冲状态
    [self.playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:NULL];//加载情况
    
    //播放完成通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemPlayEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
    //播放错误通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemFail:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.playerItem];
}

#pragma mark -- 初始化渲染图层

- (void)setupPlayerWithPlayItem:(AVPlayerItem *)playItem{
    
    self.player = [AVPlayer playerWithPlayerItem:playItem];
    
    @weakify(self);
    self.playBackTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        @strongify(self);
        if (self.state == KKPlayerStatePlaying) {
            CGFloat current = CMTimeGetSeconds(time);
            CGFloat duration = self.duration;
            double percent = [self percentForTime:current duration:duration];
            [KKPlayerEventCenter raiseEvent:self.playerInterface progressPercent:percent current:current total:duration];
        }
    }];
    
    [((KKRenderView *)(self.playerInterface.videoRenderView)) resetAVPlayer];
    
    [self reloadVolume];
}

#pragma mark -- 播放控制

- (void)play{
    switch (self.state) {
        case KKPlayerStateFinished:
            [self.player seekToTime:kCMTimeZero];
            self.state = KKPlayerStatePlaying;
            break;
        case KKPlayerStateFailed:
            [self prepareVideoForceRenderWithGL:self.forceRenderWithOpenGL];
            break;
        case KKPlayerStateNone:
            self.state = KKPlayerStateBuffering;
            break;
        case KKPlayerStateSuspend:
        case KKPlayerStateBuffering:
        case KKPlayerStateReadyToPlay:
            self.state = KKPlayerStatePlaying;
            break;
        default:
            self.state = KKPlayerStateBuffering;
            break;
    }
    
    [self.player play];
}

- (void)startBuffering{
    [self.player pause];
    if (self.state != KKPlayerStateBuffering) {
        self.stateBeforBuffering = self.state;
    }
    self.state = KKPlayerStateBuffering;
}

- (void)resumePlayIfNeed{
    if (self.stateBeforBuffering == KKPlayerStatePlaying) {
        self.stateBeforBuffering = KKPlayerStateNone;
        self.state = KKPlayerStatePlaying;
        [self.player play];
    }
}

- (void)pause{
    [self.player pause];
    self.state = KKPlayerStateSuspend;
}

- (BOOL)seekEnable{
    if (self.duration <= 0 || self.playerItem.status != AVPlayerItemStatusReadyToPlay) {
        return NO;
    }
    return YES;
}

- (void)seekToTime:(NSTimeInterval)time{
    [self seekToTime:time completeHandler:nil];
}

- (void)seekToTime:(NSTimeInterval)time completeHandler:(void (^)(BOOL))completeHandler{
    if (!self.seekEnable || self.playerItem.status != AVPlayerItemStatusReadyToPlay) {
        if (completeHandler) {
            completeHandler(NO);
        }
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        self.seeking = YES;
        
        [self startBuffering];
        
        @weakify(self);
        [self.playerItem seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC) completionHandler:^(BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @strongify(self);
                
                self.seeking = NO;
                
                [self resumePlayIfNeed];
                
                if (completeHandler) {
                    completeHandler(finished);
                }
                
                KKPlayerLog(@"KKAVPlayer seek success");
            });
        }];
    });
}

- (void)stop{
    [self clear];
}

#pragma mark -- KVO,播放状态

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context{
    if (object == self.playerItem) {
        if ([keyPath isEqualToString:@"status"]){
            switch (self.playerItem.status) {
                case AVPlayerItemStatusUnknown:{
                    [self startBuffering];
                    KKPlayerLog(@"KKAVPlayer item status unknown");
                }
                    break;
                case AVPlayerItemStatusReadyToPlay:{
                    [self setupTrackInfo];
                    self.readyToPlayTime = [NSDate date].timeIntervalSince1970;
                    self.state = KKPlayerStateReadyToPlay;
                    KKPlayerLog(@"KKAVPlayer item status ready to play");
                }
                    break;
                case AVPlayerItemStatusFailed:{
                    NSError *error = nil;
                    if (self.playerItem.error) {
                        error = self.playerItem.error;
                    } else if (self.player.error) {
                        error = self.player.error;
                    } else {
                        error = [NSError errorWithDomain:@"AVPlayer playback error" code:-1 userInfo:nil];
                    }
                    
                    self.readyToPlayTime = 0;
                    self.state = KKPlayerStateFailed;
                    
                    [KKPlayerEventCenter raiseEvent:self.playerInterface error:error];
                    
                    KKPlayerLog(@"KKAVPlayer item status failed");
                }
                    break;
            }
        }else if ([keyPath isEqualToString:@"playbackBufferEmpty"]){
            if (self.playerItem.playbackBufferEmpty) {
                [self startBuffering];
            }
        }else if ([keyPath isEqualToString:@"loadedTimeRanges"]){
            [self reloadPlayableTime];
            NSTimeInterval interval = self.playableTime - self.progress;//剩余的缓冲时长
            if (interval > self.playerInterface.playableBufferInterval) {
                [self resumePlayIfNeed];
            }
        }
    }
}

#pragma mark -- 播放完成/播放错误通知

- (void)playerItemPlayEnd:(NSNotification *)notification{
    self.state = KKPlayerStateFinished;
}

- (void)playerItemFail:(NSNotification *)notification{
    self.state = KKPlayerStateFailed ;
}

#pragma mark -- 设置视频帧的输出

- (void)trySetupFrameOutput{
    BOOL isReadyToPlay = self.playerItem.status == AVPlayerStatusReadyToPlay && self.readyToPlayTime > 0 && (([NSDate date].timeIntervalSince1970 - self.readyToPlayTime) > 0.3);
    if (isReadyToPlay && !self.pixelBufOutput) {
        [self setupFrameOutput];
    }
}

- (void)setupFrameOutput{
    [self cleanFrameOutput];
    NSDictionary *pixelBufferAttr = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)};
    self.pixelBufOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixelBufferAttr];
    [self.pixelBufOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:PixelBufferRequestInterval];
    [self.playerItem addOutput:self.pixelBufOutput];
    
    KKPlayerLog(@"KKAVPlayer add output success");
}

#pragma mark -- KKRenderAVPlayerDelegate

- (AVPlayer *)renderGetAVPlayer{
    return self.player;
}

- (CVPixelBufferRef)renderGetPixelBufferAtCurrentTime{
    if (self.seeking){
        return nil;
    }
    
    CVPixelBufferRef pixelBuffer = [self.pixelBufOutput copyPixelBufferForItemTime:self.playerItem.currentTime itemTimeForDisplay:nil];
    if (!pixelBuffer) {
        [self trySetupFrameOutput];
    }
    return pixelBuffer;
}

- (UIImage *)renderGetSnapshotAtCurrentTime{
    switch (self.playerInterface.videoType) {
        case KKVideoTypeNormal:{
            AVAssetImageGenerator *imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:self.asset];
            imageGenerator.appliesPreferredTrackTransform = YES;
            imageGenerator.requestedTimeToleranceBefore = kCMTimeZero;
            imageGenerator.requestedTimeToleranceAfter = kCMTimeZero;
            
            NSError * error = nil;
            CMTime time = self.playerItem.currentTime;
            CMTime actualTime;
            CGImageRef cgImage = [imageGenerator copyCGImageAtTime:time actualTime:&actualTime error:&error];
            UIImage * image = KKImageWithCGImage(cgImage);
            return image;
        }
            break;
        case KKVideoTypeVR:{
            return nil;
        }
            break;
    }
}

#pragma mark -- 清理工作

- (void)clear{
    [KKPlayerEventCenter raiseEvent:self.playerInterface progressPercent:0 current:0 total:0];
    [KKPlayerEventCenter raiseEvent:self.playerInterface playablePercent:0 current:0 total:0];
    
    [self.asset cancelLoading];
    self.asset = nil;
    
    [self cleanFrameOutput];
    [self cleanAVPlayerItem];
    [self cleanAVPlayer];
    [self cleanTrackInfo];
    
    self.state = KKPlayerStateNone;
    self.stateBeforBuffering = KKPlayerStateNone;
    self.playableTime = 0;
    self.readyToPlayTime = 0;
    
    ((KKRenderView *)(self.playerInterface.videoRenderView)).decodeType = KKDecoderTypeEmpty;
    ((KKRenderView *)(self.playerInterface.videoRenderView)).renderViewType = KKRenderViewTypeEmpty;
}

- (void)cleanFrameOutput{
    if (self.playerItem && self.pixelBufOutput) {
        [self.playerItem removeOutput:self.pixelBufOutput];
    }
    self.pixelBufOutput = nil;
}

- (void)cleanAVPlayerItem{
    if (self.playerItem) {
        [self.playerItem cancelPendingSeeks];
        [self.playerItem removeObserver:self forKeyPath:@"status"];
        [self.playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
        [self.playerItem removeObserver:self forKeyPath:@"loadedTimeRanges"];
        if(self.pixelBufOutput){
            [self.playerItem removeOutput:self.pixelBufOutput];
            self.pixelBufOutput = nil ;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
        self.playerItem = nil;
    }
}

- (void)cleanAVPlayer{
    [self.player pause];
    [self.player cancelPendingPrerolls];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    
    if (self.playBackTimeObserver) {
        [self.player removeTimeObserver:self.playBackTimeObserver];
        self.playBackTimeObserver = nil;
    }
    
    self.player = nil;
    
    [((KKRenderView *)(self.playerInterface.videoRenderView)) resetAVPlayer];
}

- (void)cleanTrackInfo{
    self.videoEnable = NO;
    self.videoTrack = nil;
    self.videoTracks = nil;
    
    self.audioEnable = NO;
    self.audioTrack = nil;
    self.audioTracks = nil;
}

#pragma mark -- track info

- (void)setupTrackInfo{
    if (self.videoEnable || self.audioEnable){
        return;
    }
    
    NSMutableArray <KKPlayerTrack *> *videoTracks = [NSMutableArray array];
    NSMutableArray <KKPlayerTrack *> *audioTracks = [NSMutableArray array];
    
    for (AVAssetTrack *obj in self.asset.tracks) {
        if ([obj.mediaType isEqualToString:AVMediaTypeVideo]) {
            self.videoEnable = YES;
            [videoTracks addObject:[self playerTrackFromAVTrack:obj]];
        } else if ([obj.mediaType isEqualToString:AVMediaTypeAudio]) {
            self.audioEnable = YES;
            [audioTracks addObject:[self playerTrackFromAVTrack:obj]];
        }
    }
    
    if (videoTracks.count > 0) {
        self.videoTracks = videoTracks;
        AVMediaSelectionGroup *videoGroup = [self.asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicVisual];
        if (videoGroup) {
            int trackID = [[videoGroup.defaultOption.propertyList objectForKey:AVMediaSelectionOptionTrackIDKey] intValue];
            for (KKPlayerTrack *obj in self.videoTracks) {
                if (obj.index == (int)trackID) {
                    self.videoTrack = obj;
                }
            }
            if (!self.videoTrack) {
                self.videoTrack = self.videoTracks.firstObject;
            }
        } else {
            self.videoTrack = self.videoTracks.firstObject;
        }
    }
    if (audioTracks.count > 0) {
        self.audioTracks = audioTracks;
        AVMediaSelectionGroup *audioGroup = [self.asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible];
        if (audioGroup) {
            int trackID = [[audioGroup.defaultOption.propertyList objectForKey:AVMediaSelectionOptionTrackIDKey] intValue];
            for (KKPlayerTrack *obj in self.audioTracks) {
                if (obj.index == (int)trackID) {
                    self.audioTrack = obj;
                }
            }
            if (!self.audioTrack) {
                self.audioTrack = self.audioTracks.firstObject;
            }
        } else {
            self.audioTrack = self.audioTracks.firstObject;
        }
    }
}

- (KKPlayerTrack *)playerTrackFromAVTrack:(AVAssetTrack *)track{
    if (track) {
        KKPlayerTrack *obj = [[KKPlayerTrack alloc] init];
        obj.index = (int)track.trackID;
        obj.name = track.languageCode;
        return obj;
    }
    return nil;
}

/**
 *  耳机插入、拔出事件
 */
- (void)audioRouteChangeListenerCallback:(NSNotification*)notification {
    NSDictionary *interuptionDict = notification.userInfo;
    
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    
    switch (routeChangeReason) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:{
        }
            break;
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:{
            //获取上一线路描述信息并获取上一线路的输出设备类型
            AVAudioSessionRouteDescription *previousRoute = interuptionDict[AVAudioSessionRouteChangePreviousRouteKey];
            AVAudioSessionPortDescription *previousOutput = previousRoute.outputs[0];
            NSString *portType = previousOutput.portType;
            if ([portType isEqualToString:AVAudioSessionPortHeadphones]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
                    [self play];
                });
            }
        }
            break;
        case AVAudioSessionRouteChangeReasonCategoryChange:
            break;
    }
}

#pragma mark -- @property Setter & Getter

- (NSTimeInterval)progress{
    CMTime currentTime = self.playerItem.currentTime;
    Boolean indefinite = CMTIME_IS_INDEFINITE(currentTime);
    Boolean invalid = CMTIME_IS_INVALID(currentTime);
    if (indefinite || invalid) {
        return 0;
    }
    return CMTimeGetSeconds(self.playerItem.currentTime);
}

- (NSTimeInterval)duration{
    CMTime duration = self.playerItem.duration;
    Boolean indefinite = CMTIME_IS_INDEFINITE(duration);
    Boolean invalid = CMTIME_IS_INVALID(duration);
    if (indefinite || invalid) {
        return 0;
    }
    return CMTimeGetSeconds(self.playerItem.duration);;
}

- (double)percentForTime:(NSTimeInterval)time duration:(NSTimeInterval)duration{
    double percent = 0;
    if (time > 0) {
        if (duration <= 0) {
            percent = 1;
        } else {
            percent = time / duration;
        }
    }
    return percent;
}

//暂时获取不到，待解决
- (NSTimeInterval)bitrate{
    return 0;
}

- (void)setState:(KKPlayerState)state{
    if (_state != state) {
        KKPlayerState temp = _state;
        _state = state;
        [KKPlayerEventCenter raiseEvent:self.playerInterface statePrevious:temp current:_state];
    }
}

- (void)reloadVolume{
    self.player.volume = self.playerInterface.volume;
}

- (void)reloadPlayableTime{
    if (self.playerItem.status == AVPlayerItemStatusReadyToPlay) {
        CMTimeRange range = [self.playerItem.loadedTimeRanges.firstObject CMTimeRangeValue];
        if (CMTIMERANGE_IS_VALID(range)) {
            NSTimeInterval start = CMTimeGetSeconds(range.start);
            NSTimeInterval duration = CMTimeGetSeconds(range.duration);
            self.playableTime = (start + duration);
        }
    } else {
        self.playableTime = 0;
    }
}

- (void)setPlayableTime:(NSTimeInterval)playableTime{
    if (_playableTime != playableTime) {
        _playableTime = playableTime;
        CGFloat duration = self.duration;
        double percent = [self percentForTime:_playableTime duration:duration];
        [KKPlayerEventCenter raiseEvent:self.playerInterface playablePercent:percent current:playableTime total:duration];
    }
}

- (CGSize)presentationSize{
    if (self.playerItem) {
        return self.playerItem.presentationSize;
    }
    return CGSizeZero;
}

@end
