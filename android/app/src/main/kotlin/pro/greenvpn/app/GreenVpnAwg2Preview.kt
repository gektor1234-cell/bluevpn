package pro.greenvpn.app

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.nio.charset.StandardCharsets
import java.util.UUID

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

    private data class StoredState(
        val operationId: String,
        val snapshot: Snapshot,
    )

    private const val CONFIG_CLASS = "org.amnezia.awg.config.Config"
    private const val SERVICE_CLASS = "pro.greenvpn.awg2.GreenVpnAwg2VpnService"
    private const val ACTION_CONNECT = "pro.greenvpn.awg2.action.CONNECT"
    private const val ACTION_DISCONNECT = "pro.greenvpn.awg2.action.DISCONNECT"
    private const val EXTRA_OPERATION_ID = "operationId"
    private const val EXTRA_CONFIG = "config"
    private const val STATE_FILE = "greenvpn_awg2_state.json"
    private const val COMMAND_TIMEOUT_MS = 20_000L
    private val lock = Any()

    fun isAvailable(): Boolean {
        if (!BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) return false
        return try {
            Class.forName(CONFIG_CLASS, false, GreenVpnAwg2Preview::class.java.classLoader)
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun parseConfig(configText: String): Any {
        ensureAvailable()
        val configClass = Class.forName(CONFIG_CLASS)
        val parse = configClass.getMethod("parse", java.io.InputStream::class.java)
        parse.invoke(
            null,
            ByteArrayInputStream(configText.toByteArray(StandardCharsets.UTF_8))
        ) ?: throw IllegalStateException("AWG2 parser returned no config")
        return configText
    }

    fun connect(context: Context, parsedConfig: Any): Boolean = synchronized(lock) {
        ensureAvailable()
        val configText = parsedConfig as? String
            ?: throw IllegalArgumentException("AWG2 config must be validated before connect")
        val result = execute(context, ACTION_CONNECT, configText)
        result.connected && result.state == "up"
    }

    fun disconnect(context: Context): Boolean = synchronized(lock) {
        if (!isAvailable()) return@synchronized true
        val current = snapshot(context)
        if (!current.connected && current.state !in setOf("starting", "error")) {
            return@synchronized true
        }
        val result = execute(context, ACTION_DISCONNECT)
        !result.connected && result.state == "down"
    }

    fun snapshot(context: Context): Snapshot {
        if (!isAvailable()) return Snapshot(false, false, "unavailable")
        val stored = readState(context)?.snapshot ?: Snapshot(true, false, "down")
        if (stored.connected && !isAnyVpnNetworkActive(context)) {
            return stored.copy(connected = false, state = "down", runningTunnels = emptyList())
        }
        return stored
    }

    private fun execute(context: Context, action: String, configText: String = ""): Snapshot {
        val appContext = context.applicationContext
        val operationId = UUID.randomUUID().toString()
        val intent = Intent(action)
            .setClassName(appContext.packageName, SERVICE_CLASS)
            .putExtra(EXTRA_OPERATION_ID, operationId)
        if (configText.isNotEmpty()) intent.putExtra(EXTRA_CONFIG, configText)

        try {
            appContext.startService(intent)
        } catch (error: Throwable) {
            return Snapshot(true, false, "error", error = rootMessage(error))
        }

        val deadline = System.nanoTime() + COMMAND_TIMEOUT_MS * 1_000_000L
        while (System.nanoTime() < deadline) {
            val stored = readState(appContext)
            if (stored?.operationId == operationId && stored.snapshot.state != "starting") {
                return stored.snapshot
            }
            Thread.sleep(50L)
        }
        return Snapshot(true, false, "error", error = "AWG2 service command timed out")
    }

    private fun readState(context: Context): StoredState? {
        val file = context.noBackupFilesDir.resolve(STATE_FILE)
        if (!file.isFile) return null
        return try {
            val json = JSONObject(file.readText(StandardCharsets.UTF_8))
            val running = json.optJSONArray("runningTunnels")
            val runningTunnels = buildList {
                if (running != null) {
                    for (index in 0 until running.length()) {
                        running.optString(index).trim().takeIf { it.isNotEmpty() }?.let(::add)
                    }
                }
            }
            StoredState(
                operationId = json.optString("operationId"),
                snapshot = Snapshot(
                    available = true,
                    connected = json.optBoolean("connected"),
                    state = json.optString("state", "down"),
                    runningTunnels = runningTunnels,
                    rxBytes = json.optLong("rxBytes"),
                    txBytes = json.optLong("txBytes"),
                    error = json.optString("error"),
                ),
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun isAnyVpnNetworkActive(context: Context): Boolean {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return manager.allNetworks.any { network ->
            manager.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        }
    }

    private fun ensureAvailable() {
        if (!isAvailable()) {
            throw IllegalStateException("AWG2 preview engine is not included in this build")
        }
    }

    private fun rootMessage(error: Throwable): String {
        var current = error
        while (current.cause != null && current.cause !== current) current = current.cause!!
        return current.message?.trim().takeUnless { it.isNullOrEmpty() }
            ?: current.javaClass.simpleName
    }
}
