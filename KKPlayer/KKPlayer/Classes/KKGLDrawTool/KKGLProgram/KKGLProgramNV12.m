//
//  KKGLProgramNV12.m
//  KKPlayer
//
//  Created by finger on 2017/3/27.
//  Copyright © 2017年 finger. All rights reserved.
//

#import "KKGLProgramNV12.h"

static GLfloat colorConversion709[] = {
    1.164,    1.164,     1.164,
    0.0,      -0.213,    2.112,
    1.793,    -0.533,    0.0,
};

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
 precision mediump float;
 
 uniform sampler2D SamplerY;
 uniform sampler2D SamplerUV;
 uniform mat3 colorConversionMatrix;
 varying mediump vec2 vTextureCoord;
 
 void main()
 {
     mediump vec3 yuv;
     
     yuv.x = texture2D(SamplerY, vTextureCoord).r - (16.0/255.0);
     yuv.yz = texture2D(SamplerUV, vTextureCoord).rg - vec2(0.5, 0.5);
     
     lowp vec3 rgb = colorConversionMatrix * yuv;
     
     gl_FragColor = vec4(rgb, 1);
 }
 );

@implementation KKGLProgramNV12

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
    self.locationSamplerUV = glGetUniformLocation(self.programId, "SamplerUV");
    self.locationColorConversionMatrix = glGetUniformLocation(self.programId, "colorConversionMatrix");
}

#pragma mark -- 对着色器中的变量赋值，比如attribute、uniform变量赋值

- (void)bindShaderVarValue{
    glUniformMatrix3fv(self.locationColorConversionMatrix, 1, GL_FALSE, colorConversion709);
    glUniform1i(self.locationSamplerY, 0);//对应GL_TEXTURE0
    glUniform1i(self.locationSamplerUV, 1);//对应GL_TEXTURE1
}

@end

