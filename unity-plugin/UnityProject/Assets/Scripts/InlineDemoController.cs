using System;
using System.Threading.Tasks;
using EngagementCloud;
using UnityEngine;
using UnityEngine.UI;
using EC = EngagementCloud.EngagementCloud;

namespace EngagementCloudSamples
{
    /// <summary>
    /// Minimal "show me the inline in-app inside Unity" demo. Constructs a single big
    /// <see cref="RawImage"/> in the middle of the screen, attaches a
    /// <see cref="UnityInAppTextureView"/> pointed at viewId <c>"ia"</c>, and \u2014 if the SDK is
    /// not yet enabled (typical for a fresh Editor session) \u2014 wires an "Enable &amp; Load" button
    /// that calls <c>Setup + LinkContact</c> and then flips the texture view on.
    ///
    /// The SDK's enabled state persists in <c>~/Library/Preferences/sap-sdk.plist</c>
    /// (NSUserDefaults suite <c>sap-sdk</c>), which is shared with the macOS sample and any
    /// other consumer on the same user account. So in most repeat runs, the SDK will report
    /// itself as enabled at boot and the inline view just appears without pressing anything.
    /// </summary>
    public sealed class InlineDemoController : MonoBehaviour
    {
        private const string APPLICATION_CODE = "EMSE3-B4341";
        private const string CONTACT_EMAIL    = "test1@test.com";
        private const string INLINE_VIEW_ID   = "ia";
        private const int    INLINE_W         = 900;
        private const int    INLINE_H         = 560;

        private RawImage _rawImage;
        private UnityInAppTextureView _textureView;
        private Text _statusLabel;
        private Button _enableButton;

        private async void Start()
        {
            BuildUI();
            await CheckAndLoadAsync();
        }

        private void BuildUI()
        {
            // Canvas ----------------------------------------------------------------
            var canvasGo = new GameObject("Canvas");
            var canvas = canvasGo.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 0;
            var scaler = canvasGo.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1280, 800);
            canvasGo.AddComponent<GraphicRaycaster>();

            // Central column layout (top-to-bottom: title / inline image / status / enable button)
            var column = new GameObject("Column", typeof(RectTransform), typeof(VerticalLayoutGroup));
            column.transform.SetParent(canvasGo.transform, worldPositionStays: false);
            var colRt = (RectTransform)column.transform;
            colRt.anchorMin = new Vector2(0.5f, 0.5f);
            colRt.anchorMax = new Vector2(0.5f, 0.5f);
            colRt.pivot     = new Vector2(0.5f, 0.5f);
            colRt.sizeDelta = new Vector2(INLINE_W + 40, INLINE_H + 160);
            var vlg = column.GetComponent<VerticalLayoutGroup>();
            vlg.padding = new RectOffset(16, 16, 16, 16);
            vlg.spacing = 12;
            vlg.childAlignment = TextAnchor.MiddleCenter;
            vlg.childControlWidth = true;
            vlg.childControlHeight = false;
            vlg.childForceExpandWidth = false;

            // Title -----------------------------------------------------------------
            var title = MakeLabel(column.transform, "Inline in-app  (viewId = \"ia\")",
                                  size: 22, bold: true, color: Color.white);
            var titleLayout = title.gameObject.AddComponent<LayoutElement>();
            titleLayout.preferredHeight = 34;

            // Inline image container ----------------------------------------------
            var imageGo = new GameObject("InlineImage",
                typeof(RectTransform), typeof(CanvasRenderer), typeof(RawImage),
                typeof(LayoutElement), typeof(Outline));
            imageGo.transform.SetParent(column.transform, worldPositionStays: false);
            _rawImage = imageGo.GetComponent<RawImage>();
            _rawImage.color = Color.white;
            _rawImage.raycastTarget = true;
            var imgLayout = imageGo.GetComponent<LayoutElement>();
            imgLayout.preferredWidth  = INLINE_W;
            imgLayout.preferredHeight = INLINE_H;
            imgLayout.flexibleWidth  = 0;
            imgLayout.flexibleHeight = 0;
            // Subtle outline so an empty (pre-load) rectangle is still visible against the
            // camera's dark background.
            var outline = imageGo.GetComponent<Outline>();
            outline.effectColor = new Color(1f, 1f, 1f, 0.3f);
            outline.effectDistance = new Vector2(2, -2);

            // Attach the plugin texture view, but leave it disabled until we know the SDK
            // is enabled \u2014 otherwise its OnEnable would throw MissingApplicationCode.
            _textureView = imageGo.AddComponent<UnityInAppTextureView>();
            _textureView.viewId = INLINE_VIEW_ID;
            _textureView.width  = INLINE_W;
            _textureView.height = INLINE_H;
            _textureView.enabled = false;

