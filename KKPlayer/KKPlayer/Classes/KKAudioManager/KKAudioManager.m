//
//  KKAudioManager.m
//  KKPlayer
//
//  Created by finger on 09/01/2017.
//  Copyright © 2017 single. All rights reserved.
//

#import "KKAudioManager.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

static int const max_frame_size = 4096;
static int const max_chan = 2;

typedef struct{
    AUNode node;
    AudioUnit audioUnit;
}KKAudioUnitContext;

typedef struct{
    AUGraph graph;
    KKAudioUnitContext converterUnitContext;
    KKAudioUnitContext mixerUnitContext;
    KKAudioUnitContext outputUnitContext;
    AudioStreamBasicDescription commonFormat;
}KKAudioGraphContext;

@interface KKAudioManager (){
    float *_renderBufferData;
}
@property(nonatomic,weak)id handlerTarget;
@property(nonatomic,assign)KKAudioGraphContext *graphContext;
@property(nonatomic,copy)KKAudioManagerInterruptionHandler interruptionHandler;
@property(nonatomic,copy)KKAudioManagerRouteChangeHandler routeChangeHandler;
@property(nonatomic,strong)AVAudioSession *audioSession;
@property(nonatomic,strong)NSError *error;
@property(nonatomic,assign)BOOL registered;
@end

@implementation KKAudioManager

+ (instancetype)manager{
    static KKAudioManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (void)dealloc{
    [self unregisterAudioSession];
    if (self->_renderBufferData) {
        free(self->_renderBufferData);
        self->_renderBufferData = NULL;
    }
    self->_playing = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    KKPlayerLog(@"KKAudioManager release");
}

- (instancetype)init{
    if (self = [super init]){
        self->_renderBufferData = (float *)calloc(max_frame_size * max_chan, sizeof(float));
        self.audioSession = [AVAudioSession sharedInstance];
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(audioSessionInterruptionHandler:) name:AVAudioSessionInterruptionNotification object:nil];
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(audioSessionRouteChangeHandler:) name:AVAudioSessionRouteChangeNotification object:nil];
    }
    return self;
}

#pragma mark -- AudioUnit初始化

- (BOOL)registerAudioSession{
    if (!self.registered) {
        self.registered = [self setupAudioUnit];
    }
    [self.audioSession setActive:YES error:nil];
    return self.registered;
}

