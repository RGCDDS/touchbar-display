//
//  TBPresence.h — 判断"现在该不该显示"：前台 App 白名单 + 系统闲置
//
//  两种隐藏原因分开处理，因为恢复方式不同：
//    · 白名单不匹配 → 整条撤下来，交还系统 Control Strip（用户在用电脑，需要它）
//    · 闲置超时     → 画面淡到纯黑但继续占着（OLED 纯黑 = 像素熄灭，比 Control Strip 更省）
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TBHideReason) {
    TBHideReasonNone = 0,   // 该显示
    TBHideReasonApp  = 1,   // 前台 App 不在白名单
    TBHideReasonIdle = 2,   // 闲置超时
};

@interface TBPresence : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) TBHideReason reason;
@property (nonatomic, readonly) BOOL shouldShow;
/// 给设置窗口看的一句话，比如"闲置 6 分钟，已熄灭"
@property (nonatomic, readonly, copy) NSString *reasonText;
/// 当前闲置了多久（秒），调试/显示用
@property (nonatomic, readonly) double idleSeconds;

/// 状态变化时回调（主线程）
@property (nonatomic, copy) void (^onChange)(void);

- (void)start;
/// 设置改了以后立刻重算一次，别等下一个 tick
- (void)recheck;

@end
