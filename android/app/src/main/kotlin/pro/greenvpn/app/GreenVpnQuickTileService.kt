package pro.greenvpn.app

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast

class GreenVpnQuickTileService : TileService() {
    companion object {
        @Volatile var updateInProgress = false
        fun preferences(context: Context) = context.applicationContext
            .getSharedPreferences("greenvpn_quick_tile_v2", Context.MODE_PRIVATE)
        fun requestRefresh(context: Context) {
            try { requestListeningState(context, ComponentName(context, GreenVpnQuickTileService::class.java)) }
            catch (_: Exception) {}
        }
    }
    private var observer: SharedPreferences.OnSharedPreferenceChangeListener? = null
    private var clicking = false
    override fun onStartListening() {
        super.onStartListening()
        clicking = false
        GreenVpnConnectionFeedback.observe(applicationContext)
        val values = GreenVpnRuntimeFailoverService.eventPreferences(this)
        if (observer == null) {
            observer = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
                if (key == "updated_at_ms") refresh()
            }
            values.registerOnSharedPreferenceChangeListener(observer)
        }
        refresh()
    }
    override fun onStopListening() {
        GreenVpnRuntimeFailoverService.eventPreferences(this).unregisterOnSharedPreferenceChangeListener(observer)
        observer = null
        super.onStopListening()
    }
    override fun onDestroy() {
        onStopListening()
        super.onDestroy()
    }
    override fun onClick() {
        super.onClick()
        if (clicking) return
        clicking = true
        if (isLocked) unlockAndRun { toggle() } else toggle()
    }
    private fun toggle() {
        try {
            if (updateInProgress) return
            val state = GreenVpnRuntimeFailoverService.snapshot(this)
            when (GreenVpnQuickTilePolicy.action(state["state"].toString(),
                state["desired"] == true, GreenVpnNetworkTransition.isActive(this))) {
                "wait" -> return
                "disconnect" -> GreenVpnRuntimeFailoverService.requestManagedDisconnect(this)
                else -> {
                    val saved = preferences(this)
                    if (!saved.getBoolean("configured", false) || VpnService.prepare(this) != null ||
                        state["state"] == "authentication_required") {
                        openApp()
                        return
                    }
                    val reply = GreenVpnRuntimeFailoverService.requestManagedConnect(this,
                        saved.getString("server", "").orEmpty(), saved.getString("mode", "full").orEmpty(),
                        saved.getStringSet("packages", emptySet()).orEmpty().toSet())
                    if (reply["ok"] != true || reply["permissionRequired"] == true) openApp()
                }
            }
            refresh()
        } catch (_: Exception) {
            Toast.makeText(this, "Откройте Green VPN, чтобы проверить подключение.", Toast.LENGTH_SHORT).show()
            openApp()
        } finally { clicking = false }
    }
    private fun refresh() {
        val tile = qsTile ?: return
        val state = GreenVpnRuntimeFailoverService.snapshot(this)
        val name = state["state"].toString()
        val own = GreenVpnNetworkTransition.isActive(this)
        val busy = (GreenVpnQuickTilePolicy.busy(name) || name == "error") && state["desired"] == true
        tile.label = "Green VPN"
        tile.state = when {
            updateInProgress || name == "disconnecting" -> Tile.STATE_UNAVAILABLE
            own || busy -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = when {
            updateInProgress -> "Обновление"
            name == "disconnecting" -> "Отключение"
            name == "waiting_for_network" || (name == "degraded_no_network" && own) -> "Ожидание сети"
            name == "error" && busy -> "Повторное подключение"
            busy -> "Подключение"
            own -> "Включён"
            name == "authentication_required" -> "Нужен вход"
            else -> "Выключен"
        }
        tile.updateTile()
    }
    @Suppress("DEPRECATION")
    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 7305, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        } else startActivityAndCollapse(intent)
    }
}
