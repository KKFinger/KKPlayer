//
//  KKGLProgram.h
//  KKPlayer
//
//  Created by finger on 16/01/2017.
//  Copyright © 2017 finger. All rights reserved.
//

@interface KKGLProgram:NSObject
@property (nonatomic,assign)GLint programId;
@property (nonatomic,assign)GLint locationPosition;//顶点坐标
@property (nonatomic,assign)GLint locationTextureCoord;//纹理坐标
@property (nonatomic,assign)GLint locationMatrix;//顶点变换矩阵

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)programWithVertexShader:(NSString *)vertexShader fragmentShader:(NSString *)fragmentShader;

- (void)useProgram;
- (void)updateMatrix:(GLKMatrix4)matrix;

#pragma mark -- 子类实现

- (void)bindShaderVarLocation;//获取着色器中的变量地址
- (void)bindShaderVarValue;//对着色器中的变量赋值，比如attribute、uniform变量赋值

@end
