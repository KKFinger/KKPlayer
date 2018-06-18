//
//  KKFFFrameQueue.m
//  KKPlayer
//
//  Created by finger on 18/01/2017.
//  Copyright © 2017 finger. All rights reserved.
//

#import "KKFFFrameQueue.h"

@interface KKFFFrameQueue ()
@property(nonatomic,assign)NSInteger decodedSize;
@property(nonatomic,assign)NSInteger packetSize;
@property(nonatomic,assign)NSUInteger count;
@property(atomic,assign)NSTimeInterval duration;
@property(nonatomic,strong)NSCondition *condition;
@property(nonatomic,strong)NSMutableArray<__kindof KKFFFrame *> *frames;
@property(nonatomic,assign)BOOL destoryToken;
@end

@implementation KKFFFrameQueue

+ (instancetype)frameQueue{
    return [[self alloc] init];
}

- (instancetype)init{
    if (self = [super init]) {
        self.frames = [NSMutableArray array];
        self.condition = [[NSCondition alloc] init];
        self.minFrameCountThreshold = 1;
        self.ignoreMinFrameCountThresholdLimit = NO;
    }
    return self;
}

- (void)dealloc{
    [self destroy];
    NSLog(@"%@ dealloc-----",NSStringFromClass([self class]));
}

- (void)putFrame:(__kindof KKFFFrame *)frame{
    if (!frame) return;
    [self.condition lock];
    if (self.destoryToken) {
        [self.condition unlock];
        return;
    }
    [self.frames addObject:frame];
    self.duration += frame.duration;
    self.decodedSize += frame.decodedSize;
    self.packetSize += frame.packetSize;
    [self.condition signal];
    [self.condition unlock];
}

- (void)putSortFrame:(__kindof KKFFFrame *)frame{
    if (!frame) return;
    [self.condition lock];
    if (self.destoryToken) {
        [self.condition unlock];
        return;
    }
    BOOL added = NO;
    for (NSInteger i = self.frames.count - 1; i >= 0; i--) {
        KKFFFrame *obj = [self.frames objectAtIndex:i];
        if (frame.position > obj.position) {
            [self.frames insertObject:frame atIndex:i + 1];
            added = YES;
            break;
        }
    }
    if (!added) {
        [self.frames addObject:frame];
        added = YES;
    }
    self.duration += frame.duration;
    self.decodedSize += frame.decodedSize;
    self.packetSize += frame.packetSize;
    [self.condition signal];
    [self.condition unlock];
}

//如果队列中没有frame则等待
- (__kindof KKFFFrame *)headFrameWithBlocking{
    [self.condition lock];
    while (self.frames.count < self.minFrameCountThreshold/*队列中的帧个数小于阈值*/ &&
           !(self.ignoreMinFrameCountThresholdLimit && self.frames.firstObject)/*队列不为空*/) {
        if (self.destoryToken) {
            [self.condition unlock];
            return nil;
        }
        [self.condition wait];
    }
    
    if (self.destoryToken) {
        [self.condition unlock];
        return nil;
    }
    
    KKFFFrame *frame = self.frames.firstObject;
    [self.frames removeObjectAtIndex:0];
    
    self.duration -= frame.duration;
    if (self.duration < 0 || self.count <= 0) {
        self.duration = 0;
    }
    
    self.decodedSize -= frame.decodedSize;
    if (self.decodedSize <= 0 || self.count <= 0) {
        self.decodedSize = 0;
    }
    
    self.packetSize -= frame.packetSize;
    if (self.packetSize <= 0 || self.count <= 0) {
        self.packetSize = 0;
    }
    
    [self.condition unlock];
    
    return frame;
}

//如果队列中没有frame则直接返回
- (__kindof KKFFFrame *)headFrameWithNoBlocking{
    [self.condition lock];
    if (self.destoryToken || self.frames.count <= 0) {
        [self.condition unlock];
        return nil;
    }
    //队列中的帧个数小于阈值
    if (!self.ignoreMinFrameCountThresholdLimit && self.frames.count < self.minFrameCountThreshold) {
        [self.condition unlock];
        return nil;
    }
    
    KKFFFrame *frame = self.frames.firstObject;
    [self.frames removeObjectAtIndex:0];
    
    self.duration -= frame.duration;
    if (self.duration < 0 || self.count <= 0) {
        self.duration = 0;
    }
    self.decodedSize -= frame.decodedSize;
    if (self.decodedSize <= 0 || self.count <= 0) {
        self.decodedSize = 0;
    }
    self.packetSize -= frame.packetSize;
    if (self.packetSize <= 0 || self.count <= 0) {
        self.packetSize = 0;
    }
    
    [self.condition unlock];
    
    return frame;
}

