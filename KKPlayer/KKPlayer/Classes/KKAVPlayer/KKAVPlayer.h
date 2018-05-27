//
//  KKAVPlayer.h
//  KKPlayer
//
//  Created by finger on 16/6/28.
//  Copyright © 2016年 single. All rights reserved.
//

#import "KKPlayerInterface.h"
#import <AVFoundation/AVFoundation.h>

@interface KKAVPlayer:NSObject
@property(nonatomic,weak,readonly)KKPlayerInterface *playerInterface;
@property(nonatomic,strong,readonly)AVPlayer *player;

@property(nonatomic,assign,readonly)KKPlayerState state;
@property(nonatomic,assign,readonly)CGSize presentationSize;
@property(nonatomic,assign,readonly)NSTimeInterval bitrate;
@property(nonatomic,assign,readonly)NSTimeInterval progress;
@property(nonatomic,assign,readonly)NSTimeInterval duration;
@property(nonatomic,assign,readonly)NSTimeInterval playableTime;

@property(nonatomic,assign)BOOL seeking;
@property(nonatomic,assign,readonly)BOOL seekEnable;

//音视频轨道信息
@property(nonatomic,assign,readonly)BOOL videoEnable;
@property(nonatomic,assign,readonly)BOOL audioEnable;
@property(nonatomic,strong,readonly)KKPlayerTrack *videoTrack;
@property(nonatomic,strong,readonly)KKPlayerTrack *audioTrack;
@property(nonatomic,strong,readonly)NSArray<KKPlayerTrack *> *videoTracks;
@property(nonatomic,strong,readonly)NSArray<KKPlayerTrack *> *audioTracks;

+ (instancetype)new NS_UNAVAILABLE;
+ (instancetype)init NS_UNAVAILABLE;
+ (instancetype)playerWithPlayerInterface:(KKPlayerInterface *)playerInterface;

#pragma mark -- 准备操作

/**
 prepareVideo
 @param forceRenderWithOpenGL -- NO ,使用AVPlayer渲染，YES , 使用opengl渲染
 */
- (void)prepareVideoForceRenderWithGL:(BOOL)forceRenderWithOpenGL;

#pragma mark -- 播放控制

- (void)play;
- (void)pause;
- (void)stop;
- (void)seekToTime:(NSTimeInterval)time;
- (void)seekToTime:(NSTimeInterval)time completeHandler:(void(^)(BOOL finished))completeHandler;
- (void)reloadVolume;

@end
