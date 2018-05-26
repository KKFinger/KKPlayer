//
//  KKRenderView.m
//  KKPlayer
//
//  Created by KKFinger on 12/01/2017.
//  Copyright © 2017 KKFinger. All rights reserved.
//

#import "KKRenderView.h"
#import "KKGLViewController.h"
#import "KKGLFrame.h"
#import "KKFingerRotation.h"

@interface KKRenderView ()
@property(nonatomic,weak)KKPlayerInterface *playerInterface;
@property(nonatomic,strong)KKFingerRotation *fingerRotation;
@property(nonatomic,strong)AVPlayerLayer *avPlayerLayer;//使用AVPlayer播放时渲染图层
@property(nonatomic,strong)KKGLViewController *glViewController;//使用ffmpeg、videoToolbox解码时的渲染图层
@end

@implementation KKRenderView

+ (instancetype)renderViewWithPlayerInterface:(KKPlayerInterface *)playerInterface{
    return [[self alloc] initWithPlayerInterface:playerInterface];
}

- (instancetype)initWithPlayerInterface:(KKPlayerInterface *)playerInterface{
    if (self = [super initWithFrame:CGRectZero]) {
        self.playerInterface = playerInterface;
        self.fingerRotation = [KKFingerRotation fingerRotation];
        self.backgroundColor = [UIColor blackColor];
        [self setupEventHandler];
    }
    return self;
}

-(void)dealloc{
    [self cleanView];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    KKPlayerLog(@"KKDisplayView release");
}

- (void)layoutSublayersOfLayer:(CALayer *)layer{
    [super layoutSublayersOfLayer:layer];
    [self updateDisplayViewLayout:layer.bounds];
}

#pragma mark -- 渲染方式,选择对应的渲染图层

- (void)setRenderViewType:(KKRenderViewType)renderViewType{
    if(_renderViewType != renderViewType){
        _renderViewType = renderViewType ;
        [self setupRenderView];
    }
}

#pragma mark -- 初始化渲染图层

- (void)setupRenderView{
    [self cleanView];
    switch (self.renderViewType) {
        case KKRenderViewTypeEmpty:
            break;
        case KKRenderViewTypeAVPlayerLayer:{
            [self.avPlayerLayer removeFromSuperlayer];
            self.avPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:nil];
            [self.layer insertSublayer:self.avPlayerLayer atIndex:0];
            [self resetAVPlayer];
            [self resetAVPlayerVideoGravity];
        }
            break;
        case KKRenderViewTypeGLKView:{
            dispatch_async(dispatch_get_main_queue(), ^{
                self.glViewController = [KKGLViewController viewControllerWithRenderView:self];
                GLKView *glView = [self.glViewController glkView];
                [glView removeFromSuperview];
                [self insertSubview:glView atIndex:0];
            });
        }
            break;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateDisplayViewLayout:self.bounds];
    });
}

- (void)resetAVPlayerVideoGravity{
    if (self.avPlayerLayer) {
        switch (self.playerInterface.viewGravityMode) {
            case KKGravityModeResize:
                self.avPlayerLayer.videoGravity = AVLayerVideoGravityResize;
                break;
            case KKGravityModeResizeAspect:
                self.avPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
                break;
            case KKGravityModeResizeAspectFill:
                self.avPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
                break;
        }
    }
}

