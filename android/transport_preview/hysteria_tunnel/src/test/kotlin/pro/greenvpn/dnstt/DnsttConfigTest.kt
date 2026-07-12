package pro.greenvpn.dnstt

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class DnsttConfigTest {
    private val valid = """
        {
          "zone": "t.greenvpn.pro",
          "publicKey": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
          "socks": {"listen": "127.0.0.1:1983", "username": "preview-user", "password": "cHJldmlldy1wYXNzd29yZC1sb25n"},
          "resolvers": [
            {"mode": "doh", "endpoint": "https://1.1.1.1/dns-query"},
            {"mode": "dot", "endpoint": "1.1.1.1:853"}
          ],
          "expectedEgress": "5.129.216.42"
        }
    """.trimIndent()

    @Test fun acceptsGuardedProfile() {
        val profile = DnsttConfig.profile(valid)
        assertEquals("t.greenvpn.pro", profile.zone)
        assertEquals(1983, DnsttConfig.SOCKS_PORT)
        assertEquals(listOf("doh", "dot"), profile.resolvers.map { it.mode })
    }

    @Test fun rejectsWrongZone() {
        assertThrows(IllegalArgumentException::class.java) {
            DnsttConfig.validate(valid.replace("t.greenvpn.pro", "example.com"))
        }
    }

    @Test fun rejectsInvalidPublicKey() {
        assertThrows(IllegalArgumentException::class.java) {
            DnsttConfig.validate(valid.replace(Regex("0123456789abcdef[0-9a-f]+"), "abcd"))
        }
    }

    @Test fun rejectsNonLoopbackListener() {
        assertThrows(IllegalArgumentException::class.java) {
            DnsttConfig.validate(valid.replace("127.0.0.1:1983", "0.0.0.0:1983"))
        }
    }

    @Test fun rejectsUnapprovedResolver() {
        assertThrows(IllegalArgumentException::class.java) {
            DnsttConfig.validate(valid.replace("https://1.1.1.1/dns-query", "https://example.com/dns-query"))
        }
    }

    @Test fun rejectsLoggingOrUnknownFields() {
        assertThrows(IllegalArgumentException::class.java) {
            DnsttConfig.validate(valid.dropLast(1) + ",\n\"log\": \"/sdcard/dnstt.log\"\n}")
        }
    }
}
