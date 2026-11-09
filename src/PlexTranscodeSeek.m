// Seeking in transcoded streams.
//
// Away from home Plex often streams a transcoded HLS stream (through its relay
// when the server is not reachable directly) and plays it with mpv. Seeking
// inside that stream can land far from the target: mpv asks the server for the
// segment at the target, the server's playlist has moved on, and ffmpeg jumps
// to the newest segments it lists ("maybe the m3u8 list sequence have been
// wraped"). On an iPhone over the relay, targets of 7:07, 7:13, 7:20 and 7:23
// all resumed between 7:44 and 7:52; in the simulator a seek back to 11:05
// resumed at 20:33. When the player says it cannot seek to a time, Plex instead
// soft-restarts the transcode at that offset, which landed within 5 seconds of
// the target in every test. The player says so for every seek while Plex is
// transcoding.
//
// The same stream can also report its end long before the episode ends (on the
// iPhone, at 6:58 of 24:34). Plex then treats the episode as finished, rewinds
// to the start and waits on its post-play screen. An end reported more than a
// minute before the episode's length restarts the transcode where playback was.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>

@interface NSObject (PLXPlaybackEngine)
- (BOOL)isTranscoding;
- (BOOL)isRestartingPlayback;
- (id)player;
- (void)pause;
- (void)resume;
- (void)seekTo:(double)offset completionHandler:(id)handler;
- (void)seekBy:(double)offset completionHandler:(id)handler;
@end

static __weak id PLXCurrentEngine;

// Plex's getters that return seconds; called through objc_msgSend because
// other classes declare methods of the same names with other types.
static double PLXSeconds(id object, NSString *getter) {
    SEL sel = NSSelectorFromString(getter);
    if (![object respondsToSelector:sel]) return -1;
    return ((double (*)(id, SEL))objc_msgSend)(object, sel);
}
static IMP PLXOrigCreatePlayer;

static void PLXCreatePlayer(id self, SEL _cmd, id session, double startOffset, id handler) {
    PLXCurrentEngine = self;
    ((void (*)(id, SEL, id, double, id))PLXOrigCreatePlayer)(self, _cmd, session, startOffset, handler);
}

// While a restart loads, the player's clock reads near 0, so a second
// skip-back tapped during the load counted from there and jumped to the
// beginning. Until playback reaches the restart's offset, the engine and the
// player report that offset as their position.
static double PLXPendingOffset = -1;
static CFAbsoluteTime PLXPendingTime;
static BOOL PLXSawRestart;
static IMP PLXOrigProgress, PLXOrigCurrentTime;

static void PLXSetPendingOffset(double offset) {
    PLXPendingOffset = offset;
    PLXPendingTime = CFAbsoluteTimeGetCurrent();
    PLXSawRestart = NO;
}

static double PLXPositionDuringRestart(double position, BOOL playerClock) {
    if (PLXPendingOffset < 0) return position;
    // Plex's engine already reports the offset during a restart; the player's
    // clock is the one that drops to 0, so only the player's clock decides when
    // playback has arrived. The old position can sit close to the new offset
    // (a 10 s skip), so it counts only after Plex has started and finished the
    // restart.
    BOOL restarting = [PLXCurrentEngine isRestartingPlayback];
    if (restarting) PLXSawRestart = YES;
    BOOL arrived = playerClock && PLXSawRestart && !restarting &&
                   position >= PLXPendingOffset - 1 && position <= PLXPendingOffset + 10;
    if (arrived || CFAbsoluteTimeGetCurrent() - PLXPendingTime > 30) {
        PLXPendingOffset = -1;
        return position;
    }
    return PLXPendingOffset;
}

static double PLXProgress(id self, SEL _cmd) {
    return PLXPositionDuringRestart(((double (*)(id, SEL))PLXOrigProgress)(self, _cmd), NO);
}

static double PLXCurrentTime(id self, SEL _cmd) {
    return PLXPositionDuringRestart(((double (*)(id, SEL))PLXOrigCurrentTime)(self, _cmd), YES);
}

static IMP PLXOrigCanSeekTo;

static BOOL PLXCanSeekTo(id self, SEL _cmd, double offset) {
    BOOL answer = ((BOOL (*)(id, SEL, double))PLXOrigCanSeekTo)(self, _cmd, offset);
    id engine = PLXCurrentEngine;
    if (!answer || [engine player] != self || ![engine isTranscoding]) return answer;
    NSLog(@"PlexReborn: transcoded stream, restarting it at %.1f s instead of seeking in place", offset);
    PLXSetPendingOffset(offset);
    return NO;
}

// An early end restarts the stream at most once per spot, so a file that
// really does stop short still ends after one more try.
static const double PLXEarlyEndMargin = 60;
static double PLXLastEarlyEndOffset = -1;
static CFAbsoluteTime PLXLastEarlyEndTime;
static IMP PLXOrigDidFinish;

