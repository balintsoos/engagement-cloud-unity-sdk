# SAP Engagement Cloud SDK — Unity plugin (POC)

Unity plugin for the SAP Engagement Cloud mobile SDK. **macOS-only proof-of-concept**
targeting Apple Silicon (`macosArm64`), Unity 6.0+.

This POC is intentionally scoped tight to prove the end-to-end pipeline:

```
Unity C#  ──DllImport──▶  Obj-C++ shim (.bundle)  ──ObjC──▶  EngagementCloudSDK.framework
```

Every API from the Phase-1 macOS surface is wrapped and callable from C#. In-app messages
render via the **framework's default macOS presenter** — a borderless `NSWindow` overlay above
the Unity Player. Texture-based composition (offscreen WKWebView → IOSurface → Unity
external Texture2D) is a follow-up drop; see the "Not in POC scope" section below.

## Layout

```
unity-plugin/
├── shim/                         Obj-C++ Mach-O bundle project
│   ├── src/EngagementCloudSDKUnity.mm   the whole shim, single file
│   └── build.sh                          clang++ → .bundle
├── com.sap.ec.unity/            UPM package root
│   ├── package.json             min unity: 6000.0
│   ├── Runtime/                 C# runtime — DllImports, thread pump, facade, event types
│   ├── Editor/                  menu items + inspectors
│   ├── Plugins/macOS/           built shim + framework land here (via shim/build.sh)
│   └── Samples~/                Setup + Event
└── UnityProject/                dev-time Unity project (points file:../com.sap.ec.unity)
```

## Build

Prereq: **Phase-1 framework built at least once.**

```bash
# From repo root:
./gradlew :engagement-cloud-sdk:linkDebugFrameworkMacosArm64
unity-plugin/shim/build.sh
```

`build.sh` compiles the shim, stages both the shim and `EngagementCloudSDK.framework` into
`com.sap.ec.unity/Plugins/macOS/`, and ad-hoc signs everything so Gatekeeper doesn't block
`dlopen` at runtime.

Verify:

```bash
BIN=unity-plugin/shim/build/EngagementCloudSDKUnity.bundle/Contents/MacOS/EngagementCloudSDKUnity
lipo -info "$BIN"                # arm64
nm -gU    "$BIN" | grep ^_ec_    # 14 entry points, `_ec_*`
otool -L  "$BIN" | grep EngagementCloudSDK
```

## Use from a Unity project

1. Add the UPM package by git URL (or `file:` for local dev):

   ```jsonc
   // Packages/manifest.json
   {
     "dependencies": {
       "com.sap.ec.unity": "file:../unity-plugin/com.sap.ec.unity"
     }
   }
   ```

2. From any script:

   ```csharp
   using EngagementCloud;

   // Subscribe *before* Setup so you catch events fired during enable.
   EngagementCloud.EventReceived += evt => Debug.Log($"event: {evt.Type}");

   await EngagementCloud.Setup("EMSE3-B4341");
   await EngagementCloud.LinkContact("test1@test.com");
   await EngagementCloud.TrackEvent("mysy2");   // triggers the IA1 in-app if the campaign is configured
   ```

3. Or drop `SetupSample.cs` from `Samples~/Setup` onto an empty GameObject and click through
   the buttons at runtime.

### Auto-init via a settings asset (optional)

`Assets → Tools → SAP Engagement Cloud → Create Settings Asset` creates
`Assets/Resources/EngagementCloudSettings.asset`. Populate `applicationCode` (and optionally
`initialContactValue`); the `AutoInit` runtime hook picks it up via
`RuntimeInitializeOnLoadMethod.BeforeSceneLoad` and calls Setup + LinkContact before the
first scene loads.

## API surface

Every call is async on the C# side and safely runs on Unity's main thread on completion via
the hidden `MainThreadPump` MonoBehaviour that `RequestRegistry.Resolve` posts onto.

