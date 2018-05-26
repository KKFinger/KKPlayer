//
//  KKGLDrawTool.m
//  KKPlayer
//
//  Created by finger on 2018/2/7.
//  Copyright © 2018年 finger. All rights reserved.
//

#import "KKGLDrawTool.h"
#import "KKGLProgramNV12.h"
#import "KKGLProgramYUV420.h"
#import "KKGLProgramVrBox.h"
#import "KKGLTextureNV12.h"
#import "KKGLTextureYUV420.h"
#import "KKGLCoordBufferNormal.h"
#import "KKGLCoordBufferVR.h"
#import "KKVrViewMatrix.h"
#import "KKRenderView.h"
#import "KKVRBoxDrawTool.h"

@interface KKGLDrawTool()
@property(nonatomic,assign)KKVideoType videoType;
@property(nonatomic,assign)KKDisplayType displayType;
@property(nonatomic,weak)GLKView *glView;
@property(nonatomic,weak)KKRenderView *renderView;
@property(nonatomic,weak)EAGLContext *context;
@property(nonatomic,strong)KKGLTextureNV12 *textureNV12;
@property(nonatomic,strong)KKGLTextureYUV420 *textureYUV420;
@property(nonatomic,strong)KKGLProgramNV12 *programNV12;
@property(nonatomic,strong)KKGLProgramYUV420 *programYUV420;
@property(nonatomic,strong)KKGLCoordBufferNormal *normalGLBuffer;
@property(nonatomic,strong)KKGLCoordBufferVR *vrGLBuffer;
@property(nonatomic,strong)KKVrViewMatrix *vrMatrix;
@property(nonatomic,strong)KKVRBoxDrawTool *drawBoxTool;
@end

@implementation KKGLDrawTool

- (instancetype)initWithVideoType:(KKVideoType)videoType
                       dispayType:(KKDisplayType)dispayType
                           glView:(GLKView *)glView
                       renderView:(KKRenderView *)renderView
                          context:(EAGLContext *)context{
    self = [super init];
    if(self){
        self.videoType = videoType;
        self.displayType = dispayType;
        self.context = context;
        self.glView = glView;
        self.renderView = renderView;
    }
    return self ;
}

- (void)dealloc{
    NSLog(@"%@ dealloc",NSStringFromClass([self class]));
}

#pragma mark -- 更新纹理图

- (BOOL)updateTextureWithGLFrame:(KKGLFrame *)glFrame aspect:(CGFloat *)aspect{
    KKGLTexture *texture = [self textureWithType:glFrame.type];
    return [texture updateTextureWithGLFrame:glFrame aspect:aspect];
}

#pragma mark -- 重置VRBox的绘制窗口

- (void)reloadVrBoxViewSize{
    CGFloat scale = [UIScreen mainScreen].scale;
    self.drawBoxTool.viewportSize = CGSizeMake(CGRectGetWidth(self.glView.bounds) * scale, CGRectGetHeight(self.glView.bounds) * scale);
}

#pragma mark -- 绘制相关

- (KKGLProgram *)programWithType:(KKGLFrameType)type{
    switch (type) {
        case KKGLFrameTypeNV12:{
            return self.programNV12;
        }
            break;
        case KKGLFrameTypeYUV420:{
            return self.programYUV420;
        }
            break;
    }
}

- (KKGLTexture *)textureWithType:(KKGLFrameType)type{
    switch (type) {
        case KKGLFrameTypeNV12:{
            return self.textureNV12;
        }
            break;
        case KKGLFrameTypeYUV420:{
            return self.textureYUV420;
        }
            break;
    }
}

- (KKTextureRotateType)textureRotateWithType:(KKFFVideoFrameRotateType)type{
    switch (type) {
        case KKFFVideoFrameRotateType0:
            return KKTextureRotateType0;
        case KKFFVideoFrameRotateType90:
            return KKTextureRotateType90;
        case KKFFVideoFrameRotateType180:
            return KKTextureRotateType180;
        case KKFFVideoFrameRotateType270:
            return KKTextureRotateType270;
    }
    return KKTextureRotateType0;
}

