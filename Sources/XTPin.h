#import <Cocoa/Cocoa.h>

@interface XTPinController : NSWindowController <NSWindowDelegate>
@property (nonatomic, readonly) NSImage *image;
@property (nonatomic, copy) void (^onClose)(XTPinController *pin);
- (instancetype)initWithImage:(NSImage *)image origin:(NSPoint)origin;
- (void)showPin;
- (void)hidePin;
- (void)refreshAppearance;
@end
