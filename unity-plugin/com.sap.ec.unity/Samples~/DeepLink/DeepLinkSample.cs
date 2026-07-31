using EngagementCloud;
using UnityEngine;

/// <summary>Minimal sample: forward a URL to the SDK's deep-link handler.</summary>
public class DeepLinkSample : MonoBehaviour
{
    [SerializeField] private string _url = "https://example.com/promo";

    private void Start()
    {
        bool handled = EngagementCloud.DeepLinkTrackUrl(_url);
        Debug.Log($"[DeepLinkSample] SDK handled URL: {handled}");
    }
}
