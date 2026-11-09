// Keep a stream playing through a single failed keep-alive check.
//
// While a transcoded stream plays, Plex asks the server every 30 seconds
// whether the transcode session is still alive (/video/:/transcode/universal/ping).
// Any network error on that request, or a 404, makes Plex declare the session
// expired: it stops the player, starts a new transcode and reopens the video
// at the same position, which shows as a pause, a reload and a reset of the
// zoom. Over Plex's relay a reused connection is often closed by the relay,
// so the request fails within a fraction of a second while the video itself
// is still streaming fine (11 of 51 checks in one 27-minute session).
//
// When a check fails, the same request is sent again on a fresh connection a
// few times. If the server answers, the session is alive and the expiry is
// dropped. If the server answers 404, or every retry fails, Plex restarts the
// stream as before.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *const PLXPingPath = @"/video/:/transcode/universal/ping";
static const NSInteger PLXPingRetries = 3;
static const NSTimeInterval PLXPingRetryDelay = 2;

static NSURLRequest *PLXLastPing;

static BOOL PLXIsPingRequest(NSURLRequest *request) {
    return [request.URL.path isEqualToString:PLXPingPath];
}

#if TARGET_OS_SIMULATOR
// Simulator test hook: with PLX_TEST_FAIL_PING=1 in the launch environment,
// the first keep-alive check is sent to a closed port so it fails the way a
// dropped relay connection does.
static NSURLRequest *PLXTestFailFirstPing(NSURLRequest *request) {
    static BOOL failed;
    if (failed || !getenv("PLX_TEST_FAIL_PING")) return request;
    failed = YES;
    NSLog(@"PlexReborn: test: failing this keep-alive check");
    NSMutableURLRequest *broken = [request mutableCopy];
    NSURLComponents *components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    components.host = @"127.0.0.1";
    components.port = @1;
    broken.URL = components.URL;
    return broken;
}
#endif

#if TARGET_OS_SIMULATOR
// Simulator test hook: with PLX_TEST_FORCE_RELAY=1 in the launch environment,
// requests to the server's direct addresses (LAN and WAN) go to a closed port,
// so Plex falls back to its relay (port 8443) the way a phone away from home
// does, and the stream is transcoded as it is there.
static NSURLRequest *PLXTestForceRelay(NSURLRequest *request) {
    if (!getenv("PLX_TEST_FORCE_RELAY")) return request;
    NSURLComponents *components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    NSString *host = components.host.lowercaseString;
    BOOL direct = [host hasSuffix:@".plex.direct"] && components.port.integerValue != 8443;
    // The app's own embedded server listens on the loopback address.
    BOOL rawAddress = [host rangeOfString:@"^[0-9.]+$" options:NSRegularExpressionSearch].location != NSNotFound && ![host hasPrefix:@"127."];
    if (!direct && !rawAddress) return request;
    NSMutableURLRequest *broken = [request mutableCopy];
    components.host = @"127.0.0.1";
    components.port = @1;
    broken.URL = components.URL;
    return broken;
}
#endif

static NSURLRequest *PLXObserveRequest(NSURLRequest *request) {
#if TARGET_OS_SIMULATOR
    request = PLXTestForceRelay(request);
#endif
    if (!PLXIsPingRequest(request)) return request;
    @synchronized (PLXPingPath) { PLXLastPing = [request copy]; }
#if TARGET_OS_SIMULATOR
    request = PLXTestFailFirstPing(request);
#endif
    return request;
}

static IMP PLXOrigDataTask, PLXOrigDataTaskHandler;

static id PLXDataTask(NSURLSession *self, SEL _cmd, NSURLRequest *request) {
    return ((id (*)(id, SEL, id))PLXOrigDataTask)(self, _cmd, PLXObserveRequest(request));
}

static id PLXDataTaskHandler(NSURLSession *self, SEL _cmd, NSURLRequest *request, id handler) {
    return ((id (*)(id, SEL, id, id))PLXOrigDataTaskHandler)(self, _cmd, PLXObserveRequest(request), handler);
}

// A session of its own, so each retry opens a new connection instead of
// reusing the one the relay closed.
static NSURLSession *PLXRetrySession(void) {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = 10;
    config.HTTPMaximumConnectionsPerHost = 1;
    return [NSURLSession sessionWithConfiguration:config];
}

// Retries the check; calls done(YES) when the server confirms the session.
static void PLXRetryPing(NSURLRequest *ping, NSInteger attemptsLeft, void (^done)(BOOL alive)) {
    NSURLSession *session = PLXRetrySession();
    NSURLSessionDataTask *task = ((id (*)(id, SEL, id, id))PLXOrigDataTaskHandler)(session, @selector(dataTaskWithRequest:completionHandler:), ping,
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            [session finishTasksAndInvalidate];
            NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
            if (status == 200) { done(YES); return; }
            // 404 means the server ended the transcode; Plex has to start a new one.
            if (status == 404 || attemptsLeft <= 1) { done(NO); return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PLXPingRetryDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                PLXRetryPing(ping, attemptsLeft - 1, done);
            });
        });
    [task resume];
}

static IMP PLXOrigItemDidExpire;
static const void *PLXRetryingKey = &PLXRetryingKey;

static void PLXItemDidExpire(id self, SEL _cmd, id item) {
    NSURLRequest *ping;
    @synchronized (PLXPingPath) { ping = PLXLastPing; }
    // A failed check while one is already being retried changes nothing.
    if (item && objc_getAssociatedObject(item, PLXRetryingKey)) return;
    if (!ping || !item) {
        ((void (*)(id, SEL, id))PLXOrigItemDidExpire)(self, _cmd, item);
        return;
    }
    objc_setAssociatedObject(item, PLXRetryingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"PlexReborn: keep-alive check failed, checking again before restarting the stream");
    __weak id weakSelf = self;
    PLXRetryPing(ping, PLXPingRetries, ^(BOOL alive) {
        dispatch_async(dispatch_get_main_queue(), ^{
            objc_setAssociatedObject(item, PLXRetryingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            id session = weakSelf;
            if (!session) return;
            if (alive) {
                NSLog(@"PlexReborn: stream session is alive, keeping playback going");
                [item setValue:@NO forKey:@"hasExpired"];
                return;
            }
            NSLog(@"PlexReborn: stream session is gone, letting Plex restart it");
            ((void (*)(id, SEL, id))PLXOrigItemDidExpire)(session, _cmd, item);
        });
    });
}

__attribute__((constructor)) static void PLXInstallStreamKeepAlive(void) {
    Class sessionClass = NSClassFromString(@"PMKPlaybackSession");
    Method expire = sessionClass ? class_getInstanceMethod(sessionClass, NSSelectorFromString(@"playbackSessionItemDidExpire:")) : NULL;
    if (!expire) return;
    PLXOrigItemDidExpire = method_setImplementation(expire, (IMP)PLXItemDidExpire);
    Class urlSession = NSURLSession.class;
    PLXOrigDataTask = method_setImplementation(class_getInstanceMethod(urlSession, @selector(dataTaskWithRequest:)), (IMP)PLXDataTask);
    PLXOrigDataTaskHandler = method_setImplementation(class_getInstanceMethod(urlSession, @selector(dataTaskWithRequest:completionHandler:)), (IMP)PLXDataTaskHandler);
}