- (void)resetAVPlayer{
    if (self.avPlayerLayer && self.decodeType == KKDecoderTypeAVPlayer) {
        if (self.renderAVPlayerDelegate && [self.renderAVPlayerDelegate respondsToSelector:@selector(renderGetAVPlayer)] && [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
            self.avPlayerLayer.player = [self.renderAVPlayerDelegate renderGetAVPlayer];
        } else {
            self.avPlayerLayer.player = nil;
        }
    }
}

- (void)updateDisplayViewLayout:(CGRect)frame{
    if (self.avPlayerLayer) {
        [self.avPlayerLayer setFrame:frame];
        [self.avPlayerLayer removeAllAnimations];
    }
    if (self.glViewController) {
        [self.glViewController reloadViewport:frame];
    }
}

#pragma mark -- 加载解码数据

- (void)fetchVideoFrameForGLFrame:(KKGLFrame *)glFrame{
    switch (self.decodeType) {
        case KKDecoderTypeEmpty:
        case KKDecoderTypeError:
            break;
        case KKDecoderTypeAVPlayer:{//使用avplayer播放vr视频时，视频的渲染方式为opengl
            CVPixelBufferRef pixelBuffer = [self.renderAVPlayerDelegate renderGetPixelBufferAtCurrentTime];//从avplayer获取渲染的视频数据
            if (pixelBuffer) {
                [glFrame updateWithCVPixelBuffer:pixelBuffer];
            }
        }
            break;
        case KKDecoderTypeFFmpeg:{
            //从ffmpeg获取解码的数据
            KKFFVideoFrame *videoFrame = [self.renderFFmpegDelegate renderFrameWithCurrentPostion:glFrame.currentPosition
                                                                                 currentDuration:glFrame.currentDuration];
            if (videoFrame) {
                [glFrame updateWithFFVideoFrame:videoFrame];
            }
        }
            break;
    }
}

#pragma mark -- 截屏

- (UIImage *)snapshot{
    switch (self.renderViewType) {
        case KKRenderViewTypeEmpty:
            return nil;
        case KKRenderViewTypeAVPlayerLayer:
            return [self.renderAVPlayerDelegate renderGetSnapshotAtCurrentTime];
        case KKRenderViewTypeGLKView:
            return [self.glViewController snapshot];
    }
}

#pragma mark -- 清理

- (void)cleanView{
    if (self.avPlayerLayer) {
        [self.avPlayerLayer removeFromSuperlayer];
        self.avPlayerLayer.player = nil;
        self.avPlayerLayer = nil;
    }
    if (self.glViewController) {
        GLKView *glView = [self.glViewController glkView];
        [glView removeFromSuperview];
        self.glViewController = nil;
    }
    [self.fingerRotation clean];
}

#pragma mark -- 交互事件，播放VR视频时，用于实时切换预览角度

- (void)setupEventHandler{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackgroundNotify:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForegroundNotify:) name:UIApplicationWillEnterForegroundNotification object:nil];
    UITapGestureRecognizer * tapGestureRecigbuzer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureRecigbuzer:)];
    [self addGestureRecognizer:tapGestureRecigbuzer];
}

- (void)applicationDidEnterBackgroundNotify:(NSNotification *)notification{
    if (_avPlayerLayer) {
        _avPlayerLayer.player = nil;
    }
}

- (void)applicationWillEnterForegroundNotify:(NSNotification *)notification{
    if (_avPlayerLayer) {
        _avPlayerLayer.player = [self.renderAVPlayerDelegate renderGetAVPlayer];
    }
}

- (void)tapGestureRecigbuzer:(UITapGestureRecognizer *)tapGestureRecognizer{
    if (self.playerInterface.viewTapAction) {
        self.playerInterface.viewTapAction(self.playerInterface,self);
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    if(self.playerInterface.videoType != KKVideoTypeVR){
        return ;
    }
    switch (self.renderViewType) {
        case KKRenderViewTypeEmpty:
        case KKRenderViewTypeAVPlayerLayer:
            return;
        default:{
            UITouch * touch = [touches anyObject];
            float distanceX = [touch locationInView:touch.view].x - [touch previousLocationInView:touch.view].x;
            float distanceY = [touch locationInView:touch.view].y - [touch previousLocationInView:touch.view].y;
            distanceX *= 0.005;
            distanceY *= 0.005;
            self.fingerRotation.x += distanceY *  [KKFingerRotation degress] / 100;
            self.fingerRotation.y -= distanceX *  [KKFingerRotation degress] / 100;
        }
            break;
    }
}

@end
