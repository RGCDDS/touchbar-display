//
//  bench_decode.m — 用 ImageIO 解码（App 真实走的路），比较不同格式的开销
//  用法：./bench_decode <目录> <扩展名> [重复次数]
//

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <mach/mach_time.h>

static double NowMS(void) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { printf("用法: bench_decode <dir> <ext> [repeat]\n"); return 1; }
        NSString *dir = [NSString stringWithUTF8String:argv[1]];
        NSString *ext = [NSString stringWithUTF8String:argv[2]];
        int repeat = (argc > 3) ? atoi(argv[3]) : 10;

        NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]
            filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH %@", ext]];
        files = [files sortedArrayUsingSelector:@selector(compare:)];
        if (files.count == 0) { printf("没找到 %s 文件\n", ext.UTF8String); return 1; }

        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        for (NSString *f in files) [paths addObject:[dir stringByAppendingPathComponent:f]];

        // 预热（把第一轮算进缓存/映射）
        for (NSString *p in paths) {
            CGImageSourceRef s = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:p], NULL);
            if (s) { CGImageRelease(CGImageSourceCreateImageAtIndex(s, 0, NULL)); CFRelease(s); }
        }

        double t0 = NowMS();
        int n = 0;
        for (int r = 0; r < repeat; r++) {
            for (NSString *p in paths) {
                CGImageSourceRef s = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:p], NULL);
                if (!s) continue;
                CGImageRef img = CGImageSourceCreateImageAtIndex(s, 0, NULL);
                if (img) { CGImageRelease(img); n++; }
                CFRelease(s);
            }
        }
        double ms = NowMS() - t0;

        printf("%-6s %3d 张 × %d 轮 = %d 次解码  总 %.1f ms  单张 %.3f ms\n",
               ext.UTF8String, (int)paths.count, repeat, n, ms, n ? ms / n : 0);
    }
    return 0;
}
