using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using EngagementCloud.Internal;
using UnityEngine;

namespace EngagementCloud
{
    /// <summary>
    /// Static facade for the SAP Engagement Cloud SDK on macOS.
    ///
    /// All async methods return <see cref="Task"/>/<see cref="Task{TResult}"/>
    /// that complete on Unity's main thread. Exceptions surface as
    /// <see cref="EngagementCloudException"/> or one of its typed subclasses.
    ///
    /// Setup: either call <see cref="Setup(string)"/> explicitly from user
    /// code, or drop an <c>EngagementCloudSettings</c> ScriptableObject into
    /// <c>Resources/</c> and enable <c>autoInit</c> — see
    /// <see cref="AutoInit"/>.
    /// </summary>
    public static class EngagementCloud
    {
        /// <summary>Fired for every event the SDK emits. Callbacks run on
        /// Unity's main thread.</summary>
        public static event Action<SdkEvent> EventReceived
        {
            add { CallbackDispatchers.UserEventHandler += value; EnsureEventSink(); }
            remove { CallbackDispatchers.UserEventHandler -= value; }
        }

        /// <summary>Fired for every SDK log entry (severity 0=Debug, 1=Info,
        /// 2=Warning, 3=Error). Callbacks run on Unity's main thread. The
        /// native logger sink is not yet wired (see phase-2 plan Section B);
        /// this event will start firing once that lands.</summary>
        public static event Action<int, string> LogEmitted
        {
            add { CallbackDispatchers.UserLogHandler += value; EnsureLogSink(); }
            remove { CallbackDispatchers.UserLogHandler -= value; }
        }

        /// <summary>Fired every time the in-app texture presenter produces a
        /// fresh frame in the IOSurface returned by
        /// <see cref="InAppTextureView"/>. Callbacks run on Unity's main
        /// thread.</summary>
        public static event Action<ulong> InAppFrameReceived
        {
            add { CallbackDispatchers.UserPresenterFrameHandler += value; EnsurePresenterFrameSink(); }
            remove { CallbackDispatchers.UserPresenterFrameHandler -= value; }
        }

        // Sink registration is idempotent on both sides; the shim only
        // touches the underlying SDK the first time a callback is registered.
        private static bool s_eventSinkSet;
        private static bool s_logSinkSet;
        private static bool s_presenterFrameSinkSet;

        private static void EnsureEventSink()
        {
            if (s_eventSinkSet) return;
            s_eventSinkSet = true;
            NativeBridge.ec_events_setSink(CallbackDispatchers.EventInstance);
        }
        private static void EnsureLogSink()
        {
            if (s_logSinkSet) return;
            s_logSinkSet = true;
            NativeBridge.ec_logger_setSink(CallbackDispatchers.LogInstance);
        }
        private static void EnsurePresenterFrameSink()
        {
            if (s_presenterFrameSinkSet) return;
            s_presenterFrameSinkSet = true;
            NativeBridge.ec_inapp_setPresenterFrameCallback(CallbackDispatchers.PresenterFrameInstance);
        }

        // Setup ---------------------------------------------------------------

        /// <summary>Enable the SDK with the given application code. Must be
        /// called (or auto-called via <see cref="AutoInit"/>) before any
        /// other SDK method.</summary>
        public static Task Setup(string applicationCode)
        {
            if (applicationCode == null) throw new ArgumentNullException(nameof(applicationCode));
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_setup(id, applicationCode, CallbackDispatchers.CompletionInstance);
            return tcs.Task;
        }

        // Contact -------------------------------------------------------------

        public static Task ContactLink(string contactFieldValue)
        {
            if (contactFieldValue == null) throw new ArgumentNullException(nameof(contactFieldValue));
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_contact_link(id, contactFieldValue, CallbackDispatchers.CompletionInstance);
            return tcs.Task;
        }

        public static Task ContactLinkAuthenticated(string openIdToken)
        {
            if (openIdToken == null) throw new ArgumentNullException(nameof(openIdToken));
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_contact_linkAuthenticated(id, openIdToken, CallbackDispatchers.CompletionInstance);
            return tcs.Task;
        }

        public static Task ContactUnlink()
        {
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_contact_unlink(id, CallbackDispatchers.CompletionInstance);
            return tcs.Task;
        }

        // Event ---------------------------------------------------------------

