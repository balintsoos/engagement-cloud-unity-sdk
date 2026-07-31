using System;
using System.Text.Json;
using AOT;
using UnityEngine;

namespace EngagementCloud.Internal
{
    /// <summary>
    /// Static callback trampolines that IL2CPP needs to prove reachable from
    /// managed code. All bodies must be <c>[MonoPInvokeCallback]</c> and
    /// <c>static</c>; the delegate instances that hold pointers into these
    /// methods are cached to prevent GC of the underlying thunks.
    ///
    /// Runtime shape:
    ///   1. Native side invokes one of these on an arbitrary shim thread.
    ///   2. The static method copies its arguments (UTF-8 pointers → managed
    ///      strings) synchronously.
    ///   3. Enqueues onto <see cref="MainThreadPump"/> so the actual work
    ///      (deserializing JSON, resolving <see cref="RequestRegistry"/>,
    ///      firing user callbacks) happens on Unity's main thread.
    /// </summary>
    internal static class CallbackDispatchers
    {
        // Delegate instances must be kept alive for the lifetime of any
        // pending native call; otherwise IL2CPP's thunk could be GC'd from
        // under the native side. Store them once and hand out the same
        // reference every time.
        internal static readonly NativeBridge.CompletionCallback CompletionInstance = OnCompletion;
        internal static readonly NativeBridge.EventCallback EventInstance = OnEvent;
        internal static readonly NativeBridge.LogCallback LogInstance = OnLog;
        internal static readonly NativeBridge.PresenterFrameCallback PresenterFrameInstance = OnPresenterFrame;

        internal static Action<SdkEvent> UserEventHandler;
        internal static Action<int, string> UserLogHandler;
        internal static Action<ulong> UserPresenterFrameHandler;

        [MonoPInvokeCallback(typeof(NativeBridge.CompletionCallback))]
        private static void OnCompletion(int requestId, IntPtr resultJsonPtr, IntPtr errorJsonPtr)
        {
            // Copy synchronously — native buffers are only valid for the
            // duration of this call.
            string resultJson = NativeUtf8.PtrToString(resultJsonPtr);
            string errorJson = NativeUtf8.PtrToString(errorJsonPtr);

            MainThreadPump.Post(() =>
            {
                if (errorJson != null)
                {
                    try
                    {
                        var envelope = JsonSerializer.Deserialize<ErrorEnvelope>(errorJson);
                        RequestRegistry.Fail(requestId, EngagementCloudException.FromEnvelope(
                            envelope?.Type, envelope?.Message));
                    }
                    catch (Exception e)
                    {
                        RequestRegistry.Fail(requestId, new EngagementCloudException(
                            "UnknownException",
                            $"Failed to parse error envelope: {e.Message}. Raw: {errorJson}"));
                    }
                    return;
                }
                RequestRegistry.Resolve(requestId, resultJson);
            });
        }

        [MonoPInvokeCallback(typeof(NativeBridge.EventCallback))]
        private static void OnEvent(IntPtr eventJsonPtr)
        {
            string json = NativeUtf8.PtrToString(eventJsonPtr);
            if (json == null) return;

            MainThreadPump.Post(() =>
            {
                if (UserEventHandler == null) return;
                try
                {
                    var envelope = JsonSerializer.Deserialize<EventEnvelope>(json);
                    if (envelope == null) return;
                    UserEventHandler(new SdkEvent(envelope.Type, envelope.Description));
                }
                catch (Exception e)
                {
                    Debug.LogWarning($"[EngagementCloud] Failed to parse event envelope: {e.Message}. Raw: {json}");
                }
            });
        }

        [MonoPInvokeCallback(typeof(NativeBridge.LogCallback))]
        private static void OnLog(int severity, IntPtr messagePtr)
        {
            string message = NativeUtf8.PtrToString(messagePtr);
            if (message == null) return;
            MainThreadPump.Post(() =>
            {
                UserLogHandler?.Invoke(severity, message);
                string prefixed = $"[EngagementCloud] {message}";
                switch (severity)
                {
                    case 0: case 1: Debug.Log(prefixed); break;
                    case 2: Debug.LogWarning(prefixed); break;
                    default: Debug.LogError(prefixed); break;
                }
            });
        }

        [MonoPInvokeCallback(typeof(NativeBridge.PresenterFrameCallback))]
        private static void OnPresenterFrame(ulong frameIndex)
        {
            // Presenter frame callbacks fire on the shim's serial queue at
            // ~30 Hz. Hop to Unity's main thread so the C# side can safely
            // refresh its external texture.
            MainThreadPump.Post(() => UserPresenterFrameHandler?.Invoke(frameIndex));
        }
    }
}
