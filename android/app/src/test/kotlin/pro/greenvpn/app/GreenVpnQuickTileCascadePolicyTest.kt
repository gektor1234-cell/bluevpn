package pro.greenvpn.app

import org.junit.Assert.assertEquals
import org.junit.Test

class GreenVpnQuickTileCascadePolicyTest {
    @Test
    fun strictTransportOrderIsPreserved() {
        val candidates = listOf(
            candidate("wg", "wireguard_udp"),
            candidate("dns", "dnstt"),
            candidate("naive", "naive_https"),
            candidate("vless", "vless_reality"),
            candidate("h2", "hysteria2"),
            candidate("awg", "amneziawg"),
        )

        assertEquals(
            listOf("awg", "h2", "vless", "naive", "dns", "wg"),
            GreenVpnQuickTileCascadePolicy.sort(candidates, nowMs = 1_000L).map { it.serverId },
        )
    }

    @Test
    fun coolingCandidateIsDemotedWithoutChangingBaseOrder() {
        val candidates = listOf(
            candidate("awg", "amneziawg", cooldownUntilMs = 61_000L),
            candidate("h2", "hysteria2"),
            candidate("vless", "vless_reality"),
        )

        assertEquals(
            listOf("h2", "vless", "awg"),
            GreenVpnQuickTileCascadePolicy.sort(candidates, nowMs = 1_000L).map { it.serverId },
        )
    }

    @Test
    fun cooldownScheduleIsBounded() {
        assertEquals(60_000L, GreenVpnQuickTileCascadePolicy.cooldownDurationMs(1))
        assertEquals(180_000L, GreenVpnQuickTileCascadePolicy.cooldownDurationMs(2))
        assertEquals(600_000L, GreenVpnQuickTileCascadePolicy.cooldownDurationMs(3))
        assertEquals(1_800_000L, GreenVpnQuickTileCascadePolicy.cooldownDurationMs(99))
    }

    private fun candidate(
        id: String,
        protocol: String,
        cooldownUntilMs: Long? = null,
    ) = GreenVpnTileRouteCandidate(
        serverId = id,
        protocol = protocol,
        healthScore = 100,
        latencyMs = 10,
        cooldownUntilMs = cooldownUntilMs,
    )
}
