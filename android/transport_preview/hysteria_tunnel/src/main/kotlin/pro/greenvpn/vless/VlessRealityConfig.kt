package pro.greenvpn.vless

import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.gson.JsonPrimitive
import java.net.Inet4Address
import java.net.InetAddress
import java.util.UUID

internal object VlessRealityConfig {
    const val SOCKS_PORT = 1981
    private const val CANARY_HOST = "5.129.216.42"
    private const val DNS_UPSTREAM = "1.1.1.1"
    private const val CANARY_SNI = "www.amazon.com"
    private val shortIdPattern = Regex("^(?:[0-9a-fA-F]{2}){1,8}$")

    fun validate(configText: String): String {
        loadAndValidate(configText)
        return configText.trim() + "\n"
    }

    fun routeExclusions(): Set<String> = setOf(CANARY_HOST, DNS_UPSTREAM)

    fun renderRuntime(configText: String): String {
        val root = loadAndValidate(configText)
        root.add("log", JsonObject().apply { addProperty("loglevel", "warning") })

        val outbounds = root.requiredArray("outbounds")
        val proxy = outbounds[0].requiredObject()
        proxy.requiredObject("settings")
            .requiredArray("vnext")[0].requiredObject()
            .requiredArray("users")[0].requiredObject()
            .addProperty("packetEncoding", "xudp")
        proxy.requiredObject("streamSettings")
            .requiredObject("xhttpSettings")
            .apply {
                // Android's full-tunnel DNS and push sockets expose a one-stream
                // download stall with REALITY stream-one. stream-up keeps the
                // upload and download requests independent and the server's auto
                // mode accepts both transports.
                addProperty("mode", "stream-up")
                add("extra", JsonObject().apply {
                    add("xmux", JsonObject().apply {
                        // The Android carrier stalls after opening several parallel
                        // REALITY connections. Reuse one native HTTP/2 XMUX carrier;
                        // this is XHTTP multiplexing, not the VLESS mux.cool layer.
                        addProperty("maxConnections", 1)
                        addProperty("cMaxReuseTimes", "128-256")
                        addProperty("hMaxRequestTimes", "1000-2000")
                        addProperty("hMaxReusableSecs", "600-900")
                        addProperty("hKeepAlivePeriod", 30)
                    })
                })
            }
        if (outbounds.none { it.isJsonObject && it.asJsonObject.string("tag") == "block" }) {
            outbounds.add(JsonObject().apply {
                addProperty("protocol", "blackhole")
                addProperty("tag", "block")
            })
        }
        if (outbounds.none { it.isJsonObject && it.asJsonObject.string("tag") == "dns-out" }) {
            outbounds.add(JsonObject().apply {
                addProperty("protocol", "dns")
                addProperty("tag", "dns-out")
                add("settings", JsonObject().apply {
                    add("rules", JsonArray().apply {
                        add(JsonObject().apply {
                            addProperty("action", "hijack")
                            addProperty("qType", "1,28")
                        })
                    })
                })
            })
        }
        root.add("dns", JsonObject().apply {
            addProperty("queryStrategy", "UseIPv4")
            add("servers", JsonArray().apply {
                add(JsonObject().apply {
                    addProperty("address", "https://1.1.1.1/dns-query")
                    addProperty("queryStrategy", "UseIPv4")
                    addProperty("skipFallback", true)
                    addProperty("finalQuery", true)
                    addProperty("tag", "dns-upstream")
                })
            })
        })

        val rules = JsonArray().apply {
            add(JsonObject().apply {
                addProperty("type", "field")
                addProperty("port", "53")
                addProperty("outboundTag", "dns-out")
            })
            add(JsonObject().apply {
                addProperty("type", "field")
                addProperty("network", "udp")
                addProperty("port", "443")
                addProperty("outboundTag", "block")
            })
            add(JsonObject().apply {
                addProperty("type", "field")
                add("ip", JsonArray().apply {
                    listOf(
                        "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8",
                        "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24",
                        "192.168.0.0/16", "198.18.0.0/15", "224.0.0.0/4",
                        "240.0.0.0/4", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8"
                    ).forEach { add(JsonPrimitive(it)) }
                })
                addProperty("outboundTag", "block")
            })
        }
        root.add("routing", JsonObject().apply {
            addProperty("domainStrategy", "AsIs")
            add("rules", rules)
        })
        return root.toString() + "\n"
    }

