using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using EngagementCloud;                       // types: SdkEvent, EngagementCloudException, subclasses
using EC = EngagementCloud.EngagementCloud;  // static facade class (disambiguates from the namespace)
using UnityEngine;
using UnityEngine.UI;

namespace EngagementCloudSamples
{
    /// <summary>
    /// End-to-end Unity sample that mirrors <c>macosApp/Sources/main.swift</c> button-for-button:
    /// setup / enable / disable / link, per-campaign trigger buttons for IA1 / mysy3 / mysy4 /
    /// IA4-IA7, in-app pause/resume, a live inline in-app slot rendering viewId <c>"ia"</c>
    /// into a <see cref="RawImage"/>, a boot state dump, and a scrolling log panel that
    /// captures every SDK event alongside our own status lines.
    ///
    /// The whole UI is constructed at runtime in <see cref="Start"/> so that this repo can
    /// ship without a hand-authored <c>.unity</c> file (Unity's YAML scene format is fragile
    /// to edit outside the Editor). Drop <c>SampleAppController</c> onto an empty GameObject
    /// in an empty scene, press Play, and everything is there.
    ///
    /// Constants match the Android e2e test-app (<c>Constants.APPLICATION_CODE</c>,
    /// <c>Constants.CONTACT_EMAIL</c>) so the same backend campaigns fire.
    /// </summary>
    public sealed class SampleAppController : MonoBehaviour
    {
        // ------------------------------------------------------------ configuration
        private const string APPLICATION_CODE = "EMSE3-B4341";
        private const string CONTACT_EMAIL    = "test1@test.com";
        private const string INLINE_VIEW_ID   = "ia";
        private const int    INLINE_W         = 512;
        private const int    INLINE_H         = 320;

        // ------------------------------------------------------------ runtime state
        private Text   _statusLabel;
        private Text   _logLabel;
        private ScrollRect _logScroll;
        private Text   _inlineStatus;
        private RawImage _inlineImage;
        private UnityInAppTextureView _inlineView;
        private readonly Queue<string> _logLines = new Queue<string>();
        private const int MaxLogLines = 200;

        // ------------------------------------------------------------ Unity hooks

        private void Start()
        {
            BuildUI();
            EC.EventReceived += OnSdkEvent;
            AppendLog($"SampleAppController booted (appCode={APPLICATION_CODE}, contact={CONTACT_EMAIL})");
            _ = DumpStateAsync("boot");
        }

        private void OnDestroy()
        {
            EC.EventReceived -= OnSdkEvent;
        }

        // ============================================================================
        // UI construction (programmatic)
        // ============================================================================

        private void BuildUI()
        {
            // -- Canvas ---------------------------------------------------------------
            var canvasGo = new GameObject("Canvas");
            var canvas = canvasGo.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 0;
            var scaler = canvasGo.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1280, 800);
            scaler.matchWidthOrHeight = 0.5f;
            canvasGo.AddComponent<GraphicRaycaster>();

            // Root vertical container
            var root = CreateVerticalGroup("Root", canvasGo.transform, padding: 16, spacing: 8);
            var rootRt = (RectTransform)root.transform;
            rootRt.anchorMin = Vector2.zero;
            rootRt.anchorMax = Vector2.one;
            rootRt.offsetMin = new Vector2(20, 20);
            rootRt.offsetMax = new Vector2(-20, -20);

            // -- Status label ---------------------------------------------------------
            _statusLabel = CreateLabel("StatusLabel", root.transform, "Ready.",
                                      fontSize: 16, bold: true, alignment: TextAnchor.MiddleLeft);

            // -- Setup row ------------------------------------------------------------
            CreateSectionHeader(root.transform, "Setup");
            var setupRow = CreateHorizontalGroup("SetupRow", root.transform, spacing: 8);
            CreateButton(setupRow.transform, "Enable SDK",              async () => await OnEnable());
            CreateButton(setupRow.transform, "Disable SDK",             async () => await OnDisable());
            CreateButton(setupRow.transform, $"Link {CONTACT_EMAIL}",   async () => await OnLink());

