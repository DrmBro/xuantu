#import "XTSelectionView.h"
#import "XTAnnotation.h"
#import "XTWindowSelection.h"
#import "XTCommon.h"
#import <QuartzCore/QuartzCore.h>

// 编辑区域的空白部分不拦截画布点击；工具栏空白则消费点击，防止误绘制。
@interface XTEditorClipView : NSView @end
@implementation XTEditorClipView
- (NSView *)hitTest:(NSPoint)point { NSView *view = [super hitTest:point]; return view == self ? nil : view; }
@end
@interface XTAnnotationToolbar : NSView @end
@implementation XTAnnotationToolbar
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {}
- (void)rightMouseDown:(NSEvent *)event {}
@end

@interface XTMarkupTextView : NSTextView
@property (nonatomic, copy) void (^commitText)(void);
@property (nonatomic, copy) void (^saveCapture)(void);
@property (nonatomic, strong) NSUndoManager *typingUndoManager;
@end
@implementation XTMarkupTextView
- (NSUndoManager *)undoManager {
    if (!self.typingUndoManager) self.typingUndoManager = [NSUndoManager new];
    return self.typingUndoManager;
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (!self.hasMarkedText && (event.modifierFlags & NSEventModifierFlagCommand)) {
        if ((event.keyCode == 36 || event.keyCode == 76) && self.commitText) { self.commitText(); return YES; }
        if ([event.charactersIgnoringModifiers.lowercaseString isEqual:@"s"] && self.saveCapture) { self.saveCapture(); return YES; }
    }
    return [super performKeyEquivalent:event];
}
@end

