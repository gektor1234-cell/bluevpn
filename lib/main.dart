// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

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
  ThemeMode _themeMode = ThemeMode.light;

  void _setThemeMode(ThemeMode mode) => setState(() => _themeMode = mode);

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
  Future<String> _baseDir() async {
    final base = Platform.environment['APPDATA'];
    final dir = Directory(
      base != null && base.isNotEmpty
          ? '$base\\BlueVPN\\configs'
          : 'BlueVPN\\configs',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<String> managedConfigPath() async {
    final dir = await _baseDir();
    return '$dir\\$kTunnelName.conf';
  }

  Future<bool> hasManagedConfig() async {
    if (kIsWeb) return false;
    final p = await managedConfigPath();
    return File(p).existsSync();
  }

  Future<void> writeManagedConfig(String configText) async {
    if (kIsWeb) return;
    final p = await managedConfigPath();
    await File(p).writeAsString(configText);
  }

  Future<void> deleteManagedConfig() async {
    if (kIsWeb) return;
    try {
      final p = await managedConfigPath();
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

/* =========================
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

  void goToTab(int i) => setState(() => _index = i);

  @override
  void initState() {
    super.initState();
    _vpnBackend = VpnBackend.createDefault(tunnelName: kTunnelName);
    _syncVpnStatus();
    _ensureProvisionedConfigSilently();
    _syncPlanSilently();
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
    // Для разработки без сервера: если есть локальный конфиг (например на Desktop),
    // мы тихо копируем его в managed-config (AppData\BlueVPN\configs\BlueVPN.conf).
    if (kIsWeb) return false;

    final home = Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return false;

    final candidates = <String>[
      '$home\\Desktop\\$kTunnelName.conf',
      '$home\\Downloads\\$kTunnelName.conf',
      '$home\\Desktop\\BlueVPN.conf',
      '$home\\Downloads\\BlueVPN.conf',
    ];

    for (final p in candidates) {
      final f = File(p);
      if (!f.existsSync()) continue;
      try {
        final cfg = await f.readAsString();
        if (cfg.trim().isEmpty) continue;
        await _cfg.writeManagedConfig(cfg);
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
      final has = await _cfg.hasManagedConfig();
      if (has) return;

      // DEV режим: без сервера попробуем подхватить локальный конфиг (Desktop/Downloads)
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
        await _cfg.writeManagedConfig(res.data!);
      }
    } catch (_) {}
  }

  Future<bool> _ensureProvisionedConfigInteractive() async {
    if (kIsWeb) return false;
    if (await _cfg.hasManagedConfig()) return true;

    if (widget.session.accessToken == 'dev-token') {
      final ok = await _trySeedDevConfig(showToast: true);
      if (ok) return true;
      _toast(
        context,
        'DEV: не найден локальный конфиг. Положи $kTunnelName.conf на Desktop/Downloads или подними сервер.',
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
    await _cfg.writeManagedConfig(res.data!);
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

        final configPath = await _cfg.managedConfigPath();
        final res = await _vpnBackend.connect(configPath: configPath);
        if (!res.ok) {
          _toast(context, res.message ?? 'Не удалось подключить VPN.');
          await _syncVpnStatus();
          return;
        }

        await _syncVpnStatus();
        _toast(context, 'VPN включён.');
      } else {
        final res = await _vpnBackend.disconnect();
        if (!res.ok) {
          _toast(context, res.message ?? 'Не удалось отключить VPN.');
          await _syncVpnStatus();
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
    final picked = await showModalBottomSheet<ServerLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bg = theme.colorScheme.surface;

        return _BottomSheetFrame(
          title: 'Выбор сервера',
          subtitle: 'Пока UI. Позже подключим реальные локации.',
          leading: Icons.bolt_rounded,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.62,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                ),
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                  itemCount: servers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final s = servers[i];
                    final selected = s.id == selectedServer.id;

                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(ctx).pop(s),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x140F172A)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: theme.brightness == Brightness.dark
                                    ? const Color(0xFF111827)
                                    : const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                s.isAuto
                                    ? Icons.auto_awesome_rounded
                                    : Icons.public_rounded,
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.title,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    s.isAuto
                                        ? 'Авто-подбор'
                                        : '${s.subtitle}${s.pingMs != null ? ' • ${s.pingMs} ms' : ''}',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.65),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.chevron_right_rounded,
                              color: selected
                                  ? const Color(0xFF2563EB)
                                  : theme.colorScheme.onSurface.withOpacity(
                                      0.35,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );

    if (picked != null) {
      setState(() => selectedServer = picked);
    }
  }

  Future<void> _openSocialAppsPicker(BuildContext context) async {
    // локальная копия выбора
    final initial = Set<SocialApp>.from(socialOnlyApps);

    final picked = await showModalBottomSheet<Set<SocialApp>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _BottomSheetFrame(
          title: 'Соцсети через VPN',
          subtitle: 'Выбери приложения, которые пойдут через VPN.',
          leading: Icons.filter_alt_rounded,
          child: StatefulBuilder(
            builder: (context, setLocal) {
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.66,
                minChildSize: 0.45,
                maxChildSize: 0.92,
                builder: (_, controller) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView(
                            controller: controller,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            children: [
                              ...SocialApp.values.map((app) {
                                final on = initial.contains(app);
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0x140F172A),
                                    ),
                                    color:
                                        Theme.of(ctx).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFFF8FAFC),
                                  ),
                                  child: SwitchListTile(
                                    value: on,
                                    onChanged: (v) {
                                      setLocal(() {
                                        if (v) {
                                          initial.add(app);
                                        } else {
                                          initial.remove(app);
                                        }
                                      });
                                    },
                                    secondary: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color:
                                            Theme.of(ctx).brightness ==
                                                Brightness.dark
                                            ? const Color(0xFF111827)
                                            : const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        app.icon,
                                        color: const Color(0xFF2563EB),
                                      ),
                                    ),
                                    title: Text(
                                      app.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      'Трафик этого приложения пойдёт через VPN',
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(null),
                                  child: const Text(
                                    'Отмена',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: () {
                                    if (initial.isEmpty) {
                                      _toast(
                                        ctx,
                                        'Выбери хотя бы одно приложение.',
                                      );
                                      return;
                                    }
                                    Navigator.of(ctx).pop(initial);
                                  },
                                  child: const Text(
                                    'Готово',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        socialOnlyApps
          ..clear()
          ..addAll(picked);
      });
    }
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
        socialOnlyAllowed: optSmartRouting, // привязка к тарифу
        socialOnlyApps: socialOnlyApps,
        onToggleSocialOnly: (v) {
          if (!optSmartRouting) {
            _toast(
              context,
              'Недоступно в текущей подписке. Включи “Умную маршрутизацию” в тарифе.',
            );
            return;
          }
          setState(() => socialOnlyEnabled = v);
        },
        onConfigureSocialApps: () {
          if (!optSmartRouting) {
            _toast(
              context,
              'Недоступно в текущей подписке. Включи “Умную маршрутизацию” в тарифе.',
            );
            return;
          }
          _openSocialAppsPicker(context);
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
        },
        onTrafficChanged: (p) => setState(() => trafficPack = p),
        onTrafficGbChanged: (gb) => setState(() => trafficGb = gb),
        onDevicesChanged: (v) => setState(() => devices = v.clamp(1, 5)),
        onOptNoAds: (v) => setState(() => optNoAds = v),
        onOptSmartRouting: (v) {
          setState(() {
            optSmartRouting = v;

            // если отключили smart routing — “соцсети” становятся недоступны, гасим их
            if (!optSmartRouting) {
              socialOnlyEnabled = false;
            }
          });
        },
        onOptDedicatedIp: (v) => setState(() => optDedicatedIp = v),
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
          onSelect: (v) => setState(() => sLanguage = v),
        ),
        email: widget.session.email,
        onLogout: widget.onLogout,
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

    final disabledOverlay = !socialOnlyAllowed
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x220F172A)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 16, color: Color(0xFF64748B)),
                SizedBox(width: 6),
                Text(
                  'Требуется “Умная маршрутизация”',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TariffBanner(onTap: onOpenTariff, planName: planName),
        const SizedBox(height: 18),

        // Центральный блок (переключатель + статус)
        SizedBox(
          height: 220,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BigToggle(enabled: vpnEnabled, onTap: onToggleVpn),
                const SizedBox(height: 14),
                Text(
                  statusText,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Только для соцсетей
        _Card(
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Только для соц. сетей',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                  Switch(
                    value: socialOnlyEnabled,
                    onChanged: socialOnlyAllowed
                        ? onToggleSocialOnly
                        : (_) => onToggleSocialOnly(false),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      socialOnlyEnabled
                          ? 'Через VPN: $appsText'
                          : 'Выбери приложения (если доступно в подписке)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: (socialOnlyAllowed && socialOnlyEnabled)
                            ? onConfigureSocialApps
                            : null,
                        child: const Text(
                          'Настроить',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (!socialOnlyAllowed)
                        Positioned(right: 0, child: disabledOverlay),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Сервер
        _Card(
          tint: const Color(0xFFEFF6FF),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpenServerPicker,
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Color(0xFF2563EB)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Сервер',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        serverTitle,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
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
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF2563EB),
                ),
              ],
            ),
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
    final bg = enabled ? const Color(0xFF2563EB) : const Color(0xFF334155);
    final knob = enabled ? const Color(0xFFEFF6FF) : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 210,
        height: 72,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(40),
          boxShadow: const [
            BoxShadow(
              blurRadius: 18,
              offset: Offset(0, 10),
              color: Color(0x22000000),
            ),
          ],
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: knob, shape: BoxShape.circle),
                child: Icon(
                  enabled ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: enabled
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF334155),
                  size: 30,
                ),
              ),
            ),
          ],
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

  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onPickLanguage,
    required this.email,
    required this.onLogout,
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
        reason:
            'Web-режим: реальное подключение недоступно. Запусти как Windows.',
      );
    }
    if (Platform.isWindows)
      return WireGuardWindowsBackend(tunnelName: tunnelName);
    return const UnsupportedVpnBackend(
      reason: 'Платформа не поддерживается (пока сделано под Windows).',
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

  WireGuardWindowsBackend({required this.tunnelName})
    : _exe = _resolveWireGuardExe();

  static String _resolveWireGuardExe() {
    final candidates = <String>[];

    final pf = Platform.environment['ProgramFiles'];
    final pf86 = Platform.environment['ProgramFiles(x86)'];

    if (pf != null) candidates.add('$pf\WireGuard\wireguard.exe');
    if (pf86 != null) candidates.add('$pf86\WireGuard\wireguard.exe');

    candidates.add(r'C:\Program Files\WireGuard\wireguard.exe');
    candidates.add(r'C:\Program Files (x86)\WireGuard\wireguard.exe');

    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return 'wireguard.exe';
  }

  String get _serviceName => 'WireGuardTunnel\$${tunnelName}';

  Future<ProcessResult> _run(String exe, List<String> args) async {
    return Process.run(exe, args, runInShell: true);
  }

  Future<bool> _isAdmin() async {
    // Админ-группа BUILTIN\Administrators имеет SID S-1-5-32-544
    try {
      final res = await _run('whoami', ['/groups']);
      if (res.exitCode != 0) return false;
      final out = (res.stdout ?? '').toString();
      return out.contains('S-1-5-32-544');
    } catch (_) {
      return false;
    }
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
    // Запускаем PowerShell с UAC один раз и выполняем innerScript внутри.
    // Чтобы не мучиться с кавычками — используем -EncodedCommand (UTF-16LE + Base64).
    final encoded = base64.encode(_utf16le(innerScript));

    final outer =
        r"""
$ErrorActionPreference = "Stop"
$encoded = "ENCODED_PAYLOAD"
$p = Start-Process -FilePath "powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy","Bypass",
  "-EncodedCommand",$encoded
)
exit $p.ExitCode
"""
            .replaceAll('ENCODED_PAYLOAD', encoded);

    return Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      outer,
    ], runInShell: true);
  }

  Future<VpnBackendResult> _ensureWireGuardPresent() async {
    // Проверка: если путь абсолютный — проверим файл.
    final isAbs = _exe.contains(':\\') || _exe.startsWith(r'\\');
    if (isAbs && !File(_exe).existsSync()) {
      return VpnBackendResult(
        ok: false,
        message:
            'WireGuard не найден по пути:\n$_exe\n\nУстанови WireGuard for Windows и попробуй снова.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  String _psQuote(String s) => s.replaceAll('"', '`"');

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    final wgCheck = await _ensureWireGuardPresent();
    if (!wgCheck.ok) return wgCheck;

    if (!File(configPath).existsSync()) {
      return VpnBackendResult(
        ok: false,
        message: 'Конфиг не найден:\n$configPath',
      );
    }

    try {
      // Всегда делаем "обновление" туннеля (чтобы конфиг точно применился)
      if (await _isAdmin()) {
        // Админ уже есть — делаем без UAC и с нормальными stdout/stderr
        await _run('sc', ['stop', _serviceName]);
        await _run(_exe, ['/uninstalltunnelservice', tunnelName]);

        final res = await _run(_exe, ['/installtunnelservice', configPath]);
        if (res.exitCode != 0) {
          final out = (res.stdout ?? '').toString().trim();
          final err = (res.stderr ?? '').toString().trim();
          return VpnBackendResult(
            ok: false,
            message: 'WireGuard не поднялся.\n${err.isNotEmpty ? err : out}',
          );
        }

        await _run('sc', ['start', _serviceName]);
      } else {
        // Нет админа — попросим UAC ОДИН раз и сделаем всё внутри elevated PowerShell.
        final inner =
            r"""
$ErrorActionPreference = "Stop"
$exe  = "EXE"
$cfg  = "CFG"
$tn   = "TN"
$svc  = "SVC"

# stop (ignore errors)
sc.exe stop $svc | Out-Null

# uninstall old (ignore errors)
& $exe /uninstalltunnelservice $tn | Out-Null

# install new
& $exe /installtunnelservice $cfg | Out-Null

# start
sc.exe start $svc | Out-Null
"""
                .replaceAll('EXE', _psQuote(_exe))
                .replaceAll('CFG', _psQuote(configPath))
                .replaceAll('TN', _psQuote(tunnelName))
                .replaceAll('SVC', _psQuote(_serviceName));

        final pr = await _runElevatedPowerShell(inner);
        if (pr.exitCode != 0) {
          final err = (pr.stderr ?? '').toString().trim();
          final out = (pr.stdout ?? '').toString().trim();
          final msg = (err + '\n' + out).trim();
          if (msg.toLowerCase().contains('canceled') ||
              msg.toLowerCase().contains('отмен')) {
            return const VpnBackendResult(
              ok: false,
              message: 'Операция отменена (UAC).',
            );
          }
          return VpnBackendResult(
            ok: false,
            message: msg.isEmpty
                ? 'Не удалось выполнить команду WireGuard (UAC).'
                : msg,
          );
        }
      }

      final ok = await isConnected();
      if (!ok) {
        return const VpnBackendResult(
          ok: false,
          message: 'Туннель установлен, но сервис не RUNNING.',
        );
      }
      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'Ошибка WireGuard: $e');
    }
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    final wgCheck = await _ensureWireGuardPresent();
    if (!wgCheck.ok) return wgCheck;

    try {
      if (await _isAdmin()) {
        await _run('sc', ['stop', _serviceName]);
        final res = await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
        if (res.exitCode != 0) {
          final out = (res.stdout ?? '').toString().trim();
          final err = (res.stderr ?? '').toString().trim();
          return VpnBackendResult(
            ok: false,
            message: 'WireGuard не отключился.\n${err.isNotEmpty ? err : out}',
          );
        }
      } else {
        final inner =
            r"""
$ErrorActionPreference = "Stop"
$exe  = "EXE"
$tn   = "TN"
$svc  = "SVC"

sc.exe stop $svc | Out-Null
& $exe /uninstalltunnelservice $tn | Out-Null
"""
                .replaceAll('EXE', _psQuote(_exe))
                .replaceAll('TN', _psQuote(tunnelName))
                .replaceAll('SVC', _psQuote(_serviceName));

        final pr = await _runElevatedPowerShell(inner);
        if (pr.exitCode != 0) {
          final err = (pr.stderr ?? '').toString().trim();
          final out = (pr.stdout ?? '').toString().trim();
          final msg = (err + '\n' + out).trim();
          if (msg.toLowerCase().contains('canceled') ||
              msg.toLowerCase().contains('отмен')) {
            return const VpnBackendResult(
              ok: false,
              message: 'Операция отменена (UAC).',
            );
          }
          return VpnBackendResult(
            ok: false,
            message: msg.isEmpty
                ? 'Не удалось отключить WireGuard (UAC).'
                : msg,
          );
        }
      }

      final ok = await isConnected();
      if (ok) {
        return const VpnBackendResult(
          ok: false,
          message: 'Сервис всё ещё RUNNING после отключения.',
        );
      }
      return const VpnBackendResult(ok: true);
    } catch (e) {
      return VpnBackendResult(
        ok: false,
        message: 'Ошибка отключения WireGuard: $e',
      );
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
