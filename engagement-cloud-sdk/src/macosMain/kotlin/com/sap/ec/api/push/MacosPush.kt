package com.sap.ec.api.push

/**
 * Phase-1 macOS decision #5: push is not exposed via the public macOS API surface. But the
 * common init graph ([com.sap.ec.init.states.RegisterInstancesState]) still requires a
 * [PushApi] binding at Koin resolution time. This no-op stub fills the slot so the graph can
 * be built; all methods return neutral results without touching APNS.
 *
 * If push is added to macOS in a later phase, replace this with a real implementation and
 * update [com.sap.ec.di.MacosInjection].
 */
internal class MacosPush : PushApi {
    override suspend fun registerOnContext() {
        // no-op: macOS SDK does not manage push tokens.
    }

    override suspend fun registerToken(token: String): Result<Unit> = Result.success(Unit)

    override suspend fun clearToken(): Result<Unit> = Result.success(Unit)

    override suspend fun getToken(): Result<String?> = Result.success(null)
}
