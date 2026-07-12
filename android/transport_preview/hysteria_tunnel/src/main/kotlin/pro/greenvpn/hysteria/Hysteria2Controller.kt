package pro.greenvpn.hysteria

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import java.io.File

object Hysteria2Controller {
    @JvmStatic
    fun isAvailable(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            Hysteria2VpnService.ensureNativeLoaded()
            Hysteria2VpnService.hysteriaBinary(context).isFile
        } catch (_: Throwable) {
            false
        }
    }

    @JvmStatic
    fun validateConfig(configText: String): String = Hysteria2Config.validate(configText)

    @JvmStatic
    fun connect(context: Context, configText: String): Boolean {
        require(isAvailable(context)) { "Hysteria2 preview engine is unavailable" }
        val validated = Hysteria2Config.validate(configText)
        val root = Hysteria2VpnService.runtimeRoot(context)
        require(root.exists() || root.mkdirs()) { "Hysteria2 runtime directory was not created" }
        val config = File(root, "base.yaml")
        config.writeText(validated, Charsets.UTF_8)
        require(config.setReadable(false, false) && config.setReadable(true, true)) {
            "Hysteria2 config permissions were not restricted"
        }
        config.setWritable(true, true)
        val intent = Intent(context, Hysteria2VpnService::class.java)
            .setAction(Hysteria2VpnService.ACTION_CONNECT)
            .putExtra(Hysteria2VpnService.EXTRA_CONFIG_PATH, config.canonicalPath)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        return waitForState("up", 25_000L)
    }

    @JvmStatic
    fun disconnect(context: Context): Boolean {
        if (!isAvailable(context)) return true
        if (!Hysteria2VpnService.requestDisconnect(context)) return false
        return waitForState("down", 12_000L)
    }

    @JvmStatic
    fun snapshot(context: Context): Map<String, Any> {
        val current = Hysteria2VpnService.snapshot()
        return linkedMapOf(
            "available" to isAvailable(context),
            "connected" to (current.state == "up"),
            "state" to current.state,
            "rxBytes" to current.rxBytes,
            "txBytes" to current.txBytes,
            "version" to current.version,
            "error" to current.error
        )
    }

    private fun waitForState(expected: String, timeoutMs: Long): Boolean {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        do {
            val state = Hysteria2VpnService.snapshot().state
            if (state == expected) return true
            if (state == "error" && expected != "down") return false
            Thread.sleep(100L)
        } while (SystemClock.elapsedRealtime() < deadline)
        return Hysteria2VpnService.snapshot().state == expected
    }
}
