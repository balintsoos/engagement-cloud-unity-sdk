package com.sap.ec.core.url

import com.sap.ec.core.log.Logger
import com.sap.ec.mobileengage.action.models.OpenExternalUrlActionModel
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import platform.AppKit.NSWorkspace
import platform.Foundation.NSURL

/**
 * macOS replacement for `IosExternalUrlOpener` — uses `NSWorkspace.openURL` from AppKit
 * instead of iOS's `UIApplication.openURL`. The AppKit API is synchronous and returns a Bool.
 */
internal class MacosExternalUrlOpener(
    private val mainDispatcher: CoroutineDispatcher,
    private val sdkLogger: Logger
) : ExternalUrlOpenerApi {

    override suspend fun open(actionModel: OpenExternalUrlActionModel) {
        val nsUrl = NSURL(string = actionModel.url)
        val success = withContext(mainDispatcher) {
            NSWorkspace.sharedWorkspace.openURL(nsUrl)
        }
        if (!success) {
            sdkLogger.error(
                "MacosExternalUrlOpener",
                buildJsonObject {
                    put("message", JsonPrimitive("Failed to open url: ${actionModel.url}"))
                }
            )
        }
    }
}
