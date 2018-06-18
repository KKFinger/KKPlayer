//
//  KKFFPlayer.m
//  KKPlayer
//
//  Created by finger on 03/01/2017.
//  Copyright © 2017 finger. All rights reserved.
//

#import "KKFFPlayer.h"
#import "KKFFDecoder.h"
#import "KKAudioManager.h"
#import "KKRenderView.h"
#import "KKPlayerEventCenter.h"

@interface KKFFPlayer()<KKFFDecoderDelegate,KKFFDecoderVideoConfigDelegate, KKFFDecoderAudioConfigDelegate,KKAudioManagerDelegate,KKRenderFFmpegDelegate>

@property(nonatomic,weak)KKPlayerInterface *playerInterface;
@property(nonatomic,strong)KKFFAudioFrame *currentAudioFrame;

@property(nonatomic,strong)KKFFDecoder *decoder;
@property(nonatomic,strong)KKAudioManager *audioManager;//播放声音，使用ffmpeg解码时，声音使用audioUnit播放

@property(nonatomic,strong)NSLock *stateLock;

@property(nonatomic,assign)BOOL playing;
@property(nonatomic,assign)BOOL prepareToken;//是否已经准备好播放
@property(nonatomic,assign)KKPlayerState state;
@property(nonatomic,assign)NSTimeInterval progress;
@property(nonatomic,assign)NSTimeInterval lastPostProgressTime;
@property(nonatomic,assign)NSTimeInterval lastPostPlayableTime;

@property(nonatomic,strong)NSMutableDictionary *formatContextOptions;
@property(nonatomic,strong)NSMutableDictionary *codecContextOptions;

@end

@implementation KKFFPlayer

+ (instancetype)playerWithPlayerInterface:(KKPlayerInterface *)playerInterface{
    return [[self alloc] initWithPlayerInterface:playerInterface];
}

- (instancetype)initWithPlayerInterface:(KKPlayerInterface *)playerInterface{
    if (self = [super init]) {
        self.playerInterface = playerInterface;
        self.stateLock = [[NSLock alloc] init];
        self.audioManager = [KKAudioManager manager];
        [self.audioManager registerAudioSession];
        [self.audioManager setDelegate:self];
    }
    return self;
}

- (void)dealloc{
    [self clean];
    [self.audioManager unregisterAudioSession];
    KKPlayerLog(@"KKFFPlayer release");
}

#pragma mark -- 清理

- (void)clean{
    [self cleanDecoder];
    [self cleanFrame];
    [self cleanPlayer];
}

- (void)cleanPlayer{
    self.playing = NO;
    self.state = KKPlayerStateNone;
    self.progress = 0;
    self.playableTime = 0;
    self.prepareToken = NO;
    self.lastPostProgressTime = 0;
    self.lastPostPlayableTime = 0;
    self.formatContextOptions = nil ;
    self.codecContextOptions = nil ;
    ((KKRenderView *)(self.playerInterface.videoRenderView)).renderFFmpegDelegate = nil ;
    ((KKRenderView *)(self.playerInterface.videoRenderView)).decodeType = KKDecoderTypeEmpty;
    ((KKRenderView *)(self.playerInterface.videoRenderView)).renderViewType = KKRenderViewTypeEmpty;
}

- (void)cleanFrame{
    [self.currentAudioFrame stopPlaying];
    self.currentAudioFrame = nil;
}

- (void)cleanDecoder{
    if (self.decoder) {
        [self.decoder stopDecoder];
        self.decoder = nil;
    }
}

#pragma mark -- 准备解码

