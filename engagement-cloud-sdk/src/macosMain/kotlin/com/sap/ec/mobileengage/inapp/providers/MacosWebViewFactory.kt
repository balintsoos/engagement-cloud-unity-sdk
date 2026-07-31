package com.sap.ec.mobileengage.inapp.providers

import com.sap.ec.core.factory.Factory
import com.sap.ec.mobileengage.inapp.InAppJsBridge
import com.sap.ec.mobileengage.inapp.jsbridge.InAppJsBridgeData
import com.sap.ec.mobileengage.inapp.presentation.InAppType
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.readValue
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import platform.CoreGraphics.CGRectZero
import platform.WebKit.WKProcessPool
import platform.WebKit.WKWebView
import platform.WebKit.WKWebViewConfiguration

internal class MacosWebViewFactory(
    private val mainDispatcher: CoroutineDispatcher,
    private val inAppJsBridgeFactory: Factory<InAppJsBridgeData, InAppJsBridge>
) : MacosWebViewFactoryApi {

    @OptIn(ExperimentalForeignApi::class)
    override suspend fun create(
        dismissId: String,
        trackingInfo: String,
        inAppType: InAppType
    ): WKWebView {
        return withContext(mainDispatcher) {
            val inAppJsBridge = inAppJsBridgeFactory.create(
                InAppJsBridgeData(
                    dismissId = dismissId,
                    trackingInfo = trackingInfo,
                    inAppType = inAppType
                )
            )
            // macOS WKWebView is an NSView subclass — unlike iOS it has no scrollView and no
            // contentInsetAdjustmentBehavior. HTML in-app messages paint their own background,
            // so no additional AppKit color tweaks are needed here.
            WKWebView(
                CGRectZero.readValue(),
                WKWebViewConfiguration().apply {
                    userContentController = inAppJsBridge.registerContentController()
                    setProcessPool(WKProcessPool())
                }
            )
        }
    }
}
