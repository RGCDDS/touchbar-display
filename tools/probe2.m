//
//  probe2.m — 验证两个私有/半私有能力：
//    1) 能不能把 systemModal Touch Bar 撤下来（交还 Control Strip）
//    2) 能不能无权限读系统闲置秒数（OLED 休眠要用）
//

#import <Cocoa/Cocoa.h>

int main(void) {
    @autoreleasepool {
        Class bar = NSClassFromString(@"NSTouchBar");
        printf("NSTouchBar = %s\n", bar ? "yes" : "no");

        NSArray *cands = @[
            @"dismissSystemModalTouchBar:",
            @"dismissSystemModalFunctionBar:",
            @"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:",
            @"presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:",
        ];
        for (NSString *name in cands) {
            SEL s = NSSelectorFromString(name);
            printf("  %-62s %s\n", name.UTF8String,
                   [bar respondsToSelector:s] ? "YES" : "no");
        }

        printf("\nidle 秒数（HID）: %.2f\n",
               CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState,
                                                      kCGAnyInputEventType));
        printf("idle 秒数（combined）: %.2f\n",
               CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState,
                                                      kCGAnyInputEventType));
    }
    return 0;
}
