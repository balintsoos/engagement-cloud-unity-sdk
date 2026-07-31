# macOS sample app

Minimal AppKit host that consumes the local `EngagementCloudSDK.framework` (macOS build)
and exercises the top-level SDK surface — `setup.enable`, `event.track`, `contact.link`.
The WKWebView + NSPanel in-app presenter added in Phase-1 §5 is invoked automatically once a
real in-app campaign arrives from the Engagement Cloud dashboard while this app is running.

Not an Xcode project: this uses `swiftc` + a hand-built `.app` bundle so the whole loop
(build framework → build sample → run it → see it load) is a single script and shows exactly
which flags are required to consume the framework outside SPM/KMMBridge.

## Build

Prereq: the debug framework must exist. Build it once with:

    export JAVA_HOME=$(/usr/libexec/java_home -v 17)
    ./gradlew :engagement-cloud-sdk:linkDebugFrameworkMacosArm64

Then:

    ./macosApp/build.sh

This produces `macosApp/build/MacosApp.app`. The script copies the framework into
`Contents/Frameworks/`, sets the `@executable_path/../Frameworks` rpath, and ad-hoc-signs
the bundle so Gatekeeper doesn't kill the run.

To point at a different framework build (release, xcframework slice, …):

    FRAMEWORK_DIR=/path/to/parent-of-EngagementCloudSDK.framework ./macosApp/build.sh

## Run

    open macosApp/build/MacosApp.app

Or, to see NSLog output on stderr in your terminal:

    macosApp/build/MacosApp.app/Contents/MacOS/MacosApp

## What it does

Four buttons:

1. `setup.enable` — calls `EngagementCloud.shared.setup.enable(config:onContactLinkingFailed:)`
   with the placeholder application code `EMSE3-B4341`. Replace that string in
   `Sources/main.swift` when validating against a real environment.
2. `event.track("macos-sample")` — sends a `CustomEvent`.
3. `contact.link("test@example.com")` — links a demo contact.
4. In-app trigger — informational only. Real in-app messages arrive over the network after a
   campaign fires from the Engagement Cloud dashboard. When one does, the SDK presents it via
   an `NSPanel`-hosted `WKWebView` overlay (see `MacosInAppPresenter`).

## Known limitations

- The application code is a placeholder; wire in a real one for end-to-end validation.
- Ad-hoc codesign means the bundle is not shippable — this is a dev sample only.
- No entitlements/sandbox: it's a plain unsigned test host.
- Push and embedded messaging aren't part of the macOS SDK surface (Phase-1 decisions #5 and
  #6), so they're not exercised here.