    private fun loadAndValidate(configText: String): JsonObject {
        require(configText.toByteArray(Charsets.UTF_8).size in 128..131_072) {
            "VLESS REALITY config size is invalid"
        }
        val parsed = JsonParser.parseString(configText)
        require(parsed.isJsonObject) { "VLESS REALITY config root must be an object" }
        val root = parsed.asJsonObject
        require(!containsPrivateMaterial(root)) {
            "VLESS REALITY config contains server private material"
        }

        val inbounds = root.requiredArray("inbounds")
        require(inbounds.size() == 1) { "Exactly one guarded SOCKS inbound is required" }
        val inbound = inbounds[0].requiredObject()
        require(inbound.string("listen") == "127.0.0.1") { "SOCKS listener must be loopback-only" }
        require(inbound.int("port") == SOCKS_PORT && inbound.string("protocol") == "socks") {
            "SOCKS listener contract is invalid"
        }
        require(inbound.requiredObject("settings").boolean("udp")) { "SOCKS UDP support is required" }

        val outbounds = root.requiredArray("outbounds")
        require(outbounds.size() > 0) { "VLESS outbound is missing" }
        val outbound = outbounds[0].requiredObject()
        require(outbound.string("protocol") == "vless") { "First outbound must be VLESS" }
        val vnext = outbound.requiredObject("settings").requiredArray("vnext")
        require(vnext.size() == 1) { "Exactly one VLESS endpoint is required" }
        val endpoint = vnext[0].requiredObject()
        val host = endpoint.string("address")
        val address = InetAddress.getByName(host)
        require(address is Inet4Address && host == CANARY_HOST && !address.isAnyLocalAddress) {
            "VLESS REALITY endpoint is not the guarded canary"
        }
        require(endpoint.int("port") == 443) { "VLESS REALITY endpoint must use TCP/443" }
        val users = endpoint.requiredArray("users")
        require(users.size() == 1) { "Exactly one VLESS user is required" }
        val user = users[0].requiredObject()
        UUID.fromString(user.string("id"))
        require(user.string("encryption") == "none") { "VLESS encryption must be none" }

        val stream = outbound.requiredObject("streamSettings")
        require(stream.string("network") == "xhttp" && stream.string("security") == "reality") {
            "XHTTP over REALITY is required"
        }
        val reality = stream.requiredObject("realitySettings")
        require(reality.string("serverName").lowercase() == CANARY_SNI) {
            "REALITY SNI is not allowlisted"
        }
        require(reality.string("fingerprint").isNotBlank() && reality.string("password").isNotBlank()) {
            "REALITY public client material is incomplete"
        }
        require(shortIdPattern.matches(reality.string("shortId"))) { "REALITY shortId is invalid" }
        val xhttp = stream.requiredObject("xhttpSettings")
        require(xhttp.string("path").startsWith("/")) { "XHTTP path is invalid" }
        require(xhttp.stringOrDefault("mode", "auto").lowercase() in setOf("auto", "stream-one")) {
            "XHTTP mode is invalid"
        }
        return root
    }

    private fun containsPrivateMaterial(value: JsonElement): Boolean {
        if (value.isJsonObject) {
            for ((key, child) in value.asJsonObject.entrySet()) {
                if (key.lowercase() in setOf("privatekey", "mldsa65seed") || containsPrivateMaterial(child)) {
                    return true
                }
            }
        } else if (value.isJsonArray && value.asJsonArray.any(::containsPrivateMaterial)) {
            return true
        }
        return false
    }

    private fun JsonElement.requiredObject(): JsonObject =
        takeIf { it.isJsonObject }?.asJsonObject
            ?: throw IllegalArgumentException("VLESS REALITY config object is missing")

    private fun JsonObject.requiredObject(name: String): JsonObject =
        get(name)?.requiredObject()
            ?: throw IllegalArgumentException("VLESS REALITY $name object is missing")

    private fun JsonObject.requiredArray(name: String): JsonArray =
        get(name)?.takeIf { it.isJsonArray }?.asJsonArray
            ?: throw IllegalArgumentException("VLESS REALITY $name array is missing")

    private fun JsonObject.string(name: String): String =
        get(name)?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isString }?.asString?.trim()
            ?: throw IllegalArgumentException("VLESS REALITY $name is missing")

    private fun JsonObject.stringOrDefault(name: String, fallback: String): String =
        get(name)?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isString }?.asString?.trim()
            ?: fallback

    private fun JsonObject.int(name: String): Int =
        get(name)?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isNumber }?.asInt
            ?: throw IllegalArgumentException("VLESS REALITY $name is invalid")

    private fun JsonObject.boolean(name: String): Boolean =
        get(name)?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isBoolean }?.asBoolean
            ?: false
}
