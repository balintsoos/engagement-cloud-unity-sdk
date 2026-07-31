// EngagementCloudSDKUnity.mm — Obj-C++ shim between Unity's C# (P/Invoke) and the Kotlin
// framework produced by engagement-cloud-sdk / Phase 1 (`EngagementCloudSDK.framework`).
//
// POC scope (2026-07-31), matching Unity-sdk-phase2-plan.md §11 minus the texture path:
//   - setup / disable / isEnabled (all async so we never block Unity's main thread)
//   - contact.link(contactFieldValue)
//   - event.track(name, attributesJson)
//   - inApp.pause / .resume (async); .isPaused (sync — a Kotlin property, no coroutine)
//   - config.getSdkVersion / .getApplicationCode / .getClientId
//   - deepLink.trackUrl (wraps a URL string as NSUserActivity(activityType: BrowsingWeb))
//   - events sink (AppEvent / BadgeCountEvent → JSON on a global C# fn pointer)
//   - log sink pointer (stored; hooking Kotlin's ConsoleLogger requires a Phase-1 SDK extension
//     — see the note above ec_logger_setSink)
//
// Overlay in-apps use the framework's default AppKit `MacosInAppPresenter` — they render as a
// borderless `NSWindow` above the Unity Player. Texture-based composition (WKWebView →
// IOSurface → Unity external Texture2D) is a follow-up (Phase-2 plan §C).
//
// Threading contract with C#:
//   - Every `ec_*` call is safe from any thread (Unity's main thread is the common case).
//   - Completion callbacks fire on whichever thread SKIE hops to inside the framework (main
//     queue in practice for these APIs). We do NOT re-dispatch here — the C# side's
//     MainThreadPump owns Unity-thread affinity. Fewer hops means faster completions and
//     zero risk of self-deadlock when a caller blocks main to wait on a result.
//   - Every `char *` we hand to a callback is `strdup`'d and freed *by us* immediately after
//     the callback returns. The C# side promises to `Marshal.PtrToStringUTF8` synchronously
//     (it does — see NativeCallbacks.OnCompletion).

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <EngagementCloudSDK/EngagementCloudSDK.h>

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>

// =============================================================================
// C ABI shared with C# (Runtime/Internal/NativeCallbacks.cs). Signatures must
// match delegate declarations byte-for-byte or IL2CPP marshalling will drift.
// =============================================================================

typedef void (*ec_completion_fn)(int32_t reqId, const char *resultJsonUtf8, const char *errorJsonUtf8);
typedef void (*ec_event_fn)(const char *eventJsonUtf8);
typedef void (*ec_log_fn)(int32_t severity, const char *messageUtf8);

// =============================================================================
// Small helpers
// =============================================================================

/// Copy an `NSString` into a heap-allocated UTF-8 buffer. Returns `NULL` for `nil` input.
/// Caller-frees.
static char *EcStrDup(NSString *s) {
    if (s == nil) return NULL;
    const char *utf8 = [s UTF8String];
    if (utf8 == NULL) return NULL;
    return strdup(utf8);
}

/// SKIE tags NSError.userInfo with the original Kotlin `Throwable` under one of a small
/// number of keys, depending on the SKIE version. Try all of them; return the first non-nil.
/// Returns `nil` if nothing matched (native NSError without a Kotlin origin).
static id EcExtractKotlinThrowable(NSError *err) {
    if (err == nil) return nil;
    // Known key strings across SKIE releases + vanilla Kotlin/Native.
    static NSArray<NSString *> *kKotlinExceptionKeys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kKotlinExceptionKeys = @[
            @"KotlinException",             // vanilla Kotlin/Native
            @"co.touchlab.skie.exceptionKey", // some SKIE releases
            @"co.touchlab.skie.KotlinException"
        ];
    });
    for (NSString *key in kKotlinExceptionKeys) {
        id v = err.userInfo[key];
        if (v != nil) return v;
    }
    return nil;
}

