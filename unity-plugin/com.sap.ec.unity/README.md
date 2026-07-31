# SAP Engagement Cloud — Unity Plugin

Unity 6 plugin for the SAP Engagement Cloud SDK on **Apple-Silicon macOS**.

## Install

Unity Package Manager → **Add package from git URL...**

```
https://github.com/emartech/engagement-cloud-unity-sdk.git?path=/unity-plugin/com.sap.ec.unity
```

Or drop a released `.unitypackage` into your project.

## Quick start

1. Right-click in the Project view → **Create → SAP Engagement Cloud → Settings**. Save it under `Assets/Resources/EngagementCloudSettings.asset`.
2. Set the **Application Code** field to your SAP Engagement Cloud application code.
3. Leave **Auto Init** on. That's it — the SDK will initialize before the first scene loads.

Or, opt out of auto-init and call the API directly:

```csharp
using EngagementCloud;

await EngagementCloud.Setup("YOUR_APPLICATION_CODE");
await EngagementCloud.ContactLink("user@example.com");
await EngagementCloud.TrackEvent("purchase", new Dictionary<string, string> {
    ["sku"] = "PROMO-42",
});
```

## In-app messages

Add a full-screen `RawImage` UI element, attach `UnityInAppTextureView` to it, and the SDK will composite in-app messages into it as a `Texture2D`. Pointer clicks are forwarded to the offscreen WebView so buttons in the message respond.

## Platforms

- **Apple-Silicon macOS**: Editor and Standalone Player.
- **Intel macOS, iOS, Android**: not supported in this release.

## Requirements

- Unity 6 (6000.0) or later. Validated on Unity 6.5 (6000.5.5f1).
- macOS 11+ on Apple Silicon.
