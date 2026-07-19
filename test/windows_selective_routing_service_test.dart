import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/windows_selective_routing_service.dart';

void main() {
  group('Windows selective routing input', () {
    test('normalizes a pasted site URL', () {
      expect(
        normalizeWindowsVpnSite(' https://www.VK.com/video/123 '),
        'vk.com',
      );
      expect(normalizeWindowsVpnSite('youtube.com/watch?v=1'), 'youtube.com');
    });

    test('rejects local and malformed sites', () {
      expect(normalizeWindowsVpnSite('localhost'), isNull);
      expect(normalizeWindowsVpnSite('http://127.0.0.1/admin'), isNull);
      expect(normalizeWindowsVpnSite('not a site'), isNull);
    });

    test(
      'validates executable paths without requiring technical UI labels',
      () {
        const path = r'C:\Program Files\Google\Chrome\Application\chrome.exe';
        expect(isValidWindowsApplicationPath(path), isTrue);
        expect(windowsApplicationLabel(path), 'chrome');
        expect(isValidWindowsApplicationPath(r'C:\Temp\notes.txt'), isFalse);
      },
    );

    test('accepts bounded public IPv4 routes only', () {
      expect(isValidWindowsVpnDestinationCidr('149.154.160.0/20'), isTrue);
      expect(isValidWindowsVpnDestinationCidr('142.250.1.10/32'), isTrue);
      expect(isValidWindowsVpnDestinationCidr('0.0.0.0/0'), isFalse);
      expect(isValidWindowsVpnDestinationCidr('10.0.0.0/8'), isFalse);
      expect(isValidWindowsVpnDestinationCidr('192.168.1.1/32'), isFalse);
    });

    test('parses a discovered app and supplies a fallback label', () {
      final app = WindowsLaunchableApp.fromJson({
        'path': r'C:\Apps\Telegram\Telegram.exe',
        'label': '',
      });

      expect(app, isNotNull);
      expect(app!.label, 'Telegram');
      expect(app.path, r'C:\Apps\Telegram\Telegram.exe');
    });
  });
}