/// Marshal an NSError into a JSON string matching `EngagementCloudException.FromJson()`'s
/// contract:
///   `{"type":"<KotlinExceptionSimpleName>","message":"...","domain":"...","code":N}`
/// Returns `NULL` when `err == nil`. Caller-frees.
static char *EcErrorToJson(NSError *err) {
    if (err == nil) return NULL;

    NSString *typeName = nil;
    NSString *message  = err.localizedDescription ?: @"unknown error";

    id kotlinThrowable = EcExtractKotlinThrowable(err);
    if (kotlinThrowable != nil) {
        // Kotlin `Throwable`s map to Obj-C classes prefixed with the framework's obj-c prefix
        // (`ECSDK` here). SKIE additionally flattens nested classes with the outer class name
        // as a prefix — so `SdkException.SdkAlreadyEnabledException` becomes
        // `ECSDKSdkExceptionSdkAlreadyEnabledException`. We strip both layers so C# sees the
        // simple leaf name that `EngagementCloudException.FromJson` switches on.
        NSString *cls = NSStringFromClass([(NSObject *)kotlinThrowable class]);
        if ([cls hasPrefix:@"ECSDK"])        cls = [cls substringFromIndex:5];
        if ([cls hasPrefix:@"SdkException"]) cls = [cls substringFromIndex:12];
        typeName = cls;
        if ([kotlinThrowable respondsToSelector:@selector(message)]) {
            NSString *m = [(id)kotlinThrowable message];
            if (m.length) message = m;
        }
    }
    if (typeName == nil) typeName = @"NSError";

    NSDictionary *payload = @{
        @"type": typeName,
        @"message": message,
        @"domain": err.domain ?: @"unknown",
        @"code": @(err.code)
    };
    NSError *serialErr = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&serialErr];
    if (data == nil) {
        // Extremely unlikely — NSDictionary is JSON-safe by construction — but be defensive.
        return EcStrDup([NSString stringWithFormat:
            @"{\"type\":\"Unknown\",\"message\":\"error serialising NSError: %@\"}",
            serialErr.localizedDescription ?: @"?"]);
    }
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return EcStrDup(str);
}

/// Fire a completion callback and free its shim-owned strings. Runs on whatever thread the
/// caller is on — C# is expected to hop to Unity's main thread via `MainThreadPump.Post`.
static void EcComplete(int32_t reqId,
                       char *resultJson,
                       char *errorJson,
                       ec_completion_fn cb) {
    if (cb != NULL) {
        cb(reqId, resultJson, errorJson);
    }
    if (resultJson) free(resultJson);
    if (errorJson)  free(errorJson);
}

/// Singleton accessor. `[ECSDKEngagementCloud shared]` triggers Koin init on first touch
/// (`SdkKoinIsolationContext.init()` runs inside the Kotlin `object`'s `init {}` block); every
/// entry point below goes through here so that path is exercised early and once.
static ECSDKEngagementCloud *EC(void) {
    return [ECSDKEngagementCloud shared];
}

// =============================================================================
// Events pipeline
// =============================================================================
//
// `MacosEngagementCloud.registerEventListener(listener)` appends a block to an internal list
// on the Kotlin side (see MacosEngagementCloud.kt:41). Only ever one shim-side listener is
// installed — its body forwards the Obj-C event to whichever C# fn pointer is currently
// registered via `ec_events_setSink`. That pointer can change or be nulled at any time
// without needing to re-register a listener on the framework.
//
// This means Unity subscribers see events even if they set the sink AFTER Setup completes.
// The framework starts collecting on its `Application` scope at Koin init time, so
// nothing is lost between framework load and shim-first-touch.
//
// If a Unity domain reload happens, C# state (event thunk) is torn down and re-installed via
// `NativeCallbacks.EventThunk`. The atomic pointer swap picks that up cleanly.

static std::atomic<ec_event_fn> g_eventSink { nullptr };
static std::atomic<ec_log_fn>   g_logSink   { nullptr };
static std::atomic<bool>        g_eventListenerInstalled { false };

