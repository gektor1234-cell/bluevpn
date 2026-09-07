package pro.greenvpn.app

import org.junit.Assert.assertEquals
import org.junit.Test

class GreenVpnConnectionOperationPolicyTest {
    @Test
    fun staleCompletionCannotOverwriteANewerCommand() {
        assertEquals(true, GreenVpnConnectionOperationPolicy.isCurrentOperation("connect-1", "connect-1"))
        assertEquals(false, GreenVpnConnectionOperationPolicy.isCurrentOperation("connect-1", "disconnect-2"))
        assertEquals(false, GreenVpnConnectionOperationPolicy.isCurrentOperation("disconnect-2", "connect-3"))
        assertEquals(false, GreenVpnConnectionOperationPolicy.isCurrentOperation("", "connect-3"))
    }

    @Test
    fun pendingConnectStartsOnlyWithPermissionAndValidatedNetwork() {
        assertEquals(
            true,
            GreenVpnConnectionOperationPolicy.shouldStartConnect(
                desired = true,
                state = "queued",
                permissionGranted = true,
                validatedUnderlyingNetwork = true,
            ),
        )
        assertEquals(
            false,
            GreenVpnConnectionOperationPolicy.shouldStartConnect(
                desired = true,
                state = "queued",
                permissionGranted = true,
                validatedUnderlyingNetwork = false,
            ),
        )
        assertEquals(
            false,
            GreenVpnConnectionOperationPolicy.shouldStartConnect(
                desired = true,
                state = "permission_required",
                permissionGranted = false,
                validatedUnderlyingNetwork = true,
            ),
        )
    }

    @Test
    fun missingUnderlyingNetworkPreservesAnExistingTunnel() {
        assertEquals(
            "degraded_no_network",
            GreenVpnConnectionOperationPolicy.stateWithoutUnderlyingNetwork(
                ownEngineConnected = true,
            ),
        )
        assertEquals(
            "waiting_for_network",
            GreenVpnConnectionOperationPolicy.stateWithoutUnderlyingNetwork(
                ownEngineConnected = false,
            ),
        )
        assertEquals(
            true,
            GreenVpnConnectionOperationPolicy.shouldPreserveTunnelAfterProbeFailure(
                validatedUnderlyingNetwork = false,
            ),
        )
    }

    @Test
    fun probesAndRecoveryAreSuppressedWithoutUnderlyingNetwork() {
        assertEquals(
            false,
            GreenVpnConnectionOperationPolicy.shouldProbeOrRecover(
                desired = true,
                validatedUnderlyingNetwork = false,
            ),
        )
        assertEquals(
            true,
            GreenVpnConnectionOperationPolicy.shouldProbeOrRecover(
                desired = true,
                validatedUnderlyingNetwork = true,
            ),
        )
    }

    @Test
    fun permissionQueryNeverRunsWhileAnySystemVpnIsActive() {
        assertEquals(
            false,
            GreenVpnConnectionOperationPolicy.shouldQueryVpnPermission(
                systemVpnActive = true,
            ),
        )
        assertEquals(
            true,
            GreenVpnConnectionOperationPolicy.shouldQueryVpnPermission(
                systemVpnActive = false,
            ),
        )
    }
}
