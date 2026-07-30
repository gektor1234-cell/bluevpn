import 'dart:io';

import 'package:greenvpn/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Windows full tunnel uses routes that enable the native kill switch',
    () {
      expect(
        resolveFullTunnelAllowedIps(const [
          '0.0.0.0/1',
          '128.0.0.0/1',
        ], windows: true),
        const ['0.0.0.0/0', '::/0'],
      );
    },
  );

  test('non-Windows clients keep server-provided full-tunnel routes', () {
    expect(
      resolveFullTunnelAllowedIps(const [
        '0.0.0.0/1',
        '128.0.0.0/1',
      ], windows: false),
      const ['0.0.0.0/1', '128.0.0.0/1'],
    );
  });

  test('WireGuard endpoint hostname is pinned to resolved IPv4', () async {
    const config = '''
[Interface]
PrivateKey = test-private-key

[Peer]
Endpoint = nl2.vpn.greenvpn.pro:443
AllowedIPs = 0.0.0.0/0
''';

    final prepared = await resolveWireGuardEndpointToIpv4(
      config,
      lookup: (host) async {
        expect(host, 'nl2.vpn.greenvpn.pro');
        return [InternetAddress('5.129.216.42')];
      },
    );

    expect(prepared, contains('Endpoint = 5.129.216.42:443'));
    expect(prepared, contains('PrivateKey = test-private-key'));
  });

  test('known IPv4 fallback avoids DNS on the fast path', () async {
    const config = '''
[Peer]
Endpoint = nl2.vpn.greenvpn.pro:443
''';
    var lookupCalled = false;

    final prepared = await resolveWireGuardEndpointToIpv4(
      config,
      fallbackIpv4: '5.129.216.42',
      lookup: (_) async {
        lookupCalled = true;
        return const [];
      },
    );

    expect(lookupCalled, isFalse);
    expect(prepared, contains('Endpoint = 5.129.216.42:443'));
  });

  test('literal IPv4 endpoint remains byte-for-byte unchanged', () async {
    const config = '''
[Peer]
Endpoint = 37.220.85.211:443
''';

    final prepared = await resolveWireGuardEndpointToIpv4(
      config,
      lookup: (_) async => throw StateError('lookup must not run'),
    );

    expect(prepared, config);
  });
}
