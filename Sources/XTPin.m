#import "XTPin.h"
#import "XTCommon.h"
#import "XuanTuText-Swift.h"
#import <QuartzCore/QuartzCore.h>

@class XTPinView;
@interface XTPinPanel : NSPanel
@property (nonatomic, weak) XTPinView *pinView;
@end

@interface XTPinController ()
@property (nonatomic, readwrite) NSImage *image;
@property (nonatomic) CGFloat scale;
@property (nonatomic) NSSize baseSize;
@property (nonatomic, strong) XTPinView *pinView;
- (void)scaleBy:(CGFloat)factor;
- (void)changeOpacity:(CGFloat)delta;
- (void)copy:(id)sender;
- (void)copyImage:(id)sender;
- (void)copySelectedText:(id)sender;
- (void)copyAllText:(id)sender;
- (void)selectAll:(id)sender;
- (void)extractText:(id)sender;
- (void)recognizeText:(id)sender;
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
@property (nonatomic, strong) NSButton *textButton;
@property (nonatomic, strong) XTTextSelectionController *textSelection;
- (BOOL)handleShortcut:(NSEvent *)event;
- (BOOL)handleWindowEvent:(NSEvent *)event;
- (void)clearSpaceDrag;
- (void)startTextRecognition;
- (void)flash:(NSString *)message;
@end

@implementation XTPinPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)sendEvent:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown) [self makeKeyWindow];
    // 选择层获得焦点后，滚轮和捏合仍然控制整张贴图。
    if (event.type == NSEventTypeScrollWheel) { [self.pinView scrollWheel:event]; return; }
    if (event.type == NSEventTypeMagnify) { [self.pinView magnifyWithEvent:event]; return; }
    if (![self.pinView handleWindowEvent:event]) [super sendEvent:event];
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if ((event.modifierFlags & NSEventModifierFlagCommand) && [self.pinView handleShortcut:event]) return YES;
    return [super performKeyEquivalent:event];
}
@end

