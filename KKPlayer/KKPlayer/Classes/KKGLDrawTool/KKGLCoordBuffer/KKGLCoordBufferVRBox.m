//
//  KKGLCoordBufferVRBox.m
//  KKPlayer
//
//  Created by finger on 2018/2/7.
//  Copyright © 2018年 finger. All rights reserved.
//

#import "KKGLCoordBufferVRBox.h"
#import "KKGLProgramVrBox.h"

static int const indexCount = 3158;
static int const vertexCount = 14400;

@interface KKGLCoordBufferVRBox (){
    GLfloat vertexBufferData[14400];
    GLshort indexBufferData[3158];
}
@property(nonatomic,assign)GLuint indexBufferId;
@property(nonatomic,assign)GLuint vertexBufferId;
@property(nonatomic,assign)int indexCount;
@property(nonatomic,assign)int vertexCount;
@property(nonatomic,assign)KKVRBoxType vrBoxType;
@end

@implementation KKGLCoordBufferVRBox

- (instancetype)initWithBoxType:(KKVRBoxType)vrBoxType{
    self = [super init];
    if(self){
        _vrBoxType = vrBoxType;
        [self genBufferIdentify];
        [self setupCoordBuffer];
    }
    return self;
}

- (void)dealloc{
    NSLog(@"%@ dealloc",NSStringFromClass([self class]));
}

- (void)genBufferIdentify{
    GLuint bufferIDs[2] = { 0, 0 };
    glGenBuffers(2, bufferIDs);
    self.vertexBufferId = bufferIDs[0];
    self.indexBufferId = bufferIDs[1];
}

- (void)setVrBoxType:(KKVRBoxType)vrBoxType{
    _vrBoxType = vrBoxType ;
    [self setupCoordBuffer];
}

- (void)setupCoordBuffer{
    
    self.indexCount = indexCount;
    self.vertexCount = vertexCount;
    
//    GLfloat vertexBufferData[14400];
//    GLshort indexBufferData[3158];
    
    float xEyeOffsetScreen = 0.523064613;
    float yEyeOffsetScreen = 0.80952388;
    
    float viewportWidthTexture = 1.43138313;
    float viewportHeightTexture = 1.51814604;
    
    float viewportXTexture = 0;
    float viewportYTexture = 0;
    
    float textureWidth = 2.86276627;
    float textureHeight = 1.51814604;
    
    float xEyeOffsetTexture = 0.592283607;
    float yEyeOffsetTexture = 0.839099586;
    
    float screenWidth = 2.47470069;
    float screenHeight = 1.39132345;
    
    switch (self.vrBoxType) {
        case KKVRBoxTypeLeft:
            break;
        case KKVRBoxTypeRight:
            xEyeOffsetScreen = 1.95163608;
            viewportXTexture = 1.43138313;
            xEyeOffsetTexture = 2.27048278;
            break;
    }
    
    int vertexOffset = 0;
    
    const int rows = 40;
    const int cols = 40;
    
    const float vignetteSizeTanAngle = 0.05f;
    
    for (int row = 0; row < rows; row++){
        for (int col = 0; col < cols; col++){
            const float uTextureBlue = col / 39.0f * (viewportWidthTexture / textureWidth) + viewportXTexture / textureWidth;
            const float vTextureBlue = row / 39.0f * (viewportHeightTexture / textureHeight) + viewportYTexture / textureHeight;
            
            const float xTexture = uTextureBlue * textureWidth - xEyeOffsetTexture;
            const float yTexture = vTextureBlue * textureHeight - yEyeOffsetTexture;
            const float rTexture = sqrtf(xTexture * xTexture + yTexture * yTexture);
            
            const float textureToScreenBlue = (rTexture > 0.0f) ? [self blueDistortInverse:rTexture] / rTexture : 1.0f;
            
            const float xScreen = xTexture * textureToScreenBlue;
            const float yScreen = yTexture * textureToScreenBlue;
            
            const float uScreen = (xScreen + xEyeOffsetScreen) / screenWidth;
            const float vScreen = (yScreen + yEyeOffsetScreen) / screenHeight;
            const float rScreen = rTexture * textureToScreenBlue;
            
            const float screenToTextureGreen = (rScreen > 0.0f) ? [self distortionFactor:rScreen] : 1.0f;
            const float uTextureGreen = (xScreen * screenToTextureGreen + xEyeOffsetTexture) / textureWidth;
            const float vTextureGreen = (yScreen * screenToTextureGreen + yEyeOffsetTexture) / textureHeight;
            
            const float screenToTextureRed = (rScreen > 0.0f) ? [self distortionFactor:rScreen] : 1.0f;
            const float uTextureRed = (xScreen * screenToTextureRed + xEyeOffsetTexture) / textureWidth;
            const float vTextureRed = (yScreen * screenToTextureRed + yEyeOffsetTexture) / textureHeight;
            
            const float vignetteSizeTexture = vignetteSizeTanAngle / textureToScreenBlue;
            
            const float dxTexture = xTexture + xEyeOffsetTexture - clamp(xTexture + xEyeOffsetTexture,
                                                                         viewportXTexture + vignetteSizeTexture,
                                                                         viewportXTexture + viewportWidthTexture - vignetteSizeTexture);
            const float dyTexture = yTexture + yEyeOffsetTexture - clamp(yTexture + yEyeOffsetTexture,
                                                                         viewportYTexture + vignetteSizeTexture,
                                                                         viewportYTexture + viewportHeightTexture - vignetteSizeTexture);
            const float drTexture = sqrtf(dxTexture * dxTexture + dyTexture * dyTexture);
            
            float vignette = 1.0f;
            
            bool vignetteEnabled = true;
            if (vignetteEnabled){
                vignette = 1.0f - clamp(drTexture / vignetteSizeTexture, 0.0f, 1.0f);
            }
            
            vertexBufferData[(vertexOffset + 0)] = 2.0f * uScreen - 1.0f;
            vertexBufferData[(vertexOffset + 1)] = 2.0f * vScreen - 1.0f;
            vertexBufferData[(vertexOffset + 2)] = vignette;
            vertexBufferData[(vertexOffset + 3)] = uTextureRed;
            vertexBufferData[(vertexOffset + 4)] = vTextureRed;
            vertexBufferData[(vertexOffset + 5)] = uTextureGreen;
            vertexBufferData[(vertexOffset + 6)] = vTextureGreen;
            vertexBufferData[(vertexOffset + 7)] = uTextureBlue;
            vertexBufferData[(vertexOffset + 8)] = vTextureBlue;
            
            vertexOffset += 9;
        }
    }
    
    int indexOffset = 0;
    vertexOffset = 0;
    for (int row = 0; row < rows-1; row++){
        if (row > 0){
            indexBufferData[indexOffset] = indexBufferData[(indexOffset - 1)];
            indexOffset++;
        }
        for (int col = 0; col < cols; col++){
            if (col > 0){
                if (row % 2 == 0){
                    vertexOffset++;
                }else{
                    vertexOffset--;
                }
            }
            indexBufferData[(indexOffset++)] = vertexOffset;
            indexBufferData[(indexOffset++)] = (vertexOffset + 40);
        }
        vertexOffset += 40;
    }
    
    //[self bindCoordData];
}

