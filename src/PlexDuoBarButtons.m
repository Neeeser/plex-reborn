// Plex's top bar buttons in the Duo's vertical bar.
//
// iOS 27.1 moves a navigation bar's standard buttons into the Duo's vertical
// bar, where they are easy to reach and the top bar's height goes back to the
// content. Plex builds its buttons (side menu, cast, search, more) as custom
// views, which iOS leaves in the top bar. While the vertical bar shows, each
// of those items is replaced by a standard button with the same icon that
// triggers Plex's own control. Without a vertical bar Plex's own items are restored.
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
        proxy = [[UIBarButtonItem alloc] initWithImage:PLXSnapshotIcon(control) style:UIBarButtonItemStylePlain target:nil action:nil];
        proxy.primaryAction = [UIAction actionWithTitle:label image:PLXSnapshotIcon(control) identifier:nil handler:^(UIAction *a) {
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

// The folded screen's vertical bar has room for about two buttons above the
// tabs, so several of Plex's right-hand buttons collapse into one menu, the
// overflow pattern Apple uses for the vertical bar.
static NSArray<UIBarButtonItem *> *PLXRightItems(NSArray<UIBarButtonItem *> *items, BOOL *changed) {
    NSArray *proxies = PLXProxies(items, changed);
    if (!*changed || proxies.count < 2) return proxies;
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
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
    }];
    UIBarButtonItem *overflow = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis"] menu:[UIMenu menuWithChildren:actions]];
    overflow.accessibilityLabel = @"More";
    return @[overflow];
}

// Plex's title (a label in a custom view) gets an iOS 26 glass bubble sized
// for a button; while the buttons are in the vertical bar it reads better as
// plain text.
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

static void PLXApplyToItem(UINavigationItem *navItem, BOOL useProxies) {
    if (PLXApplying || !navItem) return;
    PLXApplying = YES;
    PLXSetTitleBackgroundHidden(navItem.leftBarButtonItems, useProxies);
    PLXSetTitleBackgroundHidden(objc_getAssociatedObject(navItem, PLXOriginalLeftKey), useProxies);
    NSArray *originalLeft = objc_getAssociatedObject(navItem, PLXOriginalLeftKey);
    NSArray *originalRight = objc_getAssociatedObject(navItem, PLXOriginalRightKey);
    if (useProxies) {
        // Plex may set new items at any time; treat anything that is not one of our proxies as Plex's current items.
        NSArray *left = navItem.leftBarButtonItems, *right = navItem.rightBarButtonItems;
        BOOL leftIsOurs = left.count && [left.firstObject isEqual:objc_getAssociatedObject(originalLeft.firstObject, PLXProxyKey)];
        BOOL rightIsOurs = right.count && [right isEqualToArray:objc_getAssociatedObject(navItem, PLXProxyKey) ?: @[]];
        if (!leftIsOurs) {
            BOOL changed = NO;
            NSArray *proxies = PLXProxies(left, &changed);
            if (changed) {
                objc_setAssociatedObject(navItem, PLXOriginalLeftKey, left, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                navItem.leftBarButtonItems = proxies;
            }
        }
        if (!rightIsOurs) {
            BOOL changed = NO;
            NSArray *proxies = PLXRightItems(right, &changed);
            if (changed) {
                objc_setAssociatedObject(navItem, PLXOriginalRightKey, right, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(navItem, PLXProxyKey, proxies, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                navItem.rightBarButtonItems = proxies;
            }
        }
    } else {
        if (originalLeft) { navItem.leftBarButtonItems = originalLeft; objc_setAssociatedObject(navItem, PLXOriginalLeftKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        if (originalRight) { navItem.rightBarButtonItems = originalRight; objc_setAssociatedObject(navItem, PLXOriginalRightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
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
    dispatch_async(dispatch_get_main_queue(), ^{ PLXApplyToItem(top, use); });
}

__attribute__((constructor)) static void PLXInstallBarButtonProxies(void) {
    Method layout = class_getInstanceMethod(UINavigationBar.class, @selector(layoutSubviews));
    PLXOrigNavBarLayout = method_setImplementation(layout, (IMP)PLXNavBarLayoutSubviews);
}
