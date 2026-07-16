package pro.greenvpn.app

import android.content.Context
import android.net.VpnService
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
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
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal data class GreenVpnNativeCascadeResult(
    val ok: Boolean,
    val serverId: String = "",
    val protocol: String = "",
    val error: String = "",
)

internal data class GreenVpnRuntimeRoute(
    val serverId: String,
    val protocol: String,
)

internal class GreenVpnNativeCascadeCoordinator(context: Context) {
    private companion object {
        val API_BASE_URL = BuildConfig.GREENVPN_API_BASE_URL.trim().trimEnd('/')
        val API_FALLBACK_BASE_URLS = BuildConfig.GREENVPN_API_FALLBACK_BASE_URLS
            .split(',')
            .map { it.trim().trimEnd('/') }
            .filter { it.isNotEmpty() }
        val APP_VERSION = BuildConfig.GREENVPN_APP_VERSION
        val RELEASE_CHANNEL = BuildConfig.GREENVPN_RELEASE_CHANNEL.trim().ifEmpty { "stable" }
        val CLIENT_MARKER = BuildConfig.GREENVPN_CLIENT_MARKER.trim()
        val SUPPORTED_PROTOCOLS = buildList {
            add("wireguard_udp")
            if (BuildConfig.GREENVPN_AWG2_PREVIEW_ENABLED) add("amneziawg")
            if (BuildConfig.GREENVPN_HYSTERIA2_PREVIEW_ENABLED) add("hysteria2")
            if (BuildConfig.GREENVPN_VLESS_REALITY_PREVIEW_ENABLED) add("vless_reality")
            if (BuildConfig.GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED) add("naive_https")
            if (BuildConfig.GREENVPN_DNSTT_PREVIEW_ENABLED) add("dnstt")
        }
        const val SECURE_PREFS_NAME = "greenvpn_secure_config_store_v1"
        const val SECURE_KEY_ALIAS = "greenvpn_config_aes_v1"
        const val GCM_TAG_BITS = 128
        const val SESSION_KEY = "greenvpn_mobile_session_v1"
        const val DEVICE_ID_KEY = "greenvpn_mobile_device_id_v1"
        const val MANAGED_CONFIG_KEY = "greenvpn_mobile_managed_config_v1"
        const val MANAGED_PROTOCOL_KEY = "greenvpn_mobile_managed_protocol_v1"
        const val ROUTE_COOLDOWN_KEY = "greenvpn_quick_tile_route_cooldown_v1"
        const val LAST_ROUTE_SUCCESS_KEY = "greenvpn_quick_tile_last_route_success_v1"
        const val DEBUG_TAG = "GreenVpnNativeCascade"
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

    private val appContext = context.applicationContext
    private val tunnel: Tunnel
        get() = GreenVpnWireGuardRuntime.tunnel

    fun isProtocolConnected(protocol: String): Boolean = when (protocol.trim().lowercase()) {
        "dnstt" -> GreenVpnDnsttPreview.snapshot(appContext).connected
        "naive_https" -> GreenVpnNaiveHttpsPreview.snapshot(appContext).connected
        "vless_reality" -> GreenVpnVlessRealityPreview.snapshot(appContext).connected
        "hysteria2" -> GreenVpnHysteria2Preview.snapshot(appContext).connected
        "amneziawg" -> GreenVpnAwg2Preview.snapshot(appContext).connected
        "wireguard_udp" -> {
            val currentBackend = backend()
            currentBackend.getState(tunnel) == Tunnel.State.UP ||
                currentBackend.getRunningTunnelNames().contains(tunnel.getName())
        }
        else -> false
    }

    fun probeRoute(protocol: String): GreenVpnRouteProbe.Result =
        GreenVpnRouteProbe.probe(appContext, protocol)

    fun recordRouteFailure(route: GreenVpnRuntimeRoute) {
        recordRouteFailure(route.serverId, route.protocol)
    }

    fun disconnectAll(): Boolean {
        try { GreenVpnDnsttPreview.disconnect(appContext) } catch (_: Throwable) {}
        try { GreenVpnNaiveHttpsPreview.disconnect(appContext) } catch (_: Throwable) {}
        try { GreenVpnVlessRealityPreview.disconnect(appContext) } catch (_: Throwable) {}
        try { GreenVpnHysteria2Preview.disconnect(appContext) } catch (_: Throwable) {}
        try { GreenVpnAwg2Preview.disconnect(appContext) } catch (_: Throwable) {}
        try {
            val currentBackend = backend()
            if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
            }
        } catch (_: Throwable) {}
        val networkInactive = GreenVpnNetworkTransition.waitForInactive(appContext, 2_500L)
        if (networkInactive) GreenVpnNetworkTransition.markInactive(appContext)
        return networkInactive && SUPPORTED_PROTOCOLS.none { isProtocolConnected(it) }
    }

