//
//  TBSettings.m
//

#import "TBSettings.h"
#import <ServiceManagement/ServiceManagement.h>
#import <math.h>

NSString * const TBSettingsWeatherDidChangeNotification = @"TBSettingsWeatherDidChange";
NSString * const TBSettingsDidChangeNotification        = @"TBSettingsDidChange";
NSString * const TBSettingsBrightnessDidChangeNotification = @"TBSettingsBrightnessDidChange";
NSString * const TBSettingsSpeedDidChangeNotification      = @"TBSettingsSpeedDidChange";
NSString * const TBSettingsTimeSlotDidChangeNotification   = @"TBSettingsTimeSlotDidChange";

static NSString * const kKeyWeather        = @"weather";
static NSString * const kKeyShowMenuBar    = @"showMenuBarIcon";
static NSString * const kKeyShowDockIcon   = @"showDockIcon";
static NSString * const kKeyWeatherSource  = @"weatherSource";
static NSString * const kKeyRotationMinute = @"rotationMinutes";
static NSString * const kKeyOldRotation    = @"rotationMode";   // 老版本，只用于迁移
static NSString * const kKeyCenterSlot     = @"centerCurrentSlot";
static NSString * const kKeyMorningStart   = @"morningStart";
static NSString * const kKeyNoonStart      = @"noonStart";
static NSString * const kKeyEveningStart   = @"eveningStart";
static NSString * const kKeyWeatherCity    = @"weatherCity";
static NSString * const kKeyLoginPath      = @"loginRegisteredPath";
static NSString * const kKeyIdleHide       = @"idleHideMinutes";
static NSString * const kKeyPixelShift     = @"pixelShift";
static NSString * const kKeyAppWhitelist   = @"appWhitelist";

static NSString * const kLaunchAgentLabel  = @"com.egc.touchbarexp";

/// 每个天气一个键：brightness.0 / .1 / .2
static NSString *TBKeyForBrightness(TBWeather w) {
    return [NSString stringWithFormat:@"brightness.%ld", (long)w];
}
/// 每个天气一个键：fps.0 / .1 / .2
static NSString *TBKeyForFPS(TBWeather w) {
    return [NSString stringWithFormat:@"fps.%ld", (long)w];
}

@implementation TBSettings

+ (instancetype)shared {
    static TBSettings *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TBSettings new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d registerDefaults:@{
            kKeyWeather:        @(TBWeatherQing),
            kKeyShowMenuBar:    @YES,
            kKeyShowDockIcon:   @NO,     // 默认像 Aldente / Mos 那样：只在菜单栏，不占 Dock
            kKeyWeatherSource:  @(TBWeatherSourceManual),
            kKeyRotationMinute: @10,
            kKeyCenterSlot:     @NO,
            kKeyMorningStart:   @(6 * 60),
            kKeyNoonStart:      @(11 * 60),
            kKeyEveningStart:   @(18 * 60),
            kKeyIdleHide:       @5,
            kKeyPixelShift:     @YES,
            kKeyAppWhitelist:   @[],
            TBKeyForBrightness(TBWeatherQing): @1.0,
            TBKeyForBrightness(TBWeatherFeng): @1.0,
            TBKeyForBrightness(TBWeatherYu):   @1.0,
            TBKeyForFPS(TBWeatherQing): @(TB_FPS_DEFAULT),
            TBKeyForFPS(TBWeatherFeng): @(TB_FPS_DEFAULT),
            TBKeyForFPS(TBWeatherYu):   @(TB_FPS_DEFAULT),
        }];

        // 老版本只有 rotationMode（0 关 / 1 定时随机），迁移到 weatherSource
        if (![d objectForKey:kKeyWeatherSource] && [d objectForKey:kKeyOldRotation]) {
            [d setInteger:[d integerForKey:kKeyOldRotation] forKey:kKeyWeatherSource];
            fprintf(stderr, "[tb] migrated rotationMode -> weatherSource\n");
        }
    }
    return self;
}

