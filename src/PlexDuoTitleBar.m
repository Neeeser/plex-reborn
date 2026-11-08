// Plex's title bar on the Duo.
//
// Plex gives its navigation bar an opaque gray background, so on the folded
// screen the title takes a fixed band at the top while the screen is short and
// wide. While the vertical bar shows, the title bar gets a clear background,
// so content scrolls up under it with the system's scroll edge effect behind
// the title, and it hides while scrolling down and comes back on scrolling
// up (UIKit's bar minimization, iOS 27). Plex's own settings return when the
// vertical bar goes away or the setting is off.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PlexReborn.h"

static const void *PLXTitleBarStateKey = &PLXTitleBarStateKey;

@interface PLXTitleBarState : NSObject
@property (nonatomic, strong) UINavigationBarAppearance *standard, *scrollEdge, *compact, *compactScrollEdge;
@property (nonatomic, strong) id minimization;
@property (nonatomic, strong) UINavigationBarAppearance *clear;
@end
@implementation PLXTitleBarState
@end

static IMP PLXOrigSetStandard, PLXOrigSetScrollEdge, PLXOrigSetCompact, PLXOrigSetCompactScrollEdge;

static void PLXSetAppearance(UINavigationItem *item, IMP setter, SEL selector, UINavigationBarAppearance *value) {
    ((void (*)(id, SEL, id))setter)(item, selector, value);
}