| C# | Kotlin equivalent | Notes |
|---|---|---|
| `EngagementCloud.Setup(appCode)` | `setup.enable(config, onContactLinkingFailed)` | POC uses a no-op contact-linking-failed callback |
| `EngagementCloud.Disable()` | `setup.disable()` | |
| `EngagementCloud.IsEnabled()` | `setup.isEnabled()` | `Task<bool>` — Kotlin side is a `suspend fun` |
| `EngagementCloud.GetSdkVersion()` | `config.getSdkVersion()` | |
| `EngagementCloud.GetApplicationCode()` | `config.getApplicationCode()` | |
| `EngagementCloud.GetClientId()` | `config.getClientId()` | |
| `EngagementCloud.LinkContact(email)` | `contact.link(contactFieldValue)` | |
| `EngagementCloud.TrackEvent(name, attributesJson?)` | `event.track(CustomEvent(name, attributes))` | attributes is a JSON object of `string→string` |
| `EngagementCloud.PauseInApp()` / `ResumeInApp()` | `inApp.pause() / resume()` | |
| `EngagementCloud.IsInAppPaused` | `inApp.isPaused` | sync — Kotlin property |
| `EngagementCloud.TrackDeepLink(url)` | `deepLink.track(NSUserActivity(webpageURL=url))` | shim wraps the URL as an NSUserActivity |
| `EngagementCloud.EventReceived` | `EngagementCloud.events` | `AppEvent`, `BadgeCountEvent`, `Unknown` |
| `InlineInAppView.Open(viewId, w, h)` | `inApp.fetchInline(viewId)` + offscreen host + snapshot loop | Renders to a Unity `Texture2D` |
| `UnityInAppTextureView` MonoBehaviour | — | `RawImage`-based Unity component that ties `InlineInAppView` + pointer forwarding to a rect in a UGUI canvas |

## Not in POC scope (deferred)

- **Push notifications** — deferred in Phase 1 too (macOS requires NSApplication APNs + a
  signed push entitlement).
- **Embedded messaging UI** — deferred in Phase 1.
- **iOS + Android Unity targets** — Phase 2 scope is macOS-only.
- **IL2CPP smoke test on the Standalone Player** — the shim + C# runtime is IL2CPP-safe by
  construction (`[MonoPInvokeCallback]`, `link.xml`), but a full built Player run is not part
  of the POC verify path.
- **Kotlin logger sink hookup** — `ec_logger_setSink` stores the C# pointer but the SDK does
  not currently expose a public seam to redirect its `ConsoleLogger`. Phase-1 SDK extension
  needed before `Debug.Log` receives Kotlin log lines.
- **Overlay in-app compositing into a Unity `Texture2D`** — the *inline* path (see below) is
  covered. Overlay in-apps still use the framework's default AppKit `NSWindow` presenter and
  pop above the Unity Player. Extending the shim's inline session machinery to also drive an
  overridden `InAppPresenterApi` (via `SdkPlatformOverrides.register(…)`) is a small
  follow-up.

## Inline in-app rendering (offscreen WKWebView → Unity `Texture2D`)

The plugin renders inline in-app messages **inside** the Unity scene as a `Texture2D` you can
put on a `RawImage`, `Renderer.material.mainTexture`, or any other consumer. The pipeline is:

1. C# calls `InlineInAppView.Open(viewId, w, h)`.
2. Shim invokes Kotlin `MacosInAppApi.fetchInline(viewId)` — same code path the macOS sample
   uses, so the JS bridge (`me-close`, `me-trigger-event`, `openExternalLink`, …) is wired
   automatically.
3. Shim hosts the returned `WKWebView` on a **borderless `NSPanel` positioned at screen
   `(-20000, -20000)`** — out of sight but with a real backing store, which WKWebView needs
   to render at all.
4. A ~30 Hz `NSTimer` calls `takeSnapshotWithConfiguration:completionHandler:` (the public,
   stable WebKit snapshot API — works with WebKit's remote layer tree, unlike
   `renderInContext:` which only sees the local proxy layer).
