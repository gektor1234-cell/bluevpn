package pro.greenvpn.app

import android.content.Context
import android.os.SystemClock
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
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

internal object GreenVpnRouteProbe {
    internal const val TOTAL_PROBE_TIMEOUT_MS = 18_000L
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
        Target("www.youtube.com", "/generate_204", TargetClass.YOUTUBE),
        Target("i.ytimg.com", "/generate_204", TargetClass.YOUTUBE),
        Target("connectivitycheck.gstatic.com", "/generate_204", TargetClass.INDEPENDENT),
        Target("api.greenvpn.pro", "/healthz", TargetClass.INDEPENDENT),
    )

    private val probeExecutor = Executors.newFixedThreadPool(2) { runnable ->
        Thread(runnable, "GreenVPN-Network-Route-Probe").apply { isDaemon = true }
    }

    fun probe(context: Context, protocol: String): Result {
        val normalizedProtocol = protocol.trim().lowercase()
        val startedAt = SystemClock.elapsedRealtime()
        val future = probeExecutor.submit<Result> {
            probeBlocking(context.applicationContext, normalizedProtocol)
        }
        return try {
            future.get(TOTAL_PROBE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (_: TimeoutException) {
            future.cancel(true)
            Result(
                ok = false,
                target = targets.first().url,
                statusCode = null,
                latencyMs = SystemClock.elapsedRealtime() - startedAt,
                error = "route probe timed out",
            )
        } catch (failure: Throwable) {
            future.cancel(true)
            Result(
                ok = false,
                target = targets.first().url,
                statusCode = null,
                latencyMs = SystemClock.elapsedRealtime() - startedAt,
                error = safeError(failure),
            )
        }
    }

    private fun probeBlocking(context: Context, protocol: String): Result {
        val overallStartedAt = SystemClock.elapsedRealtime()
        val credentials = if (protocol == "dnstt") {
            GreenVpnDnsttPreview.routeProbeCredentials(context.applicationContext)
        } else {
            null
        }
        var last = Result(false, targets.first().url, null, 0L, "route probe did not run")
        var youtubeTargetOk = false
        var independentTargetOk = false
        for (target in targets) {
            if (target.targetClass == TargetClass.YOUTUBE && youtubeTargetOk) continue
            if (target.targetClass == TargetClass.INDEPENDENT && independentTargetOk) continue
            val startedAt = SystemClock.elapsedRealtime()
            last = try {
                debug("protocol=$protocol target=${target.host} phase=system start")
                val systemStatus = probeSystemRoute(target)
                require(systemStatus in 200..399) { "system route returned HTTP $systemStatus" }
                debug("protocol=$protocol target=${target.host} phase=system status=$systemStatus")
                val status = socksPortForProtocol(protocol)?.let { port ->
                    debug("protocol=$protocol target=${target.host} phase=socks start")
                    val proxyStatus = probeHttpsViaSocks(target, port, credentials)
                    require(proxyStatus in 200..399) { "SOCKS route returned HTTP $proxyStatus" }
                    debug("protocol=$protocol target=${target.host} phase=socks status=$proxyStatus")
                    proxyStatus
                } ?: systemStatus
                Result(
                    ok = status in 200..399,
                    target = target.url,
                    statusCode = status,
                    latencyMs = SystemClock.elapsedRealtime() - startedAt,
                    error = if (status in 200..399) "" else "http_$status",
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
            if (last.ok) {
                when (target.targetClass) {
                    TargetClass.YOUTUBE -> youtubeTargetOk = true
                    TargetClass.INDEPENDENT -> independentTargetOk = true
                }
            }
            if (quorumSatisfied(youtubeTargetOk, independentTargetOk)) {
                return last.copy(
                    ok = true,
                    target = "youtube+independent",
                    latencyMs = SystemClock.elapsedRealtime() - overallStartedAt,
                    youtubeTargetOk = true,
                    independentTargetOk = true,
                )
            }
        }
        return last.copy(
            ok = false,
            latencyMs = SystemClock.elapsedRealtime() - overallStartedAt,
            error = "route quorum failed youtube=$youtubeTargetOk independent=$independentTargetOk; ${last.error}",
            youtubeTargetOk = youtubeTargetOk,
            independentTargetOk = independentTargetOk,
        )
    }

    internal fun quorumSatisfied(
        youtubeTargetOk: Boolean,
        independentTargetOk: Boolean,
    ): Boolean = youtubeTargetOk && independentTargetOk

    internal fun socksPortForProtocol(protocol: String): Int? = when (protocol.trim().lowercase()) {
        "hysteria2" -> 1980
        "vless_reality" -> 1981
        "naive_https" -> 1982
        "dnstt" -> 1983
        else -> null
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

    private fun probeSystemRoute(target: Target): Int {
        val connection = (URL(target.url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 4_000
            readTimeout = 5_000
            setRequestProperty("User-Agent", "GreenVPN Android route-check")
        }
        return try {
            connection.responseCode
        } finally {
            connection.disconnect()
        }
    }

    private fun probeHttpsViaSocks(
        target: Target,
        socksPort: Int,
        credentials: GreenVpnDnsttPreview.ProxyCredentials?,
    ): Int {
        val socket = Socket()
        socket.soTimeout = 8_000
        socket.connect(InetSocketAddress("127.0.0.1", socksPort), 3_000)
        try {
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
            tls.soTimeout = 8_000
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

    private enum class TargetClass { YOUTUBE, INDEPENDENT }

    private data class Target(
        val host: String,
        val path: String,
        val targetClass: TargetClass,
    ) {
        val url: String get() = "https://$host$path"
    }
}
