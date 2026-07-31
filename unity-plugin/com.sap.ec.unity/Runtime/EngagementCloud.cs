using System;
using System.Text;
using System.Threading.Tasks;
using EngagementCloud.Internal;
using UnityEngine;

namespace EngagementCloud
{
    /// <summary>
    /// Top-level, static entry point for the Unity plugin. Every method returns a
    /// <see cref="Task"/> whose continuation resumes on Unity's main thread (see
    /// <see cref="MainThreadPump"/>). The exception surface is the typed
    /// <see cref="EngagementCloudException"/> hierarchy.
    ///
    /// The SDK's Kotlin side is initialised lazily on the first call — the shim installs event
    /// and log sinks in its bundle-load constructor, so <see cref="EventReceived"/> is safe to
    /// subscribe to before <see cref="Setup"/>.
    /// </summary>
    /// <remarks>
    /// POC scope: overlay in-app messages are rendered by the SDK's default macOS
    /// <c>MacosInAppPresenter</c> — they pop as a borderless <c>NSWindow</c> above the Unity
    /// Player. Texture-based composition (offscreen WKWebView → IOSurface → external
    /// <c>Texture2D</c>) is deferred to a follow-up drop.
    /// </remarks>
    public static class EngagementCloud
    {
        /// <summary>
        /// Fired every time the Kotlin SDK emits an <c>EngagementCloudEvent</c>. Always raised on
        /// Unity's main thread. Subscribe / unsubscribe from any thread.
        /// </summary>
        public static event Action<SdkEvent> EventReceived;

        // Ensure the P/Invoke sinks are wired exactly once, before the first shim call.
        private static readonly object s_sinkLock = new object();
        private static bool s_sinksInstalled;

        static EngagementCloud()
        {
            // On IL2CPP the type initialiser runs the first time a static member is touched;
            // that is either an EventReceived subscription (before scene load, via AutoInit)
            // or the first Setup call. Either way the sinks are ready before we take the shim
            // for a spin.
            EnsureSinksInstalled();
        }

        private static void EnsureSinksInstalled()
        {
            lock (s_sinkLock)
            {
                if (s_sinksInstalled) return;
                try
                {
                    NativeBridge.ec_events_setSink(NativeCallbacks.EventThunk);
                    NativeBridge.ec_logger_setSink(NativeCallbacks.LogThunk);
                    s_sinksInstalled = true;
                }
                catch (DllNotFoundException)
                {
                    // Editor may run without the .bundle staged in Plugins/macOS yet — surface a
                    // one-time hint but keep going; explicit calls will surface their own error.
                    Debug.LogWarning("[EngagementCloud] EngagementCloudSDKUnity.bundle not found — did you build the shim (`make unity-shim`) and stage it under Plugins/macOS/?");
                }
            }
        }

        // Internal hook so InlineInAppView (and any future companion type) can force sink
        // installation before its first shim call — avoids depending on the static ctor
        // order for consumers that never touch a Setup / Track method.
        internal static void EnsureSinksInstalledInternal() => EnsureSinksInstalled();

        internal static void RaiseEvent(SdkEvent evt)
        {
            var handler = EventReceived;
            if (handler == null) return;
            try
            {
                handler(evt);
            }
            catch (Exception ex)
            {
                Debug.LogException(ex);
            }
        }

        /// <summary>
        /// Enable the SDK with a given application code. Corresponds to the Kotlin
        /// <c>EngagementCloud.setup.enable(...)</c>. Safe to <c>await</c>; the returned task
        /// completes when the Kotlin state machine reaches its post-enable steady state.
        /// </summary>
        /// <param name="applicationCode">Backend-provided app code (e.g. <c>"EMSE3-B4341"</c>).</param>
        public static Task Setup(string applicationCode)
        {
            if (string.IsNullOrEmpty(applicationCode)) throw new ArgumentException("applicationCode required", nameof(applicationCode));
            EnsureSinksInstalled();
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_setup(id, applicationCode, NativeCallbacks.CompletionThunk);
            return tcs.Task;
        }

