import 'package:greenvpn/services/transport_preview_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview cascade keeps the guarded transport order', () {
    expect(greenVpnTransportPreviewCascade, const <String>[
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

    expect(shuffled, <String>[
      ...greenVpnTransportPreviewCascade,
      'wireguard_udp',
    ]);
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
        serverIsAuto: false,
        socialOnlyEnabled: false,
      ),
      isTrue,
    );
    expect(
      greenVpnShouldArmRuntimeFailover(
        previewEnabled: true,
        isAndroid: true,
        serverIsAuto: false,
        socialOnlyEnabled: true,
      ),
      isFalse,
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
      'hysteria2',
      'vless_reality',
      'naive_https',
      'dnstt',
      'wireguard_udp',
      'amneziawg',
    ]);
  });
}