    fun connectBest(continueRequested: () -> Boolean): GreenVpnNativeCascadeResult {
        if (SUPPORTED_PROTOCOLS.size <= 1) {
            return GreenVpnNativeCascadeResult(false, error = "transport_preview_disabled")
        }
        if (VpnService.prepare(appContext) != null) {
            return GreenVpnNativeCascadeResult(false, error = "vpn_permission_required")
        }
        val session = try { readSession() } catch (failure: Throwable) {
            return GreenVpnNativeCascadeResult(false, error = safeError(failure))
        }
        val accessToken = session.optString("accessToken").trim()
        val preferredBaseUrl = normalizeApiBaseUrl(session.optString("apiBaseUrl"))
        val deviceId = readSecureString(DEVICE_ID_KEY)?.trim().orEmpty()
        if (accessToken.isEmpty() || deviceId.length < 8) {
            return GreenVpnNativeCascadeResult(false, error = "session_or_device_missing")
        }

        val candidates = fetchCatalogCandidates(preferredBaseUrl)
        var lastError = "no_candidate_succeeded"
        for (candidate in candidates) {
            if (!continueRequested()) return GreenVpnNativeCascadeResult(false, error = "cancelled")
            debug("candidate_start id=${candidate.serverId.orEmpty()} protocol=${candidate.protocol}")
            val fetched = try {
                fetchFreshConfig(accessToken, deviceId, preferredBaseUrl, candidate.serverId)
            } catch (failure: Throwable) {
                lastError = safeError(failure)
                recordRouteFailure(candidate.serverId.orEmpty(), candidate.protocol)
                debug("candidate_fetch_failed protocol=${candidate.protocol} error=$lastError")
                null
            } ?: continue
            if (!continueRequested()) return GreenVpnNativeCascadeResult(false, error = "cancelled")
            if (fetched.protocol !in SUPPORTED_PROTOCOLS) {
                lastError = "unsupported_protocol"
                recordRouteFailure(fetched.serverId, fetched.protocol)
                continue
            }

            val connected = try {
                connectVpn(fetched.config, fetched.protocol)
            } catch (failure: Throwable) {
                lastError = safeError(failure)
                false
            }
            if (connected) GreenVpnNetworkTransition.markActive(appContext)
            if (!connected || !continueRequested()) {
                disconnectAll()
                recordRouteFailure(fetched.serverId, fetched.protocol)
                if (!continueRequested()) return GreenVpnNativeCascadeResult(false, error = "cancelled")
                continue
            }

            val probe = probeStartupRoute(fetched.protocol)
            if (!continueRequested()) {
                disconnectAll()
                return GreenVpnNativeCascadeResult(false, error = "cancelled")
            }
            if (!probe.ok) {
                lastError = probe.error.ifEmpty { "route_probe_failed" }
                disconnectAll()
                recordRouteFailure(fetched.serverId, fetched.protocol)
                continue
            }

            clearRouteFailure(fetched.serverId, fetched.protocol)
            writeSecureString(MANAGED_CONFIG_KEY, fetched.config)
            writeSecureString(MANAGED_PROTOCOL_KEY, fetched.protocol)
            writeSecureString(
                LAST_ROUTE_SUCCESS_KEY,
                JSONObject()
                    .put("serverId", fetched.serverId)
                    .put("protocol", fetched.protocol)
                    .put("verifiedAtMs", System.currentTimeMillis())
                    .toString(),
            )
            debug("candidate_success id=${fetched.serverId} protocol=${fetched.protocol}")
            return GreenVpnNativeCascadeResult(true, fetched.serverId, fetched.protocol)
        }
        return GreenVpnNativeCascadeResult(false, error = lastError)
    }

