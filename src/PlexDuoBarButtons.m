// Plex's top bar buttons in the Duo's vertical bar.
//
// iOS 27.1 moves a navigation bar's standard buttons into the Duo's vertical
// bar, where they are easy to reach and the top bar's height goes back to the
// content. Plex builds its buttons (side menu, cast, search, more) as custom
// views, which iOS leaves in the top bar. While the vertical bar shows, each
// of those items is replaced by a standard button with the same icon that
// triggers Plex's own control. Without a vertical bar Plex's own items are restored.
// A library screen's tabs can also appear here as one button (PlexDuoTabBar.m).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "PlexReborn.h"

static const void *PLXOriginalLeftKey = &PLXOriginalLeftKey;
static const void *PLXOriginalRightKey = &PLXOriginalRightKey;
static const void *PLXProxyKey = &PLXProxyKey;
static BOOL PLXApplying;

static UIControl *PLXFirstControl(UIView *view) {
    if ([view isKindOfClass:UIControl.class]) return (UIControl *)view;
    for (UIView *sub in view.subviews) { UIControl *c = PLXFirstControl(sub); if (c) return c; }
    return nil;
}

static UIImage *PLXSnapshotIcon(UIView *view) {
    CGSize size = view.bounds.size;
    if (size.width < 1 || size.height < 1) size = CGSizeMake(40, 40);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [view.layer renderInContext:ctx.CGContext];
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// A standard button standing in for one of Plex's custom-view items, or nil
// when the item is already standard or holds something other than a button.
static UIBarButtonItem *PLXProxyFor(UIBarButtonItem *item) {
    UIView *custom = item.customView;
    if (!custom) return nil;
    UIBarButtonItem *proxy = objc_getAssociatedObject(item, PLXProxyKey);
    if (proxy) return proxy;
    if ([NSStringFromClass(custom.class) isEqualToString:@"PMHamburgerMenuBarButtonItemView"]) {
        proxy = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"] style:UIBarButtonItemStylePlain target:nil action:nil];
        // Plex's side menu button is a plain view with a tap gesture whose
        // handler (pm_handleAction:) opens the menu; the stand-in runs it.
        __weak UIView *weakCustom = custom;
        proxy.primaryAction = [UIAction actionWithTitle:@"Menu" image:[UIImage systemImageNamed:@"line.3.horizontal"] identifier:nil handler:^(UIAction *a) {
            UIView *view = weakCustom;
            // The handler finds the side menu through the view's responder
            // chain, so the original view must stay in the window, invisibly.
            if (!view.window) {
                UIView *host = a.sender ? nil : nil;
                for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                    for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) host = w.rootViewController.view;
                }
                view.alpha = 0;
                view.userInteractionEnabled = NO;
                view.frame = CGRectMake(0, 0, 1, 1);
                [host addSubview:view];
            }
            for (UIGestureRecognizer *g in view.gestureRecognizers) {
                if (![g isKindOfClass:UITapGestureRecognizer.class]) continue;
                // Recognizing the tap makes UIKit deliver it to Plex's handler as a real tap would.
                g.enabled = YES;
                g.state = UIGestureRecognizerStateRecognized;
                return;
            }
        }];
    } else {
        UIControl *control = PLXFirstControl(custom);
        if (!control) return nil;
        __weak UIControl *weakControl = control;
        NSString *label = control.accessibilityLabel ?: @"";
        // Plex's back button on some screens (More) is a chevron plus the word
        // "Back"; a snapshot of both overflows the vertical bar's round button,
        // so it gets the system's back chevron, like other back buttons there.
        UIImage *icon = nil;
        if ([control isKindOfClass:UIButton.class] && ((UIButton *)control).currentTitle.length && ((UIButton *)control).currentImage) {
            icon = [UIImage systemImageNamed:@"chevron.backward"];
            if (!label.length) label = ((UIButton *)control).currentTitle;
        } else {
            icon = PLXSnapshotIcon(control);
        }
        proxy = [[UIBarButtonItem alloc] initWithImage:icon style:UIBarButtonItemStylePlain target:nil action:nil];
        proxy.primaryAction = [UIAction actionWithTitle:label image:icon identifier:nil handler:^(UIAction *a) {
            [weakControl sendActionsForControlEvents:UIControlEventTouchUpInside];
        }];
    }
    proxy.accessibilityLabel = custom.accessibilityLabel ?: proxy.primaryAction.title;
    objc_setAssociatedObject(item, PLXProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return proxy;
}

