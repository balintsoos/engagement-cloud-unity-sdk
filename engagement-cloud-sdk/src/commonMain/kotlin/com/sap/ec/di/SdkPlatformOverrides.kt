package com.sap.ec.di

import org.koin.core.module.Module

object SdkPlatformOverrides {
    private val overrides: MutableList<Module> = mutableListOf()

    fun register(modules: List<Module>) {
        overrides += modules
    }

    internal fun registeredModules(): List<Module> = overrides.toList()
}
