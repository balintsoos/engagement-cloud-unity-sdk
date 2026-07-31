using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace EngagementCloud
{
    /// <summary>
    /// Drops onto a <see cref="RawImage"/> to display an inline in-app message inside a Unity
    /// scene. Handles the full lifecycle:
    /// <list type="bullet">
    ///   <item><description>opens an <see cref="InlineInAppView"/> for <see cref="viewId"/> on <c>OnEnable</c>,</description></item>
    ///   <item><description>polls the shim for new snapshots each <c>LateUpdate</c>,</description></item>
    ///   <item><description>forwards Unity pointer events (mouse and touch, both Input Systems) to the offscreen WKWebView,</description></item>
    ///   <item><description>disposes on <c>OnDisable</c> / <c>OnDestroy</c>.</description></item>
    /// </list>
    /// The <see cref="RawImage"/>'s texture is (re)assigned when the underlying inline view
    /// finishes loading; leave the field's <c>texture</c> null in the inspector.
    /// </summary>
    [RequireComponent(typeof(RawImage))]
    [AddComponentMenu("SAP Engagement Cloud/Inline In-App Texture View")]
    public sealed class UnityInAppTextureView : MonoBehaviour,
        IPointerDownHandler, IPointerUpHandler, IPointerMoveHandler, IPointerExitHandler
    {
        [Tooltip("viewId to render, e.g. \"ia\". Must match a configured inline campaign under the SDK's applicationCode.")]
        public string viewId = "ia";

        [Tooltip("Offscreen render size in pixels. Larger values look sharper but cost more per snapshot.")]
        public int width = 512;

        [Tooltip("Same as width.")]
        public int height = 512;

        [Tooltip("Automatically dispose and re-open when the component re-enables. Useful in Editor when the viewId changes at runtime.")]
        public bool reopenOnEnable = true;

        private InlineInAppView _view;
        private RawImage _raw;
        private bool _loading;

        private void Reset()
        {
            var r = GetComponent<RawImage>();
            if (r != null) r.color = Color.white;
        }

        private void Awake()
        {
            _raw = GetComponent<RawImage>();
        }

        private async void OnEnable()
        {
            if (_view != null && !reopenOnEnable) return;
            await OpenAsync();
        }

        private void OnDisable()
        {
            Close();
        }

        private void OnDestroy()
        {
            Close();
        }

        private async Task OpenAsync()
        {
            if (_loading) return;
            _loading = true;
            try
            {
                Close(); // idempotent: no-op if nothing is open
                _view = await InlineInAppView.Open(viewId, width, height);
                if (_raw != null) _raw.texture = _view.Texture;
                Debug.Log($"[UnityInAppTextureView] opened viewId=\"{viewId}\" ({width}x{height})");
            }
            catch (EngagementCloudException ex)
            {
                Debug.LogWarning($"[UnityInAppTextureView] open failed for viewId=\"{viewId}\": {ex.KotlinType} — {ex.Message}");
            }
            catch (System.Exception ex)
            {
                Debug.LogError($"[UnityInAppTextureView] open failed for viewId=\"{viewId}\": {ex.Message}");
            }
            finally
            {
                _loading = false;
            }
        }

        private void Close()
        {
            if (_view == null) return;
            if (_raw != null) _raw.texture = null;
            _view.Dispose();
            _view = null;
        }

        // Poll for new frames in LateUpdate so any GameObject mutations from Update finish
        // first \u2014 we want the visual on the same frame the game's UI settled on.
        private void LateUpdate()
        {
            _view?.Poll();
        }

        // -- Pointer forwarding ---------------------------------------------------

        /// <summary>
        /// Translate a Unity <see cref="PointerEventData"/> to offscreen-WKWebView pixel coords.
        /// <c>RawImage</c>'s RectTransform is our reference frame; the WKWebView renders at
        /// (width, height) pixels regardless of RectTransform size, so we scale by the ratio.
        /// </summary>
        private bool TryPointerToWebView(PointerEventData e, out float x, out float y)
        {
            x = 0f; y = 0f;
            if (_view == null || _raw == null) return false;
            var rt = _raw.rectTransform;
            if (!RectTransformUtility.ScreenPointToLocalPointInRectangle(rt, e.position, e.pressEventCamera, out Vector2 local))
            {
                return false;
            }
            // local is centred on the rect (Unity convention: y grows up). Convert to
            // normalised 0..1 with top-left origin, then to WKWebView pixel coords.
            Rect r = rt.rect;
            float u =        (local.x - r.xMin) / r.width;
            float v = 1f - ((local.y - r.yMin) / r.height);
            if (u < 0f || u > 1f || v < 0f || v > 1f) return false;
            x = u * width;
            y = v * height;
            return true;
        }

        public void OnPointerDown(PointerEventData e)
        {
            if (TryPointerToWebView(e, out float x, out float y))
            {
                _view.SendPointer(InlineInAppView.PointerKind.Down, x, y);
            }
        }

        public void OnPointerUp(PointerEventData e)
        {
            if (TryPointerToWebView(e, out float x, out float y))
            {
                _view.SendPointer(InlineInAppView.PointerKind.Up, x, y);
            }
        }

        public void OnPointerMove(PointerEventData e)
        {
            if (TryPointerToWebView(e, out float x, out float y))
            {
                _view.SendPointer(InlineInAppView.PointerKind.Move, x, y);
            }
        }

        public void OnPointerExit(PointerEventData e)
        {
            // Send a move event to a coord outside the view so WKWebView clears any hover state.
            _view?.SendPointer(InlineInAppView.PointerKind.Move, -1f, -1f);
        }
    }
}
