package pro.greenvpn.app

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.ServiceCompat
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class GreenVpnRuntimeFailoverService : Service() {
    companion object {
        private const val ACTION_ARM = "pro.greenvpn.app.action.ARM_RUNTIME_FAILOVER"
        private const val ACTION_SCHEDULE_RESUME =
            "pro.greenvpn.app.action.SCHEDULE_RUNTIME_RESUME"
        private const val ACTION_REQUEST_CONNECT =
            "pro.greenvpn.app.action.REQUEST_MANAGED_CONNECT"
        private const val ACTION_PERMISSION_GRANTED =
            "pro.greenvpn.app.action.MANAGED_PERMISSION_GRANTED"
        private const val ACTION_REQUEST_DISCONNECT =
            "pro.greenvpn.app.action.REQUEST_MANAGED_DISCONNECT"
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
        private const val KEY_PAUSE_UNTIL_MS = "pause_until_ms"
        private const val KEY_RESUME_SCHEDULED = "resume_scheduled"
        private const val KEY_UPDATED_AT_MS = "updated_at_ms"
        private const val KEY_OPERATION_ID = "operation_id"
        private const val KEY_OPERATION_KIND = "operation_kind"
        private const val KEY_REQUESTED_SERVER_ID = "requested_server_id"
        private const val KEY_REQUESTED_MODE = "requested_mode"
        private const val KEY_OPERATION_STARTED_AT_MS = "operation_started_at_ms"
        private const val KEY_CONNECTED_AT_MS = "connected_at_ms"
        private const val KEY_UNDERLYING_INTERNET = "underlying_internet"
        private const val KEY_UNDERLYING_VALIDATED = "underlying_validated"
        private const val KEY_PERMISSION_GRANTED = "permission_granted"
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

        private fun serviceEnabled(): Boolean = supportedProtocols.isNotEmpty()

        fun requestManagedConnect(
            context: Context,
            serverId: String,
            mode: String,
        ): Map<String, Any> {
            val normalizedMode = mode.trim().lowercase()
            if (!serviceEnabled() || normalizedMode != "full") {
                return LinkedHashMap<String, Any>(snapshot(context)).apply {
                    put("ok", false)
                    put("message", "managed_full_mode_required")
                }
            }
            val normalizedServerId = serverId.trim().take(160)
                .takeUnless { it.equals("auto", ignoreCase = true) }
                .orEmpty()
            val permissionGranted = VpnService.prepare(context.applicationContext) == null
            val now = System.currentTimeMillis()
            val operationId = UUID.randomUUID().toString()
            val network = GreenVpnUnderlyingNetwork.snapshot(context)
            val state = when {
                !permissionGranted -> "permission_required"
                !network.validatedNetworkAvailable -> "waiting_for_network"
                else -> "queued"
            }
            val committed = prefs(context).edit()
                .putBoolean(KEY_DESIRED, true)
                .putString(KEY_OPERATION_ID, operationId)
                .putString(KEY_OPERATION_KIND, "connect")
                .putString(KEY_REQUESTED_SERVER_ID, normalizedServerId)
                .putString(KEY_REQUESTED_MODE, normalizedMode)
                .putString(KEY_STATE, state)
                .putInt(KEY_ROUTE_FAILURES, 0)
                .putInt(KEY_RECOVERY_FAILURES, 0)
                .putString(KEY_LAST_REASON, "user_connect")
                .putString(KEY_LAST_ERROR, "")
                .putLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
                .putLong(KEY_PAUSE_UNTIL_MS, 0L)
                .putBoolean(KEY_RESUME_SCHEDULED, false)
                .putLong(KEY_OPERATION_STARTED_AT_MS, now)
                .putBoolean(KEY_UNDERLYING_INTERNET, network.internetNetworkAvailable)
                .putBoolean(KEY_UNDERLYING_VALIDATED, network.validatedNetworkAvailable)
                .putBoolean(KEY_PERMISSION_GRANTED, permissionGranted)
                .putLong(KEY_UPDATED_AT_MS, now)
                .commit()
            if (committed) {
                startRuntimeService(context, ACTION_REQUEST_CONNECT)
            }
            return LinkedHashMap<String, Any>(snapshot(context)).apply {
                put("ok", committed)
                put("permissionRequired", !permissionGranted)
            }
        }

        fun markManagedPermissionGranted(context: Context) {
            val values = prefs(context)
            if (!values.getBoolean(KEY_DESIRED, false) ||
                values.getString(KEY_OPERATION_KIND, "") != "connect"
            ) {
                return
            }
            val network = GreenVpnUnderlyingNetwork.snapshot(context)
            values.edit()
                .putString(
                    KEY_STATE,
                    if (network.validatedNetworkAvailable) "queued" else "waiting_for_network",
                )
                .putString(KEY_LAST_REASON, "vpn_permission_granted")
                .putString(KEY_LAST_ERROR, "")
                .putBoolean(KEY_PERMISSION_GRANTED, true)
                .putBoolean(KEY_UNDERLYING_INTERNET, network.internetNetworkAvailable)
                .putBoolean(KEY_UNDERLYING_VALIDATED, network.validatedNetworkAvailable)
                .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
                .commit()
            startRuntimeService(context, ACTION_PERMISSION_GRANTED)
        }

        fun markManagedPermissionDenied(context: Context) {
            prefs(context).edit()
                .putBoolean(KEY_DESIRED, false)
                .putString(KEY_STATE, "permission_denied")
                .putString(KEY_LAST_REASON, "vpn_permission_denied")
                .putString(KEY_LAST_ERROR, "vpn_permission_denied")
                .putBoolean(KEY_PERMISSION_GRANTED, false)
                .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
                .commit()
            context.stopService(Intent(context, GreenVpnRuntimeFailoverService::class.java))
        }

        fun requestManagedDisconnect(context: Context): Map<String, Any> {
            val now = System.currentTimeMillis()
            val committed = prefs(context).edit()
                .putBoolean(KEY_DESIRED, false)
                .putString(KEY_OPERATION_ID, UUID.randomUUID().toString())
                .putString(KEY_OPERATION_KIND, "disconnect")
                .putString(KEY_STATE, "disconnecting")
                .putString(KEY_LAST_REASON, "user_disconnect")
                .putString(KEY_LAST_ERROR, "")
                .putLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
                .putLong(KEY_PAUSE_UNTIL_MS, 0L)
                .putBoolean(KEY_RESUME_SCHEDULED, false)
                .putLong(KEY_OPERATION_STARTED_AT_MS, now)
                .putLong(KEY_UPDATED_AT_MS, now)
                .commit()
            if (committed) {
                startRuntimeService(context, ACTION_REQUEST_DISCONNECT)
            }
            return LinkedHashMap<String, Any>(snapshot(context)).apply {
                put("ok", committed)
            }
        }

        private fun startRuntimeService(context: Context, action: String) {
            val intent = Intent(context, GreenVpnRuntimeFailoverService::class.java)
                .setAction(action)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

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
                .putString(KEY_OPERATION_KIND, "monitor")
                .putString(KEY_SERVER_ID, normalizedServerId)
                .putString(KEY_PROTOCOL, normalizedProtocol)
                .putString(KEY_STATE, "monitoring")
                .putInt(KEY_ROUTE_FAILURES, 0)
                .putInt(KEY_RECOVERY_FAILURES, 0)
                .putString(KEY_LAST_REASON, "armed")
                .putString(KEY_LAST_ERROR, "")
                .putLong(KEY_LAST_PROBE_AT_MS, now)
                .putBoolean(KEY_LAST_PROBE_OK, true)
                .putBoolean(KEY_PERMISSION_GRANTED, true)
                .putLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
                .putLong(KEY_PAUSE_UNTIL_MS, 0L)
                .putBoolean(KEY_RESUME_SCHEDULED, false)
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

        fun scheduleResume(
            context: Context,
            resumeAtMs: Long,
            serverId: String,
            protocol: String,
        ): Boolean {
            val now = System.currentTimeMillis()
            val normalizedServerId = serverId.trim().take(160)
            val normalizedProtocol = protocol.trim().lowercase()
                .takeIf { it in supportedProtocols } ?: "wireguard_udp"
            if (!serviceEnabled() ||
                !GreenVpnRuntimeFailoverPolicy.validPauseResumeAt(now, resumeAtMs)
            ) {
                return false
            }
            val committed = prefs(context).edit()
                .putBoolean(KEY_DESIRED, true)
                .putString(KEY_OPERATION_ID, UUID.randomUUID().toString())
                .putString(KEY_OPERATION_KIND, "connect")
                .putString(KEY_REQUESTED_SERVER_ID, normalizedServerId)
                .putString(KEY_REQUESTED_MODE, "full")
                .putString(KEY_SERVER_ID, normalizedServerId)
                .putString(KEY_PROTOCOL, normalizedProtocol)
                .putString(KEY_STATE, "paused")
                .putInt(KEY_ROUTE_FAILURES, 0)
                .putInt(KEY_RECOVERY_FAILURES, 0)
                .putString(KEY_LAST_REASON, "user_pause")
                .putString(KEY_LAST_ERROR, "")
                .putLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
                .putLong(KEY_PAUSE_UNTIL_MS, resumeAtMs)
                .putBoolean(KEY_RESUME_SCHEDULED, true)
                .putBoolean(KEY_PERMISSION_GRANTED, true)
                .putLong(KEY_OPERATION_STARTED_AT_MS, now)
                .putLong(KEY_UPDATED_AT_MS, now)
                .commit()
            if (!committed) return false
            GreenVpnNetworkTransition.markInactive(context)
            val intent = Intent(context, GreenVpnRuntimeFailoverService::class.java)
                .setAction(ACTION_SCHEDULE_RESUME)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            return true
        }

        fun cancelScheduledResume(context: Context) {
            val values = prefs(context)
            val shouldCancel = GreenVpnRuntimeFailoverPolicy.shouldCancelScheduledResume(
                resumeScheduled = values.getBoolean(KEY_RESUME_SCHEDULED, false),
                state = values.getString(KEY_STATE, "").orEmpty(),
            )
            if (!shouldCancel) return
            disarm(context)
        }

        fun disarm(context: Context, reason: String = "user_disconnect") {
            prefs(context).edit()
                .putBoolean(KEY_DESIRED, false)
                .putString(KEY_OPERATION_KIND, "none")
                .putString(KEY_STATE, "disarmed")
                .putString(KEY_LAST_REASON, reason.trim().take(160))
                .putString(KEY_LAST_ERROR, "")
                .putInt(KEY_ROUTE_FAILURES, 0)
                .putInt(KEY_RECOVERY_FAILURES, 0)
                .putLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
                .putLong(KEY_PAUSE_UNTIL_MS, 0L)
                .putBoolean(KEY_RESUME_SCHEDULED, false)
                .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
                .commit()
            context.stopService(Intent(context, GreenVpnRuntimeFailoverService::class.java))
        }

        fun snapshot(context: Context): Map<String, Any> {
            val values = prefs(context)
            val network = GreenVpnUnderlyingNetwork.snapshot(context)
            return linkedMapOf(
                "enabled" to serviceEnabled(),
                "runtimeFailoverEnabled" to previewEnabled(),
                "pauseResumeSupported" to serviceEnabled(),
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
                "pauseUntilMs" to values.getLong(KEY_PAUSE_UNTIL_MS, 0L),
                "resumeScheduled" to values.getBoolean(KEY_RESUME_SCHEDULED, false),
                "operationId" to values.getString(KEY_OPERATION_ID, "").orEmpty(),
                "operationKind" to values.getString(KEY_OPERATION_KIND, "").orEmpty(),
                "requestedServerId" to values.getString(KEY_REQUESTED_SERVER_ID, "").orEmpty(),
                "requestedMode" to values.getString(KEY_REQUESTED_MODE, "").orEmpty(),
                "operationStartedAtMs" to values.getLong(KEY_OPERATION_STARTED_AT_MS, 0L),
                "connectedAtMs" to values.getLong(KEY_CONNECTED_AT_MS, 0L),
                "underlyingInternet" to network.internetNetworkAvailable,
                "underlyingValidated" to network.validatedNetworkAvailable,
                "permissionGranted" to values.getBoolean(KEY_PERMISSION_GRANTED, false),
                "updatedAtMs" to values.getLong(KEY_UPDATED_AT_MS, 0L),
            )
        }

        fun eventPreferences(context: Context) = prefs(context)

        private fun prefs(context: Context) = context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private data class ActiveRoute(val serverId: String, val protocol: String)

    private val coordinator by lazy { GreenVpnNativeCascadeCoordinator(applicationContext) }
    private var monitor: ScheduledExecutorService? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onCreate() {
        super.onCreate()
        if (serviceEnabled()) {
            ensureForeground()
            startMonitor()
            networkCallback = GreenVpnUnderlyingNetwork.register(applicationContext) {
                triggerMonitor()
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!serviceEnabled()) {
            stopSelf()
            return START_NOT_STICKY
        }
        ensureForeground()
        startMonitor()
        if (intent?.action == ACTION_REQUEST_DISCONNECT) {
            monitor?.execute { disconnectManagedRouteSafely() }
            updateNotification()
            return START_NOT_STICKY
        }
        if (!isDesired()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action in setOf(
                ACTION_ARM,
                ACTION_SCHEDULE_RESUME,
                ACTION_REQUEST_CONNECT,
                ACTION_PERMISSION_GRANTED,
            )
        ) {
            updateNotification()
            triggerMonitor()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        GreenVpnUnderlyingNetwork.unregister(applicationContext, networkCallback)
        networkCallback = null
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

    private fun triggerMonitor() {
        try {
            monitor?.execute { monitorOnceSafely() }
        } catch (_: Throwable) {
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
        val values = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        var state = values.getString(KEY_STATE, "idle").orEmpty()
        if (state == "disconnecting") {
            disconnectManagedRouteSafely()
            return
        }
        if (!isDesired()) {
            stopSelf()
            return
        }

        var route = activeRoute()
        var ownEngineConnected = route?.let { coordinator.isProtocolConnected(it.protocol) }
            ?: supportedProtocols.any { coordinator.isProtocolConnected(it) }
        val systemVpnActive = GreenVpnNetworkTransition.isAnyVpnActive(applicationContext)
        val ownVpnStillActive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            GreenVpnNetworkTransition.isActive(applicationContext)
        } else {
            ownEngineConnected
        }
        val explicitTakeoverPending = state in setOf("queued", "permission_required")
        if (!explicitTakeoverPending && GreenVpnRuntimeFailoverPolicy.shouldStopForCompetingVpn(
                desired = true,
                systemVpnActive = systemVpnActive,
                ownVpnStillActive = ownVpnStillActive,
            )
        ) {
            disarmForCompetingVpn(now)
            return
        }

        if (state == "paused") {
            val pauseUntil = values.getLong(KEY_PAUSE_UNTIL_MS, 0L)
            if (pauseUntil > now) return
            values.edit()
                .putString(KEY_OPERATION_KIND, "connect")
                .putString(KEY_STATE, "queued")
                .putString(KEY_LAST_REASON, "pause_elapsed")
                .putLong(KEY_UPDATED_AT_MS, now)
                .apply()
            state = "queued"
        }

        if (GreenVpnConnectionOperationPolicy.shouldQueryVpnPermission(systemVpnActive)) {
            val permissionGranted = VpnService.prepare(applicationContext) == null
            values.edit().putBoolean(KEY_PERMISSION_GRANTED, permissionGranted).apply()
            if (!permissionGranted) {
                publishState("permission_required", "vpn_permission_required", "", 0L)
                return
            }
        }

        val underlying = GreenVpnUnderlyingNetwork.snapshot(applicationContext)
        values.edit()
            .putBoolean(KEY_UNDERLYING_INTERNET, underlying.internetNetworkAvailable)
            .putBoolean(KEY_UNDERLYING_VALIDATED, underlying.validatedNetworkAvailable)
            .apply()
        if (!GreenVpnConnectionOperationPolicy.shouldProbeOrRecover(
                desired = true,
                validatedUnderlyingNetwork = underlying.validatedNetworkAvailable,
            )
        ) {
            publishState(
                GreenVpnConnectionOperationPolicy.stateWithoutUnderlyingNetwork(
                    ownEngineConnected,
                ),
                "underlying_network_unavailable",
                "",
                0L,
            )
            return
        }

        if (state == "degraded_no_network") {
            if (ownEngineConnected) {
                values.edit()
                    .putString(KEY_STATE, "monitoring")
                    .putString(KEY_LAST_REASON, "underlying_network_restored")
                    .putString(KEY_LAST_ERROR, "")
                    .putLong(KEY_LAST_PROBE_AT_MS, 0L)
                    .putLong(KEY_UPDATED_AT_MS, now)
                    .apply()
                state = "monitoring"
            } else {
                connectRequested("underlying_network_restored")
                return
            }
        }

        if (GreenVpnConnectionOperationPolicy.shouldStartConnect(
                desired = true,
                state = state,
                permissionGranted = values.getBoolean(KEY_PERMISSION_GRANTED, false),
                validatedUnderlyingNetwork = true,
            )
        ) {
            val nextRecoveryAt = values.getLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
            if (nextRecoveryAt <= now) connectRequested(state)
            return
        }

        val nextRecoveryAt = values.getLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
        if (nextRecoveryAt > now) return

        if (state == "recovering") {
            recover("retry", markCurrentRouteFailed = false)
            return
        }

        route = activeRoute()
        if (route == null) {
            connectRequested("route_missing")
            return
        }
        ownEngineConnected = coordinator.isProtocolConnected(route.protocol)

        if (!ownEngineConnected) {
            val failures = GreenVpnRuntimeFailoverPolicy.nextRouteFailureCount(
                values.getInt(KEY_ROUTE_FAILURES, 0),
                probeOk = false,
            )
            values.edit()
                .putInt(KEY_ROUTE_FAILURES, failures)
                .putString(KEY_STATE, "degraded")
                .putString(KEY_LAST_REASON, "engine_down")
                .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
                .apply()
            if (GreenVpnRuntimeFailoverPolicy.shouldRecoverForRoute(failures)) {
                recover("engine_down", markCurrentRouteFailed = true)
            }
            return
        }

        val lastProbeAt = values.getLong(KEY_LAST_PROBE_AT_MS, 0L)
        if (now - lastProbeAt < GreenVpnRuntimeFailoverPolicy.ROUTE_PROBE_INTERVAL_MS) return
        val probe = coordinator.probeRoute(route.protocol)
        if (!isDesired()) return
        val networkAfterProbe = GreenVpnUnderlyingNetwork.snapshot(applicationContext)
        if (GreenVpnConnectionOperationPolicy.shouldPreserveTunnelAfterProbeFailure(
                networkAfterProbe.validatedNetworkAvailable,
            )
        ) {
            values.edit()
                .putBoolean(KEY_UNDERLYING_INTERNET, networkAfterProbe.internetNetworkAvailable)
                .putBoolean(KEY_UNDERLYING_VALIDATED, false)
                .putString(KEY_STATE, "degraded_no_network")
                .putString(KEY_LAST_REASON, "underlying_network_lost_during_probe")
                .putString(KEY_LAST_ERROR, "")
                .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
                .apply()
            updateNotification()
            return
        }
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
            connectExclusive(reason, markCurrentRouteFailed, countRecovery = true)
        }
    }

    private fun connectRequested(reason: String) {
        GreenVpnConnectionOperationGate.runExclusive {
            connectExclusive(reason, markCurrentRouteFailed = false, countRecovery = false)
        }
    }

    private fun connectExclusive(
        reason: String,
        markCurrentRouteFailed: Boolean,
        countRecovery: Boolean,
    ) {
        if (!isDesired()) return
        val network = GreenVpnUnderlyingNetwork.snapshot(applicationContext)
        if (!network.validatedNetworkAvailable) {
            val currentRoute = activeRoute()
            val ownConnected = currentRoute?.let { coordinator.isProtocolConnected(it.protocol) }
                ?: supportedProtocols.any { coordinator.isProtocolConnected(it) }
            publishState(
                GreenVpnConnectionOperationPolicy.stateWithoutUnderlyingNetwork(ownConnected),
                "underlying_network_unavailable",
                "",
                0L,
            )
            return
        }
        val previousRoute = activeRoute()
        publishState(if (countRecovery) "recovering" else "fetching_config", reason, "", 0L)
        if (markCurrentRouteFailed && previousRoute != null) {
            coordinator.recordRouteFailure(
                GreenVpnRuntimeRoute(previousRoute.serverId, previousRoute.protocol),
            )
        }
        val explicitTakeover = !countRecovery && reason == "queued"
        if (!explicitTakeover && coordinator.hasCompetingVpnActive()) {
            disarmForCompetingVpn()
            return
        }
        if (countRecovery) coordinator.disconnectAll()
        val values = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val preferredServerId = values.getString(KEY_REQUESTED_SERVER_ID, "").orEmpty()
        val result = coordinator.connectBest(
            preferredServerId = preferredServerId,
            hasValidatedUnderlyingNetwork = {
                GreenVpnUnderlyingNetwork.snapshot(applicationContext)
                    .validatedNetworkAvailable
            },
            onPhase = { phase ->
                if (isDesired()) publishState(phase, reason, "", 0L)
            },
            allowInitialCompetingVpnTakeover = explicitTakeover,
        ) { isDesired() && !Thread.currentThread().isInterrupted }
        if (!isDesired()) {
            coordinator.disconnectAll()
            return
        }

        if (result.ok) {
            val now = System.currentTimeMillis()
            val finalState = if (result.verified) "monitoring" else "degraded_no_network"
            values.edit()
                .putString(KEY_SERVER_ID, result.serverId)
                .putString(KEY_PROTOCOL, result.protocol)
                .putString(KEY_STATE, finalState)
                .putInt(KEY_ROUTE_FAILURES, 0)
                .putInt(KEY_RECOVERY_FAILURES, 0)
                .putInt(
                    KEY_RECOVERY_COUNT,
                    values.getInt(KEY_RECOVERY_COUNT, 0) + if (countRecovery) 1 else 0,
                )
                .putString(
                    KEY_LAST_REASON,
                    when {
                        !result.verified -> "connected_underlying_network_lost"
                        countRecovery -> "recovered"
                        else -> "connected"
                    },
                )
                .putString(KEY_LAST_ERROR, "")
                .putLong(KEY_LAST_PROBE_AT_MS, now)
                .putBoolean(KEY_LAST_PROBE_OK, result.verified)
                .putBoolean(KEY_PERMISSION_GRANTED, true)
                .putLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
                .putLong(KEY_PAUSE_UNTIL_MS, 0L)
                .putBoolean(KEY_RESUME_SCHEDULED, false)
                .putLong(KEY_CONNECTED_AT_MS, now)
                .putLong(KEY_UPDATED_AT_MS, now)
                .apply()
            GreenVpnNetworkTransition.markActive(applicationContext)
            debug("connect_complete protocol=${result.protocol} verified=${result.verified}")
        } else if (result.waitingForNetwork) {
            publishState("waiting_for_network", "underlying_network_unavailable", "", 0L)
        } else if (result.error == "vpn_permission_required") {
            values.edit().putBoolean(KEY_PERMISSION_GRANTED, false).apply()
            publishState("permission_required", "vpn_permission_required", "", 0L)
        } else if (result.error == "competing_vpn_active") {
            disarmForCompetingVpn()
        } else if (result.error == "cancelled") {
            values.edit()
                .putBoolean(KEY_DESIRED, false)
                .putString(KEY_STATE, "cancelled")
                .putString(KEY_LAST_REASON, "cancelled")
                .putString(KEY_LAST_ERROR, "")
                .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
                .apply()
            coordinator.disconnectAll()
        } else {
            coordinator.disconnectAll()
            val failures = values.getInt(KEY_RECOVERY_FAILURES, 0) + 1
            val retryAt = System.currentTimeMillis() +
                GreenVpnRuntimeFailoverPolicy.retryDelayMs(failures)
            val terminal = result.error in setOf(
                "session_or_device_missing",
                "unsupported_protocol",
            )
            values.edit()
                .putBoolean(KEY_DESIRED, !terminal)
                .putString(KEY_STATE, "error")
                .putInt(KEY_RECOVERY_FAILURES, failures)
                .putString(KEY_LAST_REASON, reason)
                .putString(KEY_LAST_ERROR, safeText(result.error))
                .putLong(KEY_NEXT_RECOVERY_AT_MS, if (terminal) 0L else retryAt)
                .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
                .apply()
            debug("connect_failed reason=$reason error=${safeText(result.error)}")
        }
        updateNotification()
    }

    private fun disarmForCompetingVpn(now: Long = System.currentTimeMillis()) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_DESIRED, false)
            .putBoolean(KEY_PERMISSION_GRANTED, false)
            .putString(KEY_OPERATION_KIND, "none")
            .putString(KEY_STATE, "competing_vpn_active")
            .putString(KEY_LAST_REASON, "competing_vpn_active")
            .putString(KEY_LAST_ERROR, "")
            .putLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
            .putLong(KEY_PAUSE_UNTIL_MS, 0L)
            .putBoolean(KEY_RESUME_SCHEDULED, false)
            .putLong(KEY_UPDATED_AT_MS, now)
            .commit()
        GreenVpnNetworkTransition.markInactive(applicationContext)
        coordinator.disconnectAll()
        Log.i(DEBUG_TAG, "runtime_failover_disarmed reason=competing_vpn_active")
        stopSelf()
    }

    private fun disconnectManagedRouteSafely() {
        try {
            GreenVpnConnectionOperationGate.runExclusive {
                val disconnected = coordinator.disconnectAll()
                if (disconnected) GreenVpnNetworkTransition.markInactive(applicationContext)
                getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                    .putBoolean(KEY_DESIRED, false)
                    .putString(KEY_STATE, if (disconnected) "disconnected" else "error")
                    .putString(
                        KEY_LAST_REASON,
                        if (disconnected) "user_disconnect" else "disconnect_incomplete",
                    )
                    .putString(KEY_LAST_ERROR, if (disconnected) "" else "disconnect_incomplete")
                    .putInt(KEY_ROUTE_FAILURES, 0)
                    .putInt(KEY_RECOVERY_FAILURES, 0)
                    .putLong(KEY_NEXT_RECOVERY_AT_MS, 0L)
                    .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
                    .commit()
            }
        } catch (failure: Throwable) {
            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_DESIRED, false)
                .putString(KEY_STATE, "error")
                .putString(KEY_LAST_REASON, "disconnect_exception")
                .putString(KEY_LAST_ERROR, safeError(failure))
                .putLong(KEY_UPDATED_AT_MS, System.currentTimeMillis())
                .commit()
        } finally {
            updateNotification()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
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

    @SuppressLint("ForegroundServiceType")
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
        val serviceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MANIFEST
        }
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(),
            serviceType,
        )
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
            "paused" -> "VPN приостановлен и включится автоматически"
            "permission_required" -> "Ожидаем разрешение Android на VPN"
            "queued", "fetching_config" -> "Готовим безопасное подключение"
            "connecting" -> "Подключаем Green VPN"
            "verifying" -> "Проверяем подключение"
            "waiting_for_network" -> "Ожидаем доступную сеть"
            "recovering" -> "Восстанавливаем подключение"
            "degraded" -> "Проверяем подключение"
            "degraded_no_network" -> "VPN сохранён, ожидаем сеть"
            "disconnecting" -> "Отключаем Green VPN"
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
