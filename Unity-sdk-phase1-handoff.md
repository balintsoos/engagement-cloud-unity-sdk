# Phase 1 macOS Port — Session Handoff

Written 2026-07-31 at the end of a session that began executing `Unity-sdk-phase1-mac-run.md`.
Read this first if you're picking up the port after the current session ended.

Companion docs (do not duplicate; read them for background):
- `Unity-sdk-spec.md` — original two-phase spec (macOS port → Unity wrapper).
- `Unity-sdk-phase1-plan.md` — Phase-1 design + decision log.
- `Unity-sdk-phase1-mac-run.md` — the on-Mac validation guide the session was executing.
- `.claude-memory/unity-sdk-project.md` — project memory: decisions locked, hotspots, and the
  Linux-authored scaffolding state as of 2026-07-31.

---

## TL;DR — where the port stands

| Section (from `Unity-sdk-phase1-mac-run.md`) | Status |
|---|---|
| 0. Prerequisites | **Partially done.** JDK 17 installed via brew and symlinked. Full Xcode NOT installed — blocker for §3+. |
| 1. Target registered | **Done.** `linkDebug/ReleaseFrameworkMacosArm64`, `macosArm64MainKlibrary`, `macosArm64Test` tasks all present. |
| 2. Compile `compileKotlinMacosArm64` | **Done — BUILD SUCCESSFUL.** Two fixes required (below). Only unrelated unchecked-cast warnings remain. |
| 3. Link `linkDebugFrameworkMacosArm64` | **Blocked** — needs full Xcode.app; CLT-only fails with `xcrun xcodebuild -version` exit 72. |
| 4. `macosArm64Test` | Blocked on §3. |
| 5. WKWebView + NSWindow presenter | Not started (current `MacosInAppPresenter` is a no-op stub). |
| 6. macOS sample app | Not started. |
| 7. Publishing | Not started. |

Next agent's first job: get Xcode.app installed on the Mac, then resume from §3.

---

## Environment already set up

- **JDK 17** installed via Homebrew (`openjdk@17` 17.0.20), keg-only, symlinked into
  `/Library/Java/JavaVirtualMachines/openjdk-17.jdk`. `/usr/libexec/java_home -v 17` returns
  the right path. Gradle wrapper reports:
  ```
  Gradle 9.4.1
  Kotlin: 2.3.0
  Launcher JVM: 17.0.20 (Homebrew 17.0.20+0)
  OS: Mac OS X 26.5.2 aarch64
  ```
- **JAVA_HOME is NOT exported in the shell profile.** Every Gradle command run in this session
  prefixed `export JAVA_HOME=$(/usr/libexec/java_home -v 17) && ...`. Either keep doing that,
  or ask the user to add it to `~/.zshrc` — do not attempt to write to `~/.zshrc` yourself.
- **Kotlin/Native toolchain** downloaded to `~/.konan/kotlin-native-prebuilt-macos-aarch64-2.3.10/`
  (LLVM 19, libffi 3.3, lldb 4). This was the one-time ~1–2 GB download; §2 already exercised it.
- **Xcode Command Line Tools** at `/Library/Developer/CommandLineTools`. This is INSUFFICIENT for
  the linker — see blocker below.

Machine: Apple Silicon, Darwin 25/26 kernel, arm64. macOS reports itself as Mac OS X 26.5.2 to
Gradle (the fleet has moved to macOS 26).

---

## Fixes already applied to unblock §2 compile

The Linux-authored scaffolding produced 5 compile errors on the first `compileKotlinMacosArm64`.
Both files below are already patched — do not re-fix. Included here so a reviewer understands
the state.

### 1. `engagement-cloud-sdk/src/macosMain/kotlin/com/sap/ec/core/device/UIDevice.kt`

**Was:** used `platform.posix.sysctlbyname` (not present in Kotlin/Native's macos_arm64 posix
klib) and dereferenced `NSOperatingSystemVersion` as a struct (it comes back from Kotlin/Native
as `CValue<NSOperatingSystemVersion>` and needs `.useContents { … }`).