- (BOOL)setupAudioUnit{
    OSStatus result;
    UInt32 audioStreamBasicDescriptionSize = sizeof(AudioStreamBasicDescription);;
    
    self.graphContext = (KKAudioGraphContext *)malloc(sizeof(KKAudioGraphContext));
    memset(self.graphContext, 0, sizeof(KKAudioGraphContext));
    
    result = NewAUGraph(&self.graphContext->graph);
    self.error = checkError(result, @"create  graph error");
    if (self.error) {
        return NO;
    }
    
    AudioComponentDescription converterDescription;
    converterDescription.componentType = kAudioUnitType_FormatConverter;
    converterDescription.componentSubType = kAudioUnitSubType_AUConverter;
    converterDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    result = AUGraphAddNode(self.graphContext->graph, &converterDescription, &self.graphContext->converterUnitContext.node);
    self.error = checkError(result, @"graph add converter node error");
    if (self.error) {
        return NO;
    }
    
    AudioComponentDescription mixerDescription;
    mixerDescription.componentType = kAudioUnitType_Mixer;
    mixerDescription.componentSubType = kAudioUnitSubType_MultiChannelMixer;
    mixerDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    result = AUGraphAddNode(self.graphContext->graph, &mixerDescription, &self.graphContext->mixerUnitContext.node);
    self.error = checkError(result, @"graph add mixer node error");
    if (self.error) {
        return NO;
    }
    
    AudioComponentDescription outputDescription;
    outputDescription.componentType = kAudioUnitType_Output;
    outputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    outputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    result = AUGraphAddNode(self.graphContext->graph, &outputDescription, &self.graphContext->outputUnitContext.node);
    self.error = checkError(result, @"graph add output node error");
    if (self.error) {
        return NO;
    }
    
    result = AUGraphOpen(self.graphContext->graph);
    self.error = checkError(result, @"open graph error");
    if (self.error) {
        return NO;
    }
    
    //连接各个节点AUNode
    result = AUGraphConnectNodeInput(self.graphContext->graph,
                                     self.graphContext->converterUnitContext.node,
                                     0,
                                     self.graphContext->mixerUnitContext.node,
                                     0);
    self.error = checkError(result, @"graph connect converter and mixer error");
    if (self.error) {
        return NO;
    }
    
    result = AUGraphConnectNodeInput(self.graphContext->graph,
                                     self.graphContext->mixerUnitContext.node,
                                     0,
                                     self.graphContext->outputUnitContext.node,
                                     0);
    self.error = checkError(result, @"graph connect converter and mixer error");
    if (self.error) {
        return NO;
    }
    
    //通过AUNode获取Audio Unit
    result = AUGraphNodeInfo(self.graphContext->graph,
                             self.graphContext->converterUnitContext.node,
                             &converterDescription,
                             &self.graphContext->converterUnitContext.audioUnit);
    self.error = checkError(result, @"graph get converter audio unit error");
    if (self.error) {
        return NO;
    }
    
    result = AUGraphNodeInfo(self.graphContext->graph,
                             self.graphContext->mixerUnitContext.node,
                             &mixerDescription,
                             &self.graphContext->mixerUnitContext.audioUnit);
    self.error = checkError(result, @"graph get minxer audio unit error");
    if (self.error) {
        return NO;
    }
    
    result = AUGraphNodeInfo(self.graphContext->graph,
                             self.graphContext->outputUnitContext.node,
                             &outputDescription,
                             &self.graphContext->outputUnitContext.audioUnit);
    self.error = checkError(result, @"graph get output audio unit error");
    if (self.error) {
        return NO;
    }
    
    
    AURenderCallbackStruct auRenderCallback;
    auRenderCallback.inputProc = renderCallback;
    auRenderCallback.inputProcRefCon = (__bridge void *)(self);
    result = AUGraphSetNodeInputCallback(self.graphContext->graph,
                                         self.graphContext->converterUnitContext.node,
                                         0,
                                         &auRenderCallback);
    self.error = checkError(result, @"graph add converter input callback error");
    if (self.error) {
        return NO;
    }
    
    result = AudioUnitGetProperty(self.graphContext->outputUnitContext.audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &self.graphContext->commonFormat,
                                  &audioStreamBasicDescriptionSize);
    self.error = checkError(result, @"get hardware output stream format error");
    if (self.error) {
        return NO;
    }
    
    if (self.audioSession.sampleRate != self.graphContext->commonFormat.mSampleRate) {
        self.graphContext->commonFormat.mSampleRate = self.audioSession.sampleRate;
        result = AudioUnitSetProperty(self.graphContext->outputUnitContext.audioUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      0,
                                      &self.graphContext->commonFormat,
                                      audioStreamBasicDescriptionSize);
        self.error = checkError(result, @"set hardware output stream format error");
        if (self.error) {
            return NO ;
        }
    }
    
    result = AudioUnitSetProperty(self.graphContext->converterUnitContext.audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &self.graphContext->commonFormat,
                                  audioStreamBasicDescriptionSize);
    self.error = checkError(result, @"graph set converter input format error");
    if (self.error) {
        return NO;
    }
    
    result = AudioUnitSetProperty(self.graphContext->converterUnitContext.audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &self.graphContext->commonFormat,
                                  audioStreamBasicDescriptionSize);
    self.error = checkError(result, @"graph set converter output format error");
    if (self.error) {
        return NO;
    }
    
    result = AudioUnitSetProperty(self.graphContext->mixerUnitContext.audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &self.graphContext->commonFormat,
                                  audioStreamBasicDescriptionSize);
    self.error = checkError(result, @"graph set converter input format error");
    if (self.error) {
        return NO;
    }
    
    result = AudioUnitSetProperty(self.graphContext->mixerUnitContext.audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &self.graphContext->commonFormat,
                                  audioStreamBasicDescriptionSize);
    self.error = checkError(result, @"graph set converter output format error");
    if (self.error) {
        return NO;
    }
    
    result = AudioUnitSetProperty(self.graphContext->mixerUnitContext.audioUnit,
                                  kAudioUnitProperty_MaximumFramesPerSlice,
                                  kAudioUnitScope_Global,
                                  0,
                                  &max_frame_size,
                                  sizeof(max_frame_size));
    self.error = checkError(result, @"graph set mixer max frames per slice size error");
    if (self.error) {
        KKPlayerLog(@"%@",self.error.domain);
    }
    
    result = AUGraphInitialize(self.graphContext->graph);
    self.error = checkError(result, @"graph initialize error");
    if (self.error) {
        return NO;
    }
    
    return YES;
}