            // -- Campaign row 1 -------------------------------------------------------
            CreateSectionHeader(root.transform, "In-app triggers (custom event → backend campaign)");
            var camRow1 = CreateHorizontalGroup("CampaignRow1", root.transform, spacing: 8);
            CreateButton(camRow1.transform, "IA1 ▶ mysy2",   async () => await Track("mysy2"));
            CreateButton(camRow1.transform, "mysy3",          async () => await Track("mysy3"));
            CreateButton(camRow1.transform, "mysy4",          async () => await Track("mysy4"));
            CreateButton(camRow1.transform, "IA4 ▶ view",     async () => await Track("test_inapp_view_event"));

            // -- Campaign row 2 -------------------------------------------------------
            var camRow2 = CreateHorizontalGroup("CampaignRow2", root.transform, spacing: 8);
            CreateButton(camRow2.transform, "IA5 ▶ click",    async () => await Track("test_inapp_click_event"));
            CreateButton(camRow2.transform, "IA6 ▶ pause",    async () => await Track("test_inapp_pause"));
            CreateButton(camRow2.transform, "IA7 ▶ resume",   async () => await Track("test_inapp_resume"));

            // -- Inline slot ----------------------------------------------------------
            CreateSectionHeader(root.transform, $"Inline in-app (viewId=\"{INLINE_VIEW_ID}\", {INLINE_W}x{INLINE_H})");
            _inlineStatus = CreateLabel("InlineStatus", root.transform,
                                        "Inline: opening…",
                                        fontSize: 12, bold: false, alignment: TextAnchor.MiddleLeft);

            // The inline image: fixed height row hosting the RawImage.
            var inlineHost = new GameObject("InlineHost", typeof(RectTransform), typeof(LayoutElement));
            inlineHost.transform.SetParent(root.transform, worldPositionStays: false);
            var hostLayout = inlineHost.GetComponent<LayoutElement>();
            hostLayout.preferredHeight = INLINE_H;
            hostLayout.flexibleHeight = 0;

            var inlineImageGo = new GameObject("InlineImage",
                typeof(RectTransform), typeof(CanvasRenderer), typeof(RawImage));
            inlineImageGo.transform.SetParent(inlineHost.transform, worldPositionStays: false);
            var iiRt = (RectTransform)inlineImageGo.transform;
            iiRt.anchorMin = Vector2.zero;
            iiRt.anchorMax = Vector2.one;
            iiRt.offsetMin = Vector2.zero;
            iiRt.offsetMax = Vector2.zero;
            _inlineImage = inlineImageGo.GetComponent<RawImage>();
            _inlineImage.color = Color.white;
            _inlineImage.raycastTarget = true;

            // Attach the plugin's texture-view MonoBehaviour so it drives the RawImage.
            _inlineView = inlineImageGo.AddComponent<UnityInAppTextureView>();
            _inlineView.viewId = INLINE_VIEW_ID;
            _inlineView.width  = INLINE_W;
            _inlineView.height = INLINE_H;

            // -- Control row ---------------------------------------------------------
            CreateSectionHeader(root.transform, "In-app control");
            var ctrlRow = CreateHorizontalGroup("ControlRow", root.transform, spacing: 8);
            CreateButton(ctrlRow.transform, "inApp.pause",  async () => await OnPause());
            CreateButton(ctrlRow.transform, "inApp.resume", async () => await OnResume());
            CreateButton(ctrlRow.transform, "reload inline", () =>
            {
                if (_inlineView == null) return;
                _inlineView.enabled = false;
                _inlineView.enabled = true;
                AppendLog("inline: reload requested");
            });
            CreateButton(ctrlRow.transform, "dump state",   () => _ = DumpStateAsync("manual"));
            CreateButton(ctrlRow.transform, "clear log",    OnClearLog);

            // -- Log view ------------------------------------------------------------
            CreateSectionHeader(root.transform, "Log");
            _logScroll = CreateScrollableLog(root.transform);
        }

        // ============================================================================
        // Small UI factories — Unity's UGUI is verbose so keep the ceremony out of the
        // action code.
        // ============================================================================

