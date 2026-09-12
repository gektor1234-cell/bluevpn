package pro.greenvpn.app

import android.app.NotificationManager
import android.content.Context
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import kotlin.math.PI
import kotlin.math.sin

internal object GreenVpnConnectionFeedback {
    private val handler = Handler(Looper.getMainLooper())
    private var observer: SharedPreferences.OnSharedPreferenceChangeListener? = null
    private var policy = GreenVpnFeedbackPolicy()
    private var player: AudioTrack? = null
    private fun prefs(context: Context) = context.applicationContext
        .getSharedPreferences("greenvpn_connection_feedback_v1", Context.MODE_PRIVATE)
    fun enabled(context: Context) = prefs(context).getBoolean("enabled", true)
    fun setEnabled(context: Context, enabled: Boolean): Boolean {
        val saved = prefs(context).edit().putBoolean("enabled", enabled).commit()
        if (!enabled) handler.post { releasePlayer() }
        return saved
    }
    @Synchronized
    fun observe(context: Context) {
        if (observer != null) return
        val app = context.applicationContext
        policy = GreenVpnFeedbackPolicy(prefs(app).getBoolean("confirmed", false) &&
            GreenVpnNetworkTransition.isActive(app))
        val values = GreenVpnRuntimeFailoverService.eventPreferences(app)
        observer = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == "updated_at_ms") {
                when (values.getString("state", "")) {
                    "monitoring" -> if (values.getBoolean("last_probe_ok", false)) confirmed(app)
                    "disconnected" -> disconnected(app)
                    "authentication_required", "permission_denied", "error" -> failure(app,
                        values.getString("operation_id", "").orEmpty(), !values.getBoolean("desired", false))
                }
                GreenVpnQuickTileService.requestRefresh(app)
            }
        }
        values.registerOnSharedPreferenceChangeListener(observer)
        // Never replay historical sounds when opening the app or restarting its service.
    }
    @Synchronized
    fun confirmed(context: Context) = emit(context, policy.confirmed())
    @Synchronized
    fun disconnected(context: Context) = emit(context, policy.disconnected())
    @Synchronized
    fun failure(context: Context, operation: String, terminal: Boolean) = emit(context, policy.failed(operation, terminal))
    private fun emit(context: Context, cue: String?) {
        if (cue == null) return
        prefs(context).edit().putBoolean("confirmed", policy.connected).apply()
        val app = context.applicationContext
        handler.post {
            try {
                val audio = app.getSystemService(AudioManager::class.java) ?: return@post
                val notifications = app.getSystemService(NotificationManager::class.java) ?: return@post
                if (!enabled(app) || audio.ringerMode != AudioManager.RINGER_MODE_NORMAL ||
                    audio.mode != AudioManager.MODE_NORMAL ||
                    audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION) == 0 ||
                    notifications.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL ||
                    !notifications.areNotificationsEnabled()) return@post
                releasePlayer()
                val notes = when (cue) {
                    "connected" -> doubleArrayOf(660.0, 880.0)
                    "disconnected" -> doubleArrayOf(660.0, 440.0)
                    else -> doubleArrayOf(330.0, 330.0)
                }
                val sampleRate = 22050
                val noteSamples = sampleRate / 10
                val samples = ShortArray(noteSamples * 2)
                for (i in samples.indices) {
                    val n = i % noteSamples
                    val envelope = sin(PI * n / noteSamples)
                    samples[i] = (3500 * envelope * sin(2 * PI * notes[i / noteSamples] * n / sampleRate)).toInt().toShort()
                }
                val track = AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    .setAudioFormat(AudioFormat.Builder().setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                    .setTransferMode(AudioTrack.MODE_STATIC).setBufferSizeInBytes(samples.size * 2).build()
                player = track
                check(track.write(samples, 0, samples.size) == samples.size)
                track.play()
                handler.postDelayed({ if (player === track) releasePlayer() }, 400L)
            } catch (_: Exception) { releasePlayer() }
        }
    }
    private fun releasePlayer() {
        val old = player
        player = null
        try { old?.stop() } catch (_: Exception) {}
        try { old?.release() } catch (_: Exception) {}
    }
}
