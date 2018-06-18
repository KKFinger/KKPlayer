//
//  KKFFVideoToolBox.h
//  KKPlayer
//
//  Created by finger on 2017/2/21.
//  Copyright © 2017年 finger. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "avformat.h"

@interface KKFFVideoToolBox:NSObject

+ (instancetype)videoToolBoxWithCodecContext:(AVCodecContext *)codecContext;

#pragma mark -- 初始化

- (BOOL)trySetupVTSession;

#pragma mark -- 将原始的音视频数据加入到数据队列

- (BOOL)sendPacket:(AVPacket)packet ;

#pragma mark -- 解码后的数据

- (CVImageBufferRef)imageBuffer;

#pragma mark -- 清理

- (void)clean;

@end
