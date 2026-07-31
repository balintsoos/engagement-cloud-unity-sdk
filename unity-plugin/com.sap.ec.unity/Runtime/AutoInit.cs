using UnityEngine;

namespace EngagementCloud
{
    /// <summary>
    /// Optional convenience: if a <see cref="EngagementCloudSettings"/> asset is present in a
    /// Resources folder with the canonical file name <c>EngagementCloudSettings</c> AND the
    /// <c>autoInit</c> flag is on, call <c>EngagementCloud.Setup(...)</c> before the first
    /// scene loads. Games that want explicit control leave <c>autoInit</c> off (or omit the
    /// asset entirely) and call <see cref="EngagementCloud.Setup"/> themselves.
    /// </summary>
    internal static class AutoInit
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        private static async void Boot()
        {
            var settings = Resources.Load<EngagementCloudSettings>("EngagementCloudSettings");
            if (settings == null) return;
            if (!settings.autoInit) return;
            if (string.IsNullOrEmpty(settings.applicationCode))
            {
                Debug.LogWarning("[EngagementCloud] autoInit skipped — applicationCode is empty on the settings asset.");
                return;
            }

            try
            {
                await EngagementCloud.Setup(settings.applicationCode);
                if (!string.IsNullOrEmpty(settings.initialContactValue))
                {
                    await EngagementCloud.LinkContact(settings.initialContactValue);
                }
                Debug.Log($"[EngagementCloud] autoInit succeeded (applicationCode={settings.applicationCode}).");
            }
            catch (EngagementCloudException ex) when (ex is SdkAlreadyEnabledException)
            {
                // Reload / domain-reload path — SDK is already up from the previous session; not an error.
                Debug.Log("[EngagementCloud] autoInit: SDK already enabled (persisted from a previous run).");
            }
            catch (System.Exception ex)
            {
                Debug.LogError($"[EngagementCloud] autoInit failed: {ex.Message}");
            }
        }
    }
}
