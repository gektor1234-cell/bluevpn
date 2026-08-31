import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/windows_support_diagnostics.dart';

void main() {
  group('Windows support diagnostics redaction', () {
    test('removes secret-bearing lines', () {
      expect(
        sanitizeWindowsSupportText('PrivateKey = abcdef123456'),
        '<redacted sensitive line>',
      );
      expect(
        sanitizeWindowsSupportText('Authorization: Bearer secret-token-value'),
        '<redacted sensitive line>',
      );
    });

    test('redacts identity while retaining operational markers', () {
      final text = sanitizeWindowsSupportText(
        r'connect phase=standby-cleanup-failed user=C:\Users\Valentin '
        'email=person@example.com exit=2',
      );
      expect(text, contains('connect phase=standby-cleanup-failed'));
      expect(text, contains('exit=2'));
      expect(text, contains(r'C:\Users\<redacted>'));
      expect(text, contains('<redacted email>'));
      expect(text, isNot(contains('Valentin')));
      expect(text, isNot(contains('person@example.com')));
    });

    test('redacts nested values with sensitive keys', () {
      final sanitized =
          sanitizeWindowsSupportValue(<String, Object?>{
                'token': 'top-secret',
                'stage': 'connect',
                'nested': <String, Object?>{'password': 'hidden'},
              })
              as Map<String, Object?>;
      expect(sanitized['token'], '<redacted>');
      expect(sanitized['stage'], 'connect');
      expect(
        (sanitized['nested'] as Map<String, Object?>)['password'],
        '<redacted>',
      );
    });

    test('retains numeric tunnel telemetry without keys or endpoint data', () {
      final sanitized =
          sanitizeWindowsSupportValue(<String, Object?>{
                'peerCount': 1,
                'latestHandshakeEpoch': 123456789,
                'receivedBytes': 2048,
                'sentBytes': 4096,
                'rawKeysStored': false,
                'rawEndpointStored': false,
              })
              as Map<String, Object?>;
      expect(sanitized['peerCount'], 1);
      expect(sanitized['latestHandshakeEpoch'], 123456789);
      expect(sanitized['receivedBytes'], 2048);
      expect(sanitized['sentBytes'], 4096);
      expect(sanitized['rawKeysStored'], isFalse);
      expect(sanitized['rawEndpointStored'], isFalse);
    });
  });

  test('log tails are bounded and individual lines are truncated', () {
    final lines = sanitizeWindowsSupportLogLines(<String>[
      'old',
      '',
      'middle',
      'x' * 900,
    ], maxLines: 2);
    expect(lines, hasLength(2));
    expect(lines.first, 'middle');
    expect(lines.last.length, lessThanOrEqualTo(711));
    expect(lines.last, endsWith('<truncated>'));
  });
}
