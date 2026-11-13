// Keep the icon buttons beside Play at full size on wide screens.
//
// Plex's movie and episode pages put Play and the icon buttons (watched,
// download, watchlist, share, more) in one row. On narrow screens Plex gives
// each icon a 44 pt button with a -4 pt gap, so the icons sit 40 pt apart. On
// wide screens (the unfolded Duo, both orientations) it switches to an iPad
// layout with 16 pt gaps, sized for an iPad's wider column. The row on the Duo
// is too short for that, so Auto Layout shrinks every icon button to about
// 15 pt and the 24 pt images get squeezed into ovals.
//
// When the row can't fit full-size buttons with Plex's gaps, it gets Plex's
// narrow-screen spacing instead, and the button images keep their aspect
// ratio. When it fits again (or Plex picks the narrow spacing itself), Plex's
// own spacing is put back.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Plex's narrow-screen values: the gap between icon buttons, the gap after
// Play, and the width each icon button gets when the row has room.
static const CGFloat PLXNarrowSpacing = -4;
static const CGFloat PLXNarrowSpacingAfterPlay = 8;
static const CGFloat PLXFullIconButtonWidth = 44;

// Plex's own spacing, kept on the stack while the narrow spacing replaces it.
static const void *PLXPlexSpacingKey = &PLXPlexSpacingKey;

static IMP PLXOrigStackLayout;

static UIView *PLXActionRowHeader(UIStackView *stack) {
    static Class headerClass;
    if (!headerClass) headerClass = NSClassFromString(@"PMPrePlayHeaderView");
    UIView *view = stack.superview;
    for (int depth = 0; view && depth < 4; depth++, view = view.superview) {
        if (![view isKindOfClass:headerClass]) continue;
        SEL getter = NSSelectorFromString(@"actionsHorizontalButtonsStack");
        if (![view respondsToSelector:getter]) return nil;
        return ((id (*)(id, SEL))objc_msgSend)(view, getter) == stack ? view : nil;
    }
    return nil;
}

static void PLXFitActionRow(UIStackView *stack, UIView *header) {
    CGFloat width = CGRectGetWidth(stack.bounds);
    if (width <= 0) return;
    UIView *play = nil;
    SEL playGetter = NSSelectorFromString(@"primaryButton");
    if ([header respondsToSelector:playGetter]) play = ((id (*)(id, SEL))objc_msgSend)(header, playGetter);

    NSNumber *saved = objc_getAssociatedObject(stack, PLXPlexSpacingKey);
    // Plex sets the spacing again when its layout changes; that value becomes Plex's choice.
    if (saved && stack.spacing != PLXNarrowSpacing) saved = nil;
    CGFloat plexSpacing = saved ? saved.doubleValue : stack.spacing;
    if (plexSpacing <= PLXNarrowSpacing) {
        objc_setAssociatedObject(stack, PLXPlexSpacingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    // Width the row needs with Plex's spacing and full-size icon buttons.
    // Spacer views stretch only into leftover room, so they count as zero.
    NSMutableArray<UIButton *> *icons = [NSMutableArray array];
    NSUInteger visible = 0;
    CGFloat fixed = 0;
    for (UIView *view in stack.arrangedSubviews) {
        if (view.hidden) continue;
        visible++;
        if ([view isKindOfClass:UIButton.class] && view != play) [icons addObject:(UIButton *)view];
        else if (![NSStringFromClass(view.class) containsString:@"FillerView"]) fixed += CGRectGetWidth(view.bounds);
    }
    if (icons.count == 0) return;
    CGFloat needed = fixed + icons.count * PLXFullIconButtonWidth + plexSpacing * (visible - 1);
    BOOL fits = needed <= width + 0.5;

    if (fits) {
        if (!saved) return;
        stack.spacing = plexSpacing;
        if (play) [stack setCustomSpacing:UIStackViewSpacingUseDefault afterView:play];
        objc_setAssociatedObject(stack, PLXPlexSpacingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!saved) objc_setAssociatedObject(stack, PLXPlexSpacingKey, @(plexSpacing), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (stack.spacing != PLXNarrowSpacing) stack.spacing = PLXNarrowSpacing;
    if (play && [stack customSpacingAfterView:play] != PLXNarrowSpacingAfterPlay) {
        [stack setCustomSpacing:PLXNarrowSpacingAfterPlay afterView:play];
    }
    // The share image is drawn 44 pt wide with its own padding; a narrower button
    // would squeeze it, so it scales down evenly instead.
    for (UIButton *icon in icons) icon.imageView.contentMode = UIViewContentModeScaleAspectFit;
}

static void PLXStackLayoutSubviews(UIStackView *self, SEL _cmd) {
    UIView *header = PLXActionRowHeader(self);
    if (header) PLXFitActionRow(self, header);
    ((void (*)(id, SEL))PLXOrigStackLayout)(self, _cmd);
}

__attribute__((constructor)) static void PLXInstallActionRowFit(void) {
    void (^install)(void) = ^{
        static BOOL installed;
        Class stack = NSClassFromString(@"PMStackView");
        if (installed || !stack) return;
        installed = YES;
        Method layout = class_getInstanceMethod(stack, @selector(layoutSubviews));
        if (class_addMethod(stack, @selector(layoutSubviews), (IMP)PLXStackLayoutSubviews, method_getTypeEncoding(layout))) {
            PLXOrigStackLayout = method_getImplementation(class_getInstanceMethod([stack superclass], @selector(layoutSubviews)));
        } else {
            PLXOrigStackLayout = method_setImplementation(layout, (IMP)PLXStackLayoutSubviews);
        }
    };
    install();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { install(); }];
}
