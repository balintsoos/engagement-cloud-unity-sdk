package com.sap.ec.core.launchapplication

import com.sap.ec.core.actions.launchapplication.LaunchApplicationHandlerApi

internal class MacosLaunchApplicationHandler : LaunchApplicationHandlerApi {
    override suspend fun launchApplication() {
        // No-op — mirrors iOS behavior; macOS in-app launch actions are not supported in Phase 1.
    }
}
