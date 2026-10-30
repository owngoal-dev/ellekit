// tvOS safety UI is presented by PineBoard's CFUserNotification service.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <errno.h>
#include <unistd.h>

static void EKShowTVSafeModeAlert(NSString *markerPath)
{
    CFUserNotificationRef (*create)(CFAllocatorRef, CFTimeInterval, CFOptionFlags, SInt32 *, CFDictionaryRef) = dlsym(RTLD_DEFAULT, "CFUserNotificationCreate");
    SInt32 (*receive)(CFUserNotificationRef, CFTimeInterval, CFOptionFlags *) = dlsym(RTLD_DEFAULT, "CFUserNotificationReceiveResponse");
    if (!create || !receive) {
        NSLog(@"MobileSafety: CFUserNotification is unavailable");
        return;
    }
    const char *names[] = {"kCFUserNotificationAlertHeaderKey", "kCFUserNotificationAlertMessageKey", "kCFUserNotificationDefaultButtonTitleKey", "kCFUserNotificationAlternateButtonTitleKey"};
    const void *keys[4];
    for (unsigned i = 0; i < 4; i++) {
        CFStringRef *key = dlsym(RTLD_DEFAULT, names[i]);
        if (!key) return;
        keys[i] = *key;
    }
    const void *values[] = {
        CFSTR("Safe Mode"),
        CFSTR("PineBoard crashed. App tweaks are disabled. Remove the faulty tweak before exiting safe mode."),
        CFSTR("Keep Safe Mode"), CFSTR("Exit Safe Mode")
    };
    CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    SInt32 error = 0;
    CFUserNotificationRef notification = create(NULL, 0, 3, &error, options);
    CFRelease(options);
    if (!notification) {
        NSLog(@"MobileSafety: notification creation failed: %d", error);
        return;
    }
    CFOptionFlags response = 0;
    SInt32 status = receive(notification, 0, &response);
    CFRelease(notification);
    // Cancel/Keep preserves ElleKit's own marker. Only an explicit Exit clears it.
    if (status == 0 && (response & 3) == 1) {
        if (unlink(markerPath.fileSystemRepresentation) == 0 || errno == ENOENT) {
            exit(0);
        }
        NSLog(@"MobileSafety: failed to clear safe mode marker: %d", errno);
    }
}

void EKEnableTVSafeModeAlert(const char *safeModePath)
{
    Class pineBoard = NSClassFromString(@"PineBoard");
    SEL selector = NSSelectorFromString(@"finishSystemAppLaunch");
    Method method = class_getInstanceMethod(pineBoard, selector);
    if (!method) {
        NSLog(@"MobileSafety: PineBoard launch callback is unavailable");
        return;
    }
    NSString *markerPath = [NSString stringWithUTF8String:safeModePath];
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(id application) {
        ((void (*)(id, SEL))original)(application, selector);
        // The service must be ready, and its main thread must remain free to render/respond.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            EKShowTVSafeModeAlert(markerPath);
        });
    });
    class_replaceMethod(pineBoard, selector, replacement, method_getTypeEncoding(method));
}
