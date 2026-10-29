//
//  TBSettings.h — 用户设置（NSUserDefaults）+ 开机自启（SMAppService，失败回退 LaunchAgent）
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TBWeather) {
    TBWeatherQing = 0,   // 晴
    TBWeatherFeng = 1,   // 风
    TBWeatherYu   = 2,   // 雨
};

/// 天气从哪来
typedef NS_ENUM(NSInteger, TBWeatherSource) {
    TBWeatherSourceManual = 0,   // 锁定手动选的那一套
    TBWeatherSourceRandom = 1,   // 定时随机轮换
    TBWeatherSourceLocal  = 2,   // 跟随当地天气（定位 / 城市）
};

/// 时段：上午 / 中午 / 晚上，对应三套 clip（早 / 午 / 晚）
typedef NS_ENUM(NSInteger, TBTimeSlot) {
    TBTimeSlotMorning = 0,
    TBTimeSlotNoon    = 1,
    TBTimeSlotEvening = 2,
};

/// 天气变了（菜单栏 / 设置窗口 / 快捷键 / 天气服务 任一入口改的，都会发这个）
extern NSString * const TBSettingsWeatherDidChangeNotification;
/// 其他设置变了（菜单栏图标开关、轮换参数等）
extern NSString * const TBSettingsDidChangeNotification;
/// 亮度变了（单独一条，免得拖滑块时把轮换计时器反复重置）
extern NSString * const TBSettingsBrightnessDidChangeNotification;
/// 动画速度变了（同上，拖滑块不该重置别的计时器）
extern NSString * const TBSettingsSpeedDidChangeNotification;
/// 时段定义或"当前时段放中间"开关变了（要重排三套 clip）
extern NSString * const TBSettingsTimeSlotDidChangeNotification;

/// 亮度范围。1.0 = 原始画面
#define TB_BRIGHTNESS_MIN 0.20
#define TB_BRIGHTNESS_MAX 1.20
/// 动画速度范围（fps）
#define TB_FPS_MIN     8
#define TB_FPS_MAX     40
// 默认 18 而不是源视频的 24：CPU 几乎完全由"每秒传多少帧"决定，
// 24→18 省 25%，而这种云飘叶摇的画面在 18fps 下几乎看不出差别。
#define TB_FPS_DEFAULT 18

@interface TBSettings : NSObject

+ (instancetype)shared;

@property (nonatomic, assign) TBWeather weather;
@property (nonatomic, assign) BOOL showMenuBarIcon;
/// 是否在 Dock / 启动台 / ⌘-Tab 里出现。关掉就退回纯菜单栏工具（窗口也不能最小化）
@property (nonatomic, assign) BOOL showDockIcon;
@property (nonatomic, assign) TBWeatherSource weatherSource;
@property (nonatomic, assign) NSInteger rotationMinutes;   // 5 / 10 / 30 / 60

/// 轮换到下一套（随机，但不会等于当前）。返回新的天气。
- (TBWeather)rotateToRandomWeather;

#pragma mark 亮度 / 速度（每个天气各记一份）

- (double)brightnessForWeather:(TBWeather)w;
- (void)setBrightness:(double)b forWeather:(TBWeather)w;

- (double)fpsForWeather:(TBWeather)w;
- (void)setFPS:(double)fps forWeather:(TBWeather)w;

#pragma mark 时段

/// 三个时段的分界点，单位：当天 0 点起的分钟数
@property (nonatomic, assign) NSInteger morningStart;   // 默认 06:00
@property (nonatomic, assign) NSInteger noonStart;      // 默认 11:00
@property (nonatomic, assign) NSInteger eveningStart;   // 默认 18:00

/// 现在属于哪个时段
- (TBTimeSlot)currentSlot;
/// 指定时刻属于哪个时段（分钟数，0..1439）
- (TBTimeSlot)slotForMinuteOfDay:(NSInteger)minute;

/// 当前时段对应的 clip 索引（0 早 / 1 午 / 2 晚），恒等于 (NSInteger)currentSlot
- (NSInteger)currentSlotClipIndex;

/// 把当前时段放到中间？关掉时三套恒为 早/午/晚
@property (nonatomic, assign) BOOL centerCurrentSlot;

/// 三套 clip 的排列顺序（原索引 0/1/2）。不居中时恒为 @[@0,@1,@2]
- (NSArray<NSNumber *> *)clipOrder;

#pragma mark 省屏（OLED 老化）

/// 闲置多少分钟就熄成纯黑。0 = 永不熄
@property (nonatomic, assign) NSInteger idleHideMinutes;
/// 画面水平微移，对抗 OLED 残影
@property (nonatomic, assign) BOOL pixelShift;
/// 只在这些 App 前台时显示（bundle id）。空 = 不限制
@property (nonatomic, copy) NSArray<NSString *> *appWhitelist;

#pragma mark 天气来源

/// 手填的城市名。空 = 用系统定位
@property (nonatomic, copy) NSString *weatherCity;

/// 内部用：定位成功后把城市名记下来，**不发通知**（避免触发天气服务重启）
- (void)rememberWeatherCity:(NSString *)city;

+ (NSString *)displayNameForWeather:(TBWeather)w;
/// qing / feng / yu
+ (NSString *)slugForWeather:(TBWeather)w;

/// 某个天气对应的三个 clip 目录（早/午/晚）。找不到返回 nil。
- (NSArray<NSString *> *)clipDirectoriesForWeather:(TBWeather)w;

#pragma mark 开机自启

- (BOOL)launchAtLogin;
- (BOOL)setLaunchAtLogin:(BOOL)enabled error:(NSError **)error;

/// App 被挪过位置（比如从 dist/ 装到 /Applications）后，登录项还指着旧路径会静默失效。
/// 启动时调一次，发现路径对不上就重新注册。
- (void)healLoginItemIfNeeded;

@end
