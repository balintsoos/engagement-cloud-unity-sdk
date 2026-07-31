package com.sap.ec.mobileengage.inapp

import com.sap.ec.core.log.Logger
import com.sap.ec.mobileengage.inapp.presentation.InAppPresentationAnimation
import com.sap.ec.mobileengage.inapp.presentation.InAppPresentationMode
import com.sap.ec.mobileengage.inapp.presentation.InAppPresenterApi
import com.sap.ec.mobileengage.inapp.reporting.InAppLoadingMetric
import com.sap.ec.mobileengage.inapp.view.InAppViewApi
import com.sap.ec.mobileengage.inapp.webview.WebViewHolder
import kotlinx.coroutines.CoroutineDispatcher

/**
 * Section E stub — full AppKit + WKWebView implementation is deferred to a follow-up commit.
 *
 * The intended shape (per the Phase-1 plan):
 * - Host a `WKWebView` inside an `NSWindow` (or `NSPanel`) overlay via AppKit layout constraints.
 * - Present / dismiss keyed off `SdkEvent.Internal.Sdk.Dismiss`, the same trigger the iOS
 *   `IosInAppPresenter` uses.
 * - Reuse the common JS-bridge, content replacer, downloader, and metrics unchanged.
 *
 * Left as a TODO because implementing it correctly requires iterating on the actual macOS
 * runtime (main thread / run-loop timing vs. iOS UIWindow model) — see the "Open implementation
 * risks" section of `Unity-sdk-phase1-plan.md`.
 */
internal class MacosInAppPresenter(
    @Suppress("UNUSED_PARAMETER") mainDispatcher: CoroutineDispatcher,
    @Suppress("UNUSED_PARAMETER") sdkDispatcher: CoroutineDispatcher,
    private val logger: Logger
) : InAppPresenterApi {

    override suspend fun trackMetric(
        trackingInfo: String,
        loadingMetric: InAppLoadingMetric,
        onScreenTimeStart: Long,
        onScreenTimeEnd: Long
    ) {
        logger.debug("MacosInAppPresenter.trackMetric is a stub (Section E TODO)")
    }

    override suspend fun present(
        inAppView: InAppViewApi,
        webViewHolder: WebViewHolder,
        mode: InAppPresentationMode,
        animation: InAppPresentationAnimation?
    ) {
        logger.debug("MacosInAppPresenter.present is a stub (Section E TODO)")
        // TODO(macos-inapp): host WKWebView in an NSWindow overlay and listen for Dismiss.
    }
}

