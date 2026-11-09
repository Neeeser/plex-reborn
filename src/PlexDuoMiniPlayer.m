// Mini player (the now-playing bar above the bottom edge) on the Duo.
//
// The folded screen is short, so the mini player's 82 pt opaque bar costs a
// large share of its height. While the vertical bar shows, the mini player
// takes one of three styles (Plex Reborn settings):
//
// - Floating card (default): a glass card that floats over the content
//   beside the vertical bar's tabs, like the system's own floating bars.
//   Content runs to the bottom edge behind it, screens get bottom padding so
//   their last row scrolls clear of the card, and the tabs run down to the
//   bottom beside it. Plex's container keeps its place, so Plex's own show
//   and hide animation (it slides the container off the bottom edge) still works.
// - Full-width bar: Plex's bar, with the row running to 12 pt from the
//   vertical bar and centered vertically, where Plex pins it to the safe area
//   and leaves the row in the bar's top-left corner.
// - Plex's bar: unchanged.
//
// Without a vertical bar (standard iPhones, and the Duo unfolded in
// portrait), the floating card is a glass capsule just above the tab bar at
// the bottom (or the home indicator when no tab bar shows), the way iOS 26
// apps place their mini players. Full-width bar falls back to Plex's bar there.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PlexReborn.h"

static const CGFloat PLXMiniPlayerEdgeMargin = 12.0;
static const CGFloat PLXCardHeight = 64.0;
static const CGFloat PLXCardInset = 8.0;   // card edge to the row inside it
static const CGFloat PLXCardGap = 8.0;     // card to the vertical bar's strip
static const CGFloat PLXCardCornerRadius = 22.0;

@interface PLXMiniPlayerState : NSObject
@property (nonatomic, strong) UILayoutGuide *guide;
@property (nonatomic, strong) NSLayoutConstraint *top, *bottom, *leading, *trailing;
// Floating card.
@property (nonatomic, assign) BOOL floating;
@property (nonatomic, strong) NSLayoutConstraint *cardHeight;
@property (nonatomic, strong) NSLayoutConstraint *navToContainer, *navToBottom;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *containerPins; // miniPlayer leading, trailing, bottom in its container
@property (nonatomic, strong) NSArray<NSNumber *> *containerPinConstants;
@property (nonatomic, strong) UIVisualEffectView *glass;
@property (nonatomic, strong) UIColor *background;
@property (nonatomic, weak) UIView *tint;
@property (nonatomic, weak) UIViewController *navigationController;
@property (nonatomic, assign) CGFloat addedBottomInset;
@end
@implementation PLXMiniPlayerState
@end

static const void *PLXMiniPlayerStateKey = &PLXMiniPlayerStateKey;

