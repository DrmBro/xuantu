#import "XTHotKeys.h"
#import "XTCommon.h"
#import <Carbon/Carbon.h>

static UInt32 XTCarbonModifiers(NSUInteger flags) {
    UInt32 result = 0;
    if (flags & NSEventModifierFlagCommand) result |= cmdKey;
    if (flags & NSEventModifierFlagOption) result |= optionKey;
    if (flags & NSEventModifierFlagControl) result |= controlKey;
    if (flags & NSEventModifierFlagShift) result |= shiftKey;
    return result;
}
static OSStatus XTHandleHotKey(EventHandlerCallRef next, EventRef event, void *context) {
    EventHotKeyID key;
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(key), NULL, &key) != noErr) return eventNotHandledErr;
    if (key.signature != 'XTu1' || key.id < 1 || key.id > 3) return eventNotHandledErr;
    XTHotKeys *owner = (__bridge XTHotKeys *)context;
    if (!owner.isSuspended && owner.handler && NSApp.modalWindow == nil) owner.handler(key.id - 1);
    return noErr;
}
@implementation XTHotKeys {
    EventHotKeyRef _refs[3];
    EventHandlerRef _eventHandler;
    NSArray<NSDictionary *> *_shortcuts;
    NSArray<NSString *> *_registrationErrors;
    BOOL _suspended;
}
- (NSArray *)shortcuts { return _shortcuts; }
- (BOOL)isSuspended { return _suspended; }
- (NSArray *)registrationErrors { return _registrationErrors ?: @[]; }
- (void)unregisterKeys { for (int i = 0; i < 3; i++) { if (_refs[i]) { UnregisterEventHotKey(_refs[i]); _refs[i] = NULL; } } }
- (NSArray<NSString *> *)registerKeys:(NSArray<NSDictionary *> *)keys {
    NSMutableArray *errors = [NSMutableArray array];
    NSArray *names = @[@"区域截图", @"剪贴板贴图", @"隐藏／显示贴图"];
    for (int i = 0; i < 3; i++) {
        EventHotKeyID hotID = { 'XTu1', (UInt32)i + 1 };
        OSStatus status = RegisterEventHotKey([keys[i][@"key"] unsignedIntValue], XTCarbonModifiers([keys[i][@"mods"] unsignedIntegerValue]), hotID, GetApplicationEventTarget(), 0, &_refs[i]);
        if (status != noErr) [errors addObject:[NSString stringWithFormat:@"%@（%@）未注册成功，可能已被占用。错误码 %d", names[i], XTShortcutTitle(keys[i]), (int)status]];
    }
    return errors;
}
- (void)start {
    EventTypeSpec type = { kEventClassKeyboard, kEventHotKeyPressed };
    OSStatus status = InstallEventHandler(GetApplicationEventTarget(), XTHandleHotKey, 1, &type, (__bridge void *)self, &_eventHandler);
    _shortcuts = [[NSUserDefaults standardUserDefaults] arrayForKey:@"shortcuts"];
    if (status != noErr) { _registrationErrors = @[@"全局快捷键服务不可用，仍可通过菜单栏操作。"]; return; }
    _registrationErrors = [self registerKeys:_shortcuts];
}
- (BOOL)applyShortcuts:(NSArray<NSDictionary *> *)shortcuts error:(NSString **)error {
    if (shortcuts.count != 3) return NO;
    for (int i = 0; i < 3; i++) for (int j = i + 1; j < 3; j++) {
        if ([shortcuts[i] isEqual:shortcuts[j]]) { if (error) *error = @"三个功能不能使用同一个快捷键。"; return NO; }
    }
    NSArray *previous = _shortcuts;
    [self unregisterKeys];
    NSArray *errors = [self registerKeys:shortcuts];
    if (errors.count) {
        [self unregisterKeys];
        _registrationErrors = [self registerKeys:previous];
        if (error) *error = [errors componentsJoinedByString:@"\n"];
        return NO;
    }
    _shortcuts = [shortcuts copy]; _registrationErrors = @[];
    [[NSUserDefaults standardUserDefaults] setObject:_shortcuts forKey:@"shortcuts"];
    [[NSNotificationCenter defaultCenter] postNotificationName:XTDefaultsDidChange object:nil];
    return YES;
}
- (void)suspend {
    if (_suspended) return;
    _suspended = YES; [self unregisterKeys];
}
- (void)resume {
    if (!_suspended) return;
    _suspended = NO; _registrationErrors = [self registerKeys:_shortcuts];
}
- (void)stop { [self unregisterKeys]; if (_eventHandler) { RemoveEventHandler(_eventHandler); _eventHandler = NULL; } }
- (void)dealloc { [self stop]; }
@end

@implementation XTShortcutButton {
    BOOL _recording;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) { self.bezelStyle = NSBezelStyleRounded; self.target = self; self.action = @selector(beginRecord:); }
    return self;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)setShortcut:(NSDictionary *)shortcut { _shortcut = [shortcut copy]; self.title = XTShortcutTitle(shortcut); }
- (void)beginRecord:(id)sender {
    [self.window makeFirstResponder:self];
    if (_recording) return;
    _recording = YES; self.title = @"按下组合键…";
    if (self.onBeginRecording) self.onBeginRecording();
}
- (void)endRecording {
    if (!_recording) return;
    _recording = NO; self.title = XTShortcutTitle(self.shortcut);
    if (self.onEndRecording) self.onEndRecording();
}
- (BOOL)resignFirstResponder { [self endRecording]; return YES; }
- (BOOL)performKeyEquivalent:(NSEvent *)event { if (_recording && event.type == NSEventTypeKeyDown) { [self keyDown:event]; return YES; } return [super performKeyEquivalent:event]; }
- (void)keyDown:(NSEvent *)event {
    if (!_recording) { [super keyDown:event]; return; }
    if (event.keyCode == 53) { [self endRecording]; return; }
    NSUInteger flags = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift);
    if (!(flags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl))) { self.title = @"需搭配 ⌘ / ⌥ / ⌃"; NSBeep(); return; }
    [self endRecording];
    if (self.onRecord) self.onRecord(@{@"key": @(event.keyCode), @"mods": @(flags)});
    self.title = XTShortcutTitle(self.shortcut);
}
@end
