#import "XTAppDelegate.h"
#import "XTCommon.h"
#import "XTHotKeys.h"
#import "XTCapture.h"
#import "XTPin.h"
#import "XTSettings.h"

@implementation XTAppDelegate {
    NSStatusItem *_status;
    XTHotKeys *_hotKeys;
    XTCaptureController *_capture;
    XTSettingsController *_settings;
    NSMutableArray<XTPinController *> *_pins;
    BOOL _pinsHidden;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID]) {
        if (app.processIdentifier != getpid()) { [app activateWithOptions:0]; [NSApp terminate:nil]; return; }
    }
    XTRegisterDefaults();
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self createMainMenu];
    _pins = [NSMutableArray array];
    _hotKeys = [XTHotKeys new];
    __weak XTAppDelegate *weakSelf = self;
    _hotKeys.handler = ^(NSUInteger index) {
        XTAppDelegate *owner = weakSelf; if (!owner) return;
        if (index == 0) [owner capture:nil];
        else if (index == 1) [owner paste:nil];
        else [owner togglePins:nil];
    };
    [_hotKeys start];
    _capture = [XTCaptureController new];
    _capture.onPin = ^(NSImage *image, NSPoint origin) { [weakSelf addPin:image origin:origin]; };
    _capture.onStateChange = ^(BOOL active) { [weakSelf updateMenu]; };
    _settings = [[XTSettingsController alloc] initWithHotKeys:_hotKeys];
    _settings.onCapture = ^{ [weakSelf capture:nil]; };
    _settings.onPaste = ^{ [weakSelf paste:nil]; };
    _status = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"pin.square" accessibilityDescription:@"悬图"];
    icon.template = YES; _status.button.image = icon;
    _status.button.toolTip = @"悬图 · 截图与贴图";
    [self updateMenu];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged:) name:XTDefaultsDidChange object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screensChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"hasOpened"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"hasOpened"];
        [_settings show];
    } else if (_hotKeys.registrationErrors.count) [_settings show];
}
- (void)createMainMenu {
    NSMenu *main = [NSMenu new];
    NSMenuItem *app = [NSMenuItem new]; [main addItem:app];
    NSMenu *appMenu = [NSMenu new]; app.submenu = appMenu;
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"悬图设置…" action:@selector(showSettings:) keyEquivalent:@","]; settings.target = self; [appMenu addItem:settings];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出悬图" action:@selector(terminate:) keyEquivalent:@"q"]; quit.target = NSApp; [appMenu addItem:quit];
    NSMenuItem *edit = [NSMenuItem new]; edit.title = @"编辑"; [main addItem:edit];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"编辑"]; edit.submenu = editMenu;
    NSArray *titles = @[@"撤销", @"重做", @"剪切", @"复制", @"粘贴", @"全选"];
    NSArray *actions = @[@"undo:", @"redo:", @"cut:", @"copy:", @"paste:", @"selectAll:"];
    NSArray *keys = @[@"z", @"z", @"x", @"c", @"v", @"a"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSMenuItem *item = [editMenu addItemWithTitle:titles[i] action:NSSelectorFromString(actions[i]) keyEquivalent:keys[i]];
        if (i == 1) item.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    }
    NSApp.mainMenu = main;
}
- (void)addMenuItem:(NSString *)title action:(SEL)action to:(NSMenu *)menu enabled:(BOOL)enabled {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self; item.enabled = enabled; [menu addItem:item];
}
- (void)updateMenu {
    if (!_status) return;
    NSMenu *menu = [NSMenu new]; menu.autoenablesItems = NO; menu.delegate = self;
    NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"悬图 · 留住眼前的画面" action:nil keyEquivalent:@""]; header.enabled = NO; [menu addItem:header];
    [menu addItem:NSMenuItem.separatorItem];
    NSArray *shortcuts = _hotKeys.shortcuts;
    NSString *capture = _capture.active ? @"正在截图…" : [NSString stringWithFormat:@"区域截图                       %@", XTShortcutTitle(shortcuts[0])];
    [self addMenuItem:capture action:@selector(capture:) to:menu enabled:!_capture.active];
    [self addMenuItem:[NSString stringWithFormat:@"剪贴板贴图                   %@", XTShortcutTitle(shortcuts[1])] action:@selector(paste:) to:menu enabled:!_capture.active];
    if (_capture.active) [self addMenuItem:@"取消当前截图" action:@selector(cancelCapture:) to:menu enabled:YES];
    [menu addItem:NSMenuItem.separatorItem];
    NSString *toggle = [NSString stringWithFormat:@"%@全部贴图（%lu）      %@", _pinsHidden ? @"显示" : @"隐藏", (unsigned long)_pins.count, XTShortcutTitle(shortcuts[2])];
    [self addMenuItem:toggle action:@selector(togglePins:) to:menu enabled:_pins.count > 0 && !_capture.active];
    [self addMenuItem:@"关闭全部贴图…" action:@selector(closeAll:) to:menu enabled:_pins.count > 0 && !_capture.active];
    [menu addItem:NSMenuItem.separatorItem];
    [self addMenuItem:@"设置与快捷键…" action:@selector(showSettings:) to:menu enabled:!_capture.active];
    [self addMenuItem:@"关于悬图" action:@selector(about:) to:menu enabled:!_capture.active];
    [menu addItem:NSMenuItem.separatorItem];
    [self addMenuItem:@"退出悬图" action:@selector(quit:) to:menu enabled:YES];
    _status.menu = menu;
}
- (void)capture:(id)sender {
    if (_capture.active || NSApp.modalWindow) return;
    [_settings.window orderOut:nil];
    [_capture begin];
}
- (void)cancelCapture:(id)sender { [_capture cancel]; }
- (void)paste:(id)sender {
    if (_capture.active || NSApp.modalWindow) return;
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    NSImage *image = [[pb readObjectsForClasses:@[NSImage.class] options:@{}] firstObject];
    if (!image) {
        NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
        NSURL *url = urls.firstObject;
        if (url.isFileURL) image = [[NSImage alloc] initWithContentsOfURL:url];
    }
    if (!image || !image.isValid) { XTAlert(@"剪贴板里还没有图片", @"先复制一张图片或本地图片文件，再使用剪贴板贴图。"); return; }
    NSSize pixels = XTPixelSize(image);
    if (pixels.width <= 0 || pixels.height <= 0 || pixels.width * pixels.height > 100000000) {
        XTAlert(@"图片尺寸过大", @"请选择不超过一亿像素的图片，或先缩小图片后再贴图。"); return;
    }
    // 固定一份位图，避免后续剪贴板变化或文件移动影响已有贴图。
    CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cg) { XTAlert(@"无法读取图片", @"请先把图片转换为 PNG 或 JPEG 后重试。"); return; }
    NSScreen *screen = NSScreen.mainScreen;
    for (NSScreen *s in NSScreen.screens) if (NSPointInRect(NSEvent.mouseLocation, s.frame)) { screen = s; break; }
    CGFloat scale = screen.backingScaleFactor;
    NSSize logical = NSMakeSize(pixels.width / scale, pixels.height / scale);
    NSImage *stable = [[NSImage alloc] initWithCGImage:cg size:logical];
    NSRect frame = screen.visibleFrame;
    NSPoint origin = NSMakePoint(NSMidX(frame) - MIN(logical.width, frame.size.width * 0.8) / 2,
                                NSMidY(frame) - MIN(logical.height, frame.size.height * 0.8) / 2);
    [self addPin:stable origin:origin];
}
- (void)addPin:(NSImage *)image origin:(NSPoint)origin {
    XTPinController *pin = [[XTPinController alloc] initWithImage:image origin:origin];
    if (!pin) return;
    __weak XTAppDelegate *weakSelf = self;
    pin.onClose = ^(XTPinController *closed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            XTAppDelegate *owner = weakSelf; if (!owner) return;
            [owner->_pins removeObject:closed];
            if (owner->_pins.count == 0) owner->_pinsHidden = NO;
            [owner updateMenu];
        });
    };
    if (_pinsHidden) { _pinsHidden = NO; for (XTPinController *p in _pins) [p showPin]; }
    [_pins addObject:pin]; [pin showPin]; [self updateMenu];
}
- (void)togglePins:(id)sender {
    if (_capture.active || _pins.count == 0) return;
    _pinsHidden = !_pinsHidden;
    for (XTPinController *pin in _pins) { if (_pinsHidden) [pin hidePin]; else [pin showPin]; }
    [self updateMenu];
}
- (void)closeAll:(id)sender {
    if (!_pins.count) return;
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *a = [NSAlert new]; a.messageText = @"关闭全部贴图？";
    a.informativeText = @"贴图不会自动保存，未保存的图片关闭后无法恢复。";
    [a addButtonWithTitle:@"取消"]; [a addButtonWithTitle:@"关闭全部"];
    if ([a runModal] == NSAlertSecondButtonReturn) for (XTPinController *pin in [_pins copy]) [pin close];
}
- (void)showSettings:(id)sender { [_settings show]; }
- (void)settingsChanged:(NSNotification *)notification {
    for (XTPinController *pin in _pins) [pin refreshAppearance];
    [self updateMenu];
}
- (void)screensChanged:(NSNotification *)notification {
    if (_capture.active) [_capture cancel];
    // 显示器断开后把已不在任何屏幕上的贴图带回当前屏幕。
    for (XTPinController *pin in _pins) {
        BOOL visible = NO;
        for (NSScreen *screen in NSScreen.screens) if (NSIntersectsRect(pin.window.frame, screen.visibleFrame)) { visible = YES; break; }
        if (!visible) [pin.window center];
    }
}
- (void)about:(id)sender {
    XTAlert(@"悬图 1.3.1", @"独立的 macOS 截图与悬浮贴图工具。\n\n图片和文字识别仅在本机处理，不自动上传。\n\n贴图：空白处拖动移动，空格拖动可移动任意位置。\n滚轮缩放，⌥滚轮调整透明度。\n文字：直接拖选，⌘C 复制所选文字，⌘A 全选文字。\n⇧⌘C 始终复制图片，右键可复制全部文字。\n双击空白处复制并关闭，双击文字选词。\nEsc 先取消文字选择，无选择时关闭；⌘W 直接关闭。\n截图：悬停选窗口，单击锁定，拖动框选，Tab 切换窗口。\n截图：拖动边缘缩放，空格拖动移动选区。\n标注：V 选择、R 矩形、A 箭头、X 文本。\n矩形：拖动框内移动，拖动八个控制点缩放。\n标注：⌘Z 撤销、⇧⌘Z 重做，文字编辑时⌘回车完成。\n导出：T 贴图，回车复制，⌘S 保存，Esc 取消。");
}
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    [_capture cancel];
    if (!_pins.count) return NSTerminateNow;
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *a = [NSAlert new]; a.messageText = @"退出悬图？";
    a.informativeText = [NSString stringWithFormat:@"当前还有 %lu 张贴图，未保存的图片将在退出后丢失。", (unsigned long)_pins.count];
    [a addButtonWithTitle:@"取消"]; [a addButtonWithTitle:@"退出"];
    return [a runModal] == NSAlertSecondButtonReturn ? NSTerminateNow : NSTerminateCancel;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    [_hotKeys stop]; [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag { [_settings show]; return YES; }
@end
