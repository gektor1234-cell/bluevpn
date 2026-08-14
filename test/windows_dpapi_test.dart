import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/windows_dpapi.dart';

void main() {
  test('Windows DPAPI round trips without a PowerShell child process', () {
    if (!Platform.isWindows) return;

    const plain = '{"session":"owner","version":1}';
    final encrypted = WindowsDpapi.protectString(plain);

    expect(encrypted, isNotNull);
    expect(encrypted, isNot(contains(plain)));
    expect(WindowsDpapi.unprotectString(encrypted!), plain);
  });

  test('Windows DPAPI rejects malformed protected data', () {
    if (!Platform.isWindows) return;

    expect(WindowsDpapi.unprotectString('not-dpapi-data'), isNull);
  });

  test('Windows DPAPI reads an optional existing encrypted session', () {
    if (!Platform.isWindows) return;
    final fixturePath = Platform.environment['GREENVPN_DPAPI_FIXTURE_PATH'];
    if (fixturePath == null || fixturePath.trim().isEmpty) return;

    final encrypted = File(fixturePath).readAsStringSync();
    final plain = WindowsDpapi.unprotectString(encrypted);
    expect(plain, isNotNull);

    final session = jsonDecode(plain!) as Map<String, dynamic>;
    expect((session['accessToken'] ?? '').toString(), isNotEmpty);
  });
}
