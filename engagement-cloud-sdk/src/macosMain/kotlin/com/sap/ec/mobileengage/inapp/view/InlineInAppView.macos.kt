package com.sap.ec.mobileengage.inapp.view

import androidx.compose.runtime.Composable
import com.sap.ec.mobileengage.inapp.InAppMessage

/**
 * macOS `InlineInAppView` actual — intentionally inert.
 *
 * Inline Compose views are not part of the Phase-1 macOS parity: in-app messages are presented
 * via a WKWebView-backed `NSWindow` overlay by [com.sap.ec.mobileengage.inapp.MacosInAppPresenter]
 * instead. The `expect` declaration in commonMain still requires an actual on every target, so
 * this stub keeps the compile green without pulling Compose UI onto the macOS classpath.
 */
@Composable
internal actual fun InlineInAppView(
    message: InAppMessage,
    onClose: () -> Unit,
    onLoaded: ((String) -> Unit)?
) {
    // no-op on macOS
}
