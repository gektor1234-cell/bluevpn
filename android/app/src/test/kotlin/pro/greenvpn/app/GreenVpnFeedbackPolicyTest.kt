package pro.greenvpn.app

import org.junit.Assert.*
import org.junit.Test

class GreenVpnFeedbackPolicyTest {
    @Test fun confirmedTransitionsAreNotRepeatedDuringMonitoringOrRecovery() {
        val policy = GreenVpnFeedbackPolicy()
        assertNull(policy.disconnected())
        assertEquals("connected", policy.confirmed())
        assertNull(policy.confirmed())
        assertNull(policy.failed("retry", false))
        assertNull(policy.confirmed())
        assertEquals("disconnected", policy.disconnected())
        assertNull(policy.disconnected())
        assertEquals("connected", policy.confirmed())
    }
    @Test fun restoredStateAndTransientFailuresAreSilent() {
        val policy = GreenVpnFeedbackPolicy(connected = true)
        assertNull(policy.confirmed())
        assertNull(policy.failed("network-loss", false))
        assertEquals("failed", policy.failed("terminal", true))
        assertNull(policy.failed("terminal", true))
        assertNull(policy.failed("", true))
    }
}
