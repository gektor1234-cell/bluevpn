package pro.greenvpn.app

import android.content.Context

object GreenVpnVlessRealityPreview {
    data class Snapshot(
        val available: Boolean,
        val connected: Boolean,
        val state: String,
        val rxBytes: Long = 0L,
        val txBytes: Long = 0L,
        val version: String = "",
        val error: String = ""
    )

    private const val CONTROLLER_CLASS = "pro.greenvpn.vless.VlessRealityController"

    fun isAvailable(context: Context): Boolean {
        if (!BuildConfig.GREENVPN_VLESS_REALITY_PREVIEW_ENABLED) return false
        return try {
            invoke("isAvailable", arrayOf(Context::class.java), context.applicationContext) as? Boolean == true
        } catch (_: Throwable) {
            false
        }
    }

    fun validateConfig(configText: String): String {
        ensureAvailable()
        return invoke("validateConfig", arrayOf(String::class.java), configText)?.toString()
            ?: throw IllegalStateException("Transport validator returned no config")
    }

    fun connect(context: Context, configText: String): Boolean {
        ensureAvailable()
        return invoke(
            "connect",
            arrayOf(Context::class.java, String::class.java),
            context.applicationContext,
            configText
        ) as? Boolean == true
    }

    fun disconnect(context: Context): Boolean {
        if (!isAvailable(context)) return true
        return invoke(
            "disconnect",
            arrayOf(Context::class.java),
            context.applicationContext
        ) as? Boolean == true
    }

    fun snapshot(context: Context): Snapshot {
        if (!isAvailable(context)) return Snapshot(false, false, "unavailable")
        return try {
            val raw = invoke(
                "snapshot",
                arrayOf(Context::class.java),
                context.applicationContext
            ) as? Map<*, *> ?: emptyMap<Any, Any>()
            Snapshot(
                available = raw["available"] as? Boolean == true,
                connected = raw["connected"] as? Boolean == true,
                state = raw["state"]?.toString().orEmpty().ifEmpty { "unknown" },
                rxBytes = (raw["rxBytes"] as? Number)?.toLong() ?: 0L,
                txBytes = (raw["txBytes"] as? Number)?.toLong() ?: 0L,
                version = raw["version"]?.toString().orEmpty(),
                error = raw["error"]?.toString().orEmpty()
            )
        } catch (failure: Throwable) {
            Snapshot(true, false, "error", error = rootMessage(failure))
        }
    }

    private fun invoke(name: String, parameterTypes: Array<Class<*>>, vararg args: Any): Any? {
        val controller = Class.forName(CONTROLLER_CLASS)
        return controller.getMethod(name, *parameterTypes).invoke(null, *args)
    }

    private fun ensureAvailable() {
        if (!BuildConfig.GREENVPN_VLESS_REALITY_PREVIEW_ENABLED) {
            throw IllegalStateException("Transport preview engine is not included in this build")
        }
        Class.forName(CONTROLLER_CLASS)
    }

    private fun rootMessage(error: Throwable): String {
        var current = error
        while (current.cause != null && current.cause !== current) current = current.cause!!
        return current.message?.trim().takeUnless { it.isNullOrEmpty() }
            ?: current.javaClass.simpleName
    }
}
