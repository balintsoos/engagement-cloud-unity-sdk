package com.sap.ec.unity

import com.sap.ec.core.log.Logger
import com.sap.ec.mobileengage.inapp.presentation.InAppPresentationAnimation
import com.sap.ec.mobileengage.inapp.presentation.InAppPresentationMode
import com.sap.ec.mobileengage.inapp.presentation.InAppPresenterApi
import com.sap.ec.mobileengage.inapp.reporting.InAppLoadingMetric
import com.sap.ec.mobileengage.inapp.view.InAppViewApi
import com.sap.ec.mobileengage.inapp.webview.WebViewHolder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * Unity-hosted presenter — swaps out the AppKit NSPanel presenter that
 * `engagement-cloud-sdk` ships by default with a texture-composited path.
 *
 * Real IOSurface/WKWebView rendering is implemented in the shim (Section C
 * of the phase-2 plan); this Kotlin class is the Koin-visible interface and
 * shell. When the shim's `EcInAppTexturePresenter` is wired up, `present`
 * will hand the `WebViewHolder`'s `WKWebView` to the shim via an Obj-C
 * callback exposed on `UnityBridge`.
 */
internal class UnityMacosInAppPresenter(
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

    override suspend fun present(
        inAppView: InAppViewApi,
        webViewHolder: WebViewHolder,
        mode: InAppPresentationMode,
        animation: InAppPresentationAnimation?
    ) {
        // Section C of the phase-2 plan implements the IOSurface presenter.
        // Until then, the shim's presenter callback is not yet wired, so this
        // is intentionally a no-op that only records that presentation was
        // requested. Direct callers of the SDK who don't set up the Unity
        // override still get the AppKit NSPanel presenter — this class only
        // runs when the shim has explicitly loaded the unity override module.
        logger.debug(
            "UnityMacosInAppPresenter.present called (mode=$mode) — texture-presenter not yet wired"
        )
    }
}