@implementation XTPinView {
    NSTrackingArea *_tracking;
    NSUInteger _flashGeneration;
    BOOL _spaceDrag;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        _textSelection = [XTTextSelectionController new];
        _textSelection.contentView = self;
        _textSelection.overlayView.frame = self.bounds;
        [self addSubview:_textSelection.overlayView];
        __weak XTPinView *weakSelf = self;
        _textSelection.onStateChange = ^{
            XTPinView *view = weakSelf;
            if (!view) return;
            view.textButton.enabled = !view.textSelection.recognizing && view.textSelection.supported;
            view.textButton.toolTip = [NSString stringWithFormat:@"%@\n点击全选文字 · ⌘A 全选 · ⇧⌘C 复制图片", view.textSelection.statusMessage];
            view.textButton.contentTintColor = view.textSelection.hasText ? XTAccent() : NSColor.whiteColor;
            [view.window invalidateCursorRectsForView:view];
            if (view.textSelection.hasText) [view flash:view.textSelection.statusMessage];
        };
        _textSelection.contextMenuProvider = ^NSMenu *{ return [weakSelf.owner contextMenu] ?: [NSMenu new]; };
        _toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 194, 34)];
        _toolbar.wantsLayer = YES; _toolbar.layer.backgroundColor = [NSColor colorWithWhite:0.13 alpha:0.94].CGColor;
        _toolbar.layer.cornerRadius = 8;
        NSArray *symbols = @[@"doc.on.doc", @"square.and.arrow.down", @"text.viewfinder", @"arrow.up.left.and.arrow.down.right", @"xmark"];
        NSArray *tips = @[@"复制图片 ⇧⌘C", @"保存图片 ⌘S", @"提取文字 · ⌘A 全选文字", @"恢复原始大小 ⌘0", @"关闭贴图 ⌘W"];
        NSArray *actions = @[@"copyImage:", @"saveImage:", @"extractText:", @"resetImage:", @"closeImage:"];
        for (NSInteger i = 0; i < 5; i++) {
            NSButton *b = XTSymbolButton(symbols[i], tips[i], self, NSSelectorFromString(actions[i]));
            b.frame = NSMakeRect(4 + 38 * i, 3, 34, 28); b.contentTintColor = NSColor.whiteColor;
            if (i == 2) self.textButton = b;
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
    self.textSelection.overlayView.frame = self.bounds;
    [self.textSelection updateLayout];
    self.toolbar.frame = NSMakeRect(MAX(0, (self.bounds.size.width - 194) / 2), MAX(0, self.bounds.size.height - 42), 194, 34);
    if (self.bounds.size.width < 198 || self.bounds.size.height < 65) self.toolbar.hidden = YES;
    CGFloat feedbackWidth = MIN(MAX(0, self.bounds.size.width - 4), MAX(130, self.feedback.intrinsicContentSize.width + 20));
    self.feedback.frame = NSMakeRect(MAX(2, (self.bounds.size.width - feedbackWidth) / 2), 8, feedbackWidth, 23);
}
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    NSView *overlay = self.textSelection.overlayView;
    if (hit && (hit == overlay || [hit isDescendantOf:overlay])) {
        NSPoint imagePoint = [overlay convertPoint:point fromView:self.superview];
        // 工具栏在覆盖层上方；仅文字区域进入系统选择交互。
        if (_spaceDrag || ![self.textSelection hasTextAtPoint:imagePoint]) return self;
    }
    return hit;
}
- (void)resetCursorRects {
    [super resetCursorRects];
    if (_spaceDrag) [self addCursorRect:self.bounds cursor:NSCursor.openHandCursor];
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
- (void)mouseEntered:(NSEvent *)event { self.toolbar.hidden = self.bounds.size.width < 198 || self.bounds.size.height < 65; }
- (void)mouseExited:(NSEvent *)event { self.toolbar.hidden = YES; }
- (void)mouseDown:(NSEvent *)event {
    [self.window makeKeyWindow]; [self.window makeFirstResponder:self];
    [self.textSelection clearSelection];
    if (!_spaceDrag && event.clickCount == 2 && [[NSUserDefaults standardUserDefaults] boolForKey:@"doubleClickCloses"]) { XTCopyImage(self.owner.image); [self.owner closePin:nil]; return; }
    [self.window performWindowDragWithEvent:event];
}
- (void)rightMouseDown:(NSEvent *)event { [NSMenu popUpContextMenu:[self.owner contextMenu] withEvent:event forView:self]; }
- (void)scrollWheel:(NSEvent *)event {
    CGFloat delta = MAX(-12, MIN(12, event.scrollingDeltaY));
    if (event.modifierFlags & NSEventModifierFlagOption) [self.owner changeOpacity:delta * 0.015];
    else [self.owner scaleBy:pow(1.035, delta)];
}
- (void)magnifyWithEvent:(NSEvent *)event { [self.owner scaleBy:MAX(0.5, 1 + event.magnification)]; }
- (BOOL)handleShortcut:(NSEvent *)event {
    NSString *s = event.charactersIgnoringModifiers.lowercaseString;
    BOOL command = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    if (event.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagOption)) return NO;
    if (event.keyCode == 53) {
        if (self.textSelection.hasSelection) { [self.textSelection clearSelection]; [self.window makeFirstResponder:self]; }
        else [self.owner closePin:nil];
    }
    else if (command && [s isEqual:@"w"]) [self.owner closePin:nil];
    else if (command && [s isEqual:@"c"]) {
        if (event.modifierFlags & NSEventModifierFlagShift) [self.owner copyImage:nil];
        else [self.owner copy:nil];
    }
    else if (command && [s isEqual:@"a"]) [self.owner selectAll:nil];
    else if (command && [s isEqual:@"s"]) [self.owner save:nil];
    else if (command && [s isEqual:@"0"]) [self.owner resetSize:nil];
    else if ([s isEqual:@"+"] || [s isEqual:@"="]) [self.owner scaleBy:1.1];
    else if ([s isEqual:@"-"]) [self.owner scaleBy:1 / 1.1];
    else return NO;
    return YES;
}
- (BOOL)handleWindowEvent:(NSEvent *)event {
    if (event.type == NSEventTypeKeyDown) {
        if (event.keyCode == 49 && !(event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption))) {
            _spaceDrag = YES; [self.window invalidateCursorRectsForView:self]; return YES;
        }
        return [self handleShortcut:event];
    }
    if (event.type == NSEventTypeKeyUp && event.keyCode == 49 && _spaceDrag) { [self clearSpaceDrag]; return YES; }
    return NO;
}
- (void)clearSpaceDrag { _spaceDrag = NO; [self.window invalidateCursorRectsForView:self]; }
- (void)startTextRecognition { [self.textSelection recognizeImage:self.owner.image]; }
- (void)keyDown:(NSEvent *)event {
    if (![self handleShortcut:event]) [super keyDown:event];
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if ((event.modifierFlags & NSEventModifierFlagCommand) && [self handleShortcut:event]) return YES;
    return [super performKeyEquivalent:event];
}
- (void)flash:(NSString *)message {
    self.feedback.stringValue = message; self.feedback.hidden = NO; self.needsLayout = YES;
    NSUInteger generation = ++_flashGeneration;
    __weak XTPinView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        XTPinView *view = weakSelf;
        if (view && view->_flashGeneration == generation) view.feedback.hidden = YES;
    });
}
- (void)copy:(id)sender { [self.owner copy:sender]; }
- (void)copyImage:(id)sender { [self.owner copyImage:sender]; }
- (void)extractText:(id)sender { [self.owner extractText:sender]; }
- (void)selectAll:(id)sender { [self.owner selectAll:sender]; }
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
        self.pinView.owner = self; panel.contentView = self.pinView; panel.pinView = self.pinView;
        [self refreshAppearance];
        [self.pinView startTextRecognition];
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
- (void)copy:(id)sender {
    if (self.pinView.textSelection.selectedText.length) [self copySelectedText:sender];
    else [self copyImage:sender];
}
- (void)copyImage:(id)sender { XTCopyImage(self.image); [self.pinView flash:@"已复制图片"]; }
- (void)copyText:(NSString *)text {
    if (!text.length) { [self.pinView flash:self.pinView.textSelection.statusMessage]; return; }
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents]; [pasteboard setString:text forType:NSPasteboardTypeString];
    [self.pinView flash:@"已复制文字"];
}
- (void)copySelectedText:(id)sender { [self copyText:self.pinView.textSelection.selectedText]; }
- (void)copyAllText:(id)sender { [self copyText:self.pinView.textSelection.recognizedText]; }
- (void)selectAll:(id)sender {
    if (!self.pinView.textSelection.hasText) { [self.pinView flash:self.pinView.textSelection.statusMessage]; return; }
    [self.window makeKeyWindow]; [self.pinView.textSelection selectAllText];
    [self.pinView flash:@"已全选文字 · ⌘C 复制"];
}
- (void)extractText:(id)sender {
    if (self.pinView.textSelection.hasText) [self selectAll:sender];
    else if (self.pinView.textSelection.recognizing) [self.pinView flash:self.pinView.textSelection.statusMessage];
    else [self recognizeText:sender];
}
- (void)recognizeText:(id)sender {
    [self.pinView startTextRecognition]; [self.pinView flash:self.pinView.textSelection.statusMessage];
}
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
    NSMenu *m = [NSMenu new]; m.autoenablesItems = NO;
    NSSize pixels = XTPixelSize(self.image);
    NSMenuItem *info = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%.0f × %.0f 像素 · %.0f%%", pixels.width, pixels.height, self.scale * 100] action:nil keyEquivalent:@""];
    info.enabled = NO; [m addItem:info]; [m addItem:NSMenuItem.separatorItem];
    XTTextSelectionController *text = self.pinView.textSelection;
    NSMenuItem *selected = [[NSMenuItem alloc] initWithTitle:@"复制选中文字" action:@selector(copySelectedText:) keyEquivalent:@"c"];
    selected.target = self; selected.enabled = text.selectedText.length > 0; [m addItem:selected];
    NSMenuItem *all = [[NSMenuItem alloc] initWithTitle:@"复制全部文字" action:@selector(copyAllText:) keyEquivalent:@""];
    all.target = self; all.enabled = text.hasText; [m addItem:all];
    NSMenuItem *select = [[NSMenuItem alloc] initWithTitle:@"全选文字" action:@selector(selectAll:) keyEquivalent:@"a"];
    select.target = self; select.enabled = text.hasText; [m addItem:select];
    if (!text.hasText) {
        NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:text.statusMessage action:nil keyEquivalent:@""];
        status.enabled = NO; [m addItem:status];
    }
    NSMenuItem *retry = [[NSMenuItem alloc] initWithTitle:@"重新识别文字" action:@selector(recognizeText:) keyEquivalent:@""];
    retry.target = self; retry.enabled = text.supported && !text.recognizing; [m addItem:retry];
    [m addItem:NSMenuItem.separatorItem];
    NSArray *titles = @[@"复制图片", @"保存为 PNG…", @"恢复原始大小", @"适应屏幕"];
    NSArray *actions = @[@"copyImage:", @"save:", @"resetSize:", @"fitToScreen:"];
    NSArray *keys = @[@"c", @"s", @"0", @""];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[i] action:NSSelectorFromString(actions[i]) keyEquivalent:keys[i]];
        item.target = self; [m addItem:item];
        if (i == 0) item.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
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
- (void)windowDidResignKey:(NSNotification *)notification { [self.pinView clearSpaceDrag]; }
- (void)windowWillClose:(NSNotification *)notification {
    [self.pinView clearSpaceDrag]; [self.pinView.textSelection invalidate];
    if (self.onClose) self.onClose(self);
}
@end
