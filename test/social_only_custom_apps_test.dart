import 'package:greenvpn/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom Android packages survive prefs round trip', () {
    final original = Prefs.defaults().copyWith(
      socialOnlyCustomPackages: const ['com.android.chrome'],
    );

    final restored = Prefs.fromJson(original.toJson());

    expect(restored.socialOnlyCustomPackages, const ['com.android.chrome']);
  });

  test('legacy prefs default to no custom Android packages', () {
    final restored = Prefs.fromJson({
      'socialOnlyEnabled': true,
      'socialOnlyApps': ['youtube'],
    });

    expect(restored.socialOnlyCustomPackages, isEmpty);
    expect(restored.socialOnlyApps, const ['youtube']);
  });

  test('Windows application paths survive prefs round trip', () {
    final original = Prefs.defaults().copyWith(
      socialOnlyWindowsApplications: const [
        r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      ],
    );

    final restored = Prefs.fromJson(original.toJson());

    expect(restored.socialOnlyWindowsApplications, const [
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    ]);
  });

  test('legacy prefs default to no Windows applications', () {
    final restored = Prefs.fromJson({
      'socialOnlyEnabled': true,
      'socialOnlyApps': ['youtube'],
    });

    expect(restored.socialOnlyWindowsApplications, isEmpty);
  });

  test('Windows sites survive prefs round trip', () {
    final original = Prefs.defaults().copyWith(
      socialOnlyWindowsSites: const ['vk.com', 'youtube.com'],
    );

    final restored = Prefs.fromJson(original.toJson());

    expect(restored.socialOnlyWindowsSites, const ['vk.com', 'youtube.com']);
  });

  test('legacy prefs default to no Windows sites', () {
    final restored = Prefs.fromJson({
      'socialOnlyEnabled': true,
      'socialOnlyApps': ['telegram'],
    });

    expect(restored.socialOnlyWindowsSites, isEmpty);
  });
}
