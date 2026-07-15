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

const List<Duration> greenVpnStartupRouteProbeDelays = <Duration>[
  Duration(milliseconds: 750),
  Duration(milliseconds: 900),
  Duration(milliseconds: 1400),
];

Duration greenVpnStartupRouteProbeDelay(int attempt) {
  final index = (attempt - 1).clamp(
    0,
    greenVpnStartupRouteProbeDelays.length - 1,
  );
  return greenVpnStartupRouteProbeDelays[index];
}

bool greenVpnShouldRetryStartupRouteProbe({
  required int attempt,
  required int latencyMs,
}) =>
    attempt < greenVpnStartupRouteProbeDelays.length &&
    latencyMs >= 0 &&
    latencyMs < 4000;

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

bool greenVpnShouldArmRuntimeFailover({
  required bool previewEnabled,
  required bool isAndroid,
  required bool serverIsAuto,
  required bool socialOnlyEnabled,
}) => previewEnabled && isAndroid && !serverIsAuto && !socialOnlyEnabled;

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
