import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/windows_vpn_status_policy.dart';

void main() {
  test('privileged running status remains authoritative for Windows UI', () {
    expect(
      greenVpnClassifyWindowsManagedTunnelStatus(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          'protocol': 'wireguard_udp',
          'tunnelState': 'running',
          'wireGuardState': 'running',
          'amneziaWgState': 'stopped',
        },
      ),
      GreenVpnWindowsManagedTunnelState.connected,
    );
  });

  test('each complete managed transport can own the connection', () {
    for (final data in const <Map<String, dynamic>>[
      <String, dynamic>{'ok': true, 'amneziaWgState': 'running'},
      <String, dynamic>{
        'ok': true,
        'hysteriaClientState': 'running',
        'hysteriaTunState': 'running',
      },
      <String, dynamic>{
        'ok': true,
        'vlessClientState': 'running',
        'vlessTunState': 'running',
      },
      <String, dynamic>{
        'ok': true,
        'naiveClientState': 'running',
        'naiveTunState': 'running',
      },
      <String, dynamic>{
        'ok': true,
        'dnsttClientState': 'running',
        'dnsttTunState': 'running',
      },
    ]) {
      expect(
        greenVpnClassifyWindowsManagedTunnelStatus(requestOk: true, data: data),
        GreenVpnWindowsManagedTunnelState.connected,
      );
    }
  });

  test('all stopped managed components are authoritatively disconnected', () {
    expect(
      greenVpnClassifyWindowsManagedTunnelStatus(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          'tunnelState': 'stopped',
          'wireGuardState': 'stopped',
          'amneziaWgState': 'missing',
          'hysteriaClientState': 'missing',
          'hysteriaTunState': 'missing',
          'vlessClientState': 'missing',
          'vlessTunState': 'missing',
          'naiveClientState': 'missing',
          'naiveTunState': 'missing',
          'dnsttClientState': 'missing',
          'dnsttTunState': 'missing',
        },
      ),
      GreenVpnWindowsManagedTunnelState.disconnected,
    );
  });

  test('transient and unauthenticated snapshots never claim disconnected', () {
    expect(
      greenVpnClassifyWindowsManagedTunnelStatus(
        requestOk: false,
        data: const <String, dynamic>{},
      ),
      GreenVpnWindowsManagedTunnelState.unknown,
    );
    expect(
      greenVpnClassifyWindowsManagedTunnelStatus(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          'tunnelState': 'start_pending',
          'wireGuardState': 'start_pending',
        },
      ),
      GreenVpnWindowsManagedTunnelState.unknown,
    );
    expect(
      greenVpnClassifyWindowsManagedTunnelStatus(
        requestOk: true,
        data: const <String, dynamic>{'ok': true},
      ),
      GreenVpnWindowsManagedTunnelState.unknown,
    );
  });

  test('one orphaned proxy process is unknown rather than connected', () {
    expect(
      greenVpnClassifyWindowsManagedTunnelStatus(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          'tunnelState': 'stopped',
          'hysteriaClientState': 'running',
          'hysteriaTunState': 'stopped',
        },
      ),
      GreenVpnWindowsManagedTunnelState.unknown,
    );
  });
}