/// Serialize a single `ECSDKEngagementCloudEvent` to JSON matching `SdkEvent.FromJson()`'s
/// discriminator + property layout. Never throws; returns `nil` if the event is malformed.
static NSString *EcEventToJson(ECSDKEngagementCloudEvent *event) {
    if (event == nil) return nil;

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"]        = event.id ?: @"";
    dict[@"timestamp"] = @((int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0));

    if ([event isKindOfClass:[ECSDKAppEvent class]]) {
        ECSDKAppEvent *ae = (ECSDKAppEvent *)event;
        dict[@"type"] = @"AppEvent";
        dict[@"name"] = ae.name ?: @"";
        if (ae.payload != nil && [NSJSONSerialization isValidJSONObject:ae.payload]) {
            // NSJSONSerialization will nest the dictionary correctly when we serialise the
            // outer dict — no extra encoding needed.
            dict[@"payload"] = ae.payload;
        }
    } else if ([event isKindOfClass:[ECSDKBadgeCountEvent class]]) {
        ECSDKBadgeCountEvent *bc = (ECSDKBadgeCountEvent *)event;
        dict[@"type"]       = @"BadgeCountEvent";
        dict[@"badgeCount"] = @(bc.badgeCount);
        dict[@"method"]     = bc.method ?: @"";
    } else {
        // Future / unknown event tag — surface the class name minus the ECSDK prefix (and
        // SdkException nested-flatten prefix) so the C# side can still route it through
        // SdkEvent.Unknown with a meaningful `Type`.
        NSString *cls = NSStringFromClass([event class]);
        if ([cls hasPrefix:@"ECSDK"])        cls = [cls substringFromIndex:5];
        if ([cls hasPrefix:@"SdkException"]) cls = [cls substringFromIndex:12];
        dict[@"type"] = cls;
    }

    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&err];
    if (data == nil) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static void EcEnsureEventListenerInstalled(void) {
    bool expected = false;
    if (!g_eventListenerInstalled.compare_exchange_strong(expected, true)) return;

    [EC() registerEventListenerListener:^(ECSDKEngagementCloudEvent *event) {
        ec_event_fn sink = g_eventSink.load();
        if (sink == nullptr) return;
        NSString *json = EcEventToJson(event);
        if (json == nil) return;
        char *cstr = EcStrDup(json);
        if (cstr == NULL) return;
        // No re-dispatch: the C# thunk MainThreadPump.Posts internally, and re-dispatching
        // here would only add latency. The shim frees the buffer after the C# thunk returns.
        sink(cstr);
        free(cstr);
    }];
}

// =============================================================================
// extern "C" entry points — matching Runtime/Internal/NativeBridge.cs
// =============================================================================

