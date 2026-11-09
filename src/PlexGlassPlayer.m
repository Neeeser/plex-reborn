// Player controls on glass.
//
// Plex 8.45 draws the full-screen player's controls on two gray bands: a dark
// gradient behind the top buttons and a full-width blur under the progress
// bar and buttons. The bottom band is sized to the space left below a hidden
// poster area, so in landscape it covers about 40% of the screen. With the
// "Glass controls" setting, both bands are hidden; the top buttons sit on
// glass circles and capsules, and the bottom controls sit on one glass panel
// sized to the controls themselves, with the video visible around them.
//
// Independent of the setting, Plex's bottom controls count the bottom safe
// area twice: their container already stops at the safe area, and the
// controls view adds the safe area again as its layout margin, leaving an
// empty band under the buttons. The controls view's margins ignore the safe
// area here.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PlexReborn.h"

// Space between the screen edges and the glass panel, and between the panel
// and the controls inside it.
static const CGFloat PLXPanelScreenInset = 12;
static const CGFloat PLXPanelPaddingX = 14;
static const CGFloat PLXPanelPaddingTop = 12;
static const CGFloat PLXPanelPaddingBottom = 8;
// Plex insets its bottom controls 10 pt from the player's edges.
static const CGFloat PLXPlexControlsInset = 10;

static const void *PLXGlassKey = &PLXGlassKey;

