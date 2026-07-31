// Native shim connecting the Unity C# runtime (via P/Invoke) to the
// Engagement Cloud macOS Kotlin/Native framework. Implements the C surface
// declared in EngagementCloudSDKUnity.h.
//
// Threading:
// - Every ec_* entry runs on the caller's thread; work that hits the SDK is
//   `dispatch_async`d onto a global concurrent queue so Unity's main thread
//   is never blocked.
// - Completion callbacks fire on whatever thread SKIE happens to resume on
//   (typically a Kotlin/Native worker). The C# runtime's MainThreadPump is
//   responsible for hopping back to Unity's main thread.
// - Result / error JSON strings are shim-owned; the callee must copy their
//   contents before returning (see EcCompletionCallback in the header).

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <EngagementCloudSDK/EngagementCloudSDK.h>
#import <EngagementCloudSDKUnityKotlin/EngagementCloudSDKUnityKotlin.h>
#include <stdatomic.h>
#include "EngagementCloudSDKUnity.h"

// ---------------------------------------------------------------------------
// Wrapper version — injected at compile time from the UPM package.json.
#ifndef EC_WRAPPER_VERSION
#define EC_WRAPPER_VERSION "0.0.0-dev"
#endif

static const char* const kWrapperName = "unity";
static const char* const kWrapperVersion = EC_WRAPPER_VERSION;

const char* ec_wrapper_version(void) {
    return kWrapperVersion;
}

// ---------------------------------------------------------------------------
// Bundle-load path. Fires when the shim's Mach-O is mapped, before any C#
// code can touch it. Registers the Unity Koin overrides while there's still
// a window before MacosEngagementCloud's eager `init { }` triggers Koin
// startup. See Phase-1.5 remediation for details.

@interface EcBundleLoader : NSObject
@end

@implementation EcBundleLoader
+ (void)load {
    @autoreleasepool {
        [[ECSDKUKEngagementCloudUnityBridge shared] registerOverrides];
        NSLog(@"[EngagementCloudSDKUnity] Registered Unity Koin overrides");
    }
}
@end

// ---------------------------------------------------------------------------
// Dispatch helpers.
//
// String lifetime: NSJSONSerialization + [NSString UTF8String] returns a
// pointer into the autoreleased NSString's backing buffer. Under ARC the
// NSString survives until the autorelease pool drains — long enough for the
// synchronous callback invocation, but not longer. Every dispatch site here
// wraps in `@autoreleasepool { ... callback(...); }` so the callee has read
// the bytes before we lose the buffer.

static void ec_dispatch_success(int32_t requestId,
                                NSString* _Nullable resultJson,
                                EcCompletionCallback callback) {
    if (!callback) return;
    const char* cstr = resultJson ? [resultJson UTF8String] : NULL;
    callback(requestId, cstr, NULL);
}

static void ec_dispatch_error(int32_t requestId,
                              NSString* errorType,
                              NSString* message,
                              EcCompletionCallback callback) {
    if (!callback) return;
    NSDictionary* payload = @{
        @"type": errorType ?: @"UnknownException",
        @"message": message ?: @"(no message)"
    };
    NSError* jsonError = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:payload
                                                   options:0
                                                     error:&jsonError];
    if (!data) {
        callback(requestId, NULL, "{\"type\":\"UnknownException\",\"message\":\"error serialization failed\"}");
        return;
    }
    NSString* json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    callback(requestId, NULL, [json UTF8String]);
}

