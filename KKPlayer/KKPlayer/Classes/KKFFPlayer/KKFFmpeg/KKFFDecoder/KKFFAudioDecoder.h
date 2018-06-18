//
//  KKFFAudioDecoder.h
//  KKPlayer
//
//  Created by finger on 2017/2/17.
//  Copyright © 2017年 single. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KKFFAudioFrame.h"
#import "avformat.h"

@interface KKFFAudioDecoder:NSObject
@property(nonatomic,assign,readonly)NSInteger packetSize;
@property(nonatomic,assign,readonly)BOOL frameQueueEmpty;
@property(nonatomic,assign,readonly)NSTimeInterval duration;

+ (instancetype)decoderWithCodecContext:(AVCodecContext *)codecContext timebase:(NSTimeInterval)timebase sampleRate:(Float64)samplingRate channelCount:(UInt32)channelCount;

#pragma mark -- 获取解码后的音频数据

- (KKFFAudioFrame *)frameWithBlocking;

#pragma mark -- 将原始的音频帧数据加到队列中

- (NSInteger)putPacket:(AVPacket)packet;

#pragma mark -- 清理

- (void)clean;
- (void)destroy;

@end
