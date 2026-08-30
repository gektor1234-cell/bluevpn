import 'package:flutter_test/flutter_test.dart';

import 'package:greenvpn/services/android_connection_operation_policy.dart';

void main() {
  test('offline connect stays active with an explicit waiting state', () {
    final state = greenVpnAndroidConnectionUiState(<String, dynamic>{
      'desired': true,
      'state': 'waiting_for_network',
    });

    expect(state.busy, isTrue);
    expect(state.terminal, isFalse);
    expect(state.stage, 'Ожидаем сеть...');
  });

  test('disconnect remains busy until native cleanup is terminal', () {
    final state = greenVpnAndroidConnectionUiState(<String, dynamic>{
      'desired': false,
      'state': 'disconnecting',
    });

    expect(state.busy, isTrue);
    expect(state.terminal, isFalse);
  });

  test('competing VPN is terminal and cannot trigger automatic restore', () {
    final state = greenVpnAndroidConnectionUiState(<String, dynamic>{
      'desired': false,
      'state': 'competing_vpn_active',
    });

    expect(state.busy, isFalse);
    expect(state.terminal, isTrue);
  });
}
