const List<String> greenVpnTransportPreviewCascade = <String>[
  'amneziawg',
  'hysteria2',
  'vless_reality',
  'naive_https',
  'dnstt',
];

const Set<String> greenVpnFullTunnelOnlyPreviewProtocols = <String>{
  'hysteria2',
  'vless_reality',
  'naive_https',
  'dnstt',
};

int greenVpnTransportPreviewRank(String protocol) {
  final normalized = protocol.trim().toLowerCase();
  final previewRank = greenVpnTransportPreviewCascade.indexOf(normalized);
  if (previewRank >= 0) return previewRank;
  if (normalized == 'wireguard_udp') {
    return greenVpnTransportPreviewCascade.length;
  }
  return greenVpnTransportPreviewCascade.length + 1;
}

bool greenVpnTransportRequiresFullTunnel(String protocol) =>
    greenVpnFullTunnelOnlyPreviewProtocols.contains(
      protocol.trim().toLowerCase(),
    );
