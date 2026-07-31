package com.sap.ec.api.inapp

import com.sap.ec.di.SdkKoinIsolationContext.koin

/**
 * macOS in-app messaging API. Unlike iOS, macOS does not expose an `InlineInAppViewController`:
 * inline Compose views are not part of Phase-1 parity (decision #6). In-app messages are
 * presented via `MacosInAppPresenter` (WKWebView + NSWindow) triggered by the same
 * `SdkEvent.Internal.Sdk.Dismiss` flow as iOS.
 */
interface MacosInAppApi {
    val isPaused: Boolean
    suspend fun pause()
    suspend fun resume()
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
}
