package pro.greenvpn.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest

internal object GreenVpnUnderlyingNetwork {
    data class Snapshot(
        val internetNetworkAvailable: Boolean,
        val validatedNetworkAvailable: Boolean,
    )

    fun snapshot(context: Context): Snapshot {
        val manager = context.applicationContext
            .getSystemService(ConnectivityManager::class.java)
        var internet = false
        var validated = false
        for (network in manager.allNetworks) {
            val capabilities = manager.getNetworkCapabilities(network) ?: continue
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
            internet = true
            if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
                validated = true
                break
            }
        }
        return Snapshot(internet, validated)
    }

    fun register(context: Context, onChanged: () -> Unit): ConnectivityManager.NetworkCallback {
        val manager = context.applicationContext
            .getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = onChanged()
            override fun onLost(network: Network) = onChanged()
            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) = onChanged()
        }
        manager.registerNetworkCallback(
            NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build(),
            callback,
        )
        return callback
    }

    fun unregister(context: Context, callback: ConnectivityManager.NetworkCallback?) {
        if (callback == null) return
        try {
            context.applicationContext
                .getSystemService(ConnectivityManager::class.java)
                .unregisterNetworkCallback(callback)
        } catch (_: Throwable) {
        }
    }
}
