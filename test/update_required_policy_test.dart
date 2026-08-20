import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

GreenVpnUpdateManifest manifest({required bool required}) {
  return GreenVpnUpdateManifest(
    platform: 'windows',
    currentVersion: '0.3.26+3105',
    latestVersion: '0.4.6+4636',
    downloadUrl: 'https://greenvpn.pro/downloads/GreenVPN_Setup.exe',
    sha256: 'A' * 64,
    required: required,
    updateAvailable: true,
    baseUpdateAvailable: true,
    rolloutEligible: true,
    rolloutPercent: 100,
    rolloutReason: 'required',
    changelog: const ['Обязательное обновление'],
    releasedAt: '2026-08-20T00:00:00Z',
  );
}

void main() {
  test('required update prompt cannot be dismissed', () {
    expect(
      greenVpnUpdatePromptCanBeDismissed(manifest(required: true)),
      isFalse,
    );
  });

  test('optional update prompt remains dismissible', () {
    expect(
      greenVpnUpdatePromptCanBeDismissed(manifest(required: false)),
      isTrue,
    );
  });
}
