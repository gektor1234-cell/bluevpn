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
}
