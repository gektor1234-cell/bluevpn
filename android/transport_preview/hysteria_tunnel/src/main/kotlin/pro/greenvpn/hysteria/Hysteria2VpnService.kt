package pro.greenvpn.hysteria

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import hev.htproxy.TProxyService
import org.json.JSONObject
import pro.greenvpn.runtime.PreviewVpnServiceRuntime
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class Hysteria2VpnService : VpnService() {
    data class Snapshot(
        val state: String,
        val rxBytes: Long,
        val txBytes: Long,
        val version: String,
        val error: String
    )

    companion object {
        const val ACTION_CONNECT = "pro.greenvpn.hysteria.CONNECT"
        const val ACTION_DISCONNECT = "pro.greenvpn.hysteria.DISCONNECT"
        const val EXTRA_CONFIG_PATH = "configPath"
        private const val NOTIFICATION_CHANNEL = "greenvpn_transport_preview_vpn"
        private const val NOTIFICATION_ID = 48742
        private const val HYSTERIA_LIBRARY = "hysteria"
        private const val BRIDGE_LIBRARY = "greenvpn-hysteria-bridge"
        private const val STATE_FILE = "state.json"

        @Volatile private var state = "down"
        @Volatile private var error = ""
        @Volatile private var rxBytes = 0L
        @Volatile private var txBytes = 0L
        @Volatile private var nativeLoaded = false
        @Volatile private var currentService: Hysteria2VpnService? = null

        @Synchronized
        fun ensureNativeLoaded() {
            if (nativeLoaded) return
            System.loadLibrary(BRIDGE_LIBRARY)
            nativeLoaded = true
        }

        fun runtimeRoot(context: Context): File = File(context.noBackupFilesDir, "h2-preview")

        fun hysteriaBinary(context: Context): File {
            val directory = File(context.applicationInfo.nativeLibraryDir).canonicalFile
            val binary = File(directory, "lib$HYSTERIA_LIBRARY.so").canonicalFile
            require(binary.parentFile == directory) { "Hysteria2 binary escaped nativeLibraryDir" }
            return binary
        }

        @Synchronized
        fun snapshot(context: Context): Snapshot {
            if (currentService != null) return Snapshot(state, rxBytes, txBytes, "2.9.3", error)
            val persisted = readPersistedSnapshot(context)
                ?: return Snapshot("down", 0L, 0L, "2.9.3", "")
            if (persisted.state in setOf("up", "starting", "stopping") &&
                !PreviewVpnServiceRuntime.isRunningOrStarting(
                    context,
                    Hysteria2VpnService::class.java,
                    persisted.state,
                    File(runtimeRoot(context), STATE_FILE),
                )
            ) {
                val recovered = Snapshot(
                    "error",
                    0L,
                    0L,
                    "2.9.3",
                    "VPN service stopped unexpectedly",
                )
                persistSnapshot(context, recovered)
                return recovered
            }
            return persisted
        }

        private fun readPersistedSnapshot(context: Context): Snapshot? = try {
            val file = File(runtimeRoot(context), STATE_FILE)
            if (!file.isFile || file.length() !in 2..4_096) null else {
                val root = JSONObject(file.readText(Charsets.UTF_8))
                val persistedState = root.optString("state", "down")
                if (persistedState !in setOf("down", "starting", "up", "stopping", "error")) {
                    null
                } else {
                    Snapshot(
                        persistedState,
                        0L,
                        0L,
                        "2.9.3",
                        root.optString("error", "").replace(Regex("[\\r\\n]+"), " ").take(240),
                    )
                }
            }
        } catch (_: Throwable) {
            null
        }

        @Synchronized
        private fun persistSnapshot(context: Context, snapshot: Snapshot) {
            try {
                val root = runtimeRoot(context)
                if (!root.exists() && !root.mkdirs()) return
                val target = File(root, STATE_FILE)
                val temporary = File(root, "$STATE_FILE.tmp")
                temporary.writeText(
                    JSONObject()
                        .put("state", snapshot.state)
                        .put("error", snapshot.error)
                        .put("version", snapshot.version)
                        .toString() + "\n",
                    Charsets.UTF_8,
                )
                temporary.setReadable(false, false)
                temporary.setReadable(true, true)
                temporary.setWritable(true, true)
                if (!temporary.renameTo(target)) {
                    target.delete()
                    temporary.renameTo(target)
                }
            } catch (_: Throwable) {}
        }

        @Synchronized
        fun prepareForConnect(context: Context) {
            rxBytes = 0L
            txBytes = 0L
            state = "starting"
            error = ""
            persistSnapshot(context, Snapshot(state, rxBytes, txBytes, "2.9.3", error))
        }

        @Synchronized
        fun requestDisconnect(context: Context): Boolean {
            val service = currentService
            if (service != null) {
                return try {
                    service.worker.execute {
                        service.cleanup("down", "")
                        service.stopSelf()
                    }
                    true
                } catch (_: Throwable) {
                    false
                }
            }
            if (PreviewVpnServiceRuntime.requestDisconnect(
                    context,
                    Hysteria2VpnService::class.java,
                    ACTION_DISCONNECT,
                )
            ) return true
            val root = runtimeRoot(context)
            for (name in listOf("fd.sock", "runtime.yaml", "hev.yaml", "base.yaml")) {
                try { File(root, name).delete() } catch (_: Throwable) {}
            }
            rxBytes = 0L
            txBytes = 0L
            state = "down"
            error = ""
            persistSnapshot(context, Snapshot(state, rxBytes, txBytes, "2.9.3", error))
            return true
        }

        internal fun debugKillEngineForTest(): Boolean {
            val process = currentService?.hysteriaProcess ?: return false
            process.destroyForcibly()
            return true
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val cleanupStarted = AtomicBoolean(false)
    private val tproxy = TProxyService()
    private var tunFd = -1
    private var hysteriaProcess: Process? = null
    private var fdControlThread: Thread? = null
    private var monitorThread: Thread? = null
    private lateinit var binaryPath: String
    private lateinit var root: File

    external fun nativeRunFdControl(socketPath: String): Int
    external fun nativeStopFdControl()

    override fun onCreate() {
        super.onCreate()
        ensureNativeLoaded()
        root = runtimeRoot(this)
        binaryPath = hysteriaBinary(this).canonicalPath
        currentService = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, notification("Green VPN запускается"))
        when (intent?.action) {
            ACTION_CONNECT -> {
                val configPath = intent.getStringExtra(EXTRA_CONFIG_PATH).orEmpty()
                worker.execute { startTunnel(configPath) }
            }
            ACTION_DISCONNECT -> worker.execute {
                cleanup("down", "")
                stopSelf()
            }
            else -> worker.execute {
                cleanup("down", "")
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    fun protectSocket(fd: Int): Boolean = protect(fd)

    override fun onRevoke() {
        val preserveFailure = shouldPreserveFailure()
        val revokedState = if (preserveFailure) "error" else "down"
        val revokedError = if (preserveFailure) error.ifEmpty { "VPN permission revoked during cleanup" } else ""
        worker.execute {
            cleanup(revokedState, revokedError)
            stopSelf()
        }
        super.onRevoke()
    }

    override fun onDestroy() {
        val preserveFailure = shouldPreserveFailure()
        val finalState = if (preserveFailure) "error" else "down"
        val finalError = if (preserveFailure) error.ifEmpty { "Hysteria2 stopped unexpectedly" } else ""
        cleanup(finalState, finalError)
        if (currentService === this) currentService = null
        worker.shutdownNow()
        super.onDestroy()
    }

    private fun startTunnel(sourcePath: String) {
        try {
            cleanup("starting", "")
            cleanupStarted.set(false)
            state = "starting"
            require(root.exists() || root.mkdirs()) { "Hysteria2 runtime directory was not created" }
            val source = File(sourcePath).canonicalFile
            require(source.parentFile == root.canonicalFile && source.name == "base.yaml" && source.isFile) {
                "Hysteria2 base config path is invalid"
            }
            require(File(binaryPath).isFile && File(binaryPath).canExecute()) {
                "Hysteria2 native binary is unavailable"
            }

            val fdSocket = File(root, "fd.sock")
            val runtimeConfig = File(root, "runtime.yaml")
            val hevConfig = File(root, "hev.yaml")
            val logFile = File(root, "hysteria.log")
            fdSocket.delete()
            runtimeConfig.writeText(
                Hysteria2Config.renderRuntime(source.readText(Charsets.UTF_8), fdSocket.canonicalPath),
                Charsets.UTF_8
            )
            source.delete()
            hevConfig.writeText(hevConfigText(), Charsets.UTF_8)
            for (file in listOf(runtimeConfig, hevConfig, logFile)) {
                if (!file.exists()) file.createNewFile()
                file.setReadable(false, false)
                file.setReadable(true, true)
                file.setWritable(true, true)
            }

            fdControlThread = Thread({
                val result = nativeRunFdControl(fdSocket.canonicalPath)
                if (result != 0 && state == "up") failClosed("FD control stopped: $result")
            }, "GreenVPN-H2-FD-Control").apply { start() }
            waitForFile(fdSocket, 3_000L)

            hysteriaProcess = ProcessBuilder(
                binaryPath,
                "client",
                "-c",
                runtimeConfig.canonicalPath
            )
                .redirectErrorStream(true)
                .redirectOutput(ProcessBuilder.Redirect.appendTo(logFile))
                .start()
            waitForSocks(10_000L)

            val descriptor = Builder()
                .setSession("Green VPN")
                .setMtu(1400)
                .addAddress("198.18.0.1", 32)
                .addAddress("fc00::1", 128)
                .addRoute("0.0.0.0", 0)
                .addRoute("::", 0)
                .addDnsServer("198.18.0.2")
                .apply { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) setMetered(false) }
                .establish() ?: throw IllegalStateException("Android did not establish the VPN interface")
            tunFd = descriptor.detachFd()
            tproxy.TProxyStartService(hevConfig.canonicalPath, tunFd)
            Thread.sleep(700L)
            require(isProcessAlive(hysteriaProcess)) { "Hysteria2 exited during startup" }
            state = "up"
            error = ""
            persistSnapshot(this, Snapshot(state, rxBytes, txBytes, "2.9.3", error))
            updateStats()
            startForeground(NOTIFICATION_ID, notification("Green VPN подключён"))
            startMonitor()
        } catch (failure: Throwable) {
            cleanup("error", safeMessage(failure))
        }
    }

    private fun startMonitor() {
        val expectedProcess = hysteriaProcess
        monitorThread = Thread({
            while (state == "up") {
                if (!isProcessAlive(expectedProcess)) {
                    failClosed("Hysteria2 process stopped")
                    return@Thread
                }
                updateStats()
                try {
                    Thread.sleep(500L)
                } catch (_: InterruptedException) {
                    return@Thread
                }
            }
        }, "GreenVPN-H2-Watchdog").apply { start() }
    }

    private fun failClosed(message: String) {
        if (cleanupStarted.compareAndSet(false, true)) {
            worker.execute {
                cleanup("error", message)
                stopSelf()
            }
        }
    }

    private fun cleanup(finalState: String, finalError: String) {
        if (state != "starting") state = "stopping"
        try { tproxy.TProxyStopService() } catch (_: Throwable) {}
        if (tunFd >= 0) {
            try { ParcelFileDescriptor.adoptFd(tunFd).close() } catch (_: Throwable) {}
            tunFd = -1
        }
        val process = hysteriaProcess
        hysteriaProcess = null
        if (process != null) {
            try {
                process.destroy()
                if (!process.waitFor(3, TimeUnit.SECONDS)) {
                    process.destroyForcibly()
                    process.waitFor(2, TimeUnit.SECONDS)
                }
            } catch (_: Throwable) {
                try { process.destroyForcibly() } catch (_: Throwable) {}
            }
        }
        try { nativeStopFdControl() } catch (_: Throwable) {}
        val fdThread = fdControlThread
        fdControlThread = null
        fdThread?.interrupt()
        if (fdThread != null && fdThread !== Thread.currentThread()) {
            try { fdThread.join(2_000L) } catch (_: InterruptedException) { Thread.currentThread().interrupt() }
        }
        monitorThread?.interrupt()
        monitorThread = null
        if (::root.isInitialized) {
            val runtimeFiles = mutableListOf("fd.sock", "runtime.yaml", "hev.yaml")
            if (finalState != "starting") runtimeFiles.add("base.yaml")
            for (name in runtimeFiles) {
                try { File(root, name).delete() } catch (_: Throwable) {}
            }
        }
        rxBytes = 0L
        txBytes = 0L
        state = finalState
        error = finalError
        persistSnapshot(this, Snapshot(state, rxBytes, txBytes, "2.9.3", error))
        if (finalState == "down") {
            cleanupStarted.set(false)
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }

    private fun shouldPreserveFailure(): Boolean =
        cleanupStarted.get() || state == "error" || error.isNotEmpty()

    private fun updateStats() {
        try {
            val stats = tproxy.TProxyGetStats()
            if (stats.size >= 4) {
                txBytes = stats[1]
                rxBytes = stats[3]
            }
        } catch (_: Throwable) {}
    }

    private fun waitForFile(file: File, timeoutMs: Long) {
        val deadline = android.os.SystemClock.elapsedRealtime() + timeoutMs
        while (!file.exists() && android.os.SystemClock.elapsedRealtime() < deadline) {
            Thread.sleep(25L)
        }
        require(file.exists()) { "Hysteria2 FD control socket did not start" }
    }

    private fun waitForSocks(timeoutMs: Long) {
        val deadline = android.os.SystemClock.elapsedRealtime() + timeoutMs
        do {
            if (!isProcessAlive(hysteriaProcess)) {
                throw IllegalStateException("Hysteria2 exited before SOCKS became ready")
            }
            try {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress("127.0.0.1", 1980), 200)
                    return
                }
            } catch (_: Throwable) {
                Thread.sleep(50L)
            }
        } while (android.os.SystemClock.elapsedRealtime() < deadline)
        throw IllegalStateException("Hysteria2 SOCKS listener did not become ready")
    }

    private fun isProcessAlive(process: Process?): Boolean {
        if (process == null) return false
        return try {
            process.exitValue()
            false
        } catch (_: IllegalThreadStateException) {
            true
        }
    }

    private fun hevConfigText(): String = """
        tunnel:
          mtu: 1400
          ipv4: 198.18.0.1
          ipv6: 'fc00::1'
        socks5:
          address: 127.0.0.1
          port: 1980
          udp: 'udp'
        mapdns:
          address: 198.18.0.2
          port: 53
          network: 100.64.0.0
          netmask: 255.192.0.0
          cache-size: 10000
        misc:
          task-stack-size: 86016
          connect-timeout: 10000
          tcp-read-write-timeout: 300000
          udp-read-write-timeout: 60000
          log-file: stderr
          log-level: warn
    """.trimIndent() + "\n"

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL,
                "Green VPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
        )
    }

    private fun notification(text: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Green VPN")
            .setContentText(text)
            .setOngoing(true)
            .build()
    }

    private fun safeMessage(error: Throwable): String {
        var current = error
        while (current.cause != null && current.cause !== current) current = current.cause!!
        return (current.message ?: current.javaClass.simpleName)
            .replace(Regex("[\\r\\n]+"), " ")
            .take(240)
    }
}