- (void)prepareVideo{
    
    if (!self.playerInterface.contentURL) return;
    
    [self clean];
    [self configFFmpegOptions];
    
    [((KKRenderView *)(self.playerInterface.videoRenderView)) setRenderFFmpegDelegate:self];
    [((KKRenderView *)(self.playerInterface.videoRenderView)) setDecodeType:KKDecoderTypeFFmpeg];
    [((KKRenderView *)(self.playerInterface.videoRenderView)) setRenderViewType:KKRenderViewTypeGLKView];
    
    self.decoder = [KKFFDecoder decoderWithContentURL:self.playerInterface.contentURL
                                 formatContextOptions:self.formatContextOptions
                                  codecContextOptions:self.codecContextOptions
                                             delegate:self
                           videoDecoderConfigDelegate:self
                           audioDecoderConfigDelegate:self];
    [self.decoder startDecoder];
    
    [self reloadVolume];
    [self reloadPlayableBufferInterval];
}

#pragma mark -- 播放控制

- (void)play{
    
    self.playing = YES;
    
    [self.decoder resume];
    
    switch (self.state) {
        case KKPlayerStateFinished:
            [self seekToTime:0];
            break;
        case KKPlayerStateNone:
        case KKPlayerStateFailed:
        case KKPlayerStateBuffering:
            self.state = KKPlayerStateBuffering;
            break;
        case KKPlayerStateSuspend:
        case KKPlayerStateSeeking:
            if (self.decoder.buffering) {
                self.state = KKPlayerStateBuffering;
            } else {
                self.state = KKPlayerStatePlaying;
            }
            break;
        case KKPlayerStateReadyToPlay:
        case KKPlayerStatePlaying:
            self.state = KKPlayerStatePlaying;
            break;
    }
}

- (void)pause{
    
    self.playing = NO;
    
    [self.decoder pause];
    
    switch (self.state) {
        case KKPlayerStateNone:
        case KKPlayerStateSuspend:
            break;
        case KKPlayerStateFailed:
        case KKPlayerStateReadyToPlay:
        case KKPlayerStateFinished:
        case KKPlayerStatePlaying:
        case KKPlayerStateBuffering:
        case KKPlayerStateSeeking:{
            self.state = KKPlayerStateSuspend;
        }
            break;
    }
}

- (void)stop{
    [self clean];
}

- (void)seekToTime:(NSTimeInterval)time{
    [self seekToTime:time completeHandler:nil];
}

- (void)seekToTime:(NSTimeInterval)time completeHandler:(void (^)(BOOL finished))completeHandler{
    if (!self.decoder.prepareToDecode) {
        if (completeHandler) {
            completeHandler(NO);
        }
        return;
    }
    [self.decoder seekToTime:time completeHandler:completeHandler];
}

- (void)reloadVolume{
    self.audioManager.volume = self.playerInterface.volume;
}

- (void)reloadPlayableBufferInterval{
    self.decoder.minBufferedDruation = self.playerInterface.playableBufferInterval;
}

#pragma mark -- KKFFDecoderDelegate

- (void)decoderWillOpenInputStream:(KKFFDecoder *)decoder{
    self.state = KKPlayerStateBuffering;
}

- (void)decoderDidPrepareToDecodeFrames:(KKFFDecoder *)decoder{
//    if (self.decoder.videoEnable) {
//        [((KKRenderView *)(self.playerInterface.videoRenderView)) setRenderViewType:KKRenderViewTypeGLKView];
//    }
}

- (void)decoderDidEndOfFile:(KKFFDecoder *)decoder{
    self.playableTime = self.duration;
}

- (void)decoderDidFinished:(KKFFDecoder *)decoder{
    self.state = KKPlayerStateFinished;
}

- (void)decoder:(KKFFDecoder *)decoder didChangeValueOfBuffering:(BOOL)buffering{
    if (buffering) {
        self.state = KKPlayerStateBuffering;
    } else {
        if (self.playing) {
            self.state = KKPlayerStatePlaying;
        } else if (!self.prepareToken) {
            self.state = KKPlayerStateReadyToPlay;
            self.prepareToken = YES;
        } else {
            self.state = KKPlayerStateSuspend;
        }
    }
}

- (void)decoder:(KKFFDecoder *)decoder didChangeValueOfBufferedDuration:(NSTimeInterval)bufferedDuration{
    self.playableTime = self.progress + bufferedDuration;
}

