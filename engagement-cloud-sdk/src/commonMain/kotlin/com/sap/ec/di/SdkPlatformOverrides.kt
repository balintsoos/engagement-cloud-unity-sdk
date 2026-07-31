package com.sap.ec.di

import com.sap.ec.InternalSdkApi
import org.koin.core.module.Module

/**
 * Entry point for consumers (e.g. wrappers like the Unity plugin) to register Koin modules
 * whose bindings **override** ones declared inside the SDK. The registered modules are loaded
 * by [SdkKoinIsolationContext.initKoin] AFTER the platform modules
 * ([SdkKoinIsolationContext.loadPlatformModules]) so `override = true` bindings win.
 *
 * Contract: call [register] BEFORE any access to `MacosEngagementCloud` (or its iOS / Android
 * counterparts). The `object`'s `init {}` block eagerly triggers Koin startup — reaching in
 * later than that is a no-op.
 *
 * Usage (Kotlin):
 * ```
 * SdkPlatformOverrides.register(listOf(
 *     module { single<InAppPresenterApi>(override = true) { UnityMacosInAppPresenter(...) } }
 * ))
 * ```
 *
 * Idempotent: multiple [register] calls append to an internal list; a single [reset] is exposed
 * for tests only.
 */
@InternalSdkApi
object SdkPlatformOverrides {
    private val registered = mutableListOf<Module>()

    val registeredModules: List<Module>
        get() = registered.toList()

    fun register(modules: List<Module>) {
        registered.addAll(modules)
    }

    fun reset() {
        registered.clear()
    }
}