static void PLXApplyTitleBar(UINavigationItem *item, BOOL on) {
    if (@available(iOS 27.0, *)) {
        PLXTitleBarState *state = objc_getAssociatedObject(item, PLXTitleBarStateKey);
        if (!on) {
            if (!state) return;
            // Clear the state first so the setters below are not intercepted.
            objc_setAssociatedObject(item, PLXTitleBarStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            item.standardAppearance = state.standard;
            item.scrollEdgeAppearance = state.scrollEdge;
            item.compactAppearance = state.compact;
            item.compactScrollEdgeAppearance = state.compactScrollEdge;
            if (state.minimization) item.navigationBarMinimization = state.minimization;
            return;
        }
        if (!state) {
            state = [PLXTitleBarState new];
            state.clear = [UINavigationBarAppearance new];
            [state.clear configureWithTransparentBackground];
            state.minimization = item.navigationBarMinimization;
            objc_setAssociatedObject(item, PLXTitleBarStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIBarMinimization *minimization = [item.navigationBarMinimization copy] ?: [UIBarMinimization new];
            minimization.minimizationBehavior = UIBarMinimizationBehaviorOnScrollDown;
            item.navigationBarMinimization = minimization;
        }
        // The item's current appearances are Plex's; the setters below keep
        // later ones out while the state exists.
        if (item.standardAppearance != state.clear) { state.standard = item.standardAppearance; PLXSetAppearance(item, PLXOrigSetStandard, @selector(setStandardAppearance:), state.clear); }
        if (item.scrollEdgeAppearance != state.clear) { state.scrollEdge = item.scrollEdgeAppearance; PLXSetAppearance(item, PLXOrigSetScrollEdge, @selector(setScrollEdgeAppearance:), state.clear); }
        if (item.compactAppearance != state.clear) { state.compact = item.compactAppearance; PLXSetAppearance(item, PLXOrigSetCompact, @selector(setCompactAppearance:), state.clear); }
        if (item.compactScrollEdgeAppearance != state.clear) { state.compactScrollEdge = item.compactScrollEdgeAppearance; PLXSetAppearance(item, PLXOrigSetCompactScrollEdge, @selector(setCompactScrollEdgeAppearance:), state.clear); }
    }
}

// Some screens (an episode's page) set a new appearance on every scroll step to
// fade in their bar. Putting the clear appearance back afterwards showed Plex's
// bar for a frame each time, so while the clear title bar is on, Plex's
// appearance is stored for restoring and the clear one stays.
#define PLX_APPEARANCE_SETTER(name, property)                                              \
    static void PLXIntercept##name(UINavigationItem *self, SEL _cmd, UINavigationBarAppearance *value) { \
        PLXTitleBarState *state = objc_getAssociatedObject(self, PLXTitleBarStateKey);       \
        if (state && value != state.clear) { state.property = value; value = state.clear; } \
        ((void (*)(id, SEL, id))PLXOrigSet##name)(self, _cmd, value);                        \
    }
PLX_APPEARANCE_SETTER(Standard, standard)
PLX_APPEARANCE_SETTER(ScrollEdge, scrollEdge)
PLX_APPEARANCE_SETTER(Compact, compact)
PLX_APPEARANCE_SETTER(CompactScrollEdge, compactScrollEdge)

// The screen's main scroll view: the tallest scroll view that scrolls vertically.
static UIScrollView *PLXMainScrollView(UIView *view, UIScrollView *best) {
    if ([view isKindOfClass:UIScrollView.class] && !view.hidden) {
        UIScrollView *scroll = (UIScrollView *)view;
        BOOL vertical = scroll.contentSize.height > CGRectGetHeight(scroll.bounds) || scroll.alwaysBounceVertical || [scroll isKindOfClass:UITableView.class];
        if (vertical && CGRectGetHeight(scroll.bounds) > CGRectGetHeight(best.bounds)) best = scroll;
    }
    for (UIView *sub in view.subviews) best = PLXMainScrollView(sub, best);
    return best;
}

// The system draws a blur behind the clear title bar where content scrolls
// under it; Plex's screens get the hard style, which ends in a visible line.
// The soft style fades out instead.
static void PLXSetSoftTopEdge(UIViewController *controller, BOOL on) {
    if (@available(iOS 26.0, *)) {
        UIScrollView *scroll = PLXMainScrollView(controller.view, nil);
        UIScrollEdgeEffectStyle *style = on ? UIScrollEdgeEffectStyle.softStyle : UIScrollEdgeEffectStyle.automaticStyle;
        if (scroll && scroll.topEdgeEffect.style != style) scroll.topEdgeEffect.style = style;
    }
}

static BOOL PLXClearTitleBarOn(UIWindow *window) {
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = window ? window.traitCollection.verticalBarEdge : 0;
    return edge != 0 && PLXSettingBool(PLXSettingClearTitleBar);
}

static IMP PLXOrigTitleBarLayout;

static void PLXTitleBarLayoutSubviews(UINavigationBar *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigTitleBarLayout)(self, _cmd);
    BOOL on = PLXClearTitleBarOn(self.window);
    UINavigationItem *top = self.topItem;
    UIViewController *controller = [self.delegate isKindOfClass:UINavigationController.class] ? ((UINavigationController *)self.delegate).topViewController : nil;
    if (top) dispatch_async(dispatch_get_main_queue(), ^{
        PLXApplyTitleBar(top, on);
        PLXSetSoftTopEdge(controller, on);
    });
}

// A pushed screen's item only becomes the bar's top item when the push
// animation ends, so the layout hook alone left Plex's gray bar showing while
// the screen slid in. Clear the item before the push starts.
static IMP PLXOrigPush;

static void PLXPush(UINavigationController *self, SEL _cmd, UIViewController *controller, BOOL animated) {
    if (controller && PLXClearTitleBarOn(self.view.window)) PLXApplyTitleBar(controller.navigationItem, YES);
    ((void (*)(id, SEL, id, BOOL))PLXOrigPush)(self, _cmd, controller, animated);
}

__attribute__((constructor)) static void PLXInstallTitleBar(void) {
    Method push = class_getInstanceMethod(UINavigationController.class, @selector(pushViewController:animated:));
    PLXOrigPush = method_setImplementation(push, (IMP)PLXPush);
    Method layout = class_getInstanceMethod(UINavigationBar.class, @selector(layoutSubviews));
    PLXOrigTitleBarLayout = method_setImplementation(layout, (IMP)PLXTitleBarLayoutSubviews);
    Class item = UINavigationItem.class;
    PLXOrigSetStandard = method_setImplementation(class_getInstanceMethod(item, @selector(setStandardAppearance:)), (IMP)PLXInterceptStandard);
    PLXOrigSetScrollEdge = method_setImplementation(class_getInstanceMethod(item, @selector(setScrollEdgeAppearance:)), (IMP)PLXInterceptScrollEdge);
    PLXOrigSetCompact = method_setImplementation(class_getInstanceMethod(item, @selector(setCompactAppearance:)), (IMP)PLXInterceptCompact);
    PLXOrigSetCompactScrollEdge = method_setImplementation(class_getInstanceMethod(item, @selector(setCompactScrollEdgeAppearance:)), (IMP)PLXInterceptCompactScrollEdge);
}
