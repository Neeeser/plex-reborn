// Keeps Plex's video renderer from freezing the app when the Duo folds or
// unfolds during playback.
//
// Plex's mpv renderer draws on its own thread, driven by a display link. When
// the picture's size changes, -[PMKOpenGLRenderLogicBasic resizeFramebuffers]
// runs on that thread and hands the framebuffer resize to the main thread
// with dispatch_sync. Folding changes the picture's size and, at the same
// moment, makes the main thread move the app's display links to the other
// screen, which waits for the render thread's current frame to finish. Each
// thread then waits for the other; the phone's watchdog kills the app after
// 10 seconds (crash reports: "scene-update watchdog transgression", main
// thread in -[CADisplayLink _swapToDisplay:]).
//
// The fix leaves Plex's code alone except for that one wait. Plex's calls to
// dispatch_sync are routed through PLXDispatchSync (its entry in Plex's symbol
// pointer table is replaced), which behaves exactly like dispatch_sync except
// inside resizeFramebuffers on a background thread: there the work is still
// handed to the main thread, but if the main thread has not started it within
// half a second, the render thread does it itself. Whichever side starts first
// runs it, so it runs exactly once.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/mach.h>
#import <stdatomic.h>
#import "PlexReborn.h"

static __thread BOOL PLXInFramebufferResize;
static void (*PLXOrigDispatchSync)(dispatch_queue_t, dispatch_block_t);

// Whichever of the main thread and the render thread claims the resize first runs it.
@interface PLXOnce : NSObject
- (BOOL)claim;
@end
@implementation PLXOnce {
    atomic_flag _taken;
}
- (BOOL)claim { return !atomic_flag_test_and_set(&_taken); }
@end

static const double PLXMainThreadWait = 0.5;

static void PLXDispatchSync(dispatch_queue_t queue, dispatch_block_t block) {
    if (!PLXInFramebufferResize || queue != dispatch_get_main_queue() || NSThread.isMainThread) {
        PLXOrigDispatchSync(queue, block);
        return;
    }
    PLXOnce *once = [PLXOnce new];
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([once claim]) block();
        dispatch_semaphore_signal(finished);
    });
    if (dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PLXMainThreadWait * NSEC_PER_SEC))) == 0) return;
    if ([once claim]) {
        NSLog(@"PlexReborn: main thread busy for %.1f s during a video resize; resizing on the render thread", PLXMainThreadWait);
        block();
        return;
    }
    // The main thread started the resize just now; let it finish.
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
}

static IMP PLXOrigResizeFramebuffers;

static void PLXResizeFramebuffers(id self, SEL _cmd) {
    BOOL outer = PLXInFramebufferResize;
    PLXInFramebufferResize = YES;
    ((void (*)(id, SEL))PLXOrigResizeFramebuffers)(self, _cmd);
    PLXInFramebufferResize = outer;
}

// Points the main executable's symbol pointer for `name` at `replacement`
// and returns the previous target. Plex calls libdispatch through these
// pointers (its __DATA_CONST,__got section), so only Plex's own calls change.
static void *PLXRebindMainExecutableSymbol(const char *name, void *replacement) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (header->filetype != MH_EXECUTE) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct segment_command_64 *linkedit = NULL;
        const struct symtab_command *symtab = NULL;
        const struct dysymtab_command *dysymtab = NULL;
        const struct load_command *cmd = (const struct load_command *)(header + 1);
        for (uint32_t c = 0; c < header->ncmds; c++, cmd = (const struct load_command *)((const char *)cmd + cmd->cmdsize)) {
            if (cmd->cmd == LC_SEGMENT_64 && strcmp(((const struct segment_command_64 *)cmd)->segname, SEG_LINKEDIT) == 0) linkedit = (const void *)cmd;
            else if (cmd->cmd == LC_SYMTAB) symtab = (const void *)cmd;
            else if (cmd->cmd == LC_DYSYMTAB) dysymtab = (const void *)cmd;
        }
        if (!linkedit || !symtab || !dysymtab) return NULL;
        uintptr_t base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
        const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff);
        const char *strings = (const char *)(base + symtab->stroff);
        const uint32_t *indirect = (const uint32_t *)(base + dysymtab->indirectsymoff);
        void *previous = NULL;
        cmd = (const struct load_command *)(header + 1);
        for (uint32_t c = 0; c < header->ncmds; c++, cmd = (const struct load_command *)((const char *)cmd + cmd->cmdsize)) {
            if (cmd->cmd != LC_SEGMENT_64) continue;
            const struct segment_command_64 *segment = (const void *)cmd;
            const struct section_64 *section = (const struct section_64 *)(segment + 1);
            for (uint32_t s = 0; s < segment->nsects; s++, section++) {
                uint32_t type = section->flags & SECTION_TYPE;
                if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) continue;
                void **pointers = (void **)((uintptr_t)slide + section->addr);
                for (uint64_t p = 0; p < section->size / sizeof(void *); p++) {
                    uint32_t index = indirect[section->reserved1 + p];
                    if (index == INDIRECT_SYMBOL_ABS || index == INDIRECT_SYMBOL_LOCAL || index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
                    if (strcmp(strings + symbols[index].n_un.n_strx, name) != 0) continue;
                    vm_address_t page = trunc_page((vm_address_t)&pointers[p]);
                    if (vm_protect(mach_task_self(), page, vm_page_size, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) continue;
                    if (!previous) previous = pointers[p];
                    pointers[p] = replacement;
                    vm_protect(mach_task_self(), page, vm_page_size, false, VM_PROT_READ);
                }
            }
        }
        return previous;
    }
    return NULL;
}

