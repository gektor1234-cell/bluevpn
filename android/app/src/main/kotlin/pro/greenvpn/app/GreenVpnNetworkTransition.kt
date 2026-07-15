package pro.greenvpn.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.SystemClock

internal object GreenVpnNetworkTransition {
    private const val PREFS_NAME = "greenvpn_secure_config_store_v1"
    private const val ACTIVE_KEY = "greenvpn_android_own_vpn_active_v1"
    private const val ACTIVE_WALL_AT_KEY = "greenvpn_android_own_vpn_active_wall_at_v1"
    private const val ACTIVE_ELAPSED_AT_KEY = "greenvpn_android_own_vpn_active_elapsed_at_v1"
    private const val MARKER_MAX_AGE_MS = 7L * 24L * 60L * 60L * 1000L

    fun waitForInactive(context: Context, timeoutMs: Long): Boolean {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs.coerceAtLeast(0L)
        while (isActive(context) && SystemClock.elapsedRealtime() < deadline) {
            Thread.sleep(50L)
        }
        return !isActive(context)
    }

    @Suppress("DEPRECATION")
    fun isActive(context: Context): Boolean = try {
        val appContext = context.applicationContext
        val connectivity = appContext
            .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val vpnNetworks = connectivity.allNetworks.mapNotNull { network ->
            val capabilities = connectivity.getNetworkCapabilities(network)
                ?: return@mapNotNull null
            capabilities.takeIf {
                it.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            }
        }
        if (vpnNetworks.isEmpty()) {
            markInactive(appContext)
            false
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            vpnNetworks.any { it.ownerUid == appContext.applicationInfo.uid }
        } else {
            hasRecentActiveMarker(appContext)
        }
    } catch (_: Throwable) {
        false
    }

    fun markActive(context: Context) {
        prefs(context).edit()
            .putBoolean(ACTIVE_KEY, true)
            .putLong(ACTIVE_WALL_AT_KEY, System.currentTimeMillis())
            .putLong(ACTIVE_ELAPSED_AT_KEY, SystemClock.elapsedRealtime())
            .apply()
    }

    fun markInactive(context: Context) {
        prefs(context).edit()
            .remove(ACTIVE_KEY)
            .remove(ACTIVE_WALL_AT_KEY)
            .remove(ACTIVE_ELAPSED_AT_KEY)
            .apply()
    }

    fun hasRecentActiveMarker(context: Context): Boolean {
        val values = prefs(context)
        if (!values.getBoolean(ACTIVE_KEY, false)) return false
        val startedAt = values.getLong(ACTIVE_ELAPSED_AT_KEY, -1L)
        val now = SystemClock.elapsedRealtime()
        if (startedAt <= 0L || startedAt > now || now - startedAt > MARKER_MAX_AGE_MS) {
            markInactive(context)
            return false
        }
        return true
    }

    private fun prefs(context: Context) = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
