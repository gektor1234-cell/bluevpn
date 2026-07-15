package pro.greenvpn.routing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Ipv4RouteExclusionsTest {
    @Test
    fun noExclusionsUsesDefaultRoute() {
        assertEquals(
            listOf(Ipv4RouteExclusions.Route("0.0.0.0", 0)),
            Ipv4RouteExclusions.routesExcluding(emptyList()),
        )
    }

    @Test
    fun oneEndpointIsExcludedAndBothNeighborsRemainRouted() {
        val routes = Ipv4RouteExclusions.routesExcluding(listOf("5.129.216.42"))

        assertFalse(routes.any { Ipv4RouteExclusions.contains(it, "5.129.216.42") })
        assertTrue(routes.any { Ipv4RouteExclusions.contains(it, "5.129.216.41") })
        assertTrue(routes.any { Ipv4RouteExclusions.contains(it, "5.129.216.43") })
        assertEquals((1L shl 32) - 1L, coveredAddressCount(routes))
    }

    @Test
    fun multipleEndpointsAreExcludedWithoutCreatingOtherHoles() {
        val excluded = listOf("1.1.1.1", "5.129.216.42", "8.8.8.8")
        val routes = Ipv4RouteExclusions.routesExcluding(excluded)

        excluded.forEach { address ->
            assertFalse(routes.any { Ipv4RouteExclusions.contains(it, address) })
        }
        assertTrue(routes.any { Ipv4RouteExclusions.contains(it, "1.1.1.2") })
        assertTrue(routes.any { Ipv4RouteExclusions.contains(it, "8.8.4.4") })
        assertEquals((1L shl 32) - excluded.size, coveredAddressCount(routes))
    }

    private fun coveredAddressCount(routes: List<Ipv4RouteExclusions.Route>): Long =
        routes.sumOf { 1L shl (32 - it.prefixLength) }
}