        private static GameObject CreateVerticalGroup(string name, Transform parent, int padding, int spacing)
        {
            var go = new GameObject(name, typeof(RectTransform), typeof(VerticalLayoutGroup), typeof(ContentSizeFitter));
            go.transform.SetParent(parent, worldPositionStays: false);
            var v = go.GetComponent<VerticalLayoutGroup>();
            v.padding = new RectOffset(padding, padding, padding, padding);
            v.spacing = spacing;
            v.childAlignment = TextAnchor.UpperLeft;
            v.childControlWidth = true;
            v.childControlHeight = true;
            v.childForceExpandWidth = true;
            v.childForceExpandHeight = false;
            var fit = go.GetComponent<ContentSizeFitter>();
            fit.horizontalFit = ContentSizeFitter.FitMode.Unconstrained;
            fit.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            return go;
        }

        private static GameObject CreateHorizontalGroup(string name, Transform parent, int spacing)
        {
            var go = new GameObject(name, typeof(RectTransform), typeof(HorizontalLayoutGroup), typeof(LayoutElement));
            go.transform.SetParent(parent, worldPositionStays: false);
            var h = go.GetComponent<HorizontalLayoutGroup>();
            h.spacing = spacing;
            h.childAlignment = TextAnchor.MiddleLeft;
            h.childControlWidth = true;
            h.childControlHeight = false;
            h.childForceExpandWidth = false;
            h.childForceExpandHeight = false;
            var el = go.GetComponent<LayoutElement>();
            el.preferredHeight = 34;
            el.flexibleHeight = 0;
            return go;
        }

        private static Text CreateLabel(string name, Transform parent, string text,
                                        int fontSize, bool bold, TextAnchor alignment)
        {
            var go = new GameObject(name, typeof(RectTransform), typeof(CanvasRenderer), typeof(Text), typeof(LayoutElement));
            go.transform.SetParent(parent, worldPositionStays: false);
            var t = go.GetComponent<Text>();
            t.text = text;
            t.fontSize = fontSize;
            t.fontStyle = bold ? FontStyle.Bold : FontStyle.Normal;
            t.alignment = alignment;
            t.color = new Color(0.9f, 0.9f, 0.9f);
            t.horizontalOverflow = HorizontalWrapMode.Wrap;
            t.verticalOverflow = VerticalWrapMode.Overflow;
            // Legacy UGUI needs a font. LegacyRuntime.ttf ships with Unity in every project.
            t.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            var el = go.GetComponent<LayoutElement>();
            el.minHeight = fontSize + 4;
            return t;
        }

        private static void CreateSectionHeader(Transform parent, string text)
        {
            var label = CreateLabel("SectionHeader", parent, text.ToUpperInvariant(),
                                    fontSize: 11, bold: true, alignment: TextAnchor.MiddleLeft);
            label.color = new Color(0.55f, 0.75f, 1f);
        }

        private static void CreateButton(Transform parent, string label, Action onClick)
        {
            CreateButton(parent, label, () => { onClick?.Invoke(); return Task.CompletedTask; });
        }

        private static void CreateButton(Transform parent, string label, Func<Task> onClick)
        {
            var go = new GameObject("Button:" + label, typeof(RectTransform), typeof(CanvasRenderer),
                                    typeof(Image), typeof(Button), typeof(LayoutElement));
            go.transform.SetParent(parent, worldPositionStays: false);
            var img = go.GetComponent<Image>();
            img.color = new Color(0.16f, 0.20f, 0.28f);
            var btn = go.GetComponent<Button>();
            var colors = btn.colors;
            colors.normalColor      = new Color(0.16f, 0.20f, 0.28f);
            colors.highlightedColor = new Color(0.22f, 0.28f, 0.36f);
            colors.pressedColor     = new Color(0.12f, 0.15f, 0.22f);
            colors.selectedColor    = colors.normalColor;
            colors.disabledColor    = new Color(0.10f, 0.12f, 0.18f);
            btn.colors = colors;
            btn.onClick.AddListener(() => _ = onClick());

            var labelGo = new GameObject("Label", typeof(RectTransform), typeof(CanvasRenderer), typeof(Text));
            labelGo.transform.SetParent(go.transform, worldPositionStays: false);
            var lrt = (RectTransform)labelGo.transform;
            lrt.anchorMin = Vector2.zero;
            lrt.anchorMax = Vector2.one;
            lrt.offsetMin = new Vector2(8, 4);
            lrt.offsetMax = new Vector2(-8, -4);
            var t = labelGo.GetComponent<Text>();
            t.text = label;
            t.fontSize = 12;
            t.color = new Color(0.95f, 0.95f, 0.95f);
            t.alignment = TextAnchor.MiddleCenter;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            t.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");

            var el = go.GetComponent<LayoutElement>();
            el.minWidth = 120;
            el.preferredWidth = 160;
            el.preferredHeight = 30;
        }