// Marshal an NSError coming back from SKIE into the tagged-JSON shape the
// C# side expects. NSError from Kotlin exceptions carries the exception
// class name in `userInfo[@"KotlinException"]`; when missing (framework or
// system errors), we fall back to `localizedDescription` and a generic tag.
static void ec_dispatch_kotlin_error(int32_t requestId,
                                     NSString* defaultType,
                                     NSError* _Nullable error,
                                     EcCompletionCallback callback) {
    NSString* type = defaultType;
    NSString* message = error.localizedDescription ?: @"(no message)";
    id kotlinException = error.userInfo[@"KotlinException"];
    if (kotlinException) {
        // SKIE surfaces the throwable object; use its Kotlin class-name.
        Class kotlinClass = [kotlinException class];
        NSString* className = NSStringFromClass(kotlinClass);
        // Strip "ECSDK" prefix so the C# side gets a clean type name.
        if ([className hasPrefix:@"ECSDK"]) {
            className = [className substringFromIndex:5];
        }
        type = className;
        if ([kotlinException respondsToSelector:@selector(message)]) {
            NSString* kotlinMessage = [kotlinException performSelector:@selector(message)];
            if (kotlinMessage.length > 0) message = kotlinMessage;
        }
    }
    ec_dispatch_error(requestId, type, message, callback);
}

// Convenience: wrap an async SDK call whose completion is a plain
// `NSError * _Nullable` block. Success returns a null result.
typedef void (^EcVoidCompletion)(NSError * _Nullable);
static EcVoidCompletion ec_completion(int32_t requestId,
                                      NSString* errorType,
                                      EcCompletionCallback callback) {
    return ^(NSError* _Nullable error) {
        @autoreleasepool {
            if (error) {
                ec_dispatch_kotlin_error(requestId, errorType, error, callback);
            } else {
                ec_dispatch_success(requestId, nil, callback);
            }
        }
    };
}

// Same as ec_completion but wraps a callback that returns an NSString?
// success payload; on success, dispatches `{"value": <string>}` JSON.
static void (^ec_stringResultCompletion(int32_t requestId,
                                        NSString* errorType,
                                        EcCompletionCallback callback))(NSString* _Nullable, NSError* _Nullable) {
    return ^(NSString* _Nullable value, NSError* _Nullable error) {
        @autoreleasepool {
            if (error) {
                ec_dispatch_kotlin_error(requestId, errorType, error, callback);
                return;
            }
            NSDictionary* payload = value ? @{@"value": value} : @{};
            NSError* jsonError = nil;
            NSData* data = [NSJSONSerialization dataWithJSONObject:payload
                                                           options:0
                                                             error:&jsonError];
            if (!data) {
                ec_dispatch_error(requestId, @"UnknownException", @"result serialization failed", callback);
                return;
            }
            NSString* json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            ec_dispatch_success(requestId, json, callback);
        }
    };
}

// ---------------------------------------------------------------------------
// Setup

void ec_setup(int32_t requestId,
              const char* applicationCode,
              EcCompletionCallback callback) {
    if (!applicationCode) {
        ec_dispatch_error(requestId,
                          @"InvalidApplicationCodeException",
                          @"applicationCode was NULL",
                          callback);
        return;
    }
    NSString* appCode = [NSString stringWithUTF8String:applicationCode];

    ECSDKEngagementCloud* engagementCloud = [ECSDKEngagementCloud shared];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            id<ECSDKMacosSetupApi> setup = engagementCloud.setup;
            id<ECSDKMacosSetupApi> __weak weakSetup = setup;

            NSString* versionString = [NSString stringWithUTF8String:kWrapperVersion];
            [setup setPlatformWrapperName:[NSString stringWithUTF8String:kWrapperName]
                                  version:versionString
                        completionHandler:^(NSError* _Nullable wrapperError) {
                if (wrapperError) {
                    ec_dispatch_kotlin_error(requestId, @"WrapperInfoException", wrapperError, callback);
                    return;
                }
                id<ECSDKMacosSetupApi> strongSetup = weakSetup;
                if (!strongSetup) {
                    ec_dispatch_error(requestId, @"SetupFailedException",
                                      @"MacosSetupApi released before enable", callback);
                    return;
                }

                ECSDKEngagementCloudConfig* config =
                    [[ECSDKEngagementCloudConfig alloc] initWithApplicationCode:appCode];

                [strongSetup enableConfig:config
                onContactLinkingFailed:^(ECSDKKotlinUnit* (^successCb)(id<ECSDKLinkContactData> _Nullable),
                                          ECSDKKotlinUnit* (^errorCb)(NSError* _Nullable)) {
                    (void)errorCb;
                    // v1 accepts default server-side contact-linking-failed
                    // handling (see Gap 5). Later, a
                    // ec_setup_setOnContactLinkingFailed(...) callback could
                    // be added to route this to the C# side.
                    successCb(nil);
                }
                     completionHandler:ec_completion(requestId, @"SetupFailedException", callback)];
            }];
        }
    });
}

