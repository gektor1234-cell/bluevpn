package pro.greenvpn.app

import com.wireguard.config.Config
import com.wireguard.config.Interface
import com.wireguard.config.Peer
import java.io.ByteArrayInputStream

internal data class GreenVpnRoutingIntent(val mode: String, val packages: Set<String>) {
    init {
        require(mode in setOf("full", "social_only")) { "unsupported_routing_mode" }
        require(packages.size <= 512 && packages.all {
            it.length <= 255 && Regex("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+").matches(it)
        }) { "invalid_routing_packages" }
        require(mode == "full" || packages.isNotEmpty()) { "selected_packages_required" }
    }

    val supportedProtocols: List<String>
        get() = if (mode == "social_only") listOf("wireguard_udp")
            else GreenVpnNativeCascadeCoordinator.SUPPORTED_PROTOCOLS

    fun apply(configText: String): String {
        if (mode == "full") return configText
        val parsed = Config.parse(ByteArrayInputStream(configText.toByteArray(Charsets.UTF_8)))
        // A selected-app tunnel routes both IP families, but only for its allowlist.
        require(parsed.peers.size == 1) { "selected_config_requires_one_peer" }
        val interfaceLines = parsed.`interface`.toWgQuickString().lines().filter { it.isNotBlank() }.filterNot {
            it.substringBefore('=').trim().lowercase() in
                setOf("includedapplications", "excludedapplications")
        } + "IncludedApplications = ${packages.sorted().joinToString(", ")}"
        val peerLines = parsed.peers.single().toWgQuickString().lines().filter { it.isNotBlank() }.filterNot {
            it.substringBefore('=').trim().equals("AllowedIPs", ignoreCase = true)
        } + "AllowedIPs = 0.0.0.0/0, ::/0"
        return Config.Builder().setInterface(Interface.parse(interfaceLines))
            .addPeer(Peer.parse(peerLines)).build().toWgQuickString()
    }
}
