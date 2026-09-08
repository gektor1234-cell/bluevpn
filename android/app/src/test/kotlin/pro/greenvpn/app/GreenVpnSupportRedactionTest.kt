package pro.greenvpn.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GreenVpnSupportRedactionTest {
    @Test fun removesCredentials() {
        assertEquals("[redacted]", GreenVpnSupportRedaction.text("Bearer synthetic-value"))
        assertEquals("[redacted]", GreenVpnSupportRedaction.text("PrivateKey = synthetic-value"))
        assertEquals("[opaque]", GreenVpnSupportRedaction.text("X".repeat(44)))
    }

    @Test fun removesNetworkAndEmailIdentity() {
        val result = GreenVpnSupportRedaction.text("192.0.2.1 2001:db8::1 somebody@example.test https://example.test/path")
        assertFalse(result.contains("192.0.2.1"))
        assertFalse(result.contains("2001:db8"))
        assertFalse(result.contains("somebody"))
        assertFalse(result.contains("example.test"))
    }

    @Test fun preservesDiagnosticCodesAndBoundsLength() {
        assertEquals("HTTP 401", GreenVpnSupportRedaction.text("HTTP 401"))
        assertEquals("session_expired", GreenVpnSupportRedaction.text("session_expired"))
        assertTrue(GreenVpnSupportRedaction.text("short ".repeat(1000)).length <= 180)
        assertEquals("a b", GreenVpnSupportRedaction.text("a\nb"))
    }
}
