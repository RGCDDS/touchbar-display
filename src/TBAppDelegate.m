//
//  TBAppDelegate.m — 菜单栏图标 / 弹出面板 / 设置窗口 / 全局快捷键 / 轮换
//

#import "TBAppDelegate.h"
#import "TBDisplay.h"
#import "TBSettings.h"
#import "TBHotKey.h"
#import "TBWeatherService.h"
#import "TBPresence.h"
#import <math.h>
#import <libproc.h>

#pragma mark - 菜单栏图标

/// 三段式 Touch Bar 造型的模板图标，自动适配深浅色菜单栏
static NSImage *TBStatusIcon(void) {
    NSImage *img = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO
                           drawingHandler:^BOOL(NSRect r) {
        [[NSColor blackColor] setStroke];
        NSBezierPath *box = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1.5, 6.0, 15.0, 6.0)
                                                            xRadius:1.6 yRadius:1.6];
        box.lineWidth = 1.2;
        [box stroke];
        for (NSNumber *x in @[@(6.5), @(11.5)]) {
            NSBezierPath *l = [NSBezierPath bezierPath];
            [l moveToPoint:NSMakePoint(x.doubleValue, 6.0)];
            [l lineToPoint:NSMakePoint(x.doubleValue, 12.0)];
            l.lineWidth = 1.0;
            [l stroke];
        }
        return YES;
    }];
    img.template = YES;
    return img;
}

#pragma mark - AppDelegate

@interface TBAppDelegate ()
@property (nonatomic, strong) TBDisplay *display;

@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) NSSegmentedControl *popoverSegmented;

@property (nonatomic, strong) NSWindow *settingsWindow;
@property (nonatomic, strong) NSSegmentedControl *settingsSeg;
@property (nonatomic, strong) NSView *settingsPanelHost;
@property (nonatomic, strong) NSView *settingsPanelDisplay;
@property (nonatomic, strong) NSView *settingsPanelGeneral;
@property (nonatomic, strong) NSSegmentedControl *settingsSegmented;
@property (nonatomic, strong) NSSwitch *loginSwitch;
@property (nonatomic, strong) NSSwitch *iconSwitch;
@property (nonatomic, strong) NSSwitch *dockSwitch;
@property (nonatomic, strong) NSPopUpButton *sourcePopup;
@property (nonatomic, strong) NSPopUpButton *intervalPopup;
@property (nonatomic, strong) NSSlider *brightnessSlider;
@property (nonatomic, strong) NSTextField *brightnessValueLabel;
@property (nonatomic, strong) NSSlider *speedSlider;
@property (nonatomic, strong) NSTextField *speedValueLabel;
@property (nonatomic, strong) NSTextField *weatherStatusLabel;
@property (nonatomic, strong) NSButton *refreshButton;
@property (nonatomic, strong) NSTextField *cityField;
@property (nonatomic, strong) NSSwitch *centerSlotSwitch;
@property (nonatomic, strong) NSDatePicker *morningPicker;
@property (nonatomic, strong) NSDatePicker *noonPicker;
@property (nonatomic, strong) NSDatePicker *eveningPicker;
@property (nonatomic, strong) NSTextField *slotHintLabel;

@property (nonatomic, strong) NSTextField *idleField;
@property (nonatomic, strong) NSSwitch *pixelShiftSwitch;
@property (nonatomic, strong) NSPopUpButton *appPopup;
@property (nonatomic, strong) NSTextField *powerHintLabel;

@property (nonatomic, strong) NSArray<NSNumber *> *currentClipOrder;
@property (nonatomic, strong) NSArray<TBClip *> *baseClips;
@property (nonatomic, assign) BOOL weatherServiceRunning;
@property (nonatomic, copy) NSString *weatherCityInUse;
@property (nonatomic, strong) NSTimer *slotTimer;
@property (nonatomic, strong) NSTimer *rotationTimer;
@property (nonatomic, strong) TBHotKey *cycleHotKey;
@property (nonatomic, strong) TBHotKey *settingsHotKey;
@end

@implementation TBAppDelegate

