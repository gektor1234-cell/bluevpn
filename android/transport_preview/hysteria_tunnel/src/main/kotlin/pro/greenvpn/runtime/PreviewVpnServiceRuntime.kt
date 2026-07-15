package pro.greenvpn.runtime

import android.app.ActivityManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build

internal object PreviewVpnServiceRuntime {
    private const val STARTUP_GRACE_MS = 10_000L

    @Suppress("DEPRECATION")
    fun isRunning(context: Context, serviceClass: Class<out Service>): Boolean {
        val manager = context.getSystemService(ActivityManager::class.java) ?: return false
        return manager.getRunningServices(Int.MAX_VALUE).any { running ->
            running.service.packageName == context.packageName &&
                running.service.className == serviceClass.name
        }
    }

    fun isRunningOrStarting(
        context: Context,
        serviceClass: Class<out Service>,
        state: String,
        stateFile: java.io.File,
    ): Boolean {
        if (isRunning(context, serviceClass)) return true
        if (state != "starting") return false
        val modifiedAt = stateFile.lastModified()
        if (modifiedAt <= 0L) return false
        return (System.currentTimeMillis() - modifiedAt) in 0L..STARTUP_GRACE_MS
    }

    fun requestDisconnect(
        context: Context,
        serviceClass: Class<out Service>,
        action: String,
    ): Boolean {
        if (!isRunning(context, serviceClass)) return false
        return try {
            val intent = Intent(context, serviceClass).setAction(action)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        } catch (_: Throwable) {
            false
        }
    }
}
