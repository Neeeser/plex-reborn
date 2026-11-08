// Plex's tabs in the Duo's native vertical tab bar, and consistent tab icon sizes.
//
// iOS 27.1 draws a UITabBarController's tabs in the Duo's vertical bar (on the
// outer screen, and on the inner screen in landscape): icons in a glass column
// at the bottom of the bar's strip that expands with labels when dragged.
// Plex 8.45 does not use UITabBarController. It places a standalone tab bar
// (PMSafeAreaTabBar) inside its own screens, so the system leaves it at the
// bottom. For each of Plex's tab bars, this file adds a real UITabBarController
// with the same tabs on top of the screen that owns the bar. Its pages are empty
// and transparent and pass touches through, so only the system's tab bar is
// visible and touchable. Choosing a tab goes through Plex's own tab bar and its
// delegate, so Plex's navigation is unchanged. Without a vertical bar (unfolded
// portrait) the native bar is hidden and Plex's own bar is used.
//
// Plex's tab images come in different sizes; the floating tab bar draws them at
// their natural size, so some icons fill the whole button and crowd their
// labels. Every tab image is redrawn once into the same square.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static const CGFloat PLXTabIconSide = 24.0;

static const void *PLXNormalizedImageKey = &PLXNormalizedImageKey;
static const void *PLXNativeTabsKey = &PLXNativeTabsKey;

