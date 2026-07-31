# Phase 1 macOS Port — On-Mac Validation Guide

This guide walks through validating and finishing the Phase-1 macOS port on your Apple-Silicon
Mac. The scaffolding was authored on a Linux sandbox and could not be compiled there, so the
first pass will surface real errors from `kotlinc-native` / `ld64`. Iterate on those before
tackling Section E.

Working directory for every command below: repo root (`engagement-cloud-unity-sdk/`).

---

## 0. Prerequisites (one-time)

- **Xcode 15.4 or newer** installed, Command Line Tools selected:
  ```bash
  xcode-select -p                          # must print a Developer path
  sudo xcode-select --install              # if it doesn't
  sudo xcodebuild -license accept          # accept SDK license
  ```
- **Apple Silicon Mac** (`macosArm64` is the only target we wired — decision #4).
- **JDK 17** on `PATH` (or via SDKMAN). Gradle wrapper handles the rest:
  ```bash
  ./gradlew --version                      # should show JDK 17, Gradle 8.x+
  ```
- No manual Kotlin/Native toolchain install needed — the Kotlin Gradle plugin downloads it on
  first build (~1–2 GB, one-time).

---

## 1. Confirm the target is registered

```bash
./gradlew :engagement-cloud-sdk:tasks --group=build | grep -i macos
```

You should see at least:
- `linkDebugFrameworkMacosArm64`
- `linkReleaseFrameworkMacosArm64`
- `macosArm64MainKlibrary`
- `macosArm64Test`

If none appear, the `isMac` block in `engagement-cloud-sdk/build.gradle.kts` didn't fire — check
`System.getProperty("os.name")` and that Gradle is running under a JDK that reports "Mac OS X".

---

## 2. Compile the source set (expect errors)

```bash
./gradlew :engagement-cloud-sdk:compileKotlinMacosArm64 --console=plain 2>&1 | tee macos-compile.log
```

**What to expect on the first run.** The Linux-authored scaffolding will surface issues in
roughly this order:

1. **Missing `expect` actuals** — anything I missed while enumerating expects in `commonMain`.
   The compiler names the exact declaration; add an `actual` under `src/macosMain/kotlin/` with
   a matching signature. Many can be trivial stubs (return `""`, `Result.success(Unit)`).

2. **Symbol resolution in `MacosInjection`** — commonMain injection modules probably reference
   `InAppViewProviderApi`, `InAppJsBridgeFactory`, and similar in-app types that I did not wire.
   Errors will read like `Could not resolve <FooApi>` at Koin startup, not at compile — so watch
   step 4 (test run) more than this step for those.

3. **API-shape drift** — the internal SDK types I couldn't fully read (`InAppPresenterApi`,
   `DeviceInfoCollectorApi`, `SetupApi`, `ConfigApi`) may have extra members not covered in my
   macOS actuals. Compiler will point at the specific missing override — add it.

4. **UIKit-only imports I missed** — anything under `com.sap.ec.mobileengage.push.*` should be
   OFF the macOS classpath (`macosMain` doesn't `dependsOn(commonComposeMain)` and doesn't
   duplicate any iosMain push files). If a push symbol leaks in, it means something in
   `commonMain` transitively pulls it — track back and fix at the source (usually a top-level
   DI binding).

**Fix loop:** edit the file the compiler names, re-run the same command. Kotlin/Native compiles
are slow (~30–90 s per iteration) — resist the urge to change more than one thing per run.

---

## 3. Link the framework

```bash
./gradlew :engagement-cloud-sdk:linkDebugFrameworkMacosArm64 --console=plain
```

Debug link is faster than Release; use it while iterating. When linking succeeds, the framework
lands at:

```
engagement-cloud-sdk/build/bin/macosArm64/debugFramework/EngagementCloudSDK.framework
```

Sanity checks on that framework:

```bash
FW=engagement-cloud-sdk/build/bin/macosArm64/debugFramework/EngagementCloudSDK.framework
lipo -info "$FW/EngagementCloudSDK"              # should say arm64
otool -L "$FW/EngagementCloudSDK" | head         # dylib deps: Foundation, AppKit, Security, ...
nm -gU "$FW/EngagementCloudSDK" | grep -i EngagementCloud | head   # exported ObjC symbols
```

