// Turn off Plex's "rate this app on the App Store" prompt.
//
// Plex asks StoreKit for a review prompt after playback. Plex Reborn is not on
// the App Store, so the prompt (which shows Plex Reborn's name) would only send
// ratings toward the real Plex app, if anywhere. Both of StoreKit's request
// calls do nothing instead.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void PLXIgnoreReviewRequest(id self, SEL _cmd) {}
static void PLXIgnoreReviewRequestInScene(id self, SEL _cmd, id scene) {}

__attribute__((constructor)) static void PLXInstallNoReviewPrompt(void) {
    void (^install)(void) = ^{
        static BOOL installed;
        Class controller = NSClassFromString(@"SKStoreReviewController");
        if (installed || !controller) return;
        installed = YES;
        Method plain = class_getClassMethod(controller, NSSelectorFromString(@"requestReview"));
        if (plain) method_setImplementation(plain, (IMP)PLXIgnoreReviewRequest);
        Method inScene = class_getClassMethod(controller, NSSelectorFromString(@"requestReviewInScene:"));
        if (inScene) method_setImplementation(inScene, (IMP)PLXIgnoreReviewRequestInScene);
    };
    install();
    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidFinishLaunchingNotification" object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { install(); }];
}
