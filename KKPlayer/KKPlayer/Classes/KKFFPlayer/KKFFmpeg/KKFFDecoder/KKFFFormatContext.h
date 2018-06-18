//
//  KKFFFormatContext.h
//  KKPlayer
//
//  Created by finger on 2017/2/17.
//  Copyright © 2017年 finger. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "KKFFVideoFrame.h"
#import "KKFFTrack.h"

@class KKFFFormatContext;

@protocol KKFFFormatContextDelegate<NSObject>
- (BOOL)formatContextNeedInterrupt:(KKFFFormatContext *)formatContext;
@end

@interface KKFFFormatContext:NSObject{
@public
    AVFormatContext *formatContext;
    AVCodecContext *videoCodecContext;
    AVCodecContext *audioCodecContext;
}

@property(nonatomic,weak)id<KKFFFormatContextDelegate>delegate;
@property(nonatomic,copy,readonly)NSError *error;
@property(nonatomic,copy,readonly)NSDictionary * metadata;
@property(nonatomic,assign,readonly)NSTimeInterval bitrate;
@property(nonatomic,assign,readonly)NSTimeInterval duration;
@property(nonatomic,assign,readonly)NSTimeInterval videoTimebase;
@property(nonatomic,assign,readonly)NSTimeInterval videoFPS;
@property(nonatomic,copy,readonly)NSString *videoFormat;
@property(nonatomic,assign,readonly)CGSize videoPresentationSize;
@property(nonatomic,assign,readonly)CGFloat videoAspect;
@property(nonatomic,assign,readonly)KKFFVideoFrameRotateType videoFrameRotateType;
@property(nonatomic,assign,readonly)NSTimeInterval audioTimebase;

@property(nonatomic,assign,readonly)BOOL videoEnable;
@property(nonatomic,assign,readonly)BOOL audioEnable;

@property(nonatomic,strong,readonly)KKFFTrack *videoTrack;
@property(nonatomic,strong,readonly)KKFFTrack *audioTrack;
@property(nonatomic,strong,readonly)NSArray<KKFFTrack *> *videoTracks;
@property(nonatomic,strong,readonly)NSArray<KKFFTrack *> *audioTracks;

+ (instancetype)formatContextWithContentURL:(NSURL *)contentURL
                       formatContextOptions:(NSDictionary *)formatContextOptions
                        codecContextOptions:(NSDictionary *)codecContextOptions
                                   delegate:(id<KKFFFormatContextDelegate>)delegate;

- (void)openFileStream;
- (void)destroy;

- (BOOL)seekEnable;
- (void)seekFileWithSecond:(NSTimeInterval)second;

- (int)readFrame:(AVPacket *)packet;

@end
