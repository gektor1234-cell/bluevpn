import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/bluevpn_paths.dart';
import '../models/backend_models.dart';

class BackendSessionService {
  static Future<BackendSession?> load() async {
    await BlueVpnPaths.ensureDirs();

    final file = BlueVpnPaths.backendSessionFile;
    if (!await file.exists()) {
      return null;
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }

    final session = BackendSession.fromJson(
      Map<String, dynamic>.from(decoded),
    );

    if (session.apiBaseUrl.isEmpty ||
        session.email.isEmpty ||
        session.token.isEmpty ||
        session.deviceUid.isEmpty) {
      return null;
    }

    return session;
  }

  static Future<void> save(BackendSession session) async {
    await BlueVpnPaths.ensureDirs();

    final encoder = const JsonEncoder.withIndent('  ');
    await BlueVpnPaths.backendSessionFile.writeAsString(
      encoder.convert(session.toJson()),
    );
  }

  static Future<void> clear() async {
    final file = BlueVpnPaths.backendSessionFile;
    if (await file.exists()) {
      await file.delete();
    }
  }

  static String generateDeviceUid() {
    const alphabet = '0123456789abcdef';
    final random = Random.secure();

    final suffix = List.generate(
      32,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();

    return 'win_$suffix';
  }
}
