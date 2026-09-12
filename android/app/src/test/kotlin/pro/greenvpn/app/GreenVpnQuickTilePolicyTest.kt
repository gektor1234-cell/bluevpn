package pro.greenvpn.app

import org.junit.Assert.*
import org.junit.Test

class GreenVpnQuickTilePolicyTest {
    @Test fun repeatedConnectTapCancelsInsteadOfEnqueueingAnotherConnect() {
        assertEquals("connect", GreenVpnQuickTilePolicy.action("idle", false, false))
        assertEquals("disconnect", GreenVpnQuickTilePolicy.action("queued", true, false))
        assertEquals("wait", GreenVpnQuickTilePolicy.action("disconnecting", false, true))
        assertEquals("disconnect", GreenVpnQuickTilePolicy.action("disarmed", false, true))
    }
    @Test fun waitingAndRecoveryAreBusyNotConfirmed() {
        assertTrue(GreenVpnQuickTilePolicy.busy("waiting_for_network"))
        assertTrue(GreenVpnQuickTilePolicy.busy("recovering"))
        assertFalse(GreenVpnQuickTilePolicy.busy("monitoring"))
        assertFalse(GreenVpnQuickTilePolicy.busy("authentication_required"))
    }
}
