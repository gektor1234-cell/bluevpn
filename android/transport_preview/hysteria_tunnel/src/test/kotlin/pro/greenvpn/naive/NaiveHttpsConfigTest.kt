package pro.greenvpn.naive

import com.google.gson.JsonParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class NaiveHttpsConfigTest {
    private val valid = """
        {
          "listen": "socks://127.0.0.1:1982",
          "proxy": "https://preview-user:preview-pass@nl2.vpn.greenvpn.pro:8443"
        }
    """.trimIndent()

    @Test fun acceptsGuardedCanary() {
        val root = JsonParser.parseString(NaiveHttpsConfig.renderRuntime(valid)).asJsonObject
        assertEquals("MAP nl2.vpn.greenvpn.pro 5.129.216.42", root["host-resolver-rules"].asString)
        assertFalse(root.has("log"))
    }

    @Test fun rejectsWrongEndpoint() {
        assertThrows(IllegalArgumentException::class.java) {
            NaiveHttpsConfig.validate(valid.replace("nl2.vpn.greenvpn.pro", "example.com"))
        }
    }

    @Test fun rejectsPlainHttp() {
        assertThrows(IllegalArgumentException::class.java) {
            NaiveHttpsConfig.validate(valid.replace("https://", "http://"))
        }
    }

    @Test fun rejectsMissingCredentials() {
        assertThrows(IllegalArgumentException::class.java) {
            NaiveHttpsConfig.validate(valid.replace("preview-user:preview-pass@", ""))
        }
    }

    @Test fun rejectsNonLoopbackListener() {
        assertThrows(IllegalArgumentException::class.java) {
            NaiveHttpsConfig.validate(valid.replace("127.0.0.1", "0.0.0.0"))
        }
    }

    @Test fun rejectsLoggingFields() {
        assertThrows(IllegalArgumentException::class.java) {
            NaiveHttpsConfig.validate(valid.dropLast(1) + ",\n\"log\": \"/sdcard/netlog.json\"\n}")
        }
    }
}