- (void)bindCoordDataWithProgram:(__weak KKGLProgramVrBox *)program{
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBufferId);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertexBufferData), vertexBufferData, GL_STATIC_DRAW);
    
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, self.indexBufferId);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indexBufferData), indexBufferData, GL_STATIC_DRAW);
    
    glVertexAttribPointer(program.locationPosition, 2, GL_FLOAT, GL_FALSE, 9 * sizeof(float), (void *)(0 * sizeof(float)));
    glEnableVertexAttribArray(program.locationPosition);
    
    glVertexAttribPointer(program.locationVignette, 1, GL_FLOAT, GL_FALSE, 9 * sizeof(float), (void *)(2 * sizeof(float)));
    glEnableVertexAttribArray(program.locationVignette);
    
    glVertexAttribPointer(program.locationBlueTextureCoord, 2, GL_FLOAT, GL_FALSE, 9 * sizeof(float), (void *)(7 * sizeof(float)));
    glEnableVertexAttribArray(program.locationBlueTextureCoord);
    
    glVertexAttribPointer(program.locationRedTextureCoord, 2, GL_FLOAT, GL_FALSE, 9 * sizeof(float), (void *)(3 * sizeof(float)));
    glEnableVertexAttribArray(program.locationRedTextureCoord);
    
    glVertexAttribPointer(program.locationGreenTextureCoord, 2, GL_FLOAT, GL_FALSE, 9 * sizeof(float), (void *)(5 * sizeof(float)));
    glEnableVertexAttribArray(program.locationGreenTextureCoord);
}

- (float)blueDistortInverse:(float)radius{
    float r0 = radius / 0.9f;
    float r = radius * 0.9f;
    float dr0 = radius - [self distort:r0];
    while (fabsf(r - r0) > 0.0001f){
        float dr = radius - [self distort:r];
        float r2 = r - dr * ((r - r0) / (dr - dr0));
        r0 = r;
        r = r2;
        dr0 = dr;
    }
    return r;
}

- (float)distort:(float)radius{
    return radius * [self distortionFactor:radius];
}

- (float)distortionFactor:(float)radius{
    int s_numberOfCoefficients = 2;
    static float _coefficients[2] = {0.441000015, 0.156000003};
    
    float result = 1.0f;
    float rFactor = 1.0f;
    float squaredRadius = radius * radius;
    for (int i = 0; i < s_numberOfCoefficients; i++){
        rFactor *= squaredRadius;
        result += _coefficients[i] * rFactor;
    }
    return result;
}

float clamp(float val, float min, float max){
    return MAX(min, MIN(max, val));
}

@end