You should see `_OBJC_CLASS_$_EngagementCloud` (from `@ObjCName("EngagementCloud")`) and
`_OBJC_CLASS_$_EngagementCloudConfig`.

Release link (for shipping):
```bash
./gradlew :engagement-cloud-sdk:linkReleaseFrameworkMacosArm64
```

---

## 4. Run `commonTest` + `macosTest` on macOS

```bash
./gradlew :engagement-cloud-sdk:macosArm64Test --console=plain
```

This runs both `commonTest` and the two smoke tests under `src/macosTest/` (`KotlinPlatform`
returns `MACOS`; `UIDevice` returns non-empty osVersion/deviceModel + `hasOsVersionAtLeast(10)`
is true).

If `commonTest` fails with native-incompatible assumptions (e.g. main-thread expectations that
don't hold on macOS), fix the test rather than the SDK — the SDK behavior is the reference.

---

## 5. Finish Section E — in-app WKWebView presenter

Once steps 2–4 are green, the remaining functional gap is in-app messages. The current
`MacosInAppPresenter` is a no-op stub. To bring it to parity with iOS:

1. **`MacosWebViewFactory`** (`src/macosMain/kotlin/com/sap/ec/mobileengage/inapp/providers/`):
   - Mirror `IosWebViewFactory` but return a `WKWebView` configured with `WKWebViewConfiguration`.
   - Replace `UIColor` with `NSColor`; drop everything that touches `scrollView` /
     `contentInsetAdjustmentBehavior` — macOS `WKWebView` has no `scrollView` (per plan §E).
   - Reuse the existing `InAppJsBridgeFactory` unchanged if possible; if it references UIKit
     types, extract a macOS-safe version.

2. **`MacosInAppViewProvider` + `MacosInAppView`**: mirror the iOS `InAppViewProvider` / `InAppView`.
   The `InAppViewApi` interface is in `commonMain` — implement it for macOS.

3. **`MacosInAppPresenter` (replace the stub)**: host the WKWebView in an `NSWindow` (or
   `NSPanel` styled as an overlay) using AppKit layout constraints. Present / dismiss driven by
   `SdkEvent.Internal.Sdk.Dismiss` from the shared distributor, exactly like `IosInAppPresenter`.

4. **Wire it into `MacosInjection`**: add `single<InAppViewProviderApi> { … }` and update the
   existing `single<InAppPresenterApi>` binding to construct the real presenter.

Every one of these files can be modeled directly on its iOS counterpart in
`src/iosMain/kotlin/com/sap/ec/mobileengage/inapp/`.

---

## 6. Build a minimal macOS sample app (Section G — required for done-bar)

Analog of `iosApp/`. Suggested minimum:

```bash
mkdir -p macosApp
```

Inside, a tiny AppKit app in Swift or Obj-C++ that:
1. Instantiates `EngagementCloudConfig(applicationCode: "…")`.
2. Calls `try await EngagementCloud.setup.enable(config: …, onContactLinkingFailed: …)`.
3. Calls `EngagementCloud.event.track(TrackedEvent(name: "test"))`.
4. Calls `EngagementCloud.contact.link(contactFieldValue: "…")`.
5. Triggers an in-app message and confirms the WKWebView overlay appears (once Section E lands).

Consume the framework by adding it to the sample's Xcode project directly (drag the
`EngagementCloudSDK.framework` bundle from step 3), or wire up SPM (`spmLocalRelease/`) once the
KMMBridge SPM flow is exercised.

---

## 7. Publishing (later)

Local dev is fine with the raw framework. When ready to distribute:
- Set `SPM_BUILD=release` and run the KMMBridge tasks. The existing `kmmbridge` block already
  picks up the macOS framework once the target compiles.
- If publishing to Maven Central / GitHub Packages, `ENABLE_PUBLISHING=true` and the standard
  `publish` tasks — no macOS-specific config was added.

---

## Full "green build" command reference

Once every step above passes:

```bash
# clean compile + link + run tests, in that order
./gradlew :engagement-cloud-sdk:clean
./gradlew :engagement-cloud-sdk:compileKotlinMacosArm64
./gradlew :engagement-cloud-sdk:linkReleaseFrameworkMacosArm64
./gradlew :engagement-cloud-sdk:macosArm64Test
```

Matches the four done-bar items from decision #10 (framework builds + commonTest on macOS +
platform tests + sample-app smoke test — the last one is manual against the built framework).