            // Status label ---------------------------------------------------------
            _statusLabel = MakeLabel(column.transform, "checking SDK state\u2026",
                                     size: 14, bold: false,
                                     color: new Color(0.85f, 0.85f, 0.85f));
            var statusLayout = _statusLabel.gameObject.AddComponent<LayoutElement>();
            statusLayout.preferredHeight = 24;

            // Enable button (hidden by default; shown if SDK isn't enabled yet) ---
            var btnGo = new GameObject("EnableButton",
                typeof(RectTransform), typeof(CanvasRenderer),
                typeof(Image), typeof(Button), typeof(LayoutElement));
            btnGo.transform.SetParent(column.transform, worldPositionStays: false);
            var btnLayout = btnGo.GetComponent<LayoutElement>();
            btnLayout.preferredWidth  = 320;
            btnLayout.preferredHeight = 40;
            var btnImg = btnGo.GetComponent<Image>();
            btnImg.color = new Color(0.20f, 0.55f, 0.85f);
            _enableButton = btnGo.GetComponent<Button>();
            _enableButton.onClick.AddListener(async () => await OnEnableClickAsync());
            var btnLabel = MakeLabel(btnGo.transform,
                                     $"Enable SDK & load \"{INLINE_VIEW_ID}\"",
                                     size: 15, bold: true, color: Color.white);
            var brt = (RectTransform)btnLabel.transform;
            brt.anchorMin = Vector2.zero; brt.anchorMax = Vector2.one;
            brt.offsetMin = Vector2.zero; brt.offsetMax = Vector2.zero;
            btnLabel.alignment = TextAnchor.MiddleCenter;
            btnGo.SetActive(false); // hidden until we confirm the SDK isn't enabled
        }

        private static Text MakeLabel(Transform parent, string text, int size, bool bold, Color color)
        {
            var go = new GameObject("Label", typeof(RectTransform), typeof(CanvasRenderer), typeof(Text));
            go.transform.SetParent(parent, worldPositionStays: false);
            var t = go.GetComponent<Text>();
            t.text = text;
            t.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            t.fontSize = size;
            t.fontStyle = bold ? FontStyle.Bold : FontStyle.Normal;
            t.color = color;
            t.alignment = TextAnchor.MiddleCenter;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            return t;
        }

        // ============================================================================
        // Flow: check enabled → if yes, flip the texture view on; if not, show the button.
        // ============================================================================

        private async Task CheckAndLoadAsync()
        {
            SetStatus("checking SDK\u2026");
            bool enabled;
            try
            {
                enabled = await EC.IsEnabled();
            }
            catch (Exception ex)
            {
                SetStatus($"IsEnabled failed: {ex.Message}");
                _enableButton?.gameObject.SetActive(true);
                return;
            }

            if (enabled)
            {
                SetStatus("SDK enabled \u2014 loading inline\u2026");
                _textureView.enabled = true;
                await Task.Delay(250);
                SetStatus($"inline \"{INLINE_VIEW_ID}\" loaded  \u2014  click the message to interact");
            }
            else
            {
                SetStatus("SDK not enabled yet");
                _enableButton?.gameObject.SetActive(true);
            }
        }

        private async Task OnEnableClickAsync()
        {
            _enableButton.interactable = false;
            SetStatus($"enabling SDK ({APPLICATION_CODE})\u2026");
            try
            {
                await EC.Setup(APPLICATION_CODE);
                SetStatus($"enabled  \u2014  linking {CONTACT_EMAIL}\u2026");
                try { await EC.LinkContact(CONTACT_EMAIL); } catch { /* non-fatal */ }
                SetStatus("linked  \u2014  loading inline\u2026");
                _textureView.enabled = true;
                _enableButton.gameObject.SetActive(false);
                await Task.Delay(250);
                SetStatus($"inline \"{INLINE_VIEW_ID}\" loaded  \u2014  click the message to interact");
            }
            catch (SdkAlreadyEnabledException)
            {
                SetStatus("SDK already enabled \u2014 loading inline\u2026");
                _textureView.enabled = true;
                _enableButton.gameObject.SetActive(false);
            }
            catch (EngagementCloudException ex)
            {
                SetStatus($"enable failed: {ex.KotlinType} \u2014 {ex.Message}");
                _enableButton.interactable = true;
            }
        }

        private void SetStatus(string s)
        {
            if (_statusLabel != null) _statusLabel.text = s;
            Debug.Log($"[InlineDemo] {s}");
        }
    }
}
