#import <Cocoa/Cocoa.h>
@class XTHotKeys;
@interface XTSettingsController : NSWindowController <NSWindowDelegate>
@property (nonatomic, copy) void (^onCapture)(void);
@property (nonatomic, copy) void (^onPaste)(void);
- (instancetype)initWithHotKeys:(XTHotKeys *)hotKeys;
- (void)show;
- (void)refresh;
@end
