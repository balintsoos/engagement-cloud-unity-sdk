using System;
using System.Runtime.InteropServices;

namespace EngagementCloud.Internal
{
    /// <summary>
    /// All <c>DllImport</c> entry points into <c>EngagementCloudSDKUnity.bundle</c> (the
    /// Obj-C++ shim). Every C entry point takes:
    /// <list type="bullet">
    ///   <item><description>an <c>int</c> request id — the shim invokes the completion callback with the same id.</description></item>
    ///   <item><description>UTF-8 <c>string</c> arguments — Unity marshals them to the shim's <c>const char *</c>.</description></item>
    ///   <item><description>a completion function pointer — a <c>[MonoPInvokeCallback]</c> static in <see cref="NativeCallbacks"/>.</description></item>
    /// </list>
    /// The shim replies exactly once per request. Any complex return payload arrives as a UTF-8
    /// JSON pointer (<c>resultJsonPtr</c>); errors arrive as a UTF-8 JSON pointer
    /// (<c>errorJsonPtr</c>) whose absence (<c>IntPtr.Zero</c>) signals success. Both pointers are
    /// owned by the shim and are freed immediately after the callback returns.
    /// </summary>
    /// <remarks>
    /// POC scope: overlay in-apps use the framework's default AppKit NSWindow overlay presenter.
    /// The offscreen WKWebView + IOSurface texture path from the Phase-2 plan is deferred; the
    /// corresponding entry points (<c>ec_inapp_texture_acquire</c>, <c>ec_inapp_input_send</c>)
    /// are stubbed out here so the C# facade stays call-compatible with the eventual full impl.
    /// </remarks>
    internal static class NativeBridge
    {
        // The shim ships as EngagementCloudSDKUnity.bundle; on macOS Unity resolves DllImport
        // names to the bundle's binary in Plugins/macOS.
        private const string DLL = "EngagementCloudSDKUnity";

        // -- lifecycle --
        [DllImport(DLL)] internal static extern void ec_setup(int reqId, string applicationCodeUtf8, NativeCallbacks.CompletionFn onCompletion);
        [DllImport(DLL)] internal static extern void ec_disable(int reqId, NativeCallbacks.CompletionFn onCompletion);
        [DllImport(DLL)] internal static extern void ec_setup_isEnabled(int reqId, NativeCallbacks.CompletionFn onCompletion);

        // -- config (readonly bits worth exposing) --
        [DllImport(DLL)] internal static extern void ec_config_getSdkVersion(int reqId, NativeCallbacks.CompletionFn onCompletion);
        [DllImport(DLL)] internal static extern void ec_config_getApplicationCode(int reqId, NativeCallbacks.CompletionFn onCompletion);
        [DllImport(DLL)] internal static extern void ec_config_getClientId(int reqId, NativeCallbacks.CompletionFn onCompletion);

        // -- contact --
        [DllImport(DLL)] internal static extern void ec_contact_linkByValue(int reqId, string contactFieldValueUtf8, NativeCallbacks.CompletionFn onCompletion);

        // -- events --
        [DllImport(DLL)] internal static extern void ec_event_track(int reqId, string eventNameUtf8, string attributesJsonUtf8, NativeCallbacks.CompletionFn onCompletion);

        // -- in-app control (isPaused is a Kotlin property; safe to poll synchronously) --
        [DllImport(DLL)] internal static extern void ec_inapp_pause(int reqId, NativeCallbacks.CompletionFn onCompletion);
        [DllImport(DLL)] internal static extern void ec_inapp_resume(int reqId, NativeCallbacks.CompletionFn onCompletion);
        [DllImport(DLL)] internal static extern int  ec_inapp_isPaused();

        // -- deep link (MacosDeepLinkApi.track(userActivity:) is a plain function — sync) --
        [DllImport(DLL)] internal static extern int  ec_deeplink_trackUrl(string urlUtf8);

        // -- global sinks: at most one active at a time --
        [DllImport(DLL)] internal static extern void ec_events_setSink(NativeCallbacks.EventFn onEvent);
        [DllImport(DLL)] internal static extern void ec_logger_setSink(NativeCallbacks.LogFn onLog);

        // -- inline in-app texture path --
        //  * ec_inline_open  — async: fetches the inline WKWebView, hosts it on an offscreen NSPanel, starts a ~30 Hz snapshot loop.
        //  * ec_inline_close — sync teardown of the session.
        //  * ec_inline_lockFrame — sync: returns a pointer to the latest BGRA buffer + monotonic version.
        //  * ec_inline_sendPointer — sync: posts a synthesized NSEvent to the offscreen panel.
        [DllImport(DLL)] internal static extern void ec_inline_open(int reqId, string viewIdUtf8, int width, int height, NativeCallbacks.CompletionFn onCompletion);
        [DllImport(DLL)] internal static extern void ec_inline_close(string viewIdUtf8);
        [DllImport(DLL)] internal static extern int  ec_inline_lockFrame(string viewIdUtf8, out IntPtr buf, out int width, out int height, out int stride, out long version);
        [DllImport(DLL)] internal static extern void ec_inline_sendPointer(string viewIdUtf8, int kind, float x, float y);
    }
}
