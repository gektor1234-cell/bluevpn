import 'package:bluevpn_ui/services/transport_preview_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview cascade keeps the guarded transport order', () {
    expect(
      greenVpnTransportPreviewCascade,
      const <String>[
        'amneziawg',
        'hysteria2',
        'vless_reality',
        'naive_https',
        'dnstt',
      ],
    );

    final shuffled = <String>[
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
}
