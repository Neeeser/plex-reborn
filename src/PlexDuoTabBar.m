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
#import "PlexReborn.h"

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
    // Only the tab bar's own buttons and platter count. The full-screen
    // floating bar container around them must pass touches through, or it
    // swallows taps on other vertical bar buttons hosted underneath.
    for (UIView *v = hit; v && v != self; v = v.superview) {
        NSString *name = NSStringFromClass(v.class);
        if ([name containsString:@"FloatingBarContainer"] || [name containsString:@"FloatingBarHosting"]) return nil;
        if ([name containsString:@"TabButton"] || [name containsString:@"TabBarItemPlatter"] ||
            [name containsString:@"TabBarExpansion"] || [v isKindOfClass:UITabBar.class]) return hit;
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

// Selects a tab in Plex's bar the way a tap does: the bar's selection, then its delegate.
static void PLXSelectBarItem(UITabBar *bar, UITabBarItem *item) {
    if (!bar || !item || bar.selectedItem == item) return;
    bar.selectedItem = item;
    if ([bar.delegate respondsToSelector:@selector(tabBar:didSelectItem:)]) [bar.delegate tabBar:bar didSelectItem:item];
}

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
    PLXSelectBarItem(bar, bar.items[index]);
}

@end

// The top of the mini player, in the owner's coordinates, so the native bar
// sits above it instead of underneath. CGFLOAT_MAX when no mini player shows.
static CGFloat PLXMiniPlayerTop(UIView *owner) {
    __block CGFloat top = CGFLOAT_MAX;
    __block void (^visit)(UIView *);
    __block __weak void (^weakVisit)(UIView *);
    weakVisit = visit = ^(UIView *v) {
        if (PLXIsMiniPlayerView(v)) {
            // A floating card sits beside the tabs, which then run to the bottom.
            BOOL shown = !v.hidden && v.alpha > 0.01 && v.window && !PLXMiniPlayerFloats(v);
            for (UIView *s = v.superview; shown && s; s = s.superview) if (s.hidden) shown = NO;
            if (shown) top = MIN(top, [v convertPoint:CGPointZero toView:owner].y);
            return;
        }
        for (UIView *s in v.subviews) weakVisit(s);
    };
    if (owner.window) visit(owner.window);
    return top;
}

// Plex's bar is on screen: in a window, and neither it nor an ancestor hidden.
static BOOL PLXPlexBarShowing(UITabBar *tabBar) {
    if (!tabBar.window) return NO;
    for (UIView *v = tabBar; v; v = v.superview) if (v.hidden) return NO;
    return YES;
}

static void PLXMakePassThrough(UIView *view);

#pragma mark - Tab entries (Home tabs and side menu)

// The tab bar of Plex's Home screen: the first Plex tab bar shown after launch,
// since Plex opens on Home.
static __weak UITabBar *PLXHomeBar;
static NSArray<PLXTabEntry *> *PLXHomeEntries;

static void PLXRememberHomeBar(UITabBar *bar) {
    if (PLXHomeBar || bar.items.count < 3 || !bar.window) return;
    PLXHomeBar = bar;
    NSMutableArray *entries = [NSMutableArray array];
    for (UITabBarItem *item in bar.items) {
        PLXTabEntry *e = [PLXTabEntry new];
        e.identifier = [@"home:" stringByAppendingString:item.title ?: @""];
        e.title = item.title;
        e.image = PLXSquareIcon(item.image);
        [entries addObject:e];
    }
    PLXHomeEntries = entries;
}

static UIView *PLXFindViewOfClass(UIView *root, NSString *className) {
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (UIView *sub in root.subviews) { UIView *v = PLXFindViewOfClass(sub, className); if (v) return v; }
    return nil;
}

static UIWindow *PLXMainWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
    }
    return nil;
}

// Plex's side menu list (PMSidebar contains a table of PMSourceListItemTableViewCell).
static UITableView *PLXSideMenuTable(void) {
    UIView *sidebar = PLXFindViewOfClass(PLXMainWindow(), @"PMSidebar");
    UIView *table = sidebar ? PLXFindViewOfClass(sidebar, @"PMReorderableTableView") : nil;
    return [table isKindOfClass:UITableView.class] ? (UITableView *)table : nil;
}

static void PLXCollectLabelsAndImage(UIView *view, NSMutableArray<NSString *> *labels, UIImage **image) {
    if (view.hidden) return;
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) [labels addObject:((UILabel *)view).text];
    if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image && CGRectGetWidth(view.bounds) >= 18 && !*image) {
        *image = ((UIImageView *)view).image;
    }
    for (UIView *sub in view.subviews) PLXCollectLabelsAndImage(sub, labels, image);
}