        private ScrollRect CreateScrollableLog(Transform parent)
        {
            // Scroll view root.
            var svGo = new GameObject("LogScrollView", typeof(RectTransform), typeof(CanvasRenderer),
                                      typeof(Image), typeof(ScrollRect), typeof(LayoutElement));
            svGo.transform.SetParent(parent, worldPositionStays: false);
            var svBg = svGo.GetComponent<Image>();
            svBg.color = new Color(0.08f, 0.09f, 0.11f, 0.9f);
            var svEl = svGo.GetComponent<LayoutElement>();
            svEl.preferredHeight = 220;
            svEl.flexibleHeight = 1;

            // Viewport (masked).
            var vpGo = new GameObject("Viewport", typeof(RectTransform), typeof(CanvasRenderer),
                                      typeof(Image), typeof(Mask));
            vpGo.transform.SetParent(svGo.transform, worldPositionStays: false);
            var vpRt = (RectTransform)vpGo.transform;
            vpRt.anchorMin = Vector2.zero; vpRt.anchorMax = Vector2.one;
            vpRt.offsetMin = new Vector2(6, 6); vpRt.offsetMax = new Vector2(-6, -6);
            vpGo.GetComponent<Image>().color = new Color(1, 1, 1, 0.01f);
            vpGo.GetComponent<Mask>().showMaskGraphic = false;

            // Content (auto-grow, top-aligned).
            var contentGo = new GameObject("Content", typeof(RectTransform), typeof(ContentSizeFitter),
                                           typeof(VerticalLayoutGroup));
            contentGo.transform.SetParent(vpGo.transform, worldPositionStays: false);
            var cRt = (RectTransform)contentGo.transform;
            cRt.anchorMin = new Vector2(0, 1);
            cRt.anchorMax = new Vector2(1, 1);
            cRt.pivot = new Vector2(0.5f, 1f);
            cRt.offsetMin = Vector2.zero; cRt.offsetMax = Vector2.zero;
            var cFit = contentGo.GetComponent<ContentSizeFitter>();
            cFit.horizontalFit = ContentSizeFitter.FitMode.Unconstrained;
            cFit.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            var cLay = contentGo.GetComponent<VerticalLayoutGroup>();
            cLay.padding = new RectOffset(8, 8, 8, 8);
            cLay.spacing = 2;
            cLay.childControlWidth = true;
            cLay.childControlHeight = true;

            _logLabel = CreateLabel("LogText", contentGo.transform, "",
                                    fontSize: 11, bold: false, alignment: TextAnchor.UpperLeft);
            _logLabel.color = new Color(0.85f, 0.85f, 0.85f);

            var sr = svGo.GetComponent<ScrollRect>();
            sr.horizontal = false;
            sr.vertical = true;
            sr.viewport = vpRt;
            sr.content = cRt;
            return sr;
        }

        // ============================================================================
        // Logging + state
        // ============================================================================

        private void AppendLog(string message)
        {
            string stamp = DateTime.UtcNow.ToString("HH:mm:ss.fff");
            string line = $"[{stamp}] {message}";
            _logLines.Enqueue(line);
            while (_logLines.Count > MaxLogLines) _logLines.Dequeue();
            if (_logLabel != null) _logLabel.text = string.Join("\n", _logLines);
            if (_logScroll != null) _logScroll.verticalNormalizedPosition = 0f; // scroll to bottom
            Debug.Log($"[SampleApp] {message}");
        }

        private void SetStatus(string s)
        {
            if (_statusLabel != null) _statusLabel.text = s;
            AppendLog($"status: {s}");
        }

