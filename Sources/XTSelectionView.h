#import <Cocoa/Cocoa.h>

@class XTSelectionView, XTWindowCandidate;
@protocol XTSelectionViewDelegate <NSObject>
- (void)selectionViewDidBegin:(XTSelectionView *)view;
- (void)selectionView:(XTSelectionView *)view didFinishWithAction:(NSString *)action;
- (void)selectionViewDidCancel:(XTSelectionView *)view;
- (void)selectionView:(XTSelectionView *)view cycleWindowBackward:(BOOL)backward;
@end

@interface XTSelectionView : NSView <NSTextViewDelegate>
@property (nonatomic, weak) id<XTSelectionViewDelegate> delegate;
@property (nonatomic, strong) NSImage *snapshot;
@property (nonatomic) NSRect screenFrame;
@property (nonatomic) NSRect selection;
@property (nonatomic, copy) NSArray<XTWindowCandidate *> *windowCandidates;
- (void)refreshWindowHover;
- (BOOL)canCycleWindows;
- (BOOL)cycleWindowBackward:(BOOL)backward lockSelection:(BOOL)lockSelection;
- (void)clearSelection;
- (NSImage *)croppedImage;
@end
