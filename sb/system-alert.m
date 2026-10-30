// PineBoard and SurfBoard present safety UI through CFUserNotification.
#include <TargetConditionals.h>
#if !TARGET_OS_OSX
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <errno.h>
#include <unistd.h>
#include "process.h"
#if !TARGET_OS_TV
#import <UIKit/UIKit.h>
#endif

static void EKShowSystemSafeModeAlert(NSString *markerPath)
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
    CFStringRef message = EKIsSurfBoard()
        ? CFSTR("You've entered safe mode. SurfBoard tweaks will not get injected until you respring your device. You can select Dismiss to safely remove your broken tweaks.")
        : CFSTR("You've entered safe mode. PineBoard tweaks will not get injected until you respring your device. You can select Dismiss to safely remove your broken tweaks.");
    const void *values[] = {
        CFSTR("Safe Mode"),
        message,
        CFSTR("Dismiss"), CFSTR("Exit Safe Mode")
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
    // Cancel/Dismiss preserves ElleKit's own marker. Only an explicit Exit clears it.
    if (status == 0 && (response & 3) == 1) {
        if (unlink(markerPath.fileSystemRepresentation) == 0 || errno == ENOENT) {
            exit(0);
        }
        NSLog(@"MobileSafety: failed to clear safe mode marker: %d", errno);
    }
}

void EKEnableSystemSafeModeAlert(const char *safeModePath)
{
    NSString *markerPath = [NSString stringWithUTF8String:safeModePath];
#if !TARGET_OS_TV
    // MobileSafety is loaded by the injector before UIApplication finishes launching.
    // Use UIKit's lifecycle notification instead of assuming PineBoard's private callback exists.
    __block id observer = nil;
    observer = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil queue:nil usingBlock:^(NSNotification *notification) {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        observer = nil;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            EKShowSystemSafeModeAlert(markerPath);
        });
    }];
#else
    Class pineBoard = NSClassFromString(@"PineBoard");
    SEL selector = NSSelectorFromString(@"finishSystemAppLaunch");
    Method method = class_getInstanceMethod(pineBoard, selector);
    if (!method) {
        NSLog(@"MobileSafety: PineBoard launch callback is unavailable");
        return;
    }
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(id application) {
        ((void (*)(id, SEL))original)(application, selector);
        // The service must be ready, and its main thread must remain free to render/respond.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            EKShowSystemSafeModeAlert(markerPath);
        });
    });
    class_replaceMethod(pineBoard, selector, replacement, method_getTypeEncoding(method));
#endif
}
#endif
