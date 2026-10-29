//
//  TBComposer.h — 三图并排 + 接缝融合的纯绘制层
//
//  几何：条宽 2170px，重叠 OV（默认 50）
//        每张 IMG_W = (2170 + 2·OV) / 3，步进 STEP = IMG_W − OV
//
//  这里只有 CG，不碰 AppKit，方便单独测试。
//

#import <CoreGraphics/CoreGraphics.h>

#define TB_BAR_W  2170.0
#define TB_BAR_H  60.0

#ifndef TB_OV
#define TB_OV 50.0
#endif

/// 交叉淡化模式（当前线上用的）。sharp 是原图，thumb 是柔焦用的缩略图。
CGImageRef TBComposeTrio(CGImageRef sharp[3], CGImageRef thumb[3]);

/// 柔和暗缝模式（TB_MODE=seam 时切）。三块各自清晰，缝处渐隐入阴影，零重影。
CGImageRef TBComposeSeam(CGImageRef sharp[3]);

/// 把整条按亮度画进 ctx。
///   b < 1  叠黑压暗：out = in × b，暗部不偏色、不发灰
///   b > 1  叠加自身提亮：out = in + in × (b−1)，纯黑仍然是纯黑（不会像叠白那样把夜空洗成灰）
///   b = 1  与直接 CGContextDrawImage 逐像素一致
void TBDrawImageWithBrightness(CGContextRef ctx, CGRect rect, CGImageRef img, double b);