// One entry per side menu row, in the menu's order.
static NSArray<PLXTabEntry *> *PLXSideMenuEntries(void) {
    UITableView *table = PLXSideMenuTable();
    id<UITableViewDataSource> source = table.dataSource;
    if (!source) return @[];
    NSMutableArray *entries = [NSMutableArray array];
    NSInteger sections = [source respondsToSelector:@selector(numberOfSectionsInTableView:)] ? [source numberOfSectionsInTableView:table] : 1;
    for (NSInteger s = 0; s < sections; s++) {
        NSInteger rows = [source tableView:table numberOfRowsInSection:s];
        for (NSInteger r = 0; r < rows; r++) {
            UITableViewCell *cell = [source tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:s]];
            [cell layoutIfNeeded];
            NSMutableArray<NSString *> *labels = [NSMutableArray array];
            UIImage *image = nil;
            PLXCollectLabelsAndImage(cell.contentView, labels, &image);
            if (labels.count == 0) continue;
            PLXTabEntry *e = [PLXTabEntry new];
            e.title = labels[0];
            e.subtitle = labels.count > 1 ? labels[1] : nil;
            e.identifier = [NSString stringWithFormat:@"menu:%@|%@", e.title, e.subtitle ?: @""];
            e.image = PLXSquareIcon(image);
            [entries addObject:e];
        }
    }
    return entries;
}

static NSArray<PLXTabEntry *> *PLXCachedMenuEntries;

NSArray<PLXTabEntry *> *PLXAvailableTabEntries(void) {
    NSArray *menu = PLXSideMenuEntries();
    if (menu.count) PLXCachedMenuEntries = menu;
    NSMutableArray *all = [NSMutableArray arrayWithArray:PLXHomeEntries ?: @[]];
    NSSet *homeTitles = [NSSet setWithArray:[PLXHomeEntries valueForKey:@"title"] ?: @[]];
    for (PLXTabEntry *e in PLXCachedMenuEntries) if (![homeTitles containsObject:e.title]) [all addObject:e];
    return all;
}

static PLXTabEntry *PLXEntryWithID(NSString *identifier) {
    for (PLXTabEntry *e in PLXAvailableTabEntries()) if ([e.identifier isEqualToString:identifier]) return e;
    return nil;
}

// Opens a side menu entry exactly as tapping it in the side menu does.
static BOOL PLXOpenSideMenuEntry(NSString *identifier) {
    UITableView *table = PLXSideMenuTable();
    id<UITableViewDataSource> source = table.dataSource;
    if (!source) return NO;
    NSInteger sections = [source respondsToSelector:@selector(numberOfSectionsInTableView:)] ? [source numberOfSectionsInTableView:table] : 1;
    for (NSInteger s = 0; s < sections; s++) {
        NSInteger rows = [source tableView:table numberOfRowsInSection:s];
        for (NSInteger r = 0; r < rows; r++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:r inSection:s];
            UITableViewCell *cell = [source tableView:table cellForRowAtIndexPath:path];
            NSMutableArray<NSString *> *labels = [NSMutableArray array];
            UIImage *image = nil;
            PLXCollectLabelsAndImage(cell.contentView, labels, &image);
            if (labels.count == 0) continue;
            NSString *candidate = [NSString stringWithFormat:@"menu:%@|%@", labels[0], labels.count > 1 ? labels[1] : @""];
            if (![candidate isEqualToString:identifier]) continue;
            [table selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
            if ([table.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
                [table.delegate tableView:table didSelectRowAtIndexPath:path];
            }
            return YES;
        }
    }
    return NO;
}

static void PLXSelectHomeTab(NSString *title) {
    UITabBar *bar = PLXHomeBar;
    for (UITabBarItem *item in bar.items) {
        if ([item.title isEqualToString:title]) { PLXSelectBarItem(bar, item); return; }
    }
}

#pragma mark - Library tabs

// A library screen has its own tab bar (Recommended, Library, Categories).
// Shown as Plex draws it, it is a second row of controls under the content
// beside the vertical bar's tabs. The default placement replaces it with one
// button in the vertical bar whose menu lists the tabs; the button shows the
// current tab's icon.

// Each library bar, keyed by the navigation item of the screen that owns it.
static NSMapTable<UINavigationItem *, UITabBar *> *PLXLibraryBars;
// The library bar shown as tabs in the vertical bar, which then stand in for the user's own tabs.
static __weak UITabBar *PLXVerticalLibraryBar;
static const void *PLXLibraryButtonKey = &PLXLibraryButtonKey;
static const void *PLXLibraryButtonStateKey = &PLXLibraryButtonStateKey;

// The screen that owns a view and sits directly in a navigation controller.
static UIViewController *PLXNavigationChildOwning(UIView *view) {
    UIViewController *vc = nil;
    for (UIResponder *r = view.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) { vc = (UIViewController *)r; break; }
    }
    while (vc.parentViewController && ![vc.parentViewController isKindOfClass:UINavigationController.class]) vc = vc.parentViewController;
    return vc.navigationController ? vc : nil;
}

