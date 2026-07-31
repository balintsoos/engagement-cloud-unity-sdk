# Phase 2 — Unity Plugin on top of the macOS Framework

> Depends on Phase 1 (`Unity-sdk-phase1-plan.md`) landing its macOS framework
> (`EngagementCloudSDK.framework`, `macosArm64`). Phase 1's Section E (AppKit
> `NSWindow` overlay presenter) is **not** on the Phase 2 critical path — Phase 2
> replaces the `InAppPresenterApi` binding with a Unity-specific offscreen
> presenter (see Section E below). Phase 1's overlay presenter stays for
> direct-framework consumers.

## Goal

Deliver a **Unity 6 plugin (UPM package + `.unitypackage`)** that lets a Unity
game running on **Apple Silicon macOS** use the Engagement Cloud SDK, with
in-app messages composited into Unity's own rendering as **`Texture2D`s** rather
than AppKit windows.

## Locked decisions (from interview, 2026-07-31)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Platform coverage | **macOS only** (Apple-Silicon Editor + Standalone Player). iOS/Android deferred |
| 2 | Native plugin format | **`.bundle` shim** built from Obj-C++ `.mm`, links against Phase-1's `EngagementCloudSDK.framework`; both ship in `Plugins/macOS/` |
| 3 | Async model | **Request-id + static callback fn pointer**; C# maps via `TaskCompletionSource` |
| 4 | Data serialization | **Scalars as C scalars; complex types (incl. `SdkEvent` sealed hierarchy) as JSON strings** via `kotlinx.serialization` ↔ `System.Text.Json` |
| 5 | Main-thread dispatch | Auto-instantiated hidden **`MonoBehaviour` pump** drains `ConcurrentQueue<Action>` in `Update()`; all C# continuations resume on Unity's main thread |
| 6 | SdkEvent surface | **`public static event Action<SdkEvent> EventReceived`** with hand-written C# hierarchy mirroring Kotlin sealed type |
| 7 | In-app messages | **Rendered as `Texture2D`s** via WKWebView → CALayer/IOSurface → Unity Metal external texture (zero-copy). Mouse input translated to synthesized `NSEvent`s. No text/keyboard input in v1 |
| 8 | Delivery | **UPM (git URL) primary + `.unitypackage` fallback**, both from a single source folder |
| 9 | Init flow | **`ScriptableObject` settings asset for auto-init** (`RuntimeInitializeOnLoadMethod`) + **static `EngagementCloud.Setup(applicationCode)`** for explicit control |
| 10 | C# root namespace | `EngagementCloud` |
| 11 | Feature scope | Mirror Phase 1 exactly: **setup, contact, event, inApp, config, deepLink, events + registerEventListener**. Push and embedded messaging deferred |
| 12 | Unity version | Min declared: **Unity 6.0 (6000.0)**. Developed/validated against **Unity 6.5 (6000.5.5f1)** |
| 13 | Repo layout | Monorepo, side-by-side modules; single `make unity-package` produces both artifacts |
| 14 | Error handling | **Typed `EngagementCloudException` hierarchy** in C# mirroring Kotlin exceptions; JSON-tagged across the boundary; `TaskCompletionSource.SetException` |
| 15 | Sample project | **Per-feature `Samples~/` entries** (Setup, Contact, Event, In-App, Config, DeepLink) — each a small standalone scene |
| 16 | Logging | Shim installs Kotlin logger sink → static `onLog` callback → `Debug.Log/Warning/Error` on main-thread pump, prefixed `[EngagementCloud]` |

## Architecture

```
┌─ Unity game (C#, IL2CPP or Mono) ───────────────────────────────┐
│  Sap.Ec / EngagementCloud namespace                             │
│  static EngagementCloud.Setup/SetContact/TrackEvent/...         │
│  static event Action<SdkEvent> EventReceived                    │
│  hidden MonoBehaviour pump (ConcurrentQueue<Action> in Update)  │
│  EngagementCloudSettings ScriptableObject (auto-init)           │
│  UnityInAppTextureView : RawImage (external Metal texture)      │
└───────────────────────────────┬─────────────────────────────────┘
                                │ P/Invoke (DllImport("EngagementCloudSDKUnity"))
                                │ request-id + static [MonoPInvokeCallback]
                                ▼
┌─ EngagementCloudSDKUnity.bundle (Obj-C++ shim) ─────────────────┐
│  extern "C" ec_setup / ec_contact_setId / ec_event_track / ...  │
│  extern "C" ec_events_setSink (onEvent callback registration)   │
│  offscreen WKWebView + IOSurface-backed CALayer                 │
│  NSEvent synthesis for mouse input from Unity                   │
│  IOSurface handle → returned to C# for CreateExternalTexture    │
│  Koin binding override: InAppPresenterApi → UnityMacosPresenter │
└───────────────────────────────┬─────────────────────────────────┘
                                │ links against
                                ▼
┌─ EngagementCloudSDK.framework (Phase 1 output) ─────────────────┐
│  Kotlin/Native macosArm64 dynamic framework                     │
│  MacosEngagementCloud + Macos*Api surface                       │
│  SKIE'd for Swift consumers (still used by direct callers)      │
└─────────────────────────────────────────────────────────────────┘
```

