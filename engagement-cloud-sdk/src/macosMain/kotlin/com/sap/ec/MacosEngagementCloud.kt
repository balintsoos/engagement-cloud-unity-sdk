package com.sap.ec

import com.sap.ec.api.config.MacosConfigApi
import com.sap.ec.api.contact.MacosContactApi
import com.sap.ec.api.deeplink.MacosDeepLinkApi
import com.sap.ec.api.event.model.EngagementCloudEvent
import com.sap.ec.api.inapp.MacosInAppApi
import com.sap.ec.api.setup.MacosSetupApi
import com.sap.ec.api.tracking.MacosTrackingApi
import com.sap.ec.di.CoroutineScopeTypes
import com.sap.ec.di.EventFlowTypes
import com.sap.ec.di.SdkKoinIsolationContext
import com.sap.ec.di.SdkKoinIsolationContext.koin
import io.ktor.utils.io.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import org.koin.core.qualifier.named
import kotlin.experimental.ExperimentalObjCName

typealias EngagementCloudEventListener = (EngagementCloudEvent) -> Unit

/**
 * macOS entry point mirroring [com.sap.ec.IosEngagementCloud]. Excludes `push` and
 * `embeddedMessaging` per Phase-1 decisions #5 and #6.
 */
@OptIn(ExperimentalObjCName::class)
@ObjCName("EngagementCloud")
object MacosEngagementCloud {
    init {
        SdkKoinIsolationContext.init()
        koin.get<CoroutineScope>(named(CoroutineScopeTypes.Application))
            .launch(start = CoroutineStart.UNDISPATCHED) {
                koin.get<Flow<EngagementCloudEvent>>(named(EventFlowTypes.Public)).collect {
                    eventListeners.forEach { listener -> listener.invoke(it) }
                }
            }
    }

    private var eventListeners: MutableList<EngagementCloudEventListener> = mutableListOf()

    val events: Flow<EngagementCloudEvent>
        get() = koin.get<Flow<EngagementCloudEvent>>(named(EventFlowTypes.Public))

    val setup: MacosSetupApi
        get() = koin.get<MacosSetupApi>()
    val contact: MacosContactApi
        get() = koin.get<MacosContactApi>()
    val event: MacosTrackingApi
        get() = koin.get<MacosTrackingApi>()
    val inApp: MacosInAppApi
        get() = koin.get<MacosInAppApi>()
    val config: MacosConfigApi
        get() = koin.get<MacosConfigApi>()
    val deepLink: MacosDeepLinkApi
        get() = koin.get<MacosDeepLinkApi>()

    @Throws(CancellationException::class)
    suspend fun initialize() {
        EngagementCloud.initialize().getOrThrow()
        koin.get<CoroutineScope>(named(CoroutineScopeTypes.Application))
            .launch(start = CoroutineStart.UNDISPATCHED) {
                koin.get<Flow<EngagementCloudEvent>>(named(EventFlowTypes.Public)).collect {
                    eventListeners.forEach { listener -> listener.invoke(it) }
                }
            }
    }

    fun registerEventListener(listener: EngagementCloudEventListener) {
        eventListeners.add(listener)
    }
}
