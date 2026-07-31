package com.sap.ec.core.permission

/**
 * Push permissions are deferred on macOS (decision #5 in the Phase-1 plan). This handler is
 * a no-op so DI wiring stays uniform across platforms without touching UNUserNotificationCenter.
 */
internal class MacosPermissionHandler : PermissionHandlerApi {
    override suspend fun requestPushPermission() {
        // no-op: push is not part of the macOS Phase-1 parity.
    }
}
