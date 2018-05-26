//
//  KKFFAudioFrame.m
//  KKPlayer
//
//  Created by finger on 2017/2/17.
//  Copyright © 2017年 single. All rights reserved.
//

#import "KKFFAudioFrame.h"

@implementation KKFFAudioFrame{
    size_t buffer_size;
}

- (KKFFFrameType)type{
    return KKFFFrameTypeAudio;
}

- (NSInteger)decodedSize{
    return (NSInteger)self->_samplesLength;
}

- (void)setSamplesLength:(NSUInteger)samplesLength{
    _samplesLength = samplesLength;
    if (self->buffer_size < samplesLength) {
        if (self->buffer_size > 0 && self->samples != NULL) {
            free(self->samples);
            self->samples = NULL ;
        }
        self->buffer_size = samplesLength;
        self->samples = malloc(self->buffer_size);
    }
    self->_outputOffset = 0;
}

- (void)dealloc{
    if (self->buffer_size > 0 && self->samples != NULL) {
        free(self->samples);
        self->samples = NULL;
    }
}

@end