        private async Task DumpStateAsync(string header)
        {
            AppendLog($"---- state dump [{header}] ----");
            try { AppendLog($"  config.sdkVersion         = {await EC.GetSdkVersion()}"); }
            catch (Exception ex) { AppendLog($"  config.sdkVersion         ERR {ex.Message}"); }

            try { AppendLog($"  config.applicationCode    = {await EC.GetApplicationCode()}"); }
            catch (Exception ex) { AppendLog($"  config.applicationCode    ERR {ex.Message}"); }

            try { AppendLog($"  config.clientId           = {await EC.GetClientId()}"); }
            catch (Exception ex) { AppendLog($"  config.clientId           ERR {ex.Message}"); }

            try { AppendLog($"  setup.isEnabled           = {await EC.IsEnabled()}"); }
            catch (Exception ex) { AppendLog($"  setup.isEnabled           ERR {ex.Message}"); }

            AppendLog($"  inApp.isPaused            = {EC.IsInAppPaused()}");
            AppendLog($"---- end state dump [{header}] ----");
        }

        private void OnSdkEvent(SdkEvent evt)
        {
            switch (evt)
            {
                case SdkEvent.AppEvent ae:
                    AppendLog($"EVENT AppEvent name={ae.Name} payload={ae.PayloadJson ?? "null"}");
                    break;
                case SdkEvent.BadgeCountEvent bc:
                    AppendLog($"EVENT BadgeCountEvent count={bc.BadgeCount} method={bc.Method}");
                    break;
                default:
                    AppendLog($"EVENT type={evt.Type}");
                    break;
            }
        }

        // ============================================================================
        // Button actions
        // ============================================================================

        private async Task OnEnable()
        {
            SetStatus($"Enabling {APPLICATION_CODE}…");
            try
            {
                await EC.Setup(APPLICATION_CODE);
                SetStatus("SDK enabled.");
            }
            catch (SdkAlreadyEnabledException)
            {
                SetStatus("SDK already enabled (persisted).");
            }
            catch (EngagementCloudException ex)
            {
                SetStatus($"Enable failed: {ex.KotlinType} — {ex.Message}");
            }
            await DumpStateAsync("after enable");
            // If the inline view failed to open before Enable (SDK wasn't ready), retry now.
            if (_inlineView != null)
            {
                _inlineView.enabled = false;
                _inlineView.enabled = true;
            }
        }

        private async Task OnDisable()
        {
            SetStatus("Disabling SDK…");
            try
            {
                await EC.Disable();
                SetStatus("SDK disabled.");
            }
            catch (EngagementCloudException ex)
            {
                SetStatus($"Disable failed: {ex.KotlinType} — {ex.Message}");
            }
            await DumpStateAsync("after disable");
        }

        private async Task OnLink()
        {
            SetStatus($"Linking {CONTACT_EMAIL}…");
            try
            {
                await EC.LinkContact(CONTACT_EMAIL);
                SetStatus($"Linked {CONTACT_EMAIL}.");
            }
            catch (EngagementCloudException ex)
            {
                SetStatus($"Link failed: {ex.KotlinType} — {ex.Message}");
            }
            await DumpStateAsync("after link");
        }

        private async Task Track(string eventName)
        {
            SetStatus($"Tracking '{eventName}'…");
            try
            {
                await EC.TrackEvent(eventName);
                SetStatus($"Tracked '{eventName}'.");
            }
            catch (EngagementCloudException ex)
            {
                SetStatus($"Track '{eventName}' failed: {ex.KotlinType} — {ex.Message}");
            }
        }

        private async Task OnPause()
        {
            SetStatus("Pausing in-app…");
            try
            {
                await EC.PauseInApp();
                SetStatus($"inApp paused (isPaused={EC.IsInAppPaused()})");
            }
            catch (EngagementCloudException ex)
            {
                SetStatus($"Pause failed: {ex.KotlinType} — {ex.Message}");
            }
        }

        private async Task OnResume()
        {
            SetStatus("Resuming in-app…");
            try
            {
                await EC.ResumeInApp();
                SetStatus($"inApp resumed (isPaused={EC.IsInAppPaused()})");
            }
            catch (EngagementCloudException ex)
            {
                SetStatus($"Resume failed: {ex.KotlinType} — {ex.Message}");
            }
        }

        private void OnClearLog()
        {
            _logLines.Clear();
            if (_logLabel != null) _logLabel.text = "";
            AppendLog("(log cleared)");
        }
    }
}
