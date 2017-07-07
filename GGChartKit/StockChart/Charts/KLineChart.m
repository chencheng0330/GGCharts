//
//  KLineChart.m
//  GGCharts
//
//  Created by 黄舜 on 17/7/4.
//  Copyright © 2017年 I really is a farmer. All rights reserved.
//

#import "KLineChart.h"
#import "GGChartDefine.h"
#import "NSArray+Stock.h"
#import "CrissCrossQueryView.h"
#import "MALayer.h"

#define FONT_ARIAL	@"ArialMT"

@interface KLineChart () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) DKLineScaler * kLineScaler;   ///< 定标器

@property (nonatomic, strong) CAShapeLayer * greenLineLayer;    ///< 绿色k线
@property (nonatomic, strong) CAShapeLayer * redLineLayer;      ///< 红色K线

@property (nonatomic, strong) GGGridRenderer * kLineGrid;       ///< k线网格渲染器
@property (nonatomic, strong) GGGridRenderer * volumGrid;       ///< k线网格渲染器

@property (nonatomic, strong) GGAxisRenderer * axisRenderer;        ///< 轴渲染
@property (nonatomic, strong) GGAxisRenderer * kAxisRenderer;       ///< K线轴
@property (nonatomic, strong) GGAxisRenderer * vAxisRenderer;       ///< 成交量轴

@property (nonatomic, strong) CrissCrossQueryView * queryPriceView;     ///< 查价层

#pragma mark - 缩放手势

@property (nonatomic, assign) CGFloat currentZoom;  ///< 当前缩放比例
@property (nonatomic, assign) CGFloat zoomCenterSpacingLeft;    ///< 缩放中心K线位置距离左边的距离
@property (nonatomic, assign) NSUInteger zoomCenterIndex;     ///< 中心点k线

#pragma mark - 滑动手势

@property (nonatomic, assign) CGPoint lastPanPoint;     ///< 最后滑动的点
@property (nonatomic, assign) BOOL respondPanRecognizer;       ///< 是否相应滑动手势

@property (nonatomic, assign) BOOL disPlay;

@property (nonatomic, strong) MALayer * maLayer;

@end

@implementation KLineChart

#pragma mark - Surper

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self) {

        _disPlay = YES;
        
        [self.scrollView.layer addSublayer:self.redLineLayer];
        [self.scrollView.layer addSublayer:self.greenLineLayer];
        [self.scrollView.layer addSublayer:self.maLayer];
        
        self.volumGrid.width = 0.25;
        [self.kLineBackLayer addRenderer:self.volumGrid];
        self.kLineGrid.width = 0.25;
        [self.kLineBackLayer addRenderer:self.kLineGrid];
        self.axisRenderer.width = 0.25;
        [self.kLineBackLayer addRenderer:self.axisRenderer];
        
        self.kAxisRenderer.width = 0.25;
        [self.stringLayer addRenderer:self.kAxisRenderer];
        self.vAxisRenderer.width = 0.25;
        [self.stringLayer addRenderer:self.vAxisRenderer];
        
        _kAxisSplit = 7;
        _kInterval = 3;
        _kLineCountVisibale = 60;
        _kMaxCountVisibale = 120;
        _kMinCountVisibale = 20;
        _axisFont = [UIFont fontWithName:FONT_ARIAL size:10];
        _riseColor = RGB(234, 82, 83);
        _fallColor = RGB(77, 166, 73);
        _gridColor = RGB(225, 225, 225);
        _axisStringColor = C_HEX(0xaeb1b6);
        _currentZoom = -.001f;
        
        self.queryPriceView.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);
        [self addSubview:self.queryPriceView];
        
        UIPinchGestureRecognizer * pinchGestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchesViewOnGesturer:)];
        [self addGestureRecognizer:pinchGestureRecognizer];
        
        UILongPressGestureRecognizer * longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressViewOnGesturer:)];
        [self addGestureRecognizer:longPress];
    }
    
    return self;
}

/** 成交量是否为红 */
- (BOOL)volumIsRed:(id)obj
{
    return [self isRed:obj];
}

/** k线是否为红 */
- (BOOL)isRed:(id <KLineAbstract>)kLineObj
{
    return kLineObj.ggOpen >= kLineObj.ggClose;
}

