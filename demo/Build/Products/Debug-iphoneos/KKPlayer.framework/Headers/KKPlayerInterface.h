//
//  KKPlayerInterface.h
//  KKPlayer
//
//  Created by finger on 16/6/28.
//  Copyright © 2016年 finger. All rights reserved.
//

//1、自动根据视频的类型(判断文件的后缀名)选择相应的解码器，如果是MP3、MP4、mov类型，则使用avplayer解码，其他则使用ffmpeg解码，如果avplayer解码失败，则自动切换至ffmpeg解码
//2、avplayer解码时会默认使用硬件加速，在使用ffmpeg解码时，如果编码格式是h264，则使用videoToolbox解码实现硬件加速，videoToolbox解码的原始音视频数据来自ffmpeg
//3、渲染方式:avplayer解码时，一般类型的视频使用系统自带的渲染方式，vr类型的视频，使用opengl渲染，使用avplayer播放vr类型的数据时，渲染的数据通过AVPlayerItemVideoOutput获得，具体实现可查看KKAVPlayer类，ffmpeg解码时，不管是一般类型的视频还是vr格式的视频，统一使用opengl es渲染
//4、ffmpeg解码、opengl渲染流程:
//   ffmpeg解码初始化时开启两个线程，一个线程负责从视频源读取音视频数据AVPacket并放入到视频解码器和音频解码器中，一个线程负责解码视频的AVPacket并封装成KKVideoFrame帧，且将KKVideoFrame压入视频解码帧队列中。音频实时解码，对于添加到音频解码器中的AVPacket立即进行解码，并将解码后的音频帧添加到帧队列中。
//   绘制使用GLKView，GLKView的GLKViewDelegate在绘制期间不断的调用，在GLKViewDelegate中从视频解码器的解码帧队列中获取已经解码的视频帧。因此，在GLKViewDelegate中需要完成以下工作:
//    1、获取原始的视频帧数据
//    2、根据视频帧数据生成opengl的纹理图
//    3、将opengl的顶点坐标、纹理坐标、投影矩阵传入opengl的渲染管道并完成一幅视频帧的绘制
//
// 5、声音的播放:
//    5.1、使用AVPlayer播放视频时，音频的播放由AVPlayer管理，程序不需要做任何处理
//    5.2、使用FFmpeg播放时，音频使用AudioUnit播放，详见KKAudioManager
//
//
// 6、程序中各个类解释:
//
// KKPlayerInterface:播放器对外提供的接口类，本身不做解码和渲染工作
//
// KKAVPlayer:对AVPlayer的封装，可通过AVPlayerItemVideoOutput对外提供视频帧数据，如将视频帧的数据提供给opengl绘制
//
// KKFFVideoToolBox:对VideoToolbox的封装，h264编码格式的视频，使用VideoToolbox解码
//
// KKAudioManager:对Audio Unit的封装，使用ffmpeg解码时，声音的播放由Audio Unit完成
//
// KKFFPlayer:ffmpeg解码时声音、音视频解码器的管理，对解码的流程进行控制
//
// KKFFFramePool、KKFFFrameQueue、KKFFPacketQueue:
// KKFFFramePool--帧的重用池，避免重复创建，节省内存，提高效率
// KKFFFrameQueue--解码后的音视频帧可以存放在该队列中
// KKFFPacketQueue--从视频源读取的AVPacket包可以存储在该队列中
//
// KKFFDecoder:对KKFFFormatContext、KKFFAudioDecoder和KKFFVideoDecoder的管理，KKFFAudioDecoder是音频解码，KKFFVideoDecoder是视频解码
//
//KKRenderView:视频画面的渲染，它不负责渲染，是渲染图层的容器(父视图)，真正负责渲染的是KKGLViewController和AVPlayerLayer，可根据实际情况选择合适的渲染方式。关于KKRenderView的视频数据的获取和渲染图层的选择问题:
//    1、数据的获取，在KKRenderView中声明了两个代理，分别为KKRenderFFmpegDelegate和KKRenderAVPlayerDelegate，使用AVPlayer播放vr视频时从KKRenderAVPlayerDelegate中获取数据，使用ffmpeg解码时从KKRenderFFmpegDelegate中获取数据。这两个代理分别在KkAVPlayer的prepareVideoForceRenderWithGL和KKFFPlayer的prepareVideo中初始化，同时还设定了KKRenderView的解码方式（decodeType），渲染的时候，根据decodeType从相应的代理中获取数据。
//    2、KKRenderView加载哪种渲染图层是通过设置其renderViewType属性来实现的，具体的加载方式可查看该属性的setter方法。
//
// KKGLDrawTool:对opengl绘制流程的细分，对opengl的顶点和纹理坐标、纹理图等进行管理
//
// KKVrViewMatrix:播放VR类型的视频，对投影矩阵实时更新，达到从不同角度观看影片的效果


