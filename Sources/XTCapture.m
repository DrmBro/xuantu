#import "XTCapture.h"
#import "XTCommon.h"
#import "XTSelectionView.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <QuartzCore/QuartzCore.h>

@interface XTSelectionPanel : NSPanel @end
@implementation XTSelectionPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface XTCaptureController () <XTSelectionViewDelegate>
@property (nonatomic, readwrite) BOOL active;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) NSMutableArray<NSPanel *> *panels;
@property (nonatomic, weak) XTSelectionView *selectedView;
@property (nonatomic, strong) NSRunningApplication *previousApplication;
- (void)selectView:(XTSelectionView *)view;
- (void)finishView:(XTSelectionView *)view action:(NSString *)action;
@end

@implementation XTCaptureController
- (instancetype)init { if ((self = [super init])) _panels = [NSMutableArray array]; return self; }
- (void)setActive:(BOOL)active { _active = active; if (self.onStateChange) self.onStateChange(active); }
- (BOOL)hasPermission {
    if (CGPreflightScreenCaptureAccess()) return YES;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (![d boolForKey:@"askedScreenPermission"]) {
        [d setBool:YES forKey:@"askedScreenPermission"];
        CGRequestScreenCaptureAccess();
        if (CGPreflightScreenCaptureAccess()) return YES;
    }
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *a = [NSAlert new]; a.messageText = @"允许悬图截取屏幕";
    a.informativeText = @"请在系统设置的“录屏与系统录音”中允许“悬图”。授权后如仍无法截图，请退出并重新打开悬图。剪贴板贴图无需录屏权限。";
    [a addButtonWithTitle:@"打开系统设置"]; [a addButtonWithTitle:@"暂不截图"];
    if ([a runModal] == NSAlertFirstButtonReturn) [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"]];
    return NO;
}
- (void)begin {
    if (self.active) return;
    if (![self hasPermission]) return;
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    self.previousApplication = front.processIdentifier == getpid() ? nil : front;
    self.active = YES;
    NSUInteger generation = ++self.generation;
    // 菜单关闭后再采集，避免把菜单阴影留在截图里。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!self.active || self.generation != generation) return;
        [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *content, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!self.active || self.generation != generation) return;
                if (error || !content) { [self fail:error.localizedDescription ?: @"未能读取屏幕内容。请检查录屏权限。" generation:generation]; return; }
                [self captureContent:content generation:generation];
            });
        }];
    });
    // 系统服务异常时可以恢复，不让“截图中”状态永久卡住。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.active && self.generation == generation && self.panels.count == 0)
            [self fail:@"获取屏幕图像超时。可以稍后重试，或检查系统录屏权限。" generation:generation];
    });
}
- (void)captureContent:(SCShareableContent *)content generation:(NSUInteger)generation {
    NSArray<NSScreen *> *screens = NSScreen.screens;
    NSMutableArray<NSDictionary *> *snapshots = [NSMutableArray array];
    NSMutableArray<NSString *> *errors = [NSMutableArray array];
    NSMutableArray<SCWindow *> *excluded = [NSMutableArray array];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"excludePins"]) {
        for (SCWindow *window in content.windows) if (window.owningApplication.processID == getpid()) [excluded addObject:window];
    }
    dispatch_group_t group = dispatch_group_create();
    for (NSScreen *screen in screens) {
        CGDirectDisplayID displayID = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        SCDisplay *display = nil;
        for (SCDisplay *candidate in content.displays) if (candidate.displayID == displayID) { display = candidate; break; }
        if (!display) { [errors addObject:@"某个显示器暂时不可用于截图。"]; continue; }
        NSRect screenFrame = screen.frame;
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:excluded];
        SCStreamConfiguration *configuration = [SCStreamConfiguration new];
        configuration.width = (size_t)llround(screen.frame.size.width * screen.backingScaleFactor);
        configuration.height = (size_t)llround(screen.frame.size.height * screen.backingScaleFactor);
        configuration.showsCursor = NO; configuration.scalesToFit = YES;
        configuration.captureResolution = SCCaptureResolutionBest;
        dispatch_group_enter(group);
        [SCScreenshotManager captureImageWithFilter:filter configuration:configuration completionHandler:^(CGImageRef image, NSError *error) {
            NSImage *snapshot = image ? [[NSImage alloc] initWithCGImage:image size:screenFrame.size] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (snapshot) [snapshots addObject:@{@"image": snapshot, @"frame": [NSValue valueWithRect:screenFrame]}];
                else [errors addObject:error.localizedDescription ?: @"显示器图像获取失败。"];
                dispatch_group_leave(group);
            });
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (!self.active || self.generation != generation) return;
        if (errors.count || snapshots.count == 0) { [self fail:errors.firstObject ?: @"没有可用显示器。" generation:generation]; return; }
        [self showSnapshots:snapshots];
    });
}
- (void)showSnapshots:(NSArray<NSDictionary *> *)snapshots {
    [NSApp activateIgnoringOtherApps:YES];
    NSPanel *keyPanel = nil;
    for (NSDictionary *item in snapshots) {
        NSRect frame = [item[@"frame"] rectValue];
        XTSelectionPanel *panel = [[XTSelectionPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        // 位于菜单栏上方，但给原生下拉菜单和输入法候选窗留出层级。
        panel.level = NSStatusWindowLevel + 1; panel.backgroundColor = NSColor.blackColor;
        panel.opaque = YES; panel.hasShadow = NO; panel.hidesOnDeactivate = NO; panel.releasedWhenClosed = NO;
        panel.acceptsMouseMovedEvents = YES; panel.animationBehavior = NSWindowAnimationBehaviorNone;
        panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary;
        XTSelectionView *view = [[XTSelectionView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
        view.snapshot = item[@"image"]; view.screenFrame = frame; view.delegate = self;
        panel.contentView = view; [self.panels addObject:panel];
        [panel orderFrontRegardless];
        if (NSPointInRect(NSEvent.mouseLocation, frame)) keyPanel = panel;
    }
    keyPanel = keyPanel ?: self.panels.firstObject;
    [keyPanel makeKeyWindow]; [keyPanel makeFirstResponder:keyPanel.contentView];
    [NSCursor.crosshairCursor set];
}
- (void)selectionViewDidBegin:(XTSelectionView *)view { [self selectView:view]; }
- (void)selectionViewDidCancel:(XTSelectionView *)view { [self cancel]; }
- (void)selectionView:(XTSelectionView *)view didFinishWithAction:(NSString *)action { [self finishView:view action:action]; }
- (void)selectView:(XTSelectionView *)view {
    if (self.selectedView != view) [self.selectedView clearSelection];
    self.selectedView = view;
}
- (void)finishView:(XTSelectionView *)view action:(NSString *)action {
    NSImage *image = [view croppedImage];
    if (!image) { NSBeep(); return; }
    NSPoint origin = NSMakePoint(view.screenFrame.origin.x + view.selection.origin.x, view.screenFrame.origin.y + view.selection.origin.y);
    [self cancel];
    if ([action isEqual:@"pin"]) { if (self.onPin) self.onPin(image, origin); }
    else if ([action isEqual:@"copy"]) XTCopyImage(image);
    else if ([action isEqual:@"save"]) XTSaveImage(image, nil);
}
- (void)fail:(NSString *)message generation:(NSUInteger)generation {
    if (generation != self.generation) return;
    [self cancel]; XTAlert(@"暂时无法截图", message);
}
- (void)cancel {
    ++self.generation;
    for (NSPanel *panel in self.panels) { [panel orderOut:nil]; [panel close]; }
    [self.panels removeAllObjects]; self.selectedView = nil;
    self.active = NO; [NSCursor.arrowCursor set];
    [self.previousApplication activateWithOptions:0]; self.previousApplication = nil;
}
@end
