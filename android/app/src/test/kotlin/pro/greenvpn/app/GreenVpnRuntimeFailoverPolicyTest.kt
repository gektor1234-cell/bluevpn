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

    @Test
    fun pauseResumeMustBeFutureAndWithinOneDay() {
        val now = 1_000_000L

        assertEquals(false, GreenVpnRuntimeFailoverPolicy.validPauseResumeAt(now, now))
        assertEquals(true, GreenVpnRuntimeFailoverPolicy.validPauseResumeAt(now, now + 5 * 60_000L))
        assertEquals(
            true,
            GreenVpnRuntimeFailoverPolicy.validPauseResumeAt(
                now,
                now + GreenVpnRuntimeFailoverPolicy.MAX_PAUSE_DURATION_MS,
            ),
        )
        assertEquals(
            false,
            GreenVpnRuntimeFailoverPolicy.validPauseResumeAt(
                now,
                now + GreenVpnRuntimeFailoverPolicy.MAX_PAUSE_DURATION_MS + 1,
            ),
        )
    }

    @Test
    fun scheduledResumeCanBeCancelledWhilePausedOrRecovering() {
        assertEquals(
            true,
            GreenVpnRuntimeFailoverPolicy.shouldCancelScheduledResume(true, "paused"),
        )
        assertEquals(
            true,
            GreenVpnRuntimeFailoverPolicy.shouldCancelScheduledResume(true, "recovering"),
        )
        assertEquals(
            true,
            GreenVpnRuntimeFailoverPolicy.shouldCancelScheduledResume(true, "error"),
        )
        assertEquals(
            false,
            GreenVpnRuntimeFailoverPolicy.shouldCancelScheduledResume(false, "recovering"),
        )
        assertEquals(
            false,
            GreenVpnRuntimeFailoverPolicy.shouldCancelScheduledResume(true, "monitoring"),
        )
    }
}