extern "C" {

// ----------------------------------------------------------------------------- lifecycle

/// `EngagementCloud.setup.enable(config, onContactLinkingFailed)`. The POC provides a no-op
/// contact-linking-failed callback that resolves with `nil`, i.e. accept the framework's
/// default behaviour. Extending this to expose a C# callback is straightforward once needed.
void ec_setup(int32_t reqId, const char *applicationCodeUtf8, ec_completion_fn cb) {
    if (applicationCodeUtf8 == NULL) {
        EcComplete(reqId, NULL,
                   EcStrDup(@"{\"type\":\"IllegalArgument\",\"message\":\"applicationCode is null\"}"),
                   cb);
        return;
    }
    NSString *code = [NSString stringWithUTF8String:applicationCodeUtf8];
    ECSDKEngagementCloudConfig *config = [[ECSDKEngagementCloudConfig alloc] initWithApplicationCode:code];

    EcEnsureEventListenerInstalled();

    [[EC() setup] enableConfig:config
        onContactLinkingFailed:^(ECSDKKotlinUnit *(^onSuccess)(id<ECSDKLinkContactData> _Nullable),
                                 ECSDKKotlinUnit *(^onError)(NSError * _Nullable)) {
                                     (void)onSuccess(nil);
                                 }
             completionHandler:^(NSError * _Nullable error) {
                 EcComplete(reqId, NULL, EcErrorToJson(error), cb);
             }];
}

/// `EngagementCloud.setup.disable()`.
void ec_disable(int32_t reqId, ec_completion_fn cb) {
    [[EC() setup] disableWithCompletionHandler:^(NSError * _Nullable error) {
        EcComplete(reqId, NULL, EcErrorToJson(error), cb);
    }];
}

/// Async `isEnabled()` — Kotlin's underlying implementation is a `suspend fun`, so a sync
/// wrapper would deadlock when called from the same queue the completion resumes on. The C#
/// side awaits.
void ec_setup_isEnabled(int32_t reqId, ec_completion_fn cb) {
    [[EC() setup] isEnabledWithCompletionHandler:^(ECSDKBoolean * _Nullable value, NSError * _Nullable error) {
        char *result = NULL;
        if (error == nil) {
            result = EcStrDup(([value boolValue] ? @"true" : @"false"));
        }
        EcComplete(reqId, result, EcErrorToJson(error), cb);
    }];
}

// ----------------------------------------------------------------------------- config

/// `EngagementCloud.config.getSdkVersion()` — SDK build version string.
void ec_config_getSdkVersion(int32_t reqId, ec_completion_fn cb) {
    [[EC() config] getSdkVersionWithCompletionHandler:^(NSString * _Nullable value, NSError * _Nullable error) {
        EcComplete(reqId,
                   error == nil ? EcStrDup(value ?: @"") : NULL,
                   EcErrorToJson(error), cb);
    }];
}

/// `EngagementCloud.config.getApplicationCode()` — currently persisted app code (may be nil
/// before Setup). We serialise nil as an empty string so C# doesn't have to distinguish.
void ec_config_getApplicationCode(int32_t reqId, ec_completion_fn cb) {
    [[EC() config] getApplicationCodeWithCompletionHandler:^(NSString * _Nullable value, NSError * _Nullable error) {
        EcComplete(reqId,
                   error == nil ? EcStrDup(value ?: @"") : NULL,
                   EcErrorToJson(error), cb);
    }];
}

/// `EngagementCloud.config.getClientId()` — SDK-assigned UUID for this device install.
void ec_config_getClientId(int32_t reqId, ec_completion_fn cb) {
    [[EC() config] getClientIdWithCompletionHandler:^(NSString * _Nullable value, NSError * _Nullable error) {
        EcComplete(reqId,
                   error == nil ? EcStrDup(value ?: @"") : NULL,
                   EcErrorToJson(error), cb);
    }];
}

// ----------------------------------------------------------------------------- contact

/// `EngagementCloud.contact.link(contactFieldValue)` — links this install to a contact by
/// field value (email by default; server-side contact-field id is inferred from the setup).
void ec_contact_linkByValue(int32_t reqId, const char *contactValueUtf8, ec_completion_fn cb) {
    if (contactValueUtf8 == NULL) {
        EcComplete(reqId, NULL,
                   EcStrDup(@"{\"type\":\"IllegalArgument\",\"message\":\"contactValue is null\"}"),
                   cb);
        return;
    }
    NSString *value = [NSString stringWithUTF8String:contactValueUtf8];
    [[EC() contact] linkContactFieldValue:value
                       completionHandler_:^(NSError * _Nullable error) {
                           EcComplete(reqId, NULL, EcErrorToJson(error), cb);
                       }];
}

// ----------------------------------------------------------------------------- events

/// `EngagementCloud.event.track(CustomEvent(name, attributes))`. Attributes is an optional
/// JSON *object* string mapping strings → strings; anything else in the payload is silently
/// dropped (matches Kotlin's `Map<String, String>?` contract).
void ec_event_track(int32_t reqId, const char *eventNameUtf8, const char *attributesJsonUtf8, ec_completion_fn cb) {
    if (eventNameUtf8 == NULL) {
        EcComplete(reqId, NULL,
                   EcStrDup(@"{\"type\":\"IllegalArgument\",\"message\":\"eventName is null\"}"),
                   cb);
        return;
    }
    NSString *name = [NSString stringWithUTF8String:eventNameUtf8];

    NSDictionary<NSString *, NSString *> *attrs = nil;
    if (attributesJsonUtf8 != NULL && attributesJsonUtf8[0] != '\0') {
        NSData *data = [NSData dataWithBytes:attributesJsonUtf8 length:strlen(attributesJsonUtf8)];
        NSError *jsonErr = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if ([parsed isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *strDict = [NSMutableDictionary dictionary];
            for (id key in parsed) {
                id val = parsed[key];
                if ([key isKindOfClass:[NSString class]] && [val isKindOfClass:[NSString class]]) {
                    strDict[key] = val;
                }
            }
            if (strDict.count > 0) attrs = strDict;
        }
    }

    ECSDKCustomEvent *event = [[ECSDKCustomEvent alloc] initWithName:name attributes:attrs];
    [[EC() event] trackEvent:event
           completionHandler:^(NSError * _Nullable error) {
               EcComplete(reqId, NULL, EcErrorToJson(error), cb);
           }];
}

// ----------------------------------------------------------------------------- in-app control

/// `EngagementCloud.inApp.pause()` — subsequent overlay/inline messages queue instead of showing.
void ec_inapp_pause(int32_t reqId, ec_completion_fn cb) {
    [[EC() inApp] pauseWithCompletionHandler_:^(NSError * _Nullable error) {
        EcComplete(reqId, NULL, EcErrorToJson(error), cb);
    }];
}

/// `EngagementCloud.inApp.resume()` — dequeue and re-evaluate paused messages.
void ec_inapp_resume(int32_t reqId, ec_completion_fn cb) {
    [[EC() inApp] resumeWithCompletionHandler_:^(NSError * _Nullable error) {
        EcComplete(reqId, NULL, EcErrorToJson(error), cb);
    }];
}

/// `EngagementCloud.inApp.isPaused` — synchronous because the underlying Kotlin is a
/// property (`val isPaused: Boolean`), not a suspend fun. Safe to poll every frame.
int32_t ec_inapp_isPaused(void) {
    return [[EC() inApp] isPaused] ? 1 : 0;
}

// ----------------------------------------------------------------------------- deep link

/// `EngagementCloud.deepLink.track(userActivity: NSUserActivity(...webpageURL: url))`.
/// The Kotlin-side deep-link API takes an `NSUserActivity`; C# consumers don't have that
/// type, so we synthesise one here from a plain URL string. Returns `1` if the SDK handled
/// the deep-link, `0` otherwise (mirrors the Kotlin `Bool` return).
///
/// This is a sync entry point because `MacosDeepLinkApi.track(userActivity:)` is a plain
/// (non-suspend) function on the Kotlin side.
int32_t ec_deeplink_trackUrl(const char *urlUtf8) {
    if (urlUtf8 == NULL) return 0;
    NSString *urlStr = [NSString stringWithUTF8String:urlUtf8];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (url == nil) return 0;

    NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
    activity.webpageURL = url;

    return [[EC() deepLink] trackUserActivity:activity] ? 1 : 0;
}

// ----------------------------------------------------------------------------- sinks

/// Install (or replace) the events sink. Passing `nullptr` disables event forwarding without
/// affecting the underlying framework listener — Kotlin-side events keep flowing, we just
/// stop delivering them across the P/Invoke boundary.
///
/// Safe to call from any thread; the atomic swap is memory-ordered against the listener
/// block's read.
void ec_events_setSink(ec_event_fn onEvent) {
    g_eventSink.store(onEvent);
    EcEnsureEventListenerInstalled();
}

/// Install (or replace) the Kotlin logger sink. STATUS: the Phase-1 SDK does not currently
/// expose a public hookup point for redirecting `ConsoleLogger`'s output — its output goes
/// straight to `printf`/stdout. Wiring this would require adding a `LogSink` interface on the
/// commonMain `Logger` binding plus a macOS-side implementation that forwards to the stored
/// function pointer.
///
/// For the POC we store the pointer so it's ready when that extension lands; C# callers get
/// a no-op that still logs their `Debug.Log` prefix via `Debug.Log` on the pump.
void ec_logger_setSink(ec_log_fn onLog) {
    g_logSink.store(onLog);
}

} // extern "C"

// =============================================================================
// Inline in-app texture path
// =============================================================================
//
// `MacosInAppApi.fetchInline(viewId)` returns a `WKWebView` that renders the message HTML
// with the SDK's JS bridge already installed. To make that view usable *inside* a Unity scene
// we:
//
//   1. Attach the WKWebView to an offscreen `NSPanel` positioned far below any physical
//      display (screen coords `(-20000, -20000)`). WKWebView requires an on-window backing
//      store to actually render — an unhosted view will hand back empty snapshots — so we
//      pay for a window but keep it invisible.
//
//   2. Drive a ~30 Hz snapshot loop with `takeSnapshotWithConfiguration:completionHandler:`.
//      This is the public, stable WebKit API for capturing a WKWebView's rendered content
//      including the parts running in the WebContent process (remote layer tree). We NEVER
//      call `renderInContext:` on the WKWebView's layer directly — that only sees the local
//      process's layer proxy and returns blank.
//
//   3. Convert each `NSImage` snapshot into a heap-allocated **BGRA8, premultiplied,
//      top-left-origin** buffer of size `width * height * 4`. That layout matches Unity's
//      `TextureFormat.BGRA32` verbatim so C# does a plain `LoadRawTextureData` without any
//      channel swizzle or Y-flip on the shader side. Origin-flip is handled by drawing the
//      NSImage into a `flipped:YES` `NSGraphicsContext`.
//
//   4. Expose the current frame to C# through a lightweight `ec_inline_lockFrame` API that
//      returns a pointer + width/height/stride + a monotonic `frameVersion`. C# only re-uploads
//      the texture when the version changes, so idle inline views cost effectively zero.
//
//   5. Route pointer events from Unity through `ec_inline_sendPointer`. We synthesize an
//      `NSEvent` located in the offscreen window's coordinate space and post it via
//      `-[NSWindow sendEvent:]`, which runs through NSResponder's standard chain — exactly
//      what an on-screen click would do, so WKWebView's WebContent hit-testing kicks in and
//      the JS bridge sees the click.

API_AVAILABLE(macos(10.15))
@interface EcInlineSession : NSObject
@property (nonatomic, copy)   NSString  *viewId;
@property (nonatomic, assign) NSInteger  width;
@property (nonatomic, assign) NSInteger  height;
@property (nonatomic, strong) NSPanel   *offscreenPanel;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSTimer   *snapshotTimer;
@property (nonatomic, strong) NSLock    *frameLock;
@property (nonatomic, strong) NSMutableData *frameBuffer;  // BGRA8, premultiplied, top-left origin
@property (nonatomic, assign) int64_t    frameVersion;     // monotonic; C# uses this to skip re-uploads
@property (nonatomic, assign) BOOL       snapshotInFlight; // guards overlapping snapshot calls
@end

@implementation EcInlineSession

/// Snapshot tick. Never runs re-entrantly — if the previous snapshot's completion is still
/// pending we simply skip this tick. The completion queue is main by default (WebKit's
/// contract), but we do the pixel conversion off the main thread to avoid stealing render
/// budget from Unity's Update loop.
- (void)tick {
    if (self.snapshotInFlight) return;
    self.snapshotInFlight = YES;

    WKSnapshotConfiguration *cfg = [[WKSnapshotConfiguration alloc] init];
    cfg.afterScreenUpdates = YES;
    cfg.rect = self.webView.bounds;
    // Ask WebKit to size the returned NSImage to our target width; height follows aspect. We
    // downscale/upscale to the exact (width, height) during the BGRA conversion so the final
    // buffer is always the caller-configured size.
    cfg.snapshotWidth = @((CGFloat)self.width);

    __weak EcInlineSession *weakSelf = self;
    [self.webView takeSnapshotWithConfiguration:cfg
                              completionHandler:^(NSImage *image, NSError *error) {
        EcInlineSession *strong = weakSelf;
        if (strong == nil) return;
        strong.snapshotInFlight = NO;
        if (error != nil || image == nil) return;

        // Move the pixel-conversion work off the main queue — WKWebView's snapshot completion
        // is main-thread by design, but we don't want the memcpy on Unity's frame path.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSData *bgra = [strong bgraFromImage:image];
            if (bgra == nil) return;
            [strong.frameLock lock];
            strong.frameBuffer = [bgra mutableCopy];
            strong.frameVersion++;
            [strong.frameLock unlock];
        });
    }];
}