// ---------------------------------------------------------------------------
// Contact

void ec_contact_link(int32_t requestId,
                     const char* contactFieldValue,
                     EcCompletionCallback callback) {
    if (!contactFieldValue) {
        ec_dispatch_error(requestId, @"IllegalArgumentException",
                          @"contactFieldValue was NULL", callback);
        return;
    }
    NSString* value = [NSString stringWithUTF8String:contactFieldValue];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].contact
                linkContactFieldValue:value
                completionHandler_:ec_completion(requestId, @"ContactLinkFailedException", callback)];
        }
    });
}

void ec_contact_linkAuthenticated(int32_t requestId,
                                  const char* openIdToken,
                                  EcCompletionCallback callback) {
    if (!openIdToken) {
        ec_dispatch_error(requestId, @"IllegalArgumentException",
                          @"openIdToken was NULL", callback);
        return;
    }
    NSString* token = [NSString stringWithUTF8String:openIdToken];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].contact
                linkAuthenticatedOpenIdToken:token
                completionHandler_:ec_completion(requestId, @"ContactLinkFailedException", callback)];
        }
    });
}

void ec_contact_unlink(int32_t requestId, EcCompletionCallback callback) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].contact
                unlinkWithCompletionHandler_:ec_completion(requestId, @"ContactUnlinkFailedException", callback)];
        }
    });
}

// ---------------------------------------------------------------------------
// Event tracking. Attributes are string→string per `CustomEvent`'s Kotlin
// contract; we decode the JSON, reject non-string values, then wrap.

void ec_event_track(int32_t requestId,
                    const char* eventName,
                    const char* _Nullable eventAttrsStringMapJson,
                    EcCompletionCallback callback) {
    if (!eventName) {
        ec_dispatch_error(requestId, @"IllegalArgumentException",
                          @"eventName was NULL", callback);
        return;
    }
    NSString* name = [NSString stringWithUTF8String:eventName];

    NSDictionary<NSString*, NSString*>* attributes = nil;
    if (eventAttrsStringMapJson) {
        NSData* data = [[NSString stringWithUTF8String:eventAttrsStringMapJson]
                        dataUsingEncoding:NSUTF8StringEncoding];
        NSError* jsonError = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || ![parsed isKindOfClass:[NSDictionary class]]) {
            ec_dispatch_error(requestId, @"IllegalArgumentException",
                              @"eventAttrsStringMapJson is not a JSON object", callback);
            return;
        }
        NSMutableDictionary<NSString*, NSString*>* strMap = [NSMutableDictionary new];
        for (id key in (NSDictionary*)parsed) {
            id value = ((NSDictionary*)parsed)[key];
            if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSString class]]) {
                ec_dispatch_error(requestId, @"IllegalArgumentException",
                                  @"event attributes must be a string→string map (CustomEvent contract)",
                                  callback);
                return;
            }
            strMap[key] = value;
        }
        attributes = strMap;
    }

    ECSDKCustomEvent* event = [[ECSDKCustomEvent alloc] initWithName:name attributes:attributes];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].event
                trackEvent:event
                completionHandler:ec_completion(requestId, @"EventTrackFailedException", callback)];
        }
    });
}

// ---------------------------------------------------------------------------
// In-app messages

void ec_inapp_pause(int32_t requestId, EcCompletionCallback callback) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].inApp
                pauseWithCompletionHandler_:ec_completion(requestId, @"InAppPauseFailedException", callback)];
        }
    });
}

