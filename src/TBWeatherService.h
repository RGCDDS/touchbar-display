//
//  TBWeatherService.h — 跟随当地天气：定位（或手填城市）→ 拉天气 → 映射成 晴/风/雨
//

#import <Foundation/Foundation.h>
#import "TBSettings.h"

@interface TBWeatherService : NSObject

+ (instancetype)shared;

/// 最近一次成功拿到的天气。没拿到过时是 TBWeatherQing。
@property (nonatomic, readonly) TBWeather weather;

/// 给设置窗口显示的一行状态："上海 · 多云 14°C · 08:50 更新"
@property (nonatomic, readonly, copy) NSString *status;

/// 每次刷新结束（成功或失败）都会回调，主线程
@property (nonatomic, copy) void (^handler)(void);

/// 立刻刷新一次
- (void)refresh;

/// 开始定时刷新（秒）。会先立刻刷一次。
- (void)startWithInterval:(NSTimeInterval)seconds;

- (void)stop;

@end