/// Draw `image` into a freshly-allocated BGRA8 buffer of size `self.width * self.height * 4`
/// and return it as an NSData. Returns nil if the CG bitmap context can't be created (only
/// happens under extreme memory pressure). Uses a flipped context so the resulting bytes are
/// **top-left origin** — that matches how Unity's Texture2D uploads want their data.
- (NSData *)bgraFromImage:(NSImage *)image {
    NSInteger w = self.width;
    NSInteger h = self.height;
    if (w <= 0 || h <= 0) return nil;

    size_t rowBytes = (size_t)w * 4;
    void *bytes = calloc(1, rowBytes * (size_t)h);
    if (bytes == NULL) return nil;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    // BGRA8, alpha-first (premultiplied), little-endian byte order — == Unity BGRA32.
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
    CGContextRef ctx = CGBitmapContextCreate(bytes, (size_t)w, (size_t)h, 8, rowBytes,
                                             colorSpace, bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    if (ctx == NULL) {
        free(bytes);
        return nil;
    }

    // Draw with a Y-flipped context so the resulting bytes have top-left origin.
    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gc];
    CGContextTranslateCTM(ctx, 0, (CGFloat)h);
    CGContextScaleCTM(ctx, 1.0, -1.0);
    [image drawInRect:NSMakeRect(0, 0, (CGFloat)w, (CGFloat)h)
             fromRect:NSZeroRect
            operation:NSCompositingOperationCopy
             fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];

    NSData *data = [NSData dataWithBytesNoCopy:bytes length:rowBytes * (size_t)h freeWhenDone:YES];
    CGContextRelease(ctx);
    return data;
}