- (void)decoder:(KKFFDecoder *)decoder didChangeValueOfProgress:(NSTimeInterval)progress{
    self.progress = progress;
}

- (void)decoder:(KKFFDecoder *)decoder didError:(NSError *)error{
    [self errorHandler:error];
}

- (void)errorHandler:(NSError *)error{
    self.state = KKPlayerStateFailed;
    [KKPlayerEventCenter raiseEvent:self.playerInterface error:error];
}

#pragma mark -- KKFFDecoderVideoConfigDelegate

- (BOOL)decoderVideoConfigAVCodecContextDecodeAsync{
    if (self.playerInterface.videoType == KKVideoTypeVR) {
        return NO;
    }
    return YES;
}

#pragma mark -- KKFFDecoderAudioConfigDelegate

- (Float64)decoderAudioConfigGetSamplingRate{
    return self.audioManager.samplingRate;
}

- (UInt32)decoderAudioConfigGetNumberOfChannels{
    return self.audioManager.numberOfChannels;
}

#pragma mark -- KKRenderFFmpegDelegate,KKRenderView渲染视频时获取视频数据的入口

- (KKFFVideoFrame *)renderFrameWithCurrentPostion:(NSTimeInterval)currentPostion
                                  currentDuration:(NSTimeInterval)currentDuration{
    if (self.decoder) {
        return [self.decoder fetchVideoFrameWithCurrentPostion:currentPostion
                                               currentDuration:currentDuration];
    }
    return nil;
}

#pragma mark -- KKAudioManagerDelegate,获取解码的音频数据，并使用AudioUnit播放

- (void)audioManager:(KKAudioManager *)audioManager outputData:(float *)outputData numberOfFrames:(UInt32)numberOfFrames numberOfChannels:(UInt32)numberOfChannels{
    if (!self.playing) {
        memset(outputData, 0, numberOfFrames * numberOfChannels * sizeof(float));
        return;
    }
    @autoreleasepool{
        while (numberOfFrames > 0){
            if (!self.currentAudioFrame) {
                self.currentAudioFrame = [self.decoder fetchAudioFrame];
                [self.currentAudioFrame startPlaying];
            }
            if (!self.currentAudioFrame) {
                memset(outputData, 0, numberOfFrames * numberOfChannels * sizeof(float));
                return;
            }
            
            const Byte *bytes = (Byte *)self.currentAudioFrame->samples + self.currentAudioFrame.outputOffset;
            const NSUInteger bytesLeft = self.currentAudioFrame.samplesLength - self.currentAudioFrame.outputOffset;
            const NSUInteger frameSizeOf = numberOfChannels * sizeof(float);
            const NSUInteger bytesToCopy = MIN(numberOfFrames * frameSizeOf, bytesLeft);
            const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
            
            memcpy(outputData, bytes, bytesToCopy);
            numberOfFrames -= framesToCopy;
            outputData += framesToCopy * numberOfChannels;
            
            if (bytesToCopy < bytesLeft) {
                self.currentAudioFrame.outputOffset += bytesToCopy;
            } else {
                [self.currentAudioFrame stopPlaying];
                self.currentAudioFrame = nil;
            }
        }
    }
}

#pragma mark -- @property getter & setter

- (BOOL)seekEnable{
    return self.decoder.seekEnable;
}

