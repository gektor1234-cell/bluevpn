import 'dart:io';

class ConfigService {
  static const String configPath = r'C:\ProgramData\BlueVPN\BlueVPN.conf';

  static Future<bool> exists() async => File(configPath).exists();

  static Future<String> readConfig() async {
    final f = File(configPath);
    if (!await f.exists()) {
      throw Exception('Config not found: $configPath');
    }
    return f.readAsString();
  }

  // Импорт нового .conf в ProgramData.
  // Если права не позволят — UI покажет ошибку.
  static Future<void> replaceConfigFromPath(String sourcePath) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw Exception('Source not found: $sourcePath');
    }
    final dst = File(configPath);
    await dst.parent.create(recursive: true);
    await src.copy(dst.path);
  }
}