@end

// Registry shared across all inline sessions. Access is guarded by g_inlineLock; every
// entry point below takes the lock only long enough to grab the session, then works on the
// (retained) session outside the critical section.
static NSMutableDictionary<NSString *, EcInlineSession *> *g_inlineSessions = nil;
static NSLock *g_inlineLock = nil;

static void EcEnsureInlineRegistry(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_inlineSessions = [NSMutableDictionary dictionary];
        g_inlineLock     = [NSLock new];
    });
}

static EcInlineSession *EcLookupInlineSession(NSString *viewId) {
    if (viewId == nil) return nil;
    [g_inlineLock lock];
    EcInlineSession *session = g_inlineSessions[viewId];
    [g_inlineLock unlock];
    return session;
}

extern "C" {

/// Fetch the inline in-app for `viewId`, host it on an offscreen NSPanel of `width×height`,
/// and start a snapshot loop at ~30 Hz. Completion callback fires when the fetch resolves —
/// error path if the backend returned no message or the SDK is disabled, success path when
/// the offscreen panel is up and the snapshot loop is running (first frame may still take a
/// tick to arrive).
///
/// Idempotent per `viewId`: re-opening an already-open session tears the old one down first.
void ec_inline_open(int32_t reqId, const char *viewIdUtf8, int32_t width, int32_t height, ec_completion_fn cb) {
    if (viewIdUtf8 == NULL || width <= 0 || height <= 0) {
        EcComplete(reqId, NULL,
                   EcStrDup(@"{\"type\":\"IllegalArgument\",\"message\":\"viewId/width/height required\"}"),
                   cb);
        return;
    }
    NSString *viewId = [NSString stringWithUTF8String:viewIdUtf8];
    EcEnsureInlineRegistry();

    // If a session already exists for this viewId, tear it down synchronously before opening a
    // new one — keeps state predictable if the caller re-opens on resize.
    EcInlineSession *prev = nil;
    [g_inlineLock lock];
    prev = g_inlineSessions[viewId];
    [g_inlineSessions removeObjectForKey:viewId];
    [g_inlineLock unlock];
    if (prev != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [prev.snapshotTimer invalidate];
            [prev.offscreenPanel orderOut:nil];
            [prev.offscreenPanel close];
        });
    }

    [[EC() inApp] fetchInlineViewId:viewId
                  completionHandler:^(WKWebView * _Nullable webView, NSError * _Nullable error) {
        if (error != nil) {
            EcComplete(reqId, NULL, EcErrorToJson(error), cb);
            return;
        }
        if (webView == nil) {
            EcComplete(reqId, NULL,
                       EcStrDup(@"{\"type\":\"NotFound\",\"message\":\"no inline message for viewId\"}"),
                       cb);
            return;
        }

        // Everything past this point must run on main — AppKit ownership rules.
        dispatch_async(dispatch_get_main_queue(), ^{
            // Position the panel WAY off any physical display so we still get a real backing
            // store (needed for WKWebView to render) but the window is never visible to the
            // user. `.borderless` + clear background keeps the panel invisible even in edge
            // cases where the OS repositions offscreen windows.
            NSRect frame = NSMakeRect(-20000.0, -20000.0, (CGFloat)width, (CGFloat)height);
            NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                        styleMask:NSWindowStyleMaskBorderless
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
            panel.level = NSNormalWindowLevel;
            panel.backgroundColor = [NSColor clearColor];
            panel.opaque = NO;
            panel.releasedWhenClosed = NO;
            // WKWebView is an NSView subclass — wire it directly as the content view.
            webView.frame = NSMakeRect(0, 0, (CGFloat)width, (CGFloat)height);
            panel.contentView = webView;
            // Order in but don't activate — offscreen but rendering.
            [panel orderBack:nil];

            EcInlineSession *session = [[EcInlineSession alloc] init];
            session.viewId          = viewId;
            session.width           = width;
            session.height          = height;
            session.offscreenPanel  = panel;
            session.webView         = webView;
            session.frameLock       = [NSLock new];
            session.frameVersion    = 0;

            [g_inlineLock lock];
            g_inlineSessions[viewId] = session;
            [g_inlineLock unlock];

            // ~30 Hz snapshot tick. NSTimer here (rather than dispatch_source_timer) so the
            // callback stays on the main run loop — WKWebView's snapshot API requires main.
            session.snapshotTimer =
                [NSTimer scheduledTimerWithTimeInterval:(1.0 / 30.0)
                                                 target:session
                                               selector:@selector(tick)
                                               userInfo:nil
                                                repeats:YES];

            EcComplete(reqId, NULL, NULL, cb);
        });
    }];
}

