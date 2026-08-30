package pro.greenvpn.app

internal object GreenVpnConnectionOperationPolicy {
    val pendingConnectStates = setOf(
        "queued",
        "permission_required",
        "waiting_for_network",
        "fetching_config",
        "connecting",
        "verifying",
        "recovering",
    )

    val connectedStates = setOf(
        "monitoring",
        "degraded",
        "degraded_no_network",
    )

    fun isConnectPending(desired: Boolean, state: String): Boolean =
        desired && state in pendingConnectStates

    fun shouldStartConnect(
        desired: Boolean,
        state: String,
        permissionGranted: Boolean,
        validatedUnderlyingNetwork: Boolean,
    ): Boolean = desired &&
        permissionGranted &&
        validatedUnderlyingNetwork &&
        state in setOf("queued", "waiting_for_network", "error")

    fun shouldProbeOrRecover(
        desired: Boolean,
        validatedUnderlyingNetwork: Boolean,
    ): Boolean = desired && validatedUnderlyingNetwork

    fun stateWithoutUnderlyingNetwork(ownEngineConnected: Boolean): String =
        if (ownEngineConnected) "degraded_no_network" else "waiting_for_network"

    fun shouldPreserveTunnelAfterProbeFailure(
        validatedUnderlyingNetwork: Boolean,
    ): Boolean = !validatedUnderlyingNetwork
}
