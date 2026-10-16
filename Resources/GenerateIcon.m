#import <Cocoa/Cocoa.h>

static NSData *DrawIcon(NSInteger size) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:size pixelsHigh:size bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    NSAffineTransform *scale = [NSAffineTransform transform]; [scale scaleBy:size / 1024.0]; [scale concat];
    NSBezierPath *base = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(62, 62, 900, 900) xRadius:205 yRadius:205];
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:0.03 green:0.31 blue:0.33 alpha:1] endingColor:[NSColor colorWithSRGBRed:0.13 green:0.72 blue:0.60 alpha:1]];
    [gradient drawInBezierPath:base angle:55];
    [[NSColor colorWithWhite:1 alpha:0.24] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(208, 312, 500, 440) xRadius:52 yRadius:52] fill];
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [NSShadow new]; shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.22]; shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSMakeSize(0, -16); [shadow set];
    [[NSColor colorWithWhite:1 alpha:0.98] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(310, 236, 502, 442) xRadius:52 yRadius:52] fill];
    [NSGraphicsContext restoreGraphicsState];
    NSBezierPath *landscape = [NSBezierPath bezierPath];
    [landscape moveToPoint:NSMakePoint(365, 295)]; [landscape lineToPoint:NSMakePoint(494, 465)]; [landscape lineToPoint:NSMakePoint(582, 374)]; [landscape lineToPoint:NSMakePoint(656, 461)]; [landscape lineToPoint:NSMakePoint(757, 295)]; [landscape closePath];
    [[NSColor colorWithSRGBRed:0.10 green:0.60 blue:0.51 alpha:1] setFill]; [landscape fill];
    [[NSColor colorWithSRGBRed:0.77 green:0.93 blue:0.84 alpha:1] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(640, 506, 63, 63)] fill];
    [[NSColor colorWithSRGBRed:0.96 green:0.77 blue:0.39 alpha:1] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(682, 638, 118, 118)] fill];
    [NSGraphicsContext restoreGraphicsState];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSNumber *n in @[@16, @32, @128, @256, @512]) {
            NSInteger size = n.integerValue;
            for (NSInteger factor = 1; factor <= 2; factor++) {
                NSString *name = [NSString stringWithFormat:@"icon_%ldx%ld%@.png", (long)size, (long)size, factor == 2 ? @"@2x" : @""];
                if (![DrawIcon(size * factor) writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]) return 1;
            }
        }
    }
    return 0;
}