/// Tear down the inline session for `viewId`. Safe to call multiple times / with an unknown
/// viewId (no-op). All resources — timer, offscreen panel, WKWebView, frame buffer — are
/// released; the C# side's Texture2D is unaffected (that's C# lifetime).
void ec_inline_close(const char *viewIdUtf8) {
    if (viewIdUtf8 == NULL) return;
    NSString *viewId = [NSString stringWithUTF8String:viewIdUtf8];

    EcInlineSession *session = nil;
    [g_inlineLock lock];
    session = g_inlineSessions[viewId];
    [g_inlineSessions removeObjectForKey:viewId];
    [g_inlineLock unlock];
    if (session == nil) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [session.snapshotTimer invalidate];
        session.snapshotTimer = nil;
        [session.offscreenPanel orderOut:nil];
        [session.offscreenPanel close];
        session.offscreenPanel = nil;
        session.webView = nil;
    });
}

/// Pull the current frame for `viewId`. On success: `1` is returned, `*outBuf` points at the
/// BGRA buffer (owned by the session; valid until the next `ec_inline_lockFrame` on the same
/// viewId or until `ec_inline_close`), width/height/stride are set, and `*outVersion` is
/// filled with a monotonic counter. The C# caller compares `outVersion` to its last-seen
/// version to decide whether to re-upload the texture.
///
/// Returns `0` when there is no session for the viewId OR no frame has arrived yet. Callers
/// should treat `0` as "try again next frame".
int32_t ec_inline_lockFrame(const char *viewIdUtf8,
                             uint8_t **outBuf, int32_t *outW, int32_t *outH,
                             int32_t *outStride, int64_t *outVersion) {
    if (viewIdUtf8 == NULL) return 0;
    NSString *viewId = [NSString stringWithUTF8String:viewIdUtf8];
    EcInlineSession *session = EcLookupInlineSession(viewId);
    if (session == nil) return 0;

    [session.frameLock lock];
    if (session.frameBuffer == nil) {
        [session.frameLock unlock];
        return 0;
    }
    if (outBuf)     *outBuf     = (uint8_t *)[session.frameBuffer mutableBytes];
    if (outW)       *outW       = (int32_t)session.width;
    if (outH)       *outH       = (int32_t)session.height;
    if (outStride)  *outStride  = (int32_t)(session.width * 4);
    if (outVersion) *outVersion = session.frameVersion;
    [session.frameLock unlock];
    return 1;
}

