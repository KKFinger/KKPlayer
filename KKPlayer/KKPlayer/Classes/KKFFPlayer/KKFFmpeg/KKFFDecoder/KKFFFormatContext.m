//
//  KKFFFormatContext.m
//  KKPlayer
//
//  Created by finger on 2017/2/17.
//  Copyright © 2017年 finger. All rights reserved.
//

#import "KKFFFormatContext.h"
#import "KKTools.h"

static int ffmpegInterruptCallback(void *ctx){
    KKFFFormatContext *obj = (__bridge KKFFFormatContext *)ctx;
    if(obj.delegate && [obj.delegate respondsToSelector:@selector(formatContextNeedInterrupt:)]){
        return [obj.delegate formatContextNeedInterrupt:obj];
    }
    return 0;
}

@interface KKFFFormatContext ()
@property(nonatomic,copy)NSURL *contentURL;
@property(nonatomic,copy)NSError *error;
@property(nonatomic,copy)NSDictionary *metadata;
@property(nonatomic,assign)NSTimeInterval videoTimebase;
@property(nonatomic,assign)NSTimeInterval videoFPS;
@property(nonatomic,copy)NSString *videoFormat;
@property(nonatomic,assign)CGSize videoPresentationSize;
@property(nonatomic,assign)CGFloat videoAspect;
@property(nonatomic,assign)NSTimeInterval audioTimebase;

@property(nonatomic,copy)NSDictionary *formatContextOptions;
@property(nonatomic,copy)NSDictionary *codecContextOptions;

@property(nonatomic,assign)BOOL videoEnable;
@property(nonatomic,assign)BOOL audioEnable;

@property(nonatomic,strong)KKFFTrack *videoTrack;
@property(nonatomic,strong)KKFFTrack *audioTrack;
@property(nonatomic,strong)NSArray<KKFFTrack *> *videoTracks;
@property(nonatomic,strong)NSArray<KKFFTrack *> *audioTracks;

@end

@implementation KKFFFormatContext

+ (instancetype)formatContextWithContentURL:(NSURL *)contentURL
                       formatContextOptions:(NSDictionary *)formatContextOptions
                        codecContextOptions:(NSDictionary *)codecContextOptions
                                   delegate:(id<KKFFFormatContextDelegate>)delegate{
    return [[self alloc] initWithContentURL:contentURL
                       formatContextOptions:formatContextOptions
                        codecContextOptions:(NSDictionary *)codecContextOptions
                                   delegate:delegate];
}

- (instancetype)initWithContentURL:(NSURL *)contentURL
              formatContextOptions:(NSDictionary *)formatContextOptions
               codecContextOptions:(NSDictionary *)codecContextOptions
                          delegate:(id<KKFFFormatContextDelegate>)delegate{
    if (self = [super init]){
        self.contentURL = contentURL;
        self.formatContextOptions = formatContextOptions;
        self.codecContextOptions = codecContextOptions;
        self.delegate = delegate;
    }
    return self;
}

- (void)dealloc{
    [self destroy];
    KKPlayerLog(@"KKFFFormatContext release");
}

#pragma mark -- 销毁解码资源

- (void)destroy{
    [self destroyVideo];
    [self destroyAudio];
    if (formatContext){
        avformat_close_input(&formatContext);
        formatContext = NULL;
    }
}

- (void)destroyAudio{
    self.audioEnable = NO;
    self.audioTrack = nil;
    self.audioTracks = nil;
    if (audioCodecContext){
        avcodec_close(audioCodecContext);
        audioCodecContext = NULL;
    }
}

- (void)destroyVideo{
    self.videoEnable = NO;
    self.videoTrack = nil;
    self.videoTracks = nil;
    if (videoCodecContext){
        avcodec_close(videoCodecContext);
        videoCodecContext = NULL;
    }
}

#pragma mark -- 打开文件流

- (void)openFileStream{
    self.error = [self openStream];
    if (self.error){
        return;
    }
    
    [self fetchAVTracks];
    
    NSError *videoError = [self setupVideoCodec];
    NSError *audioError = [self setupAudioCodec];
    
    if (videoError && audioError){
        if (videoError.code == KKFFDecoderErrorCodeStreamNotFound && audioError.code != KKFFDecoderErrorCodeStreamNotFound){
            self.error = videoError;
        }else{
            self.error = audioError;
        }
    }
}

