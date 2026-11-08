// Hide Plex's online content, each kind on its own setting.
//
// Plex mixes sources from its own online providers in with the person's
// libraries: Movies & Shows and Rentals (tv.plex.provider.vod), Discover
// (tv.plex.provider.discover) and its free Live TV channels
// (tv.plex.provider.epg). They appear in the side menu and the More page, add
// rows to Home, and Plex's channels fill the Live TV guide beside a server's
// own DVR channels. The lists screens read are filtered: Plex's pinned
// sources (side menu, Home), the More page's list and the guide's sources.
// Plex's full source list is left alone: Home's Trending, Activity, Find
// Friends and My Profile tabs come from the Discover source in it. The
// Watchlist is kept too: it also comes from the Discover provider but holds
// the person's own list.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "PlexReborn.h"

// Plex's source types (PMKSource.type) used below.
static const NSInteger PLXSourceTypeRentals = 21;
static const NSInteger PLXSourceTypeWatchlist = 20;

// The setting that hides this source, or nil when the source is not Plex's online content.
static NSString *PLXHideSettingForSource(id source) {
    if (![source respondsToSelector:NSSelectorFromString(@"providerIdentifier")]) return nil;
    NSString *provider = [source valueForKey:@"providerIdentifier"];
    if (![provider isKindOfClass:NSString.class]) return nil;
    NSInteger type = [[source valueForKey:@"type"] integerValue];
    if ([provider isEqualToString:@"tv.plex.provider.vod"]) return type == PLXSourceTypeRentals ? PLXSettingHideRentals : PLXSettingHideMoviesAndShows;
    if ([provider isEqualToString:@"tv.plex.provider.discover"]) return type == PLXSourceTypeWatchlist ? nil : PLXSettingHideDiscover;
    if ([provider isEqualToString:@"tv.plex.provider.epg"]) return PLXSettingHidePlexLiveTV;
    return nil;
}

static BOOL PLXIsHidden(id source) {
    NSString *setting = PLXHideSettingForSource(source);
    return setting && PLXSettingBool(setting);
}

// Plex's own Live TV source is also the side menu's way into Live TV, the
// guide that holds a server's DVR channels too, so it stays in the source
// lists; only the guide's own list drops it (guide: YES).
static id PLXFiltered(id sources, BOOL guide) {
    if (![sources isKindOfClass:NSArray.class]) return sources;
    NSIndexSet *keep = [sources indexesOfObjectsPassingTest:^BOOL(id s, NSUInteger i, BOOL *stop) {
        if (!guide && [PLXHideSettingForSource(s) isEqualToString:PLXSettingHidePlexLiveTV]) return YES;
        return !PLXIsHidden(s);
    }];
    return keep.count == [sources count] ? sources : [sources objectsAtIndexes:keep];
}

static __weak id PLXSourceManager;
static IMP PLXOrigPinnedSources, PLXOrigGuideSources, PLXOrigMainGuideSource;

static id PLXPinnedSources(id self, SEL _cmd) {
    PLXSourceManager = self;
    return PLXFiltered(((id (*)(id, SEL))PLXOrigPinnedSources)(self, _cmd), NO);
}

// The Live TV guide's sources: a server's DVR and Plex's own channels.
static id PLXGuideSources(id self, SEL _cmd) {
    return PLXFiltered(((id (*)(id, SEL))PLXOrigGuideSources)(self, _cmd), YES);
}

// Plex opens the guide on its own channels; with those hidden, on the first remaining source.
static id PLXMainGuideSource(id self, SEL _cmd) {
    id source = ((id (*)(id, SEL))PLXOrigMainGuideSource)(self, _cmd);
    if (!PLXIsHidden(source)) return source;
    id remaining = PLXFiltered(((id (*)(id, SEL))PLXOrigGuideSources)(self, NSSelectorFromString(@"hybridGuideSources")), YES);
    return [remaining isKindOfClass:NSArray.class] ? [remaining firstObject] : nil;
}

// The More page lists every source grouped by server (sourcesByServer: one
// array per server), built from the server objects rather than the source
// lists above. Each server's array is filtered as Plex stores it, before the
// page counts its rows; Plex's own Live TV row goes too, since the side menu
// keeps its own way into Live TV.
static IMP PLXOrigSetSourcesByServer;

static void PLXSetSourcesByServer(id self, SEL _cmd, NSArray *byServer) {
    if ([byServer isKindOfClass:NSArray.class]) {
        NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:byServer.count];
        for (id sources in byServer) [filtered addObject:PLXFiltered(sources, YES)];
        byServer = filtered;
    }
    ((void (*)(id, SEL, id))PLXOrigSetSourcesByServer)(self, _cmd, byServer);
}

// Plex also has its own switch for leaving its channels out of Live TV
// (PMSourceManager.isLiveTVCloudProviderDisabled), but with it on Plex removes
// the whole Live TV entry, server channels included.

static void PLXReplace(Class cls, NSString *name, IMP replacement, IMP *original) {
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (m) *original = method_setImplementation(m, replacement);
}

static NSArray<NSNumber *> *PLXHideValues(void) {
    return @[@(PLXSettingBool(PLXSettingHideMoviesAndShows)), @(PLXSettingBool(PLXSettingHideRentals)),
             @(PLXSettingBool(PLXSettingHideDiscover)), @(PLXSettingBool(PLXSettingHidePlexLiveTV))];
}

__attribute__((constructor)) static void PLXInstallHideOnline(void) {
    Class manager = NSClassFromString(@"PMSourceManager");
    if (!manager) return;
    PLXReplace(manager, @"pinnedSources", (IMP)PLXPinnedSources, &PLXOrigPinnedSources);
    PLXReplace(manager, @"hybridGuideSources", (IMP)PLXGuideSources, &PLXOrigGuideSources);
    PLXReplace(manager, @"mainGuideSource", (IMP)PLXMainGuideSource, &PLXOrigMainGuideSource);
    Class more = NSClassFromString(@"PMMoreSourcesListViewModel");
    if (more) PLXReplace(more, @"setSourcesByServer:", (IMP)PLXSetSourcesByServer, &PLXOrigSetSourcesByServer);

    // Plex rebuilds the side menu, More page and Home when its source manager
    // reports a change. Only these settings need that reload.
    __block NSArray *last = PLXHideValues();
    [NSNotificationCenter.defaultCenter addObserverForName:PLXSettingsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *note) {
            NSArray *now = PLXHideValues();
            if ([now isEqualToArray:last]) return;
            last = now;
            id sourceManager = PLXSourceManager;
            SEL notify = NSSelectorFromString(@"notifyUpdate");
            if ([sourceManager respondsToSelector:notify]) ((void (*)(id, SEL))objc_msgSend)(sourceManager, notify);
        }];
}
