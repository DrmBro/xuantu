#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, XTAnnotationKind) {
    XTAnnotationRectangle = 1,
    XTAnnotationArrow = 2,
    XTAnnotationText = 3,
};

// 坐标统一为选区视图的左下角原点；文本 start 表示文本区域左上角。
@interface XTAnnotation : NSObject <NSCopying>
@property (nonatomic) XTAnnotationKind kind;
@property (nonatomic) NSPoint start;
@property (nonatomic) NSPoint end;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic) CGFloat lineWidth;
@property (nonatomic) CGFloat fontSize;
@property (nonatomic, copy) NSString *text;
@property (nonatomic) CGFloat textWidth;
- (NSRect)bounds;
- (BOOL)hitTest:(NSPoint)point tolerance:(CGFloat)tolerance;
- (void)moveBy:(NSSize)delta;
- (void)draw;
@end

// 返回保留截图原像素比例的合成图；不包含选区边框、编辑框或工具栏。
FOUNDATION_EXPORT NSImage * _Nullable XTCompositeCapture(NSImage *snapshot, NSSize canvasSize, NSRect selection, NSArray<XTAnnotation *> *annotations);
NS_ASSUME_NONNULL_END