@implementation XTSelectionView {
    NSPoint _anchor;
    NSRect _startRect;
    XTWindowCandidate *_hoverCandidate;
    XTWindowCandidate *_clickCandidate;
    CGWindowID _lockedWindowID;
    BOOL _startedFreeDrag;
    NSInteger _dragMode;
    BOOL _dragging;
    NSTrackingArea *_tracking;
    NSView *_toolbar;
    NSTextField *_instruction;
    NSTextField *_styleHint;
    NSMutableArray<NSButton *> *_toolButtons;
    NSMutableArray<NSButton *> *_colorButtons;
    NSArray<NSColor *> *_colors;
    NSButton *_undoButton;
    NSButton *_redoButton;
    NSButton *_deleteButton;
    NSPopUpButton *_linePopup;
    NSPopUpButton *_fontPopup;
    NSMutableArray<XTAnnotation *> *_annotations;
    NSMutableArray<NSArray<XTAnnotation *> *> *_undoStack;
    NSMutableArray<NSArray<XTAnnotation *> *> *_redoStack;
    NSInteger _tool; // 0 选择，1 矩形，2 箭头，3 文本
    NSInteger _selectedIndex;
    NSColor *_styleColor;
    CGFloat _styleWidth;
    CGFloat _styleFont;
    XTAnnotation *_pending;
    XTAnnotation *_movingOriginal;
    NSArray<XTAnnotation *> *_moveBaseline;
    BOOL _moveChanged;
    NSView *_editorClip;
    NSScrollView *_editorScroll;
    XTMarkupTextView *_textEditor;
    XTAnnotation *_editingDraft;
    NSInteger _editingIndex;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        _windowCandidates = @[];
        _annotations = [NSMutableArray array]; _undoStack = [NSMutableArray array]; _redoStack = [NSMutableArray array];
        _selectedIndex = NSNotFound; _editingIndex = NSNotFound;
        _styleWidth = 3; _styleFont = 20;
        _colors = @[[NSColor colorWithSRGBRed:0.96 green:0.23 blue:0.25 alpha:1],
                    [NSColor colorWithSRGBRed:1 green:0.76 blue:0.12 alpha:1],
                    [NSColor colorWithSRGBRed:0.15 green:0.82 blue:0.42 alpha:1],
                    [NSColor colorWithSRGBRed:0.15 green:0.56 blue:1 alpha:1], NSColor.whiteColor, NSColor.blackColor];
        _styleColor = _colors.firstObject;
        _instruction = XTLabel(@"悬停选窗口 · 单击锁定 · 拖动框选 · T 贴图 · Esc 取消", 13, NSFontWeightMedium);
        _instruction.textColor = NSColor.whiteColor; _instruction.alignment = NSTextAlignmentCenter;
        _instruction.wantsLayer = YES; _instruction.layer.backgroundColor = [NSColor colorWithWhite:0.07 alpha:0.9].CGColor;
        _instruction.layer.cornerRadius = 10; [self addSubview:_instruction];
        [self buildToolbar]; self.needsLayout = YES;
    }
    return self;
}
- (NSButton *)toolbarButton:(NSString *)title symbol:(NSString *)symbol tip:(NSString *)tip x:(CGFloat)x width:(CGFloat)width action:(SEL)action {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bordered = NO; b.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
    b.imagePosition = NSImageAbove; b.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
    b.contentTintColor = NSColor.whiteColor; b.frame = NSMakeRect(x, 42, width, 42); b.toolTip = tip;
    b.wantsLayer = YES; b.layer.cornerRadius = 6; b.refusesFirstResponder = YES;
    [_toolbar addSubview:b]; return b;
}
- (void)buildToolbar {
    _toolbar = [[XTAnnotationToolbar alloc] initWithFrame:NSMakeRect(0, 0, 600, 92)];
    _toolbar.wantsLayer = YES; _toolbar.layer.cornerRadius = 10;
    _toolbar.layer.backgroundColor = [NSColor colorWithWhite:0.12 alpha:0.98].CGColor;
    _toolbar.layer.borderColor = [NSColor colorWithWhite:1 alpha:0.14].CGColor; _toolbar.layer.borderWidth = 1;
    _toolbar.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    _toolButtons = [NSMutableArray array]; _colorButtons = [NSMutableArray array];
    NSArray *names = @[@"选择 V", @"矩形 R", @"箭头 A", @"文本 X"];
    NSArray *symbols = @[@"cursorarrow", @"rectangle", @"arrow.up.right", @"textformat"];
    NSArray *tips = @[@"选择、移动标注；拖动空白区域或边缘调整选区", @"拖动绘制矩形框", @"从起点拖向终点绘制箭头", @"点击输入文字；回车换行，⌘回车完成"];
    for (NSInteger i = 0; i < 4; i++) {
        NSButton *b = [self toolbarButton:names[i] symbol:symbols[i] tip:tips[i] x:8 + i * 46 width:44 action:@selector(toolChanged:)];
        b.tag = i; [_toolButtons addObject:b];
    }
    _undoButton = [self toolbarButton:@"撤销" symbol:@"arrow.uturn.backward" tip:@"撤销 ⌘Z" x:200 width:32 action:@selector(undo:)];
    _redoButton = [self toolbarButton:@"重做" symbol:@"arrow.uturn.forward" tip:@"重做 ⇧⌘Z" x:234 width:32 action:@selector(redo:)];
    _deleteButton = [self toolbarButton:@"删除" symbol:@"trash" tip:@"删除选中的标注 Delete" x:268 width:32 action:@selector(deleteAnnotation:)];
    [self toolbarButton:@"取消 Esc" symbol:@"xmark" tip:@"取消本次截图" x:310 width:68 action:@selector(cancelAction:)];
    [self toolbarButton:@"保存 ⌘S" symbol:@"square.and.arrow.down" tip:@"保存带标注的 PNG 图片" x:380 width:68 action:@selector(saveAction:)];
    [self toolbarButton:@"复制 ↩" symbol:@"doc.on.doc" tip:@"复制带标注的图片" x:450 width:68 action:@selector(copyAction:)];
    NSButton *pin = [self toolbarButton:@"贴图 T" symbol:@"pin.fill" tip:@"将带标注的图片悬浮贴图" x:520 width:68 action:@selector(pinAction:)];
    pin.contentTintColor = [NSColor colorWithSRGBRed:0.35 green:0.94 blue:0.75 alpha:1];
    for (NSInteger i = 0; i < (NSInteger)_colors.count; i++) {
        NSButton *b = [NSButton buttonWithTitle:@"●" target:self action:@selector(colorChanged:)];
        b.bordered = NO; b.font = [NSFont systemFontOfSize:22]; b.frame = NSMakeRect(10 + 24 * i, 7, 24, 27);
        b.attributedTitle = [[NSAttributedString alloc] initWithString:@"●" attributes:@{NSForegroundColorAttributeName:_colors[i], NSFontAttributeName:b.font}];
        b.tag = i; b.wantsLayer = YES; b.layer.cornerRadius = 5; b.refusesFirstResponder = YES;
        b.toolTip = @[@"红色", @"黄色", @"绿色", @"蓝色", @"白色", @"黑色"][i];
        [_colorButtons addObject:b]; [_toolbar addSubview:b];
    }
    NSTextField *line = XTLabel(@"线宽", 10, NSFontWeightRegular); line.textColor = NSColor.lightGrayColor; line.frame = NSMakeRect(166, 12, 32, 16); [_toolbar addSubview:line];
    _linePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(198, 7, 58, 27) pullsDown:NO];
    for (NSNumber *n in @[@1,@2,@3,@5,@8]) { [_linePopup addItemWithTitle:[NSString stringWithFormat:@"%@ pt", n]]; _linePopup.lastItem.tag = n.integerValue; }
    _linePopup.target = self; _linePopup.action = @selector(lineChanged:); [_toolbar addSubview:_linePopup];
    NSTextField *font = XTLabel(@"字号", 10, NSFontWeightRegular); font.textColor = NSColor.lightGrayColor; font.frame = NSMakeRect(267, 12, 32, 16); [_toolbar addSubview:font];
    _fontPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(299, 7, 66, 27) pullsDown:NO];
    for (NSNumber *n in @[@12,@16,@20,@24,@32,@40,@48,@64]) { [_fontPopup addItemWithTitle:[NSString stringWithFormat:@"%@ pt", n]]; _fontPopup.lastItem.tag = n.integerValue; }
    _fontPopup.target = self; _fontPopup.action = @selector(fontChanged:); [_toolbar addSubview:_fontPopup];
    _styleHint = XTLabel(@"选中标注可移动或删除", 10, NSFontWeightRegular);
    _styleHint.textColor = NSColor.lightGrayColor; _styleHint.frame = NSMakeRect(380, 10, 210, 19); [_toolbar addSubview:_styleHint];
    _toolbar.hidden = YES; [self addSubview:_toolbar]; [self refreshToolbar];
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; self.needsLayout = YES; }
- (void)layout {
    [super layout];
    CGFloat width = MIN(510, self.bounds.size.width - 24);
    _instruction.frame = NSMakeRect((self.bounds.size.width - width) / 2, self.bounds.size.height - 70, width, 34);
    [self positionToolbar];
}
- (void)positionToolbar {
    if (NSIsEmptyRect(self.selection)) return;
    CGFloat scale = MIN(1, MAX(0.4, (self.bounds.size.width - 16) / 600));
    NSSize size = NSMakeSize(600 * scale, 92 * scale);
    CGFloat x = MAX(8, MIN(NSMaxX(self.selection) - size.width, self.bounds.size.width - size.width - 8));
    CGFloat y = NSMinY(self.selection) - size.height - 10;
    if (y < 8) y = MIN(self.bounds.size.height - size.height - 8, NSMaxY(self.selection) + 10);
    _toolbar.frame = NSMakeRect(x, y, size.width, size.height); _toolbar.bounds = NSMakeRect(0, 0, 600, 92);
}
- (XTAnnotation *)selectedAnnotation {
    return _selectedIndex != NSNotFound && _selectedIndex >= 0 && _selectedIndex < (NSInteger)_annotations.count ? _annotations[_selectedIndex] : nil;
}
- (void)refreshToolbar {
    for (NSButton *b in _toolButtons) {
        b.layer.backgroundColor = b.tag == _tool ? [NSColor colorWithSRGBRed:0.08 green:0.44 blue:0.37 alpha:1].CGColor : NSColor.clearColor.CGColor;
    }
    for (NSInteger i = 0; i < (NSInteger)_colorButtons.count; i++) {
        BOOL selected = [_colors[i] isEqual:_styleColor];
        _colorButtons[i].layer.backgroundColor = selected ? [NSColor colorWithWhite:1 alpha:0.22].CGColor : NSColor.clearColor.CGColor;
        _colorButtons[i].layer.borderWidth = selected ? 1 : 0;
        _colorButtons[i].layer.borderColor = [NSColor colorWithWhite:1 alpha:0.6].CGColor;
    }
    [_linePopup selectItemWithTag:(NSInteger)_styleWidth]; [_fontPopup selectItemWithTag:(NSInteger)_styleFont];
    _undoButton.enabled = _textEditor ? _textEditor.undoManager.canUndo : _undoStack.count > 0;
    _redoButton.enabled = _textEditor ? _textEditor.undoManager.canRedo : _redoStack.count > 0;
    _deleteButton.enabled = [self selectedAnnotation] != nil;
    _styleHint.stringValue = _textEditor ? @"回车换行 · ⌘回车完成" : (_tool == 3 ? @"点击输入 · 双击文字可修改" : @"选中标注可移动或删除");
    self.needsDisplay = YES;
}
- (NSArray<XTAnnotation *> *)snapshotAnnotations { return [[NSArray alloc] initWithArray:_annotations copyItems:YES]; }
- (void)recordBefore:(NSArray<XTAnnotation *> *)before {
    [_undoStack addObject:before]; if (_undoStack.count > 100) [_undoStack removeObjectAtIndex:0];
    [_redoStack removeAllObjects];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingActiveAlways | NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (NSArray<NSValue *> *)handlePoints {
    NSRect r = self.selection;
    return @[[NSValue valueWithPoint:NSMakePoint(NSMinX(r), NSMinY(r))], [NSValue valueWithPoint:NSMakePoint(NSMidX(r), NSMinY(r))],
             [NSValue valueWithPoint:NSMakePoint(NSMaxX(r), NSMinY(r))], [NSValue valueWithPoint:NSMakePoint(NSMaxX(r), NSMidY(r))],
             [NSValue valueWithPoint:NSMakePoint(NSMaxX(r), NSMaxY(r))], [NSValue valueWithPoint:NSMakePoint(NSMidX(r), NSMaxY(r))],
             [NSValue valueWithPoint:NSMakePoint(NSMinX(r), NSMaxY(r))], [NSValue valueWithPoint:NSMakePoint(NSMinX(r), NSMidY(r))]];
}
- (NSInteger)handleAt:(NSPoint)p {
    if (NSIsEmptyRect(self.selection) || _tool != 0) return -1;
    NSArray *points = [self handlePoints];
    for (NSInteger i = 0; i < 8; i++) {
        NSPoint h = [points[i] pointValue]; if (fabs(h.x - p.x) <= 7 && fabs(h.y - p.y) <= 7) return i;
    }
    return -1;
}
- (NSInteger)annotationAt:(NSPoint)p {
    if (!NSPointInRect(p, self.selection)) return NSNotFound;
    for (NSInteger i = (NSInteger)_annotations.count - 1; i >= 0; i--) if ([_annotations[i] hitTest:p tolerance:5]) return i;
    return NSNotFound;
}
- (void)drawRect:(NSRect)dirtyRect {
    [self.snapshot drawInRect:self.bounds fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1 respectFlipped:NO hints:nil];
    NSRect shown = NSIsEmptyRect(self.selection) && _hoverCandidate ? _hoverCandidate.frame : self.selection;
    BOOL preview = NSIsEmptyRect(self.selection) && _hoverCandidate != nil;
    NSBezierPath *shade = [NSBezierPath bezierPathWithRect:self.bounds];
    if (!NSIsEmptyRect(shown)) [shade appendBezierPathWithRect:shown];
    shade.windingRule = NSWindingRuleEvenOdd; [[NSColor colorWithWhite:0 alpha:0.43] setFill]; [shade fill];
    if (NSIsEmptyRect(shown)) return;
    [NSGraphicsContext saveGraphicsState]; [NSBezierPath clipRect:shown];
    for (NSInteger i = 0; i < (NSInteger)_annotations.count; i++) if (!_textEditor || i != _editingIndex) [_annotations[i] draw];
    [_pending draw];
    XTAnnotation *selected = [self selectedAnnotation];
    if (selected && !_textEditor) {
        NSBezierPath *outline = [NSBezierPath bezierPathWithRect:NSInsetRect(selected.bounds, -4, -4)];
        CGFloat pattern[] = {4, 3}; [outline setLineDash:pattern count:2 phase:0]; outline.lineWidth = 1;
        [[NSColor colorWithSRGBRed:0.2 green:0.9 blue:0.73 alpha:1] setStroke]; [outline stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
    [[NSColor colorWithSRGBRed:0.2 green:0.9 blue:0.73 alpha:1] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:shown]; border.lineWidth = 1.5; [border stroke];
    if (!preview && !_dragging && _tool == 0) for (NSValue *v in [self handlePoints]) {
        NSPoint p = v.pointValue;
        NSBezierPath *handle = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(p.x - 3.5, p.y - 3.5, 7, 7) xRadius:1.5 yRadius:1.5];
        [NSColor.whiteColor setFill]; [handle fill]; [XTAccent() setStroke]; [handle stroke];
    }
    NSSize pixels = XTPixelSize(self.snapshot);
    NSString *size = [NSString stringWithFormat:@"%@%.0f × %.0f", preview ? @"窗口 · " : @"", shown.size.width * pixels.width / self.bounds.size.width, shown.size.height * pixels.height / self.bounds.size.height];
    NSDictionary *attributes = @{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium], NSForegroundColorAttributeName:NSColor.whiteColor};
    NSSize labelSize = [size sizeWithAttributes:attributes];
    CGFloat x = MIN(self.bounds.size.width - labelSize.width - 16, MAX(4, NSMinX(shown)));
    CGFloat y = MIN(self.bounds.size.height - 27, NSMaxY(shown) + 7);
    [[NSColor colorWithWhite:0.08 alpha:0.95] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, y, labelSize.width + 16, 24) xRadius:5 yRadius:5] fill];
    [size drawAtPoint:NSMakePoint(x + 8, y + 5) withAttributes:attributes];
}
- (NSArray<XTWindowCandidate *> *)windowHitsAt:(NSPoint)point {
    return [XTWindowSelection candidates:self.windowCandidates atLocalPoint:point];
}
- (void)setWindowCandidates:(NSArray<XTWindowCandidate *> *)windowCandidates {
    _windowCandidates = [windowCandidates copy];
    _instruction.stringValue = _windowCandidates.count ? @"悬停选窗口 · 单击锁定 · 拖动框选 · Tab 切换窗口" : @"拖动框选 · 标注后 T 贴图 · 回车复制 · Esc 取消";
}
- (void)refreshWindowHover {
    if (!self.window || _dragging || !NSIsEmptyRect(self.selection)) return;
    NSPoint global = NSEvent.mouseLocation;
    NSPoint point = [self convertPoint:[self.window convertPointFromScreen:global] fromView:nil];
    XTWindowCandidate *candidate = NSPointInRect(point, self.bounds) ? [self windowHitsAt:point].firstObject : nil;
    if (_hoverCandidate.windowID != candidate.windowID || !NSEqualRects(_hoverCandidate.frame, candidate.frame)) {
        _hoverCandidate = candidate; self.needsDisplay = YES;
    }
}
- (void)mouseExited:(NSEvent *)event {
    if (NSIsEmptyRect(self.selection)) { _hoverCandidate = nil; self.needsDisplay = YES; }
}
- (BOOL)canCycleWindows { return !_dragging && !_textEditor && _annotations.count == 0; }
- (BOOL)cycleWindowBackward:(BOOL)backward lockSelection:(BOOL)lockSelection {
    if (![self canCycleWindows]) {
        NSBeep(); _styleHint.stringValue = @"有标注时不切换窗口"; return NO;
    }
    NSPoint point = [self convertPoint:[self.window convertPointFromScreen:NSEvent.mouseLocation] fromView:nil];
    NSArray<XTWindowCandidate *> *hits = [self windowHitsAt:point];
    if (!hits.count) { NSBeep(); return NO; }
    BOOL preview = NSIsEmptyRect(self.selection) && !lockSelection;
    CGWindowID current = preview ? _hoverCandidate.windowID : _lockedWindowID;
    NSInteger index = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)hits.count; i++) if (hits[i].windowID == current) { index = i; break; }
    if (index == NSNotFound) index = backward ? (NSInteger)hits.count - 1 : 0;
    else index = (index + (backward ? -1 : 1) + (NSInteger)hits.count) % (NSInteger)hits.count;
    XTWindowCandidate *candidate = hits[index];
    if (preview) { _hoverCandidate = candidate; self.needsDisplay = YES; }
    else {
        [self.delegate selectionViewDidBegin:self];
        self.selection = candidate.frame; _lockedWindowID = candidate.windowID;
        // 更换裁剪上下文后不允许撤销恢复另一个窗口里的旧标注。
        [_undoStack removeAllObjects]; [_redoStack removeAllObjects];
        _hoverCandidate = nil; _instruction.hidden = YES; _toolbar.hidden = NO;
        _selectedIndex = NSNotFound; [self positionToolbar]; [self refreshToolbar];
    }
    [self.window makeKeyWindow]; [self.window makeFirstResponder:self];
    return YES;
}
- (void)mouseEntered:(NSEvent *)event {
    // 未锁定时让光标所在显示器接收 Tab；已有选区的键盘焦点保留至用户点击。
    if (NSIsEmptyRect(self.selection)) {
        BOOL otherLocked = NO;
        for (NSWindow *window in NSApp.windows) {
            if (window != self.window && [window.contentView isKindOfClass:XTSelectionView.class] && !NSIsEmptyRect(((XTSelectionView *)window.contentView).selection)) { otherLocked = YES; break; }
        }
        if (!otherLocked) { [self.window makeKeyWindow]; [self.window makeFirstResponder:self]; }
    }
    [self mouseMoved:event];
}
- (void)mouseMoved:(NSEvent *)event {
    [self refreshWindowHover];
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSIsEmptyRect(self.selection) && _hoverCandidate) { [NSCursor.crosshairCursor set]; return; }
    if (!_toolbar.hidden && NSPointInRect(p, _toolbar.frame)) { [NSCursor.arrowCursor set]; return; }
    if (_textEditor && NSPointInRect(p, [_editorScroll convertRect:_editorScroll.bounds toView:self])) { [NSCursor.IBeamCursor set]; return; }
    NSInteger handle = [self handleAt:p];
    if (_tool == 3 && NSPointInRect(p, self.selection)) [NSCursor.IBeamCursor set];
    else if (handle == 1 || handle == 5) [NSCursor.resizeUpDownCursor set];
    else if (handle == 3 || handle == 7) [NSCursor.resizeLeftRightCursor set];
    else if (_tool == 0 && handle < 0 && NSPointInRect(p, self.selection)) [NSCursor.openHandCursor set];
    else [NSCursor.crosshairCursor set];
}
- (NSPoint)clampedPoint:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    return NSMakePoint(MAX(0, MIN(self.bounds.size.width, p.x)), MAX(0, MIN(self.bounds.size.height, p.y)));
}
- (NSPoint)point:(NSPoint)p clampedTo:(NSRect)rect {
    return NSMakePoint(MAX(NSMinX(rect), MIN(NSMaxX(rect), p.x)), MAX(NSMinY(rect), MIN(NSMaxY(rect), p.y)));
}
- (void)selectAnnotationAt:(NSInteger)index {
    _selectedIndex = index;
    XTAnnotation *item = [self selectedAnnotation];
    if (item) { _styleColor = item.color; _styleWidth = item.lineWidth; _styleFont = item.fontSize; }
    [self refreshToolbar];
}
- (XTAnnotation *)newAnnotation:(XTAnnotationKind)kind at:(NSPoint)point {
    XTAnnotation *a = [XTAnnotation new]; a.kind = kind; a.start = point; a.end = point;
    a.color = _styleColor; a.lineWidth = _styleWidth; a.fontSize = _styleFont;
    return a;
}
- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self clampedPoint:event];
    [self commitTextEditing];
    [self.window makeKeyWindow]; [self.window makeFirstResponder:self];
    [self.delegate selectionViewDidBegin:self];
    _clickCandidate = nil; _startedFreeDrag = NO;
    if (NSIsEmptyRect(self.selection)) {
        if (_hoverCandidate && NSPointInRect(p, _hoverCandidate.frame)) _clickCandidate = _hoverCandidate;
        else _clickCandidate = [self windowHitsAt:p].firstObject;
    }
    _hoverCandidate = nil;
    _dragging = NO; _dragMode = -1; _anchor = p; _startRect = self.selection;
    _pending = nil; _movingOriginal = nil; _moveBaseline = nil; _moveChanged = NO;
    NSInteger hit = [self annotationAt:p];
    BOOL hasSelection = !NSIsEmptyRect(self.selection);
    if (hasSelection && _tool == 3) {
        if (!NSPointInRect(p, self.selection)) return;
        if (hit != NSNotFound && _annotations[hit].kind == XTAnnotationText) [self editTextAtIndex:hit point:p];
        else [self editTextAtIndex:NSNotFound point:p];
        return;
    }
    if (hasSelection && (_tool == 1 || _tool == 2)) {
        if (!NSPointInRect(p, self.selection)) return;
        _selectedIndex = NSNotFound;
        _pending = [self newAnnotation:(XTAnnotationKind)_tool at:p];
        _dragMode = 11; _dragging = YES; [self refreshToolbar]; return;
    }
    NSInteger handle = [self handleAt:p];
    if (hasSelection && hit != NSNotFound && handle < 0) {
        [self selectAnnotationAt:hit];
        if (event.clickCount == 2 && _annotations[hit].kind == XTAnnotationText) { [self editTextAtIndex:hit point:p]; return; }
        _movingOriginal = [_annotations[hit] copy]; _moveBaseline = [self snapshotAnnotations];
        _dragMode = 10; _dragging = YES; return;
    }
    if (event.clickCount == 2 && hasSelection && NSPointInRect(p, self.selection)) { [self pinAction:nil]; return; }
    _selectedIndex = NSNotFound;
    // 已标注后，选区外单击只取消选中，避免误删整段标注；选区仍可通过边缘调整。
    if (_annotations.count > 0 && handle < 0 && !NSPointInRect(p, self.selection)) { [self refreshToolbar]; return; }
    _dragMode = handle >= 0 ? handle + 2 : (hasSelection && NSPointInRect(p, self.selection) ? 1 : 0);
    _dragging = YES;
    if (_dragMode == 0) { _lockedWindowID = kCGNullWindowID; self.selection = NSZeroRect; [_annotations removeAllObjects]; [_undoStack removeAllObjects]; [_redoStack removeAllObjects]; _tool = 0; }
    _toolbar.hidden = YES; _instruction.hidden = YES; [self refreshToolbar];
}
- (NSSize)clampedTranslation:(NSSize)delta forItem:(XTAnnotation *)item {
    NSRect b = item.bounds, s = self.selection;
    CGFloat minX = NSMinX(s) - NSMinX(b), maxX = NSMaxX(s) - NSMaxX(b);
    CGFloat minY = NSMinY(s) - NSMinY(b), maxY = NSMaxY(s) - NSMaxY(b);
    if (b.size.width > s.size.width) { minX = NSMinX(s) - NSMaxX(b) + 8; maxX = NSMaxX(s) - NSMinX(b) - 8; }
    if (b.size.height > s.size.height) { minY = NSMinY(s) - NSMaxY(b) + 8; maxY = NSMaxY(s) - NSMinY(b) - 8; }
    // 裁剪选区后标注可以部分位于选区外；零位移必须保持不动，不能在单击时自动吸回边界。
    minX = MIN(0, minX); maxX = MAX(0, maxX);
    minY = MIN(0, minY); maxY = MAX(0, maxY);
    return NSMakeSize(MAX(minX, MIN(maxX, delta.width)), MAX(minY, MIN(maxY, delta.height)));
}
- (void)mouseDragged:(NSEvent *)event {
    if (!_dragging) return;
    NSPoint p = [self clampedPoint:event];
    if (_dragMode == 11) {
        _pending.end = [self point:p clampedTo:self.selection]; self.needsDisplay = YES; return;
    }
    if (_dragMode == 10 && _movingOriginal && [self selectedAnnotation]) {
        NSSize delta = [self clampedTranslation:NSMakeSize(p.x - _anchor.x, p.y - _anchor.y) forItem:_movingOriginal];
        _moveChanged = fabs(delta.width) > 0.01 || fabs(delta.height) > 0.01;
        XTAnnotation *moved = [_movingOriginal copy]; [moved moveBy:delta]; _annotations[_selectedIndex] = moved;
        self.needsDisplay = YES; return;
    }
    if (_dragMode == 0) {
        NSPoint raw = [self convertPoint:event.locationInWindow fromView:nil];
        if (hypot(raw.x - _anchor.x, raw.y - _anchor.y) >= 4) _startedFreeDrag = YES;
        if (!_startedFreeDrag) return;
        _clickCandidate = nil;
        self.selection = NSMakeRect(MIN(p.x, _anchor.x), MIN(p.y, _anchor.y), fabs(p.x - _anchor.x), fabs(p.y - _anchor.y));
    } else if (_dragMode == 1) {
        NSRect r = _startRect;
        r.origin.x = MAX(0, MIN(self.bounds.size.width - r.size.width, r.origin.x + p.x - _anchor.x));
        r.origin.y = MAX(0, MIN(self.bounds.size.height - r.size.height, r.origin.y + p.y - _anchor.y));
        self.selection = r;
    } else if (_dragMode >= 2 && _dragMode <= 9) {
        NSInteger h = _dragMode - 2;
        CGFloat x1 = NSMinX(_startRect), x2 = NSMaxX(_startRect), y1 = NSMinY(_startRect), y2 = NSMaxY(_startRect);
        if (h == 0 || h == 6 || h == 7) x1 = MIN(p.x, x2 - 3);
        if (h == 2 || h == 3 || h == 4) x2 = MAX(p.x, x1 + 3);
        if (h == 0 || h == 1 || h == 2) y1 = MIN(p.y, y2 - 3);
        if (h == 4 || h == 5 || h == 6) y2 = MAX(p.y, y1 + 3);
        self.selection = NSIntersectionRect(self.bounds, NSMakeRect(x1, y1, x2 - x1, y2 - y1));
    }
    self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent *)event {
    if (!_dragging) return;
    [self mouseDragged:event]; _dragging = NO;
    if (_dragMode == 11) {
        CGFloat dx = fabs(_pending.end.x - _pending.start.x), dy = fabs(_pending.end.y - _pending.start.y);
        BOOL valid = _pending.kind == XTAnnotationRectangle ? dx >= 2 && dy >= 2 : hypot(dx, dy) >= 3;
        if (valid) { [self recordBefore:[self snapshotAnnotations]]; [_annotations addObject:_pending]; _selectedIndex = _annotations.count - 1; }
        _pending = nil; [self refreshToolbar]; return;
    }
    if (_dragMode == 10) {
        if (_moveChanged) [self recordBefore:_moveBaseline];
        _movingOriginal = nil; _moveBaseline = nil; [self refreshToolbar]; return;
    }
    if (_dragMode == 0 && !_startedFreeDrag && _clickCandidate) {
        self.selection = _clickCandidate.frame; _lockedWindowID = _clickCandidate.windowID;
    }
    _clickCandidate = nil;
    if (self.selection.size.width < 3 || self.selection.size.height < 3) { [self clearSelection]; return; }
    if (_dragMode == 0 && [[NSUserDefaults standardUserDefaults] boolForKey:@"autoPin"]) { [self pinAction:nil]; return; }
    [self positionToolbar]; _toolbar.hidden = NO; [self refreshToolbar];
}
- (void)rightMouseDown:(NSEvent *)event {
    if (_textEditor) [self cancelTextEditing];
    else [self.delegate selectionViewDidCancel:self];
}
- (void)clearSelection {
    [self cancelTextEditing];
    self.selection = NSZeroRect; _hoverCandidate = nil; _clickCandidate = nil; _lockedWindowID = kCGNullWindowID;
    _toolbar.hidden = YES; _instruction.hidden = NO; _dragging = NO;
    _pending = nil; _selectedIndex = NSNotFound; _tool = 0;
    [_annotations removeAllObjects]; [_undoStack removeAllObjects]; [_redoStack removeAllObjects]; [self refreshToolbar];
}
- (void)toolChanged:(NSButton *)button { [self chooseTool:button.tag]; }
- (void)chooseTool:(NSInteger)tool {
    [self commitTextEditing]; _tool = tool; _selectedIndex = NSNotFound;
    [self.window makeFirstResponder:self]; [self refreshToolbar];
}
- (void)colorChanged:(NSButton *)button {
    [self commitTextEditing]; _styleColor = _colors[button.tag];
    XTAnnotation *a = [self selectedAnnotation];
    if (a && ![a.color isEqual:_styleColor]) { [self recordBefore:[self snapshotAnnotations]]; a.color = _styleColor; }
    [self refreshToolbar]; [self.window makeFirstResponder:self];
}
- (void)lineChanged:(NSPopUpButton *)button {
    CGFloat chosen = button.selectedItem.tag;
    [self commitTextEditing]; _styleWidth = chosen;
    XTAnnotation *a = [self selectedAnnotation];
    if (a && a.kind != XTAnnotationText && a.lineWidth != _styleWidth) { [self recordBefore:[self snapshotAnnotations]]; a.lineWidth = _styleWidth; }
    [self refreshToolbar]; [self.window makeFirstResponder:self];
}
- (void)fontChanged:(NSPopUpButton *)button {
    CGFloat chosen = button.selectedItem.tag;
    [self commitTextEditing]; _styleFont = chosen;
    XTAnnotation *a = [self selectedAnnotation];
    if (a && a.kind == XTAnnotationText && a.fontSize != _styleFont) { [self recordBefore:[self snapshotAnnotations]]; a.fontSize = _styleFont; }
    [self refreshToolbar]; [self.window makeFirstResponder:self];
}
- (void)undo:(id)sender {
    if (_textEditor) { if (_textEditor.undoManager.canUndo) [_textEditor.undoManager undo]; [self refreshToolbar]; return; }
    if (!_undoStack.count) return;
    [_redoStack addObject:[self snapshotAnnotations]];
    _annotations = [[NSMutableArray alloc] initWithArray:_undoStack.lastObject copyItems:YES];
    [_undoStack removeLastObject]; _selectedIndex = NSNotFound; [self refreshToolbar];
}
- (void)redo:(id)sender {
    if (_textEditor) { if (_textEditor.undoManager.canRedo) [_textEditor.undoManager redo]; [self refreshToolbar]; return; }
    if (!_redoStack.count) return;
    [_undoStack addObject:[self snapshotAnnotations]];
    _annotations = [[NSMutableArray alloc] initWithArray:_redoStack.lastObject copyItems:YES];
    [_redoStack removeLastObject]; _selectedIndex = NSNotFound; [self refreshToolbar];
}
- (void)deleteAnnotation:(id)sender {
    [self commitTextEditing];
    if (![self selectedAnnotation]) return;
    [self recordBefore:[self snapshotAnnotations]]; [_annotations removeObjectAtIndex:_selectedIndex];
    _selectedIndex = NSNotFound; [self refreshToolbar]; [self.window makeFirstResponder:self];
}
- (void)editTextAtIndex:(NSInteger)index point:(NSPoint)point {
    [self commitTextEditing];
    if (self.selection.size.width < 24 || self.selection.size.height < 18) { NSBeep(); _styleHint.stringValue = @"请先扩大选区再添加文字"; return; }
    _editingIndex = index;
    if (index != NSNotFound) _editingDraft = [_annotations[index] copy];
    else {
        point.x = MAX(NSMinX(self.selection), MIN(point.x, NSMaxX(self.selection) - MIN(80, self.selection.size.width)));
        point.y = MAX(NSMinY(self.selection) + MIN(_styleFont * 1.3, self.selection.size.height), MIN(point.y, NSMaxY(self.selection)));
        _editingDraft = [self newAnnotation:XTAnnotationText at:point];
        _editingDraft.textWidth = MAX(16, MIN(320, NSMaxX(self.selection) - point.x));
    }
    _selectedIndex = index;
    _editorClip = [[XTEditorClipView alloc] initWithFrame:self.selection];
    _editorClip.wantsLayer = YES; _editorClip.layer.masksToBounds = YES;
    [self addSubview:_editorClip positioned:NSWindowBelow relativeTo:_toolbar];
    _editorScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _editorScroll.borderType = NSNoBorder; _editorScroll.drawsBackground = YES;
    _editorScroll.backgroundColor = [NSColor colorWithWhite:1 alpha:0.92];
    _editorScroll.hasVerticalScroller = YES; _editorScroll.autohidesScrollers = YES;
    _editorScroll.hasHorizontalScroller = NO; _editorScroll.scrollerStyle = NSScrollerStyleOverlay;
    _editorScroll.wantsLayer = YES; _editorScroll.layer.cornerRadius = 3;
    _editorScroll.layer.borderWidth = 1; _editorScroll.layer.borderColor = XTAccent().CGColor;
    [_editorClip addSubview:_editorScroll];
    CGFloat width = _editingDraft.textWidth + 8;
    _textEditor = [[XTMarkupTextView alloc] initWithFrame:NSMakeRect(0, 0, width, _editingDraft.fontSize * 1.4 + 8)];
    _textEditor.delegate = self; _textEditor.richText = NO; _textEditor.importsGraphics = NO;
    _textEditor.allowsUndo = YES; _textEditor.drawsBackground = NO;
    _textEditor.horizontallyResizable = NO; _textEditor.verticallyResizable = YES;
    _textEditor.minSize = NSMakeSize(width, 0); _textEditor.maxSize = NSMakeSize(width, CGFLOAT_MAX);
    _textEditor.autoresizingMask = NSViewWidthSizable;
    _textEditor.textContainerInset = NSMakeSize(4, 4);
    _textEditor.textContainer.lineFragmentPadding = 0;
    _textEditor.textContainer.widthTracksTextView = YES; _textEditor.textContainer.heightTracksTextView = NO;
    _textEditor.textContainer.containerSize = NSMakeSize(_editingDraft.textWidth, CGFLOAT_MAX);
    _textEditor.layoutManager.usesFontLeading = YES;
    _textEditor.font = [NSFont systemFontOfSize:_editingDraft.fontSize];
    _textEditor.textColor = _editingDraft.color; _textEditor.insertionPointColor = NSColor.blackColor;
    _textEditor.automaticQuoteSubstitutionEnabled = NO; _textEditor.automaticDashSubstitutionEnabled = NO;
    _textEditor.automaticSpellingCorrectionEnabled = NO;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new]; paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    _textEditor.defaultParagraphStyle = paragraph;
    NSDictionary *attributes = @{NSFontAttributeName:_textEditor.font, NSForegroundColorAttributeName:_editingDraft.color, NSParagraphStyleAttributeName:paragraph};
    [_textEditor.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:_editingDraft.text attributes:attributes]];
    _textEditor.typingAttributes = attributes;
    [_textEditor.undoManager removeAllActions];
    __weak XTSelectionView *weakSelf = self;
    _textEditor.commitText = ^{ [weakSelf commitTextEditing]; };
    _textEditor.saveCapture = ^{ [weakSelf saveAction:nil]; };
    _editorScroll.documentView = _textEditor;
    [self sizeTextEditor]; [self.window makeFirstResponder:_textEditor];
    [_textEditor setSelectedRange:NSMakeRange(_textEditor.string.length, 0)];
    [_textEditor scrollRangeToVisible:_textEditor.selectedRange]; [self refreshToolbar];
}
- (void)sizeTextEditor {
    if (!_textEditor) return;
    [_textEditor.layoutManager ensureLayoutForTextContainer:_textEditor.textContainer];
    CGFloat height = NSMaxY([_textEditor.layoutManager usedRectForTextContainer:_textEditor.textContainer]);
    if (_textEditor.layoutManager.extraLineFragmentTextContainer == _textEditor.textContainer)
        height = MAX(height, NSMaxY(_textEditor.layoutManager.extraLineFragmentRect));
    height = MAX(height, [_textEditor.layoutManager defaultLineHeightForFont:_textEditor.font]);
    CGFloat documentHeight = ceil(height) + 8;
    CGFloat visibleHeight = MIN(documentHeight, MAX(18, _editingDraft.start.y - NSMinY(self.selection) + 4));
    _editorScroll.frame = NSMakeRect(_editingDraft.start.x - NSMinX(self.selection) - 4,
                                     _editingDraft.start.y - NSMinY(self.selection) + 4 - visibleHeight,
                                     _editingDraft.textWidth + 8, visibleHeight);
    [_textEditor setFrameSize:NSMakeSize(_editingDraft.textWidth + 8, documentHeight)];
}
- (void)textDidChange:(NSNotification *)notification { [self sizeTextEditor]; [self refreshToolbar]; }
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if (command == @selector(cancelOperation:) && !textView.hasMarkedText) { [self cancelTextEditing]; return YES; }
    return NO;
}
- (void)removeTextEditor {
    _textEditor.delegate = nil;
    [_editorClip removeFromSuperview];
    _textEditor = nil; _editorScroll = nil; _editorClip = nil; _editingDraft = nil; _editingIndex = NSNotFound;
    [self.window makeFirstResponder:self];
}
- (void)commitTextEditing {
    if (!_textEditor) return;
    // 先结束原生输入会话再读取最终文本，避免拼音组合态泄漏到截图快捷键。
    [_textEditor unmarkText];
    [self.window makeFirstResponder:self];
    NSString *text = [_textEditor.string copy];
    BOOL hasText = [[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] > 0;
    if (hasText) {
        _editingDraft.text = text;
        if (_editingIndex == NSNotFound) {
            [self recordBefore:[self snapshotAnnotations]];
            [_annotations addObject:[_editingDraft copy]]; _selectedIndex = _annotations.count - 1;
        } else if (![_annotations[_editingIndex].text isEqual:text]) {
            [self recordBefore:[self snapshotAnnotations]];
            _annotations[_editingIndex] = [_editingDraft copy]; _selectedIndex = _editingIndex;
        }
    } else if (_editingIndex != NSNotFound) {
        [self recordBefore:[self snapshotAnnotations]]; [_annotations removeObjectAtIndex:_editingIndex]; _selectedIndex = NSNotFound;
    }
    [self removeTextEditor]; [self refreshToolbar];
}
- (void)cancelTextEditing {
    if (!_textEditor) return;
    _selectedIndex = _editingIndex;
    [_textEditor unmarkText]; [self removeTextEditor]; [self refreshToolbar];
}
- (void)keyDown:(NSEvent *)event {
    if (_textEditor) return;
    NSString *key = event.charactersIgnoringModifiers.lowercaseString;
    BOOL command = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    if (event.keyCode == 53) { [self.delegate selectionViewDidCancel:self]; return; }
    if (!command && event.keyCode == 48) { [self.delegate selectionView:self cycleWindowBackward:(event.modifierFlags & NSEventModifierFlagShift) != 0]; return; }
    if (NSIsEmptyRect(self.selection)) { NSBeep(); return; }
    if (command && [key isEqual:@"z"]) {
        if (event.modifierFlags & NSEventModifierFlagShift) [self redo:nil]; else [self undo:nil];
    } else if (command && [key isEqual:@"s"]) [self saveAction:nil];
    else if (command && [key isEqual:@"c"]) [self copyAction:nil];
    else if (command && [key isEqual:@"y"]) [self redo:nil];
    else if (!command && [key isEqual:@"v"]) [self chooseTool:0];
    else if (!command && [key isEqual:@"r"]) [self chooseTool:1];
    else if (!command && [key isEqual:@"a"]) [self chooseTool:2];
    else if (!command && [key isEqual:@"x"]) [self chooseTool:3];
    else if (!command && [key isEqual:@"t"]) [self pinAction:nil];
    else if (event.keyCode == 36 || event.keyCode == 76) [self copyAction:nil];
    else if (event.keyCode == 51 || event.keyCode == 117) [self deleteAnnotation:nil];
    else if (event.keyCode >= 123 && event.keyCode <= 126) {
        CGFloat step = (event.modifierFlags & NSEventModifierFlagShift) ? 10 : 1;
        NSSize delta = NSMakeSize(event.keyCode == 123 ? -step : (event.keyCode == 124 ? step : 0),
                                 event.keyCode == 125 ? -step : (event.keyCode == 126 ? step : 0));
        XTAnnotation *selected = [self selectedAnnotation];
        if (selected) {
            delta = [self clampedTranslation:delta forItem:selected];
            if (fabs(delta.width) > 0.01 || fabs(delta.height) > 0.01) { [self recordBefore:[self snapshotAnnotations]]; [selected moveBy:delta]; }
        } else {
            NSRect r = self.selection;
            r.origin.x = MAX(0, MIN(self.bounds.size.width - r.size.width, r.origin.x + delta.width));
            r.origin.y = MAX(0, MIN(self.bounds.size.height - r.size.height, r.origin.y + delta.height));
            self.selection = r; [self positionToolbar];
        }
        [self refreshToolbar];
    } else [super keyDown:event];
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (_textEditor) return [super performKeyEquivalent:event];
    if ((event.modifierFlags & NSEventModifierFlagCommand) && [@[@"c", @"s", @"z", @"y"] containsObject:event.charactersIgnoringModifiers.lowercaseString]) { [self keyDown:event]; return YES; }
    return [super performKeyEquivalent:event];
}
- (NSImage *)croppedImage {
    [self commitTextEditing];
    return XTCompositeCapture(self.snapshot, self.bounds.size, self.selection, _annotations);
}
- (void)cancelAction:(id)sender { [self.delegate selectionViewDidCancel:self]; }
- (void)saveAction:(id)sender { [self commitTextEditing]; [self.delegate selectionView:self didFinishWithAction:@"save"]; }
- (void)copy:(id)sender { [self copyAction:sender]; }
- (void)copyAction:(id)sender { [self commitTextEditing]; [self.delegate selectionView:self didFinishWithAction:@"copy"]; }
- (void)pinAction:(id)sender { [self commitTextEditing]; [self.delegate selectionView:self didFinishWithAction:@"pin"]; }
@end
