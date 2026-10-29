//
//  winid.m — 列出某个 App 的窗口 ID（用来 screencapture -l 精确截窗口）
//  用法：./winid <App 名关键字>
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *needle = (argc > 1) ? [NSString stringWithUTF8String:argv[1]] : nil;
        CFArrayRef list = CGWindowListCopyWindowInfo(
            kCGWindowListOptionAll | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
        for (NSDictionary *w in (__bridge NSArray *)list) {
            NSString *owner = w[(id)kCGWindowOwnerName];
            if (needle && ![owner containsString:needle]) continue;
            CGRect b = CGRectZero;
            CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds], &b);
            printf("%-6s  %-22s  %4.0fx%-4.0f  layer=%s  %s\n",
                   [[w[(id)kCGWindowNumber] stringValue] UTF8String],
                   owner.UTF8String ?: "?",
                   b.size.width, b.size.height,
                   [[w[(id)kCGWindowLayer] stringValue] UTF8String],
                   [w[(id)kCGWindowName] UTF8String] ?: "");
        }
        CFRelease(list);
    }
    return 0;
}