- (NSError *)openStream{
    int reslut = 0;
    NSError * error = nil;
    
    formatContext = avformat_alloc_context();
    if (!formatContext){
        reslut = -1;
        error = [NSError errorWithDomain:@"KKFFDecoderErrorCodeFormatCreate error" code:KKFFDecoderErrorCodeFormatCreate userInfo:nil];
        return error;
    }
    
    formatContext->interrupt_callback.callback = ffmpegInterruptCallback;
    formatContext->interrupt_callback.opaque = (__bridge void *)self;
    
    AVDictionary *options = KKFFNSDictionaryToAVDictionary(self.formatContextOptions);
    
    //options filter.
    NSString *URLString = [self contentURLString];
    NSString *lowercaseURLString = [URLString lowercaseString];
    if ([lowercaseURLString hasPrefix:@"rtmp"] ||
        [lowercaseURLString hasPrefix:@"rtsp"]) {
        av_dict_set(&options, "timeout", NULL, 0);
    }
    
    reslut = avformat_open_input(&formatContext, URLString.UTF8String, NULL, &options);
    if (options) {
        av_dict_free(&options);
    }
    error = KKFFCheckErrorCode(reslut, KKFFDecoderErrorCodeFormatOpenInput);
    if (error || !formatContext){
        if (formatContext){
            avformat_free_context(formatContext);
            formatContext = NULL;
        }
        return error;
    }
    
    reslut = avformat_find_stream_info(formatContext, NULL);
    error = KKFFCheckErrorCode(reslut, KKFFDecoderErrorCodeFormatFindStreamInfo);
    if (error || !formatContext){
        if (formatContext){
            avformat_close_input(&formatContext);
            formatContext = NULL;
        }
        return error;
    }
    self.metadata = KKFFAVDictionaryToNSDictionary(formatContext->metadata);
    
    return error;
}

#pragma mark -- 提取音视频轨道信息

- (void)fetchAVTracks{
    NSMutableArray<KKFFTrack *> *videoTracks = [NSMutableArray array];
    NSMutableArray<KKFFTrack *> *audioTracks = [NSMutableArray array];
    
    for (int i = 0; i < formatContext->nb_streams; i ++){
        AVStream *stream = formatContext->streams[i];
        switch (stream->codecpar->codec_type){
            case AVMEDIA_TYPE_VIDEO:{
                KKFFTrack *track = [[KKFFTrack alloc] init];
                track.type = KKFFTrackTypeVideo;
                track.index = i;
                track.metadata = [KKFFMetadata metadataWithAVDictionary:stream->metadata];
                [videoTracks addObject:track];
            }
                break;
            case AVMEDIA_TYPE_AUDIO:{
                KKFFTrack * track = [[KKFFTrack alloc] init];
                track.type = KKFFTrackTypeAudio;
                track.index = i;
                track.metadata = [KKFFMetadata metadataWithAVDictionary:stream->metadata];
                [audioTracks addObject:track];
            }
                break;
            default:
                break;
        }
    }
    
    if (videoTracks.count > 0){
        self.videoTracks = videoTracks;
    }
    if (audioTracks.count > 0){
        self.audioTracks = audioTracks;
    }
}

#pragma mark -- 初始化音视频解码器

- (NSError *)setupVideoCodec{
    NSError * error = nil;
    if (self.videoTracks.count > 0){
        for (KKFFTrack *obj in self.videoTracks){
            int index = obj.index;
            if ((formatContext->streams[index]->disposition & AV_DISPOSITION_ATTACHED_PIC) == 0){
                AVCodecContext *codec_context;
                error = [self openStreamWithTrackIndex:index codecContext:&codec_context domain:@"video"];
                if (!error){
                    self.videoTrack = obj;
                    self.videoEnable = YES;
                    self.videoTimebase = KKFFStreamGetTimebase(formatContext->streams[index], 0.00004);
                    self.videoFPS = KKFFStreamGetFPS(formatContext->streams[index], self.videoTimebase);
                    self.videoPresentationSize = CGSizeMake(codec_context->width, codec_context->height);
                    self.videoAspect = (CGFloat)codec_context->width / (CGFloat)codec_context->height;
                    self->videoCodecContext = codec_context;
                    break;
                }
            }
        }
    }else{
        error = [NSError errorWithDomain:@"video stream not found" code:KKFFDecoderErrorCodeStreamNotFound userInfo:nil];
        return error;
    }
    
    return error;
}

- (NSError *)setupAudioCodec{
    NSError * error = nil;
    if (self.audioTracks.count > 0){
        for (KKFFTrack * obj in self.audioTracks){
            int index = obj.index;
            AVCodecContext *codec_context;
            error = [self openStreamWithTrackIndex:index codecContext:&codec_context domain:@"audio"];
            if (!error){
                self.audioTrack = obj;
                self.audioEnable = YES;
                self.audioTimebase = KKFFStreamGetTimebase(formatContext->streams[index], 0.000025);
                self->audioCodecContext = codec_context;
                break;
            }
        }
    }else{
        error = [NSError errorWithDomain:@"audio stream not found" code:KKFFDecoderErrorCodeStreamNotFound userInfo:nil];
        return error;
    }
    
    return error;
}

