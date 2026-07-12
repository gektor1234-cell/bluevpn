package pro.greenvpn.hysteria

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class Hysteria2ConfigTest {
    @Test
    fun `valid canary config renders only the managed local listener`() {
        val rendered = Hysteria2Config.renderRuntime(validConfig(), "/data/user/0/app/no_backup/fd.sock")

        assertTrue(rendered.contains("listen: 127.0.0.1:1980"))
        assertTrue(rendered.contains("fdControlUnixSocket: /data/user/0/app/no_backup/fd.sock"))
        assertTrue(rendered.contains("level: warn"))
        assertFalse(rendered.contains("insecure: true"))
        assertEquals(validConfig().trim() + "\n", Hysteria2Config.validate(validConfig()))
    }

    @Test
    fun `base config cannot define any local listener`() {
        val config = validConfig() + "socks5:\n  listen: 0.0.0.0:1080\n"

        assertThrows(IllegalArgumentException::class.java) {
            Hysteria2Config.validate(config)
        }
    }

    @Test
    fun `endpoint must be an IPv4 literal`() {
        assertThrows(IllegalArgumentException::class.java) {
            Hysteria2Config.validate(validConfig().replace("5.129.216.42:443", "canary.example:443"))
        }
    }

    @Test
    fun `insecure TLS is rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            Hysteria2Config.validate(validConfig().replace("insecure: false", "insecure: true"))
        }
    }

    @Test
    fun `salamander obfuscation with a password is mandatory`() {
        assertThrows(IllegalArgumentException::class.java) {
            Hysteria2Config.validate(validConfig().replace("type: salamander", "type: plain"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            Hysteria2Config.validate(validConfig().replace("password: test-obfs", "password: ''"))
        }
    }

    @Test
    fun `yaml aliases are rejected`() {
        val config = validConfig() + "extra: &shared\n  value: 1\ncopy: *shared\n"

        assertThrows(RuntimeException::class.java) {
            Hysteria2Config.validate(config)
        }
    }

    private fun validConfig(): String = """
        server: 5.129.216.42:443
        auth: test-auth
        tls:
          sni: canary.greenvpn.pro
          insecure: false
        obfs:
          type: salamander
          salamander:
            password: test-obfs
        quic:
          initStreamReceiveWindow: 8388608
        log:
          level: info
    """.trimIndent() + "\n"
}
