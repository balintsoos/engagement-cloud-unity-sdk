package com.sap.ec


internal enum class KotlinPlatform {
    JS,
    Android,
    IOS,
    MACOS
}

internal expect val currentPlatform: KotlinPlatform