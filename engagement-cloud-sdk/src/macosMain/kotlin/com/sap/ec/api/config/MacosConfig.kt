package com.sap.ec.api.config

import com.sap.ec.api.SdkState
import kotlin.coroutines.cancellation.CancellationException

/**
 * macOS Config API — mirrors [com.sap.ec.api.config.IosConfigApi] minus `getNotificationSettings`,
 * which is coupled to push permissions and therefore deferred in Phase 1 (decision #5).
 */
interface MacosConfigApi {
    suspend fun getApplicationCode(): String?
    suspend fun getClientId(): String
    suspend fun getLanguageCode(): String
    suspend fun getApplicationVersion(): String
    suspend fun getSdkVersion(): String
    suspend fun getCurrentSdkState(): SdkState

    @Throws(CancellationException::class)
    suspend fun changeApplicationCode(applicationCode: String)

    @Throws(CancellationException::class)
    suspend fun setLanguage(language: String)

    @Throws(CancellationException::class)
    suspend fun resetLanguage()
}

internal class MacosConfig(
    private val configApi: ConfigApi
) : MacosConfigApi {

    override suspend fun getApplicationCode(): String? = configApi.getApplicationCode()
    override suspend fun getClientId(): String = configApi.getClientId()
    override suspend fun getLanguageCode(): String = configApi.getLanguageCode()
    override suspend fun getApplicationVersion(): String = configApi.getApplicationVersion()
    override suspend fun getSdkVersion(): String = configApi.getSdkVersion()
    override suspend fun getCurrentSdkState(): SdkState = configApi.getCurrentSdkState()

    override suspend fun changeApplicationCode(applicationCode: String) {
        configApi.changeApplicationCode(applicationCode).getOrThrow()
    }

    override suspend fun setLanguage(language: String) {
        configApi.setLanguage(language).getOrThrow()
    }

    override suspend fun resetLanguage() {
        configApi.resetLanguage().getOrThrow()
    }
}
