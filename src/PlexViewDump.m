// Debug aid: write the live view hierarchy to Library/PlexViewDump.txt when the
// "plexreborn.viewdump" Darwin notification is posted, so layout problems
// can be diagnosed from the Mac without a debugger attached. Posting it from
// the Mac: xcrun simctl spawn <udid> notifyutil -p plexreborn.viewdump
#import <UIKit/UIKit.h>
#import <notify.h>

CGRect PLXDeskPostureFold(UIView *view);
NSLayoutConstraint *PLXTopEdgeConstraint(UIView *view, UIView *parent);

static void PLXDumpView(UIView *view, NSUInteger depth, NSMutableString *out) {
    CGRect inWindow = view.window ? [view convertRect:view.bounds toView:nil] : view.frame;
    [out appendFormat:@"%@%@ frame=%@ inWindow=%@%@%@\n",
        [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
        NSStringFromClass(view.class),
        NSStringFromCGRect(view.frame),
        NSStringFromCGRect(inWindow),
        view.hidden ? @" hidden" : @"",
        view.layer.sublayers.count ? [NSString stringWithFormat:@" layers=%@", [[view.layer.sublayers valueForKey:@"class"] componentsJoinedByString:@","]] : @""];
    if ([NSStringFromClass(view.class) isEqualToString:@"PMTopPlayerControlsView"]) {
        [out appendFormat:@"  ↳ topConstraint %@ autoresizing=%d\n", PLXTopEdgeConstraint(view, view.superview), view.translatesAutoresizingMaskIntoConstraints];
    }
    if ([NSStringFromClass(view.class) containsString:@"Slider"]) {
        for (CALayer *layer in view.layer.sublayers) {
            [out appendFormat:@"%@  ↳ layer %@ frame=%@ hidden=%d bg=%@\n", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
                NSStringFromClass(layer.class), NSStringFromCGRect(layer.frame), layer.hidden, layer.backgroundColor ? [UIColor colorWithCGColor:layer.backgroundColor] : @"none"];
        }
    }
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        [out appendFormat:@"%@  ↳ gesture %@ enabled=%d state=%ld delegate=%@ targets=%@\n",
            [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
            NSStringFromClass(recognizer.class), recognizer.enabled, (long)recognizer.state,
            NSStringFromClass([recognizer.delegate class]), [[recognizer valueForKey:@"targets"] description].length > 160 ? [[[recognizer valueForKey:@"targets"] description] substringToIndex:160] : [[recognizer valueForKey:@"targets"] description]];
    }
    [out appendFormat:@"%@  userInteraction=%d alpha=%.2f\n", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0], view.userInteractionEnabled, view.alpha];
    for (UIView *subview in view.subviews) PLXDumpView(subview, depth + 1, out);
}

static void PLXDumpAll(void) {
    NSMutableString *out = [NSMutableString string];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray *allScreens = UIScreen.screens;
    @try { allScreens = [UIScreen valueForKey:@"_screens"] ?: allScreens; } @catch (NSException *e) {}
    for (UIScreen *screen in allScreens) {
        [out appendFormat:@"SCREEN %p main=%d bounds=%@ scale=%.1f mirrored=%@\n", screen, screen == UIScreen.mainScreen,
            NSStringFromCGRect(screen.bounds), screen.scale, screen.mirroredScreen];
    }
#pragma clang diagnostic pop
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        [out appendFormat:@"scene bounds=%@ orientation=%ld\n",
            NSStringFromCGRect(windowScene.coordinateSpace.bounds), (long)windowScene.effectiveGeometry.interfaceOrientation];
        for (UIWindow *window in windowScene.windows) {
            if (@available(iOS 27.1, *)) {
                for (UIViewReservedRegion *region in [window reservedRegionsOfKind:[UIViewReservedRegionKind divisionRegionKind] options:UIViewReservedRegionQueryOptionsIncludeInactive]) {
                    [out appendFormat:@"FOLD frame=%@ active=%d desk=%@\n", NSStringFromCGRect(region.frame), region.isActive, NSStringFromCGRect(PLXDeskPostureFold(window))];
                }
            }
            [out appendFormat:@"WINDOW screen=%p %@ level=%.0f key=%d root=%@\n", window.screen, NSStringFromClass(window.class), window.windowLevel,
                window.isKeyWindow, NSStringFromClass(window.rootViewController.class)];
            UIViewController *presented = window.rootViewController;
            while (presented.presentedViewController) {
                presented = presented.presentedViewController;
                [out appendFormat:@"  presented %@ style=%ld\n", NSStringFromClass(presented.class), (long)presented.modalPresentationStyle];
            }
            PLXDumpView(window, 1, out);
        }
    }
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    [out writeToFile:[library stringByAppendingPathComponent:@"PlexViewDump.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

__attribute__((constructor)) static void PLXRegisterViewDump(void) {
    int token;
    notify_register_dispatch("plexreborn.viewdump", &token, dispatch_get_main_queue(), ^(int t) { PLXDumpAll(); });
}
