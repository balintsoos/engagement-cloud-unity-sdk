---
name: unity-sdk-project
description: Two-phase plan to bring the Engagement Cloud KMP SDK to Unity via a macOS port
metadata: 
  node_type: memory
  type: project
  originSessionId: 3a71ecf7-9823-4d54-949c-8b97e7e65b71
---

Goal: make the Engagement Cloud SDK (Kotlin Multiplatform; today Android AAR + iOS XCFramework + JS/NPM) usable from the Unity game engine. Spec file: `Unity-sdk-spec.md`.

Split into two phases (user decision, 2026-07-31):
- **Phase 1** — add a native **macOS** target to the KMP SDK so it produces a macOS binary at parity with iOS.
- **Phase 2** — build a Unity plugin/wrapper on top of the Phase 1 macOS port.

Phase 1 decisions locked so far:
- **UI**: replace Compose Multiplatform with native **AppKit** on the macOS target (Compose UI is not supported on Kotlin/Native macOS). Two UI subsystems: in-app messages are WKWebView-based (ports easily to macOS WKWebView); embedded messaging is ~19 native composables (large AppKit rebuild).
- **Source sets**: standalone `macosMain` — do NOT refactor/touch the working `iosMain`. (Trade-off: duplicates the ~58 non-UIKit Apple files from iosMain.)
- **Architecture**: Apple Silicon only → `macosArm64` target only.
- **Push**: deferred for Phase 1 (macOS push needs NSApplication APNs registration + signed push entitlement; no UIDevice).
- **UI scope**: in-app messages (WKWebView) only. Embedded messaging UI skipped in Phase 1. Note: `commonMain/.../InlineInAppView.kt` imports androidx.compose → must be isolated behind expect/actual or source-set move so macosMain commonMain compiles without Compose UI.
- **Artifact**: Phase 1 produces a macOS Obj-C **.framework** (standard Kotlin/Native output, mirrors iOS). Unity cannot call Obj-C/Swift directly — the flat C ABI shim (Obj-C++ `.mm` → `extern "C"`) + Unity `.bundle` packaging is a **Phase 2** concern. Keeps phases cleanly separated.
- **Entry point**: parallel `Macos*` wrapper classes (MacosEngagementCloud, MacosSetupApi, MacosContactApi, …) mirroring the `Ios*` ones — unwrap Result→throwing suspend, exposed to Obj-C. macosMain is standalone so it can't reuse Ios* wrappers.
- **SKIE**: apply to the macOS framework too (matching iOS), to keep Swift consumers possible even though the Phase 2 Unity shim is Obj-C++.

Phase 1 porting hotspots (macosMain reimplementations of iosMain platform code):
- `UIDeviceApi` (device model + OS version) — UIDevice is iOS-only → use NSProcessInfo/sysctl on macOS.
- `IosWebViewFactory` — uses UIColor + WKWebView.scrollView + contentInsetAdjustmentBehavior (UIKit). macOS WKWebView has NO scrollView; use NSColor and AppKit-appropriate config.
- In-app presentation (`IosInAppPresenter`, `InAppView`) — UIWindow/rootViewController/NSLayoutConstraint → NSWindow/NSView/AppKit constraints.
- SHAREABLE as-is (Foundation/CoreFoundation/Security/Network): KeychainStorage (Security framework), NWPathMonitor connectivity watchdog, NSUserDefaults storage, ktor-darwin, sqldelight-native, OpenSSL crypto. ~58 of 73 iosMain files are non-UIKit.
- Push files (UNUserNotifications*) — skipped (push deferred).

Key SDK facts:
- Entry points: `com.sap.ec.EngagementCloud` (common, HiddenFromObjC), `IosEngagementCloud` (@ObjCName("EngagementCloud")), `com.sap.ec.android.EngagementCloud`.
- Public API areas: setup, contact, push, event(track), inApp, config, deepLink, embeddedMessaging, plus `events` Flow / registerEventListener.
- Almost all methods are suspend fns returning `Result<Unit>`.
- DI via Koin (SdkKoinIsolationContext). SKIE used for Swift interop on iOS.
- `DeviceInfo` already has `platformWrapper`/`platformWrapperVersion` (WrapperInfo) — the hook a Unity wrapper uses to identify itself.
- Build: `engagement-cloud-sdk/build.gradle.kts` declares iosX64/iosArm64/iosSimulatorArm64 only; uses applyDefaultHierarchyTemplate. Deps (paging 3.4, lifecycle 2.10, ktor 3.4, koin 4.1, sqldelight 2.3, cryptography 0.5) publish macosArm64 artifacts.

Still open: in-app vs embedded-messaging UI scope split, Phase 1 output artifact format, macOS API entry-point exposure, macOS test/sample app, then all of Phase 2.

**Implementation state (2026-07-31)**: Phase 1 scaffolded on Linux sandbox without validation. Landed: build wiring (macosArm64 target, macosMain deps on commonMain not commonComposeMain), Compose isolation (paging-compose moved to commonComposeMain, LazyPagingItemsExtension moved), 40 files under `macosMain/` covering platform code (keychain, NSUserDefaults, NWPathMonitor, sqldelight-native, NSCachesDirectory, NSApplication lifecycle, sysctlbyname UIDevice, NSWorkspace url opener, NSPasteboard clipboard), Macos* API surface (Setup/Contact/Tracking/InApp/Config/DeepLink + MacosEngagementCloud + MacosEngagementCloudSDKConfig), and MacosInjection Koin module. Deferred/stubbed: Section E (WKWebView + NSWindow presenter is a no-op stub), sample app, and any of the missing DI slots (InAppViewProvider, InAppJsBridgeFactory) that will surface only when compiling on the actual Xcode toolchain.