    private fun backend(): GoBackend = GreenVpnWireGuardRuntime.backend(appContext)

    private fun connectVpn(configText: String, protocol: String): Boolean {
        disconnectAll()
        return when (protocol) {
            "dnstt" -> GreenVpnDnsttPreview.connect(
                appContext,
                GreenVpnDnsttPreview.validateConfig(configText),
            )
            "naive_https" -> GreenVpnNaiveHttpsPreview.connect(
                appContext,
                GreenVpnNaiveHttpsPreview.validateConfig(configText),
            )
            "vless_reality" -> GreenVpnVlessRealityPreview.connect(
                appContext,
                GreenVpnVlessRealityPreview.validateConfig(configText),
            )
            "hysteria2" -> GreenVpnHysteria2Preview.connect(
                appContext,
                GreenVpnHysteria2Preview.validateConfig(configText),
            )
            "amneziawg" -> {
                GreenVpnAwg2Preview.connect(appContext, GreenVpnAwg2Preview.parseConfig(configText))
            }
            "wireguard_udp" -> {
                val parsed = Config.parse(
                    ByteArrayInputStream(configText.toByteArray(StandardCharsets.UTF_8)),
                )
                backend().setState(tunnel, Tunnel.State.UP, parsed) == Tunnel.State.UP
            }
            else -> false
        }
    }