static NSArray<UIBarButtonItem *> *PLXProxies(NSArray<UIBarButtonItem *> *items, BOOL *changed) {
    NSMutableArray *result = [NSMutableArray array];
    for (UIBarButtonItem *item in items) {
        UIBarButtonItem *proxy = PLXProxyFor(item);
        if (proxy) *changed = YES;
        [result addObject:proxy ?: item];
    }
    return result;
}

static NSString *PLXMenuTitle(UIBarButtonItem *original, UIBarButtonItem *proxy, NSUInteger index, NSUInteger count) {
    NSString *title = proxy.primaryAction.title;
    if (title.length) return title;
    UIControl *control = PLXFirstControl(original.customView);
    if ([NSStringFromClass(control.class) containsString:@"Cast"]) return @"Cast";
    // Plex orders its buttons cast, search, more.
    if (index == count - 1 && count >= 3) return @"More";
    return @"Search";
}

static const void *PLXOverflowKey = &PLXOverflowKey;
static const void *PLXOverflowStateKey = &PLXOverflowStateKey;

// The folded screen's vertical bar has room for about two buttons above the
// tabs, so several of Plex's right-hand buttons collapse into one menu, the
// overflow pattern Apple uses for the vertical bar. librarySection, when
// given, is listed first in that menu. The menu button is reused so the
// navigation item's buttons only change when their content does.
static NSArray<UIBarButtonItem *> *PLXRightItems(UINavigationItem *navItem, NSArray<UIBarButtonItem *> *items, BOOL *changed, UIBarButtonItem *librarySection) {
    NSArray *proxies = PLXProxies(items, changed);
    if (!librarySection && (!*changed || proxies.count < 2)) return proxies;
    *changed = YES;
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    NSMutableString *state = [NSMutableString string];
    if (librarySection.menu) {
        [actions addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:librarySection.menu.children]];
        [state appendFormat:@"library=%@;", librarySection.title];
    }
    [proxies enumerateObjectsUsingBlock:^(UIBarButtonItem *proxy, NSUInteger i, BOOL *stop) {
        UIAction *original = proxy.primaryAction;
        if (!original) return;
        NSString *title = PLXMenuTitle(items[i], proxy, i, proxies.count);
        // Snapshots of Plex's glyphs render poorly at menu size; use system symbols where the meaning is clear.
        UIImage *image = original.image;
        NSString *lower = title.lowercaseString;
        if ([lower containsString:@"search"]) image = [UIImage systemImageNamed:@"magnifyingglass"];
        else if (![lower containsString:@"player"] && ![lower containsString:@"cast"]) image = [UIImage systemImageNamed:@"ellipsis.circle"];
        [actions addObject:[UIAction actionWithTitle:title image:image identifier:nil handler:^(UIAction *a) {
            [original performWithSender:nil target:nil];
        }]];
        [state appendFormat:@"%p;", original];
    }];
    UIBarButtonItem *overflow = objc_getAssociatedObject(navItem, PLXOverflowKey);
    if (!overflow) {
        overflow = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis"] menu:nil];
        overflow.accessibilityLabel = @"More";
        objc_setAssociatedObject(navItem, PLXOverflowKey, overflow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![objc_getAssociatedObject(overflow, PLXOverflowStateKey) isEqualToString:state]) {
        objc_setAssociatedObject(overflow, PLXOverflowStateKey, state, OBJC_ASSOCIATION_COPY_NONATOMIC);
        overflow.menu = [UIMenu menuWithChildren:actions];
    }
    return @[overflow];
}

