using System.Text.Json.Serialization;

namespace EngagementCloud.Internal
{
    /// <summary>
    /// Wire shape for the shim's error callback payload. Matches
    /// <c>ec_dispatch_error</c> / <c>ec_dispatch_kotlin_error</c> in
    /// <c>unity-plugin/shim/src/EngagementCloudSDKUnity.mm</c>:
    ///   { "type": "<Kotlin class name>", "message": "<localized>" }
    /// </summary>
    internal sealed class ErrorEnvelope
    {
        [JsonPropertyName("type")]
        public string Type { get; set; }

        [JsonPropertyName("message")]
        public string Message { get; set; }
    }

    /// <summary>Wire shape for <c>{"value": "..."}</c> result payloads.</summary>
    internal sealed class StringValueEnvelope
    {
        [JsonPropertyName("value")]
        public string Value { get; set; }
    }

    /// <summary>Wire shape for <c>{"state": &lt;int&gt;}</c> (SdkState).</summary>
    internal sealed class SdkStateEnvelope
    {
        [JsonPropertyName("state")]
        public int State { get; set; }
    }

    /// <summary>Wire shape for the shim's event callback payload.
    /// v1 emits <c>{"type": "&lt;ECSDK-stripped class name&gt;", "description": "..."}</c>;
    /// richer per-variant JSON is a follow-up (see phase-2 plan Section B).</summary>
    internal sealed class EventEnvelope
    {
        [JsonPropertyName("type")]
        public string Type { get; set; }

        [JsonPropertyName("description")]
        public string Description { get; set; }
    }
}
