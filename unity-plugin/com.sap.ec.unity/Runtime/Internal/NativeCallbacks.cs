using System;
using System.Runtime.InteropServices;
using AOT;
using UnityEngine;

namespace EngagementCloud.Internal
{
    /// <summary>
    /// Static callback trampolines exposed to the Obj-C++ shim. IL2CPP requires that anything
    /// crossing the P/Invoke boundary as a function pointer be a <c>static</c> method annotated
    /// with <see cref="MonoPInvokeCallbackAttribute"/>; instance methods and closures will not
    /// survive AOT stripping. All three signatures below match the shim's typedefs in
    /// <c>EcAsyncBridge.mm</c> byte-for-byte.
    /// </summary>
    /// <remarks>
    /// The shim owns every UTF-8 buffer it hands us. We copy synchronously with
    /// <see cref="Marshal.PtrToStringUTF8(IntPtr)"/> BEFORE returning; after return the shim
    /// frees the buffer, so the string reference we keep is a managed copy.
    /// </remarks>
    internal static class NativeCallbacks
    {
        /// <summary>
        /// Completion delegate for request-response entry points. <paramref name="reqId"/> matches
        /// the id passed to the entry point; success sets <paramref name="resultJsonPtr"/>
        /// (may be <c>IntPtr.Zero</c> for methods that return <c>Unit</c>) and leaves
        /// <paramref name="errorJsonPtr"/> = <c>IntPtr.Zero</c>. Failure sets
        /// <paramref name="errorJsonPtr"/> to a UTF-8 JSON string describing a mapped exception
        /// (see <see cref="EngagementCloudException.FromJson(string)"/>).
        /// </summary>
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        internal delegate void CompletionFn(int reqId, IntPtr resultJsonPtr, IntPtr errorJsonPtr);

        /// <summary>Event sink delegate. Payload is a UTF-8 JSON string; see <see cref="SdkEvent"/>.</summary>
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        internal delegate void EventFn(IntPtr eventJsonPtr);

        /// <summary>
        /// Log sink delegate. <paramref name="severity"/> is 0=verbose, 1=debug, 2=info,
        /// 3=warning, 4=error — matching Kotlin's <c>LogLevel</c> ordinal.
        /// </summary>
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        internal delegate void LogFn(int severity, IntPtr messageUtf8);

        // MonoPInvokeCallback demands a `static` delegate reference — keeping these as fields on
        // the static class prevents them from being GC'd while the shim still holds the pointer.
        internal static readonly CompletionFn CompletionThunk = OnCompletion;
        internal static readonly EventFn      EventThunk      = OnEvent;
        internal static readonly LogFn        LogThunk        = OnLog;

        [MonoPInvokeCallback(typeof(CompletionFn))]
        private static void OnCompletion(int reqId, IntPtr resultJsonPtr, IntPtr errorJsonPtr)
        {
            // Copy immediately — buffers are shim-owned and freed after this returns.
            string result = resultJsonPtr == IntPtr.Zero ? null : Marshal.PtrToStringUTF8(resultJsonPtr);
            string error  = errorJsonPtr  == IntPtr.Zero ? null : Marshal.PtrToStringUTF8(errorJsonPtr);

            // Resolution happens off the P/Invoke callback thread — resolve on Unity's main
            // thread via the pump so `.ContinueWith` (Unity's default SynchronizationContext)
            // continuations land in a Unity-safe place.
            MainThreadPump.Post(() => RequestRegistry.Resolve(reqId, result, error));
        }

        [MonoPInvokeCallback(typeof(EventFn))]
        private static void OnEvent(IntPtr eventJsonPtr)
        {
            if (eventJsonPtr == IntPtr.Zero) return;
            string json = Marshal.PtrToStringUTF8(eventJsonPtr);
            MainThreadPump.Post(() =>
            {
                try
                {
                    var evt = SdkEvent.FromJson(json);
                    if (evt != null) EngagementCloud.RaiseEvent(evt);
                }
                catch (Exception ex)
                {
                    Debug.LogWarning($"[EngagementCloud] failed to decode SdkEvent: {ex.Message}\nraw: {json}");
                }
            });
        }

        [MonoPInvokeCallback(typeof(LogFn))]
        private static void OnLog(int severity, IntPtr messageUtf8)
        {
            if (messageUtf8 == IntPtr.Zero) return;
            string message = Marshal.PtrToStringUTF8(messageUtf8);
            MainThreadPump.Post(() =>
            {
                const string prefix = "[EngagementCloud] ";
                switch (severity)
                {
                    case 0: // verbose
                    case 1: // debug
                    case 2: // info
                        Debug.Log(prefix + message);
                        break;
                    case 3:
                        Debug.LogWarning(prefix + message);
                        break;
                    default:
                        Debug.LogError(prefix + message);
                        break;
                }
            });
        }
    }
}