## Repo layout

```
engagement-cloud-unity-sdk/                     (this repo)
├── engagement-cloud-sdk/                       (existing KMP module, unchanged by Phase 2)
├── unity-plugin/
│   ├── shim/
│   │   ├── EngagementCloudSDKUnity.xcodeproj/
│   │   ├── src/
│   │   │   ├── EcAsyncBridge.mm                (request-id + callback trampolines)
│   │   │   ├── EcEventsBridge.mm               (Flow<SdkEvent> collector → onEvent)
│   │   │   ├── EcInAppTexturePresenter.mm      (WKWebView + IOSurface presenter)
│   │   │   ├── EcInputRouter.mm                (Unity mouse coords → NSEvent injection)
│   │   │   ├── EcLoggerSink.mm                 (Kotlin logger → onLog callback)
│   │   │   └── EcExceptionMarshaller.mm        (Throwable → tagged JSON)
│   │   └── EngagementCloudSDKUnity-Info.plist  (CFBundlePackageType=BNDL)
│   ├── com.sap.ec.unity/                       (UPM package root)
│   │   ├── package.json                        (min unity: 6000.0)
│   │   ├── Runtime/
│   │   │   ├── EngagementCloud.cs              (static facade)
│   │   │   ├── SdkEvent.cs                     (hierarchy)
│   │   │   ├── EngagementCloudException.cs     (typed hierarchy)
│   │   │   ├── Internal/
│   │   │   │   ├── NativeBridge.cs             (DllImport surface)
│   │   │   │   ├── MainThreadPump.cs           (MonoBehaviour + queue)
│   │   │   │   ├── RequestRegistry.cs          (id → TaskCompletionSource)
│   │   │   │   └── JsonContracts.cs            (System.Text.Json POCOs)
│   │   │   ├── EngagementCloudSettings.cs      (ScriptableObject)
│   │   │   ├── AutoInit.cs                     (RuntimeInitializeOnLoadMethod)
│   │   │   ├── UnityInAppTextureView.cs        (RawImage + input forwarding)
│   │   │   ├── link.xml                        (IL2CPP preservation)
│   │   │   └── EngagementCloud.Runtime.asmdef
│   │   ├── Plugins/macOS/                      (build output lands here)
│   │   │   ├── EngagementCloudSDKUnity.bundle/
│   │   │   └── EngagementCloudSDK.framework/
│   │   ├── Editor/
│   │   │   ├── SettingsInspector.cs
│   │   │   ├── SettingsMenuItem.cs             ("Create → SAP EC → Settings")
│   │   │   └── EngagementCloud.Editor.asmdef
│   │   ├── Samples~/
│   │   │   ├── Setup/
│   │   │   ├── Contact/
│   │   │   ├── Event/
│   │   │   ├── InApp/
│   │   │   ├── Config/
│   │   │   └── DeepLink/
│   │   ├── Tests/
│   │   │   ├── EditMode/                       (JSON round-trip, exception mapping, pump)
│   │   │   └── PlayMode/                       (main-thread dispatch on Update)
│   │   └── CHANGELOG.md
│   ├── UnityProject/                           (dev-time Unity project referencing local package)
│   │   ├── ProjectSettings/ProjectVersion.txt  (6000.5.5f1)
│   │   └── Packages/manifest.json              (file:../com.sap.ec.unity)
│   └── build.gradle.kts                        (orchestrates xcodebuild + copies)
└── Makefile
    ├── unity-shim         → xcodebuild the .bundle
    ├── unity-copy         → copy framework + bundle into com.sap.ec.unity/Plugins/macOS
    ├── unity-package      → tgz the UPM package
    └── unity-unitypackage → Unity CLI -batchmode -exportPackage
```

## Work breakdown

### A. Prerequisites from Phase 1
- Phase 1's `EngagementCloudSDK.framework` links cleanly on `macosArm64`
  (`:engagement-cloud-sdk:linkReleaseFrameworkMacosArm64` succeeds).
