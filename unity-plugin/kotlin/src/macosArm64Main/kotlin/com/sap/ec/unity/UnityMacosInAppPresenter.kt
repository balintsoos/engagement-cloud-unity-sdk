package com.sap.ec.unity

import com.sap.ec.core.log.Logger
import com.sap.ec.mobileengage.inapp.MacosWebViewHolder
import com.sap.ec.mobileengage.inapp.presentation.InAppPresentationAnimation
import com.sap.ec.mobileengage.inapp.presentation.InAppPresentationMode
import com.sap.ec.mobileengage.inapp.presentation.InAppPresenterApi
import com.sap.ec.mobileengage.inapp.reporting.InAppLoadingMetric
import com.sap.ec.mobileengage.inapp.view.InAppViewApi
import com.sap.ec.mobileengage.inapp.webview.WebViewHolder
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import platform.Foundation.NSClassFromString
import platform.Foundation.NSSelectorFromString
import platform.Foundation.performSelector
import platform.WebKit.WKWebView
import platform.darwin.NSObject

/**
 * Unity-hosted presenter. Replaces the AppKit NSPanel presenter (used by
 * direct SDK consumers) with a texture-composited path implemented in the
 * shim (`EcInAppTexturePresenter.mm`).
 *
 * Dispatch happens on the main dispatcher — WKWebView is main-thread-only.
 * The shim's presenter class is looked up dynamically via
 * `NSClassFromString("EcPresenterBridge")` because the Kotlin module has no
 * link-time dependency on the shim bundle (the arrow goes the other way).
 */
internal class UnityMacosInAppPresenter(
    private val mainDispatcher: CoroutineDispatcher,
    private val logger: Logger
) : InAppPresenterApi {

    override suspend fun trackMetric(
        trackingInfo: String,
        loadingMetric: InAppLoadingMetric,
        onScreenTimeStart: Long,
        onScreenTimeEnd: Long
    ) {
        logger.metric(
            message = "InAppMetric",
            data = buildJsonObject {
                put("trackingInfo", JsonPrimitive(trackingInfo))
                put("loadingTimeStart", JsonPrimitive(loadingMetric.loadingStarted))
                put("loadingTimeEnd", JsonPrimitive(loadingMetric.loadingEnded))
                put(
                    "loadingTimeDuration",
                    JsonPrimitive(loadingMetric.loadingEnded - loadingMetric.loadingStarted)
                )
                put("onScreenTimeStart", JsonPrimitive(onScreenTimeStart))
                put("onScreenTimeEnd", JsonPrimitive(onScreenTimeEnd))
                put(
                    "onScreenTimeDuration",
                    JsonPrimitive(onScreenTimeEnd - onScreenTimeStart)
                )
            }
        )
    }

    @OptIn(ExperimentalForeignApi::class)
    override suspend fun present(
        inAppView: InAppViewApi,
        webViewHolder: WebViewHolder,
        mode: InAppPresentationMode,
        animation: InAppPresentationAnimation?
    ) {
        val webView: WKWebView = (webViewHolder as? MacosWebViewHolder)?.webView
            ?: run {
                logger.error(
                    "UnityMacosInAppPresenter.present: expected MacosWebViewHolder, got ${webViewHolder::class.simpleName}"
                )
                return
            }

        withContext(mainDispatcher) {
            val bridge = NSClassFromString("EcPresenterBridge")
            if (bridge == null) {
                logger.error(
                    "UnityMacosInAppPresenter.present: EcPresenterBridge class not found — shim not loaded?"
                )
                return@withContext
            }
            (bridge as NSObject).performSelector(
                NSSelectorFromString("onPresentWebView:"),
                webView
            )
        }
        // Dismiss handling is deferred to the shim's caller: when the SDK's
        // event distributor fires `Sdk.Dismiss`, the C# runtime (or a future
        // Kotlin subscriber inside this module) will call
        // `EcPresenterBridge.onDismiss`. v1 relies on the C# side observing
        // the dismiss event and clearing the texture view.
    }
}
