package com.sap.ec.api.tracking

import com.sap.ec.api.event.model.TrackedEvent
import com.sap.ec.di.SdkKoinIsolationContext.koin
import com.sap.ec.tracking.TrackingApi
import io.ktor.utils.io.CancellationException

interface MacosTrackingApi {
    @Throws(CancellationException::class)
    suspend fun track(event: TrackedEvent)
}

class MacosTracking : MacosTrackingApi {
    override suspend fun track(event: TrackedEvent) {
        koin.get<TrackingApi>().track(event)
    }
}