5. Snapshot NSImage is drawn into a heap-allocated **BGRA8, premultiplied, top-left origin**
   buffer of exactly `w * h * 4` bytes. This layout matches Unity's `TextureFormat.BGRA32`
   byte-for-byte — no swizzle, no shader Y-flip.
6. C# polls `ec_inline_lockFrame` in `LateUpdate` and only re-uploads when the shim's
   monotonic `frameVersion` counter advances — idle inline views cost effectively zero.
7. Pointer events from Unity (`OnPointerDown/Up/Move`) go through `ec_inline_sendPointer`
   which synthesises an `NSEvent` and routes it through `-[NSPanel sendEvent:]` — the same
   path an on-screen click would take, so the JS bridge fires exactly like on macOS/iOS.

Drop **`UnityInAppTextureView`** on any GameObject with a `RawImage` and it does all of the
above automatically:

```csharp
var go = new GameObject("MyInAppSlot", typeof(RawImage), typeof(UnityInAppTextureView));
var view = go.GetComponent<UnityInAppTextureView>();
view.viewId = "ia";
view.width  = 512;
view.height = 320;
// That's it — the RawImage's texture is populated on the first snapshot after the fetch
// resolves. Clicks inside the RawImage's rect are forwarded to the offscreen WKWebView.
```

Or use the API directly for finer control:

```csharp
var view = await InlineInAppView.Open("ia", 512, 320);
myRawImage.texture = view.Texture;
// In LateUpdate:
view.Poll();
// On dismount:
view.Dispose();
```

See `UnityProject/Assets/Scripts/SampleAppController.cs` for a full working example.

## Unity sample app (`UnityProject/`)

A full sample project mirroring the macOS AppKit sample (`macosApp/main.swift`) button for
button. Setup / Enable / Disable / Link, IA1–IA7 campaign triggers, in-app pause/resume,
live inline `"ia"` slot, boot state dump, event log — all constructed programmatically in
`SampleAppController.cs` so the repo doesn't ship a Unity-YAML `.unity` scene (fragile to
edit without Unity opening the project first).

To run:

```
# From repo root, ensure the SDK framework + shim are built + staged:
./gradlew :engagement-cloud-sdk:linkDebugFrameworkMacosArm64
unity-plugin/shim/build.sh

# Open unity-plugin/UnityProject/ in Unity 6.0+ (developed against 6000.5.6f1).
# Then, once the Editor is up:
#   Tools → SAP Engagement Cloud → Create Sample Scene
#   File → Save
#   Play  (⌘ P)
```

The editor menu (`Assets/Editor/SampleSceneBootstrap.cs`) programmatically builds
`Assets/Scenes/SampleScene.unity` with a Main Camera + EventSystem + a
`SampleAppController` GameObject. `SampleAppController.Start()` then constructs the full UI
(canvas, buttons, log, inline slot) at runtime.

The sample points at the same `EMSE3-B4341` application code + `test1@test.com` contact used
by the macOS sample and the Android e2e test-app, so the same backend campaigns fire.

## POC verification evidence

The shim is exercised outside Unity via a small .NET smoke test that mirrors the
`NativeBridge`/`NativeCallbacks` bindings. Running it against a fresh shim build produces:

```
config.getSdkVersion      = 4.0.0-LOCAL
setup                     OK (or "already enabled" if persisted)
setup.isEnabled           = True
config.getApplicationCode = EMSE3-B4341
config.getClientId        = <uuid>
contact.link              200 OK → POST /v4/apps/EMSE3-B4341/client/contact
event.track(mysy2)        OK    → POST /v5/apps/EMSE3-B4341/client/events
inApp.isPaused            False → True → False
deepLink.track(sap.com)   matched=True (routed to SDK; 403 from backend RBAC is expected)
```

The full DllImport surface (14 `_ec_*` symbols) is verified with
`nm -gU $BIN | grep ^_ec_` and matches `Runtime/Internal/NativeBridge.cs` one-for-one.
