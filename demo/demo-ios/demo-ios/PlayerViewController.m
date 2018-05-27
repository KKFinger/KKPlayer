//
//  PlayerViewController.m
//  demo-ios
//
//  Created by finger on 2017/3/15.
//  Copyright © 2017年 finger. All rights reserved.
//

#import "PlayerViewController.h"
#import <KKPlayer/KKPlayer.h>

@interface PlayerViewController ()
@property(nonatomic,strong)KKPlayerInterface *player;
@property(weak,nonatomic)IBOutlet UILabel *stateLabel;
@property(weak,nonatomic)IBOutlet UISlider *progressSilder;
@property(weak,nonatomic)IBOutlet UILabel *currentTimeLabel;
@property(weak,nonatomic)IBOutlet UILabel *totalTimeLabel;
@property(nonatomic,assign)BOOL progressSilderTouching;
@end

@implementation PlayerViewController

- (void)viewDidLoad{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    
    self.player = [KKPlayerInterface player];
    
    __weak typeof(self)weakSelf = self;
    [self.player playerStateChangeBlock:^(KKPlayerInterface *interface, KKPlayerState preState, KKPlayerState state) {
        __strong typeof(weakSelf)strongSelf = weakSelf;
        NSString * text;
        switch (state) {
            case KKPlayerStateNone:
                text = @"None";
                break;
            case KKPlayerStateBuffering:
                text = @"Buffering...";
                break;
            case KKPlayerStateReadyToPlay:
                text = @"Prepare";
                strongSelf.totalTimeLabel.text = [strongSelf timeStringFromSeconds:strongSelf.player.duration];
                [strongSelf.player play];
                break;
            case KKPlayerStatePlaying:
                text = @"Playing";
                break;
            case KKPlayerStateSuspend:
                text = @"Suspend";
                break;
            case KKPlayerStateFinished:
                text = @"Finished";
                break;
            case KKPlayerStateFailed:
                text = @"Error";
                break;
            case KKPlayerStateSeeking:
                text = @"seeking";
                break ;
        }
        strongSelf.stateLabel.text = text;
    } progressChangeBlock:^(KKPlayerInterface *interface, CGFloat percent, CGFloat currentTime, CGFloat totalTime) {
        __strong typeof(weakSelf)strongSelf = weakSelf;
        if (!strongSelf.progressSilderTouching) {
            strongSelf.progressSilder.value = percent;
        }
        strongSelf.currentTimeLabel.text = [strongSelf timeStringFromSeconds:currentTime];
    } playableChangeBlock:^(KKPlayerInterface *interface, CGFloat percent, CGFloat currentTime, CGFloat totalTime) {
        //NSLog(@"playable time : %f", currentTime);
    } errorBlock:^(KKPlayerInterface *interface, NSError *error) {
        NSLog(@"player did error : %@", error);
    }];
    [self.player setViewTapAction:^(KKPlayerInterface * _Nonnull player, UIView * _Nonnull view) {
        NSLog(@"player display view did click!");
    }];
    [self.view insertSubview:self.player.videoRenderView atIndex:0];
    
    //NSURL * normalVideo = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"The Three Diablos" ofType:@"avi"]];
    //NSURL *normalVideo = [NSURL URLWithString:@"https://aweme.snssdk.com/aweme/v1/play/?video_id=v0200f190000bc24btrrh3p0ipf27v20&line=0&app_id=13"];
    NSURL * normalVideo = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"i-see-fire" ofType:@"mp4"]];
    [self.player preparePlayerWithURL:normalVideo videoType:KKVideoTypeNormal displayType:KKDisplayTypeNormal];
    
//    NSURL * vrVideo = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"google-help-vr" ofType:@"mp4"]];
//    [self.player preparePlayerWithURL:vrVideo videoType:KKVideoTypeVR displayType:KKDisplayTypeVRBox];
    //[self.player preparePlayerWithURL:vrVideo videoType:KKVideoTypeVR displayType:KKDisplayTypeVRBox];
}

- (void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    self.player.videoRenderView.frame = self.view.bounds;
}

- (IBAction)back:(id)sender{
    [self.navigationController popViewControllerAnimated:YES];
}

- (IBAction)play:(id)sender{
    [self.player play];
}

- (IBAction)pause:(id)sender{
    [self.player pause];
}

- (IBAction)progressTouchDown:(id)sender{
    self.progressSilderTouching = YES;
}

- (IBAction)progressTouchUp:(id)sender{
    self.progressSilderTouching = NO;
    [self.player seekToTime:self.player.duration * self.progressSilder.value];
}

- (NSString *)timeStringFromSeconds:(CGFloat)seconds{
    return [NSString stringWithFormat:@"%ld:%.2ld", (long)seconds / 60, (long)seconds % 60];
}

@end