// Replaces constraints between the view's content and its safe-area guide with
// the same constraints against a guide this file controls.
static PLXMiniPlayerState *PLXInstallMiniPlayerGuide(UIView *view) {
    PLXMiniPlayerState *state = objc_getAssociatedObject(view, PLXMiniPlayerStateKey);
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
    // The full-size mini player has no safe-area constraints; it still gets a
    // state so it can float.

    state = [PLXMiniPlayerState new];
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
    objc_setAssociatedObject(view, PLXMiniPlayerStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return state;
}

static void PLXSetConstant(NSLayoutConstraint *c, CGFloat value) {
    if (fabs(c.constant - value) > 0.5) c.constant = value;
}

static NSInteger PLXVerticalBarEdge(UIView *view) {
    if (@available(iOS 27.1, *)) return view.window ? view.window.traitCollection.verticalBarEdge : 0;
    return 0;
}

static BOOL PLXIsFullSizeMiniPlayer(UIView *view) {
    static Class fullSize;
    if (!fullSize) fullSize = NSClassFromString(@"PMMiniPlayerViewFullSize");
    return fullSize && [view isKindOfClass:fullSize];
}

BOOL PLXIsMiniPlayerView(UIView *view) {
    static Class compact;
    if (!compact) compact = NSClassFromString(@"PMMiniPlayerView");
    return (compact && [view isKindOfClass:compact]) || PLXIsFullSizeMiniPlayer(view);
}

#pragma mark - Floating card

// Touches in the container around the card reach the content underneath.
static BOOL PLXContainerPointInside(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    for (UIView *sub in self.subviews) {
        if (!sub.hidden && CGRectContainsPoint(sub.frame, point)) return YES;
    }
    return NO;
}

static void PLXMakeContainerPassThrough(UIView *container, BOOL on) {
    static Class passThrough;
    static Class original;
    if (!passThrough) {
        original = UIView.class;
        passThrough = objc_allocateClassPair(UIView.class, "PLXMiniPlayerContainerView", 0);
        class_addMethod(passThrough, @selector(pointInside:withEvent:), (IMP)PLXContainerPointInside, "B@:{CGPoint=dd}@");
        objc_registerClassPair(passThrough);
    }
    // Plex's container is a plain UIView; only that exact class is swapped.
    if (on && object_getClass(container) == original) object_setClass(container, passThrough);
    else if (!on && object_getClass(container) == passThrough) object_setClass(container, original);
}

// The pins of the mini player inside its container (Plex: leading, trailing and bottom at 0).
static NSArray<NSLayoutConstraint *> *PLXContainerPins(UIView *miniPlayer, UIView *container) {
    NSMutableArray *pins = [NSMutableArray arrayWithObjects:NSNull.null, NSNull.null, NSNull.null, nil];
    for (NSLayoutConstraint *c in container.constraints) {
        if (c.firstItem != miniPlayer && c.secondItem != miniPlayer) continue;
        NSLayoutAttribute attr = c.firstItem == miniPlayer ? c.firstAttribute : c.secondAttribute;
        if (attr == NSLayoutAttributeLeading || attr == NSLayoutAttributeLeft) pins[0] = c;
        else if (attr == NSLayoutAttributeTrailing || attr == NSLayoutAttributeRight) pins[1] = c;
        else if (attr == NSLayoutAttributeBottom) pins[2] = c;
    }
    return [pins containsObject:NSNull.null] ? nil : pins;
}

// Plex's constraint that stops the screens' container at the top of the mini player's container.
static NSLayoutConstraint *PLXContentToMiniPlayer(UIView *container, UIView *root, UIView **content) {
    for (NSLayoutConstraint *c in root.constraints) {
        BOOL forward = c.secondItem == container && c.secondAttribute == NSLayoutAttributeTop && c.firstAttribute == NSLayoutAttributeBottom;
        BOOL backward = c.firstItem == container && c.firstAttribute == NSLayoutAttributeTop && c.secondAttribute == NSLayoutAttributeBottom;
        if (!forward && !backward) continue;
        // Plex hides the mini player with container.top == root.bottom; only a sibling view counts.
        id other = forward ? c.firstItem : c.secondItem;
        if (other == root || ![other isKindOfClass:UIView.class] || ((UIView *)other).superview != root) continue;
        *content = other;
        return c;
    }
    return nil;
}

// Sets a constraint's constant so the mini player sits `inset` points inside its container on that edge.
static void PLXSetPinInset(NSLayoutConstraint *pin, UIView *miniPlayer, CGFloat inset, BOOL leadingEdge) {
    BOOL playerFirst = pin.firstItem == miniPlayer;
    CGFloat value = (playerFirst == leadingEdge) ? inset : -inset;
    PLXSetConstant(pin, value);
}

static void PLXSetAddedBottomInset(PLXMiniPlayerState *state, CGFloat inset) {
    UIViewController *nav = state.navigationController;
    if (!nav || fabs(state.addedBottomInset - inset) < 0.5) return;
    UIEdgeInsets additional = nav.additionalSafeAreaInsets;
    additional.bottom += inset - state.addedBottomInset;
    nav.additionalSafeAreaInsets = additional;
    state.addedBottomInset = inset;
}

static const void *PLXContainerOwnerKey = &PLXContainerOwnerKey;

// Plex swaps the mini player view for the other size's view in the same
// container when the screen's width class changes (PMMiniPlayerView folded,
// PMMiniPlayerViewFullSize unfolded). The old view's floating card had moved
// the screens' bottom constraint, so the new view could not find it and stayed
// Plex's bar. The container remembers which view floats it, and a new view
// first puts back what the old one changed.
static void PLXReleaseContainer(UIView *container, PLXMiniPlayerState *state) {
    PLXMiniPlayerState *owner = objc_getAssociatedObject(container, PLXContainerOwnerKey);
    if (!owner || owner == state || !owner.floating) return;
    [NSLayoutConstraint deactivateConstraints:@[owner.navToBottom]];
    [NSLayoutConstraint activateConstraints:@[owner.navToContainer]];
    PLXSetAddedBottomInset(owner, 0);
    PLXMakeContainerPassThrough(container, NO);
    owner.floating = NO;
    objc_setAssociatedObject(container, PLXContainerOwnerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL PLXStartFloating(UIView *miniPlayer, PLXMiniPlayerState *state) {
    UIView *container = miniPlayer.superview, *root = container.superview;
    if (!container || !root) return NO;
    PLXReleaseContainer(container, state);
    NSArray *pins = PLXContainerPins(miniPlayer, container);
    UIView *content = nil;
    NSLayoutConstraint *contentToPlayer = PLXContentToMiniPlayer(container, root, &content);
    if (!pins || !contentToPlayer || !content) return NO;

    state.containerPins = pins;
    state.containerPinConstants = [pins valueForKey:@"constant"];
    state.navToContainer = contentToPlayer;
    state.navToBottom = [content.bottomAnchor constraintEqualToAnchor:root.bottomAnchor];
    state.navToBottom.priority = contentToPlayer.priority;
    [NSLayoutConstraint deactivateConstraints:@[contentToPlayer]];
    [NSLayoutConstraint activateConstraints:@[state.navToBottom]];
    UIResponder *next = content.nextResponder;
    state.navigationController = [next isKindOfClass:UIViewController.class] ? (UIViewController *)next : nil;

    // The full-size mini player lays its row out for its own 60 pt height.
    if (!PLXIsFullSizeMiniPlayer(miniPlayer)) {
        state.cardHeight = [miniPlayer.heightAnchor constraintEqualToConstant:PLXCardHeight];
        state.cardHeight.active = YES;
    }

    state.background = miniPlayer.backgroundColor;
    miniPlayer.backgroundColor = UIColor.clearColor;
    UIView *tint = miniPlayer.subviews.firstObject;
    if (tint && ![tint isKindOfClass:UIVisualEffectView.class] && !tint.hidden) { state.tint = tint; tint.hidden = YES; }

    if (@available(iOS 26.0, *)) {
        state.glass = [[UIVisualEffectView alloc] initWithEffect:[UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular]];
        state.glass.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:PLXCardCornerRadius]];
    } else {
        state.glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
        state.glass.layer.cornerRadius = PLXCardCornerRadius;
        state.glass.clipsToBounds = YES;
    }
    state.glass.userInteractionEnabled = NO;
    state.glass.frame = miniPlayer.bounds;
    state.glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [miniPlayer insertSubview:state.glass atIndex:0];
    miniPlayer.layer.cornerRadius = PLXCardCornerRadius;
    miniPlayer.layer.cornerCurve = kCACornerCurveContinuous;
    PLXMakeContainerPassThrough(container, YES);
    objc_setAssociatedObject(container, PLXContainerOwnerKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    state.floating = YES;
    return YES;
}

static void PLXStopFloating(UIView *miniPlayer, PLXMiniPlayerState *state) {
    if (!state.floating) return;
    [NSLayoutConstraint deactivateConstraints:@[state.navToBottom]];
    state.cardHeight.active = NO;
    state.cardHeight = nil;
    [NSLayoutConstraint activateConstraints:@[state.navToContainer]];
    [state.containerPins enumerateObjectsUsingBlock:^(NSLayoutConstraint *pin, NSUInteger i, BOOL *stop) {
        pin.constant = state.containerPinConstants[i].doubleValue;
    }];
    PLXSetAddedBottomInset(state, 0);
    [state.glass removeFromSuperview];
    miniPlayer.backgroundColor = state.background;
    state.tint.hidden = NO;
    miniPlayer.layer.cornerRadius = 0;
    PLXMakeContainerPassThrough(miniPlayer.superview, NO);
    if (objc_getAssociatedObject(miniPlayer.superview, PLXContainerOwnerKey) == state)
        objc_setAssociatedObject(miniPlayer.superview, PLXContainerOwnerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    state.floating = NO;
}

static void PLXLayoutFloating(UIView *miniPlayer, PLXMiniPlayerState *state, NSInteger edge) {
    UIView *container = miniPlayer.superview, *root = container.superview;
    UIEdgeInsets safe = root.safeAreaInsets;
    BOOL rightToLeft = miniPlayer.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL barOnRight = (edge == 2) != rightToLeft;
    CGFloat barSide = PLXVerticalBarColumnWidth + PLXCardGap;
    CGFloat left = barOnRight ? MAX(safe.left, PLXMiniPlayerEdgeMargin) : MAX(safe.left + PLXCardGap, barSide);
    CGFloat right = barOnRight ? MAX(safe.right + PLXCardGap, barSide) : MAX(safe.right, PLXMiniPlayerEdgeMargin);
    // The card sits just above the home indicator; the container (Plex's,
    // which hugs the mini player) is the card plus that gap.
    CGFloat bottom = MAX(PLXMiniPlayerEdgeMargin, safe.bottom - 16);
    // Pins are leading, trailing, bottom; leading/trailing follow layout direction.
    PLXSetPinInset(state.containerPins[0], miniPlayer, rightToLeft ? right : left, YES);
    PLXSetPinInset(state.containerPins[1], miniPlayer, rightToLeft ? left : right, NO);
    PLXSetPinInset(state.containerPins[2], miniPlayer, bottom, NO);

    PLXSetConstant(state.top, PLXCardInset);
    PLXSetConstant(state.bottom, PLXCardInset);
    PLXSetConstant(state.leading, PLXCardInset);
    PLXSetConstant(state.trailing, 0);
    // The Duo unfolded in portrait has no vertical bar and uses the capsule's rounder corners.
    if (@available(iOS 26.0, *)) {
        state.glass.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:PLXCardCornerRadius]];
    } else {
        state.glass.layer.cornerRadius = PLXCardCornerRadius;
    }
    miniPlayer.layer.cornerRadius = PLXCardCornerRadius;

    // Padding at the bottom of the screens so their content scrolls clear of the card.
    BOOL shown = !container.hidden && !miniPlayer.hidden && CGRectGetMinY(container.frame) < CGRectGetHeight(root.bounds) - 1;
    CGFloat cardHeight = state.cardHeight ? PLXCardHeight : CGRectGetHeight(miniPlayer.bounds);
    CGFloat cardTopFromBottom = cardHeight + bottom;
    PLXSetAddedBottomInset(state, shown ? MAX(0, cardTopFromBottom + PLXCardGap - safe.bottom) : 0);
}

static void PLXFindMiniPlayers(UIView *view, NSMutableArray<UIView *> *found);

#pragma mark - Without a vertical bar

static BOOL PLXShowsOnScreen(UIView *view) {
    if (!view.window) return NO;
    for (UIView *v = view; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
    }
    return YES;
}

// Top of the tab bar showing along the bottom of `root` (Plex Reborn's own
// tabs, or one of Plex's bars), in root's coordinates; CGFLOAT_MAX when none.
static CGFloat PLXBottomBarTop(UIView *root, UIView *view) {
    if (view.hidden || view.alpha < 0.01) return CGFLOAT_MAX;
    if ([view isKindOfClass:UITabBar.class]) {
        if (!PLXShowsOnScreen(view)) return CGFLOAT_MAX;
        CGRect frame = [view convertRect:view.bounds toView:root];
        return CGRectGetMaxY(frame) >= CGRectGetHeight(root.bounds) - 2 ? CGRectGetMinY(frame) : CGFLOAT_MAX;
    }
    CGFloat top = CGFLOAT_MAX;
    for (UIView *sub in view.subviews) top = MIN(top, PLXBottomBarTop(root, sub));
    return top;
}

static const CGFloat PLXCapsuleSideMargin = 20.0;  // matches the system tab bar's inset
static const CGFloat PLXCapsuleLeadingInset = 14.0; // clears the capsule's rounded end

static void PLXLayoutCapsule(UIView *miniPlayer, PLXMiniPlayerState *state) {
    UIView *container = miniPlayer.superview, *root = container.superview;
    UIEdgeInsets safe = root.safeAreaInsets;
    CGFloat height = CGRectGetHeight(root.bounds);
    // Plex Reborn's own tab bar sits in the window's root screen, outside the mini player's parent.
    CGFloat barTop = root.window ? PLXBottomBarTop(root, root.window) : CGFLOAT_MAX;
    BOOL bar = barTop < height;
    CGFloat bottom = bar ? height - barTop + PLXCardGap : MAX(PLXMiniPlayerEdgeMargin, safe.bottom - 16);
    PLXSetPinInset(state.containerPins[0], miniPlayer, safe.left + PLXCapsuleSideMargin, YES);
    PLXSetPinInset(state.containerPins[1], miniPlayer, safe.right + PLXCapsuleSideMargin, NO);
    PLXSetPinInset(state.containerPins[2], miniPlayer, bottom, NO);

    CGFloat cardHeight = state.cardHeight ? PLXCardHeight : CGRectGetHeight(miniPlayer.bounds);
    CGFloat radius = cardHeight / 2;
    if (@available(iOS 26.0, *)) {
        state.glass.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:radius]];
    } else {
        state.glass.layer.cornerRadius = radius;
    }
    miniPlayer.layer.cornerRadius = radius;
    PLXSetConstant(state.top, PLXCardInset);
    PLXSetConstant(state.bottom, PLXCardInset);
    PLXSetConstant(state.leading, PLXCapsuleLeadingInset);
    PLXSetConstant(state.trailing, 0);

    // Padding so screens scroll clear of the capsule. A tab bar's own height
    // is already padded for (by Plex, or by the tab bar code for Plex
    // Reborn's tabs), so only the capsule and its gaps are added above it.
    BOOL shown = !container.hidden && !miniPlayer.hidden && CGRectGetMinY(container.frame) < height - 1;
    CGFloat inset = bar ? cardHeight + 2 * PLXCardGap : MAX(0, cardHeight + bottom + PLXCardGap - safe.bottom);
    PLXSetAddedBottomInset(state, shown ? inset : 0);
}

