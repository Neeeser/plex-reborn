// Simulator-only: never report watch progress to the Plex server.
//
// Test playback in the simulator otherwise sends /:/timeline, /:/scrobble and
// /:/progress requests that overwrite the owner's real resume position and
// watched state. Rewriting those requests to an unroutable address makes them
// fail locally while everything else (browsing, streaming) works as normal.
#import <TargetConditionals.h>
#if TARGET_OS_SIMULATOR
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static BOOL PLXIsProgressRequest(NSURLRequest *request) {
    NSString *path = request.URL.path;
    return [path hasPrefix:@"/:/timeline"] || [path hasPrefix:@"/:/scrobble"] ||
           [path hasPrefix:@"/:/unscrobble"] || [path hasPrefix:@"/:/progress"];
}

static NSURLRequest *PLXBlockedRequest(NSURLRequest *request) {
    NSMutableURLRequest *blocked = [request mutableCopy];
    blocked.URL = [NSURL URLWithString:@"http://127.0.0.1:9/blocked-by-plex-duo-test"];
    return blocked;
}

// Patch every session class that has its own implementation (NSURLSession is
// a class cluster; real sessions are private subclasses), each with a block
// that calls that class's original method.
static void PLXPatchSessionClass(Class cls) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL name = method_getName(methods[i]);
        if (name == @selector(dataTaskWithRequest:)) {
            IMP original = method_getImplementation(methods[i]);
            method_setImplementation(methods[i], imp_implementationWithBlock(^id(id self, NSURLRequest *request) {
                if (PLXIsProgressRequest(request)) request = PLXBlockedRequest(request);
                return ((id (*)(id, SEL, id))original)(self, name, request);
            }));
        } else if (name == @selector(dataTaskWithRequest:completionHandler:)) {
            IMP original = method_getImplementation(methods[i]);
            method_setImplementation(methods[i], imp_implementationWithBlock(^id(id self, NSURLRequest *request, id handler) {
                if (PLXIsProgressRequest(request)) request = PLXBlockedRequest(request);
                return ((id (*)(id, SEL, id, id))original)(self, name, request, handler);
            }));
        }
    }
    free(methods);
}

__attribute__((constructor)) static void PLXInstallNoProgress(void) {
    for (NSString *name in @[ @"NSURLSession", @"__NSURLSessionLocal", @"__NSCFURLSession" ]) {
        Class cls = NSClassFromString(name);
        if (cls) PLXPatchSessionClass(cls);
    }
}
#endif
