package pro.greenvpn.app

import java.io.Closeable

/** Closing a Future alone does not interrupt blocking Android socket I/O. */
internal class GreenVpnProbeResources : Closeable {
    private val resources = mutableListOf<Closeable>()
    private var closed = false

    @Synchronized
    fun track(resource: Closeable) {
        if (closed) {
            resource.close()
            throw InterruptedException("probe cancelled")
        }
        resources.add(resource)
    }

    override fun close() {
        val closing = synchronized(this) {
            if (closed) return
            closed = true
            resources.toList().also { resources.clear() }
        }
        closing.forEach { try { it.close() } catch (_: Exception) {} }
    }
}
