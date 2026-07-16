package pro.greenvpn.app

internal object GreenVpnTunnelBackendPolicy {
    fun usesStandardBackend(protocol: String): Boolean =
        protocol.trim().lowercase() == "wireguard_udp"

    fun usesAmneziaBackend(protocol: String): Boolean =
        protocol.trim().lowercase() == "amneziawg"

    fun previewSnapshotIsActive(connected: Boolean, state: String): Boolean =
        connected || state == "starting"

    fun previewSnapshotNeedsCleanup(connected: Boolean, state: String): Boolean =
        previewSnapshotIsActive(connected, state) || state == "error"
}
