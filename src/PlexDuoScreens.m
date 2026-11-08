// Keep Plex from treating the Duo's second panel as an external display.
//
// iOS reports both Duo panels in UIScreen.screens (outer 466x678 and inner
// 951x669). Plex 8.45 assumes any screen besides the one it runs on is a TV
// and starts its external-screen player there; under the scene lifecycle that
// window lands on top of the real player, steals every tap and keeps the status
// bar visible. Plex only ever sees the screen its scene is on, and connect /
// disconnect notifications for other screens are not delivered to it.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static UIScreen *PLXActiveScreen(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) return ((UIWindowScene *)scene).screen;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return UIScreen.mainScreen;
#pragma clang diagnostic pop
}

static IMP PLXOrigScreens;

static NSArray<UIScreen *> *PLXScreens(id self, SEL _cmd) {
    UIScreen *active = PLXActiveScreen();
    return active ? @[ active ] : ((NSArray *(*)(id, SEL))PLXOrigScreens)(self, _cmd);
}

static IMP PLXOrigAddObserverBlock, PLXOrigAddObserverSelector;

static BOOL PLXIsScreenNotification(NSString *name) {
    return [name isEqualToString:UIScreenDidConnectNotification] || [name isEqualToString:UIScreenDidDisconnectNotification];
}

// Block observers: wrap the block so it only fires for the active screen.
static id PLXAddObserverBlock(id self, SEL _cmd, NSString *name, id object, NSOperationQueue *queue, void (^block)(NSNotification *)) {
    if (PLXIsScreenNotification(name) && block) {
        void (^original)(NSNotification *) = block;
        block = ^(NSNotification *note) {
            if (note.object == PLXActiveScreen()) original(note);
        };
    }
    return ((id (*)(id, SEL, id, id, id, id))PLXOrigAddObserverBlock)(self, _cmd, name, object, queue, block);
}

// Selector observers: drop the registration for screen connect / disconnect.
// Plex uses these only to drive its external-screen player.
static void PLXAddObserverSelector(id self, SEL _cmd, id observer, SEL selector, NSString *name, id object) {
    if (PLXIsScreenNotification(name)) return;
    ((void (*)(id, SEL, id, SEL, id, id))PLXOrigAddObserverSelector)(self, _cmd, observer, selector, name, object);
}

__attribute__((constructor)) static void PLXInstallScreenFilter(void) {
    Method screens = class_getClassMethod(UIScreen.class, @selector(screens));
    PLXOrigScreens = method_setImplementation(screens, (IMP)PLXScreens);
    Method block = class_getInstanceMethod(NSNotificationCenter.class, @selector(addObserverForName:object:queue:usingBlock:));
    PLXOrigAddObserverBlock = method_setImplementation(block, (IMP)PLXAddObserverBlock);
    Method selector = class_getInstanceMethod(NSNotificationCenter.class, @selector(addObserver:selector:name:object:));
    PLXOrigAddObserverSelector = method_setImplementation(selector, (IMP)PLXAddObserverSelector);
}
