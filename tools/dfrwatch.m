// dfrwatch.m — 只读探针：周期性调用 DFRGetStatus()，看数值会不会随时间变化
// 用途：判断 Touch Bar 是否在某个时间点进入暗/灭状态（数值跳变即为信号）
#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef int (*GetStatusFn)(void);

int main(int argc, char *argv[]) {
    @autoreleasepool {
        void *h = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation",
                         RTLD_NOW);
        if (!h) { printf("dlopen FAILED: %s\n", dlerror()); return 1; }
        GetStatusFn getStatus = (GetStatusFn)dlsym(h, "DFRGetStatus");
        if (!getStatus) { printf("no DFRGetStatus\n"); return 1; }

        int seconds = (argc > 1) ? atoi(argv[1]) : 30;
        printf("polling DFRGetStatus() every 1s for %ds\n", seconds);
        for (int i = 0; i <= seconds; i++) {
            int s = getStatus();
            printf("  t=%3ds  DFRGetStatus() = %d  (0x%08x)\n", i, s, s);
            fflush(stdout);
            if (i < seconds) sleep(1);
        }
    }
    return 0;
}
