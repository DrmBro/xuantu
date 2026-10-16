#import "XTPin.h"
#import "XTCommon.h"
#import <QuartzCore/QuartzCore.h>

@interface XTPinPanel : NSPanel @end
@implementation XTPinPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@class XTPinView;
@interface XTPinController ()
@property (nonatomic, readwrite) NSImage *image;
@property (nonatomic) CGFloat scale;
@property (nonatomic) NSSize baseSize;
@property (nonatomic, strong) XTPinView *pinView;
- (void)scaleBy:(CGFloat)factor;
- (void)changeOpacity:(CGFloat)delta;
- (void)copy:(id)sender;
- (void)save:(id)sender;
- (void)closePin:(id)sender;
- (void)resetSize:(id)sender;
- (void)fitToScreen:(id)sender;
- (NSMenu *)contextMenu;
@end

@interface XTPinView : NSView
@property (nonatomic, weak) XTPinController *owner;
@property (nonatomic, strong) NSView *toolbar;
@property (nonatomic, strong) NSTextField *feedback;
- (void)flash:(NSString *)message;
@end
@implementation XTPinView {
    NSTrackingArea *_tracking;
    NSUInteger _flashGeneration;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        _toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 156, 34)];
        _toolbar.wantsLayer = YES; _toolbar.layer.backgroundColor = [NSColor colorWithWhite:0.13 alpha:0.94].CGColor;
        _toolbar.layer.cornerRadius = 8;
        NSArray *symbols = @[@"doc.on.doc", @"square.and.arrow.down", @"arrow.up.left.and.arrow.down.right", @"xmark"];
        NSArray *tips = @[@"复制图片 ⌘C", @"保存图片 ⌘S", @"恢复原始大小 ⌘0", @"关闭贴图 ⌘W / Esc"];
        NSArray *actions = @[@"copyImage:", @"saveImage:", @"resetImage:", @"closeImage:"];
        for (NSInteger i = 0; i < 4; i++) {
            NSButton *b = XTSymbolButton(symbols[i], tips[i], self, NSSelectorFromString(actions[i]));
            b.frame = NSMakeRect(4 + 38 * i, 3, 34, 28); b.contentTintColor = NSColor.whiteColor;
            [_toolbar addSubview:b];
        }
        [self addSubview:_toolbar]; _toolbar.hidden = YES;
        _feedback = XTLabel(@"", 11, NSFontWeightMedium); _feedback.textColor = NSColor.whiteColor;
        _feedback.alignment = NSTextAlignmentCenter; _feedback.wantsLayer = YES;
        _feedback.layer.backgroundColor = [NSColor colorWithWhite:0.1 alpha:0.85].CGColor;
        _feedback.layer.cornerRadius = 6; _feedback.hidden = YES;
        [self addSubview:_feedback]; self.needsLayout = YES;
    }
    return self;
}
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; self.needsLayout = YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)layout {
    [super layout];
    self.toolbar.frame = NSMakeRect(MAX(0, (self.bounds.size.width - 156) / 2), MAX(0, self.bounds.size.height - 42), 156, 34);
    self.feedback.frame = NSMakeRect(MAX(2, (self.bounds.size.width - 130) / 2), 8, MIN(130, self.bounds.size.width - 4), 23);
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.clearColor setFill]; NSRectFillUsingOperation(self.bounds, NSCompositingOperationCopy);
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;
    [self.owner.image drawInRect:self.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:NO hints:nil];
    [[NSColor colorWithWhite:0 alpha:0.16] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:self.layer.cornerRadius yRadius:self.layer.cornerRadius];
    border.lineWidth = 1; [border stroke];
}
- (void)mouseEntered:(NSEvent *)event { self.toolbar.hidden = self.bounds.size.width < 160 || self.bounds.size.height < 65; }
- (void)mouseExited:(NSEvent *)event { self.toolbar.hidden = YES; }
- (void)mouseDown:(NSEvent *)event {
    [self.window makeKeyWindow]; [self.window makeFirstResponder:self];
    if (event.clickCount == 2 && [[NSUserDefaults standardUserDefaults] boolForKey:@"doubleClickCloses"]) { XTCopyImage(self.owner.image); [self.owner closePin:nil]; return; }
    [self.window performWindowDragWithEvent:event];
}
- (void)rightMouseDown:(NSEvent *)event { [NSMenu popUpContextMenu:[self.owner contextMenu] withEvent:event forView:self]; }
- (void)scrollWheel:(NSEvent *)event {
    CGFloat delta = MAX(-12, MIN(12, event.scrollingDeltaY));
    if (event.modifierFlags & NSEventModifierFlagOption) [self.owner changeOpacity:delta * 0.015];
    else [self.owner scaleBy:pow(1.035, delta)];
}
- (void)magnifyWithEvent:(NSEvent *)event { [self.owner scaleBy:MAX(0.5, 1 + event.magnification)]; }
- (void)keyDown:(NSEvent *)event {
    NSString *s = event.charactersIgnoringModifiers.lowercaseString;
    BOOL command = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    if (event.keyCode == 53 || (command && [s isEqual:@"w"])) [self.owner closePin:nil];
    else if (command && [s isEqual:@"c"]) [self.owner copy:nil];
    else if (command && [s isEqual:@"s"]) [self.owner save:nil];
    else if (command && [s isEqual:@"0"]) [self.owner resetSize:nil];
    else if ([s isEqual:@"+"] || [s isEqual:@"="]) [self.owner scaleBy:1.1];
    else if ([s isEqual:@"-"]) [self.owner scaleBy:1 / 1.1];
    else [super keyDown:event];
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if ((event.modifierFlags & NSEventModifierFlagCommand) && [@[@"w", @"c", @"s", @"0", @"+", @"=", @"-"] containsObject:event.charactersIgnoringModifiers.lowercaseString]) { [self keyDown:event]; return YES; }
    return [super performKeyEquivalent:event];
}
- (void)flash:(NSString *)message {
    self.feedback.stringValue = message; self.feedback.hidden = NO;
    NSUInteger generation = ++_flashGeneration;
    __weak XTPinView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        XTPinView *view = weakSelf;
        if (view && view->_flashGeneration == generation) view.feedback.hidden = YES;
    });
}
- (void)copy:(id)sender { [self.owner copy:sender]; }
- (void)copyImage:(id)sender { [self.owner copy:sender]; }
- (void)saveImage:(id)sender { [self.owner save:sender]; }
- (void)resetImage:(id)sender { [self.owner resetSize:sender]; }
- (void)closeImage:(id)sender { [self.owner closePin:sender]; }
@end

