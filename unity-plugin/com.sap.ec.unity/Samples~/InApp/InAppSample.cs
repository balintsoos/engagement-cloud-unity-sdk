using EngagementCloud;
using UnityEngine;
using UnityEngine.UI;

/// <summary>Minimal sample: full-screen RawImage that displays in-app
/// messages and dismisses on Sdk.Dismiss event.</summary>
[RequireComponent(typeof(RawImage))]
public class InAppSample : MonoBehaviour
{
    private void Awake()
    {
        // Attach the texture view. It handles the IOSurface → Texture2D
        // plumbing plus pointer forwarding.
        if (GetComponent<UnityInAppTextureView>() == null)
        {
            gameObject.AddComponent<UnityInAppTextureView>();
        }
    }

    private void OnEnable()
    {
        EngagementCloud.EventReceived += OnEvent;
    }

    private void OnDisable()
    {
        EngagementCloud.EventReceived -= OnEvent;
    }

    private void OnEvent(SdkEvent evt)
    {
        // v1 events surface as {Type, Description}; dismiss shows up as
        // "SdkEventInternalSdkDismiss".
        Debug.Log($"[InAppSample] {evt}");
        if (evt.Type.Contains("Dismiss"))
        {
            gameObject.SetActive(false);
        }
    }
}