/// Inject a pointer event into the inline WKWebView. `kind` is 0=move, 1=down, 2=up. `x`/`y`
/// are in the inline view's pixel coordinate space (top-left origin, matching how the frame
/// buffer is oriented). We synthesize an `NSEvent` in the offscreen panel's coord space (which
/// is bottom-left origin) and post it via `-[NSPanel sendEvent:]` so WKWebView's standard
/// hit-testing path fires — the JS bridge sees these exactly like on-screen clicks.
void ec_inline_sendPointer(const char *viewIdUtf8, int32_t kind, float x, float y) {
    if (viewIdUtf8 == NULL) return;
    NSString *viewId = [NSString stringWithUTF8String:viewIdUtf8];
    EcInlineSession *session = EcLookupInlineSession(viewId);
    if (session == nil) return;

    // Convert top-left-origin pixel coords to bottom-left AppKit coords in the offscreen
    // panel's frame. Panel bounds are (0, 0, width, height).
    NSPoint location = NSMakePoint((CGFloat)x, session.height - (CGFloat)y);

    NSEventType type;
    switch (kind) {
        case 1:  type = NSEventTypeLeftMouseDown; break;
        case 2:  type = NSEventTypeLeftMouseUp;   break;
        default: type = NSEventTypeMouseMoved;    break;
    }

    // NSEvent creation + dispatch must be on main.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSPanel *panel = session.offscreenPanel;
        if (panel == nil) return;
        NSEvent *event = [NSEvent mouseEventWithType:type
                                            location:location
                                       modifierFlags:0
                                           timestamp:[[NSProcessInfo processInfo] systemUptime]
                                        windowNumber:[panel windowNumber]
                                             context:nil
                                         eventNumber:0
                                          clickCount:(kind == 0 ? 0 : 1)
                                            pressure:(kind == 1 ? 1.0f : 0.0f)];
        if (event != nil) {
            [panel sendEvent:event];
        }
    });
}

} // extern "C" (inline block)
