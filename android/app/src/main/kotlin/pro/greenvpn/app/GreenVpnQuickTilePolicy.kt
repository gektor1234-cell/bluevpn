package pro.greenvpn.app

internal object GreenVpnQuickTilePolicy {
    fun busy(state: String) = state in setOf("queued", "fetching_config", "connecting",
        "verifying", "recovering", "disconnecting", "waiting_for_network", "permission_required")
    fun action(state: String, desired: Boolean, ownConnected: Boolean): String = when {
        state == "disconnecting" -> "wait"
        ownConnected || desired -> "disconnect"
        else -> "connect"
    }
}
