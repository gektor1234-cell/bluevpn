package pro.greenvpn.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.net.VpnService
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.content.FileProvider
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "green_vpn/android_vpn"
        const val VPN_PERMISSION_REQUEST = 48737
        const val SECURE_PREFS_NAME = "greenvpn_secure_config_store_v1"
        const val SECURE_KEY_ALIAS = "greenvpn_config_aes_v1"
        const val GCM_TAG_BITS = 128
        const val OWN_VPN_ACTIVE_KEY = "greenvpn_android_own_vpn_active_v1"
        const val OWN_VPN_ACTIVE_WALL_AT_KEY = "greenvpn_android_own_vpn_active_wall_at_v1"
        const val OWN_VPN_ACTIVE_ELAPSED_AT_KEY = "greenvpn_android_own_vpn_active_elapsed_at_v1"
        const val OWN_VPN_MARKER_MAX_AGE_MS = 7L * 24L * 60L * 60L * 1000L
        val BACKEND_LOCK = Any()

        @Volatile
        var sharedBackend: GoBackend? = null

        @Volatile
        var sharedTunnel: GreenVpnTunnel? = null
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val tunnel: GreenVpnTunnel
        get() {
            sharedTunnel?.let { return it }
            return synchronized(BACKEND_LOCK) {
                sharedTunnel ?: GreenVpnTunnel("GreenVPN").also { sharedTunnel = it }
            }
        }
    private var pendingConnectResult: MethodChannel.Result? = null
    private var pendingConfig: Any? = null
    private var pendingProtocol: String = "wireguard_udp"
    private var pendingInstallApkPath: String? = null
    private val securePrefs by lazy {
        applicationContext.getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> handleStatusV2(call, result)
                "connect" -> handleConnect(call, result)
                "disconnect" -> handleDisconnect(result)
                "secureRead" -> handleSecureRead(call, result)
                "secureWrite" -> handleSecureWrite(call, result)
                "secureDelete" -> handleSecureDelete(call, result)
                "listInstalledApps" -> handleListInstalledApps(result)
                "openUrl" -> handleOpenUrl(call, result)
                "getUpdateCacheDir" -> handleGetUpdateCacheDir(result)
                "installApk" -> handleInstallApk(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        maybeResumePendingApkInstall()
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    @Deprecated("Deprecated in Android API, still supported by FlutterActivity here.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_PERMISSION_REQUEST) return

        val result = pendingConnectResult
        val config = pendingConfig
        val protocol = pendingProtocol
        pendingConnectResult = null
        pendingConfig = null
        pendingProtocol = "wireguard_udp"

        if (result == null) return
        if (resultCode != Activity.RESULT_OK || config == null) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "Android не выдал разрешение на VPN. Подтверди системный запрос и попробуй снова."
                )
            )
            return
        }

        connectWithConfig(protocol, config, result)
    }

    private fun backend(): GoBackend {
        sharedBackend?.let { return it }
        return synchronized(BACKEND_LOCK) {
            sharedBackend ?: GoBackend(applicationContext).also { sharedBackend = it }
        }
    }

    private fun handleConnect(call: MethodCall, result: MethodChannel.Result) {
        if (pendingConnectResult != null) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "Green VPN уже ждёт системное разрешение Android."
                )
            )
            return
        }

        val configText = call.argument<String>("config").orEmpty().trim()
        val protocol = call.argument<String>("protocol")
            .orEmpty()
            .trim()
            .lowercase()
            .ifEmpty { "wireguard_udp" }
        if (configText.isEmpty()) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "VPN-конфиг пустой. Сначала войди в аккаунт и получи конфиг с сервера."
                )
            )
            return
        }

        val effectiveConfigText = if (protocol in setOf("hysteria2", "vless_reality", "naive_https", "dnstt")) {
            configText
        } else {
            filterVpnApplicationSelectors(configText)
        }
        if (protocol !in setOf("wireguard_udp", "amneziawg", "hysteria2", "vless_reality", "naive_https", "dnstt")) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "Этот VPN-режим не поддерживается текущей сборкой."
                )
            )
            return
        }
        if (protocol == "amneziawg" && !GreenVpnAwg2Preview.isAvailable()) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "AWG2 доступен только в специальной preview-сборке."
                )
            )
            return
        }
        if (protocol == "hysteria2" && !GreenVpnHysteria2Preview.isAvailable(applicationContext)) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "Этот режим доступен только в специальной preview-сборке."
                )
            )
            return
        }
        if (protocol == "vless_reality" && !GreenVpnVlessRealityPreview.isAvailable(applicationContext)) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "This mode is available only in a dedicated preview build."
                )
            )
            return
        }
        if (protocol == "naive_https" && !GreenVpnNaiveHttpsPreview.isAvailable(applicationContext)) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "This mode is available only in a dedicated preview build."
                )
            )
            return
        }
        if (protocol == "dnstt" && !GreenVpnDnsttPreview.isAvailable(applicationContext)) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "Transport preview engine is unavailable."
                )
            )
            return
        }

        val parsed: Any = try {
            when {
                protocol == "hysteria2" -> GreenVpnHysteria2Preview.validateConfig(effectiveConfigText)
                protocol == "vless_reality" -> GreenVpnVlessRealityPreview.validateConfig(effectiveConfigText)
                protocol == "naive_https" -> GreenVpnNaiveHttpsPreview.validateConfig(effectiveConfigText)
                protocol == "dnstt" -> GreenVpnDnsttPreview.validateConfig(effectiveConfigText)
                protocol == "amneziawg" ||
                    (protocol == "wireguard_udp" && BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) ->
                    GreenVpnAwg2Preview.parseConfig(effectiveConfigText)
                else -> Config.parse(
                    ByteArrayInputStream(effectiveConfigText.toByteArray(StandardCharsets.UTF_8))
                )
            }
        } catch (e: Exception) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "Android не смог подготовить VPN-подключение: ${safeError(e)}"
                )
            )
            return
        }

        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent != null) {
            pendingConnectResult = result
            pendingConfig = parsed
            pendingProtocol = protocol
            startActivityForResult(permissionIntent, VPN_PERMISSION_REQUEST)
            return
        }

        connectWithConfig(protocol, parsed, result)
    }

    private fun connectWithConfig(protocol: String, config: Any, result: MethodChannel.Result) {
        executor.execute {
            try {
                if (protocol != "dnstt") {
                    val dnstt = GreenVpnDnsttPreview.snapshot(applicationContext)
                    if (dnstt.connected || dnstt.state == "starting" || dnstt.state == "error") {
                        GreenVpnDnsttPreview.disconnect(applicationContext)
                    }
                }
                val connected = if (protocol == "dnstt") {
                    val naive = GreenVpnNaiveHttpsPreview.snapshot(applicationContext)
                    if (naive.connected || naive.state == "starting") {
                        GreenVpnNaiveHttpsPreview.disconnect(applicationContext)
                    }
                    val vless = GreenVpnVlessRealityPreview.snapshot(applicationContext)
                    if (vless.connected || vless.state == "starting") {
                        GreenVpnVlessRealityPreview.disconnect(applicationContext)
                    }
                    val hysteria = GreenVpnHysteria2Preview.snapshot(applicationContext)
                    if (hysteria.connected || hysteria.state == "starting") {
                        GreenVpnHysteria2Preview.disconnect(applicationContext)
                    }
                    if (GreenVpnAwg2Preview.isAvailable()) {
                        GreenVpnAwg2Preview.disconnect(applicationContext)
                    }
                    val currentBackend = backend()
                    if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                        currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                    }
                    if (!waitForOwnVpnNetworkInactive(2_500L)) {
                        throw IllegalStateException("Android did not stop the previous VPN connection")
                    }
                    GreenVpnDnsttPreview.connect(applicationContext, config as String)
                } else if (protocol == "naive_https") {
                    val vless = GreenVpnVlessRealityPreview.snapshot(applicationContext)
                    if (vless.connected || vless.state == "starting") {
                        GreenVpnVlessRealityPreview.disconnect(applicationContext)
                    }
                    val hysteria = GreenVpnHysteria2Preview.snapshot(applicationContext)
                    if (hysteria.connected || hysteria.state == "starting") {
                        GreenVpnHysteria2Preview.disconnect(applicationContext)
                    }
                    if (GreenVpnAwg2Preview.isAvailable()) {
                        GreenVpnAwg2Preview.disconnect(applicationContext)
                    }
                    val currentBackend = backend()
                    if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                        currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                    }
                    if (!waitForOwnVpnNetworkInactive(2_500L)) {
                        throw IllegalStateException("Android did not stop the previous VPN connection")
                    }
                    GreenVpnNaiveHttpsPreview.connect(applicationContext, config as String)
                } else if (protocol == "vless_reality") {
                    val naive = GreenVpnNaiveHttpsPreview.snapshot(applicationContext)
                    if (naive.connected || naive.state == "starting") {
                        GreenVpnNaiveHttpsPreview.disconnect(applicationContext)
                    }
                    val hysteria = GreenVpnHysteria2Preview.snapshot(applicationContext)
                    if (hysteria.connected || hysteria.state == "starting") {
                        GreenVpnHysteria2Preview.disconnect(applicationContext)
                    }
                    if (GreenVpnAwg2Preview.isAvailable()) {
                        GreenVpnAwg2Preview.disconnect(applicationContext)
                    }
                    val currentBackend = backend()
                    if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                        currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                    }
                    if (!waitForOwnVpnNetworkInactive(2_500L)) {
                        throw IllegalStateException("Android did not stop the previous VPN connection")
                    }
                    GreenVpnVlessRealityPreview.connect(applicationContext, config as String)
                } else if (protocol == "hysteria2") {
                    val naive = GreenVpnNaiveHttpsPreview.snapshot(applicationContext)
                    if (naive.connected || naive.state == "starting") {
                        GreenVpnNaiveHttpsPreview.disconnect(applicationContext)
                    }
                    val vless = GreenVpnVlessRealityPreview.snapshot(applicationContext)
                    if (vless.connected || vless.state == "starting") {
                        GreenVpnVlessRealityPreview.disconnect(applicationContext)
                    }
                    if (GreenVpnAwg2Preview.isAvailable()) {
                        GreenVpnAwg2Preview.disconnect(applicationContext)
                    }
                    val currentBackend = backend()
                    if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                        currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                    }
                    if (!waitForOwnVpnNetworkInactive(2_500L)) {
                        throw IllegalStateException("Android не завершил предыдущее VPN-подключение")
                    }
                    GreenVpnHysteria2Preview.connect(applicationContext, config as String)
                } else if (
                    protocol == "amneziawg" ||
                    (protocol == "wireguard_udp" && BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED)
                ) {
                    val naive = GreenVpnNaiveHttpsPreview.snapshot(applicationContext)
                    if (naive.connected || naive.state == "starting") {
                        GreenVpnNaiveHttpsPreview.disconnect(applicationContext)
                    }
                    val vless = GreenVpnVlessRealityPreview.snapshot(applicationContext)
                    if (vless.connected || vless.state == "starting") {
                        GreenVpnVlessRealityPreview.disconnect(applicationContext)
                    }
                    val hysteria = GreenVpnHysteria2Preview.snapshot(applicationContext)
                    if (hysteria.connected || hysteria.state == "starting") {
                        GreenVpnHysteria2Preview.disconnect(applicationContext)
                    }
                    if (!BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) {
                        val currentBackend = backend()
                        if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                            currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                        }
                    }
                    GreenVpnAwg2Preview.connect(applicationContext, config)
                } else {
                    val naive = GreenVpnNaiveHttpsPreview.snapshot(applicationContext)
                    if (naive.connected || naive.state == "starting") {
                        GreenVpnNaiveHttpsPreview.disconnect(applicationContext)
                    }
                    val vless = GreenVpnVlessRealityPreview.snapshot(applicationContext)
                    if (vless.connected || vless.state == "starting") {
                        GreenVpnVlessRealityPreview.disconnect(applicationContext)
                    }
                    val hysteria = GreenVpnHysteria2Preview.snapshot(applicationContext)
                    if (hysteria.connected || hysteria.state == "starting") {
                        GreenVpnHysteria2Preview.disconnect(applicationContext)
                    }
                    if (GreenVpnAwg2Preview.isAvailable()) {
                        GreenVpnAwg2Preview.disconnect(applicationContext)
                    }
                    val currentBackend = backend()
                    if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                        currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                        if (!waitForOwnVpnNetworkInactive(2_500L)) {
                            throw IllegalStateException("Android не завершил предыдущее VPN-подключение")
                        }
                    }
                    currentBackend.setState(tunnel, Tunnel.State.UP, config as Config) == Tunnel.State.UP
                }
                if (connected) {
                    markOwnVpnActive()
                } else {
                    markOwnVpnInactive()
                }
                runOnUiThread {
                    result.success(
                        response(
                            ok = connected,
                            connected = connected,
                            message = if (connected) {
                                "VPN подключён."
                            } else {
                                "Android не подтвердил запуск VPN."
                            }
                        )
                    )
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.success(
                        response(
                            ok = false,
                            connected = false,
                            message = "Не удалось включить VPN на Android: ${safeError(e)}"
                        )
                    )
                }
            }
        }
    }

    private fun handleDisconnect(result: MethodChannel.Result) {
        executor.execute {
            try {
                val dnstt = GreenVpnDnsttPreview.snapshot(applicationContext)
                if (dnstt.connected || dnstt.state == "starting" || dnstt.state == "error") {
                    val disconnected = GreenVpnDnsttPreview.disconnect(applicationContext)
                    if (disconnected) markOwnVpnInactive()
                    runOnUiThread {
                        result.success(
                            response(
                                ok = disconnected,
                                connected = !disconnected,
                                message = if (disconnected) "VPN disabled." else "VPN is still active."
                            )
                        )
                    }
                    return@execute
                }
                val naive = GreenVpnNaiveHttpsPreview.snapshot(applicationContext)
                if (naive.connected || naive.state == "starting" || naive.state == "error") {
                    val disconnected = GreenVpnNaiveHttpsPreview.disconnect(applicationContext)
                    if (disconnected) markOwnVpnInactive()
                    runOnUiThread {
                        result.success(
                            response(
                                ok = disconnected,
                                connected = !disconnected,
                                message = if (disconnected) "VPN disabled." else "VPN is still active."
                            )
                        )
                    }
                    return@execute
                }
                val vless = GreenVpnVlessRealityPreview.snapshot(applicationContext)
                if (vless.connected || vless.state == "starting" || vless.state == "error") {
                    val disconnected = GreenVpnVlessRealityPreview.disconnect(applicationContext)
                    if (disconnected) markOwnVpnInactive()
                    runOnUiThread {
                        result.success(
                            response(
                                ok = disconnected,
                                connected = !disconnected,
                                message = if (disconnected) "VPN disabled." else "VPN is still active."
                            )
                        )
                    }
                    return@execute
                }
                val hysteria = GreenVpnHysteria2Preview.snapshot(applicationContext)
                if (hysteria.connected || hysteria.state == "starting" || hysteria.state == "error") {
                    val disconnected = GreenVpnHysteria2Preview.disconnect(applicationContext)
                    if (disconnected) markOwnVpnInactive()
                    runOnUiThread {
                        result.success(
                            response(
                                ok = disconnected,
                                connected = !disconnected,
                                message = if (disconnected) "VPN выключен." else "VPN ещё активен."
                            )
                        )
                    }
                    return@execute
                }
                if (BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) {
                    val disconnected = GreenVpnAwg2Preview.disconnect(applicationContext)
                    if (disconnected) markOwnVpnInactive()
                    runOnUiThread {
                        result.success(
                            response(
                                ok = disconnected,
                                connected = !disconnected,
                                message = if (disconnected) "VPN выключен." else "VPN ещё активен."
                            )
                        )
                    }
                    return@execute
                }
                val currentBackend = backend()
                val state = currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                val awgDisconnected = GreenVpnAwg2Preview.disconnect(applicationContext)
                val runningNames = currentBackend.getRunningTunnelNames().toList()
                val stillRunning = runningNames.contains(tunnel.getName()) ||
                    !waitForOwnVpnNetworkInactive(2_500L)
                val disconnected = state == Tunnel.State.DOWN && awgDisconnected && !stillRunning
                if (disconnected) {
                    markOwnVpnInactive()
                }
                runOnUiThread {
                    result.success(
                        response(
                            ok = disconnected,
                            connected = state == Tunnel.State.UP || stillRunning,
                            message = if (disconnected) {
                                "VPN выключен."
                            } else {
                                "Android вернул состояние VPN: $state"
                            }
                        )
                    )
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.success(
                        response(
                            ok = false,
                            connected = false,
                            message = "Не удалось выключить VPN на Android: ${safeError(e)}"
                        )
                    )
                }
            }
        }
    }

    private fun waitForOwnVpnNetworkInactive(timeoutMs: Long): Boolean {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (isOwnVpnNetworkActive() && SystemClock.elapsedRealtime() < deadline) {
            Thread.sleep(50L)
        }
        return !isOwnVpnNetworkActive()
    }

    private fun handleStatus(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                val currentBackend = backend()
                val state = currentBackend.getState(tunnel)
                val runningNames = currentBackend.getRunningTunnelNames().toList()
                val ownRunning = state == Tunnel.State.UP || runningNames.contains(tunnel.getName())
                val stats = if (state == Tunnel.State.UP) currentBackend.getStatistics(tunnel) else null
                runOnUiThread {
                    result.success(
                        mapOf(
                            "ok" to true,
                            "connected" to ownRunning,
                            "state" to state.name.lowercase(),
                            "rxBytes" to (stats?.totalRx() ?: 0L),
                            "txBytes" to (stats?.totalTx() ?: 0L),
                            "version" to currentBackend.getVersion(),
                            "runningTunnels" to runningNames,
                            "systemVpnActive" to isAnyVpnNetworkActive()
                        )
                    )
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.success(
                        response(
                            ok = false,
                            connected = false,
                            message = "Не удалось проверить VPN на Android: ${safeError(e)}"
                        )
                    )
                }
            }
        }
    }

    private fun handleStatusV2(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            val requestedName = call.argument<String>("name").orEmpty()
            val systemVpnActive = isAnyVpnNetworkActive()
            val systemOwnVpnActive = systemVpnActive && isOwnVpnNetworkActive()
            if (!systemVpnActive) {
                markOwnVpnInactive()
            }
            if (BuildConfig.GREENVPN_DNSTT_PREVIEW_ENABLED) {
                val dnstt = GreenVpnDnsttPreview.snapshot(applicationContext)
                if (dnstt.connected || dnstt.state == "starting") {
                    val markerOwnRunning = !systemOwnVpnActive &&
                        systemVpnActive &&
                        hasOwnVpnActiveMarker(systemVpnActive)
                    val ownRunning = dnstt.connected || systemOwnVpnActive || markerOwnRunning
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "ok" to dnstt.available,
                                "connected" to ownRunning,
                                "ownTunnelRunning" to ownRunning,
                                "state" to if (ownRunning) "up" else dnstt.state,
                                "rxBytes" to dnstt.rxBytes,
                                "txBytes" to dnstt.txBytes,
                                "version" to dnstt.version,
                                "runningTunnels" to if (ownRunning) listOf("GreenVPN") else emptyList<String>(),
                                "systemVpnActive" to systemVpnActive,
                                "systemVpnActiveWithoutOwnTunnel" to (systemVpnActive && !ownRunning),
                                "externalVpnActive" to (systemVpnActive && !ownRunning),
                                "lastGreenVpnActive" to (systemOwnVpnActive || markerOwnRunning),
                                "lastGreenVpnActiveAgeMs" to ownVpnMarkerAgeMs(),
                                "ownTunnelSource" to when {
                                    dnstt.connected -> "dnstt"
                                    systemOwnVpnActive -> "system_owner"
                                    markerOwnRunning -> "marker"
                                    else -> "none"
                                },
                                "nativeTunnelName" to "GreenVPN",
                                "requestedTunnelName" to requestedName,
                                "statusError" to dnstt.error
                            )
                        )
                    }
                    return@execute
                }
            }
            if (BuildConfig.GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED) {
                val naive = GreenVpnNaiveHttpsPreview.snapshot(applicationContext)
                if (naive.connected || naive.state == "starting") {
                    val markerOwnRunning = !systemOwnVpnActive &&
                        systemVpnActive &&
                        hasOwnVpnActiveMarker(systemVpnActive)
                    val ownRunning = naive.connected || systemOwnVpnActive || markerOwnRunning
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "ok" to naive.available,
                                "connected" to ownRunning,
                                "ownTunnelRunning" to ownRunning,
                                "state" to if (ownRunning) "up" else naive.state,
                                "rxBytes" to naive.rxBytes,
                                "txBytes" to naive.txBytes,
                                "version" to naive.version,
                                "runningTunnels" to if (ownRunning) listOf("GreenVPN") else emptyList<String>(),
                                "systemVpnActive" to systemVpnActive,
                                "systemVpnActiveWithoutOwnTunnel" to (systemVpnActive && !ownRunning),
                                "externalVpnActive" to (systemVpnActive && !ownRunning),
                                "lastGreenVpnActive" to (systemOwnVpnActive || markerOwnRunning),
                                "lastGreenVpnActiveAgeMs" to ownVpnMarkerAgeMs(),
                                "ownTunnelSource" to when {
                                    naive.connected -> "naive_https"
                                    systemOwnVpnActive -> "system_owner"
                                    markerOwnRunning -> "marker"
                                    else -> "none"
                                },
                                "nativeTunnelName" to "GreenVPN",
                                "requestedTunnelName" to requestedName,
                                "statusError" to naive.error
                            )
                        )
                    }
                    return@execute
                }
            }
            if (BuildConfig.GREENVPN_VLESS_REALITY_PREVIEW_ENABLED) {
                val vless = GreenVpnVlessRealityPreview.snapshot(applicationContext)
                if (vless.connected || vless.state == "starting") {
                    val markerOwnRunning = !systemOwnVpnActive &&
                        systemVpnActive &&
                        hasOwnVpnActiveMarker(systemVpnActive)
                    val ownRunning = vless.connected || systemOwnVpnActive || markerOwnRunning
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "ok" to vless.available,
                                "connected" to ownRunning,
                                "ownTunnelRunning" to ownRunning,
                                "state" to if (ownRunning) "up" else vless.state,
                                "rxBytes" to vless.rxBytes,
                                "txBytes" to vless.txBytes,
                                "version" to vless.version,
                                "runningTunnels" to if (ownRunning) listOf("GreenVPN") else emptyList<String>(),
                                "systemVpnActive" to systemVpnActive,
                                "systemVpnActiveWithoutOwnTunnel" to (systemVpnActive && !ownRunning),
                                "externalVpnActive" to (systemVpnActive && !ownRunning),
                                "lastGreenVpnActive" to (systemOwnVpnActive || markerOwnRunning),
                                "lastGreenVpnActiveAgeMs" to ownVpnMarkerAgeMs(),
                                "ownTunnelSource" to when {
                                    vless.connected -> "vless_reality"
                                    systemOwnVpnActive -> "system_owner"
                                    markerOwnRunning -> "marker"
                                    else -> "none"
                                },
                                "nativeTunnelName" to "GreenVPN",
                                "requestedTunnelName" to requestedName,
                                "statusError" to vless.error
                            )
                        )
                    }
                    return@execute
                }
            }
            if (BuildConfig.GREENVPN_HYSTERIA2_PREVIEW_ENABLED) {
                val hysteria = GreenVpnHysteria2Preview.snapshot(applicationContext)
                if (hysteria.connected || hysteria.state == "starting") {
                    val markerOwnRunning = !systemOwnVpnActive &&
                        systemVpnActive &&
                        hasOwnVpnActiveMarker(systemVpnActive)
                    val ownRunning = hysteria.connected || systemOwnVpnActive || markerOwnRunning
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "ok" to hysteria.available,
                                "connected" to ownRunning,
                                "ownTunnelRunning" to ownRunning,
                                "state" to if (ownRunning) "up" else hysteria.state,
                                "rxBytes" to hysteria.rxBytes,
                                "txBytes" to hysteria.txBytes,
                                "version" to hysteria.version,
                                "runningTunnels" to if (ownRunning) listOf("GreenVPN") else emptyList<String>(),
                                "systemVpnActive" to systemVpnActive,
                                "systemVpnActiveWithoutOwnTunnel" to (systemVpnActive && !ownRunning),
                                "externalVpnActive" to (systemVpnActive && !ownRunning),
                                "lastGreenVpnActive" to (systemOwnVpnActive || markerOwnRunning),
                                "lastGreenVpnActiveAgeMs" to ownVpnMarkerAgeMs(),
                                "ownTunnelSource" to when {
                                    hysteria.connected -> "hysteria2"
                                    systemOwnVpnActive -> "system_owner"
                                    markerOwnRunning -> "marker"
                                    else -> "none"
                                },
                                "nativeTunnelName" to "GreenVPN",
                                "requestedTunnelName" to requestedName,
                                "statusError" to hysteria.error
                            )
                        )
                    }
                    return@execute
                }
            }
            if (BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) {
                val awg = GreenVpnAwg2Preview.snapshot(applicationContext)
                val markerOwnRunning = !systemOwnVpnActive &&
                    systemVpnActive &&
                    hasOwnVpnActiveMarker(systemVpnActive)
                val ownRunning = awg.connected || systemOwnVpnActive || markerOwnRunning
                runOnUiThread {
                    result.success(
                        mapOf(
                            "ok" to awg.available,
                            "connected" to ownRunning,
                            "ownTunnelRunning" to ownRunning,
                            "state" to if (ownRunning) "up" else awg.state,
                            "rxBytes" to awg.rxBytes,
                            "txBytes" to awg.txBytes,
                            "version" to awg.version,
                            "runningTunnels" to awg.runningTunnels,
                            "systemVpnActive" to systemVpnActive,
                            "systemVpnActiveWithoutOwnTunnel" to (systemVpnActive && !ownRunning),
                            "externalVpnActive" to (systemVpnActive && !ownRunning),
                            "lastGreenVpnActive" to (systemOwnVpnActive || markerOwnRunning),
                            "lastGreenVpnActiveAgeMs" to ownVpnMarkerAgeMs(),
                            "ownTunnelSource" to when {
                                awg.connected -> "backend"
                                systemOwnVpnActive -> "system_owner"
                                markerOwnRunning -> "marker"
                                else -> "none"
                            },
                            "nativeTunnelName" to "GreenVPN",
                            "requestedTunnelName" to requestedName,
                            "statusError" to awg.error
                        )
                    )
                }
                return@execute
            }
            val statusErrors = mutableListOf<String>()
            val currentBackend = try {
                backend()
            } catch (e: Exception) {
                statusErrors.add("backend=${safeError(e)}")
                null
            }

            val runningNames = try {
                currentBackend?.getRunningTunnelNames()?.toList() ?: emptyList()
            } catch (e: Exception) {
                statusErrors.add("running=${safeError(e)}")
                emptyList()
            }

            val state = try {
                currentBackend?.getState(tunnel)
            } catch (e: Exception) {
                statusErrors.add("state=${safeError(e)}")
                null
            }

            val backendOwnRunning = systemVpnActive &&
                (state == Tunnel.State.UP || runningNames.contains(tunnel.getName()))
            val markerOwnRunning = !backendOwnRunning && !systemOwnVpnActive &&
                systemVpnActive &&
                hasOwnVpnActiveMarker(systemVpnActive)
            val ownRunning = backendOwnRunning || systemOwnVpnActive || markerOwnRunning
            val markerAgeMs = ownVpnMarkerAgeMs()
            val stats = try {
                if (backendOwnRunning && currentBackend != null) currentBackend.getStatistics(tunnel) else null
            } catch (e: Exception) {
                statusErrors.add("stats=${safeError(e)}")
                null
            }

            val version = try {
                currentBackend?.getVersion().orEmpty()
            } catch (e: Exception) {
                statusErrors.add("version=${safeError(e)}")
                ""
            }

            runOnUiThread {
                result.success(
                    mapOf(
                        "ok" to (currentBackend != null),
                        "connected" to ownRunning,
                        "ownTunnelRunning" to ownRunning,
                        "state" to if (systemOwnVpnActive || markerOwnRunning) "up" else (state?.name?.lowercase() ?: "unknown"),
                        "rxBytes" to (stats?.totalRx() ?: 0L),
                        "txBytes" to (stats?.totalTx() ?: 0L),
                        "version" to version,
                        "runningTunnels" to runningNames,
                        "systemVpnActive" to systemVpnActive,
                        "systemVpnActiveWithoutOwnTunnel" to (systemVpnActive && !ownRunning),
                        "externalVpnActive" to (systemVpnActive && !ownRunning),
                        "lastGreenVpnActive" to (systemOwnVpnActive || markerOwnRunning),
                        "lastGreenVpnActiveAgeMs" to markerAgeMs,
                        "ownTunnelSource" to when {
                            backendOwnRunning -> "backend"
                            systemOwnVpnActive -> "system_owner"
                            markerOwnRunning -> "marker"
                            else -> "none"
                        },
                        "nativeTunnelName" to tunnel.getName(),
                        "requestedTunnelName" to requestedName,
                        "statusError" to statusErrors.joinToString("; ")
                    )
                )
            }
        }
    }

    private fun handleOpenUrl(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url").orEmpty().trim()
        if (url.isEmpty()) {
            result.success(response(ok = false, connected = false, message = "URL пустой."))
            return
        }
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            startActivity(intent)
            result.success(response(ok = true, connected = false, message = "Ссылка открыта."))
        } catch (e: Exception) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "Не удалось открыть ссылку: ${safeError(e)}"
                )
            )
        }
    }

    private fun filterVpnApplicationSelectors(configText: String): String {
        val fieldRegex = Regex(
            "^\\s*(IncludedApplications|ExcludedApplications)\\s*=\\s*(.*?)\\s*$",
            setOf(RegexOption.IGNORE_CASE)
        )
        val lines = configText.split(Regex("\\r?\\n"))
        val filtered = mutableListOf<String>()
        for (line in lines) {
            val match = fieldRegex.matchEntire(line)
            if (match == null) {
                filtered.add(line)
                continue
            }
            val fieldName = match.groupValues[1]
            val packages = match.groupValues[2]
                .split(',')
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .filter { isPackageInstalled(it) }
                .distinct()
                .sorted()
            if (packages.isNotEmpty()) {
                filtered.add("$fieldName = ${packages.joinToString(", ")}")
            } else {
                filtered.add(line)
            }
        }
        return filtered.joinToString("\n")
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    android.content.pm.PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun handleListInstalledApps(result: MethodChannel.Result) {
        executor.execute {
            try {
                val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_LAUNCHER)
                }
                val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.queryIntentActivities(
                        launcherIntent,
                        PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong())
                    )
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.queryIntentActivities(launcherIntent, PackageManager.MATCH_ALL)
                }
                val apps = resolved
                    .mapNotNull { info ->
                        val appInfo = info.activityInfo?.applicationInfo ?: return@mapNotNull null
                        val packageName = appInfo.packageName?.trim().orEmpty()
                        if (packageName.isEmpty() || packageName == applicationContext.packageName) {
                            return@mapNotNull null
                        }
                        val label = info.loadLabel(packageManager)?.toString()?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: packageName
                        mapOf(
                            "packageName" to packageName,
                            "label" to label,
                            "system" to ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0)
                        )
                    }
                    .distinctBy { it["packageName"] }
                    .sortedWith(
                        compareBy<Map<String, Any>> {
                            it["label"].toString().lowercase()
                        }.thenBy { it["packageName"].toString() }
                    )
                runOnUiThread { result.success(apps) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "GREENVPN_INSTALLED_APPS",
                        "Не удалось получить список приложений: ${safeError(e)}",
                        null
                    )
                }
            }
        }
    }

    private fun handleGetUpdateCacheDir(result: MethodChannel.Result) {
        try {
            val dir = File(cacheDir, "greenvpn_updates")
            if (!dir.exists() && !dir.mkdirs()) {
                throw IllegalStateException("Update cache directory was not created")
            }
            result.success(dir.canonicalPath)
        } catch (e: Exception) {
            result.error("GREENVPN_UPDATE_CACHE", safeError(e), null)
        }
    }

    private fun handleInstallApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path").orEmpty().trim()
        if (path.isEmpty()) {
            result.success(response(ok = false, connected = false, message = "Путь к APK пустой."))
            return
        }

        val apk = try {
            File(path).canonicalFile
        } catch (e: Exception) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "Android не смог открыть файл обновления: ${safeError(e)}"
                )
            )
            return
        }

        if (!apk.exists() || !apk.isFile || !apk.name.lowercase().endsWith(".apk")) {
            result.success(response(ok = false, connected = false, message = "Файл обновления APK не найден."))
            return
        }

        val cacheRoot = cacheDir.canonicalFile
        val externalRoot = externalCacheDir?.canonicalFile
        val insideInternalCache = apk.path.startsWith(cacheRoot.path + File.separator)
        val insideExternalCache = externalRoot != null &&
            apk.path.startsWith(externalRoot.path + File.separator)
        if (!insideInternalCache && !insideExternalCache) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "APK должен быть загружен во временную папку Green VPN."
                )
            )
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            pendingInstallApkPath = apk.path
            try {
                val settingsIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
                startActivity(settingsIntent)
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES))
            }
            result.success(
                response(
                    ok = true,
                    connected = false,
                    message = "Allow Green VPN to install apps. The installer will continue automatically."
                )
            )
            return
        }

        try {
            val apkUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apk
            )
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(installIntent)
            result.success(response(ok = true, connected = false, message = "Открыта установка APK."))
        } catch (e: Exception) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "Не удалось открыть установку APK: ${safeError(e)}"
                )
            )
        }
    }

    private fun maybeResumePendingApkInstall() {
        val path = pendingInstallApkPath ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            return
        }

        pendingInstallApkPath = null
        try {
            val apk = File(path).canonicalFile
            if (apk.exists() && apk.isFile && apk.name.lowercase().endsWith(".apk")) {
                launchApkInstaller(apk)
            }
        } catch (_: Exception) {
            // Flutter will offer the update button again if Android cannot resume the installer.
        }
    }

    private fun launchApkInstaller(apk: File) {
        val apkUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apk
        )
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(installIntent)
    }

    private fun handleSecureRead(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key").orEmpty()
        if (!isAllowedSecureKey(key)) {
            result.success(null)
            return
        }

        try {
            result.success(readSecureString(key))
        } catch (e: Exception) {
            result.error("GREENVPN_SECURE_READ", safeError(e), null)
        }
    }

    private fun handleSecureWrite(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key").orEmpty()
        val value = call.argument<String>("value").orEmpty()
        if (!isAllowedSecureKey(key)) {
            result.error("GREENVPN_SECURE_KEY", "Недопустимый ключ локального хранилища.", null)
            return
        }

        try {
            writeSecureString(key, value)
            result.success(null)
        } catch (e: Exception) {
            result.error("GREENVPN_SECURE_WRITE", safeError(e), null)
        }
    }

    private fun handleSecureDelete(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key").orEmpty()
        if (!isAllowedSecureKey(key)) {
            result.success(null)
            return
        }

        try {
            if (!securePrefs.edit().remove(key).commit()) {
                throw IllegalStateException("Secure value was not deleted")
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("GREENVPN_SECURE_DELETE", safeError(e), null)
        }
    }

    private fun isAllowedSecureKey(key: String): Boolean {
        return key == "greenvpn_mobile_managed_config_v1" ||
            key == "greenvpn_mobile_managed_protocol_v1" ||
            key == "greenvpn_mobile_base_config_v1" ||
            key == "greenvpn_mobile_session_v1" ||
            key == "greenvpn_mobile_device_id_v1"
    }

    private fun readSecureString(key: String): String? {
        val stored = securePrefs.getString(key, null) ?: return null
        val parts = stored.split(":", limit = 2)
        if (parts.size != 2) return null

        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val encrypted = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateConfigKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return String(cipher.doFinal(encrypted), StandardCharsets.UTF_8)
    }

    private fun writeSecureString(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateConfigKey())
        val encrypted = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val body = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        if (!securePrefs.edit().putString(key, "$iv:$body").commit()) {
            throw IllegalStateException("Secure value was not saved")
        }
    }

    private fun getOrCreateConfigKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getEntry(SECURE_KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore"
        )
        val spec = KeyGenParameterSpec.Builder(
            SECURE_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun response(
        ok: Boolean,
        connected: Boolean,
        message: String
    ): Map<String, Any> {
        return mapOf(
            "ok" to ok,
            "connected" to connected,
            "state" to if (connected) "up" else "down",
            "message" to message
        )
    }

    private fun markOwnVpnActive() {
        securePrefs.edit()
            .putBoolean(OWN_VPN_ACTIVE_KEY, true)
            .putLong(OWN_VPN_ACTIVE_WALL_AT_KEY, System.currentTimeMillis())
            .putLong(OWN_VPN_ACTIVE_ELAPSED_AT_KEY, SystemClock.elapsedRealtime())
            .apply()
    }

    private fun markOwnVpnInactive() {
        securePrefs.edit()
            .remove(OWN_VPN_ACTIVE_KEY)
            .remove(OWN_VPN_ACTIVE_WALL_AT_KEY)
            .remove(OWN_VPN_ACTIVE_ELAPSED_AT_KEY)
            .apply()
    }

    private fun hasOwnVpnActiveMarker(systemVpnActive: Boolean): Boolean {
        if (!systemVpnActive) {
            markOwnVpnInactive()
            return false
        }
        if (!securePrefs.getBoolean(OWN_VPN_ACTIVE_KEY, false)) return false
        val startedAtElapsed = securePrefs.getLong(OWN_VPN_ACTIVE_ELAPSED_AT_KEY, -1L)
        val nowElapsed = SystemClock.elapsedRealtime()
        if (startedAtElapsed <= 0L || startedAtElapsed > nowElapsed) {
            markOwnVpnInactive()
            return false
        }
        if (nowElapsed - startedAtElapsed > OWN_VPN_MARKER_MAX_AGE_MS) {
            markOwnVpnInactive()
            return false
        }
        return true
    }

    private fun ownVpnMarkerAgeMs(): Long {
        val startedAtElapsed = securePrefs.getLong(OWN_VPN_ACTIVE_ELAPSED_AT_KEY, -1L)
        if (startedAtElapsed <= 0L) return -1L
        val nowElapsed = SystemClock.elapsedRealtime()
        if (startedAtElapsed > nowElapsed) return -1L
        return nowElapsed - startedAtElapsed
    }

    // activeNetwork misses non-default split-tunnel VPNs, so enumerate all networks here.
    @Suppress("DEPRECATION")
    private fun isAnyVpnNetworkActive(): Boolean {
        return try {
            val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            connectivity.allNetworks.any { network ->
                connectivity.getNetworkCapabilities(network)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            }
        } catch (_: Exception) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun isOwnVpnNetworkActive(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return try {
            val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            connectivity.allNetworks.any { network ->
                val capabilities = connectivity.getNetworkCapabilities(network)
                    ?: return@any false
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                    capabilities.ownerUid == applicationInfo.uid
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun safeError(error: Throwable): String {
        val message = error.message ?: error.javaClass.simpleName
        return message.replace(Regex("[\\r\\n]+"), " ").take(280)
    }

    private class GreenVpnTunnel(private val tunnelName: String) : Tunnel {
        @Volatile
        private var state: Tunnel.State = Tunnel.State.DOWN

        override fun getName(): String = tunnelName

        override fun onStateChange(newState: Tunnel.State) {
            state = newState
        }
    }
}