- (NSTimeInterval)headFramePositionWithNoBlocking{
    [self.condition lock];
    if (self.destoryToken || self.frames.count <= 0) {
        [self.condition unlock];
        return -1;
    }
    //队列中的帧个数小于阈值
    if (!self.ignoreMinFrameCountThresholdLimit && self.frames.count < self.minFrameCountThreshold) {
        [self.condition unlock];
        return -1;
    }
    NSTimeInterval time = self.frames.firstObject.position;
    [self.condition unlock];
    
    return time;
}

- (__kindof KKFFFrame *)frameWithNoBlockingAtPosistion:(NSTimeInterval)position discardFrames:(NSMutableArray <__kindof KKFFFrame *> **)discardFrames{
    [self.condition lock];
    if (self.destoryToken || self.frames.count <= 0) {
        [self.condition unlock];
        return nil;
    }
    //队列中的帧个数小于阈值
    if (!self.ignoreMinFrameCountThresholdLimit && self.frames.count < self.minFrameCountThreshold) {
        [self.condition unlock];
        return nil;
    }
    KKFFFrame *frame = nil;
    NSMutableArray *temp = [NSMutableArray array];
    for (KKFFFrame *obj in self.frames) {
        if (obj.position + obj.duration < position) {
            [temp addObject:obj];
            self.duration -= obj.duration;
            self.decodedSize -= obj.decodedSize;
            self.packetSize -= obj.packetSize;
        } else {
            break;
        }
    }
    if (temp.count > 0) {
        frame = temp.lastObject;
        [self.frames removeObjectsInArray:temp];
        [temp removeObject:frame];
        if (temp.count > 0) {
            *discardFrames = temp;
        }
    } else {
        frame = self.frames.firstObject;
        [self.frames removeObject:frame];
        self.duration -= frame.duration;
        self.decodedSize -= frame.decodedSize;
        self.packetSize -= frame.packetSize;
    }
    if (self.duration < 0 || self.count <= 0) {
        self.duration = 0;
    }
    if (self.decodedSize <= 0 || self.count <= 0) {
        self.decodedSize = 0;
    }
    if (self.packetSize <= 0 || self.count <= 0) {
        self.packetSize = 0;
    }
    [self.condition unlock];
    
    return frame;
}

- (NSMutableArray <__kindof KKFFFrame *> *)discardFrameBeforPosition:(NSTimeInterval)position{
    [self.condition lock];
    if (self.destoryToken || self.frames.count <= 0) {
        [self.condition unlock];
        return nil;
    }
    if (!self.ignoreMinFrameCountThresholdLimit && self.frames.count < self.minFrameCountThreshold) {
        [self.condition unlock];
        return nil;
    }
    
    NSMutableArray *temp = [NSMutableArray array];
    for (KKFFFrame *obj in self.frames) {
        if (obj.position + obj.duration < position) {
            [temp addObject:obj];
            self.duration -= obj.duration;
            self.decodedSize -= obj.decodedSize;
            self.packetSize -= obj.packetSize;
        } else {
            break;
        }
    }
    if (temp.count > 0) {
        [self.frames removeObjectsInArray:temp];
    }
    
    if (self.duration < 0 || self.count <= 0) {
        self.duration = 0;
    }
    if (self.decodedSize <= 0 || self.count <= 0) {
        self.decodedSize = 0;
    }
    if (self.packetSize <= 0 || self.count <= 0) {
        self.packetSize = 0;
    }
    
    [self.condition unlock];
    
    if (temp.count > 0) {
        return temp;
    } else {
        return nil;
    }
}

- (NSUInteger)count{
    return self.frames.count;
}

- (void)clean{
    [self.condition lock];
    [self.frames removeAllObjects];
    self.duration = 0;
    self.decodedSize = 0;
    self.packetSize = 0;
    self.ignoreMinFrameCountThresholdLimit = NO;
    [self.condition unlock];
}

- (void)destroy{
    [self clean];
    [self.condition lock];
    self.destoryToken = YES;
    [self.condition broadcast];
    [self.condition unlock];
}

@end
