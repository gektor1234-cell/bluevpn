package pro.greenvpn.vless

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.io.File

class VlessRealityDebugReceiver : BroadcastReceiver() {
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
                        require(config.length() in 128..131_072) { "Debug transport config size is invalid" }
                        VlessRealityController.connect(context, config.readText(Charsets.UTF_8))
                    }
                    "disconnect" -> VlessRealityController.disconnect(context)
                    "kill_engine" -> require(VlessRealityVpnService.debugKillEngineForTest()) {
                        "Debug transport engine is not running"
                    }
                    "stop_tun" -> require(VlessRealityVpnService.debugStopTunForTest()) {
                        "Debug transport tunnel is not running"
                    }
                    "status" -> Unit
                    else -> throw IllegalArgumentException("Unsupported debug command")
                }
                writeResult(context, command, "")
            } catch (failure: Throwable) {
                writeResult(context, "error", safeMessage(failure))
            } finally {
                pending.finish()
            }
        }, "GreenVPN-VLESS-Debug-Control").start()
    }

    private fun writeResult(context: Context, command: String, commandError: String) {
        val snapshot = VlessRealityController.snapshot(context)
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

    companion object {
        const val CONFIG_NAME = "greenvpn-vless-debug.json"
        const val RESULT_NAME = "greenvpn-vless-debug-result.json"
    }
}
