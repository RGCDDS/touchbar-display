//
//  TBDisplay.h — 把三个 clip 挂到 Touch Bar 上，并负责逐帧推进
//

#import <Foundation/Foundation.h>
#import "TBClip.h"

@interface TBDisplay : NSObject

@property (nonatomic, assign) double fps;      // 默认 24
@property (nonatomic, assign) BOOL seamMode;   // YES = 柔和暗缝，NO = 交叉淡化

/// 亮度，1.0 = 原始画面，<1 压暗，>1 提亮。改了立刻重画。
@property (nonatomic, assign) double brightness;

/// 画面是否该露出来。NO 会淡到纯黑（OLED 上等于熄灯），YES 淡回来。
@property (nonatomic, assign) BOOL contentVisible;

/// 画面水平缓慢微移，对抗 OLED 残影
@property (nonatomic, assign) BOOL pixelShift;

/// 把整条撤下来、交还系统 Control Strip（前台 App 不在白名单时用）
- (void)detach;
/// 重新占回来
- (void)attach;

/// 首次挂载。clips 必须是 3 个。失败返回 NO（比如私有 API 不可用）。
- (BOOL)presentWithClips:(NSArray<TBClip *> *)clips;

/// 换一套 clip，不重新 present，条上无闪烁。切换后动画从第 0 帧重新开始。
- (BOOL)swapClips:(NSArray<TBClip *> *)clips;

- (void)dismiss;

@property (nonatomic, readonly) BOOL isPresented;

@end
