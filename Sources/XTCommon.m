#import "XTCommon.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Carbon/Carbon.h>

NSString * const XTDefaultsDidChange = @"XTDefaultsDidChange";

void XTRegisterDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"doubleClickCloses": @YES, @"roundedPins": @YES,
        @"autoPin": @NO, @"excludePins": @NO,
        @"defaultOpacity": @1.0,
        @"shortcuts": @[@{@"key": @0, @"mods": @(NSEventModifierFlagCommand | NSEventModifierFlagOption)},
                         @{@"key": @1, @"mods": @(NSEventModifierFlagCommand | NSEventModifierFlagOption)},
                         @{@"key": @4, @"mods": @(NSEventModifierFlagCommand | NSEventModifierFlagOption)}]
    }];
}
NSColor *XTAccent(void) { return [NSColor colorWithSRGBRed:0.06 green:0.57 blue:0.50 alpha:1]; }
NSTextField *XTLabel(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    return label;
}
NSButton *XTSymbolButton(NSString *symbol, NSString *tip, id target, SEL action) {
    NSButton *b = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip]
                                  target:target action:action];
    b.bordered = NO; b.toolTip = tip; b.contentTintColor = NSColor.labelColor;
    b.imageScaling = NSImageScaleProportionallyDown;
    b.accessibilityLabel = tip;
    return b;
}
void XTAlert(NSString *title, NSString *message) {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *a = [NSAlert new]; a.messageText = title; a.informativeText = message;
    [a addButtonWithTitle:@"好"]; [a runModal];
}
NSSize XTPixelSize(NSImage *image) {
    CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
    return cg ? NSMakeSize(CGImageGetWidth(cg), CGImageGetHeight(cg)) : image.size;
}
void XTCopyImage(NSImage *image) {
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents]; [pb writeObjects:@[image]];
}
void XTSaveImage(NSImage *image, void (^completion)(BOOL)) {
    [NSApp activateIgnoringOtherApps:YES];
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypePNG]; panel.canCreateDirectories = YES;
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyyMMdd-HHmmss";
    panel.nameFieldStringValue = [NSString stringWithFormat:@"悬图-%@.png", [f stringFromDate:NSDate.date]];
    [panel beginWithCompletionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !panel.URL) { if (completion) completion(NO); return; }
        CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
        NSBitmapImageRep *rep = cg ? [[NSBitmapImageRep alloc] initWithCGImage:cg] : nil;
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSError *error = nil;
        BOOL saved = png && [png writeToURL:panel.URL options:NSDataWritingAtomic error:&error];
        if (!saved) XTAlert(@"图片未保存", error.localizedDescription ?: @"无法编码图片，请换一个保存位置后重试。");
        if (completion) completion(saved);
    }];
}
NSString *XTShortcutTitle(NSDictionary *shortcut) {
    NSUInteger mods = [shortcut[@"mods"] unsignedIntegerValue];
    NSDictionary *names = @{@0:@"A", @1:@"S", @2:@"D", @3:@"F", @4:@"H", @5:@"G", @6:@"Z", @7:@"X", @8:@"C", @9:@"V", @11:@"B", @12:@"Q", @13:@"W", @14:@"E", @15:@"R", @16:@"Y", @17:@"T", @18:@"1", @19:@"2", @20:@"3", @21:@"4", @22:@"6", @23:@"5", @24:@"=", @25:@"9", @26:@"7", @27:@"−", @28:@"8", @29:@"0", @30:@"]", @31:@"O", @32:@"U", @33:@"[", @34:@"I", @35:@"P", @37:@"L", @38:@"J", @39:@"'", @40:@"K", @41:@";", @42:@"\\", @43:@",", @44:@"/", @45:@"N", @46:@"M", @47:@".", @49:@"空格", @50:@"`", @96:@"F5", @97:@"F6", @98:@"F7", @99:@"F3", @100:@"F8", @101:@"F9", @103:@"F11", @109:@"F10", @111:@"F12", @118:@"F4", @120:@"F2", @122:@"F1", @123:@"←", @124:@"→", @125:@"↓", @126:@"↑"};
    NSMutableString *s = [NSMutableString string];
    if (mods & NSEventModifierFlagControl) [s appendString:@"⌃"];
    if (mods & NSEventModifierFlagOption) [s appendString:@"⌥"];
    if (mods & NSEventModifierFlagShift) [s appendString:@"⇧"];
    if (mods & NSEventModifierFlagCommand) [s appendString:@"⌘"];
    [s appendString:names[shortcut[@"key"]] ?: [NSString stringWithFormat:@"键%@", shortcut[@"key"]]];
    return s;
}
