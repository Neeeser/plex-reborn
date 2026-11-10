// Full-bleed video for the iPhone Duo.
//
// Plex 8.45 sizes its video container to the safe area. On the unfolded Duo the
// right-hand system strip is an 84 pt safe-area inset, so the container is
// 382 of 466 pt wide and a 16:9 picture renders small and pinned left. Video
// should run edge to edge (as Infuse does) while the playback controls keep
// respecting the safe area, so only the container and the player view inside
// it are stretched to the playback view's full bounds after each layout pass.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PlexReborn.h"

static IMP PLXOriginalPlaybackLayout;

// Desk (laptop) posture: the Duo is half open with the crease running across
// the screen. Like Netflix and the TV app, the video moves to the half above
// the crease and the controls to the half below it. In book posture the crease
// runs top to bottom and the full-screen layout stays.
//
// Returns the crease's frame in the view's coordinates, or CGRectNull when the
// device is flat, closed, in book posture, or has no hinge.
CGRect PLXDeskPostureFold(UIView *view) {
    if (@available(iOS 27.1, *)) {
        for (UIViewReservedRegion *region in [view reservedRegionsOfKind:[UIViewReservedRegionKind divisionRegionKind]]) {
            CGRect fold = region.frame;
            if (region.isActive && fold.size.width > fold.size.height) return fold;
        }
    }
    return CGRectNull;
}

static const void *PLXHingeInteractionKey = &PLXHingeInteractionKey;

