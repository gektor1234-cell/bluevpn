package pro.greenvpn.app

import android.content.Context

object GreenVpnDnsttPreview {
    data class Snapshot(
        val available: Boolean,
        val connected: Boolean,
        val state: String,
        val rxBytes: Long = 0L,
        val txBytes: Long = 0L,
        val version: String = "",
        val error: String = ""
    )

    private const val CONTROLLER_CLASS = "pro.greenvpn.dnstt.DnsttController"

    fun isAvailable(context: Context): Boolean {
        if (!BuildConfig.GREENVPN_DNSTT_PREVIEW_ENABLED) return false
        return try {
            invoke("isAvailable", arrayOf(Context::class.java), context.applicationContext) as? Boolean == true
        } catch (_: Throwable) { false }
    }

    fun validateConfig(configText: String): String {
        ensureAvailable()
        return invoke("validateConfig", arrayOf(String::class.java), configText)?.toString()
            ?: throw IllegalStateException("Transport validator returned no config")
    }

    fun connect(context: Context, configText: String): Boolean {
        ensureAvailable()
        return invoke(
            "connect", arrayOf(Context::class.java, String::class.java), context.applicationContext, configText
        ) as? Boolean == true
    }

    fun disconnect(context: Context): Boolean {
        if (!isAvailable(context)) return true
        return invoke("disconnect", arrayOf(Context::class.java), context.applicationContext) as? Boolean == true
    }

    fun snapshot(context: Context): Snapshot {
        if (!isAvailable(context)) return Snapshot(false, false, "unavailable")
        return try {
            val raw = invoke("snapshot", arrayOf(Context::class.java), context.applicationContext) as? Map<*, *>
                ?: emptyMap<Any, Any>()
            Snapshot(
                raw["available"] as? Boolean == true,
                raw["connected"] as? Boolean == true,
                raw["state"]?.toString().orEmpty().ifEmpty { "unknown" },
                (raw["rxBytes"] as? Number)?.toLong() ?: 0L,
                (raw["txBytes"] as? Number)?.toLong() ?: 0L,
                raw["version"]?.toString().orEmpty(),
                raw["error"]?.toString().orEmpty()
            )
        } catch (failure: Throwable) {
            Snapshot(true, false, "error", error = rootMessage(failure))
        }
    }

    private fun invoke(name: String, parameterTypes: Array<Class<*>>, vararg args: Any): Any? =
        Class.forName(CONTROLLER_CLASS).getMethod(name, *parameterTypes).invoke(null, *args)

    private fun ensureAvailable() {
        if (!BuildConfig.GREENVPN_DNSTT_PREVIEW_ENABLED) {
            throw IllegalStateException("Transport preview engine is not included in this build")
        }
        Class.forName(CONTROLLER_CLASS)
    }

    private fun rootMessage(error: Throwable): String {
        var current = error
        while (current.cause != null && current.cause !== current) current = current.cause!!
        return current.message?.trim().takeUnless { it.isNullOrEmpty() } ?: current.javaClass.simpleName
    }
}
