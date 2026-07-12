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

int greenVpnCompareTransportPreviewCandidates({
  required String leftProtocol,
  required String rightProtocol,
  required DateTime? leftCooldownUntil,
  required DateTime? rightCooldownUntil,
  required int leftScore,
  required int rightScore,
  required int? leftPingMs,
  required int? rightPingMs,
  required String leftTitle,
  required String rightTitle,
}) {
  if (leftCooldownUntil == null && rightCooldownUntil != null) return -1;
  if (leftCooldownUntil != null && rightCooldownUntil == null) return 1;
  if (leftCooldownUntil != null && rightCooldownUntil != null) {
    final byCooldown = leftCooldownUntil.compareTo(rightCooldownUntil);
    if (byCooldown != 0) return byCooldown;
  }

  final byTransport = greenVpnTransportPreviewRank(
    leftProtocol,
  ).compareTo(greenVpnTransportPreviewRank(rightProtocol));
  if (byTransport != 0) return byTransport;

  final byScore = rightScore.compareTo(leftScore);
  if (byScore != 0) return byScore;

  final byPing = (leftPingMs ?? 999999).compareTo(rightPingMs ?? 999999);
  if (byPing != 0) return byPing;
  return leftTitle.compareTo(rightTitle);
}