#pragma mark - 读写

- (TBWeather)weather {
    return (TBWeather)[[NSUserDefaults standardUserDefaults] integerForKey:kKeyWeather];
}

- (void)setWeather:(TBWeather)weather {
    if (weather < TBWeatherQing || weather > TBWeatherYu) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL changed = ([d integerForKey:kKeyWeather] != weather);
    [d setInteger:weather forKey:kKeyWeather];
    if (changed)
        [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsWeatherDidChangeNotification
                                                            object:self];
}

- (BOOL)showMenuBarIcon {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kKeyShowMenuBar];
}

- (void)setShowMenuBarIcon:(BOOL)v {
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:kKeyShowMenuBar];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsDidChangeNotification object:self];
}

- (BOOL)showDockIcon {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kKeyShowDockIcon];
}

- (void)setShowDockIcon:(BOOL)v {
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:kKeyShowDockIcon];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsDidChangeNotification object:self];
}

- (TBWeatherSource)weatherSource {
    return (TBWeatherSource)[[NSUserDefaults standardUserDefaults] integerForKey:kKeyWeatherSource];
}

- (void)setWeatherSource:(TBWeatherSource)src {
    if (src < TBWeatherSourceManual || src > TBWeatherSourceLocal) return;
    [[NSUserDefaults standardUserDefaults] setInteger:src forKey:kKeyWeatherSource];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsDidChangeNotification object:self];
}

- (NSInteger)rotationMinutes {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kKeyRotationMinute];
}

- (void)setRotationMinutes:(NSInteger)m {
    [[NSUserDefaults standardUserDefaults] setInteger:m forKey:kKeyRotationMinute];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsDidChangeNotification object:self];
}

#pragma mark - 省屏

- (NSInteger)idleHideMinutes {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kKeyIdleHide];
}
- (void)setIdleHideMinutes:(NSInteger)m {
    if (m < 0) m = 0;
    if (m > 240) m = 240;
    [[NSUserDefaults standardUserDefaults] setInteger:m forKey:kKeyIdleHide];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsDidChangeNotification object:self];
}

- (BOOL)pixelShift {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kKeyPixelShift];
}
- (void)setPixelShift:(BOOL)v {
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:kKeyPixelShift];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsDidChangeNotification object:self];
}

- (NSArray<NSString *> *)appWhitelist {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:kKeyAppWhitelist];
    return [a isKindOfClass:[NSArray class]] ? a : @[];
}
- (void)setAppWhitelist:(NSArray<NSString *> *)list {
    [[NSUserDefaults standardUserDefaults] setObject:(list ?: @[]) forKey:kKeyAppWhitelist];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsDidChangeNotification object:self];
}

- (NSString *)weatherCity {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kKeyWeatherCity] ?: @"";
}

- (void)setWeatherCity:(NSString *)city {
    NSString *v = [city stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    [[NSUserDefaults standardUserDefaults] setObject:v forKey:kKeyWeatherCity];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsDidChangeNotification object:self];
}

- (void)rememberWeatherCity:(NSString *)city {
    if (city.length == 0) return;
    [[NSUserDefaults standardUserDefaults] setObject:city forKey:kKeyWeatherCity];
    fprintf(stderr, "[tb] 记住城市：%s（以后不再请求定位）\n", city.UTF8String);
}

#pragma mark - 亮度

- (double)brightnessForWeather:(TBWeather)w {
    if (w < TBWeatherQing || w > TBWeatherYu) return 1.0;
    double b = [[NSUserDefaults standardUserDefaults] doubleForKey:TBKeyForBrightness(w)];
    if (b <= 0.0) b = 1.0;                      // 没存过
    if (b < TB_BRIGHTNESS_MIN) b = TB_BRIGHTNESS_MIN;
    if (b > TB_BRIGHTNESS_MAX) b = TB_BRIGHTNESS_MAX;
    return b;
}

