// Plex's own sheets reach the screen edge beside the Duo's vertical bar.
//
// Plex presents some sheets (for example the server picker) with its own
// UIPresentationController subclasses, which size the sheet to the safe area.
// With the Duo's vertical bar showing, the sheet stops 84 pt short of the
// screen edge with a square corner. Apple's Duo guidance is that backgrounds
// extend to the edge while interactive content stays inside the safe area; a
// view that reaches the edge gets the bar's inset as its own safe area, so
// table rows and other safe-area-aware content still stay clear of the bar.
// Every presentation controller class defined in Plex's binary gets its
// presented frame extended across the bar's strip when the frame ends exactly
// at the strip.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>

static NSMutableDictionary<NSString *, NSValue *> *PLXOriginalFrameIMPs;

static CGRect PLXExtendedPresentedFrame(UIPresentationController *self, SEL _cmd) {
    IMP original = PLXOriginalFrameIMPs[NSStringFromClass(object_getClass(self))].pointerValue;
    Class cls = object_getClass(self);
    while (!original && (cls = class_getSuperclass(cls))) original = PLXOriginalFrameIMPs[NSStringFromClass(cls)].pointerValue;
    CGRect frame = original ? ((CGRect (*)(id, SEL))original)(self, _cmd) : CGRectZero;

    UIView *container = self.containerView;
    if (!container) return frame;
    NSInteger edge = 0;
    if (@available(iOS 27.1, *)) edge = container.traitCollection.verticalBarEdge;
    if (edge == 0) return frame;
    UIEdgeInsets safe = container.safeAreaInsets;
    CGFloat width = CGRectGetWidth(container.bounds);
    BOOL rightToLeft = container.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    BOOL barOnRight = (edge == 2) != rightToLeft;
    if (barOnRight && safe.right > 0 && fabs(CGRectGetMaxX(frame) - (width - safe.right)) < 1) {
        frame.size.width = width - CGRectGetMinX(frame);
    } else if (!barOnRight && safe.left > 0 && fabs(CGRectGetMinX(frame) - safe.left) < 1) {
        frame.size.width += frame.origin.x;
        frame.origin.x = 0;
    }
    return frame;
}

static void PLXPatchPresentationControllers(void) {
    PLXOriginalFrameIMPs = [NSMutableDictionary dictionary];
    const char *mainImage = _dyld_get_image_name(0);
    unsigned int count = 0;
    const char **names = objc_copyClassNamesForImage(mainImage, &count);
    Class base = [UIPresentationController class];
    SEL selector = @selector(frameOfPresentedViewInContainerView);
    for (unsigned int i = 0; i < count; i++) {
        Class cls = objc_getClass(names[i]);
        BOOL isPresentationController = NO;
        for (Class c = class_getSuperclass(cls); c; c = class_getSuperclass(c)) if (c == base) { isPresentationController = YES; break; }
        if (!isPresentationController) continue;
        // Only classes that implement the method themselves; subclasses fall through to their parent's wrapper.
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned int m = 0; m < methodCount; m++) {
            if (method_getName(methods[m]) != selector) continue;
            IMP old = method_setImplementation(methods[m], (IMP)PLXExtendedPresentedFrame);
            PLXOriginalFrameIMPs[NSStringFromClass(cls)] = [NSValue valueWithPointer:(const void *)old];
        }
        free(methods);
    }
    free(names);
}

__attribute__((constructor)) static void PLXInstallSheetWidthFix(void) {
    // Plex's Swift classes are registered once the main image has loaded.
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            static dispatch_once_t once;
            dispatch_once(&once, ^{ PLXPatchPresentationControllers(); });
        }];
}
