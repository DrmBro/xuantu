#import <Cocoa/Cocoa.h>
#import "XTAppDelegate.h"
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        __attribute__((objc_precise_lifetime)) XTAppDelegate *delegate = [XTAppDelegate new];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