- (void)unregisterAudioSession{
    if (self.registered) {
        self.registered = NO;
        OSStatus result = AUGraphUninitialize(self.graphContext->graph);
        self.error = checkError(result, @"graph uninitialize error");
        if (self.error) {
            KKPlayerLog(@"%@",self.error.domain);
        }
        result = AUGraphClose(self.graphContext->graph);
        self.error = checkError(result, @"graph close error");
        if (self.error) {
            KKPlayerLog(@"%@",self.error.domain);
        }
        result = DisposeAUGraph(self.graphContext->graph);
        self.error = checkError(result, @"graph dispose error");
        if (self.error) {
            KKPlayerLog(@"%@",self.error.domain);
        }
        if (self.graphContext) {
            free(self.graphContext);
            self.graphContext = NULL;
        }
    }
}

#pragma mark -- 播放声音

static OSStatus renderCallback(void * inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inOutputBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData){
    KKAudioManager * manager = (__bridge KKAudioManager *)inRefCon;
    return [manager renderFrames:inNumberFrames ioData:ioData];
}

- (OSStatus)renderFrames:(UInt32)numberOfFrames ioData:(AudioBufferList *)ioData{
    if (!self.registered) {
        return noErr;
    }
    
    for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; iBuffer++) {
        memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);
    }
    
    if (self.playing && self.delegate){
        
        [self.delegate audioManager:self outputData:self->_renderBufferData numberOfFrames:numberOfFrames numberOfChannels:self.numberOfChannels];
        
        UInt32 numBytesPerSample = self.graphContext->commonFormat.mBitsPerChannel / 8;
        if (numBytesPerSample == 4) {
            float zero = 0.0;
            for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; iBuffer++) {
                int thisNumChannels = ioData->mBuffers[iBuffer].mNumberChannels;
                for (int iChannel = 0; iChannel < thisNumChannels; iChannel++) {
                    vDSP_vsadd(self->_renderBufferData + iChannel,
                               self.numberOfChannels,
                               &zero,
                               (float *)ioData->mBuffers[iBuffer].mData,
                               thisNumChannels,
                               numberOfFrames);
                }
            }
        }else if (numBytesPerSample == 2){
            float scale = (float)INT16_MAX;
            vDSP_vsmul(self->_renderBufferData, 1, &scale, self->_renderBufferData, 1, numberOfFrames * self.numberOfChannels);
            
            for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; iBuffer++) {
                int thisNumChannels = ioData->mBuffers[iBuffer].mNumberChannels;
                for (int iChannel = 0; iChannel < thisNumChannels; iChannel++) {
                    vDSP_vfix16(self->_renderBufferData + iChannel,
                                self.numberOfChannels,
                                (SInt16 *)ioData->mBuffers[iBuffer].mData + iChannel,
                                thisNumChannels,
                                numberOfFrames);
                }
            }
        }
    }
    
    return noErr;
}

#pragma mark -- 声音的播放暂停

- (void)play{
    if (!self->_playing) {
        if ([self registerAudioSession]) {
            OSStatus result = AUGraphStart(self.graphContext->graph);
            self.error = checkError(result, @"graph start error");
            if (self.error) {
                KKPlayerLog(@"%@",self.error.domain);
            } else {
                self->_playing = YES;
            }
        }
    }
}

- (void)pause{
    if (self->_playing) {
        OSStatus result = AUGraphStop(self.graphContext->graph);
        self.error = checkError(result, @"graph stop error");
        if (self.error) {
            KKPlayerLog(@"%@",self.error.domain);
        }
        self->_playing = NO;
    }
}

