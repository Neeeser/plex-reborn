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

static const void *PLXGuideSafePinKey = &PLXGuideSafePinKey;
static const void *PLXGuideEdgePinKey = &PLXGuideEdgePinKey;

static void PLXUpdateGuideEdge(UIViewController *controller) {
    UIView *view = controller.viewIfLoaded;
    if (!view.window) return;
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = view.window.traitCollection.verticalBarEdge;
    BOOL rightToLeft = view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL barOnRight = (edge == 2) != rightToLeft;
    BOOL under = edge != 0 && PLXSettingBool(PLXSettingRowsUnderBar);

    NSLayoutConstraint *safePin = objc_getAssociatedObject(view, PLXGuideSafePinKey);
    NSLayoutConstraint *edgePin = objc_getAssociatedObject(view, PLXGuideEdgePinKey);
    if (!safePin) {
        // Plex's pin of the stack's bar-side edge to the safe area.
        NSLayoutAttribute side = barOnRight ? NSLayoutAttributeRight : NSLayoutAttributeLeft;
        for (NSLayoutConstraint *c in view.constraints) {
            if (c.secondItem != view.safeAreaLayoutGuide || ![c.firstItem isKindOfClass:UIStackView.class]) continue;
            if (c.firstAttribute != side || c.secondAttribute != side) continue;
            safePin = c;
            break;
        }
        if (!safePin) return;
        UIStackView *stack = safePin.firstItem;
        NSLayoutXAxisAnchor *stackAnchor = barOnRight ? stack.rightAnchor : stack.leftAnchor;
        NSLayoutXAxisAnchor *viewAnchor = barOnRight ? view.rightAnchor : view.leftAnchor;
        edgePin = [stackAnchor constraintEqualToAnchor:viewAnchor];
        objc_setAssociatedObject(view, PLXGuideSafePinKey, safePin, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, PLXGuideEdgePinKey, edgePin, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (edgePin.active == under) return;
    if (under) {
        safePin.active = NO;
        edgePin.active = YES;
    } else {
        edgePin.active = NO;
        safePin.active = YES;
    }
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
