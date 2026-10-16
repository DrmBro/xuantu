#import "XTAnnotation.h"
#import <math.h>
#import <stdint.h>

static BOOL XTFinitePoint(NSPoint point) {
    return isfinite(point.x) && isfinite(point.y);
}

static BOOL XTFiniteRect(NSRect rect) {
    return XTFinitePoint(rect.origin) && isfinite(rect.size.width) &&
        isfinite(rect.size.height) && isfinite(NSMaxX(rect)) && isfinite(NSMaxY(rect));
}

static CGFloat XTPositiveValue(CGFloat value, CGFloat fallback) {
    return isfinite(value) && value > 0 ? value : fallback;
}

static CGFloat XTStrokeWidth(XTAnnotation *annotation) {
    return XTPositiveValue(annotation.lineWidth, 3);
}

// 使用单位方向投影，避免直接计算线段长度平方造成溢出。
static CGFloat XTDistanceToSegment(NSPoint point, NSPoint a, NSPoint b) {
    CGFloat dx = b.x - a.x, dy = b.y - a.y;
    CGFloat length = hypot(dx, dy);
    if (!isfinite(length)) return CGFLOAT_MAX;
    if (length == 0) return hypot(point.x - a.x, point.y - a.y);
    CGFloat ux = dx / length, uy = dy / length;
    CGFloat projection = (point.x - a.x) * ux + (point.y - a.y) * uy;
    projection = MAX(0, MIN(length, projection));
    return hypot(point.x - (a.x + projection * ux), point.y - (a.y + projection * uy));
}

static BOOL XTArrowWings(XTAnnotation *annotation, NSPoint *left, NSPoint *right) {
    if (!XTFinitePoint(annotation.start) || !XTFinitePoint(annotation.end)) return NO;
    CGFloat dx = annotation.end.x - annotation.start.x;
    CGFloat dy = annotation.end.y - annotation.start.y;
    CGFloat length = hypot(dx, dy);
    if (!isfinite(length) || length <= 0) return NO;
    CGFloat ux = dx / length, uy = dy / length;
    CGFloat headLength = MIN(length, MAX(12, XTStrokeWidth(annotation) * 4));
    CGFloat halfWidth = headLength * 0.45;
    NSPoint base = NSMakePoint(annotation.end.x - ux * headLength,
                              annotation.end.y - uy * headLength);
    *left = NSMakePoint(base.x - uy * halfWidth, base.y + ux * halfWidth);
    *right = NSMakePoint(base.x + uy * halfWidth, base.y - ux * halfWidth);
    return XTFinitePoint(*left) && XTFinitePoint(*right);
}

// 每次布局均使用同样的字体、段落及容器参数，绘制和命中范围保持一致。
static NSTextStorage *XTTextLayout(XTAnnotation *annotation, CGFloat *height) {
    CGFloat fontSize = XTPositiveValue(annotation.fontSize, 20);
    CGFloat width = XTPositiveValue(annotation.textWidth, 240);
    NSFont *font = [NSFont systemFontOfSize:fontSize];
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    NSString *text = annotation.text.length ? annotation.text : @" ";
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:text attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: annotation.color ?: NSColor.redColor,
        NSParagraphStyleAttributeName: paragraph
    }];
    NSLayoutManager *layout = [[NSLayoutManager alloc] init];
    layout.usesFontLeading = YES;
    NSTextContainer *container = [[NSTextContainer alloc]
        initWithContainerSize:NSMakeSize(width, CGFLOAT_MAX)];
    container.lineFragmentPadding = 0;
    container.lineBreakMode = NSLineBreakByWordWrapping;
    [layout addTextContainer:container];
    [storage addLayoutManager:layout];
    [layout ensureLayoutForTextContainer:container];
    CGFloat measured = NSMaxY([layout usedRectForTextContainer:container]);
    if (layout.extraLineFragmentTextContainer == container) {
        measured = MAX(measured, NSMaxY(layout.extraLineFragmentRect));
    }
    *height = MAX([layout defaultLineHeightForFont:font], measured);
    return storage;
}

@implementation XTAnnotation

