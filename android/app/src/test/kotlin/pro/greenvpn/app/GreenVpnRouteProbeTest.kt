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
        assertEquals(18_000L, GreenVpnRouteProbe.TOTAL_PROBE_TIMEOUT_MS)
    }

    @Test
    fun routeNeedsYoutubeAndAnIndependentTarget() {
        assertEquals(false, GreenVpnRouteProbe.quorumSatisfied(true, false))
        assertEquals(false, GreenVpnRouteProbe.quorumSatisfied(false, true))
        assertEquals(true, GreenVpnRouteProbe.quorumSatisfied(true, true))
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
