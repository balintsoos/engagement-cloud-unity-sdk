using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace EngagementCloud
{
    /// <summary>
    /// C# mirror of the Kotlin <c>EngagementCloudEvent</c> sealed hierarchy exposed via
    /// <c>EngagementCloud.events</c> (public flow) on the Kotlin side. The shim serialises
    /// events with <c>kotlinx.serialization</c> using a discriminator field named
    /// <c>type</c> whose value is the Kotlin subclass simple name; we dispatch on that tag
    /// here.
    ///
    /// Unknown / future event types are surfaced as <see cref="SdkEvent.Unknown"/> — the SDK
    /// contract says clients must tolerate additions.
    /// </summary>
    public abstract class SdkEvent
    {
        /// <summary>Wall-clock milliseconds when the SDK emitted the event.</summary>
        public long Timestamp { get; internal set; }

        /// <summary>Original tag from the Kotlin side (e.g. <c>"AppEvent"</c>, <c>"BadgeCountEvent"</c>).</summary>
        public string Type { get; internal set; }

        /// <summary>Custom app-level event fired from an in-app message's <c>me-trigger-app-event</c> action.</summary>
        public sealed class AppEvent : SdkEvent
        {
            public string Name { get; internal set; }
            /// <summary>JSON payload attached to the app event, or <c>null</c> if none.</summary>
            public string PayloadJson { get; internal set; }
        }

        /// <summary>Badge count update — value is what the app should display on its icon.</summary>
        public sealed class BadgeCountEvent : SdkEvent
        {
            public int BadgeCount { get; internal set; }
            /// <summary>Delta / set / clear method; string mirror of the Kotlin enum.</summary>
            public string Method { get; internal set; }
        }

        /// <summary>Any event tag the shim can't map. Callers may still inspect the raw JSON.</summary>
        public sealed class Unknown : SdkEvent
        {
            /// <summary>The full raw JSON payload as-received (post-Kotlin serialisation).</summary>
            public string RawJson { get; internal set; }
        }

        internal static SdkEvent FromJson(string json)
        {
            if (string.IsNullOrEmpty(json)) return null;
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            // kotlinx.serialization writes the class discriminator as "type" by default (the
            // shim confirms this in the Koin `SerializersModule`). Anything else falls through
            // to Unknown so unrecognized events don't blow up.
            string type = root.TryGetProperty("type", out var t) ? t.GetString() : null;

            long timestamp = 0;
            if (root.TryGetProperty("timestamp", out var ts) && ts.ValueKind == JsonValueKind.Number)
            {
                timestamp = ts.GetInt64();
            }

            switch (type)
            {
                case "AppEvent":
                {
                    string name = root.TryGetProperty("name", out var n) ? n.GetString() : null;
                    string payload = null;
                    if (root.TryGetProperty("payload", out var p) && p.ValueKind != JsonValueKind.Null)
                    {
                        payload = p.GetRawText();
                    }
                    return new AppEvent { Type = type, Timestamp = timestamp, Name = name, PayloadJson = payload };
                }
                case "BadgeCountEvent":
                {
                    int count = root.TryGetProperty("badgeCount", out var c) && c.ValueKind == JsonValueKind.Number ? c.GetInt32() : 0;
                    string method = root.TryGetProperty("method", out var m) ? m.GetString() : null;
                    return new BadgeCountEvent { Type = type, Timestamp = timestamp, BadgeCount = count, Method = method };
                }
                default:
                    return new Unknown { Type = type ?? "<untagged>", Timestamp = timestamp, RawJson = json };
            }
        }
    }
}
