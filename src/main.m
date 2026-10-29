//
//  main.m — 入口。带 --trio 时走离线预览模式（不出图到条上，只存 PNG）
//

#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#import "TBAppDelegate.h"
#import "TBClip.h"
#import "TBComposer.h"
#import "TBSettings.h"

/// 离线预览：./TouchBarExp --trio out.png <dir1> <dir2> <dir3> <i1> <i2> <i3>
static int RunTrioPreview(int argc, const char *argv[]) {
    NSString *outPath = [NSString stringWithUTF8String:argv[2]];
    NSMutableArray<TBClip *> *clips = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        TBClip *c = [TBClip clipWithDirectory:[NSString stringWithUTF8String:argv[3 + i]]];
        if (!c) { fprintf(stderr, "load fail: %s\n", argv[3 + i]); return 1; }
        [clips addObject:c];
    }
    CGImageRef s[3], t[3];
    for (int i = 0; i < 3; i++) {
        NSUInteger idx = (NSUInteger)atoi(argv[6 + i]) % clips[i].count;
        s[i] = [clips[i] sharpAt:idx];
        t[i] = [clips[i] thumbAt:idx];
        if (!t[i]) t[i] = s[i];
    }
    BOOL seam = getenv("TB_MODE") && strcmp(getenv("TB_MODE"), "seam") == 0;
    CGImageRef comp = seam ? TBComposeSeam(s) : TBComposeTrio(s, t);

    // 预览也能带亮度：TB_BRIGHT=0.85 ./dist/tbexp --trio out.png ...
    double bright = getenv("TB_BRIGHT") ? atof(getenv("TB_BRIGHT")) : 1.0;
    CGImageRef out = comp;
    BOOL ownOut = NO;
    if (fabs(bright - 1.0) > 0.001) {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef c = CGBitmapContextCreate(NULL, (size_t)TB_BAR_W, (size_t)TB_BAR_H, 8, 0, cs,
                                               kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(cs);
        CGContextSetInterpolationQuality(c, kCGInterpolationLow);
        TBDrawImageWithBrightness(c, CGRectMake(0, 0, TB_BAR_W, TB_BAR_H), comp, bright);
        out = CGBitmapContextCreateImage(c);
        CGContextRelease(c);
        ownOut = YES;
    }

    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:outPath], CFSTR("public.png"), 1, NULL);
    if (!dst) { fprintf(stderr, "cannot write %s\n", argv[2]); return 1; }
    CGImageDestinationAddImage(dst, out, NULL);
    BOOL ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
    if (ownOut) CGImageRelease(out);
    CGImageRelease(comp);
    printf("%s %s\n", outPath.UTF8String, ok ? "ok" : "fail");
    return ok ? 0 : 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc >= 9 && strcmp(argv[1], "--trio") == 0)
            return RunTrioPreview(argc, argv);

        // 开发探针：启动后直接打开设置窗口，方便验证布局
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--settings") == 0) setenv("TB_OPEN_SETTINGS", "1", 1);
        }

        NSApplication *app = [NSApplication sharedApplication];
        // 有 Dock 图标 = 正经 App（启动台 / ⌘-Tab 里都能找到）；
        // 关掉就退回纯菜单栏工具，只在菜单栏挂个图标
        BOOL dock = [[TBSettings shared] showDockIcon];
        [app setActivationPolicy:dock ? NSApplicationActivationPolicyRegular
                                      : NSApplicationActivationPolicyAccessory];

        TBAppDelegate *delegate = [TBAppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
