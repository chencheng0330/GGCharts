//
//  InnerLable.m
//  GGCharts
//
//  Created by 黄舜 on 17/9/20.
//  Copyright © 2017年 I really is a farmer. All rights reserved.
//

#import "InnerLable.h"
#import "PieInnerLableAbstract.h"

@interface InnerLable ()

@end

@implementation InnerLable

/**
 * 初始化方法
 */
- (instancetype)init
{
    self = [super init];
    
    if (self) {
        
        _lableFont = [UIFont systemFontOfSize:9];
        _lableColor = [UIColor blackColor];
        _stringFormat = @"%.2f";
        _stringRatio = CGPointMake(-.5f, -.5f);
        _stringOffSet = CGSizeZero;
    }
    
    return self;
}

- (void)setStringRatio:(CGPoint)stringRatio
{
    _stringRatio = stringRatio;
    
    if (stringRatio.x < -1 || stringRatio.x > 1) {
        
        _stringRatio.x = stringRatio.x > 0 ? 1 : -1;
    }
    
    if (stringRatio.y < -1 || stringRatio.y > 1) {
        
        _stringRatio.y = stringRatio.y > 0 ? 1 : -1;
    }
}

@end