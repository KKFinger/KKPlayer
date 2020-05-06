//
//  KKPlayer.h
//  KKPlayer
//
//  Created by finger on 2017/3/9.
//  Copyright © 2017年 finger. All rights reserved.
//


//public类型的头文件只能引入public类型的头文件，否则会提示头文件找不到
//.m文件引入头文件没有限制

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double KKPlayerVersionNumber;
FOUNDATION_EXPORT const unsigned char KKPlayerVersionString[];

#import <KKPlayer/KKPlayerInterface.h>
#import <KKPlayer/KKPlayerTrack.h>
