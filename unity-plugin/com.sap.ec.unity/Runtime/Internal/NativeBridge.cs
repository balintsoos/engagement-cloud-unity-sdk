using System;
using System.Runtime.InteropServices;

namespace EngagementCloud.Internal
{
    /// <summary>
    /// Direct P/Invoke surface into the native shim
    /// (<c>EngagementCloudSDKUnity.bundle</c>).
    ///
    /// One-to-one with the C entry points declared in
    /// <c>unity-plugin/shim/src/EngagementCloudSDKUnity.h</c>. Callers hand a
    /// <see cref="CompletionCallback"/> pointer produced by
    /// <see cref="CallbackDispatchers.MakeCompletion"/> so the native side can
    /// invoke back on completion.
    ///
    /// String lifetime: strings passed IN are marshaled by
    /// <see cref="LPUTF8Str"/> (Unity 6 supports this via System.Runtime.InteropServices);
    /// strings passed OUT to callbacks arrive as <see cref="IntPtr"/> to
    /// shim-owned UTF-8 buffers that the callback must copy before returning.
    /// See <see cref="CallbackDispatchers"/>.
    /// </summary>
    internal static class NativeBridge
    {
        private const string DllName = "EngagementCloudSDKUnity";

        // Native callback signatures ------------------------------------------

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        internal delegate void CompletionCallback(int requestId, IntPtr resultJsonUtf8, IntPtr errorJsonUtf8);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        internal delegate void EventCallback(IntPtr eventJsonUtf8);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        internal delegate void LogCallback(int severity, IntPtr messageUtf8);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        internal delegate void PresenterFrameCallback(ulong frameIndex);

        // Setup ---------------------------------------------------------------

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        internal static extern void ec_setup(int requestId,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string applicationCode,
            CompletionCallback callback);

        // Contact -------------------------------------------------------------

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        internal static extern void ec_contact_link(int requestId,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string contactFieldValue,
            CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        internal static extern void ec_contact_linkAuthenticated(int requestId,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string openIdToken,
            CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_contact_unlink(int requestId, CompletionCallback callback);

        // Event ---------------------------------------------------------------

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        internal static extern void ec_event_track(int requestId,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string eventName,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string eventAttrsStringMapJson,
            CompletionCallback callback);

        // In-app messages -----------------------------------------------------

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_inapp_pause(int requestId, CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_inapp_resume(int requestId, CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int ec_inapp_isPaused();

        // Config --------------------------------------------------------------

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        internal static extern void ec_config_changeApplicationCode(int requestId,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string applicationCode,
            CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_config_getApplicationCode(int requestId, CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_config_getApplicationVersion(int requestId, CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_config_getClientId(int requestId, CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_config_getSdkVersion(int requestId, CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_config_getLanguageCode(int requestId, CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        internal static extern void ec_config_setLanguage(int requestId,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string language,
            CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_config_resetLanguage(int requestId, CompletionCallback callback);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_config_getCurrentSdkState(int requestId, CompletionCallback callback);

        // Deep link -----------------------------------------------------------

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        internal static extern int ec_deeplink_trackUrl(
            [MarshalAs(UnmanagedType.LPUTF8Str)] string url);

        // Events sink ---------------------------------------------------------

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_events_setSink(EventCallback callback);

        // Logger sink (currently a no-op on the native side) ------------------

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_logger_setSink(LogCallback callback);

        // In-app texture presenter -------------------------------------------

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr ec_inapp_texture_acquire();

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_inapp_input_send(int kind, double x, double y, int buttons);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void ec_inapp_setPresenterFrameCallback(PresenterFrameCallback callback);

        // Introspection -------------------------------------------------------

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr ec_wrapper_version();
    }
}
