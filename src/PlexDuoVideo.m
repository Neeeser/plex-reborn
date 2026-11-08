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

static void PLXPlaybackLayoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOriginalPlaybackLayout)(self, _cmd);
    PLXObserveHinge(self);

    CGRect fold = PLXDeskPostureFold(self);
    BOOL desk = !CGRectIsNull(fold);
    CGRect videoFrame = self.bounds;
    if (desk) videoFrame.size.height = CGRectGetMinY(fold);

    Class containerClass = NSClassFromString(@"PMKVideoPlayerContainerView");
    for (UIView *container in self.subviews) {
        if (!containerClass || ![container isKindOfClass:containerClass]) continue;
        if (CGRectEqualToRect(container.frame, videoFrame)) continue;
        CGSize oldSize = container.bounds.size;
        container.frame = videoFrame;
        // Children that filled the old container (the mpv/AVPlayer view) fill the new one.
        for (UIView *child in container.subviews) {
            if (CGSizeEqualToSize(child.frame.size, oldSize)) child.frame = container.bounds;
        }
    }

    // Plex's top bar (close, cast, settings) fades rather than moves when the
    // controls hide, so moving it below the crease keeps it working. Plex
    // asserts on views with a transform, so the bar is moved through the
    // constraint that pins its top edge.
    static Class topControlsClass;
    if (!topControlsClass) topControlsClass = NSClassFromString(@"PMTopPlayerControlsView");
    UIView *parent = self.superview;
    for (UIView *bar in parent.subviews) {
        if (![bar isKindOfClass:topControlsClass]) continue;
        CGFloat shift = desk ? CGRectGetMaxY([self convertRect:fold toView:parent]) : 0;
        PLXShiftTopEdge(bar, parent, shift);
    }
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

// Player controls on the Duo.
//
// Plex picks its compact (phone) controls whenever the horizontal size class
// is compact. The unfolded Duo is 466 pt wide, so it gets the compact layout,
// whose transport row is taller than the space Plex reserves and ends up below
// the screen: only the scrubber and title show, with no play/pause buttons.
// Screens this large get the full controls instead; small screens (the folded
// outer display, regular iPhones) keep the compact ones.
static const CGFloat PLXFullControlsMinimumShortSide = 400.0;

static IMP PLXOrigSetControlsCompact;

static void PLXSetControlsCompact(UIViewController *self, SEL _cmd, BOOL compact) {
    CGSize size = self.view.bounds.size;
    if (compact && MIN(size.width, size.height) >= PLXFullControlsMinimumShortSide) compact = NO;
    ((void (*)(id, SEL, BOOL))PLXOrigSetControlsCompact)(self, _cmd, compact);
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
        Method compact = class_getInstanceMethod(player, NSSelectorFromString(@"setControlsViewCompact:"));
        Method toggle = class_getInstanceMethod(player, NSSelectorFromString(@"toggleControlsHidden"));
        if (compact) PLXOrigSetControlsCompact = method_setImplementation(compact, (IMP)PLXSetControlsCompact);
        if (toggle) PLXOrigToggleControlsHidden = method_setImplementation(toggle, (IMP)PLXToggleControlsHidden);
    };
    install();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { install(); }];
}