- (void)setBrightness:(double)b forWeather:(TBWeather)w {
    if (w < TBWeatherQing || w > TBWeatherYu) return;
    if (b < TB_BRIGHTNESS_MIN) b = TB_BRIGHTNESS_MIN;
    if (b > TB_BRIGHTNESS_MAX) b = TB_BRIGHTNESS_MAX;

    double old = [self brightnessForWeather:w];
    [[NSUserDefaults standardUserDefaults] setDouble:b forKey:TBKeyForBrightness(w)];
    if (fabs(b - old) > 0.0005)
        [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsBrightnessDidChangeNotification
                                                            object:self];
}

- (TBWeather)rotateToRandomWeather {
    TBWeather cur = self.weather;
    TBWeather next = cur;
    // 三选一，避开当前，保证真的换了一套
    for (int guard = 0; guard < 16 && next == cur; guard++)
        next = (TBWeather)(arc4random_uniform(3));
    self.weather = next;
    return next;
}

#pragma mark - 速度

- (double)fpsForWeather:(TBWeather)w {
    if (w < TBWeatherQing || w > TBWeatherYu) return TB_FPS_DEFAULT;
    double f = [[NSUserDefaults standardUserDefaults] doubleForKey:TBKeyForFPS(w)];
    if (f <= 0.0) f = TB_FPS_DEFAULT;
    if (f < TB_FPS_MIN) f = TB_FPS_MIN;
    if (f > TB_FPS_MAX) f = TB_FPS_MAX;
    return f;
}

- (void)setFPS:(double)fps forWeather:(TBWeather)w {
    if (w < TBWeatherQing || w > TBWeatherYu) return;
    if (fps < TB_FPS_MIN) fps = TB_FPS_MIN;
    if (fps > TB_FPS_MAX) fps = TB_FPS_MAX;

    double old = [self fpsForWeather:w];
    [[NSUserDefaults standardUserDefaults] setDouble:fps forKey:TBKeyForFPS(w)];
    if (fabs(fps - old) > 0.0005)
        [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsSpeedDidChangeNotification
                                                            object:self];
}

#pragma mark - 时段

- (NSInteger)morningStart {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kKeyMorningStart];
}
- (void)setMorningStart:(NSInteger)m {
    [[NSUserDefaults standardUserDefaults] setInteger:m forKey:kKeyMorningStart];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsTimeSlotDidChangeNotification object:self];
}
- (NSInteger)noonStart {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kKeyNoonStart];
}
- (void)setNoonStart:(NSInteger)m {
    [[NSUserDefaults standardUserDefaults] setInteger:m forKey:kKeyNoonStart];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsTimeSlotDidChangeNotification object:self];
}
- (NSInteger)eveningStart {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kKeyEveningStart];
}
- (void)setEveningStart:(NSInteger)m {
    [[NSUserDefaults standardUserDefaults] setInteger:m forKey:kKeyEveningStart];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsTimeSlotDidChangeNotification object:self];
}

- (BOOL)centerCurrentSlot {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kKeyCenterSlot];
}
- (void)setCenterCurrentSlot:(BOOL)v {
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:kKeyCenterSlot];
    [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsTimeSlotDidChangeNotification object:self];
}

/// 三个分界点排好序后判断落在哪一段。
/// 允许用户把三个点设成任意顺序（比如上午 06:00 / 中午 11:00 / 晚上 18:00），
/// 也允许跨夜（晚上 22:00 → 次日 06:00）。
- (TBTimeSlot)slotForMinuteOfDay:(NSInteger)minute {
    minute = ((minute % 1440) + 1440) % 1440;

    NSInteger m = self.morningStart, n = self.noonStart, e = self.eveningStart;
    // 按时间轴排序，最小的那个点是"晚上结束 / 上午开始"
    NSInteger pts[3] = {m, n, e};
    for (int i = 0; i < 3; i++)
        for (int j = i + 1; j < 3; j++)
            if (pts[j] < pts[i]) { NSInteger t = pts[i]; pts[i] = pts[j]; pts[j] = t; }

    // 排序后每个点的身份
    TBTimeSlot slotOf[3];
    for (int i = 0; i < 3; i++) {
        if (pts[i] == m)      slotOf[i] = TBTimeSlotMorning;
        else if (pts[i] == n) slotOf[i] = TBTimeSlotNoon;
        else                  slotOf[i] = TBTimeSlotEvening;
    }

    // 落在 [pts[i], pts[i+1]) 里，时段取 pts[i] 的；小于 pts[0] 的属于"晚上"
    TBTimeSlot cur = TBTimeSlotEvening;
    for (int i = 0; i < 3; i++) {
        if (minute >= pts[i]) cur = slotOf[i];
    }
    return cur;
}

