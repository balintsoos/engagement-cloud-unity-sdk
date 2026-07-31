// Minimal shim scaffolding. This first pass implements only `ec_setup` and
// the bundle-load path that registers Unity's Koin overrides. Everything else
// short-circuits into a "not yet implemented" error via the completion
// callback — enough to prove the toolchain (xcodegen → xcodebuild → linked
// bundle → framework-load → Kotlin bridge invocation) end-to-end.
//
// Section B commit 2 fills in the remaining entry points.

#import <Foundation/Foundation.h>
#import <EngagementCloudSDK/EngagementCloudSDK.h>
#import <EngagementCloudSDKUnityKotlin/EngagementCloudSDKUnityKotlin.h>
#include "EngagementCloudSDKUnity.h"

// ---------------------------------------------------------------------------
// Wrapper version — injected at compile time from the UPM package.json.
// The Gradle build passes GCC_PREPROCESSOR_DEFINITIONS="EC_WRAPPER_VERSION=..."
// to xcodebuild; if the flag isn't set (unit-test compilation, IDE), fall
// back to a sentinel so we don't emit an ambiguous "unity" identity to the
// server side.
#ifndef EC_WRAPPER_VERSION
#define EC_WRAPPER_VERSION "0.0.0-dev"
#endif

static const char* const kWrapperName = "unity";
static const char* const kWrapperVersion = EC_WRAPPER_VERSION;

const char* ec_wrapper_version(void) {
    return kWrapperVersion;
}

// ---------------------------------------------------------------------------
// Bundle-load path: `+load` fires once when the shim's Mach-O is mapped into
// the process. This runs BEFORE any Unity C# code touches the shim, and
// therefore before any ec_* entry point — which is the only window during
// which `SdkPlatformOverrides.register(...)` can be called. See the
// Phase-1.5 remediation notes in `Unity-sdk-phase2-plan.md` for why the
// eager `init { }` block on `MacosEngagementCloud` forces this ordering.
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
// Callback dispatch helpers. Result / error strings must be copied by the
// callee before we return, so we own the memory.

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

// ---------------------------------------------------------------------------
// ec_setup — invokes MacosSetupApi.setPlatformWrapper (Phase-1.5 hook) then
// MacosSetupApi.enable(...) with an application-code-only config and a
// no-op onContactLinkingFailed callback.

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

    // Touching ECSDKEngagementCloud kicks off Koin init — but the +load path
    // has already registered the Unity overrides, so the resulting Koin
    // container has our InAppPresenterApi binding in place.
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
                    ec_dispatch_error(requestId,
                                      @"WrapperInfoException",
                                      wrapperError.localizedDescription,
                                      callback);
                    return;
                }

                ECSDKEngagementCloudConfig* config =
                    [[ECSDKEngagementCloudConfig alloc] initWithApplicationCode:appCode];

                id<ECSDKMacosSetupApi> strongSetup = weakSetup;
                if (!strongSetup) {
                    ec_dispatch_error(requestId,
                                      @"SetupFailedException",
                                      @"MacosSetupApi released before enable",
                                      callback);
                    return;
                }

                // No-op contact-linking-failed callback: resume with nil (accept
                // server default behaviour). Inner blocks must return
                // ECSDKKotlinUnit (Kotlin Unit boxed for Obj-C). See Gap 5 in
                // Phase-1.5 remediation.
                [strongSetup enableConfig:config
                onContactLinkingFailed:^(ECSDKKotlinUnit* (^successCb)(id<ECSDKLinkContactData> _Nullable),
                                          ECSDKKotlinUnit* (^errorCb)(NSError* _Nullable)) {
                    (void)errorCb;
                    successCb(nil);
                }
                     completionHandler:^(NSError* _Nullable enableError) {
                    if (enableError) {
                        ec_dispatch_error(requestId,
                                          @"SetupFailedException",
                                          enableError.localizedDescription,
                                          callback);
                        return;
                    }
                    ec_dispatch_success(requestId, nil, callback);
                }];
            }];
        }
    });
}

// ---------------------------------------------------------------------------
// Stubs — see EngagementCloudSDKUnity.h for the eventual contract. These
// short-circuit into an error callback so the C# side can distinguish
// "not-yet-implemented shim" from "SDK returned an error". Section B
// commit 2 replaces each with the real path.

#define EC_UNIMPLEMENTED(nameLit)                                              \
    ec_dispatch_error(requestId,                                               \
                      @"NotImplementedException",                              \
                      @nameLit @" not yet implemented in this shim build",     \
                      callback)

void ec_contact_setId(int32_t requestId, int32_t contactFieldId,
                      const char* contactFieldValue,
                      EcCompletionCallback callback) {
    (void)contactFieldId; (void)contactFieldValue;
    EC_UNIMPLEMENTED("ec_contact_setId");
}
void ec_contact_clear(int32_t requestId, EcCompletionCallback callback) {
    EC_UNIMPLEMENTED("ec_contact_clear");
}
void ec_event_track(int32_t requestId, const char* eventName,
                    const char* eventAttrsJson, EcCompletionCallback callback) {
    (void)eventName; (void)eventAttrsJson;
    EC_UNIMPLEMENTED("ec_event_track");
}
void ec_inapp_pause(int32_t requestId, EcCompletionCallback callback) {
    EC_UNIMPLEMENTED("ec_inapp_pause");
}
void ec_inapp_resume(int32_t requestId, EcCompletionCallback callback) {
    EC_UNIMPLEMENTED("ec_inapp_resume");
}
void ec_inapp_isPaused(int32_t requestId, EcCompletionCallback callback) {
    EC_UNIMPLEMENTED("ec_inapp_isPaused");
}
void ec_config_setContactFieldId(int32_t requestId, int32_t contactFieldId,
                                 EcCompletionCallback callback) {
    (void)contactFieldId;
    EC_UNIMPLEMENTED("ec_config_setContactFieldId");
}
void ec_config_getContactFieldId(int32_t requestId,
                                 EcCompletionCallback callback) {
    EC_UNIMPLEMENTED("ec_config_getContactFieldId");
}
void ec_deeplink_handle(int32_t requestId, const char* url,
                        EcCompletionCallback callback) {
    (void)url;
    EC_UNIMPLEMENTED("ec_deeplink_handle");
}
void ec_events_setSink(EcEventCallback callback) {
    (void)callback;
    NSLog(@"[EngagementCloudSDKUnity] ec_events_setSink not yet implemented");
}
void ec_logger_setSink(EcLogCallback callback) {
    (void)callback;
    NSLog(@"[EngagementCloudSDKUnity] ec_logger_setSink not yet implemented");
}
IOSurfaceRef _Nullable ec_inapp_texture_acquire(void) {
    NSLog(@"[EngagementCloudSDKUnity] ec_inapp_texture_acquire not yet implemented");
    return NULL;
}
void ec_inapp_input_send(int32_t kind, double x, double y, int32_t buttons) {
    (void)kind; (void)x; (void)y; (void)buttons;
}
void ec_inapp_setPresenterFrameCallback(EcPresenterFrameCallback callback) {
    (void)callback;
}