- (void)setState:(KKPlayerState)state{
    [self.stateLock lock];
    if (_state != state) {
        KKPlayerState temp = _state;
        _state = state;
        if (_state == KKPlayerStatePlaying) {
            [self.audioManager play];
        }else {
            [self.audioManager pause];
        }
        [KKPlayerEventCenter raiseEvent:self.playerInterface statePrevious:temp current:_state];
    }
    [self.stateLock unlock];
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

- (void)setProgress:(NSTimeInterval)progress{
    if (_progress != progress) {
        _progress = progress;
        NSTimeInterval duration = self.duration;
        double percent = [self percentForTime:_progress duration:duration];
        if (_progress <= 0.000001 || _progress == duration) {
            [KKPlayerEventCenter raiseEvent:self.playerInterface progressPercent:percent current:_progress total:duration];
        } else {
            NSTimeInterval currentTime = [NSDate date].timeIntervalSince1970;
            if (currentTime - self.lastPostProgressTime >= 1) {
                self.lastPostProgressTime = currentTime;
                [KKPlayerEventCenter raiseEvent:self.playerInterface progressPercent:percent current:_progress total:duration];
            }
        }
    }
}

- (void)setPlayableTime:(NSTimeInterval)playableTime{
    NSTimeInterval duration = self.duration;
    if (playableTime > duration) {
        playableTime = duration;
    } else if (playableTime < 0) {
        playableTime = 0;
    }
    
    if (_playableTime != playableTime) {
        _playableTime = playableTime;
        double percent = [self percentForTime:_playableTime duration:duration];
        if (_playableTime == 0 || _playableTime == duration) {
            [KKPlayerEventCenter raiseEvent:self.playerInterface playablePercent:percent current:_playableTime total:duration];
        } else {
            NSTimeInterval currentTime = [NSDate date].timeIntervalSince1970;
            if (currentTime - self.lastPostPlayableTime >= 1) {
                self.lastPostPlayableTime = currentTime;
                [KKPlayerEventCenter raiseEvent:self.playerInterface playablePercent:percent current:_playableTime total:duration];
            }
        }
    }
}

- (NSTimeInterval)duration{
    return self.decoder.duration;
}

- (CGSize)presentationSize{
    if (self.decoder.prepareToDecode) {
        return self.decoder.presentationSize;
    }
    return CGSizeZero;
}

- (NSTimeInterval)bitrate{
    if (self.decoder.prepareToDecode) {
        return self.decoder.bitrate;
    }
    return 0;
}

- (BOOL)videoDecodeOnMainThread{
    return self.decoder.videoDecodeOnMainThread;
}

#pragma mark -- 音视频轨道信息

- (BOOL)videoEnable{
    return self.decoder.videoEnable;
}

- (BOOL)audioEnable{
    return self.decoder.audioEnable;
}

- (KKPlayerTrack *)videoTrack{
    return [self playerTrackFromFFTrack:self.decoder.videoTrack];
}

- (KKPlayerTrack *)audioTrack{
    return [self playerTrackFromFFTrack:self.decoder.audioTrack];
}

- (NSArray <KKPlayerTrack *> *)videoTracks{
    return [self playerTracksFromFFTracks:self.decoder.videoTracks];
}

- (NSArray <KKPlayerTrack *> *)audioTracks{
    return [self playerTracksFromFFTracks:self.decoder.audioTracks];;
}

- (KKPlayerTrack *)playerTrackFromFFTrack:(KKFFTrack *)track{
    if (track) {
        KKPlayerTrack * obj = [[KKPlayerTrack alloc] init];
        obj.index = track.index;
        obj.name = track.metadata.language;
        return obj;
    }
    return nil;
}

- (NSArray <KKPlayerTrack *> *)playerTracksFromFFTracks:(NSArray <KKFFTrack *> *)tracks{
    NSMutableArray <KKPlayerTrack *> * array = [NSMutableArray array];
    for (KKFFTrack * obj in tracks) {
        KKPlayerTrack * track = [self playerTrackFromFFTrack:obj];
        [array addObject:track];
    }
    if (array.count > 0) {
        return array;
    }
    return nil;
}

#pragma mark -- ffmpeg配置

- (void)configFFmpegOptions{
    self.formatContextOptions = [NSMutableDictionary dictionary];
    self.codecContextOptions = [NSMutableDictionary dictionary];
    
    [self.formatContextOptions setObject:@"KKPlayer" forKey:@"user-agent"];
    [self.formatContextOptions setObject:@(20 * 1000 * 1000) forKey:@"timeout"];
    [self.formatContextOptions setObject:@(1) forKey:@"reconnect"];
}

@end