/**
 * 视图滚动
 */
- (void)scrollViewContentSizeDidChange
{
    [super scrollViewContentSizeDidChange];
    
    [self updateSubLayer];
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];
    
    self.queryPriceView.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self scrollViewContentSizeDidChange];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    CGFloat minMove = self.kLineScaler.shapeWidth + self.kLineScaler.shapeInterval;
    self.scrollView.contentOffset = CGPointMake(round(self.scrollView.contentOffset.x / minMove) * minMove, 0);
    
    [self scrollViewContentSizeDidChange];
}

#pragma mark - K线手势

- (void)longPressViewOnGesturer:(UILongPressGestureRecognizer *)recognizer
{
    self.scrollView.scrollEnabled = NO;
    
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        
        self.scrollView.scrollEnabled = YES;
        self.queryPriceView.hidden = YES;
        [self.queryPriceView clearLine];
    }
    else if (recognizer.state == UIGestureRecognizerStateBegan) {
        
        CGPoint velocity = [recognizer locationInView:self];
        [self updateQueryLayerWithPoint:velocity];
        self.queryPriceView.hidden = NO;
    }
    else if (recognizer.state == UIGestureRecognizerStateChanged) {
    
        CGPoint velocity = [recognizer locationInView:self];
        [self updateQueryLayerWithPoint:velocity];
    }
}

- (void)updateQueryLayerWithPoint:(CGPoint)velocity
{
    CGPoint velocityInScroll = [self.scrollView convertPoint:velocity fromView:self.queryPriceView];
    NSInteger index = [self pointConvertIndex:velocityInScroll.x];
    id <KLineAbstract, QueryViewAbstract> kData = self.kLineArray[index];
    
    NSString * yString = @"";
    
    self.queryPriceView.xAxisOffsetY = self.redLineLayer.gg_bottom;
    
    if (CGRectContainsPoint(self.redLineLayer.frame, velocity)) {
        
        yString = [NSString stringWithFormat:@"%.2f", [self.kLineScaler getPriceWithPoint:CGPointMake(0, velocity.y - self.queryPriceView.lineWidth)]];
    }
    else if (CGRectContainsPoint(self.redVolumLayer.frame, velocity)) {
    
        yString = [NSString stringWithFormat:@"%.2f万手", [self.volumScaler getPriceWithPoint:CGPointMake(0, velocity.y - self.queryPriceView.lineWidth - self.redVolumLayer.gg_top)]];
    }
    
    NSString * title = [self getDateString:kData.ggKLineDate];
    [self.queryPriceView setYString:yString setXString:title];
    [self.queryPriceView.queryView setQueryData:kData];
    
    GGKShape shape = self.kLineScaler.kShapes[index];
    CGPoint queryVelocity = [self.scrollView convertPoint:shape.top toView:self.queryPriceView];
    [self.queryPriceView setCenterPoint:CGPointMake(queryVelocity.x, velocity.y)];
}

- (NSString *)getDateString:(NSDate *)date
{
    NSDateFormatter * showFormatter = [[NSDateFormatter alloc] init];
    showFormatter.dateFormat = @"yyyy-MM-dd";
    return [showFormatter stringFromDate:date];
}

/** 获取点对应的数据 */
- (NSInteger)pointConvertIndex:(CGFloat)x
{
    NSInteger idx = x / (self.kLineScaler.shapeWidth + self.kLineScaler.shapeInterval);
    return idx >= self.kLineScaler.kLineObjAry.count ? self.kLineScaler.kLineObjAry.count - 1 : idx;
}

