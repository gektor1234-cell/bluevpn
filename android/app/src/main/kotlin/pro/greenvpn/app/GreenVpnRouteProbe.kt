package pro.greenvpn.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.SystemClock
import android.os.Build
import android.util.Log
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean
import java.io.Closeable
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

internal object GreenVpnRouteProbe {
    internal const val TOTAL_PROBE_TIMEOUT_MS = 10_000L
    private const val TAG = "GreenVpnRouteProbe"

    data class Result(
        val ok: Boolean,
        val target: String,
        val statusCode: Int?,
        val latencyMs: Long,
        val error: String,
        val youtubeTargetOk: Boolean = false,
        val independentTargetOk: Boolean = false,
    )

    private val targets = listOf(
        Target("connectivitycheck.gstatic.com", "/generate_204", 204),
        Target("api.greenvpn.pro", "/healthz", 200),
    )

    private val probeExecutor = ThreadPoolExecutor(2, 2, 0L, TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(2), { runnable ->
            Thread(runnable, "GreenVPN-Network-Route-Probe").apply { isDaemon = true }
        })
    private val supplementaryExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "GreenVPN-Service-Probe").apply { isDaemon = true }
    }
    private val supplementaryRunning = AtomicBoolean(false)
    private var lastSupplementaryAt = 0L

    fun probe(context: Context, protocol: String): Result {
        val normalizedProtocol = protocol.trim().lowercase()
        val startedAt = SystemClock.elapsedRealtime()
        val resources = GreenVpnProbeResources()
        val completion = ExecutorCompletionService<Result>(probeExecutor)
        val futures = mutableListOf<Future<Result>>()
        return try {
            targets.forEach { target ->
                futures.add(completion.submit {
                    probeTarget(context.applicationContext, normalizedProtocol, target, resources)
                })
            }
            var last = Result(false, "baseline", null, 0L, "route probe failed")
            repeat(targets.size) {
                val remaining = TOTAL_PROBE_TIMEOUT_MS - (SystemClock.elapsedRealtime() - startedAt)
                val completed = completion.poll(remaining.coerceAtLeast(0), TimeUnit.MILLISECONDS)
                    ?: throw TimeoutException()
                last = completed.get()
                if (last.ok) return last.copy(independentTargetOk = true,
                    latencyMs = SystemClock.elapsedRealtime() - startedAt)
            }
            last.copy(latencyMs = SystemClock.elapsedRealtime() - startedAt)
        } catch (_: TimeoutException) {
            Result(
                ok = false,
                target = targets.first().url,
                statusCode = null,
                latencyMs = SystemClock.elapsedRealtime() - startedAt,
                error = "route probe timed out",
            )
        } catch (failure: Throwable) {
            if (failure is InterruptedException) Thread.currentThread().interrupt()
            Result(
                ok = false,
                target = targets.first().url,
                statusCode = null,
                latencyMs = SystemClock.elapsedRealtime() - startedAt,
                error = safeError(failure),
            )
        } finally {
            resources.close()
            futures.forEach { it.cancel(true) }
            probeExecutor.purge()
        }
    }

    private fun probeTarget(context: Context, protocol: String, target: Target,
        resources: GreenVpnProbeResources): Result {
        val credentials = if (protocol == "dnstt") {
            GreenVpnDnsttPreview.routeProbeCredentials(context.applicationContext)
        } else {
            null
        }
            val startedAt = SystemClock.elapsedRealtime()
            return try {
                debug("protocol=$protocol target=${target.host} phase=system start")
                val systemStatus = probeSystemRoute(context, target, resources)
                require(acceptsStatus(systemStatus, target.expectedStatus)) { "system route returned HTTP $systemStatus" }
                debug("protocol=$protocol target=${target.host} phase=system status=$systemStatus")
                val status = socksPortForProtocol(protocol)?.let { port ->
                    debug("protocol=$protocol target=${target.host} phase=socks start")
                    val proxyStatus = probeHttpsViaSocks(target, port, credentials, resources)
                    require(acceptsStatus(proxyStatus, target.expectedStatus)) { "SOCKS route returned HTTP $proxyStatus" }
                    debug("protocol=$protocol target=${target.host} phase=socks status=$proxyStatus")
                    proxyStatus
                } ?: systemStatus
                Result(
                    ok = true,
                    target = target.url,
                    statusCode = status,
                    latencyMs = SystemClock.elapsedRealtime() - startedAt,
                    error = "",
                )
            } catch (failure: Throwable) {
                debug("protocol=$protocol target=${target.host} failed=${safeError(failure)}")
                Result(
                    ok = false,
                    target = target.url,
                    statusCode = null,
                    latencyMs = SystemClock.elapsedRealtime() - startedAt,
                    error = safeError(failure),
                )
            }
    }

    internal fun acceptsStatus(actual: Int, expected: Int): Boolean = actual == expected

    // Supplementary service availability never changes connection state or cooldowns.
    @Synchronized
    fun observeYoutube(context: Context, protocol: String) {
        val now = SystemClock.elapsedRealtime()
        if (supplementaryRunning.get() ||
            (lastSupplementaryAt != 0L && now - lastSupplementaryAt < 300_000L)) return
        supplementaryRunning.set(true)
        lastSupplementaryAt = now
        val operation = GreenVpnRuntimeFailoverService.eventPreferences(context)
            .getString("operation_id", "")
        supplementaryExecutor.execute {
            try {
                GreenVpnProbeResources().use { resources ->
                    val result = probeTarget(context, protocol,
                        Target("www.youtube.com", "/generate_204", 204), resources)
                    if (operation == GreenVpnRuntimeFailoverService.eventPreferences(context)
                        .getString("operation_id", "") && GreenVpnNetworkTransition.isActive(context)) {
                        GreenVpnSupportJournal.record(context, "youtube_supplementary", mapOf(
                            "lastProbeOk" to result.ok, "status" to (result.statusCode ?: 0),
                            "durationMs" to result.latencyMs))
                    }
                }
            } finally { supplementaryRunning.set(false) }
        }
    }

    internal fun socksPortForProtocol(protocol: String): Int? = when (protocol.trim().lowercase()) {
        "hysteria2" -> 1980
        "vless_reality" -> 1981
        "naive_https" -> 1982
        "dnstt" -> 1983
        else -> null
    }

    internal fun <T> preferVpnNetwork(
        activeNetwork: T?,
        availableNetworks: List<T>,
        isVpnNetwork: (T) -> Boolean,
    ): T? {
        if (activeNetwork != null && isVpnNetwork(activeNetwork)) return activeNetwork
        return availableNetworks.firstOrNull(isVpnNetwork)
    }

    internal fun socksGreeting(credentials: GreenVpnDnsttPreview.ProxyCredentials?): ByteArray =
        if (credentials == null) {
            byteArrayOf(0x05, 0x01, 0x00)
        } else {
            byteArrayOf(0x05, 0x02, 0x00, 0x02)
        }

    internal fun usernamePasswordRequest(
        credentials: GreenVpnDnsttPreview.ProxyCredentials,
    ): ByteArray {
        val username = credentials.username.toByteArray(StandardCharsets.UTF_8)
        val password = credentials.password.toByteArray(StandardCharsets.UTF_8)
        require(username.size in 1..255 && password.size in 1..255) {
            "SOCKS credentials are invalid"
        }
        return byteArrayOf(0x01, username.size.toByte()) + username +
            byteArrayOf(password.size.toByte()) + password
    }

    private fun probeSystemRoute(context: Context, target: Target, resources: GreenVpnProbeResources): Int {
        val network = awaitVpnNetwork(context)
        val connection = (network.openConnection(URL(target.url)) as HttpURLConnection).apply {
            requestMethod = "GET"
            instanceFollowRedirects = false
            useCaches = false
            connectTimeout = 4_000
            readTimeout = 5_000
            setRequestProperty("User-Agent", "GreenVPN Android route-check")
        }
        resources.track(Closeable { connection.disconnect() })
        return try {
            connection.responseCode
        } finally {
            connection.disconnect()
        }
    }

    @Suppress("DEPRECATION")
    private fun awaitVpnNetwork(context: Context): Network {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
            ?: error("Connectivity manager is unavailable")
        val deadline = SystemClock.elapsedRealtime() + 2_500L
        do {
            val network = preferVpnNetwork(
                activeNetwork = connectivity.activeNetwork,
                availableNetworks = connectivity.allNetworks.toList(),
            ) { candidate ->
                val caps = connectivity.getNetworkCapabilities(candidate)
                caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true &&
                    (Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
                        caps.ownerUid == context.applicationInfo.uid)
            }
            if (network != null) return network
            try {
                Thread.sleep(100L)
            } catch (interrupted: InterruptedException) {
                Thread.currentThread().interrupt()
                throw interrupted
            }
        } while (SystemClock.elapsedRealtime() < deadline)
        error("VPN network is unavailable for route probe")
    }

    private fun probeHttpsViaSocks(
        target: Target,
        socksPort: Int,
        credentials: GreenVpnDnsttPreview.ProxyCredentials?,
        resources: GreenVpnProbeResources,
    ): Int {
        val socket = Socket()
        resources.track(socket)
        try {
            socket.soTimeout = 4_000
            socket.connect(InetSocketAddress("127.0.0.1", socksPort), 2_000)
            val input = DataInputStream(socket.getInputStream())
            val output = DataOutputStream(socket.getOutputStream())
            output.write(socksGreeting(credentials))
            output.flush()
            val greeting = ByteArray(2)
            input.readFully(greeting)
            require(greeting[0].toInt() == 0x05) { "SOCKS authentication negotiation failed" }
            when (greeting[1].toInt() and 0xff) {
                0x00 -> Unit
                0x02 -> authenticateUsernamePassword(input, output, credentials)
                else -> error("SOCKS authentication negotiation failed")
            }

            val host = target.host.toByteArray(StandardCharsets.US_ASCII)
            require(host.size in 1..255) { "SOCKS target host is invalid" }
            output.write(byteArrayOf(0x05, 0x01, 0x00, 0x03, host.size.toByte()))
            output.write(host)
            output.writeShort(443)
            output.flush()

            val response = ByteArray(4)
            input.readFully(response)
            require(response[0].toInt() == 0x05 && response[1].toInt() == 0x00) {
                "SOCKS connect failed: ${response[1].toInt() and 0xff}"
            }
            when (response[3].toInt() and 0xff) {
                0x01 -> input.skipFully(4)
                0x03 -> input.skipFully(input.readUnsignedByte())
                0x04 -> input.skipFully(16)
                else -> error("SOCKS returned an unsupported address type")
            }
            input.skipFully(2)

            val tlsFactory = SSLSocketFactory.getDefault() as SSLSocketFactory
            val tls = tlsFactory.createSocket(socket, target.host, 443, true) as SSLSocket
            resources.track(tls)
            tls.soTimeout = 4_000
            tls.sslParameters = tls.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
            tls.startHandshake()
            tls.getOutputStream().bufferedWriter(StandardCharsets.US_ASCII).use { writer ->
                writer.write("GET ${target.path} HTTP/1.1\r\n")
                writer.write("Host: ${target.host}\r\n")
                writer.write("User-Agent: GreenVPN Android route-check\r\n")
                writer.write("Connection: close\r\n\r\n")
                writer.flush()
                val statusLine = tls.getInputStream().bufferedReader(StandardCharsets.US_ASCII).readLine().orEmpty()
                return Regex("^HTTP/\\S+\\s+(\\d{3})").find(statusLine)
                    ?.groupValues?.getOrNull(1)?.toIntOrNull()
                    ?: error("HTTPS probe returned an invalid status line")
            }
        } finally {
            try { socket.close() } catch (_: Throwable) {}
        }
    }

    private fun authenticateUsernamePassword(
        input: DataInputStream,
        output: DataOutputStream,
        credentials: GreenVpnDnsttPreview.ProxyCredentials?,
    ) {
        requireNotNull(credentials) { "SOCKS credentials are unavailable" }
        output.write(usernamePasswordRequest(credentials))
        output.flush()
        val response = ByteArray(2)
        input.readFully(response)
        require(response[0].toInt() == 0x01 && response[1].toInt() == 0x00) {
            "SOCKS username/password authentication failed"
        }
    }

    private fun DataInputStream.skipFully(length: Int) {
        val buffer = ByteArray(length)
        readFully(buffer)
    }

    private fun safeError(error: Throwable): String {
        var current = error
        while (current.cause != null && current.cause !== current) current = current.cause!!
        return (current.message ?: current.javaClass.simpleName)
            .replace(Regex("[\\r\\n]+"), " ")
            .take(180)
    }

    private fun debug(message: String) {
        if (BuildConfig.DEBUG) Log.d(TAG, message)
    }

    private data class Target(
        val host: String,
        val path: String,
        val expectedStatus: Int,
    ) {
        val url: String get() = "https://$host$path"
    }
}
