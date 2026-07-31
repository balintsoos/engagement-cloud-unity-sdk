# Adding the SAP Engagement Cloud plugin to an existing Unity project

This tutorial walks a Unity developer through adding the plugin to a Unity
project that already exists. Total time: **15–30 minutes** first time, mostly
waiting for compiles.

## Before you start

You need:

- **An Apple-Silicon Mac.** The plugin only supports `macosArm64` — Intel Macs and Windows/Linux will not work.
- **Unity 6.0 or later.** Validated on Unity 6.5 (6000.5.5f1). Make sure the **macOS Build Support** module is installed in Unity Hub.
- **Xcode 15+.** Only needed if you plan to build the plugin from source. If you're consuming a pre-built `.tgz` release, skip Xcode.
- **`xcodegen`.** Only needed for building from source: `brew install xcodegen`.
- Your **SAP Engagement Cloud application code** (a short string issued by SAP for your app).

If you're only *consuming* a pre-built release (Step 1a below), skip Xcode and xcodegen.

---

## Step 1: Get the plugin

Pick **one** of the two options below.

### Option 1a — Consume a pre-built release (recommended for game developers)

Download the latest `com.sap.ec.unity-<version>.tgz` from the [GitHub releases page](https://github.com/emartech/engagement-cloud-unity-sdk/releases). Save it somewhere you'll remember — e.g. `~/Downloads/`.

Skip to **Step 2**.

### Option 1b — Build from source (for SDK contributors)

Clone the SDK repository and build the tarball locally:

```bash
git clone git@github.com:emartech/engagement-cloud-unity-sdk.git
cd engagement-cloud-unity-sdk
make unity-package
```

The build takes **2–3 minutes** the first time (downloads Kotlin/Native compiler, links two frameworks, compiles the Obj-C++ shim). Output:

```
dist/com.sap.ec.unity-0.1.0-dev.tgz
```

If you hit `xcodegen not found`, run `brew install xcodegen` and retry.

---

## Step 2: Import into your Unity project

### Option 2a — Install from the local folder (recommended for development)

**Only works if you built from source in Step 1b.** If you downloaded a `.tgz`, use Option 2b.

1. **Close** your Unity project if it's open. Package Manager can get confused if you edit `Packages/manifest.json` while Unity is running.
2. Open `Packages/manifest.json` in your Unity project.
3. Add the plugin under `dependencies`, pointing at the local folder:
   ```json
   {
     "dependencies": {
       "com.sap.ec.unity": "file:/ABSOLUTE/PATH/TO/engagement-cloud-unity-sdk/unity-plugin/com.sap.ec.unity",
       // ... your existing dependencies
     }
   }
   ```
   Use the absolute path, not `~/...`. On macOS it typically looks like `file:/Users/you/dev/engagement-cloud-unity-sdk/unity-plugin/com.sap.ec.unity`.
4. Save and reopen the Unity project. Unity will import the package (watch the progress bar — first import takes ~10 seconds).

### Option 2b — Install from the tarball

1. In Unity: **Window → Package Manager**.
2. Click the **+** button at the top-left of the Package Manager window → **Add package from tarball...**
3. Select the `.tgz` file you downloaded or built.
4. Wait for the import (~10 seconds).

### Confirm the import worked

In the Package Manager, filter by "In Project" — you should see **SAP Engagement Cloud 0.1.0-dev** (or later).

In the Project view under **Packages → SAP Engagement Cloud**, you should see:
- `Runtime/` — the C# source
- `Plugins/macOS/` — three native artifacts (`EngagementCloudSDK.framework`, `EngagementCloudSDKUnityKotlin.framework`, `EngagementCloudSDKUnity.bundle`)
- `Samples~/` — hidden by default; visible only through Package Manager's "Samples" tab

If any of these are missing, the import didn't complete — check the **Console** for red errors.

---

## Step 3: Configure the plugin importers

Unity's plugin importer needs to know that the three native artifacts are macOS-only. **This is a one-time step per project.**

For each of the three artifacts under `Packages/SAP Engagement Cloud/Plugins/macOS/`:

- `EngagementCloudSDK.framework`
- `EngagementCloudSDKUnityKotlin.framework`
- `EngagementCloudSDKUnity.bundle`

do this:

1. Select the artifact in the Project view.
2. In the **Inspector**, find the **Platform settings** section.
3. Under **Include Platforms**, tick **only** these:
   - **Editor** → set **CPU** to `ARM64` and **OS** to `macOS`
   - **Standalone** → set **CPU** to `ARM64` and **OS** to `macOS`
   Untick everything else (iOS, Android, Windows, Linux, WebGL).
4. Click **Apply** at the bottom of the Inspector.

Unity will reimport the artifact and rebuild the Player. Wait for the progress bar.

**If Unity gives you a "duplicate assembly" error**: you probably left an "Any Platform" tick on. Only tick Editor + Standalone macOS ARM64, nothing else.

---

## Step 4: Create the settings asset

The plugin auto-initializes at startup from a `ScriptableObject` in `Assets/Resources/`.

1. In the Project view, navigate to `Assets/`.
2. Right-click → **Create → Folder** → name it `Resources` (case-sensitive, singular).
3. Right-click inside `Resources` → **Create → SAP Engagement Cloud → Settings**.
4. Unity creates `EngagementCloudSettings.asset`. **Don't rename it** — the auto-init path looks up this exact name.
5. Select the new asset. In the Inspector:
   - **Application Code**: paste your SAP Engagement Cloud application code.
   - **Auto Init**: leave **on** (the default).

That's it — the SDK will initialize automatically before your first scene loads.

If you'd rather initialize manually from your own code (e.g. after a login flow), uncheck **Auto Init** and call `EngagementCloud.Setup(applicationCode)` yourself from your bootstrap script.

---

## Step 5: Smoke test — is Setup working?

1. In the Project view, right-click in any folder under `Assets/` → **Create → C# Script** → name it `EngagementCloudSmokeTest`.
2. Open it and replace the contents with:

   ```csharp
   using UnityEngine;
   using EngagementCloud;

   public class EngagementCloudSmokeTest : MonoBehaviour
   {
       private void Awake()
       {
           EngagementCloud.EventReceived += OnEvent;
           Debug.Log($"[Smoke] Wrapper version: {EngagementCloud.WrapperVersion}");
       }

       private void OnDestroy()
       {
           EngagementCloud.EventReceived -= OnEvent;
       }

       private async void Start()
       {
           try
           {
               string clientId = await EngagementCloud.ConfigGetClientId();
               Debug.Log($"[Smoke] SDK is up. Client ID: {clientId}");
           }
           catch (EngagementCloudException e)
           {
               Debug.LogError($"[Smoke] Failed ({e.Type}): {e.Message}");
           }
       }

       private void OnEvent(SdkEvent evt)
       {
           Debug.Log($"[Smoke] Event: {evt}");
       }
   }
   ```

3. Save. Wait for Unity to compile (bottom-right corner shows the spinner).
4. In your scene, create an empty GameObject: **GameObject → Create Empty**.
5. With the empty GameObject selected, in the Inspector click **Add Component** → search for `EngagementCloudSmokeTest` → add it.
6. Press **Play**.

Watch the Console. **Expected output:**

```
[EngagementCloud] AutoInit complete.
[Smoke] Wrapper version: 0.1.0-dev
[Smoke] SDK is up. Client ID: <a UUID-ish string>
```

If you see this, the plugin is working end-to-end.

### If AutoInit fails

Common failure modes and what they mean:

- `[EngagementCloud] AutoInit failed: InvalidApplicationCodeException` — the application code in the settings asset isn't recognized by the server. Double-check it.
- `[EngagementCloud] AutoInit failed: NetworkIOException` — SDK reached out to the server and got a network error. Check connectivity.
- `EntryPointNotFoundException: ec_setup` — Unity can't find the native shim. Revisit **Step 3** (plugin importer platform settings).
- `DllNotFoundException: EngagementCloudSDKUnity` — same as above. The shim `.bundle` isn't being loaded.
- **Nothing prints, Unity hangs on Play** — Kotlin/Native's Koin init might be crashing silently. Attach LLDB (see the "Debugging" section below) or check the system console (Console.app) for messages tagged `[EngagementCloudSDKUnity]`.

---

## Step 6: Use the API

Once Setup works, you have the full API available. All methods return `Task` and complete on Unity's main thread:

```csharp
using System.Collections.Generic;
using UnityEngine;
using EngagementCloud;

public class MyGameEvents : MonoBehaviour
{
    // Link the current player to a contact (call once, e.g. after login)
    public async void OnUserSignedIn(string userEmail)
    {
        await EngagementCloud.ContactLink(userEmail);
    }

    // Track a custom event with string attributes
    public async void OnLevelComplete(int levelNumber, int score)
    {
        await EngagementCloud.TrackEvent("level_complete", new Dictionary<string, string> {
            ["level"] = levelNumber.ToString(),
            ["score"] = score.ToString(),
        });
    }

    // Pause in-app messages during cutscenes, resume after
    public async void OnCutsceneStart()  => await EngagementCloud.InAppPause();
    public async void OnCutsceneEnd()    => await EngagementCloud.InAppResume();

    // Log the current user out
    public async void OnUserSignedOut()  => await EngagementCloud.ContactUnlink();
}
```

### Displaying in-app messages

In-app messages are rendered as a Unity `Texture2D`:

1. In your scene, create a full-screen UI canvas: **GameObject → UI → Canvas**. Set **Render Mode** to **Screen Space - Overlay**.
2. Right-click the canvas → **UI → Raw Image**. Set its RectTransform to stretch to fill the canvas (top-left anchor `(0,1)`, bottom-right anchor `(1,0)`, all offsets `0`).
3. With the Raw Image selected, click **Add Component** → search for `Unity In App Texture View` → add it.
4. That's it. When the SDK server pushes an in-app message, it will composite into that Raw Image as a texture. Pointer clicks are forwarded to the underlying WebView, so buttons in the message will respond.

To dismiss the message from code (or observe when the user dismisses it):

```csharp
EngagementCloud.EventReceived += evt => {
    if (evt.Type.Contains("Dismiss"))
    {
        // Message was dismissed — hide your canvas
        rawImage.gameObject.SetActive(false);
    }
};
```

---

## Step 7: Commit `.meta` files

**This step matters if you're using the plugin as a `file:` reference from Option 2a.** On first import, Unity generated `.meta` files inside `unity-plugin/com.sap.ec.unity/`. These files carry stable asset GUIDs — commit them alongside the C# sources so scene references, prefab references, and cross-file dependencies survive across machines.

```bash
cd engagement-cloud-unity-sdk
git status  # inspect the new .meta files
git add unity-plugin/com.sap.ec.unity/**/*.meta
git commit -m "chore(unity-plugin): add Unity-generated .meta files"
```

If someone else has already committed `.meta` files upstream, you don't need to do this — pull the latest and Unity will use theirs.

---

## Step 8: Ship a macOS Player build

- **File → Build Settings** → select **macOS**.
- **Architecture**: `Apple silicon` (or `Intel 64-bit + Apple silicon` — but Intel won't have the plugin available). If you want to run on Rosetta on Intel Macs, you'd need an x64 build of the shim too, which is not currently supported.
- Click **Build**.
- The output `.app` will bundle the shim `.bundle` + both `.framework`s automatically. No extra copy step.

To verify at runtime that your build is running with wrapper identity: any HTTP request the SDK sends to SAP's servers will include the header/body field `platformWrapper: "unity"` and `platformWrapperVersion: <package version>`. Check server-side logs to confirm.

---

## Debugging tips

### Attaching LLDB to a running Unity Editor

To debug the native shim while your game is playing:

1. Press **Play** in Unity, leave the game running.
2. Open Xcode.
3. **Debug → Attach to Process by PID or Name...** → **Unity**.
4. In the Xcode Project navigator, add the shim source: **File → Add Files to Project...** → select `unity-plugin/shim/src/EngagementCloudSDKUnity.mm` and `EcInAppTexturePresenter.mm`.
5. Set breakpoints — they'll fire when your Unity code exercises the shim.

### Iterating on the native shim

If you're modifying `unity-plugin/shim/src/*.mm`, the workflow is:

1. Edit the `.mm`.
2. Stop Unity Play mode (Unity holds the `.bundle` open while playing).
3. `make unity-copy` (rebuilds shim, restages into `Plugins/macOS/`).
4. Unity notices the file change and reimports (~1s).
5. Press Play again.

There's no hot-reload path — Unity has to release the `.bundle` before you can rebuild it.

### Where to find native logs

The shim writes to `NSLog`. On macOS these end up in:

- Unity's Console window (if the log fires while Play mode is running).
- **Console.app** system log — filter by process name "Unity" and message content `[EngagementCloudSDKUnity]`.
- If Unity was launched from Terminal: `stdout`/`stderr` of the terminal session.

---

## Common problems

**"The type or namespace name 'EngagementCloud' could not be found"** — the package didn't import. Check Package Manager, then Console for import errors.

**"Reference rewriter: Error: type `System.Runtime.InteropServices.UnmanagedType.LPUTF8Str` doesn't exist"** — your Unity is too old. Upgrade to Unity 6.0 or later.

**In-app message shows as a blank/transparent rectangle** — most likely the pixel format mismatch (BGRA vs RGBA) or the snapshot loop hasn't ticked yet. Check the Console for the shim's `NSLog`; if you don't see any `[EngagementCloudSDKUnity]` messages, the shim isn't loading (revisit Step 3).

**Clicks on the in-app message don't do anything** — pointer forwarding requires a `GraphicRaycaster` on the Canvas (Unity adds one automatically when you create a UI Canvas). If yours is missing, add it: select the Canvas → **Add Component → Graphic Raycaster**.

**"MissingApplicationCodeException"** — the `EngagementCloudSettings.asset` isn't being found. It must live under `Assets/Resources/EngagementCloudSettings.asset` — not in a subfolder, and the filename must match exactly.

**"NotImplementedException" on some SDK call** — the shim doesn't yet implement that path. Currently applies to `ec_logger_setSink` (native logger routing is pending a future patch — see the phase-2 plan).

---

## Getting help

- **Plugin bugs / feature requests**: [GitHub issues](https://github.com/emartech/engagement-cloud-unity-sdk/issues)
- **SDK / server-side questions**: your SAP Engagement Cloud support contact
- **Xcode build errors**: check `unity-plugin/shim/README.md` and try `make unity-clean && make unity-package` from a clean state
