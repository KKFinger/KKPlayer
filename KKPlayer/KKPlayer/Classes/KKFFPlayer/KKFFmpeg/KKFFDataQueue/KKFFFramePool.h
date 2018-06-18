//
//  KKFFFramePool.h
//  KKPlayer
//
//  Created by finger on 2017/3/3.
//  Copyright © 2017年 finger. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KKFFFrame.h"

@interface KKFFFramePool:NSObject
+ (instancetype)videoPool;
+ (instancetype)audioPool;
+ (instancetype)poolWithCapacity:(NSUInteger)number frameClass:(Class)frameClass;
- (NSUInteger)count;
- (NSUInteger)unuseCount;
- (NSUInteger)usedCount;
- (__kindof KKFFFrame *)getUnuseFrame;
- (void)clean;
- (void)destory;
@end
