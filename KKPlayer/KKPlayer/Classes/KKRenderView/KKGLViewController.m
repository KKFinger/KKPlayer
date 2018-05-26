//
//  KKGLViewController.m
//  KKPlayer
//
//  Created by finger on 2017/3/27.
//  Copyright © 2017年 finger. All rights reserved.
//

#import "KKGLViewController.h"
#import "KKGLFrame.h"
#import "KKGLDrawTool.h"

@interface KKGLViewController ()
@property(nonatomic,weak)KKRenderView *renderView;
@property(nonatomic,strong)KKGLFrame *currentGLFrame;
@property(nonatomic,strong)KKGLDrawTool *drawTool;
@property(nonatomic,strong)NSLock *openGLLock;
@property(nonatomic,assign)BOOL drawToken;
@property(nonatomic,assign)CGFloat aspect;
@property(nonatomic,assign)CGRect viewport;
@end

@implementation KKGLViewController

+ (instancetype)viewControllerWithRenderView:(KKRenderView *)renderView{
    return [[self alloc] initWithRenderView:renderView];
}

- (instancetype)initWithRenderView:(KKRenderView *)renderView{
    if (self = [super init]) {
        self->_renderView = renderView;
    }
    return self;
}

- (void)viewDidLoad{
    [super viewDidLoad];
    [self setupOpenGL];
}

- (void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    [self.drawTool reloadVrBoxViewSize];
}

- (void)dealloc{
    [EAGLContext setCurrentContext:nil];
    KKPlayerLog(@"%@ release", self.class);
}

#pragma mark -- 初始化opengl

- (void)setupOpenGL{
    self.openGLLock = [[NSLock alloc] init];

    EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    [EAGLContext setCurrentContext:context];
    
    GLKView *glView = (GLKView *)self.view;
    glView.backgroundColor = [UIColor blackColor];
    glView.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    glView.contentScaleFactor = [UIScreen mainScreen].scale;
    glView.context = context;
    
    self.pauseOnWillResignActive = NO;
    self.resumeOnDidBecomeActive = YES;
    
    self.drawTool = [[KKGLDrawTool alloc]initWithVideoType:self.renderView.playerInterface.videoType dispayType:self.renderView.playerInterface.displayType glView:glView renderView:self.renderView context:context];
    
    self.currentGLFrame = [KKGLFrame frame];
    
    self.aspect = 16.0 / 9.0;
    
    KKVideoType videoType = self.renderView.playerInterface.videoType;
    switch (videoType) {
        case KKVideoTypeNormal:
            self.preferredFramesPerSecond = 35;
            break;
        case KKVideoTypeVR:
            self.preferredFramesPerSecond = 60;
            break;
    }
}

#pragma mark -- 重置绘制窗口

- (void)reloadViewport:(CGRect)frame{
    GLKView *glView = (GLKView *)self.view;
    CGRect superviewFrame = frame;
    CGFloat superviewAspect = superviewFrame.size.width / superviewFrame.size.height;
    
    if (self.aspect <= 0) {
        glView.frame = superviewFrame;
        return;
    }
    
    CGFloat resultAspect = self.aspect;
    switch (self.currentGLFrame.rotateType) {
        case KKFFVideoFrameRotateType90:
        case KKFFVideoFrameRotateType270:
            resultAspect = 1 / self.aspect;
            break;
        case KKFFVideoFrameRotateType0:
        case KKFFVideoFrameRotateType180:
            break;
    }
    
    KKGravityMode gravityMode = self.renderView.playerInterface.viewGravityMode;
    switch (gravityMode) {
        case KKGravityModeResize:
            glView.frame = superviewFrame;
            break;
        case KKGravityModeResizeAspect:
            if (superviewAspect < resultAspect) {
                CGFloat height = superviewFrame.size.width / resultAspect;
                glView.frame = CGRectMake(0, (superviewFrame.size.height - height) / 2, superviewFrame.size.width, height);
            } else if (superviewAspect > resultAspect) {
                CGFloat width = superviewFrame.size.height * resultAspect;
                glView.frame = CGRectMake((superviewFrame.size.width - width) / 2, 0, width, superviewFrame.size.height);
            } else {
                glView.frame = superviewFrame;
            }
            break;
        case KKGravityModeResizeAspectFill:
            if (superviewAspect < resultAspect) {
                CGFloat width = superviewFrame.size.height * resultAspect;
                glView.frame = CGRectMake(-(width - superviewFrame.size.width) / 2, 0, width, superviewFrame.size.height);
            } else if (superviewAspect > resultAspect) {
                CGFloat height = superviewFrame.size.width / resultAspect;
                glView.frame = CGRectMake(0, -(height - superviewFrame.size.height) / 2, superviewFrame.size.width, height);
            } else {
                glView.frame = superviewFrame;
            }
            break;
        default:
            glView.frame = superviewFrame;
            break;
    }
    self.drawToken = NO;
}

#pragma mark -- 设置绘制视图的宽高比例

- (void)setAspect:(CGFloat)aspect{
    if (_aspect != aspect) {
        _aspect = aspect;
        [self reloadViewport:self.glkView.superview.bounds];
    }
}

#pragma mark -- 截屏

- (UIImage *)snapshot{
    GLKView *glView = (GLKView *)self.view;
    if (self.renderView.playerInterface.videoType == KKVideoTypeVR) {
        return glView.snapshot;
    } else {
        UIImage *image = [self.currentGLFrame imageFromVideoFrame];
        if (image) {
            return image;
        }
    }
    return glView.snapshot;
}

#pragma mark -- 获取GLKView

- (GLKView *)glkView{
    return (GLKView *)self.view;
}

#pragma mark -- GLKViewDelegate

/*KKGLViewController初始化完成后便会不间断的调用GLKViewDelegate中的代理方法，因此，在GLKViewDelegate中
  需要完成以下工作:
  1、获取原始的视频帧数据
  2、根据视频帧数据生成opengl的纹理图
  3、将opengl的顶点坐标、纹理坐标、投影矩阵传入opengl的渲染管道并完成一幅视频帧的绘制
 */
- (void)glkView:(GLKView *)glView drawInRect:(CGRect)rect{
    
    [self.openGLLock lock];
    
    [EAGLContext setCurrentContext:glView.context];
    
    if ([self needDrawOpenGL]) {
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
            [self.openGLLock unlock];
            return;
        }
        [self setViewport:glView.bounds];
        [self.drawTool drawWithGLFrame:self.currentGLFrame viewPort:self.viewport];
        [self.currentGLFrame didDraw];
        [self setDrawToken:YES];
    }
    
    [self.openGLLock unlock];
}

- (BOOL)needDrawOpenGL{
    //获取音视频帧，数据来源为AVPlayer或者FFmpeg
    [self.renderView fetchVideoFrameForGLFrame:self.currentGLFrame];
    
    if (!self.currentGLFrame.hasUpate) {
        return NO;
    }
    if (self.renderView.playerInterface.videoType != KKVideoTypeVR &&
        !self.currentGLFrame.hasUpate &&
        self.drawToken) {
        return NO;
    }
    
    //更新纹理图
    CGFloat aspect = 16.0 / 9.0;
    if(![self.drawTool updateTextureWithGLFrame:self.currentGLFrame aspect:&aspect]){
        return NO;
    }
    
    if (self.renderView.playerInterface.videoType == KKVideoTypeVR) {
        self.aspect = 16.0 / 9.0;
    } else {
        self.aspect = aspect;
    }
    return YES;
}

@end
