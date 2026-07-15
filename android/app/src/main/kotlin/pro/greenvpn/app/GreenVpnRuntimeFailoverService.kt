package pro.greenvpn.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class GreenVpnRuntimeFailoverService : Service() {
    companion object {
        private const val ACTION_ARM = "pro.greenvpn.app.action.ARM_RUNTIME_FAILOVER"
        private const val PREFS_NAME = "greenvpn_runtime_failover_v1"
        private const val KEY_DESIRED = "desired"
        private const val KEY_SERVER_ID = "server_id"
        private const val KEY_PROTOCOL = "protocol"
        private const val KEY_STATE = "state"
        private const val KEY_ROUTE_FAILURES = "route_failures"
        private const val KEY_RECOVERY_FAILURES = "recovery_failures"
        private const val KEY_RECOVERY_COUNT = "recovery_count"
        private const val KEY_LAST_REASON = "last_reason"
        private const val KEY_LAST_ERROR = "last_error"
        private const val KEY_LAST_PROBE_AT_MS = "last_probe_at_ms"
        private const val KEY_LAST_PROBE_OK = "last_probe_ok"
        private const val KEY_NEXT_RECOVERY_AT_MS = "next_recovery_at_ms"
        private const val KEY_UPDATED_AT_MS = "updated_at_ms"
        private const val CHANNEL_ID = "greenvpn_runtime_connection"
        private const val NOTIFICATION_ID = 7302
        private const val DEBUG_TAG = "GreenVpnRuntimeFailover"

        private val supportedProtocols: Set<String>
            get() = buildSet {
                add("wireguard_udp")
                if (BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) add("amneziawg")
                if (BuildConfig.GREENVPN_HYSTERIA2_PREVIEW_ENABLED) add("hysteria2")
                if (BuildConfig.GREENVPN_VLESS_REALITY_PREVIEW_ENABLED) add("vless_reality")
                if (BuildConfig.GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED) add("naive_https")
                if (BuildConfig.GREENVPN_DNSTT_PREVIEW_ENABLED) add("dnstt")
            }

        private fun previewEnabled(): Boolean = supportedProtocols.size > 1

        fun arm(context: Context, serverId: String, protocol: String): Boolean {
            val normalizedServerId = serverId.trim()
            val normalizedProtocol = protocol.trim().lowercase()
            if (!previewEnabled() || normalizedServerId.isEmpty() ||
                normalizedServerId.length > 160 || normalizedProtocol !in supportedProtocols
            ) {
                return false
            }
            val now = System.currentTimeMillis()
            val committed = prefs(context).edit()
                .putBoolean(KEY_DESIRED, true)
                .putString(KEY_SERVER_ID, normalizedServerId)
                .putString(KEY_PROTOCOL, normalizedProtocol)
                .putString(KEY_STATE, "monitoring")
                .putInt(KEY_ROUTE_FAILURES, 0)
                .putInt(KEY_RECOVERY_FAILURES, 0)
                .putString(KEY_LAST_REASON, "armed")
                .putString(KEY_LAST_ERROR, "")
                .putLong(KEY_LAST_PROBE_AT_MS, now)
                .putBoolean(KEY_LAST_PROBE_OK, true)
                .putLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
                .putLong(KEY_UPDATED_AT_MS, now)
                .commit()
            if (!committed) return false
            GreenVpnNetworkTransition.markActive(context)

            val intent = Intent(context, GreenVpnRuntimeFailoverService::class.java)
                .setAction(ACTION_ARM)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            return true
        }

        fun disarm(context: Context) {
            prefs(context).edit()
                .putBoolean(KEY_DESIRED, false)
                .putString(KEY_STATE, "disarmed")
                .putInt(KEY_ROUTE_FAILURES, 0)
                .putInt(KEY_RECOVERY_FAILURES, 0)
                .putLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
                .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
                .commit()
            context.stopService(Intent(context, GreenVpnRuntimeFailoverService::class.java))
        }

        fun snapshot(context: Context): Map<String, Any> {
            val values = prefs(context)
            return linkedMapOf(
                "enabled" to previewEnabled(),
                "desired" to values.getBoolean(KEY_DESIRED, false),
                "serverId" to values.getString(KEY_SERVER_ID, "").orEmpty(),
                "protocol" to values.getString(KEY_PROTOCOL, "").orEmpty(),
                "state" to values.getString(KEY_STATE, "idle").orEmpty(),
                "routeFailures" to values.getInt(KEY_ROUTE_FAILURES, 0),
                "recoveryFailures" to values.getInt(KEY_RECOVERY_FAILURES, 0),
                "recoveryCount" to values.getInt(KEY_RECOVERY_COUNT, 0),
                "lastReason" to values.getString(KEY_LAST_REASON, "").orEmpty(),
                "lastError" to values.getString(KEY_LAST_ERROR, "").orEmpty(),
                "lastProbeAtMs" to values.getLong(KEY_LAST_PROBE_AT_MS, 0L),
                "lastProbeOk" to values.getBoolean(KEY_LAST_PROBE_OK, false),
                "nextRecoveryAtMs" to values.getLong(KEY_NEXT_RECOVERY_AT_MS, 0L),
                "updatedAtMs" to values.getLong(KEY_UPDATED_AT_MS, 0L),
            )
        }

        private fun prefs(context: Context) = context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private data class ActiveRoute(val serverId: String, val protocol: String)

    private val coordinator by lazy { GreenVpnNativeCascadeCoordinator(applicationContext) }
    private var monitor: ScheduledExecutorService? = null

    override fun onCreate() {
        super.onCreate()
        if (previewEnabled()) {
            ensureForeground()
            startMonitor()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!previewEnabled()) {
            stopSelf()
            return START_NOT_STICKY
        }
        ensureForeground()
        startMonitor()
        if (!isDesired()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_ARM) updateNotification()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        monitor?.shutdownNow()
        monitor = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun startMonitor() {
        if (monitor != null) return
        monitor = Executors.newSingleThreadScheduledExecutor().also { executor ->
            executor.scheduleWithFixedDelay(
                { monitorOnceSafely() },
                1_000L,
                GreenVpnRuntimeFailoverPolicy.MONITOR_INTERVAL_MS,
                TimeUnit.MILLISECONDS,
            )
        }
    }

    private fun monitorOnceSafely() {
        try {
            monitorOnce()
        } catch (failure: Throwable) {
            if (failure is InterruptedException || !isDesired()) return
            publishState(
                state = "error",
                reason = "monitor_exception",
                error = safeError(failure),
                nextRecoveryAtMs = System.currentTimeMillis() +
                    GreenVpnRuntimeFailoverPolicy.retryDelayMs(1),
            )
        }
    }

    private fun monitorOnce() {
        if (!isDesired()) {
            stopSelf()
            return
        }
        val values = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val nextRecoveryAt = values.getLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
        if (nextRecoveryAt > now) return

        val state = values.getString(KEY_STATE, "monitoring").orEmpty()
        if (state == "error" || state == "recovering") {
            recover("retry", markCurrentRouteFailed = false)
            return
        }

        val route = activeRoute() ?: run {
            recover("route_missing", markCurrentRouteFailed = false)
            return
        }
        if (!coordinator.isProtocolConnected(route.protocol)) {
            recover("engine_down", markCurrentRouteFailed = true)
            return
        }

        val lastProbeAt = values.getLong(KEY_LAST_PROBE_AT_MS, 0L)
        if (now - lastProbeAt < GreenVpnRuntimeFailoverPolicy.ROUTE_PROBE_INTERVAL_MS) return
        val probe = coordinator.probeRoute(route.protocol)
        if (!isDesired()) return
        val failures = GreenVpnRuntimeFailoverPolicy.nextRouteFailureCount(
            values.getInt(KEY_ROUTE_FAILURES, 0),
            probe.ok,
        )
        values.edit()
            .putInt(KEY_ROUTE_FAILURES, failures)
            .putLong(KEY_LAST_PROBE_AT_MS, System.currentTimeMillis())
            .putBoolean(KEY_LAST_PROBE_OK, probe.ok)
            .putString(KEY_STATE, if (probe.ok) "monitoring" else "degraded")
            .putString(KEY_LAST_REASON, if (probe.ok) "route_ok" else "route_probe_failed")
            .putString(KEY_LAST_ERROR, if (probe.ok) "" else safeText(probe.error))
            .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
            .apply()
        updateNotification()
        if (GreenVpnRuntimeFailoverPolicy.shouldRecoverForRoute(failures)) {
            recover("route_probe_failed", markCurrentRouteFailed = true)
        }
    }

    private fun recover(reason: String, markCurrentRouteFailed: Boolean) {
        GreenVpnConnectionOperationGate.runExclusive {
            recoverExclusive(reason, markCurrentRouteFailed)
        }
    }

    private fun recoverExclusive(reason: String, markCurrentRouteFailed: Boolean) {
        if (!isDesired()) return
        val previousRoute = activeRoute()
        publishState("recovering", reason, "", 0L)
        if (markCurrentRouteFailed && previousRoute != null) {
            coordinator.recordRouteFailure(
                GreenVpnRuntimeRoute(previousRoute.serverId, previousRoute.protocol),
            )
        }
        coordinator.disconnectAll()
        val result = coordinator.connectBest { isDesired() && !Thread.currentThread().isInterrupted }
        if (!isDesired()) {
            coordinator.disconnectAll()
            return
        }

        val values = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (result.ok) {
            val now = System.currentTimeMillis()
            values.edit()
                .putString(KEY_SERVER_ID, result.serverId)
                .putString(KEY_PROTOCOL, result.protocol)
                .putString(KEY_STATE, "monitoring")
                .putInt(KEY_ROUTE_FAILURES, 0)
                .putInt(KEY_RECOVERY_FAILURES, 0)
                .putInt(KEY_RECOVERY_COUNT, values.getInt(KEY_RECOVERY_COUNT, 0) + 1)
                .putString(KEY_LAST_REASON, "recovered")
                .putString(KEY_LAST_ERROR, "")
                .putLong(KEY_LAST_PROBE_AT_MS, now)
                .putBoolean(KEY_LAST_PROBE_OK, true)
                .putLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
                .putLong(KEY_UPDATED_AT_MS, now)
                .apply()
            debug("recovered protocol=${result.protocol}")
        } else {
            coordinator.disconnectAll()
            val failures = values.getInt(KEY_RECOVERY_FAILURES, 0) + 1
            val retryAt = System.currentTimeMillis() +
                GreenVpnRuntimeFailoverPolicy.retryDelayMs(failures)
            values.edit()
                .putString(KEY_STATE, "error")
                .putInt(KEY_RECOVERY_FAILURES, failures)
                .putString(KEY_LAST_REASON, reason)
                .putString(KEY_LAST_ERROR, safeText(result.error))
                .putLong(KEY_NEXT_RECOVERY_AT_MS, retryAt)
                .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
                .apply()
            debug("recovery_failed reason=$reason error=${safeText(result.error)}")
        }
        updateNotification()
    }

    private fun activeRoute(): ActiveRoute? {
        val values = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val serverId = values.getString(KEY_SERVER_ID, "").orEmpty().trim()
        val protocol = values.getString(KEY_PROTOCOL, "").orEmpty().trim().lowercase()
        return if (serverId.isEmpty() || protocol !in supportedProtocols) {
            null
        } else {
            ActiveRoute(serverId, protocol)
        }
    }

    private fun isDesired(): Boolean = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getBoolean(KEY_DESIRED, false)

    private fun publishState(
        state: String,
        reason: String,
        error: String,
        nextRecoveryAtMs: Long,
    ) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_STATE, state)
            .putString(KEY_LAST_REASON, reason)
            .putString(KEY_LAST_ERROR, safeText(error))
            .putLong(KEY_NEXT_RECOVERY_AT_MS, nextRecoveryAtMs)
            .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
            .apply()
        updateNotification()
    }

    private fun ensureForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Подключение Green VPN",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    private fun updateNotification() {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification())
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(): Notification {
        val state = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_STATE, "monitoring")
        val text = when (state) {
            "recovering" -> "Восстанавливаем подключение"
            "degraded" -> "Проверяем подключение"
            "error" -> "Ожидаем восстановления подключения"
            else -> "VPN подключён"
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(BuildConfig.GREENVPN_APP_LABEL)
            .setContentText(text)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun safeError(error: Throwable): String =
        safeText(error.message ?: error.javaClass.simpleName)

    private fun safeText(value: String): String = value
        .replace(Regex("[\\r\\n]+"), " ")
        .replace(Regex("Bearer\\s+[^\\s]+", RegexOption.IGNORE_CASE), "Bearer [redacted]")
        .take(180)

    private fun debug(message: String) {
        if (BuildConfig.DEBUG) Log.i(DEBUG_TAG, message)
    }
}
