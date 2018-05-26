//
//  KKGLProgram.m
//  KKPlayer
//
//  Created by finger on 16/01/2017.
//  Copyright © 2017 finger. All rights reserved.
//

/*
 *opengl绘制一般流程
 *1、创建渲染程序
 *2、编译顶点和片元着色器
 *3、将顶点坐标(决定纹理图在渲染视图中的位置)和纹理坐标(决定渲染纹理图的区域)传入渲染管道
 *4、根据视频帧更新纹理图
 *5、绘制
 */

#import "KKGLProgram.h"

@interface KKGLProgram()
@property(nonatomic,assign)GLuint vertexShaderId;
@property(nonatomic,assign)GLuint fragmentShaderId;
@property(nonatomic,copy)NSString *vertexShaderString;
@property(nonatomic,copy)NSString *fragmentShaderString;
@end

@implementation KKGLProgram

+ (instancetype)programWithVertexShader:(NSString *)vertexShader fragmentShader:(NSString *)fragmentShader{
    return [[self alloc] initWithVertexShader:vertexShader fragmentShader:fragmentShader];
}

- (instancetype)initWithVertexShader:(NSString *)vertexShader fragmentShader:(NSString *)fragmentShader{
    if (self = [super init]) {
        self.vertexShaderString = vertexShader;
        self.fragmentShaderString = fragmentShader;
        [self setup];
    }
    return self;
}

- (void)setup{
    [self genProgram];
    [self setupShader];
    [self linkProgram];
    [self useProgram];
    [self bindShaderVarLocation];
    [self bindShaderVarValue];
}

- (void)dealloc{
    [self clearShader];
    [self clearProgram];
    KKPlayerLog(@"%@ release", self.class);
}

#pragma mark -- 更新视图的投影矩阵

//播放VR视频时用于预览不同角度的画面，非vr类型的视频则设置为GLKMatrix4Identity
- (void)updateMatrix:(GLKMatrix4)matrix{
    glUniformMatrix4fv(self.locationMatrix, 1, GL_FALSE, matrix.m);
}

#pragma mark -- 渲染Program

- (void)genProgram{
    self.programId = glCreateProgram();
}

- (void)useProgram{
    glUseProgram(self.programId);
}

#pragma mark -- 编译着色器

- (void)setupShader{
    if (![self compileShader:&_vertexShaderId type:GL_VERTEX_SHADER string:self.vertexShaderString.UTF8String]){
        KKPlayerLog(@"load vertex shader failure");
    }
    if (![self compileShader:&_fragmentShaderId type:GL_FRAGMENT_SHADER string:self.fragmentShaderString.UTF8String]){
        KKPlayerLog(@"load fragment shader failure");
    }
    glAttachShader(self.programId, self.vertexShaderId);
    glAttachShader(self.programId, self.fragmentShaderId);
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type string:(const char *)shaderString{
    if (!shaderString){
        KKPlayerLog(@"Failed to load shader");
        return NO;
    }
    
    GLint status;
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &shaderString, NULL);
    glCompileShader(*shader);
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status != GL_TRUE){
        GLint logLength = 0;
        glGetShaderiv(* shader, GL_INFO_LOG_LENGTH, &logLength);
        if (logLength > 0) {
            GLchar *log = (GLchar *)malloc(logLength);
            glGetShaderInfoLog(* shader, logLength, &logLength, log);
            KKPlayerLog(@"Shader compile log:\n%s", log);
            free(log);
            log = NULL;
        }
    }
    
    return status == GL_TRUE;
}

#pragma mark -- 链接渲染Program

- (BOOL)linkProgram{
    GLint status;
    glLinkProgram(self.programId);
    glGetProgramiv(self.programId, GL_LINK_STATUS, &status);
    if (status == GL_FALSE){
        return NO;
    }
    
    [self clearShader];
    
    return YES;
}

#pragma mark -- 清理

- (void)clearShader{
    if (self.vertexShaderId) {
        glDeleteShader(self.vertexShaderId);
    }
    
    if (self.fragmentShaderId) {
        glDeleteShader(self.fragmentShaderId);
    }
}

- (void)clearProgram{
    if (self.programId) {
        glDeleteProgram(self.programId);
        self.programId = 0;
    }
}

#pragma mark -- 子类实现

- (void)bindShaderVarLocation {}
- (void)bindShaderVarValue {}

@end
