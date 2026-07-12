package pro.greenvpn.hysteria

import org.yaml.snakeyaml.DumperOptions
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.constructor.SafeConstructor
import java.net.Inet4Address
import java.net.InetAddress

internal object Hysteria2Config {
    private val forbiddenLocalModes = setOf(
        "socks5", "http", "tcpForwarding", "udpForwarding", "tcpTProxy",
        "udpTProxy", "tcpRedirect", "tun"
    )

    fun validate(baseConfig: String): String {
        loadBase(baseConfig)
        return baseConfig.trim() + "\n"
    }

    fun renderRuntime(baseConfig: String, fdControlPath: String): String {
        val root = loadBase(baseConfig)
        root["socks5"] = linkedMapOf("listen" to "127.0.0.1:1980")
        val quic = mutableMap(root["quic"])
        val sockopts = mutableMap(quic["sockopts"])
        sockopts["fdControlUnixSocket"] = fdControlPath
        quic["sockopts"] = sockopts
        root["quic"] = quic
        val log = mutableMap(root["log"])
        log["level"] = "warn"
        root["log"] = log

        val options = DumperOptions().apply {
            defaultFlowStyle = DumperOptions.FlowStyle.BLOCK
            isPrettyFlow = false
            indent = 2
        }
        return Yaml(options).dump(root)
    }

    @Suppress("UNCHECKED_CAST")
    private fun loadBase(config: String): LinkedHashMap<String, Any?> {
        require(config.toByteArray(Charsets.UTF_8).size in 1..131_072) {
            "Hysteria2 config size is invalid"
        }
        val loaderOptions = LoaderOptions().apply {
            maxAliasesForCollections = 0
            codePointLimit = 131_072
            nestingDepthLimit = 24
        }
        val loaded = Yaml(SafeConstructor(loaderOptions)).load<Any?>(config)
        require(loaded is Map<*, *>) { "Hysteria2 config root must be a mapping" }
        val root = linkedMap(loaded)
        require(forbiddenLocalModes.none { root.containsKey(it) }) {
            "Hysteria2 base config must not contain a local listener"
        }

        val server = root["server"]?.toString()?.trim().orEmpty()
        val match = Regex("^([0-9]{1,3}(?:\\.[0-9]{1,3}){3}):([0-9]{1,5})$").matchEntire(server)
            ?: throw IllegalArgumentException("Hysteria2 server must be an IPv4 literal with a port")
        val address = InetAddress.getByName(match.groupValues[1])
        require(address is Inet4Address && !address.isAnyLocalAddress && !address.isLoopbackAddress) {
            "Hysteria2 server address is invalid"
        }
        require(match.groupValues[2].toInt() in 1..65535) { "Hysteria2 server port is invalid" }
        require(root["auth"]?.toString()?.isNotBlank() == true) { "Hysteria2 auth is missing" }

        val tls = mutableMap(root["tls"])
        require(tls["sni"]?.toString()?.isNotBlank() == true) { "Hysteria2 TLS SNI is missing" }
        require(tls["insecure"] != true && tls["insecure"]?.toString()?.lowercase() != "true") {
            "Hysteria2 insecure TLS is forbidden"
        }
        val obfs = mutableMap(root["obfs"])
        require(obfs["type"]?.toString()?.lowercase() == "salamander") {
            "Hysteria2 Salamander obfuscation is required"
        }
        require(obfs["salamander"]?.let { mutableMap(it)["password"] }?.toString()?.isNotBlank() == true) {
            "Hysteria2 Salamander password is missing"
        }
        return root
    }

    private fun linkedMap(source: Map<*, *>): LinkedHashMap<String, Any?> {
        val result = LinkedHashMap<String, Any?>()
        for ((key, value) in source) {
            require(key is String && key.isNotBlank()) { "Hysteria2 config contains an invalid key" }
            result[key] = deepCopy(value)
        }
        return result
    }

    private fun mutableMap(value: Any?): LinkedHashMap<String, Any?> {
        return if (value is Map<*, *>) linkedMap(value) else LinkedHashMap()
    }

    private fun deepCopy(value: Any?): Any? = when (value) {
        is Map<*, *> -> linkedMap(value)
        is List<*> -> value.map(::deepCopy)
        else -> value
    }
}
