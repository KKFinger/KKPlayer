//
//  KKVRBoxDrawTool.m
//  KKPlayer
//
//  Created by finger on 26/12/2016.
//  Copyright © 2016 finger. All rights reserved.
//

#import "KKVRBoxDrawTool.h"
#import "KKGLCoordBufferVRBox.h"
#import "KKGLTextureVRBox.h"
#import "KKGLProgramVrBox.h"

@interface KKVRBoxDrawTool ()
@property(nonatomic,strong)KKGLProgramVrBox *program;
@property(nonatomic,strong)KKGLTextureVRBox *texture;
@property(nonatomic,strong)KKGLCoordBufferVRBox *leftEye;
@property(nonatomic,strong)KKGLCoordBufferVRBox *rightEye;
@end

@implementation KKVRBoxDrawTool

+ (instancetype)vrBoxDrawTool{
    return [[self alloc] initWithViewportSize:CGSizeZero];
}

- (instancetype)initWithViewportSize:(CGSize)viewportSize{
    if (self = [super init]) {
        self.viewportSize = viewportSize;
    }
    return self;
}

#pragma maek -- 绘制

- (void)beforDraw{
    glBindFramebuffer(GL_FRAMEBUFFER, self->_texture.frameBufferId);
}

- (void)drawBox{
    
    [self.program useProgram];
    [self.program bindShaderVarValue];
    
    glViewport(0, 0, self.viewportSize.width, self.viewportSize.height);
    
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    glDisable(GL_CULL_FACE);
    glEnable(GL_SCISSOR_TEST);
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, self.texture.textureId);
    
    glScissor(0, 0, self.viewportSize.width / 2, self.viewportSize.height);
    [self.leftEye bindCoordDataWithProgram:self.program];
    glDrawElements(GL_TRIANGLE_STRIP, self.leftEye.indexCount, GL_UNSIGNED_SHORT, 0);
    
    glScissor(self.viewportSize.width / 2, 0, self.viewportSize.width / 2, self.viewportSize.height);
    [self.rightEye bindCoordDataWithProgram:self.program];
    glDrawElements(GL_TRIANGLE_STRIP, self.rightEye.indexCount, GL_UNSIGNED_SHORT, 0);
    
    glDisable(GL_SCISSOR_TEST);
}

#pragma mark -- @property setter

- (void)setViewportSize:(CGSize)viewportSize{
    if (!CGSizeEqualToSize(_viewportSize, viewportSize)) {
        _viewportSize = viewportSize;
        [self.texture resetTextureBufferSize:viewportSize];
    }
}

#pragma mark -- @property getter

- (KKGLProgramVrBox *)program{
    if(!_program){
        _program = [KKGLProgramVrBox program];
    }
    return _program;
}

- (KKGLTextureVRBox *)texture{
    if(!_texture){
        _texture = [KKGLTextureVRBox new];
    }
    return _texture;
}

- (KKGLCoordBufferVRBox *)leftEye{
    if (!_leftEye) {
        _leftEye = [[KKGLCoordBufferVRBox alloc]initWithBoxType:KKVRBoxTypeLeft];
    }
    return _leftEye;
}
 
- (KKGLCoordBufferVRBox *)rightEye{
    if (!_rightEye) {
        _rightEye = [[KKGLCoordBufferVRBox alloc]initWithBoxType:KKVRBoxTypeRight];
    }
    return _rightEye;
}

@end
