package pro.greenvpn.hysteria

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class Hysteria2DebugReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread({
            try {
                val command = intent.getStringExtra("command").orEmpty().trim().lowercase()
                when (command) {
                    "connect" -> {
                        val config = File(context.filesDir, CONFIG_NAME).canonicalFile
                        require(config.parentFile == context.filesDir.canonicalFile && config.isFile) {
                            "Debug Hysteria2 config is missing"
                        }
                        require(config.length() in 1..131_072) { "Debug Hysteria2 config size is invalid" }
                        Hysteria2Controller.connect(context, config.readText(Charsets.UTF_8))
                    }
                    "disconnect" -> Hysteria2Controller.disconnect(context)
                    "kill_engine" -> require(Hysteria2VpnService.debugKillEngineForTest()) {
                        "Hysteria2 debug engine is not running"
                    }
                    "status" -> Unit
                    else -> throw IllegalArgumentException("Unsupported debug command")
                }
                writeResult(context, command, "", includeNetworkProbes = false)
            } catch (failure: Throwable) {
                writeResult(context, "error", safeMessage(failure), includeNetworkProbes = false)
            } finally {
                pending.finish()
            }
        }, "GreenVPN-H2-Debug-Control").start()
    }

    private fun writeResult(
        context: Context,
        command: String,
        commandError: String,
        includeNetworkProbes: Boolean,
    ) {
        val snapshot = Hysteria2Controller.snapshot(context)
        val connected = snapshot["connected"] == true
        val shouldProbe = connected && includeNetworkProbes
        val egress = if (shouldProbe) probe("https://api.ipify.org") else Probe()
        val production = if (shouldProbe) probe("https://api.greenvpn.pro/healthz") else Probe()
        val paidPrimary = if (shouldProbe) probe("https://api.greenvpn.pro/paid-beta-api/healthz") else Probe()
        val paidFallback = if (shouldProbe) probe("https://176-113-81-35.sslip.io/paid-beta-api/healthz") else Probe()
        val youtube = if (shouldProbe) probe("https://www.youtube.com/") else Probe()
        val result = JSONObject()
            .put("command", command)
            .put("available", snapshot["available"])
            .put("connected", snapshot["connected"])
            .put("state", snapshot["state"])
            .put("rxBytes", snapshot["rxBytes"])
            .put("txBytes", snapshot["txBytes"])
            .put("version", snapshot["version"])
            .put("engineError", snapshot["error"])
            .put("commandError", commandError)
            .put("canaryEgress", egress.body.trim())
            .put("egressStatus", egress.status)
            .put("productionApiStatus", production.status)
            .put("paidBetaPrimaryStatus", paidPrimary.status)
            .put("paidBetaFallbackStatus", paidFallback.status)
            .put("youtubeStatus", youtube.status)
            .put("wallTimeMs", System.currentTimeMillis())
        File(context.filesDir, RESULT_NAME).writeText(result.toString(), Charsets.UTF_8)
    }

    private fun safeMessage(error: Throwable): String {
        var current = error
        while (current.cause != null && current.cause !== current) current = current.cause!!
        return (current.message ?: current.javaClass.simpleName)
            .replace(Regex("[\\r\\n]+"), " ")
            .take(240)
    }

    private fun probe(uri: String): Probe {
        return try {
            val connection = URL(uri).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = true
            connection.connectTimeout = 12_000
            connection.readTimeout = 12_000
            connection.requestMethod = "GET"
            connection.setRequestProperty("User-Agent", "GreenVPN-Transport-Preview")
            val status = connection.responseCode
            val stream = if (status in 200..399) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText().take(256) }.orEmpty()
            connection.disconnect()
            Probe(status, body)
        } catch (_: Throwable) {
            Probe()
        }
    }

    private data class Probe(val status: Int = 0, val body: String = "")

    companion object {
        const val CONFIG_NAME = "greenvpn-h2-debug.yaml"
        const val RESULT_NAME = "greenvpn-h2-debug-result.json"
    }
}
