# SAP Engagement Cloud — Unity Plugin

Unity 6 plugin for the SAP Engagement Cloud SDK on **Apple-Silicon macOS**.

## What's in this release

- **`com.sap.ec.unity-<version>.tgz`** — UPM package. Install via Unity Package Manager (see below).
- **`EngagementCloud-<version>.unitypackage`** (when built) — legacy Unity package format for the "Import Custom Package..." workflow.

## Install

Unity 6 (6000.0 or later) on Apple-Silicon macOS.

### Option 1 — Package Manager (recommended)

1. Download the `com.sap.ec.unity-<version>.tgz` asset from this release.
2. In Unity: **Window → Package Manager → + → Add package from tarball...** → select the `.tgz`.

### Option 2 — Legacy `.unitypackage`

1. Download the `EngagementCloud-<version>.unitypackage` asset.
2. In Unity: **Assets → Import Package → Custom Package...** → select the file.

## Next steps

See the [full tutorial](https://github.com/emartech/engagement-cloud-unity-sdk/blob/main/Unity-sdk-tutorial.md) for:
- Plugin importer settings (macOS ARM64, Editor + Standalone)
- Creating the `EngagementCloudSettings` asset
- Smoke test to verify Setup works
- API usage examples (contact link, event tracking, in-app messages)

## Requirements

- Unity 6.0 or later (validated on 6.5)
- macOS 11+ on Apple Silicon
- Xcode 15+ only if you plan to rebuild the plugin from source

## Notes

Intel Macs, iOS, Android, WebGL, Windows, and Linux Player builds are **not** supported in this release.