#pragma mark 生命周期

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self redirectLog];
    [self buildMainMenu];

    self.display = [TBDisplay new];

    [self buildStatusItem];
    [self buildPopover];
    [self registerHotKeys];
    [self applyActivationPolicy];
    // App 可能刚从 dist/ 装到 /Applications，登录项还指着旧路径
    [[TBSettings shared] healLoginItemIfNeeded];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(weatherDidChange:)
                                                 name:TBSettingsWeatherDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsDidChange:)
                                                 name:TBSettingsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(brightnessDidChange:)
                                                 name:TBSettingsBrightnessDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(speedDidChange:)
                                                 name:TBSettingsSpeedDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(timeSlotDidChange:)
                                                 name:TBSettingsTimeSlotDidChangeNotification
                                               object:nil];

    [self applyWeatherAnimated:NO];
    [self restartRotationTimer];
    [self startSlotTimer];

    // 省屏：前台 App 白名单 + 闲置熄灭
    __weak typeof(self) weakSelf = self;
    [TBPresence shared].onChange = ^{ [weakSelf applyPresence]; };
    [[TBPresence shared] start];
    [self applyPresence];

    // 开发探针：TB_AUTOCYCLE=秒数 时自动轮换，用来验证"不重启换天气"这条路径
    const char *ac = getenv("TB_AUTOCYCLE");
    if (ac && atoi(ac) > 0) {
        NSTimeInterval ti = atoi(ac);
        fprintf(stderr, "[tb] TB_AUTOCYCLE=%.0fs\n", ti);
        [NSTimer scheduledTimerWithTimeInterval:ti repeats:YES block:^(NSTimer *tm) {
            TBSettings *s = [TBSettings shared];
            s.weather = (TBWeather)((s.weather + 1) % 3);
        }];
    }

    if (getenv("TB_OPEN_SETTINGS")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self showSettings:nil];
            const char *tab = getenv("TB_SETTINGS_TAB");   // 探针：直接翻到某一页
            if (tab) {
                self.settingsSeg.selectedSegment = atoi(tab);
                [self settingsPageChanged:self.settingsSeg];
            }
            fprintf(stderr, "[tb] settings window %.0fx%.0f visible=%d number=%ld\n",
                    self.settingsWindow.frame.size.width, self.settingsWindow.frame.size.height,
                    self.settingsWindow.isVisible, (long)self.settingsWindow.windowNumber);
        });
    }

    if (getenv("TB_OPEN_POPOVER")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self togglePopover:nil];
            fprintf(stderr, "[tb] popover shown=%d size=%.0fx%.0f\n",
                    self.popover.isShown,
                    self.popover.contentSize.width, self.popover.contentSize.height);
        });
    }

    // 开发探针：TB_TEST_BRIGHT=0.6 时直接走一遍滑块的 action，验证实时生效链路
    const char *tbr = getenv("TB_TEST_BRIGHT");
    if (tbr && atof(tbr) > 0) {
        NSSlider *fake = [[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        fake.minValue = TB_BRIGHTNESS_MIN;
        fake.maxValue = TB_BRIGHTNESS_MAX;
        fake.doubleValue = atof(tbr);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self brightnessChanged:fake];
            fprintf(stderr, "[tb] TB_TEST_BRIGHT=%.2f applied\n", atof(tbr));
        });
    }

    // 开发探针：TB_TEST_WHITELIST=bundleid 先设成"只在这个 App 显示"，8 秒后清空
    // 用来验证 detach（交还系统）/ attach（重新占用）两条路
    const char *tw = getenv("TB_TEST_WHITELIST");
    if (tw) {
        NSString *bid = [NSString stringWithUTF8String:tw];
        [TBSettings shared].appWhitelist = @[bid];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            fprintf(stderr, "[tb] TB_TEST_WHITELIST 清空\n");
            [TBSettings shared].appWhitelist = @[];
        });
    }

    // 开发探针：TB_TEST_SLOT=1 时把"晚上"的起点改成 1 分钟前，用来验证跨时段重排
    if (getenv("TB_TEST_SLOT")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NSDateComponents *c = [[NSCalendar currentCalendar]
                                   components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                     fromDate:[NSDate date]];
            NSInteger nowMin = c.hour * 60 + c.minute;
            [TBSettings shared].eveningStart = (nowMin + 1439) % 1440;
            fprintf(stderr, "[tb] TB_TEST_SLOT -> eveningStart=%ld, slot=%ld\n",
                    (long)(nowMin + 1439) % 1440, (long)[[TBSettings shared] currentSlot]);
        });
    }

    if (getenv("TB_TEST_LOGIN")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            TBSettings *st = [TBSettings shared];
            NSError *e = nil;
            BOOL on = [st setLaunchAtLogin:YES error:&e];
            fprintf(stderr, "[tb] login ON -> %d (%s) readback=%d\n", on,
                    e.localizedDescription.UTF8String ?: "-", [st launchAtLogin]);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                NSError *e2 = nil;
                BOOL off = [st setLaunchAtLogin:NO error:&e2];
                fprintf(stderr, "[tb] login OFF -> %d (%s) readback=%d\n", off,
                        e2.localizedDescription.UTF8String ?: "-", [st launchAtLogin]);
            });
        });
    }

    fprintf(stderr, "[tb] ready. weather=%s source=%ld menubar=%d rotation=%ldmin slot=%ld order=%s\n",
            [TBSettings displayNameForWeather:[TBSettings shared].weather].UTF8String,
            (long)[TBSettings shared].weatherSource,
            [TBSettings shared].showMenuBarIcon,
            (long)[TBSettings shared].rotationMinutes,
            (long)[[TBSettings shared] currentSlot],
            [[[TBSettings shared] clipOrder] componentsJoinedByString:@""].UTF8String);

    // 每 10 秒一行心跳，带 CPU% 和真实内存（phys_footprint，和活动监视器一致）
    [NSTimer scheduledTimerWithTimeInterval:10 repeats:YES block:^(NSTimer *tm) {
        struct rusage ru;
        getrusage(RUSAGE_SELF, &ru);
        static time_t t0 = 0;
        if (!t0) t0 = time(NULL);
        double cpu = ru.ru_utime.tv_sec + ru.ru_utime.tv_usec / 1e6
                   + ru.ru_stime.tv_sec + ru.ru_stime.tv_usec / 1e6;
        long el = (long)(time(NULL) - t0);

        // ru_maxrss 是"峰值 RSS"，含 mmap 的框架，报出来会虚高一大截（80MB vs 实际 23MB）
        double memMB = ru.ru_maxrss / 1048576.0;
        struct rusage_info_v4 ri;
        if (proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&ri) == 0)
            memMB = ri.ri_phys_footprint / 1048576.0;

        fprintf(stderr, "[tb] alive t=%lds cpu=%.1fs (%.0f%%) mem=%.1fMB\n",
                el, cpu, el > 0 ? cpu / el * 100.0 : 0.0, memMB);
    }];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return NO; }

/// 点 Dock 图标 / 重新打开时，把设置窗口叫出来
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag) [self showSettings:nil];
    return YES;
}

/// Dock 图标开关：Regular = 正经 App（启动台、⌘-Tab 都有），Accessory = 纯菜单栏工具
- (void)applyActivationPolicy {
    BOOL dock = [TBSettings shared].showDockIcon;
    [NSApp setActivationPolicy:dock ? NSApplicationActivationPolicyRegular
                                    : NSApplicationActivationPolicyAccessory];
    // 没有 Dock 图标时最小化就找不回来了，干脆禁掉（miniaturizable 是只读的，改 styleMask）
    NSWindow *w = self.settingsWindow;
    if (w) {
        NSWindowStyleMask m = w.styleMask;
        if (dock) m |= NSWindowStyleMaskMiniaturizable;
        else      m &= ~NSWindowStyleMaskMiniaturizable;
        w.styleMask = m;
    }
    fprintf(stderr, "[tb] activation policy = %s，窗口 styleMask=%lu\n",
            dock ? "Regular（有 Dock 图标）" : "Accessory（纯菜单栏）",
            (unsigned long)(self.settingsWindow ? self.settingsWindow.styleMask : 0));
}

- (void)applicationWillTerminate:(NSNotification *)note {
    [self.rotationTimer invalidate];
    [self.cycleHotKey unregister];
    [self.settingsHotKey unregister];
    [self.display dismiss];
}

- (void)redirectLog {
    NSString *lp = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs"]
                    stringByAppendingPathComponent:@"tbexp.log"];
    freopen(lp.fileSystemRepresentation, "a", stderr);
    setvbuf(stderr, NULL, _IONBF, 0);   // 不设这个，freopen 之后日志是空的
}

- (void)buildMainMenu {
    NSMenu *main = [NSMenu new];

    NSMenuItem *appItem = [NSMenuItem new];
    [main addItem:appItem];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:@"关于 Touch Bar 装饰屏"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *prefs = [appMenu addItemWithTitle:@"设置…"
                                           action:@selector(showSettings:)
                                    keyEquivalent:@","];
    prefs.target = self;
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *hide = [appMenu addItemWithTitle:@"隐藏"
                                          action:@selector(hide:)
                                   keyEquivalent:@"h"];
    hide.target = NSApp;
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [appMenu addItemWithTitle:@"退出 Touch Bar 装饰屏"
                                          action:@selector(terminate:)
                                   keyEquivalent:@"q"];
    quit.target = NSApp;
    appItem.submenu = appMenu;

    NSMenuItem *winItem = [NSMenuItem new];
    [main addItem:winItem];
    NSMenu *winMenu = [NSMenu new];
    NSMenuItem *close = [winMenu addItemWithTitle:@"关闭窗口"
                                           action:@selector(performClose:)
                                    keyEquivalent:@"w"];
    close.target = nil;
    winItem.submenu = winMenu;
    [NSApp setWindowsMenu:winMenu];

    NSApp.mainMenu = main;
}

