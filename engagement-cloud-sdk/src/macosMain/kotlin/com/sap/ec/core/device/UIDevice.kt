package com.sap.ec.core.device

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.cValue
import kotlinx.cinterop.useContents
import platform.Foundation.NSProcessInfo

@OptIn(ExperimentalForeignApi::class)
internal class UIDevice(
    private val processInfo: NSProcessInfo
) : UIDeviceApi {

    override fun osVersion(): String =
        processInfo.operatingSystemVersion.useContents {
            "$majorVersion.$minorVersion.$patchVersion"
        }

    override fun deviceModel(): String = "Mac"

    override fun hasOsVersionAtLeast(majorVersion: Int): Boolean {
        val systemVersion = cValue<platform.Foundation.NSOperatingSystemVersion> {
            this.majorVersion = majorVersion.toLong()
            minorVersion = 0
            patchVersion = 0
        }
        return processInfo.isOperatingSystemAtLeastVersion(systemVersion)
    }
}
