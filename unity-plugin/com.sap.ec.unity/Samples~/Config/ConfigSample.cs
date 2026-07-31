using EngagementCloud;
using UnityEngine;

/// <summary>Minimal sample: read a few config values on startup.</summary>
public class ConfigSample : MonoBehaviour
{
    private async void Start()
    {
        try
        {
            string appCode = await EngagementCloud.ConfigGetApplicationCode();
            string clientId = await EngagementCloud.ConfigGetClientId();
            string sdkVersion = await EngagementCloud.ConfigGetSdkVersion();
            var state = await EngagementCloud.ConfigGetCurrentSdkState();
            Debug.Log($"[ConfigSample] appCode={appCode} clientId={clientId} sdkVersion={sdkVersion} state={state}");
        }
        catch (EngagementCloudException e)
        {
            Debug.LogError($"[ConfigSample] Read failed ({e.Type}): {e.Message}");
        }
    }
}
