package pro.greenvpn.app

internal data class GreenVpnTileRouteCandidate(
    val serverId: String,
    val protocol: String,
    val healthScore: Int,
    val latencyMs: Int?,
    val cooldownUntilMs: Long?,
)

internal object GreenVpnQuickTileCascadePolicy {
    private val transportOrder = listOf(
        "amneziawg",
        "hysteria2",
        "vless_reality",
        "naive_https",
        "dnstt",
        "wireguard_udp",
    )
    private val cooldownScheduleMs = longArrayOf(60_000L, 180_000L, 600_000L, 1_800_000L)
    private val routeProbeDelaysMs = longArrayOf(750L, 900L, 1_400L)

    fun sort(
        candidates: List<GreenVpnTileRouteCandidate>,
        nowMs: Long,
    ): List<GreenVpnTileRouteCandidate> = candidates.sortedWith { left, right ->
        val leftCooling = left.cooldownUntilMs?.let { it > nowMs } == true
        val rightCooling = right.cooldownUntilMs?.let { it > nowMs } == true
        if (leftCooling != rightCooling) {
            return@sortedWith if (leftCooling) 1 else -1
        }
        if (leftCooling && rightCooling) {
            val byCooldown = requireNotNull(left.cooldownUntilMs)
                .compareTo(requireNotNull(right.cooldownUntilMs))
            if (byCooldown != 0) return@sortedWith byCooldown
        }

        val byProtocol = rank(left.protocol).compareTo(rank(right.protocol))
        if (byProtocol != 0) return@sortedWith byProtocol
        val byHealth = right.healthScore.compareTo(left.healthScore)
        if (byHealth != 0) return@sortedWith byHealth
        val byLatency = (left.latencyMs ?: Int.MAX_VALUE)
            .compareTo(right.latencyMs ?: Int.MAX_VALUE)
        if (byLatency != 0) return@sortedWith byLatency
        left.serverId.compareTo(right.serverId)
    }

    fun cooldownDurationMs(failureCount: Int): Long =
        cooldownScheduleMs[(failureCount.coerceAtLeast(1) - 1).coerceAtMost(cooldownScheduleMs.lastIndex)]

    fun routeProbeDelayMs(attempt: Int): Long =
        routeProbeDelaysMs[(attempt.coerceAtLeast(1) - 1).coerceAtMost(routeProbeDelaysMs.lastIndex)]

    fun shouldRetryRouteProbe(attempt: Int, latencyMs: Long): Boolean =
        attempt < routeProbeDelaysMs.size && latencyMs in 0L..3_999L

    private fun rank(protocol: String): Int {
        val index = transportOrder.indexOf(protocol.trim().lowercase())
        return if (index >= 0) index else transportOrder.size
    }
}
