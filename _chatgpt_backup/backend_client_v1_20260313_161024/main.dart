// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/*
  BlueVPN — режим "как пользовательский продукт":
  - Первый запуск: регистрация/вход (через сервер)
  - Дальше: авто-вход по сохранённой сессии
  - Пользователь НЕ видит: конфиги/папки/импорт/экспорт/профили
  - Конфиг выдаёт сервер (provision), хранится внутри AppData (скрыто)

  ВАЖНО: в VPN-экране НЕТ карточки "Профиль" (дырка закрыта).
*/

const String kTunnelName = 'BlueVPN';

// TODO: поставь реальный URL API твоего сервера (без / в конце).
const String kApiBaseUrl = String.fromEnvironment(
  'BLUEVPN_API_BASE_URL',
  defaultValue: 'https://api.example.com',
);

// DEV-кнопка для входа без сервера появляется ТОЛЬКО в debug.
// Для релиза не влияет (kDebugMode == false).
const bool _kEnableDevBypassInDebug = true;

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('FlutterError: ${details.exceptionAsString()}');
        if (details.stack != null) {
          debugPrintStack(stackTrace: details.stack);
        }
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Uncaught (PlatformDispatcher): $error');
        debugPrintStack(stackTrace: stack);
        return true;
      };

      runApp(const BlueVPNApp());
    },
    (error, stack) {
      debugPrint('Uncaught (Zone): $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}

/* =========================
   APP SHELL + BOOTSTRAP
   ========================= */

class BlueVPNApp extends StatefulWidget {
  const BlueVPNApp({super.key});

  @override
  State<BlueVPNApp> createState() => _BlueVPNAppState();
}

class _BlueVPNAppState extends State<BlueVPNApp> {
  final PrefsStore _prefsStore = PrefsStore();
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  void _loadPrefs() {
    if (kIsWeb) return;
    unawaited(() async {
      final p = await _prefsStore.readPrefs();
      if (!mounted) return;
      setState(() {
        _themeMode = p.themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
      });
    }());
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    if (kIsWeb) return;
    unawaited(
      _prefsStore.patch({
        'themeMode': mode == ThemeMode.dark ? 'dark' : 'light',
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final light = ThemeData(
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F8FC),
    );

    final dark = ThemeData(
      useMaterial3: true,
      fontFamily: 'Segoe UI',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0B1220),
    );

    return MaterialApp(
      title: 'BlueVPN',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: _themeMode,
      home: AppBootstrap(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}

class AppBootstrap extends StatefulWidget {
  final ThemeMode themeMode;
  final void Function(ThemeMode mode) onThemeModeChanged;

  const AppBootstrap({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  final SessionStore _sessionStore = SessionStore();
  Session? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _sessionStore.read();
    if (!mounted) return;
    setState(() {
      _session = s;
      _loading = false;
    });
  }

  Future<void> _onAuthSuccess(Session s) async {
    await _sessionStore.write(s);
    if (!mounted) return;
    setState(() => _session = s);
  }

  Future<void> _logout() async {
    await _sessionStore.clear();
    await ConfigStore().deleteManagedConfig(); // скрыто от пользователя
    if (!mounted) return;
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _CenteredLoading();

    if (_session == null) {
      return AuthPage(onAuthSuccess: _onAuthSuccess);
    }

    return RootShell(
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
      session: _session!,
      onLogout: _logout,
    );
  }
}

class _CenteredLoading extends StatelessWidget {
  const _CenteredLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/* =========================
   AUTH MODELS + STORAGE
   ========================= */

class Session {
  final String accessToken;
  final String email;

  const Session({required this.accessToken, required this.email});

  Map<String, dynamic> toJson() => {'accessToken': accessToken, 'email': email};

  static Session fromJson(Map<String, dynamic> json) {
    return Session(
      accessToken: (json['accessToken'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }
}

class SessionStore {
  Future<String> _appDirPath() async {
    final base = Platform.environment['APPDATA'];
    final dir = Directory(
      base != null && base.isNotEmpty ? '$base\\BlueVPN' : 'BlueVPN',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<File> _file() async {
    final dir = await _appDirPath();
    return File('$dir\\session.json');
  }

  Future<Session?> read() async {
    if (kIsWeb) return null;
    try {
      final f = await _file();
      if (!f.existsSync()) return null;
      final raw = await f.readAsString();
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
      final s = Session.fromJson(jsonMap);
      if (s.accessToken.isEmpty) return null;
      return s;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Session session) async {
    if (kIsWeb) return;
    final f = await _file();
    await f.writeAsString(jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    if (kIsWeb) return;
    try {
      final f = await _file();
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

class DeviceIdStore {
  Future<String> _appDirPath() async {
    final base = Platform.environment['APPDATA'];
    final dir = Directory(
      base != null && base.isNotEmpty ? '$base\\BlueVPN' : 'BlueVPN',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<File> _file() async {
    final dir = await _appDirPath();
    return File('$dir\\device_id.txt');
  }

  String _gen() {
    // Короткий, но уникальный для устройства идентификатор
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'dev_$hex';
  }

  Future<String?> read() async {
    if (kIsWeb) return null;
    try {
      final f = await _file();
      if (!f.existsSync()) return null;
      final s = (await f.readAsString()).trim();
      if (s.length < 8) return null;
      return s;
    } catch (_) {
      return null;
    }
  }

  Future<String> getOrCreate() async {
    if (kIsWeb) return 'web';
    final existing = await read();
    if (existing != null) return existing;

    final id = _gen();
    final f = await _file();
    await f.writeAsString(id);
    return id;
  }
}

/* =========================
   PREFS (LOCAL UI SETTINGS)
   ========================= */

class Prefs {
  final String themeMode; // 'light' | 'dark'
  final String language;

  final String serverId;

  final bool socialOnlyEnabled;
  final List<String> socialOnlyApps; // SocialApp.name

  final List<String> selectedApps; // TariffApp.name
  final String trafficPack; // TrafficPack.name
  final double trafficGb;
  final int devices;

  final bool optNoAds;
  final bool optSmartRouting;
  final bool optDedicatedIp;

  const Prefs({
    required this.themeMode,
    required this.language,
    required this.serverId,
    required this.socialOnlyEnabled,
    required this.socialOnlyApps,
    required this.selectedApps,
    required this.trafficPack,
    required this.trafficGb,
    required this.devices,
    required this.optNoAds,
    required this.optSmartRouting,
    required this.optDedicatedIp,
  });

  static Prefs defaults() => const Prefs(
    themeMode: 'light',
    language: 'Русский',
    serverId: 'auto',
    socialOnlyEnabled: false,
    socialOnlyApps: ['telegram', 'instagram'],
    selectedApps: [],
    trafficPack: 'gb20',
    trafficGb: 20,
    devices: 1,
    optNoAds: true,
    optSmartRouting: true,
    optDedicatedIp: false,
  );

  Prefs copyWith({
    String? themeMode,
    String? language,
    String? serverId,
    bool? socialOnlyEnabled,
    List<String>? socialOnlyApps,
    List<String>? selectedApps,
    String? trafficPack,
    double? trafficGb,
    int? devices,
    bool? optNoAds,
    bool? optSmartRouting,
    bool? optDedicatedIp,
  }) {
    return Prefs(
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      serverId: serverId ?? this.serverId,
      socialOnlyEnabled: socialOnlyEnabled ?? this.socialOnlyEnabled,
      socialOnlyApps: socialOnlyApps ?? this.socialOnlyApps,
      selectedApps: selectedApps ?? this.selectedApps,
      trafficPack: trafficPack ?? this.trafficPack,
      trafficGb: trafficGb ?? this.trafficGb,
      devices: devices ?? this.devices,
      optNoAds: optNoAds ?? this.optNoAds,
      optSmartRouting: optSmartRouting ?? this.optSmartRouting,
      optDedicatedIp: optDedicatedIp ?? this.optDedicatedIp,
    );
  }

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'language': language,
    'serverId': serverId,
    'socialOnlyEnabled': socialOnlyEnabled,
    'socialOnlyApps': socialOnlyApps,
    'selectedApps': selectedApps,
    'trafficPack': trafficPack,
    'trafficGb': trafficGb,
    'devices': devices,
    'optNoAds': optNoAds,
    'optSmartRouting': optSmartRouting,
    'optDedicatedIp': optDedicatedIp,
  };

  static Prefs fromJson(Map<String, dynamic> map) {
    final d = Prefs.defaults();

    String _s(String k, String def) {
      final v = map[k];
      if (v == null) return def;
      final s = v.toString().trim();
      return s.isEmpty ? def : s;
    }

    bool _b(String k, bool def) {
      final v = map[k];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
      }
      return def;
    }

    int _i(String k, int def) {
      final v = map[k];
      if (v is int) return v;
      if (v is num) return v.round();
      if (v is String) return int.tryParse(v) ?? def;
      return def;
    }

    double _d(String k, double def) {
      final v = map[k];
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? def;
      return def;
    }

    List<String> _ls(String k, List<String> def) {
      final v = map[k];
      if (v is List) {
        final out = <String>[];
        for (final it in v) {
          if (it == null) continue;
          final s = it.toString().trim();
          if (s.isNotEmpty) out.add(s);
        }
        return out;
      }
      return def;
    }

    final theme = _s('themeMode', d.themeMode);
    final safeTheme = (theme == 'dark' || theme == 'light')
        ? theme
        : d.themeMode;

    return d.copyWith(
      themeMode: safeTheme,
      language: _s('language', d.language),
      serverId: _s('serverId', d.serverId),
      socialOnlyEnabled: _b('socialOnlyEnabled', d.socialOnlyEnabled),
      socialOnlyApps: _ls('socialOnlyApps', d.socialOnlyApps),
      selectedApps: _ls('selectedApps', d.selectedApps),
      trafficPack: _s('trafficPack', d.trafficPack),
      trafficGb: _d('trafficGb', d.trafficGb).clamp(1.0, 500.0),
      devices: _i('devices', d.devices).clamp(1, 5),
      optNoAds: _b('optNoAds', d.optNoAds),
      optSmartRouting: _b('optSmartRouting', d.optSmartRouting),
      optDedicatedIp: _b('optDedicatedIp', d.optDedicatedIp),
    );
  }
}

class PrefsStore {
  Future<String> _appDirPath() async {
    final base = Platform.environment['APPDATA'];
    final dir = Directory(
      base != null && base.isNotEmpty ? '$base\\BlueVPN' : 'BlueVPN',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<File> _file() async {
    final dir = await _appDirPath();
    return File('$dir\\prefs.json');
  }

  Future<Map<String, dynamic>> _readMap() async {
    if (kIsWeb) return <String, dynamic>{};
    try {
      final f = await _file();
      if (!f.existsSync()) return <String, dynamic>{};
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeMap(Map<String, dynamic> map) async {
    if (kIsWeb) return;
    final f = await _file();
    await f.writeAsString(jsonEncode(map));
  }

  Future<Prefs> readPrefs() async {
    final m = await _readMap();
    return Prefs.fromJson(m);
  }

  Future<void> patch(Map<String, dynamic> patch) async {
    if (kIsWeb) return;
    final m = await _readMap();
    for (final e in patch.entries) {
      m[e.key] = e.value;
    }
    await _writeMap(m);
  }
}

/* =========================
   API CLIENT (SERVER AUTH + PROVISION)
   ========================= */

class ApiResult<T> {
  final bool ok;
  final T? data;
  final String? message;

  const ApiResult.ok(this.data) : ok = true, message = null;

  const ApiResult.err(this.message) : ok = false, data = null;
}

class BlueVpnApi {
  final String baseUrl;
  const BlueVpnApi({required this.baseUrl});

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<ApiResult<Session>> register({
    required String email,
    required String password,
  }) async {
    return _postSession('/v1/auth/register', {
      'email': email,
      'password': password,
    });
  }

  Future<ApiResult<Session>> login({
    required String email,
    required String password,
  }) async {
    return _postSession('/v1/auth/login', {
      'email': email,
      'password': password,
    });
  }

  Future<ApiResult<String>> fetchPlanName({
    required String accessToken,
    String? deviceId,
  }) async {
    // Ожидаем JSON вида: { "plan": "Base" } или { "planName": "Base" }
    try {
      final client = HttpClient();
      final req = await client.getUrl(_u('/v1/me'));
      req.headers.set('Authorization', 'Bearer $accessToken');
      if (deviceId != null && deviceId.isNotEmpty) {
        req.headers.set('X-Device-Id', deviceId);
      }
      final res = await req.close();
      final body = await utf8.decodeStream(res);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final jsonMap = jsonDecode(body) as Map<String, dynamic>;
        final p = (jsonMap['plan'] ?? jsonMap['planName'] ?? 'Base').toString();
        return ApiResult.ok(p.isEmpty ? 'Base' : p);
      }
      return ApiResult.err('Ошибка сервера (${res.statusCode}): $body');
    } catch (e) {
      return ApiResult.err('Ошибка сети: $e');
    }
  }

  Future<ApiResult<String>> fetchWireGuardConfig({
    required String accessToken,
    String? deviceId,
    String? serverId,
  }) async {
    // Ожидаемые форматы ответа:
    // A) JSON: { "config": "[Interface]..." }
    // B) text/plain: сам конфиг
    try {
      final client = HttpClient();

      final uri = serverId == null || serverId.isEmpty
          ? _u('/v1/wg/config')
          : _u('/v1/wg/config').replace(queryParameters: {'server': serverId});

      final req = await client.getUrl(uri);
      req.headers.set('Authorization', 'Bearer $accessToken');
      if (deviceId != null && deviceId.isNotEmpty) {
        req.headers.set('X-Device-Id', deviceId);
      }

      final res = await req.close();
      final body = await utf8.decodeStream(res);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final trimmed = body.trim();
        if (trimmed.startsWith('{')) {
          final jsonMap = jsonDecode(trimmed) as Map<String, dynamic>;
          final cfg = (jsonMap['config'] ?? '').toString();
          if (cfg.trim().isEmpty)
            return const ApiResult.err('Сервер вернул пустой конфиг.');
          return ApiResult.ok(cfg);
        }
        if (trimmed.isEmpty)
          return const ApiResult.err('Сервер вернул пустой конфиг.');
        return ApiResult.ok(body);
      }

      return ApiResult.err('Ошибка сервера (${res.statusCode}): $body');
    } catch (e) {
      return ApiResult.err('Не удалось получить конфиг: $e');
    }
  }

  Future<ApiResult<Session>> _postSession(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final client = HttpClient();
      final req = await client.postUrl(_u(path));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(payload));

      final res = await req.close();
      final body = await utf8.decodeStream(res);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final jsonMap = jsonDecode(body) as Map<String, dynamic>;
        final token = (jsonMap['accessToken'] ?? '').toString();
        final email = (jsonMap['email'] ?? payload['email'] ?? '').toString();

        if (token.isEmpty)
          return const ApiResult.err('Сервер не вернул accessToken.');
        return ApiResult.ok(Session(accessToken: token, email: email));
      }

      return ApiResult.err('Ошибка сервера (${res.statusCode}): $body');
    } catch (e) {
      return ApiResult.err('Ошибка сети: $e');
    }
  }
}

/* =========================
   CONFIG STORE (HIDDEN)
   ========================= */

class ConfigStore {
  // Active managed config path. Stored in ProgramData so the WireGuard service (LocalSystem) can read it.
  String get managedConfigPath {
    if (kIsWeb) return '';
    if (!Platform.isWindows) return '';
    return r'C:\ProgramData\BlueVPN\BlueVPN.conf';
  }

  // Hidden base config received from server/dev seed. We never apply it directly.
  String get baseConfigPath {
    if (kIsWeb) return '';
    if (!Platform.isWindows) return '';
    return r'C:\ProgramData\BlueVPN\BlueVPN.base.conf';
  }

  Future<bool> hasManagedConfig() async {
    if (kIsWeb) return false;
    final p = managedConfigPath;
    if (p.isEmpty) return false;
    return File(p).existsSync();
  }

  Future<bool> hasBaseConfig() async {
    if (kIsWeb) return false;
    final p = baseConfigPath;
    if (p.isEmpty) return false;
    return File(p).existsSync();
  }

  Future<void> writeManagedConfig(String content) async {
    if (kIsWeb) return;
    final p = managedConfigPath;
    if (p.isEmpty) return;
    final f = File(p);
    if (!f.parent.existsSync()) {
      f.parent.createSync(recursive: true);
    }
    await f.writeAsString(content);
  }

  Future<void> writeBaseConfig(String content) async {
    if (kIsWeb) return;
    final p = baseConfigPath;
    if (p.isEmpty) return;
    final f = File(p);
    if (!f.parent.existsSync()) {
      f.parent.createSync(recursive: true);
    }
    await f.writeAsString(content);
  }

  Future<String?> readBaseConfig() async {
    if (kIsWeb) return null;
    final p = baseConfigPath;
    if (p.isEmpty) return null;
    final f = File(p);
    if (!f.existsSync()) return null;
    return f.readAsString();
  }

  Future<void> ensureBaseSeededFromManagedIfMissing() async {
    if (kIsWeb) return;
    final hasBase = await hasBaseConfig();
    if (hasBase) return;

    final managed = managedConfigPath;
    if (managed.isEmpty) return;

    final mf = File(managed);
    if (!mf.existsSync()) return;

    final raw = await mf.readAsString();
    if (raw.trim().isEmpty) return;
    await writeBaseConfig(raw);
  }

  Future<void> deleteManagedConfig() async {
    if (kIsWeb) return;

    final managed = managedConfigPath;
    if (managed.isNotEmpty) {
      final f = File(managed);
      if (f.existsSync()) {
        await f.delete();
      }
    }

    final base = baseConfigPath;
    if (base.isNotEmpty) {
      final f = File(base);
      if (f.existsSync()) {
        await f.delete();
      }
    }
  }
} /* =========================
   AUTH UI
   ========================= */

class AuthPage extends StatefulWidget {
  final Future<void> Function(Session s) onAuthSuccess;
  const AuthPage({super.key, required this.onAuthSuccess});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _api = const BlueVpnApi(baseUrl: kApiBaseUrl);

  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _submit({required bool isRegister}) async {
    if (_busy) return;

    final email = _email.text.trim();
    final pass = _password.text;

    if (email.isEmpty || !email.contains('@')) {
      _toast('Введи корректный email.');
      return;
    }
    if (pass.length < 6) {
      _toast('Пароль минимум 6 символов.');
      return;
    }

    setState(() => _busy = true);
    try {
      final res = isRegister
          ? await _api.register(email: email, password: pass)
          : await _api.login(email: email, password: pass);

      if (!res.ok || res.data == null) {
        _toast(res.message ?? 'Ошибка авторизации.');
        return;
      }

      await widget.onAuthSuccess(res.data!);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _devBypass() async {
    if (!(kDebugMode && _kEnableDevBypassInDebug)) return;
    final email = _email.text.trim().isEmpty
        ? 'dev@bluevpn.local'
        : _email.text.trim();
    await widget.onAuthSuccess(Session(accessToken: 'dev-token', email: email));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _Card(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.vpn_key_rounded,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BlueVPN',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Войти или зарегистрироваться',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TabBar(
                      controller: _tabs,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                      tabs: const [
                        Tab(text: 'Вход'),
                        Tab(text: 'Регистрация'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Пароль',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _busy
                            ? null
                            : () => _submit(isRegister: _tabs.index == 1),
                        child: Text(
                          _busy
                              ? 'Подождите…'
                              : (_tabs.index == 1
                                    ? 'Создать аккаунт'
                                    : 'Войти'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    if (kDebugMode && _kEnableDevBypassInDebug) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _busy ? null : _devBypass,
                        child: Text(
                          'DEV: войти без сервера',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.65,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* =========================
   ROOT SHELL (NO PROFILE UI)
   ========================= */

/* =========================
   MODELS
   ========================= */

class ServerLocation {
  final String id;
  final String title;
  final String subtitle;
  final int? pingMs;
  final bool isAuto;

  const ServerLocation({
    required this.id,
    required this.title,
    required this.subtitle,
    this.pingMs,
    this.isAuto = false,
  });
}

enum SocialApp {
  telegram('Telegram', Icons.send_rounded),
  instagram('Instagram', Icons.photo_camera_rounded),
  tiktok('TikTok', Icons.music_note_rounded),
  discord('Discord', Icons.forum_rounded),
  youtube('YouTube', Icons.play_circle_fill_rounded);

  const SocialApp(this.title, this.icon);
  final String title;
  final IconData icon;
}

class RootShell extends StatefulWidget {
  final ThemeMode themeMode;
  final void Function(ThemeMode mode) onThemeModeChanged;

  final Session session;
  final Future<void> Function() onLogout;

  const RootShell({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.session,
    required this.onLogout,
  });

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  final _api = const BlueVpnApi(baseUrl: kApiBaseUrl);
  final _cfg = ConfigStore();

  // device identifier (for server-side provisioning) — hidden from user
  final DeviceIdStore _deviceStore = DeviceIdStore();
  String? _deviceId;

  // plan name shown in UI (from /v1/me)
  String planName = 'Base';

  late final VpnBackend _vpnBackend;

  static const Map<SocialApp, List<String>> _socialAllowedIps = {
    SocialApp.telegram: [
      '149.154.160.0/20',
      '91.108.4.0/22',
      '91.108.8.0/22',
      '91.108.12.0/22',
      '91.108.16.0/22',
      '91.108.56.0/22',
    ],
    SocialApp.instagram: [
      '31.13.24.0/21',
      '31.13.64.0/18',
      '66.220.144.0/20',
      '69.63.176.0/20',
      '157.240.0.0/16',
    ],
    SocialApp.youtube: [
      '74.125.0.0/16',
      '142.250.0.0/15',
      '142.251.0.0/16',
      '172.217.0.0/16',
    ],
    // Starter ranges for MVP; later these should be moved to server-side/domain-based rules.
    SocialApp.discord: ['162.159.128.0/17', '66.22.192.0/18'],
    SocialApp.tiktok: ['23.192.0.0/11', '23.32.0.0/11'],
  };

  int _index = 0;

  // VPN state
  bool vpnEnabled = false;
  bool vpnBusy = false;

  // “Только для соцсетей”
  bool socialOnlyEnabled = false;
  final Set<SocialApp> socialOnlyApps = {
    SocialApp.telegram,
    SocialApp.instagram,
  };

  // Сервер
  final List<ServerLocation> servers = const [
    ServerLocation(
      id: 'auto',
      title: 'Авто',
      subtitle: 'Самая быстрая локация',
      pingMs: null,
      isAuto: true,
    ),
    ServerLocation(
      id: 'nl',
      title: 'Нидерланды',
      subtitle: 'Амстердам',
      pingMs: 32,
    ),
    ServerLocation(
      id: 'de',
      title: 'Германия',
      subtitle: 'Франкфурт',
      pingMs: 44,
    ),
    ServerLocation(
      id: 'fi',
      title: 'Финляндия',
      subtitle: 'Хельсинки',
      pingMs: 48,
    ),
    ServerLocation(
      id: 'uk',
      title: 'Великобритания',
      subtitle: 'Лондон',
      pingMs: 58,
    ),
    ServerLocation(id: 'us', title: 'США', subtitle: 'Нью-Йорк', pingMs: 120),
  ];

  ServerLocation selectedServer = const ServerLocation(
    id: 'auto',
    title: 'Авто',
    subtitle: 'Самая быстрая локация',
    pingMs: null,
    isAuto: true,
  );

  // ===== TARIFF STATE =====
  final Set<TariffApp> selectedApps = {};
  TrafficPack trafficPack = TrafficPack.gb20; // “режим” (по ГБ / безлимит)
  double trafficGb = 20; // любой объём ГБ
  int devices = 1;

  bool optNoAds = true;
  bool optSmartRouting = true; // этим флагом управляем доступностью “соцсетей”
  bool optDedicatedIp = false;

  // ===== SETTINGS (косметика) =====
  String sLanguage = 'Русский';

  // Local prefs (persist UI settings)
  final PrefsStore _prefsStore = PrefsStore();
  Timer? _prefsDebounce;

  void goToTab(int i) => setState(() => _index = i);

  @override
  void initState() {
    super.initState();
    _vpnBackend = VpnBackend.createDefault(tunnelName: kTunnelName);

    _loadPrefsAndApply();

    _syncVpnStatus();
    _ensureProvisionedConfigSilently();
    _syncPlanSilently();
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadPrefsAndApply() async {
    if (kIsWeb) return;

    try {
      final p = await _prefsStore.readPrefs();
      if (!mounted) return;

      // Apply language
      sLanguage = p.language;

      // Apply server
      final srv = servers.firstWhere(
        (s) => s.id == p.serverId,
        orElse: () => servers.first,
      );
      selectedServer = srv;

      // Apply social-only
      socialOnlyEnabled = p.socialOnlyEnabled;
      socialOnlyApps
        ..clear()
        ..addAll(
          p.socialOnlyApps
              .map(
                (n) => SocialApp.values.firstWhere(
                  (e) => e.name == n,
                  orElse: () => SocialApp.telegram,
                ),
              )
              .toSet(),
        );
      if (socialOnlyApps.isEmpty) {
        socialOnlyApps.addAll({SocialApp.telegram, SocialApp.instagram});
      }

      // Apply tariff settings
      selectedApps
        ..clear()
        ..addAll(
          p.selectedApps
              .map(
                (n) => TariffApp.values.firstWhere(
                  (e) => e.name == n,
                  orElse: () => TariffApp.telegram,
                ),
              )
              .toSet(),
        );

      trafficPack = TrafficPack.values.firstWhere(
        (e) => e.name == p.trafficPack,
        orElse: () => TrafficPack.gb20,
      );
      trafficGb = p.trafficGb.clamp(1.0, 500.0);
      devices = p.devices.clamp(1, 5);

      optNoAds = p.optNoAds;
      optSmartRouting =
          true; // временно всегда разрешаем Social Only в Windows-клиенте
      optDedicatedIp = p.optDedicatedIp;

      await _repairProvisionedConfigFromPreferredDevSource(showToast: false);
      await _cfg.ensureBaseSeededFromManagedIfMissing();
      final base = await _cfg.readBaseConfig();
      if (base != null && base.trim().isNotEmpty) {
        await _cfg.writeManagedConfig(_buildManagedConfigFromBase(base));
      }

      if (mounted) setState(() {});
    } catch (_) {
      // ignore
    }
  }

  void _schedulePrefsSave() {
    if (kIsWeb) return;
    _prefsDebounce?.cancel();
    _prefsDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(
        _prefsStore.patch({
          'language': sLanguage,
          'serverId': selectedServer.id,
          'socialOnlyEnabled': socialOnlyEnabled,
          'socialOnlyApps': socialOnlyApps.map((e) => e.name).toList(),
          'selectedApps': selectedApps.map((e) => e.name).toList(),
          'trafficPack': trafficPack.name,
          'trafficGb': trafficGb,
          'devices': devices,
          'optNoAds': optNoAds,
          'optSmartRouting': true,
          'optDedicatedIp': optDedicatedIp,
        }),
      );
    });
  }

  bool _configLooksLikeFullTunnel(String raw) {
    final line = RegExp(
      r'^\s*AllowedIPs\s*=\s*(.*)$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(raw);

    if (line == null) return false;
    final value = (line.group(1) ?? '').toLowerCase();
    return value.contains('0.0.0.0/0') || value.contains('::/0');
  }

  List<String> _preferredLocalConfigCandidates() {
    if (kIsWeb) return const [];
    final home = Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return const [];

    return <String>[
      '$home\\OneDrive\\Desktop\\WARP.conf',
      '$home\\Desktop\\WARP.conf',
      '$home\\Downloads\\WARP.conf',
      '$home\\Downloads\\WARP (1).conf',
      '$home\\Downloads\\Telegram Desktop\\WARP.conf',
      '$home\\Downloads\\Telegram Desktop\\WARP (2).conf',
      '$home\\Downloads\\Telegram Desktop\\WARP (3).conf',
      '$home\\Desktop\\$kTunnelName.conf',
      '$home\\Downloads\\$kTunnelName.conf',
      '$home\\Desktop\\BlueVPN.conf',
      '$home\\Downloads\\BlueVPN.conf',
    ];
  }

  Future<String?> _findPreferredLocalConfig() async {
    for (final p in _preferredLocalConfigCandidates()) {
      final f = File(p);
      if (!f.existsSync()) continue;
      try {
        final raw = await f.readAsString();
        if (raw.trim().isEmpty) continue;
        return raw;
      } catch (_) {
        // ignore and try next
      }
    }
    return null;
  }

  Future<void> _repairProvisionedConfigFromPreferredDevSource({
    required bool showToast,
  }) async {
    if (kIsWeb) return;
    if (widget.session.accessToken != 'dev-token') return;

    String? base;
    try {
      base = await _cfg.readBaseConfig();
    } catch (_) {
      base = null;
    }

    if (base != null &&
        base.trim().isNotEmpty &&
        _configLooksLikeFullTunnel(base)) {
      return;
    }

    final preferred = await _findPreferredLocalConfig();
    if (preferred == null || preferred.trim().isEmpty) return;

    await _writeProvisionedConfig(preferred);

    if (showToast && mounted) {
      _toast(context, 'Локальный WARP/BlueVPN конфиг восстановлен.');
    }
  }

  List<String> _resolveSocialAllowedIps(Set<SocialApp> apps) {
    final out = <String>{};

    for (final app in apps) {
      final ranges = _socialAllowedIps[app];
      if (ranges != null) {
        out.addAll(ranges);
      }
    }

    if (out.isEmpty) {
      final fallback = _socialAllowedIps[SocialApp.telegram];
      if (fallback != null) out.addAll(fallback);
    }

    final list = out.toList()..sort();
    return list;
  }

  String _replaceAllowedIps(String configText, List<String> allowedIps) {
    final value = allowedIps.join(', ');

    final regExp = RegExp(
      r'(^\s*AllowedIPs\s*=\s*.*$)',
      multiLine: true,
      caseSensitive: false,
    );

    if (regExp.hasMatch(configText)) {
      return configText.replaceFirst(regExp, 'AllowedIPs = $value');
    }

    final lines = configText.split('\n');
    final peerIndex = lines.indexWhere(
      (line) => line.trim().toLowerCase() == '[peer]',
    );

    if (peerIndex == -1) {
      return configText;
    }

    lines.insert(peerIndex + 1, 'AllowedIPs = $value');
    return lines.join('\n');
  }

  String _buildManagedConfigFromBase(String baseConfig) {
    if (!socialOnlyEnabled) {
      return _replaceAllowedIps(baseConfig, const ['0.0.0.0/0', '::/0']);
    }

    final allowedIps = _resolveSocialAllowedIps(socialOnlyApps);
    return _replaceAllowedIps(baseConfig, allowedIps);
  }

  Future<void> _writeProvisionedConfig(String rawConfig) async {
    await _cfg.writeBaseConfig(rawConfig);
    await _cfg.writeManagedConfig(_buildManagedConfigFromBase(rawConfig));
  }

  Future<bool> _applyCurrentConfigMode({
    required bool reconnectIfNeeded,
    required bool showToastOnSuccess,
  }) async {
    await _cfg.ensureBaseSeededFromManagedIfMissing();

    final base = await _cfg.readBaseConfig();
    if (base == null || base.trim().isEmpty) {
      if (showToastOnSuccess) {
        _toast(
          context,
          socialOnlyEnabled
              ? 'Режим сохранён. Применится после получения конфига.'
              : 'Обычный режим сохранён.',
        );
      }
      return true;
    }

    await _cfg.writeManagedConfig(_buildManagedConfigFromBase(base));

    if (reconnectIfNeeded && vpnEnabled) {
      final off = await _vpnBackend.disconnect();
      if (!off.ok) {
        _toast(context, off.message ?? 'Не удалось переподключить VPN.');
        await _syncVpnStatus();
        return false;
      }

      final on = await _vpnBackend.connect(configPath: _cfg.managedConfigPath);
      if (!on.ok) {
        _toast(context, on.message ?? 'Не удалось заново подключить VPN.');
        await _syncVpnStatus();
        return false;
      }

      await _syncVpnStatus();
    }

    if (showToastOnSuccess) {
      _toast(
        context,
        socialOnlyEnabled
            ? 'Social Only применён.'
            : 'Обычный режим восстановлен.',
      );
    }

    return true;
  }

  void _setLanguage(String v) {
    setState(() => sLanguage = v);
    _schedulePrefsSave();
  }

  Future<void> _syncVpnStatus() async {
    final on = await _vpnBackend.isConnected();
    if (mounted) setState(() => vpnEnabled = on);
  }

  Future<String?> _ensureDeviceId() async {
    if (kIsWeb) return null;
    _deviceId ??= await _deviceStore.getOrCreate();
    return _deviceId;
  }

  Future<void> _syncPlanSilently() async {
    if (kIsWeb) return;
    try {
      // DEV режим — план не тянем
      if (widget.session.accessToken == 'dev-token') return;

      final did = await _ensureDeviceId();
      final res = await _api.fetchPlanName(
        accessToken: widget.session.accessToken,
        deviceId: did,
      );
      if (res.ok && res.data != null && mounted) {
        setState(() => planName = res.data!);
      }
    } catch (_) {}
  }

  Future<bool> _trySeedDevConfig({required bool showToast}) async {
    // Для разработки без сервера: ищем сначала WARP.conf, потом BlueVPN.conf.
    if (kIsWeb) return false;

    for (final p in _preferredLocalConfigCandidates()) {
      final f = File(p);
      if (!f.existsSync()) continue;
      try {
        final cfg = await f.readAsString();
        if (cfg.trim().isEmpty) continue;
        await _writeProvisionedConfig(cfg);
        if (showToast) {
          _toast(context, 'DEV: конфиг подхвачен из $p');
        }
        return true;
      } catch (_) {
        // ignore and try next
      }
    }

    return false;
  }

  Future<void> _ensureProvisionedConfigSilently() async {
    // тихо подтянем конфиг при старте, если его нет
    if (kIsWeb) return;
    try {
      if (widget.session.accessToken == 'dev-token') {
        await _repairProvisionedConfigFromPreferredDevSource(showToast: false);
      }

      final has = await _cfg.hasManagedConfig();
      if (has) {
        await _cfg.ensureBaseSeededFromManagedIfMissing();
        final base = await _cfg.readBaseConfig();
        if (base != null && base.trim().isNotEmpty) {
          await _cfg.writeManagedConfig(_buildManagedConfigFromBase(base));
        }
        return;
      }

      if (widget.session.accessToken == 'dev-token') {
        await _trySeedDevConfig(showToast: false);
        return;
      }

      final res = await _api.fetchWireGuardConfig(
        accessToken: widget.session.accessToken,
        deviceId: await _ensureDeviceId(),
        serverId: selectedServer.id == 'auto' ? null : selectedServer.id,
      );
      if (res.ok && res.data != null) {
        await _writeProvisionedConfig(res.data!);
      }
    } catch (_) {}
  }

  Future<bool> _ensureProvisionedConfigInteractive() async {
    if (kIsWeb) return false;

    if (widget.session.accessToken == 'dev-token') {
      await _repairProvisionedConfigFromPreferredDevSource(showToast: true);
    }

    if (await _cfg.hasManagedConfig()) {
      await _cfg.ensureBaseSeededFromManagedIfMissing();
      final base = await _cfg.readBaseConfig();
      if (base != null && base.trim().isNotEmpty) {
        await _cfg.writeManagedConfig(_buildManagedConfigFromBase(base));
      }
      return true;
    }

    if (widget.session.accessToken == 'dev-token') {
      final ok = await _trySeedDevConfig(showToast: true);
      if (ok) return true;
      _toast(
        context,
        'DEV: не найден локальный конфиг. Положи WARP.conf или BlueVPN.conf на Desktop/Downloads либо подними сервер.',
      );
      return false;
    }

    final res = await _api.fetchWireGuardConfig(
      accessToken: widget.session.accessToken,
      deviceId: await _ensureDeviceId(),
      serverId: selectedServer.id == 'auto' ? null : selectedServer.id,
    );
    if (!res.ok || res.data == null) {
      _toast(context, res.message ?? 'Не удалось получить конфиг с сервера.');
      return false;
    }
    await _writeProvisionedConfig(res.data!);
    return true;
  }

  Future<void> _toggleVpnReal() async {
    if (vpnBusy) return;

    if (kIsWeb) {
      _toast(
        context,
        'Web-режим: реальный VPN недоступен. Запусти приложение как Windows.',
      );
      return;
    }

    setState(() => vpnBusy = true);
    try {
      if (!vpnEnabled) {
        final ok = await _ensureProvisionedConfigInteractive();
        if (!ok) return;

        final configPath = _cfg.managedConfigPath;
        final res = await _vpnBackend.connect(configPath: configPath);
        if (!res.ok) {
          _toast(context, res.message ?? 'Не удалось подключить VPN.');
          await _syncVpnStatus();
          var onNow = false;
          for (var i = 0; i < 40; i++) {
            onNow = await _vpnBackend.isConnected();
            if (onNow) break;
            await Future.delayed(const Duration(milliseconds: 250));
          }
          if (mounted) setState(() => vpnEnabled = onNow);
          if (!onNow) {
            _toast(context, 'VPN did not start (service not RUNNING).');
            await _syncVpnStatus();
            return;
          }

          return;
        }

        await _syncVpnStatus();
        _toast(context, 'VPN включён.');
      } else {
        final res = await _vpnBackend.disconnect();
        if (!res.ok) {
          _toast(context, res.message ?? 'Не удалось отключить VPN.');
          await _syncVpnStatus();
          final onNow = await _vpnBackend.isConnected();
          if (mounted) setState(() => vpnEnabled = onNow);

          return;
        }

        await _syncVpnStatus();
        _toast(context, 'VPN выключен.');
      }
    } finally {
      if (mounted) setState(() => vpnBusy = false);
    }
  }


  Future<void> _openServerPicker(BuildContext context) async {
    final picked = await showDialog<ServerLocation>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Выбор сервера'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: servers.map((s) {
                  final selected = s.id == selectedServer.id;
                  final subtitle = s.isAuto
                      ? 'Авто-подбор'
                      : '${s.subtitle}${s.pingMs != null ? ' • ${s.pingMs} ms' : ''}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      s.isAuto ? Icons.auto_awesome_rounded : Icons.public_rounded,
                      color: const Color(0xFF2563EB),
                    ),
                    title: Text(
                      s.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(subtitle),
                    trailing: selected
                        ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB))
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(ctx).pop(s),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );

    if (picked != null) {
      setState(() => selectedServer = picked);
      _schedulePrefsSave();

      if (!vpnEnabled) {
        unawaited(_cfg.deleteManagedConfig());
      } else {
        _toast(context, 'Сервер изменён. Переподключись, чтобы применить.');
      }
    }
  }


  Future<void> _openSocialAppsPicker(BuildContext context) async {
    final temp = Set<SocialApp>.from(socialOnlyApps);

    final picked = await showDialog<Set<SocialApp>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Соцсети через VPN'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: SocialApp.values.map((app) {
                      return CheckboxListTile(
                        value: temp.contains(app),
                        onChanged: (v) {
                          setLocal(() {
                            if (v == true) {
                              temp.add(app);
                            } else {
                              temp.remove(app);
                            }
                          });
                        },
                        title: Text(app.title),
                        secondary: Icon(app.icon, color: const Color(0xFF2563EB)),
                        controlAffinity: ListTileControlAffinity.trailing,
                        contentPadding: EdgeInsets.zero,
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (temp.isEmpty) {
                      _toast(ctx, 'Выбери хотя бы одно приложение.');
                      return;
                    }
                    Navigator.of(ctx).pop(Set<SocialApp>.from(temp));
                  },
                  child: const Text('Готово'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return;

    setState(() {
      socialOnlyApps
        ..clear()
        ..addAll(picked);
    });
    _schedulePrefsSave();

    if (socialOnlyEnabled) {
      await _applyCurrentConfigMode(
        reconnectIfNeeded: true,
        showToastOnSuccess: true,
      );
    }
  }


  @override
  void dispose() {
    _prefsDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      VpnPage(
        planName: planName,
        vpnEnabled: vpnEnabled,
        onToggleVpn: () => _toggleVpnReal(),

        // Сервер
        selectedServer: selectedServer,
        onOpenServerPicker: () => _openServerPicker(context),

        // Соцсети
        socialOnlyEnabled: socialOnlyEnabled,
        socialOnlyAllowed: true,
        socialOnlyApps: socialOnlyApps,
        onToggleSocialOnly: (v) async {
          if (vpnBusy) return;

          setState(() {
            vpnBusy = true;
            socialOnlyEnabled = v;
          });
          _schedulePrefsSave();

          try {
            await _applyCurrentConfigMode(
              reconnectIfNeeded: true,
              showToastOnSuccess: true,
            );
          } finally {
            if (mounted) {
              setState(() => vpnBusy = false);
            }
          }
        },
        onConfigureSocialApps: () async {
          if (vpnBusy) return;
          await _openSocialAppsPicker(context);
        },

        onOpenTariff: () => goToTab(1),
      ),

      TariffPage(
        selectedApps: selectedApps,
        trafficPack: trafficPack,
        trafficGb: trafficGb,
        devices: devices,
        optNoAds: optNoAds,
        optSmartRouting: optSmartRouting,
        optDedicatedIp: optDedicatedIp,
        onToggleApp: (app) {
          setState(() {
            if (selectedApps.contains(app)) {
              selectedApps.remove(app);
            } else {
              selectedApps.add(app);
            }
          });
          _schedulePrefsSave();
        },
        onTrafficChanged: (p) {
          setState(() => trafficPack = p);
          _schedulePrefsSave();
        },
        onTrafficGbChanged: (gb) {
          setState(() => trafficGb = gb);
          _schedulePrefsSave();
        },
        onDevicesChanged: (v) {
          setState(() => devices = v.clamp(1, 5));
          _schedulePrefsSave();
        },
        onOptNoAds: (v) {
          setState(() => optNoAds = v);
          _schedulePrefsSave();
        },
        onOptSmartRouting: (v) {
          setState(() {
            optSmartRouting = v;
          });
          _schedulePrefsSave();
        },
        onOptDedicatedIp: (v) {
          setState(() => optDedicatedIp = v);
          _schedulePrefsSave();
        },
      ),

      const TasksPage(),

      SettingsPage(
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        language: sLanguage,
        onPickLanguage: () => _pickOne(
          context,
          title: 'Язык',
          current: sLanguage,
          items: const ['Русский', 'English'],
          onSelect: (v) => _setLanguage(v),
        ),
        email: widget.session.email,
        onLogout: widget.onLogout,
        onOpenDiagnostics: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const DiagnosticsPage()));
        },
      ),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _index = i),
        selectedItemColor: const Color(0xFF2563EB),
        unselectedItemColor: const Color(0xFF94A3B8),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.vpn_key_rounded),
            label: 'VPN',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.star_rounded),
            label: 'Тариф',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checklist_rounded),
            label: 'Задания',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }

  Future<void> _pickOne(
    BuildContext context, {
    required String title,
    required String current,
    required List<String> items,
    required void Function(String v) onSelect,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _BottomSheetFrame(
          title: title,
          subtitle: 'Выбери значение',
          leading: Icons.tune_rounded,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final it = items[i];
                final on = it == current;
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(ctx).pop(it),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x140F172A)),
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF8FAFC),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            it,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Icon(
                          on
                              ? Icons.check_circle_rounded
                              : Icons.chevron_right_rounded,
                          color: on
                              ? const Color(0xFF2563EB)
                              : Theme.of(
                                  ctx,
                                ).colorScheme.onSurface.withOpacity(0.35),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    if (picked != null) onSelect(picked);
  }
}

/* =========================
   VPN PAGE
   ========================= */

class VpnPage extends StatelessWidget {
  final String planName;
  final bool vpnEnabled;
  final VoidCallback onToggleVpn;
  final VoidCallback onOpenTariff;
  final ServerLocation selectedServer;
  final VoidCallback onOpenServerPicker;
  final bool socialOnlyEnabled;
  final bool socialOnlyAllowed;
  final Set<SocialApp> socialOnlyApps;
  final ValueChanged<bool> onToggleSocialOnly;
  final VoidCallback onConfigureSocialApps;

  const VpnPage({
    super.key,
    required this.planName,
    required this.vpnEnabled,
    required this.onToggleVpn,
    required this.onOpenTariff,
    required this.selectedServer,
    required this.onOpenServerPicker,
    required this.socialOnlyEnabled,
    required this.socialOnlyAllowed,
    required this.socialOnlyApps,
    required this.onToggleSocialOnly,
    required this.onConfigureSocialApps,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = vpnEnabled ? 'Включено' : 'Отключено';
    final serverTitle = selectedServer.isAuto
        ? 'Самая быстрая локация'
        : selectedServer.title;
    final serverSub = selectedServer.isAuto
        ? 'Авто-подбор'
        : '${selectedServer.subtitle}${selectedServer.pingMs != null ? ' • ${selectedServer.pingMs} ms' : ''}';
    final appsText = socialOnlyApps.isEmpty
        ? 'Не выбрано'
        : socialOnlyApps.map((e) => e.title).join(', ');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.tonal(
          onPressed: onOpenTariff,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.star_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Тариф',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Текущий: $planName • открыть тариф',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Card(
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onToggleVpn,
                  icon: Icon(
                    vpnEnabled ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(vpnEnabled ? 'Отключить VPN' : 'Подключить VPN'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                statusText,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Только для соц. сетей',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  socialOnlyEnabled
                      ? 'Через VPN: $appsText'
                      : 'Выбери приложения, которые должны идти через VPN',
                  style: const TextStyle(fontSize: 12),
                ),
                value: socialOnlyEnabled,
                onChanged: onToggleSocialOnly,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onConfigureSocialApps,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text(
                    'Настроить приложения',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                socialOnlyAllowed
                    ? 'Функция активна. Кнопка выше должна открывать выбор приложений.'
                    : 'Функция временно недоступна для текущего режима.',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          tint: const Color(0xFFEFF6FF),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: onOpenServerPicker,
            leading: const Icon(Icons.bolt_rounded, color: Color(0xFF2563EB)),
            title: const Text(
              'Сервер',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    serverTitle,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    serverSub,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ],
    );
  }
}

class _TariffBanner extends StatelessWidget {
  final VoidCallback onTap;
  final String planName;
  const _TariffBanner({required this.onTap, required this.planName});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              offset: Offset(0, 6),
              color: Color(0x22000000),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Тариф',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Текущий: $planName • настрой подписку',
                    style: TextStyle(
                      color: Color(0xFFBFDBFE),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Color(0xFFBFDBFE)),
          ],
        ),
      ),
    );
  }
}

class _BigToggle extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _BigToggle({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(enabled ? Icons.pause_rounded : Icons.play_arrow_rounded),
        label: Text(enabled ? 'Отключить VPN' : 'Подключить VPN'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }
}

/* =========================
   TARIFF PAGE
   ========================= */

enum TariffApp {
  youtube('YouTube', Icons.play_circle_fill_rounded),
  telegram('Telegram', Icons.send_rounded),
  tiktok('TikTok', Icons.music_note_rounded),
  instagram('Instagram', Icons.photo_camera_rounded),
  discord('Discord', Icons.forum_rounded),
  steam('Steam', Icons.sports_esports_rounded),
  netflix('Netflix', Icons.movie_rounded);

  const TariffApp(this.title, this.icon);
  final String title;
  final IconData icon;
}

enum TrafficPack {
  gb5('5 ГБ', 99),
  gb20('20 ГБ', 199),
  gb50('50 ГБ', 299),
  gb100('100 ГБ', 399),
  unlimited('Безлимит', 799);

  const TrafficPack(this.title, this.basePriceRub);
  final String title;
  final int basePriceRub;
}

class TariffPage extends StatelessWidget {
  final Set<TariffApp> selectedApps;
  final TrafficPack trafficPack;
  final double trafficGb;
  final int devices;

  final bool optNoAds;
  final bool optSmartRouting;
  final bool optDedicatedIp;

  final void Function(TariffApp) onToggleApp;
  final void Function(TrafficPack) onTrafficChanged;
  final ValueChanged<double> onTrafficGbChanged;
  final void Function(int) onDevicesChanged;

  final void Function(bool) onOptNoAds;
  final void Function(bool) onOptSmartRouting;
  final void Function(bool) onOptDedicatedIp;

  const TariffPage({
    super.key,
    required this.selectedApps,
    required this.trafficPack,
    required this.trafficGb,
    required this.devices,
    required this.optNoAds,
    required this.optSmartRouting,
    required this.optDedicatedIp,
    required this.onToggleApp,
    required this.onTrafficChanged,
    required this.onTrafficGbChanged,
    required this.onDevicesChanged,
    required this.onOptNoAds,
    required this.onOptSmartRouting,
    required this.onOptDedicatedIp,
  });

  int _basePriceForGb(double gb) {
    final g = gb.clamp(1.0, 500.0);

    const points = <_GbPricePoint>[
      _GbPricePoint(1, 79),
      _GbPricePoint(5, 99),
      _GbPricePoint(20, 199),
      _GbPricePoint(50, 299),
      _GbPricePoint(100, 399),
      _GbPricePoint(200, 499),
      _GbPricePoint(500, 699),
    ];

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (g <= b.gb) {
        final t = (g - a.gb) / (b.gb - a.gb);
        final price = a.price + (b.price - a.price) * t;
        return price.round();
      }
    }
    return points.last.price;
  }

  int _calcPriceRub() {
    final isUnlimited = trafficPack == TrafficPack.unlimited;

    final base = isUnlimited
        ? trafficPack.basePriceRub
        : _basePriceForGb(trafficGb);

    final apps = isUnlimited ? 0 : selectedApps.length * 49;

    final dev = (devices - 1) * 49;
    final extras =
        (optNoAds ? 49 : 0) +
        (optSmartRouting ? 29 : 0) +
        (optDedicatedIp ? 149 : 0);

    final total = base + apps + dev + extras;
    return total < 0 ? 0 : total;
  }

  @override
  Widget build(BuildContext context) {
    final price = _calcPriceRub();

    final appsText = selectedApps.isEmpty
        ? 'Без безлимитных приложений'
        : selectedApps.map((e) => e.title).join(', ');

    final appsDisabled = trafficPack == TrafficPack.unlimited;

    final gbInt = trafficGb.round().clamp(1, 500);
    final baseForGb = appsDisabled
        ? trafficPack.basePriceRub
        : _basePriceForGb(trafficGb);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _PageTitle(
          title: 'Тариф',
          subtitle: 'Гигабайты или безлимит + докупай безлимит на приложения',
          icon: Icons.star_rounded,
        ),
        const SizedBox(height: 12),

        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Трафик'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      appsDisabled ? 'Безлимитный трафик' : 'Трафик: $gbInt ГБ',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ChipButton(
                    icon: Icons.data_usage_rounded,
                    text: 'По ГБ',
                    selected: !appsDisabled,
                    onTap: () => onTrafficChanged(TrafficPack.gb20),
                  ),
                  const SizedBox(width: 8),
                  _ChipButton(
                    icon: Icons.all_inclusive_rounded,
                    text: 'Безлимит',
                    selected: appsDisabled,
                    onTap: () => onTrafficChanged(TrafficPack.unlimited),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: appsDisabled ? 0.45 : 1,
                child: IgnorePointer(
                  ignoring: appsDisabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Slider(
                        value: gbInt.toDouble(),
                        min: 1,
                        max: 500,
                        divisions: 499,
                        label: '$gbInt ГБ',
                        onChanged: (v) => onTrafficGbChanged(v.roundToDouble()),
                      ),
                      Row(
                        children: const [
                          Text(
                            '1 ГБ',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          Spacer(),
                          Text(
                            '500 ГБ',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                appsDisabled
                    ? 'База: $baseForGb ₽ (безлимит)'
                    : 'База: $baseForGb ₽ за $gbInt ГБ',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              if (appsDisabled) ...const [
                SizedBox(height: 10),
                Text(
                  'Выбран “Безлимит” — безлимитные приложения не нужны (и отключены).',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Безлимитные приложения (дёшево)'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: TariffApp.values.map((app) {
                  final on = selectedApps.contains(app);
                  return Opacity(
                    opacity: appsDisabled ? 0.45 : 1,
                    child: IgnorePointer(
                      ignoring: appsDisabled,
                      child: _ChipButton(
                        icon: app.icon,
                        text: app.title,
                        selected: on,
                        onTap: () => onToggleApp(app),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Устройства'),
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    onPressed: () => onDevicesChanged(devices - 1),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$devices',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => onDevicesChanged(devices + 1),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Сколько девайсов одновременно',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Опции'),
              const SizedBox(height: 6),
              _SwitchRow(
                title: 'Без рекламы',
                subtitle: 'Чистый интерфейс в приложении',
                value: optNoAds,
                onChanged: onOptNoAds,
              ),
              const Divider(height: 18),
              _SwitchRow(
                title: 'Умная маршрутизация',
                subtitle: 'Нужные сайты/приложения через VPN',
                value: optSmartRouting,
                onChanged: onOptSmartRouting,
              ),
              const Divider(height: 18),
              _SwitchRow(
                title: 'Выделенный IP',
                subtitle: 'Для своих сервисов/доступов',
                value: optDedicatedIp,
                onChanged: onOptDedicatedIp,
              ),
            ],
          ),
        ),
        const SizedBox(height: 110),
      ],
    );
  }
}

class _GbPricePoint {
  final double gb;
  final int price;
  const _GbPricePoint(this.gb, this.price);
}

/* =========================
   TASKS PAGE (placeholder)
   ========================= */

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderPage(
      title: 'Задания',
      subtitle: 'Позже добавим: бонусы, рефы, промо, ежедневные задания.',
      icon: Icons.checklist_rounded,
    );
  }
}

class SettingsPage extends StatelessWidget {
  final ThemeMode themeMode;
  final void Function(ThemeMode mode) onThemeModeChanged;

  final String language;
  final VoidCallback onPickLanguage;

  final String email;
  final Future<void> Function() onLogout;
  final VoidCallback onOpenDiagnostics;

  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onPickLanguage,
    required this.email,
    required this.onLogout,
    required this.onOpenDiagnostics,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = themeMode == ThemeMode.dark;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const _PageTitle(
            title: 'Настройки',
            subtitle: 'Только косметика и аккаунт',
            icon: Icons.settings_rounded,
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Внешний вид'),
                const SizedBox(height: 8),
                _SwitchRow(
                  title: 'Тёмная тема',
                  subtitle: 'Меняет тему приложения',
                  value: isDark,
                  onChanged: (v) =>
                      onThemeModeChanged(v ? ThemeMode.dark : ThemeMode.light),
                ),
                const Divider(height: 18),
                _SettingsNavRow(
                  title: 'Язык',
                  subtitle: language,
                  icon: Icons.language_rounded,
                  onTap: onPickLanguage,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Аккаунт'),
                const SizedBox(height: 8),
                _SettingsNavRow(
                  title: 'Почта',
                  subtitle: email,
                  icon: Icons.person_rounded,
                  onTap: () {},
                ),
                const Divider(height: 18),
                _SettingsActionRow(
                  title: 'Выйти',
                  subtitle: 'Сбросить сессию на этом устройстве',
                  icon: Icons.logout_rounded,
                  onTap: () => onLogout(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('О приложении'),
                const SizedBox(height: 8),
                _SettingsActionRow(
                  title: 'Диагностика',
                  subtitle: 'Проверка WireGuard, прав и конфигурации',
                  icon: Icons.health_and_safety_rounded,
                  onTap: onOpenDiagnostics,
                ),
                const Divider(height: 18),
                _SettingsActionRow(
                  title: 'О BlueVPN',
                  subtitle: 'UI-прототип. Дальше подключим сервер и подписку.',
                  icon: Icons.info_outline_rounded,
                  onTap: () => _showAbout(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('BlueVPN'),
          content: const Text(
            'Концепция: максимум простоты для пользователя.\n\n'
            'Пользователь не видит конфиги и папки.\n'
            'Конфиг выдаёт сервер после входа.\n',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ок'),
            ),
          ],
        );
      },
    );
  }
}

/* =========================
   UI HELPERS
   ========================= */

class _BottomSheetFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData leading;
  final Widget child;

  const _BottomSheetFrame({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFF111827)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(leading, color: const Color(0xFF2563EB)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _PageTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF2563EB)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: Color(0xFF0F172A),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _SettingsNavRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsNavRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF111827)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurface.withOpacity(0.35),
          ),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsActionRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF111827)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurface.withOpacity(0.35),
          ),
        ],
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _ChipButton({
    required this.icon,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF2563EB) : const Color(0xFFEFF6FF);
    final fg = selected ? Colors.white : const Color(0xFF1E3A8A);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x1A1E3A8A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(color: fg, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _PlaceholderPage({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _Card(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF2563EB)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final Color? tint;

  const _Card({required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x110F172A)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 8),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: child,
    );
  }
}

/* =========================
   DIAGNOSTICS (READ-ONLY)
   ========================= */

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  bool _loading = true;

  String _appDataPath = '';
  String _configPath = '';
  bool _configExists = false;

  bool _isAdmin = false;

  String _wgExe = '';
  bool _wgFound = false;

  String _serviceName = '';
  String _serviceState = 'unknown';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    final app = Platform.environment['APPDATA'] ?? '';
    _appDataPath = app.isEmpty ? '(APPDATA не найден)' : '$app\\BlueVPN';

    final cfg = ConfigStore();
    _configPath = cfg.managedConfigPath;
    _configExists = File(_configPath).existsSync();

    _wgExe = _resolveWireGuardExe();
    _wgFound =
        File(_wgExe).existsSync() || _wgExe.toLowerCase() == 'wireguard.exe';

    _isAdmin = await _isAdminWindows();

    _serviceName = 'WireGuardTunnel\$${kTunnelName}';
    _serviceState = await _queryServiceState(_serviceName);

    if (!mounted) return;
    setState(() => _loading = false);
  }

  static String _resolveWireGuardExe() {
    final candidates = <String>[];

    final pf = Platform.environment['ProgramFiles'];
    final pf86 = Platform.environment['ProgramFiles(x86)'];

    if (pf != null) candidates.add('$pf\\WireGuard\\wireguard.exe');
    if (pf86 != null) candidates.add('$pf86\\WireGuard\\wireguard.exe');

    candidates.add(r'C:\Program Files\WireGuard\wireguard.exe');
    candidates.add(r'C:\Program Files (x86)\WireGuard\wireguard.exe');

    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return 'wireguard.exe';
  }

  static Future<bool> _isAdminWindows() async {
    if (!Platform.isWindows) return false;
    try {
      final res = await Process.run('whoami', ['/groups'], runInShell: true);
      if (res.exitCode != 0) return false;
      final out = (res.stdout ?? '').toString();
      return out.contains('S-1-5-32-544');
    } catch (_) {
      return false;
    }
  }

  static Future<String> _queryServiceState(String serviceName) async {
    if (!Platform.isWindows) return 'unsupported';
    try {
      final res = await Process.run('sc', [
        'query',
        serviceName,
      ], runInShell: true);
      if (res.exitCode != 0) return 'not_installed';
      final out = (res.stdout ?? '').toString();
      if (out.contains('RUNNING')) return 'running';
      if (out.contains('STOPPED')) return 'stopped';
      return 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  void _copyReport() {
    final lines = <String>[
      'BlueVPN Diagnostics',
      'AppData: $_appDataPath',
      'Config: $_configPath',
      'Config exists: $_configExists',
      'WireGuard exe: $_wgExe',
      'WireGuard found: $_wgFound',
      'Admin: $_isAdmin',
      'Service: $_serviceName ($_serviceState)',
    ];

    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Отчёт скопирован в буфер.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Диагностика'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _DiagTile(
                  title: 'WireGuard установлен',
                  value: _wgFound ? 'Да' : 'Нет',
                  subtitle: _wgExe,
                  ok: _wgFound,
                ),
                const SizedBox(height: 10),
                _DiagTile(
                  title: 'Права администратора',
                  value: _isAdmin ? 'Да' : 'Нет',
                  subtitle: _isAdmin
                      ? 'Ок'
                      : 'Для подключения/отключения через wireguard.exe нужны права администратора.\nЗапусти приложение от имени администратора.',
                  ok: _isAdmin,
                ),
                const SizedBox(height: 10),
                _DiagTile(
                  title: 'Конфигурация (скрытая)',
                  value: _configExists ? 'Есть' : 'Нет',
                  subtitle: _configPath,
                  ok: _configExists,
                ),
                const SizedBox(height: 10),
                _DiagTile(
                  title: 'Сервис WireGuard',
                  value: _serviceState,
                  subtitle: _serviceName,
                  ok: _serviceState == 'running' || _serviceState == 'stopped',
                ),
                const SizedBox(height: 14),
                _Card(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.content_copy_rounded,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Скопировать отчёт',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _copyReport,
                        child: const Text('Копировать'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _DiagTile extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final bool ok;

  const _DiagTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: ok ? const Color(0xFFEFF6FF) : const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              ok ? Icons.check_circle_rounded : Icons.error_rounded,
              color: ok ? const Color(0xFF2563EB) : const Color(0xFFDC2626),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.55),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================
   BACKEND (WIREGUARD FOR WINDOWS)
   ========================= */

class VpnBackendResult {
  final bool ok;
  final String? message;
  const VpnBackendResult({required this.ok, this.message});
}

abstract class VpnBackend {
  const VpnBackend();

  Future<VpnBackendResult> connect({required String configPath});
  Future<VpnBackendResult> disconnect();
  Future<bool> isConnected();

  static VpnBackend createDefault({required String tunnelName}) {
    if (kIsWeb) {
      return const UnsupportedVpnBackend(
        reason: 'Web mode: VPN backend is not available.',
      );
    }
    if (Platform.isWindows) {
      return WireGuardWindowsBackend(tunnelName: tunnelName);
    }
    return const UnsupportedVpnBackend(
      reason: 'Unsupported platform (Windows-only backend).',
    );
  }
}

class UnsupportedVpnBackend extends VpnBackend {
  final String reason;
  const UnsupportedVpnBackend({required this.reason});

  @override
  Future<VpnBackendResult> connect({required String configPath}) async =>
      VpnBackendResult(ok: false, message: reason);

  @override
  Future<VpnBackendResult> disconnect() async =>
      VpnBackendResult(ok: false, message: reason);

  @override
  Future<bool> isConnected() async => false;
}

class WireGuardWindowsBackend extends VpnBackend {
  final String tunnelName;
  final String _exe;

  // remember last configPath for cleanup (route removal)
  String? _lastConfigPath;

  WireGuardWindowsBackend({required this.tunnelName})
    : _exe = _resolveWireGuardExe();

  static String _resolveWireGuardExe() {
    final candidates = <String>[];

    final pf = Platform.environment['ProgramFiles'];
    final pf86 = Platform.environment['ProgramFiles(x86)'];

    if (pf != null && pf.trim().isNotEmpty) {
      candidates.add('${pf.trim()}\\WireGuard\\wireguard.exe');
    }
    if (pf86 != null && pf86.trim().isNotEmpty) {
      candidates.add('${pf86.trim()}\\WireGuard\\wireguard.exe');
    }

    candidates.add(r'C:\Program Files\WireGuard\wireguard.exe');
    candidates.add(r'C:\Program Files (x86)\WireGuard\wireguard.exe');

    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return 'wireguard.exe';
  }

  // IMPORTANT: literal '$' must NOT be used with interpolation like $${tunnelName}
  // Use raw string + concat.
  String get _serviceName => r'WireGuardTunnel$' + tunnelName;

  Future<ProcessResult> _run(String exe, List<String> args) async {
    return Process.run(exe, args, runInShell: true);
  }

  List<int> _utf16le(String s) {
    final units = s.codeUnits;
    final bytes = BytesBuilder(copy: false);
    for (final u in units) {
      bytes.addByte(u & 0xFF);
      bytes.addByte((u >> 8) & 0xFF);
    }
    return bytes.toBytes();
  }

  Future<ProcessResult> _runElevatedPowerShell(String innerScript) async {
    // Run innerScript with UAC using -EncodedCommand (UTF-16LE Base64)
    final encoded = base64.encode(_utf16le(innerScript));

    final outer =
        r'''
$ErrorActionPreference="Stop"
$enc="__ENC__"
$p = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy","Bypass",
  "-EncodedCommand",$enc
)
exit $p.ExitCode
'''
            .replaceAll('__ENC__', encoded);

    return _run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      outer,
    ]);
  }

  static String? _extractEndpointIPv4(String cfg) {
    final re = RegExp(
      r'^\s*Endpoint\s*=\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s*:\s*\d+\s*$',
      multiLine: true,
    );
    final m = re.firstMatch(cfg);
    return m?.group(1);
  }

  Future<String?> _configPathForCleanup() async {
    if (_lastConfigPath != null && _lastConfigPath!.trim().isNotEmpty) {
      return _lastConfigPath;
    }
    // best effort: try to parse from sc qc if service exists
    try {
      final res = await _run('sc', ['qc', _serviceName]);
      if (res.exitCode != 0) return null;
      final out = ('${res.stdout}\n${res.stderr}').toString();
      final re = RegExp(r'([A-Za-z]:\\[^"\r\n]+\.conf)', caseSensitive: false);
      return re.firstMatch(out)?.group(1);
    } catch (_) {
      return null;
    }
  }


  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    _lastConfigPath = configPath;
    final logFile = File(r'C:\ProgramData\BlueVPN\backend.log');

    Future<void> log(String s) async {
      try {
        final ts = DateTime.now().toIso8601String();
        await logFile.writeAsString(
          '[' + ts + '] ' + s + '\n',
          mode: FileMode.append,
        );
      } catch (_) {}
    }

    String outOf(ProcessResult r) =>
        ((r.stdout ?? '').toString() + '\n' + (r.stderr ?? '').toString()).trim();

    bool isRunningText(String out) => out.contains('RUNNING');
    Future<ProcessResult> scQueryEx() => _run('sc', ['queryex', _serviceName]);

    Future<bool> waitRunning({int loops = 60}) async {
      for (var i = 0; i < loops; i++) {
        final q = await scQueryEx();
        final o = outOf(q);
        await log('queryex(connect)[$i] ec=${q.exitCode} :: ' + o.replaceAll('\r', ' ').replaceAll('\n', ' | '));
        if (q.exitCode == 0 && isRunningText(o)) return true;
        await Future.delayed(const Duration(milliseconds: 250));
      }
      return false;
    }

    Future<bool> isAdmin() async {
      try {
        final res = await _run('whoami', ['/groups']);
        final out = ((res.stdout ?? '').toString() + '\n' + (res.stderr ?? '').toString());
        return out.contains('S-1-5-32-544');
      } catch (_) {
        return false;
      }
    }

    try {
      await log('=== CONNECT requested ===');
      await log('service=' + _serviceName);
      await log('exe=' + _exe);
      await log('cfg=' + configPath);

      if (!File(configPath).existsSync()) {
        await log('ERROR: configPath does not exist');
        return VpnBackendResult(ok: false, message: 'Config not found: $configPath');
      }

      final q0 = await scQueryEx();
      final o0 = outOf(q0);
      await log('queryex(initial) ec=${q0.exitCode} :: ' + o0.replaceAll('\r', ' ').replaceAll('\n', ' | '));

      final admin = await isAdmin();
      await log('isAdmin=' + admin.toString());

      if (admin) {
        if (q0.exitCode != 0) {
          final ins = await _run(_exe, ['/installtunnelservice', configPath]);
          await log('wireguard install ec=${ins.exitCode} :: ' + outOf(ins).replaceAll('\r', ' ').replaceAll('\n', ' | '));
        }
        final st = await _run('sc', ['start', _serviceName]);
        await log('sc start ec=${st.exitCode} :: ' + outOf(st).replaceAll('\r', ' ').replaceAll('\n', ' | '));
      } else {
        final ps = r'''$ErrorActionPreference = "Stop"
$svc = "__SVC__"
$cfg = "__CFG__"
$wg  = "__WG__"
if (!(Test-Path $cfg)) { throw "Config not found: $cfg" }
sc.exe queryex $svc *> $null
if ($LASTEXITCODE -ne 0) {
  & $wg /installtunnelservice $cfg | Out-Null
}
sc.exe start $svc | Out-Null
'''
            .replaceAll('__SVC__', _serviceName)
            .replaceAll('__CFG__', configPath)
            .replaceAll('__WG__', _exe);

        final elevated = await _runElevatedPowerShell(ps);
        await log('elevated connect ec=${elevated.exitCode} :: ' + outOf(elevated).replaceAll('\r', ' ').replaceAll('\n', ' | '));
      }

      final ok = await waitRunning(loops: 60);
      if (!ok) {
        await log('=== CONNECT FAIL: not RUNNING after wait ===');
        return const VpnBackendResult(ok: false, message: 'VPN did not start (service not RUNNING). See backend.log');
      }

      for (var i = 0; i < 40; i++) {
        final on = await isConnected();
        await log('verify(connect)[$i] isConnected=' + on.toString());
        if (on) {
          await log('=== CONNECT OK ===');
          return const VpnBackendResult(ok: true);
        }
        await Future.delayed(const Duration(milliseconds: 250));
      }

      await log('=== CONNECT FAIL: verify isConnected still false ===');
      return const VpnBackendResult(ok: false, message: 'Service RUNNING but isConnected() false. See backend.log');
    } catch (e) {
      await log('EXCEPTION(connect): ' + e.toString());
      return VpnBackendResult(ok: false, message: 'Connect error: $e (see backend.log)');
    }
  }


  @override
  Future<VpnBackendResult> disconnect() async {
    final logFile = File(r'C:\ProgramData\BlueVPN\backend.log');

    Future<void> log(String s) async {
      try {
        final ts = DateTime.now().toIso8601String();
        await logFile.writeAsString('[' + ts + '] ' + s + '\n', mode: FileMode.append);
      } catch (_) {}
    }

    String outOf(ProcessResult r) =>
        ((r.stdout ?? '').toString() + '\n' + (r.stderr ?? '').toString()).trim();

    bool isStoppedText(String out) => out.contains('STOPPED');
    Future<ProcessResult> scQueryEx() => _run('sc', ['queryex', _serviceName]);

    Future<bool> waitStopped({int loops = 40}) async {
      for (var i = 0; i < loops; i++) {
        final q = await scQueryEx();
        final o = outOf(q);
        await log('queryex[$i] ec=${q.exitCode} :: ' + o.replaceAll('\r', ' ').replaceAll('\n', ' | '));
        if (q.exitCode != 0) return true;
        if (isStoppedText(o)) return true;
        await Future.delayed(const Duration(milliseconds: 250));
      }
      return false;
    }

    Future<bool> isAdmin() async {
      try {
        final res = await _run('whoami', ['/groups']);
        final out = ((res.stdout ?? '').toString() + '\n' + (res.stderr ?? '').toString());
        return out.contains('S-1-5-32-544');
      } catch (_) {
        return false;
      }
    }

    try {
      await log('=== DISCONNECT requested ===');
      await log('service=' + _serviceName);
      final admin = await isAdmin();
      await log('isAdmin=' + admin.toString());

      if (admin) {
        final stop = await _run('sc', ['stop', _serviceName]);
        await log('sc stop ec=${stop.exitCode} :: ' + outOf(stop).replaceAll('\r', ' ').replaceAll('\n', ' | '));
        final un = await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
        await log('wireguard uninstall ec=${un.exitCode} :: ' + outOf(un).replaceAll('\r', ' ').replaceAll('\n', ' | '));
      } else {
        final ps = r'''$ErrorActionPreference = "SilentlyContinue"
$svc = "__SVC__"
$wg  = "__WG__"
sc.exe stop $svc | Out-Null
Start-Sleep -Milliseconds 700
& $wg /uninstalltunnelservice __TUN__ | Out-Null
'''
            .replaceAll('__SVC__', _serviceName)
            .replaceAll('__WG__', _exe)
            .replaceAll('__TUN__', tunnelName);
        final elevated = await _runElevatedPowerShell(ps);
        await log('elevated disconnect ec=${elevated.exitCode} :: ' + outOf(elevated).replaceAll('\r', ' ').replaceAll('\n', ' | '));
      }

      final stopped = await waitStopped(loops: 40);
      if (!stopped) {
        await log('=== DISCONNECT FAIL: still RUNNING ===');
        return const VpnBackendResult(ok: false, message: 'Service still RUNNING after stop/uninstall. See backend.log');
      }

      await log('=== DISCONNECT OK ===');
      return const VpnBackendResult(ok: true);
    } catch (e) {
      await log('EXCEPTION: ' + e.toString());
      return VpnBackendResult(ok: false, message: 'Disconnect error: $e (see backend.log)');
    }
  }

  @override
  Future<bool> isConnected() async {
    try {
      final res = await _run('sc', ['query', _serviceName]);
      if (res.exitCode != 0) return false;
      final out = (res.stdout ?? '').toString();
      return out.contains('RUNNING');
    } catch (_) {
      return false;
    }
  }
}