#pragma mark 天气应用

- (void)applyWeatherAnimated:(BOOL)animated {
    TBSettings *s = [TBSettings shared];
    NSArray<NSString *> *dirs = [s clipDirectoriesForWeather:s.weather];
    if (!dirs) {
        fprintf(stderr, "[tb] 找不到天气 %s 的帧目录\n",
                [TBSettings slugForWeather:s.weather].UTF8String);
        return;
    }

    NSMutableArray<TBClip *> *clips = [NSMutableArray arrayWithCapacity:3];
    for (NSString *d in dirs) {
        TBClip *c = [TBClip clipWithDirectory:d];
        if (!c) {
            fprintf(stderr, "[tb] 加载失败: %s\n", d.UTF8String);
            return;
        }
        [clips addObject:c];
    }

    // 按"当前时段是否放中间"排一下顺序
    self.baseClips = clips;              // 未排序的三套，跨时段时直接从这里重排，不用重新加载
    NSArray<NSNumber *> *order = [s clipOrder];
    NSMutableArray<TBClip *> *ordered = [NSMutableArray arrayWithCapacity:3];
    for (NSNumber *n in order) {
        NSUInteger i = n.unsignedIntegerValue;
        if (i < clips.count) [ordered addObject:clips[i]];
    }
    self.currentClipOrder = order;
    if (![order isEqualToArray:@[@0, @1, @2]])
        fprintf(stderr, "[tb] clip order %s%s%s（当前时段居中）\n",
                order[0].stringValue.UTF8String, order[1].stringValue.UTF8String,
                order[2].stringValue.UTF8String);

    if (self.display.isPresented) {
        [self.display swapClips:ordered];
    } else if (![self.display presentWithClips:ordered]) {
        fprintf(stderr, "[tb] present 失败\n");
    }

    [self syncWeatherControls];
}

/// 只重排现有三套 clip（跨时段 / 改开关时用），不重新读盘
- (void)applyClipOrder {
    if (self.baseClips.count < 3) return;
    NSArray<NSNumber *> *order = [[TBSettings shared] clipOrder];
    if ([order isEqualToArray:self.currentClipOrder]) return;

    NSMutableArray<TBClip *> *ordered = [NSMutableArray arrayWithCapacity:3];
    for (NSNumber *n in order) {
        NSUInteger i = n.unsignedIntegerValue;
        if (i < self.baseClips.count) [ordered addObject:self.baseClips[i]];
    }
    self.currentClipOrder = order;
    fprintf(stderr, "[tb] clip order -> %s%s%s\n",
            order[0].stringValue.UTF8String, order[1].stringValue.UTF8String,
            order[2].stringValue.UTF8String);
    [self.display swapClips:ordered];
}

- (void)syncWeatherControls {
    NSInteger w = [TBSettings shared].weather;
    if (self.popoverSegmented.selectedSegment != w) self.popoverSegmented.selectedSegment = w;
    if (self.settingsSegmented.selectedSegment != w) self.settingsSegmented.selectedSegment = w;
    self.statusItem.button.toolTip =
        [NSString stringWithFormat:@"Touch Bar 装饰屏 · %@",
         [TBSettings displayNameForWeather:(TBWeather)w]];
    [self syncBrightnessControls];   // 换了天气就换成那个天气记着的亮度
    [self syncSpeedControls];        // 速度同理
}

#pragma mark 时段（当前时段放中间）

- (void)startSlotTimer {
    [self.slotTimer invalidate];
    // 每 30 秒看一眼是不是跨过时段边界了；没开"居中"就只当无事发生
    self.slotTimer = [NSTimer scheduledTimerWithTimeInterval:30
                                                      target:self
                                                    selector:@selector(slotTick:)
                                                    userInfo:nil
                                                     repeats:YES];
    self.slotTimer.tolerance = 10;
}

- (void)slotTick:(NSTimer *)tm {
    if (![TBSettings shared].centerCurrentSlot) return;
    [self applyClipOrder];
}

- (void)timeSlotDidChange:(NSNotification *)note {
    [self syncTimeSlotControls];
    [self applyClipOrder];      // 顺序可能变了，不用重新读盘
}

- (void)weatherDidChange:(NSNotification *)note {
    [self applyWeatherAnimated:YES];
    [self restartRotationTimer];   // 手动切换后重新计时
}

- (void)settingsDidChange:(NSNotification *)note {
    self.statusItem.visible = [TBSettings shared].showMenuBarIcon;
    [self applyActivationPolicy];
    [self syncSettingsControls];
    [self syncWeatherStatus];
    [self restartRotationTimer];
    [[TBPresence shared] recheck];
    [self applyPresence];
}

#pragma mark 省屏

/// 把 presence 的判断落到条子上
- (void)applyPresence {
    TBSettings *s = [TBSettings shared];
    TBPresence *p = [TBPresence shared];

    self.display.pixelShift = s.pixelShift;

    switch (p.reason) {
        case TBHideReasonNone:
            [self.display attach];              // 之前被撤下过就占回来
            self.display.contentVisible = YES;
            break;
        case TBHideReasonApp:
            // 用户在用电脑，把条子还给他，Control Strip 该在
            [self.display detach];
            break;
        case TBHideReasonIdle:
            // 人不在，纯黑比 Control Strip 更省
            [self.display attach];
            self.display.contentVisible = NO;
            break;
    }
    [self syncPowerStatus];
}

- (void)syncPowerStatus {
    if (!self.powerHintLabel) return;
    TBPresence *p = [TBPresence shared];
    NSInteger mins = [TBSettings shared].idleHideMinutes;

    NSString *head;
    if (mins <= 0) {
        head = @"闲置熄灭已关闭";
    } else if (p.reason == TBHideReasonIdle) {
        head = [NSString stringWithFormat:@"已熄灭（闲置超过 %ld 分钟）", (long)mins];
    } else if (p.reason == TBHideReasonApp) {
        head = @"已交还系统（当前 App 不在列表里）";
    } else {
        head = [NSString stringWithFormat:@"显示中，%ld 分钟无操作后淡出", (long)mins];
    }
    self.powerHintLabel.stringValue = head;
}

- (void)syncWeatherStatus {
    if (!self.weatherStatusLabel) return;
    TBSettings *s = [TBSettings shared];
    NSString *text;
    switch (s.weatherSource) {
        case TBWeatherSourceManual:
            text = @"手动选择，不会自动变。";
            break;
        case TBWeatherSourceRandom:
            text = [NSString stringWithFormat:@"每 %ld 分钟随机换一套。", (long)s.rotationMinutes];
            break;
        case TBWeatherSourceLocal:
            text = [TBWeatherService shared].status;
            break;
    }
    self.weatherStatusLabel.stringValue = text ?: @"";
    BOOL local = (s.weatherSource == TBWeatherSourceLocal);
    self.refreshButton.hidden = !local;
    self.cityField.enabled = local;
}

