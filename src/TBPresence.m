//
//  TBPresence.m
//

#import "TBPresence.h"
#import "TBSettings.h"
#import <Cocoa/Cocoa.h>

@interface TBPresence ()
@property (nonatomic, assign) TBHideReason reason;
@property (nonatomic, assign) double idleSeconds;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation TBPresence

+ (instancetype)shared {
    static TBPresence *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TBPresence new]; });
    return s;
}

- (void)start {
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                  target:self
                                                selector:@selector(tick:)
                                                userInfo:nil
                                                 repeats:YES];
    self.timer.tolerance = 0.2;

    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserver:self
           selector:@selector(appActivated:)
               name:NSWorkspaceDidActivateApplicationNotification
             object:nil];

    [self evaluate];
}

- (void)recheck { [self evaluate]; }

- (void)tick:(NSTimer *)tm { [self evaluate]; }

- (void)appActivated:(NSNotification *)note { [self evaluate]; }

- (BOOL)shouldShow { return self.reason == TBHideReasonNone; }

- (NSString *)reasonText {
    switch (self.reason) {
        case TBHideReasonNone:
            return [NSString stringWithFormat:@"显示中（闲置 %.0f 秒）", self.idleSeconds];
        case TBHideReasonApp: {
            NSString *n = [NSWorkspace sharedWorkspace].frontmostApplication.localizedName;
            return [NSString stringWithFormat:@"%@ 不在显示列表里，已交还系统", n ?: @"当前 App"];
        }
        case TBHideReasonIdle:
            return [NSString stringWithFormat:@"闲置 %.0f 分钟，已熄成纯黑", self.idleSeconds / 60.0];
    }
    return @"";
}

#pragma mark - 判断

- (void)evaluate {
    TBSettings *s = [TBSettings shared];

    self.idleSeconds = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState,
                                                              kCGAnyInputEventType);

    TBHideReason r = TBHideReasonNone;

    // 1) 白名单：空 = 不限制
    NSArray<NSString *> *wl = s.appWhitelist;
    if (wl.count > 0) {
        NSString *front = [NSWorkspace sharedWorkspace].frontmostApplication.bundleIdentifier;
        NSString *selfID = [[NSBundle mainBundle] bundleIdentifier];
        // 自己开着设置窗口时也算允许，不然一开设置条子就没了
        BOOL ok = (front == nil) || [wl containsObject:front] ||
                  (selfID && [front isEqualToString:selfID]);
        if (!ok) r = TBHideReasonApp;
    }

    // 2) 闲置：0 = 不熄
    if (r == TBHideReasonNone) {
        double threshold = s.idleHideMinutes * 60.0;
        const char *ti = getenv("TB_TEST_IDLE");   // 开发探针：秒数覆盖
        if (ti) threshold = atof(ti);
        if (threshold > 0 && self.idleSeconds >= threshold) r = TBHideReasonIdle;
    }

    if (r == self.reason) return;

    self.reason = r;
    fprintf(stderr, "[tb] presence -> %ld (%s)\n", (long)r, self.reasonText.UTF8String);
    if (self.onChange) self.onChange();
}

@end
