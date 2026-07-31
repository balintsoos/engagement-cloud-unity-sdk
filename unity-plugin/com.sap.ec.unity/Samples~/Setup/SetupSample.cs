using System.Threading.Tasks;
using EngagementCloud;
using UnityEngine;

/// <summary>
/// Minimal sample: explicit `EngagementCloud.Setup(applicationCode)` from
/// user code (auto-init disabled in the sample scene's settings asset).
/// </summary>
public class SetupSample : MonoBehaviour
{
    [Tooltip("Application code issued by SAP Engagement Cloud.")]
    [SerializeField] private string _applicationCode = "REPLACE_ME";

    private async void Start()
    {
        try
        {
            await EngagementCloud.Setup(_applicationCode);
            Debug.Log($"[SetupSample] SDK ready. Wrapper version: {EngagementCloud.WrapperVersion}");
        }
        catch (EngagementCloudException e)
        {
            Debug.LogError($"[SetupSample] Setup failed ({e.Type}): {e.Message}");
        }
    }
}
