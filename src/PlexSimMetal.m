// Simulator-only: close Metal command encoders Plex abandons.
//
// One of Plex's layer-drawing paths creates a render command encoder and lets
// it deallocate without calling endEncoding. Devices tolerate this; the
// simulator's Metal serializer asserts and aborts the app during the first
// frame. Tracking endEncoding and finishing any open encoder in dealloc keeps
// the simulator usable for UI testing. It is never compiled into device builds.
#import <TargetConditionals.h>
#if TARGET_OS_SIMULATOR
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>

static const void *PLXEncoderEndedKey = &PLXEncoderEndedKey;

static void PLXPatchEncoderClass(NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) return;

    Method endMethod = class_getInstanceMethod(cls, @selector(endEncoding));
    Method deallocMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"dealloc"));
    if (!endMethod || !deallocMethod) return;

    IMP originalEnd = method_getImplementation(endMethod);
    IMP originalDealloc = method_getImplementation(deallocMethod);

    // Each class gets its own wrappers so subclasses do not double-wrap a parent's IMP.
    IMP newEnd = imp_implementationWithBlock(^(id self) {
        objc_setAssociatedObject(self, PLXEncoderEndedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ((void (*)(id, SEL))originalEnd)(self, @selector(endEncoding));
    });
    IMP newDealloc = imp_implementationWithBlock(^(__unsafe_unretained id self) {
        if (!objc_getAssociatedObject(self, PLXEncoderEndedKey)) {
            ((void (*)(id, SEL))originalEnd)(self, @selector(endEncoding));
        }
        ((void (*)(id, SEL))originalDealloc)(self, NSSelectorFromString(@"dealloc"));
    });
    class_replaceMethod(cls, @selector(endEncoding), newEnd, method_getTypeEncoding(endMethod));
    class_replaceMethod(cls, NSSelectorFromString(@"dealloc"), newDealloc, method_getTypeEncoding(deallocMethod));
}

static NSMutableSet<NSString *> *PLXPatchedClasses;

static void PLXPatchAvailableEncoders(void) {
    // Patch the outermost encoder classes the simulator hands out; the
    // serializer wraps the real encoder, so finishing it finishes both.
    for (NSString *name in @[ @"MTLSerializerRenderCommandEncoder",
                              @"MTLSerializerComputeCommandEncoder",
                              @"MTLSerializerBlitCommandEncoder" ]) {
        if ([PLXPatchedClasses containsObject:name] || !NSClassFromString(name)) continue;
        PLXPatchEncoderClass(name);
        [PLXPatchedClasses addObject:name];
    }
}

static void PLXImageAdded(const struct mach_header *header, intptr_t slide) {
    // MetalSerializer loads lazily when Metal first starts, after this library.
    PLXPatchAvailableEncoders();
}

__attribute__((constructor)) static void PLXInstallSimulatorMetalFix(void) {
    PLXPatchedClasses = [NSMutableSet set];
    _dyld_register_func_for_add_image(PLXImageAdded);
}
#endif
