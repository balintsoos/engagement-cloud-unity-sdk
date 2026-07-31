package com.sap.ec.mobileengage.inapp

import com.sap.ec.core.channel.SdkEventDistributorApi
import com.sap.ec.core.log.Logger
import com.sap.ec.event.SdkEvent
import com.sap.ec.mobileengage.inapp.presentation.InAppPresentationAnimation
import com.sap.ec.mobileengage.inapp.presentation.InAppPresentationMode
import com.sap.ec.mobileengage.inapp.presentation.InAppPresenterApi
import com.sap.ec.mobileengage.inapp.reporting.InAppLoadingMetric
import com.sap.ec.mobileengage.inapp.view.InAppViewApi
import com.sap.ec.mobileengage.inapp.webview.WebViewHolder
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.useContents
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import platform.AppKit.NSBackingStoreBuffered
import platform.AppKit.NSFloatingWindowLevel
import platform.AppKit.NSPanel
import platform.AppKit.NSScreen
import platform.AppKit.NSView
import platform.AppKit.NSViewHeightSizable
import platform.AppKit.NSViewWidthSizable
import platform.AppKit.NSWindowStyleMaskBorderless
import platform.AppKit.NSWindowStyleMaskNonactivatingPanel
import platform.CoreGraphics.CGRectMake

internal class MacosInAppPresenter(
    private val mainDispatcher: CoroutineDispatcher,
    private val sdkDispatcher: CoroutineDispatcher,
    private val sdkEventDistributor: SdkEventDistributorApi,
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
        val webView = (webViewHolder as MacosWebViewHolder).webView

        val panel = withContext(mainDispatcher) {
            val screen = NSScreen.mainScreen
                ?: (NSScreen.screens.firstOrNull() as? NSScreen)
            if (screen == null) {
                logger.error("No NSScreen available; cannot present in-app message")
                return@withContext null
            }

            val styleMask =
                NSWindowStyleMaskBorderless or NSWindowStyleMaskNonactivatingPanel
            val panel = NSPanel(
                contentRect = screen.frame,
                styleMask = styleMask,
                backing = NSBackingStoreBuffered,
                defer = false
            ).apply {
                setOpaque(false)
                setLevel(NSFloatingWindowLevel)
                setHidesOnDeactivate(false)
                setBecomesKeyOnlyIfNeeded(true)
            }

            val container: NSView = panel.contentView ?: return@withContext null
            val bounds = container.bounds
            val width: Double = bounds.useContents { size.width }
            val height: Double = bounds.useContents { size.height }
            (webView as NSView).setFrame(CGRectMake(0.0, 0.0, width, height))
            webView.setAutoresizingMask(NSViewWidthSizable or NSViewHeightSizable)
            container.addSubview(webView)

            panel.orderFrontRegardless()
            panel
        } ?: return

        sdkEventDistributor.registerEvent(
            SdkEvent.Internal.InApp.Viewed(
                trackingInfo = inAppView.inAppMessage.trackingInfo,
                attributes = null
            )
        )

        CoroutineScope(sdkDispatcher).launch {
            sdkEventDistributor.sdkEventFlow.first {
                it is SdkEvent.Internal.Sdk.Dismiss && it.id == inAppView.inAppMessage.dismissId
            }

            withContext(mainDispatcher) {
                webView.removeFromSuperview()
                panel.orderOut(null)
                panel.close()
            }
        }
    }
}
