import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/transport_preview_policy.dart';

void main() {
  test('transport cascade has one strict first-to-last order', () {
    expect(greenVpnTransportPreviewCascade, const <String>[
      'wireguard_udp',
      'amneziawg',
      'hysteria2',
      'vless_reality',
      'naive_https',
      'dnstt',
    ]);
    expect(
      greenVpnTransportPreviewCascade.toSet().length,
      greenVpnTransportPreviewCascade.length,
    );
  });
}
