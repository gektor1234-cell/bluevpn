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
}