**Now:** trimmed to Foundation-only. `deviceModel()` returns the literal `"Mac"` (parity
trade-off — iOS returns `UIDevice.currentDevice.model` which is a similarly generic string;
we can later revisit with an IOKit-based hardware identifier if telemetry needs it).

If you want a richer `deviceModel()` (e.g. `"MacBookPro18,3"`), the right paths are:
- Add a Kotlin/Native cinterop def for `sys/sysctl.h` in `engagement-cloud-sdk/build.gradle.kts`
  (`cinterops { create("sysctl") { … } }` under the `macosArm64` target).
- Or bridge through IOKit's `IORegistry` — heavier.
Do not put `sysctlbyname` back in without doing one of the above first — the raw
`platform.posix.sysctlbyname` import does not resolve on this target.

### 2. `engagement-cloud-sdk/src/commonMain/kotlin/com/sap/ec/core/crypto/Crypto.kt`

**Was:** `when (currentPlatform)` handled JS / Android / IOS. Missing MACOS made the `when`
non-exhaustive.

**Now:** added a `KotlinPlatform.MACOS -> { ECDSA.SignatureFormat.DER to Base64.decode(...) }`
branch mirroring the IOS branch (macOS Kotlin/Native uses the same DER-formatted ECDSA output).

---

## The current blocker — full Xcode required

Section 3 fails immediately with:

```
Failed command: /usr/bin/xcrun xcodebuild -version
The /usr/bin/xcrun command returned non-zero exit code: 72.
org.jetbrains.kotlin.konan.MissingXcodeException
```

`xcodebuild` is NOT part of Command Line Tools — it ships only with Xcode.app. Kotlin/Native's
linker (2.3.x) calls `xcrun xcodebuild -version` during its Xcode-version probe, and that
probe fails when CLT is the active developer directory.

Verified state at session end:
- `xcode-select -p` → `/Library/Developer/CommandLineTools`
- `ls /Applications | grep -i xcode` → nothing
- `xcrun -sdk macosx --show-sdk-path` → `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`
  (works, but linker still needs full Xcode).

**To unblock (must be done by the user, not the agent):**

1. Install Xcode from the App Store or https://developer.apple.com/download/all/. Guide says
   "Xcode 15.4 or newer"; anything current will do.
2. Point the developer dir at it:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   ```
3. Verify:
   ```bash
   xcrun xcodebuild -version                 # must print Xcode <version> without error
   xcode-select -p                           # must print /Applications/Xcode.app/...
   ```

Do NOT run the `sudo` commands from an agent tool — the user has stated they will not provide
their password to the agent. Ask them to run these outside the session.

---

## Resume plan for the next agent

Assuming Xcode.app is installed and selected, resume in this exact order.

### Step A — sanity re-check the compile

The last successful compile was in a session that also downloaded the Kotlin/Native toolchain
under `~/.konan/`. Verify nothing regressed:

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
./gradlew :engagement-cloud-sdk:compileKotlinMacosArm64 --console=plain
```

Expected: `BUILD SUCCESSFUL`, only the two unchecked-cast warnings in
`AppEventActionModelExtensions.kt:16` / `:17` (pre-existing, not ours).

