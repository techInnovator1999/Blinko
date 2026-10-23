// BlinkoMedia — tiny MediaRemote bridge loaded by /usr/bin/perl (see blinko-media.pl).
// Since macOS 15.4 mediaremoted only serves platform binaries, so this code runs inside
// Apple's perl and streams state to Blinko as JSON lines. It is fully event-driven:
// it sleeps in the run loop until MediaRemote posts a change or Blinko sends a command.
//
// stdout: {"type":"state", ...} lines. Artwork is sent only when it changes.
// stdin : play | pause | toggle | next | previous | seek <seconds> | refresh
// The process exits when stdin closes, so it can never outlive Blinko.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*MRClientBundleFn)(id);
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef Boolean (*MRSendCommandFn)(int, CFDictionaryRef);
typedef void (*MRSetElapsedFn)(double);

static MRGetInfoFn gGetInfo;
static MRGetIsPlayingFn gGetIsPlaying;
static MRGetClientFn gGetClient;
static MRClientBundleFn gClientBundle;
static MRClientBundleFn gClientParentBundle;
static MRSendCommandFn gSendCommand;
static MRSetElapsedFn gSetElapsed;

static dispatch_queue_t gQueue;
static NSUInteger gLastArtworkHash = 0;
static BOOL gPending = NO;

static void emit(NSDictionary *payload) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id value(NSDictionary *info, NSString *key) {
    id v = info[[@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:key]];
    return (v == [NSNull null]) ? nil : v;
}

static void publish(void) {
    gGetInfo(gQueue, ^(CFDictionaryRef cfInfo) {
        NSDictionary *info = (__bridge NSDictionary *)cfInfo ?: @{};
        gGetIsPlaying(gQueue, ^(Boolean playing) {
            gGetClient(gQueue, ^(id client) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"type"] = @"state";
                out[@"playing"] = @(playing);
                out[@"title"] = value(info, @"Title") ?: @"";
                out[@"artist"] = value(info, @"Artist") ?: @"";
                out[@"album"] = value(info, @"Album") ?: @"";
                out[@"duration"] = value(info, @"Duration") ?: @0;
                out[@"elapsed"] = value(info, @"ElapsedTime") ?: @0;
                out[@"rate"] = value(info, @"PlaybackRate") ?: @(playing ? 1 : 0);
                // MRMediaRemoteShuffleMode / RepeatMode: 0 unknown, 1 off, 2+ on (repeat: 2 one, 3 all).
                out[@"shuffle"] = value(info, @"ShuffleMode") ?: @0;
                out[@"repeat"] = value(info, @"RepeatMode") ?: @0;
                NSDate *ts = value(info, @"Timestamp");
                out[@"timestamp"] = @((ts ?: [NSDate date]).timeIntervalSince1970);

                if (client && gClientBundle) {
                    NSString *bundle = nil;
                    if (gClientParentBundle) bundle = (__bridge NSString *)gClientParentBundle(client);
                    if (!bundle) bundle = (__bridge NSString *)gClientBundle(client);
                    if (bundle) out[@"bundle"] = bundle;
                }

                NSData *art = value(info, @"ArtworkData");
                NSUInteger hash = art ? art.hash ^ art.length : 0;
                out[@"artworkId"] = @(hash);
                if (hash != gLastArtworkHash) {
                    gLastArtworkHash = hash;
                    if (art) out[@"artwork"] = [art base64EncodedStringWithOptions:0];
                }
                emit(out);
            });
        });
    });
}

/// Coalesces bursts of MediaRemote notifications (they arrive in clusters) into one read.
static void schedulePublish(void) {
    if (gPending) return;
    gPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), gQueue, ^{
        gPending = NO;
        publish();
    });
}

static void handleCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *cmd = parts.firstObject;
    // MRMediaRemoteCommand values.
    if ([cmd isEqualToString:@"play"]) gSendCommand(0, NULL);
    else if ([cmd isEqualToString:@"pause"]) gSendCommand(1, NULL);
    else if ([cmd isEqualToString:@"toggle"]) gSendCommand(2, NULL);
    else if ([cmd isEqualToString:@"next"]) gSendCommand(4, NULL);
    else if ([cmd isEqualToString:@"previous"]) gSendCommand(5, NULL);
    else if ([cmd isEqualToString:@"shuffle"]) gSendCommand(6, NULL);  // advance shuffle mode
    else if ([cmd isEqualToString:@"repeat"]) gSendCommand(7, NULL);   // advance repeat mode
    else if ([cmd isEqualToString:@"seek"] && parts.count > 1 && gSetElapsed) gSetElapsed(parts[1].doubleValue);
    else if ([cmd isEqualToString:@"refresh"]) { gLastArtworkHash = 0; }
    schedulePublish();
}

static void readStdin(void) {
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, gQueue);
    static NSMutableData *buffer;
    buffer = [NSMutableData data];
    dispatch_source_set_event_handler(src, ^{
        char chunk[1024];
        ssize_t n = read(STDIN_FILENO, chunk, sizeof chunk);
        if (n <= 0) exit(0); // Blinko went away
        [buffer appendBytes:chunk length:(NSUInteger)n];
        while (true) {
            NSRange nl = [buffer rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, buffer.length)];
            if (nl.location == NSNotFound) break;
            NSData *lineData = [buffer subdataWithRange:NSMakeRange(0, nl.location)];
            [buffer replaceBytesInRange:NSMakeRange(0, nl.location + 1) withBytes:NULL length:0];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            if (line.length) handleCommand(line);
        }
    });
    dispatch_resume(src);
    (void)CFBridgingRetain(src);
}

__attribute__((visibility("default")))
void blinko_media_main(void *perlInterpreter, void *cv) {
    (void)perlInterpreter; (void)cv;
    @autoreleasepool {
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (!mr) { emit(@{@"type": @"error", @"message": @"MediaRemote unavailable"}); exit(2); }

        gGetInfo = (MRGetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        gGetIsPlaying = (MRGetIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        gGetClient = (MRGetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
        gClientBundle = (MRClientBundleFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
        gClientParentBundle = (MRClientBundleFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
        gSendCommand = (MRSendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
        gSetElapsed = (MRSetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
        MRRegisterFn reg = (MRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");

        if (!gGetInfo || !gGetIsPlaying || !gGetClient || !gSendCommand || !reg) {
            emit(@{@"type": @"error", @"message": @"MediaRemote symbols missing"});
            exit(2);
        }

        gQueue = dispatch_queue_create("app.blinko.media", DISPATCH_QUEUE_SERIAL);
        reg(gQueue);

        NSArray *names = @[
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
        ];
        for (NSString *name in names) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                          usingBlock:^(NSNotification *note) { schedulePublish(); }];
        }

        emit(@{@"type": @"ready"});
        readStdin();
        schedulePublish();
        CFRunLoopRun();
    }
}