        /// <summary>Track a custom event. Attributes are string→string per
        /// the underlying <c>CustomEvent</c> contract; pass <c>null</c> for
        /// no attributes.</summary>
        public static Task TrackEvent(string eventName, IReadOnlyDictionary<string, string> attributes = null)
        {
            if (eventName == null) throw new ArgumentNullException(nameof(eventName));
            string attrsJson = null;
            if (attributes != null && attributes.Count > 0)
            {
                var dict = new Dictionary<string, string>(attributes.Count);
                foreach (var kvp in attributes) dict[kvp.Key] = kvp.Value;
                attrsJson = JsonSerializer.Serialize(dict);
            }
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_event_track(id, eventName, attrsJson, CallbackDispatchers.CompletionInstance);
            return tcs.Task;
        }

        // In-app messages -----------------------------------------------------

        public static Task InAppPause()
        {
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_inapp_pause(id, CallbackDispatchers.CompletionInstance);
            return tcs.Task;
        }

        public static Task InAppResume()
        {
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_inapp_resume(id, CallbackDispatchers.CompletionInstance);
            return tcs.Task;
        }

        /// <summary>Synchronous read of the SDK's <c>isPaused</c> property.</summary>
        public static bool InAppIsPaused() => NativeBridge.ec_inapp_isPaused() != 0;

        // Config --------------------------------------------------------------

        public static Task ConfigChangeApplicationCode(string applicationCode)
        {
            if (applicationCode == null) throw new ArgumentNullException(nameof(applicationCode));
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_config_changeApplicationCode(id, applicationCode, CallbackDispatchers.CompletionInstance);
            return tcs.Task;
        }

        public static Task<string> ConfigGetApplicationCode()
            => ReadStringValue(NativeBridge.ec_config_getApplicationCode);

        public static Task<string> ConfigGetApplicationVersion()
            => ReadStringValue(NativeBridge.ec_config_getApplicationVersion);

        public static Task<string> ConfigGetClientId()
            => ReadStringValue(NativeBridge.ec_config_getClientId);

        public static Task<string> ConfigGetSdkVersion()
            => ReadStringValue(NativeBridge.ec_config_getSdkVersion);

        public static Task<string> ConfigGetLanguageCode()
            => ReadStringValue(NativeBridge.ec_config_getLanguageCode);

        public static Task ConfigSetLanguage(string language)
        {
            if (language == null) throw new ArgumentNullException(nameof(language));
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_config_setLanguage(id, language, CallbackDispatchers.CompletionInstance);
            return tcs.Task;
        }

        public static Task ConfigResetLanguage()
        {
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_config_resetLanguage(id, CallbackDispatchers.CompletionInstance);
            return tcs.Task;
        }

        public static async Task<SdkState> ConfigGetCurrentSdkState()
        {
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_config_getCurrentSdkState(id, CallbackDispatchers.CompletionInstance);
            var json = await tcs.Task;
            var envelope = JsonSerializer.Deserialize<SdkStateEnvelope>(json);
            return (SdkState)(envelope?.State ?? 0);
        }

        // Deep link -----------------------------------------------------------

        /// <summary>Forward a URL to the SDK's deep-link handler. Synchronous;
        /// returns <c>true</c> if the SDK consumed it.</summary>
        public static bool DeepLinkTrackUrl(string url)
        {
            if (url == null) throw new ArgumentNullException(nameof(url));
            return NativeBridge.ec_deeplink_trackUrl(url) != 0;
        }

        // Introspection -------------------------------------------------------

        /// <summary>Version of the shim (matches the UPM package version).</summary>
        public static string WrapperVersion
        {
            get
            {
                var ptr = NativeBridge.ec_wrapper_version();
                return NativeUtf8.PtrToString(ptr) ?? "0.0.0-dev";
            }
        }

        // Helpers -------------------------------------------------------------

        private static async Task<string> ReadStringValue(
            Action<int, NativeBridge.CompletionCallback> nativeCall)
        {
            var (id, tcs) = RequestRegistry.Register();
            nativeCall(id, CallbackDispatchers.CompletionInstance);
            var json = await tcs.Task;
            if (string.IsNullOrEmpty(json)) return null;
            var envelope = JsonSerializer.Deserialize<StringValueEnvelope>(json);
            return envelope?.Value;
        }
    }
}