### Step B — link the debug framework (§3 of the run guide)

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
./gradlew :engagement-cloud-sdk:linkDebugFrameworkMacosArm64 --console=plain 2>&1 | tee macos-link.log
```

**What you're likely to hit here** — the Linux-authored scaffolding was never linked:

- **Missing DI slots** in `MacosInjection`. `commonMain` DI probably still expects
  `InAppViewProviderApi` and `InAppJsBridgeFactory` singletons; if so, Koin will fail at
  framework-load time, not link time — but any unresolved cross-module refs will surface here.
- **API-shape drift** in interfaces I couldn't fully read from Linux: `InAppPresenterApi`,
  `DeviceInfoCollectorApi`, `SetupApi`, `ConfigApi`. Compiler names the specific missing
  override — add it.
- **UIKit leakage.** `macosMain` deliberately does NOT depend on `commonComposeMain` and MUST
  NOT pull `com.sap.ec.mobileengage.push.*` (iosMain-only). If linker complains about a push
  symbol, trace back to whatever `commonMain` binding pulled it and either isolate behind
  `expect/actual` or move the source file.

Kotlin/Native link cycles are 30–90 s. **Fix one thing per iteration.** Log every fix in a
running list at the bottom of this handoff so the next handoff (if there is one) has continuity.

Framework lands at:
```
engagement-cloud-sdk/build/bin/macosArm64/debugFramework/EngagementCloudSDK.framework
```

Sanity checks from the run guide (§3):
```bash
FW=engagement-cloud-sdk/build/bin/macosArm64/debugFramework/EngagementCloudSDK.framework
lipo -info "$FW/EngagementCloudSDK"
otool -L "$FW/EngagementCloudSDK" | head
nm -gU "$FW/EngagementCloudSDK" | grep -i EngagementCloud | head
```

Expect `_OBJC_CLASS_$_EngagementCloud` and `_OBJC_CLASS_$_EngagementCloudConfig`.

### Step C — run tests (§4)

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
./gradlew :engagement-cloud-sdk:macosArm64Test --console=plain
```

Runs `commonTest` + the two smoke tests under `src/macosTest/` (KotlinPlatform=MACOS,
UIDevice returns non-empty osVersion + `hasOsVersionAtLeast(10)` true — note: `deviceModel`
now returns `"Mac"`; the existing smoke test just checks non-empty, so it passes).

If `commonTest` fails with iOS-specific assumptions (main-thread expectations), fix the test,
not the SDK — SDK behavior is the reference.

### Step D — Section E (in-app presenter)

Only after §2–4 are green. See `Unity-sdk-phase1-mac-run.md` §5 for the sub-steps
(`MacosWebViewFactory`, `MacosInAppViewProvider` / `MacosInAppView`, real
`MacosInAppPresenter`, wire into `MacosInjection`). Model each on its iOS counterpart in
`src/iosMain/kotlin/com/sap/ec/mobileengage/inapp/`.

Two hard rules from the plan:
- macOS `WKWebView` has NO `scrollView` / `contentInsetAdjustmentBehavior`. Drop that config.
- `UIColor` → `NSColor`. UIKit imports must not appear in `macosMain`.

### Step E — sample app (§6) and publishing (§7)

Follow the run guide as-is. These are the last two done-bar items.

---

## Repo state at handoff

Branch: `main` (per session's initial `git status`). Files touched during the session:

- **Modified:**
  - `engagement-cloud-sdk/src/commonMain/kotlin/com/sap/ec/core/crypto/Crypto.kt`
    (added MACOS branch to `when`).
  - `engagement-cloud-sdk/src/macosMain/kotlin/com/sap/ec/core/device/UIDevice.kt`
    (removed sysctl path, fixed `NSOperatingSystemVersion` via `useContents`).
- **New (not committed):**
  - `macos-compile.log`, `macos-link.log` — build logs at repo root. Safe to delete.
  - `Unity-sdk-phase1-handoff.md` — this file.

Not committed by this session. Nothing pushed. No branches created. Nothing dropped.

Pre-existing pending state (already there when the session started — not our doing):
`.gitmodules` add, `Makefile` edit, `engagement-cloud-sdk-docs` submodule, several files
under `engagement-cloud-sdk/src/macosMain/` and `macosTest/`, `Unity-sdk-*.md` docs — these
are the Linux-authored scaffolding from a prior session.

---

## Running list of fixes (append as you go)

- 2026-07-31 — `Crypto.kt`: added `KotlinPlatform.MACOS` branch to `verify()`'s `when`.
- 2026-07-31 — `UIDevice.kt`: dropped `sysctlbyname`; `deviceModel()` returns `"Mac"`;
  `osVersion()` uses `.useContents { }` on the `CValue<NSOperatingSystemVersion>`.
- (Add next fix here.)
