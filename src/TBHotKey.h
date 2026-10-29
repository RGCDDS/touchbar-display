//
//  TBHotKey.h — 全局快捷键（Carbon RegisterEventHotKey，不需要辅助功能授权）
//

#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>

@interface TBHotKey : NSObject

/// modifiers 用 Carbon 的 cmdKey / optionKey / controlKey / shiftKey 组合
- (instancetype)initWithKeyCode:(UInt32)keyCode
                      modifiers:(UInt32)modifiers
                        handler:(void (^)(void))handler;

- (void)unregister;

@end
