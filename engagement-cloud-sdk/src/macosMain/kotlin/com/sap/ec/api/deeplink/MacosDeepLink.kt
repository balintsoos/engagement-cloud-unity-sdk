package com.sap.ec.api.deeplink

import com.sap.ec.di.SdkKoinIsolationContext.koin
import io.ktor.http.Url
import platform.Foundation.NSUserActivity

interface MacosDeepLinkApi {
    fun track(userActivity: NSUserActivity): Boolean
}

class MacosDeepLink : MacosDeepLinkApi {
    override fun track(userActivity: NSUserActivity): Boolean {
        return userActivity.webpageURL?.absoluteString()?.let {
            koin.get<DeepLinkApi>().track(Url(it)).getOrNull()
        } ?: false
    }
}
