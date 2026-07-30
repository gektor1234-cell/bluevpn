const List<String> greenVpnTransportPreviewCascade = <String>[
  'wireguard_udp',
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

const Duration greenVpnWindowsWireGuardConfirmationBudget = Duration(
  seconds: 10,
);
const Duration greenVpnWindowsWireGuardConfirmationPollInterval = Duration(
  milliseconds: 500,
);
const int greenVpnWindowsWireGuardMissingInterfaceLimit = 4;
const Duration greenVpnPreferredRouteTtl = Duration(hours: 24);

const int greenVpnRuntimeFailoverFailureThreshold = 2;
const int greenVpnManagedRouteIdMaxLength = 160;

final RegExp _greenVpnManagedRouteIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9_.:-]*$',
);

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
  return greenVpnTransportPreviewCascade.length;
}

bool greenVpnTransportRequiresFullTunnel(String protocol) =>
    greenVpnFullTunnelOnlyPreviewProtocols.contains(
      protocol.trim().toLowerCase(),
    );

bool greenVpnShouldArmRuntimeFailover({
  required bool previewEnabled,
  required bool isAndroid,
  required bool isWindows,
  required bool serverIsAuto,
  required bool socialOnlyEnabled,
}) =>
    previewEnabled &&
    (isAndroid || isWindows) &&
    !serverIsAuto &&
    !socialOnlyEnabled;

int greenVpnNextRuntimeFailoverFailureCount({
  required int currentFailureCount,
  required bool routeHealthy,
}) {
  if (routeHealthy) return 0;
  return (currentFailureCount + 1).clamp(
    0,
    greenVpnRuntimeFailoverFailureThreshold,
  );
}

bool greenVpnShouldTriggerRuntimeFailover(int failureCount) =>
    failureCount >= greenVpnRuntimeFailoverFailureThreshold;

bool greenVpnIsCompetingVpnFailureMessage(String? message) {
  final normalized = (message ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.contains('другой vpn') ||
      normalized.contains('другого vpn') ||
      normalized.contains('another vpn is active') ||
      normalized.contains('competing vpn');
}

bool greenVpnShouldContinueWindowsWireGuardConfirmation({
  required Duration elapsed,
  required int consecutiveMissingInterfaceChecks,
}) =>
    elapsed < greenVpnWindowsWireGuardConfirmationBudget &&
    consecutiveMissingInterfaceChecks <
        greenVpnWindowsWireGuardMissingInterfaceLimit;

String greenVpnNormalizeManagedRouteId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > greenVpnManagedRouteIdMaxLength ||
      !_greenVpnManagedRouteIdPattern.hasMatch(normalized)) {
    return '';
  }
  return normalized;
}

bool greenVpnIsFreshPreferredRoute({
  required String candidateId,
  required String candidateProtocol,
  required String preferredId,
  required String preferredProtocol,
  required DateTime? preferredAt,
  required DateTime now,
}) {
  final normalizedCandidateId = greenVpnNormalizeManagedRouteId(candidateId);
  final normalizedPreferredId = greenVpnNormalizeManagedRouteId(preferredId);
  final normalizedCandidateProtocol = candidateProtocol.trim().toLowerCase();
  final normalizedPreferredProtocol = preferredProtocol.trim().toLowerCase();
  if (normalizedCandidateId.isEmpty ||
      normalizedPreferredId.isEmpty ||
      normalizedCandidateId != normalizedPreferredId ||
      normalizedCandidateProtocol.isEmpty ||
      normalizedCandidateProtocol != normalizedPreferredProtocol ||
      preferredAt == null) {
    return false;
  }

  final age = now.toUtc().difference(preferredAt.toUtc());
  return !age.isNegative && age <= greenVpnPreferredRouteTtl;
}

bool greenVpnCanUseImmediateCachedRoute({
  required bool isWindows,
  required bool socialOnlyEnabled,
  required bool hasManagedConfig,
  required String candidateId,
  required String candidateProtocol,
  required String managedRouteId,
  required String managedProtocol,
  required String preferredId,
  required String preferredProtocol,
  required DateTime? preferredAt,
  required DateTime now,
}) {
  if (!isWindows || socialOnlyEnabled || !hasManagedConfig) return false;
  final normalizedCandidateId = greenVpnNormalizeManagedRouteId(candidateId);
  final normalizedManagedRouteId = greenVpnNormalizeManagedRouteId(
    managedRouteId,
  );
  final normalizedCandidateProtocol = candidateProtocol.trim().toLowerCase();
  final normalizedManagedProtocol = managedProtocol.trim().toLowerCase();
  if (normalizedCandidateId.isEmpty ||
      normalizedManagedRouteId != normalizedCandidateId ||
      normalizedCandidateProtocol.isEmpty ||
      normalizedManagedProtocol != normalizedCandidateProtocol) {
    return false;
  }
  return greenVpnIsFreshPreferredRoute(
    candidateId: normalizedCandidateId,
    candidateProtocol: normalizedCandidateProtocol,
    preferredId: preferredId,
    preferredProtocol: preferredProtocol,
    preferredAt: preferredAt,
    now: now,
  );
}

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
  bool leftWasRecentlySuccessful = false,
  bool rightWasRecentlySuccessful = false,
}) {
  if (leftCooldownUntil == null && rightCooldownUntil != null) return -1;
  if (leftCooldownUntil != null && rightCooldownUntil == null) return 1;
  if (leftCooldownUntil != null && rightCooldownUntil != null) {
    final byCooldown = leftCooldownUntil.compareTo(rightCooldownUntil);
    if (byCooldown != 0) return byCooldown;
  }

  if (leftWasRecentlySuccessful != rightWasRecentlySuccessful) {
    return leftWasRecentlySuccessful ? -1 : 1;
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
