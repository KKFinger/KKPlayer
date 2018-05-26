//
//  KKGLDrawTool.h
//  KKPlayer
//
//  Created by finger on 2018/2/7.
//  Copyright © 2018年 finger. All rights reserved.
//

/*
 1、GLProgram系列负责渲染管道的初始化以及加载编译顶点、片元着色器，并对着色器内的变量做一些初始化工作
 2、GLCoordBuffer系列主要用于将顶点坐标和纹理坐标传入渲染管道
 3、GLTexture系列主要用于将视频画面数据生成一图纹理图供opengl渲染
 */

/*
 关于VR视频的全景播放:
 播放器的KKRenderView添加了手势操作，KKMotion中启动了手机内置的传感器用于实时监控手机屏幕的方向，手势和传感器
 共同决定了预览视频画面的角度，详情请参考KKVrViewMatrix，绘制vr视频时，首先计算投影矩阵(KKVrViewMatrix完成)，
 。然后更新当前opengl的投影矩阵(参见KKGLProgram的updateMatrix方法)，完成了VR视频的全景播放。
 */

#import <Foundation/Foundation.h>
#import "KKPlayerInterface.h"

@class KKGLFrame;
@class KKRenderView;
@interface KKGLDrawTool : NSObject
- (instancetype)initWithVideoType:(KKVideoType)videoType
                       dispayType:(KKDisplayType)dispayType
                           glView:(GLKView *)glView
                       renderView:(KKRenderView *)renderView
                          context:(EAGLContext *)context;
- (BOOL)updateTextureWithGLFrame:(KKGLFrame *)glFrame aspect:(CGFloat *)aspect;
- (void)reloadVrBoxViewSize;
- (void)drawWithGLFrame:(KKGLFrame *)glFrame viewPort:(CGRect)viewport;
@end
