// Debug aid: write the live view hierarchy to Library/PlexViewDump.txt when the
// "plexreborn.viewdump" Darwin notification is posted, so layout problems
// can be diagnosed from the Mac without a debugger attached. Posting it from
// the Mac: xcrun simctl spawn <udid> notifyutil -p plexreborn.viewdump
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/runtime.h>

CGRect PLXDeskPostureFold(UIView *view);

@interface UIBarButtonItem (PLXDump)
@end
@implementation UIBarButtonItem (PLXDump)
- (NSString *)debugDescriptionForDump {
    return [NSString stringWithFormat:@" [item title=%@ ax=%@ image=%@ %@ custom=%@ menu=%d]", self.title, self.accessibilityLabel,
        NSStringFromCGSize(self.image.size), self.image.isSymbolImage ? @"symbol" : @"bitmap", NSStringFromClass(self.customView.class), self.menu != nil];
}
@end
NSLayoutConstraint *PLXTopEdgeConstraint(UIView *view, UIView *parent);

static void PLXDumpView(UIView *view, NSUInteger depth, NSMutableString *out) {
    CGRect inWindow = view.window ? [view convertRect:view.bounds toView:nil] : view.frame;
    [out appendFormat:@"%@%@ frame=%@ inWindow=%@%@%@%@\n",
        [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
        NSStringFromClass(view.class),
        NSStringFromCGRect(view.frame),
        NSStringFromCGRect(inWindow),
        view.hidden ? @" hidden" : @"",
        ([view isKindOfClass:UINavigationBar.class] ? [[[(UINavigationBar *)view topItem].rightBarButtonItems valueForKey:@"debugDescriptionForDump"] componentsJoinedByString:@" | "] : @""),
        view.layer.sublayers.count ? [NSString stringWithFormat:@" layers=%@", [[view.layer.sublayers valueForKey:@"class"] componentsJoinedByString:@","]] : @""];
    if (!UIEdgeInsetsEqualToEdgeInsets(view.safeAreaInsets, UIEdgeInsetsZero)) {
        [out appendFormat:@"  ↳ safeArea %@\n", NSStringFromUIEdgeInsets(view.safeAreaInsets)];
    }
    if ([view.nextResponder isKindOfClass:UIViewController.class]) {
        UIViewController *vc = (UIViewController *)view.nextResponder;
        [out appendFormat:@"  ↳ controller %@ additionalSafeArea=%@ edges=%lu extendOpaque=%d\n", NSStringFromClass(vc.class),
            NSStringFromUIEdgeInsets(vc.additionalSafeAreaInsets), (unsigned long)vc.edgesForExtendedLayout, vc.extendedLayoutIncludesOpaqueBars];
    }
    if ([view isKindOfClass:UINavigationBar.class]) {
        UINavigationBar *bar = (UINavigationBar *)view;
        [out appendFormat:@"  ↳ navbar translucent=%d prefersLarge=%d standardBg=%@ scrollEdge=%@ barTint=%@\n", bar.translucent, bar.prefersLargeTitles,
            bar.standardAppearance.backgroundColor, bar.scrollEdgeAppearance ? @"set" : @"nil", bar.barTintColor];
    }
    if ([NSStringFromClass(view.class) isEqualToString:@"PMTopPlayerControlsView"]) {
        [out appendFormat:@"  ↳ topConstraint %@ autoresizing=%d\n", PLXTopEdgeConstraint(view, view.superview), view.translatesAutoresizingMaskIntoConstraints];
    }
    // Constraints of the view classes named in Library/PlexConstraintDump.txt (one per line).
    static NSArray<NSString *> *constraintClasses;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
        NSString *list = [NSString stringWithContentsOfFile:[library stringByAppendingPathComponent:@"PlexConstraintDump.txt"] encoding:NSUTF8StringEncoding error:nil];
        constraintClasses = [list componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] ?: @[];
    });
    if ([constraintClasses containsObject:NSStringFromClass(view.class)]) {
        for (NSLayoutConstraint *c in view.constraints) [out appendFormat:@"  ↳ constraint %@\n", c];
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
            [out appendFormat:@"WINDOW screen=%p %@ level=%.0f key=%d root=%@ safeArea=%@\n", window.screen, NSStringFromClass(window.class), window.windowLevel,
                window.isKeyWindow, NSStringFromClass(window.rootViewController.class), NSStringFromUIEdgeInsets(window.safeAreaInsets)];
            if (@available(iOS 27.1, *)) {
                [out appendFormat:@"VERTICALBAR edge=%ld (0 none, 1 leading, 2 trailing)\n", (long)window.traitCollection.verticalBarEdge];
            }
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

// Lists UIKit classes and methods whose names match a pattern, to find private
// API behind a behavior. Pattern comes from Library/PlexClassDumpPattern.txt
// (a regular expression; default matches vertical-bar and tab-bar classes).
static void PLXDumpClasses(void) {
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *pattern = [NSString stringWithContentsOfFile:[library stringByAppendingPathComponent:@"PlexClassDumpPattern.txt"] encoding:NSUTF8StringEncoding error:nil];
    pattern = [pattern stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!pattern.length) pattern = @"VerticalBar|TabBar";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSMutableString *out = [NSMutableString string];
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if (![regex firstMatchInString:name options:0 range:NSMakeRange(0, name.length)]) continue;
        [out appendFormat:@"CLASS %@ : %@\n", name, NSStringFromClass(class_getSuperclass(classes[i]))];
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(classes[i], &methodCount);
        for (unsigned int m = 0; m < methodCount; m++) [out appendFormat:@"  - %@\n", NSStringFromSelector(method_getName(methods[m]))];
        free(methods);
        unsigned int propertyCount = 0;
        objc_property_t *properties = class_copyPropertyList(classes[i], &propertyCount);
        for (unsigned int p = 0; p < propertyCount; p++) [out appendFormat:@"  @ %s\n", property_getName(properties[p])];
        free(properties);
    }
    free(classes);
    [out writeToFile:[library stringByAppendingPathComponent:@"PlexClassDump.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// Which view receives a touch at a point: Library/PlexHitTestPoint.txt holds "x y";
// the chain from the hit view up to the window goes to Library/PlexHitTest.txt.
static void PLXHitTestProbe(void) {
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *parts = [[NSString stringWithContentsOfFile:[library stringByAppendingPathComponent:@"PlexHitTestPoint.txt"] encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByString:@" "];
    if (parts.count < 2) return;
    CGPoint point = CGPointMake([parts[0] doubleValue], [parts[1] doubleValue]);
    NSMutableString *out = [NSMutableString string];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIView *hit = [window hitTest:point withEvent:nil];
            [out appendFormat:@"WINDOW %@ level=%.0f\n", NSStringFromClass(window.class), window.windowLevel];
            for (UIView *v = hit; v; v = v.superview) [out appendFormat:@"  %@ %@\n", NSStringFromClass(v.class), NSStringFromCGRect([v convertRect:v.bounds toView:nil])];
        }
    }
    [out writeToFile:[library stringByAppendingPathComponent:@"PlexHitTest.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

__attribute__((constructor)) static void PLXRegisterViewDump(void) {
    int token, classToken, hitToken;
    notify_register_dispatch("plexreborn.hittest", &hitToken, dispatch_get_main_queue(), ^(int t) { PLXHitTestProbe(); });
    notify_register_dispatch("plexreborn.viewdump", &token, dispatch_get_main_queue(), ^(int t) { PLXDumpAll(); });
    notify_register_dispatch("plexreborn.classdump", &classToken, dispatch_get_main_queue(), ^(int t) { PLXDumpClasses(); });
}
