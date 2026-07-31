using System;
using EngagementCloud.Internal;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
using UnityEngine.Rendering;
#endif

namespace EngagementCloud
{
    /// <summary>
    /// Displays the SDK's in-app messages as a <c>Texture2D</c> on a
    /// <c>RawImage</c>. Attach to a GameObject that has a <c>RawImage</c>
    /// component (typically a full-screen canvas panel). Pointer events on
    /// the <c>RawImage</c> are forwarded to the offscreen WKWebView via
    /// <see cref="NativeBridge.ec_inapp_input_send"/>.
    ///
    /// Texture pipeline:
    /// - On <c>Enable</c>, subscribe to <see cref="EngagementCloud.InAppFrameReceived"/>.
    ///   Each callback triggers a texture refresh — we call
    ///   <c>ec_inapp_texture_acquire</c> and, if the returned IOSurface
    ///   pointer changed, rebuild the external <c>Texture2D</c>. Otherwise
    ///   the same texture is already showing the fresh content (the surface
    ///   was updated in-place by the shim).
    /// - Editor / non-macOS: no-op — the native shim doesn't build.
    /// </summary>
    [RequireComponent(typeof(RawImage))]
    public sealed class UnityInAppTextureView : MonoBehaviour,
        IPointerDownHandler, IPointerUpHandler, IPointerMoveHandler
    {
        // Presenter viewport size — matches EcInAppTexturePresenter's default.
        // See the phase-2 plan Section C follow-up on dynamic sizing.
        private const int PresenterWidth = 1280;
        private const int PresenterHeight = 720;

        private RawImage _rawImage;
        private Texture2D _externalTexture;
        private IntPtr _lastSurfacePtr = IntPtr.Zero;

        private void Awake()
        {
            _rawImage = GetComponent<RawImage>();
        }

        private void OnEnable()
        {
            EngagementCloud.InAppFrameReceived += OnPresenterFrame;
            // Poll once at enable so users who show the panel BEFORE any
            // frame arrives get whatever the surface currently holds.
            RefreshTexture();
        }

        private void OnDisable()
        {
            EngagementCloud.InAppFrameReceived -= OnPresenterFrame;
        }

        private void OnDestroy()
        {
            if (_externalTexture != null)
            {
                Destroy(_externalTexture);
                _externalTexture = null;
            }
        }

        private void OnPresenterFrame(ulong frameIndex)
        {
            RefreshTexture();
        }

        private void RefreshTexture()
        {
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
            IntPtr surfacePtr = NativeBridge.ec_inapp_texture_acquire();
            if (surfacePtr == IntPtr.Zero) return;

            if (surfacePtr != _lastSurfacePtr)
            {
                // IOSurface pointer changed — rebuild the external texture.
                if (_externalTexture != null) Destroy(_externalTexture);
                _externalTexture = Texture2D.CreateExternalTexture(
                    PresenterWidth, PresenterHeight,
                    TextureFormat.BGRA32,
                    mipChain: false, linear: false,
                    surfacePtr);
                _lastSurfacePtr = surfacePtr;
                _rawImage.texture = _externalTexture;
            }
            else
            {
                // Same surface, updated in-place. Force the RawImage to
                // repaint (Unity doesn't know the pixels changed).
                _rawImage.SetMaterialDirty();
            }
#endif
        }

        // Pointer input --------------------------------------------------------
        // Translate from RawImage local coordinates (bottom-left origin, Unity
        // convention) to WebView pixel space (top-left origin) and forward.
        // See EcInAppTexturePresenter's sendInputKind for the receiving end.

        private const int KindMove = 0;
        private const int KindDown = 1;
        private const int KindUp = 2;

        private const int ButtonPrimary = 0x1;
        private const int ButtonSecondary = 0x2;

        public void OnPointerDown(PointerEventData eventData)
            => SendPointer(KindDown, eventData);

        public void OnPointerUp(PointerEventData eventData)
            => SendPointer(KindUp, eventData);

        public void OnPointerMove(PointerEventData eventData)
            => SendPointer(KindMove, eventData);

        private void SendPointer(int kind, PointerEventData eventData)
        {
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX
            var rect = _rawImage.rectTransform;
            if (!RectTransformUtility.ScreenPointToLocalPointInRectangle(
                    rect, eventData.position, eventData.pressEventCamera, out var local))
                return;

            // Local space has origin at RectTransform pivot. Map to (0,0)-(1,1).
            var size = rect.rect.size;
            var pivot = rect.pivot;
            float u = (local.x + pivot.x * size.x) / size.x;
            float v = (local.y + pivot.y * size.y) / size.y;
            if (u < 0f || u > 1f || v < 0f || v > 1f) return;

            // Convert to WebView pixel space with top-left origin (Unity v is
            // bottom-up; flip to top-down).
            double x = u * PresenterWidth;
            double y = (1.0 - v) * PresenterHeight;

            int buttons = 0;
            switch (eventData.button)
            {
                case PointerEventData.InputButton.Left:   buttons = ButtonPrimary; break;
                case PointerEventData.InputButton.Right:  buttons = ButtonSecondary; break;
                case PointerEventData.InputButton.Middle: buttons = ButtonPrimary; break;
            }
            NativeBridge.ec_inapp_input_send(kind, x, y, buttons);
#endif
        }
    }
}
