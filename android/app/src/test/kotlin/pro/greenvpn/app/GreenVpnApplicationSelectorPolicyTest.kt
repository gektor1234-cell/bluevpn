package pro.greenvpn.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class GreenVpnApplicationSelectorPolicyTest {
    @Test
    fun keepsOnlyInstalledSelectedApplications() {
        val filtered = GreenVpnApplicationSelectorPolicy.filterInstalledApplications(
            """[Interface]
                |IncludedApplications = org.telegram.messenger, com.instagram.android, org.telegram.messenger
                |PrivateKey = secret
            """.trimMargin(),
        ) { it == "org.telegram.messenger" }

        assertEquals(
            """[Interface]
                |IncludedApplications = org.telegram.messenger
                |PrivateKey = secret
            """.trimMargin(),
            filtered,
        )
    }

    @Test
    fun emptyIncludedApplicationsFailsClosed() {
        assertThrows(IllegalArgumentException::class.java) {
            GreenVpnApplicationSelectorPolicy.filterInstalledApplications(
                """[Interface]
                    |IncludedApplications = com.missing.application
                    |PrivateKey = secret
                """.trimMargin(),
            ) { false }
        }
    }

    @Test
    fun emptyExcludedApplicationsIsRemoved() {
        val filtered = GreenVpnApplicationSelectorPolicy.filterInstalledApplications(
            """[Interface]
                |ExcludedApplications = com.missing.application
                |PrivateKey = secret
            """.trimMargin(),
        ) { false }

        assertEquals("[Interface]\nPrivateKey = secret", filtered)
    }
}