#import "KKPlayerTrack.h"
#import <UIKit/UIKit.h>

//视频类型 正常 VR
typedef NS_ENUM(NSUInteger, KKVideoType) {
    KKVideoTypeNormal,
    KKVideoTypeVR,
};

//渲染图层的类型
typedef NS_ENUM(NSUInteger,KKRenderViewType) {
    KKRenderViewTypeEmpty,
    KKRenderViewTypeAVPlayerLayer,//AVplayer
    KKRenderViewTypeGLKView,//ffmpeg,videoToolbox
};

//解码方式
typedef NS_ENUM(NSUInteger, KKDecoderType) {
    KKDecoderTypeError,
    KKDecoderTypeAVPlayer,
    KKDecoderTypeFFmpeg,
    KKDecoderTypeEmpty,
};

//显示方式
typedef NS_ENUM(NSUInteger, KKDisplayType) {
    KKDisplayTypeNormal,//正常的视频画面
    KKDisplayTypeVRBox,//vr盒子
};

//播放器状态
typedef NS_ENUM(NSUInteger, KKPlayerState) {
    KKPlayerStateNone = 0,
    KKPlayerStateBuffering = 1,
    KKPlayerStateReadyToPlay = 2,
    KKPlayerStatePlaying = 3,
    KKPlayerStateSuspend = 4,
    KKPlayerStateFinished = 5,
    KKPlayerStateFailed = 6,
    KKPlayerStateSeeking = 7,
};

//视频填充模式
typedef NS_ENUM(NSUInteger, KKGravityMode) {
    KKGravityModeResize,
    KKGravityModeResizeAspect,
    KKGravityModeResizeAspectFill,
};

//后台模式
typedef NS_ENUM(NSUInteger, KKPlayerBackgroundMode) {
    KKPlayerBackgroundModeNothing,
    KKPlayerBackgroundModeAutoPlayAndPause,
    KKPlayerBackgroundModeContinue,
};

//文件格式
typedef NS_ENUM(NSUInteger, KKMediaFormat) {
    KKMediaFormatError,
    KKMediaFormatUnknown,
    KKMediaFormatMP3,
    KKMediaFormatMPEG4,
    KKMediaFormatMOV,
    KKMediaFormatFLV,
    KKMediaFormatM3U8,
    KKMediaFormatRTMP,
    KKMediaFormatRTSP,
};

#pragma mark - KKPlayer

NS_ASSUME_NONNULL_BEGIN

@interface KKPlayerInterface : NSObject
@property(nonatomic,copy,readonly)NSURL *contentURL;
@property(nonatomic,assign,readonly)KKVideoType videoType;
@property(nonatomic,assign,readonly)KKDecoderType decoderType;
@property(nonatomic,assign,readonly)KKMediaFormat mediaFormat;
@property(nonatomic,assign,readonly)KKDisplayType displayType;
@property(nonatomic,assign,readonly)KKGravityMode viewGravityMode;
@property(nonatomic,assign,readonly)KKPlayerBackgroundMode backgroundMode;

//视频渲染视图
@property(nonatomic,strong,readonly)UIView *videoRenderView;
@property(nonatomic,copy)void(^viewTapAction)(KKPlayerInterface *player, UIView *view);

