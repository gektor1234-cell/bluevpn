import 'package:greenvpn/services/transport_preview_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview cascade keeps the guarded transport order', () {
    expect(greenVpnTransportPreviewCascade, const <String>[
      'wireguard_udp',
      'amneziawg',
      'hysteria2',
      'vless_reality',
      'naive_https',
      'dnstt',
    ]);

    final shuffled =
        <String>[
          'dnstt',
          'wireguard_udp',
          'vless_reality',
          'amneziawg',
          'naive_https',
          'hysteria2',
        ]..sort(
          (left, right) => greenVpnTransportPreviewRank(
            left,
          ).compareTo(greenVpnTransportPreviewRank(right)),
        );

    expect(shuffled, <String>[...greenVpnTransportPreviewCascade]);
  });

  test('proxy transports are restricted to full-tunnel mode', () {
    for (final protocol in const <String>[
      'hysteria2',
      'vless_reality',
      'naive_https',
      'dnstt',
    ]) {
      expect(greenVpnTransportRequiresFullTunnel(protocol), isTrue);
    }
    expect(greenVpnTransportRequiresFullTunnel('amneziawg'), isFalse);
    expect(greenVpnTransportRequiresFullTunnel('wireguard_udp'), isFalse);
  });

  test('runtime failover never widens selective app routing', () {
    expect(
      greenVpnShouldArmRuntimeFailover(
        previewEnabled: true,
        isAndroid: true,
        isWindows: false,
        serverIsAuto: false,
        socialOnlyEnabled: false,
      ),
      isTrue,
    );
    expect(
      greenVpnShouldArmRuntimeFailover(
        previewEnabled: true,
        isAndroid: true,
        isWindows: false,
        serverIsAuto: false,
        socialOnlyEnabled: true,
      ),
      isFalse,
    );
    expect(
      greenVpnShouldArmRuntimeFailover(
        previewEnabled: true,
        isAndroid: false,
        isWindows: true,
        serverIsAuto: false,
        socialOnlyEnabled: false,
      ),
      isTrue,
    );
    expect(
      greenVpnShouldArmRuntimeFailover(
        previewEnabled: true,
        isAndroid: false,
        isWindows: false,
        serverIsAuto: false,
        socialOnlyEnabled: false,
      ),
      isFalse,
    );
  });

  test('runtime failover requires two consecutive unhealthy checks', () {
    var failures = greenVpnNextRuntimeFailoverFailureCount(
      currentFailureCount: 0,
      routeHealthy: false,
    );
    expect(failures, 1);
    expect(greenVpnShouldTriggerRuntimeFailover(failures), isFalse);

    failures = greenVpnNextRuntimeFailoverFailureCount(
      currentFailureCount: failures,
      routeHealthy: true,
    );
    expect(failures, 0);

    failures = greenVpnNextRuntimeFailoverFailureCount(
      currentFailureCount: failures,
      routeHealthy: false,
    );
    failures = greenVpnNextRuntimeFailoverFailureCount(
      currentFailureCount: failures,
      routeHealthy: false,
    );
    expect(failures, greenVpnRuntimeFailoverFailureThreshold);
    expect(greenVpnShouldTriggerRuntimeFailover(failures), isTrue);
  });

  test('Windows unexpected tunnel loss stays armed for runtime recovery', () {
    expect(
      greenVpnShouldRecoverUnexpectedWindowsDisconnect(
        reportedConnected: false,
        vpnEnabled: true,
        monitorArmed: true,
        recoveryRunning: false,
        vpnBusy: false,
      ),
      isTrue,
    );
    expect(
      greenVpnShouldRecoverUnexpectedWindowsDisconnect(
        reportedConnected: false,
        vpnEnabled: true,
        monitorArmed: false,
        recoveryRunning: false,
        vpnBusy: false,
      ),
      isFalse,
    );
    expect(
      greenVpnShouldRecoverUnexpectedWindowsDisconnect(
        reportedConnected: false,
        vpnEnabled: true,
        monitorArmed: true,
        recoveryRunning: false,
        vpnBusy: true,
      ),
      isFalse,
    );
    expect(
      greenVpnShouldRecoverUnexpectedWindowsDisconnect(
        reportedConnected: true,
        vpnEnabled: true,
        monitorArmed: true,
        recoveryRunning: false,
        vpnBusy: false,
      ),
      isFalse,
    );
  });

  test('Windows runtime health requires transport and routed data plane', () {
    expect(
      greenVpnRuntimeRouteHealthy(
        backendConnected: false,
        dataPlaneProbeOk: true,
      ),
      isFalse,
    );
    expect(
      greenVpnRuntimeRouteHealthy(
        backendConnected: true,
        dataPlaneProbeOk: false,
      ),
      isFalse,
    );
    expect(
      greenVpnRuntimeRouteHealthy(
        backendConnected: true,
        dataPlaneProbeOk: true,
      ),
      isTrue,
    );
    expect(
      greenVpnRuntimeRouteHealthy(
        backendConnected: false,
        dataPlaneProbeOk: false,
      ),
      isFalse,
    );
  });

  test('Windows standby proof freezes on the first runtime failure', () {
    expect(
      greenVpnCanAcceptWindowsStandbyProof(
        runtimeFailureCount: 0,
        recoveryRunning: false,
      ),
      isTrue,
    );
    expect(
      greenVpnCanAcceptWindowsStandbyProof(
        runtimeFailureCount: 1,
        recoveryRunning: false,
      ),
      isFalse,
    );
    expect(
      greenVpnCanAcceptWindowsStandbyProof(
        runtimeFailureCount: 0,
        recoveryRunning: true,
      ),
      isFalse,
    );
  });

  test('Windows never blocks the connect button on an Internet probe', () {
    expect(
      greenVpnShouldBlockForegroundForPostConnectProbe(
        probeRequested: true,
        isWindows: true,
      ),
      isFalse,
    );
    expect(
      greenVpnShouldBlockForegroundForPostConnectProbe(
        probeRequested: true,
        isWindows: false,
      ),
      isTrue,
    );
    expect(
      greenVpnShouldBlockForegroundForPostConnectProbe(
        probeRequested: false,
        isWindows: false,
      ),
      isFalse,
    );
  });

  test('Windows foreground connect prefers an exact cached route', () {
    expect(
      greenVpnWindowsForegroundCandidateIndex(
        protocols: const <String>['amneziawg', 'wireguard_udp', 'hysteria2'],
        immediateCachedIndex: 0,
      ),
      0,
    );
    expect(
      greenVpnWindowsForegroundCandidateIndex(
        protocols: const <String>['amneziawg', 'wireguard_udp', 'hysteria2'],
      ),
      1,
    );
    expect(
      greenVpnWindowsForegroundCandidateIndex(
        protocols: const <String>[
          'wireguard_udp',
          'wireguard_udp',
          'amneziawg',
        ],
        immediateCachedIndex: 1,
      ),
      1,
    );
    expect(
      greenVpnWindowsForegroundCandidateIndex(
        protocols: const <String>['amneziawg', 'hysteria2'],
        immediateCachedIndex: 0,
      ),
      0,
    );
    expect(
      greenVpnWindowsForegroundCandidateIndex(protocols: const <String>[]),
      -1,
    );
  });

  test('persisted runtime route ids are strictly normalized', () {
    expect(
      greenVpnNormalizeManagedRouteId('  nl2-amneziawg.public:1  '),
      'nl2-amneziawg.public:1',
    );
    expect(greenVpnNormalizeManagedRouteId(''), isEmpty);
    expect(greenVpnNormalizeManagedRouteId('../route'), isEmpty);
    expect(greenVpnNormalizeManagedRouteId('route with spaces'), isEmpty);
    expect(
      greenVpnNormalizeManagedRouteId(
        'r' * (greenVpnManagedRouteIdMaxLength + 1),
      ),
      isEmpty,
    );
  });

  test('startup route probe retries only fast failures', () {
    expect(
      greenVpnStartupRouteProbeDelay(1),
      const Duration(milliseconds: 750),
    );
    expect(
      greenVpnStartupRouteProbeDelay(2),
      const Duration(milliseconds: 900),
    );
    expect(
      greenVpnStartupRouteProbeDelay(3),
      const Duration(milliseconds: 1400),
    );
    expect(
      greenVpnShouldRetryStartupRouteProbe(attempt: 1, latencyMs: 25),
      isTrue,
    );
    expect(
      greenVpnShouldRetryStartupRouteProbe(attempt: 2, latencyMs: 3999),
      isTrue,
    );
    expect(
      greenVpnShouldRetryStartupRouteProbe(attempt: 2, latencyMs: 4000),
      isFalse,
    );
    expect(
      greenVpnShouldRetryStartupRouteProbe(attempt: 3, latencyMs: 25),
      isFalse,
    );
  });

  test(
    'Windows WireGuard confirmation is bounded by time and adapter state',
    () {
      expect(
        greenVpnShouldContinueWindowsWireGuardConfirmation(
          elapsed: const Duration(seconds: 9),
          consecutiveMissingInterfaceChecks:
              greenVpnWindowsWireGuardMissingInterfaceLimit - 1,
        ),
        isTrue,
      );
      expect(
        greenVpnShouldContinueWindowsWireGuardConfirmation(
          elapsed: greenVpnWindowsWireGuardConfirmationBudget,
          consecutiveMissingInterfaceChecks: 0,
        ),
        isFalse,
      );
      expect(
        greenVpnShouldContinueWindowsWireGuardConfirmation(
          elapsed: Duration.zero,
          consecutiveMissingInterfaceChecks:
              greenVpnWindowsWireGuardMissingInterfaceLimit,
        ),
        isFalse,
      );
    },
  );

  test('competing VPN failures stop the transport cascade', () {
    expect(
      greenVpnIsCompetingVpnFailureMessage(
        'Другой VPN уже активен. Отключи его и попробуй снова.',
      ),
      isTrue,
    );
    expect(
      greenVpnIsCompetingVpnFailureMessage(
        'Another VPN is active. Disconnect it before continuing.',
      ),
      isTrue,
    );
    expect(
      greenVpnIsCompetingVpnFailureMessage(
        'VPN did not start (service not RUNNING).',
      ),
      isFalse,
    );
    expect(greenVpnIsCompetingVpnFailureMessage(null), isFalse);
  });

  test('last successful route is preferred for only 24 hours', () {
    final now = DateTime.utc(2026, 7, 29, 20);
    expect(
      greenVpnIsFreshPreferredRoute(
        candidateId: 'gb1-awg2-canary',
        candidateProtocol: 'amneziawg',
        preferredId: 'gb1-awg2-canary',
        preferredProtocol: 'AMNEZIAWG',
        preferredAt: now.subtract(const Duration(hours: 23)),
        now: now,
      ),
      isTrue,
    );
    expect(
      greenVpnIsFreshPreferredRoute(
        candidateId: 'gb1-awg2-canary',
        candidateProtocol: 'amneziawg',
        preferredId: 'gb1-awg2-canary',
        preferredProtocol: 'amneziawg',
        preferredAt: now.subtract(const Duration(hours: 25)),
        now: now,
      ),
      isFalse,
    );
    expect(
      greenVpnIsFreshPreferredRoute(
        candidateId: 'another-route',
        candidateProtocol: 'amneziawg',
        preferredId: 'gb1-awg2-canary',
        preferredProtocol: 'amneziawg',
        preferredAt: now,
        now: now,
      ),
      isFalse,
    );
  });

  test('Windows can immediately reuse only the exact fresh managed route', () {
    final now = DateTime.utc(2026, 7, 30, 10);
    bool canUse({
      bool isWindows = true,
      bool socialOnlyEnabled = false,
      bool hasManagedConfig = true,
      String candidateId = 'nl1-fast',
      String candidateProtocol = 'wireguard_udp',
      String managedRouteId = 'nl1-fast',
      String managedProtocol = 'wireguard_udp',
      String preferredId = 'nl1-fast',
      String preferredProtocol = 'wireguard_udp',
      DateTime? preferredAt,
    }) => greenVpnCanUseImmediateCachedRoute(
      isWindows: isWindows,
      socialOnlyEnabled: socialOnlyEnabled,
      hasManagedConfig: hasManagedConfig,
      candidateId: candidateId,
      candidateProtocol: candidateProtocol,
      managedRouteId: managedRouteId,
      managedProtocol: managedProtocol,
      preferredId: preferredId,
      preferredProtocol: preferredProtocol,
      preferredAt: preferredAt ?? now.subtract(const Duration(minutes: 5)),
      now: now,
    );

    expect(canUse(), isTrue);
    expect(canUse(isWindows: false), isFalse);
    expect(canUse(socialOnlyEnabled: true), isFalse);
    expect(canUse(hasManagedConfig: false), isFalse);
    expect(canUse(managedRouteId: 'another-route'), isFalse);
    expect(canUse(managedProtocol: 'amneziawg'), isFalse);
    expect(canUse(preferredId: 'another-route'), isFalse);
    expect(
      canUse(
        candidateId: 'gb1-awg2-canary',
        candidateProtocol: 'amneziawg',
        managedRouteId: 'gb1-awg2-canary',
        managedProtocol: 'amneziawg',
        preferredId: 'gb1-awg2-canary',
        preferredProtocol: 'amneziawg',
      ),
      isTrue,
    );
    expect(
      canUse(preferredAt: now.subtract(const Duration(hours: 25))),
      isFalse,
    );
  });

  test('cooldown demotes a failed route without changing cascade order', () {
    final now = DateTime.utc(2026, 7, 12, 12);
    final candidates =
        <
            ({
              String protocol,
              DateTime? cooldownUntil,
              int score,
              int? ping,
              String title,
            })
          >[
            (
              protocol: 'wireguard_udp',
              cooldownUntil: null,
              score: 500,
              ping: 1,
              title: 'Stable',
            ),
            (
              protocol: 'dnstt',
              cooldownUntil: null,
              score: 100,
              ping: 30,
              title: 'DNS',
            ),
            (
              protocol: 'amneziawg',
              cooldownUntil: now.add(const Duration(minutes: 1)),
              score: 100,
              ping: 5,
              title: 'AWG2',
            ),
            (
              protocol: 'hysteria2',
              cooldownUntil: null,
              score: 100,
              ping: 10,
              title: 'H2',
            ),
            (
              protocol: 'vless_reality',
              cooldownUntil: null,
              score: 100,
              ping: 15,
              title: 'VLESS',
            ),
            (
              protocol: 'naive_https',
              cooldownUntil: null,
              score: 100,
              ping: 20,
              title: 'Naive',
            ),
          ]
          ..sort(
            (left, right) => greenVpnCompareTransportPreviewCandidates(
              leftProtocol: left.protocol,
              rightProtocol: right.protocol,
              leftCooldownUntil: left.cooldownUntil,
              rightCooldownUntil: right.cooldownUntil,
              leftScore: left.score,
              rightScore: right.score,
              leftPingMs: left.ping,
              rightPingMs: right.ping,
              leftTitle: left.title,
              rightTitle: right.title,
            ),
          );

    expect(candidates.map((candidate) => candidate.protocol), <String>[
      'wireguard_udp',
      'hysteria2',
      'vless_reality',
      'naive_https',
      'dnstt',
      'amneziawg',
    ]);
  });

  test('recently successful route leads until it fails or expires', () {
    final candidates =
        <({String protocol, bool preferred})>[
          (protocol: 'wireguard_udp', preferred: false),
          (protocol: 'amneziawg', preferred: true),
        ]..sort(
          (left, right) => greenVpnCompareTransportPreviewCandidates(
            leftProtocol: left.protocol,
            rightProtocol: right.protocol,
            leftCooldownUntil: null,
            rightCooldownUntil: null,
            leftScore: 100,
            rightScore: 100,
            leftPingMs: 10,
            rightPingMs: 20,
            leftTitle: left.protocol,
            rightTitle: right.protocol,
            leftWasRecentlySuccessful: left.preferred,
            rightWasRecentlySuccessful: right.preferred,
          ),
        );

    expect(candidates.first.protocol, 'amneziawg');
  });

  test(
    'fresh standby proof leads only when caller opts into recovery order',
    () {
      int compare(String left, String right, {required bool useProof}) =>
          greenVpnCompareTransportPreviewCandidates(
            leftProtocol: left,
            rightProtocol: right,
            leftCooldownUntil: null,
            rightCooldownUntil: null,
            leftScore: 100,
            rightScore: 100,
            leftPingMs: 10,
            rightPingMs: 20,
            leftTitle: left,
            rightTitle: right,
            leftHasFreshStandbyProof: false,
            rightHasFreshStandbyProof: useProof,
          );

      expect(
        compare('wireguard_udp', 'hysteria2', useProof: false),
        lessThan(0),
      );
      expect(
        compare('wireguard_udp', 'hysteria2', useProof: true),
        greaterThan(0),
      );
    },
  );

  test('standby proof JSON is strict and expires after ten minutes', () {
    final now = DateTime.utc(2026, 7, 31, 12);
    final proof = GreenVpnStandbyRouteProof(
      routeId: 'nl2-hysteria',
      protocol: 'hysteria2',
      kind: GreenVpnStandbyProofKind.proxyYoutube,
      preparedAt: now.subtract(const Duration(minutes: 2)),
      verifiedAt: now.subtract(const Duration(minutes: 9)),
      latencyMs: 321,
    );
    final restored = GreenVpnStandbyRouteProof.fromJson(proof.toJson());
    expect(restored, isNotNull);
    expect(restored!.key, 'nl2-hysteria|hysteria2');
    expect(restored.isFresh(now), isTrue);
    expect(restored.isFreshForPreparedConfig(now, proof.preparedAt), isTrue);
    expect(
      restored.isFreshForPreparedConfig(
        now,
        proof.preparedAt.add(const Duration(milliseconds: 1)),
      ),
      isFalse,
    );
    expect(restored.isFresh(now.add(const Duration(minutes: 2))), isFalse);
    expect(
      GreenVpnStandbyRouteProof.fromJson(<String, dynamic>{
        ...proof.toJson(),
        'routeId': '../unsafe',
      }),
      isNull,
    );
  });

  test('standby config refresh is bounded by a six hour TTL', () {
    final now = DateTime.utc(2026, 7, 31, 12);
    expect(
      greenVpnShouldRefreshStandbyConfig(
        cachedAt: now.subtract(const Duration(hours: 5)),
        now: now,
      ),
      isFalse,
    );
    expect(
      greenVpnShouldRefreshStandbyConfig(
        cachedAt: now.subtract(const Duration(hours: 7)),
        now: now,
      ),
      isTrue,
    );
  });
}
