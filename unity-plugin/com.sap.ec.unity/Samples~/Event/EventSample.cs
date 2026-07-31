using System.Collections.Generic;
using System.Threading.Tasks;
using EngagementCloud;
using UnityEngine;

/// <summary>Minimal sample: track a custom event with string attributes.</summary>
public class EventSample : MonoBehaviour
{
    private async void Start()
    {
        // Assumes AutoInit has already fired (settings asset in Resources/).
        try
        {
            await EngagementCloud.TrackEvent("sample_event", new Dictionary<string, string>
            {
                ["source"] = "unity",
                ["scene"] = "EventSample",
            });
            Debug.Log("[EventSample] Event tracked.");
        }
        catch (EngagementCloudException e)
        {
            Debug.LogError($"[EventSample] Track failed ({e.Type}): {e.Message}");
        }
    }
}
