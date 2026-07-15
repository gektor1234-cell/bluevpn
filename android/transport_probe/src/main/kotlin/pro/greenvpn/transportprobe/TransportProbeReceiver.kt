package pro.greenvpn.transportprobe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class TransportProbeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread({
            try {
                val targets = mapOf(
                    "egress" to "https://1.1.1.1/cdn-cgi/trace",
                    "egressAlternate" to "https://api.ipify.org",
                    "productionApi" to "https://api.greenvpn.pro/healthz",
                    "paidBetaPrimary" to "https://api.greenvpn.pro/paid-beta-api/healthz",
                    "paidBetaFallback" to "https://176-113-81-35.sslip.io/paid-beta-api/healthz",
                    "youtube" to "https://www.youtube.com/generate_204"
                )
                val target = intent.getStringExtra("target").orEmpty().trim()
                val uri = targets[target] ?: throw IllegalArgumentException("Unsupported probe target")
                val timeoutMs = intent.getIntExtra("timeoutMs", DEFAULT_TIMEOUT_MS)
                    .coerceIn(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS)
                val probe = probe(uri, timeoutMs)
                val result = JSONObject()
                    .put("target", target)
                    .put("timeoutMs", timeoutMs)
                    .put("status", probe.status)
                    .put("body", probe.body.trim())
                    .put("error", probe.error)
                    .put("wallTimeMs", System.currentTimeMillis())
                File(context.filesDir, RESULT_NAME).writeText(result.toString(), Charsets.UTF_8)
            } catch (failure: Throwable) {
                File(context.filesDir, RESULT_NAME).writeText(
                    JSONObject()
                        .put("target", "error")
                        .put("status", 0)
                        .put("body", "")
                        .put("error", failure.javaClass.simpleName)
                        .toString(),
                    Charsets.UTF_8
                )
            } finally {
                pending.finish()
            }
        }, "GreenVPN-External-Transport-Probe").start()
    }

    private fun probe(uri: String, timeoutMs: Int): Probe = try {
        val connection = URL(uri).openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = true
        connection.connectTimeout = timeoutMs
        connection.readTimeout = timeoutMs
        connection.requestMethod = "GET"
        connection.setRequestProperty("User-Agent", "GreenVPN-External-Transport-Probe")
        val status = connection.responseCode
        val stream = if (status in 200..399) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText().take(256) }.orEmpty()
        connection.disconnect()
        Probe(status, body)
    } catch (failure: Throwable) {
        Probe(
            error = buildString {
                append(failure.javaClass.simpleName)
                failure.message?.trim()?.takeIf { it.isNotEmpty() }?.let {
                    append(": ")
                    append(it.replace(Regex("[\\r\\n]+"), " ").take(240))
                }
            }
        )
    }

    private data class Probe(
        val status: Int = 0,
        val body: String = "",
        val error: String = ""
    )

    companion object {
        const val RESULT_NAME = "transport-probe-result.json"
        private const val DEFAULT_TIMEOUT_MS = 5_000
        private const val MIN_TIMEOUT_MS = 1_000
        private const val MAX_TIMEOUT_MS = 60_000
    }
}
