package com.sap.ec.core.device

import platform.Foundation.NSProcessInfo
import kotlin.test.Test
import kotlin.test.assertTrue

class UIDeviceMacosTest {

    private val device = UIDevice(NSProcessInfo.processInfo)

    @Test
    fun `osVersion returns a non-empty dotted string`() {
        val version = device.osVersion()
        assertTrue(version.isNotEmpty(), "osVersion should not be empty")
        assertTrue(version.contains("."), "osVersion should look like major.minor.patch, got $version")
    }

    @Test
    fun `deviceModel returns a non-empty identifier`() {
        val model = device.deviceModel()
        assertTrue(model.isNotEmpty(), "deviceModel should not be empty")
    }

    @Test
    fun `hasOsVersionAtLeast returns true for OS X 10`() {
        assertTrue(device.hasOsVersionAtLeast(10))
    }
}
