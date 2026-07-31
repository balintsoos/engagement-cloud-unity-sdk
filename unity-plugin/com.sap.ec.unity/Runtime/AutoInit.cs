using UnityEngine;

namespace EngagementCloud
{
    /// <summary>
    /// Automatic initialization from a <see cref="EngagementCloudSettings"/>
    /// asset dropped into <c>Assets/Resources/</c>. Fires on
    /// <c>RuntimeInitializeLoadType.BeforeSceneLoad</c> — before any scene's
    /// <c>Awake</c>/<c>Start</c>. If no settings asset is present, or its
    /// <c>autoInit</c> flag is off, this is a no-op and users can call
    /// <see cref="EngagementCloud.Setup"/> themselves.
    ///
    /// Errors are logged (not rethrown) since scene-load must never fail
    /// because of a missing SDK setup — this is a common-case convenience,
    /// not the sole path.
    /// </summary>
    internal static class AutoInit
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        internal static void Init()
        {
            var settings = Resources.Load<EngagementCloudSettings>(EngagementCloudSettings.ResourcesPath);
            if (settings == null) return;
            if (!settings.AutoInit) return;
            if (string.IsNullOrEmpty(settings.ApplicationCode))
            {
                Debug.LogWarning(
                    "[EngagementCloud] EngagementCloudSettings has autoInit=true but applicationCode is empty. Skipping auto-init.");
                return;
            }
            var task = EngagementCloud.Setup(settings.ApplicationCode);
            // Task continuations resume on Unity's main thread via
            // MainThreadPump (TaskCreationOptions.RunContinuationsAsynchronously
            // + the pump's SetResult site), so a plain ContinueWith here is
            // fine — no explicit SynchronizationContext needed.
            _ = task.ContinueWith(t =>
            {
                if (t.IsFaulted)
                {
                    Debug.LogError($"[EngagementCloud] AutoInit failed: {t.Exception?.GetBaseException().Message}");
                }
                else
                {
                    Debug.Log("[EngagementCloud] AutoInit complete.");
                }
            });
        }
    }
}