#pragma mark 轮换

- (void)restartRotationTimer {
    [self.rotationTimer invalidate];
    self.rotationTimer = nil;

    TBSettings *s = [TBSettings shared];

    // 天气服务：只有"跟随当地天气"才跑。城市名改了要重来一次。
    BOOL wantLocal = (s.weatherSource == TBWeatherSourceLocal);
    NSString *city = s.weatherCity ?: @"";
    if (wantLocal) {
        if (!self.weatherServiceRunning || ![city isEqualToString:self.weatherCityInUse]) {
            TBWeatherService *svc = [TBWeatherService shared];
            svc.handler = ^{ [self syncWeatherStatus]; };
            [svc startWithInterval:15 * 60];
            self.weatherServiceRunning = YES;
            self.weatherCityInUse = city;
            fprintf(stderr, "[tb] weather service started (city='%s')\n", city.UTF8String);
        }
    } else if (self.weatherServiceRunning) {
        [[TBWeatherService shared] stop];
        self.weatherServiceRunning = NO;
        self.weatherCityInUse = nil;
        fprintf(stderr, "[tb] weather service stopped\n");
    }

    if (s.weatherSource != TBWeatherSourceRandom) return;

    NSTimeInterval ti = MAX((NSInteger)1, s.rotationMinutes) * 60.0;
    self.rotationTimer = [NSTimer scheduledTimerWithTimeInterval:ti
                                                          target:self
                                                        selector:@selector(rotationTick:)
                                                        userInfo:nil
                                                         repeats:YES];
    self.rotationTimer.tolerance = 10;
    fprintf(stderr, "[tb] rotation timer armed: %.0f min\n", ti / 60.0);
}

- (void)rotationTick:(NSTimer *)tm {
    TBWeather next = [[TBSettings shared] rotateToRandomWeather];
    fprintf(stderr, "[tb] rotated -> %s\n", [TBSettings displayNameForWeather:next].UTF8String);
}

#pragma mark 菜单栏

- (void)buildStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSStatusBarButton *btn = self.statusItem.button;
    btn.image = TBStatusIcon();
    btn.target = self;
    btn.action = @selector(togglePopover:);
    btn.toolTip = @"Touch Bar 装饰屏";
    self.statusItem.visible = [TBSettings shared].showMenuBarIcon;
}

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self.popover close];
        return;
    }
    NSStatusBarButton *btn = self.statusItem.button;
    [self.popover showRelativeToRect:btn.bounds ofView:btn preferredEdge:NSRectEdgeMinY];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildPopover {
    NSViewController *vc = [NSViewController new];

    NSTextField *title = [NSTextField labelWithString:@"天气"];
    title.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    title.textColor = [NSColor secondaryLabelColor];

    self.popoverSegmented =
        [NSSegmentedControl segmentedControlWithLabels:@[@"晴", @"风", @"雨"]
                                          trackingMode:NSSegmentSwitchTrackingSelectOne
                                                target:self
                                                action:@selector(popoverWeatherChanged:)];
    self.popoverSegmented.segmentStyle = NSSegmentStyleRounded;
    self.popoverSegmented.selectedSegment = [TBSettings shared].weather;
    [self.popoverSegmented.widthAnchor constraintEqualToConstant:200].active = YES;

    NSBox *sep = [NSBox new];
    sep.boxType = NSBoxSeparator;

    NSButton *settingsBtn = [NSButton buttonWithTitle:@"设置…"
                                               target:self
                                               action:@selector(showSettings:)];
    settingsBtn.bezelStyle = NSBezelStyleRounded;
    settingsBtn.controlSize = NSControlSizeSmall;
    settingsBtn.font = [NSFont systemFontOfSize:11];

    NSButton *quitBtn = [NSButton buttonWithTitle:@"退出"
                                           target:NSApp
                                           action:@selector(terminate:)];
    quitBtn.bezelStyle = NSBezelStyleRounded;
    quitBtn.controlSize = NSControlSizeSmall;
    quitBtn.font = [NSFont systemFontOfSize:11];

    NSStackView *footer = [NSStackView stackViewWithViews:@[settingsBtn, quitBtn]];
    footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    footer.spacing = 8;
    footer.distribution = NSStackViewDistributionFillEqually;

    NSStackView *stack = [NSStackView stackViewWithViews:@[title, self.popoverSegmented, sep, footer]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 14);
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = [NSView new];
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    vc.view = content;
    NSSize fit = stack.fittingSize;
    vc.preferredContentSize = fit;
    content.frame = NSMakeRect(0, 0, fit.width, fit.height);

    self.popover = [NSPopover new];
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.contentViewController = vc;
}

- (void)popoverWeatherChanged:(NSSegmentedControl *)sender {
    [self userPickedWeather:(TBWeather)sender.selectedSegment];
}

#pragma mark 设置窗口

- (void)showSettings:(id)sender {
    if (!self.settingsWindow) [self buildSettingsWindow];
    [self syncSettingsControls];
    [NSApp activateIgnoringOtherApps:YES];
    [self.settingsWindow makeKeyAndOrderFront:nil];
    // 不然城市输入框会自动抢焦点、套上蓝框
    [self.settingsWindow makeFirstResponder:nil];
    [self.popover close];
}

- (NSTextField *)sectionHeader:(NSString *)text {
    NSTextField *l = [NSTextField labelWithString:text];
    l.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    l.textColor = [NSColor secondaryLabelColor];
    return l;
}

- (NSTextField *)hint:(NSString *)text {
    NSTextField *l = [NSTextField labelWithString:text];
    l.font = [NSFont systemFontOfSize:11];
    l.textColor = [NSColor tertiaryLabelColor];
    l.lineBreakMode = NSLineBreakByWordWrapping;
    l.preferredMaxLayoutWidth = 320;
    return l;
}

- (NSBox *)separator {
    NSBox *b = [NSBox new];
    b.boxType = NSBoxSeparator;
    return b;
}

