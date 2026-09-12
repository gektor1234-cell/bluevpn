package pro.greenvpn.app

internal class GreenVpnFeedbackPolicy(var connected: Boolean = false) {
    private var failedOperation = ""
    fun confirmed(): String? {
        if (connected) return null
        connected = true
        failedOperation = ""
        return "connected"
    }
    fun disconnected(): String? {
        if (!connected) return null
        connected = false
        return "disconnected"
    }
    fun failed(operation: String, terminal: Boolean): String? {
        if (!terminal || operation.isBlank() || operation == failedOperation) return null
        failedOperation = operation
        connected = false
        return "failed"
    }
}
