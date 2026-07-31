# Testing the Unity plugin

## Prerequisites (one-time)

1. **Xcode** — needed to compile the shim. Xcode 15 or later, on Apple Silicon.
2. **xcodegen** — `brew install xcodegen`. Generates the shim's `.xcodeproj` from `unity-plugin/shim/project.yml`.
3. **Unity 6** — install via [Unity Hub](https://unity.com/download). The plugin declares `unity: 6000.0` and is validated on Unity 6.5 (6000.5.5f1). Include the **macOS Build Support** module.
4. **Apple-Silicon Mac** — the shim only builds for `macosArm64`.

## Build the plugin

From the repo root:

```
make unity-package
```

This runs the full Gradle pipeline:

1. Compiles Phase-1's `EngagementCloudSDK.framework` (Kotlin/Native, dynamic).
2. Compiles Unity Kotlin overrides → `EngagementCloudSDKUnityKotlin.framework`.
3. Runs `xcodegen` + `xcodebuild` to produce `EngagementCloudSDKUnity.bundle`.
4. Stages all three artifacts under `unity-plugin/com.sap.ec.unity/Plugins/macOS/`.
5. Tarballs the UPM package into `dist/com.sap.ec.unity-<version>.tgz`.

Individual steps:

- `make unity-shim` — just build the shim bundle.
- `make unity-copy` — build + stage into `Plugins/macOS/`.
- `make unity-clean` — wipe all Unity plugin build outputs.

## Wire into a Unity project

**Option A — local folder reference (recommended for development):**

1. Open Unity Hub → **New project** → **3D (Built-in)** template → Unity 6.5 → any name.
2. Once Unity opens, close it. Edit `Packages/manifest.json` and add under `dependencies`:
   ```json
   "com.sap.ec.unity": "file:/ABSOLUTE/PATH/TO/engagement-cloud-unity-sdk/unity-plugin/com.sap.ec.unity"
   ```
3. Reopen the project. Unity imports the package and generates `.meta` files. Commit those `.meta` files back to this repo — they carry stable asset GUIDs that consumers need.

**Option B — install from tarball:**

1. Unity → Window → Package Manager → **+** → **Add package from tarball...**
2. Select `dist/com.sap.ec.unity-<version>.tgz`.

## Configure

1. In the Unity Project view, right-click → **Create → SAP Engagement Cloud → Settings**.
2. Save under `Assets/Resources/EngagementCloudSettings.asset`.
3. Set the **Application Code** field to a valid SAP Engagement Cloud application code.
4. Leave **Auto Init** on.

## Test it

1. Create an empty GameObject, attach the `SetupSample` script from the imported samples (or just press Play if AutoInit is on).
2. Watch the **Console**:
   - `[EngagementCloud] AutoInit complete.` — setup worked
   - `[EngagementCloud] AutoInit failed: <exception>` — check the app code / network / logs

## Known first-time gotchas

- **Plugin importer settings**: Unity may need each `.framework`/`.bundle` to be flagged macOS-only. Select each artifact under `Plugins/macOS/` in the Project view; in the Inspector, check **macOS** only under "Include Platforms". Save.
- **`.meta` files**: `.meta` files under `unity-plugin/com.sap.ec.unity/` get created on first Unity import. These need to be committed alongside the C# sources so package consumers get the same GUIDs (otherwise scene references break).
- **IL2CPP builds**: The `link.xml` already preserves the P/Invoke thunks and JSON contract types. If you hit "field not found" errors under IL2CPP, add the type to `Runtime/link.xml`.
- **BGRA vs RGBA**: `UnityInAppTextureView` uses `TextureFormat.BGRA32`. If the message renders with swapped red/blue, switch to `TextureFormat.RGBA32` in `UnityInAppTextureView.cs` (line ~85).

## Debugging in Xcode

Attach LLDB to the running Unity process to debug the native shim:

1. Unity → Play (leave running).
2. Xcode → Debug → Attach to Process by PID or Name... → **Unity**.
3. Set breakpoints in `unity-plugin/shim/src/EngagementCloudSDKUnity.mm` or `EcInAppTexturePresenter.mm`.

To iterate on the shim without restarting Unity: **not currently supported** — Unity holds the `.bundle` open, so you need to Stop Play, `make unity-copy`, and Play again.
