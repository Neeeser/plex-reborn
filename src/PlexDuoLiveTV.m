// Live TV guide runs under the Duo's vertical bar.
//
// Plex pins the guide (its source tabs and the program grid, in one stack
// view) to the screen's safe area, so with the vertical bar showing the grid
// stops 84 pt short of the screen edge and the bar's column is empty. Like the
// poster rows (PlexDuoContentUnderBar.m, same setting), the stack now runs to
// the screen edge on the bar's side; the stack still has the bar as its safe
// area, so the grid's own content inset lets its last column scroll clear of
// the bar.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PlexReborn.h"

static const void *PLXGuideEdgePinKey = &PLXGuideEdgePinKey;
static const void *PLXGuideSafePinsKey = &PLXGuideSafePinsKey;

// Plex may rebuild the guide's constraints after it first appears (on a
// layout change such as the title bar moving its content up), adding a fresh
// pin to the safe area that beat the edge pin and left the grid 84 pt short.
// So every layout looks again for any active safe-area pin on the bar's side.
static void PLXUpdateGuideEdge(UIViewController *controller) {
    UIView *view = controller.viewIfLoaded;
    if (!view.window) return;
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = view.window.traitCollection.verticalBarEdge;
    BOOL rightToLeft = view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL barOnRight = (edge == 2) != rightToLeft;
    BOOL under = edge != 0 && PLXSettingBool(PLXSettingRowsUnderBar);
    NSLayoutAttribute side = barOnRight ? NSLayoutAttributeRight : NSLayoutAttributeLeft;

    NSMutableArray<NSLayoutConstraint *> *saved = objc_getAssociatedObject(view, PLXGuideSafePinsKey);
    NSLayoutConstraint *edgePin = objc_getAssociatedObject(view, PLXGuideEdgePinKey);
    if (!under) {
        if (edgePin.active) edgePin.active = NO;
        for (NSLayoutConstraint *c in saved) if (!c.active && c.firstItem) c.active = YES;
        [saved removeAllObjects];
        return;
    }
    // Plex's pin of the stack's bar-side edge to the safe area.
    UIStackView *stack = nil;
    for (NSLayoutConstraint *c in view.constraints) {
        if (!c.active || c.secondItem != view.safeAreaLayoutGuide || ![c.firstItem isKindOfClass:UIStackView.class]) continue;
        if (c.firstAttribute != side || c.secondAttribute != side) continue;
        stack = c.firstItem;
        c.active = NO;
        if (!saved) { saved = [NSMutableArray array]; objc_setAssociatedObject(view, PLXGuideSafePinsKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        [saved addObject:c];
    }
    if (!stack) stack = edgePin.firstItem;
    if (!stack || stack.superview != view) return;
    NSLayoutXAxisAnchor *viewAnchor = barOnRight ? view.rightAnchor : view.leftAnchor;
    if (edgePin.firstItem != stack || edgePin.secondAttribute != side) {
        edgePin.active = NO;
        edgePin = [(barOnRight ? stack.rightAnchor : stack.leftAnchor) constraintEqualToAnchor:viewAnchor];
        objc_setAssociatedObject(view, PLXGuideEdgePinKey, edgePin, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!edgePin.active) edgePin.active = YES;
}

static IMP PLXOrigGuideLayout;

static void PLXGuideViewDidLayoutSubviews(UIViewController *self, SEL _cmd) {
    if (PLXOrigGuideLayout) ((void (*)(id, SEL))PLXOrigGuideLayout)(self, _cmd);
    PLXUpdateGuideEdge(self);
}

static BOOL PLXInstallLiveTVGuideIfPossible(void) {
    static BOOL installed;
    if (installed) return YES;
    Class guide = NSClassFromString(@"PMProgramGuideViewController");
    if (!guide) return NO;
    installed = YES;
    SEL selector = @selector(viewDidLayoutSubviews);
    Method method = class_getInstanceMethod(guide, selector);
    // Add an override on the class itself so UIViewController's implementation is never replaced.
    if (class_addMethod(guide, selector, (IMP)PLXGuideViewDidLayoutSubviews, method_getTypeEncoding(method))) {
        PLXOrigGuideLayout = method_getImplementation(class_getInstanceMethod([guide superclass], selector));
    } else {
        PLXOrigGuideLayout = method_setImplementation(method, (IMP)PLXGuideViewDidLayoutSubviews);
    }
    return YES;
}

__attribute__((constructor)) static void PLXInstallLiveTVGuide(void) {
    if (PLXInstallLiveTVGuideIfPossible()) return;
    // Plex's classes may register after this library's constructor; retry at launch.
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { PLXInstallLiveTVGuideIfPossible(); }];
}