#pragma mark -- 中断、热插拔回调

- (void)setHandlerTarget:(id)handlerTarget
            interruption:(KKAudioManagerInterruptionHandler)interruptionHandler
             routeChange:(KKAudioManagerRouteChangeHandler)routeChangeHandler{
    self.handlerTarget = handlerTarget;
    self.interruptionHandler = interruptionHandler;
    self.routeChangeHandler = routeChangeHandler;
}

- (void)removeHandlerTarget:(id)handlerTarget{
    if (self.handlerTarget == handlerTarget || !self.handlerTarget) {
        self.handlerTarget = nil;
        self.interruptionHandler = nil;
        self.routeChangeHandler = nil;
    }
}

#pragma mark -- 系统回调通知

- (void)audioSessionInterruptionHandler:(NSNotification *)notification{
    if (self.handlerTarget && self.interruptionHandler) {
        AVAudioSessionInterruptionType avType = [[notification.userInfo objectForKey:AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
        KKAudioManagerInterruptionType type = KKAudioManagerInterruptionTypeBegin;
        if (avType == AVAudioSessionInterruptionTypeEnded) {
            type = KKAudioManagerInterruptionTypeEnded;
        }
        KKAudioManagerInterruptionOption option = KKAudioManagerInterruptionOptionNone;
        id avOption = [notification.userInfo objectForKey:AVAudioSessionInterruptionOptionKey];
        if (avOption) {
            AVAudioSessionInterruptionOptions temp = [avOption unsignedIntegerValue];
            if (temp == AVAudioSessionInterruptionOptionShouldResume) {
                option = KKAudioManagerInterruptionOptionShouldResume;
            }
        }
        self.interruptionHandler(self.handlerTarget, self, type, option);
    }
}

- (void)audioSessionRouteChangeHandler:(NSNotification *)notification{
    if (self.handlerTarget && self.routeChangeHandler) {
        AVAudioSessionRouteChangeReason avReason = [[notification.userInfo objectForKey:AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
        switch (avReason) {
            case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:{
                self.routeChangeHandler(self.handlerTarget, self, KKAudioManagerRouteChangeReasonOldDeviceUnavailable);
            }
                break;
            default:
                break;
        }
        
    }
}

#pragma mark -- @property getter & setter

- (float)volume{
    if (self.registered) {
        AudioUnitParameterID param = kMultiChannelMixerParam_Volume;
        AudioUnitParameterValue volume;
        OSStatus result = AudioUnitGetParameter(self.graphContext->mixerUnitContext.audioUnit,
                                                param,
                                                kAudioUnitScope_Input,
                                                0,
                                                &volume);
        self.error = checkError(result, @"graph get mixer volum error");
        if (self.error) {
            KKPlayerLog(@"%@",self.error.domain);
        } else {
            return volume;
        }
    }
    return 1.f;
}

- (void)setVolume:(float)volume{
    if (self.registered) {
        OSStatus result = AudioUnitSetParameter(self.graphContext->mixerUnitContext.audioUnit,
                                                kMultiChannelMixerParam_Volume,
                                                kAudioUnitScope_Input,
                                                0,
                                                volume,
                                                0);
        self.error = checkError(result, @"graph set mixer volum error");
        if (self.error) {
            KKPlayerLog(@"%@",self.error.domain);
        }
    }
}

- (Float64)samplingRate{
    if (!self.registered) {
        return 0;
    }
    Float64 number = self.graphContext->commonFormat.mSampleRate;
    if (number > 0) {
        return number;
    }
    return (Float64)self.audioSession.sampleRate;
}

- (UInt32)numberOfChannels{
    if (!self.registered) {
        return 0;
    }
    UInt32 number = self.graphContext->commonFormat.mChannelsPerFrame;
    if (number > 0) {
        return number;
    }
    return (UInt32)self.audioSession.outputNumberOfChannels;
}

#pragma mark --错误处理

static NSError *checkError(OSStatus result, NSString *domain){
    if (result == noErr) return nil;
    NSError * error = [NSError errorWithDomain:domain code:result userInfo:nil];
    return error;
}

@end
