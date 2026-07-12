package pro.greenvpn.naive

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.net.URI

internal object NaiveHttpsConfig {
    const val SOCKS_PORT = 1982
    private const val CANARY_HOST = "nl2.vpn.greenvpn.pro"
    private const val CANARY_IP = "5.129.216.42"
    private const val CANARY_PORT = 8443
    private const val LISTEN = "socks://127.0.0.1:$SOCKS_PORT"
    private val allowedKeys = setOf("listen", "proxy")

    fun validate(configText: String): String {
        loadAndValidate(configText)
        return configText.trim() + "\n"
    }

    fun renderRuntime(configText: String): String {
        val root = loadAndValidate(configText)
        root.addProperty("host-resolver-rules", "MAP $CANARY_HOST $CANARY_IP")
        return root.toString() + "\n"
    }

    private fun loadAndValidate(configText: String): JsonObject {
        require(configText.toByteArray(Charsets.UTF_8).size in 64..16_384) {
            "Naive HTTPS config size is invalid"
        }
        val parsed = JsonParser.parseString(configText)
        require(parsed.isJsonObject) { "Naive HTTPS config root must be an object" }
        val root = parsed.asJsonObject
        require(root.keySet().all(allowedKeys::contains)) { "Naive HTTPS config contains unsupported fields" }
        require(root.string("listen") == LISTEN) { "Naive HTTPS listener must be loopback-only" }

        val proxyText = root.string("proxy")
        require(!proxyText.any { it.isWhitespace() || it.code < 0x20 }) { "Naive HTTPS proxy URI is invalid" }
        val proxy = URI(proxyText)
        require(proxy.scheme.equals("https", ignoreCase = true)) { "Naive HTTPS requires TLS" }
        require(proxy.host.equals(CANARY_HOST, ignoreCase = true) && proxy.port == CANARY_PORT) {
            "Naive HTTPS endpoint is not the guarded canary"
        }
        require(proxy.rawPath.isNullOrEmpty() && proxy.rawQuery == null && proxy.rawFragment == null) {
            "Naive HTTPS proxy URI contains unsupported components"
        }
        val userInfo = proxy.rawUserInfo.orEmpty()
        require(userInfo.length in 3..512 && ':' in userInfo) { "Naive HTTPS credentials are incomplete" }
        val parts = userInfo.split(':', limit = 2)
        require(parts[0].isNotBlank() && parts[1].isNotBlank()) { "Naive HTTPS credentials are incomplete" }
        return root
    }

    private fun JsonObject.string(name: String): String =
        get(name)?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isString }?.asString?.trim()
            ?: throw IllegalArgumentException("Naive HTTPS $name is missing")
}
