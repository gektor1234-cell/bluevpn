import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/windows_selective_routing_service.dart';

void main() {
  final enabled = Platform.environment['GREENVPN_RUN_NETWORK_SMOKE'] == '1';
  test(
    'resolves user-facing site names to bounded selective routes',
    () async {
      final result = await resolveWindowsVpnSites(const [
        'vk.com',
        'youtube.com',
      ]);

      expect(result.unresolvedSites, isEmpty);
      expect(result.ipv4Cidrs, isNotEmpty);
      expect(result.ipv4Cidrs.every(isValidWindowsVpnDestinationCidr), isTrue);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