- (instancetype)init {
    if ((self = [super init])) {
        _kind = XTAnnotationRectangle;
        _color = NSColor.redColor;
        _lineWidth = 3;
        _fontSize = 20;
        _text = @"";
        _textWidth = 240;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    XTAnnotation *copy = [[[self class] allocWithZone:zone] init];
    copy.kind = self.kind;
    copy.start = self.start;
    copy.end = self.end;
    copy.color = [self.color copyWithZone:zone];
    copy.lineWidth = self.lineWidth;
    copy.fontSize = self.fontSize;
    copy.text = [self.text copyWithZone:zone];
    copy.textWidth = self.textWidth;
    return copy;
}

- (NSRect)bounds {
    if (!XTFinitePoint(self.start)) return NSZeroRect;
    NSRect rect;
    if (self.kind == XTAnnotationText) {
        CGFloat height = 0;
        XTTextLayout(self, &height);
        rect = NSMakeRect(self.start.x, self.start.y - height,
                          XTPositiveValue(self.textWidth, 240), height);
    } else {
        if (!XTFinitePoint(self.end)) return NSZeroRect;
        CGFloat minX = MIN(self.start.x, self.end.x), minY = MIN(self.start.y, self.end.y);
        CGFloat maxX = MAX(self.start.x, self.end.x), maxY = MAX(self.start.y, self.end.y);
        if (self.kind == XTAnnotationArrow) {
            NSPoint left, right;
            if (!XTArrowWings(self, &left, &right)) return NSZeroRect;
            minX = MIN(minX, MIN(left.x, right.x));
            minY = MIN(minY, MIN(left.y, right.y));
            maxX = MAX(maxX, MAX(left.x, right.x));
            maxY = MAX(maxY, MAX(left.y, right.y));
        } else if (self.kind != XTAnnotationRectangle || minX == maxX || minY == maxY) {
            return NSZeroRect;
        }
        rect = NSMakeRect(minX, minY, maxX - minX, maxY - minY);
        rect = NSInsetRect(rect, -XTStrokeWidth(self) / 2, -XTStrokeWidth(self) / 2);
    }
    return XTFiniteRect(rect) ? rect : NSZeroRect;
}

- (BOOL)hitTest:(NSPoint)point tolerance:(CGFloat)tolerance {
    if (!XTFinitePoint(point)) return NO;
    NSRect bounds = self.bounds;
    if (NSIsEmptyRect(bounds)) return NO;
    CGFloat extra = isfinite(tolerance) ? MAX(0, tolerance) : 0;
    if (self.kind == XTAnnotationText) {
        return point.x >= NSMinX(bounds) - extra && point.x <= NSMaxX(bounds) + extra &&
            point.y >= NSMinY(bounds) - extra && point.y <= NSMaxY(bounds) + extra;
    }
    CGFloat radius = XTStrokeWidth(self) / 2 + extra;
    if (self.kind == XTAnnotationArrow) {
        NSPoint left, right;
        if (!XTArrowWings(self, &left, &right)) return NO;
        return XTDistanceToSegment(point, self.start, self.end) <= radius ||
            XTDistanceToSegment(point, self.end, left) <= radius ||
            XTDistanceToSegment(point, self.end, right) <= radius;
    }
    if (self.kind != XTAnnotationRectangle) return NO;
    NSPoint a = self.start, c = self.end;
    NSPoint b = NSMakePoint(c.x, a.y), d = NSMakePoint(a.x, c.y);
    return XTDistanceToSegment(point, a, b) <= radius ||
        XTDistanceToSegment(point, b, c) <= radius ||
        XTDistanceToSegment(point, c, d) <= radius ||
        XTDistanceToSegment(point, d, a) <= radius;
}

- (void)moveBy:(NSSize)delta {
    if (!isfinite(delta.width) || !isfinite(delta.height)) return;
    NSPoint start = NSMakePoint(self.start.x + delta.width, self.start.y + delta.height);
    NSPoint end = NSMakePoint(self.end.x + delta.width, self.end.y + delta.height);
    if (!XTFinitePoint(start) || !XTFinitePoint(end)) return;
    self.start = start;
    self.end = end;
}

- (void)draw {
    if (!NSGraphicsContext.currentContext || NSIsEmptyRect(self.bounds)) return;
    [NSGraphicsContext saveGraphicsState];
    @try {
        CGContextRef drawingContext = NSGraphicsContext.currentContext.CGContext;
        CGContextSetShouldAntialias(drawingContext, true);
        CGContextSetShouldSmoothFonts(drawingContext, false);
        if (self.kind == XTAnnotationText) {
            if (self.text.length == 0) return;
            CGFloat height = 0;
            // NSLayoutManager 不持有 textStorage，确保文本存储存活至绘制结束。
            __attribute__((objc_precise_lifetime)) NSTextStorage *storage = XTTextLayout(self, &height);
            NSLayoutManager *layout = storage.layoutManagers.firstObject;
            CGContextRef context = NSGraphicsContext.currentContext.CGContext;
            // TextKit 使用左上角原点；只在文本的局部空间翻转一次。
            CGContextTranslateCTM(context, self.start.x, self.start.y);
            CGContextScaleCTM(context, 1, -1);
            NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:context flipped:YES];
            CGContextClipToRect(context, CGRectMake(0, 0, XTPositiveValue(self.textWidth, 240), height));
            NSRange range = [layout glyphRangeForTextContainer:layout.textContainers.firstObject];
            [layout drawBackgroundForGlyphRange:range atPoint:NSZeroPoint];
            [layout drawGlyphsForGlyphRange:range atPoint:NSZeroPoint];
        } else {
            NSBezierPath *path = [NSBezierPath bezierPath];
            path.lineWidth = XTStrokeWidth(self);
            path.lineCapStyle = NSLineCapStyleRound;
            path.lineJoinStyle = NSLineJoinStyleRound;
            if (self.kind == XTAnnotationRectangle) {
                [path appendBezierPathWithRect:NSMakeRect(MIN(self.start.x, self.end.x),
                    MIN(self.start.y, self.end.y), fabs(self.end.x - self.start.x),
                    fabs(self.end.y - self.start.y))];
            } else if (self.kind == XTAnnotationArrow) {
                NSPoint left, right;
                if (!XTArrowWings(self, &left, &right)) return;
                [path moveToPoint:self.start];
                [path lineToPoint:self.end];
                [path moveToPoint:left];
                [path lineToPoint:self.end];
                [path lineToPoint:right];
            }
            [(self.color ?: NSColor.redColor) setStroke];
            [path stroke];
        }
    } @finally {
        [NSGraphicsContext restoreGraphicsState];
    }
}

