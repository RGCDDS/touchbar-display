//
//  TBComposer.m — 从 tbexp.m 原样搬过来的合成逻辑，一个字没改
//

#import "TBComposer.h"
#import <math.h>
#import <stdlib.h>

#define OVERLAP TB_OV
#define IMG_W   ((TB_BAR_W + 2.0 * OVERLAP) / 3.0)
#define STEP    (IMG_W - OVERLAP)

#pragma mark - 渐变遮罩

// smootherstep：比 smoothstep 更平顺，两端一阶二阶导都为 0
static double Smootherstep(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return t * t * t * (t * (t * 6 - 15) + 10);
}

// 横向渐变遮罩，预展开成 BAR_W × BAR_H 整幅（不要用 1px 拉伸，每次重采样白烧 CPU）
static CGImageRef MakeMask(double x0, double x1, double peak) {
    size_t w = (size_t)TB_BAR_W, h = (size_t)TB_BAR_H;
    uint8_t *buf = calloc(w * h, 1);
    for (size_t x = 0; x < w; x++) {
        double t = ((double)x - x0) / (x1 - x0);
        uint8_t v = (uint8_t)lround(Smootherstep(t) * 255.0 * peak);
        for (size_t y = 0; y < h; y++) buf[y * w + x] = v;
    }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef c = CGBitmapContextCreate(buf, w, h, 8, w, cs, (CGBitmapInfo)0);
    CGImageRef img = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    CGColorSpaceRelease(cs);
    free(buf);
    return img;
}

// 钟形遮罩：中间最柔，两端归零
static CGImageRef MakeBell(double x0, double x1, double peak) {
    size_t w = (size_t)TB_BAR_W, h = (size_t)TB_BAR_H;
    uint8_t *buf = calloc(w * h, 1);
    for (size_t x = 0; x < w; x++) {
        double t = ((double)x - x0) / (x1 - x0);
        uint8_t v = 0;
        if (t > 0 && t < 1) v = (uint8_t)lround(pow(sin(M_PI * t), 1.6) * 255.0 * peak);
        for (size_t y = 0; y < h; y++) buf[y * w + x] = v;
    }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef c = CGBitmapContextCreate(buf, w, h, 8, w, cs, (CGBitmapInfo)0);
    CGImageRef img = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    CGColorSpaceRelease(cs);
    free(buf);
    return img;
}

