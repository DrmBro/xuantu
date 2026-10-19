#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
// 系统窗口列表顺序为前到后。只保存 ID 和矩形，不保存标题或用户数据。
@interface XTWindowCandidate : NSObject
@property (nonatomic, readonly) CGWindowID windowID;
@property (nonatomic, readonly) NSRect frame;
- (instancetype)initWithWindowID:(CGWindowID)windowID frame:(NSRect)frame;
@end

@interface XTWindowSelection : NSObject
+ (NSArray<XTWindowCandidate *> *)captureCandidatesForShareableIDs:(NSSet<NSNumber *> *)shareableIDs
                                                   excludedIDs:(NSSet<NSNumber *> *)excludedIDs
                                              allowedOwnPinIDs:(NSSet<NSNumber *> *)pinIDs;
+ (NSArray<XTWindowCandidate *> *)candidates:(NSArray<XTWindowCandidate *> *)candidates
                             forScreenFrame:(NSRect)screenFrame;
+ (NSArray<XTWindowCandidate *> *)candidates:(NSArray<XTWindowCandidate *> *)candidates
                              atLocalPoint:(NSPoint)point;
@end
NS_ASSUME_NONNULL_END
