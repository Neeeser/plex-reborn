// Mini player (the now-playing bar above the bottom edge) on the Duo.
//
// Plex pins the mini player's content to the safe area. With the Duo's
// vertical bar showing, the safe area loses 84 pt on the bar's edge and the
// home-indicator inset at the bottom, so the 48 pt row sits in the top-left
// of an 82 pt bar with an empty strip beside it, although the vertical bar has
// nothing at that height. While the vertical bar shows, Plex's safe-area pins
// are moved to a guide that runs to 12 pt from the bar's edge and centers the
// row vertically in the bar. Without a vertical bar the guide equals the safe area.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PlexReborn.h"

static const CGFloat PLXMiniPlayerEdgeMargin = 12.0;

@interface PLXMiniPlayerGuide : NSObject
@property (nonatomic, strong) UILayoutGuide *guide;
@property (nonatomic, strong) NSLayoutConstraint *top, *bottom, *leading, *trailing;
@end
@implementation PLXMiniPlayerGuide
@end

static const void *PLXMiniPlayerGuideKey = &PLXMiniPlayerGuideKey;

// Replaces constraints between the view's content and its safe-area guide with
// the same constraints against a guide this file controls.
static PLXMiniPlayerGuide *PLXInstallMiniPlayerGuide(UIView *view) {
    PLXMiniPlayerGuide *state = objc_getAssociatedObject(view, PLXMiniPlayerGuideKey);
    if (state) return state;
    UILayoutGuide *safe = view.safeAreaLayoutGuide;
    NSMutableArray<NSLayoutConstraint *> *old = [NSMutableArray array], *replacements = [NSMutableArray array];
    for (NSLayoutConstraint *c in view.constraints) {
        BOOL firstIsSafe = c.firstItem == safe, secondIsSafe = c.secondItem == safe;
        if (firstIsSafe == secondIsSafe) continue;
        id other = firstIsSafe ? c.secondItem : c.firstItem;
        if (other == view || other == nil) continue; // UIKit's own definition of the safe area
        [old addObject:c];
    }
    if (old.count == 0) return nil;

    state = [PLXMiniPlayerGuide new];
    state.guide = [UILayoutGuide new];
    state.guide.identifier = @"PLXMiniPlayerGuide";
    [view addLayoutGuide:state.guide];
    state.top = [state.guide.topAnchor constraintEqualToAnchor:view.topAnchor];
    state.bottom = [view.bottomAnchor constraintEqualToAnchor:state.guide.bottomAnchor];
    state.leading = [state.guide.leftAnchor constraintEqualToAnchor:view.leftAnchor];
    state.trailing = [view.rightAnchor constraintEqualToAnchor:state.guide.rightAnchor];

    for (NSLayoutConstraint *c in old) {
        id first = c.firstItem == safe ? state.guide : c.firstItem;
        id second = c.secondItem == safe ? state.guide : c.secondItem;
        NSLayoutConstraint *n = [NSLayoutConstraint constraintWithItem:first attribute:c.firstAttribute relatedBy:c.relation
            toItem:second attribute:c.secondAttribute multiplier:c.multiplier constant:c.constant];
        n.priority = c.priority;
        n.identifier = c.identifier;
        [replacements addObject:n];
    }
    [NSLayoutConstraint deactivateConstraints:old];
    [NSLayoutConstraint activateConstraints:replacements];
    [NSLayoutConstraint activateConstraints:@[state.top, state.bottom, state.leading, state.trailing]];
    objc_setAssociatedObject(view, PLXMiniPlayerGuideKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return state;
}

static void PLXSetConstant(NSLayoutConstraint *c, CGFloat value) {
    if (fabs(c.constant - value) > 0.5) c.constant = value;
}

static void PLXUpdateMiniPlayerGuide(UIView *view) {
    PLXMiniPlayerGuide *state = PLXInstallMiniPlayerGuide(view);
    if (!state) return;
    UIEdgeInsets safe = view.safeAreaInsets;
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = view.window ? view.window.traitCollection.verticalBarEdge : 0;
    if (edge == 0 || !PLXSettingBool(PLXSettingFullWidthMiniPlayer)) {
        PLXSetConstant(state.top, safe.top);
        PLXSetConstant(state.bottom, safe.bottom);
        PLXSetConstant(state.leading, safe.left);
        PLXSetConstant(state.trailing, safe.right);
        return;
    }
    BOOL rightToLeft = view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL barOnRight = (edge == 2) != rightToLeft;
    PLXSetConstant(state.leading, barOnRight ? safe.left : PLXMiniPlayerEdgeMargin);
    PLXSetConstant(state.trailing, barOnRight ? PLXMiniPlayerEdgeMargin : safe.right);
    // Keep the row's height (bar height minus the safe insets) and center it.
    CGFloat rowHeight = CGRectGetHeight(view.bounds) - safe.top - safe.bottom;
    CGFloat margin = MAX(0, (CGRectGetHeight(view.bounds) - rowHeight) / 2);
    PLXSetConstant(state.top, margin);
    PLXSetConstant(state.bottom, margin);
}

static IMP PLXOrigMiniPlayerLayout;

static void PLXMiniPlayerLayoutSubviews(UIView *self, SEL _cmd) {
    PLXUpdateMiniPlayerGuide(self);
    ((void (*)(id, SEL))PLXOrigMiniPlayerLayout)(self, _cmd);
}

static BOOL PLXInstallMiniPlayerFix(void) {
    static BOOL installed;
    if (installed) return YES;
    Class miniPlayer = NSClassFromString(@"PMMiniPlayerView");
    if (!miniPlayer) return NO;
    installed = YES;
    Method layout = class_getInstanceMethod(miniPlayer, @selector(layoutSubviews));
    if (class_addMethod(miniPlayer, @selector(layoutSubviews), (IMP)PLXMiniPlayerLayoutSubviews, method_getTypeEncoding(layout))) {
        PLXOrigMiniPlayerLayout = method_getImplementation(class_getInstanceMethod([miniPlayer superclass], @selector(layoutSubviews)));
    } else {
        PLXOrigMiniPlayerLayout = method_setImplementation(layout, (IMP)PLXMiniPlayerLayoutSubviews);
    }
    return YES;
}

__attribute__((constructor)) static void PLXInstallMiniPlayerFixAtLaunch(void) {
    if (PLXInstallMiniPlayerFix()) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { PLXInstallMiniPlayerFix(); }];
}
