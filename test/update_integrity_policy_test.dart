import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  Map<String, dynamic> fixture() => {
    'platform': 'windows',
    'currentVersion': '0.4.10+4643',
    'latestVersion': '0.4.11',
    'buildNumber': 4644,
    'downloadUrl': 'https://greenvpn.pro/downloads/GreenVPN_Setup.exe',
    'sha256': 'a' * 64,
    'sizeBytes': 100,
    'fileReady': true,
    'updateAvailable': true,
    'required': true,
  };
  test('strict metadata required for a trusted download', () {
    expect(GreenVpnUpdateManifest.fromJson(fixture()).canDownload, isTrue);
    for (final key in ['sha256', 'sizeBytes', 'fileReady']) {
      final json = fixture()..remove(key);
      expect(
        GreenVpnUpdateManifest.fromJson(json).canDownload,
        isFalse,
        reason: key,
      );
    }
    for (final url in [
      'http://greenvpn.pro/file.exe',
      'https://greenvpn.pro.attacker.test/file.exe',
      Uri(
        scheme: 'https',
        userInfo: ['user', 'pass'].join(':'),
        host: 'greenvpn.pro',
        path: '/file.exe',
      ).toString(),
      'https://greenvpn.pro:444/file.exe',
    ]) {
      expect(
        GreenVpnUpdateManifest.fromJson(
          fixture()..['downloadUrl'] = url,
        ).canDownload,
        isFalse,
      );
    }
  });
  test('same version requires a known newer build', () {
    final json = fixture()..['latestVersion'] = '0.4.10';
    expect(GreenVpnUpdateManifest.fromJson(json).hasUpdate, isTrue);
    json['buildNumber'] = 4643;
    expect(GreenVpnUpdateManifest.fromJson(json).hasUpdate, isFalse);
    json['currentVersion'] = '0.4.10';
    json['buildNumber'] = 9999;
    expect(GreenVpnUpdateManifest.fromJson(json).hasUpdate, isFalse);
  });
  test(
    'downgrade and malformed versions cannot become updates via server flag',
    () {
      for (final version in ['0.4.9', '0.4.10+4642', 'garbage', '']) {
        final json = fixture()
          ..['latestVersion'] = version
          ..['buildNumber'] = '';
        expect(
          GreenVpnUpdateManifest.fromJson(json).hasUpdate,
          isFalse,
          reason: version,
        );
      }
      expect(GreenVpnUpdateManifest.fromJson(fixture()).hasUpdate, isTrue);
    },
  );
}
