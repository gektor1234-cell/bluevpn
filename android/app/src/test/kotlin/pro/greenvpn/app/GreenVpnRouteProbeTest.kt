package pro.greenvpn.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GreenVpnRouteProbeTest {
    @Test
    fun proxyTransportsRequireTheirDedicatedLoopbackSocksPortsAfterSystemRoute() {
        assertEquals(1980, GreenVpnRouteProbe.socksPortForProtocol("hysteria2"))
        assertEquals(1981, GreenVpnRouteProbe.socksPortForProtocol("vless_reality"))
        assertEquals(1982, GreenVpnRouteProbe.socksPortForProtocol("naive_https"))
        assertEquals(1983, GreenVpnRouteProbe.socksPortForProtocol("dnstt"))
    }

    @Test
    fun tunnelProtocolsUseTheSystemVpnRoute() {
        assertNull(GreenVpnRouteProbe.socksPortForProtocol("amneziawg"))
        assertNull(GreenVpnRouteProbe.socksPortForProtocol("wireguard_udp"))
    }

    @Test
    fun nativeProbeDeadlineFinishesBeforeFlutterChannelTimeout() {
        assertEquals(10_000L, GreenVpnRouteProbe.TOTAL_PROBE_TIMEOUT_MS)
    }

    @Test
    fun baselineRequiresTheExactExpectedStatusNotRedirectsOrCaptivePortals() {
        assertEquals(true, GreenVpnRouteProbe.acceptsStatus(204, 204))
        assertEquals(true, GreenVpnRouteProbe.acceptsStatus(200, 200))
        assertEquals(false, GreenVpnRouteProbe.acceptsStatus(200, 204))
        assertEquals(false, GreenVpnRouteProbe.acceptsStatus(302, 204))
        assertEquals(false, GreenVpnRouteProbe.acceptsStatus(503, 200))
    }

    @Test
    fun activeVpnNetworkIsPreferred() {
        val selected = GreenVpnRouteProbe.preferVpnNetwork(
            activeNetwork = "active-vpn",
            availableNetworks = listOf("fallback-vpn", "direct"),
            isVpnNetwork = { it.endsWith("vpn") },
        )

        assertEquals("active-vpn", selected)
    }

    @Test
    fun vpnNetworkIsFoundWhenTheActiveNetworkIsDirect() {
        val selected = GreenVpnRouteProbe.preferVpnNetwork(
            activeNetwork = "direct",
            availableNetworks = listOf("direct", "candidate-vpn"),
            isVpnNetwork = { it.endsWith("vpn") },
        )

        assertEquals("candidate-vpn", selected)
    }

    @Test
    fun directNetworkCannotSatisfyVpnRouteProbe() {
        val selected = GreenVpnRouteProbe.preferVpnNetwork(
            activeNetwork = "direct",
            availableNetworks = listOf("direct", "mobile"),
            isVpnNetwork = { it.endsWith("vpn") },
        )

        assertNull(selected)
    }

    @Test
    fun authenticatedSocksGreetingOffersNoAuthAndUsernamePassword() {
        val credentials = GreenVpnDnsttPreview.ProxyCredentials("probe-user", "probe-password-value")

        assertArrayEquals(
            byteArrayOf(0x05, 0x02, 0x00, 0x02),
            GreenVpnRouteProbe.socksGreeting(credentials),
        )
        assertArrayEquals(
            byteArrayOf(0x05, 0x01, 0x00),
            GreenVpnRouteProbe.socksGreeting(null),
        )
    }

    @Test
    fun usernamePasswordRequestUsesRfc1929WireFormat() {
        val credentials = GreenVpnDnsttPreview.ProxyCredentials("user", "password-value-123")
        val request = GreenVpnRouteProbe.usernamePasswordRequest(credentials)

        assertEquals(0x01, request[0].toInt())
        assertEquals(4, request[1].toInt())
        assertEquals("user", request.copyOfRange(2, 6).toString(Charsets.UTF_8))
        assertEquals(18, request[6].toInt())
        assertEquals("password-value-123", request.copyOfRange(7, request.size).toString(Charsets.UTF_8))
    }
}
