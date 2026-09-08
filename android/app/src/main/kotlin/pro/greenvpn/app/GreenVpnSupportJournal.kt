package pro.greenvpn.app

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Bounded, app-private event history. No polling, network traffic or wake locks. */
object GreenVpnSupportJournal {
    private const val FILE_BYTES = 96 * 1024
    private const val MAX_PENDING = 64
    private const val MAX_AGE_MS = 24L * 60 * 60 * 1000
    private val pending = AtomicInteger()
    private val dropped = AtomicInteger()
    private val writer = Executors.newSingleThreadExecutor { task ->
        Thread(task, "greenvpn-support-journal").apply { isDaemon = true }
    }
    private var observer: SharedPreferences.OnSharedPreferenceChangeListener? = null
    private var previousState = ""
    private var previousStateAt = 0L
    private val keys = setOf(
        "state", "desired", "reason", "lastReason", "lastError", "error", "stage",
        "serverId", "protocol", "mode", "operationId", "operationKind", "ok",
        "status", "durationMs", "previousStateDurationMs", "endpointKind", "apiRole",
        "routeFailures", "recoveryFailures", "recoveryCount", "lastProbeAtMs",
        "lastProbeOk", "nextRecoveryAtMs", "pauseUntilMs", "resumeScheduled",
        "requestedServerId", "requestedMode", "operationStartedAtMs", "connectedAtMs",
        "underlyingInternet", "underlyingValidated", "permissionGranted", "updatedAtMs",
        "enabled", "runtimeFailoverEnabled", "pauseResumeSupported", "source",
    )

    private fun safe(value: Any?): Any = when (value) {
        is Boolean, is Int, is Long, is Double -> value
        else -> GreenVpnSupportRedaction.text(value.toString())
    }

    fun record(context: Context, event: String, fields: Map<String, Any?> = emptyMap()) {
        if (pending.incrementAndGet() > MAX_PENDING) {
            pending.decrementAndGet()
            dropped.incrementAndGet()
            return
        }
        try {
            val app = context.applicationContext
            val entry = JSONObject().put("atMs", System.currentTimeMillis())
                .put("elapsedMs", SystemClock.elapsedRealtime()).put("event", safe(event))
                .put("operationId", safe(GreenVpnRuntimeFailoverService.eventPreferences(app)
                    .getString("operation_id", "").orEmpty()))
            fields.filterKeys { it in keys }.forEach { (key, value) -> entry.put(key, safe(value)) }
            writer.execute {
                try {
                    val (current, previous) = files(app)
                    for (file in listOf(current, previous)) {
                        if (file.exists() && System.currentTimeMillis() - file.lastModified() > MAX_AGE_MS) file.delete()
                    }
                    val line = entry.toString() + "\n"
                    if (current.length() + line.toByteArray(Charsets.UTF_8).size > FILE_BYTES) {
                        check(!previous.exists() || previous.delete())
                        check(!current.exists() || current.renameTo(previous))
                    }
                    current.appendText(line, Charsets.UTF_8)
                } catch (_: Exception) {
                    dropped.incrementAndGet()
                } finally {
                    pending.decrementAndGet()
                }
            }
        } catch (_: Exception) {
            dropped.incrementAndGet()
            pending.decrementAndGet()
        }
    }

    @Synchronized
    fun observeRuntime(context: Context) {
        if (observer != null) return
        try {
            val app = context.applicationContext
            val preferences = GreenVpnRuntimeFailoverService.eventPreferences(app)
            observer = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
                if (key == "updated_at_ms") captureRuntime(app)
            }
            preferences.registerOnSharedPreferenceChangeListener(observer)
            record(app, "process_started")
            captureRuntime(app)
        } catch (_: Exception) {
            observer = null
            dropped.incrementAndGet()
        }
    }

    @Synchronized
    private fun captureRuntime(context: Context) {
        try {
            val snapshot = GreenVpnRuntimeFailoverService.snapshot(context).toMutableMap()
            // Identical observations need no new disk record; probe/state changes do.
            val signature = snapshot.filterKeys { it != "updatedAtMs" }.toString()
            if (signature == previousState) return
            val now = SystemClock.elapsedRealtime()
            snapshot["previousStateDurationMs"] = if (previousStateAt == 0L) 0L else now - previousStateAt
            previousState = signature
            previousStateAt = now
            record(context, "runtime", snapshot)
        } catch (_: Exception) {
            record(context, "runtime_snapshot_unavailable")
        }
    }

    fun collect(context: Context): Map<String, Any> {
        val app = context.applicationContext
        return writer.submit<Map<String, Any>> {
            val cutoff = System.currentTimeMillis() - MAX_AGE_MS
            val (current, previous) = files(app)
            val entries = listOf(previous, current).flatMap { file ->
                if (!file.exists() || file.length() > FILE_BYTES) emptyList()
                else file.readLines(Charsets.UTF_8).mapNotNull { line ->
                    try {
                        val item = JSONObject(line)
                        if (item.optLong("atMs") < cutoff) null
                        else item.keys().asSequence().associateWith { item.get(it) }
                    } catch (_: Exception) { null }
                }
            }.takeLast(400)
            val power = app.getSystemService(Context.POWER_SERVICE) as PowerManager
            linkedMapOf(
                "schema" to 1,
                "capturedAtMs" to System.currentTimeMillis(),
                "runtime" to GreenVpnRuntimeFailoverService.snapshot(app).filterKeys { it in keys }.mapValues { safe(it.value) },
                "environment" to mapOf(
                    "sdk" to Build.VERSION.SDK_INT,
                    "manufacturer" to safe(Build.MANUFACTURER),
                    "model" to safe(Build.MODEL),
                    "powerSaveMode" to power.isPowerSaveMode,
                    "deviceIdleMode" to power.isDeviceIdleMode,
                    "ignoringBatteryOptimizations" to power.isIgnoringBatteryOptimizations(app.packageName),
                    "uptimeMs" to SystemClock.elapsedRealtime(),
                    "appHeapUsedBytes" to Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory(),
                    "appHeapMaxBytes" to Runtime.getRuntime().maxMemory(),
                ),
                // Backend keeps at most 100 list entries; explicit pages preserve history.
                "eventPages" to entries.chunked(100).mapIndexed { index, page -> "page$index" to page }.toMap(),
                "eventCount" to entries.size,
                "droppedEvents" to dropped.get(),
                "maxDiskBytes" to FILE_BYTES * 2,
                "retentionHours" to 24,
            )
        }.get(4, TimeUnit.SECONDS)
    }

    private fun files(context: Context): Pair<File, File> {
        val directory = File(context.noBackupFilesDir, "support-journal")
        check(directory.isDirectory || directory.mkdirs())
        return File(directory, "current.jsonl") to File(directory, "previous.jsonl")
    }
}