static void PLXDidFinish(id self, SEL _cmd, id player) {
    double duration = PLXSeconds(self, @"duration");
    double offset = PLXSeconds(self, @"progress");
    if (offset <= 0 || offset >= duration) offset = PLXSeconds(self, @"lastKnownProgress");
    BOOL early = [self isTranscoding] && duration > 0 && offset > 0 && offset < duration - PLXEarlyEndMargin;
    BOOL retried = fabs(offset - PLXLastEarlyEndOffset) < 15 && CFAbsoluteTimeGetCurrent() - PLXLastEarlyEndTime < 60;
    if (!early || retried) {
        ((void (*)(id, SEL, id))PLXOrigDidFinish)(self, _cmd, player);
        return;
    }
    PLXLastEarlyEndOffset = offset;
    PLXLastEarlyEndTime = CFAbsoluteTimeGetCurrent();
    NSLog(@"PlexReborn: stream ended at %.1f s of %.1f s, restarting it there", offset, duration);
    PLXSetPendingOffset(offset);
    SEL restart = NSSelectorFromString(@"softRestartSessionWithOffset:completionHandler:");
    ((void (*)(id, SEL, double, id))objc_msgSend)(self, restart, offset, ^(id result) {});
}

#if TARGET_OS_SIMULATOR
// Simulator test hook: playback commands for the current video, so seeks can
// be tested without tapping the player. Write one command to
// Library/PlexEngineCommand.txt ("seek <seconds>", "seekby <seconds>",
// "pause", "resume", "fakeend" or "status"), then post the "plexreborn.engine"
// notification. "status" writes Library/PlexEngineStatus.txt.
static void PLXRunEngineCommand(void) {
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *command = [NSString stringWithContentsOfFile:[library stringByAppendingPathComponent:@"PlexEngineCommand.txt"] encoding:NSUTF8StringEncoding error:nil];
    NSArray<NSString *> *words = [[command stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsSeparatedByString:@" "];
    id engine = PLXCurrentEngine;
    if (!engine || !words.count) return;
    NSString *verb = words[0];
    double value = words.count > 1 ? words[1].doubleValue : 0;
    NSLog(@"PlexReborn: test: engine command %@", command);
    if ([verb isEqualToString:@"seek"]) [engine seekTo:value completionHandler:nil];
    else if ([verb isEqualToString:@"seekby"]) [engine seekBy:value completionHandler:nil];
    else if ([verb isEqualToString:@"pause"]) [engine pause];
    else if ([verb isEqualToString:@"resume"]) [engine resume];
    // What mpv reported on the iPhone when the stream ended early.
    else if ([verb isEqualToString:@"fakeend"]) {
        SEL finished = NSSelectorFromString(@"videoPlayerDidFinishPlayingSuccessfully:");
        ((void (*)(id, SEL, id))objc_msgSend)(engine, finished, [engine player]);
    }
    id player = [engine player];
    NSString *status = [NSString stringWithFormat:@"progress=%.3f mpv=%.3f duration=%.3f transcoding=%d restarting=%d\n",
                        PLXSeconds(engine, @"progress"), PLXSeconds(player, @"currentTime"), PLXSeconds(engine, @"duration"),
                        [engine isTranscoding], [engine isRestartingPlayback]];
    [status writeToFile:[library stringByAppendingPathComponent:@"PlexEngineStatus.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
#endif

__attribute__((constructor)) static void PLXInstallTranscodeSeek(void) {
    void (^install)(void) = ^{
        static BOOL installed;
        Class engine = NSClassFromString(@"PMKVideoPlaybackEngine");
        if (installed || !engine) return;
        installed = YES;
        Method create = class_getInstanceMethod(engine, NSSelectorFromString(@"createPlayerWithSession:startOffset:completionHandler:"));
        if (create) PLXOrigCreatePlayer = method_setImplementation(create, (IMP)PLXCreatePlayer);
        Class mpvPlayer = NSClassFromString(@"PMKMPVVideoPlayer");
        Method canSeek = class_getInstanceMethod(mpvPlayer, NSSelectorFromString(@"canSeekTo:"));
        if (canSeek) PLXOrigCanSeekTo = method_setImplementation(canSeek, (IMP)PLXCanSeekTo);
        Method currentTime = class_getInstanceMethod(mpvPlayer, NSSelectorFromString(@"currentTime"));
        if (currentTime) PLXOrigCurrentTime = method_setImplementation(currentTime, (IMP)PLXCurrentTime);
        Method progress = class_getInstanceMethod(engine, NSSelectorFromString(@"progress"));
        if (progress) PLXOrigProgress = method_setImplementation(progress, (IMP)PLXProgress);
        Method finish = class_getInstanceMethod(engine, NSSelectorFromString(@"videoPlayerDidFinishPlayingSuccessfully:"));
        if (finish) PLXOrigDidFinish = method_setImplementation(finish, (IMP)PLXDidFinish);
#if TARGET_OS_SIMULATOR
        int token;
        notify_register_dispatch("plexreborn.engine", &token, dispatch_get_main_queue(), ^(int t) { PLXRunEngineCommand(); });
#endif
    };
    install();
    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidFinishLaunchingNotification" object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { install(); }];
}
