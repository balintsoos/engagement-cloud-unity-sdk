package com.sap.ec.core.clipboard

import com.sap.ec.core.actions.clipboard.ClipboardHandlerApi
import platform.AppKit.NSPasteboard
import platform.AppKit.NSPasteboardTypeString

internal class MacosClipboardHandler(
    private val pasteboard: NSPasteboard
) : ClipboardHandlerApi {

    override suspend fun copyToClipboard(text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType = NSPasteboardTypeString)
    }
}