- `WrapperInfo` hook accessible from the framework so Phase 2 can set
  `platformWrapper = "unity"` at Setup time.
- `InAppPresenterApi` binding remains overridable via Koin (Phase 2 supplies a
  Unity-specific implementation; Phase 1's AppKit presenter stays for direct
  callers).

### B. Native shim (`unity-plugin/shim/`)
1. Xcode project producing `EngagementCloudSDKUnity.bundle` (Mach-O bundle,
   `CFBundlePackageType=BNDL`, target `macosArm64`, deployment `macOS 11+`).
2. Links against `EngagementCloudSDK.framework` via `@rpath` with
   `LD_RUNPATH_SEARCH_PATHS = @loader_path/../Frameworks @loader_path`.
3. `extern "C"` entry points per Phase 1 API area:
   - `ec_setup(reqId, applicationCodeUtf8, callback)`
   - `ec_contact_setId(reqId, contactFieldId, contactFieldValueUtf8, callback)`
   - `ec_contact_clear(reqId, callback)`
   - `ec_event_track(reqId, eventNameUtf8, eventAttrsJsonUtf8, callback)`
   - `ec_inapp_pause(reqId, callback)` / `ec_inapp_resume(reqId, callback)` / …
   - `ec_config_setContactFieldId(reqId, id, callback)` / …
   - `ec_deeplink_handle(reqId, urlUtf8, callback)`
   - `ec_events_setSink(onEvent)` (single global sink)
   - `ec_logger_setSink(onLog)`
   - `ec_inapp_texture_acquire() -> IOSurfaceRef` (for external texture)
   - `ec_inapp_input_send(kind, x, y, buttons)`
4. Kotlin coroutine invoker: `dispatch_async` onto a shim-owned serial queue that
   runs a `runBlocking` — or, better, uses SKIE's completion-handler bridge if
   applicable to macOS Obj-C exported suspend functions.
5. Exception marshaller: `try/catch(NSException *e)` + Kotlin `Throwable.simpleName`
   → JSON `{ "type": "...", "message": "...", "cause": {...} }`. Emitted via
   `strdup`'d C string; freed after callback returns.
6. Events sink: on setup, shim starts collecting `MacosEngagementCloud.events`;
   for each `SdkEvent`, serialize to JSON (via Kotlin polymorphic serializer),
   invoke the registered `onEvent(jsonPtr)` callback; free after return.
7. Logger sink: register a `LogSink` implementation with the framework; forward
   log lines with `(severity, tag, message)` via `onLog(severity, msgPtr)`;
   free after return.

### C. In-app texture presenter (`EcInAppTexturePresenter.mm`)
1. Offscreen `NSView` with `wantsLayer = YES`, hosting a `WKWebView` sized to
   the layer.
