import 'dart:io';

class ManagedConfigBuildResult {
  final String managedConfigPath;
  final String mode; // full_tunnel | social_only
  final List<String> allowedIps;

  const ManagedConfigBuildResult({
    required this.managedConfigPath,
    required this.mode,
    required this.allowedIps,
  });
}

class ManagedConfigService {
  final String baseConfigPath;
  final String managedConfigPath;

  ManagedConfigService({
    required this.baseConfigPath,
    required this.managedConfigPath,
  });

  static const Map<String, List<String>> socialAppAllowedIps = {
    'telegram': [
      '149.154.160.0/20',
      '91.108.4.0/22',
      '91.108.8.0/22',
      '91.108.12.0/22',
      '91.108.16.0/22',
      '91.108.56.0/22',
    ],
    'youtube': [
      '142.250.0.0/15',
      '172.217.0.0/16',
      '142.251.0.0/16',
      '74.125.0.0/16',
    ],
    'instagram': [
      '31.13.24.0/21',
      '31.13.64.0/18',
      '66.220.144.0/20',
      '69.63.176.0/20',
      '157.240.0.0/16',
    ],
    'facebook': [
      '31.13.24.0/21',
      '31.13.64.0/18',
      '66.220.144.0/20',
      '69.63.176.0/20',
      '157.240.0.0/16',
    ],
    'x': [
      '104.244.42.0/24',
      '185.45.5.0/24',
      '192.133.76.0/22',
    ],
  };

  Future<ManagedConfigBuildResult> buildManagedConfig({
    required bool socialOnlyEnabled,
    required List<String> selectedApps,
  }) async {
    final baseFile = File(baseConfigPath);

    if (!baseFile.existsSync()) {
      throw Exception('Base config not found: $baseConfigPath');
    }

    final original = await baseFile.readAsString();

    late final String mode;
    late final List<String> allowedIps;
    late final String updatedConfig;

    if (!socialOnlyEnabled) {
      mode = 'full_tunnel';
      allowedIps = const ['0.0.0.0/0', '::/0'];
      updatedConfig = _replaceAllowedIps(
        original,
        allowedIps.join(', '),
      );
    } else {
      final resolvedIps = _resolveAllowedIpsForApps(selectedApps);
      mode = 'social_only';
      allowedIps = resolvedIps;
      updatedConfig = _replaceAllowedIps(
        original,
        resolvedIps.join(', '),
      );
    }

    final outFile = File(managedConfigPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsString(updatedConfig);

    return ManagedConfigBuildResult(
      managedConfigPath: managedConfigPath,
      mode: mode,
      allowedIps: allowedIps,
    );
  }

  List<String> _resolveAllowedIpsForApps(List<String> apps) {
    final result = <String>{};

    for (final app in apps) {
      final normalized = app.trim().toLowerCase();
      final ranges = socialAppAllowedIps[normalized];
      if (ranges != null) {
        result.addAll(ranges);
      }
    }

    if (result.isEmpty) {
      // С‡С‚РѕР±С‹ СЂРµР¶РёРј РЅРµ Р»РѕРјР°Р»СЃСЏ РїСЂРё РїСѓСЃС‚РѕРј РІС‹Р±РѕСЂРµ
      return ['149.154.160.0/20']; // fallback РЅР° telegram range
    }

    return result.toList()..sort();
  }

  String _replaceAllowedIps(String configText, String allowedIpsValue) {
    final regExp = RegExp(
      r'(^\s*AllowedIPs\s*=\s*.*$)',
      multiLine: true,
      caseSensitive: false,
    );

    if (regExp.hasMatch(configText)) {
      return configText.replaceFirst(
        regExp,
        'AllowedIPs = $allowedIpsValue',
      );
    }

    final lines = configText.split('\n');
    final peerIndex = lines.indexWhere(
      (line) => line.trim().toLowerCase() == '[peer]',
    );

    if (peerIndex == -1) {
      throw Exception('Invalid WireGuard config: [Peer] section not found.');
    }

    lines.insert(peerIndex + 1, 'AllowedIPs = $allowedIpsValue');
    return lines.join('\n');
  }
}
