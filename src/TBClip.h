//
//  TBClip.h — 一个 clip = 一组已抽好的帧（sharp + thumb）
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface TBClip : NSObject

/// 从目录加载，目录下需有 sharp/ 与 thumb/。失败返回 nil。
+ (instancetype)clipWithDirectory:(NSString *)dir;

@property (nonatomic, readonly, copy) NSString *directory;
@property (nonatomic, readonly) NSUInteger count;

/// 返回的 CGImage 由 clip 持有（内部 FIFO 缓存），不要 release。
- (CGImageRef)sharpAt:(NSUInteger)index;
- (CGImageRef)thumbAt:(NSUInteger)index;

@end