static UIVisualEffect *PLXGlassEffect(void) {
    if (@available(iOS 26.0, *)) return [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
}

// The glass view Plex Reborn keeps behind `owner`, created on first use.
static UIVisualEffectView *PLXGlassFor(id owner) {
    UIVisualEffectView *glass = objc_getAssociatedObject(owner, PLXGlassKey);
    if (glass) return glass;
    glass = [[UIVisualEffectView alloc] initWithEffect:PLXGlassEffect()];
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    glass.userInteractionEnabled = NO;
    glass.clipsToBounds = YES;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    objc_setAssociatedObject(owner, PLXGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return glass;
}

static const void *PLXGlassPinsKey = &PLXGlassPinsKey;

// Puts `glass` at the back of `parent` and pins its sides to `sides`, its top
// to `top` and its bottom to `bottom`, grown by `outset`. Constraints keep the
// glass on its buttons when Plex moves them without laying them out again,
// as it does when the screen rotates.
static void PLXPinGlass(UIVisualEffectView *glass, UIView *parent, UIView *sides, UIView *top, UIView *bottom,
                        UIEdgeInsets outset, CGFloat radius) {
    if (glass.superview != parent) {
        [glass removeFromSuperview];
        [parent insertSubview:glass atIndex:0];
    } else if (parent.subviews.firstObject != glass) {
        [parent sendSubviewToBack:glass];
    }
    NSArray<NSLayoutConstraint *> *pins = objc_getAssociatedObject(glass, PLXGlassPinsKey);
    if (pins.count != 4 || !pins[0].active || pins[0].secondItem != sides || pins[2].secondItem != top || pins[3].secondItem != bottom) {
        if (pins) [NSLayoutConstraint deactivateConstraints:pins];
        pins = @[[glass.leadingAnchor constraintEqualToAnchor:sides.leadingAnchor],
                 [glass.trailingAnchor constraintEqualToAnchor:sides.trailingAnchor],
                 [glass.topAnchor constraintEqualToAnchor:top.topAnchor],
                 [glass.bottomAnchor constraintEqualToAnchor:bottom.bottomAnchor]];
        [NSLayoutConstraint activateConstraints:pins];
        objc_setAssociatedObject(glass, PLXGlassPinsKey, pins, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat constants[4] = { -outset.left, outset.right, -outset.top, outset.bottom };
    for (NSUInteger i = 0; i < 4; i++) {
        if (fabs(pins[i].constant - constants[i]) > 0.5) pins[i].constant = constants[i];
    }
    glass.hidden = NO;
    if (glass.layer.cornerRadius != radius) glass.layer.cornerRadius = radius;
}

static void PLXHideGlass(id owner) {
    UIView *glass = objc_getAssociatedObject(owner, PLXGlassKey);
    glass.hidden = YES;
}

static BOOL PLXIsShown(UIView *view, UIView *upTo) {
    for (UIView *v = view; v && v != upTo; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
    }
    return view.bounds.size.width > 0 && view.bounds.size.height > 0;
}

static UIView *PLXFindView(UIView *root, BOOL (^match)(UIView *view)) {
    if (match(root)) return root;
    for (UIView *subview in root.subviews) {
        UIView *found = PLXFindView(subview, match);
        if (found) return found;
    }
    return nil;
}

// Plex's bottom controls: PMCompactPlayerControlsView (landscape) or
// PMVideoPlayerControlsView (portrait).
static UIView *PLXBottomControls(UIView *player) {
    return PLXFindView(player, ^BOOL(UIView *view) {
        NSString *name = NSStringFromClass(view.class);
        return [name hasSuffix:@"PlayerControlsView"] && ![name isEqualToString:@"PMTopPlayerControlsView"] &&
            ![name isEqualToString:@"PMPlayerControlsSettingsView"];
    });
}

// Union of the labels and buttons that show inside `root`, in `space`'s coordinates.
static CGRect PLXVisibleContentFrame(UIView *root, UIView *space) {
    __block CGRect frame = CGRectNull;
    __block void (^walk)(UIView *);
    __weak __block void (^weakWalk)(UIView *);
    weakWalk = walk = ^(UIView *view) {
        if (view.hidden || view.alpha < 0.01) return;
        BOOL label = [view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length > 0;
        if (label || [view isKindOfClass:UIControl.class]) {
            if (PLXIsShown(view, root)) frame = CGRectUnion(frame, [view convertRect:view.bounds toView:space]);
            return;
        }
        for (UIView *subview in view.subviews) weakWalk(subview);
    };
    walk(root);
    return frame;
}

// Plex pins its bottom controls 10 pt inside the player's sides (Plex Reborn
// keeps those pins, see PlexDuoVideo.m) and the progress bar to the player's
// edges. In glass mode the controls move inward to sit inside the panel, and
// the progress bar follows the controls' column so it lines up with the
// buttons whichever side the camera is on.
static const void *PLXSliderPinsKey = &PLXSliderPinsKey;
static const void *PLXSliderEdgePinsKey = &PLXSliderEdgePinsKey;

static void PLXSetSideInsets(UIView *player, UIView *wrapper, UIView *slider, BOOL glass) {
    CGFloat inset = PLXPanelScreenInset + PLXPanelPaddingX;
    NSMutableArray<NSLayoutConstraint *> *edgePins = [NSMutableArray array];
    for (NSLayoutConstraint *c in player.constraints) {
        if (c.firstAttribute != NSLayoutAttributeLeading && c.firstAttribute != NSLayoutAttributeTrailing) continue;
        if (slider && c.firstItem == slider && [c.identifier isEqualToString:@"PLXProgressBarEdge"]) {
            [edgePins addObject:c];
            continue;
        }
        if (c.firstItem != wrapper || c.constant == 0) continue;
        CGFloat sign = c.firstAttribute == NSLayoutAttributeLeading ? 1 : -1;
        CGFloat wanted = sign * (glass ? inset : PLXPlexControlsInset);
        if (c.constant != wanted) c.constant = wanted;
    }
    if (!slider) return;
    // Deactivated constraints leave player.constraints, so the edge pins are kept here.
    if (edgePins.count == 2) objc_setAssociatedObject(slider, PLXSliderEdgePinsKey, [edgePins copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    edgePins = objc_getAssociatedObject(slider, PLXSliderEdgePinsKey);
    if (edgePins.count != 2) return;
    NSArray<NSLayoutConstraint *> *columnPins = objc_getAssociatedObject(slider, PLXSliderPinsKey);
    if (!columnPins) {
        columnPins = @[[slider.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor],
                       [slider.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor]];
        objc_setAssociatedObject(slider, PLXSliderPinsKey, columnPins, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (columnPins.firstObject.active == glass) return;
    if (glass) {
        [NSLayoutConstraint deactivateConstraints:edgePins];
        [NSLayoutConstraint activateConstraints:columnPins];
    } else {
        [NSLayoutConstraint deactivateConstraints:columnPins];
        [NSLayoutConstraint activateConstraints:edgePins];
    }
}

// A glass circle behind a lone button and a capsule behind a row of them. A
// stack view leaves its hidden buttons out of its size, so the capsule fits
// the buttons that show.
static void PLXUpdateTopButtons(UIView *topBar, BOOL glass) {
    UIView *content = topBar.subviews.firstObject;
    for (UIView *item in content.subviews) {
        BOOL shown = NO;
        if ([item isKindOfClass:UIStackView.class]) {
            for (UIView *button in ((UIStackView *)item).arrangedSubviews) shown = shown || !button.hidden;
        } else {
            shown = [item isKindOfClass:UIControl.class];
        }
        if (!glass || !shown || item.hidden) { PLXHideGlass(item); continue; }
        CGFloat height = CGRectGetHeight(item.bounds) ?: 44;
        PLXPinGlass(PLXGlassFor(item), content, item, item, item, UIEdgeInsetsZero, height / 2);
    }
}

// The glass panel behind the bottom controls: from just above the progress
// bar to just below the last row that shows, across the controls' column.
static void PLXUpdateBottomPanel(UIView *controls) {
    UIView *wrapper = controls.superview;
    UIView *container = wrapper.superview;
    if (!container) return;
    if (!PLXSettingBool(PLXSettingGlassPlayerControls)) { PLXHideGlass(container); return; }
    CGRect content = PLXVisibleContentFrame(controls, controls);
    if (CGRectIsNull(content)) { PLXHideGlass(container); return; }
    UIView *slider = PLXFindView(container, ^BOOL(UIView *view) {
        return [view.accessibilityIdentifier isEqualToString:@"videoPlayer.progressView"];
    });
    BOOL sliderShown = slider && !slider.hidden;
    UIEdgeInsets outset = UIEdgeInsetsMake(sliderShown ? PLXPanelPaddingTop : PLXPanelPaddingTop - CGRectGetMinY(content), PLXPanelPaddingX,
                                           CGRectGetMaxY(content) + PLXPanelPaddingBottom - CGRectGetHeight(controls.bounds), PLXPanelPaddingX);
    PLXPinGlass(PLXGlassFor(container), container, wrapper, sliderShown ? slider : controls, controls, outset, 26);
}

void PLXUpdatePlayerControls(UIView *player) {
    if (!player) return;
    BOOL glass = PLXSettingBool(PLXSettingGlassPlayerControls);

    // Plex's gradient behind the top buttons fades in and out with the
    // controls. Plex hides the top buttons when the layer is hidden, so its
    // colors are made clear instead; Plex sets them again on rotation, which
    // PLXGradientSetColors catches.
    for (CALayer *layer in player.layer.sublayers) {
        if (![layer isKindOfClass:CAGradientLayer.class] || CGRectGetMinY(layer.frame) > 1) continue;
        CAGradientLayer *gradient = (CAGradientLayer *)layer;
        if (!objc_getAssociatedObject(gradient, PLXGlassKey) && gradient.colors) {
            objc_setAssociatedObject(gradient, PLXGlassKey, gradient.colors, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        gradient.colors = objc_getAssociatedObject(gradient, PLXGlassKey);
    }

    UIView *controls = PLXBottomControls(player);
    UIView *wrapper = controls.superview;
    UIView *container = wrapper.superview;
    if (!controls || !container || container == player) return;
    if (controls.insetsLayoutMarginsFromSafeArea) controls.insetsLayoutMarginsFromSafeArea = NO;

    UIView *slider = PLXFindView(container, ^BOOL(UIView *view) {
        return [view.accessibilityIdentifier isEqualToString:@"videoPlayer.progressView"];
    });
    PLXSetSideInsets(player, wrapper, slider, glass);

    // Plex's blur fills the container, one level down.
    for (UIView *child in container.subviews) {
        for (UIView *view in child.subviews) {
            if (![view isKindOfClass:UIVisualEffectView.class] || view == objc_getAssociatedObject(container, PLXGlassKey)) continue;
            if (view.hidden != glass) view.hidden = glass;
        }
    }
}

// Plex's colors for its top gradient are kept on the layer (PLXGlassKey) and
// replaced with clear ones while glass controls are on.
static IMP PLXOrigSetColors;

static void PLXGradientSetColors(CAGradientLayer *self, SEL _cmd, NSArray *colors) {
    if (colors && objc_getAssociatedObject(self, PLXGlassKey)) {
        objc_setAssociatedObject(self, PLXGlassKey, colors, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (PLXSettingBool(PLXSettingGlassPlayerControls)) {
            NSMutableArray *clear = [NSMutableArray arrayWithCapacity:colors.count];
            for (NSUInteger i = 0; i < colors.count; i++) [clear addObject:(id)UIColor.clearColor.CGColor];
            colors = clear;
        }
    }
    ((void (*)(id, SEL, id))PLXOrigSetColors)(self, _cmd, colors);
}

// The glass behind the buttons follows each layout of the bars themselves,
// since buttons show, hide and move without the player's layout running.
static IMP PLXOrigTopLayout, PLXOrigCompactLayout, PLXOrigFullLayout;

static void PLXTopLayout(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigTopLayout)(self, _cmd);
    PLXUpdateTopButtons(self, PLXSettingBool(PLXSettingGlassPlayerControls));
}

static void PLXCompactLayout(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigCompactLayout)(self, _cmd);
    PLXUpdateBottomPanel(self);
}

static void PLXFullLayout(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigFullLayout)(self, _cmd);
    PLXUpdateBottomPanel(self);
}

// Adds a layoutSubviews override to the class itself, so a superclass's
// implementation is never replaced; returns the implementation to call first.
static IMP PLXOverrideLayout(NSString *className, IMP replacement) {
    Class cls = NSClassFromString(className);
    if (!cls) return NULL;
    Method layout = class_getInstanceMethod(cls, @selector(layoutSubviews));
    if (class_addMethod(cls, @selector(layoutSubviews), replacement, method_getTypeEncoding(layout))) {
        return method_getImplementation(class_getInstanceMethod(class_getSuperclass(cls), @selector(layoutSubviews)));
    }
    return method_setImplementation(layout, replacement);
}

static BOOL PLXInstallGlassPlayerIfPossible(void) {
    static BOOL installed;
    if (installed) return YES;
    if (!NSClassFromString(@"PMTopPlayerControlsView")) return NO;
    installed = YES;
    PLXOrigSetColors = method_setImplementation(class_getInstanceMethod(CAGradientLayer.class, @selector(setColors:)), (IMP)PLXGradientSetColors);
    PLXOrigTopLayout = PLXOverrideLayout(@"PMTopPlayerControlsView", (IMP)PLXTopLayout);
    PLXOrigCompactLayout = PLXOverrideLayout(@"PMCompactPlayerControlsView", (IMP)PLXCompactLayout);
    PLXOrigFullLayout = PLXOverrideLayout(@"PMVideoPlayerControlsView", (IMP)PLXFullLayout);
    return YES;
}

__attribute__((constructor)) static void PLXInstallGlassPlayer(void) {
    if (PLXInstallGlassPlayerIfPossible()) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { PLXInstallGlassPlayerIfPossible(); }];
}