- (void)buildSettingsWindow {
    TBSettings *s = [TBSettings shared];

    // ---- 通用 ----
    self.loginSwitch = [NSSwitch new];
    self.loginSwitch.target = self;
    self.loginSwitch.action = @selector(loginToggled:);
    self.loginSwitch.state = s.launchAtLogin ? NSControlStateValueOn : NSControlStateValueOff;

    self.iconSwitch = [NSSwitch new];
    self.iconSwitch.target = self;
    self.iconSwitch.action = @selector(iconToggled:);
    self.iconSwitch.state = s.showMenuBarIcon ? NSControlStateValueOn : NSControlStateValueOff;

    self.dockSwitch = [NSSwitch new];
    self.dockSwitch.target = self;
    self.dockSwitch.action = @selector(dockToggled:);
    self.dockSwitch.state = s.showDockIcon ? NSControlStateValueOn : NSControlStateValueOff;

    // ---- 天气 ----
    self.sourcePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.sourcePopup addItemWithTitle:@"手动（锁定当前这一套）"];
    [self.sourcePopup addItemWithTitle:@"定时随机轮换"];
    [self.sourcePopup addItemWithTitle:@"跟随当地天气"];
    self.sourcePopup.target = self;
    self.sourcePopup.action = @selector(sourceChanged:);
    [self.sourcePopup selectItemAtIndex:s.weatherSource];
    [self.sourcePopup.widthAnchor constraintEqualToConstant:180].active = YES;

    self.intervalPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSNumber *m in @[@5, @10, @30, @60]) {
        [self.intervalPopup addItemWithTitle:[NSString stringWithFormat:@"%@ 分钟", m]];
        self.intervalPopup.lastItem.tag = m.integerValue;
    }
    self.intervalPopup.target = self;
    self.intervalPopup.action = @selector(rotationIntervalChanged:);
    [self.intervalPopup selectItemWithTag:s.rotationMinutes];
    [self.intervalPopup.widthAnchor constraintEqualToConstant:180].active = YES;

    self.settingsSegmented =
        [NSSegmentedControl segmentedControlWithLabels:@[@"晴", @"风", @"雨"]
                                          trackingMode:NSSegmentSwitchTrackingSelectOne
                                                target:self
                                                action:@selector(settingsWeatherChanged:)];
    self.settingsSegmented.segmentStyle = NSSegmentStyleRounded;
    self.settingsSegmented.selectedSegment = s.weather;
    [self.settingsSegmented.widthAnchor constraintEqualToConstant:180].active = YES;

    self.cityField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.cityField.placeholderString = @"留空则用系统定位";
    self.cityField.font = [NSFont systemFontOfSize:12];
    self.cityField.target = self;
    self.cityField.action = @selector(cityChanged:);
    [self.cityField.widthAnchor constraintEqualToConstant:126].active = YES;

    self.refreshButton = [NSButton buttonWithTitle:@"刷新"
                                            target:self
                                            action:@selector(refreshWeather:)];
    self.refreshButton.bezelStyle = NSBezelStyleRounded;
    self.refreshButton.controlSize = NSControlSizeSmall;
    self.refreshButton.font = [NSFont systemFontOfSize:11];

    NSStackView *cityRow = [NSStackView stackViewWithViews:@[self.cityField, self.refreshButton]];
    cityRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    cityRow.alignment = NSLayoutAttributeCenterY;
    cityRow.spacing = 8;

    self.weatherStatusLabel = [self hint:@""];

    // ---- 画面 ----
    self.brightnessSlider = [NSSlider sliderWithValue:[s brightnessForWeather:s.weather]
                                             minValue:TB_BRIGHTNESS_MIN
                                             maxValue:TB_BRIGHTNESS_MAX
                                               target:self
                                               action:@selector(brightnessChanged:)];
    [self.brightnessSlider setContinuous:YES];
    self.brightnessSlider.toolTip = @"亮度，每个天气单独记忆";
    [self.brightnessSlider.widthAnchor constraintEqualToConstant:136].active = YES;

    self.brightnessValueLabel = [NSTextField labelWithString:@"100%"];
    self.brightnessValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:11
                                                                      weight:NSFontWeightRegular];
    self.brightnessValueLabel.textColor = [NSColor secondaryLabelColor];
    self.brightnessValueLabel.alignment = NSTextAlignmentRight;
    [self.brightnessValueLabel.widthAnchor constraintEqualToConstant:38].active = YES;

    NSStackView *brightnessRow =
        [NSStackView stackViewWithViews:@[self.brightnessSlider, self.brightnessValueLabel]];
    brightnessRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    brightnessRow.alignment = NSLayoutAttributeCenterY;
    brightnessRow.spacing = 8;

    self.speedSlider = [NSSlider sliderWithValue:[s fpsForWeather:s.weather]
                                        minValue:TB_FPS_MIN
                                        maxValue:TB_FPS_MAX
                                          target:self
                                          action:@selector(speedChanged:)];
    [self.speedSlider setContinuous:YES];
    self.speedSlider.toolTip = @"动画帧率，每个天气单独记忆";
    [self.speedSlider.widthAnchor constraintEqualToConstant:136].active = YES;

    self.speedValueLabel = [NSTextField labelWithString:@"24 fps"];
    self.speedValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:11
                                                                 weight:NSFontWeightRegular];
    self.speedValueLabel.textColor = [NSColor secondaryLabelColor];
    self.speedValueLabel.alignment = NSTextAlignmentRight;
    [self.speedValueLabel.widthAnchor constraintEqualToConstant:38].active = YES;

    NSStackView *speedRow =
        [NSStackView stackViewWithViews:@[self.speedSlider, self.speedValueLabel]];
    speedRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    speedRow.alignment = NSLayoutAttributeCenterY;
    speedRow.spacing = 8;

    // ---- 时段 ----
    self.centerSlotSwitch = [NSSwitch new];
    self.centerSlotSwitch.target = self;
    self.centerSlotSwitch.action = @selector(centerSlotToggled:);
    self.centerSlotSwitch.state = s.centerCurrentSlot ? NSControlStateValueOn : NSControlStateValueOff;

    self.morningPicker = [self timePickerWithMinute:s.morningStart action:@selector(timePicked:)];
    self.noonPicker    = [self timePickerWithMinute:s.noonStart    action:@selector(timePicked:)];
    self.eveningPicker = [self timePickerWithMinute:s.eveningStart action:@selector(timePicked:)];

    NSStackView *slotRow = [NSStackView stackViewWithViews:@[
        [self tinyLabel:@"上午"], self.morningPicker,
        [self tinyLabel:@"中午"], self.noonPicker,
        [self tinyLabel:@"晚上"], self.eveningPicker,
    ]];
    slotRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    slotRow.alignment = NSLayoutAttributeCenterY;
    slotRow.spacing = 6;
    [slotRow setCustomSpacing:14 afterView:self.morningPicker];
    [slotRow setCustomSpacing:14 afterView:self.noonPicker];

    // ---- 省屏 ----
    self.idleField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.idleField.stringValue = [NSString stringWithFormat:@"%ld", (long)s.idleHideMinutes];
    self.idleField.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.idleField.alignment = NSTextAlignmentRight;
    self.idleField.target = self;
    self.idleField.action = @selector(idleChanged:);
    [self.idleField.widthAnchor constraintEqualToConstant:44].active = YES;

    NSStackView *idleRow = [NSStackView stackViewWithViews:@[
        self.idleField, [self tinyLabel:@"分钟（0 = 不熄）"]]];
    idleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    idleRow.alignment = NSLayoutAttributeCenterY;
    idleRow.spacing = 6;

    self.pixelShiftSwitch = [NSSwitch new];
    self.pixelShiftSwitch.target = self;
    self.pixelShiftSwitch.action = @selector(pixelShiftToggled:);
    self.pixelShiftSwitch.state = s.pixelShift ? NSControlStateValueOn : NSControlStateValueOff;

    self.appPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.appPopup.target = self;
    self.appPopup.action = @selector(appPopupChanged:);
    [self.appPopup.widthAnchor constraintEqualToConstant:180].active = YES;

    self.powerHintLabel = [self hint:@""];

    // ---- 组装：所有行塞进同一个 grid，标签才会对齐 ----
    NSMutableArray<NSArray<NSView *> *> *rows = [NSMutableArray array];
    NSMutableArray<NSNumber *> *wideRows = [NSMutableArray array];

    void (^wide)(NSView *) = ^(NSView *v) {
        [rows addObject:@[v, [NSView new]]];
        [wideRows addObject:@(rows.count - 1)];
    };
    void (^pair)(NSString *, NSView *) = ^(NSString *title, NSView *control) {
        [rows addObject:@[[NSTextField labelWithString:title], control]];
    };

    // ===== 页 1：显示 =====
    wide([self sectionHeader:@"天气"]);
    pair(@"来源", self.sourcePopup);
    pair(@"间隔", self.intervalPopup);
    pair(@"当前", self.settingsSegmented);
    pair(@"城市", cityRow);
    wide(self.weatherStatusLabel);
    wide([self separator]);

    wide([self sectionHeader:@"画面"]);
    pair(@"亮度", brightnessRow);
    pair(@"速度", speedRow);
    wide([self hint:@"亮度和速度都按天气分别记忆，切到哪套就用哪套。"]);
    wide([self separator]);

    wide([self sectionHeader:@"时段"]);
    pair(@"当前时段放中间", self.centerSlotSwitch);
    wide(slotRow);
    self.slotHintLabel = [self hint:@""];
    wide(self.slotHintLabel);

    NSView *panel1 = [self gridPanelWithRows:rows wideRows:wideRows width:400];

    // ===== 页 2：通用 + 省屏 =====
    // 注意：wide/pair 这两个 block 抓的是原来的数组对象，只能清空不能重新赋值
    [rows removeAllObjects];
    [wideRows removeAllObjects];

    wide([self sectionHeader:@"通用"]);
    pair(@"开机自启", self.loginSwitch);
    pair(@"显示 Dock 图标", self.dockSwitch);
    pair(@"显示菜单栏图标", self.iconSwitch);
    wide([self hint:@"关掉 Dock 图标就是纯菜单栏工具（像 Mos / Aldente 那样）。两个都关掉就只能靠快捷键：⌃⌥⌘, 开设置，⌃⌥⌘T 切天气。"]);
    wide([self separator]);

    wide([self sectionHeader:@"省屏（OLED 老化）"]);
    pair(@"闲置熄灭", idleRow);
    pair(@"像素位移", self.pixelShiftSwitch);
    pair(@"只在指定 App 显示", self.appPopup);
    wide(self.powerHintLabel);

    NSView *panel2 = [self gridPanelWithRows:rows wideRows:wideRows width:400];

    // ===== 两页：分段控件 + 手动切换（NSTabView 的尺寸测量不靠谱，不用它）=====
    CGFloat panelH = MAX(panel1.frame.size.height, panel2.frame.size.height);
    panel1.frame = NSMakeRect(0, 0, 400, panelH);
    panel2.frame = NSMakeRect(0, 0, 400, panelH);
    panel2.hidden = YES;

    const CGFloat segH = 26, segGap = 10, topPad = 12;
    CGFloat winH = panelH + segH + segGap + topPad;

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, winH)];

    self.settingsSeg =
        [NSSegmentedControl segmentedControlWithLabels:@[@"显示", @"通用"]
                                          trackingMode:NSSegmentSwitchTrackingSelectOne
                                                target:self
                                                action:@selector(settingsPageChanged:)];
    self.settingsSeg.segmentStyle = NSSegmentStyleRounded;
    self.settingsSeg.selectedSegment = 0;
    self.settingsSeg.frame = NSMakeRect(round((400 - 160) / 2.0), panelH + segGap, 160, segH);

    self.settingsPanelHost = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, panelH)];
    [self.settingsPanelHost addSubview:panel1];
    [self.settingsPanelHost addSubview:panel2];
    self.settingsPanelDisplay = panel1;
    self.settingsPanelGeneral = panel2;

    [content addSubview:self.settingsPanelHost];
    [content addSubview:self.settingsSeg];

    NSSize winSize = NSMakeSize(400, winH);

    NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    // 没有 Dock 图标时最小化就找不回来了，创建时就别给这个按钮
    if ([TBSettings shared].showDockIcon) mask |= NSWindowStyleMaskMiniaturizable;

    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, winSize.width, winSize.height)
                                                styleMask:mask
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = @"设置";
    win.contentView = content;
    win.releasedWhenClosed = NO;
    win.opaque = YES;
    [win center];
    [win setContentSize:winSize];

    self.settingsWindow = win;
    [self syncSettingsControls];
    [self syncWeatherStatus];
    // 窗口是这会儿才建的，得再走一次策略，才能按"有没有 Dock 图标"决定最小化按钮
    [self applyActivationPolicy];
}

