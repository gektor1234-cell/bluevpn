package pro.greenvpn.app

import java.io.Closeable
import org.junit.Assert.*
import org.junit.Test

class GreenVpnProbeResourcesTest {
    @Test fun timeoutClosesEveryResourceEvenIfOneCloseFails() {
        val scope = GreenVpnProbeResources()
        var closed = 0
        scope.track(Closeable { closed++; throw IllegalStateException() })
        scope.track(Closeable { closed++ })
        scope.close()
        scope.close()
        assertEquals(2, closed)
    }
    @Test fun lateSocketCannotOutliveCancellation() {
        val scope = GreenVpnProbeResources()
        scope.close()
        var closed = false
        try {
            scope.track(Closeable { closed = true })
            fail("must reject late socket")
        } catch (_: InterruptedException) {}
        assertTrue(closed)
    }
}
