// Scene adapter for Plex 8.45 re-stamped with the iOS 27.1 SDK.
//
// iOS 27-SDK apps must use the UIScene lifecycle or UIKit traps at launch.
// Plex 8.45 creates its UIWindow in the app delegate and never adopts scenes,
// so this delegate (named in Info.plist's UIApplicationSceneManifest) attaches
// that existing window to the scene and forwards the scene lifecycle back to
// the app-level callbacks Plex still implements, since UIKit stops calling
// them once a scene manifest exists.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Plex creates more windows after launch (the main UI after sign-in, alerts,
// the video player). Under the scene lifecycle a window with no windowScene is
// never shown, so every window Plex makes is attached to the connected scene.
static __weak UIWindowScene *PLXConnectedScene;
static NSHashTable<UIWindow *> *PLXPendingWindows;

static void PLXAttachWindow(UIWindow *window) {
    if (!window || window.windowScene) return;
    UIWindowScene *scene = PLXConnectedScene;
    if (scene) {
        window.windowScene = scene;
    } else {
        // The scene is not connected yet; remember the window until it is.
        [PLXPendingWindows addObject:window];
    }
}

static IMP PLXOriginalInitWithFrame;
static IMP PLXOriginalMakeKeyAndVisible;
static IMP PLXOriginalSetHidden;

static id PLXInitWithFrame(UIWindow *self, SEL _cmd, CGRect frame) {
    self = ((id (*)(id, SEL, CGRect))PLXOriginalInitWithFrame)(self, _cmd, frame);
    PLXAttachWindow(self);
    return self;
}

static void PLXMakeKeyAndVisible(UIWindow *self, SEL _cmd) {
    PLXAttachWindow(self);
    ((void (*)(id, SEL))PLXOriginalMakeKeyAndVisible)(self, _cmd);
}

static void PLXSetHidden(UIWindow *self, SEL _cmd, BOOL hidden) {
    if (!hidden) PLXAttachWindow(self);
    ((void (*)(id, SEL, BOOL))PLXOriginalSetHidden)(self, _cmd, hidden);
}

__attribute__((constructor)) static void PLXInstallWindowHooks(void) {
    PLXPendingWindows = [NSHashTable weakObjectsHashTable];
    Class cls = [UIWindow class];
    PLXOriginalInitWithFrame = method_setImplementation(class_getInstanceMethod(cls, @selector(initWithFrame:)), (IMP)PLXInitWithFrame);
    PLXOriginalMakeKeyAndVisible = method_setImplementation(class_getInstanceMethod(cls, @selector(makeKeyAndVisible)), (IMP)PLXMakeKeyAndVisible);
    PLXOriginalSetHidden = method_setImplementation(class_getInstanceMethod(cls, @selector(setHidden:)), (IMP)PLXSetHidden);
}

@interface PLXSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation PLXSceneDelegate

static id<UIApplicationDelegate> PLXAppDelegate(void) {
    return UIApplication.sharedApplication.delegate;
}

static UIWindow *PLXFindAppWindow(void) {
    id<UIApplicationDelegate> delegate = PLXAppDelegate();
    if ([delegate respondsToSelector:@selector(window)]) {
        UIWindow *window = [delegate window];
        if (window) return window;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        return window;
    }
#pragma clang diagnostic pop
    return nil;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    PLXConnectedScene = windowScene;
    for (UIWindow *pending in PLXPendingWindows.allObjects) {
        if (!pending.windowScene) pending.windowScene = windowScene;
    }
    [PLXPendingWindows removeAllObjects];

    UIWindow *window = PLXFindAppWindow();
    if (!window) {
        // Plex had not built its window yet; give it one so the scene shows something.
        window = [[UIWindow alloc] initWithWindowScene:windowScene];
        id<UIApplicationDelegate> delegate = PLXAppDelegate();
        if ([delegate respondsToSelector:@selector(setWindow:)]) [delegate setWindow:window];
    }
    window.windowScene = windowScene;
    window.frame = windowScene.coordinateSpace.bounds;
    self.window = window;
    [window makeKeyAndVisible];

    // Links that launched the app arrive here instead of application:openURL:.
    if (connectionOptions.URLContexts.count > 0) {
        [self scene:scene openURLContexts:connectionOptions.URLContexts];
    }
    for (NSUserActivity *activity in connectionOptions.userActivities) {
        [self scene:scene continueUserActivity:activity];
    }
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    id delegate = PLXAppDelegate();
    if ([delegate respondsToSelector:@selector(applicationDidBecomeActive:)]) [delegate applicationDidBecomeActive:UIApplication.sharedApplication];
}

- (void)sceneWillResignActive:(UIScene *)scene {
    id delegate = PLXAppDelegate();
    if ([delegate respondsToSelector:@selector(applicationWillResignActive:)]) [delegate applicationWillResignActive:UIApplication.sharedApplication];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    id delegate = PLXAppDelegate();
    if ([delegate respondsToSelector:@selector(applicationWillEnterForeground:)]) [delegate applicationWillEnterForeground:UIApplication.sharedApplication];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    id delegate = PLXAppDelegate();
    if ([delegate respondsToSelector:@selector(applicationDidEnterBackground:)]) [delegate applicationDidEnterBackground:UIApplication.sharedApplication];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    id delegate = PLXAppDelegate();
    if (![delegate respondsToSelector:@selector(application:openURL:options:)]) return;
    for (UIOpenURLContext *context in URLContexts) {
        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        if (context.options.sourceApplication) options[UIApplicationOpenURLOptionsSourceApplicationKey] = context.options.sourceApplication;
        if (context.options.annotation) options[UIApplicationOpenURLOptionsAnnotationKey] = context.options.annotation;
        options[UIApplicationOpenURLOptionsOpenInPlaceKey] = @(context.options.openInPlace);
        [delegate application:UIApplication.sharedApplication openURL:context.URL options:options];
    }
}

- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity {
    id delegate = PLXAppDelegate();
    if ([delegate respondsToSelector:@selector(application:continueUserActivity:restorationHandler:)]) {
        [delegate application:UIApplication.sharedApplication continueUserActivity:userActivity restorationHandler:^(NSArray *objects) {}];
    }
}

@end