void PLXMiniPlayersNeedLayout(UIWindow *window) {
    NSMutableArray<UIView *> *players = [NSMutableArray array];
    PLXFindMiniPlayers(window, players);
    for (UIView *player in players) {
        if (PLXMiniPlayerFloats(player)) [player setNeedsLayout];
    }
}

#pragma mark - Layout

BOOL PLXMiniPlayerFloats(UIView *miniPlayer) {
    PLXMiniPlayerState *state = objc_getAssociatedObject(miniPlayer, PLXMiniPlayerStateKey);
    return state.floating;
}

static void PLXUpdateMiniPlayer(UIView *view) {
    PLXMiniPlayerState *state = PLXInstallMiniPlayerGuide(view);
    if (!state) return;
    NSInteger edge = PLXVerticalBarEdge(view);
    NSInteger style = PLXSettingInteger(PLXSettingMiniPlayerStyle);
    if (edge == 0 && style == PLXMiniPlayerFullWidth) style = PLXMiniPlayerPlex;

    if (style == PLXMiniPlayerFloatingCard && (state.floating || PLXStartFloating(view, state))) {
        if (edge == 0) PLXLayoutCapsule(view, state);
        else PLXLayoutFloating(view, state, edge);
        return;
    }
    PLXStopFloating(view, state);
    UIEdgeInsets safe = view.safeAreaInsets;
    if (style == PLXMiniPlayerPlex) {
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
    PLXUpdateMiniPlayer(self);
    ((void (*)(id, SEL))PLXOrigMiniPlayerLayout)(self, _cmd);
}

static void PLXFindMiniPlayers(UIView *view, NSMutableArray<UIView *> *found) {
    if (PLXIsMiniPlayerView(view)) { [found addObject:view]; return; }
    for (UIView *sub in view.subviews) PLXFindMiniPlayers(sub, found);
}

// Each class gets its own override that calls that class's original layout.
static IMP PLXOrigFullSizeLayout;

static void PLXFullSizeLayoutSubviews(UIView *self, SEL _cmd) {
    PLXUpdateMiniPlayer(self);
    ((void (*)(id, SEL))PLXOrigFullSizeLayout)(self, _cmd);
}

static void PLXHookLayout(Class cls, IMP replacement, IMP *original) {
    Method layout = class_getInstanceMethod(cls, @selector(layoutSubviews));
    // Add an override on the class itself so a superclass implementation is never replaced.
    if (class_addMethod(cls, @selector(layoutSubviews), replacement, method_getTypeEncoding(layout))) {
        *original = method_getImplementation(class_getInstanceMethod([cls superclass], @selector(layoutSubviews)));
    } else {
        *original = method_setImplementation(layout, replacement);
    }
}

static BOOL PLXInstallMiniPlayerFix(void) {
    static BOOL installed;
    if (installed) return YES;
    Class miniPlayer = NSClassFromString(@"PMMiniPlayerView");
    Class fullSize = NSClassFromString(@"PMMiniPlayerViewFullSize");
    if (!miniPlayer || !fullSize) return NO;
    installed = YES;
    PLXHookLayout(miniPlayer, (IMP)PLXMiniPlayerLayoutSubviews, &PLXOrigMiniPlayerLayout);
    PLXHookLayout(fullSize, (IMP)PLXFullSizeLayoutSubviews, &PLXOrigFullSizeLayout);
    return YES;
}

__attribute__((constructor)) static void PLXInstallMiniPlayerFixAtLaunch(void) {
    if (!PLXInstallMiniPlayerFix()) {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { PLXInstallMiniPlayerFix(); }];
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:PLXSettingsDidChangeNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    NSMutableArray<UIView *> *players = [NSMutableArray array];
                    PLXFindMiniPlayers(window, players);
                    for (UIView *player in players) { [player setNeedsLayout]; [player.superview.superview setNeedsLayout]; }
                }
            }
        }];
}
