package pro.greenvpn.app

import java.util.concurrent.locks.ReentrantLock

internal object GreenVpnConnectionOperationGate {
    private val lock = ReentrantLock(true)

    fun <T> runExclusive(operation: () -> T): T {
        lock.lockInterruptibly()
        return try {
            operation()
        } finally {
            lock.unlock()
        }
    }

    fun awaitIdle() {
        runExclusive { Unit }
    }
}