- (void)drawWithGLFrame:(KKGLFrame *)glFrame viewPort:(CGRect)viewport{
    if (self.videoType == KKVideoTypeVR && self.displayType == KKDisplayTypeVRBox) {
        [self.drawBoxTool beforDraw];
    }
    
    KKGLProgram *program = [self programWithType:glFrame.type];
    [program useProgram];
    [program bindShaderVarValue];
    
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    
    CGFloat scale = [UIScreen mainScreen].scale;
    CGRect rect = CGRectMake(0, 0, viewport.size.width * scale, viewport.size.height * scale);
    switch (self.videoType) {
        case KKVideoTypeNormal:{
            //更新纹理坐标和顶点坐标
            [self.normalGLBuffer bindPositionLocation:program.locationPosition textureCoordLocation:program.locationTextureCoord textureRotateType:[self textureRotateWithType:glFrame.rotateType]];
            glViewport(rect.origin.x, rect.origin.y, CGRectGetWidth(rect), CGRectGetHeight(rect));
            [program updateMatrix:GLKMatrix4Identity];
            glDrawElements(GL_TRIANGLES, self.normalGLBuffer.indexCount, GL_UNSIGNED_SHORT, 0);
        }
            break;
        case KKVideoTypeVR:{
            //更新纹理坐标和顶点坐标
            [self.vrGLBuffer bindPositionLocation:program.locationPosition textureCoordLocation:program.locationTextureCoord];
            switch (self.displayType) {
                case KKDisplayTypeNormal:{
                    //计算顶点变换矩阵
                    GLKMatrix4 matrix;
                    BOOL success = [self.vrMatrix singleMatrixWithSize:rect.size matrix:&matrix fingerRotation:self.renderView.fingerRotation];
                    if (success) {
                        glViewport(rect.origin.x, rect.origin.y, CGRectGetWidth(rect), CGRectGetHeight(rect));
                        [program updateMatrix:matrix];
                        glDrawElements(GL_TRIANGLES, self.vrGLBuffer.indexCount, GL_UNSIGNED_SHORT, 0);
                    }
                }
                    break;
                case KKDisplayTypeVRBox:{
                    //计算顶点变换矩阵
                    GLKMatrix4 leftMatrix;
                    GLKMatrix4 rightMatrix;
                    BOOL success = [self.vrMatrix doubleMatrixWithSize:rect.size leftMatrix:&leftMatrix rightMatrix:&rightMatrix fingerRotation:self.renderView.fingerRotation];
                    if (success) {
                        glViewport(rect.origin.x, rect.origin.y, CGRectGetWidth(rect)/2, CGRectGetHeight(rect));
                        [program updateMatrix:leftMatrix];
                        glDrawElements(GL_TRIANGLES, self.vrGLBuffer.indexCount, GL_UNSIGNED_SHORT, 0);
                        
                        glViewport(CGRectGetWidth(rect)/2 + rect.origin.x, rect.origin.y, CGRectGetWidth(rect)/2, CGRectGetHeight(rect));
                        [program updateMatrix:rightMatrix];
                        glDrawElements(GL_TRIANGLES, self.vrGLBuffer.indexCount, GL_UNSIGNED_SHORT, 0);
                    }
                }
                    break;
            }
        }
            break;
    }
    
    [self.glView bindDrawable];
    
    if (self.videoType == KKVideoTypeVR && self.displayType == KKDisplayTypeVRBox) {
        [self.drawBoxTool drawBox];
    }
}

#pragma mark -- @property

- (KKGLProgramNV12 *)programNV12{
    if(!_programNV12){
        _programNV12 = [KKGLProgramNV12 program];
    }
    return _programNV12;
}

- (KKGLProgramYUV420 *)programYUV420{
    if(!_programYUV420){
        _programYUV420 = [KKGLProgramYUV420 program];
    }
    return _programYUV420;
}

- (KKGLTextureNV12 *)textureNV12{
    if(!_textureNV12){
        _textureNV12 = [[KKGLTextureNV12 alloc] initWithContext:self.context];
    }
    return _textureNV12;
}

- (KKGLTextureYUV420 *)textureYUV420{
    if(!_textureYUV420){
        _textureYUV420 = [[KKGLTextureYUV420 alloc] init];
    }
    return _textureYUV420;
}

- (KKGLCoordBufferNormal *)normalGLBuffer{
    if(!_normalGLBuffer){
        _normalGLBuffer = [KKGLCoordBufferNormal coordBuffer];
    }
    return _normalGLBuffer;
}

- (KKGLCoordBufferVR *)vrGLBuffer{
    if(!_vrGLBuffer){
        _vrGLBuffer = [KKGLCoordBufferVR coordBuffer];
    }
    return _vrGLBuffer;
}

- (KKVrViewMatrix *)vrMatrix{
    if(!_vrMatrix){
        _vrMatrix = [[KKVrViewMatrix alloc]init];
    }
    return _vrMatrix;
}

- (KKVRBoxDrawTool *)drawBoxTool{
    if(!_drawBoxTool){
        _drawBoxTool = [[KKVRBoxDrawTool alloc]initWithViewportSize:CGSizeZero];
    }
    return _drawBoxTool;
}

@end
