//
//  KKGLViewController.h
//  KKPlayer
//
//  Created by finger on 2017/3/27.
//  Copyright © 2017年 finger. All rights reserved.
//

#import "KKRenderView.h"

@interface KKGLViewController:GLKViewController
+ (instancetype)viewControllerWithRenderView:(KKRenderView *)renderView;
- (void)reloadViewport:(CGRect)frame;
- (UIImage *)snapshot;
- (GLKView *)glkView;
@end
