using System;
using System.Text.Json;

namespace EngagementCloud
{
    /// <summary>
    /// Base class for every failure the shim surfaces from the Kotlin side. The shim serialises
    /// mapped Kotlin exception types as a tagged JSON object:
    /// <code>
    ///   { "type": "InvalidApplicationCodeException", "message": "...", "cause": { … } }
    /// </code>
    /// The <c>type</c> discriminator drives the concrete subclass we throw here. Kotlin
    /// exceptions we haven't listed below fall back to the base class with the original type
    /// tag in <see cref="KotlinType"/> so callers can still branch on it.
    /// </summary>
    public class EngagementCloudException : Exception
    {
        /// <summary>Kotlin-side simple class name (e.g. <c>"InvalidApplicationCodeException"</c>).</summary>
        public string KotlinType { get; }

        internal EngagementCloudException(string kotlinType, string message, Exception inner = null)
            : base(message, inner)
        {
            KotlinType = kotlinType;
        }

        /// <summary>
        /// Decode a shim error payload into a typed exception. Never throws — malformed JSON is
        /// swallowed into a generic <see cref="EngagementCloudException"/> so the caller's
        /// <c>await</c> still fails deterministically instead of throwing a JSON parse error.
        /// </summary>
        public static EngagementCloudException FromJson(string json)
        {
            if (string.IsNullOrEmpty(json))
            {
                return new EngagementCloudException("Unknown", "empty error payload");
            }
            try
            {
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;
                string type    = root.TryGetProperty("type",    out var t) ? t.GetString() : "Unknown";
                string message = root.TryGetProperty("message", out var m) ? m.GetString() : type;
                Exception cause = null;
                if (root.TryGetProperty("cause", out var c) && c.ValueKind != JsonValueKind.Null)
                {
                    cause = FromJson(c.GetRawText());
                }

                switch (type)
                {
                    case "InvalidApplicationCodeException":  return new InvalidApplicationCodeException(message, cause);
                    case "SdkAlreadyEnabledException":       return new SdkAlreadyEnabledException(message, cause);
                    case "SdkAlreadyDisabledException":      return new SdkAlreadyDisabledException(message, cause);
                    case "MissingApplicationCodeException":  return new MissingApplicationCodeException(message, cause);
                    case "NetworkIOException":               return new NetworkException(type, message, cause);
                    case "FailedRequestException":           return new NetworkException(type, message, cause);
                    case "PreconditionFailedException":      return new PreconditionFailedException(message, cause);
                    case "RetryLimitReachedException":       return new NetworkException(type, message, cause);
                    case "CoroutineException":               return new EngagementCloudException(type, message, cause);
                    default:                                 return new EngagementCloudException(type, message, cause);
                }
            }
            catch (JsonException ex)
            {
                return new EngagementCloudException("Unknown", $"malformed error payload: {ex.Message}\nraw: {json}");
            }
        }
    }

    /// <summary>Application code did not pass server-side validation.</summary>
    public sealed class InvalidApplicationCodeException : EngagementCloudException
    {
        internal InvalidApplicationCodeException(string message, Exception inner)
            : base("InvalidApplicationCodeException", message, inner) { }
    }

    /// <summary><c>Setup</c> called twice without an intervening <c>Disable</c>.</summary>
    public sealed class SdkAlreadyEnabledException : EngagementCloudException
    {
        internal SdkAlreadyEnabledException(string message, Exception inner)
            : base("SdkAlreadyEnabledException", message, inner) { }
    }

    /// <summary><c>Disable</c> called when the SDK is not currently enabled.</summary>
    public sealed class SdkAlreadyDisabledException : EngagementCloudException
    {
        internal SdkAlreadyDisabledException(string message, Exception inner)
            : base("SdkAlreadyDisabledException", message, inner) { }
    }

    /// <summary>Called an API that needs an application code before <c>Setup</c>.</summary>
    public sealed class MissingApplicationCodeException : EngagementCloudException
    {
        internal MissingApplicationCodeException(string message, Exception inner)
            : base("MissingApplicationCodeException", message, inner) { }
    }

    /// <summary>Umbrella for network-layer failures — I/O, non-2xx responses, retry limits.</summary>
    public sealed class NetworkException : EngagementCloudException
    {
        internal NetworkException(string kotlinType, string message, Exception inner)
            : base(kotlinType, message, inner) { }
    }

    /// <summary>Backend responded 412 — the SDK state doesn't match server expectations.</summary>
    public sealed class PreconditionFailedException : EngagementCloudException
    {
        internal PreconditionFailedException(string message, Exception inner)
            : base("PreconditionFailedException", message, inner) { }
    }
}
