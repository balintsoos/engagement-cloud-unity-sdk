# Phase 1 macOS Port — Session Handoff

Updated 2026-07-31. Read this first if you're picking up the port.

Companion docs (do not duplicate; read them for background):
- `Unity-sdk-spec.md` — original two-phase spec (macOS port → Unity wrapper).
- `Unity-sdk-phase1-plan.md` — Phase-1 design + decision log.
- `Unity-sdk-phase1-mac-run.md` — the on-Mac validation guide the session was executing.
- `.claude-memory/unity-sdk-project.md` — project memory: decisions locked and hotspots.

---

## TL;DR — where the port stands

| Section (from `Unity-sdk-phase1-mac-run.md`) | Status |
|---|---|
| 0. Prerequisites (JDK 17, Xcode) | **Done.** |
| 1. Target registered | **Done.** |
| 2. `compileKotlinMacosArm64` | **Done — BUILD SUCCESSFUL.** Two fixes applied (below). |
| 3. `linkDebugFrameworkMacosArm64` | **Done — BUILD SUCCESSFUL.** Framework linked, sanity checks green. |
| 4. `macosArm64Test` | **Done — 766/767 passed, 1 skipped, 0 failures.** |
| 5. Real WKWebView + NSWindow in-app presenter | **Not started.** Current `MacosInAppPresenter` is a no-op stub. |
| 6. macOS sample app | Not started. |
| 7. Publishing (KMMBridge / Maven) | Not started. |

**Phase-1 core done-bar has been met on the Linux-authored scaffolding** — the port compiles,
links to an arm64 macOS `.framework`, and passes the entire commonTest + macosTest suite on
real macOS without any further changes beyond the two fixes in this document.

Next agent's job: pick between (a) implementing §5 (real in-app presenter) or (b) §6 (sample
app) — the plan lists both as required for the done-bar. Ask the user which they want first.

---

## Environment already set up

- **JDK 17** installed via Homebrew (`openjdk@17` 17.0.20), symlinked into
  `/Library/Java/JavaVirtualMachines/openjdk-17.jdk`. `/usr/libexec/java_home -v 17` returns
  the right path.
- **JAVA_HOME is NOT exported in the shell profile.** Every Gradle command in this session
  prefixed `export JAVA_HOME=$(/usr/libexec/java_home -v 17) && ...`. Keep doing that, or ask
  the user to add it to `~/.zshrc` (do not attempt to write to `~/.zshrc` yourself).
- **Xcode 26.6** installed at `/Applications/Xcode.app`, active developer dir already points
  at it, license accepted. `xcrun xcodebuild -version` prints `Xcode 26.6` cleanly.
- **Kotlin/Native toolchain** downloaded to
  `~/.konan/kotlin-native-prebuilt-macos-aarch64-2.3.10/` (LLVM 19, libffi 3.3, lldb 4).
  One-time ~1–2 GB download, already done.
- **Gradle 9.4.1**, **Kotlin 2.3.0**. Machine: Apple Silicon, Darwin 25/26 kernel (Mac OS X
  26.5.2 reported to Gradle).

---

## Fixes already applied to unblock §2 compile

The Linux-authored scaffolding produced 5 compile errors on the first `compileKotlinMacosArm64`.
Both files below are already patched — do not re-fix. Listed here so a reviewer understands
the state and can revisit trade-offs if needed.

### 1. `engagement-cloud-sdk/src/macosMain/kotlin/com/sap/ec/core/device/UIDevice.kt`

**Was:** used `platform.posix.sysctlbyname` (not present in Kotlin/Native's macos_arm64 posix
klib) and dereferenced `NSOperatingSystemVersion` as a struct (it comes back from Kotlin/Native
as `CValue<NSOperatingSystemVersion>` and needs `.useContents { … }`).

**Now:** trimmed to Foundation-only. `deviceModel()` returns the literal `"Mac"` — parity
trade-off; iOS returns `UIDevice.currentDevice.model` which is a similarly generic string.
If richer telemetry is needed later (`"MacBookPro18,3"`), the right paths are:
- Add a Kotlin/Native cinterop def for `sys/sysctl.h` in `engagement-cloud-sdk/build.gradle.kts`
  under the `macosArm64` target.
- Or bridge through IOKit's `IORegistry` — heavier.

### 2. `engagement-cloud-sdk/src/commonMain/kotlin/com/sap/ec/core/crypto/Crypto.kt`

**Was:** `when (currentPlatform)` handled JS / Android / IOS. Missing MACOS made the `when`
non-exhaustive.

**Now:** added a `KotlinPlatform.MACOS -> { ECDSA.SignatureFormat.DER to Base64.decode(...) }`
branch mirroring the IOS branch (macOS Kotlin/Native uses the same DER-formatted ECDSA output).

---

## Verified §3 framework output

`engagement-cloud-sdk/build/bin/macosArm64/debugFramework/EngagementCloudSDK.framework`:
- `lipo -info` → `arm64` (single-arch, correct for macosArm64-only target).
- `otool -L` → Foundation + libSystem + libc++ + libobjc + libsqlite3 + libz + libncurses + libbz2.
  No UIKit, no AppKit yet (AppKit will appear once §5 lands).
- `nm -gU | grep OBJC_CLASS.*EngagementCloud` → exports `ECSDKEngagementCloud`,
  `ECSDKEngagementCloudConfig`, `ECSDKEngagementCloudEvent`, etc. (The `ECSDK` prefix is the
  configured framework class prefix — this is the SKIE/framework standard, not a rename bug.)

