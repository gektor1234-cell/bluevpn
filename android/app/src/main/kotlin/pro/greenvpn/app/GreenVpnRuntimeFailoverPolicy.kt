package pro.greenvpn.app

internal object GreenVpnRuntimeFailoverPolicy {
    const val MONITOR_INTERVAL_MS = 3_000L
    const val ROUTE_PROBE_INTERVAL_MS = 20_000L
    const val REQUIRED_ROUTE_FAILURES = 2
    const val MAX_PAUSE_DURATION_MS = 24L * 60L * 60L * 1_000L

    private val retryScheduleMs = longArrayOf(3_000L, 10_000L, 30_000L, 60_000L)

    fun nextRouteFailureCount(previous: Int, probeOk: Boolean): Int =
        if (probeOk) 0 else (previous + 1).coerceAtMost(REQUIRED_ROUTE_FAILURES)

    fun shouldRecoverForRoute(failureCount: Int): Boolean =
        failureCount >= REQUIRED_ROUTE_FAILURES

    fun retryDelayMs(failureCount: Int): Long =
        retryScheduleMs[
            (failureCount.coerceAtLeast(1) - 1).coerceAtMost(retryScheduleMs.lastIndex)
        ]

    fun validPauseResumeAt(nowMs: Long, resumeAtMs: Long): Boolean =
        resumeAtMs > nowMs && resumeAtMs <= nowMs + MAX_PAUSE_DURATION_MS

    fun shouldCancelScheduledResume(resumeScheduled: Boolean, state: String): Boolean =
        resumeScheduled && state in setOf("paused", "recovering", "error")

    fun shouldStopForCompetingVpn(
        desired: Boolean,
        systemVpnActive: Boolean,
        ownVpnStillActive: Boolean,
    ): Boolean = desired && systemVpnActive && !ownVpnStillActive
}
