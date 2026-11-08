// Center Plex's navigation bar buttons inside their glass platter slots.
//
// Plex wraps its navigation bar buttons (PMSymbolButton) in custom views and
// pins some of them off-center for the pre-iOS 26 bar. In the iOS 26 glass
// platter each slot is 40 pt and the ellipsis button sits 7 pt right of
// center, so it crowds the platter's right edge while the cast button has
// room on its left. After layout, any horizontal constraint that holds the
// button off-center in its slot is shifted so the button is centered.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static IMP PLXOrigSymbolButtonLayout;

static BOOL PLXInNavigationBarSlot(UIView *button) {
    UIView *wrapper = button.superview.superview;
    return wrapper && [NSStringFromClass(wrapper.class) containsString:@"ItemWrapperView"];
}

static void PLXSymbolButtonLayoutSubviews(UIButton *self, SEL _cmd) {
    ((void (*)(id, SEL))PLXOrigSymbolButtonLayout)(self, _cmd);
    if (!PLXInNavigationBarSlot(self)) return;
    UIView *slot = self.superview;
    CGFloat offset = CGRectGetMidX(self.frame) - CGRectGetMidX(slot.bounds);
    if (fabs(offset) < 0.5) return;
    for (NSLayoutConstraint *c in slot.constraints) {
        NSLayoutAttribute a = c.firstItem == self ? c.firstAttribute : (c.secondItem == self ? c.secondAttribute : NSLayoutAttributeNotAnAttribute);
        if (a != NSLayoutAttributeLeading && a != NSLayoutAttributeTrailing && a != NSLayoutAttributeLeft &&
            a != NSLayoutAttributeRight && a != NSLayoutAttributeCenterX) continue;
        // Moving the button left by `offset` means: button.attr = slot.attr + k  ->  k - offset;
        // slot.attr = button.attr + k  ->  k + offset.
        c.constant += (c.firstItem == self) ? -offset : offset;
        return;
    }
}

__attribute__((constructor)) static void PLXInstallNavButtonCentering(void) {
    void (^install)(void) = ^{
        static BOOL installed;
        Class button = NSClassFromString(@"PMSymbolButton");
        if (installed || !button) return;
        installed = YES;
        Method layout = class_getInstanceMethod(button, @selector(layoutSubviews));
        if (class_addMethod(button, @selector(layoutSubviews), (IMP)PLXSymbolButtonLayoutSubviews, method_getTypeEncoding(layout))) {
            PLXOrigSymbolButtonLayout = method_getImplementation(class_getInstanceMethod([button superclass], @selector(layoutSubviews)));
        } else {
            PLXOrigSymbolButtonLayout = method_setImplementation(layout, (IMP)PLXSymbolButtonLayoutSubviews);
        }
    };
    install();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { install(); }];
}