    private fun probeStartupRoute(protocol: String): GreenVpnRouteProbe.Result {
        var attempt = 1
        while (true) {
            Thread.sleep(GreenVpnQuickTileCascadePolicy.routeProbeDelayMs(attempt))
            val probe = GreenVpnRouteProbe.probe(appContext, protocol)
            if (probe.ok || !GreenVpnQuickTileCascadePolicy.shouldRetryRouteProbe(attempt, probe.latencyMs)) {
                return probe
            }
            attempt += 1
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

    private fun fetchCatalogCandidates(preferredBaseUrl: String?): List<CatalogCandidate> = try {
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
            if (!server.optBoolean("available", true)) continue
            if (!server.optBoolean("clientConfigReady", true)) continue
            if (server.optString("status").trim().lowercase() == "disabled") continue
            val serverId = server.optString("id").trim()
            if (serverId.isEmpty()) continue
            val protocol = server.optJSONArray("protocols")
                ?.optJSONObject(0)?.optString("code")?.trim()?.lowercase().orEmpty()
            if (protocol !in SUPPORTED_PROTOCOLS) continue
            val latency = if (server.has("latencyMs") && !server.isNull("latencyMs")) {
                server.optInt("latencyMs")
            } else {
                null
            }
            val cooldownUntil = readRouteCooldown(serverId, protocol)?.optLong("untilMs")
                ?.takeIf { it > nowMs }
            parsed += CatalogCandidate(
                serverId,
                protocol,
                server.optInt("healthScore", 50),
                latency,
                cooldownUntil,
            )
        }
        if (parsed.isEmpty()) {
            listOf(CatalogCandidate(null, "wireguard_udp", 100, null, null))
        } else {
            val indexed = parsed.associateBy { requireNotNull(it.serverId) }
            GreenVpnQuickTileCascadePolicy.sort(
                parsed.map {
                    GreenVpnTileRouteCandidate(
                        requireNotNull(it.serverId),
                        it.protocol,
                        it.healthScore,
                        it.latencyMs,
                        it.cooldownUntilMs,
                    )
                },
                nowMs,
            ).mapNotNull { indexed[it.serverId] }
        }
    } catch (failure: Throwable) {
        debug("catalog_failed error=${safeError(failure)}")
        listOf(CatalogCandidate(null, "wireguard_udp", 100, null, null))
    }

    private fun recordRouteFailure(serverId: String, protocol: String) {
        if (serverId.isBlank() || protocol.isBlank()) return
        val key = "$serverId|${protocol.trim().lowercase()}"
        val document = try {
            JSONObject(readSecureString(ROUTE_COOLDOWN_KEY).orEmpty().ifBlank { "{}" })
        } catch (_: Throwable) {
            JSONObject()
        }
        val failures = (document.optJSONObject(key)?.optInt("failures", 0) ?: 0) + 1
        val untilMs = System.currentTimeMillis() +
            GreenVpnQuickTileCascadePolicy.cooldownDurationMs(failures)
        document.put(key, JSONObject().put("failures", failures).put("untilMs", untilMs))
        writeSecureString(ROUTE_COOLDOWN_KEY, document.toString())
    }

    private fun clearRouteFailure(serverId: String, protocol: String) {
        if (serverId.isBlank() || protocol.isBlank()) return
        val document = try {
            JSONObject(readSecureString(ROUTE_COOLDOWN_KEY).orEmpty().ifBlank { "{}" })
        } catch (_: Throwable) {
            return
        }
        document.remove("$serverId|${protocol.trim().lowercase()}")
        writeSecureString(ROUTE_COOLDOWN_KEY, document.toString())
    }

    private fun readRouteCooldown(serverId: String, protocol: String): JSONObject? = try {
        JSONObject(readSecureString(ROUTE_COOLDOWN_KEY).orEmpty().ifBlank { "{}" })
            .optJSONObject("$serverId|${protocol.trim().lowercase()}")
    } catch (_: Throwable) {
        null
    }

    private fun postJson(
        path: String,
        accessToken: String,
        preferredBaseUrl: String?,
        payload: JSONObject,
    ): JSONObject {
        var lastError: Exception? = null
        for (baseUrl in orderedApiBaseUrls(preferredBaseUrl)) {
            try {
                return postJsonToBase(baseUrl, path, accessToken, payload)
            } catch (failure: Exception) {
                lastError = failure
                if (!isRetryableApiError(failure)) throw failure
            }
        }
        throw lastError ?: IllegalStateException("api_unavailable")
    }

    private fun getJson(path: String, preferredBaseUrl: String?): JSONObject {
        var lastError: Exception? = null
        for (baseUrl in orderedApiBaseUrls(preferredBaseUrl)) {
            try {
                return getJsonFromBase(baseUrl, path)
            } catch (failure: Exception) {
                lastError = failure
                if (!isRetryableApiError(failure)) throw failure
            }
        }
        throw lastError ?: IllegalStateException("api_unavailable")
    }

    private fun orderedApiBaseUrls(preferredBaseUrl: String?): List<String> {
        val bases = linkedSetOf(API_BASE_URL).apply { addAll(API_FALLBACK_BASE_URLS) }
        val preferred = normalizeApiBaseUrl(preferredBaseUrl)
        if (preferred != null && preferred in bases) {
            return linkedSetOf(preferred).apply { addAll(bases) }.toList()
        }
        return bases.toList()
    }

    private fun normalizeApiBaseUrl(value: String?): String? {
        val normalized = value?.trim()?.trimEnd('/').orEmpty()
        if (normalized.isEmpty()) return null
        return try {
            URL(normalized).takeIf { it.protocol.isNotBlank() && it.host.isNotBlank() }?.toString()?.trimEnd('/')
        } catch (_: Throwable) {
            null
        }
    }

    private fun postJsonToBase(
        baseUrl: String,
        path: String,
        accessToken: String,
        payload: JSONObject,
    ): JSONObject {
        val connection = (URL("$baseUrl$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 5_000
            readTimeout = 15_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Authorization", "Bearer $accessToken")
            setRequestProperty("X-GreenVPN-Release-Channel", RELEASE_CHANNEL)
            setRequestProperty("X-GreenVPN-Version", APP_VERSION)
            setRequestProperty("X-GreenVPN-Supported-Protocols", SUPPORTED_PROTOCOLS.joinToString(","))
        }
        return try {
            connection.outputStream.use {
                it.write(payload.toString().toByteArray(StandardCharsets.UTF_8))
            }
            readJsonResponse(connection)
        } finally {
            connection.disconnect()
        }
    }

    private fun getJsonFromBase(baseUrl: String, path: String): JSONObject {
        val connection = (URL("$baseUrl$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 5_000
            readTimeout = 10_000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("X-GreenVPN-Release-Channel", RELEASE_CHANNEL)
            setRequestProperty("X-GreenVPN-Version", APP_VERSION)
            setRequestProperty("X-GreenVPN-Supported-Protocols", SUPPORTED_PROTOCOLS.joinToString(","))
        }
        return try {
            readJsonResponse(connection)
        } finally {
            connection.disconnect()
        }
    }

    private fun readJsonResponse(connection: HttpURLConnection): JSONObject {
        val code = connection.responseCode
        val stream = if (code in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader(StandardCharsets.UTF_8)?.use { it.readText() }.orEmpty()
        if (code !in 200..299) throw IllegalStateException("HTTP $code")
        return JSONObject(body)
    }

    private fun isRetryableApiError(error: Exception): Boolean {
        val status = Regex("HTTP (\\d{3})").find(error.message.orEmpty())
            ?.groupValues?.getOrNull(1)?.toIntOrNull()
        return status == null || status == 408 || status >= 500
    }

    private fun readSession(): JSONObject {
        val raw = readSecureString(SESSION_KEY)?.trim().orEmpty()
        return if (raw.isEmpty()) JSONObject() else JSONObject(raw)
    }

    private fun readSecureString(key: String): String? {
        val stored = securePrefs().getString(key, null) ?: return null
        val parts = stored.split(":", limit = 2)
        if (parts.size != 2) return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateConfigKey(),
            GCMParameterSpec(GCM_TAG_BITS, Base64.decode(parts[0], Base64.NO_WRAP)),
        )
        return String(
            cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)),
            StandardCharsets.UTF_8,
        )
    }

    private fun writeSecureString(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateConfigKey())
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val body = Base64.encodeToString(
            cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8)),
            Base64.NO_WRAP,
        )
        check(securePrefs().edit().putString(key, "$iv:$body").commit()) {
            "secure_write_failed"
        }
    }

    private fun securePrefs() =
        appContext.getSharedPreferences(SECURE_PREFS_NAME, Context.MODE_PRIVATE)

    private fun getOrCreateConfigKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getEntry(SECURE_KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                SECURE_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun safeError(error: Throwable): String {
        var current = error
        while (current.cause != null && current.cause !== current) current = current.cause!!
        return (current.message ?: current.javaClass.simpleName)
            .replace(Regex("[\\r\\n]+"), " ")
            .replace(Regex("Bearer\\s+[^\\s]+", RegexOption.IGNORE_CASE), "Bearer [redacted]")
            .take(180)
    }

    private fun debug(message: String) {
        if (BuildConfig.DEBUG) Log.i(DEBUG_TAG, message)
    }

    private class GreenVpnCascadeTunnel(private val name: String) : Tunnel {
        @Volatile private var state = Tunnel.State.DOWN
        override fun getName(): String = name
        override fun onStateChange(newState: Tunnel.State) { state = newState }
    }
}
