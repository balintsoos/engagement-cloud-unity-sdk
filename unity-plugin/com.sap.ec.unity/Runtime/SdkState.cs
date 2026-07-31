namespace EngagementCloud
{
    /// <summary>
    /// Current lifecycle state of the SDK. Returned by
    /// <c>EngagementCloud.ConfigGetCurrentSdkState()</c>.
    /// </summary>
    public enum SdkState
    {
        Uninitialized = 0,
        Initialized = 1,
        Active = 2,
        OnHold = 3,
    }
}
