#import "XTSettings.h"
#import "XTHotKeys.h"
#import "XTCommon.h"
#import <QuartzCore/QuartzCore.h>

@interface XTSettingsRoot : NSView @end
@implementation XTSettingsRoot
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect { [NSColor.windowBackgroundColor setFill]; NSRectFill(self.bounds); }
@end

@implementation XTSettingsController {
    XTHotKeys *_hotKeys;
    NSMutableArray<XTShortcutButton *> *_recorders;
    NSMutableDictionary<NSString *, NSButton *> *_toggles;
    NSTextField *_permissionLabel;
    NSTextField *_opacityLabel;
    NSSlider *_opacity;
    NSPopUpButton *_presets;
}
- (instancetype)initWithHotKeys:(XTHotKeys *)hotKeys {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 690)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                  backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        _hotKeys = hotKeys; _recorders = [NSMutableArray array]; _toggles = [NSMutableDictionary dictionary];
        window.title = @"悬图"; window.releasedWhenClosed = NO; window.delegate = self;
        window.titlebarAppearsTransparent = YES; window.movableByWindowBackground = YES;
        [window center]; [self buildInterface];
    }
    return self;
}
- (NSTextField *)addLabel:(NSString *)text frame:(NSRect)frame size:(CGFloat)size weight:(NSFontWeight)weight secondary:(BOOL)secondary to:(NSView *)parent {
    NSTextField *label = XTLabel(text, size, weight); label.frame = frame;
    if (secondary) label.textColor = NSColor.secondaryLabelColor;
    [parent addSubview:label]; return label;
}
- (void)addCard:(NSRect)frame to:(NSView *)view {
    NSBox *box = [[NSBox alloc] initWithFrame:frame]; box.boxType = NSBoxCustom;
    box.fillColor = NSColor.controlBackgroundColor; box.borderColor = NSColor.separatorColor;
    box.borderWidth = 0.5; box.cornerRadius = 12;
    [view addSubview:box];
}
- (void)buildInterface {
    XTSettingsRoot *root = [[XTSettingsRoot alloc] initWithFrame:NSMakeRect(0, 0, 640, 690)];
    self.window.contentView = root;
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(28, 20, 64, 64)];
    icon.image = NSApp.applicationIconImage; icon.imageScaling = NSImageScaleProportionallyUpOrDown; [root addSubview:icon];
    [self addLabel:@"悬图" frame:NSMakeRect(108, 20, 400, 38) size:29 weight:NSFontWeightSemibold secondary:NO to:root];
    [self addLabel:@"把需要的画面，留在眼前。" frame:NSMakeRect(110, 61, 450, 23) size:14 weight:NSFontWeightRegular secondary:YES to:root];
    NSButton *capture = [NSButton buttonWithTitle:@"  区域截图" target:self action:@selector(capture:)];
    capture.image = [NSImage imageWithSystemSymbolName:@"viewfinder" accessibilityDescription:nil];
    capture.imagePosition = NSImageLeft; capture.bezelStyle = NSBezelStyleRounded; capture.controlSize = NSControlSizeLarge;
    capture.bezelColor = XTAccent(); capture.toolTip = @"框选后支持矩形、箭头和文字标注"; capture.frame = NSMakeRect(26, 104, 286, 44); [root addSubview:capture];
    NSButton *paste = [NSButton buttonWithTitle:@"  剪贴板贴图" target:self action:@selector(paste:)];
    paste.image = [NSImage imageWithSystemSymbolName:@"pin" accessibilityDescription:nil];
    paste.imagePosition = NSImageLeft; paste.bezelStyle = NSBezelStyleRounded; paste.controlSize = NSControlSizeLarge;
    paste.frame = NSMakeRect(326, 104, 286, 44); [root addSubview:paste];
    [self addCard:NSMakeRect(28, 168, 584, 204) to:root];
    [self addLabel:@"全局快捷键" frame:NSMakeRect(46, 183, 230, 23) size:14 weight:NSFontWeightSemibold secondary:NO to:root];
    NSArray *names = @[@"区域截图", @"剪贴板贴图", @"隐藏 / 显示全部贴图"];
    for (NSUInteger i = 0; i < 3; i++) {
        [self addLabel:names[i] frame:NSMakeRect(46, 221 + i * 36, 300, 23) size:13 weight:NSFontWeightRegular secondary:NO to:root];
        XTShortcutButton *button = [[XTShortcutButton alloc] initWithFrame:NSMakeRect(390, 213 + i * 36, 204, 32)];
        button.shortcut = _hotKeys.shortcuts[i]; button.toolTip = @"点击后按下新的组合键，Esc 取消";
        __weak XTSettingsController *weakSelf = self;
        button.onBeginRecording = ^{ XTSettingsController *owner = weakSelf; if (owner) [owner->_hotKeys suspend]; };
        button.onEndRecording = ^{ XTSettingsController *owner = weakSelf; if (owner) [owner->_hotKeys resume]; };
        button.onRecord = ^(NSDictionary *shortcut) {
            XTSettingsController *owner = weakSelf;
            if (!owner) return;
            NSMutableArray *keys = [owner->_hotKeys.shortcuts mutableCopy]; keys[i] = shortcut;
            NSString *error = nil;
            if (![owner->_hotKeys applyShortcuts:keys error:&error]) XTAlert(@"快捷键未更改", error ?: @"无法注册此快捷键。");
            [owner refresh];
        };
        [root addSubview:button]; [_recorders addObject:button];
    }
    [self addLabel:@"点击右侧组合键可修改" frame:NSMakeRect(46, 338, 270, 18) size:11 weight:NSFontWeightRegular secondary:YES to:root];
    _presets = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(390, 330, 204, 27) pullsDown:NO];
    [_presets addItemsWithTitles:@[@"选择快捷键预设…", @"悬图：⌥⌘ + A / S / H", @"Option 预设：⌥ + A / S / H", @"Control 预设：⌃ + A / S / H"]];
    _presets.target = self; _presets.action = @selector(presetChanged:);
    _presets.toolTip = @"预设会全局占用所选组合键；与其他程序冲突时会保留原配置。"; [root addSubview:_presets];
    [self addCard:NSMakeRect(28, 390, 584, 190) to:root];
    [self addLabel:@"截图与贴图" frame:NSMakeRect(46, 404, 400, 22) size:14 weight:NSFontWeightSemibold secondary:NO to:root];
    NSArray *toggleNames = @[@"框选后直接贴图（跳过标注）", @"截图时排除悬图窗口", @"双击复制并关闭贴图", @"圆角贴图"];
    NSArray *toggleKeys = @[@"autoPin", @"excludePins", @"doubleClickCloses", @"roundedPins"];
    for (NSUInteger i = 0; i < toggleNames.count; i++) {
        CGFloat x = i % 2 == 0 ? 46 : 334;
        CGFloat y = i < 2 ? 442 : 476;
        NSButton *button = [NSButton checkboxWithTitle:toggleNames[i] target:self action:@selector(toggleChanged:)];
        button.frame = NSMakeRect(x, y, 250, 22); button.identifier = toggleKeys[i];
        _toggles[toggleKeys[i]] = button; [root addSubview:button];
    }
    [self addLabel:@"新贴图不透明度" frame:NSMakeRect(46, 534, 140, 23) size:12 weight:NSFontWeightRegular secondary:NO to:root];
    _opacity = [NSSlider sliderWithValue:1 minValue:0.2 maxValue:1 target:self action:@selector(opacityChanged:)];
    _opacity.frame = NSMakeRect(201, 528, 310, 28); _opacity.continuous = YES; [root addSubview:_opacity];
    _opacityLabel = [self addLabel:@"100%" frame:NSMakeRect(534, 533, 60, 22) size:12 weight:NSFontWeightMedium secondary:YES to:root];
    _permissionLabel = [self addLabel:@"" frame:NSMakeRect(30, 598, 578, 38) size:11 weight:NSFontWeightRegular secondary:YES to:root];
    _permissionLabel.maximumNumberOfLines = 2; _permissionLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self addLabel:@"拖动移动 · 滚轮缩放 · ⌥滚轮调透明度 · 右键更多操作" frame:NSMakeRect(30, 644, 580, 20) size:11 weight:NSFontWeightRegular secondary:YES to:root];
    [self refresh];
}
- (void)show { [self refresh]; [NSApp activateIgnoringOtherApps:YES]; [self showWindow:nil]; [self.window makeKeyAndOrderFront:nil]; }
- (void)refresh {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (NSString *key in _toggles) _toggles[key].state = [d boolForKey:key] ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSUInteger i = 0; i < _recorders.count; i++) _recorders[i].shortcut = _hotKeys.shortcuts[i];
    _opacity.doubleValue = [d doubleForKey:@"defaultOpacity"];
    _opacityLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", _opacity.doubleValue * 100];
    if (_hotKeys.registrationErrors.count) {
        _permissionLabel.stringValue = [_hotKeys.registrationErrors componentsJoinedByString:@"\n"];
        _permissionLabel.textColor = NSColor.systemOrangeColor;
    } else {
        _permissionLabel.stringValue = CGPreflightScreenCaptureAccess() ? @"录屏权限已开启。图片保留在内存中，退出前请保存需要的贴图。" : @"首次截图需要系统录屏权限；剪贴板贴图可以直接使用。图片不自动上传或保存。";
        _permissionLabel.textColor = NSColor.secondaryLabelColor;
    }
}
- (void)windowDidBecomeKey:(NSNotification *)notification { [self refresh]; }
- (void)windowDidResignKey:(NSNotification *)notification { for (XTShortcutButton *b in _recorders) [b endRecording]; }
- (void)windowWillClose:(NSNotification *)notification { for (XTShortcutButton *b in _recorders) [b endRecording]; }
- (void)capture:(id)sender { if (self.onCapture) self.onCapture(); }
- (void)paste:(id)sender { if (self.onPaste) self.onPaste(); }
- (void)toggleChanged:(NSButton *)button {
    [[NSUserDefaults standardUserDefaults] setBool:button.state == NSControlStateValueOn forKey:button.identifier];
    [[NSNotificationCenter defaultCenter] postNotificationName:XTDefaultsDidChange object:nil];
}
- (void)opacityChanged:(NSSlider *)slider {
    [[NSUserDefaults standardUserDefaults] setDouble:slider.doubleValue forKey:@"defaultOpacity"];
    _opacityLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", slider.doubleValue * 100];
}
- (void)presetChanged:(NSPopUpButton *)sender {
    NSInteger choice = sender.indexOfSelectedItem;
    if (choice <= 0) return;
    NSUInteger mods = choice == 1 ? NSEventModifierFlagOption | NSEventModifierFlagCommand : (choice == 2 ? NSEventModifierFlagOption : NSEventModifierFlagControl);
    NSArray *keys = @[@{@"key":@0, @"mods":@(mods)}, @{@"key":@1, @"mods":@(mods)}, @{@"key":@4, @"mods":@(mods)}];
    NSString *error = nil;
    if (![_hotKeys applyShortcuts:keys error:&error]) XTAlert(@"预设未应用", error ?: @"快捷键不可用。");
    [sender selectItemAtIndex:0]; [self refresh];
}
@end