// Top of the first button in the vertical bar, in window coordinates, or
// CGFLOAT_MAX before the bar has buttons. The system draws them as glass
// views inside the navigation controller's floating bar container.
static CGFloat PLXFirstBarButtonTop(UIView *view, UIWindow *window, BOOL inFloatingBar) {
    if (view.hidden) return CGFLOAT_MAX;
    // The title's glass in the horizontal navigation bar is the same kind of view; only the floating bar counts.
    inFloatingBar = inFloatingBar || [NSStringFromClass(view.class) containsString:@"FloatingBarContainer"];
    if (inFloatingBar && [NSStringFromClass(view.class) containsString:@"GlassInteractionView"] && CGRectGetHeight(view.bounds) > 0) {
        return [view convertRect:view.bounds toView:window].origin.y;
    }
    CGFloat top = CGFLOAT_MAX;
    for (UIView *sub in view.subviews) top = MIN(top, PLXFirstBarButtonTop(sub, window, inFloatingBar));
    return top;
}

// Plex's title (a label in a custom view) gets an iOS 26 glass bubble sized
// for a button; it reads better as plain text.
static BOOL PLXHasLabelOnly(UIView *view) {
    if (!view || PLXFirstControl(view)) return NO;
    if ([view isKindOfClass:UILabel.class]) return YES;
    for (UIView *sub in view.subviews) if (PLXHasLabelOnly(sub)) return YES;
    return NO;
}

static void PLXSetTitleBackgroundHidden(NSArray<UIBarButtonItem *> *items, BOOL hidden) {
    if (@available(iOS 26.0, *)) {
        for (UIBarButtonItem *item in items) {
            if (PLXHasLabelOnly(item.customView) && item.hidesSharedBackground != hidden) item.hidesSharedBackground = hidden;
        }
    }
}

// verticalBar: the vertical bar is showing. useProxies: Plex's buttons are
// replaced by standard ones there (a setting).
// Spacing between the vertical bar's buttons (48 pt glass buttons, 12 pt apart).
static const CGFloat PLXBarButtonPitch = 60.0;