/// 把一堆行拼成一块对齐的网格面板
- (NSView *)gridPanelWithRows:(NSArray<NSArray<NSView *> *> *)rows
                     wideRows:(NSArray<NSNumber *> *)wideRows
                        width:(CGFloat)width {
    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.rowSpacing = 9;
    grid.columnSpacing = 14;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;

    for (NSNumber *r in wideRows) {
        NSInteger idx = r.integerValue;
        [grid mergeCellsInHorizontalRange:NSMakeRange(0, 2) verticalRange:NSMakeRange(idx, 1)];
        // 合并后的单元格默认继承第 0 列的右对齐，改回左对齐
        [grid cellAtColumnIndex:0 rowIndex:idx].xPlacement = NSGridCellPlacementLeading;
    }

    grid.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, 100)];
    [content addSubview:grid];

    // 先临时钉住底边量出自然高度，量完把底边放开——这样面板被撑高时
    // 多出来的空间留在下面，而不是把行距拉散
    NSLayoutConstraint *bottom =
        [grid.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16];
    [NSLayoutConstraint activateConstraints:@[
        [grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:22],
        [grid.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22],
        [grid.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
        bottom,
        [content.widthAnchor constraintEqualToConstant:width],
    ]];

    NSSize fit = [content fittingSize];
    bottom.active = NO;
    content.frame = NSMakeRect(0, 0, width, fit.height);
    return content;
}

