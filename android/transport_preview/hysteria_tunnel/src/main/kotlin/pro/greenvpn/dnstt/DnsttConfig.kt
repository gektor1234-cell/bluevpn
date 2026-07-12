package pro.greenvpn.dnstt

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.net.URI

internal object DnsttConfig {
    const val SOCKS_PORT = 1983
    private const val ZONE = "t.greenvpn.pro"
    private const val EXPECTED_EGRESS = "5.129.216.42"
    private const val LISTEN = "127.0.0.1:$SOCKS_PORT"
    private val allowedRootKeys = setOf("zone", "publicKey", "socks", "resolvers", "expectedEgress")
    private val allowedSocksKeys = setOf("listen", "username", "password")
    private val allowedResolverKeys = setOf("mode", "endpoint")
    private val allowedResolvers = setOf(
        "doh:https://1.1.1.1/dns-query",
        "doh:https://8.8.8.8/dns-query",
        "dot:1.1.1.1:853"
    )

    data class Resolver(val mode: String, val endpoint: String)
    data class Profile(
        val zone: String,
        val publicKey: String,
        val username: String,
        val password: String,
        val resolvers: List<Resolver>
    )

    fun validate(configText: String): String {
        loadAndValidate(configText)
        return configText.trim() + "\n"
    }

    fun profile(configText: String): Profile {
        val root = loadAndValidate(configText)
        val socks = root.getAsJsonObject("socks")
        return Profile(
            zone = root.string("zone"),
            publicKey = root.string("publicKey"),
            username = socks.string("username"),
            password = socks.string("password"),
            resolvers = root.getAsJsonArray("resolvers").map { element ->
                val resolver = element.asJsonObject
                Resolver(resolver.string("mode"), resolver.string("endpoint"))
            }
        )
    }

    private fun loadAndValidate(configText: String): JsonObject {
        require(configText.toByteArray(Charsets.UTF_8).size in 180..16_384) { "dnstt config size is invalid" }
        val parsed = JsonParser.parseString(configText)
        require(parsed.isJsonObject) { "dnstt config root must be an object" }
        val root = parsed.asJsonObject
        require(root.keySet().all(allowedRootKeys::contains) && root.keySet().size == allowedRootKeys.size) {
            "dnstt config fields are invalid"
        }
        require(root.string("zone") == ZONE) { "dnstt zone is not the guarded canary" }
        require(root.string("expectedEgress") == EXPECTED_EGRESS) { "dnstt egress contract is invalid" }
        require(root.string("publicKey").matches(Regex("^[0-9a-f]{64}$"))) { "dnstt public key is invalid" }

        val socks = root.objectValue("socks")
        require(socks.keySet().all(allowedSocksKeys::contains) && socks.keySet().size == allowedSocksKeys.size) {
            "dnstt SOCKS fields are invalid"
        }
        require(socks.string("listen") == LISTEN) { "dnstt listener must be loopback-only" }
        require(socks.string("username").matches(Regex("^[A-Za-z0-9_.-]{3,128}$")) &&
            socks.string("password").matches(Regex("^[A-Za-z0-9+/=]{16,256}$"))) {
            "dnstt SOCKS credentials are incomplete"
        }

        val resolvers = root.arrayValue("resolvers")
        require(resolvers.size() in 1..3) { "dnstt resolver count is invalid" }
        val seen = mutableSetOf<String>()
        resolvers.forEach { element ->
            require(element.isJsonObject) { "dnstt resolver must be an object" }
            val resolver = element.asJsonObject
            require(resolver.keySet().all(allowedResolverKeys::contains) && resolver.keySet().size == allowedResolverKeys.size) {
                "dnstt resolver fields are invalid"
            }
            val mode = resolver.string("mode")
            val endpoint = resolver.string("endpoint")
            require("$mode:$endpoint" in allowedResolvers && seen.add("$mode:$endpoint")) {
                "dnstt resolver is not allowlisted"
            }
            if (mode == "doh") {
                val uri = URI(endpoint)
                require(uri.scheme == "https" && uri.rawQuery == null && uri.rawFragment == null) {
                    "dnstt DoH resolver is invalid"
                }
            }
        }
        return root
    }

    private fun JsonObject.string(name: String): String =
        get(name)?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isString }?.asString?.trim()
            ?: throw IllegalArgumentException("dnstt $name is missing")

    private fun JsonObject.objectValue(name: String): JsonObject =
        get(name)?.takeIf { it.isJsonObject }?.asJsonObject
            ?: throw IllegalArgumentException("dnstt $name is missing")

    private fun JsonObject.arrayValue(name: String): JsonArray =
        get(name)?.takeIf { it.isJsonArray }?.asJsonArray
            ?: throw IllegalArgumentException("dnstt $name is missing")
}
