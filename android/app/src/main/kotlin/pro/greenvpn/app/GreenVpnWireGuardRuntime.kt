package pro.greenvpn.app

import android.content.Context
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel

/** One standard tunnel runtime shared by the activity, tile and watchdog. */
internal object GreenVpnWireGuardRuntime {
    private val lock = Any()

    @Volatile
    private var sharedBackend: GoBackend? = null

    val tunnel: Tunnel = SharedTunnel("GreenVPN")

    fun backend(context: Context): GoBackend {
        sharedBackend?.let { return it }
        return synchronized(lock) {
            sharedBackend ?: GoBackend(context.applicationContext).also { sharedBackend = it }
        }
    }

    private class SharedTunnel(private val tunnelName: String) : Tunnel {
        override fun getName(): String = tunnelName

        override fun onStateChange(newState: Tunnel.State) = Unit
    }
}
