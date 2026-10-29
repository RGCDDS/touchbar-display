//
//  bench_compose.m — 单独测 TBComposeTrio 一次要多久（不含绘制到窗口）
//  24fps 的预算是 41.7ms/帧，先看合成占了多少
//

#import <Foundation/Foundation.h>
#import "TBComposer.h"
#import "TBClip.h"
#import <mach/mach_time.h>

static double NowMS(void) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 5) { printf("用法: bench_compose <dir1> <dir2> <dir3> [rounds]\n"); return 1; }
        TBClip *clips[3];
        for (int i = 0; i < 3; i++) {
            clips[i] = [TBClip clipWithDirectory:[NSString stringWithUTF8String:argv[1 + i]]];
            if (!clips[i]) { printf("加载失败 %s\n", argv[1 + i]); return 1; }
        }
        int rounds = (argc > 4) ? atoi(argv[4]) : 300;

        // 预热
        for (int r = 0; r < 20; r++) {
            CGImageRef s[3], t[3];
            for (int i = 0; i < 3; i++) { s[i] = [clips[i] sharpAt:r % clips[i].count];
                                          t[i] = [clips[i] thumbAt:r % clips[i].count]; }
            CGImageRef c = TBComposeTrio(s, t);
            if (c) CGImageRelease(c);
        }

        double t0 = NowMS();
        for (int r = 0; r < rounds; r++) {
            CGImageRef s[3], t[3];
            for (int i = 0; i < 3; i++) {
                NSUInteger idx = r % clips[i].count;
                s[i] = [clips[i] sharpAt:idx];
                t[i] = [clips[i] thumbAt:idx];
                if (!t[i]) t[i] = s[i];
            }
            CGImageRef c = TBComposeTrio(s, t);
            if (c) CGImageRelease(c);
        }
        double ms = NowMS() - t0;

        printf("合成 %d 次：总 %.1f ms，单次 %.2f ms  （24fps 预算 41.7ms，占 %.0f%%）\n",
               rounds, ms, ms / rounds, ms / rounds / 41.7 * 100);
    }
    return 0;
}
