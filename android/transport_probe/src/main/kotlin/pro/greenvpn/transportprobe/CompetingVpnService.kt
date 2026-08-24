package pro.greenvpn.transportprobe

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor

class CompetingVpnService : VpnService() {
    private var tunnel: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: android.content.Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            shutdown()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        if (tunnel == null) {
            tunnel = Builder()
                .setSession("Competing VPN acceptance probe")
                .addAddress("10.231.0.1", 32)
                .addRoute("192.0.2.0", 24)
                .establish()
        }
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        shutdown()
        super.onRevoke()
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
    }

    private fun shutdown() {
        tunnel?.close()
        tunnel = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "VPN acceptance probe",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle("VPN acceptance probe")
            .setContentText("Testing competing VPN takeover")
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_STOP = "pro.greenvpn.transportprobe.action.STOP_VPN"
        private const val CHANNEL_ID = "greenvpn-competing-vpn-probe"
        private const val NOTIFICATION_ID = 4101
    }
}