-(void)pinchesViewOnGesturer:(UIPinchGestureRecognizer *)recognizer
{
    self.scrollView.scrollEnabled = NO;     // 放大禁用滚动手势
    
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        
        _currentZoom = recognizer.scale;
        
        self.scrollView.scrollEnabled = YES;
    }
    else if (recognizer.state == UIGestureRecognizerStateBegan && _currentZoom != 0.0f) {
        
        recognizer.scale = _currentZoom;
        
        CGPoint touch1 = [recognizer locationOfTouch:0 inView:self];
        CGPoint touch2 = [recognizer locationOfTouch:1 inView:self];

        // 放大开始记录位置等数据
        CGFloat center_x = (touch1.x + touch2.x) / 2.0f;
        _zoomCenterIndex = [self pointConvertIndex:self.scrollView.contentOffset.x + center_x];
        GGKShape shape = self.kLineScaler.kShapes[_zoomCenterIndex];
        _zoomCenterSpacingLeft = shape.top.x - self.scrollView.contentOffset.x;
    }
    else if (recognizer.state == UIGestureRecognizerStateChanged) {
    
        CGFloat tmpZoom;
        tmpZoom = recognizer.scale / _currentZoom;
        _currentZoom = recognizer.scale;
        NSInteger showNum = round(_kLineCountVisibale / tmpZoom);
        
        // 避免没必要计算
        if (showNum == _kLineCountVisibale) { return; }
        if (showNum >= _kLineCountVisibale && _kLineCountVisibale == _kMaxCountVisibale) return;
        if (showNum <= _kLineCountVisibale && _kLineCountVisibale == _kMinCountVisibale) return;
        
        // 极大值极小值
        _kLineCountVisibale = showNum;
        _kLineCountVisibale = _kLineCountVisibale < 20 ? 20 : _kLineCountVisibale;
        _kLineCountVisibale = _kLineCountVisibale > 120 ? 120 : _kLineCountVisibale;
        
        [self kLineSubLayerRespond];
        
        GGKShape shape = self.kLineScaler.kShapes[_zoomCenterIndex];
        CGFloat offsetX = shape.top.x - _zoomCenterSpacingLeft;
        
        if (offsetX < 0) { offsetX = 0; }
        if (offsetX > self.scrollView.contentSize.width - self.scrollView.frame.size.width) {
            offsetX = self.scrollView.contentSize.width - self.scrollView.frame.size.width;
        }
        
        self.scrollView.contentOffset = CGPointMake(offsetX, 0);
    }
}

#pragma mark - Setter

/** 设置k线方法 */
- (void)setKLineArray:(NSArray<id<KLineAbstract, VolumeAbstract, QueryViewAbstract>> *)kLineArray
{
    _kLineArray = kLineArray;
    
    [self.maLayer updateIndexWithArray:kLineArray param:@{@5 : RGB(215, 161, 104),
                                                          @10 : RGB(115, 190, 222),
                                                          @20 : RGB(62, 121, 202),
                                                          @40 : RGB(110, 226, 121)}];
    
    [self.kLineScaler setObjArray:kLineArray
                          getOpen:@selector(ggOpen)
                         getClose:@selector(ggClose)
                          getHigh:@selector(ggHigh)
                           getLow:@selector(ggLow)];
}

#pragma mark - 更新视图

- (void)updateChart
{
    [self baseConfigRendererAndLayer];
    
    [self kLineSubLayerRespond];
}

- (void)kLineSubLayerRespond
{
    [self baseConfigKLineLayer];
    [self baseConfigVolumLayer];
    
    [self updateSubLayer];
    [self updateKLineGridLayer];
}

#pragma mark - 基础设置层

/** K线 */
- (void)baseConfigKLineLayer
{
    self.redLineLayer.frame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height * .6f);
    self.kLineScaler.rect = self.redLineLayer.frame;
    self.kLineScaler.shapeWidth = self.kLineScaler.rect.size.width / _kLineCountVisibale - _kInterval;
    self.kLineScaler.shapeInterval = _kInterval;
    
    CGSize contentSize = self.kLineScaler.contentSize;
    
    // 设置滚动位置关闭隐士动画
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    self.kLineBackLayer.frame = CGRectMake(0, 0, contentSize.width, self.frame.size.height);
    
    // 滚动大小
    self.scrollView.contentSize = contentSize;
    self.backScrollView.contentSize = contentSize;
    
    // K线
    self.redLineLayer.frame = CGRectMake(0, 0, contentSize.width, contentSize.height);
    self.greenLineLayer.frame = CGRectMake(0, 0, contentSize.width, contentSize.height);

    // K线上的指标线
    self.maLayer.frame = CGRectMake(_kInterval / 2, 0, contentSize.width - _kInterval, contentSize.height);
    
    [CATransaction commit];
}

