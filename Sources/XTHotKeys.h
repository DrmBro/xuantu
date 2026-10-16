#import <Cocoa/Cocoa.h>

@interface XTHotKeys : NSObject
@property (nonatomic, copy) void (^handler)(NSUInteger index);
@property (nonatomic, readonly) NSArray<NSDictionary *> *shortcuts;
@property (nonatomic, readonly) NSArray<NSString *> *registrationErrors;
@property (nonatomic, readonly, getter=isSuspended) BOOL suspended;
- (void)start;
- (BOOL)applyShortcuts:(NSArray<NSDictionary *> *)shortcuts error:(NSString **)error;
- (void)suspend;
- (void)resume;
- (void)stop;
@end

@interface XTShortcutButton : NSButton
@property (nonatomic, copy) NSDictionary *shortcut;
@property (nonatomic, copy) void (^onRecord)(NSDictionary *shortcut);
@property (nonatomic, copy) void (^onBeginRecording)(void);
@property (nonatomic, copy) void (^onEndRecording)(void);
- (void)endRecording;
@end
