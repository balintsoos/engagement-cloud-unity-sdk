package com.sap.ec.core.providers.inputmode

internal actual class InputModeProvider : InputModeProviderApi {
    // macOS Macs have keyboard/mouse input; touch is not the primary input mode.
    actual override fun hasTouchSupport(): Boolean = false
}