- (TBTimeSlot)currentSlot {
    NSDateComponents *c = [[NSCalendar currentCalendar]
                           components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];
    return [self slotForMinuteOfDay:c.hour * 60 + c.minute];
}

- (NSInteger)currentSlotClipIndex {
    return (NSInteger)[self currentSlot];
}

- (NSArray<NSNumber *> *)clipOrder {
    if (!self.centerCurrentSlot) return @[@0, @1, @2];

    NSInteger cur = [self currentSlotClipIndex];
    NSMutableArray<NSNumber *> *others = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++)
        if (i != cur) [others addObject:@(i)];
    // 当前时段放中间，另外两个保持原来的相对顺序
    return @[others[0], @(cur), others[1]];
}

#pragma mark - 命名

+ (NSString *)displayNameForWeather:(TBWeather)w {
    switch (w) {
        case TBWeatherQing: return @"晴";
        case TBWeatherFeng: return @"风";
        case TBWeatherYu:   return @"雨";
    }
    return @"?";
}

+ (NSString *)slugForWeather:(TBWeather)w {
    switch (w) {
        case TBWeatherQing: return @"qing";
        case TBWeatherFeng: return @"feng";
        case TBWeatherYu:   return @"yu";
    }
    return @"qing";
}

#pragma mark - 帧目录

- (NSArray<NSString *> *)clipDirectoriesForWeather:(TBWeather)w {
    NSString *slug = [TBSettings slugForWeather:w];

    // 1) 优先用 App 包内资源
    NSString *res = [[NSBundle mainBundle] resourcePath];
    NSString *root = [res stringByAppendingPathComponent:@"frames"];

    // 2) 开发模式：包内没有就退回仓库里的 assets/frames
    if (![[NSFileManager defaultManager] fileExistsAtPath:root]) {
        // .../dist/TouchBarExp.app/Contents/MacOS/TouchBarExp → 上溯到仓库根
        NSString *exe = [[NSBundle mainBundle] executablePath];
        NSString *repo = [[[[exe stringByDeletingLastPathComponent]   // MacOS
                            stringByDeletingLastPathComponent]        // Contents
                           stringByDeletingLastPathComponent]         // .app
                          stringByDeletingLastPathComponent];         // dist
        root = [repo stringByAppendingPathComponent:@"assets/frames"];
    }

    NSMutableArray *dirs = [NSMutableArray array];
    for (NSString *t in @[@"z", @"m", @"w"]) {
        NSString *d = [root stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"%@_%@", slug, t]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:
              [d stringByAppendingPathComponent:@"sharp"]]) return nil;
        [dirs addObject:d];
    }
    return dirs;
}

#pragma mark - 开机自启

- (NSString *)launchAgentPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"Library/LaunchAgents/%@.plist", kLaunchAgentLabel]];
}

- (BOOL)launchAtLogin {
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self launchAgentPath]]) return YES;
    if (@available(macOS 13.0, *)) {
        return [SMAppService mainAppService].status == SMAppServiceStatusEnabled;
    }
    return NO;
}

