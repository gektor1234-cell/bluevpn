import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/windows_selective_routing_service.dart';

void main() {
  test(
    'discovers launchable Windows programs by user-facing names',
    () async {
      final apps = await listWindowsLaunchableApps();

      expect(apps, isNotEmpty);
      expect(
        apps.map((app) => app.path.toLowerCase()).toSet(),
        hasLength(apps.length),
      );
      expect(apps.every((app) => app.label.trim().isNotEmpty), isTrue);
      expect(apps.every((app) => File(app.path).existsSync()), isTrue);
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
