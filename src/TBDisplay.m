//
//  TBDisplay.m
//

#import "TBDisplay.h"
#import "TBComposer.h"
#import "TBSettings.h"
#import <Cocoa/Cocoa.h>
#import <mach/mach_time.h>

static double TBNowMS(void) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

#pragma mark - 私有 API

@interface NSTouchBar (TBSystemModal14)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
                         placement:(long long)placement
          systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
@end
@interface NSTouchBar (TBSystemModal13)
+ (void)presentSystemModalFunctionBar:(NSTouchBar *)touchBar
                            placement:(long long)placement
             systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
@end
@interface NSTouchBar (TBDismiss)
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

/// 像素位移的幅度（pt）。左右各留这么多余量，源图放大一点点，移动时不会露边。
static const double kShiftAmp = 6.0;
/// 每隔多少秒挪 1pt
static const double kShiftStepSeconds = 10.0;

#pragma mark - 视图

@interface TBDisplayView : NSView
@property (nonatomic, strong) NSArray<TBClip *> *clips;
@property (nonatomic, assign) unsigned long tick;
@property (nonatomic, assign) BOOL seamMode;
@property (nonatomic, assign) BOOL pixelShift;
@property (nonatomic, assign) double brightness;
@property (nonatomic, assign) double fade;      // 0 = 全黑，1 = 正常
@end

@implementation TBDisplayView

- (BOOL)isFlipped { return NO; }

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    fprintf(stderr, "[tb] view attached %.0fx%.0f pt\n",
            self.bounds.size.width, self.bounds.size.height);
}

/// 缓慢往返的水平位移：每 10 秒挪 1pt，走到头再回来。
/// 用绝对时间算，所以改 fps 也不会跳。
- (double)shiftOffset {
    double t = [NSDate timeIntervalSinceReferenceDate];
    long step = (long)(t / kShiftStepSeconds);
    long period = (long)(kShiftAmp * 4);       // 0..2A..0
    long p = step % period;
    if (p < 0) p += period;
    if (p > 2 * (long)kShiftAmp) p = period - p;
    return (double)p - kShiftAmp;              // −A .. +A
}

- (void)drawRect:(NSRect)dirtyRect {
    static BOOL prof = NO, profInit = NO;
    if (!profInit) { prof = getenv("TB_PROFILE") != NULL; profInit = YES; }

    double t0 = prof ? TBNowMS() : 0;
    [self drawContent];
    if (!prof) return;

    // 每 120 次报一次：平均耗时 + 调用频率（能看出有没有被重复重绘）
    static double acc = 0;
    static int cnt = 0;
    static double lastReport = 0;
    double now = TBNowMS();
    acc += now - t0;
    cnt++;
    if (cnt >= 120) {
        if (lastReport > 0) {
            double wall = (now - lastReport) / 1000.0;
            fprintf(stderr, "[tb] draw %.2f ms/次，%d 次/%.1fs = %.1f fps\n",
                    acc / cnt, cnt, wall, cnt / wall);
        }
        lastReport = now;
        acc = 0; cnt = 0;
    }
}

- (void)drawContent {
    NSSize b = self.bounds.size;
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    // 探针：只填黑，不解码不合成，用来量"重绘一次"本身的固定开销
    static BOOL black = NO, blackInit = NO;
    if (!blackInit) { black = getenv("TB_BLACK") != NULL; blackInit = YES; }
    if (black) {
        CGContextSetFillColorWithColor(ctx, CGColorGetConstantColor(kCGColorBlack));
        CGContextFillRect(ctx, CGRectMake(0, 0, b.width, b.height));
        return;
    }

    // 完全熄灭：只填一块黑，不做合成、不解码（OLED 上纯黑 = 像素物理关闭）
    if (self.fade <= 0.001) {
        CGContextSetFillColorWithColor(ctx, CGColorGetConstantColor(kCGColorBlack));
        CGContextFillRect(ctx, CGRectMake(0, 0, b.width, b.height));
        return;
    }

    if (self.clips.count < 3) return;

    CGImageRef s[3], t[3];
    for (int i = 0; i < 3; i++) {
        TBClip *c = self.clips[i];
        NSUInteger n = c.count;
        if (n == 0) return;
        NSUInteger idx = self.tick % n;
        s[i] = [c sharpAt:idx];
        t[i] = [c thumbAt:idx];
        if (!s[i]) return;
        if (!t[i]) t[i] = s[i];
    }

    CGImageRef comp = self.seamMode ? TBComposeSeam(s) : TBComposeTrio(s, t);

    // 像素位移：把整条画进一个略微放大的矩形，再左右平移
    double ov  = self.pixelShift ? kShiftAmp : 0.0;
    double off = self.pixelShift ? [self shiftOffset] : 0.0;
    CGRect dst = CGRectMake(-ov + off, 0, b.width + 2 * ov, b.height);

    CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
    // isFlipped = NO，直接画就是正的，不要翻 CTM
    TBDrawImageWithBrightness(ctx, dst, comp, self.brightness);
    CGImageRelease(comp);

    // 淡入淡出：整体压一层黑
    if (self.fade < 0.999) {
        CGColorRef black = CGColorCreateGenericRGB(0, 0, 0, 1.0 - self.fade);
        CGContextSetFillColorWithColor(ctx, black);
        CGContextFillRect(ctx, CGRectMake(0, 0, b.width, b.height));
        CGColorRelease(black);
    }
}

