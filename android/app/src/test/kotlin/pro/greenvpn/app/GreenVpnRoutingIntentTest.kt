package pro.greenvpn.app

import com.wireguard.config.Config
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream

class GreenVpnRoutingIntentTest {
    private fun config(): String {
        val key = com.wireguard.crypto.KeyPair().privateKey.toBase64()
        val peer = com.wireguard.crypto.KeyPair().publicKey.toBase64()
        return "[Interface]\nPrivateKey = $key\nAddress = 10.1.0.2/32\n" +
            "ExcludedApplications = old.example\n\n[Peer]\nPublicKey = $peer\n" +
            "AllowedIPs = 192.0.2.1/32\nEndpoint = 192.0.2.2:51820\n"
    }

    @Test fun selectedResumeKeepsPackagesAndBothIpFamilies() {
        val intent = GreenVpnRoutingIntent("social_only", setOf("fixture.browser", "fixture.chat"))
        val rendered = intent.apply(config())
        val parsed = Config.parse(ByteArrayInputStream(rendered.toByteArray()))
        assertEquals(intent.packages, parsed.`interface`.includedApplications)
        assertTrue(parsed.`interface`.excludedApplications.isEmpty())
        assertEquals(setOf("0.0.0.0/0", "0:0:0:0:0:0:0:0/0"), parsed.peers.single().allowedIps.map { it.toString() }.toSet())
        assertEquals(listOf("wireguard_udp"), intent.supportedProtocols)
        assertEquals(rendered, intent.apply(rendered))
    }

    @Test fun fullResumeDoesNotRewriteConfig() {
        val original = config()
        assertEquals(original, GreenVpnRoutingIntent("full", emptySet()).apply(original))
    }

    @Test fun emptyOrInvalidSelectedIntentFailsClosed() {
        for (packages in listOf(emptySet(), setOf("../other"))) {
            try {
                GreenVpnRoutingIntent("social_only", packages)
                fail("invalid selected intent accepted")
            } catch (_: IllegalArgumentException) { }
        }
    }

    @Test fun validationIsNotRequiredButCaptiveAndVpnNetworksAreRejected() {
        assertTrue(GreenVpnUnderlyingNetwork.canProbe(internet = true, vpn = false, captivePortal = false))
        assertFalse(GreenVpnUnderlyingNetwork.canProbe(internet = false, vpn = false, captivePortal = false))
        assertFalse(GreenVpnUnderlyingNetwork.canProbe(internet = true, vpn = true, captivePortal = false))
        assertFalse(GreenVpnUnderlyingNetwork.canProbe(internet = true, vpn = false, captivePortal = true))
    }
}
