#import <Cocoa/Cocoa.h>

@class XTSelectionView;
@protocol XTSelectionViewDelegate <NSObject>
- (void)selectionViewDidBegin:(XTSelectionView *)view;
- (void)selectionView:(XTSelectionView *)view didFinishWithAction:(NSString *)action;
- (void)selectionViewDidCancel:(XTSelectionView *)view;
@end

@interface XTSelectionView : NSView <NSTextViewDelegate>
@property (nonatomic, weak) id<XTSelectionViewDelegate> delegate;
@property (nonatomic, strong) NSImage *snapshot;
@property (nonatomic) NSRect screenFrame;
@property (nonatomic) NSRect selection;
- (void)clearSelection;
- (NSImage *)croppedImage;
@end
