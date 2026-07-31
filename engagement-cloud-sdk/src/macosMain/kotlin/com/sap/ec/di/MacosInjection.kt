package com.sap.ec.di

import app.cash.sqldelight.driver.native.NativeSqliteDriver
import com.sap.ec.MacosEngagementCloudSDKConfig
import com.sap.ec.api.config.MacosConfig
import com.sap.ec.api.config.MacosConfigApi
import com.sap.ec.api.contact.MacosContact
import com.sap.ec.api.contact.MacosContactApi
import com.sap.ec.api.deeplink.MacosDeepLink
import com.sap.ec.api.deeplink.MacosDeepLinkApi
import com.sap.ec.api.inapp.MacosInApp
import com.sap.ec.api.inapp.MacosInAppApi
import com.sap.ec.api.push.MacosPush
import com.sap.ec.api.push.PushApi
import com.sap.ec.api.setup.MacosSetup
import com.sap.ec.api.setup.MacosSetupApi
import com.sap.ec.api.tracking.MacosTracking
import com.sap.ec.api.tracking.MacosTrackingApi
import com.sap.ec.core.actions.clipboard.ClipboardHandlerApi
import com.sap.ec.core.actions.launchapplication.LaunchApplicationHandlerApi
import com.sap.ec.core.cache.FileCacheApi
import com.sap.ec.core.cache.MacosFileCache
import com.sap.ec.core.clipboard.MacosClipboardHandler
import com.sap.ec.core.db.events.EventsDaoApi
import com.sap.ec.core.db.events.MacosSqDelightEventsDao
import com.sap.ec.core.device.DeviceInfoCollector
import com.sap.ec.core.device.DeviceInfoCollectorApi
import com.sap.ec.core.device.UIDevice
import com.sap.ec.core.device.UIDeviceApi
import com.sap.ec.core.language.LanguageTagValidatorApi
import com.sap.ec.core.language.MacosLanguageTagValidator
import com.sap.ec.core.launchapplication.MacosLaunchApplicationHandler
import com.sap.ec.core.permission.MacosPermissionHandler
import com.sap.ec.core.permission.PermissionHandlerApi
import com.sap.ec.core.providers.ApplicationVersionProviderApi
import com.sap.ec.core.providers.ClientIdProvider
import com.sap.ec.core.providers.LanguageProviderApi
import com.sap.ec.core.providers.MacosApplicationVersionProvider
import com.sap.ec.core.providers.MacosLanguageProvider
import com.sap.ec.core.providers.inputmode.InputModeProvider
import com.sap.ec.core.providers.inputmode.InputModeProviderApi
import com.sap.ec.core.providers.pagelocation.PageLocationProvider
import com.sap.ec.core.providers.pagelocation.PageLocationProviderApi
import com.sap.ec.core.providers.platform.PlatformCategoryProvider
import com.sap.ec.core.providers.platform.PlatformCategoryProviderApi
import com.sap.ec.core.state.State
import com.sap.ec.core.storage.StorageConstants
import com.sap.ec.core.storage.StorageConstants.DB_NAME
import com.sap.ec.core.storage.StringStorage
import com.sap.ec.core.storage.StringStorageApi
import com.sap.ec.core.url.ExternalUrlOpenerApi
import com.sap.ec.core.url.MacosExternalUrlOpener
import com.sap.ec.core.watchdog.connection.MacosConnectionWatchdog
import com.sap.ec.core.watchdog.connection.NWPathMonitorWrapper
import com.sap.ec.core.watchdog.lifecycle.MacosLifecycleWatchdog
import com.sap.ec.enable.PlatformInitializer
import com.sap.ec.enable.PlatformInitializerApi
import com.sap.ec.enable.config.MacosSdkConfigStore
import com.sap.ec.enable.config.SdkConfigStoreApi
import com.sap.ec.init.states.LegacySDKMigrationState
import com.sap.ec.mobileengage.action.EventActionFactoryApi
import com.sap.ec.mobileengage.inapp.MacosInAppPresenter
import com.sap.ec.mobileengage.inapp.MacosInAppViewProvider
import com.sap.ec.mobileengage.inapp.presentation.InAppPresenterApi
import com.sap.ec.mobileengage.inapp.providers.InAppJsBridgeFactory
import com.sap.ec.mobileengage.inapp.providers.MacosWebViewFactory
import com.sap.ec.mobileengage.inapp.view.InAppViewProviderApi
import com.sap.ec.sqldelight.SapEngagementCloudDB
import com.sap.ec.watchdog.connection.ConnectionWatchDog
import com.sap.ec.watchdog.lifecycle.LifecycleWatchDog
import org.koin.core.module.Module
import org.koin.core.parameter.parametersOf
import org.koin.core.qualifier.named
import org.koin.dsl.module
import platform.AppKit.NSPasteboard
import platform.Foundation.NSFileManager
import platform.Foundation.NSProcessInfo
import platform.Foundation.NSUserDefaults

