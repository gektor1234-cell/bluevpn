package pro.greenvpn.app

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
import android.widget.Toast
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.concurrent.ExecutorService
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
        const val SECURE_PREFS_NAME = "greenvpn_secure_config_store_v1"
        const val SECURE_KEY_ALIAS = "greenvpn_config_aes_v1"
        const val GCM_TAG_BITS = 128
        const val SESSION_KEY = "greenvpn_mobile_session_v1"
        const val DEVICE_ID_KEY = "greenvpn_mobile_device_id_v1"
        const val MANAGED_CONFIG_KEY = "greenvpn_mobile_managed_config_v1"
        const val MANAGED_PROTOCOL_KEY = "greenvpn_mobile_managed_protocol_v1"
        val FREE_PLAN_CODES = setOf("trial", "free", "free_start", "support_trial", "base")
        val SUPPORTED_PROTOCOLS = buildList {
            add("wireguard_udp")
            if (BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) add("amneziawg")
            if (BuildConfig.GREENVPN_HYSTERIA2_PREVIEW_ENABLED) add("hysteria2")
            if (BuildConfig.GREENVPN_VLESS_REALITY_PREVIEW_ENABLED) add("vless_reality")
            if (BuildConfig.GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED) add("naive_https")
            if (BuildConfig.GREENVPN_DNSTT_PREVIEW_ENABLED) add("dnstt")
        }
    }

    private data class FetchedConfig(val config: String, val protocol: String)

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var backend: GoBackend? = null
    private val tunnel = GreenVpnTileTunnel("GreenVPN")

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
        executor.execute {
            try {
                if (isVpnConnected()) {
                    disconnectVpn()
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
                        .put("supportedProtocols", JSONArray(SUPPORTED_PROTOCOLS))
                )
                val subscription = bootstrap.optJSONObject("subscription")
                if (!canConnectFromTile(subscription)) {
                    openApp(tileBlockedMessage())
                    setTile(Tile.STATE_INACTIVE, "Нужен Trial")
                    return@execute
                }

                val fetched = fetchFreshConfig(accessToken, deviceId, sessionApiBaseUrl)
                val config = fetched?.config
                    ?: readSecureString(MANAGED_CONFIG_KEY)?.trim()
                val protocol = fetched?.protocol
                    ?: readSecureString(MANAGED_PROTOCOL_KEY)?.trim()?.lowercase()
                    ?: "wireguard_udp"
                if (config.isNullOrBlank()) {
                    openApp("Откройте Green VPN, чтобы получить VPN-конфиг.")
                    setTile(Tile.STATE_INACTIVE, "Нужен конфиг")
                    return@execute
                }

                val permissionIntent = VpnService.prepare(this)
                if (permissionIntent != null) {
                    openApp("Подтвердите системное разрешение VPN в приложении.")
                    setTile(Tile.STATE_INACTIVE, "Нужно разрешение")
                    return@execute
                }

                val connected = connectVpn(config, protocol)
                if (connected) {
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

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    private fun refreshTileState() {
        executor.execute {
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

    private fun backend(): GoBackend {
        val current = backend
        if (current != null) return current
        val created = GoBackend(applicationContext)
        backend = created
        return created
    }

    private fun isVpnConnected(): Boolean {
        if (GreenVpnDnsttPreview.snapshot(applicationContext).connected) return true
        if (GreenVpnNaiveHttpsPreview.snapshot(applicationContext).connected) return true
        if (GreenVpnVlessRealityPreview.snapshot(applicationContext).connected) return true
        if (GreenVpnHysteria2Preview.snapshot(applicationContext).connected) return true
        if (BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) {
            return GreenVpnAwg2Preview.snapshot(applicationContext).connected
        }
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
        if (protocol == "amneziawg" ||
            (protocol == "wireguard_udp" && BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED)
        ) {
            if (!BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) {
                val currentBackend = backend()
                if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                    currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                }
            }
            val parsed = GreenVpnAwg2Preview.parseConfig(configText)
            return GreenVpnAwg2Preview.connect(applicationContext, parsed)
        }
        GreenVpnAwg2Preview.disconnect(applicationContext)
        val currentBackend = backend()
        if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
            currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
            Thread.sleep(250)
        }
        val parsed = Config.parse(ByteArrayInputStream(configText.toByteArray(StandardCharsets.UTF_8)))
        return currentBackend.setState(tunnel, Tunnel.State.UP, parsed) == Tunnel.State.UP
    }

    private fun disconnectVpn(): Boolean {
        val dnstt = GreenVpnDnsttPreview.snapshot(applicationContext)
        if (dnstt.connected || dnstt.state == "starting" || dnstt.state == "error") {
            return GreenVpnDnsttPreview.disconnect(applicationContext)
        }
        val naive = GreenVpnNaiveHttpsPreview.snapshot(applicationContext)
        if (naive.connected || naive.state == "starting" || naive.state == "error") {
            return GreenVpnNaiveHttpsPreview.disconnect(applicationContext)
        }
        val vless = GreenVpnVlessRealityPreview.snapshot(applicationContext)
        if (vless.connected || vless.state == "starting" || vless.state == "error") {
            return GreenVpnVlessRealityPreview.disconnect(applicationContext)
        }
        val hysteria = GreenVpnHysteria2Preview.snapshot(applicationContext)
        if (hysteria.connected || hysteria.state == "starting" || hysteria.state == "error") {
            return GreenVpnHysteria2Preview.disconnect(applicationContext)
        }
        if (BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) {
            return GreenVpnAwg2Preview.disconnect(applicationContext)
        }
        val currentBackend = backend()
        val state = currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
        val awgDisconnected = GreenVpnAwg2Preview.disconnect(applicationContext)
        return state == Tunnel.State.DOWN && awgDisconnected &&
            !currentBackend.getRunningTunnelNames().contains(tunnel.getName())
    }

    private fun fetchFreshConfig(
        accessToken: String,
        deviceId: String,
        preferredBaseUrl: String?
    ): FetchedConfig? {
        val json = postJson(
            path = "/api/v1/client/config",
            accessToken = accessToken,
            preferredBaseUrl = preferredBaseUrl,
            payload = JSONObject()
                .put("deviceUid", deviceId)
                .put("mode", "full")
                .put("supportedProtocols", JSONArray(SUPPORTED_PROTOCOLS))
        )
        val config = json.optString("configText").trim()
        val protocol = json.optString("protocol", "wireguard_udp").trim().lowercase()
        if (config.isNotEmpty()) {
            writeSecureString(MANAGED_CONFIG_KEY, config)
            writeSecureString(MANAGED_PROTOCOL_KEY, protocol)
        }
        return if (config.isEmpty()) null else FetchedConfig(config, protocol)
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
                val message = e.message.orEmpty()
                if (!message.contains("HTTP 408") && !message.contains("HTTP 5")) {
                    throw e
                }
            }
        }
        throw lastError ?: IllegalStateException("API недоступен")
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
