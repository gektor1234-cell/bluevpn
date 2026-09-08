package pro.greenvpn.app

object GreenVpnSupportRedaction {
    fun text(value: String): String = value
        .replace(Regex("(?i)(bearer\\s+\\S+|(?:token|password|privatekey|secret)\\s*[:=]\\s*\\S+)"), "[redacted]")
        .replace(Regex("https?://\\S+"), "[url]")
        .replace(Regex("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+"), "[email]")
        .replace(Regex("\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b"), "[ip]")
        .replace(Regex("(?:[0-9a-fA-F]{0,4}:){2,}[0-9a-fA-F:.%]+"), "[ip]")
        .replace(Regex("[A-Za-z0-9+/=_-]{40,}"), "[opaque]")
        .replace(Regex("[\\r\\n]+"), " ").take(180)
}
