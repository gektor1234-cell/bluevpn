import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/windows_vpn_status_policy.dart';

const Map<String, dynamic> _stableRuntimeState = <String, dynamic>{
  'runtimeStateGenerationKnown': true,
  'runtimeStateGeneration': 2,
  'runtimeStateConsistent': true,
};

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

  test('routing mode is authoritative only for authenticated status', () {
    expect(
      greenVpnClassifyWindowsRoutingMode(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          ..._stableRuntimeState,
          'routingMode': 'applications',
        },
      ),
      GreenVpnWindowsRoutingMode.applications,
    );
    expect(
      greenVpnClassifyWindowsRoutingMode(
        requestOk: false,
        data: const <String, dynamic>{'routingMode': 'full'},
      ),
      GreenVpnWindowsRoutingMode.unknown,
    );
  });

  test('full mode requires a running tunnel and exact service mode', () {
    expect(
      greenVpnWindowsRoutingModeIsConfirmed(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          ..._stableRuntimeState,
          'wireGuardState': 'running',
          'routingMode': 'full',
          'externalVpnStateKnown': true,
          'processRouterRequirementKnown': true,
        },
        applicationsOnly: false,
        processRouterRequired: false,
      ),
      isTrue,
    );
    expect(
      greenVpnWindowsRoutingModeIsConfirmed(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          ..._stableRuntimeState,
          'wireGuardState': 'running',
          'routingMode': 'applications',
          'externalVpnStateKnown': true,
          'processRouterRequirementKnown': true,
        },
        applicationsOnly: false,
        processRouterRequired: false,
      ),
      isFalse,
    );
    expect(
      greenVpnWindowsRoutingModeIsConfirmed(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          ..._stableRuntimeState,
          'wireGuardState': 'running',
          'routingMode': 'full',
          'processRouterState': 'running',
          'processRouterRequired': true,
          'externalVpnStateKnown': true,
          'processRouterRequirementKnown': true,
        },
        applicationsOnly: false,
        processRouterRequired: true,
      ),
      isFalse,
    );
  });

  test('requested process-router requirement must match privileged state', () {
    expect(
      greenVpnWindowsRoutingModeIsConfirmed(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          ..._stableRuntimeState,
          'wireGuardState': 'running',
          'routingMode': 'applications',
          'processRouterState': 'running',
          'processRouterRequired': false,
          'processRouterRequirementKnown': true,
          'externalVpnStateKnown': true,
        },
        applicationsOnly: true,
        processRouterRequired: true,
      ),
      isFalse,
    );
  });

  test('a stale process router cannot be reported as full protection', () {
    const data = <String, dynamic>{
      'ok': true,
      ..._stableRuntimeState,
      'wireGuardState': 'running',
      'routingMode': 'full',
      'processRouterState': 'running',
      'processRouterRequired': false,
      'processRouterRequirementKnown': true,
      'externalVpnStateKnown': true,
    };
    expect(
      greenVpnWindowsRoutingModeIsConfirmed(
        requestOk: true,
        data: data,
        applicationsOnly: false,
        processRouterRequired: false,
      ),
      isFalse,
    );
    expect(
      greenVpnAuthoritativeActiveRoutingMode(
        requestOk: true,
        data: data,
        processRouterRequired: false,
      ),
      isNull,
    );
  });

  test(
    'authoritative mode rejects a caller and privileged requirement mismatch',
    () {
      expect(
        greenVpnAuthoritativeActiveRoutingMode(
          requestOk: true,
          data: const <String, dynamic>{
            'ok': true,
            ..._stableRuntimeState,
            'wireGuardState': 'running',
            'routingMode': 'applications',
            'processRouterState': 'running',
            'processRouterRequired': true,
            'processRouterRequirementKnown': true,
            'externalVpnStateKnown': true,
          },
          processRouterRequired: false,
        ),
        isNull,
      );
    },
  );

  test('application mode also confirms the required process router', () {
    expect(
      greenVpnWindowsRoutingModeIsConfirmed(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          ..._stableRuntimeState,
          'wireGuardState': 'running',
          'routingMode': 'applications',
          'processRouterState': 'running',
          'processRouterRequired': true,
          'externalVpnStateKnown': true,
          'processRouterRequirementKnown': true,
        },
        applicationsOnly: true,
        processRouterRequired: true,
      ),
      isTrue,
    );
    expect(
      greenVpnWindowsRoutingModeIsConfirmed(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          ..._stableRuntimeState,
          'wireGuardState': 'running',
          'routingMode': 'applications',
          'processRouterState': 'missing',
          'externalVpnStateKnown': true,
          'processRouterRequirementKnown': true,
        },
        applicationsOnly: true,
        processRouterRequired: true,
      ),
      isFalse,
    );
    expect(
      greenVpnWindowsRoutingModeIsConfirmed(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          ..._stableRuntimeState,
          'wireGuardState': 'running',
          'routingMode': 'applications',
          'processRouterState': 'missing',
          'externalVpnStateKnown': true,
          'processRouterRequirementKnown': true,
        },
        applicationsOnly: true,
        processRouterRequired: false,
      ),
      isTrue,
    );
  });

  test('a competing VPN prevents Green VPN confirmation', () {
    const data = <String, dynamic>{
      'ok': true,
      ..._stableRuntimeState,
      'wireGuardState': 'running',
      'routingMode': 'full',
      'externalVpnActive': true,
      'externalVpnStateKnown': true,
      'processRouterRequirementKnown': true,
    };
    expect(
      greenVpnWindowsRoutingModeIsConfirmed(
        requestOk: true,
        data: data,
        applicationsOnly: false,
        processRouterRequired: false,
      ),
      isFalse,
    );
    expect(
      greenVpnAuthoritativeActiveRoutingMode(
        requestOk: true,
        data: data,
        processRouterRequired: false,
      ),
      isNull,
    );
  });

  test('unknown competing VPN state fails closed', () {
    const data = <String, dynamic>{
      'ok': true,
      ..._stableRuntimeState,
      'wireGuardState': 'running',
      'routingMode': 'full',
      'externalVpnActive': false,
      'externalVpnStateKnown': false,
      'processRouterRequirementKnown': true,
    };
    expect(
      greenVpnWindowsRoutingModeIsConfirmed(
        requestOk: true,
        data: data,
        applicationsOnly: false,
        processRouterRequired: false,
      ),
      isFalse,
    );
    expect(
      greenVpnAuthoritativeActiveRoutingMode(
        requestOk: true,
        data: data,
        processRouterRequired: false,
      ),
      isNull,
    );
  });

  test('only an active, complete tunnel can override UI mode', () {
    expect(
      greenVpnAuthoritativeActiveRoutingMode(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          'wireGuardState': 'missing',
          'routingMode': 'applications',
        },
        processRouterRequired: true,
      ),
      isNull,
    );
    expect(
      greenVpnAuthoritativeActiveRoutingMode(
        requestOk: true,
        data: const <String, dynamic>{
          'ok': true,
          ..._stableRuntimeState,
          'wireGuardState': 'running',
          'routingMode': 'applications',
          'processRouterState': 'running',
          'processRouterRequired': true,
          'externalVpnStateKnown': true,
          'processRouterRequirementKnown': true,
        },
        processRouterRequired: true,
      ),
      GreenVpnWindowsRoutingMode.applications,
    );
  });

  test('unknown process-router requirement fails closed', () {
    const data = <String, dynamic>{
      'ok': true,
      ..._stableRuntimeState,
      'wireGuardState': 'running',
      'routingMode': 'full',
      'externalVpnActive': false,
      'externalVpnStateKnown': true,
    };
    expect(
      greenVpnWindowsRoutingModeIsConfirmed(
        requestOk: true,
        data: data,
        applicationsOnly: false,
        processRouterRequired: false,
      ),
      isFalse,
    );
    expect(
      greenVpnAuthoritativeActiveRoutingMode(
        requestOk: true,
        data: data,
        processRouterRequired: false,
      ),
      isNull,
    );
  });

  test('full UI protection also requires a fresh data-plane proof', () {
    expect(
      greenVpnWindowsUiProtectionIsConfirmed(
        systemStateConfirmed: true,
        routingMode: GreenVpnWindowsRoutingMode.full,
        fullTunnelDataPlaneConfirmed: false,
      ),
      isFalse,
    );
    expect(
      greenVpnWindowsUiProtectionIsConfirmed(
        systemStateConfirmed: true,
        routingMode: GreenVpnWindowsRoutingMode.full,
        fullTunnelDataPlaneConfirmed: true,
      ),
      isTrue,
    );
    expect(
      greenVpnWindowsUiProtectionIsConfirmed(
        systemStateConfirmed: true,
        routingMode: GreenVpnWindowsRoutingMode.applications,
        fullTunnelDataPlaneConfirmed: false,
      ),
      isTrue,
    );
    expect(
      greenVpnWindowsUiProtectionIsConfirmed(
        systemStateConfirmed: false,
        routingMode: GreenVpnWindowsRoutingMode.applications,
        fullTunnelDataPlaneConfirmed: true,
      ),
      isFalse,
    );
  });

  test('routing mode rejects missing, odd, and mixed runtime snapshots', () {
    for (final data in const <Map<String, dynamic>>[
      <String, dynamic>{'ok': true, 'routingMode': 'full'},
      <String, dynamic>{
        'ok': true,
        'routingMode': 'full',
        'runtimeStateGenerationKnown': true,
        'runtimeStateGeneration': 3,
        'runtimeStateConsistent': true,
      },
      <String, dynamic>{
        'ok': true,
        'routingMode': 'full',
        'runtimeStateGenerationKnown': true,
        'runtimeStateGeneration': 4,
        'runtimeStateConsistent': false,
      },
    ]) {
      expect(
        greenVpnClassifyWindowsRoutingMode(requestOk: true, data: data),
        GreenVpnWindowsRoutingMode.unknown,
      );
    }
  });
}
