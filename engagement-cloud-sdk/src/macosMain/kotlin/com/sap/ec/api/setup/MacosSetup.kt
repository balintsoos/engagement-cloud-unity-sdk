package com.sap.ec.api.setup

import com.sap.ec.MacosEngagementCloudSDKConfig
import com.sap.ec.config.LinkContactData
import com.sap.ec.core.exceptions.SdkException.InvalidApplicationCodeException
import com.sap.ec.core.exceptions.SdkException.SdkAlreadyDisabledException
import com.sap.ec.core.exceptions.SdkException.SdkAlreadyEnabledException
import com.sap.ec.core.storage.StorageConstants
import com.sap.ec.core.storage.TypedStorageApi
import com.sap.ec.core.wrapper.WrapperInfo
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

    /**
     * Records the identity of a platform wrapper hosting the SDK (e.g. "unity",
     * "react-native"). Must be called before [enable] so the wrapper identity is
     * present on the very first outbound request.
     *
     * Persisted via [TypedStorageApi] under [StorageConstants.WRAPPER_INFO_KEY];
     * read by `DeviceInfoCollector` on every device-info build.
     */
    suspend fun setPlatformWrapper(name: String, version: String)
}

internal class MacosSetup(
    private val setup: SetupApi,
    private val wrapperInfoStorage: TypedStorageApi
) : MacosSetupApi {

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

    override suspend fun setPlatformWrapper(name: String, version: String) {
        wrapperInfoStorage.put(
            StorageConstants.WRAPPER_INFO_KEY,
            WrapperInfo.serializer(),
            WrapperInfo(platformWrapper = name, wrapperVersion = version)
        )
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
