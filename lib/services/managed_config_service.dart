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
    'x': ['104.244.42.0/24', '185.45.5.0/24', '192.133.76.0/22'],
  };

  static const Map<String, List<String>> androidSocialPackageNames = {
    'telegram': [
      'org.telegram.messenger',
      'org.telegram.messenger.web',
      'org.thunderdog.challegram',
    ],
    'instagram': ['com.instagram.android'],
    'youtube': ['com.google.android.youtube'],
    'discord': ['com.discord'],
    'tiktok': ['com.zhiliaoapp.musically'],
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
      final baseAllowedIps = _readAllowedIps(original);
      allowedIps = baseAllowedIps.isEmpty
          ? const ['0.0.0.0/1', '128.0.0.0/1']
          : baseAllowedIps;
      updatedConfig = _removeInterfaceField(
        _removeInterfaceField(
          _replaceAllowedIps(original, allowedIps.join(', ')),
          'IncludedApplications',
        ),
        'ExcludedApplications',
      );
    } else if (Platform.isAndroid) {
      mode = 'social_only';
      final baseAllowedIps = _readAllowedIps(original);
      allowedIps = baseAllowedIps.isEmpty
          ? const ['0.0.0.0/1', '128.0.0.0/1']
          : baseAllowedIps;
      final packageNames = _resolveAndroidPackagesForApps(selectedApps);
      updatedConfig = _setInterfaceCsvField(
        _removeInterfaceField(
          _replaceAllowedIps(original, allowedIps.join(', ')),
          'ExcludedApplications',
        ),
        'IncludedApplications',
        packageNames,
      );
    } else {
      final resolvedIps = _resolveAllowedIpsForApps(selectedApps);
      mode = 'social_only';
      allowedIps = resolvedIps;
      updatedConfig = _replaceAllowedIps(original, resolvedIps.join(', '));
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
      // Не ломаем режим при пустом выборе: оставляем безопасный минимальный набор.
      return ['149.154.160.0/20'];
    }

    return result.toList()..sort();
  }

  List<String> _resolveAndroidPackagesForApps(List<String> apps) {
    final result = <String>{};
    for (final app in apps) {
      final normalized = app.trim().toLowerCase();
      final packages = androidSocialPackageNames[normalized];
      if (packages != null) {
        result.addAll(packages);
      }
    }
    if (result.isEmpty) {
      result.addAll(androidSocialPackageNames['telegram'] ?? const []);
    }
    return result.toList()..sort();
  }

  String _removeInterfaceField(String configText, String fieldName) {
    final escaped = RegExp.escape(fieldName);
    return configText.replaceAll(
      RegExp(
        r'^\s*' + escaped + r'\s*=.*(?:\r?\n)?',
        multiLine: true,
        caseSensitive: false,
      ),
      '',
    );
  }

  String _setInterfaceCsvField(
    String configText,
    String fieldName,
    List<String> values,
  ) {
    final cleaned = _removeInterfaceField(configText, fieldName);
    if (values.isEmpty) return cleaned;

    final lines = cleaned.split('\n');
    final interfaceIndex = lines.indexWhere(
      (line) => line.trim().toLowerCase() == '[interface]',
    );
    final fieldLine = '$fieldName = ${values.join(', ')}';
    if (interfaceIndex == -1) {
      return '$fieldLine\n$cleaned';
    }
    lines.insert(interfaceIndex + 1, fieldLine);
    return lines.join('\n');
  }

  String _replaceAllowedIps(String configText, String allowedIpsValue) {
    final regExp = RegExp(
      r'(^\s*AllowedIPs\s*=\s*.*$)',
      multiLine: true,
      caseSensitive: false,
    );

    if (regExp.hasMatch(configText)) {
      return configText.replaceFirst(regExp, 'AllowedIPs = $allowedIpsValue');
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

  List<String> _readAllowedIps(String configText) {
    final match = RegExp(
      r'^\s*AllowedIPs\s*=\s*(.+?)\s*$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(configText);
    final raw = match?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