/** 成交量 */
- (void)baseConfigVolumLayer
{
    CGFloat volumKLineSep = 15;
    CGRect volumRect = CGRectMake(0, self.redLineLayer.gg_bottom + volumKLineSep, self.kLineScaler.contentSize.width, self.frame.size.height - self.redLineLayer.gg_bottom - volumKLineSep);
    
    [self setVolumRect:volumRect];
    self.volumScaler.rect = CGRectMake(_kInterval / 2, 0, self.redVolumLayer.gg_width - _kInterval, self.redVolumLayer.gg_height);
    self.volumScaler.barWidth = self.kLineScaler.shapeWidth;
    [self.volumScaler setObjAry:_kLineArray getSelector:@selector(ggVolume)];
}

/** 设置渲染器 */
- (void)baseConfigRendererAndLayer
{
    // 成交量颜色设置
    self.redVolumLayer.strokeColor = _riseColor.CGColor;
    self.redVolumLayer.fillColor = _riseColor.CGColor;
    
    self.greenVolumLayer.strokeColor = _fallColor.CGColor;
    self.greenVolumLayer.fillColor = _fallColor.CGColor;
    
    // k线图颜色设置
    self.redLineLayer.strokeColor = _riseColor.CGColor;
    self.redLineLayer.fillColor = _riseColor.CGColor;
    
    self.greenLineLayer.strokeColor = _fallColor.CGColor;
    self.greenLineLayer.fillColor = _fallColor.CGColor;
    
    // 成交量网格设置
    self.volumGrid.color = _gridColor;
    
    // 成交量Y轴设置
    self.vAxisRenderer.strColor = _axisStringColor;
    self.vAxisRenderer.showLine = NO;
    self.vAxisRenderer.strFont = _axisFont;
    self.vAxisRenderer.offSetRatio = CGPointMake(0, -1);
    
    // K线Y轴设置
    self.kAxisRenderer.strColor = _axisStringColor;
    self.kAxisRenderer.showLine = NO;
    self.kAxisRenderer.strFont = _axisFont;
    self.kAxisRenderer.offSetRatio = CGPointMake(0, -1);
    
    // X横轴设置
    self.axisRenderer.strColor = _axisStringColor;
    self.axisRenderer.showLine = NO;
    self.axisRenderer.strFont = _axisFont;
    
    // K线网格设置
    self.kLineGrid.color = _gridColor;
}

/** 更新k线背景层 */
- (void)updateKLineGridLayer
{
    // 纵向分割高度
    CGFloat v_spe = self.greenLineLayer.gg_height / _kAxisSplit;
    
    // 成交量网格设置
    self.volumGrid.grid = GGGridRectMake(self.redVolumLayer.frame, v_spe, 0);
    
    // 成交量Y轴设置
    GGLine leftLine = GGLeftLineRect(self.redVolumLayer.frame);
    self.vAxisRenderer.axis = GGAxisLineMake(leftLine, 0, v_spe);
    
    // K线Y轴设置
    leftLine = GGLeftLineRect(self.greenLineLayer.frame);
    self.kAxisRenderer.axis = GGAxisLineMake(leftLine, 0, GGLengthLine(leftLine) / _kAxisSplit);
    
    // X横轴设置
    self.axisRenderer.axis = GGAxisLineMake(GGBottomLineRect(self.greenLineLayer.frame), 1.5, 0);
    
    // K线网格设置
    [self.kLineGrid removeAllLine];
    self.kLineGrid.grid = GGGridRectMake(self.redLineLayer.frame, v_spe, 0);
    
    [_kLineArray enumerateObjectsUsingBlock:^(id<KLineAbstract,VolumeAbstract, QueryViewAbstract> obj, NSUInteger idx, BOOL * stop) {
        
        if ([obj isShowTitle]) {
            
            CGFloat x = self.kLineScaler.kShapes[idx].top.x;
            [self.axisRenderer addString:obj.ggKLineTitle point:CGPointMake(x, CGRectGetMaxY(self.greenLineLayer.frame))];
            
            if (idx == 0) { return; }
            
            GGLine kline = [self lineWithX:x rect:self.greenLineLayer.frame];
            GGLine vline = [self lineWithX:x rect:self.redVolumLayer.frame];
            [self.kLineGrid addLine:kline];
            [self.kLineGrid addLine:vline];
        }
    }];
    
    [self.kLineBackLayer setNeedsDisplay];
}