static void PLXRegisterLibraryBar(UITabBar *bar) {
    UIViewController *owner = PLXNavigationChildOwning(bar);
    if (!owner) return;
    if (!PLXLibraryBars) PLXLibraryBars = [NSMapTable weakToWeakObjectsMapTable];
    if ([PLXLibraryBars objectForKey:owner.navigationItem] != bar) [PLXLibraryBars setObject:bar forKey:owner.navigationItem];
    [owner.navigationController.navigationBar setNeedsLayout];
}

UIBarButtonItem *PLXLibraryTabsItemForNavigationItem(UINavigationItem *navItem) {
    UITabBar *bar = [PLXLibraryBars objectForKey:navItem];
    if (!bar || bar == PLXHomeBar || bar.items.count < 2 || !PLXPlexBarShowing(bar)) return nil;
    if (PLXSettingInteger(PLXSettingLibraryTabs) != PLXLibraryTabsButton) return nil;
    UIBarButtonItem *button = objc_getAssociatedObject(bar, PLXLibraryButtonKey);
    if (!button) {
        button = [[UIBarButtonItem alloc] initWithImage:nil menu:nil];
        objc_setAssociatedObject(bar, PLXLibraryButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UITabBarItem *selected = bar.selectedItem ?: bar.items.firstObject;
    NSString *state = [NSString stringWithFormat:@"%@>%@", [[bar.items valueForKey:@"title"] componentsJoinedByString:@"|"], selected.title];
    if ([objc_getAssociatedObject(button, PLXLibraryButtonStateKey) isEqualToString:state]) return button;
    objc_setAssociatedObject(button, PLXLibraryButtonStateKey, state, OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    __weak UITabBar *weakBar = bar;
    for (UITabBarItem *item in bar.items) {
        __weak UITabBarItem *weakItem = item;
        UIImage *icon = [PLXSquareIcon(item.image) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIAction *action = [UIAction actionWithTitle:item.title ?: @"" image:icon identifier:nil handler:^(UIAction *a) {
            PLXSelectBarItem(weakBar, weakItem);
        }];
        action.state = item == selected ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    button.menu = [UIMenu menuWithChildren:actions];
    button.image = [PLXSquareIcon(selected.image) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    button.title = selected.title;
    button.accessibilityLabel = selected.title;
    return button;
}

static CGFloat PLXPlatterTop(UIView *view, UIWindow *window) {
    if (view.hidden || view.alpha < 0.01) return CGFLOAT_MAX;
    if ([NSStringFromClass(view.class) containsString:@"ExpansionPlatterContainer"] && CGRectGetHeight(view.bounds) > 0) {
        return [view convertRect:view.bounds toView:window].origin.y;
    }
    CGFloat top = CGFLOAT_MAX;
    for (UIView *sub in view.subviews) top = MIN(top, PLXPlatterTop(sub, window));
    return top;
}

CGFloat PLXVerticalTabsTop(UIWindow *window) {
    CGFloat top = CGFLOAT_MAX;
    for (UIViewController *child in window.rootViewController.childViewControllers) {
        if (![child isKindOfClass:UITabBarController.class] || child.view.hidden || !child.view.window) continue;
        top = MIN(top, PLXPlatterTop(child.view, window)); // iOS 26 draws the tabs in a floating container in the controller's view, outside its tabBar
    }
    return top;
}

#pragma mark - Custom tab bar (user's own tabs)

@interface PLXCustomTabs : NSObject <UITabBarControllerDelegate>
@property (nonatomic, strong) UITabBarController *controller;
@property (nonatomic, copy) NSArray<NSString *> *identifiers;
@end

static PLXCustomTabs *PLXCustom;

@implementation PLXCustomTabs

- (void)reloadIfNeeded {
    NSArray<NSString *> *ids = [NSUserDefaults.standardUserDefaults arrayForKey:PLXSettingTabBarItems] ?: [PLXHomeEntries valueForKey:@"identifier"];
    if ([ids isEqualToArray:self.identifiers] && self.controller.viewControllers.count) return;
    NSMutableArray *pages = [NSMutableArray array];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *identifier in ids) {
        PLXTabEntry *entry = PLXEntryWithID(identifier);
        if (!entry) continue; // side menu not loaded yet; retried on the next layout
        UIViewController *page = [UIViewController new];
        page.view.backgroundColor = UIColor.clearColor;
        page.view.userInteractionEnabled = NO;
        page.tabBarItem = [[UITabBarItem alloc] initWithTitle:entry.title image:entry.image selectedImage:entry.image];
        [pages addObject:page];
        [kept addObject:identifier];
    }
    if (pages.count == 0) return;
    self.identifiers = ids.count == kept.count ? ids : nil;
    self.controller.viewControllers = pages;
    objc_setAssociatedObject(self.controller, @selector(identifiers), kept, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    NSArray<NSString *> *ids = objc_getAssociatedObject(tabBarController, @selector(identifiers));
    NSUInteger index = [tabBarController.viewControllers indexOfObject:viewController];
    if (index == NSNotFound || index >= ids.count) return;
    NSString *identifier = ids[index];
    if ([identifier hasPrefix:@"menu:"]) {
        PLXOpenSideMenuEntry(identifier);
        return;
    }
    NSString *title = [identifier substringFromIndex:5];
    if (PLXHomeBar && PLXPlexBarShowing(PLXHomeBar)) {
        PLXSelectHomeTab(title);
        return;
    }
    // Another screen is showing: go Home through the side menu, then pick the tab.
    for (PLXTabEntry *e in PLXCachedMenuEntries) {
        if ([e.title isEqualToString:PLXHomeEntries.firstObject.title]) { PLXOpenSideMenuEntry(e.identifier); break; }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ PLXSelectHomeTab(title); });
}

@end

// The system places the vertical tab bar inside its host's safe area. On the
// unfolded screen the window does not reserve the vertical bar's column (it
// reports a top inset instead), so the tab bar lands flush against the screen
// edge, 24 pt outside the column the bar buttons use. Reserve the column on
// the host so both line up.

static void PLXReserveVerticalBarColumn(UIViewController *host, UIWindow *window, NSInteger edge) {
    UIEdgeInsets windowSafe = window.safeAreaInsets;
    UIEdgeInsets extra = UIEdgeInsetsZero;
    if (edge == 2) extra.right = MAX(0, PLXVerticalBarColumnWidth - windowSafe.right);
    if (edge == 1) extra.left = MAX(0, PLXVerticalBarColumnWidth - windowSafe.left);
    if (!UIEdgeInsetsEqualToEdgeInsets(host.additionalSafeAreaInsets, extra)) host.additionalSafeAreaInsets = extra;
}

static void PLXUpdateCustomTabs(UIWindow *window) {
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = window ? window.traitCollection.verticalBarEdge : 0;
    BOOL show = PLXSettingBool(PLXSettingCustomTabBar) && edge != 0 && PLXHomeEntries.count;
    UITabBar *library = PLXVerticalLibraryBar;
    if (library && PLXPlexBarShowing(library) && PLXSettingInteger(PLXSettingLibraryTabs) == PLXLibraryTabsVerticalBar) show = NO;
    UIViewController *root = window.rootViewController;
    if (!show || !root) { PLXCustom.controller.view.hidden = YES; return; }
    if (!PLXCustom) {
        PLXCustom = [PLXCustomTabs new];
        PLXCustom.controller = [UITabBarController new];
        PLXCustom.controller.delegate = PLXCustom;
    }
    UITabBarController *controller = PLXCustom.controller;
    if (controller.parentViewController != root) {
        [controller willMoveToParentViewController:nil];
        [controller.view removeFromSuperview];
        [controller removeFromParentViewController];
        [root addChildViewController:controller];
        controller.view.backgroundColor = UIColor.clearColor;
        PLXMakePassThrough(controller.view);
        [root.view addSubview:controller.view];
        [controller didMoveToParentViewController:root];
    }
    [PLXCustom reloadIfNeeded];
    controller.view.hidden = controller.viewControllers.count == 0;
    PLXReserveVerticalBarColumn(controller, window, edge);
    CGRect frame = root.view.bounds;
    CGFloat miniPlayerTop = PLXMiniPlayerTop(root.view);
    if (miniPlayerTop < CGRectGetMaxY(frame)) frame.size.height = MAX(0, miniPlayerTop);
    if (!CGRectEqualToRect(controller.view.frame, frame)) controller.view.frame = frame;
    if (root.view.subviews.lastObject != controller.view) [root.view bringSubviewToFront:controller.view];
}

static void PLXUpdateNativeTabs(UITabBar *tabBar) {
    PLXNativeTabs *tabs = objc_getAssociatedObject(tabBar, PLXNativeTabsKey);
    PLXRememberHomeBar(tabBar);
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = tabBar.window ? tabBar.window.traitCollection.verticalBarEdge : 0;
    BOOL useNative = edge != 0 && tabBar.items.count > 0;

    BOOL isHome = tabBar == PLXHomeBar;
    BOOL custom = PLXSettingBool(PLXSettingCustomTabBar) && PLXHomeEntries.count;
    NSInteger libraryPlacement = PLXSettingInteger(PLXSettingLibraryTabs);
    if (useNative && !isHome) PLXRegisterLibraryBar(tabBar);

    // A library's tabs as a menu button (added by the navigation bar code) or as Plex's own bar.
    if (useNative && !isHome && libraryPlacement != PLXLibraryTabsVerticalBar) {
        tabs.controller.view.hidden = YES;
        BOOL hidePlexBar = libraryPlacement == PLXLibraryTabsButton;
        tabBar.alpha = hidePlexBar ? 0 : 1;
        objc_setAssociatedObject(tabBar, @selector(alpha), hidePlexBar ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (custom) PLXUpdateCustomTabs(tabBar.window);
        return;
    }
    if (useNative && !isHome) PLXVerticalLibraryBar = tabBar;

    // With the user's own tabs, the Home screen's tabs live in that bar.
    if (useNative && custom && isHome) {
        tabs.controller.view.hidden = YES;
        tabBar.alpha = 0;
        objc_setAssociatedObject(tabBar, @selector(alpha), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        PLXUpdateCustomTabs(tabBar.window);
        return;
    }
    if (!custom) PLXCustom.controller.view.hidden = YES;

    if (!useNative) {
        tabs.controller.view.hidden = YES;
        if (objc_getAssociatedObject(tabBar, @selector(alpha))) {
            tabBar.alpha = 1;
            objc_setAssociatedObject(tabBar, @selector(alpha), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    // Host on the window's root screen, not the screen that owns Plex's bar:
    // Plex slides its content sideways while the side menu is open, and the
    // system places the vertical tab bar from its host's position at layout
    // time, so a host inside the sliding content left the bar on the wrong side.
    UIViewController *owner = tabBar.window.rootViewController;
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
    if (custom) PLXUpdateCustomTabs(tabBar.window);

    // Plex's bar stays in place for its own layout code, invisible and untouchable.
    tabBar.alpha = 0;
    objc_setAssociatedObject(tabBar, @selector(alpha), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    controller.view.hidden = !PLXPlexBarShowing(tabBar);

    PLXReserveVerticalBarColumn(controller, tabBar.window, edge);
    CGRect frame = owner.view.bounds;
    CGFloat miniPlayerTop = PLXMiniPlayerTop(owner.view);
    if (miniPlayerTop < CGRectGetMaxY(frame)) frame.size.height = MAX(0, miniPlayerTop - CGRectGetMinY(frame));
    if (!CGRectEqualToRect(controller.view.frame, frame)) controller.view.frame = frame;
    if (owner.view.subviews.lastObject != controller.view) [owner.view bringSubviewToFront:controller.view];
}

// Plex pads the content screen beside its tab bar by the bar's height
// (additionalSafeAreaInsets.bottom on that screen). While Plex Reborn hides
// the bar, that padding is dead space at the end of every list, so it is
// removed and put back when the bar shows again.
static const void *PLXSuppressedInsetKey = &PLXSuppressedInsetKey;

static void PLXUpdatePlexBarInset(UITabBar *bar) {
    BOOL hidden = objc_getAssociatedObject(bar, @selector(alpha)) != nil && bar.alpha < 0.01 && bar.window;
    UIResponder *responder = bar.superview.nextResponder;
    if (![responder isKindOfClass:UIViewController.class]) return;
    for (UIViewController *child in ((UIViewController *)responder).childViewControllers) {
        NSNumber *saved = objc_getAssociatedObject(child, PLXSuppressedInsetKey);
        UIEdgeInsets insets = child.additionalSafeAreaInsets;
        if (hidden && insets.bottom > 1) {
            objc_setAssociatedObject(child, PLXSuppressedInsetKey, @(insets.bottom), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            insets.bottom = 0;
            child.additionalSafeAreaInsets = insets;
        } else if (!hidden && saved) {
            if (insets.bottom < 1) {
                insets.bottom = saved.doubleValue;
                child.additionalSafeAreaInsets = insets;
            }
            objc_setAssociatedObject(child, PLXSuppressedInsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static IMP PLXOrigTabBarLayout;

static void PLXTabBarLayoutSubviews(UITabBar *self, SEL _cmd) {
    PLXNormalizeTabImages(self);
    ((void (*)(id, SEL))PLXOrigTabBarLayout)(self, _cmd);
    PLXUpdateNativeTabs(self);
    PLXUpdatePlexBarInset(self);
}

static IMP PLXOrigTabBarSetHidden;

static void PLXTabBarSetHidden(UITabBar *self, SEL _cmd, BOOL hidden) {
    ((void (*)(id, SEL, BOOL))PLXOrigTabBarSetHidden)(self, _cmd, hidden);
    PLXNativeTabs *tabs = objc_getAssociatedObject(self, PLXNativeTabsKey);
    if (tabs && objc_getAssociatedObject(self, @selector(alpha))) tabs.controller.view.hidden = !PLXPlexBarShowing(self);
}

// Plex removes a screen's view from the window when another is pushed over it
// or it is popped; its native bar must go with it.
static IMP PLXOrigTabBarDidMoveToWindow;

static void PLXTabBarDidMoveToWindow(UITabBar *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigTabBarDidMoveToWindow)(self, _cmd);
    PLXNativeTabs *tabs = objc_getAssociatedObject(self, PLXNativeTabsKey);
    if (self.window) PLXUpdateNativeTabs(self);
    else tabs.controller.view.hidden = YES;
    if (!self.window && PLXCustom) PLXUpdateCustomTabs(PLXMainWindow());
}

static IMP PLXOrigTabBarSetSelectedItem;

static void PLXTabBarSetSelectedItem(UITabBar *self, SEL _cmd, UITabBarItem *item) {
    ((void (*)(id, SEL, UITabBarItem *))PLXOrigTabBarSetSelectedItem)(self, _cmd, item);
    [(PLXNativeTabs *)objc_getAssociatedObject(self, PLXNativeTabsKey) syncSelection];
    if (objc_getAssociatedObject(self, PLXLibraryButtonKey)) [PLXNavigationChildOwning(self).navigationController.navigationBar setNeedsLayout];
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
    PLXOrigTabBarDidMoveToWindow = PLXReplaceOnClass(tabBarClass, @selector(didMoveToWindow), (IMP)PLXTabBarDidMoveToWindow);
    return YES;
}

// Plex's root screen lays out when the mini player appears or goes away; the
// custom tab bar follows so it stays above the mini player.
static IMP PLXOrigRootDidLayout;

static void PLXRootDidLayoutSubviews(UIViewController *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigRootDidLayout)(self, _cmd);
    if (PLXCustom || PLXSettingBool(PLXSettingCustomTabBar)) PLXUpdateCustomTabs(self.view.window);
}

static void PLXRelayoutTabBars(UIView *view) {
    if ([NSStringFromClass(view.class) isEqualToString:@"PMSafeAreaTabBar"]) PLXUpdateNativeTabs((UITabBar *)view);
    for (UIView *sub in view.subviews) PLXRelayoutTabBars(sub);
}

__attribute__((constructor)) static void PLXInstallNativeTabsAtLaunch(void) {
    void (^installRoot)(void) = ^{
        static BOOL installed;
        Class root = NSClassFromString(@"PMAppViewController");
        if (installed || !root) return;
        installed = YES;
        PLXOrigRootDidLayout = PLXReplaceOnClass(root, @selector(viewDidLayoutSubviews), (IMP)PLXRootDidLayoutSubviews);
    };
    if (PLXInstallNativeTabs()) installRoot();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { PLXInstallNativeTabs(); installRoot(); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:PLXSettingsDidChangeNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            PLXCustom.identifiers = nil;
            UIWindow *window = PLXMainWindow();
            PLXRelayoutTabBars(window);
            PLXUpdateCustomTabs(window);
        }];
}
