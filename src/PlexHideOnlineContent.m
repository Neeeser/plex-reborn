// Hide Plex's online content (Movies & Shows, Rentals, Discover) when the
// "Hide Plex's online content" setting is on.
//
// Plex pins sources from its own online providers next to the person's
// libraries: they appear in the side menu and add their hubs to Home. Plex's
// source manager returns those pinned sources to every screen, so filtering
// its list removes them everywhere at once. The Watchlist is kept: it also
// comes from Plex's Discover provider but holds the person's own list.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "PlexReborn.h"

// Plex's source type for the Watchlist (PMKSource.type).
static const NSInteger PLXSourceTypeWatchlist = 20;

static BOOL PLXIsPlexOnlineSource(id source) {
    if (![source respondsToSelector:@selector(providerIdentifier)]) return NO;
    NSString *provider = [source valueForKey:@"providerIdentifier"];
    if (![provider isKindOfClass:NSString.class] || ![provider hasPrefix:@"tv.plex.provider."]) return NO;
    if ([provider isEqualToString:@"tv.plex.provider.vod"]) return YES;
    if ([provider isEqualToString:@"tv.plex.provider.discover"]) return [[source valueForKey:@"type"] integerValue] != PLXSourceTypeWatchlist;
    return NO;
}

static IMP PLXOrigPinnedSources;
static __weak id PLXSourceManager;

static id PLXPinnedSources(id self, SEL _cmd) {
    PLXSourceManager = self;
    NSArray *sources = ((id (*)(id, SEL))PLXOrigPinnedSources)(self, _cmd);
    if (!PLXSettingBool(PLXSettingHideOnlineContent) || ![sources isKindOfClass:NSArray.class]) return sources;
    NSIndexSet *keep = [sources indexesOfObjectsPassingTest:^BOOL(id s, NSUInteger i, BOOL *stop) { return !PLXIsPlexOnlineSource(s); }];
    return keep.count == sources.count ? sources : [sources objectsAtIndexes:keep];
}

__attribute__((constructor)) static void PLXInstallHideOnline(void) {
    Class c = NSClassFromString(@"PMSourceManager");
    Method m = c ? class_getInstanceMethod(c, @selector(pinnedSources)) : NULL;
    if (!m) return;
    PLXOrigPinnedSources = method_setImplementation(m, (IMP)PLXPinnedSources);
    // Plex rebuilds the side menu and Home when its source manager reports a
    // change. Only this setting needs that reload, so other settings don't trigger it.
    __block BOOL hidden = PLXSettingBool(PLXSettingHideOnlineContent);
    [NSNotificationCenter.defaultCenter addObserverForName:PLXSettingsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *note) {
            if (PLXSettingBool(PLXSettingHideOnlineContent) == hidden) return;
            hidden = !hidden;
            id manager = PLXSourceManager;
            if ([manager respondsToSelector:@selector(notifyUpdate)]) [manager performSelector:@selector(notifyUpdate)];
        }];
}