void ec_inapp_resume(int32_t requestId, EcCompletionCallback callback) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].inApp
                resumeWithCompletionHandler_:ec_completion(requestId, @"InAppResumeFailedException", callback)];
        }
    });
}

int32_t ec_inapp_isPaused(void) {
    return [[ECSDKEngagementCloud shared].inApp isPaused] ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Config

void ec_config_changeApplicationCode(int32_t requestId,
                                     const char* applicationCode,
                                     EcCompletionCallback callback) {
    if (!applicationCode) {
        ec_dispatch_error(requestId, @"IllegalArgumentException",
                          @"applicationCode was NULL", callback);
        return;
    }
    NSString* code = [NSString stringWithUTF8String:applicationCode];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].config
                changeApplicationCodeApplicationCode:code
                completionHandler_:ec_completion(requestId, @"ConfigChangeFailedException", callback)];
        }
    });
}

void ec_config_getApplicationCode(int32_t requestId, EcCompletionCallback callback) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].config
                getApplicationCodeWithCompletionHandler:
                    ec_stringResultCompletion(requestId, @"ConfigReadFailedException", callback)];
        }
    });
}

void ec_config_getApplicationVersion(int32_t requestId, EcCompletionCallback callback) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].config
                getApplicationVersionWithCompletionHandler:
                    ec_stringResultCompletion(requestId, @"ConfigReadFailedException", callback)];
        }
    });
}

void ec_config_getClientId(int32_t requestId, EcCompletionCallback callback) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].config
                getClientIdWithCompletionHandler:
                    ec_stringResultCompletion(requestId, @"ConfigReadFailedException", callback)];
        }
    });
}

void ec_config_getSdkVersion(int32_t requestId, EcCompletionCallback callback) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].config
                getSdkVersionWithCompletionHandler:
                    ec_stringResultCompletion(requestId, @"ConfigReadFailedException", callback)];
        }
    });
}

void ec_config_getLanguageCode(int32_t requestId, EcCompletionCallback callback) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].config
                getLanguageCodeWithCompletionHandler:
                    ec_stringResultCompletion(requestId, @"ConfigReadFailedException", callback)];
        }
    });
}

void ec_config_setLanguage(int32_t requestId, const char* language, EcCompletionCallback callback) {
    if (!language) {
        ec_dispatch_error(requestId, @"IllegalArgumentException",
                          @"language was NULL", callback);
        return;
    }
    NSString* lang = [NSString stringWithUTF8String:language];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].config
                setLanguageLanguage:lang
                completionHandler_:ec_completion(requestId, @"ConfigWriteFailedException", callback)];
        }
    });
}

void ec_config_resetLanguage(int32_t requestId, EcCompletionCallback callback) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].config
                resetLanguageWithCompletionHandler_:ec_completion(requestId, @"ConfigWriteFailedException", callback)];
        }
    });
}

void ec_config_getCurrentSdkState(int32_t requestId, EcCompletionCallback callback) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            [[ECSDKEngagementCloud shared].config
                getCurrentSdkStateWithCompletionHandler:
                    ^(ECSDKSdkState* _Nullable state, NSError* _Nullable error) {
                @autoreleasepool {
                    if (error) {
                        ec_dispatch_kotlin_error(requestId, @"ConfigReadFailedException", error, callback);
                        return;
                    }
                    // Map SdkState enum to integer per header contract.
                    int32_t intState = 0;
                    if (state == [ECSDKSdkState uninitialized])      intState = 0;
                    else if (state == [ECSDKSdkState initialized])   intState = 1;
                    else if (state == [ECSDKSdkState active])        intState = 2;
                    else if (state == [ECSDKSdkState onhold])        intState = 3;
                    NSString* json = [NSString stringWithFormat:@"{\"state\":%d}", intState];
                    ec_dispatch_success(requestId, json, callback);
                }
            }];
        }
    });
}

