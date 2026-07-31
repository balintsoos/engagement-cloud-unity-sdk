// EngagementCloudSDKUnity — C surface consumed by the Unity C# runtime via
// P/Invoke (`DllImport("EngagementCloudSDKUnity")`).
//
// Async model: every non-void entry point takes a monotonically-increasing
// request id and a callback pointer. The shim invokes the callback exactly
// once on completion (or error) on an arbitrary shim-owned thread — the C#
// side is responsible for pumping onto Unity's main thread. Result payloads
// and error payloads are UTF-8 JSON strings whose ownership passes to the
// callback: the callee copies the strings and returns; the shim then frees
// the memory. If a call succeeds with no meaningful result, `resultJson` is
// `NULL` and `errorJson` is `NULL`; on error, `errorJson` is a JSON-encoded
// exception per `EcExceptionMarshaller.mm`.
//
// String scalars are UTF-8 C strings, transient on entry (shim copies before
// returning). Enum values (`SdkState`, log severity, input kind) travel as
// int32_t; the mapping is spelled out per-function.

#ifndef ENGAGEMENT_CLOUD_SDK_UNITY_H
#define ENGAGEMENT_CLOUD_SDK_UNITY_H

#include <stdint.h>
#include <IOSurface/IOSurfaceRef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Callback signatures --------------------------------------------------------

// Fired on completion of any async ec_* call. Exactly one of resultJson /
// errorJson is non-NULL. Both pointers are shim-owned; the callee must copy
// their contents before returning.
typedef void (*EcCompletionCallback)(int32_t requestId,
                                     const char* _Nullable resultJson,
                                     const char* _Nullable errorJson);

// Fired for every SdkEvent the SDK emits. `eventJson` is shim-owned UTF-8;
// copy before returning. Registered once via ec_events_setSink.
typedef void (*EcEventCallback)(const char* eventJson);

// Fired for every SDK log entry. `severity` is 0=Debug, 1=Info, 2=Warning,
// 3=Error. `message` is shim-owned UTF-8; copy before returning.
typedef void (*EcLogCallback)(int32_t severity, const char* message);

// Fired when the in-app presenter has a fresh frame available on the
// IOSurface returned by ec_inapp_texture_acquire. Fired on the presenter's
// serial queue. `frameIndex` is a monotonically-increasing counter useful
// for detecting missed frames.
typedef void (*EcPresenterFrameCallback)(uint64_t frameIndex);

// Setup ----------------------------------------------------------------------

// Application code is UTF-8. Wrapper identity is set inside the shim before
// enable() is invoked, using the `MacosSetupApi.setPlatformWrapper` hook.
void ec_setup(int32_t requestId,
              const char* applicationCode,
              EcCompletionCallback callback);

// Contact --------------------------------------------------------------------

// Link the current device to a contact by field value. Contact-field id is
// server-configured (or set via config.changeApplicationCode). See
// `MacosContactApi.link` in the Kotlin SDK.
void ec_contact_link(int32_t requestId,
                     const char* contactFieldValue,
                     EcCompletionCallback callback);

// Link the current device to a contact via a signed OpenID token.
void ec_contact_linkAuthenticated(int32_t requestId,
                                  const char* openIdToken,
                                  EcCompletionCallback callback);

// Remove the current contact link.
void ec_contact_unlink(int32_t requestId, EcCompletionCallback callback);

// Event ----------------------------------------------------------------------

// Track a custom event. `eventAttrsStringMapJson` is a UTF-8 JSON object of
// {string: string} (may be NULL for events with no attributes). Non-string
// values in the JSON are rejected with a marshalling error before the SDK is
// touched — the underlying SDK contract is string→string.
void ec_event_track(int32_t requestId,
                    const char* eventName,
                    const char* _Nullable eventAttrsStringMapJson,
                    EcCompletionCallback callback);

// In-app messages ------------------------------------------------------------

void ec_inapp_pause(int32_t requestId, EcCompletionCallback callback);
void ec_inapp_resume(int32_t requestId, EcCompletionCallback callback);

// Synchronous read of the `isPaused` property. Returns 1 if paused, 0 if not.
// Available at any time after ec_setup completes.
int32_t ec_inapp_isPaused(void);

// Config ---------------------------------------------------------------------

void ec_config_changeApplicationCode(int32_t requestId,
                                     const char* applicationCode,
                                     EcCompletionCallback callback);
void ec_config_getApplicationCode(int32_t requestId,
                                  EcCompletionCallback callback);
void ec_config_getApplicationVersion(int32_t requestId,
                                     EcCompletionCallback callback);
void ec_config_getClientId(int32_t requestId, EcCompletionCallback callback);
void ec_config_getSdkVersion(int32_t requestId, EcCompletionCallback callback);
void ec_config_getLanguageCode(int32_t requestId, EcCompletionCallback callback);
void ec_config_setLanguage(int32_t requestId,
                           const char* language,
                           EcCompletionCallback callback);
void ec_config_resetLanguage(int32_t requestId, EcCompletionCallback callback);

// Result is one of: 0 = uninitialized, 1 = initialized, 2 = active, 3 = onhold.
// Reported through the completion callback's `resultJson` as `{"state":<int>}`.
void ec_config_getCurrentSdkState(int32_t requestId, EcCompletionCallback callback);

// Deep link ------------------------------------------------------------------

// Track a deep-link URL. Internally builds an NSUserActivity(BrowsingWeb) with
// `webpageURL = url` and forwards to `MacosDeepLinkApi.track`. Synchronous;
// returns 1 if the SDK consumed the link, 0 otherwise.
int32_t ec_deeplink_trackUrl(const char* url);

// Events sink (single global) -----------------------------------------------

// Registers the `EngagementCloudEvent` listener via
// `EngagementCloud.registerEventListener(...)`. Every emitted event is
// JSON-serialized and dispatched to `callback` on an arbitrary background
// thread. Passing NULL clears any previously-registered sink.
void ec_events_setSink(EcEventCallback _Nullable callback);

// Logger sink (single global) -----------------------------------------------

// v1: not yet wired to the SDK's logger — the Kotlin logger surface is
// package-internal. See phase-2 plan Section B commit 2 notes.
void ec_logger_setSink(EcLogCallback _Nullable callback);

// In-app texture presenter --------------------------------------------------

// Acquires (and lazily creates) the IOSurface the offscreen WKWebView renders
// into. Returned surface is retained by the shim; the caller must NOT release
// it. Wraps into a Metal MTLTexture on the C# side via
// `MTLDevice.newTextureWithDescriptor:iosurface:plane:`. Section C.
IOSurfaceRef _Nullable ec_inapp_texture_acquire(void);

// Send a synthesized mouse event to the offscreen WebView.
// kind: 0=Move, 1=Down, 2=Up
// buttons: bitmask, bit 0 = primary, bit 1 = secondary
// x/y are WebView-pixel coordinates (top-left origin; C# flips before calling).
void ec_inapp_input_send(int32_t kind,
                         double x, double y,
                         int32_t buttons);

// Presenter frame notification (optional; C# can also poll every Update).
void ec_inapp_setPresenterFrameCallback(EcPresenterFrameCallback _Nullable callback);

// Introspection --------------------------------------------------------------

// Returns the shim's platform-wrapper version string as compiled in (see
// EC_WRAPPER_VERSION in the xcodegen spec). Caller must NOT free.
const char* ec_wrapper_version(void);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // ENGAGEMENT_CLOUD_SDK_UNITY_H