@end

#pragma mark - TBDisplay

@interface TBDisplay ()
@property (nonatomic, strong) TBDisplayView *view;
@property (nonatomic, strong) NSTouchBar *bar;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL presented;
@property (nonatomic, assign) BOOL detached;       // 已撤下，交还系统
@property (nonatomic, assign) double fade;
@property (nonatomic, assign) NSTimeInterval lastFadeTime;
@end

@implementation TBDisplay

- (instancetype)init {
    if ((self = [super init])) {
        _fps = 24.0;
        _brightness = 1.0;
        _fade = 1.0;
        _contentVisible = YES;
        _seamMode = getenv("TB_MODE") && strcmp(getenv("TB_MODE"), "seam") == 0;
    }
    return self;
}

- (void)setBrightness:(double)brightness {
    _brightness = brightness;
    if (self.view) {
        self.view.brightness = brightness;
        [self.view setNeedsDisplay:YES];
    }
}

/// 改帧率要重建 timer（NSTimer 的间隔不能改）
- (void)setFps:(double)fps {
    if (fps < 1.0) fps = 1.0;
    _fps = fps;
    if (self.timer) [self startTimer];
}

- (void)setPixelShift:(BOOL)on {
    _pixelShift = on;
    self.view.pixelShift = on;
    [self.view setNeedsDisplay:YES];
}

- (BOOL)isPresented { return self.presented; }

#pragma mark 显示 / 熄灭

- (void)setContentVisible:(BOOL)v {
    if (_contentVisible == v) return;
    _contentVisible = v;
    self.lastFadeTime = [NSDate timeIntervalSinceReferenceDate];
    if (v) {
        if (!self.timer && self.presented && !self.detached) [self startTimer];
        fprintf(stderr, "[tb] display wake\n");
    } else {
        fprintf(stderr, "[tb] display fading out\n");
    }
}

/// 每帧推一点 fade。淡入快（0.35s），淡出慢（2.8s）——"优雅地熄"
- (void)stepFade {
    double target = self.contentVisible ? 1.0 : 0.0;
    if (fabs(self.fade - target) < 0.0015) {
        if (self.fade == target) return;
        self.fade = target;
    } else {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        double dt = now - self.lastFadeTime;
        self.lastFadeTime = now;
        if (dt < 0) dt = 0;
        if (dt > 0.5) dt = 0.5;                 // 系统挂起过就别一下跳完
        double rate = (target > self.fade) ? (1.0 / 0.35) : (1.0 / 2.8);
        if (self.fade < target) self.fade = MIN(target, self.fade + dt * rate);
        else                    self.fade = MAX(target, self.fade - dt * rate);
    }
    self.view.fade = self.fade;
    [self.view setNeedsDisplay:YES];

    // 彻底黑了就把 timer 停掉，闲置期间 CPU 归零
    if (self.fade <= 0.001 && !self.contentVisible && self.timer) {
        [self.timer invalidate];
        self.timer = nil;
        fprintf(stderr, "[tb] display asleep (timer stopped)\n");
    }
}

/// 撤下整条，Control Strip 回来。用于"前台 App 不在白名单"。
- (void)detach {
    if (!self.presented || self.detached) return;
    self.detached = YES;
    [self.timer invalidate];
    self.timer = nil;
    if ([NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)])
        [NSTouchBar dismissSystemModalTouchBar:self.bar];
    fprintf(stderr, "[tb] detached（交还系统）\n");
}

