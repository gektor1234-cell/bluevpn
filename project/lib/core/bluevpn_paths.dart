import 'dart:io';

class BlueVpnPaths {
  static const String tunnelName = 'BlueVPN';

  static Directory get roamingDir {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return Directory('$appData\\BlueVPN');
    }

    final userProfile =
        Platform.environment['USERPROFILE'] ?? Directory.current.path;
    return Directory('$userProfile\\AppData\\Roaming\\BlueVPN');
  }

  static Directory get programDataDir => Directory(r'C:\ProgramData\BlueVPN');

  static File get backendSessionFile =>
      File('${roamingDir.path}\\backend_session.json');

  static File get managedConfigFile =>
      File('${programDataDir.path}\\$tunnelName.conf');

  static String get wireguardExe => r'C:\Program Files\WireGuard\wireguard.exe';
  static String get wgExe => r'C:\Program Files\WireGuard\wg.exe';

  static String get serviceName => 'WireGuardTunnel\$' + tunnelName;

  static Future<void> ensureDirs() async {
    if (!await roamingDir.exists()) {
      await roamingDir.create(recursive: true);
    }
    if (!await programDataDir.exists()) {
      await programDataDir.create(recursive: true);
    }
  }
}
