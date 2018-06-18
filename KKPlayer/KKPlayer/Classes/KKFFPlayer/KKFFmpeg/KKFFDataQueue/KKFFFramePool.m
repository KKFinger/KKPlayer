//
//  KKFFFramePool.m
//  KKPlayer
//
//  Created by finger on 2017/3/3.
//  Copyright © 2017年 finger. All rights reserved.
//

#import "KKFFFramePool.h"

@interface KKFFFramePool ()<KKFFFrameDelegate>
@property(nonatomic,copy)Class frameClass;
@property(nonatomic,strong)NSLock *lock;
@property(nonatomic,strong)KKFFFrame *playingFrame;
@property(nonatomic,strong)NSMutableSet<KKFFFrame *> *unuseFrames;
@property(nonatomic,strong)NSMutableSet<KKFFFrame *> *usedFrames;
@end

@implementation KKFFFramePool

+ (instancetype)videoPool{
    return [self poolWithCapacity:60 frameClass:NSClassFromString(@"KKFFAVYUVVideoFrame")];
}

+ (instancetype)audioPool{
    return [self poolWithCapacity:500 frameClass:NSClassFromString(@"KKFFAudioFrame")];
}

+ (instancetype)poolWithCapacity:(NSUInteger)number frameClass:(Class)frameClass{
    return [[self alloc] initWithCapacity:number frameClass:frameClass];
}

- (instancetype)initWithCapacity:(NSUInteger)number frameClass:(Class)frameClass{
    if (self = [super init]) {
        self.frameClass = frameClass;
        self.lock = [[NSLock alloc] init];
        self.unuseFrames = [NSMutableSet setWithCapacity:number];
        self.usedFrames = [NSMutableSet setWithCapacity:number];
    }
    return self;
}

- (void)dealloc{
    [self destory];
    KKPlayerLog(@"KKFFFramePool release");
}

- (NSUInteger)count{
    return [self unuseCount] + [self usedCount] + (self.playingFrame ? 1 : 0);
}

- (NSUInteger)unuseCount{
    return self.unuseFrames.count;
}

- (NSUInteger)usedCount{
    return self.usedFrames.count;
}

- (__kindof KKFFFrame *)getUnuseFrame{
    [self.lock lock];
    KKFFFrame *frame;
    if (self.unuseFrames.count > 0) {
        frame = [self.unuseFrames anyObject];
        [self.unuseFrames removeObject:frame];
        [self.usedFrames addObject:frame];
    } else {
        frame = [[self.frameClass alloc] init];
        frame.delegate = self;
        [self.usedFrames addObject:frame];
    }
    [self.lock unlock];
    return frame;
}

- (void)setFrameUnuse:(KKFFFrame *)frame{
    if (!frame) return;
    if (![frame isKindOfClass:self.frameClass]) return;
    [self.lock lock];
    [self.unuseFrames addObject:frame];
    [self.usedFrames removeObject:frame];
    [self.lock unlock];
}

- (void)setFramesUnuse:(NSArray<KKFFFrame *> *)frames{
    if (frames.count <= 0) return;
    [self.lock lock];
    for (KKFFFrame *obj in frames) {
        if (![obj isKindOfClass:self.frameClass]) continue;
        [self.usedFrames removeObject:obj];
        [self.unuseFrames addObject:obj];
    }
    [self.lock unlock];
}

- (void)setFrameStartDrawing:(KKFFFrame *)frame{
    if (!frame) return;
    if (![frame isKindOfClass:self.frameClass]) return;
    [self.lock lock];
    if (self.playingFrame) {
        [self.unuseFrames removeObject:self.playingFrame];
        [self.usedFrames addObject:self.playingFrame];
    }
    self.playingFrame = frame;
    [self.lock unlock];
}

- (void)setFrameStopDrawing:(KKFFFrame *)frame{
    if (!frame) return;
    if (![frame isKindOfClass:self.frameClass]) return;
    [self.lock lock];
    if (self.playingFrame == frame) {
        [self.unuseFrames addObject:self.playingFrame];
        [self.usedFrames removeObject:self.playingFrame];
        self.playingFrame = nil;
    }
    [self.lock unlock];
}

- (void)clean{
    [self.lock lock];
    
    @weakify(self);
    [self.usedFrames enumerateObjectsUsingBlock:^(KKFFFrame * _Nonnull obj, BOOL * _Nonnull stop) {
        @strongify(self);
        [self.unuseFrames addObject:obj];
    }];
    [self.usedFrames removeAllObjects];
    
    [self.lock unlock];
}

- (void)destory{
    [self.lock lock];
    [self.usedFrames removeAllObjects];
    [self.unuseFrames removeAllObjects];
    [self.lock unlock];
}

#pragma mark -- KKFFFrameDelegate

- (void)frameDidStartPlaying:(KKFFFrame *)frame{
    [self setFrameStartDrawing:frame];
}

- (void)frameDidStopPlaying:(KKFFFrame *)frame{
    [self setFrameStopDrawing:frame];
}

- (void)frameDidCancel:(KKFFFrame *)frame{
    [self setFrameUnuse:frame];
}

@end