- (NSTextField *)tinyLabel:(NSString *)text {
    NSTextField *l = [NSTextField labelWithString:text];
    l.font = [NSFont systemFontOfSize:12];
    l.textColor = [NSColor secondaryLabelColor];
    return l;
}

- (NSDatePicker *)timePickerWithMinute:(NSInteger)minute action:(SEL)action {
    NSDatePicker *p = [[NSDatePicker alloc] initWithFrame:NSMakeRect(0, 0, 62, 22)];
    p.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    p.datePickerElements = NSDatePickerElementFlagHourMinute;
    p.datePickerMode = NSDatePickerModeSingle;
    p.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    p.target = self;
    p.action = action;
    p.dateValue = [self dateForMinuteOfDay:minute];
    [p.widthAnchor constraintEqualToConstant:62].active = YES;
    return p;
}

- (NSDate *)dateForMinuteOfDay:(NSInteger)minute {
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = 2001; c.month = 1; c.day = 1;
    c.hour = minute / 60;
    c.minute = minute % 60;
    return [[NSCalendar currentCalendar] dateFromComponents:c];
}

- (NSInteger)minuteOfDayForPicker:(NSDatePicker *)p {
    NSDateComponents *c = [[NSCalendar currentCalendar]
                           components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:p.dateValue];
    return c.hour * 60 + c.minute;
}

- (void)settingsPageChanged:(NSSegmentedControl *)sender {
    BOOL general = (sender.selectedSegment == 1);
    self.settingsPanelDisplay.hidden = general;
    self.settingsPanelGeneral.hidden = !general;
}

- (void)syncSettingsControls {
    TBSettings *s = [TBSettings shared];
    self.settingsSegmented.selectedSegment = s.weather;
    self.iconSwitch.state = s.showMenuBarIcon ? NSControlStateValueOn : NSControlStateValueOff;
    self.dockSwitch.state = s.showDockIcon ? NSControlStateValueOn : NSControlStateValueOff;
    self.loginSwitch.state = s.launchAtLogin ? NSControlStateValueOn : NSControlStateValueOff;
    [self.sourcePopup selectItemAtIndex:s.weatherSource];
    [self.intervalPopup selectItemWithTag:s.rotationMinutes];
    self.intervalPopup.enabled = (s.weatherSource == TBWeatherSourceRandom);
    if (![self.cityField.stringValue isEqualToString:(s.weatherCity ?: @"")])
        self.cityField.stringValue = s.weatherCity ?: @"";
    [self syncBrightnessControls];
    [self syncSpeedControls];
    [self syncTimeSlotControls];

    self.idleField.stringValue = [NSString stringWithFormat:@"%ld", (long)s.idleHideMinutes];
    self.pixelShiftSwitch.state = s.pixelShift ? NSControlStateValueOn : NSControlStateValueOff;
    [self rebuildAppMenu];
    [self syncPowerStatus];
}

#pragma mark 速度

- (void)syncSpeedControls {
    TBSettings *s = [TBSettings shared];
    double f = [s fpsForWeather:s.weather];
    self.speedSlider.doubleValue = f;
    if (fabs(self.display.fps - f) > 0.01) {   // 只有真变了才重建 timer
        self.display.fps = f;
        fprintf(stderr, "[tb] speed %s -> %.0f fps\n",
                [TBSettings slugForWeather:s.weather].UTF8String, f);
    }
    [self updateSpeedLabel];
}

- (void)updateSpeedLabel {
    TBSettings *s = [TBSettings shared];
    self.speedValueLabel.stringValue =
        [NSString stringWithFormat:@"%.0f fps", [s fpsForWeather:s.weather]];
}

- (void)speedChanged:(NSSlider *)sender {
    TBSettings *s = [TBSettings shared];
    double f = round(sender.doubleValue);
    if (fabs(f - TB_FPS_DEFAULT) < 1.0) f = TB_FPS_DEFAULT;   // 24 fps 附近吸附
    [s setFPS:f forWeather:s.weather];
    [self updateSpeedLabel];
}

- (void)speedDidChange:(NSNotification *)note {
    TBSettings *s = [TBSettings shared];
    self.display.fps = [s fpsForWeather:s.weather];
    [self updateSpeedLabel];
    fprintf(stderr, "[tb] speed live -> %.0f fps\n", self.display.fps);
}

#pragma mark 时段

- (void)syncTimeSlotControls {
    TBSettings *s = [TBSettings shared];
    self.centerSlotSwitch.state = s.centerCurrentSlot ? NSControlStateValueOn : NSControlStateValueOff;
    self.morningPicker.dateValue = [self dateForMinuteOfDay:s.morningStart];
    self.noonPicker.dateValue    = [self dateForMinuteOfDay:s.noonStart];
    self.eveningPicker.dateValue = [self dateForMinuteOfDay:s.eveningStart];

    NSArray *names = @[@"上午", @"中午", @"晚上"];
    TBTimeSlot slot = [s currentSlot];
    if (s.centerCurrentSlot)
        self.slotHintLabel.stringValue =
            [NSString stringWithFormat:@"现在是「%@」，这一套排在中间。晚上一直持续到次日「上午」。",
             names[(NSInteger)slot]];
    else
        self.slotHintLabel.stringValue =
            [NSString stringWithFormat:@"现在是「%@」。打开上面的开关，这一套就会排到中间。",
             names[(NSInteger)slot]];
}

- (void)centerSlotToggled:(NSSwitch *)sender {
    [TBSettings shared].centerCurrentSlot = (sender.state == NSControlStateValueOn);
}

- (void)timePicked:(NSDatePicker *)sender {
    TBSettings *s = [TBSettings shared];
    NSInteger m = [self minuteOfDayForPicker:sender];
    if (sender == self.morningPicker)      s.morningStart = m;
    else if (sender == self.noonPicker)    s.noonStart = m;
    else if (sender == self.eveningPicker) s.eveningStart = m;
}

#pragma mark 省屏 UI

- (void)idleChanged:(NSTextField *)sender {
    NSInteger m = sender.integerValue;
    if (m < 0) m = 0;
    if (m > 240) m = 240;
    [TBSettings shared].idleHideMinutes = m;
    sender.stringValue = [NSString stringWithFormat:@"%ld", (long)m];
    [self syncPowerStatus];
}

- (void)pixelShiftToggled:(NSSwitch *)sender {
    [TBSettings shared].pixelShift = (sender.state == NSControlStateValueOn);
}

