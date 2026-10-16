#import <Cocoa/Cocoa.h>

@interface XTCaptureController : NSObject
@property (nonatomic, readonly) BOOL active;
@property (nonatomic, copy) void (^onPin)(NSImage *image, NSPoint origin);
@property (nonatomic, copy) void (^onStateChange)(BOOL active);
- (void)begin;
- (void)cancel;
@end