- (NSError *)openStreamWithTrackIndex:(int)trackIndex codecContext:(AVCodecContext **)codecContext domain:(NSString *)domain{
    int result = 0;
    NSError *error = nil;
    AVStream *stream = formatContext->streams[trackIndex];
    AVCodecContext *codec_context = avcodec_alloc_context3(NULL);
    if (!codec_context){
        error = [NSError errorWithDomain:[NSString stringWithFormat:@"%@ codec context create error", domain]
                                    code:KKFFDecoderErrorCodeCodecContextCreate
                                userInfo:nil];
        return error;
    }
    
    result = avcodec_parameters_to_context(codec_context, stream->codecpar);
    error = KKFFCheckErrorCode(result, KKFFDecoderErrorCodeCodecContextSetParam);
    if (error){
        avcodec_free_context(&codec_context);
        return error;
    }
    
    av_codec_set_pkt_timebase(codec_context, stream->time_base);
    
    AVCodec *codec = avcodec_find_decoder(codec_context->codec_id);
    if (!codec){
        avcodec_free_context(&codec_context);
        error = [NSError errorWithDomain:[NSString stringWithFormat:@"%@ codec not found decoder", domain]
                                    code:KKFFDecoderErrorCodeCodecFindDecoder
                                userInfo:nil];
        return error;
    }
    codec_context->codec_id = codec->id;
    
    AVDictionary *options = KKFFNSDictionaryToAVDictionary(self.codecContextOptions);
    if (!av_dict_get(options, "threads", NULL, 0)) {
        av_dict_set(&options, "threads", "auto", 0);
    }
    if (codec_context->codec_type == AVMEDIA_TYPE_VIDEO ||
        codec_context->codec_type == AVMEDIA_TYPE_AUDIO) {
        av_dict_set(&options, "refcounted_frames", "1", 0);
    }
    result = avcodec_open2(codec_context, codec, &options);
    error = KKFFCheckErrorCode(result, KKFFDecoderErrorCodeCodecOpen2);
    if (error){
        avcodec_free_context(&codec_context);
        return error;
    }
    
    *codecContext = codec_context;
    
    return error;
}

#pragma mark -- 文件seek

- (void)seekFileWithSecond:(NSTimeInterval)second{
    int64_t ts = second * AV_TIME_BASE;
    av_seek_frame(self->formatContext, -1, ts, AVSEEK_FLAG_BACKWARD);
}

- (BOOL)seekEnable{
    if (!self->formatContext) return NO;
    BOOL ioSeekAble = YES;
    if (self->formatContext->pb) {
        ioSeekAble = self->formatContext->pb->seekable;
    }
    if (ioSeekAble && self.duration > 0) {
        return YES;
    }
    return NO;
}

#pragma mark -- 读取视频帧

- (int)readFrame:(AVPacket *)packet{
    return av_read_frame(self->formatContext, packet);
}

#pragma mark -- 视频相关信息

- (NSTimeInterval)duration{
    if (!self->formatContext) return 0;
    int64_t duration = self->formatContext->duration;//duration的单位是微秒，1秒=1000毫秒=1000000微秒
    if (duration < 0) {
        return 0;
    }
    return (NSTimeInterval)duration / AV_TIME_BASE;
}

- (NSTimeInterval)bitrate{
    if (!self->formatContext) return 0;
    return (self->formatContext->bit_rate / 1000.0f);//AVFormatContext中的bit_rate单位为bps，转换成kbps需要除以1000
}

- (NSString *)contentURLString{
    if ([self.contentURL isFileURL]){
        return [self.contentURL path];
    }else{
        return [self.contentURL absoluteString];
    }
}

- (KKFFVideoFrameRotateType)videoFrameRotateType{
    int rotate = [[self.videoTrack.metadata.metadata objectForKey:@"rotate"] intValue];
    if (rotate == 90) {
        return KKFFVideoFrameRotateType90;
    } else if (rotate == 180) {
        return KKFFVideoFrameRotateType180;
    } else if (rotate == 270) {
        return KKFFVideoFrameRotateType270;
    }
    return KKFFVideoFrameRotateType0;
}

- (NSString *)videoFormat{
    const char *formatName = self->formatContext->iformat->name;
    if (!formatName) {
        return @"";
    }
    return [NSString stringWithCString:formatName encoding:NSUTF8StringEncoding];
}

@end
