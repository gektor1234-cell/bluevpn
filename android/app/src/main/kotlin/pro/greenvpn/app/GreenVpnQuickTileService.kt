package pro.greenvpn.app

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Base64
import android.util.Log
import android.widget.Toast
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class GreenVpnQuickTileService : TileService() {
    private companion object {
        val API_BASE_URL = BuildConfig.GREENVPN_API_BASE_URL.trim().trimEnd('/')
        val API_FALLBACK_BASE_URLS = BuildConfig.GREENVPN_API_FALLBACK_BASE_URLS
            .split(',')
            .map { it.trim().trimEnd('/') }
            .filter { it.isNotEmpty() }
        val APP_VERSION = BuildConfig.GREENVPN_APP_VERSION
        val APP_LABEL = BuildConfig.GREENVPN_APP_LABEL
        val RELEASE_CHANNEL = BuildConfig.GREENVPN_RELEASE_CHANNEL.trim().ifEmpty { "stable" }
        val CLIENT_MARKER = BuildConfig.GREENVPN_CLIENT_MARKER.trim()
        const val SECURE_PREFS_NAME = "greenvpn_secure_config_store_v1"
        const val SECURE_KEY_ALIAS = "greenvpn_config_aes_v1"
        const val GCM_TAG_BITS = 128
        const val SESSION_KEY = "greenvpn_mobile_session_v1"
        const val DEVICE_ID_KEY = "greenvpn_mobile_device_id_v1"
        const val MANAGED_CONFIG_KEY = "greenvpn_mobile_managed_config_v1"
        const val MANAGED_PROTOCOL_KEY = "greenvpn_mobile_managed_protocol_v1"
        const val ROUTE_COOLDOWN_KEY = "greenvpn_quick_tile_route_cooldown_v1"
        const val LAST_ROUTE_SUCCESS_KEY = "greenvpn_quick_tile_last_route_success_v1"
        val FREE_PLAN_CODES = setOf("trial", "free", "free_start", "support_trial", "base")
        val SUPPORTED_PROTOCOLS = buildList {
            add("wireguard_udp")
            if (BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) add("amneziawg")
            if (BuildConfig.GREENVPN_HYSTERIA2_PREVIEW_ENABLED) add("hysteria2")
            if (BuildConfig.GREENVPN_VLESS_REALITY_PREVIEW_ENABLED) add("vless_reality")
            if (BuildConfig.GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED) add("naive_https")
            if (BuildConfig.GREENVPN_DNSTT_PREVIEW_ENABLED) add("dnstt")
        }
        val TRANSPORT_PREVIEW_ENABLED = SUPPORTED_PROTOCOLS.size > 1
        val TILE_EXECUTOR = Executors.newSingleThreadExecutor()
        const val DEBUG_TAG = "GreenVpnQuickTile"
    }

    private data class FetchedConfig(
        val config: String,
        val protocol: String,
        val serverId: String,
    )

    private data class CatalogCandidate(
        val serverId: String?,
        val protocol: String,
        val healthScore: Int,
        val latencyMs: Int?,
        val cooldownUntilMs: Long?,
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val tunnel: Tunnel
        get() = GreenVpnWireGuardRuntime.tunnel

    override fun onStartListening() {
        super.onStartListening()
        refreshTileState()
    }

    override fun onStopListening() {
        super.onStopListening()
        refreshTileState()
    }

    override fun onClick() {
        super.onClick()
        setTile(Tile.STATE_UNAVAILABLE, "Проверяем...")
        TILE_EXECUTOR.execute {
            try {
                GreenVpnRuntimeFailoverService.disarm(applicationContext)
                GreenVpnConnectionOperationGate.awaitIdle()
                if (isVpnConnected()) {
                    disconnectVpn()
                    if (TRANSPORT_PREVIEW_ENABLED) {
                        securePrefs().edit().remove(LAST_ROUTE_SUCCESS_KEY).commit()
                    }
                    showToast("Green VPN выключен.")
                    setTile(Tile.STATE_INACTIVE, "Отключено")
                    return@execute
                }

                val session = readSession()
                val accessToken = session.optString("accessToken").trim()
                val sessionApiBaseUrl = normalizeApiBaseUrl(session.optString("apiBaseUrl"))
                if (accessToken.isEmpty()) {
                    openApp("Войдите в Green VPN, чтобы использовать плитку.")
                    setTile(Tile.STATE_INACTIVE, "Нужен вход")
                    return@execute
                }

                val deviceId = readSecureString(DEVICE_ID_KEY)?.trim().orEmpty()
                if (deviceId.length < 8) {
                    openApp("Откройте Green VPN один раз, чтобы привязать устройство.")
                    setTile(Tile.STATE_INACTIVE, "Откройте приложение")
                    return@execute
                }

                val bootstrap = postJson(
                    path = "/api/v1/client/bootstrap",
                    accessToken = accessToken,
                    preferredBaseUrl = sessionApiBaseUrl,
                    payload = JSONObject()
                        .put("deviceUid", deviceId)
                        .put("deviceName", "Android Quick Settings")
                        .put("platform", "android")
                        .put("appVersion", APP_VERSION)
                        .put("releaseChannel", RELEASE_CHANNEL)
                        .put("supportedProtocols", JSONArray(SUPPORTED_PROTOCOLS))
                        .apply {
                            if (CLIENT_MARKER.isNotEmpty()) put("clientMarker", CLIENT_MARKER)
                        }
                )
                val subscription = bootstrap.optJSONObject("subscription")
                if (!canConnectFromTile(subscription)) {
                    openApp(tileBlockedMessage())
                    setTile(Tile.STATE_INACTIVE, "Нужен Trial")
                    return@execute
                }

                val permissionIntent = VpnService.prepare(this)
                if (permissionIntent != null) {
                    openApp("Подтвердите системное разрешение VPN в приложении.")
                    setTile(Tile.STATE_INACTIVE, "Нужно разрешение")
                    return@execute
                }

                val candidates = fetchCatalogCandidates(sessionApiBaseUrl)
                if (TRANSPORT_PREVIEW_ENABLED) {
                    securePrefs().edit().remove(LAST_ROUTE_SUCCESS_KEY).commit()
                }
                var connectedConfig: FetchedConfig? = null
                for (candidate in candidates) {
                    debugLog("candidate_start protocol=${candidate.protocol}")
                    val fetched = try {
                        fetchFreshConfig(
                            accessToken = accessToken,
                            deviceId = deviceId,
                            preferredBaseUrl = sessionApiBaseUrl,
                            serverId = candidate.serverId,
                        )
                    } catch (failure: Exception) {
                        debugLog(
                            "candidate_fetch_failed protocol=${candidate.protocol} " +
                                "error=${safeError(failure)}"
                        )
                        null
                    }
                    if (fetched == null) {
                        recordRouteFailure(candidate)
                        continue
                    }

                    val connected = try {
                        connectVpn(fetched.config, fetched.protocol)
                    } catch (failure: Exception) {
                        debugLog(
                            "candidate_connect_exception protocol=${fetched.protocol} " +
                                "error=${safeError(failure)}"
                        )
                        false
                    }
                    if (connected) GreenVpnNetworkTransition.markActive(applicationContext)
                    if (!connected || (TRANSPORT_PREVIEW_ENABLED && !probeConnectedRoute(fetched.protocol))) {
                        debugLog(
                            "candidate_rejected protocol=${fetched.protocol} connected=$connected " +
                                transportFailureSummary(fetched.protocol)
                        )
                        val stopped = try { disconnectVpn() } catch (_: Exception) { false }
                        recordRouteFailure(candidate)
                        if (!stopped) {
                            debugLog(
                                "candidate_cleanup_failed protocol=${fetched.protocol}; " +
                                    "cascade_stopped"
                            )
                            break
                        }
                        continue
                    }

                    clearRouteFailure(candidate)
                    writeSecureString(MANAGED_CONFIG_KEY, fetched.config)
                    writeSecureString(MANAGED_PROTOCOL_KEY, fetched.protocol)
                    if (TRANSPORT_PREVIEW_ENABLED) {
                        writeSecureString(
                            LAST_ROUTE_SUCCESS_KEY,
                            JSONObject()
                                .put("serverId", fetched.serverId)
                                .put("protocol", fetched.protocol)
                                .put("verifiedAtMs", System.currentTimeMillis())
                                .toString(),
                        )
                    }
                    debugLog("candidate_success protocol=${fetched.protocol}")
                    connectedConfig = fetched
                    break
                }

                if (connectedConfig == null && candidates.size == 1 && candidates.first().serverId == null) {
                    val cachedConfig = readSecureString(MANAGED_CONFIG_KEY)?.trim()
                    val cachedProtocol = readSecureString(MANAGED_PROTOCOL_KEY)
                        ?.trim()?.lowercase() ?: "wireguard_udp"
                    if (!cachedConfig.isNullOrBlank()) {
                        val cachedConnected = try {
                            val engineConnected = connectVpn(cachedConfig, cachedProtocol)
                            if (engineConnected) {
                                GreenVpnNetworkTransition.markActive(applicationContext)
                            }
                            engineConnected &&
                                (!TRANSPORT_PREVIEW_ENABLED || probeConnectedRoute(cachedProtocol))
                        } catch (_: Exception) {
                            false
                        }
                        if (cachedConnected) {
                            connectedConfig = FetchedConfig(cachedConfig, cachedProtocol, "cached")
                        } else {
                            val stopped = try { disconnectVpn() } catch (_: Exception) { false }
                            if (!stopped) {
                                debugLog(
                                    "cached_candidate_cleanup_failed protocol=$cachedProtocol"
                                )
                            }
                        }
                    }
                }

                if (connectedConfig != null) {
                    val failoverArmed = GreenVpnRuntimeFailoverService.arm(
                        applicationContext,
                        connectedConfig.serverId,
                        connectedConfig.protocol,
                    )
                    debugLog("runtime_failover_armed=$failoverArmed")
                    showToast("Green VPN включен.")
                    setTile(Tile.STATE_ACTIVE, "Включено")
                } else {
                    showToast("Не удалось включить Green VPN.")
                    setTile(Tile.STATE_INACTIVE, "Ошибка")
                }
            } catch (e: Exception) {
                showToast("Green VPN: ${safeError(e)}")
                refreshTileState()
            }
        }
    }

    private fun refreshTileState() {
        TILE_EXECUTOR.execute {
            try {
                if (isVpnConnected()) {
                    setTile(Tile.STATE_ACTIVE, "Включено")
                } else {
                    setTile(Tile.STATE_INACTIVE, "Отключено")
                }
            } catch (_: Exception) {
                setTile(Tile.STATE_INACTIVE, "Отключено")
            }
        }
    }

    private fun backend(): GoBackend = GreenVpnWireGuardRuntime.backend(applicationContext)

    private fun isVpnConnected(): Boolean {
        if (GreenVpnDnsttPreview.snapshot(applicationContext).connected) return true
        if (GreenVpnNaiveHttpsPreview.snapshot(applicationContext).connected) return true
        if (GreenVpnVlessRealityPreview.snapshot(applicationContext).connected) return true
        if (GreenVpnHysteria2Preview.snapshot(applicationContext).connected) return true
        if (GreenVpnAwg2Preview.snapshot(applicationContext).connected) return true
        val currentBackend = backend()
        return currentBackend.getState(tunnel) == Tunnel.State.UP ||
            currentBackend.getRunningTunnelNames().contains(tunnel.getName())
    }

    private fun connectVpn(configText: String, protocol: String): Boolean {
        if (protocol == "dnstt") {
            require(GreenVpnDnsttPreview.isAvailable(applicationContext)) {
                "This mode is not included in the current build"
            }
            GreenVpnNaiveHttpsPreview.disconnect(applicationContext)
            GreenVpnVlessRealityPreview.disconnect(applicationContext)
            GreenVpnHysteria2Preview.disconnect(applicationContext)
            GreenVpnAwg2Preview.disconnect(applicationContext)
            val currentBackend = backend()
            if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                Thread.sleep(250)
            }
            requirePreviousVpnNetworkInactive()
            return GreenVpnDnsttPreview.connect(
                applicationContext,
                GreenVpnDnsttPreview.validateConfig(configText)
            )
        }
        val dnstt = GreenVpnDnsttPreview.snapshot(applicationContext)
        if (dnstt.connected || dnstt.state == "starting" || dnstt.state == "error") {
            GreenVpnDnsttPreview.disconnect(applicationContext)
        }
        if (protocol == "naive_https") {
            require(GreenVpnNaiveHttpsPreview.isAvailable(applicationContext)) {
                "This mode is not included in the current build"
            }
            GreenVpnVlessRealityPreview.disconnect(applicationContext)
            GreenVpnHysteria2Preview.disconnect(applicationContext)
            GreenVpnAwg2Preview.disconnect(applicationContext)
            val currentBackend = backend()
            if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                Thread.sleep(250)
            }
            requirePreviousVpnNetworkInactive()
            return GreenVpnNaiveHttpsPreview.connect(
                applicationContext,
                GreenVpnNaiveHttpsPreview.validateConfig(configText)
            )
        }
        if (protocol == "vless_reality") {
            require(GreenVpnVlessRealityPreview.isAvailable(applicationContext)) {
                "This mode is not included in the current build"
            }
            GreenVpnNaiveHttpsPreview.disconnect(applicationContext)
            GreenVpnHysteria2Preview.disconnect(applicationContext)
            GreenVpnAwg2Preview.disconnect(applicationContext)
            val currentBackend = backend()
            if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                Thread.sleep(250)
            }
            requirePreviousVpnNetworkInactive()
            val validated = GreenVpnVlessRealityPreview.validateConfig(configText)
            return GreenVpnVlessRealityPreview.connect(applicationContext, validated)
        }
        if (protocol == "hysteria2") {
            require(GreenVpnHysteria2Preview.isAvailable(applicationContext)) {
                "Этот режим не включён в текущую сборку"
            }
            GreenVpnNaiveHttpsPreview.disconnect(applicationContext)
            GreenVpnAwg2Preview.disconnect(applicationContext)
            GreenVpnVlessRealityPreview.disconnect(applicationContext)
            val currentBackend = backend()
            if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                Thread.sleep(250)
            }
            requirePreviousVpnNetworkInactive()
            val validated = GreenVpnHysteria2Preview.validateConfig(configText)
            return GreenVpnHysteria2Preview.connect(applicationContext, validated)
        }
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
        if (GreenVpnTunnelBackendPolicy.usesAmneziaBackend(protocol)) {
            val currentBackend = backend()
            if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
            }
            requirePreviousVpnNetworkInactive()
            val parsed = GreenVpnAwg2Preview.parseConfig(configText)
            return GreenVpnAwg2Preview.connect(applicationContext, parsed)
        }
        GreenVpnAwg2Preview.disconnect(applicationContext)
        val currentBackend = backend()
        if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
            currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
            Thread.sleep(250)
        }
        requirePreviousVpnNetworkInactive()
        val parsed = Config.parse(ByteArrayInputStream(configText.toByteArray(StandardCharsets.UTF_8)))
        return currentBackend.setState(tunnel, Tunnel.State.UP, parsed) == Tunnel.State.UP
    }

    private fun disconnectVpn(): Boolean {
        val dnstt = GreenVpnDnsttPreview.snapshot(applicationContext)
        if (dnstt.connected || dnstt.state == "starting" || dnstt.state == "error") {
            return finishDisconnect(GreenVpnDnsttPreview.disconnect(applicationContext))
        }
        val naive = GreenVpnNaiveHttpsPreview.snapshot(applicationContext)
        if (naive.connected || naive.state == "starting" || naive.state == "error") {
            return finishDisconnect(GreenVpnNaiveHttpsPreview.disconnect(applicationContext))
        }
        val vless = GreenVpnVlessRealityPreview.snapshot(applicationContext)
        if (vless.connected || vless.state == "starting" || vless.state == "error") {
            return finishDisconnect(GreenVpnVlessRealityPreview.disconnect(applicationContext))
        }
        val hysteria = GreenVpnHysteria2Preview.snapshot(applicationContext)
        if (hysteria.connected || hysteria.state == "starting" || hysteria.state == "error") {
            return finishDisconnect(GreenVpnHysteria2Preview.disconnect(applicationContext))
        }
        val awg = GreenVpnAwg2Preview.snapshot(applicationContext)
        if (GreenVpnTunnelBackendPolicy.previewSnapshotNeedsCleanup(awg.connected, awg.state)) {
            return finishDisconnect(GreenVpnAwg2Preview.disconnect(applicationContext))
        }
        val currentBackend = backend()
        val state = currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
        val awgDisconnected = GreenVpnAwg2Preview.disconnect(applicationContext)
        return finishDisconnect(
            state == Tunnel.State.DOWN && awgDisconnected &&
                !currentBackend.getRunningTunnelNames().contains(tunnel.getName())
        )
    }

    private fun finishDisconnect(disconnected: Boolean): Boolean {
        if (!disconnected) return false
        val inactive = GreenVpnNetworkTransition.waitForInactive(applicationContext, 2_500L)
        if (inactive) GreenVpnNetworkTransition.markInactive(applicationContext)
        return inactive
    }

    private fun requirePreviousVpnNetworkInactive() {
        check(GreenVpnNetworkTransition.waitForInactive(applicationContext, 2_500L)) {
            "Android did not finish the previous VPN connection"
        }
    }

    private fun fetchFreshConfig(
        accessToken: String,
        deviceId: String,
        preferredBaseUrl: String?,
        serverId: String?,
    ): FetchedConfig? {
        val payload = JSONObject()
            .put("deviceUid", deviceId)
            .put("mode", "full")
            .put("releaseChannel", RELEASE_CHANNEL)
            .put("supportedProtocols", JSONArray(SUPPORTED_PROTOCOLS))
        if (CLIENT_MARKER.isNotEmpty()) payload.put("clientMarker", CLIENT_MARKER)
        if (!serverId.isNullOrBlank()) payload.put("serverId", serverId)
        val json = postJson(
            path = "/api/v1/client/config",
            accessToken = accessToken,
            preferredBaseUrl = preferredBaseUrl,
            payload = payload,
        )
        val config = json.optString("configText").trim()
        val protocol = json.optString("protocol", "wireguard_udp").trim().lowercase()
        val returnedServerId = json.optString("serverId", serverId.orEmpty()).trim()
        return if (config.isEmpty()) null else FetchedConfig(config, protocol, returnedServerId)
    }

    private fun fetchCatalogCandidates(preferredBaseUrl: String?): List<CatalogCandidate> {
        if (!TRANSPORT_PREVIEW_ENABLED) {
            return listOf(CatalogCandidate(null, "wireguard_udp", 100, null, null))
        }
        return try {
            val channel = URLEncoder.encode(RELEASE_CHANNEL, StandardCharsets.UTF_8.name())
            val version = URLEncoder.encode(APP_VERSION, StandardCharsets.UTF_8.name())
            val response = getJson(
                path = "/api/v1/catalog/servers?channel=$channel&currentVersion=$version",
                preferredBaseUrl = preferredBaseUrl,
            )
            val servers = response.optJSONObject("catalog")?.optJSONArray("servers")
                ?: return listOf(CatalogCandidate(null, "wireguard_udp", 100, null, null))
            val nowMs = System.currentTimeMillis()
            val parsed = mutableListOf<CatalogCandidate>()
            for (index in 0 until servers.length()) {
                val server = servers.optJSONObject(index) ?: continue
                if (server.optBoolean("available", true).not()) continue
                if (server.optBoolean("clientConfigReady", true).not()) continue
                if (server.optString("status").trim().lowercase() == "disabled") continue
                val serverId = server.optString("id").trim()
                if (serverId.isEmpty()) continue
                val protocols = server.optJSONArray("protocols") ?: continue
                val protocol = protocols.optJSONObject(0)?.optString("code")
                    ?.trim()?.lowercase().orEmpty()
                if (protocol !in SUPPORTED_PROTOCOLS) continue
                val latency = if (server.has("latencyMs") && !server.isNull("latencyMs")) {
                    server.optInt("latencyMs")
                } else {
                    null
                }
                val cooldownUntil = readRouteCooldown(serverId, protocol)?.optLong("untilMs")
                    ?.takeIf { it > nowMs }
                parsed += CatalogCandidate(
                    serverId = serverId,
                    protocol = protocol,
                    healthScore = server.optInt("healthScore", 50),
                    latencyMs = latency,
                    cooldownUntilMs = cooldownUntil,
                )
            }
            if (parsed.isEmpty()) {
                listOf(CatalogCandidate(null, "wireguard_udp", 100, null, null))
            } else {
                val indexed = parsed.associateBy { requireNotNull(it.serverId) }
                GreenVpnQuickTileCascadePolicy.sort(
                    candidates = parsed.map {
                        GreenVpnTileRouteCandidate(
                            serverId = requireNotNull(it.serverId),
                            protocol = it.protocol,
                            healthScore = it.healthScore,
                            latencyMs = it.latencyMs,
                            cooldownUntilMs = it.cooldownUntilMs,
                        )
                    },
                    nowMs = nowMs,
                ).mapNotNull { indexed[it.serverId] }
            }
        } catch (_: Exception) {
            listOf(CatalogCandidate(null, "wireguard_udp", 100, null, null))
        }
    }

    private fun routeCooldownKey(candidate: CatalogCandidate): String? {
        val serverId = candidate.serverId?.trim().orEmpty()
        if (serverId.isEmpty()) return null
        return "$serverId|${candidate.protocol.trim().lowercase()}"
    }

    private fun readRouteCooldown(serverId: String, protocol: String): JSONObject? = try {
        val document = JSONObject(readSecureString(ROUTE_COOLDOWN_KEY).orEmpty().ifBlank { "{}" })
        document.optJSONObject("$serverId|${protocol.trim().lowercase()}")
    } catch (_: Exception) {
        null
    }

    private fun recordRouteFailure(candidate: CatalogCandidate) {
        if (!TRANSPORT_PREVIEW_ENABLED) return
        val key = routeCooldownKey(candidate) ?: return
        val document = try {
            JSONObject(readSecureString(ROUTE_COOLDOWN_KEY).orEmpty().ifBlank { "{}" })
        } catch (_: Exception) {
            JSONObject()
        }
        val previousFailures = document.optJSONObject(key)?.optInt("failures", 0) ?: 0
        val failures = previousFailures + 1
        val untilMs = System.currentTimeMillis() +
            GreenVpnQuickTileCascadePolicy.cooldownDurationMs(failures)
        document.put(key, JSONObject().put("failures", failures).put("untilMs", untilMs))
        try {
            writeSecureString(ROUTE_COOLDOWN_KEY, document.toString())
        } catch (_: Exception) {}
    }

    private fun clearRouteFailure(candidate: CatalogCandidate) {
        if (!TRANSPORT_PREVIEW_ENABLED) return
        val key = routeCooldownKey(candidate) ?: return
        val document = try {
            JSONObject(readSecureString(ROUTE_COOLDOWN_KEY).orEmpty().ifBlank { "{}" })
        } catch (_: Exception) {
            return
        }
        document.remove(key)
        try {
            writeSecureString(ROUTE_COOLDOWN_KEY, document.toString())
        } catch (_: Exception) {}
    }

    private fun probeConnectedRoute(protocol: String): Boolean {
        var attempt = 1
        while (true) {
            Thread.sleep(GreenVpnQuickTileCascadePolicy.routeProbeDelayMs(attempt))
            val result = GreenVpnRouteProbe.probe(applicationContext, protocol)
            debugLog(
                "route_probe protocol=$protocol attempt=$attempt ok=${result.ok} " +
                    "status=${result.statusCode ?: -1} latencyMs=${result.latencyMs} error=${result.error}"
            )
            if (result.ok) return true
            if (!GreenVpnQuickTileCascadePolicy.shouldRetryRouteProbe(attempt, result.latencyMs)) {
                return false
            }
            attempt += 1
        }
    }

    private fun transportFailureSummary(protocol: String): String {
        val snapshot = when (protocol) {
            "hysteria2" -> GreenVpnHysteria2Preview.snapshot(applicationContext)
            "vless_reality" -> GreenVpnVlessRealityPreview.snapshot(applicationContext)
            "naive_https" -> GreenVpnNaiveHttpsPreview.snapshot(applicationContext)
            "dnstt" -> GreenVpnDnsttPreview.snapshot(applicationContext)
            "amneziawg" -> GreenVpnAwg2Preview.snapshot(applicationContext)
            "wireguard_udp" -> return try {
                val currentBackend = backend()
                val state = currentBackend.getState(tunnel).name.lowercase()
                "state=$state error="
            } catch (failure: Throwable) {
                "state=error error=${safeError(failure)}"
            }
            else -> return "state=unknown"
        }
        val state = when (snapshot) {
            is GreenVpnHysteria2Preview.Snapshot -> snapshot.state to snapshot.error
            is GreenVpnVlessRealityPreview.Snapshot -> snapshot.state to snapshot.error
            is GreenVpnNaiveHttpsPreview.Snapshot -> snapshot.state to snapshot.error
            is GreenVpnDnsttPreview.Snapshot -> snapshot.state to snapshot.error
            is GreenVpnAwg2Preview.Snapshot -> snapshot.state to snapshot.error
            else -> "unknown" to ""
        }
        return "state=${state.first} error=${safeError(IllegalStateException(state.second))}"
    }

    private fun debugLog(message: String) {
        if (BuildConfig.DEBUG) Log.i(DEBUG_TAG, message)
    }

    private fun canConnectFromTile(subscription: JSONObject?): Boolean {
        if (subscription == null) return false
        if (subscription.optBoolean("isActive", false)) return true

        val planCode = subscription.optString("planCode").trim().lowercase()
        val planName = subscription.optString("planName").trim().lowercase()
        val appVersion = APP_VERSION.lowercase()
        return planCode in FREE_PLAN_CODES ||
            planName in FREE_PLAN_CODES ||
            appVersion.contains("trial-only")
    }

    private fun tileBlockedMessage(): String =
        "Откройте Green VPN и активируйте Trial или подписку, чтобы включать VPN из плитки."

    private fun postJson(
        path: String,
        accessToken: String,
        preferredBaseUrl: String? = null,
        payload: JSONObject
    ): JSONObject {
        val bases = orderedApiBaseUrls(preferredBaseUrl)
        var lastError: Exception? = null
        for (baseUrl in bases) {
            try {
                return postJsonToBase(baseUrl, path, accessToken, payload)
            } catch (e: Exception) {
                lastError = e
                if (!isRetryableApiError(e)) throw e
            }
        }
        throw lastError ?: IllegalStateException("API недоступен")
    }

    private fun getJson(path: String, preferredBaseUrl: String?): JSONObject {
        var lastError: Exception? = null
        for (baseUrl in orderedApiBaseUrls(preferredBaseUrl)) {
            try {
                return getJsonFromBase(baseUrl, path)
            } catch (e: Exception) {
                lastError = e
                if (!isRetryableApiError(e)) throw e
            }
        }
        throw lastError ?: IllegalStateException("API недоступен")
    }

    private fun isRetryableApiError(error: Exception): Boolean {
        val status = Regex("HTTP (\\d{3})").find(error.message.orEmpty())
            ?.groupValues?.getOrNull(1)?.toIntOrNull()
        return status == null || status == 408 || status >= 500
    }

    private fun orderedApiBaseUrls(preferredBaseUrl: String? = null): List<String> {
        val bases = linkedSetOf<String>()
        bases.add(API_BASE_URL)
        bases.addAll(API_FALLBACK_BASE_URLS)

        val preferred = normalizeApiBaseUrl(preferredBaseUrl)
        if (preferred != null && bases.contains(preferred)) {
            val ordered = linkedSetOf<String>()
            ordered.add(preferred)
            ordered.addAll(bases)
            return ordered.toList()
        }

        val healthy = bases.firstOrNull { isApiBaseHealthy(it) }
        if (healthy == null) return bases.toList()

        val ordered = linkedSetOf<String>()
        ordered.add(healthy)
        ordered.addAll(bases)
        return ordered.toList()
    }

    private fun normalizeApiBaseUrl(value: String?): String? {
        var normalized = value?.trim().orEmpty()
        while (normalized.endsWith("/")) {
            normalized = normalized.dropLast(1)
        }
        if (normalized.isEmpty()) return null
        return try {
            val url = URL(normalized)
            if (url.protocol.isNullOrBlank() || url.host.isNullOrBlank()) null else normalized
        } catch (_: Exception) {
            null
        }
    }

    private fun isApiBaseHealthy(baseUrl: String): Boolean {
        val connection = (URL("$baseUrl/healthz").openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 1200
            readTimeout = 1600
            setRequestProperty("Accept", "application/json")
        }
        return try {
            connection.responseCode in 200..299
        } catch (_: Exception) {
            false
        } finally {
            connection.disconnect()
        }
    }

    private fun postJsonToBase(
        baseUrl: String,
        path: String,
        accessToken: String,
        payload: JSONObject
    ): JSONObject {
        val connection = (URL("$baseUrl$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 5000
            readTimeout = 10000
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Authorization", "Bearer $accessToken")
            setRequestProperty("X-GreenVPN-Release-Channel", RELEASE_CHANNEL)
            setRequestProperty("X-GreenVPN-Version", APP_VERSION)
            setRequestProperty("X-GreenVPN-Supported-Protocols", SUPPORTED_PROTOCOLS.joinToString(","))
        }
        val bytes = payload.toString().toByteArray(StandardCharsets.UTF_8)
        connection.outputStream.use { it.write(bytes) }

        val code = connection.responseCode
        val stream = if (code in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader(StandardCharsets.UTF_8)?.use { it.readText() }.orEmpty()
        connection.disconnect()
        if (code !in 200..299) {
            throw IllegalStateException("сервер вернул HTTP $code: $body")
        }
        return JSONObject(body)
    }

    private fun getJsonFromBase(baseUrl: String, path: String): JSONObject {
        val connection = (URL("$baseUrl$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 5000
            readTimeout = 10000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("X-GreenVPN-Release-Channel", RELEASE_CHANNEL)
            setRequestProperty("X-GreenVPN-Version", APP_VERSION)
            setRequestProperty("X-GreenVPN-Supported-Protocols", SUPPORTED_PROTOCOLS.joinToString(","))
        }
        return try {
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader(StandardCharsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (code !in 200..299) {
                throw IllegalStateException("сервер вернул HTTP $code: $body")
            }
            JSONObject(body)
        } finally {
            connection.disconnect()
        }
    }

    private fun readSession(): JSONObject {
        val raw = readSecureString(SESSION_KEY)?.trim().orEmpty()
        if (raw.isEmpty()) return JSONObject()
        return JSONObject(raw)
    }

    private fun readSecureString(key: String): String? {
        val stored = securePrefs().getString(key, null) ?: return null
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
        if (!securePrefs().edit().putString(key, "$iv:$body").commit()) {
            throw IllegalStateException("не удалось сохранить VPN-конфиг")
        }
    }

    private fun securePrefs() =
        applicationContext.getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE)

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

    private fun setTile(state: Int, subtitle: String) {
        mainHandler.post {
            val tile = qsTile ?: return@post
            tile.label = APP_LABEL
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = subtitle
            }
            tile.state = state
            tile.updateTile()
        }
    }

    private fun showToast(message: String) {
        mainHandler.post {
            Toast.makeText(applicationContext, message, Toast.LENGTH_LONG).show()
        }
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun openApp(message: String) {
        showToast(message)
        val intent = Intent(this, MainActivity::class.java).apply {
            action = "${BuildConfig.APPLICATION_ID}.OPEN_TARIFF"
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("greenVpnTileMessage", message)
        }
        if (Build.VERSION.SDK_INT >= 34) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun safeError(error: Throwable): String {
        val message = error.message ?: error.javaClass.simpleName
        return message.replace(Regex("[\\r\\n]+"), " ").take(160)
    }

    private class GreenVpnTileTunnel(private val tunnelName: String) : Tunnel {
        @Volatile
        private var state: Tunnel.State = Tunnel.State.DOWN

        override fun getName(): String = tunnelName

        override fun onStateChange(newState: Tunnel.State) {
            state = newState
        }
    }

}
