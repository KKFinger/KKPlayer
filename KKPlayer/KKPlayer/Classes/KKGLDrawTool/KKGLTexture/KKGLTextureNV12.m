//
//  KKGLTextureNV12.m
//  KKPlayer
//
//  Created by finger on 2017/3/27.
//  Copyright © 2017年 finger. All rights reserved.
//

#import "KKGLTextureNV12.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

@interface KKGLTextureNV12 ()
@property(nonatomic,strong)EAGLContext *context;
@property(nonatomic,assign)CVOpenGLESTextureRef lumaTexture;
@property(nonatomic,assign)CVOpenGLESTextureRef chromaTexture;
@property(nonatomic,assign)CVOpenGLESTextureCacheRef textureCache;
@property(nonatomic,assign)CGFloat textureAspect;
@property(nonatomic,assign)BOOL didBindTexture;
@end

@implementation KKGLTextureNV12

- (instancetype)initWithContext:(EAGLContext *)context{
    if (self = [super init]) {
        self.context = context;
        [self setupTextureCache];
    }
    return self;
}

- (void)dealloc{
    [self clearTextureCache];
    [self cleanTextures];
}

- (void)setupTextureCache{
    if (!self.textureCache) {
        CVReturn result = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, self.context, NULL, &self->_textureCache);
        if (result != noErr) {
            KKPlayerLog(@"create CVOpenGLESTextureCacheCreate failure %d", result);
            return;
        }
    }
}

//更新纹理图
- (BOOL)updateTextureWithGLFrame:(KKGLFrame *)glFrame aspect:(CGFloat *)aspect{
    CVPixelBufferRef pixelBuffer = [glFrame pixelBufferForNV12];
    if (pixelBuffer == nil) {
        if (self.lumaTexture && self.chromaTexture) {
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(CVOpenGLESTextureGetTarget(self.lumaTexture), CVOpenGLESTextureGetName(self.lumaTexture));
            glActiveTexture(GL_TEXTURE1);
            glBindTexture(CVOpenGLESTextureGetTarget(self.chromaTexture), CVOpenGLESTextureGetName(self.chromaTexture));
            *aspect = self.textureAspect;
            return YES;
        } else {
            return NO;
        }
    }

    if (!self.textureCache) {
        KKPlayerLog(@"no video texture cache");
        return NO;
    }

    GLsizei textureWidth = (GLsizei)CVPixelBufferGetWidth(pixelBuffer);
    GLsizei textureHeight = (GLsizei)CVPixelBufferGetHeight(pixelBuffer);
    self.textureAspect = (textureWidth * 1.0) / (textureHeight * 1.0);
    *aspect = self.textureAspect;

    [self cleanTextures];

    CVReturn result;
    // Y-plane
    glActiveTexture(GL_TEXTURE0);
    result = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                          self.textureCache,
                                                          pixelBuffer,
                                                          NULL,
                                                          GL_TEXTURE_2D,
                                                          GL_RED_EXT,
                                                          textureWidth,
                                                          textureHeight,
                                                          GL_RED_EXT,
                                                          GL_UNSIGNED_BYTE,
                                                          0,
                                                          &self->_lumaTexture);

    if (result == kCVReturnSuccess) {
        glBindTexture(CVOpenGLESTextureGetTarget(self.lumaTexture), CVOpenGLESTextureGetName(self.lumaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    } else {
        KKPlayerLog(@"create CVOpenGLESTextureCacheCreateTextureFromImage failure 1 %d", result);
    }

    // UV-plane.
    glActiveTexture(GL_TEXTURE1);
    result = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                          self.textureCache,
                                                          pixelBuffer,
                                                          NULL,
                                                          GL_TEXTURE_2D,
                                                          GL_RG_EXT,
                                                          textureWidth/2,
                                                          textureHeight/2,
                                                          GL_RG_EXT,
                                                          GL_UNSIGNED_BYTE,
                                                          1,
                                                          &self->_chromaTexture);

    if (result == kCVReturnSuccess) {
        glBindTexture(CVOpenGLESTextureGetTarget(self.chromaTexture), CVOpenGLESTextureGetName(self.chromaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    } else {
        KKPlayerLog(@"create CVOpenGLESTextureCacheCreateTextureFromImage failure 2 %d", result);
    }

    self.didBindTexture = YES;
    return YES;
}

- (void)clearTextureCache{
    if (self.textureCache) {
        CFRelease(self.textureCache);
        self.textureCache = nil;
    }
}

- (void)cleanTextures{
    if (self.lumaTexture) {
        CFRelease(_lumaTexture);
        self.lumaTexture = NULL;
    }
    
    if (self.chromaTexture) {
        CFRelease(_chromaTexture);
        self.chromaTexture = NULL;
    }
    self.textureAspect = 16.0 / 9.0;
    CVOpenGLESTextureCacheFlush(self.textureCache, 0);
}

@end

