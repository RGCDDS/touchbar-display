//
//  make_icon.m — 生成 1024×1024 的 App 图标 PNG
//  用法: ./make_icon <输出.png>
//
//  造型：深色圆角方块 + 一条横贯的渐变条（早→午→晚），中间两道细分隔线
//

#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>

static void DrawGradient(CGContextRef ctx, CGRect rect, CGColorSpaceRef cs,
                         CGFloat *comps, size_t count, BOOL horizontal) {
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, count);
    CGPoint s = horizontal ? CGPointMake(CGRectGetMinX(rect), CGRectGetMidY(rect))
                           : CGPointMake(CGRectGetMidX(rect), CGRectGetMaxY(rect));
    CGPoint e = horizontal ? CGPointMake(CGRectGetMaxX(rect), CGRectGetMidY(rect))
                           : CGPointMake(CGRectGetMidX(rect), CGRectGetMinY(rect));
    CGContextSaveGState(ctx);
    CGContextAddRect(ctx, rect);
    CGContextClip(ctx);
    CGContextDrawLinearGradient(ctx, g, s, e, 0);
    CGContextRestoreGState(ctx);
    CGGradientRelease(g);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "用法: %s <out.png>\n", argv[0]); return 1; }
        const size_t S = 1024;

        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, S, S, 8, 0, cs,
                                                 kCGImageAlphaPremultipliedLast |
                                                 kCGBitmapByteOrder32Big);
        CGContextSetShouldAntialias(ctx, true);
        CGContextClearRect(ctx, CGRectMake(0, 0, S, S));

        // ---- 底板：圆角深色方块 ----
        CGRect plate = CGRectMake(92, 92, 840, 840);
        CGPathRef platePath = CGPathCreateWithRoundedRect(plate, 188, 188, NULL);
        CGContextSaveGState(ctx);
        CGContextAddPath(ctx, platePath);
        CGContextClip(ctx);
        CGFloat bg[] = {
            0.157, 0.204, 0.259, 1.0,   // 上：#283442
            0.067, 0.098, 0.137, 1.0,   // 下：#111923
        };
        DrawGradient(ctx, plate, cs, bg, 2, NO);
        CGContextRestoreGState(ctx);

        // ---- 渐变条：早 → 午 → 晚 ----
        CGRect bar = CGRectMake(148, 462, 728, 100);
        CGPathRef barPath = CGPathCreateWithRoundedRect(bar, 50, 50, NULL);
        CGContextSaveGState(ctx);
        CGContextAddPath(ctx, barPath);
        CGContextClip(ctx);
        CGFloat barComps[] = {
            0.498, 0.702, 0.835, 1.0,   // 早：清透蓝 #7FB3D5
            0.949, 0.753, 0.471, 1.0,   // 午：暖阳橙 #F2C078
            0.424, 0.357, 0.482, 1.0,   // 晚：暮色紫 #6C5B7B
        };
        DrawGradient(ctx, bar, cs, barComps, 3, YES);
        CGContextRestoreGState(ctx);

        // ---- 两道细分隔线，呼应三段式 ----
        CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.28);
        CGFloat third = 728.0 / 3.0;
        for (int i = 1; i < 3; i++) {
            CGFloat x = CGRectGetMinX(bar) + third * i;
            CGContextFillRect(ctx, CGRectMake(x - 1.5, CGRectGetMinY(bar) + 8, 3, 84));
        }

        CGImageRef img = CGBitmapContextCreateImage(ctx);
        CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]],
            CFSTR("public.png"), 1, NULL);
        CGImageDestinationAddImage(dst, img, NULL);
        BOOL ok = CGImageDestinationFinalize(dst);
        CFRelease(dst); CGImageRelease(img);
        CGContextRelease(ctx); CGColorSpaceRelease(cs);
        CGPathRelease(platePath); CGPathRelease(barPath);

        printf("icon %s\n", ok ? "ok" : "fail");
        return ok ? 0 : 1;
    }
}