@implementation XTPinController
- (instancetype)initWithImage:(NSImage *)image origin:(NSPoint)origin {
    NSSize base = image.size;
    if (base.width <= 0 || base.height <= 0) return nil;
    NSScreen *screen = NSScreen.mainScreen;
    for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(origin, candidate.frame)) { screen = candidate; break; }
    NSRect visible = screen.visibleFrame;
    CGFloat scale = MIN(1, MIN(visible.size.width * 0.8 / base.width, visible.size.height * 0.8 / base.height));
    NSSize size = NSMakeSize(MAX(1, base.width * scale), MAX(1, base.height * scale));
    origin.x = MAX(NSMinX(visible), MIN(origin.x, NSMaxX(visible) - size.width));
    origin.y = MAX(NSMinY(visible), MIN(origin.y, NSMaxY(visible) - size.height));
    XTPinPanel *panel = [[XTPinPanel alloc] initWithContentRect:NSMakeRect(origin.x, origin.y, size.width, size.height) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:panel])) {
        self.image = image; self.baseSize = base; self.scale = scale;
        panel.delegate = self; panel.title = @"悬图 · 贴图";
        panel.opaque = NO; panel.backgroundColor = NSColor.clearColor;
        panel.hasShadow = YES; panel.level = NSFloatingWindowLevel;
        panel.hidesOnDeactivate = NO; panel.becomesKeyOnlyIfNeeded = NO;
        panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
        panel.releasedWhenClosed = NO; panel.animationBehavior = NSWindowAnimationBehaviorNone;
        panel.alphaValue = MAX(0.2, MIN(1, [[NSUserDefaults standardUserDefaults] doubleForKey:@"defaultOpacity"]));
        self.pinView = [[XTPinView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
        self.pinView.owner = self; panel.contentView = self.pinView;
        [self refreshAppearance];
    }
    return self;
}
- (void)refreshAppearance {
    self.pinView.layer.cornerRadius = [[NSUserDefaults standardUserDefaults] boolForKey:@"roundedPins"] ? 8 : 0;
    self.pinView.layer.masksToBounds = YES; self.pinView.needsDisplay = YES;
    [self.window invalidateShadow];
}
- (void)showPin { [self.window orderFrontRegardless]; }
- (void)hidePin { [self.window orderOut:nil]; }
- (void)setScaleKeepingCenter:(CGFloat)scale {
    CGFloat maxScale = MIN(8, 12000 / MAX(self.baseSize.width, self.baseSize.height));
    CGFloat minScale = MIN(maxScale, MAX(0.02, 32 / MAX(self.baseSize.width, self.baseSize.height)));
    self.scale = MAX(minScale, MIN(maxScale, scale));
    NSRect old = self.window.frame;
    NSSize size = NSMakeSize(self.baseSize.width * self.scale, self.baseSize.height * self.scale);
    NSRect frame = NSMakeRect(NSMidX(old) - size.width / 2, NSMidY(old) - size.height / 2, size.width, size.height);
    [self.window setFrame:frame display:YES];
    [self.pinView flash:[NSString stringWithFormat:@"缩放 %.0f%%", self.scale * 100]];
}
- (void)scaleBy:(CGFloat)factor { [self setScaleKeepingCenter:self.scale * factor]; }
- (void)changeOpacity:(CGFloat)delta {
    self.window.alphaValue = MAX(0.2, MIN(1, self.window.alphaValue + delta));
    [self.pinView flash:[NSString stringWithFormat:@"不透明度 %.0f%%", self.window.alphaValue * 100]];
}
- (void)copy:(id)sender { XTCopyImage(self.image); [self.pinView flash:@"已复制"]; }
- (void)save:(id)sender { XTSaveImage(self.image, nil); }
- (void)closePin:(id)sender { [self close]; }
- (void)resetSize:(id)sender { [self setScaleKeepingCenter:1]; }
- (void)fitToScreen:(id)sender {
    NSRect screen = (self.window.screen ?: NSScreen.mainScreen).visibleFrame;
    [self setScaleKeepingCenter:MIN(screen.size.width * 0.8 / self.baseSize.width, screen.size.height * 0.8 / self.baseSize.height)];
    NSRect f = self.window.frame;
    f.origin = NSMakePoint(NSMidX(screen) - f.size.width / 2, NSMidY(screen) - f.size.height / 2);
    [self.window setFrame:f display:YES];
}
- (void)opacityChanged:(NSSlider *)slider { self.window.alphaValue = slider.doubleValue; }
- (NSMenu *)contextMenu {
    NSMenu *m = [NSMenu new];
    NSSize pixels = XTPixelSize(self.image);
    NSMenuItem *info = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%.0f × %.0f 像素 · %.0f%%", pixels.width, pixels.height, self.scale * 100] action:nil keyEquivalent:@""];
    info.enabled = NO; [m addItem:info]; [m addItem:NSMenuItem.separatorItem];
    NSArray *titles = @[@"复制图片", @"保存为 PNG…", @"恢复原始大小", @"适应屏幕"];
    NSArray *actions = @[@"copy:", @"save:", @"resetSize:", @"fitToScreen:"];
    NSArray *keys = @[@"c", @"s", @"0", @""];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[i] action:NSSelectorFromString(actions[i]) keyEquivalent:keys[i]];
        item.target = self; [m addItem:item];
    }
    [m addItem:NSMenuItem.separatorItem];
    NSView *opacityView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 230, 48)];
    NSTextField *l = XTLabel(@"不透明度", 11, NSFontWeightRegular); l.frame = NSMakeRect(16, 29, 190, 16); [opacityView addSubview:l];
    NSSlider *slider = [NSSlider sliderWithValue:self.window.alphaValue minValue:0.2 maxValue:1 target:self action:@selector(opacityChanged:)];
    slider.frame = NSMakeRect(14, 4, 200, 22); slider.continuous = YES; [opacityView addSubview:slider];
    NSMenuItem *opacity = [NSMenuItem new]; opacity.view = opacityView; [m addItem:opacity];
    [m addItem:NSMenuItem.separatorItem];
    NSMenuItem *close = [[NSMenuItem alloc] initWithTitle:@"关闭贴图" action:@selector(closePin:) keyEquivalent:@"w"];
    close.target = self; [m addItem:close]; return m;
}
- (void)windowWillClose:(NSNotification *)notification { if (self.onClose) self.onClose(self); }
@end
