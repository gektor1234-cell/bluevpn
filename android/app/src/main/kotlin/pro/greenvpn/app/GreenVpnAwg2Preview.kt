package pro.greenvpn.app

import android.content.Context
import java.io.ByteArrayInputStream
import java.lang.reflect.Proxy
import java.nio.charset.StandardCharsets

object GreenVpnAwg2Preview {
    data class Snapshot(
        val available: Boolean,
        val connected: Boolean,
        val state: String,
        val runningTunnels: List<String> = emptyList(),
        val rxBytes: Long = 0L,
        val txBytes: Long = 0L,
        val version: String = "",
        val error: String = ""
    )

    private const val BACKEND_CLASS = "org.amnezia.awg.backend.GoBackend"
    private const val TUNNEL_CLASS = "org.amnezia.awg.backend.Tunnel"
    private const val STATE_CLASS = "org.amnezia.awg.backend.Tunnel\$State"
    private const val CONFIG_CLASS = "org.amnezia.awg.config.Config"
    private const val TUNNEL_NAME = "GreenVPN"
    private val lock = Any()

    @Volatile
    private var backend: Any? = null

    @Volatile
    private var tunnel: Any? = null

    fun isAvailable(): Boolean {
        if (!BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) return false
        return try {
            Class.forName(BACKEND_CLASS)
            Class.forName(CONFIG_CLASS)
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun parseConfig(configText: String): Any {
        ensureAvailable()
        val configClass = Class.forName(CONFIG_CLASS)
        val parse = configClass.getMethod("parse", java.io.InputStream::class.java)
        return parse.invoke(
            null,
            ByteArrayInputStream(configText.toByteArray(StandardCharsets.UTF_8))
        ) ?: throw IllegalStateException("AWG2 parser returned no config")
    }

    fun connect(context: Context, parsedConfig: Any): Boolean = synchronized(lock) {
        ensureAvailable()
        val currentBackend = backend(context)
        val currentTunnel = tunnel()
        val setState = currentBackend.javaClass.methods.first {
            it.name == "setState" && it.parameterTypes.size == 3
        }
        if (runningTunnelNames(currentBackend).contains(TUNNEL_NAME)) {
            setState.invoke(currentBackend, currentTunnel, state("DOWN"), null)
        }
        val result = setState.invoke(currentBackend, currentTunnel, state("UP"), parsedConfig)
        enumName(result) == "UP"
    }

    fun disconnect(context: Context): Boolean = synchronized(lock) {
        if (!isAvailable()) return@synchronized true
        val currentBackend = backend(context)
        val currentTunnel = tunnel()
        val setState = currentBackend.javaClass.methods.first {
            it.name == "setState" && it.parameterTypes.size == 3
        }
        val result = setState.invoke(currentBackend, currentTunnel, state("DOWN"), null)
        enumName(result) == "DOWN" && !runningTunnelNames(currentBackend).contains(TUNNEL_NAME)
    }

    fun snapshot(context: Context): Snapshot = synchronized(lock) {
        if (!isAvailable()) return@synchronized Snapshot(false, false, "unavailable")
        try {
            val currentBackend = backend(context)
            val currentTunnel = tunnel()
            val running = runningTunnelNames(currentBackend)
            val getState = currentBackend.javaClass.methods.first {
                it.name == "getState" && it.parameterTypes.size == 1
            }
            val state = enumName(getState.invoke(currentBackend, currentTunnel)).lowercase()
            val connected = state == "up" || running.contains(TUNNEL_NAME)
            var rx = 0L
            var tx = 0L
            if (connected) {
                val getStatistics = currentBackend.javaClass.methods.firstOrNull {
                    it.name == "getStatistics" && it.parameterTypes.size == 1
                }
                val stats = getStatistics?.invoke(currentBackend, currentTunnel)
                rx = invokeLong(stats, "totalRx")
                tx = invokeLong(stats, "totalTx")
            }
            val version = currentBackend.javaClass.getMethod("getVersion").invoke(currentBackend)
                ?.toString().orEmpty()
            Snapshot(true, connected, state, running, rx, tx, version)
        } catch (error: Throwable) {
            Snapshot(true, false, "error", error = rootMessage(error))
        }
    }

    private fun backend(context: Context): Any {
        backend?.let { return it }
        return Class.forName(BACKEND_CLASS)
            .getConstructor(Context::class.java)
            .newInstance(context.applicationContext)
            .also { backend = it }
    }

    private fun tunnel(): Any {
        tunnel?.let { return it }
        val tunnelClass = Class.forName(TUNNEL_CLASS)
        return Proxy.newProxyInstance(
            tunnelClass.classLoader,
            arrayOf(tunnelClass)
        ) { proxy, method, args ->
            when (method.name) {
                "getName" -> TUNNEL_NAME
                "onStateChange" -> null
                "hashCode" -> System.identityHashCode(proxy)
                "equals" -> proxy === args?.firstOrNull()
                "toString" -> "GreenVpnAwg2Tunnel($TUNNEL_NAME)"
                else -> null
            }
        }.also { tunnel = it }
    }

    private fun state(name: String): Any {
        val constants = requireNotNull(Class.forName(STATE_CLASS).enumConstants) {
            "$STATE_CLASS is not an enum"
        }
        return constants.first { enumName(it) == name }
    }

    private fun runningTunnelNames(currentBackend: Any): List<String> {
        val raw = currentBackend.javaClass.getMethod("getRunningTunnelNames").invoke(currentBackend)
        return (raw as? Iterable<*>)?.map { it.toString() } ?: emptyList()
    }

    private fun enumName(value: Any?): String = (value as? Enum<*>)?.name.orEmpty()

    private fun invokeLong(target: Any?, method: String): Long {
        if (target == null) return 0L
        return (target.javaClass.getMethod(method).invoke(target) as? Number)?.toLong() ?: 0L
    }

    private fun ensureAvailable() {
        if (!isAvailable()) {
            throw IllegalStateException("AWG2 preview engine is not included in this build")
        }
    }

    private fun rootMessage(error: Throwable): String {
        var current = error
        while (current.cause != null && current.cause !== current) {
            current = current.cause!!
        }
        return current.message?.trim().takeUnless { it.isNullOrEmpty() }
            ?: current.javaClass.simpleName
    }
}
