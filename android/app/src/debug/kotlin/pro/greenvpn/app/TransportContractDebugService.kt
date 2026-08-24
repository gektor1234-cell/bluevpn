package pro.greenvpn.app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.security.keystore.KeyProperties
import android.util.Base64
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
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
            "current_wg0" to "wireguard_udp",
            "ruvds-2584554-ld8" to "wireguard_udp",
            "tw-7879598-nl1" to "wireguard_udp",
            "gb1-awg2-canary" to "amneziawg",
            "nl1-awg2-canary" to "amneziawg",
            "nl2-awg2-canary" to "amneziawg",
            "gb1-hysteria2-canary" to "hysteria2",
            "nl1-hysteria2-canary" to "hysteria2",
            "nl2-hysteria2-canary" to "hysteria2",
            "gb1-vless-reality-xhttp-canary" to "vless_reality",
            "nl1-vless-reality-xhttp-canary" to "vless_reality",
            "nl2-vless-reality-xhttp-canary" to "vless_reality",
            "gb1-naive-https-canary" to "naive_https",
            "nl1-naive-https-canary" to "naive_https",
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
                    "probe_route" -> {
                        val protocol = intent?.getStringExtra("protocol").orEmpty()
                        val probe = GreenVpnRouteProbe.probe(this, protocol)
                        result
                            .put("ok", probe.ok)
                            .put("target", probe.target)
                            .put("statusCode", probe.statusCode)
                            .put("latencyMs", probe.latencyMs)
                            .put("probeError", probe.error)
                            .put("success", true)
                    }
                    "connect_candidate" -> connectCandidate(result, requireNotNull(intent))
                    "set_tile_cooldown" -> setTileCooldown(result, requireNotNull(intent))
                    "clear_tile_cooldown" -> {
                        getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE)
                            .edit().remove(ROUTE_COOLDOWN_KEY).commit()
                        result.put("success", true)
                    }
                    "fail_active_engine" -> {
                        val protocol = intent?.getStringExtra("protocol").orEmpty()
                            .trim().lowercase()
                        val disconnected = when (protocol) {
                            "amneziawg" -> GreenVpnAwg2Preview.disconnect(this)
                            "wireguard_udp" -> disconnectStandardTunnel()
                            "hysteria2" -> GreenVpnHysteria2Preview.disconnect(this)
                            "vless_reality" -> GreenVpnVlessRealityPreview.disconnect(this)
                            "naive_https" -> GreenVpnNaiveHttpsPreview.disconnect(this)
                            "dnstt" -> GreenVpnDnsttPreview.disconnect(this)
                            else -> error("unsupported_protocol")
                        }
                        check(disconnected) { "engine_disconnect_failed" }
                        writeTransportSnapshot(result)
                        result.put("injectedProtocol", protocol)
                    }
                    "disconnect_all" -> {
                        GreenVpnRuntimeFailoverService.disarm(this)
                        GreenVpnConnectionOperationGate.awaitIdle()
                        disconnectStandardTunnel()
                        GreenVpnDnsttPreview.disconnect(this)
                        GreenVpnNaiveHttpsPreview.disconnect(this)
                        GreenVpnVlessRealityPreview.disconnect(this)
                        GreenVpnHysteria2Preview.disconnect(this)
                        GreenVpnAwg2Preview.disconnect(this)
                        if (GreenVpnNetworkTransition.waitForInactive(this, 2_500L)) {
                            GreenVpnNetworkTransition.markInactive(this)
                        }
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
        result
            .put("engines", engines)
            .put("activeProtocols", active)
            .put(
                "runtimeFailover",
                JSONObject(GreenVpnRuntimeFailoverService.snapshot(this)),
            )
            .put("success", true)
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

    private fun disconnectStandardTunnel(): Boolean {
        val backend = GreenVpnWireGuardRuntime.backend(this)
        return backend.setState(
            GreenVpnWireGuardRuntime.tunnel,
            Tunnel.State.DOWN,
            null,
        ) == Tunnel.State.DOWN
    }

    private fun connectCandidate(result: JSONObject, intent: Intent) {
        val serverId = intent.getStringExtra("serverId").orEmpty().trim()
        val expectedProtocol = CANDIDATES[serverId] ?: error("unsupported_candidate")
        val includedApplications = intent.getStringExtra("includedApplications")
            .orEmpty()
            .split(',')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .sorted()
        val session = JSONObject(readSecureString(this, SESSION_KEY))
        val accessToken = session.optString("accessToken").trim()
        val deviceId = readSecureString(this, DEVICE_ID_KEY).trim()
        require(accessToken.isNotEmpty()) { "session_missing" }
        require(deviceId.length >= 8) { "device_missing" }

        val bases = listOf(BuildConfig.GREENVPN_API_BASE_URL) +
            BuildConfig.GREENVPN_API_FALLBACK_BASE_URLS.split(',')
        var response: JSONObject? = null
        var lastError: Throwable? = null
        for (rawBaseUrl in bases) {
            val baseUrl = rawBaseUrl.trim().trimEnd('/')
            if (baseUrl.isEmpty()) continue
            try {
                response = fetchConfig(baseUrl, accessToken, deviceId, serverId)
                break
            } catch (error: Throwable) {
                lastError = error
            }
        }
        val config = response ?: throw lastError ?: error("config_unavailable")
        val protocol = config.optString("protocol").trim().lowercase()
        val returnedServerId = config.optString("serverId").trim()
        val rawConfigText = config.optString("configText")
        require(protocol == expectedProtocol) { "protocol_mismatch" }
        require(returnedServerId == serverId) { "server_mismatch" }
        require(rawConfigText.length in 16..1_048_576) { "config_missing" }
        val configText = if (includedApplications.isEmpty()) {
            rawConfigText
        } else {
            require(protocol in setOf("wireguard_udp", "amneziawg")) {
                "selected_app_protocol_unsupported"
            }
            applyIncludedApplications(rawConfigText, includedApplications)
        }

        GreenVpnRuntimeFailoverService.disarm(this)
        GreenVpnConnectionOperationGate.awaitIdle()
        disconnectStandardTunnel()
        GreenVpnDnsttPreview.disconnect(this)
        GreenVpnNaiveHttpsPreview.disconnect(this)
        GreenVpnVlessRealityPreview.disconnect(this)
        GreenVpnHysteria2Preview.disconnect(this)
        GreenVpnAwg2Preview.disconnect(this)
        check(GreenVpnNetworkTransition.waitForInactive(this, 2_500L)) {
            "previous_route_still_active"
        }
        GreenVpnNetworkTransition.markInactive(this)
        val connected = when (protocol) {
            "amneziawg" -> GreenVpnAwg2Preview.connect(
                this,
                GreenVpnAwg2Preview.parseConfig(configText),
            )
            "hysteria2" -> GreenVpnHysteria2Preview.connect(
                this,
                GreenVpnHysteria2Preview.validateConfig(configText),
            )
            "vless_reality" -> GreenVpnVlessRealityPreview.connect(
                this,
                GreenVpnVlessRealityPreview.validateConfig(configText),
            )
            "naive_https" -> GreenVpnNaiveHttpsPreview.connect(
                this,
                GreenVpnNaiveHttpsPreview.validateConfig(configText),
            )
            "dnstt" -> GreenVpnDnsttPreview.connect(
                this,
                GreenVpnDnsttPreview.validateConfig(configText),
            )
            "wireguard_udp" -> {
                val parsed = Config.parse(
                    ByteArrayInputStream(configText.toByteArray(StandardCharsets.UTF_8)),
                )
                GreenVpnWireGuardRuntime.backend(this).setState(
                    GreenVpnWireGuardRuntime.tunnel,
                    Tunnel.State.UP,
                    parsed,
                ) == Tunnel.State.UP
            }
            else -> error("unsupported_debug_connect_protocol")
        }
        check(connected) { "engine_connect_failed" }
        GreenVpnNetworkTransition.markActive(this)
        writeSecureString(
            this,
            LAST_ROUTE_SUCCESS_KEY,
            JSONObject()
                .put("serverId", returnedServerId)
                .put("protocol", protocol)
                .put("verifiedAtMs", System.currentTimeMillis())
                .toString(),
        )
        if (includedApplications.isEmpty()) {
            check(GreenVpnRuntimeFailoverService.arm(this, returnedServerId, protocol)) {
                "runtime_failover_arm_failed"
            }
        }
        writeTransportSnapshot(result)
        result
            .put("serverId", serverId)
            .put("protocol", protocol)
            .put("includedApplications", JSONArray(includedApplications))
    }

    private fun applyIncludedApplications(
        configText: String,
        includedApplications: List<String>,
    ): String {
        val selectorPattern = Regex(
            "^\\s*(IncludedApplications|ExcludedApplications)\\s*=.*$",
            RegexOption.IGNORE_CASE,
        )
        val lines = configText
            .split(Regex("\\r?\\n"))
            .filterNot { selectorPattern.matches(it) }
            .toMutableList()
        val interfaceIndex = lines.indexOfFirst {
            it.trim().equals("[Interface]", ignoreCase = true)
        }
        require(interfaceIndex >= 0) { "wireguard_interface_missing" }
        lines.add(
            interfaceIndex + 1,
            "IncludedApplications = ${includedApplications.joinToString(", ")}",
        )
        return GreenVpnApplicationSelectorPolicy.filterInstalledApplications(
            lines.joinToString("\n"),
        ) { packageName -> isPackageInstalled(packageName) }
    }

    private fun isPackageInstalled(packageName: String): Boolean = try {
        @Suppress("DEPRECATION")
        packageManager.getPackageInfo(packageName, 0)
        true
    } catch (_: Exception) {
        false
    }

    private fun fetchConfig(
        baseUrl: String,
        accessToken: String,
        deviceId: String,
        serverId: String,
    ): JSONObject {
        val payload = JSONObject()
            .put("deviceUid", deviceId)
            .put("mode", "full")
            .put("serverId", serverId)
            .put(
                "releaseChannel",
                BuildConfig.GREENVPN_RELEASE_CHANNEL.trim().ifEmpty { "stable" },
            )
            .put("supportedProtocols", JSONArray(SUPPORTED_PROTOCOLS))
        BuildConfig.GREENVPN_CLIENT_MARKER.trim().takeIf { it.isNotEmpty() }?.let {
            payload.put("clientMarker", it)
        }
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
            check(code in 200..299) { "config_http_$code" }
            JSONObject(body)
        } finally {
            connection.disconnect()
        }
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
            .put(
                "releaseChannel",
                BuildConfig.GREENVPN_RELEASE_CHANNEL.trim().ifEmpty { "stable" },
            )
            .put("supportedProtocols", JSONArray(SUPPORTED_PROTOCOLS))
        BuildConfig.GREENVPN_CLIENT_MARKER.trim().takeIf { it.isNotEmpty() }?.let {
            payload.put("clientMarker", it)
        }
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