static void PLXApplyToItem(UINavigationItem *navItem, BOOL verticalBar, BOOL useProxies, UINavigationBar *bar) {
    if (PLXApplying || !navItem) return;
    PLXApplying = YES;
    // Plex's title label keeps padding meant for the pre-iOS 26 bar, so inside
    // a glass bubble it sat off-center; it is plain text in every layout.
    PLXSetTitleBackgroundHidden(navItem.leftBarButtonItems, YES);
    PLXSetTitleBackgroundHidden(objc_getAssociatedObject(navItem, PLXOriginalLeftKey), YES);
    NSArray *originalLeft = objc_getAssociatedObject(navItem, PLXOriginalLeftKey);
    NSArray *originalRight = objc_getAssociatedObject(navItem, PLXOriginalRightKey);
    if (useProxies) {
        // Plex may set new items at any time; treat anything that is not one of our proxies as Plex's current items.
        NSArray *left = navItem.leftBarButtonItems;
        BOOL leftIsOurs = left.count && [left.firstObject isEqual:objc_getAssociatedObject(originalLeft.firstObject, PLXProxyKey)];
        if (!leftIsOurs) {
            BOOL changed = NO;
            NSArray *proxies = PLXProxies(left, &changed);
            if (changed) {
                objc_setAssociatedObject(navItem, PLXOriginalLeftKey, left, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                navItem.leftBarButtonItems = proxies;
            }
        }
    } else if (originalLeft) {
        navItem.leftBarButtonItems = originalLeft;
        objc_setAssociatedObject(navItem, PLXOriginalLeftKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // Right side: Plex's items (or their overflow menu), then the library tabs button.
    NSArray *right = navItem.rightBarButtonItems ?: @[];
    NSArray *applied = objc_getAssociatedObject(navItem, PLXProxyKey);
    BOOL rightIsOurs = applied && [right isEqualToArray:applied];
    NSArray *plexRight = rightIsOurs ? originalRight : right;
    // Non-nil only while Plex Reborn hides the library's own bar: beside the
    // vertical bar, or at the bottom edge when the user's own tabs replace it.
    UIBarButtonItem *libraryTabs = PLXLibraryTabsItemForNavigationItem(navItem);
    BOOL remeasure = NO;
    NSArray *base = plexRight;
    if (useProxies) {
        BOOL changed = NO;
        base = PLXRightItems(navItem, plexRight, &changed, nil);
        // The navigation bar's buttons and the tabs share the vertical bar but
        // come from different containers, so the system cannot make room. When
        // the library tabs button would run into the tabs, its menu joins the overflow menu.
        UIWindow *window = bar.window;
        CGFloat firstTop = PLXFirstBarButtonTop(bar.superview, window, NO);
        NSUInteger count = navItem.leftBarButtonItems.count + base.count + (libraryTabs ? 1 : 0);
        CGFloat tabsTop = PLXVerticalTabsTop(window);
        if (libraryTabs && (firstTop == CGFLOAT_MAX || tabsTop == CGFLOAT_MAX)) remeasure = YES;
        if (libraryTabs && firstTop < CGFLOAT_MAX && firstTop + count * PLXBarButtonPitch > tabsTop) {
            base = PLXRightItems(navItem, plexRight, &changed, libraryTabs);
            libraryTabs = nil;
        }
    }
    NSArray *final = libraryTabs ? [base arrayByAddingObject:libraryTabs] : base;
    // The system places the vertical bar's buttons and animates the tabs after
    // this pass, so a measurement taken now can be missing or mid-animation.
    // Measure again shortly after any change; this settles once nothing changes.
    if (![final isEqualToArray:right]) remeasure = YES;
    if (remeasure && bar) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [bar setNeedsLayout]; });
    }
    if (![final isEqualToArray:plexRight]) {
        if (![final isEqualToArray:right]) {
            objc_setAssociatedObject(navItem, PLXOriginalRightKey, plexRight, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(navItem, PLXProxyKey, final, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            navItem.rightBarButtonItems = final;
        }
    } else if (rightIsOurs) {
        navItem.rightBarButtonItems = plexRight;
        objc_setAssociatedObject(navItem, PLXOriginalRightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(navItem, PLXProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    PLXApplying = NO;
}

static IMP PLXOrigNavBarLayout;

static void PLXNavBarLayoutSubviews(UINavigationBar *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigNavBarLayout)(self, _cmd);
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = self.window ? self.window.traitCollection.verticalBarEdge : 0;
    BOOL use = edge != 0 && PLXSettingBool(PLXSettingBarButtonsInVerticalBar);
    UINavigationItem *top = self.topItem;
    __weak UINavigationBar *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ PLXApplyToItem(top, edge != 0, use, weakSelf); });
}

// A pushed screen's item only becomes the bar's top item when the push
// animation ends, so Plex's own buttons showed in the title bar while the
// screen slid in. Load the screen (Plex sets its buttons when the view loads)
// and move its buttons before the push starts.
static IMP PLXOrigPushForButtons;

static void PLXPushMovingButtons(UINavigationController *self, SEL _cmd, UIViewController *controller, BOOL animated) {
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = self.view.window ? self.view.window.traitCollection.verticalBarEdge : 0;
    if (controller && edge != 0 && PLXSettingBool(PLXSettingBarButtonsInVerticalBar)) {
        [controller loadViewIfNeeded];
        PLXApplyToItem(controller.navigationItem, YES, YES, self.navigationBar);
    }
    ((void (*)(id, SEL, id, BOOL))PLXOrigPushForButtons)(self, _cmd, controller, animated);
}

__attribute__((constructor)) static void PLXInstallBarButtonProxies(void) {
    Method layout = class_getInstanceMethod(UINavigationBar.class, @selector(layoutSubviews));
    PLXOrigNavBarLayout = method_setImplementation(layout, (IMP)PLXNavBarLayoutSubviews);
    Method push = class_getInstanceMethod(UINavigationController.class, @selector(pushViewController:animated:));
    PLXOrigPushForButtons = method_setImplementation(push, (IMP)PLXPushMovingButtons);
}