Warnings from §3 that are informational only:
- `Opt-in requirement marker com.sap.ec.InternalSdkApi is unresolved` — SKIE-related,
  benign; internal APIs are still callable from within the module.
- `Cannot infer a bundle ID from packages of source files ...` — Kotlin/Native suggests
  `-Xbinary=bundleId=<id>`. Not required for local dev; wire it in when publishing (§7).
- `Ktor_httpHttpStatusCode.description` renamed to `description_` due to SKIE name collision.
  Consumers use Kotlin API; the renamed Swift symbol is only surfaced to Swift-consumers of
  the framework.

---

## §4 test summary

- 133 JUnit-XML test suite files under `engagement-cloud-sdk/build/test-results/macosArm64Test/`.
- Totals: **767 tests, 766 passed, 1 skipped, 0 failures, 0 errors.**
- The one skipped test is not tracked yet — grep the XML for `skipped="1"` if you need to
  identify it, but it did not affect the pass verdict.

---

## What's next — §5, §6, §7

### §5 — Real in-app WKWebView + NSWindow presenter (`Unity-sdk-phase1-mac-run.md` §5)

Current `MacosInAppPresenter` is a no-op stub. Files to add (all under
`engagement-cloud-sdk/src/macosMain/kotlin/`), modeled directly on their iOS counterparts
in `engagement-cloud-sdk/src/iosMain/kotlin/com/sap/ec/mobileengage/inapp/`:

1. **`MacosWebViewFactory`** (`.../mobileengage/inapp/providers/`) — mirror `IosWebViewFactory`,
   returning a `WKWebView` with `WKWebViewConfiguration`. Two mandatory drops:
   - macOS `WKWebView` has **no** `scrollView` / `contentInsetAdjustmentBehavior`.
   - `UIColor` → `NSColor` (from AppKit).
2. **`MacosInAppViewProvider` + `MacosInAppView`** — implement the commonMain `InAppViewApi`.
3. **`MacosInAppPresenter`** — host the WKWebView in an `NSWindow` (or overlay-styled `NSPanel`),
   present/dismiss driven by `SdkEvent.Internal.Sdk.Dismiss`. Replace the stub binding in
   `MacosInjection` — add `single<InAppViewProviderApi> { … }` and update `single<InAppPresenterApi>`.

If `InAppJsBridgeFactory` references UIKit types, extract a macOS-safe version — do NOT
`dependsOn(commonComposeMain)` from `macosMain`.

### §6 — Minimal macOS sample app (`Unity-sdk-phase1-mac-run.md` §6)

Analog of `iosApp/`. Suggested layout: `macosApp/` with a tiny AppKit app (Swift or Obj-C++) that:
1. Instantiates `EngagementCloudConfig(applicationCode: "…")`.
2. Calls `EngagementCloud.setup.enable(config:, onContactLinkingFailed:)`.
3. Calls `EngagementCloud.event.track(TrackedEvent(name: "test"))`.
4. Calls `EngagementCloud.contact.link(contactFieldValue: "…")`.
5. Triggers an in-app message and confirms the WKWebView overlay appears (once §5 lands).

Consume the framework by dragging `EngagementCloudSDK.framework` from the debug build directly
into the sample's Xcode project. SPM wiring (via `spmLocalRelease/` and KMMBridge) is a later
concern tied to §7.

### §7 — Publishing

Set `SPM_BUILD=release` and run KMMBridge tasks. The existing `kmmbridge` block already picks
up the macOS framework now that the target compiles. For Maven Central / GitHub Packages,
`ENABLE_PUBLISHING=true` and standard `publish` tasks — no macOS-specific config added.

---

## Repo state at handoff

Branch: `main`. Files changed by this session:

- **Modified (uncommitted):**
  - `engagement-cloud-sdk/src/commonMain/kotlin/com/sap/ec/core/crypto/Crypto.kt`
  - `engagement-cloud-sdk/src/macosMain/kotlin/com/sap/ec/core/device/UIDevice.kt`
- **New (uncommitted, safe to delete if noisy):**
  - `macos-compile.log`, `macos-link.log`, `macos-test.log` at repo root — verbose build logs.
  - `Unity-sdk-phase1-handoff.md` — this file.

Nothing committed, nothing pushed, no branches created. Pre-existing pending state (already
there when the session started, not from this session): `.gitmodules`, `Makefile`,
`engagement-cloud-sdk-docs` submodule, most of `engagement-cloud-sdk/src/macosMain/` and
`macosTest/`, and the three `Unity-sdk-*.md` docs — that's the Linux-authored scaffolding.

Consider `git add -p` on `Crypto.kt` and `UIDevice.kt` alongside the scaffolding when the
user is ready to commit.

---

## Running list of fixes (append as you go)

- 2026-07-31 — `Crypto.kt`: added `KotlinPlatform.MACOS` branch to `verify()`'s `when`.
- 2026-07-31 — `UIDevice.kt`: dropped `sysctlbyname`; `deviceModel()` returns `"Mac"`;
  `osVersion()` uses `.useContents { }` on the `CValue<NSOperatingSystemVersion>`.
- 2026-07-31 — Xcode.app installed by user; §3 linked, §4 tests 766/767 passed. No SDK code
  changes needed beyond the two above.
- (Add next fix here.)
