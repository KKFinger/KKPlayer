//
//  KKFFPacketQueue.h
//  KKPlayer
//
//  Created by finger on 18/01/2017.
//  Copyright © 2017 finger. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "avformat.h"

@interface KKFFPacketQueue:NSObject
@property(nonatomic,assign,readonly)NSUInteger count;//packet的数量
@property(nonatomic,assign,readonly)NSInteger size;//队列中全部packet的数据大小
@property(nonatomic,assign,readonly)NSTimeInterval duration;//队列中全部packet的时长
@property(nonatomic,assign,readonly)NSTimeInterval timebase;
+ (instancetype)packetQueueWithTimebase:(NSTimeInterval)timebase;
- (void)putPacket:(AVPacket)packet duration:(NSTimeInterval)duration;
- (AVPacket)getPacketWithBlocking;//如果队列中没有packet则等待
- (AVPacket)getPacketWithNoBlocking;//如果队列中没有packet则直接返回
- (void)clean;
- (void)destroy;
@end
