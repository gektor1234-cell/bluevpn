package pro.greenvpn.naive

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.io.File

class NaiveHttpsDebugReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread({
            try {
                val command = intent.getStringExtra("command").orEmpty().trim().lowercase()
                when (command) {
                    "connect" -> {
                        val config = File(context.filesDir, CONFIG_NAME).canonicalFile
                        require(config.parentFile == context.filesDir.canonicalFile && config.isFile) {
                            "Debug transport config is missing"
                        }
                        require(config.length() in 64..16_384) { "Debug transport config size is invalid" }
                        NaiveHttpsController.connect(context, config.readText(Charsets.UTF_8))
                    }
                    "disconnect" -> NaiveHttpsController.disconnect(context)
                    "kill_engine" -> require(NaiveHttpsVpnService.debugKillEngineForTest()) {
                        "Debug transport engine is not running"
                    }
                    "status" -> Unit
                    else -> throw IllegalArgumentException("Unsupported debug command")
                }
                writeResult(context, command, "")
            } catch (failure: Throwable) {
                writeResult(context, "error", safeMessage(failure))
            } finally { pending.finish() }
        }, "GreenVPN-Naive-Debug-Control").start()
    }

    private fun writeResult(context: Context, command: String, commandError: String) {
        val snapshot = NaiveHttpsController.snapshot(context)
        val result = JSONObject().put("command", command).put("available", snapshot["available"])
            .put("connected", snapshot["connected"]).put("state", snapshot["state"])
            .put("rxBytes", snapshot["rxBytes"]).put("txBytes", snapshot["txBytes"])
            .put("version", snapshot["version"]).put("engineError", snapshot["error"])
            .put("commandError", commandError).put("wallTimeMs", System.currentTimeMillis())
        File(context.filesDir, RESULT_NAME).writeText(result.toString(), Charsets.UTF_8)
    }

    private fun safeMessage(error: Throwable): String {
        var current = error
        while (current.cause != null && current.cause !== current) current = current.cause!!
        return (current.message ?: current.javaClass.simpleName).replace(Regex("[\\r\\n]+"), " ").take(240)
    }

    companion object {
        const val CONFIG_NAME = "greenvpn-naive-debug.json"
        const val RESULT_NAME = "greenvpn-naive-debug-result.json"
    }
}
