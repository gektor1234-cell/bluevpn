import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  test('saved sessions open directly on supported native clients', () {
    expect(
      greenVpnShouldOpenSavedSessionDirectly(
        hasSession: true,
        isWeb: false,
        isAndroid: true,
        isWindows: false,
      ),
      isTrue,
    );
    expect(
      greenVpnShouldOpenSavedSessionDirectly(
        hasSession: true,
        isWeb: false,
        isAndroid: false,
        isWindows: true,
      ),
      isTrue,
    );
  });

  test('session gate remains for web and missing sessions', () {
    expect(
      greenVpnShouldOpenSavedSessionDirectly(
        hasSession: true,
        isWeb: true,
        isAndroid: false,
        isWindows: false,
      ),
      isFalse,
    );
    expect(
      greenVpnShouldOpenSavedSessionDirectly(
        hasSession: false,
        isWeb: false,
        isAndroid: false,
        isWindows: true,
      ),
      isFalse,
    );
  });

  test('only automatically replaced devices rotate their local identity', () {
    expect(
      greenVpnShouldRotateAutoReplacedDevice(<String, dynamic>{
        'reason': 'device_disabled',
        'device': <String, dynamic>{
          'isEnabled': false,
          'disabledReason': 'auto_replaced_by_new_device',
        },
      }),
      isTrue,
    );
    expect(
      greenVpnShouldRotateAutoReplacedDevice(<String, dynamic>{
        'reason': 'device_disabled',
        'device': <String, dynamic>{
          'isEnabled': false,
          'disabledReason': 'disabled_by_admin',
        },
      }),
      isFalse,
    );
    expect(
      greenVpnShouldRotateAutoReplacedDevice(<String, dynamic>{
        'reason': 'device_limit_exceeded',
      }),
      isFalse,
    );
  });
}
