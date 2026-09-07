import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/transport_preview_policy.dart';

void main() {
  test('external VPN or unknown ownership forbids automatic takeover', () {
    for (final active in [false, true]) {
      for (final known in [false, true]) {
        expect(
          greenVpnShouldRecoverUnexpectedWindowsDisconnect(
            reportedConnected: false,
            vpnEnabled: true,
            monitorArmed: true,
            recoveryRunning: false,
            vpnBusy: false,
            externalVpnActive: active,
            externalVpnStateKnown: known,
          ),
          known && !active,
        );
      }
    }
  });

  test('no teardown without status, ownership and a proven alternative', () {
    for (final known in [false, true]) {
      for (final ownershipKnown in [false, true]) {
        for (final external in [false, true]) {
          for (final alternative in [false, true]) {
            for (final seconds in [0, 10, 29, 30, 120]) {
              expect(
                greenVpnCanBeginWindowsRuntimeRecovery(
                  statusKnown: known,
                  externalVpnStateKnown: ownershipKnown,
                  externalVpnActive: external,
                  hasProvenAlternative: alternative,
                  unhealthyFor: Duration(seconds: seconds),
                ),
                known &&
                    ownershipKnown &&
                    !external &&
                    alternative &&
                    seconds >= 30,
              );
            }
          }
        }
      }
    }
  });

  test('recovery never re-enables explicitly disabled VPN', () {
    expect(
      greenVpnShouldRecoverUnexpectedWindowsDisconnect(
        reportedConnected: false,
        vpnEnabled: false,
        monitorArmed: true,
        recoveryRunning: false,
        vpnBusy: false,
      ),
      isFalse,
    );
  });
}
