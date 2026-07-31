package com.sap.ec.api.contact

import com.sap.ec.di.SdkKoinIsolationContext.koin
import io.ktor.utils.io.CancellationException

interface MacosContactApi {
    @Throws(CancellationException::class)
    suspend fun link(contactFieldValue: String)

    @Throws(CancellationException::class)
    suspend fun linkAuthenticated(openIdToken: String)

    @Throws(CancellationException::class)
    suspend fun unlink()
}

class MacosContact : MacosContactApi {
    override suspend fun link(contactFieldValue: String) {
        koin.get<ContactApi>().link(contactFieldValue)
    }

    override suspend fun linkAuthenticated(openIdToken: String) {
        koin.get<ContactApi>().linkAuthenticated(openIdToken)
    }

    override suspend fun unlink() {
        koin.get<ContactApi>().unlink()
    }
}
