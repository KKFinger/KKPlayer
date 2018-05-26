//
//  KKGLProgramYUV420.m
//  KKPlayer
//
//  Created by finger on 2017/3/27.
//  Copyright © 2017年 finger. All rights reserved.
//

#import "KKGLProgramYUV420.h"

#define KK_GLES_STRINGIZE(x) #x

static const char vertexShaderString[] = KK_GLES_STRINGIZE
(
 attribute vec4 position;
 attribute vec2 textureCoord;
 uniform mat4 posMatrix;
 varying vec2 vTextureCoord;
 
 void main()
 {
     vTextureCoord = textureCoord;
     gl_Position = posMatrix * position;
 }
 );

static const char fragmentShaderString[] = KK_GLES_STRINGIZE
(
 uniform sampler2D SamplerY;
 uniform sampler2D SamplerU;
 uniform sampler2D SamplerV;
 varying mediump vec2 vTextureCoord;
 
 void main()
 {
     highp float y = texture2D(SamplerY, vTextureCoord).r;
     highp float u = texture2D(SamplerU, vTextureCoord).r - 0.5;
     highp float v = texture2D(SamplerV, vTextureCoord).r - 0.5;
     
     highp float r = y + 1.402 * v;
     highp float g = y - 0.344 * u - 0.714 * v;
     highp float b = y + 1.772 * u;
     
     gl_FragColor = vec4(r , g, b, 1.0);
 }
 );

@implementation KKGLProgramYUV420

+ (instancetype)program{
    return [self programWithVertexShader:[NSString stringWithUTF8String:vertexShaderString]
                          fragmentShader:[NSString stringWithUTF8String:fragmentShaderString]];
}

#pragma mark -- 获取着色器中的变量地址

- (void)bindShaderVarLocation{
    self.locationPosition = glGetAttribLocation(self.programId, "position");
    self.locationTextureCoord = glGetAttribLocation(self.programId, "textureCoord");
    self.locationMatrix = glGetUniformLocation(self.programId, "posMatrix");
    self.locationSamplerY = glGetUniformLocation(self.programId, "SamplerY");
    self.locationSamplerU = glGetUniformLocation(self.programId, "SamplerU");
    self.locationSamplerV = glGetUniformLocation(self.programId, "SamplerV");
}

#pragma mark -- 对着色器中的变量赋值，比如attribute、uniform变量赋值

- (void)bindShaderVarValue{
    glUniform1i(self.locationSamplerY, 0);//对应GL_TEXTURE0
    glUniform1i(self.locationSamplerU, 1);//对应GL_TEXTURE1
    glUniform1i(self.locationSamplerV, 2);//对应GL_TEXTURE2
}

@end