// ---------------------------------------------------------------------------
// Deep link. `MacosDeepLinkApi.track` takes an NSUserActivity; construct one
// from the URL string and forward. Synchronous.

int32_t ec_deeplink_trackUrl(const char* url) {
    if (!url) return 0;
    NSString* urlString = [NSString stringWithUTF8String:url];
    NSURL* nsurl = [NSURL URLWithString:urlString];
    if (!nsurl) return 0;

    NSUserActivity* activity = [[NSUserActivity alloc]
        initWithActivityType:NSUserActivityTypeBrowsingWeb];
    activity.webpageURL = nsurl;
    return [[ECSDKEngagementCloud shared].deepLink trackUserActivity:activity] ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Events sink. Uses `registerEventListener:` (already exposed on
// ECSDKEngagementCloud) to receive every event, JSON-encodes, and forwards
// to the currently-registered C callback. NSJSONSerialization can't handle
// arbitrary Kotlin objects, so we hand-serialize the fields the C# side
// cares about: type + a payload dictionary of scalars/strings.

static _Atomic(EcEventCallback) g_eventCallback = NULL;
static BOOL g_eventListenerRegistered = NO;
static dispatch_queue_t ec_events_serial(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.sap.ec.unity.events", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSString* ec_encode_engagement_event(ECSDKEngagementCloudEvent* event) {
    // ECSDKEngagementCloudEvent has: type (enum EngagementCloudEventType) and
    // typed subclasses (CustomEvent, DeviceEvent, etc.). SKIE exposes them as
    // ECSDKEngagementCloudEvent + companions. For v1 we emit a minimal shape
    // that the C# side can grow into — the class name plus the description.
    Class kls = [event class];
    NSString* className = NSStringFromClass(kls);
    if ([className hasPrefix:@"ECSDK"]) className = [className substringFromIndex:5];
    NSString* description = [event description] ?: @"";
    NSDictionary* payload = @{
        @"type": className,
        @"description": description
    };
    NSError* err = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&err];
    if (!data) return @"{\"type\":\"UnknownEvent\"}";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

void ec_events_setSink(EcEventCallback _Nullable callback) {
    atomic_store(&g_eventCallback, callback);
    if (!callback) return;

    dispatch_sync(ec_events_serial(), ^{
        if (g_eventListenerRegistered) return;
        g_eventListenerRegistered = YES;

        [[ECSDKEngagementCloud shared] registerEventListenerListener:^(ECSDKEngagementCloudEvent* event) {
            @autoreleasepool {
                EcEventCallback current = atomic_load(&g_eventCallback);
                if (!current) return;
                NSString* json = ec_encode_engagement_event(event);
                current([json UTF8String]);
            }
        }];
    });
}

// ---------------------------------------------------------------------------
// Logger sink. The Kotlin SDK's Logger + LogSink types are internal today;
// wiring the shim into them requires another Phase-1 remediation similar to
// SdkPlatformOverrides. Held over — this call currently no-ops with a
// diagnostic NSLog so C# integration can still register a sink without
// erroring out.

void ec_logger_setSink(EcLogCallback _Nullable callback) {
    (void)callback;
    if (callback) {
        NSLog(@"[EngagementCloudSDKUnity] ec_logger_setSink: SDK logger sink is not wired yet (see phase-2 plan Section B follow-up)");
    }
}

// ---------------------------------------------------------------------------
// In-app texture presenter — Section C. Stubs remain until then.

IOSurfaceRef _Nullable ec_inapp_texture_acquire(void) {
    NSLog(@"[EngagementCloudSDKUnity] ec_inapp_texture_acquire not yet implemented (Section C)");
    return NULL;
}
void ec_inapp_input_send(int32_t kind, double x, double y, int32_t buttons) {
    (void)kind; (void)x; (void)y; (void)buttons;
}
void ec_inapp_setPresenterFrameCallback(EcPresenterFrameCallback _Nullable callback) {
    (void)callback;
}
