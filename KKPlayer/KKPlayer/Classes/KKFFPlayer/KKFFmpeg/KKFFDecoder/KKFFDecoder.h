//
//  KKFFDecoder.h
//  KKPlayer
//
//  Created by finger on 05/01/2017.
//  Copyright © 2017 single. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "KKFFAudioFrame.h"
#import "KKFFVideoFrame.h"
#import "KKFFTrack.h"

@class KKFFDecoder;

@protocol KKFFDecoderDelegate <NSObject>
@optional
- (void)decoderWillOpenInputStream:(KKFFDecoder *)decoder;
- (void)decoderDidPrepareToDecodeFrames:(KKFFDecoder *)decoder;
- (void)decoderDidEndOfFile:(KKFFDecoder *)decoder;
- (void)decoderDidFinished:(KKFFDecoder *)decoder;
- (void)decoder:(KKFFDecoder *)decoder didError:(NSError *)error;
- (void)decoder:(KKFFDecoder *)decoder didChangeValueOfBuffering:(BOOL)buffering;
- (void)decoder:(KKFFDecoder *)decoder didChangeValueOfBufferedDuration:(NSTimeInterval)bufferedDuration;
- (void)decoder:(KKFFDecoder *)decoder didChangeValueOfProgress:(NSTimeInterval)progress;
@end

@protocol KKFFDecoderAudioConfigDelegate <NSObject>
- (Float64)decoderAudioConfigGetSamplingRate;
- (UInt32)decoderAudioConfigGetNumberOfChannels;
@end

@protocol KKFFDecoderVideoConfigDelegate <NSObject>
- (BOOL)decoderVideoConfigAVCodecContextDecodeAsync;
@end

@interface KKFFDecoder:NSObject
@property(nonatomic,strong,readonly)NSError *error;
@property(nonatomic,copy,readonly)NSURL *contentURL;
@property(nonatomic,assign,readonly)CGSize presentationSize;
@property(nonatomic,assign,readonly)CGFloat aspect;
@property(nonatomic,assign,readonly)NSTimeInterval bitrate;
@property(nonatomic,assign,readonly)NSTimeInterval progress;//播放进度
@property(nonatomic,assign,readonly)NSTimeInterval duration;//总时长
@property(nonatomic,assign,readonly)NSTimeInterval bufferedDuration;//已缓冲好的时时长
@property(nonatomic,assign)NSTimeInterval minBufferedDruation;//最小的缓冲时间

@property(nonatomic,assign,readonly)BOOL buffering;
@property(nonatomic,assign,readonly)BOOL seekEnable;
@property(nonatomic,assign,readonly)BOOL prepareToDecode;
@property(nonatomic,assign,readonly)BOOL videoDecodeOnMainThread;

@property(nonatomic,assign,readonly)BOOL videoEnable;
@property(nonatomic,assign,readonly)BOOL audioEnable;

@property(nonatomic,copy,readonly)NSDictionary *metadata;

#pragma mark -- 轨道信息

@property(nonatomic,strong,readonly)KKFFTrack *videoTrack;
@property(nonatomic,strong,readonly)KKFFTrack *audioTrack;
@property(nonatomic,strong,readonly)NSArray<KKFFTrack *> *videoTracks;
@property(nonatomic,strong,readonly)NSArray<KKFFTrack *> *audioTracks;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)decoderWithContentURL:(NSURL *)contentURL
                 formatContextOptions:(NSDictionary *)formatContextOptions
                  codecContextOptions:(NSDictionary *)codecContextOptions
                             delegate:(id<KKFFDecoderDelegate>)delegate
           videoDecoderConfigDelegate:(id<KKFFDecoderVideoConfigDelegate>)videoDecoderConfigDelegate
           audioDecoderConfigDelegate:(id<KKFFDecoderAudioConfigDelegate>)audioDecoderConfigDelegate;


#pragma mark -- 解码控制

- (void)pause;
- (void)resume;
- (void)seekToTime:(NSTimeInterval)time;
- (void)seekToTime:(NSTimeInterval)time completeHandler:(void (^)(BOOL finished))completeHandler;

#pragma mark -- 开始/结束解码

- (void)startDecoder;
- (void)stopDecoder;

#pragma mark -- 获取解码的视频帧

- (KKFFVideoFrame *)fetchVideoFrameWithCurrentPostion:(NSTimeInterval)currentPostion
                                      currentDuration:(NSTimeInterval)currentDuration;

#pragma mark -- 获取解码的音频帧

- (KKFFAudioFrame *)fetchAudioFrame;

@end
