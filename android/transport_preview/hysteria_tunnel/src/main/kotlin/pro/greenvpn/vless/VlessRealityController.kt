package pro.greenvpn.vless

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import java.io.File

object VlessRealityController {
    @JvmStatic
    fun isAvailable(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            try { VlessRealityVpnService.xrayBinary(context).isFile } catch (_: Throwable) { false }

    @JvmStatic
    fun validateConfig(configText: String): String = VlessRealityConfig.validate(configText)

    @JvmStatic
    fun connect(context: Context, configText: String): Boolean {
        require(isAvailable(context)) { "VLESS REALITY preview engine is unavailable" }
        val root = VlessRealityVpnService.runtimeRoot(context)
        require(root.exists() || root.mkdirs()) { "VLESS REALITY runtime directory was not created" }
        val config = File(root, "base.json")
        config.writeText(VlessRealityConfig.validate(configText), Charsets.UTF_8)
        require(config.setReadable(false, false) && config.setReadable(true, true)) {
            "VLESS REALITY config permissions were not restricted"
        }
        config.setWritable(true, true)
        VlessRealityVpnService.prepareForConnect(context)
        val intent = Intent(context, VlessRealityVpnService::class.java)
            .setAction(VlessRealityVpnService.ACTION_CONNECT)
            .putExtra(VlessRealityVpnService.EXTRA_CONFIG_PATH, config.canonicalPath)
        context.startForegroundService(intent)
        return waitForState(context, "up", 30_000L)
    }

    @JvmStatic
    fun disconnect(context: Context): Boolean {
        if (!isAvailable(context)) return true
        if (!VlessRealityVpnService.requestDisconnect(context)) return false
        return waitForState(context, "down", 12_000L)
    }

    @JvmStatic
    fun snapshot(context: Context): Map<String, Any> {
        val current = VlessRealityVpnService.snapshot(context)
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

    private fun waitForState(context: Context, expected: String, timeoutMs: Long): Boolean {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        do {
            val state = VlessRealityVpnService.snapshot(context).state
            if (state == expected) return true
            if (state == "error" && expected != "down") return false
            Thread.sleep(100L)
        } while (SystemClock.elapsedRealtime() < deadline)
        return VlessRealityVpnService.snapshot(context).state == expected
    }
}
