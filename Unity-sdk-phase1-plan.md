# Phase 1 — macOS Native Port of the Engagement Cloud SDK

> Prerequisite for Phase 2 (Unity wrapper). Phase 2 is deliberately **not** designed here —
> its specifics depend on the framework this phase produces, and will get its own interview.

## Goal

Add a native **macOS (`macosArm64`)** target to the Kotlin Multiplatform SDK that produces an
Objective-C **`EngagementCloudSDK.framework`** at functional parity with iOS, minus deferred
features (push, embedded-messaging UI). This framework is the handoff artifact Phase 2 consumes.

## Locked decisions (from interview)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Overall shape | Two phases: macOS port (this) → Unity wrapper (later) |
| 2 | Feature parity | Full, but UI reimplemented in **AppKit** (Compose UI unsupported on K/N macOS) |
| 3 | Source sets | **Standalone `macosMain`** — do not touch working `iosMain` |
| 4 | Architectures | **`macosArm64` only** (Apple Silicon) |
| 5 | Push | **Deferred** (macOS needs NSApplication APNs + signed push entitlement) |
| 6 | UI scope | **In-app messages (WKWebView) only**; embedded-messaging UI **skipped** |
| 7 | Artifact | macOS Obj-C **`.framework`**; C ABI shim + `.bundle` = Phase 2 |
| 8 | Entry point | Parallel **`Macos*`** wrapper classes mirroring `Ios*` |
| 9 | SKIE | **Applied** on macOS too (keep Swift consumers possible) |
| 10 | Done-bar | Framework builds + commonTest on macOS + macOS platform tests + macOS sample smoke test |

## Feasibility summary

- All core deps publish `macosArm64` artifacts: compose-runtime, paging 3.4, lifecycle 2.10,
  ktor 3.4 (darwin), koin 4.1, sqldelight 2.3 (native), cryptography 0.5 (openssl3), okio, datetime.
- Of 73 `iosMain` files, ~58 are non-UIKit (Foundation/CoreFoundation/Security/Network) and port
  cleanly; ~15 touch UIKit/UNUserNotifications and need macOS reimplementation or are skipped.
- **Compose-in-commonMain risk**: `commonMain` has 2 files importing `androidx.compose`
  (`mobileengage/inapp/view/InlineInAppView.kt`, `mobileengage/inapp/presentation/InlineInAppViewRendererApi.kt`)
  plus embedded-messaging view-models using `androidx.paging`. Must be isolated so the macOS
  compilation path does not require Compose **UI**. (Compose *runtime*/state is fine on native.)

## Work breakdown

### A. Build wiring (`engagement-cloud-sdk/build.gradle.kts`)
1. Add `macosArm64()` target inside the `isMac` block, with `binaries.framework { baseName = "EngagementCloudSDK"; isStatic = false }`.
2. Create `macosMain` / `macosTest` source sets. `macosMain.dependsOn(commonMain)` (NOT commonComposeMain).
3. macOS deps mirror the non-UI iosMain set: `ktor-client-darwin`, `cryptography-provider-openssl3`, `sqldelight-native`, coroutines, datetime, koin.
4. Extend SKIE config to cover the macOS framework.
5. Decide framework publication path (local build first; KMMBridge/SPM optional later).

### B. Isolate Compose UI out of the macOS commonMain path
- Move or `expect/actual` the 2 Compose-importing commonMain files so `macosMain` compiles without Compose UI.
- Embedded-messaging UI composables live in `commonComposeMain` (not depended on by macosMain) — fine.
- Embedded-messaging **view-models/paging** in commonMain: keep (paging-common is native-capable) OR exclude if they transitively pull Compose UI — verify during implementation.