- (GGLine)lineWithX:(CGFloat)x rect:(CGRect)rect
{
    return GGLineMake(x, CGRectGetMinY(rect), x, CGRectGetMaxY(rect));
}

#pragma mark - 实时更新

- (void)updateSubLayer
{
    // 计算显示的在屏幕中的k线
    NSInteger index = (self.scrollView.contentOffset.x - self.kLineScaler.rect.origin.x) / (self.kLineScaler.shapeInterval + self.kLineScaler.shapeWidth);
    NSInteger len = _kLineCountVisibale;
    
    if (index < 0) index = 0;
    if (index > _kLineArray.count) index = _kLineArray.count;
    if (index + _kLineCountVisibale > _kLineArray.count) { len = _kLineArray.count - index; }
    
    NSRange range = NSMakeRange(index, len);
    
    // 更新视图
    [self updateKLineLayerWithRange:range];
    [self updateVolumLayerWithRange:range];
}

/** K线图实时更新 */
- (void)updateKLineLayerWithRange:(NSRange)range
{
    // 计算k线最大最小
    CGFloat max = 0;
    CGFloat min = 0;
    [_kLineArray getKLineMax:&max min:&min range:range];
    
    // 更新K线指标线
    [self.maLayer updateLayerWithRange:range max:max min:min];
    
    // 更新k线层
    self.kLineScaler.max = max;
    self.kLineScaler.min = min;
    [self.kLineScaler updateScaler];
    
    CGMutablePathRef refRed = CGPathCreateMutable();
    CGMutablePathRef refGreen = CGPathCreateMutable();
    
    for (NSUInteger i = range.location; i < range.location + range.length; i++) {
        
        id obj = _kLineArray[i];
        GGKShape shape = self.kLineScaler.kShapes[i];
        
        [self isRed:obj] ? GGPathAddKShape(refRed, shape) : GGPathAddKShape(refGreen, shape);
    }
    
    self.redLineLayer.path = refRed;
    CGPathRelease(refRed);
    self.greenLineLayer.path = refGreen;
    CGPathRelease(refGreen);
    
    // 更新k线Y轴
    self.kAxisRenderer.aryString = [NSArray splitWithMax:max min:min split:_kAxisSplit + 1 format:@"%.2f" attached:@""];
    self.vAxisRenderer.range = NSMakeRange(1, _kAxisSplit);
    [self.stringLayer setNeedsDisplay];
}

/** 柱状图实时更新 */
- (void)updateVolumLayerWithRange:(NSRange)range
{
    // 计算柱状图最大最小
    CGFloat barMax = 0;
    CGFloat barMin = 0;
    [_kLineArray getMax:&barMax min:&barMin selGetter:@selector(ggVolume) range:range base:0.1];
    
    // 更新成交量
    self.volumScaler.min = 0;
    self.volumScaler.max = barMax;
    [self.volumScaler updateScaler];
    [self updateVolumLayer:range];
    
    // 更新成交量Y轴
    CGFloat v_spe = self.greenLineLayer.gg_height / _kAxisSplit;
    CGFloat high = CGRectGetHeight(self.redVolumLayer.frame);
    NSUInteger volumCount = high / v_spe;
    self.vAxisRenderer.aryString = [NSArray splitWithMax:barMax min:0 split:volumCount format:@"%.1f" attached:@"万手"];
    self.vAxisRenderer.range = NSMakeRange(1, volumCount - 1);
    [self.stringLayer setNeedsDisplay];
}

#pragma mark - Lazy

GGLazyGetMethod(MALayer, maLayer);

GGLazyGetMethod(CAShapeLayer, redLineLayer);
GGLazyGetMethod(CAShapeLayer, greenLineLayer);

GGLazyGetMethod(GGGridRenderer, kLineGrid);
GGLazyGetMethod(GGGridRenderer, volumGrid);

GGLazyGetMethod(GGAxisRenderer, axisRenderer);
GGLazyGetMethod(GGAxisRenderer, kAxisRenderer);
GGLazyGetMethod(GGAxisRenderer, vAxisRenderer);

GGLazyGetMethod(DKLineScaler, kLineScaler);

GGLazyGetMethod(CrissCrossQueryView, queryPriceView);

@end