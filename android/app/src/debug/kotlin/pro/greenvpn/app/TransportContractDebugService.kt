package pro.greenvpn.app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec

class TransportContractDebugService : Service() {
    private companion object {
        const val RESULT_FILE = "greenvpn-transport-contract-debug-result.json"
        const val SECURE_PREFS_NAME = "greenvpn_secure_config_store_v1"
        const val SECURE_KEY_ALIAS = "greenvpn_config_aes_v1"
        const val SESSION_KEY = "greenvpn_mobile_session_v1"
        const val DEVICE_ID_KEY = "greenvpn_mobile_device_id_v1"
        const val ROUTE_COOLDOWN_KEY = "greenvpn_quick_tile_route_cooldown_v1"
        const val LAST_ROUTE_SUCCESS_KEY = "greenvpn_quick_tile_last_route_success_v1"
        const val GCM_TAG_BITS = 128

        val CANDIDATES = linkedMapOf(
            "nl2-awg2-canary" to "amneziawg",
            "nl2-hysteria2-canary" to "hysteria2",
            "nl2-vless-reality-xhttp-canary" to "vless_reality",
            "nl2-naive-https-canary" to "naive_https",
            "nl2-dnstt-canary" to "dnstt",
        )
        val SUPPORTED_PROTOCOLS = listOf(
            "wireguard_udp",
            "amneziawg",
            "hysteria2",
            "vless_reality",
            "naive_https",
            "dnstt",
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Thread {
            val result = JSONObject()
                .put("versionCode", BuildConfig.VERSION_CODE)
                .put("checks", JSONArray())
                .put("success", false)
            try {
                when (val command = intent?.getStringExtra("command").orEmpty()) {
                    "probe" -> runContractProbe(result)
                    "snapshot" -> writeTransportSnapshot(result)
                    "set_tile_cooldown" -> setTileCooldown(result, requireNotNull(intent))
                    "clear_tile_cooldown" -> {
                        getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE)
                            .edit().remove(ROUTE_COOLDOWN_KEY).commit()
                        result.put("success", true)
                    }
                    "disconnect_all" -> {
                        GreenVpnDnsttPreview.disconnect(this)
                        GreenVpnNaiveHttpsPreview.disconnect(this)
                        GreenVpnVlessRealityPreview.disconnect(this)
                        GreenVpnHysteria2Preview.disconnect(this)
                        GreenVpnAwg2Preview.disconnect(this)
                        getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE)
                            .edit().remove(LAST_ROUTE_SUCCESS_KEY).commit()
                        writeTransportSnapshot(result)
                    }
                    else -> error("unsupported_command:$command")
                }
            } catch (error: Throwable) {
                result.put("error", safeError(error))
            } finally {
                openFileOutput(RESULT_FILE, Context.MODE_PRIVATE).use {
                    it.write(result.toString().toByteArray(StandardCharsets.UTF_8))
                }
                stopSelf(startId)
            }
        }.start()
        return START_NOT_STICKY
    }

    private fun runContractProbe(result: JSONObject) {
        val session = JSONObject(readSecureString(this, SESSION_KEY))
        val accessToken = session.optString("accessToken").trim()
        val deviceId = readSecureString(this, DEVICE_ID_KEY).trim()
        require(accessToken.isNotEmpty()) { "session_missing" }
        require(deviceId.length >= 8) { "device_missing" }

        val bases = linkedMapOf(
            "primary" to BuildConfig.GREENVPN_API_BASE_URL.trim().trimEnd('/'),
            "fallback" to BuildConfig.GREENVPN_API_FALLBACK_BASE_URLS
                .split(',')
                .first { it.trim().isNotEmpty() }
                .trim()
                .trimEnd('/'),
        )
        for ((role, baseUrl) in bases) {
            for ((serverId, expectedProtocol) in CANDIDATES) {
                val check = probeConfig(
                    baseUrl = baseUrl,
                    accessToken = accessToken,
                    deviceId = deviceId,
                    serverId = serverId,
                    expectedProtocol = expectedProtocol,
                ).put("apiRole", role)
                result.getJSONArray("checks").put(check)
            }
        }
        val checks = result.getJSONArray("checks")
        result.put(
            "success",
            checks.length() == bases.size * CANDIDATES.size &&
                (0 until checks.length()).all { checks.getJSONObject(it).getBoolean("valid") },
        )
    }

    private fun writeTransportSnapshot(result: JSONObject) {
        val snapshots = linkedMapOf(
            "amneziawg" to GreenVpnAwg2Preview.snapshot(this),
            "hysteria2" to GreenVpnHysteria2Preview.snapshot(this),
            "vless_reality" to GreenVpnVlessRealityPreview.snapshot(this),
            "naive_https" to GreenVpnNaiveHttpsPreview.snapshot(this),
            "dnstt" to GreenVpnDnsttPreview.snapshot(this),
        )
        val engines = JSONObject()
        val active = JSONArray()
        for ((protocol, snapshot) in snapshots) {
            val connected = when (snapshot) {
                is GreenVpnAwg2Preview.Snapshot -> snapshot.connected
                is GreenVpnHysteria2Preview.Snapshot -> snapshot.connected
                is GreenVpnVlessRealityPreview.Snapshot -> snapshot.connected
                is GreenVpnNaiveHttpsPreview.Snapshot -> snapshot.connected
                is GreenVpnDnsttPreview.Snapshot -> snapshot.connected
                else -> false
            }
            val state = when (snapshot) {
                is GreenVpnAwg2Preview.Snapshot -> snapshot.state
                is GreenVpnHysteria2Preview.Snapshot -> snapshot.state
                is GreenVpnVlessRealityPreview.Snapshot -> snapshot.state
                is GreenVpnNaiveHttpsPreview.Snapshot -> snapshot.state
                is GreenVpnDnsttPreview.Snapshot -> snapshot.state
                else -> "unknown"
            }
            engines.put(protocol, JSONObject().put("connected", connected).put("state", state))
            if (connected) active.put(protocol)
        }
        result.put("engines", engines).put("activeProtocols", active).put("success", true)
        val lastRoute = try {
            JSONObject(readSecureString(this, LAST_ROUTE_SUCCESS_KEY))
        } catch (_: Exception) {
            JSONObject()
        }
        result.put("lastRouteSuccess", lastRoute)
    }

    private fun setTileCooldown(result: JSONObject, intent: Intent) {
        val serverId = intent.getStringExtra("serverId").orEmpty().trim()
        val protocol = intent.getStringExtra("protocol").orEmpty().trim().lowercase()
        require(CANDIDATES[serverId] == protocol) { "unsupported_candidate" }
        val failureCount = intent.getIntExtra("failureCount", 1).coerceIn(1, 4)
        val document = try {
            JSONObject(readSecureString(this, ROUTE_COOLDOWN_KEY).ifBlank { "{}" })
        } catch (_: Exception) {
            JSONObject()
        }
        val untilMs = System.currentTimeMillis() +
            GreenVpnQuickTileCascadePolicy.cooldownDurationMs(failureCount)
        document.put(
            "$serverId|$protocol",
            JSONObject().put("failures", failureCount).put("untilMs", untilMs),
        )
        writeSecureString(this, ROUTE_COOLDOWN_KEY, document.toString())
        result.put("success", true).put("serverId", serverId).put("protocol", protocol)
    }

    private fun probeConfig(
        baseUrl: String,
        accessToken: String,
        deviceId: String,
        serverId: String,
        expectedProtocol: String,
    ): JSONObject {
        val payload = JSONObject()
            .put("deviceUid", deviceId)
            .put("mode", "full")
            .put("serverId", serverId)
            .put("releaseChannel", "paid-beta")
            .put("clientMarker", "green-vpn-paid-beta-v1")
            .put("supportedProtocols", JSONArray(SUPPORTED_PROTOCOLS))
        val connection = (URL("$baseUrl/api/v1/client/config").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 5000
            readTimeout = 15000
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Authorization", "Bearer $accessToken")
        }
        return try {
            connection.outputStream.use {
                it.write(payload.toString().toByteArray(StandardCharsets.UTF_8))
            }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader(StandardCharsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (code !in 200..299) {
                return JSONObject()
                    .put("serverId", serverId)
                    .put("expectedProtocol", expectedProtocol)
                    .put("httpStatus", code)
                    .put("valid", false)
            }
            val response = JSONObject(body)
            val protocol = response.optString("protocol").trim().lowercase()
            val returnedServerId = response.optString("serverId").trim()
            val configLength = response.optString("configText").length
            JSONObject()
                .put("serverId", serverId)
                .put("expectedProtocol", expectedProtocol)
                .put("protocol", protocol)
                .put("httpStatus", code)
                .put("configLength", configLength)
                .put(
                    "valid",
                    protocol == expectedProtocol &&
                        returnedServerId == serverId &&
                        configLength in 16..1_048_576,
                )
        } catch (error: Throwable) {
            JSONObject()
                .put("serverId", serverId)
                .put("expectedProtocol", expectedProtocol)
                .put("httpStatus", 0)
                .put("valid", false)
                .put("error", safeError(error))
        } finally {
            connection.disconnect()
        }
    }

    private fun readSecureString(context: Context, key: String): String {
        val stored = context.getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE)
            .getString(key, null)
            ?: return ""
        val parts = stored.split(":", limit = 2)
        if (parts.size != 2) return ""
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val secretKey = (keyStore.getEntry(SECURE_KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)
            ?.secretKey
            ?: return ""
        require(secretKey.algorithm == KeyProperties.KEY_ALGORITHM_AES)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey,
            GCMParameterSpec(GCM_TAG_BITS, Base64.decode(parts[0], Base64.NO_WRAP)),
        )
        return String(
            cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)),
            StandardCharsets.UTF_8,
        )
    }

    private fun writeSecureString(context: Context, key: String, value: String) {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val secretKey = (keyStore.getEntry(SECURE_KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)
            ?.secretKey
            ?: error("secure_key_missing")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val encrypted = Base64.encodeToString(
            cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8)),
            Base64.NO_WRAP,
        )
        require(
            context.getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putString(key, "$iv:$encrypted").commit(),
        ) { "secure_write_failed" }
    }

    private fun safeError(error: Throwable): String {
        val name = error::class.java.simpleName.ifBlank { "Error" }
        val message = error.message.orEmpty()
            .replace(Regex("Bearer\\s+[^\\s]+", RegexOption.IGNORE_CASE), "Bearer [redacted]")
            .take(160)
        return if (message.isBlank()) name else "$name: $message"
    }
}