@end

NSImage *XTCompositeCapture(NSImage *snapshot, NSSize canvasSize, NSRect selection,
                            NSArray<XTAnnotation *> *annotations) {
    if (!snapshot || !isfinite(canvasSize.width) || !isfinite(canvasSize.height) ||
        canvasSize.width <= 0 || canvasSize.height <= 0 || !XTFiniteRect(selection) ||
        NSIsEmptyRect(selection)) return nil;
    selection = NSIntersectionRect(selection, NSMakeRect(0, 0, canvasSize.width, canvasSize.height));
    if (NSIsEmptyRect(selection)) return nil;
    CGImageRef full = [snapshot CGImageForProposedRect:NULL context:nil hints:nil];
    if (!full) return nil;
    size_t fullWidth = CGImageGetWidth(full), fullHeight = CGImageGetHeight(full);
    if (fullWidth == 0 || fullHeight == 0) return nil;
    CGFloat sx = (CGFloat)fullWidth / canvasSize.width;
    CGFloat sy = (CGFloat)fullHeight / canvasSize.height;
    if (!isfinite(sx) || !isfinite(sy) || sx <= 0 || sy <= 0) return nil;
    // CGImage 的裁剪坐标自左上开始；向外对齐完整像素后再与原图相交。
    CGFloat left = MAX(0, floor(NSMinX(selection) * sx));
    CGFloat top = MAX(0, floor((canvasSize.height - NSMaxY(selection)) * sy));
    CGFloat right = MIN((CGFloat)fullWidth, ceil(NSMaxX(selection) * sx));
    CGFloat bottom = MIN((CGFloat)fullHeight, ceil((canvasSize.height - NSMinY(selection)) * sy));
    CGRect crop = CGRectMake(left, top, right - left, bottom - top);
    if (!XTFiniteRect(NSRectFromCGRect(crop)) || CGRectIsEmpty(crop)) return nil;
    CGImageRef cropped = CGImageCreateWithImageInRect(full, crop);
    if (!cropped) return nil;
    size_t width = CGImageGetWidth(cropped), height = CGImageGetHeight(cropped);
    if (width == 0 || height == 0 || width > SIZE_MAX / 4 || height > SIZE_MAX / (width * 4)) {
        CGImageRelease(cropped);
        return nil;
    }
    // 尽量保留截图的 RGB 色域；非 RGB 截图统一使用 sRGB 绘制。
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(full);
    if (colorSpace && CGColorSpaceGetModel(colorSpace) == kCGColorSpaceModelRGB) {
        CGColorSpaceRetain(colorSpace);
    } else {
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    }
    if (!colorSpace) { CGImageRelease(cropped); return nil; }
    CGContextRef bitmap = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!bitmap) { CGImageRelease(cropped); return nil; }
    NSImage *result = nil;
    @try {
        // 默认 Quartz 左下角坐标直接绘制，不再对整张截图进行上下翻转。
        CGContextSetInterpolationQuality(bitmap, kCGInterpolationNone);
        CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), cropped);
        CGContextSetShouldAntialias(bitmap, true);
        CGContextSetShouldSmoothFonts(bitmap, false);
        [NSGraphicsContext saveGraphicsState];
        @try {
            NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:bitmap flipped:NO];
            CGContextScaleCTM(bitmap, sx, sy);
            CGFloat originX = left / sx;
            CGFloat originY = ((CGFloat)fullHeight - bottom) / sy;
            CGContextTranslateCTM(bitmap, -originX, -originY);
            CGContextClipToRect(bitmap, NSRectToCGRect(selection));
            for (XTAnnotation *annotation in annotations) [annotation draw];
        } @finally {
            [NSGraphicsContext restoreGraphicsState];
        }
        CGImageRef composite = CGBitmapContextCreateImage(bitmap);
        if (composite) {
            @try {
                NSSize logicalSize = NSMakeSize((CGFloat)width / sx, (CGFloat)height / sy);
                if (isfinite(logicalSize.width) && isfinite(logicalSize.height)) {
                    // 显式保留 bitmap representation，逻辑点大小与像素尺寸分别保存。
                    NSBitmapImageRep *representation = [[NSBitmapImageRep alloc] initWithCGImage:composite];
                    if (representation) {
                        representation.size = logicalSize;
                        result = [[NSImage alloc] initWithSize:logicalSize];
                        [result addRepresentation:representation];
                    }
                }
            } @finally {
                CGImageRelease(composite);
            }
        }
    } @finally {
        CGContextRelease(bitmap);
        CGImageRelease(cropped);
    }
    return result;
}
