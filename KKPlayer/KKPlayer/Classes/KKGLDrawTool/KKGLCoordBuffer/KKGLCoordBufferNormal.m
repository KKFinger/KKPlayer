//
//  KKGLCoordBufferNormal.m
//  KKPlayer
//
//  Created by finger on 17/01/2017.
//  Copyright © 2017 finger. All rights reserved.
//

#import "KKGLCoordBufferNormal.h"

//顶点坐标
static GLKVector3 vertexBufferData[] = {
    {-1, 1, 0.0},
    {1, 1, 0.0},
    {1, -1, 0.0},
    {-1, -1, 0.0},
};

//顶点索引
static GLushort indexBufferData[] = {
    0, 1, 2, 0, 2, 3
};

//正常画面
static GLKVector2 textureBufferDataR0[] = {
    {0.0, 0.0},
    {1.0, 0.0},
    {1.0, 1.0},
    {0.0, 1.0},
};

//翻转90度
static GLKVector2 textureBufferDataR90[] = {
    {0.0, 1.0},
    {0.0, 0.0},
    {1.0, 0.0},
    {1.0, 1.0},
};

//翻转180度
static GLKVector2 textureBufferDataR180[] = {
    {1.0, 1.0},
    {0.0, 1.0},
    {0.0, 0.0},
    {1.0, 0.0},
};

//翻转270度
static GLKVector2 textureBufferDataR270[] = {
    {1.0, 0.0},
    {1.0, 1.0},
    {0.0, 1.0},
    {0.0, 0.0},
};

static GLuint vertexBufferId = 0;
static GLuint indexBufferId = 0;
static GLuint textureBufferId = 0;

@implementation KKGLCoordBufferNormal

- (void)genBufferIdentify{
    glGenBuffers(1, &indexBufferId);
    glGenBuffers(1, &vertexBufferId);
    glGenBuffers(1, &textureBufferId);
}

- (void)setupCoordBuffer{
    self.indexCount = 6;
    self.vertexCount = 4;
    self.indexBufferId = indexBufferId;
    self.vertexBufferId = vertexBufferId;
    self.textureBufferId = textureBufferId;
}

- (void)bindPositionLocation:(GLint)positionLocation
        textureCoordLocation:(GLint)textureCoordLocation{
    [self bindPositionLocation:positionLocation
          textureCoordLocation:textureCoordLocation
             textureRotateType:KKTextureRotateType0];
}

- (void)bindPositionLocation:(GLint)positionLocation
        textureCoordLocation:(GLint)textureCoordLocation
           textureRotateType:(KKTextureRotateType)textureRotateType{
    //顶点索引Buffer
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, self.indexBufferId);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, self.indexCount * sizeof(GLushort), indexBufferData, GL_STATIC_DRAW);
    
    //顶点坐标Buffer
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBufferId);
    glBufferData(GL_ARRAY_BUFFER, self.vertexCount * 3 * sizeof(GLfloat), vertexBufferData, GL_STATIC_DRAW);
    glEnableVertexAttribArray(positionLocation);
    glVertexAttribPointer(positionLocation, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), NULL);
    /**
     定义顶点属性数组
     
     @param index 顶点属性的索引，一般为着色器中attribute属性的索引
     @param size 指定每个顶点属性的组件数量，如position是由3个（x,y,z）组成，而颜色是4个（r,g,b,a）
     @param type 指定数组中每个组件的数据类型。可用的符号常量有GL_BYTE, GL_UNSIGNED_BYTE, GL_SHORT,GL_UNSIGNED_SHORT, GL_FIXED, 和 GL_FLOAT，初始值为GL_FLOAT。
     @param normalized 指定当被访问时，固定点数据值是否应该被归一化（GL_TRUE）或者直接转换为固定点值（GL_FALSE）
     @param stride 指定连续顶点属性之间的偏移量。如果为0，那么顶点属性会被理解为：它们是紧密排列在一起的。初始值为0
     @param pointer 指定一个指针，指向数组中第一个顶点属性的第一个组件。初始值为0。
     */
    //void glVertexAttribPointer (GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid *pointer);
    
    //纹理坐标Buffer
    glBindBuffer(GL_ARRAY_BUFFER, self.textureBufferId);
    switch (textureRotateType) {
        case KKTextureRotateType0:
            glBufferData(GL_ARRAY_BUFFER, self.vertexCount * 2 * sizeof(GLfloat), textureBufferDataR0, GL_DYNAMIC_DRAW);
            break;
        case KKTextureRotateType90:
            glBufferData(GL_ARRAY_BUFFER, self.vertexCount * 2 * sizeof(GLfloat), textureBufferDataR90, GL_DYNAMIC_DRAW);
            break;
        case KKTextureRotateType180:
            glBufferData(GL_ARRAY_BUFFER, self.vertexCount * 2 * sizeof(GLfloat), textureBufferDataR180, GL_DYNAMIC_DRAW);
            break;
        case KKTextureRotateType270:
            glBufferData(GL_ARRAY_BUFFER, self.vertexCount * 2 * sizeof(GLfloat), textureBufferDataR270, GL_DYNAMIC_DRAW);
            break;
    }
    glEnableVertexAttribArray(textureCoordLocation);
    glVertexAttribPointer(textureCoordLocation, 2, GL_FLOAT, GL_FALSE, sizeof(GLfloat)*2, NULL);
}

@end
