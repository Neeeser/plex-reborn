// Load artwork that lives on the local network directly.
//
// Plex loads every image through its server's photo transcoder
// (/photo/:/transcode?url=...). Live TV & DVR sources from IPTV tools give
// absolute URLs on the local network for channel logos and show posters
// (http://192.168.x.x:port/...), and current Plex Media Server versions answer
// those transcode requests with 404, so Home's Live TV rows and the guide had
// blank artwork. Requests whose image URL points at a private network address
// are sent straight to that address instead; every other image still goes
// through the server.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <arpa/inet.h>

static BOOL PLXIsPrivateIPv4(NSString *host) {
    struct in_addr addr;
    if (inet_pton(AF_INET, host.UTF8String, &addr) != 1) return NO;
    uint32_t ip = ntohl(addr.s_addr);
    return (ip >> 24) == 10 || (ip >> 20) == (172 << 4 | 1) || (ip >> 16) == (192 << 8 | 168);
}

// The local image URL a transcode request wraps, or nil.
static NSURL *PLXDirectImageURL(NSURL *url) {
    if (![url.path isEqualToString:@"/photo/:/transcode"]) return nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if (![item.name isEqualToString:@"url"]) continue;
        NSURL *inner = [NSURL URLWithString:item.value];
        BOOL web = [inner.scheme isEqualToString:@"http"] || [inner.scheme isEqualToString:@"https"];
        return web && PLXIsPrivateIPv4(inner.host) ? inner : nil;
    }
    return nil;
}

static NSURLRequest *PLXDirectRequest(NSURLRequest *request) {
    NSURL *direct = PLXDirectImageURL(request.URL);
    if (!direct) return request;
    return [NSURLRequest requestWithURL:direct cachePolicy:request.cachePolicy timeoutInterval:request.timeoutInterval];
}

static IMP PLXOrigDataTask, PLXOrigDataTaskHandler;

static id PLXDataTask(NSURLSession *self, SEL _cmd, NSURLRequest *request) {
    return ((id (*)(id, SEL, id))PLXOrigDataTask)(self, _cmd, PLXDirectRequest(request));
}

static id PLXDataTaskHandler(NSURLSession *self, SEL _cmd, NSURLRequest *request, id handler) {
    return ((id (*)(id, SEL, id, id))PLXOrigDataTaskHandler)(self, _cmd, PLXDirectRequest(request), handler);
}

__attribute__((constructor)) static void PLXInstallLocalImages(void) {
    Class session = NSURLSession.class;
    PLXOrigDataTask = method_setImplementation(class_getInstanceMethod(session, @selector(dataTaskWithRequest:)), (IMP)PLXDataTask);
    PLXOrigDataTaskHandler = method_setImplementation(class_getInstanceMethod(session, @selector(dataTaskWithRequest:completionHandler:)), (IMP)PLXDataTaskHandler);
}

