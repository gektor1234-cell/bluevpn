package pro.greenvpn.app

object GreenVpnApiFailurePolicy {
    fun requiresAuthentication(message: String): Boolean =
        message == "session_expired" || message == "session_or_device_missing" ||
            Regex("\\bHTTP 401\\b", RegexOption.IGNORE_CASE).containsMatchIn(message)
}