### C. Port shareable platform code into `macosMain`
Duplicate (standalone, per decision #3) the non-UIKit iosMain files, adjusting imports where needed:
- Storage: `KeychainStorage` (Security fwk — works on macOS), `NSUserDefaults` string storage.
- Networking watchdog: `NWPathMonitor`/Reachability (Network fwk — works on macOS).
- DB: sqldelight native driver. Crypto: openssl3 provider. DateTime, cache, providers, language.
- DI: `MacosInjection` (Koin module) mirroring `IosInjection` minus push/embedded/UI-not-ported.

### D. Reimplement macOS-specific platform pieces
- `UIDeviceApi` actual: device model + OS version via `NSProcessInfo` / `sysctlbyname` (no UIDevice).
- Platform category / `KotlinPlatform` value for macOS.

### E. In-app messaging (AppKit + WKWebView)
- WebView factory: `WKWebView` on macOS (NSColor instead of UIColor; **no `scrollView`** — drop scrollView tuning, configure via WKWebViewConfiguration).
- Presenter: host webview in an `NSWindow`/`NSView` overlay with AppKit layout constraints; present/dismiss keyed off the same `SdkEvent.Internal.Sdk.Dismiss` flow as iOS.
- Reuse common JS-bridge, content replacer, downloader, metrics unchanged.

### F. Public API surface (`Macos*` wrappers)
- `MacosEngagementCloud` (@ObjCName("EngagementCloud")) singleton exposing: setup, contact, event, inApp, config, deepLink, events flow + registerEventListener.
- `MacosSetupApi/ContactApi/TrackingApi/InAppApi/ConfigApi/DeepLinkApi` mirroring the `Ios*` unwrap-Result→throwing-suspend pattern.
- **Excluded**: push API, embedded-messaging API (deferred/skipped).
- `EngagementCloudConfig` (macOS) mirroring `IosEngagementCloudSDKConfig` (applicationCode).
- Set `platformWrapper` via existing `WrapperInfo` hook to identify the macOS/Unity wrapper.

### G. Validation (all four required)
1. `:engagement-cloud-sdk:linkReleaseFrameworkMacosArm64` (or assemble XCFramework) succeeds.
2. Run `commonTest` on macOS: `macosArm64Test`. Fix any native-incompatible assumptions.
3. Add `macosTest` for the new platform code: device info, keychain, webview factory, in-app presenter, config/setup wrappers.
4. Minimal macOS sample app (analogous to `iosApp`): enable(config), track event, link contact, display an in-app message end-to-end on a real Apple-Silicon Mac.

## Open implementation risks (resolve during build, not blocking design)
- Exact extent of Compose coupling in embedded-messaging view-models pulled by commonMain.
- SKIE behavior/config for a macOS framework (less exercised than iOS).
- macOS main-thread/run-loop assumptions in the in-app presenter vs iOS UIWindow model.
- Whether any `commonMain` code assumes an application lifecycle owner (Android startup / iOS AppDelegate) that macOS lacks.

## Explicitly out of scope for Phase 1
- Push notifications (token API + UNUserNotificationCenter machinery).
- Embedded-messaging native UI (list/detail/category/tabs/theme/paging/shimmer).
- Intel (`macosX64`) / universal binary.
- The Unity C ABI shim, C# bindings, and `.bundle`/UPM packaging — all Phase 2.

## Implementation status (2026-07-31)

Landed in `src/macosMain/`:

- **Build wiring (A)** — `macosArm64()` target + framework binaries added inside the `isMac`
  block; `macosMain` depends on `commonMain` (not `commonComposeMain`); macOS deps mirror the
  non-UI iOS set. `paging-compose` moved from `commonMain` → `commonComposeMain`.
- **Compose isolation (B)** — `LazyPagingItemsExtension.kt` moved to `commonComposeMain`.
  `InlineInAppView` expect stays in `commonMain` (compose-runtime is native-capable); an inert
  actual is provided for macOS.
- **Platform code (C + D)** — non-UIKit ports for storage (Keychain, NSUserDefaults), date/time,
  locale/language, providers (application version, language, page location, platform category,
  input mode), watchdogs (NWPathMonitor connection + NSApplication lifecycle), file cache
  (`NSCachesDirectory`), sqldelight events DAO. UIKit-only pieces reimplemented for macOS:
  `UIDevice` (via `NSProcessInfo` + `sysctlbyname("hw.model")`), `MacosExternalUrlOpener`
  (`NSWorkspace.openURL`), `MacosClipboardHandler` (`NSPasteboard`). Push permission handler and
  notification-settings collection are stubbed inert (push deferred).
- **Public API (F)** — `MacosEngagementCloud` singleton (`@ObjCName("EngagementCloud")`) exposing
  `setup / contact / event / inApp / config / deepLink / events / registerEventListener`.
  Parallel `Macos*Api` interfaces + implementations for setup, contact, tracking, in-app, config,
  deep-link. `MacosEngagementCloudSDKConfig` (`@ObjCName("EngagementCloudConfig")`),
  `MacosSdkConfigStore`, `MacosInjection` (Koin), `SdkKoinIsolationContext.loadPlatformModules`
  actual.
- **Tests (G, partial)** — `macosTest/` scaffolding with a `KotlinPlatform` smoke test and a
  `UIDevice` platform test (osVersion / deviceModel / hasOsVersionAtLeast).

Not landed yet (need iteration on real macOS toolchain):

- **In-app messaging (E)** — `MacosInAppPresenter` is a stub that satisfies `InAppPresenterApi`
  but no-ops at runtime. Still to do: `MacosWebViewFactory` (WKWebView, `NSColor`, no
  `scrollView` — configure via `WKWebViewConfiguration`), `NSWindow`-hosted overlay presenter
  keyed off `SdkEvent.Internal.Sdk.Dismiss`, `MacosInAppViewProvider` + `MacosInApp View`, and
  DI wiring for `InAppViewProviderApi` / `InAppJsBridgeFactory` bindings currently missing from
  `MacosInjection`.
- **Sample macOS app (G)** — no `macosApp` module yet (analog of `iosApp`).
- **Validation (G)** — this workstream was authored on a Linux sandbox without the Xcode
  toolchain, so none of `:engagement-cloud-sdk:linkReleaseFrameworkMacosArm64`,
  `macosArm64Test`, or the smoke test has actually been run. First pass on a Mac will surface
  compile errors around any expect declarations I missed and around the incomplete Section-E DI
  slots — those need iterating on before the framework link succeeds.

Files touched: `build.gradle.kts`, `commonMain/.../KotlinPlatform.kt` (added `MACOS` enum),
40 new files under `macosMain/` and `macosTest/`, one move
(`LazyPagingItemsExtension.kt` → `commonComposeMain`).