- (BOOL)setLaunchAtLogin:(BOOL)enabled error:(NSError **)error {
    if (enabled) {
        // 先试系统标准做法
        if (@available(macOS 13.0, *)) {
            NSError *e = nil;
            if ([[SMAppService mainAppService] registerAndReturnError:&e]) {
                fprintf(stderr, "[tb] launch-at-login via SMAppService OK\n");
                [self rememberLoginPath];
                return YES;
            }
            fprintf(stderr, "[tb] SMAppService failed (%s), falling back to LaunchAgent\n",
                    e.localizedDescription.UTF8String);
        }
        // 回退：自己写 LaunchAgent
        BOOL ok = [self writeLaunchAgent:error];
        if (ok) [self rememberLoginPath];
        return ok;
    }

    // 关闭：两条路都清掉
    if (@available(macOS 13.0, *)) {
        NSError *e = nil;
        if ([SMAppService mainAppService].status == SMAppServiceStatusEnabled) {
            if (![[SMAppService mainAppService] unregisterAndReturnError:&e])
                fprintf(stderr, "[tb] SMAppService unregister failed: %s\n",
                        e.localizedDescription.UTF8String);
        }
    }
    return [self removeLaunchAgent:error];
}

- (void)rememberLoginPath {
    [[NSUserDefaults standardUserDefaults] setObject:[[NSBundle mainBundle] bundlePath]
                                             forKey:kKeyLoginPath];
}

- (void)healLoginItemIfNeeded {
    if (![self launchAtLogin]) return;

    NSString *cur = [[NSBundle mainBundle] bundlePath];
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kKeyLoginPath];
    if (saved.length && [cur isEqualToString:saved]) return;

    // 没记录过（老版本）或者路径变了：重注册一次，让它指向现在这份
    fprintf(stderr, "[tb] 登录项路径需要修正：'%s' -> '%s'\n",
            saved.UTF8String ?: "(空)", cur.UTF8String);
    NSError *e = nil;
    [self setLaunchAtLogin:NO error:&e];
    if ([self setLaunchAtLogin:YES error:&e])
        fprintf(stderr, "[tb] 登录项已指向 %s\n", cur.UTF8String);
    else
        fprintf(stderr, "[tb] 登录项修正失败：%s\n", e.localizedDescription.UTF8String);
}

- (BOOL)writeLaunchAgent:(NSError **)error {
    NSString *exe = [[NSBundle mainBundle] executablePath];
    if (!exe) {
        if (error) *error = [NSError errorWithDomain:@"tbexp" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"找不到可执行文件"}];
        return NO;
    }
    NSDictionary *plist = @{
        @"Label": kLaunchAgentLabel,
        @"ProgramArguments": @[exe],
        @"RunAtLoad": @YES,
        @"KeepAlive": @NO,
        @"ProcessType": @"Interactive",
    };
    NSString *path = [self launchAgentPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0 error:error];
    if (!data) return NO;
    if (![data writeToFile:path atomically:YES]) {
        if (error) *error = [NSError errorWithDomain:@"tbexp" code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"写入 LaunchAgent 失败"}];
        return NO;
    }
    [self launchctl:@[@"bootout", [NSString stringWithFormat:@"gui/%d", getuid()], path]];
    [self launchctl:@[@"bootstrap", [NSString stringWithFormat:@"gui/%d", getuid()], path]];
    return YES;
}

- (BOOL)removeLaunchAgent:(NSError **)error {
    NSString *path = [self launchAgentPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return YES;
    [self launchctl:@[@"bootout", [NSString stringWithFormat:@"gui/%d", getuid()], path]];
    if (![[NSFileManager defaultManager] removeItemAtPath:path error:error]) return NO;
    return YES;
}

- (void)launchctl:(NSArray<NSString *> *)args {
    NSTask *t = [NSTask new];
    t.launchPath = @"/bin/launchctl";
    t.arguments = args;
    t.standardOutput = [NSPipe pipe];
    t.standardError = [NSPipe pipe];
    @try { [t launch]; [t waitUntilExit]; } @catch (NSException *e) {
        fprintf(stderr, "[tb] launchctl %s: %s\n", args.firstObject.UTF8String, e.reason.UTF8String);
    }
}

@end
