//
//  KKGLProgramVrBox.h
//  KKPlayer
//
//  Created by finger on 2018/2/7.
//  Copyright © 2018年 finger. All rights reserved.
//

#import "KKGLProgram.h"

@interface KKGLProgramVrBox : KKGLProgram
@property(nonatomic,assign)GLint locationSampler;//sampler2D纹理图
@property(nonatomic,assign)GLint locationVignette;
@property(nonatomic,assign)GLint locationRedTextureCoord;
@property(nonatomic,assign)GLint locationGreenTextureCoord;
@property(nonatomic,assign)GLint locationBlueTextureCoord;
@property(nonatomic,assign)GLint locationTextureCoordScale;
+ (instancetype)program;
- (void)bindShaderVarValue;
@end
