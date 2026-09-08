package pro.greenvpn.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GreenVpnApiFailurePolicyTest {
    @Test fun unauthorizedTerminatesCascadeAndRecovery() {
        for (message in listOf("HTTP 401", "session_expired", "session_or_device_missing")) {
            assertTrue(message, GreenVpnApiFailurePolicy.requiresAuthentication(message))
        }
    }

    @Test fun networkAndSubscriptionErrorsAreNotSessionExpiry() {
        for (message in listOf("HTTP 403", "HTTP 429", "HTTP 502", "network_unavailable", "connect_timeout", "HTTP 4010")) {
            assertFalse(message, GreenVpnApiFailurePolicy.requiresAuthentication(message))
        }
    }
}
