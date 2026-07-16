package pro.greenvpn.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GreenVpnTunnelBackendPolicyTest {
    @Test
    fun standardProtocolNeverUsesAmneziaBackend() {
        assertTrue(GreenVpnTunnelBackendPolicy.usesStandardBackend("wireguard_udp"))
        assertFalse(GreenVpnTunnelBackendPolicy.usesAmneziaBackend("wireguard_udp"))
    }

    @Test
    fun amneziaProtocolNeverUsesStandardBackend() {
        assertTrue(GreenVpnTunnelBackendPolicy.usesAmneziaBackend("amneziawg"))
        assertFalse(GreenVpnTunnelBackendPolicy.usesStandardBackend("amneziawg"))
    }

    @Test
    fun inactivePreviewDoesNotHideStandardBackendStatus() {
        assertFalse(GreenVpnTunnelBackendPolicy.previewSnapshotIsActive(false, "down"))
        assertTrue(GreenVpnTunnelBackendPolicy.previewSnapshotIsActive(false, "starting"))
        assertTrue(GreenVpnTunnelBackendPolicy.previewSnapshotNeedsCleanup(false, "error"))
    }
}
