#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const XTDefaultsDidChange;
void XTRegisterDefaults(void);
NSColor *XTAccent(void);
NSTextField *XTLabel(NSString *text, CGFloat size, NSFontWeight weight);
NSButton *XTSymbolButton(NSString *symbol, NSString *tip, id target, SEL action);
void XTAlert(NSString *title, NSString *message);
void XTCopyImage(NSImage *image);
void XTSaveImage(NSImage *image, void (^ _Nullable completion)(BOOL saved));
NSSize XTPixelSize(NSImage *image);
NSString *XTShortcutTitle(NSDictionary *shortcut);
NS_ASSUME_NONNULL_END
