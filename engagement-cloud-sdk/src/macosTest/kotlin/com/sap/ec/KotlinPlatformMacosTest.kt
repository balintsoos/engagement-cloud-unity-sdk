package com.sap.ec

import kotlin.test.Test
import kotlin.test.assertEquals

class KotlinPlatformMacosTest {

    @Test
    fun `currentPlatform is MACOS on macOS target`() {
        assertEquals(KotlinPlatform.MACOS, currentPlatform)
    }
}
