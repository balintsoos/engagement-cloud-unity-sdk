using System;

namespace EngagementCloud
{
    /// <summary>
    /// Base type for all exceptions raised by the SDK bridge.
    ///
    /// Native errors travel across the boundary as JSON envelopes of the shape
    /// <c>{"type": "&lt;name&gt;", "message": "..."}</c>. The C# side maps the
    /// <c>type</c> field to one of the concrete subclasses below; unknown
    /// types surface as the base <see cref="EngagementCloudException"/> with
    /// <see cref="Type"/> set to the raw type string.
    /// </summary>
    public class EngagementCloudException : Exception
    {
        /// <summary>The Kotlin/native exception class name that produced this
        /// error, e.g. <c>SdkExceptionInvalidApplicationCodeException</c>.</summary>
        public string Type { get; }

        public EngagementCloudException(string type, string message) : base(message)
        {
            Type = type;
        }

        internal static EngagementCloudException FromEnvelope(string type, string message)
        {
            switch (type)
            {
                case "SdkExceptionInvalidApplicationCodeException":
                case "InvalidApplicationCodeException":
                    return new InvalidApplicationCodeException(message);
                case "SdkExceptionMissingApplicationCodeException":
                case "MissingApplicationCodeException":
                    return new MissingApplicationCodeException(message);
                case "SdkExceptionSdkAlreadyEnabledException":
                case "SdkAlreadyEnabledException":
                    return new SdkAlreadyEnabledException(message);
                case "SdkExceptionSdkAlreadyDisabledException":
                case "SdkAlreadyDisabledException":
                    return new SdkAlreadyDisabledException(message);
                case "SdkExceptionNetworkIOException":
                case "NetworkIOException":
                    return new NetworkIOException(message);
                case "SdkExceptionFailedRequestException":
                case "FailedRequestException":
                    return new FailedRequestException(message);
                case "SdkExceptionPreconditionFailedException":
                case "PreconditionFailedException":
                    return new PreconditionFailedException(message);
                case "SdkExceptionRetryLimitReachedException":
                case "RetryLimitReachedException":
                    return new RetryLimitReachedException(message);
                case "SdkExceptionDecryptionFailedException":
                case "DecryptionFailedException":
                    return new DecryptionFailedException(message);
                case "SdkExceptionCoroutineException":
                case "CoroutineException":
                    return new CoroutineException(message);
                case "IllegalArgumentException":
                case "KotlinIllegalArgumentException":
                    return new IllegalArgumentException(message);
                case "NotImplementedException":
                    return new NotImplementedException(message);
                default:
                    return new EngagementCloudException(type ?? "UnknownException", message);
            }
        }
    }

    public sealed class InvalidApplicationCodeException : EngagementCloudException
    { public InvalidApplicationCodeException(string message) : base(nameof(InvalidApplicationCodeException), message) { } }

    public sealed class MissingApplicationCodeException : EngagementCloudException
    { public MissingApplicationCodeException(string message) : base(nameof(MissingApplicationCodeException), message) { } }

    public sealed class SdkAlreadyEnabledException : EngagementCloudException
    { public SdkAlreadyEnabledException(string message) : base(nameof(SdkAlreadyEnabledException), message) { } }

    public sealed class SdkAlreadyDisabledException : EngagementCloudException
    { public SdkAlreadyDisabledException(string message) : base(nameof(SdkAlreadyDisabledException), message) { } }

    public sealed class NetworkIOException : EngagementCloudException
    { public NetworkIOException(string message) : base(nameof(NetworkIOException), message) { } }

    public sealed class FailedRequestException : EngagementCloudException
    { public FailedRequestException(string message) : base(nameof(FailedRequestException), message) { } }

    public sealed class PreconditionFailedException : EngagementCloudException
    { public PreconditionFailedException(string message) : base(nameof(PreconditionFailedException), message) { } }

    public sealed class RetryLimitReachedException : EngagementCloudException
    { public RetryLimitReachedException(string message) : base(nameof(RetryLimitReachedException), message) { } }

    public sealed class DecryptionFailedException : EngagementCloudException
    { public DecryptionFailedException(string message) : base(nameof(DecryptionFailedException), message) { } }

    public sealed class CoroutineException : EngagementCloudException
    { public CoroutineException(string message) : base(nameof(CoroutineException), message) { } }

    public sealed class IllegalArgumentException : EngagementCloudException
    { public IllegalArgumentException(string message) : base(nameof(IllegalArgumentException), message) { } }

    public sealed class NotImplementedException : EngagementCloudException
    { public NotImplementedException(string message) : base(nameof(NotImplementedException), message) { } }
}