static void PLXInstallRenderHandoff(void) {
    static BOOL installed;
    Class logic = NSClassFromString(@"PMKOpenGLRenderLogicBasic");
    if (installed || !logic) return;
    installed = YES;
    Method resize = class_getInstanceMethod(logic, NSSelectorFromString(@"resizeFramebuffers"));
    if (!resize) return;
    BOOL rebind = YES;
#if TARGET_OS_SIMULATOR
    // Lets the regression test watch the freeze without the fix.
    rebind = !NSProcessInfo.processInfo.environment[@"PLX_TEST_NO_RENDER_HANDOFF"];
#endif
    if (rebind) {
        void *previous = PLXRebindMainExecutableSymbol("_dispatch_sync", (void *)PLXDispatchSync);
        if (!previous) return;
        PLXOrigDispatchSync = previous;
    }
    PLXOrigResizeFramebuffers = method_setImplementation(resize, (IMP)PLXResizeFramebuffers);
}

#if TARGET_OS_SIMULATOR
#import <notify.h>
// Regression test. Recreates the freeze from the crash reports: the main
// thread waits for another thread while that thread runs Plex's framebuffer
// resize, which hands work to the main thread. Without the fix the main
// thread gives up after 3 seconds and reports a freeze; with it, the resize
// finishes on its own thread. The simulator plays video through a different
// Plex renderer, so the test runs the phone's renderer code on a bare
// instance (no GL context, so its drawing calls do nothing):
//   xcrun simctl spawn <udid> notifyutil -p plexreborn.resizetest
// The result is in Library/PlexResizeTest.txt and the log.
static void PLXRunResizeTest(void) {
    Class logicClass = NSClassFromString(@"PMKOpenGLRenderLogicBasic");
    id logic = logicClass ? class_createInstance(logicClass, 0) : nil;
    NSString *result;
    if (!logic) {
        result = @"PMKOpenGLRenderLogicBasic not found";
    } else {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        [NSThread detachNewThreadWithBlock:^{
            ((void (*)(id, SEL))objc_msgSend)(logic, NSSelectorFromString(@"resizeFramebuffers"));
            dispatch_semaphore_signal(done);
        }];
        BOOL finished = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0;
        double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
        result = finished ? [NSString stringWithFormat:@"PASS: resize finished in %.0f ms while the main thread was busy", ms]
                          : @"FAIL: freeze, the main thread waited 3 s and the resize never finished";
    }
    NSLog(@"PlexReborn: resize test: %@", result);
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"PlexResizeTest.txt"];
    [result writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
#endif

__attribute__((constructor)) static void PLXInstallRenderHandoffAtLoad(void) {
    PLXInstallRenderHandoff();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { PLXInstallRenderHandoff(); }];
#if TARGET_OS_SIMULATOR
    int token;
    notify_register_dispatch("plexreborn.resizetest", &token, dispatch_get_main_queue(), ^(int t) { PLXRunResizeTest(); });
#endif
}