/// 把"运行中的普通 App"铺进下拉菜单，勾上的就是在白名单里的
- (void)rebuildAppMenu {
    if (!self.appPopup) return;

    NSArray<NSString *> *wl = [TBSettings shared].appWhitelist;
    NSArray<NSRunningApplication *> *apps = [[NSWorkspace sharedWorkspace].runningApplications
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:
            ^BOOL(NSRunningApplication *a, NSDictionary *bind) {
                return a.activationPolicy == NSApplicationActivationPolicyRegular &&
                       a.localizedName.length > 0 && a.bundleIdentifier.length > 0;
            }]];
    apps = [apps sortedArrayUsingComparator:^NSComparisonResult(NSRunningApplication *a,
                                                               NSRunningApplication *b) {
        return [a.localizedName localizedCompare:b.localizedName];
    }];

    [self.appPopup removeAllItems];
    NSString *title = wl.count == 0
        ? @"未限制"
        : [NSString stringWithFormat:@"已选 %lu 个", (unsigned long)wl.count];
    [self.appPopup addItemWithTitle:title];
    self.appPopup.lastItem.enabled = NO;

    for (NSRunningApplication *a in apps) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:a.localizedName
                                                    action:nil
                                             keyEquivalent:@""];
        it.representedObject = a.bundleIdentifier;
        it.state = [wl containsObject:a.bundleIdentifier] ? NSControlStateValueOn
                                                          : NSControlStateValueOff;
        NSImage *icon = a.icon;
        if (icon) {
            NSImage *small = [icon copy];
            small.size = NSMakeSize(16, 16);
            it.image = small;
        }
        [self.appPopup.menu addItem:it];
    }

    if (apps.count == 0) {
        NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:@"（没有运行中的 App）"
                                                      action:nil keyEquivalent:@""];
        none.enabled = NO;
        [self.appPopup.menu addItem:none];
    }
    [self.appPopup selectItemAtIndex:0];
}

/// NSPopUpButton 只发自己的 action，菜单项的 action 不生效——所以在这里统一处理
- (void)appPopupChanged:(NSPopUpButton *)sender {
    NSString *bid = sender.selectedItem.representedObject;
    if (!bid) {                       // 选中的是"未限制/已选 N 个"这个占位标题
        [sender selectItemAtIndex:0];
        return;
    }

    NSMutableArray<NSString *> *wl = [[TBSettings shared].appWhitelist mutableCopy];
    if ([wl containsObject:bid]) [wl removeObject:bid];
    else [wl addObject:bid];
    [TBSettings shared].appWhitelist = wl;

    [self rebuildAppMenu];
    [self syncPowerStatus];
}

#pragma mark 亮度

/// 把当前天气记着的亮度同步到滑块、数值标签和条上
- (void)syncBrightnessControls {
    TBSettings *s = [TBSettings shared];
    double b = [s brightnessForWeather:s.weather];
    self.brightnessSlider.doubleValue = b;
    self.display.brightness = b;
    [self updateBrightnessLabel];
    fprintf(stderr, "[tb] brightness %s -> %.2f\n",
            [TBSettings slugForWeather:s.weather].UTF8String, b);
}

- (void)updateBrightnessLabel {
    TBSettings *s = [TBSettings shared];
    self.brightnessValueLabel.stringValue =
        [NSString stringWithFormat:@"%.0f%%", [s brightnessForWeather:s.weather] * 100.0];
}

- (void)brightnessChanged:(NSSlider *)sender {
    TBSettings *s = [TBSettings shared];
    // 存到 1% 精度，免得存一堆 0.8734213
    double b = round(sender.doubleValue * 100.0) / 100.0;
    // 100% 附近做个吸附，方便回到"原始画面"
    if (fabs(b - 1.0) < 0.03) b = 1.0;
    [s setBrightness:b forWeather:s.weather];
    [self updateBrightnessLabel];   // 滑块本身不回调，避免和拖拽打架
}

- (void)brightnessDidChange:(NSNotification *)note {
    TBSettings *s = [TBSettings shared];
    self.display.brightness = [s brightnessForWeather:s.weather];
    [self updateBrightnessLabel];
    fprintf(stderr, "[tb] brightness live -> %.2f\n", self.display.brightness);
}

- (void)settingsWeatherChanged:(NSSegmentedControl *)sender {
    [self userPickedWeather:(TBWeather)sender.selectedSegment];
}

/// 用户手动点/按了天气：如果正在"跟随当地天气"，就退出跟随（不然马上被下一次刷新覆盖）
- (void)userPickedWeather:(TBWeather)w {
    TBSettings *s = [TBSettings shared];
    if (s.weatherSource == TBWeatherSourceLocal) {
        fprintf(stderr, "[tb] 手动切天气 → 退出跟随模式\n");
        s.weatherSource = TBWeatherSourceManual;
        [self syncSettingsControls];
        [self syncWeatherStatus];
    }
    s.weather = w;
}

- (void)iconToggled:(NSSwitch *)sender {
    [TBSettings shared].showMenuBarIcon = (sender.state == NSControlStateValueOn);
}

- (void)dockToggled:(NSSwitch *)sender {
    [TBSettings shared].showDockIcon = (sender.state == NSControlStateValueOn);
}

- (void)loginToggled:(NSSwitch *)sender {
    BOOL want = (sender.state == NSControlStateValueOn);
    NSError *err = nil;
    if (![[TBSettings shared] setLaunchAtLogin:want error:&err]) {
        sender.state = want ? NSControlStateValueOff : NSControlStateValueOn;
        NSAlert *a = [NSAlert new];
        a.messageText = @"无法修改开机自启";
        a.informativeText = err.localizedDescription ?: @"系统拒绝了这次操作。";
        a.alertStyle = NSAlertStyleWarning;
        [a runModal];
        return;
    }
    [self syncSettingsControls];
}

- (void)sourceChanged:(NSPopUpButton *)sender {
    TBSettings *s = [TBSettings shared];
    s.weatherSource = (TBWeatherSource)sender.indexOfSelectedItem;
    [self syncSettingsControls];
    [self syncWeatherStatus];
    if (s.weatherSource == TBWeatherSourceLocal) [[TBWeatherService shared] refresh];
}

- (void)cityChanged:(NSTextField *)sender {
    [TBSettings shared].weatherCity = sender.stringValue;
    [[TBWeatherService shared] refresh];
}

- (void)refreshWeather:(id)sender {
    [[TBWeatherService shared] refresh];
}

- (void)rotationIntervalChanged:(NSPopUpButton *)sender {
    [TBSettings shared].rotationMinutes = sender.selectedItem.tag;
    [self syncSettingsControls];
}

#pragma mark 快捷键

- (void)registerHotKeys {
    // ⌃⌥⌘T —— 循环切天气
    self.cycleHotKey = [[TBHotKey alloc] initWithKeyCode:kVK_ANSI_T
                                               modifiers:(controlKey | optionKey | cmdKey)
                                                 handler:^{
        TBSettings *s = [TBSettings shared];
        [self userPickedWeather:(TBWeather)((s.weather + 1) % 3)];
    }];

    // ⌃⌥⌘, —— 打开设置
    self.settingsHotKey = [[TBHotKey alloc] initWithKeyCode:kVK_ANSI_Comma
                                                  modifiers:(controlKey | optionKey | cmdKey)
                                                    handler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showSettings:nil];
        });
    }];
}

@end
