package com.sap.ec.unity

import com.sap.ec.di.DispatcherTypes
import com.sap.ec.di.SdkPlatformOverrides
import com.sap.ec.mobileengage.inapp.presentation.InAppPresenterApi
import kotlinx.coroutines.CoroutineDispatcher
import org.koin.core.parameter.parametersOf
import org.koin.core.qualifier.named
import org.koin.dsl.module

/**
 * Entry point the Obj-C++ shim calls at bundle-load time (before ANY access to
 * `MacosEngagementCloud`, whose `init {}` block would otherwise trigger Koin
 * init and lock the module list).
 *
 * Exported to Obj-C as class `EngagementCloudUnityBridge` (see `@ObjCName`).
 * The shim's bundle-load path is:
 *   `[EngagementCloudUnityBridge shared registerOverrides]`
 * before dispatching any `ec_*` entry point.
 */
@ObjCName("EngagementCloudUnityBridge")
object UnityBridge {

    private val unityMacosModule = module {
        single<InAppPresenterApi> {
            UnityMacosInAppPresenter(
                mainDispatcher = get<CoroutineDispatcher>(named(DispatcherTypes.Main)),
                logger = get { parametersOf(UnityMacosInAppPresenter::class.simpleName) }
            )
        }
    }

    /**
     * Registers the Unity-side Koin overrides. Idempotent — safe to call
     * multiple times; only the first call has effect (subsequent calls
     * append duplicate modules that no-op because Koin loads with
     * `allowOverride = true`).
     */
    fun registerOverrides() {
        SdkPlatformOverrides.register(listOf(unityMacosModule))
    }
}

