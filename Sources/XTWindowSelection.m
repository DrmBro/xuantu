#import "XTWindowSelection.h"
#import <math.h>

@implementation XTWindowCandidate
- (instancetype)initWithWindowID:(CGWindowID)windowID frame:(NSRect)frame {
    if ((self = [super init])) { _windowID = windowID; _frame = frame; }
    return self;
}
@end

@implementation XTWindowSelection
+ (NSArray<XTWindowCandidate *> *)captureCandidatesForShareableIDs:(NSSet<NSNumber *> *)shareableIDs
                                                   excludedIDs:(NSSet<NSNumber *> *)excludedIDs
                                              allowedOwnPinIDs:(NSSet<NSNumber *> *)pinIDs {
    NSArray<NSDictionary *> *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    if (!windows.count) return @[];
    // Quartz 全局坐标由主屏左上开始；AppKit 由主屏左下开始。均为逻辑点，不乘 Retina 倍率。
    NSScreen *primary = NSScreen.screens.firstObject;
    if (!primary) return @[];
    CGFloat primaryTop = NSMaxY(primary.frame);
    NSMutableArray<XTWindowCandidate *> *result = [NSMutableArray array];
    for (NSDictionary *info in windows) {
        NSNumber *identifier = info[(id)kCGWindowNumber];
        if (!identifier || ![shareableIDs containsObject:identifier] || [excludedIDs containsObject:identifier]) continue;
        NSNumber *owner = info[(id)kCGWindowOwnerPID];
        NSNumber *layer = info[(id)kCGWindowLayer];
        NSNumber *alpha = info[(id)kCGWindowAlpha];
        BOOL ownPin = [pinIDs containsObject:identifier];
        if (!owner || !layer || (owner.intValue == getpid() && !ownPin)) continue;
        // 普通应用窗口使用第 0 层；本应用的悬浮贴图可以例外，但遮罩和菜单不参与。
        if (!ownPin && layer.integerValue != 0) continue;
        NSString *ownerName = info[(id)kCGWindowOwnerName];
        if ([ownerName isEqualToString:@"Dock"] || [ownerName isEqualToString:@"Window Server"] || [ownerName isEqualToString:@"WindowServer"]) continue;
        if (alpha && alpha.doubleValue <= 0.01) continue;
        NSDictionary *bounds = info[(id)kCGWindowBounds];
        CGRect rect = CGRectZero;
        if (![bounds isKindOfClass:NSDictionary.class] || !CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)bounds, &rect)) continue;
        if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) || !isfinite(rect.size.width) || !isfinite(rect.size.height) || rect.size.width < 16 || rect.size.height < 16) continue;
        NSRect frame = NSMakeRect(rect.origin.x, primaryTop - CGRectGetMaxY(rect), rect.size.width, rect.size.height);
        [result addObject:[[XTWindowCandidate alloc] initWithWindowID:identifier.unsignedIntValue frame:frame]];
    }
    return result;
}
+ (NSArray<XTWindowCandidate *> *)candidates:(NSArray<XTWindowCandidate *> *)candidates forScreenFrame:(NSRect)screenFrame {
    NSMutableArray *result = [NSMutableArray array];
    for (XTWindowCandidate *candidate in candidates) {
        NSRect clipped = NSIntersectionRect(candidate.frame, screenFrame);
        if (clipped.size.width < 3 || clipped.size.height < 3) continue;
        clipped.origin.x -= screenFrame.origin.x; clipped.origin.y -= screenFrame.origin.y;
        [result addObject:[[XTWindowCandidate alloc] initWithWindowID:candidate.windowID frame:clipped]];
    }
    return result;
}
+ (NSArray<XTWindowCandidate *> *)candidates:(NSArray<XTWindowCandidate *> *)candidates atLocalPoint:(NSPoint)point {
    NSMutableArray *result = [NSMutableArray array];
    for (XTWindowCandidate *candidate in candidates) if (NSPointInRect(point, candidate.frame)) [result addObject:candidate];
    return result;
}
@end
