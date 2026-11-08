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

static void PLXApplyTitleBar(UINavigationItem *item, BOOL on) {
    if (@available(iOS 27.0, *)) {
        PLXTitleBarState *state = objc_getAssociatedObject(item, PLXTitleBarStateKey);
        if (!on) {
            if (!state) return;
            item.standardAppearance = state.standard;
            item.scrollEdgeAppearance = state.scrollEdge;
            item.compactAppearance = state.compact;
            item.compactScrollEdgeAppearance = state.compactScrollEdge;
            if (state.minimization) item.navigationBarMinimization = state.minimization;
            objc_setAssociatedObject(item, PLXTitleBarStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
        // Some screens (a movie's page) set their own appearance after they
        // appear; whatever Plex sets last is kept for restoring, and the clear
        // appearance goes back on.
        if (item.standardAppearance != state.clear) { state.standard = item.standardAppearance; item.standardAppearance = state.clear; }
        if (item.scrollEdgeAppearance != state.clear) { state.scrollEdge = item.scrollEdgeAppearance; item.scrollEdgeAppearance = state.clear; }
        if (item.compactAppearance != state.clear) { state.compact = item.compactAppearance; item.compactAppearance = state.clear; }
        if (item.compactScrollEdgeAppearance != state.clear) { state.compactScrollEdge = item.compactScrollEdgeAppearance; item.compactScrollEdgeAppearance = state.clear; }
    }
}

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

static IMP PLXOrigTitleBarLayout;

static void PLXTitleBarLayoutSubviews(UINavigationBar *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigTitleBarLayout)(self, _cmd);
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = self.window ? self.window.traitCollection.verticalBarEdge : 0;
    BOOL on = edge != 0 && PLXSettingBool(PLXSettingClearTitleBar);
    UINavigationItem *top = self.topItem;
    UIViewController *controller = [self.delegate isKindOfClass:UINavigationController.class] ? ((UINavigationController *)self.delegate).topViewController : nil;
    if (top) dispatch_async(dispatch_get_main_queue(), ^{
        PLXApplyTitleBar(top, on);
        PLXSetSoftTopEdge(controller, on);
    });
}

__attribute__((constructor)) static void PLXInstallTitleBar(void) {
    Method layout = class_getInstanceMethod(UINavigationBar.class, @selector(layoutSubviews));
    PLXOrigTitleBarLayout = method_setImplementation(layout, (IMP)PLXTitleBarLayoutSubviews);
}