static UIImage *PLXSquareIcon(UIImage *image) {
    if (!image || objc_getAssociatedObject(image, PLXNormalizedImageKey)) return image;
    CGSize box = CGSizeMake(PLXTabIconSide, PLXTabIconSide);
    CGFloat scale = MIN(box.width / MAX(image.size.width, 1), box.height / MAX(image.size.height, 1));
    CGSize drawn = CGSizeMake(image.size.width * scale, image.size.height * scale);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:box];
    UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake((box.width - drawn.width) / 2, (box.height - drawn.height) / 2, drawn.width, drawn.height)];
    }];
    result = [result imageWithRenderingMode:image.renderingMode];
    objc_setAssociatedObject(result, PLXNormalizedImageKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

static void PLXNormalizeTabImages(UITabBar *tabBar) {
    for (UITabBarItem *item in tabBar.items) {
        UIImage *image = PLXSquareIcon(item.image);
        if (image != item.image) item.image = image;
        UIImage *selected = PLXSquareIcon(item.selectedImage);
        if (selected != item.selectedImage) item.selectedImage = selected;
    }
}

#pragma mark - Pass-through container view

// The tab bar controller covers the whole screen; touches anywhere except its
// tab bar must reach Plex underneath. Its view gets a subclass whose hit test
// only returns views inside the system's bar UI.
static UIView *PLXPassThroughHitTest(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    struct objc_super parent = { self, class_getSuperclass(object_getClass(self)) };
    UIView *hit = ((UIView *(*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&parent, _cmd, point, event);
    for (UIView *v = hit; v && v != self; v = v.superview) {
        NSString *name = NSStringFromClass(v.class);
        if ([v isKindOfClass:UITabBar.class] || [name containsString:@"TabBar"] || [name containsString:@"FloatingBar"] || [name containsString:@"TabButton"]) return hit;
    }
    return nil;
}

static void PLXMakePassThrough(UIView *view) {
    NSString *name = [@"PLXPassThrough_" stringByAppendingString:NSStringFromClass(view.class)];
    Class subclass = NSClassFromString(name);
    if (!subclass) {
        subclass = objc_allocateClassPair(view.class, name.UTF8String, 0);
        Method m = class_getInstanceMethod(UIView.class, @selector(hitTest:withEvent:));
        class_addMethod(subclass, @selector(hitTest:withEvent:), (IMP)PLXPassThroughHitTest, method_getTypeEncoding(m));
        objc_registerClassPair(subclass);
    }
    object_setClass(view, subclass);
}

#pragma mark - Native tabs

@interface PLXNativeTabs : NSObject <UITabBarControllerDelegate>
@property (nonatomic, weak) UITabBar *plexBar;
@property (nonatomic, strong) UITabBarController *controller;
@property (nonatomic, copy) NSArray<NSString *> *titles;
@end

@implementation PLXNativeTabs

- (void)reloadPagesIfNeeded {
    NSArray<UITabBarItem *> *items = self.plexBar.items;
    NSArray<NSString *> *titles = [items valueForKey:@"title"];
    if ([titles isEqualToArray:self.titles]) return;
    self.titles = titles;
    NSMutableArray *pages = [NSMutableArray array];
    for (UITabBarItem *item in items) {
        UIViewController *page = [UIViewController new];
        page.view.backgroundColor = UIColor.clearColor;
        page.view.userInteractionEnabled = NO;
        page.tabBarItem = [[UITabBarItem alloc] initWithTitle:item.title image:PLXSquareIcon(item.image) selectedImage:PLXSquareIcon(item.selectedImage)];
        page.tabBarItem.accessibilityLabel = item.accessibilityLabel ?: item.title;
        [pages addObject:page];
    }
    self.controller.viewControllers = pages;
}

- (void)syncSelection {
    UITabBarItem *selected = self.plexBar.selectedItem;
    NSUInteger index = selected ? [self.plexBar.items indexOfObject:selected] : NSNotFound;
    if (index != NSNotFound && index < self.controller.viewControllers.count && self.controller.selectedIndex != index) {
        self.controller.selectedIndex = index;
    }
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    UITabBar *bar = self.plexBar;
    NSUInteger index = [tabBarController.viewControllers indexOfObject:viewController];
    if (!bar || index == NSNotFound || index >= bar.items.count) return;
    UITabBarItem *item = bar.items[index];
    if (bar.selectedItem == item) return;
    bar.selectedItem = item;
    if ([bar.delegate respondsToSelector:@selector(tabBar:didSelectItem:)]) [bar.delegate tabBar:bar didSelectItem:item];
}

@end

// The view controller whose view contains the tab bar.
static UIViewController *PLXOwningViewController(UIView *view) {
    for (UIResponder *r = view.superview; r; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) return (UIViewController *)r;
    }
    return nil;
}

// The top of the mini player, in the owner's coordinates, so the native bar
// sits above it instead of underneath. CGFLOAT_MAX when no mini player shows.
static CGFloat PLXMiniPlayerTop(UIView *owner) {
    static Class miniPlayerClass;
    if (!miniPlayerClass) miniPlayerClass = NSClassFromString(@"PMMiniPlayerView");
    __block CGFloat top = CGFLOAT_MAX;
    __block void (^visit)(UIView *);
    __block __weak void (^weakVisit)(UIView *);
    weakVisit = visit = ^(UIView *v) {
        if ([v isKindOfClass:miniPlayerClass]) {
            BOOL shown = !v.hidden && v.alpha > 0.01 && v.window;
            for (UIView *s = v.superview; shown && s; s = s.superview) if (s.hidden) shown = NO;
            if (shown) top = MIN(top, [v convertPoint:CGPointZero toView:owner].y);
            return;
        }
        for (UIView *s in v.subviews) weakVisit(s);
    };
    if (owner.window) visit(owner.window);
    return top;
}

static void PLXUpdateNativeTabs(UITabBar *tabBar) {
    PLXNativeTabs *tabs = objc_getAssociatedObject(tabBar, PLXNativeTabsKey);
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = tabBar.window ? tabBar.window.traitCollection.verticalBarEdge : 0;
    BOOL useNative = edge != 0 && tabBar.items.count > 0;

    if (!useNative) {
        tabs.controller.view.hidden = YES;
        if (objc_getAssociatedObject(tabBar, @selector(alpha))) {
            tabBar.alpha = 1;
            objc_setAssociatedObject(tabBar, @selector(alpha), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    UIViewController *owner = PLXOwningViewController(tabBar);
    if (!owner) return;
    if (!tabs) {
        tabs = [PLXNativeTabs new];
        tabs.plexBar = tabBar;
        tabs.controller = [UITabBarController new];
        tabs.controller.delegate = tabs;
        objc_setAssociatedObject(tabBar, PLXNativeTabsKey, tabs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UITabBarController *controller = tabs.controller;
    if (controller.parentViewController != owner) {
        [controller willMoveToParentViewController:nil];
        [controller.view removeFromSuperview];
        [controller removeFromParentViewController];
        [owner addChildViewController:controller];
        controller.view.backgroundColor = UIColor.clearColor;
        PLXMakePassThrough(controller.view);
        [owner.view addSubview:controller.view];
        [controller didMoveToParentViewController:owner];
    }
    [tabs reloadPagesIfNeeded];
    [tabs syncSelection];

    // Plex's bar stays in place for its own layout code, invisible and untouchable.
    tabBar.alpha = 0;
    objc_setAssociatedObject(tabBar, @selector(alpha), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    controller.view.hidden = tabBar.isHidden;

    CGRect frame = owner.view.bounds;
    CGFloat miniPlayerTop = PLXMiniPlayerTop(owner.view);
    if (miniPlayerTop < CGRectGetMaxY(frame)) frame.size.height = MAX(0, miniPlayerTop - CGRectGetMinY(frame));
    if (!CGRectEqualToRect(controller.view.frame, frame)) controller.view.frame = frame;
    if (owner.view.subviews.lastObject != controller.view) [owner.view bringSubviewToFront:controller.view];
}

static IMP PLXOrigTabBarLayout;

static void PLXTabBarLayoutSubviews(UITabBar *self, SEL _cmd) {
    PLXNormalizeTabImages(self);
    ((void (*)(id, SEL))PLXOrigTabBarLayout)(self, _cmd);
    PLXUpdateNativeTabs(self);
}

static IMP PLXOrigTabBarSetHidden;

static void PLXTabBarSetHidden(UITabBar *self, SEL _cmd, BOOL hidden) {
    ((void (*)(id, SEL, BOOL))PLXOrigTabBarSetHidden)(self, _cmd, hidden);
    PLXNativeTabs *tabs = objc_getAssociatedObject(self, PLXNativeTabsKey);
    if (tabs && objc_getAssociatedObject(self, @selector(alpha))) tabs.controller.view.hidden = hidden;
}

static IMP PLXOrigTabBarSetSelectedItem;

static void PLXTabBarSetSelectedItem(UITabBar *self, SEL _cmd, UITabBarItem *item) {
    ((void (*)(id, SEL, UITabBarItem *))PLXOrigTabBarSetSelectedItem)(self, _cmd, item);
    [(PLXNativeTabs *)objc_getAssociatedObject(self, PLXNativeTabsKey) syncSelection];
}

static IMP PLXReplaceOnClass(Class cls, SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    if (class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) {
        return method_getImplementation(class_getInstanceMethod(class_getSuperclass(cls), selector));
    }
    return method_setImplementation(method, replacement);
}

static BOOL PLXInstallNativeTabs(void) {
    static BOOL installed;
    if (installed) return YES;
    Class tabBarClass = NSClassFromString(@"PMSafeAreaTabBar");
    if (!tabBarClass) return NO;
    installed = YES;
    PLXOrigTabBarLayout = PLXReplaceOnClass(tabBarClass, @selector(layoutSubviews), (IMP)PLXTabBarLayoutSubviews);
    PLXOrigTabBarSetHidden = PLXReplaceOnClass(tabBarClass, @selector(setHidden:), (IMP)PLXTabBarSetHidden);
    PLXOrigTabBarSetSelectedItem = PLXReplaceOnClass(tabBarClass, @selector(setSelectedItem:), (IMP)PLXTabBarSetSelectedItem);
    return YES;
}

__attribute__((constructor)) static void PLXInstallNativeTabsAtLaunch(void) {
    if (PLXInstallNativeTabs()) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { PLXInstallNativeTabs(); }];
}