// 柔和暗缝：黑色、按 smootherstep 落到底
static CGImageRef MakeDarkBand(double center, double halfW, double peak) {
    size_t w = (size_t)TB_BAR_W, h = (size_t)TB_BAR_H;
    uint8_t *buf = calloc(w * h * 4, 1);
    for (size_t x = 0; x < w; x++) {
        double d = fabs((double)x - center) / halfW;
        double a = (d >= 1.0) ? 0.0 : (1.0 - Smootherstep(d)) * peak;
        for (size_t y = 0; y < h; y++) {
            uint8_t *px = buf + (y * w + x) * 4;
            px[0] = px[1] = px[2] = 0;             // 黑
            px[3] = (uint8_t)lround(a * 255.0);    // 预乘后仍是 0
        }
    }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(buf, w, h, 8, w * 4, cs,
                                           kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGImageRef img = CGBitmapContextCreateImage(c);
    CGContextRelease(c); CGColorSpaceRelease(cs); free(buf);
    return img;
}

static CGImageRef gRamp1, gRamp2, gBell1, gBell2, gDark1, gDark2;

static void BuildMasks(void) {
    if (gRamp1) return;
    gRamp1 = MakeMask(STEP, STEP + OVERLAP, 1.0);              // 第 2 张淡入
    gRamp2 = MakeMask(STEP * 2, STEP * 2 + OVERLAP, 1.0);      // 第 3 张淡入
    double bp = getenv("TB_BELL") ? atof(getenv("TB_BELL")) : 0.55;
    gBell1 = MakeBell(STEP, STEP + OVERLAP, bp);               // 接缝柔焦
    gBell2 = MakeBell(STEP * 2, STEP * 2 + OVERLAP, bp);
    double dh = getenv("TB_DARK_HALF") ? atof(getenv("TB_DARK_HALF")) : 44.0;
    double dp = getenv("TB_DARK_PEAK") ? atof(getenv("TB_DARK_PEAK")) : 0.80;
    gDark1 = MakeDarkBand(TB_BAR_W / 3.0, dh, dp);
    gDark2 = MakeDarkBand(TB_BAR_W / 3.0 * 2.0, dh, dp);
}

#pragma mark - 合成

CGImageRef TBComposeTrio(CGImageRef s[3], CGImageRef t[3]) {
    BuildMasks();

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, (size_t)TB_BAR_W, (size_t)TB_BAR_H, 8, 0, cs,
                                           kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    CGContextSetInterpolationQuality(c, kCGInterpolationLow);

    CGRect full = CGRectMake(0, 0, TB_BAR_W, TB_BAR_H);

    // 1) 第一张，整块打底
    CGContextDrawImage(c, CGRectMake(0, 0, IMG_W, TB_BAR_H), s[0]);

    // 2) 第二张按 ramp 淡入
    CGContextSaveGState(c);
    CGContextClipToMask(c, full, gRamp1);
    CGContextDrawImage(c, CGRectMake(STEP, 0, IMG_W, TB_BAR_H), s[1]);
    CGContextRestoreGState(c);

    // 3) 第三张按 ramp 淡入
    CGContextSaveGState(c);
    CGContextClipToMask(c, full, gRamp2);
    CGContextDrawImage(c, CGRectMake(STEP * 2, 0, IMG_W, TB_BAR_H), s[2]);
    CGContextRestoreGState(c);

    // 4) 接缝处：把两张的失焦版做成一个"模糊的交叉淡化"，再整体按钟形叠回去
    //    用透明图层，避免两次半透明叠加累积成灰雾
    BOOL skipBell = getenv("TB_NOBELL") != NULL;
    for (int k = 0; k < 2 && !skipBell; k++) {
        double bx0 = (k == 0) ? STEP : STEP * 2;
        CGImageRef bell = (k == 0) ? gBell1 : gBell2;
        CGImageRef ramp = (k == 0) ? gRamp1 : gRamp2;

        CGContextSaveGState(c);
        CGContextClipToRect(c, CGRectMake(bx0, 0, OVERLAP, TB_BAR_H));
        CGContextClipToMask(c, full, bell);
        CGContextBeginTransparencyLayer(c, NULL);
        {
            CGContextDrawImage(c, CGRectMake(STEP * k, 0, IMG_W, TB_BAR_H), t[k]);
            CGContextSaveGState(c);
            CGContextClipToMask(c, full, ramp);
            CGContextDrawImage(c, CGRectMake(STEP * (k + 1), 0, IMG_W, TB_BAR_H), t[k + 1]);
            CGContextRestoreGState(c);
        }
        CGContextEndTransparencyLayer(c);
        CGContextRestoreGState(c);
    }

    CGImageRef out = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    return out;
}

CGImageRef TBComposeSeam(CGImageRef s[3]) {
    BuildMasks();
    double step = TB_BAR_W / 3.0;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, (size_t)TB_BAR_W, (size_t)TB_BAR_H, 8, 0, cs,
                                           kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    CGContextSetInterpolationQuality(c, kCGInterpolationLow);

    for (int i = 0; i < 3; i++)
        CGContextDrawImage(c, CGRectMake(step * i, 0, step, TB_BAR_H), s[i]);

    CGContextDrawImage(c, CGRectMake(0, 0, TB_BAR_W, TB_BAR_H), gDark1);
    CGContextDrawImage(c, CGRectMake(0, 0, TB_BAR_W, TB_BAR_H), gDark2);

    CGImageRef out = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    return out;
}

#pragma mark - 亮度

void TBDrawImageWithBrightness(CGContextRef ctx, CGRect rect, CGImageRef img, double b) {
    if (!ctx || !img) return;
    if (!(b > 0.0)) b = 1.0;   // NaN / 0 兜底

    CGContextSetAlpha(ctx, 1.0);
    CGContextSetBlendMode(ctx, kCGBlendModeNormal);
    CGContextDrawImage(ctx, rect, img);

    if (b < 0.999) {
        // 叠一层黑：out = in × b
        CGColorRef black = CGColorCreateGenericRGB(0, 0, 0, 1.0 - b);
        CGContextSetFillColorWithColor(ctx, black);
        CGContextFillRect(ctx, rect);
        CGColorRelease(black);
    } else if (b > 1.001) {
        // 再叠一次自己（PlusLighter）：out = in + in × (b−1)，暗部不会被抬起来
        CGContextSetBlendMode(ctx, kCGBlendModePlusLighter);
        CGContextSetAlpha(ctx, (b - 1.0 > 1.0) ? 1.0 : (b - 1.0));
        CGContextDrawImage(ctx, rect, img);
        CGContextSetAlpha(ctx, 1.0);
        CGContextSetBlendMode(ctx, kCGBlendModeNormal);
    }
}
