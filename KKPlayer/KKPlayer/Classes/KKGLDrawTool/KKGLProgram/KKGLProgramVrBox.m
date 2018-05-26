//
//  KKGLProgramVrBox.m
//  KKPlayer
//
//  Created by finger on 2018/2/7.
//  Copyright © 2018年 finger. All rights reserved.
//

#import "KKGLProgramVrBox.h"

#define KK_GLES_STRINGIZE(x) #x

static const char vertexShaderString[] = KK_GLES_STRINGIZE
(
 attribute vec2 aPosition;
 attribute float aVignette;
 attribute vec2 aRedTextureCoord;
 attribute vec2 aGreenTextureCoord;
 attribute vec2 aBlueTextureCoord;
 varying vec2 vRedTextureCoord;
 varying vec2 vBlueTextureCoord;
 varying vec2 vGreenTextureCoord;
 varying float vVignette;
 uniform float uTextureCoordScale;
 void main() {
     gl_Position = vec4(aPosition, 0.0, 1.0);
     vRedTextureCoord = aRedTextureCoord.xy * uTextureCoordScale;
     vGreenTextureCoord = aGreenTextureCoord.xy * uTextureCoordScale;
     vBlueTextureCoord = aBlueTextureCoord.xy * uTextureCoordScale;
     vVignette = aVignette;
 }
 );

static const char fragmentShaderString[] = KK_GLES_STRINGIZE
(
 precision mediump float;
 varying vec2 vRedTextureCoord;
 varying vec2 vBlueTextureCoord;
 varying vec2 vGreenTextureCoord;
 varying float vVignette;
 uniform sampler2D uTextureSampler;
 void main() {
     gl_FragColor = vVignette * vec4(texture2D(uTextureSampler, vRedTextureCoord).r,
                                     texture2D(uTextureSampler, vGreenTextureCoord).g,
                                     texture2D(uTextureSampler, vBlueTextureCoord).b, 1.0);
 }
 );

@implementation KKGLProgramVrBox

+ (instancetype)program{
    return [self programWithVertexShader:[NSString stringWithUTF8String:vertexShaderString]
                          fragmentShader:[NSString stringWithUTF8String:fragmentShaderString]];
}

#pragma mark -- 获取着色器中的变量地址

- (void)bindShaderVarLocation{
    self.locationPosition = glGetAttribLocation(self.programId, "aPosition");
    self.locationVignette = glGetAttribLocation(self.programId, "aVignette");
    self.locationRedTextureCoord = glGetAttribLocation(self.programId, "aRedTextureCoord");
    self.locationGreenTextureCoord = glGetAttribLocation(self.programId, "aGreenTextureCoord");
    self.locationBlueTextureCoord = glGetAttribLocation(self.programId, "aBlueTextureCoord") ;
    self.locationTextureCoordScale = glGetUniformLocation(self.programId, "uTextureCoordScale");
    self.locationSampler = glGetUniformLocation(self.programId, "uTextureSampler");
}

#pragma mark -- 对着色器中的变量赋值，比如attribute、uniform变量赋值

- (void)bindShaderVarValue{
    glUniform1i(self.locationSampler, 0);//对应GL_TEXTURE0
    glUniform1f(self.locationTextureCoordScale, 1);
}

@end
