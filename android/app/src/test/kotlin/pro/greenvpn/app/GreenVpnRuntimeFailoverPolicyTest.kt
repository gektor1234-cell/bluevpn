package pro.greenvpn.app

import org.junit.Assert.assertEquals
import org.junit.Test

class GreenVpnRuntimeFailoverPolicyTest {
    @Test
    fun routeNeedsTwoConsecutiveFailures() {
        val first = GreenVpnRuntimeFailoverPolicy.nextRouteFailureCount(0, probeOk = false)
        val second = GreenVpnRuntimeFailoverPolicy.nextRouteFailureCount(first, probeOk = false)

        assertEquals(1, first)
        assertEquals(false, GreenVpnRuntimeFailoverPolicy.shouldRecoverForRoute(first))
        assertEquals(2, second)
        assertEquals(true, GreenVpnRuntimeFailoverPolicy.shouldRecoverForRoute(second))
    }

    @Test
    fun successfulProbeClearsFailureSequence() {
        assertEquals(
            0,
            GreenVpnRuntimeFailoverPolicy.nextRouteFailureCount(1, probeOk = true),
        )
    }

    @Test
    fun recoveryRetryDelayIsBounded() {
        assertEquals(3_000L, GreenVpnRuntimeFailoverPolicy.retryDelayMs(1))
        assertEquals(10_000L, GreenVpnRuntimeFailoverPolicy.retryDelayMs(2))
        assertEquals(30_000L, GreenVpnRuntimeFailoverPolicy.retryDelayMs(3))
        assertEquals(60_000L, GreenVpnRuntimeFailoverPolicy.retryDelayMs(99))
    }
}