2. Root `CALayer` swapped to an IOSurface-backed layer (`IOSurfaceCreate` with
   BGRA8 + sRGB), redrawn via `renderInContext:` on invalidation (or CADisplayLink
   ticking at Unity's render rate).
3. `ec_inapp_texture_acquire()` returns the `IOSurfaceRef`; C# side wraps it as
   a Metal `MTLTexture` via `MTLDevice.newTextureWithDescriptor:iosurface:plane:`
   and hands the pointer to `Texture2D.CreateExternalTexture`.
4. Coordinate handling: WebKit uses flipped Y; either flip in the presenter's
   `wantsUpdateLayer` path or in the C# `UnityInAppTextureView` shader (UV flip).
   Pre-lock: **flip in C#** — simpler, avoids stepping on WebKit's layout.
5. Alpha: WebKit surfaces are premultiplied; C# `RawImage.material` uses the
   premultiplied shader.
6. Input: `ec_inapp_input_send(kind, x, y, buttons)` where `kind ∈ {Move, Down, Up}`.
   Shim synthesizes an `NSEvent` (`mouseEventWithType:location:...`) and posts to
   the WebView via `-[NSView mouseDown:]` / `mouseUp:` / `mouseMoved:` on the
   main thread (dispatched via `dispatch_async(dispatch_get_main_queue())`).
7. Koin override registered from the shim: `InAppPresenterApi` bound to
   `UnityMacosInAppPresenter` (Kotlin side, referenced by the shim during
   framework init).

### D. C# runtime (`com.sap.ec.unity/Runtime/`)
1. **`NativeBridge.cs`**: all `[DllImport("EngagementCloudSDKUnity")]` extern
   decls, one per shim entry point.
2. **`RequestRegistry.cs`**: `ConcurrentDictionary<int, TaskCompletionSource<string>>`
   keyed by request id (monotonic `Interlocked.Increment`).
3. **`MainThreadPump.cs`**: hidden MonoBehaviour, `ConcurrentQueue<Action>`,
   drained in `Update()`. Instantiated once via
   `[RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]`
   creating a `DontDestroyOnLoad` GameObject.
4. **Static callback dispatchers** (`[MonoPInvokeCallback]`, `static`):
   - `OnCompletionCallback(int reqId, IntPtr resultJsonPtr, IntPtr errorJsonPtr)`
     → copies both strings via `Marshal.PtrToStringUTF8`, enqueues onto pump,
     pump resolves `TaskCompletionSource` (`SetResult(json)` or
     `SetException(BuildException(errorJson))`).
   - `OnEventCallback(IntPtr eventJsonPtr)` → copy, enqueue, pump deserializes
     `SdkEvent` and invokes `EventReceived` multicast.
   - `OnLogCallback(int severity, IntPtr msgPtr)` → copy, enqueue, pump calls
     `Debug.Log/Warning/Error` with `[EngagementCloud] ` prefix.
5. **`EngagementCloud.cs`**: static facade. Each method:
   ```csharp
   public static Task Setup(string applicationCode) {
     var (id, tcs) = RequestRegistry.Register();
     NativeBridge.ec_setup(id, applicationCode, s_onCompletion);
     return tcs.Task;
   }
   ```
6. **`SdkEvent.cs`**: abstract base + subclasses per Kotlin sealed variant.
   `System.Text.Json` polymorphic deserialization keyed on the `type` field
   emitted by kotlinx.serialization.
7. **`EngagementCloudException.cs`**: base + hand-written subclasses for known
   Kotlin exception types (`InvalidApplicationCodeException`,
   `NotConfiguredException`, `NetworkException`, …). Unknown `type` → base.
8. **`EngagementCloudSettings.cs`** (ScriptableObject): `[CreateAssetMenu]`,
   fields `applicationCode`, `logLevel`, `autoInit`.
9. **`AutoInit.cs`**: `[RuntimeInitializeOnLoadMethod(BeforeSceneLoad)]`; loads
   `Resources.Load<EngagementCloudSettings>("EngagementCloudSettings")`; if
   present and `autoInit`, calls `EngagementCloud.Setup(...)`.
10. **`UnityInAppTextureView.cs`**: MonoBehaviour attached to a `RawImage`.
    Acquires the IOSurface via `NativeBridge.ec_inapp_texture_acquire()`,
    calls `Texture2D.CreateExternalTexture(..., IntPtr texturePtr)`, assigns to
    `rawImage.texture`. Forwards `OnPointerDown/Up/Move` events (via
    `IPointerDownHandler` etc.) to `NativeBridge.ec_inapp_input_send(...)`
    after translating coords from RectTransform space to WebView pixel space
    (with UV flip).
11. **`link.xml`**: preserve all `[MonoPInvokeCallback]` static methods and the
    `System.Text.Json` reflection surface for `SdkEvent` polymorphism.

### E. C# editor (`com.sap.ec.unity/Editor/`)
1. `[CustomEditor(typeof(EngagementCloudSettings))]` inspector — plain PropertyDrawer
   for now; no fancy validation in v1.
2. `[MenuItem("Assets/Create/SAP Engagement Cloud/Settings")]` creates a
   settings asset under `Assets/Resources/`.

### F. Build orchestration (Gradle + Makefile)
1. New Gradle module `unity-plugin/build.gradle.kts` declares tasks:
   - `assembleUnityShim` — invokes `xcodebuild -project shim/... -scheme Bundle -sdk macosx -destination "generic/platform=macOS,arch=arm64" -configuration Release build` and locates the produced `.bundle`.
   - `copyUnityNativePlugins` — depends on `:engagement-cloud-sdk:linkReleaseFrameworkMacosArm64` and `assembleUnityShim`; copies both into `com.sap.ec.unity/Plugins/macOS/`.
   - `packUnityUpm` — `tar czf com.sap.ec.unity-<version>.tgz -C com.sap.ec.unity .`.
   - `exportUnityPackage` — runs Unity CLI `-batchmode -exportPackage`; requires Unity 6.5 on the CI worker; skippable locally.
2. `Makefile` top-level:
   - `make unity-package` → runs Gradle `packUnityUpm` then `exportUnityPackage`.
3. C# assembly is compiled *by Unity* on package import — no separate `dotnet build` step for shipping; but a project-level `EngagementCloud.Runtime.csproj` mirroring the `.asmdef` is checked in for IDE tooling and EditMode test discovery.

### G. Tests
1. **EditMode** (`Tests/EditMode/`):
   - `SdkEventJsonRoundTripTests` — every known sealed variant serializes and
     deserializes to the same shape as the Kotlin serializer.
   - `ExceptionMappingTests` — every mapped Kotlin exception type produces the
     right C# subclass; unknown type falls back to base.
   - `MainThreadPumpTests` — action enqueued from a background thread runs on
     the pump thread (verified via `Thread.ManagedThreadId` capture).
   - `TaskCompletionSourceResolutionTests` — simulated callback resolves
     matching `TaskCompletionSource`; concurrent requests don't cross-talk.
2. **PlayMode** (`Tests/PlayMode/`):
   - `AutoInitTest` — with a settings asset present, `EngagementCloud` is
     initialized before the first scene loads.
   - `MainThreadDispatchTest` — a real P/Invoke callback (against a test-only
     `ec_test_ping` shim entry) resolves on Unity's main thread.

### H. Wrapper identification
- At Setup, the shim calls the framework's existing `WrapperInfo` hook with
  `platformWrapper = "unity"` and `platformWrapperVersion = <UPM package version>`
  (read from `package.json`'s `version`, injected via `#define` at build).
- Verified in Phase-2 smoke test by checking the field in outbound HTTP
  requests / server logs.

## Done-bar

1. `make unity-package` produces both `com.sap.ec.unity-<version>.tgz` (UPM
   tarball) and `EngagementCloud-<version>.unitypackage` on a fresh checkout on
   Apple-Silicon macOS.
2. `UnityProject/` opens in Unity 6.5 (6000.5.5f1), compiles under IL2CPP,
   builds a Standalone macOS Apple-Silicon Player.
3. Manual smoke test on real Apple-Silicon Mac: Setup → SetContact → TrackEvent
   → server triggers an in-app message → message renders as a texture inside a
   Unity scene, a click dismisses it, `EventReceived` fires `Dismissed` on the
   main thread.
4. C# EditMode tests green: `SdkEvent` polymorphic JSON round-trip, exception
   mapping table, main-thread pump, `TaskCompletionSource` resolution.
5. IL2CPP `link.xml` preserves P/Invoke callback statics; smoke test also runs
   under an IL2CPP-stripped Standalone build.
6. `WrapperInfo.platformWrapper = "unity"` and `platformWrapperVersion = <pkg version>`
   verified in server logs during the smoke test.

## Open implementation risks (resolve during build)

- **Kotlin/Native + shim linking**: Phase 1's framework is dynamic (`.framework`).
  The shim links against `@rpath/EngagementCloudSDK.framework`, so
  `@rpath = @loader_path/../Frameworks` must be set on the bundle *and* the
  framework must land in `Plugins/macOS/EngagementCloudSDK.framework` — Unity's
  own bundling into the Player may relocate it. Requires a
  `[PostProcessBuildAttribute]` on macOS Player build to fix `@rpath` if Unity
  moves the framework.
- **IOSurface pixel format alignment**: BGRA8-sRGB with premultiplied alpha vs
  Unity's expected format. Coordinate flip. Get this working end-to-end with a
  smoke HTML (`<body style="background:red">`) before anything real.
- **Kotlin coroutine → shim serial queue**: SKIE's completion-handler bridge on
  macOS is less exercised than iOS. May need to fall back to a shim-owned
  `runBlocking` on a background dispatch queue. Verify at Phase 2 kickoff.
- **`Application.RequiresLegacyInputManager` / new Input System**: pointer event
  forwarding must work under both input backends. Design assumes new Input
  System (Unity 6 default); legacy Input Manager fallback is a small addition.
- **Editor vs Player thread model**: Unity Editor's main thread ≠ Player's; the
  pump abstracts this, but PlayMode tests must run through the pump too.

## Explicitly out of scope for Phase 2

- iOS Unity plugin (reuse of the existing iOS XCFramework, Xcode post-build).
- Android Unity plugin (JNI wrapper layer, Gradle template merging).
- Push notifications (also deferred in Phase 1).
- Embedded-messaging API/UI (deferred in Phase 1; texture-composition strategy
  would also apply but it's a much bigger UI surface).
- Text/keyboard input into in-app WebView (form fields, keyboard focus).
- WebView video playback / advanced CSS filters (may or may not survive
  offscreen capture — validate; not a v1 done-bar item).
- Automated end-to-end tests against a live Engagement Cloud instance.
- `.NET Framework` / Mono-only accommodations (Mono works, but IL2CPP is
  the assumed shipping target).
- Intel (`macosX64`) Unity Player support.

## Implementation status (2026-07-31)

Not started. This document captures the design contract; work items above
are ready to be broken into implementation tasks.
