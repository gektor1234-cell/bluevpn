package pro.greenvpn.naive

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import java.io.File

object NaiveHttpsController {
    @JvmStatic
    fun isAvailable(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            try { NaiveHttpsVpnService.naiveBinary(context).isFile } catch (_: Throwable) { false }

    @JvmStatic
    fun validateConfig(configText: String): String = NaiveHttpsConfig.validate(configText)

    @JvmStatic
    fun connect(context: Context, configText: String): Boolean {
        require(isAvailable(context)) { "Naive HTTPS preview engine is unavailable" }
        val root = NaiveHttpsVpnService.runtimeRoot(context)
        require(root.exists() || root.mkdirs()) { "Naive HTTPS runtime directory was not created" }
        val config = File(root, "base.json")
        config.writeText(NaiveHttpsConfig.validate(configText), Charsets.UTF_8)
        require(config.setReadable(false, false) && config.setReadable(true, true)) {
            "Naive HTTPS config permissions were not restricted"
        }
        config.setWritable(true, true)
        NaiveHttpsVpnService.prepareForConnect(context)
        context.startForegroundService(
            Intent(context, NaiveHttpsVpnService::class.java)
                .setAction(NaiveHttpsVpnService.ACTION_CONNECT)
                .putExtra(NaiveHttpsVpnService.EXTRA_CONFIG_PATH, config.canonicalPath)
        )
        return waitForState(context, "up", 30_000L)
    }

    @JvmStatic
    fun disconnect(context: Context): Boolean {
        if (!isAvailable(context)) return true
        if (!NaiveHttpsVpnService.requestDisconnect(context)) return false
        return waitForState(context, "down", 12_000L)
    }

    @JvmStatic
    fun snapshot(context: Context): Map<String, Any> {
        val current = NaiveHttpsVpnService.snapshot(context)
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
            val state = NaiveHttpsVpnService.snapshot(context).state
            if (state == expected) return true
            if (state == "error" && expected != "down") return false
            Thread.sleep(100L)
        } while (SystemClock.elapsedRealtime() < deadline)
        return NaiveHttpsVpnService.snapshot(context).state == expected
    }
}
