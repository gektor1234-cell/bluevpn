package pro.greenvpn.routing

import java.net.Inet4Address
import java.net.InetAddress

internal object Ipv4RouteExclusions {
    private const val IPV4_SPACE_SIZE = 1L shl 32

    data class Route(val address: String, val prefixLength: Int)

    fun routesExcluding(addresses: Collection<String>): List<Route> {
        val excluded = addresses
            .map(::toLong)
            .distinct()
            .sorted()
        if (excluded.isEmpty()) return listOf(Route("0.0.0.0", 0))

        val routes = mutableListOf<Route>()
        var cursor = 0L
        for (address in excluded) {
            if (cursor < address) appendRange(routes, cursor, address - 1L)
            cursor = address + 1L
        }
        if (cursor < IPV4_SPACE_SIZE) appendRange(routes, cursor, IPV4_SPACE_SIZE - 1L)
        require(routes.size <= 256) { "IPv4 endpoint exclusion produced too many routes" }
        return routes
    }

    internal fun contains(route: Route, address: String): Boolean {
        val value = toLong(address)
        val network = toLong(route.address)
        val size = 1L shl (32 - route.prefixLength)
        return value >= network && value < network + size
    }

    private fun appendRange(routes: MutableList<Route>, start: Long, end: Long) {
        var current = start
        while (current <= end) {
            val remaining = end - current + 1L
            val alignment = if (current == 0L) IPV4_SPACE_SIZE else java.lang.Long.lowestOneBit(current)
            val blockSize = minOf(alignment, java.lang.Long.highestOneBit(remaining))
            val prefixLength = 32 - java.lang.Long.numberOfTrailingZeros(blockSize)
            routes += Route(toAddress(current), prefixLength)
            current += blockSize
        }
    }

    private fun toLong(address: String): Long {
        val parsed = InetAddress.getByName(address)
        require(parsed is Inet4Address && address == parsed.hostAddress) {
            "A canonical IPv4 transport endpoint is required"
        }
        return parsed.address.fold(0L) { value, byte ->
            (value shl 8) or (byte.toInt() and 0xff).toLong()
        }
    }

    private fun toAddress(value: Long): String = listOf(
        value ushr 24,
        value ushr 16,
        value ushr 8,
        value,
    ).joinToString(".") { (it and 0xffL).toString() }
}