//播放相关
@property(nonatomic,assign,readonly)KKPlayerState state;
@property(nonatomic,assign,readonly)CGSize presentationSize;
@property(nonatomic,assign,readonly)NSTimeInterval bitrate;
@property(nonatomic,assign,readonly)NSTimeInterval progress;
@property(nonatomic,assign,readonly)NSTimeInterval duration;
@property(nonatomic,assign,readonly)NSTimeInterval playableTime;
@property(nonatomic,assign)NSTimeInterval playableBufferInterval;//最小缓冲时长
@property(nonatomic,assign)CGFloat volume;

@property(nonatomic,assign,readonly)BOOL seekEnable;
@property(nonatomic,assign,readonly)BOOL seeking;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)player;

//播放器初始化
- (void)preparePlayerWithURL:(nullable NSURL *)contentURL
                   videoType:(KKVideoType)videoType
                 displayType:(KKDisplayType)displayType;

//如果使用avplayer播放失败，则使用ffmpeg解码
- (void)switchDecoderToFFmpeg;

//播放控制
- (void)play;
- (void)pause;
- (void)stop;
- (void)seekToTime:(NSTimeInterval)time;
- (void)seekToTime:(NSTimeInterval)time completeHandler:(nullable void(^)(BOOL finished))completeHandler;

//截屏
- (UIImage *)snapshot;

@end


#pragma mark -- 音视频轨 Category

@interface KKPlayerInterface(Tracks)

@property(nonatomic,assign,readonly)BOOL videoEnable;
@property(nonatomic,assign,readonly)BOOL audioEnable;

@property(nonatomic,strong,readonly)KKPlayerTrack *videoTrack;
@property(nonatomic,strong,readonly)KKPlayerTrack *audioTrack;

@property(nonatomic,strong,readonly)NSArray<KKPlayerTrack *> *videoTracks;
@property(nonatomic,strong,readonly)NSArray<KKPlayerTrack *> *audioTracks;

@end


#pragma mark -- 解码线程 Category

@interface KKPlayerInterface(Thread)
@property(nonatomic,assign,readonly)BOOL videoDecodeOnMainThread;
@property(nonatomic,assign,readonly)BOOL audioDecodeOnMainThread;
@end

#pragma mark -- 播放器状态回调

@protocol KKPlayerStateDelegate <NSObject>
@optional
- (void)stateChange:(KKPlayerInterface *)interface preState:(KKPlayerState)preState state:(KKPlayerState)state;
- (void)progressChange:(KKPlayerInterface *)interface percent:(CGFloat)percent currentTime:(CGFloat)currentTime totalTime:(CGFloat)totalTime;
- (void)playableChange:(KKPlayerInterface *)interface percent:(CGFloat)percent currentTime:(CGFloat)currentTime totalTime:(CGFloat)totalTime;
- (void)playerError:(KKPlayerInterface *)interface error:(NSError *)error;
@end

typedef void(^stateChangeBlock)(KKPlayerInterface *interface,KKPlayerState preState ,KKPlayerState state);
typedef void(^progressChangeBlock)(KKPlayerInterface *interface,CGFloat percent,CGFloat currentTime,CGFloat totalTime);
typedef void(^playableChangeBlock)(KKPlayerInterface *interface,CGFloat percent,CGFloat currentTime,CGFloat totalTime);
typedef void(^errorBlock)(KKPlayerInterface *interface,NSError *error);

@interface KKPlayerInterface(KKPlayerState)
@property(nonatomic,weak)id<KKPlayerStateDelegate>playerStateDelegate;
@property(nonatomic,copy)stateChangeBlock stateChangeBlock;
@property(nonatomic,copy)progressChangeBlock progressChangeBlock;
@property(nonatomic,copy)playableChangeBlock playableChangeBlock;
@property(nonatomic,copy)errorBlock errorBlock;
- (void)playerStateChangeBlock:(stateChangeBlock)stateChangeBlock progressChangeBlock:(progressChangeBlock)progressChangeBlock playableChangeBlock:(playableChangeBlock)playableChangeBlock errorBlock:(errorBlock)errorBlock;
@end

NS_ASSUME_NONNULL_END