// Folding without rotating leaves the view's size unchanged, so nothing would
// re-run layout. A hinge listener asks for layout whenever the posture changes.
static void PLXObserveHinge(UIView *view) {
    if (@available(iOS 27.1, *)) {
        if (objc_getAssociatedObject(view, PLXHingeInteractionKey)) return;
        __weak UIView *weakView = view;
        UIHingeInteraction *hinge = [[UIHingeInteraction alloc] initWithUpdateHandler:^(UIHingeInteraction *interaction, UIHingeInteractionUpdate *update) {
            UIView *strongView = weakView;
            [strongView setNeedsLayout];
            [strongView.superview setNeedsLayout];
        }];
        [view addInteraction:hinge];
        objc_setAssociatedObject(view, PLXHingeInteractionKey, hinge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static const void *PLXOriginalTopConstantKey = &PLXOriginalTopConstantKey;

// The constraint in `parent` that places `view`'s top edge, if Auto Layout places it.
NSLayoutConstraint *PLXTopEdgeConstraint(UIView *view, UIView *parent) {
    for (NSLayoutConstraint *c in parent.constraints) {
        if ((c.firstItem == view && c.firstAttribute == NSLayoutAttributeTop) ||
            (c.secondItem == view && c.secondAttribute == NSLayoutAttributeTop)) return c;
    }
    return nil;
}

static void PLXShiftTopEdge(UIView *view, UIView *parent, CGFloat shift) {
    NSLayoutConstraint *top = PLXTopEdgeConstraint(view, parent);
    if (!top) return;
    NSNumber *original = objc_getAssociatedObject(top, PLXOriginalTopConstantKey);
    if (!original) {
        original = @(top.constant);
        objc_setAssociatedObject(top, PLXOriginalTopConstantKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The constraint may read either way round (bar.top = guide.top + c, or guide.top = bar.top - c).
    CGFloat sign = top.firstItem == view ? 1 : -1;
    CGFloat wanted = original.doubleValue + sign * shift;
    if (top.constant != wanted) top.constant = wanted;
}

// Desk posture reflection: like Netflix, the half below the crease shows the
// picture mirrored, blurred and darkened behind the controls, so the bottom
// half continues the video instead of being a flat panel. UIKit's portal view
// (private _UIPortalView) draws another view's live rendering, video
// included, so nothing is copied frame by frame.
//
// The blur is a system blur view with its gray tint removed. The view's
// backdrop layer samples whatever is drawn under it every frame, video
// included, and its tint is a separate subview; with that subview hidden and
// only a saturation boost and a Gaussian blur left on the backdrop, the
// reflection keeps the picture's colors (the material made it read as a gray
// panel). A blur filter set on the portal itself kept the colors but froze
// the reflection between layout passes, since that filter caches the video it
// samples. The tint comes back on trait changes, so it is removed again on
// every layout.
static const void *PLXReflectionKey = &PLXReflectionKey;
static const void *PLXReflectionFiltersKey = &PLXReflectionFiltersKey;

static id PLXFilter(NSString *type) {
    Class filterClass = NSClassFromString(@"CAFilter");
    if (![filterClass respondsToSelector:@selector(filterWithType:)]) return nil;
    return [filterClass performSelector:@selector(filterWithType:) withObject:type];
}

static void PLXRemoveBlurTint(UIVisualEffectView *blur) {
    NSArray *filters = objc_getAssociatedObject(blur, PLXReflectionFiltersKey);
    if (!filters) {
        id saturate = PLXFilter(@"colorSaturate");
        id gaussian = PLXFilter(@"gaussianBlur");
        if (!saturate || !gaussian) return;
        [saturate setValue:@1.8 forKey:@"inputAmount"];
        [gaussian setValue:@28 forKey:@"inputRadius"];
        [gaussian setValue:@YES forKey:@"inputNormalizeEdges"];
        filters = @[saturate, gaussian];
        objc_setAssociatedObject(blur, PLXReflectionFiltersKey, filters, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *sub in blur.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if ([name containsString:@"Backdrop"]) {
            if (![sub.layer.filters isEqualToArray:filters]) sub.layer.filters = filters;
        } else if ([name containsString:@"VisualEffectSubview"] && !sub.hidden) {
            sub.hidden = YES;
        }
    }
}

static UIView *PLXReflectionView(UIView *playbackView, UIView *source) {
    UIView *root = objc_getAssociatedObject(playbackView, PLXReflectionKey);
    if (root) return root;
    Class portalClass = NSClassFromString(@"_UIPortalView");
    if (!portalClass || !source) return nil;
    root = [UIView new];
    root.clipsToBounds = YES;
    root.userInteractionEnabled = NO;
    root.backgroundColor = UIColor.blackColor;

    UIView *portal = [portalClass new];
    [portal setValue:source forKey:@"sourceView"];
    if ([portal respondsToSelector:NSSelectorFromString(@"setMatchesPosition:")]) [portal setValue:@NO forKey:@"matchesPosition"];
    if ([portal respondsToSelector:NSSelectorFromString(@"setMatchesTransform:")]) [portal setValue:@NO forKey:@"matchesTransform"];
    portal.tag = 1;
    [root addSubview:portal];

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.tag = 2;
    [root addSubview:blur];

    // Like Netflix's: strongest at the crease and mostly dark by the middle
    // of the lower half, where the controls' text sits.
    UIView *shade = [UIView new];
    shade.tag = 3;
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.2].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.6].CGColor,
                        (id)[UIColor colorWithWhite:0 alpha:0.88].CGColor];
    gradient.locations = @[@0, @0.45, @1];
    [shade.layer addSublayer:gradient];
    [root addSubview:shade];

    objc_setAssociatedObject(playbackView, PLXReflectionKey, root, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return root;
}

static void PLXLayoutReflection(UIView *playbackView, UIView *container, CGRect fold, BOOL desk) {
    BOOL on = desk && container && PLXSettingBool(PLXSettingDeskReflection);
    UIView *existing = objc_getAssociatedObject(playbackView, PLXReflectionKey);
    if (!on) { existing.hidden = YES; return; }
    UIView *root = PLXReflectionView(playbackView, container);
    if (!root) return;
    if (root.superview != playbackView) [playbackView insertSubview:root aboveSubview:container];
    root.hidden = NO;
    CGFloat top = CGRectGetMinY(fold);
    root.frame = CGRectMake(CGRectGetMinX(container.frame), top, CGRectGetWidth(container.frame), CGRectGetHeight(playbackView.bounds) - top);

    // The portal shows the video container's picture at the container's size,
    // flipped so the picture's bottom edge meets the crease.
    UIView *portal = [root viewWithTag:1];
    CGSize videoSize = container.bounds.size;
    portal.transform = CGAffineTransformIdentity;
    portal.bounds = CGRectMake(0, 0, videoSize.width, videoSize.height);
    portal.center = CGPointMake(videoSize.width / 2, videoSize.height / 2);
    portal.transform = CGAffineTransformMakeScale(1, -1);
    UIVisualEffectView *blur = (UIVisualEffectView *)[root viewWithTag:2];
    blur.frame = root.bounds;
    PLXRemoveBlurTint(blur);
    UIView *shade = [root viewWithTag:3];
    shade.frame = root.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    shade.layer.sublayers.firstObject.frame = shade.bounds;
    [CATransaction commit];
}

// Plex lays out the player inside its animation that fades the controls in
// and out. Laid out there, the portal's flip (reset to identity, then flipped
// again) animated through a zero height, so the reflection vanished for the
// length of the fade on every tap. The reflection is laid out without animation.
static void PLXUpdateReflection(UIView *playbackView, UIView *container, CGRect fold, BOOL desk) {
    [UIView performWithoutAnimation:^{ PLXLayoutReflection(playbackView, container, fold, desk); }];
}

// Plex pins the progress bar to the player's safe area, which stops it at the
// camera strip in landscape. The bar sits well above the camera in either
// orientation, so pin it to the player's edges instead.
static void PLXPinProgressBarToEdges(UIView *player) {
    static NSString *const pinned = @"PLXProgressBarEdge";
    NSMutableArray<NSLayoutConstraint *> *safeAreaPins = [NSMutableArray array];
    UIView *bar = nil;
    for (NSLayoutConstraint *c in player.constraints) {
        if ([c.identifier isEqualToString:pinned]) return;
        if (c.secondItem != player.safeAreaLayoutGuide || ![c.firstItem isKindOfClass:UIView.class]) continue;
        if (c.firstAttribute != NSLayoutAttributeLeading && c.firstAttribute != NSLayoutAttributeTrailing) continue;
        UIView *view = c.firstItem;
        if (![view.accessibilityIdentifier isEqualToString:@"videoPlayer.progressView"]) continue;
        bar = view;
        [safeAreaPins addObject:c];
    }
    if (!bar || safeAreaPins.count != 2) return;
    [NSLayoutConstraint deactivateConstraints:safeAreaPins];
    NSLayoutConstraint *leading = [bar.leadingAnchor constraintEqualToAnchor:player.leadingAnchor];
    NSLayoutConstraint *trailing = [bar.trailingAnchor constraintEqualToAnchor:player.trailingAnchor];
    leading.identifier = trailing.identifier = pinned;
    [NSLayoutConstraint activateConstraints:@[leading, trailing]];
}

// Plex pins the bottom row of controls 10 points inside the player's safe
// area. Swap between those pins and the same 10 points inside the player's
// edges; both sets are kept and only one is active at a time.
static const void *PLXBottomSafePinsKey = &PLXBottomSafePinsKey;
static const void *PLXBottomEdgePinsKey = &PLXBottomEdgePinsKey;

static void PLXPinBottomControls(UIView *player, BOOL toEdges) {
    NSArray<NSLayoutConstraint *> *safePins = objc_getAssociatedObject(player, PLXBottomSafePinsKey);
    NSArray<NSLayoutConstraint *> *edgePins = objc_getAssociatedObject(player, PLXBottomEdgePinsKey);
    if (!safePins) {
        NSMutableArray<NSLayoutConstraint *> *found = [NSMutableArray array];
        UIView *row = nil;
        for (NSLayoutConstraint *c in player.constraints) {
            if (c.secondItem != player.safeAreaLayoutGuide || ![c.firstItem isKindOfClass:UIView.class]) continue;
            if (c.firstAttribute != NSLayoutAttributeLeading && c.firstAttribute != NSLayoutAttributeTrailing) continue;
            if (fabs(c.constant) != 10) continue;
            if (row && c.firstItem != row) return;
            row = c.firstItem;
            [found addObject:c];
        }
        if (!row || found.count != 2) return;
        NSMutableArray<NSLayoutConstraint *> *edges = [NSMutableArray array];
        for (NSLayoutConstraint *c in found) {
            NSLayoutAnchor *rowAnchor = c.firstAttribute == NSLayoutAttributeLeading ? row.leadingAnchor : row.trailingAnchor;
            NSLayoutAnchor *playerAnchor = c.firstAttribute == NSLayoutAttributeLeading ? player.leadingAnchor : player.trailingAnchor;
            [edges addObject:[rowAnchor constraintEqualToAnchor:playerAnchor constant:c.constant]];
        }
        safePins = found;
        edgePins = edges;
        objc_setAssociatedObject(player, PLXBottomSafePinsKey, safePins, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(player, PLXBottomEdgePinsKey, edgePins, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (edgePins.firstObject.active == toEdges) return;
    if (toEdges) {
        [NSLayoutConstraint deactivateConstraints:safePins];
        [NSLayoutConstraint activateConstraints:edgePins];
    } else {
        [NSLayoutConstraint deactivateConstraints:edgePins];
        [NSLayoutConstraint activateConstraints:safePins];
    }
}

// Plex lays out its top bar inside the bar's layout margins (18 pt each side)
// plus the safe area. Unfolded in landscape, the safe area also reserves space
// across the top although the status bar sits only in the side strip, which
// pushed the whole bar down. The bar's margins are set here instead: Plex's
// own margins, plus the side insets, which keep the bar clear of the
// strip. Unfolded in portrait there is no side strip: the status bar shows in
// the top right corner, inside the top inset, so the bar stays below it; the
// picture is letterboxed there, so this costs no video.
static const void *PLXTopBarMarginsKey = &PLXTopBarMarginsKey;

static void PLXSetTopBarMargins(UIView *bar, UIEdgeInsets safe, BOOL desk) {
    NSValue *stored = objc_getAssociatedObject(bar, PLXTopBarMarginsKey);
    if (!stored) {
        stored = [NSValue valueWithUIEdgeInsets:bar.layoutMargins];
        objc_setAssociatedObject(bar, PLXTopBarMarginsKey, stored, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIEdgeInsets plex = stored.UIEdgeInsetsValue;
    UIEdgeInsets margins = UIEdgeInsetsMake(plex.top, plex.left, plex.bottom, plex.right);
    margins.left += safe.left;
    margins.right += safe.right;
    // In desk posture the bar already sits below the crease, away from the status bar.
    BOOL statusBarAbove = !desk && safe.top > 0 && safe.left == 0 && safe.right == 0;
    if (statusBarAbove) margins.top += safe.top;
    // Glass buttons need space from the screen's top edge (PlexGlassPlayer.m).
    else if (PLXSettingBool(PLXSettingGlassPlayerControls)) margins.top += 8;
    if (bar.insetsLayoutMarginsFromSafeArea) bar.insetsLayoutMarginsFromSafeArea = NO;
    if (!UIEdgeInsetsEqualToEdgeInsets(bar.layoutMargins, margins)) bar.layoutMargins = margins;
}

static void PLXPlaybackLayoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOriginalPlaybackLayout)(self, _cmd);
    PLXObserveHinge(self);

    CGRect fold = PLXDeskPostureFold(self);
    BOOL desk = !CGRectIsNull(fold);
    // The window's full width, in case Plex's playback view itself stops at
    // the safe area (the Duo's status strip) instead of the screen edge.
    CGRect videoFrame = self.bounds;
    if (self.window && CGRectGetHeight(self.bounds) > 200) {
        CGRect windowInSelf = [self.window convertRect:self.window.bounds toView:self];
        videoFrame.origin.x = CGRectGetMinX(windowInSelf);
        videoFrame.size.width = CGRectGetWidth(windowInSelf);
    }
    if (desk) videoFrame.size.height = CGRectGetMinY(fold);

    Class containerClass = NSClassFromString(@"PMKVideoPlayerContainerView");
    UIView *videoContainer = nil;
    for (UIView *container in self.subviews) {
        if (!containerClass || ![container isKindOfClass:containerClass]) continue;
        videoContainer = container;
        if (CGRectEqualToRect(container.frame, videoFrame)) continue;
        CGSize oldSize = container.bounds.size;
        container.frame = videoFrame;
        // Children that filled the old container (the mpv/AVPlayer view) fill the new one.
        for (UIView *child in container.subviews) {
            if (CGSizeEqualToSize(child.frame.size, oldSize)) child.frame = container.bounds;
        }
    }
    // The mini player's small video view is a playback view too; only the full player is reflected.
    PLXUpdateReflection(self, CGRectGetHeight(self.bounds) > 200 ? videoContainer : nil, fold, desk);

    // Plex's top bar (close, cast, settings) fades rather than moves when the
    // controls hide, so moving it below the crease keeps it working. Plex
    // asserts on views with a transform, so the bar is moved through the
    // constraint that pins its top edge.
    static Class topControlsClass;
    if (!topControlsClass) topControlsClass = NSClassFromString(@"PMTopPlayerControlsView");
    UIView *parent = self.superview;
    // The Duo reserves an 84-pt strip on one side for its vertical status bar,
    // which shows at the top of that strip whenever the player's controls
    // show, in every pose (iOS 27.2 shows it in folded landscape too, which
    // put the clock over the close button). In folded landscape the camera
    // also sits in the strip, level with the top bar on the left or in the
    // bottom corner on the right. The top bar always stays clear of the strip.
    UIEdgeInsets safe = parent.safeAreaInsets;
    BOOL compactHeight = parent.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
    BOOL cameraBottomRight = compactHeight && safe.right > 0 && safe.left == 0;
    // The bottom row (time labels, transport buttons, more) is clear of both
    // the status bar and the camera everywhere except beside a bottom-corner camera.
    if (parent) PLXPinBottomControls(parent, !cameraBottomRight);
    for (UIView *bar in parent.subviews) {
        if (![bar isKindOfClass:topControlsClass]) continue;
        CGFloat shift = desk ? CGRectGetMaxY([self convertRect:fold toView:parent]) : 0;
        PLXShiftTopEdge(bar, parent, shift);
        PLXSetTopBarMargins(bar, safe, desk);
    }
    if (parent) PLXPinProgressBarToEdges(parent);
    if (CGRectGetHeight(self.bounds) > 200) PLXUpdatePlayerControls(parent);
}

static BOOL PLXInstallFullBleedVideoIfPossible(void) {
    static BOOL installed;
    if (installed) return YES;
    Class playbackView = NSClassFromString(@"PMKVideoPlaybackView");
    if (!playbackView) return NO;
    installed = YES;
    Method layout = class_getInstanceMethod(playbackView, @selector(layoutSubviews));
    // Add an override on the class itself so a superclass implementation is never replaced.
    if (class_addMethod(playbackView, @selector(layoutSubviews), (IMP)PLXPlaybackLayoutSubviews, method_getTypeEncoding(layout))) {
        PLXOriginalPlaybackLayout = method_getImplementation(class_getInstanceMethod([playbackView superclass], @selector(layoutSubviews)));
    } else {
        PLXOriginalPlaybackLayout = method_setImplementation(layout, (IMP)PLXPlaybackLayoutSubviews);
    }
    return YES;
}

__attribute__((constructor)) static void PLXInstallFullBleedVideo(void) {
    if (PLXInstallFullBleedVideoIfPossible()) return;
    // Plex's classes may register after this library's constructor; retry at launch.
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { PLXInstallFullBleedVideoIfPossible(); }];
}

// Hide the Duo's vertical status bar while the player is up.
//
// iOS 27.1 shows the status bar as a vertical strip on the Duo's trailing edge
// and keeps it visible even when prefersStatusBarHidden is YES. Apple's
// guidance is to disable the vertical bar for fullscreen video players; the
// status bar then reverts to the horizontal axis, where Plex's existing
// prefersStatusBarHidden logic hides it with the controls.
static NSInteger PLXPlayerVerticalBarBehavior(id self, SEL _cmd) {
    return 1; // UIVerticalBarBehaviorDisabled
}

static BOOL PLXPlayerHidesHomeIndicator(id self, SEL _cmd) {
    return YES;
}

__attribute__((constructor)) static void PLXInstallPlayerBarHiding(void) {
    void (^install)(void) = ^{
        Class player = NSClassFromString(@"PMPlayerViewController");
        if (!player) return;
        class_replaceMethod(player, NSSelectorFromString(@"preferredVerticalBarBehavior"), (IMP)PLXPlayerVerticalBarBehavior, "q@:");
        class_replaceMethod(player, @selector(prefersHomeIndicatorAutoHidden), (IMP)PLXPlayerHidesHomeIndicator, "B@:");
    };
    install();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { install(); }];
}

// Plex opens the player believing its controls are visible while they are
// actually transparent, so the first tap "hides" them and nothing appears.
// When a tap finds the controls invisible and they are still invisible after
// Plex toggles, toggle again so a single tap always shows them.
static IMP PLXOrigToggleControlsHidden;

static UIView *PLXFindTopControls(UIView *view) {
    static Class topControlsClass;
    if (!topControlsClass) topControlsClass = NSClassFromString(@"PMTopPlayerControlsView");
    if ([view isKindOfClass:topControlsClass]) return view;
    for (UIView *subview in view.subviews) {
        UIView *found = PLXFindTopControls(subview);
        if (found) return found;
    }
    return nil;
}

static void PLXToggleControlsHidden(UIViewController *self, SEL _cmd) {
    UIView *topControls = PLXFindTopControls(self.view);
    BOOL looksHidden = topControls && topControls.alpha < 0.05;
    ((void (*)(id, SEL))PLXOrigToggleControlsHidden)(self, _cmd);
    if (!looksHidden) return;
    __weak UIViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *player = weakSelf;
        UIView *controls = player ? PLXFindTopControls(player.view) : nil;
        if (controls && controls.alpha < 0.05) {
            ((void (*)(id, SEL))PLXOrigToggleControlsHidden)(player, _cmd);
        }
    });
}

__attribute__((constructor)) static void PLXInstallPlayerControlFixes(void) {
    void (^install)(void) = ^{
        static BOOL installed;
        Class player = NSClassFromString(@"PMVideoPlayerViewController");
        if (installed || !player) return;
        installed = YES;
        Method toggle = class_getInstanceMethod(player, NSSelectorFromString(@"toggleControlsHidden"));
        if (toggle) PLXOrigToggleControlsHidden = method_setImplementation(toggle, (IMP)PLXToggleControlsHidden);
    };
    install();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { install(); }];
}
