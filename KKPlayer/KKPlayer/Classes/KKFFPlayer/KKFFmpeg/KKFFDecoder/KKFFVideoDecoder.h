//
//  KKFFVideoDecoder.h
//  KKPlayer
//
//  Created by finger on 2017/2/17.
//  Copyright © 2017年 finger. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KKFFVideoFrame.h"
#import "avformat.h"

@class KKFFVideoDecoder;

@protocol KKFFVideoDecoderDlegate <NSObject>
- (void)videoDecoder:(KKFFVideoDecoder *)videoDecoder didError:(NSError *)error;
@end

@interface KKFFVideoDecoder : NSObject

@property(nonatomic,weak)id<KKFFVideoDecoderDlegate>delegate;

@property(nonatomic,strong,readonly)NSError *error;
@property(nonatomic,assign,readonly)KKFFVideoFrameRotateType rotateType;
@property(nonatomic,assign,readonly)NSInteger packetSize;
@property(nonatomic,assign,readonly)NSTimeInterval duration;
@property(nonatomic,assign,readonly)BOOL frameQueueEmpty;
@property(nonatomic,assign,readonly)BOOL decodeOnMainThread;
@property(nonatomic,assign)BOOL paused;
@property(nonatomic,assign)BOOL readPacketFinish;

+ (instancetype)decoderWithCodecContext:(AVCodecContext *)codecContext
                               timebase:(NSTimeInterval)timebase
                                    fps:(NSTimeInterval)fps
                      ffmpegDecodeAsync:(BOOL)ffmpegDecodeAsync
                     enableVideoToolbox:(BOOL)enableVideoToolbox
                             rotateType:(KKFFVideoFrameRotateType)rotateType
                               delegate:(id <KKFFVideoDecoderDlegate>)delegate;

#pragma mark -- 获取音视频帧

- (KKFFVideoFrame *)headFrame;
- (KKFFVideoFrame *)frameAtPosition:(NSTimeInterval)position;

#pragma mark -- 丢弃帧

- (void)discardFrameBeforPosition:(NSTimeInterval)position;

#pragma mark -- 添加音视频原始帧数据到队列中

- (void)putPacket:(AVPacket)packet;

#pragma mark -- 销毁

- (void)clean;
- (void)destroy;

#pragma mark -- 解码线程

- (void)startDecodeThread;

@end
