package com.sap.ec.api.inapp

import com.sap.ec.di.SdkKoinIsolationContext.koin
import com.sap.ec.mobileengage.inapp.MacosWebViewHolder
import com.sap.ec.mobileengage.inapp.networking.download.InlineInAppMessageFetcherApi
import com.sap.ec.mobileengage.inapp.view.InAppViewProviderApi
import platform.WebKit.WKWebView

/**
 * macOS in-app messaging API. Unlike iOS, macOS does not expose Compose-based inline views:
 * Phase-1 skips Compose UI on macOS (decision #6). We do expose an alternative inline entry
 * point through [fetchInline] that returns a fully wired `WKWebView` — the Swift host adds it
 * to its own view hierarchy (any AppKit container works, e.g. `NSView`, `NSStackView`, etc.).
 *
 * Overlay in-app messages are still handled entirely by `MacosInAppPresenter` (WKWebView +
 * NSWindow) triggered by the shared `SdkEvent.Internal.Sdk.Dismiss` flow.
 */
interface MacosInAppApi {
    val isPaused: Boolean
    suspend fun pause()
    suspend fun resume()

    /**
     * Fetch an inline in-app message by [viewId] and return a fully-configured `WKWebView`
     * that renders the message content with the JS bridge attached (so `me-close`,
     * `me-trigger-event`, `openExternalLink`, etc. fire the same callbacks as an overlay
     * in-app).
     *
     * Returns `null` when the backend has no message for [viewId] (HTTP 204 or empty body),
     * when the SDK is disabled, or when the request fails; the caller can log the error and
     * retry later.
     *
     * Ownership of the returned `WKWebView` transfers to the caller — add it as a subview of
     * whatever `NSView` container you want. The message dismiss + button actions still route
     * through `SdkEventDistributor`, so `MacosInAppPresenter`'s dismiss handling does NOT run
     * for inline messages; the caller is responsible for removing the view when appropriate
     * (typically on `Sdk.Dismiss` observed via `EngagementCloud.events` or on an explicit
     * close callback of your choosing).
     */
    suspend fun fetchInline(viewId: String): WKWebView?
}

class MacosInApp : MacosInAppApi {
    override val isPaused: Boolean
        get() = koin.get<InAppApi>().isPaused

    override suspend fun pause() {
        koin.get<InAppApi>().pause()
    }

    override suspend fun resume() {
        koin.get<InAppApi>().resume()
    }

    override suspend fun fetchInline(viewId: String): WKWebView? {
        // The fetcher already handles "204 No Content", empty content, and network errors
        // by returning null; we just forward that. The returned InAppMessage already has
        // `type = InAppType.INLINE` set on the fetcher side (see InlineInAppMessageFetcher).
        val message = koin.get<InlineInAppMessageFetcherApi>().fetch(viewId) ?: return null

        // Reuse the same view provider used by the overlay path: same JS bridge, same content
        // replacer, same main-dispatcher handling inside `MacosInAppView.load`. The returned
        // holder is a `MacosWebViewHolder` on this target.
        val view = koin.get<InAppViewProviderApi>().provide()
        val holder = view.load(message) as MacosWebViewHolder
        return holder.webView
    }
}

