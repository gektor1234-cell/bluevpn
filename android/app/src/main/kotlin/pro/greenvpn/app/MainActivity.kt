package pro.greenvpn.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
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
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var backend: GoBackend? = null
    private var tunnel = GreenVpnTunnel("GreenVPN")
    private var pendingConnectResult: MethodChannel.Result? = null
    private var pendingConfig: Config? = null
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
                "status" -> handleStatus(result)
                "connect" -> handleConnect(call, result)
                "disconnect" -> handleDisconnect(result)
                "secureRead" -> handleSecureRead(call, result)
                "secureWrite" -> handleSecureWrite(call, result)
                "secureDelete" -> handleSecureDelete(call, result)
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
        pendingConnectResult = null
        pendingConfig = null

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

        connectWithConfig(config, result)
    }

    private fun backend(): GoBackend {
        val current = backend
        if (current != null) return current
        val created = GoBackend(applicationContext)
        backend = created
        return created
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

        val parsed = try {
            Config.parse(ByteArrayInputStream(configText.toByteArray(StandardCharsets.UTF_8)))
        } catch (e: Exception) {
            result.success(
                response(
                    ok = false,
                    connected = false,
                    message = "Android не смог прочитать WireGuard-конфиг: ${safeError(e)}"
                )
            )
            return
        }

        val permissionIntent = VpnService.prepare(this)
        if (permissionIntent != null) {
            pendingConnectResult = result
            pendingConfig = parsed
            startActivityForResult(permissionIntent, VPN_PERMISSION_REQUEST)
            return
        }

        connectWithConfig(parsed, result)
    }

    private fun connectWithConfig(config: Config, result: MethodChannel.Result) {
        executor.execute {
            try {
                val currentBackend = backend()
                if (currentBackend.getRunningTunnelNames().contains(tunnel.getName())) {
                    currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                    Thread.sleep(250)
                }
                val state = currentBackend.setState(tunnel, Tunnel.State.UP, config)
                runOnUiThread {
                    result.success(
                        response(
                            ok = state == Tunnel.State.UP,
                            connected = state == Tunnel.State.UP,
                            message = if (state == Tunnel.State.UP) {
                                "VPN подключён."
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
                val currentBackend = backend()
                val state = currentBackend.setState(tunnel, Tunnel.State.DOWN, null)
                val runningNames = currentBackend.getRunningTunnelNames().toList()
                val stillRunning = runningNames.contains(tunnel.getName())
                runOnUiThread {
                    result.success(
                        response(
                            ok = state == Tunnel.State.DOWN && !stillRunning,
                            connected = state == Tunnel.State.UP || stillRunning,
                            message = if (state == Tunnel.State.DOWN && !stillRunning) {
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

    private fun handleStatus(result: MethodChannel.Result) {
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
