package pro.greenvpn.vless

import com.google.gson.JsonParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VlessRealityConfigTest {
    @Test
    fun runtimeKeepsSingleLoopbackInboundAndAddsFailClosedRules() {
        val runtime = JsonParser.parseString(VlessRealityConfig.renderRuntime(validConfig())).asJsonObject
        val inbounds = runtime.getAsJsonArray("inbounds")
        assertEquals(1, inbounds.size())
        assertEquals("127.0.0.1", inbounds[0].asJsonObject.get("listen").asString)
        assertEquals(1981, inbounds[0].asJsonObject.get("port").asInt)
        assertTrue(
            runtime.getAsJsonArray("outbounds").any {
                it.asJsonObject.get("tag")?.asString == "block"
            }
        )
        assertEquals(3, runtime.getAsJsonObject("routing").getAsJsonArray("rules").size())
        val proxy = runtime.getAsJsonArray("outbounds")[0].asJsonObject
        val endpoint = proxy.getAsJsonObject("settings").getAsJsonArray("vnext")[0].asJsonObject
        assertEquals("xudp", endpoint.getAsJsonArray("users")[0].asJsonObject.get("packetEncoding").asString)
        assertEquals(
            "stream-up",
            proxy.getAsJsonObject("streamSettings").getAsJsonObject("xhttpSettings").get("mode").asString
        )
        val xmux = proxy.getAsJsonObject("streamSettings")
            .getAsJsonObject("xhttpSettings")
            .getAsJsonObject("extra")
            .getAsJsonObject("xmux")
        assertEquals(1, xmux.get("maxConnections").asInt)
        assertEquals("128-256", xmux.get("cMaxReuseTimes").asString)
        assertTrue(!proxy.has("mux"))
        assertEquals(
            "https://1.1.1.1/dns-query",
            runtime.getAsJsonObject("dns").getAsJsonArray("servers")[0]
                .asJsonObject.get("address").asString
        )
        assertTrue(
            runtime.getAsJsonArray("outbounds").any {
                it.asJsonObject.get("tag")?.asString == "dns-out"
            }
        )
    }

    @Test
    fun validIssuedConfigPassesWithoutMutation() {
        assertEquals(validConfig().trim() + "\n", VlessRealityConfig.validate(validConfig()))
        assertEquals(setOf("5.129.216.42", "1.1.1.1"), VlessRealityConfig.routeExclusions(validConfig()))
    }

    @Test
    fun acceptsEveryGuardedDataPlanePassport() {
        VlessRealityConfig.validate(validConfig().replace("5.129.216.42", "37.220.85.211"))
        VlessRealityConfig.validate(
            validConfig()
                .replace("5.129.216.42", "88.218.250.86")
                .replace("\"port\": 443", "\"port\": 9443")
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsServerPrivateMaterial() {
        VlessRealityConfig.validate(
            validConfig().replace(
                "\"password\": \"test-public-material\"",
                "\"password\": \"test-public-material\", \"privateKey\": \"forbidden\""
            )
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsNonLoopbackListener() {
        VlessRealityConfig.validate(validConfig().replace("127.0.0.1", "0.0.0.0"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsUnknownEndpoint() {
        VlessRealityConfig.validate(validConfig().replace("5.129.216.42", "203.0.113.42"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsGuardedEndpointOnWrongPort() {
        VlessRealityConfig.validate(validConfig().replace("\"port\": 443", "\"port\": 9443"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsSniDrift() {
        VlessRealityConfig.validate(validConfig().replace("www.amazon.com", "wrong.example"))
    }

    private fun validConfig(): String = """
        {
          "log": {"loglevel": "warning"},
          "inbounds": [
            {
              "listen": "127.0.0.1",
              "port": 1981,
              "protocol": "socks",
              "settings": {"udp": true},
              "tag": "managed-socks"
            }
          ],
          "outbounds": [
            {
              "tag": "proxy",
              "protocol": "vless",
              "settings": {
                "vnext": [
                  {
                    "address": "5.129.216.42",
                    "port": 443,
                    "users": [
                      {
                        "id": "11111111-2222-4333-8444-555555555555",
                        "encryption": "none"
                      }
                    ]
                  }
                ]
              },
              "streamSettings": {
                "network": "xhttp",
                "security": "reality",
                "realitySettings": {
                  "serverName": "www.amazon.com",
                  "fingerprint": "chrome",
                  "password": "test-public-material",
                  "shortId": "a1b2c3d4"
                },
                "xhttpSettings": {
                  "path": "/transport-preview",
                  "mode": "auto"
                }
              }
            },
            {"tag": "direct", "protocol": "freedom"}
          ]
        }
    """.trimIndent()
}
