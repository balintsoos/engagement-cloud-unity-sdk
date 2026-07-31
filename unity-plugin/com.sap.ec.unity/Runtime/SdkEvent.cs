using System;

namespace EngagementCloud
{
    /// <summary>
    /// Base type of the event stream emitted by the native SDK. Subclasses
    /// mirror the Kotlin sealed <c>EngagementCloudEvent</c> hierarchy that
    /// crosses the boundary as JSON.
    ///
    /// v1 wire shape (see <c>ec_encode_engagement_event</c> in the shim):
    ///   { "type": "<Kotlin class name>", "description": "..." }
    /// Richer per-variant serialization is a future task (phase-2 plan
    /// Section B follow-up). Consumers that need typed fields today should
    /// read <see cref="Type"/> and <see cref="Description"/>.
    /// </summary>
    public class SdkEvent
    {
        /// <summary>The Kotlin class name (ECSDK prefix stripped), e.g.
        /// <c>SdkEventInternalSdkDismiss</c>, <c>SdkEventExternalCustom</c>.</summary>
        public string Type { get; }

        /// <summary>The Kotlin object's <c>toString()</c> — a best-effort
        /// human-readable form. Contents are unstable and subject to change.</summary>
        public string Description { get; }

        public SdkEvent(string type, string description)
        {
            Type = type ?? "UnknownEvent";
            Description = description ?? string.Empty;
        }

        public override string ToString() => $"SdkEvent({Type}): {Description}";
    }
}
