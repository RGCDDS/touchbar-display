//
//  TBClip.m
//

#import "TBClip.h"
#import <ImageIO/ImageIO.h>

@interface TBClip ()
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) NSArray<NSString *> *sharpPaths;
@property (nonatomic, strong) NSArray *thumbs;                  // CGImage 或 NSNull
@property (nonatomic, strong) NSMutableDictionary *cache;       // @(idx) -> CGImage
@property (nonatomic, strong) NSMutableArray<NSNumber *> *fifo;
@property (nonatomic, assign) NSUInteger cacheCap;
@end

@implementation TBClip

+ (instancetype)clipWithDirectory:(NSString *)dir {
    TBClip *c = [TBClip new];
    if (![c loadFromDirectory:dir]) return nil;
    return c;
}

- (BOOL)loadFromDirectory:(NSString *)dir {
    self.directory = dir;
    // 顺序播放时缓存命中率约 0（126 帧循环、只留 12 帧），纯属占内存。
    // 留 3 帧够应付"同一 tick 被重绘两次"的情况。
    self.cacheCap = getenv("TB_CACHE") ? (NSUInteger)atoi(getenv("TB_CACHE")) : 3;

    NSString *sp = [dir stringByAppendingPathComponent:@"sharp"];
    NSString *tp = [dir stringByAppendingPathComponent:@"thumb"];

    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:sp error:NULL];
    // 支持 png / jpg / heic，缩略图目录用同名文件
    files = [[files filteredArrayUsingPredicate:
              [NSPredicate predicateWithFormat:
               @"self ENDSWITH[cd] '.png' OR self ENDSWITH[cd] '.jpg' OR self ENDSWITH[cd] '.heic'"]]
             sortedArrayUsingSelector:@selector(compare:)];
    if (files.count == 0) return NO;

    NSMutableArray *paths = [NSMutableArray arrayWithCapacity:files.count];
    for (NSString *f in files) [paths addObject:[sp stringByAppendingPathComponent:f]];
    self.sharpPaths = paths;

    NSMutableArray *th = [NSMutableArray arrayWithCapacity:files.count];
    for (NSString *f in files) {
        NSString *p = [tp stringByAppendingPathComponent:f];
        CGImageSourceRef src = CGImageSourceCreateWithURL(
            (__bridge CFURLRef)[NSURL fileURLWithPath:p], NULL);
        if (!src) { [th addObject:[NSNull null]]; continue; }
        CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
        CFRelease(src);
        if (img) [th addObject:CFBridgingRelease(img)];
        else     [th addObject:[NSNull null]];
    }
    self.thumbs = th;

    self.cache = [NSMutableDictionary dictionary];
    self.fifo  = [NSMutableArray array];
    return YES;
}

- (NSUInteger)count { return self.sharpPaths.count; }

- (CGImageRef)sharpAt:(NSUInteger)i {
    if (i >= self.count) return NULL;
    NSNumber *key = @(i);
    id hit = self.cache[key];
    if (hit) return (__bridge CGImageRef)hit;

    // 简单 FIFO 淘汰，控制内存
    if (self.fifo.count >= self.cacheCap && self.fifo.count > 0) {
        [self.cache removeObjectForKey:self.fifo.firstObject];
        [self.fifo removeObjectAtIndex:0];
    }
    CGImageSourceRef src = CGImageSourceCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:self.sharpPaths[i]], NULL);
    if (!src) return NULL;
    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!img) return NULL;

    id obj = CFBridgingRelease(img);
    self.cache[key] = obj;
    [self.fifo addObject:key];
    return (__bridge CGImageRef)obj;
}

- (CGImageRef)thumbAt:(NSUInteger)i {
    if (i >= self.thumbs.count) return NULL;
    id o = self.thumbs[i];
    return (o == [NSNull null]) ? NULL : (__bridge CGImageRef)o;
}

@end