/**
 * Koin bindings for the macOS target. Mirrors [com.sap.ec.di.IosInjection] with the following
 * omissions (Phase-1 decisions):
 * - Push (5): no `PushApi` / `IosPushInstance` / `IosBadgeCountHandler` / `IosPermissionHandler`.
 * - Embedded messaging (6): no `IosEmbeddedMessagingApi` binding.
 * - Inline Compose views: no `InlineInAppViewRendererApi` binding (macOS uses WKWebView presenter
 *   instead — see [MacosInAppPresenter]).
 *
 * The in-app presenter is a real WKWebView + NSPanel overlay (see [MacosInAppPresenter]).
 */
internal object MacosInjection {
    val macosModules = module {
        single<NSUserDefaults> { NSUserDefaults(StorageConstants.SUITE_NAME) }

        single<MacosSetupApi> { MacosSetup(get()) }
        single<MacosContactApi> { MacosContact() }
        single<MacosTrackingApi> { MacosTracking() }
        single<MacosInAppApi> { MacosInApp() }
        single<MacosConfigApi> { MacosConfig(configApi = get()) }
        single<MacosDeepLinkApi> { MacosDeepLink() }

        single<StringStorageApi> { StringStorage(userDefaults = get()) }
        single<SdkConfigStoreApi<MacosEngagementCloudSDKConfig>> {
            MacosSdkConfigStore(typedStorage = get())
        }
        single<PermissionHandlerApi> { MacosPermissionHandler() }
        single<UIDeviceApi> { UIDevice(NSProcessInfo()) }

        // Phase-1 decision #5: push is not exposed on macOS. Provide a no-op PushApi so the
        // shared init graph (RegisterInstancesState) can be constructed.
        single<PushApi> { MacosPush() }

        single<PageLocationProviderApi> { PageLocationProvider() }
        single<PlatformCategoryProviderApi> { PlatformCategoryProvider() }
        single<InputModeProviderApi> { InputModeProvider() }

        single<DeviceInfoCollectorApi> {
            DeviceInfoCollector(
                clientIdProvider = ClientIdProvider(uuidProvider = get(), storage = get()),
                applicationVersionProvider = get(),
                languageProvider = get(),
                timezoneProvider = get(),
                deviceInformation = get(),
                wrapperInfoStorage = get(),
                json = get(),
                stringStorage = get(),
                sdkContext = get(),
                platformCategoryProvider = get()
            )
        }

        single<State>(named(InitStateTypes.LegacySDKMigration)) {
            LegacySDKMigrationState(
                requestContext = get(),
                sdkContext = get(),
                stringStorage = get(),
                sdkLogger = get { parametersOf(LegacySDKMigrationState::class.simpleName) }
            )
        }

        single<EventsDaoApi> {
            val driver = NativeSqliteDriver(SapEngagementCloudDB.Schema, DB_NAME)
            MacosSqDelightEventsDao(db = SapEngagementCloudDB(driver), json = get())
        }

        single<ApplicationVersionProviderApi> { MacosApplicationVersionProvider() }
        single<LanguageProviderApi> { MacosLanguageProvider() }
        single<PlatformInitializerApi> { PlatformInitializer() }

        single<ExternalUrlOpenerApi> {
            MacosExternalUrlOpener(
                mainDispatcher = get(named(DispatcherTypes.Main)),
                sdkLogger = get { parametersOf(MacosExternalUrlOpener::class.simpleName) }
            )
        }

        single<ConnectionWatchDog> {
            MacosConnectionWatchdog(
                NWPathMonitorWrapper(sdkDispatcher = get(named(DispatcherTypes.Sdk)))
            )
        }
        single<LifecycleWatchDog> { MacosLifecycleWatchdog() }

        single<FileCacheApi> { MacosFileCache(NSFileManager.defaultManager) }

        single<ClipboardHandlerApi> { MacosClipboardHandler(NSPasteboard.generalPasteboard) }
        single<LaunchApplicationHandlerApi> { MacosLaunchApplicationHandler() }
        single<LanguageTagValidatorApi> { MacosLanguageTagValidator() }

        // In-app messaging: WKWebView + NSPanel overlay presenter, matching the iOS flow.
        single<InAppViewProviderApi> {
            val inAppJsBridgeFactory = InAppJsBridgeFactory(
                actionFactory = get<EventActionFactoryApi>(),
                json = get(),
                mainDispatcher = get(named(DispatcherTypes.Main)),
                sdkDispatcher = get(named(DispatcherTypes.Sdk)),
                sdkLogger = get { parametersOf(InAppJsBridgeFactory::class.simpleName) }
            )
            val macosWebViewFactory = MacosWebViewFactory(
                mainDispatcher = get(named(DispatcherTypes.Main)),
                inAppJsBridgeFactory = inAppJsBridgeFactory
            )
            MacosInAppViewProvider(
                mainDispatcher = get(named(DispatcherTypes.Main)),
                webViewProvider = macosWebViewFactory,
                timestampProvider = get(),
                contentReplacer = get()
            )
        }
        single<InAppPresenterApi> {
            MacosInAppPresenter(
                mainDispatcher = get(named(DispatcherTypes.Main)),
                sdkDispatcher = get(named(DispatcherTypes.Sdk)),
                sdkEventDistributor = get(),
                logger = get { parametersOf(MacosInAppPresenter::class.simpleName) }
            )
        }
    }
}

internal actual fun SdkKoinIsolationContext.loadPlatformModules(): List<Module> {
    return listOf(MacosInjection.macosModules)
}
