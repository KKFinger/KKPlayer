//
//  KKFFFrameQueue.h
//  KKPlayer
//
//  Created by finger on 18/01/2017.
//  Copyright © 2017 finger. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KKFFFrame.h"

@interface KKFFFrameQueue : NSObject
@property(nonatomic,assign,readonly)NSInteger decodedSize;//解码后的音视频帧数据大小
@property(nonatomic,assign,readonly)NSInteger packetSize;//原始音视频packet的数据大小
@property(nonatomic,assign,readonly)NSUInteger count;//解码后的音视频帧数量
@property(atomic,assign,readonly)NSTimeInterval duration;//解码后可用于播放的总时长
@property(nonatomic,assign)NSUInteger minFrameCountThreshold;//队列中帧个数的最小阈值，小于这个阈值不能获取帧
@property(nonatomic,assign)BOOL ignoreMinFrameCountThresholdLimit;//忽略阈值的限制
+ (instancetype)frameQueue;
- (void)putFrame:(__kindof KKFFFrame *)frame;
- (void)putSortFrame:(__kindof KKFFFrame *)frame;
- (__kindof KKFFFrame *)headFrameWithBlocking;//如果队列中没有frame则等待
- (__kindof KKFFFrame *)headFrameWithNoBlocking;//如果队列中没有frame则直接返回
- (__kindof KKFFFrame *)frameWithNoBlockingAtPosistion:(NSTimeInterval)position discardFrames:(NSMutableArray <__kindof KKFFFrame *> **)discardFrames;
- (NSMutableArray <__kindof KKFFFrame *> *)discardFrameBeforePosition:(NSTimeInterval)position;
- (NSTimeInterval)headFramePositionWithNoBlocking;
- (void)clean;
- (void)destroy;
@end
