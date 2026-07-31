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
// Complex payloads (event attributes, `SdkEvent` variants) travel as JSON.
// Scalars travel as scalars.

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

void ec_contact_setId(int32_t requestId,
                      int32_t contactFieldId,
                      const char* contactFieldValue,
                      EcCompletionCallback callback);

void ec_contact_clear(int32_t requestId, EcCompletionCallback callback);

// Event ----------------------------------------------------------------------

// eventAttrsJson is a UTF-8 JSON object of {string: JsonElement} (may be NULL
// for events with no attributes).
void ec_event_track(int32_t requestId,
                    const char* eventName,
                    const char* _Nullable eventAttrsJson,
                    EcCompletionCallback callback);

// In-app messages ------------------------------------------------------------

void ec_inapp_pause(int32_t requestId, EcCompletionCallback callback);
void ec_inapp_resume(int32_t requestId, EcCompletionCallback callback);
void ec_inapp_isPaused(int32_t requestId, EcCompletionCallback callback);

// Config ---------------------------------------------------------------------

void ec_config_setContactFieldId(int32_t requestId,
                                 int32_t contactFieldId,
                                 EcCompletionCallback callback);
void ec_config_getContactFieldId(int32_t requestId,
                                 EcCompletionCallback callback);

// Deep link ------------------------------------------------------------------

void ec_deeplink_handle(int32_t requestId,
                        const char* url,
                        EcCompletionCallback callback);

// Events sink (single global) -----------------------------------------------

void ec_events_setSink(EcEventCallback callback);

// Logger sink (single global) -----------------------------------------------

void ec_logger_setSink(EcLogCallback callback);

// In-app texture presenter --------------------------------------------------

// Acquires (and lazily creates) the IOSurface the offscreen WKWebView renders
// into. Returned surface is retained by the shim; the caller must NOT release
// it. Wraps into a Metal MTLTexture on the C# side via
// `MTLDevice.newTextureWithDescriptor:iosurface:plane:`.
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