        /// <summary>Disable the SDK. See Kotlin <c>EngagementCloud.setup.disable()</c>.</summary>
        public static Task Disable()
        {
            EnsureSinksInstalled();
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_disable(id, NativeCallbacks.CompletionThunk);
            return tcs.Task;
        }

        /// <summary>
        /// Async mirror of Kotlin <c>setup.isEnabled()</c>. The underlying Kotlin function is a
        /// <c>suspend fun</c>, so we can't offer a synchronous getter without risking a queue
        /// deadlock. Returns <c>false</c> if the shim can't be reached (e.g. Editor without
        /// staged bundle) — the shim still throws through <see cref="EngagementCloudException"/>
        /// on any other failure.
        /// </summary>
        public static async Task<bool> IsEnabled()
        {
            EnsureSinksInstalled();
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_setup_isEnabled(id, NativeCallbacks.CompletionThunk);
            string result = await tcs.Task;
            return string.Equals(result, "true", StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>Link a contact by field value (e-mail address by default).</summary>
        public static Task LinkContact(string contactFieldValue)
        {
            if (contactFieldValue == null) throw new ArgumentNullException(nameof(contactFieldValue));
            EnsureSinksInstalled();
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_contact_linkByValue(id, contactFieldValue, NativeCallbacks.CompletionThunk);
            return tcs.Task;
        }

        /// <summary>
        /// Track a custom event. <paramref name="attributes"/> is a JSON object string (may be
        /// <c>null</c>). Backend automations key off <paramref name="eventName"/> to trigger
        /// in-app messages, push campaigns, etc.
        /// </summary>
        public static Task TrackEvent(string eventName, string attributesJson = null)
        {
            if (string.IsNullOrEmpty(eventName)) throw new ArgumentException("eventName required", nameof(eventName));
            EnsureSinksInstalled();
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_event_track(id, eventName, attributesJson ?? "", NativeCallbacks.CompletionThunk);
            return tcs.Task;
        }

        // Convenience wrappers over ec_config_* — each returns the raw string result.
        public static async Task<string> GetSdkVersion()
        {
            EnsureSinksInstalled();
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_config_getSdkVersion(id, NativeCallbacks.CompletionThunk);
            return await tcs.Task;
        }

        public static async Task<string> GetApplicationCode()
        {
            EnsureSinksInstalled();
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_config_getApplicationCode(id, NativeCallbacks.CompletionThunk);
            return await tcs.Task;
        }

        public static async Task<string> GetClientId()
        {
            EnsureSinksInstalled();
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_config_getClientId(id, NativeCallbacks.CompletionThunk);
            return await tcs.Task;
        }

        /// <summary>Pause in-app message display. New messages queue instead of showing.</summary>
        public static Task PauseInApp()
        {
            EnsureSinksInstalled();
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_inapp_pause(id, NativeCallbacks.CompletionThunk);
            return tcs.Task;
        }

        /// <summary>Resume in-app message display. Any queued messages are re-evaluated.</summary>
        public static Task ResumeInApp()
        {
            EnsureSinksInstalled();
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_inapp_resume(id, NativeCallbacks.CompletionThunk);
            return tcs.Task;
        }

        /// <summary>Whether in-app display is currently paused (synchronous, cached).</summary>
        public static bool IsInAppPaused()
        {
            EnsureSinksInstalled();
            return NativeBridge.ec_inapp_isPaused() != 0;
        }

        /// <summary>
        /// Route a URL through the deep-link handler. Returns <c>true</c> if the SDK matched a
        /// tracked link and consumed the URL, <c>false</c> otherwise (in which case the caller
        /// is free to route the URL elsewhere).
        /// </summary>
        /// <remarks>
        /// Deep-link tracking is synchronous on the Kotlin side (<c>MacosDeepLinkApi.track</c>
        /// is a plain function), so this method does not return a <see cref="Task"/>. The URL
        /// is wrapped in an <c>NSUserActivity</c> of type <c>NSUserActivityTypeBrowsingWeb</c>
        /// inside the shim to match what the framework expects.
        /// </remarks>
        public static bool TrackDeepLink(string url)
        {
            if (string.IsNullOrEmpty(url)) return false;
            EnsureSinksInstalled();
            return NativeBridge.ec_deeplink_trackUrl(url) != 0;
        }
    }
}
