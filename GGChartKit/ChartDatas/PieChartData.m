//
//  PieChartData.m
//  HSCharts
//
//  Created by 黄舜 on 17/6/9.
//  Copyright © 2017年 I really is a farmer. All rights reserved.
//

#import "PieChartData.h"

@implementation PieChartData

+ (void)pieAry:(NSArray <PieChartData *>*)ary enumerateObjectsUsingBlock:(void(^)(CGFloat arc, CGFloat transArc, PieChartData * data, NSUInteger idx))usingBlock
{
    __block CGFloat sum = 0;
    
    [ary enumerateObjectsUsingBlock:^(PieChartData * obj, NSUInteger idx, BOOL * stop) {
        
        sum += obj.pieData.floatValue;
    }];
    
    __block CGFloat layer_arc = 0;
    
    [ary enumerateObjectsUsingBlock:^(PieChartData * obj, NSUInteger idx, BOOL * stop) {
        
        CGFloat arc = obj.pieData.floatValue / sum * M_PI * 2;
        layer_arc = layer_arc + arc;
        
        // 数据从12点方向出现
        if (usingBlock) { usingBlock(arc, M_PI * 2 - layer_arc - M_PI_2, obj, idx); }
    }];
}

@end