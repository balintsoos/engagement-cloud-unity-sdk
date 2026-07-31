package com.sap.ec.init.states

import com.sap.ec.context.SdkContextApi
import com.sap.ec.core.log.Logger
import com.sap.ec.core.networking.context.RequestContextApi
import com.sap.ec.core.state.State
import com.sap.ec.core.storage.StringStorageApi

@Suppress("EXPECT_ACTUAL_CLASSIFIERS_ARE_IN_BETA_WARNING")
internal actual class LegacySDKMigrationState(
    @Suppress("UNUSED_PARAMETER") requestContext: RequestContextApi,
    @Suppress("UNUSED_PARAMETER") sdkContext: SdkContextApi,
    @Suppress("UNUSED_PARAMETER") stringStorage: StringStorageApi,
    @Suppress("UNUSED_PARAMETER") sdkLogger: Logger
) : State {
    // No legacy macOS SDK exists — nothing to migrate. Kept as an inert state so
    // the initialization pipeline can register it uniformly across platforms.
    actual override val name: String = "legacySDKMigrationState"

    actual override fun prepare() {}
    actual override suspend fun active(): Result<Unit> = Result.success(Unit)
    actual override fun relax() {}
}