/// 重新占回来
- (void)attach {
    if (!self.detached) return;
    self.detached = NO;
    // 如果这会儿本来就该是黑的，直接以黑的状态出现，别闪一下画面
    if (!self.contentVisible) {
        self.fade = 0.0;
        self.view.fade = 0.0;
        [self.view setNeedsDisplay:YES];
    }
    [self presentBar];
    self.lastFadeTime = [NSDate timeIntervalSinceReferenceDate];
    if (self.contentVisible) [self startTimer];
    fprintf(stderr, "[tb] attached（重新占用）\n");
}

#pragma mark 挂载

- (void)presentBar {
    if ([NSTouchBar respondsToSelector:
         @selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]) {
        [NSTouchBar presentSystemModalTouchBar:self.bar placement:1
                      systemTrayItemIdentifier:@"com.apple.controlstrip"];
        fprintf(stderr, "[tb] presented (systemModalTouchBar)\n");
    } else {
        [NSTouchBar presentSystemModalFunctionBar:self.bar placement:1
                         systemTrayItemIdentifier:@"com.apple.controlstrip"];
        fprintf(stderr, "[tb] presented (systemModalFunctionBar)\n");
    }
}

- (BOOL)presentWithClips:(NSArray<TBClip *> *)clips {
    if (clips.count < 3) return NO;

    TBDisplayView *view = [[TBDisplayView alloc] initWithFrame:NSMakeRect(0, 0, 1085, 30)];
    view.clips = clips;
    view.seamMode = self.seamMode;
    view.brightness = self.brightness;
    view.pixelShift = self.pixelShift;
    view.fade = self.contentVisible ? 1.0 : 0.0;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    // 不加这条会被压到 445pt
    NSLayoutConstraint *w = [view.widthAnchor constraintEqualToConstant:1085.0];
    w.priority = 999;
    w.active = YES;
    [[view.heightAnchor constraintEqualToConstant:30.0] setActive:YES];

    NSCustomTouchBarItem *item =
        [[NSCustomTouchBarItem alloc] initWithIdentifier:@"com.egc.touchbarexp.canvas"];
    item.view = view;

    NSTouchBar *bar = [[NSTouchBar alloc] init];
    // 必须设 templateItems，否则 item 不生成、视图不挂载
    bar.templateItems = [NSSet setWithObject:item];
    bar.defaultItemIdentifiers = @[@"com.egc.touchbarexp.canvas"];
    bar.principalItemIdentifier = @"com.egc.touchbarexp.canvas";

    self.view = view;
    self.bar = bar;
    self.presented = YES;
    self.detached = NO;
    self.fade = self.contentVisible ? 1.0 : 0.0;
    self.lastFadeTime = [NSDate timeIntervalSinceReferenceDate];

    [self presentBar];
    [view setNeedsDisplay:YES];
    if (self.contentVisible) [self startTimer];
    return YES;
}

- (BOOL)swapClips:(NSArray<TBClip *> *)clips {
    if (clips.count < 3) return NO;
    if (!self.view) return NO;
    self.view.clips = clips;
    self.view.brightness = self.brightness;
    self.view.tick = 0;
    [self.view setNeedsDisplay:YES];
    fprintf(stderr, "[tb] swapped clips -> %s / %s / %s\n",
            clips[0].directory.lastPathComponent.UTF8String,
            clips[1].directory.lastPathComponent.UTF8String,
            clips[2].directory.lastPathComponent.UTF8String);
    return YES;
}

- (void)startTimer {
    [self.timer invalidate];
    if (self.fps <= 0) self.fps = 24.0;
    self.lastFadeTime = [NSDate timeIntervalSinceReferenceDate];
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:1.0 / self.fps repeats:YES block:^(NSTimer *tm) {
        __strong typeof(weakSelf) self_ = weakSelf;
        if (!self_) { [tm invalidate]; return; }
        self_.view.tick++;
        [self_ stepFade];
        // 注意：stepFade 在 fade 稳定时会提前返回，所以这里必须无条件重绘
        [self_.view setNeedsDisplay:YES];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)dismiss {
    [self.timer invalidate];
    self.timer = nil;
    self.view.clips = nil;
    self.presented = NO;
}

@end
