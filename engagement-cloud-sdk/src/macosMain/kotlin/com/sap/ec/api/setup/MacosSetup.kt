package com.sap.ec.api.setup

import com.sap.ec.MacosEngagementCloudSDKConfig
import com.sap.ec.config.LinkContactData
import com.sap.ec.core.exceptions.SdkException.InvalidApplicationCodeException
import com.sap.ec.core.exceptions.SdkException.SdkAlreadyDisabledException
import com.sap.ec.core.exceptions.SdkException.SdkAlreadyEnabledException
import io.ktor.utils.io.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import platform.Foundation.NSError
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

typealias OnContactLinkingFailed = (onSuccess: (LinkContactData?) -> Unit, onError: (NSError?) -> Unit) -> Unit

interface MacosSetupApi {
    @Throws(
        SdkAlreadyEnabledException::class,
        InvalidApplicationCodeException::class,
        CancellationException::class
    )
    suspend fun enable(
        config: MacosEngagementCloudSDKConfig,
        onContactLinkingFailed: OnContactLinkingFailed
    )

    @Throws(SdkAlreadyDisabledException::class, CancellationException::class)
    suspend fun disable()

    suspend fun isEnabled(): Boolean

    fun setOnContactLinkingFailedCallback(onContactLinkingFailed: OnContactLinkingFailed)
}

class MacosSetup(private val setup: SetupApi) : MacosSetupApi {

    override suspend fun enable(
        config: MacosEngagementCloudSDKConfig,
        onContactLinkingFailed: OnContactLinkingFailed
    ) {
        setup.enable(config, wrap(onContactLinkingFailed)).getOrThrow()
    }

    override suspend fun disable() {
        setup.disable().getOrThrow()
    }

    override suspend fun isEnabled(): Boolean = setup.isEnabled()

    override fun setOnContactLinkingFailedCallback(onContactLinkingFailed: OnContactLinkingFailed) {
        setup.setOnContactLinkingFailedCallback(wrap(onContactLinkingFailed))
    }

    private fun wrap(cb: OnContactLinkingFailed): suspend () -> LinkContactData? = suspend {
        suspendCancellableCoroutine { continuation ->
            cb(
                { continuation.resume(it) },
                { error ->
                    continuation.resumeWithException(
                        error?.let { RuntimeException(it.localizedDescription) }
                            ?: Exception("Unknown error in onContactLinkingFailedCallback")
                    )
                }
            )
        }
    }
}
