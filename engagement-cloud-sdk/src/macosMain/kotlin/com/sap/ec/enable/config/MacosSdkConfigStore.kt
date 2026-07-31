package com.sap.ec.enable.config

import com.sap.ec.MacosEngagementCloudSDKConfig
import com.sap.ec.config.SdkConfig
import com.sap.ec.core.storage.StorageConstants
import com.sap.ec.core.storage.TypedStorageApi
import kotlinx.serialization.KSerializer

internal class MacosSdkConfigStore(
    override val typedStorage: TypedStorageApi
) : SdkConfigStoreApi<MacosEngagementCloudSDKConfig> {
    override val deserializer: KSerializer<MacosEngagementCloudSDKConfig> =
        MacosEngagementCloudSDKConfig.serializer()

    override suspend fun store(config: SdkConfig) {
        typedStorage.put(
            StorageConstants.SDK_CONFIG_STORAGE_KEY,
            MacosEngagementCloudSDKConfig.serializer(),
            config as MacosEngagementCloudSDKConfig
        )
    }

    override suspend fun clear() {
        typedStorage.remove(StorageConstants.SDK_CONFIG_STORAGE_KEY)
    }
}
