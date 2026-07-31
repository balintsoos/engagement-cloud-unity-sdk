using System;
using System.Threading.Tasks;
using EngagementCloud.Internal;
using UnityEngine;

namespace EngagementCloud
{
    /// <summary>
    /// Handle to a live inline in-app message rendered offscreen into a <see cref="Texture2D"/>.
    /// One instance == one <c>viewId</c> == one offscreen WKWebView backing it.
    ///
    /// Lifecycle:
    /// <list type="number">
    ///   <item><description><see cref="Open"/> \u2014 async: fetches the inline message, spins up the offscreen NSPanel, starts the shim's ~30 Hz snapshot loop.</description></item>
    ///   <item><description><see cref="Poll"/> \u2014 sync, cheap: called from a MonoBehaviour's <c>LateUpdate</c>. Uploads the new frame into the <see cref="Texture"/> only when the shim's monotonic version counter advances; a static inline in-app therefore costs one upload after load and then zero.</description></item>
    ///   <item><description><see cref="SendPointer"/> \u2014 sync: forwards a click / move to the offscreen WKWebView so the in-app's JS bridge (<c>me-close</c>, <c>me-trigger-event</c>, <c>openExternalLink</c>) fires normally.</description></item>
    ///   <item><description><see cref="Dispose"/> \u2014 tears the shim session down and destroys the <see cref="Texture"/>. Safe to call from any thread; the shim does its work on the AppKit main queue.</description></item>
    /// </list>
    ///
    /// The <see cref="Texture"/> is <see cref="TextureFormat.BGRA32"/> with top-left origin, matching
    /// the shim's snapshot output byte-for-byte \u2014 no swizzle, no Y-flip needed on the shader side.
    /// </summary>
    public sealed class InlineInAppView : IDisposable
    {
        /// <summary>The <c>viewId</c> passed to <see cref="Open"/>; matches the campaign target on the backend.</summary>
        public string ViewId { get; }

        /// <summary>Configured pixel width of the offscreen render.</summary>
        public int Width { get; }

        /// <summary>Configured pixel height of the offscreen render.</summary>
        public int Height { get; }

        /// <summary>
        /// GPU-side texture that mirrors the offscreen WKWebView. Assign to a
        /// <see cref="UnityEngine.UI.RawImage.texture"/> (or any other consumer) to display it
        /// inside a Unity scene. Never null after a successful <see cref="Open"/>; becomes null
        /// after <see cref="Dispose"/>.
        /// </summary>
        public Texture2D Texture { get; private set; }

        /// <summary>Non-null after Dispose to prevent accidental reuse.</summary>
        private bool _disposed;

        /// <summary>Shim frame-version counter. Rising ⇒ we should re-upload.</summary>
        private long _lastVersion;

        private InlineInAppView(string viewId, int width, int height)
        {
            ViewId = viewId;
            Width = width;
            Height = height;
            // BGRA32 == shim BGRA8 little-endian premultiplied. mipChain: false, linear: false so
            // the default Unity UI shader treats the pixels as sRGB (WebKit hands us sRGB).
            Texture = new Texture2D(width, height, TextureFormat.BGRA32, mipChain: false, linear: false)
            {
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp,
                name = $"InlineInApp[{viewId}]"
            };
        }

        /// <summary>
        /// Fetch the inline in-app for <paramref name="viewId"/> and start rendering it into a
        /// <see cref="Texture2D"/> of <paramref name="width"/> x <paramref name="height"/>
        /// pixels. Throws <see cref="EngagementCloudException"/> if the backend returned no
        /// message (typed as <c>NotFound</c>) or if the SDK isn't ready.
        /// </summary>
        public static async Task<InlineInAppView> Open(string viewId, int width, int height)
        {
            if (string.IsNullOrEmpty(viewId)) throw new ArgumentException("viewId required", nameof(viewId));
            if (width <= 0 || height <= 0)  throw new ArgumentOutOfRangeException(nameof(width), "width and height must be positive");

            EngagementCloud.EnsureSinksInstalledInternal();
            var (id, tcs) = RequestRegistry.Register();
            NativeBridge.ec_inline_open(id, viewId, width, height, NativeCallbacks.CompletionThunk);
            await tcs.Task; // throws EngagementCloudException on failure
            return new InlineInAppView(viewId, width, height);
        }

        /// <summary>
        /// Copy the shim's latest snapshot into <see cref="Texture"/> if the shim reports a
        /// version we haven't seen. Returns <c>true</c> when an upload happened. Safe to call
        /// every frame; caller-cheap when no new frame is ready.
        /// </summary>
        public bool Poll()
        {
            if (_disposed || Texture == null) return false;
            if (NativeBridge.ec_inline_lockFrame(ViewId, out IntPtr buf, out int w, out int h, out int stride, out long version) == 0)
            {
                return false;
            }
            if (version <= _lastVersion) return false;
            _lastVersion = version;

            // Guard against an out-of-band resize on the shim side (shouldn't happen for a POC,
            // but future-proofing is cheap). Recreate the texture if the shim's reported size
            // stopped matching ours \u2014 the RawImage picks up the new instance next frame.
            if (w != Texture.width || h != Texture.height)
            {
                var old = Texture;
                Texture = new Texture2D(w, h, TextureFormat.BGRA32, mipChain: false, linear: false)
                {
                    filterMode = FilterMode.Bilinear,
                    wrapMode = TextureWrapMode.Clamp,
                    name = $"InlineInApp[{ViewId}]"
                };
                if (old != null) UnityEngine.Object.Destroy(old);
            }

            // Row-stride tolerant upload: LoadRawTextureData assumes tightly-packed bytes; when
            // the shim's stride equals width*4 (always in the POC), that's a straight blit.
            int rowBytes = w * 4;
            if (stride == rowBytes)
            {
                Texture.LoadRawTextureData(buf, rowBytes * h);
            }
            else
            {
                // Should never happen in POC \u2014 log once so we notice if it starts.
                Debug.LogWarning($"[EngagementCloud] InlineInAppView: stride {stride} != rowBytes {rowBytes}, ignoring frame");
                return false;
            }
            Texture.Apply(updateMipmaps: false, makeNoLongerReadable: false);
            return true;
        }

        /// <summary>Pointer kind constants matching the shim's <c>ec_inline_sendPointer</c> `kind` argument.</summary>
        public enum PointerKind
        {
            /// <summary>Cursor moved without a button down.</summary>
            Move = 0,
            /// <summary>Left mouse button went down.</summary>
            Down = 1,
            /// <summary>Left mouse button came up.</summary>
            Up   = 2,
        }

        /// <summary>
        /// Forward a pointer event to the offscreen WKWebView. Coordinates are in the
        /// inline view's pixel space, top-left origin.
        /// </summary>
        public void SendPointer(PointerKind kind, float x, float y)
        {
            if (_disposed) return;
            NativeBridge.ec_inline_sendPointer(ViewId, (int)kind, x, y);
        }

        /// <summary>Idempotent teardown \u2014 releases the shim session and destroys the texture.</summary>
        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            NativeBridge.ec_inline_close(ViewId);
            if (Texture != null)
            {
                UnityEngine.Object.Destroy(Texture);
                Texture = null;
            }
        }
    }
}
