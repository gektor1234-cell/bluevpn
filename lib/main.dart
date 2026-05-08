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
  Green VPN — режим "как пользовательский продукт":
  - Первый запуск: регистрация/вход (через сервер)
  - Дальше: авто-вход по сохранённой сессии
  - Пользователь НЕ видит: конфиги/папки/импорт/экспорт/профили
  - Конфиг выдаёт сервер (provision), хранится внутри AppData (скрыто)

  ВАЖНО: в VPN-экране НЕТ карточки "Профиль" (дырка закрыта).
*/

const String kTunnelName = 'BlueVPNDev1';
const String kProductName = 'Green VPN';
const String kIntelligentSmewHost = '37.220.85.211';
const String kAppVersion = '0.2.2-windows-mvp';

const String kApiBaseUrl = String.fromEnvironment(
  'BLUEVPN_API_BASE_URL',
  defaultValue: 'https://api.greenvpn.pro',
);

const String kBuildMarker = 'bluevpn-safety-runtime-20260428-2355';

const Color kBrandPrimary = Color(0xFF12A36F);
const Color kBrandPrimaryDeep = Color(0xFF08785D);
const Color kBrandPrimarySoft = Color(0xFFE7F7EF);
const Color kBrandAccent = Color(0xFF1FA9D8);
const Color kBrandLightBg = Color(0xFFF4F7F5);
const Color kBrandDarkBg = Color(0xFF071A14);
const Color kBrandDarkSurface = Color(0xFF0C241C);
const Color kBrandText = Color(0xFF101828);
const Color kBrandMuted = Color(0xFF667085);
const Color kBrandWarm = Color(0xFFFACC15);
const Color kBrandDanger = Color(0xFFE5484D);

class _LocalConfigCandidate {
  final String path;
  final String content;

  const _LocalConfigCandidate({required this.path, required this.content});
}

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await appendBlueVpnClientLog('main start build=$kBuildMarker');

      final startupReady = await ensureWindowsStartupReady();
      await appendBlueVpnClientLog('main startupReady=$startupReady');
      if (!startupReady) return;

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
    ThemeData buildTheme(Brightness brightness) {
      final isDark = brightness == Brightness.dark;
      final scheme = ColorScheme.fromSeed(
        seedColor: kBrandPrimary,
        brightness: brightness,
      );

      return ThemeData(
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        colorScheme: scheme,
        scaffoldBackgroundColor: isDark ? kBrandDarkBg : kBrandLightBg,
      ).copyWith(
        dividerColor: scheme.onSurface.withOpacity(isDark ? 0.18 : 0.10),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark ? kBrandDarkSurface : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: scheme.onSurface.withOpacity(isDark ? 0.18 : 0.12),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: scheme.onSurface.withOpacity(isDark ? 0.18 : 0.12),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBrandPrimary, width: 1.4),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kBrandPrimary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: scheme.onSurface.withOpacity(0.10),
            disabledForegroundColor: scheme.onSurface.withOpacity(0.42),
            elevation: 0,
            shadowColor: kBrandPrimary.withOpacity(0.22),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? Colors.white : kBrandPrimaryDeep,
            side: BorderSide(
              color: scheme.onSurface.withOpacity(isDark ? 0.22 : 0.16),
            ),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? (isDark ? const Color(0xFFB8F5D8) : Colors.white)
                : (isDark ? const Color(0xFF607068) : null),
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? kBrandPrimary
                : scheme.onSurface.withOpacity(isDark ? 0.18 : 0.12),
          ),
          trackOutlineColor: WidgetStatePropertyAll(
            scheme.onSurface.withOpacity(isDark ? 0.22 : 0.12),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: kBrandPrimary,
          inactiveTrackColor: kBrandPrimary.withOpacity(isDark ? 0.20 : 0.16),
          thumbColor: kBrandPrimary,
          overlayColor: kBrandPrimary.withOpacity(0.14),
          valueIndicatorColor: kBrandPrimaryDeep,
          valueIndicatorTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    final light = buildTheme(Brightness.light);
    final dark = buildTheme(Brightness.dark);

    return MaterialApp(
      title: kProductName,
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
  bool _openSessionDirectly = false;
  String _loadingStage = 'Запускаем Green VPN...';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final startedAt = DateTime.now();
    await appendBlueVpnClientLog('bootstrap load start');
    if (mounted) {
      setState(() => _loadingStage = 'Проверяем системный компонент...');
    }
    await _resumeStartupDisconnectIfNeeded();
    if (mounted) {
      setState(() => _loadingStage = 'Проверяем сохранённую сессию...');
    }
    final s = await _sessionStore.read();
    await appendBlueVpnClientLog(
      'bootstrap session=${s == null ? "none" : "present"}',
    );
    if (s == null && !kIsWeb && Platform.isWindows) {
      try {
        if (mounted) {
          setState(() => _loadingStage = 'Готовим сетевой слой...');
        }
        final backend = VpnBackend.createDefault(tunnelName: kTunnelName);
        await backend.disconnect();
      } catch (_) {}
    }
    final elapsed = DateTime.now().difference(startedAt);
    const minBootTime = Duration(milliseconds: 850);
    if (elapsed < minBootTime) {
      await Future<void>.delayed(minBootTime - elapsed);
    }
    if (!mounted) return;
    setState(() {
      _loadingStage = 'Открываем приложение...';
      _session = s;
      _loading = false;
    });
  }

  Future<void> _resumeStartupDisconnectIfNeeded() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final pendingStore = PendingVpnActionStore();
      final action = await pendingStore.read();
      if (action != 'disconnect') return;

      final backend = VpnBackend.createDefault(tunnelName: kTunnelName);
      final res = await backend.disconnect();
      if (res.ok) {
        await pendingStore.clear();
      }
    } catch (_) {}
  }

  Future<void> _onAuthSuccess(Session s) async {
    await _sessionStore.write(s);
    if (!mounted) return;
    setState(() {
      _session = s;
      _openSessionDirectly = true;
    });
  }

  Future<void> _logout() async {
    await _sessionStore.clear();
    await ConfigStore().deleteManagedConfig(); // скрыто от пользователя
    if (!mounted) return;
    setState(() {
      _session = null;
      _openSessionDirectly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _CenteredLoading(stage: _loadingStage);

    if (_session == null) {
      return AuthPage(onAuthSuccess: _onAuthSuccess);
    }

    final shell = RootShell(
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
      session: _session!,
      onLogout: _logout,
    );
    if (_openSessionDirectly) return shell;

    return SessionGatePage(
      session: _session!,
      onUseCurrentSession: () {
        if (!mounted) return;
        setState(() => _openSessionDirectly = true);
      },
      onUseAnotherAccount: _logout,
      child: shell,
    );
  }
}

class _CenteredLoading extends StatelessWidget {
  final String stage;

  const _CenteredLoading({required this.stage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? kBrandDarkSurface : Colors.white;
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = textColor.withOpacity(0.62);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF06130F), Color(0xFF0B2A20)]
                : const [Color(0xFFF7FBF8), Color(0xFFE9F8F0)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: kBrandPrimary.withOpacity(0.14)),
                  boxShadow: [
                    BoxShadow(
                      color: kBrandPrimaryDeep.withOpacity(
                        isDark ? 0.22 : 0.10,
                      ),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: kBrandPrimarySoft,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.vpn_key_rounded,
                            color: kBrandPrimary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Green VPN',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Готовим защищённое подключение',
                                style: TextStyle(
                                  color: mutedColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        backgroundColor: kBrandPrimary.withOpacity(0.10),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          kBrandPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      stage,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Обычно это занимает пару секунд. Если Windows готовит сетевой компонент, приложение само продолжит загрузку.',
                      style: TextStyle(
                        color: mutedColor,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
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

class SessionGatePage extends StatefulWidget {
  final Session session;
  final Future<void> Function() onUseAnotherAccount;
  final VoidCallback onUseCurrentSession;
  final Widget child;

  const SessionGatePage({
    super.key,
    required this.session,
    required this.onUseAnotherAccount,
    required this.onUseCurrentSession,
    required this.child,
  });

  @override
  State<SessionGatePage> createState() => _SessionGatePageState();
}

class _SessionGatePageState extends State<SessionGatePage> {
  bool _enterApp = false;
  bool _busy = false;

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _enterApp = true;
    });
    widget.onUseCurrentSession();
  }

  Future<void> _switchAccount() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onUseAnotherAccount();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_enterApp) return widget.child;

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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: kBrandPrimarySoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.vpn_key_rounded,
                            color: kBrandPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kProductName,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Выбери, как открыть приложение',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: kBrandMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBF8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x1A08785D)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Сохранённая сессия',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: kBrandMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.session.email,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: kBrandText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Если это твой аккаунт, можно продолжить. Если устройство новое или нужен другой аккаунт, открой экран входа.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: kBrandMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _continue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrandPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _busy
                              ? 'Подождите…'
                              : 'Продолжить как ${widget.session.email}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _switchAccount,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Войти или зарегистрироваться',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
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
   AUTH MODELS + STORAGE
   ========================= */

class Session {
  final String accessToken;
  final String email;
  final bool emailVerified;
  final bool emailConfirmationRequired;
  final String? phone;
  final bool phoneVerified;

  const Session({
    required this.accessToken,
    required this.email,
    this.emailVerified = false,
    this.emailConfirmationRequired = false,
    this.phone,
    this.phoneVerified = false,
  });

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'email': email,
    'emailVerified': emailVerified,
    'emailConfirmationRequired': emailConfirmationRequired,
    'phone': phone,
    'phoneVerified': phoneVerified,
  };

  static Session fromJson(Map<String, dynamic> json) {
    return Session(
      accessToken: (json['accessToken'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      emailVerified: json['emailVerified'] == true,
      emailConfirmationRequired: json['emailConfirmationRequired'] == true,
      phone: json['phone']?.toString(),
      phoneVerified: json['phoneVerified'] == true,
    );
  }

  Session copyWith({
    String? accessToken,
    String? email,
    bool? emailVerified,
    bool? emailConfirmationRequired,
    String? phone,
    bool? phoneVerified,
  }) {
    return Session(
      accessToken: accessToken ?? this.accessToken,
      email: email ?? this.email,
      emailVerified: emailVerified ?? this.emailVerified,
      emailConfirmationRequired:
          emailConfirmationRequired ?? this.emailConfirmationRequired,
      phone: phone ?? this.phone,
      phoneVerified: phoneVerified ?? this.phoneVerified,
    );
  }
}

class WindowsLocalSecurity {
  const WindowsLocalSecurity._();

  static Future<String?> _currentUserSid() async {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      final sidRes = await Process.run('whoami', [
        '/user',
        '/fo',
        'csv',
        '/nh',
      ]);
      final columns = (sidRes.stdout ?? '')
          .toString()
          .trim()
          .split(',')
          .map((v) => v.replaceAll('"', '').trim())
          .toList();
      final sidCandidates = columns.where((v) => v.startsWith('S-1-')).toList();
      return sidCandidates.isEmpty ? null : sidCandidates.last;
    } catch (_) {
      return null;
    }
  }

  static Future<void> repairDirectoryAcl(String path) async {
    if (kIsWeb || !Platform.isWindows || path.trim().isEmpty) return;
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return;
      final userSid = await _currentUserSid();
      if (userSid == null) return;

      // Important: never remove inherited permissions here. The previous
      // hardening was too aggressive and could lock BlueVPN out of AppData.
      await Process.run('icacls', [
        dir.path,
        '/inheritance:e',
        '/grant',
        '*$userSid:(OI)(CI)(F)',
        '*S-1-5-18:(OI)(CI)(F)',
        '*S-1-5-32-544:(OI)(CI)(F)',
        '/T',
      ], runInShell: true);
    } catch (_) {}
  }

  static Future<void> repairBlueVpnLocalAcls() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.trim().isNotEmpty) {
        await repairDirectoryAcl('$appData\\BlueVPN');
      }
      final programData = Platform.environment['ProgramData'];
      if (programData != null && programData.trim().isNotEmpty) {
        await repairDirectoryAcl('$programData\\BlueVPN');
      }
    } catch (_) {}
  }

  static Future<String> _runPowerShellWithStdin(
    String script,
    String stdinText,
  ) async {
    final p = await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ], runInShell: false);

    p.stdin.write(stdinText);
    await p.stdin.close();

    final stdoutFuture = p.stdout.transform(utf8.decoder).join();
    final stderrFuture = p.stderr.transform(utf8.decoder).join();
    late final List<Object?> result;
    try {
      result = await Future.wait<Object?>([
        stdoutFuture,
        stderrFuture,
        p.exitCode,
      ]).timeout(const Duration(seconds: 4));
    } on TimeoutException {
      p.kill(ProcessSignal.sigkill);
      throw TimeoutException('PowerShell DPAPI timeout');
    }

    final stdoutText = (result[0] ?? '').toString();
    final stderrText = (result[1] ?? '').toString();
    final code = result[2] as int;
    if (code != 0) {
      throw Exception('PowerShell failed ($code): $stderrText');
    }
    return stdoutText.trimRight();
  }

  static Future<String?> protectString(String plain) async {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      const script = r'''
$plain = [Console]::In.ReadToEnd()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($plain)
$entropy = [System.Text.Encoding]::UTF8.GetBytes('BlueVPN-Machine-v1')
$protected = [System.Security.Cryptography.ProtectedData]::Protect(
  $bytes,
  $entropy,
  [System.Security.Cryptography.DataProtectionScope]::LocalMachine
)
[Convert]::ToBase64String($protected)
''';
      final encrypted = await _runPowerShellWithStdin(script, plain);
      return encrypted.trim().isEmpty ? null : encrypted.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> unprotectString(String encrypted) async {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      const script = r'''
$encrypted = [Console]::In.ReadToEnd().Trim()
$bytes = [Convert]::FromBase64String($encrypted)
$entropy = [System.Text.Encoding]::UTF8.GetBytes('BlueVPN-Machine-v1')
$plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
  $bytes,
  $entropy,
  [System.Security.Cryptography.DataProtectionScope]::LocalMachine
)
[System.Text.Encoding]::UTF8.GetString($plain)
''';
      return await _runPowerShellWithStdin(script, encrypted);
    } catch (_) {
      try {
        const legacyScript = r'''
$encrypted = [Console]::In.ReadToEnd().Trim()
$secure = ConvertTo-SecureString -String $encrypted
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
''';
        return await _runPowerShellWithStdin(legacyScript, encrypted);
      } catch (_) {
        return null;
      }
    }
  }

  static Future<void> hardenPath(
    String path, {
    bool directory = false,
    bool hidden = true,
    bool privateAcl = true,
  }) async {
    if (kIsWeb || !Platform.isWindows || path.trim().isEmpty) return;
    try {
      final typeFlag = directory ? '+h +s' : '+h';
      if (hidden) {
        await Process.run('attrib', [
          ...typeFlag.split(' '),
          path,
        ], runInShell: true);
      }

      if (!privateAcl) return;
      final userSid = await _currentUserSid();
      if (userSid == null) return;

      final grants = directory
          ? [
              '*$userSid:(OI)(CI)(F)',
              '*S-1-5-18:(OI)(CI)(F)',
              '*S-1-5-32-544:(OI)(CI)(F)',
            ]
          : ['*$userSid:(F)', '*S-1-5-18:(F)', '*S-1-5-32-544:(F)'];
      await Process.run('icacls', [
        path,
        '/grant',
        ...grants,
      ], runInShell: true);
    } catch (_) {}
  }

  static Future<void> repairBlueVpnAppDataAcl() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final base = Platform.environment['APPDATA'];
      if (base == null || base.trim().isEmpty) return;
      final dir = Directory('$base\\BlueVPN');
      if (!dir.existsSync()) return;
      await repairDirectoryAcl(dir.path);
    } catch (_) {}
  }

  static Future<void> prepareSharedStateDirectory(String path) async {
    if (kIsWeb || !Platform.isWindows || path.trim().isEmpty) return;
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return;
      await Process.run('attrib', ['+h', '+s', dir.path], runInShell: true);
      await Process.run('icacls', [
        dir.path,
        '/inheritance:e',
        '/grant',
        '*S-1-5-11:(OI)(CI)(M)',
        '*S-1-5-18:(OI)(CI)(F)',
        '*S-1-5-32-544:(OI)(CI)(F)',
        '/T',
      ], runInShell: true);
    } catch (_) {}
  }

  static Future<void> prepareSharedStateFile(String path) async {
    if (kIsWeb || !Platform.isWindows || path.trim().isEmpty) return;
    try {
      await Process.run('attrib', ['+h', path], runInShell: true);
      await Process.run('icacls', [
        path,
        '/inheritance:e',
        '/grant',
        '*S-1-5-11:(M)',
        '*S-1-5-18:(F)',
        '*S-1-5-32-544:(F)',
      ], runInShell: true);
    } catch (_) {}
  }

  static Future<void> prepareSharedConfigDirectory(String path) async {
    if (kIsWeb || !Platform.isWindows || path.trim().isEmpty) return;
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      await Process.run('attrib', [
        '-H',
        '-S',
        '-R',
        dir.path,
      ], runInShell: true);
      await Process.run('icacls', [
        dir.path,
        '/inheritance:e',
        '/grant',
        '*S-1-5-11:(OI)(CI)M',
        '*S-1-5-18:(OI)(CI)F',
        '*S-1-5-32-544:(OI)(CI)F',
      ], runInShell: true);
    } catch (_) {}
  }

  static Future<void> prepareSharedConfigFile(String path) async {
    if (kIsWeb || !Platform.isWindows || path.trim().isEmpty) return;
    try {
      final f = File(path);
      if (!f.existsSync()) return;
      await Process.run('attrib', ['-H', '-S', '-R', path], runInShell: true);
      await Process.run('icacls', [
        path,
        '/inheritance:e',
        '/grant',
        '*S-1-5-11:M',
        '*S-1-5-18:F',
        '*S-1-5-32-544:F',
      ], runInShell: true);
    } catch (_) {}
  }
}

class BlueVpnLocalPaths {
  const BlueVpnLocalPaths._();

  static String sharedStateDirSync() {
    final base = Platform.environment['ProgramData'];
    if (base != null && base.trim().isNotEmpty) {
      return '$base\\BlueVPN\\state';
    }
    return r'C:\ProgramData\BlueVPN\state';
  }

  static Future<String> sharedStateDir() async {
    final dir = Directory(sharedStateDirSync());
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    await WindowsLocalSecurity.prepareSharedStateDirectory(dir.path);
    return dir.path;
  }

  static Future<List<Directory>> legacyStateDirs() async {
    final out = <Directory>[];
    final seen = <String>{};

    void addPath(String? path) {
      if (path == null || path.trim().isEmpty) return;
      final dir = Directory(path);
      final key = dir.path.toLowerCase();
      if (seen.contains(key) || !dir.existsSync()) return;
      seen.add(key);
      out.add(dir);
    }

    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      addPath('$appData\\BlueVPN');
    }

    final usersRoot = Directory(r'C:\Users');
    if (usersRoot.existsSync()) {
      for (final entry in usersRoot.listSync().whereType<Directory>()) {
        addPath('${entry.path}\\AppData\\Roaming\\BlueVPN');
      }
    }

    return out;
  }

  static Future<File?> firstLegacyFile(String fileName) async {
    final dirs = await legacyStateDirs();
    for (final dir in dirs) {
      final f = File('${dir.path}\\$fileName');
      if (f.existsSync()) return f;
    }
    return null;
  }

  static bool isSharedStatePath(String path) {
    final shared = sharedStateDirSync().toLowerCase();
    final candidate = path.toLowerCase();
    return candidate == shared || candidate.startsWith('$shared\\');
  }
}

class SecureLocalFile {
  final String path;
  final bool encrypted;

  const SecureLocalFile(this.path, {this.encrypted = false});

  File get file => File(path);

  Future<String?> readString() async {
    try {
      if (!file.existsSync()) return null;
      final raw = await file.readAsString();
      if (!encrypted) return raw;
      return await WindowsLocalSecurity.unprotectString(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeString(String value) async {
    try {
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      if (BlueVpnLocalPaths.isSharedStatePath(dir.path)) {
        unawaited(WindowsLocalSecurity.prepareSharedStateDirectory(dir.path));
      } else {
        unawaited(WindowsLocalSecurity.hardenPath(dir.path, directory: true));
      }

      if (encrypted && !kIsWeb && Platform.isWindows) {
        final protected = await WindowsLocalSecurity.protectString(value);
        if (protected != null && protected.trim().isNotEmpty) {
          await file.writeAsString(protected);
          if (BlueVpnLocalPaths.isSharedStatePath(file.path)) {
            unawaited(WindowsLocalSecurity.prepareSharedStateFile(file.path));
          } else {
            unawaited(WindowsLocalSecurity.hardenPath(file.path));
          }
          return;
        }
      }

      await file.writeAsString(value);
      if (BlueVpnLocalPaths.isSharedStatePath(file.path)) {
        unawaited(WindowsLocalSecurity.prepareSharedStateFile(file.path));
      } else {
        unawaited(WindowsLocalSecurity.hardenPath(file.path));
      }
    } catch (_) {
      rethrow;
    }
  }

  Future<void> delete() async {
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }
}

class SessionStore {
  Future<String> _appDirPath() async {
    return BlueVpnLocalPaths.sharedStateDir();
  }

  Future<File> _file() async {
    final dir = await _appDirPath();
    return File('$dir\\session.json');
  }

  Future<SecureLocalFile> _secureFile() async {
    final dir = await _appDirPath();
    return SecureLocalFile('$dir\\session.dat', encrypted: true);
  }

  Future<Session?> read() async {
    if (kIsWeb) return null;
    try {
      final secure = await _secureFile();
      var raw = await secure.readString();
      if (raw == null || raw.trim().isEmpty) {
        final f = await _file();
        if (f.existsSync()) {
          raw = await f.readAsString();
        } else {
          final legacySecure = await BlueVpnLocalPaths.firstLegacyFile(
            'session.dat',
          );
          if (legacySecure != null) {
            raw = await SecureLocalFile(
              legacySecure.path,
              encrypted: true,
            ).readString();
          }
          raw ??= await (await BlueVpnLocalPaths.firstLegacyFile(
            'session.json',
          ))?.readAsString();
          if (raw == null || raw.trim().isEmpty) return null;
        }
      }
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
      final s = Session.fromJson(jsonMap);
      if (s.accessToken.isEmpty) return null;
      await write(s);
      final legacy = await _file();
      if (legacy.existsSync()) {
        try {
          await legacy.delete();
        } catch (_) {}
      }
      return s;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Session session) async {
    if (kIsWeb) return;
    final raw = jsonEncode(session.toJson());
    try {
      final f = await _secureFile();
      await f.writeString(raw);
      return;
    } catch (_) {
      final legacy = await _file();
      await legacy.writeAsString(raw);
      unawaited(
        WindowsLocalSecurity.prepareSharedStateDirectory(legacy.parent.path),
      );
      unawaited(WindowsLocalSecurity.prepareSharedStateFile(legacy.path));
    }
  }

  Future<void> clear() async {
    if (kIsWeb) return;
    try {
      final f = await _file();
      if (f.existsSync()) f.deleteSync();
      await (await _secureFile()).delete();
    } catch (_) {}
  }
}

class DeviceIdStore {
  Future<String> _appDirPath() async {
    return BlueVpnLocalPaths.sharedStateDir();
  }

  Future<File> _file() async {
    final dir = await _appDirPath();
    return File('$dir\\device_id.txt');
  }

  String _gen() {
    // Short but unique enough for one local device.
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'dev_$hex';
  }

  Future<String?> read() async {
    if (kIsWeb) return null;
    try {
      final f = await _file();
      String? raw;
      if (f.existsSync()) {
        raw = await f.readAsString();
      } else {
        raw = await (await BlueVpnLocalPaths.firstLegacyFile(
          'device_id.txt',
        ))?.readAsString();
      }
      if (raw == null) return null;
      final s = raw.trim();
      if (s.length < 8) return null;
      return s;
    } on FileSystemException {
      await WindowsLocalSecurity.prepareSharedStateDirectory(
        (await _file()).parent.path,
      );
      try {
        final f = await _file();
        if (!f.existsSync()) return null;
        final s = (await f.readAsString()).trim();
        if (s.length < 8) return null;
        return s;
      } catch (_) {
        return null;
      }
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
    try {
      await f.writeAsString(id);
    } on FileSystemException {
      await WindowsLocalSecurity.prepareSharedStateDirectory(f.parent.path);
      await f.writeAsString(id);
    }
    await WindowsLocalSecurity.prepareSharedStateDirectory(f.parent.path);
    await WindowsLocalSecurity.prepareSharedStateFile(f.path);
    return id;
  }

  Future<String> rotate() async {
    if (kIsWeb) return 'web';
    final id = _gen();
    final f = await _file();
    try {
      await f.writeAsString(id);
    } on FileSystemException {
      await WindowsLocalSecurity.prepareSharedStateDirectory(f.parent.path);
      await f.writeAsString(id);
    }
    await WindowsLocalSecurity.prepareSharedStateDirectory(f.parent.path);
    await WindowsLocalSecurity.prepareSharedStateFile(f.path);
    return id;
  }

  Future<void> clear() async {
    if (kIsWeb) return;
    final f = await _file();
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

class AdminTokenStore {
  Future<String> _appDirPath() async {
    return BlueVpnLocalPaths.sharedStateDir();
  }

  Future<File> _file() async {
    final dir = await _appDirPath();
    return File('$dir\\admin_token.txt');
  }

  Future<SecureLocalFile> _secureFile() async {
    final dir = await _appDirPath();
    return SecureLocalFile('$dir\\admin_token.dat', encrypted: true);
  }

  Future<String?> read() async {
    if (kIsWeb) return null;
    try {
      final secure = await _secureFile();
      var raw = (await secure.readString())?.trim();
      if (raw == null || raw.isEmpty) {
        final f = await _file();
        if (f.existsSync()) {
          raw = (await f.readAsString()).trim();
          if (raw.isNotEmpty) {
            await write(raw);
            try {
              await f.delete();
            } catch (_) {}
          }
        } else {
          final legacySecure = await BlueVpnLocalPaths.firstLegacyFile(
            'admin_token.dat',
          );
          if (legacySecure != null) {
            raw = (await SecureLocalFile(
              legacySecure.path,
              encrypted: true,
            ).readString())?.trim();
          }
          raw ??= (await (await BlueVpnLocalPaths.firstLegacyFile(
            'admin_token.txt',
          ))?.readAsString())?.trim();
        }
      }
      if (raw == null || raw.isEmpty) return null;
      return raw;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String token) async {
    if (kIsWeb) return;
    final raw = token.trim();
    try {
      final f = await _secureFile();
      await f.writeString(raw);
      return;
    } catch (_) {
      final legacy = await _file();
      await legacy.writeAsString(raw);
      unawaited(
        WindowsLocalSecurity.prepareSharedStateDirectory(legacy.parent.path),
      );
      unawaited(WindowsLocalSecurity.prepareSharedStateFile(legacy.path));
    }
  }

  Future<void> clear() async {
    if (kIsWeb) return;
    final f = await _file();
    if (f.existsSync()) {
      await f.delete();
    }
    await (await _secureFile()).delete();
  }
}

class PendingBillingOrderStore {
  Future<File> _file() async {
    final dir = await BlueVpnLocalPaths.sharedStateDir();
    return File('$dir\\pending_billing_order.json');
  }

  Future<Map<String, dynamic>?> read() async {
    if (kIsWeb) return null;
    try {
      final f = await _file();
      if (!f.existsSync()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final orderId = (map['orderId'] ?? '').toString().trim();
      if (orderId.isEmpty) return null;
      return map;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> order) async {
    if (kIsWeb) return;
    final f = await _file();
    await f.writeAsString(jsonEncode(order));
    await WindowsLocalSecurity.prepareSharedStateDirectory(f.parent.path);
    await WindowsLocalSecurity.prepareSharedStateFile(f.path);
  }

  Future<void> clear() async {
    if (kIsWeb) return;
    try {
      final f = await _file();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}

class PendingVpnActionStore {
  Future<String> _sharedDirPath() async {
    return BlueVpnLocalPaths.sharedStateDir();
  }

  Future<String> _legacyAppDirPath() async {
    final base = Platform.environment['APPDATA'];
    final dir = Directory(
      base != null && base.isNotEmpty ? '$base\\BlueVPN' : 'BlueVPN',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<File> _file() async {
    final dir = await _sharedDirPath();
    return File('$dir\\pending_vpn_action.txt');
  }

  Future<File> _legacyFile() async {
    final dir = await _legacyAppDirPath();
    return File('$dir\\pending_vpn_action.txt');
  }

  Future<String?> read() async {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      final f = await _file();
      File? source;
      if (f.existsSync()) {
        source = f;
      } else {
        final legacy = await _legacyFile();
        if (legacy.existsSync()) source = legacy;
      }
      if (source == null) return null;
      final raw = (await source.readAsString()).trim().toLowerCase();
      if (raw != 'connect' && raw != 'disconnect') return null;
      return raw;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String action) async {
    if (kIsWeb || !Platform.isWindows) return;
    final normalized = action.trim().toLowerCase();
    if (normalized != 'connect' && normalized != 'disconnect') return;
    try {
      final f = await _file();
      await f.writeAsString(normalized);
      await WindowsLocalSecurity.prepareSharedStateDirectory(f.parent.path);
      await WindowsLocalSecurity.prepareSharedStateFile(f.path);
      return;
    } on FileSystemException {
      await WindowsLocalSecurity.repairBlueVpnLocalAcls();
      final f = await _file();
      await f.writeAsString(normalized);
      await WindowsLocalSecurity.prepareSharedStateDirectory(f.parent.path);
      await WindowsLocalSecurity.prepareSharedStateFile(f.path);
    }
  }

  Future<void> clear() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final f = await _file();
      if (f.existsSync()) {
        await f.delete();
      }
      final legacy = await _legacyFile();
      if (legacy.existsSync()) {
        await legacy.delete();
      }
    } catch (_) {}
  }
}

Future<void> appendBlueVpnClientLog(String message) async {
  if (kIsWeb || !Platform.isWindows) return;
  try {
    final f = File(r'C:\ProgramData\BlueVPN\auth.log');
    final ts = DateTime.now().toIso8601String();
    await f.writeAsString('[$ts] UI $message\n', mode: FileMode.append);
  } catch (_) {}
}

Future<bool> isWindowsProcessElevated() async {
  if (kIsWeb || !Platform.isWindows) return false;
  try {
    final res = await Process.run('whoami', ['/groups'], runInShell: true);
    final out =
        ((res.stdout ?? '').toString() + '\n' + (res.stderr ?? '').toString());
    return out.contains('S-1-16-12288') || out.contains('S-1-16-16384');
  } catch (_) {
    return false;
  }
}

Future<bool> ensureWindowsStartupReady() async {
  // Native Windows runner now handles startup self-elevation before Flutter
  // initializes. Dart keeps only per-action fallback relaunch logic.
  await applyStartupLocalHardening();
  return true;
}

Future<void> applyStartupLocalHardening() async {
  if (kIsWeb || !Platform.isWindows) return;
  try {
    await WindowsLocalSecurity.repairBlueVpnLocalAcls();
    final sharedStateDir = Directory(BlueVpnLocalPaths.sharedStateDirSync());
    if (!sharedStateDir.existsSync()) {
      sharedStateDir.createSync(recursive: true);
    }
    await WindowsLocalSecurity.prepareSharedStateDirectory(sharedStateDir.path);

    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      final dir = Directory('$appData\\BlueVPN');
      if (dir.existsSync()) {
        await WindowsLocalSecurity.hardenPath(dir.path, directory: true);
        for (final name in const [
          'session.dat',
          'session.json',
          'admin_token.dat',
          'admin_token.txt',
          'device_id.txt',
          'prefs.json',
          'pending_vpn_action.txt',
        ]) {
          final f = File('${dir.path}\\$name');
          if (f.existsSync()) {
            await WindowsLocalSecurity.hardenPath(f.path);
          }
        }
      }
    }

    final programData = Platform.environment['ProgramData'];
    if (programData != null && programData.trim().isNotEmpty) {
      final dir = Directory('$programData\\BlueVPN');
      if (dir.existsSync()) {
        await WindowsLocalSecurity.prepareSharedConfigDirectory(dir.path);
        for (final f in dir.listSync().whereType<File>()) {
          final lower = f.path.toLowerCase();
          if (lower.endsWith('.conf') ||
              lower.endsWith('.bak') ||
              lower.endsWith('.log') ||
              lower.endsWith('.txt')) {
            await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
          }
        }
      }
    }
  } catch (_) {}
}

class WireGuardInstallState {
  final bool installed;
  final bool wingetAvailable;
  final String exePath;

  const WireGuardInstallState({
    required this.installed,
    required this.wingetAvailable,
    required this.exePath,
  });

  String get subtitle {
    if (installed) return 'WireGuard найден: $exePath';
    if (wingetAvailable) {
      return 'WireGuard не установлен. Green VPN может поставить его автоматически.';
    }
    return 'WireGuard не установлен. Понадобится ручная установка.';
  }
}

class WireGuardInstallResult {
  final bool ok;
  final String message;

  const WireGuardInstallResult({required this.ok, required this.message});
}

String resolveWireGuardExePathShared() {
  if (kIsWeb || !Platform.isWindows) return 'wireguard.exe';

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

Future<bool> isWingetAvailable() async {
  if (kIsWeb || !Platform.isWindows) return false;
  try {
    final res = await Process.run('winget', ['--version'], runInShell: true);
    return res.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<WireGuardInstallState> probeWireGuardInstall() async {
  final exePath = resolveWireGuardExePathShared();
  final installed =
      exePath.toLowerCase() != 'wireguard.exe' && File(exePath).existsSync();
  final wingetAvailable = await isWingetAvailable();
  return WireGuardInstallState(
    installed: installed,
    wingetAvailable: wingetAvailable,
    exePath: exePath,
  );
}

Future<void> openWireGuardInstallPage() async {
  if (kIsWeb || !Platform.isWindows) return;
  try {
    await Process.start('cmd', [
      '/c',
      'start',
      '',
      'https://www.wireguard.com/install/',
    ], runInShell: true);
  } catch (_) {}
}

Future<void> openExternalUrl(String url) async {
  if (kIsWeb || !Platform.isWindows) return;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return;
  try {
    await Process.start('cmd', ['/c', 'start', '', trimmed], runInShell: true);
  } catch (_) {}
}

Future<WireGuardInstallResult> installWireGuardForWindows() async {
  if (kIsWeb || !Platform.isWindows) {
    return const WireGuardInstallResult(
      ok: false,
      message: 'Автоустановка доступна только на Windows.',
    );
  }

  final wingetAvailable = await isWingetAvailable();
  if (!wingetAvailable) {
    await openWireGuardInstallPage();
    return const WireGuardInstallResult(
      ok: false,
      message:
          'winget не найден. Открыл страницу установки WireGuard в браузере.',
    );
  }

  final script =
      r'''Start-Process -FilePath "winget" -Verb RunAs -Wait -ArgumentList @(
  "install",
  "--id", "WireGuard.WireGuard",
  "-e",
  "--accept-source-agreements",
  "--accept-package-agreements"
)''';

  try {
    final res = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ], runInShell: true);

    final check = await probeWireGuardInstall();
    if (check.installed) {
      return WireGuardInstallResult(
        ok: true,
        message: 'WireGuard установлен: ${check.exePath}',
      );
    }

    final stderr = (res.stderr ?? '').toString().trim();
    return WireGuardInstallResult(
      ok: false,
      message: stderr.isNotEmpty
          ? 'Установка не завершилась: $stderr'
          : 'WireGuard пока не найден после установки. Нажми "Проверить снова".',
    );
  } catch (e) {
    return WireGuardInstallResult(
      ok: false,
      message: 'Не удалось запустить установку WireGuard: $e',
    );
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
  final bool optAutoRenew;

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
    required this.optAutoRenew,
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
    optAutoRenew: true,
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
    bool? optAutoRenew,
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
      optAutoRenew: optAutoRenew ?? this.optAutoRenew,
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
    'optAutoRenew': optAutoRenew,
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
      optAutoRenew: _b('optAutoRenew', d.optAutoRenew),
    );
  }
}

class PrefsStore {
  Future<String> _appDirPath() async {
    return BlueVpnLocalPaths.sharedStateDir();
  }

  Future<File> _file() async {
    final dir = await _appDirPath();
    return File('$dir\\prefs.json');
  }

  Future<Map<String, dynamic>> _readMap() async {
    if (kIsWeb) return <String, dynamic>{};
    try {
      final f = await _file();
      String? raw;
      if (f.existsSync()) {
        raw = await f.readAsString();
      } else {
        raw = await (await BlueVpnLocalPaths.firstLegacyFile(
          'prefs.json',
        ))?.readAsString();
      }
      if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
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
    await WindowsLocalSecurity.prepareSharedStateDirectory(f.parent.path);
    await WindowsLocalSecurity.prepareSharedStateFile(f.path);
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

class GreenVpnUpdateManifest {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String sha256;
  final bool required;
  final bool updateAvailable;
  final bool baseUpdateAvailable;
  final bool rolloutEligible;
  final int rolloutPercent;
  final String rolloutReason;
  final List<String> changelog;
  final String releasedAt;

  const GreenVpnUpdateManifest({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.sha256,
    required this.required,
    required this.updateAvailable,
    required this.baseUpdateAvailable,
    required this.rolloutEligible,
    required this.rolloutPercent,
    required this.rolloutReason,
    required this.changelog,
    required this.releasedAt,
  });

  bool get serverHasNewerVersion =>
      latestVersion.trim().isNotEmpty && latestVersion.trim() != currentVersion;

  bool get hasUpdate => updateAvailable && serverHasNewerVersion;

  bool get heldByRollout => serverHasNewerVersion && !updateAvailable;

  bool get canDownload => downloadUrl.trim().isNotEmpty;

  static GreenVpnUpdateManifest fromJson(Map<String, dynamic> json) {
    bool asBool(dynamic value) {
      if (value == true) return true;
      final lower = value?.toString().toLowerCase().trim();
      return lower == 'true' || lower == '1' || lower == 'yes';
    }

    int asPercent(dynamic value, {int fallback = 100}) {
      final parsed = int.tryParse((value ?? '').toString());
      if (parsed == null) return fallback;
      if (parsed < 0) return 0;
      if (parsed > 100) return 100;
      return parsed;
    }

    final rawChangelog = json['changelog'];
    final changelog = rawChangelog is List
        ? rawChangelog
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    final current = (json['currentVersion'] ?? kAppVersion).toString();
    final latest = (json['latestVersion'] ?? '').toString();
    final fallbackUpdateAvailable =
        latest.trim().isNotEmpty && latest.trim() != current;
    final hasExplicitUpdateFlag = json.containsKey('updateAvailable');
    final updateAvailable = hasExplicitUpdateFlag
        ? asBool(json['updateAvailable'])
        : fallbackUpdateAvailable;
    return GreenVpnUpdateManifest(
      currentVersion: current,
      latestVersion: latest,
      downloadUrl: (json['downloadUrl'] ?? '').toString(),
      sha256: (json['sha256'] ?? '').toString(),
      required: asBool(json['required']),
      updateAvailable: updateAvailable,
      baseUpdateAvailable: json.containsKey('baseUpdateAvailable')
          ? asBool(json['baseUpdateAvailable'])
          : fallbackUpdateAvailable,
      rolloutEligible: json.containsKey('rolloutEligible')
          ? asBool(json['rolloutEligible'])
          : updateAvailable,
      rolloutPercent: asPercent(json['rolloutPercent']),
      rolloutReason: (json['rolloutReason'] ?? '').toString(),
      changelog: changelog,
      releasedAt: (json['releasedAt'] ?? '').toString(),
    );
  }
}

String authUserMessage(Object error, {String fallback = 'Не удалось войти.'}) {
  final raw = error.toString().trim();
  if (raw.isEmpty) return fallback;

  var text = raw
      .replaceFirst(RegExp(r'^HttpException:\s*'), '')
      .replaceFirst(RegExp(r'^SocketException:\s*'), '')
      .replaceFirst(RegExp(r'^HandshakeException:\s*'), '')
      .replaceFirst(RegExp(r'^FormatException:\s*'), '')
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .trim();

  text = text.replaceFirst(RegExp(r', uri = .+$'), '').trim();
  final lower = text.toLowerCase();

  if (lower.contains('user already exists') ||
      lower.contains('already registered') ||
      lower.contains('уже зарегистр')) {
    return 'Пользователь с таким email уже зарегистрирован. Войди по паролю или используй код.';
  }
  if (lower.contains('invalid credentials') ||
      lower.contains('unauthorized') ||
      lower.contains('401')) {
    return 'Неверный email или пароль. Проверь данные и попробуй снова.';
  }
  if (lower.contains('invalid email')) {
    return 'Этот email выглядит некорректно. Проверь адрес и попробуй снова.';
  }
  if (lower.contains('password too short')) {
    return 'Пароль слишком короткий. Нужны минимум 6 символов.';
  }
  if (lower.contains('invalid_code') ||
      lower.contains('invalid code') ||
      lower.contains('expired')) {
    return 'Код не подошёл или уже истёк. Запроси новый код и попробуй снова.';
  }
  if (lower.contains('connection refused') ||
      lower.contains('failed host lookup') ||
      lower.contains('timed out') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection reset')) {
    return 'Не получается связаться с сервером Green VPN. Проверь интернет и попробуй ещё раз.';
  }
  if (lower.contains('access denied')) {
    return 'Windows не дала Green VPN доступ к локальным файлам. Переустанови приложение последним установщиком.';
  }

  if (text.startsWith('Ошибка сети:')) {
    text = text.replaceFirst('Ошибка сети:', '').trim();
  }
  if (text.startsWith('Ошибка входа:')) {
    text = text.replaceFirst('Ошибка входа:', '').trim();
  }

  return text.isEmpty ? fallback : text;
}

String normalizeProvisionedEndpoint(String rawConfig) {
  return rawConfig.replaceAllMapped(
    RegExp(
      r'(^\s*Endpoint\s*=\s*)(37\.202\.85\.211|37\.220\.85\.21)(:\d+\s*$)',
      multiLine: true,
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}$kIntelligentSmewHost${match.group(3)}',
  );
}

String replaceAllowedIpsInConfig(String configText, List<String> allowedIps) {
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

class ProvisioningWarmupResult {
  final bool ok;
  final String? planName;
  final String? message;

  const ProvisioningWarmupResult({
    required this.ok,
    this.planName,
    this.message,
  });
}

class AuthProvisioningService {
  final BlueVpnApi api;
  final ConfigStore cfg;
  final DeviceIdStore deviceStore;

  const AuthProvisioningService({
    required this.api,
    required this.cfg,
    required this.deviceStore,
  });

  bool _isDeviceAttachedConflict(String? message) {
    final raw = (message ?? '').toLowerCase();
    return raw.contains('409') &&
        raw.contains('device') &&
        raw.contains('attached') &&
        raw.contains('another user');
  }

  String _buildManagedConfig(String baseConfig) {
    return replaceAllowedIpsInConfig(baseConfig, const ['0.0.0.0/0', '::/0']);
  }

  Future<void> _writeProvisionedConfig(String rawConfig) async {
    await cfg.writeManagedConfig(_buildManagedConfig(rawConfig));
    try {
      await cfg.writeBaseConfig(rawConfig);
    } catch (e) {
      await appendBlueVpnClientLog(
        'config write skipped path=${cfg.baseConfigPath} kind=base-auth error=$e',
      );
    }
  }

  Future<bool> _reuseLocalConfigIfPresent(String reason) async {
    try {
      await cfg.ensureBaseSeededFromManagedIfMissing();
      final base = await cfg.readBaseConfig();
      if (base == null || base.trim().isEmpty) return false;
      await cfg.writeManagedConfig(_buildManagedConfig(base));
      await appendBlueVpnClientLog(
        'auth config fetch failed; using existing local config: $reason',
      );
      return true;
    } catch (e) {
      await appendBlueVpnClientLog('auth local config fallback failed: $e');
      return false;
    }
  }

  Future<ProvisioningWarmupResult> warmup(Session session) async {
    if (kIsWeb || !Platform.isWindows) {
      return const ProvisioningWarmupResult(ok: true);
    }
    if (session.accessToken == 'dev-token') {
      return const ProvisioningWarmupResult(ok: true);
    }

    var deviceId = await deviceStore.getOrCreate();
    var boot = await api.bootstrapClient(
      accessToken: session.accessToken,
      deviceId: deviceId,
      deviceName: Platform.localHostname,
      platform: 'windows',
      appVersion: kAppVersion,
    );

    if (_isDeviceAttachedConflict(boot.message)) {
      deviceId = await deviceStore.rotate();
      boot = await api.bootstrapClient(
        accessToken: session.accessToken,
        deviceId: deviceId,
        deviceName: Platform.localHostname,
        platform: 'windows',
        appVersion: kAppVersion,
      );
    }

    if (!boot.ok || boot.data == null) {
      return ProvisioningWarmupResult(
        ok: false,
        message: boot.message ?? 'Не удалось пройти bootstrap.',
      );
    }

    final bootMap = boot.data!;

    final planMap = bootMap['subscription'];
    final planName = planMap is Map
        ? (planMap['planName'] ?? planMap['planCode'] ?? '').toString().trim()
        : null;

    final cfgRes = await api.fetchWireGuardConfig(
      accessToken: session.accessToken,
      deviceId: deviceId,
    );

    if (!cfgRes.ok || cfgRes.data == null || cfgRes.data!.trim().isEmpty) {
      final reused = await _reuseLocalConfigIfPresent(cfgRes.message ?? '');
      if (reused) {
        return ProvisioningWarmupResult(ok: true, planName: planName);
      }
      return ProvisioningWarmupResult(
        ok: false,
        message: cfgRes.message ?? 'Не удалось получить WireGuard-конфиг.',
      );
    }

    await _writeProvisionedConfig(normalizeProvisionedEndpoint(cfgRes.data!));
    return ProvisioningWarmupResult(ok: true, planName: planName);
  }
}

class BlueVpnApi {
  final String baseUrl;
  const BlueVpnApi({required this.baseUrl});

  static const int _wslRelayPort = 18000;
  static Uri? _cachedWslRelayUri;
  static Future<Uri?>? _wslRelayStartFuture;
  static Process? _wslRelayProcess;

  Uri _u(String path) => Uri.parse('$baseUrl$path');
  Uri _uFor(String resolvedBaseUrl, String path) =>
      Uri.parse('$resolvedBaseUrl$path');

  HttpClient _client({bool direct = true}) {
    final client = HttpClient();
    if (direct) {
      client.findProxy = (_) => 'DIRECT';
    }
    client.connectionTimeout = const Duration(seconds: 12);
    return client;
  }

  bool _isRetriableNetworkError(Object error) {
    return error is SocketException || error is HttpException;
  }

  bool _isWindowsDevBackend() {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final uri = Uri.parse(baseUrl);
      return uri.host == kIntelligentSmewHost;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _canReachLocalRelay(int port) async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(seconds: 2),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _canReachPrimaryTcp({
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    try {
      final uri = Uri.parse(baseUrl);
      if (uri.host.isEmpty) return false;
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final socket = await Socket.connect(uri.host, port, timeout: timeout);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  String _wslRelayPythonScript() {
    return '''
import socket
import sys
import threading

REMOTE_HOST = sys.argv[1]
REMOTE_PORT = int(sys.argv[2])
LISTEN_PORT = int(sys.argv[3])

def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except Exception:
            pass
        try:
            dst.close()
        except Exception:
            pass

def handle(client):
    upstream = None
    try:
        upstream = socket.create_connection((REMOTE_HOST, REMOTE_PORT), timeout=10)
        threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
        pipe(upstream, client)
    except Exception:
        try:
            client.close()
        except Exception:
            pass
        if upstream is not None:
            try:
                upstream.close()
            except Exception:
                pass

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("0.0.0.0", LISTEN_PORT))
server.listen(128)

while True:
    client, _ = server.accept()
    threading.Thread(target=handle, args=(client,), daemon=True).start()
''';
  }

  Future<Uri?> _ensureWslRelayUri() async {
    if (kIsWeb || !Platform.isWindows) return null;

    if (_cachedWslRelayUri != null &&
        await _canReachLocalRelay(_cachedWslRelayUri!.port)) {
      return _cachedWslRelayUri;
    }

    final primaryUri = Uri.parse(baseUrl);
    if (primaryUri.scheme != 'http' || primaryUri.host.isEmpty) return null;

    final relayUri = Uri.parse('http://127.0.0.1:$_wslRelayPort');
    if (await _canReachLocalRelay(_wslRelayPort)) {
      _cachedWslRelayUri = relayUri;
      return relayUri;
    }

    final existingStart = _wslRelayStartFuture;
    if (existingStart != null) return existingStart;

    final startFuture = _startWslRelay(primaryUri, relayUri);
    _wslRelayStartFuture = startFuture;
    try {
      return await startFuture;
    } finally {
      _wslRelayStartFuture = null;
    }
  }

  Future<Uri?> _startWslRelay(Uri primaryUri, Uri relayUri) async {
    try {
      final relayScript = File(
        '${Directory.systemTemp.path}\\bluevpn_wsl_backend_relay.py',
      );
      await relayScript.parent.create(recursive: true);
      await relayScript.writeAsString(_wslRelayPythonScript());

      final remotePort = primaryUri.hasPort
          ? primaryUri.port
          : (primaryUri.scheme == 'https' ? 443 : 80);
      final wslScriptPath = relayScript.path.replaceAll(r'\', '/');
      final wslCommand =
          'exec python3 "${wslScriptPath.replaceFirst('C:/', '/mnt/c/')}" '
          '${primaryUri.host} $remotePort $_wslRelayPort';

      final process = await Process.start('wsl.exe', [
        'bash',
        '-lc',
        wslCommand,
      ], mode: ProcessStartMode.normal);
      _wslRelayProcess = process;
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      unawaited(
        process.exitCode.then((code) async {
          if (identical(_wslRelayProcess, process)) {
            _wslRelayProcess = null;
          }
          await _authLog('WSL relay exited code=$code');
        }),
      );
      await _authLog('WSL relay spawned pid=${process.pid}');

      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (await _canReachLocalRelay(_wslRelayPort)) {
        _cachedWslRelayUri = relayUri;
        return relayUri;
      }
    } catch (e) {
      await _authLog('WSL relay spawn error=$e');
    }

    return null;
  }

  Future<Uri?> _preferredRelayUriIfNeeded() async {
    if (!_isWindowsDevBackend()) return null;
    if (await _canReachPrimaryTcp()) return null;
    return _ensureWslRelayUri();
  }

  Future<T> _withHttpRetry<T>(
    Future<T> Function(HttpClient client, bool direct, String resolvedBaseUrl)
    action,
  ) async {
    Object? lastError;

    final preferredRelay = await _preferredRelayUriIfNeeded();
    if (preferredRelay != null) {
      final client = _client(direct: false);
      try {
        await _authLog('HTTP preferred WSL relay base=$preferredRelay');
        return await action(client, false, preferredRelay.toString());
      } catch (e) {
        lastError = e;
      } finally {
        client.close(force: true);
      }
    }

    for (final direct in const [true, false]) {
      final client = _client(direct: direct);
      try {
        return await action(client, direct, baseUrl);
      } catch (e) {
        lastError = e;
        if (!_isRetriableNetworkError(e) || !direct) {
          break;
        }
      } finally {
        client.close(force: true);
      }
    }

    if (lastError != null && _isRetriableNetworkError(lastError)) {
      final relayUri = await _ensureWslRelayUri();
      if (relayUri != null) {
        final client = _client(direct: false);
        try {
          await _authLog('HTTP retry via WSL relay base=$relayUri');
          return await action(client, false, relayUri.toString());
        } finally {
          client.close(force: true);
        }
      }
    }

    throw lastError ?? Exception('Unknown HTTP retry failure');
  }

  File? _authLogFile() {
    if (kIsWeb || !Platform.isWindows) return null;
    return File(r'C:\ProgramData\BlueVPN\auth.log');
  }

  Future<void> _authLog(String s) async {
    try {
      final f = _authLogFile();
      if (f == null) return;
      final ts = DateTime.now().toIso8601String();
      await f.writeAsString('[' + ts + '] ' + s + '\n', mode: FileMode.append);
    } catch (_) {}
  }

  Future<String> _tcpPreflight(String path) async {
    final uri = _u(path);
    try {
      final socket = await Socket.connect(
        uri.host,
        uri.port,
        timeout: const Duration(seconds: 5),
      );
      final remote =
          socket.remoteAddress.address + ':' + socket.remotePort.toString();
      await socket.close();
      return 'tcp=ok remote=' + remote;
    } catch (e) {
      return 'tcp=fail error=' + e.toString();
    }
  }

  Future<ApiResult<Session>> register({
    required String email,
    required String password,
  }) async {
    return _postSession('/api/v1/auth/register', {
      'email': email,
      'password': password,
    });
  }

  Future<ApiResult<Session>> login({
    required String email,
    required String password,
  }) async {
    return _postSession('/api/v1/auth/login', {
      'email': email,
      'password': password,
    });
  }

  Future<ApiResult<Map<String, dynamic>>> startEmailCodeAuth({
    required String email,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/auth/email/code/start',
      payload: {'email': email},
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ auth/email/code/start.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Session>> verifyEmailCodeAuth({
    required String email,
    required String code,
    String? deviceUid,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    return _postSession('/api/v1/auth/email/code/verify', {
      'email': email,
      'code': code,
      if (deviceUid != null) 'deviceUid': deviceUid,
      if (deviceName != null) 'deviceName': deviceName,
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
    });
  }

  Future<ApiResult<Map<String, dynamic>>> startPhoneCodeAuth({
    required String phone,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/auth/phone/login/start',
      payload: {'phone': phone},
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ auth/phone/login/start.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Session>> verifyPhoneCodeAuth({
    required String phone,
    required String code,
    String? deviceUid,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    return _postSession('/api/v1/auth/phone/login/verify', {
      'phone': phone,
      'code': code,
      if (deviceUid != null) 'deviceUid': deviceUid,
      if (deviceName != null) 'deviceName': deviceName,
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
    });
  }

  Future<ApiResult<Map<String, dynamic>>> startAuthChallenge({
    required String method,
    String? phone,
    String? email,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/auth/challenge/start',
      payload: {
        'method': method,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
      },
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ auth/challenge/start.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Session>> verifyAuthChallenge({
    required String method,
    required String code,
    String? phone,
    String? email,
    String? deviceUid,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    return _postSession('/api/v1/auth/challenge/verify', {
      'method': method,
      'code': code,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (deviceUid != null) 'deviceUid': deviceUid,
      if (deviceName != null) 'deviceName': deviceName,
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
    });
  }

  Future<ApiResult<Map<String, dynamic>>> fetchWindowsBootstrap() async {
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/bootstrap/windows?currentVersion=$kAppVersion',
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ bootstrap/windows.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<String>> fetchPlanName({
    required String accessToken,
    String? deviceId,
  }) async {
    try {
      final body = await _withHttpRetry<String>((
        client,
        _,
        resolvedBaseUrl,
      ) async {
        final uri = _uFor(resolvedBaseUrl, '/api/v1/subscription/me');
        final req = await client.getUrl(uri);
        req.headers.set('Authorization', 'Bearer $accessToken');
        final res = await req.close();
        final body = await utf8.decodeStream(res);

        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException(
            'Ошибка сервера (${res.statusCode}): $body',
            uri: uri,
          );
        }
        return body;
      });

      {
        final jsonMap = Map<String, dynamic>.from(jsonDecode(body) as Map);
        final p = (jsonMap['planName'] ?? jsonMap['planCode'] ?? 'Base')
            .toString();
        return ApiResult.ok(p.isEmpty ? 'Base' : p);
      }
    } catch (e) {
      return ApiResult.err('Ошибка сети: $e');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> fetchSubscriptionProfile({
    required String accessToken,
  }) async {
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/subscription/me',
      bearerToken: accessToken,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ subscription/me.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> fetchEmailStatus({
    required String accessToken,
  }) async {
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/auth/email/status',
      bearerToken: accessToken,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ auth/email/status.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> resendEmailConfirmation({
    required String accessToken,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/auth/email/resend',
      bearerToken: accessToken,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ auth/email/resend.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> fetchPhoneStatus({
    required String accessToken,
  }) async {
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/auth/phone/status',
      bearerToken: accessToken,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ auth/phone/status.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> startPhoneConfirmation({
    required String accessToken,
    required String phone,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/auth/phone/start',
      bearerToken: accessToken,
      payload: {'phone': phone},
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ auth/phone/start.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> verifyPhoneConfirmation({
    required String accessToken,
    required String phone,
    required String code,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/auth/phone/verify',
      bearerToken: accessToken,
      payload: {'phone': phone, 'code': code},
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ auth/phone/verify.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> sendSupportReport({
    required String accessToken,
    required String report,
    required String summary,
    String? appVersion,
    String? deviceUid,
  }) async {
    final payload = <String, dynamic>{
      'report': report,
      'summary': summary,
      'appVersion': appVersion ?? kAppVersion,
    };
    final cleanDeviceUid = deviceUid?.trim();
    if (cleanDeviceUid != null && cleanDeviceUid.isNotEmpty) {
      payload['deviceUid'] = cleanDeviceUid;
    }

    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/support/reports',
      bearerToken: accessToken,
      payload: payload,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ support/reports.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> fetchTariffCatalog() async {
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/catalog/tariffs',
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ catalog/tariffs.');
    }
    final map = Map<String, dynamic>.from(res.data as Map);
    final catalog = map['catalog'];
    if (catalog is! Map) {
      return const ApiResult.err('Сервер не вернул каталог тарифов.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(catalog));
  }

  Future<ApiResult<Map<String, dynamic>>> fetchServerCatalog() async {
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/catalog/servers',
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ catalog/servers.');
    }
    final map = Map<String, dynamic>.from(res.data as Map);
    final catalog = map['catalog'];
    if (catalog is! Map) {
      return const ApiResult.err('Сервер не вернул каталог серверов.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(catalog));
  }

  Future<ApiResult<Map<String, dynamic>>> fetchMonitoringStatus() async {
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/monitoring/status',
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ monitoring/status.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<GreenVpnUpdateManifest>> fetchWindowsUpdateManifest({
    required String currentVersion,
    String? clientId,
  }) async {
    final query = <String, String>{
      'currentVersion': currentVersion,
      if ((clientId ?? '').trim().isNotEmpty) 'clientId': clientId!.trim(),
    };
    final path = Uri(
      path: '/api/v1/updates/windows',
      queryParameters: query,
    ).toString();
    final res = await _jsonRequest(method: 'GET', path: path);
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ updates/windows.');
    }
    final map = Map<String, dynamic>.from(res.data as Map);
    final rawManifest = map['manifest'];
    final manifest = rawManifest is Map
        ? Map<String, dynamic>.from(rawManifest)
        : map;
    return ApiResult.ok(GreenVpnUpdateManifest.fromJson(manifest));
  }

  Future<ApiResult<Map<String, dynamic>>> quoteTariff({
    required String trafficPack,
    required int trafficGb,
    required List<String> unlimitedApps,
    required int devices,
    required bool dedicatedIp,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/subscription/quote',
      payload: {
        'trafficPack': trafficPack,
        'trafficGb': trafficGb,
        'unlimitedApps': unlimitedApps,
        'devices': devices,
        'dedicatedIp': dedicatedIp,
      },
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ subscription/quote.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> createBillingOrder({
    required String accessToken,
    required String trafficPack,
    required int trafficGb,
    required List<String> unlimitedApps,
    required int devices,
    required bool dedicatedIp,
    required bool autoRenew,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/billing/orders',
      bearerToken: accessToken,
      payload: {
        'trafficPack': trafficPack,
        'trafficGb': trafficGb,
        'unlimitedApps': unlimitedApps,
        'devices': devices,
        'dedicatedIp': dedicatedIp,
        'autoRenew': autoRenew,
      },
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ billing/orders.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> fetchBillingOrder({
    required String accessToken,
    required String orderId,
  }) async {
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/billing/orders/${Uri.encodeComponent(orderId)}',
      bearerToken: accessToken,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ billing order.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> cancelAutoRenew({
    required String accessToken,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/subscription/auto-renew/cancel',
      bearerToken: accessToken,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ auto-renew/cancel.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> bootstrapClient({
    required String accessToken,
    required String deviceId,
    required String deviceName,
    String platform = 'windows',
    String appVersion = '0.1.0',
  }) async {
    try {
      final body = await _withHttpRetry<String>((
        client,
        _,
        resolvedBaseUrl,
      ) async {
        final uri = _uFor(resolvedBaseUrl, '/api/v1/client/bootstrap');
        final req = await client.postUrl(uri);
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer $accessToken');
        req.write(
          jsonEncode({
            'deviceUid': deviceId,
            'deviceName': deviceName,
            'platform': platform,
            'appVersion': appVersion,
          }),
        );

        final res = await req.close();
        final body = await utf8.decodeStream(res);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException(
            'Ошибка bootstrap (${res.statusCode}): $body',
            uri: uri,
          );
        }
        return body;
      });

      {
        final jsonMap = Map<String, dynamic>.from(jsonDecode(body) as Map);
        return ApiResult.ok(jsonMap);
      }
    } catch (e) {
      return ApiResult.err('Ошибка bootstrap: $e');
    }
  }

  Future<ApiResult<String>> fetchWireGuardConfig({
    required String accessToken,
    String? deviceId,
    String? serverId,
  }) async {
    try {
      if (deviceId == null || deviceId.trim().isEmpty) {
        return const ApiResult.err('Отсутствует device id.');
      }

      final body = await _withHttpRetry<String>((
        client,
        _,
        resolvedBaseUrl,
      ) async {
        final uri = _uFor(resolvedBaseUrl, '/api/v1/client/config');
        final req = await client.postUrl(uri);
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer $accessToken');
        final payload = <String, dynamic>{
          'deviceUid': deviceId,
          'mode': 'full',
        };
        if (serverId != null && serverId.trim().isNotEmpty) {
          payload['serverId'] = serverId.trim();
        }
        req.write(jsonEncode(payload));

        final res = await req.close();
        final body = await utf8.decodeStream(res);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException(
            'Ошибка сервера (${res.statusCode}): $body',
            uri: uri,
          );
        }
        return body;
      });

      {
        final trimmed = body.trim();
        if (trimmed.isEmpty) {
          return const ApiResult.err('Сервер вернул пустой конфиг.');
        }

        final jsonMap = Map<String, dynamic>.from(jsonDecode(trimmed) as Map);
        final cfg = (jsonMap['configText'] ?? jsonMap['config'] ?? '')
            .toString();
        if (cfg.trim().isEmpty) {
          return const ApiResult.err('Сервер вернул пустой configText.');
        }
        return ApiResult.ok(cfg);
      }
    } catch (e) {
      return ApiResult.err('Не удалось получить конфиг: $e');
    }
  }

  Future<ApiResult<Session>> _postSession(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _authLog(
        'POST ' + path + ' email=' + ((payload['email'] ?? '').toString()),
      );
      await _authLog(await _tcpPreflight(path));
      final body = await _withHttpRetry<String>((
        client,
        direct,
        resolvedBaseUrl,
      ) async {
        final uri = _uFor(resolvedBaseUrl, path);
        final req = await client.postUrl(uri);
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(payload));

        final res = await req.close();
        final body = await utf8.decodeStream(res);
        await _authLog(
          'HTTP ' +
              path +
              ' status=' +
              res.statusCode.toString() +
              ' route=' +
              (direct ? 'direct' : 'system') +
              ' base=' +
              resolvedBaseUrl,
        );
        if (res.statusCode < 200 || res.statusCode >= 300) {
          final friendly = _friendlyAuthError(
            path: path,
            statusCode: res.statusCode,
            body: body,
          );
          throw HttpException(
            friendly ?? 'Ошибка сервера (${res.statusCode}): $body',
            uri: uri,
          );
        }
        return body;
      });

      {
        final jsonMap = jsonDecode(body) as Map<String, dynamic>;
        final token = (jsonMap['accessToken'] ?? '').toString();
        final email = (jsonMap['email'] ?? payload['email'] ?? '').toString();

        if (token.isEmpty)
          return const ApiResult.err('Сервер не вернул accessToken.');
        return ApiResult.ok(Session(accessToken: token, email: email));
      }
    } catch (e) {
      await _authLog('HTTP ' + path + ' exception=' + e.toString());
      return ApiResult.err(authUserMessage(e, fallback: 'Ошибка авторизации.'));
    }
  }

  String? _friendlyAuthError({
    required String path,
    required int statusCode,
    required String body,
  }) {
    String detail = body.trim();
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] != null) {
        detail = decoded['detail'].toString().trim();
      }
    } catch (_) {}

    final lower = detail.toLowerCase();

    if (path.endsWith('/auth/register')) {
      if (statusCode == 409 ||
          lower.contains('user already exists') ||
          lower.contains('already exists')) {
        return 'Пользователь с таким email уже зарегистрирован. Просто войди в аккаунт.';
      }
      if (statusCode == 400 && lower.contains('invalid email')) {
        return 'Этот email выглядит некорректно. Проверь адрес и попробуй снова.';
      }
      if (statusCode == 400 && lower.contains('password too short')) {
        return 'Пароль слишком короткий. Нужны минимум 6 символов.';
      }
    }

    if (path.endsWith('/auth/login')) {
      if (statusCode == 401 ||
          lower.contains('invalid credentials') ||
          lower.contains('unauthorized')) {
        return 'Неверный email или пароль. Проверь данные и попробуй снова.';
      }
    }

    if (path.endsWith('/auth/challenge/verify') ||
        path.endsWith('/auth/email/code/verify') ||
        path.endsWith('/auth/phone/login/verify')) {
      if (statusCode == 401 ||
          lower.contains('invalid_code') ||
          lower.contains('invalid code') ||
          lower.contains('expired')) {
        return 'Код не подошёл или уже истёк. Запроси новый код и попробуй снова.';
      }
    }

    return null;
  }

  Future<ApiResult<dynamic>> _jsonRequest({
    required String method,
    required String path,
    String? bearerToken,
    String? adminToken,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _authLog('API $method $path start');
      final body = await _withHttpRetry<String>((
        client,
        direct,
        resolvedBaseUrl,
      ) async {
        final uri = _uFor(resolvedBaseUrl, path);
        final req = method == 'GET'
            ? await client.getUrl(uri)
            : await client.postUrl(uri);

        if (payload != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(payload));
        }
        if (bearerToken != null && bearerToken.trim().isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $bearerToken');
        }
        if (adminToken != null && adminToken.trim().isNotEmpty) {
          req.headers.set('X-Admin-Token', adminToken.trim());
        }

        final res = await req.close();
        final body = await utf8.decodeStream(res);
        await _authLog(
          'API $method $path status=${res.statusCode} route=${direct ? 'direct' : 'system'} base=$resolvedBaseUrl',
        );
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException(
            'Ошибка сервера (${res.statusCode}): $body',
            uri: uri,
          );
        }
        return body;
      });

      if (body.trim().isEmpty) {
        return const ApiResult.ok(<String, dynamic>{});
      }

      return ApiResult.ok(jsonDecode(body));
    } catch (e) {
      await _authLog('API $method $path exception=$e');
      return ApiResult.err('Ошибка сети: $e');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> adminOverview({
    required String adminToken,
  }) async {
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/admin/overview',
      adminToken: adminToken,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ admin overview.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<List<Map<String, dynamic>>>> adminUsers({
    required String adminToken,
  }) async {
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/admin/users',
      adminToken: adminToken,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ admin users.');
    }
    final map = Map<String, dynamic>.from(res.data as Map);
    final raw = map['users'];
    if (raw is! List) return const ApiResult.ok(<Map<String, dynamic>>[]);
    final out = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return ApiResult.ok(out);
  }

  Future<ApiResult<List<Map<String, dynamic>>>> adminBillingOrders({
    required String adminToken,
    String status = 'pending',
  }) async {
    final suffix = status.trim().isEmpty
        ? ''
        : '?status=${Uri.encodeQueryComponent(status.trim())}';
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/admin/billing/orders$suffix',
      adminToken: adminToken,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ admin billing orders.');
    }
    final map = Map<String, dynamic>.from(res.data as Map);
    final raw = map['orders'];
    if (raw is! List) return const ApiResult.ok(<Map<String, dynamic>>[]);
    final out = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return ApiResult.ok(out);
  }

  Future<ApiResult<Map<String, dynamic>>> adminMarkBillingOrderPaid({
    required String adminToken,
    required String orderId,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path:
          '/api/v1/admin/billing/orders/${Uri.encodeComponent(orderId)}/mark-paid',
      adminToken: adminToken,
      payload: const <String, dynamic>{},
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ mark billing order paid.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<List<Map<String, dynamic>>>> adminUserDevices({
    required String adminToken,
    required int userId,
  }) async {
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/admin/users/$userId/devices',
      adminToken: adminToken,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ admin user devices.');
    }
    final map = Map<String, dynamic>.from(res.data as Map);
    final raw = map['devices'];
    if (raw is! List) return const ApiResult.ok(<Map<String, dynamic>>[]);
    final out = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return ApiResult.ok(out);
  }

  Future<ApiResult<Map<String, dynamic>>> adminDisableDevice({
    required String adminToken,
    required String deviceUid,
    String reason = 'disabled_by_admin',
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/admin/devices/$deviceUid/disable',
      adminToken: adminToken,
      payload: {'reason': reason},
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ disable device.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> adminEnableDevice({
    required String adminToken,
    required String deviceUid,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/admin/devices/$deviceUid/enable',
      adminToken: adminToken,
      payload: const <String, dynamic>{},
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ enable device.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> adminSetSubscription({
    required String adminToken,
    required int userId,
    required String planCode,
    required String planName,
    required int maxDevices,
    required bool isActive,
    String? expiresAt,
  }) async {
    final payload = <String, dynamic>{
      'planCode': planCode,
      'planName': planName,
      'maxDevices': maxDevices,
      'isActive': isActive,
    };
    if (expiresAt != null && expiresAt.trim().isNotEmpty) {
      payload['expiresAt'] = expiresAt.trim();
    }

    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/admin/users/$userId/subscription',
      adminToken: adminToken,
      payload: payload,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ set subscription.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> adminApplyTariff({
    required String adminToken,
    required int userId,
    required String trafficPack,
    required int trafficGb,
    required List<String> unlimitedApps,
    required int devices,
    required bool dedicatedIp,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/admin/users/$userId/tariff/apply',
      adminToken: adminToken,
      payload: {
        'trafficPack': trafficPack,
        'trafficGb': trafficGb,
        'unlimitedApps': unlimitedApps,
        'devices': devices,
        'dedicatedIp': dedicatedIp,
      },
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ admin apply tariff.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }
}

/* =========================
   CONFIG STORE (HIDDEN)
   ========================= */

class ConfigStore {
  static Future<void> _configIoBarrier = Future<void>.value();

  Future<T> _runConfigIo<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _configIoBarrier = _configIoBarrier.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  // Active managed config path. Stored in ProgramData so the WireGuard service (LocalSystem) can read it.
  String get managedConfigPath {
    if (kIsWeb) return '';
    if (!Platform.isWindows) return '';
    return r'C:\ProgramData\BlueVPN\BlueVPNDev1.conf';
  }

  // Hidden base config received from server/dev seed. We never apply it directly.
  String get baseConfigPath {
    if (kIsWeb) return '';
    if (!Platform.isWindows) return '';
    return r'C:\ProgramData\BlueVPN\BlueVPNDev1.base.conf';
  }

  Future<bool> hasManagedConfig() async {
    return _runConfigIo(() async {
      if (kIsWeb) return false;
      final p = managedConfigPath;
      if (p.isEmpty) return false;
      return File(p).existsSync();
    });
  }

  Future<bool> hasBaseConfig() async {
    return _runConfigIo(() async {
      if (kIsWeb) return false;
      final p = baseConfigPath;
      if (p.isEmpty) return false;
      return File(p).existsSync();
    });
  }

  Future<String?> readManagedConfig() async {
    return _runConfigIo(() async {
      if (kIsWeb) return null;
      final p = managedConfigPath;
      if (p.isEmpty) return null;
      final f = File(p);
      if (!f.existsSync()) return null;
      await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
      await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
      try {
        return await f.readAsString();
      } on FileSystemException {
        await appendBlueVpnClientLog(
          'config read retry path=${f.path} kind=managed',
        );
        await WindowsLocalSecurity.repairBlueVpnLocalAcls();
        await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
        await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
        return f.existsSync() ? await f.readAsString() : null;
      }
    });
  }

  Future<String?> _readManagedConfigUnlocked() async {
    if (kIsWeb) return null;
    final p = managedConfigPath;
    if (p.isEmpty) return null;
    final f = File(p);
    if (!f.existsSync()) return null;
    await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
    await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
    try {
      return await f.readAsString();
    } on FileSystemException {
      await appendBlueVpnClientLog(
        'config read retry path=${f.path} kind=managed',
      );
      await WindowsLocalSecurity.repairBlueVpnLocalAcls();
      await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
      await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
      return f.existsSync() ? await f.readAsString() : null;
    }
  }

  Future<void> writeManagedConfig(String content) async {
    await _runConfigIo(() async {
      if (kIsWeb) return;
      final p = managedConfigPath;
      if (p.isEmpty) return;
      final f = File(p);
      if (!f.parent.existsSync()) {
        f.parent.createSync(recursive: true);
      }
      await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
      if (f.existsSync()) {
        await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
      }
      try {
        await f.writeAsString(content);
      } on FileSystemException {
        await appendBlueVpnClientLog(
          'config write retry path=${f.path} kind=managed',
        );
        await WindowsLocalSecurity.repairBlueVpnLocalAcls();
        await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
        if (f.existsSync()) {
          await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
        }
        await f.writeAsString(content);
      }
      await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
      await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
    });
  }

  Future<void> writeBaseConfig(String content) async {
    await _runConfigIo(() async {
      if (kIsWeb) return;
      final p = baseConfigPath;
      if (p.isEmpty) return;
      final f = File(p);
      if (!f.parent.existsSync()) {
        f.parent.createSync(recursive: true);
      }
      await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
      if (f.existsSync()) {
        await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
      }
      try {
        await f.writeAsString(content);
      } on FileSystemException {
        await appendBlueVpnClientLog(
          'config write retry path=${f.path} kind=base',
        );
        await WindowsLocalSecurity.repairBlueVpnLocalAcls();
        await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
        if (f.existsSync()) {
          await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
        }
        await f.writeAsString(content);
      }
      await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
      await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
    });
  }

  Future<String?> readBaseConfig() async {
    return _runConfigIo(() async {
      if (kIsWeb) return null;
      final p = baseConfigPath;
      if (p.isEmpty) return null;
      final f = File(p);
      if (!f.existsSync()) {
        return _readManagedConfigUnlocked();
      }
      await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
      await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
      try {
        return await f.readAsString();
      } on FileSystemException {
        await appendBlueVpnClientLog(
          'config read retry path=${f.path} kind=base',
        );
        await WindowsLocalSecurity.repairBlueVpnLocalAcls();
        await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
        await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
        if (f.existsSync()) {
          return await f.readAsString();
        }
        return _readManagedConfigUnlocked();
      }
    });
  }

  Future<void> ensureBaseSeededFromManagedIfMissing() async {
    await _runConfigIo(() async {
      if (kIsWeb) return;
      final base = baseConfigPath;
      if (base.isNotEmpty && File(base).existsSync()) return;

      final managed = managedConfigPath;
      if (managed.isEmpty) return;

      final mf = File(managed);
      if (!mf.existsSync()) return;

      await WindowsLocalSecurity.prepareSharedConfigDirectory(mf.parent.path);
      await WindowsLocalSecurity.prepareSharedConfigFile(mf.path);
      String raw;
      try {
        raw = await mf.readAsString();
      } on FileSystemException {
        await appendBlueVpnClientLog(
          'config read retry path=${mf.path} kind=managed-seed',
        );
        await WindowsLocalSecurity.repairBlueVpnLocalAcls();
        await WindowsLocalSecurity.prepareSharedConfigDirectory(mf.parent.path);
        await WindowsLocalSecurity.prepareSharedConfigFile(mf.path);
        raw = await mf.readAsString();
      }
      if (raw.trim().isEmpty) return;

      final bf = File(base);
      if (!bf.parent.existsSync()) {
        bf.parent.createSync(recursive: true);
      }
      await WindowsLocalSecurity.prepareSharedConfigDirectory(bf.parent.path);
      if (bf.existsSync()) {
        await WindowsLocalSecurity.prepareSharedConfigFile(bf.path);
      }
      try {
        await bf.writeAsString(raw);
      } on FileSystemException {
        await appendBlueVpnClientLog(
          'config write retry path=${bf.path} kind=base-seed',
        );
        await WindowsLocalSecurity.repairBlueVpnLocalAcls();
        await WindowsLocalSecurity.prepareSharedConfigDirectory(bf.parent.path);
        if (bf.existsSync()) {
          await WindowsLocalSecurity.prepareSharedConfigFile(bf.path);
        }
        try {
          await bf.writeAsString(raw);
        } on FileSystemException {
          await appendBlueVpnClientLog(
            'config write skipped path=${bf.path} kind=base-seed',
          );
          return;
        }
      }
      await WindowsLocalSecurity.prepareSharedConfigDirectory(bf.parent.path);
      await WindowsLocalSecurity.prepareSharedConfigFile(bf.path);
    });
  }

  Future<void> deleteManagedConfig() async {
    await _runConfigIo(() async {
      if (kIsWeb) return;

      final managed = managedConfigPath;
      if (managed.isNotEmpty) {
        final f = File(managed);
        if (f.existsSync()) {
          try {
            await WindowsLocalSecurity.prepareSharedConfigDirectory(
              f.parent.path,
            );
            await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
            await f.delete();
          } on FileSystemException {
            await WindowsLocalSecurity.repairBlueVpnLocalAcls();
            await WindowsLocalSecurity.prepareSharedConfigDirectory(
              f.parent.path,
            );
            await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
            if (f.existsSync()) {
              await f.delete();
            }
          }
        }
      }

      final base = baseConfigPath;
      if (base.isNotEmpty) {
        final f = File(base);
        if (f.existsSync()) {
          try {
            await WindowsLocalSecurity.prepareSharedConfigDirectory(
              f.parent.path,
            );
            await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
            await f.delete();
          } on FileSystemException {
            await WindowsLocalSecurity.repairBlueVpnLocalAcls();
            await WindowsLocalSecurity.prepareSharedConfigDirectory(
              f.parent.path,
            );
            await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
            if (f.existsSync()) {
              await f.delete();
            }
          }
        }
      }
    });
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
  final _cfg = ConfigStore();
  final _deviceStore = DeviceIdStore();

  final _phone = TextEditingController();
  final _phoneCode = TextEditingController();
  final _emailCodeEmail = TextEditingController();
  final _emailCode = TextEditingController();
  final _legacyEmail = TextEditingController();
  final _legacyPassword = TextEditingController();

  bool _busy = false;
  String? _authStatus;
  String? _activePhone;
  String? _activeEmailCodeAddress;
  bool _phoneCodeRequested = false;
  bool _emailCodeRequested = false;
  WireGuardInstallState? _wireGuardState;
  bool _wireGuardBusy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    unawaited(_refreshWireGuardState());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _phone.dispose();
    _phoneCode.dispose();
    _emailCodeEmail.dispose();
    _emailCode.dispose();
    _legacyEmail.dispose();
    _legacyPassword.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _setAuthStatus(String? text) {
    if (!mounted) return;
    setState(() => _authStatus = text);
  }

  Future<void> _authLog(String text) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final f = File(r'C:\ProgramData\BlueVPN\auth.log');
      final ts = DateTime.now().toIso8601String();
      await f.writeAsString('[$ts] $text\n', mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _refreshWireGuardState() async {
    final state = await probeWireGuardInstall();
    if (!mounted) return;
    setState(() => _wireGuardState = state);
  }

  Future<void> _installWireGuard() async {
    if (_wireGuardBusy) return;
    setState(() => _wireGuardBusy = true);
    try {
      await _authLog('wireguard install requested from auth');
      final res = await installWireGuardForWindows();
      await _authLog('wireguard install auth ok=${res.ok} msg=${res.message}');
      if (mounted) {
        _toast(res.message);
      }
      await _refreshWireGuardState();
    } finally {
      if (mounted) {
        setState(() => _wireGuardBusy = false);
      }
    }
  }

  Future<bool> _prepareNetworkForAuth(String actionLabel) async {
    if (kIsWeb || !Platform.isWindows) return true;
    try {
      _setAuthStatus('Готовим сеть...');
      final backend = VpnBackend.createDefault(tunnelName: kTunnelName);
      final off = await backend.disconnect();
      await _authLog(
        'disconnect before $actionLabel ok=${off.ok} msg=${off.message ?? ''}',
      );
      if (!off.ok) {
        final text = off.message ?? 'Не удалось подготовить сеть для входа.';
        _setAuthStatus(text);
        _toast(text);
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    } catch (e, st) {
      await _authLog('disconnect before $actionLabel exception=$e stack=$st');
    }
    return true;
  }

  Future<String?> _deviceIdForAuth() async {
    if (kIsWeb) return 'web';
    try {
      return await _deviceStore.getOrCreate();
    } catch (e, st) {
      await _authLog('device id for auth exception=$e stack=$st');
      return null;
    }
  }

  String get _deviceNameForAuth => kIsWeb ? 'Web' : Platform.localHostname;

  String get _platformForAuth => kIsWeb ? 'web' : Platform.operatingSystem;

  String _challengeDeliveryMessage({
    required bool phone,
    required String delivery,
    required bool deliveryReady,
  }) {
    if (phone) {
      if (delivery == 'sent') return 'SMS-код отправлен.';
      if (delivery == 'failed' || !deliveryReady) {
        return 'SMS сейчас недоступна. Используй вход по email-коду.';
      }
      return 'Код подготовлен. Проверь SMS.';
    }
    if (delivery == 'sent') return 'Код отправлен на email.';
    if (delivery == 'failed' || !deliveryReady) {
      return 'Email сейчас недоступен. Попробуй позже или войди по паролю.';
    }
    return 'Код подготовлен. Проверь email.';
  }

  Future<void> _startChallenge({required bool phone}) async {
    if (_busy) return;

    final contact = phone ? _phone.text.trim() : _emailCodeEmail.text.trim();
    if (phone) {
      if (contact.isEmpty) {
        _toast('Введи номер телефона.');
        return;
      }
    } else if (contact.isEmpty || !contact.contains('@')) {
      _toast('Введи корректный email.');
      return;
    }

    setState(() => _busy = true);
    try {
      await _authLog(
        'challenge start method=${phone ? 'phone_sms' : 'email_code'}',
      );
      final networkReady = await _prepareNetworkForAuth(
        phone ? 'phone_challenge_start' : 'email_challenge_start',
      );
      if (!networkReady) return;

      _setAuthStatus(phone ? 'Отправляем SMS-код...' : 'Отправляем код...');
      final res = await _api.startAuthChallenge(
        method: phone ? 'phone_sms' : 'email_code',
        phone: phone ? contact : null,
        email: phone ? null : contact,
      );
      await _authLog(
        'challenge start result ok=${res.ok} msg=${res.message ?? ''}',
      );

      if (!res.ok || res.data == null) {
        final text = authUserMessage(
          res.message ?? 'Не удалось отправить код.',
          fallback: 'Не удалось отправить код.',
        );
        _setAuthStatus(text);
        _toast(text);
        return;
      }

      final data = res.data!;
      final normalized = (data[phone ? 'phone' : 'email'] ?? contact)
          .toString();
      final delivery = (data['deliveryStatus'] ?? '').toString();
      final deliveryReady = data['deliveryReady'] == true;
      final message = _challengeDeliveryMessage(
        phone: phone,
        delivery: delivery,
        deliveryReady: deliveryReady,
      );
      final canEnterCode = delivery != 'failed' && deliveryReady;

      if (!mounted) return;
      setState(() {
        _authStatus = message;
        if (phone) {
          _activePhone = normalized;
          _phone.text = normalized;
          _phoneCode.clear();
          _phoneCodeRequested = canEnterCode;
        } else {
          _activeEmailCodeAddress = normalized;
          _emailCodeEmail.text = normalized;
          _emailCode.clear();
          _emailCodeRequested = canEnterCode;
        }
      });
      _toast(message);
    } catch (e, st) {
      await _authLog('challenge start exception=$e stack=$st');
      final text = authUserMessage(e, fallback: 'Не удалось отправить код.');
      _setAuthStatus(text);
      _toast(text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyChallenge({required bool phone}) async {
    if (_busy) return;

    final contact = phone
        ? (_activePhone ?? _phone.text).trim()
        : (_activeEmailCodeAddress ?? _emailCodeEmail.text).trim();
    final code = phone ? _phoneCode.text.trim() : _emailCode.text.trim();
    if (contact.isEmpty) {
      _toast(phone ? 'Введи номер телефона.' : 'Введи email.');
      return;
    }
    if (code.isEmpty) {
      _toast('Введи код.');
      return;
    }

    setState(() => _busy = true);
    try {
      await _authLog(
        'challenge verify method=${phone ? 'phone_sms' : 'email_code'}',
      );
      final networkReady = await _prepareNetworkForAuth(
        phone ? 'phone_challenge_verify' : 'email_challenge_verify',
      );
      if (!networkReady) return;

      final deviceId = await _deviceIdForAuth();
      _setAuthStatus('Проверяем код...');
      final res = await _api.verifyAuthChallenge(
        method: phone ? 'phone_sms' : 'email_code',
        phone: phone ? contact : null,
        email: phone ? null : contact,
        code: code,
        deviceUid: deviceId,
        deviceName: _deviceNameForAuth,
        platform: _platformForAuth,
        appVersion: kAppVersion,
      );
      await _authLog(
        'challenge verify result ok=${res.ok} msg=${res.message ?? ''}',
      );

      if (!res.ok || res.data == null) {
        final text = authUserMessage(
          res.message ?? 'Не удалось войти по коду.',
          fallback: 'Не удалось войти по коду.',
        );
        _setAuthStatus(text);
        _toast(text);
        return;
      }

      await _completeAuth(
        res.data!,
        progressText: phone
            ? 'Телефон подтверждён. Готовим VPN для этого устройства...'
            : 'Email подтверждён. Готовим VPN для этого устройства...',
      );
    } catch (e, st) {
      await _authLog('challenge verify exception=$e stack=$st');
      final text = authUserMessage(e, fallback: 'Ошибка входа.');
      _setAuthStatus(text);
      _toast(text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitLegacy({required bool isRegister}) async {
    if (_busy) return;

    final email = _legacyEmail.text.trim();
    final pass = _legacyPassword.text;

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
      _setAuthStatus(
        isRegister
            ? 'Создаём аккаунт и сразу войдём в приложение...'
            : 'Входим в аккаунт...',
      );
      await _authLog(
        'legacy auth action=${isRegister ? 'register' : 'login'} email=$email',
      );
      final networkReady = await _prepareNetworkForAuth(
        isRegister ? 'legacy_register' : 'legacy_login',
      );
      if (!networkReady) return;

      _setAuthStatus(
        isRegister ? 'Регистрируем аккаунт...' : 'Проверяем данные...',
      );
      final res = isRegister
          ? await _api.register(email: email, password: pass)
          : await _api.login(email: email, password: pass);
      await _authLog(
        'legacy auth result ok=${res.ok} msg=${res.message ?? ''}',
      );

      if (!res.ok || res.data == null) {
        final text = authUserMessage(
          res.message ?? 'Ошибка авторизации.',
          fallback: 'Ошибка авторизации.',
        );
        _setAuthStatus(text);
        _toast(text);
        return;
      }

      await _completeAuth(
        res.data!,
        progressText: isRegister
            ? 'Аккаунт создан. Готовим VPN для этого устройства...'
            : 'Готовим VPN для этого устройства...',
      );
    } catch (e, st) {
      await _authLog('legacy auth exception=$e stack=$st');
      final text = authUserMessage(e, fallback: 'Ошибка входа.');
      _setAuthStatus(text);
      _toast(text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeAuth(
    Session session, {
    required String progressText,
  }) async {
    _setAuthStatus(progressText);
    final warmup = await AuthProvisioningService(
      api: _api,
      cfg: _cfg,
      deviceStore: _deviceStore,
    ).warmup(session);
    await _authLog('warmup ok=${warmup.ok} msg=${warmup.message ?? ''}');
    if (!warmup.ok && mounted) {
      _toast(
        'Вход выполнен, но серверный VPN-конфиг пока не прогрелся. '
        'Продолжим вход и дотянем конфиг на главном экране.',
      );
    }

    _setAuthStatus('Открываем Green VPN...');
    try {
      await widget.onAuthSuccess(session);
      await _authLog('onAuthSuccess ok=true');
    } catch (e, st) {
      await _authLog('onAuthSuccess exception=$e stack=$st');
      final text =
          'Вход прошёл, но не удалось сохранить сессию на этом ПК. Попробуй запустить Green VPN от имени администратора или переустановить.';
      _setAuthStatus(text);
      _toast(text);
    }
  }

  Widget _buildPrimaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: kBrandPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(
          _busy ? 'Подождите...' : label,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildResendButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildPhoneAuthForm() {
    return Column(
      children: [
        TextField(
          controller: _phone,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          textInputAction: _phoneCodeRequested
              ? TextInputAction.next
              : TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Телефон',
            hintText: '+7 900 000-00-00',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            if (!_busy && !_phoneCodeRequested) {
              unawaited(_startChallenge(phone: true));
            }
          },
        ),
        if (_phoneCodeRequested) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _phoneCode,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Код из SMS',
              hintText: '000000',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              if (!_busy) unawaited(_verifyChallenge(phone: true));
            },
          ),
        ],
        const SizedBox(height: 14),
        _buildPrimaryButton(
          icon: _phoneCodeRequested ? Icons.login_rounded : Icons.sms_rounded,
          label: _phoneCodeRequested ? 'Войти по коду' : 'Получить код',
          onPressed: _busy
              ? null
              : () => _phoneCodeRequested
                    ? _verifyChallenge(phone: true)
                    : _startChallenge(phone: true),
        ),
        if (_phoneCodeRequested) ...[
          const SizedBox(height: 8),
          _buildResendButton(
            label: 'Получить новый код',
            onPressed: _busy ? null : () => _startChallenge(phone: true),
          ),
        ],
      ],
    );
  }

  Widget _buildEmailCodeAuthForm() {
    return Column(
      children: [
        TextField(
          controller: _emailCodeEmail,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: _emailCodeRequested
              ? TextInputAction.next
              : TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            if (!_busy && !_emailCodeRequested) {
              unawaited(_startChallenge(phone: false));
            }
          },
        ),
        if (_emailCodeRequested) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _emailCode,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Код из письма',
              hintText: '000000',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              if (!_busy) unawaited(_verifyChallenge(phone: false));
            },
          ),
        ],
        const SizedBox(height: 14),
        _buildPrimaryButton(
          icon: _emailCodeRequested
              ? Icons.login_rounded
              : Icons.mark_email_read_rounded,
          label: _emailCodeRequested ? 'Войти по коду' : 'Получить код',
          onPressed: _busy
              ? null
              : () => _emailCodeRequested
                    ? _verifyChallenge(phone: false)
                    : _startChallenge(phone: false),
        ),
        if (_emailCodeRequested) ...[
          const SizedBox(height: 8),
          _buildResendButton(
            label: 'Получить новый код',
            onPressed: _busy ? null : () => _startChallenge(phone: false),
          ),
        ],
      ],
    );
  }

  Widget _buildLegacyPasswordForm() {
    return Column(
      children: [
        TextField(
          controller: _legacyEmail,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _legacyPassword,
          enabled: !_busy,
          obscureText: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Пароль',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            if (!_busy) unawaited(_submitLegacy(isRegister: false));
          },
        ),
        const SizedBox(height: 14),
        _buildPrimaryButton(
          icon: Icons.login_rounded,
          label: 'Войти по паролю',
          onPressed: _busy ? null : () => _submitLegacy(isRegister: false),
        ),
        const SizedBox(height: 8),
        _buildResendButton(
          label: 'Создать аккаунт',
          onPressed: _busy ? null : () => _submitLegacy(isRegister: true),
        ),
      ],
    );
  }

  Widget _buildActiveAuthForm() {
    switch (_tabs.index) {
      case 1:
        return _buildEmailCodeAuthForm();
      case 2:
        return _buildLegacyPasswordForm();
      case 0:
      default:
        return _buildPhoneAuthForm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wireGuardState = _wireGuardState;
    final wireGuardMissing =
        wireGuardState != null && !wireGuardState.installed;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
                                    color: kBrandPrimarySoft,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.vpn_key_rounded,
                                    color: kBrandPrimary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        kProductName,
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
                                          color: kBrandMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (wireGuardMissing) ...[
                              _WireGuardSetupCard(
                                title: 'Нужен WireGuard',
                                subtitle: wireGuardState.subtitle,
                                busy: _wireGuardBusy,
                                onInstall: _installWireGuard,
                                onRefresh: _refreshWireGuardState,
                              ),
                              const SizedBox(height: 12),
                            ],
                            TabBar(
                              controller: _tabs,
                              labelStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                              tabs: const [
                                Tab(text: 'Телефон'),
                                Tab(text: 'Email-код'),
                                Tab(text: 'Пароль'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: KeyedSubtree(
                                key: ValueKey<int>(_tabs.index),
                                child: _buildActiveAuthForm(),
                              ),
                            ),
                            if (_authStatus != null &&
                                _authStatus!.trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _authStatus!,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.72),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
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
          },
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
  final String? endpointHost;
  final int? pingMs;
  final bool isAuto;
  final String country;
  final String city;
  final String status;
  final bool available;
  final int? healthScore;
  final String protocolLabel;

  const ServerLocation({
    required this.id,
    required this.title,
    required this.subtitle,
    this.endpointHost,
    this.pingMs,
    this.isAuto = false,
    this.country = '',
    this.city = '',
    this.status = 'unknown',
    this.available = true,
    this.healthScore,
    this.protocolLabel = 'WireGuard',
  });

  static ServerLocation fromCatalogJson(Map<String, dynamic> json) {
    final endpoint = json['endpoint'];
    final endpointMap = endpoint is Map
        ? Map<String, dynamic>.from(endpoint)
        : <String, dynamic>{};
    final protocols = json['protocols'];
    String protocolLabel = 'WireGuard';
    if (protocols is List && protocols.isNotEmpty && protocols.first is Map) {
      final first = Map<String, dynamic>.from(protocols.first as Map);
      protocolLabel = (first['title'] ?? first['code'] ?? protocolLabel)
          .toString();
    }
    final latencyRaw = json['latencyMs'];
    final scoreRaw = json['healthScore'];
    final country = (json['country'] ?? '').toString();
    final city = (json['city'] ?? '').toString();
    final provider = (json['provider'] ?? '').toString();
    final defaultSubtitle = [
      if (city.isNotEmpty) city,
      if (country.isNotEmpty) country,
      if (provider.isNotEmpty) provider,
    ].join(' • ');
    return ServerLocation(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? 'Green VPN endpoint').toString(),
      subtitle: (json['subtitle'] ?? defaultSubtitle).toString(),
      endpointHost: (endpointMap['host'] ?? json['endpointHost'] ?? '')
          .toString(),
      pingMs: latencyRaw is num ? latencyRaw.toInt() : null,
      isAuto: false,
      country: country,
      city: city,
      status: (json['status'] ?? 'unknown').toString(),
      available:
          json['available'] != false &&
          (json['status'] ?? 'unknown').toString() != 'disabled',
      healthScore: scoreRaw is num ? scoreRaw.toInt() : null,
      protocolLabel: protocolLabel,
    );
  }
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
  final _pendingBillingOrderStore = PendingBillingOrderStore();

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

  // "Только для соцсетей"
  bool socialOnlyEnabled = false;
  final Set<SocialApp> socialOnlyApps = {
    SocialApp.telegram,
    SocialApp.instagram,
  };

  // Сервер
  List<ServerLocation> servers = const [
    ServerLocation(
      id: 'auto',
      title: 'Авто',
      subtitle: 'Безопасный dev-сервер Intelligent Smew',
      pingMs: null,
      isAuto: true,
    ),
    ServerLocation(
      id: 'intelligent_smew',
      title: 'Intelligent Smew',
      subtitle: 'Сервер разработки, 37.220.85.211',
      endpointHost: kIntelligentSmewHost,
      pingMs: 44,
      country: 'NL',
      city: 'Amsterdam',
      status: 'healthy',
      healthScore: 95,
    ),
  ];

  ServerLocation selectedServer = const ServerLocation(
    id: 'auto',
    title: 'Авто',
    subtitle: 'Безопасный dev-сервер Intelligent Smew',
    pingMs: null,
    isAuto: true,
  );

  // ===== TARIFF STATE =====
  final Set<TariffApp> selectedApps = {};
  TrafficPack trafficPack = TrafficPack.gb20; // "режим" (по ГБ / безлимит)
  double trafficGb = 20; // любой объём ГБ
  int devices = 1;

  bool optNoAds = true;
  bool optSmartRouting = true; // этим флагом управляем доступностью "соцсетей"
  bool optDedicatedIp = false;
  bool optAutoRenew = true;

  // ===== SETTINGS (косметика) =====
  String sLanguage = 'Русский';

  // Local prefs (persist UI settings)
  final PrefsStore _prefsStore = PrefsStore();
  final PendingVpnActionStore _pendingVpnActionStore = PendingVpnActionStore();
  Timer? _prefsDebounce;
  Timer? _tariffDebounce;
  Timer? _vpnTapCooldownTimer;
  Timer? _pendingBillingPollTimer;
  WireGuardInstallState? _wireGuardState;
  bool _wireGuardBusy = false;
  bool _tariffBusy = false;
  bool _serverCatalogBusy = false;
  Map<String, dynamic>? _tariffCatalog;
  Map<String, dynamic>? _tariffQuote;
  String? _tariffStatus;
  String? _serverCatalogStatus;
  bool _subscriptionActive = false;
  bool _subscriptionAutoRenew = false;
  bool _paymentMethodSaved = false;
  String? _subscriptionExpiresAt;
  int? _subscriptionMonthlyPriceRub;
  bool _vpnTapCooldown = false;
  bool _pendingBillingCheckRunning = false;
  String? _vpnBusyStage;
  String? _vpnBusyHint;
  bool _pendingVpnResumeScheduled = false;
  Map<String, dynamic>? _pendingBillingOrder;
  late bool _emailVerified;
  late bool _emailConfirmationRequired;
  bool _emailStatusBusy = false;
  String? _emailStatusMessage;
  String? _phone;
  bool _phoneVerified = false;
  bool _phoneStatusBusy = false;
  String? _phoneStatusMessage;

  void goToTab(int i) => setState(() => _index = i);

  bool get _vpnInteractionLocked => vpnBusy || _vpnTapCooldown;

  @override
  void initState() {
    super.initState();
    _vpnBackend = VpnBackend.createDefault(tunnelName: kTunnelName);
    _emailVerified = widget.session.emailVerified;
    _emailConfirmationRequired = widget.session.emailConfirmationRequired;
    _phone = widget.session.phone;
    _phoneVerified = widget.session.phoneVerified;

    _loadPrefsAndApply();

    _syncVpnStatus();
    _ensureProvisionedConfigSilently();
    _syncPlanSilently();
    _syncTariffFromServerSilently();
    _loadPendingBillingOrder();
    _refreshTariffServerState(showToast: false);
    _refreshServerCatalog(showToast: false);
    _refreshEmailStatus(showToast: false);
    _refreshPhoneStatus(showToast: false);
    unawaited(_refreshWireGuardState());
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _refreshWireGuardState() async {
    final state = await probeWireGuardInstall();
    if (!mounted) return;
    setState(() => _wireGuardState = state);
  }

  Future<void> _installWireGuard() async {
    if (_wireGuardBusy) return;
    setState(() => _wireGuardBusy = true);
    try {
      final res = await installWireGuardForWindows();
      if (mounted) {
        _toast(context, res.message);
      }
      await _refreshWireGuardState();
      await _syncVpnStatus();
    } finally {
      if (mounted) {
        setState(() => _wireGuardBusy = false);
      }
    }
  }

  Future<void> _refreshEmailStatus({required bool showToast}) async {
    if (kIsWeb || widget.session.accessToken == 'dev-token') return;
    if (_emailStatusBusy) return;
    setState(() => _emailStatusBusy = true);
    try {
      final res = await _api.fetchEmailStatus(
        accessToken: widget.session.accessToken,
      );
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        final text = res.message ?? 'Не удалось проверить статус почты.';
        setState(() => _emailStatusMessage = text);
        if (showToast) _toast(context, text);
        return;
      }
      final data = res.data!;
      final verified = data['emailVerified'] == true;
      final required = data['emailConfirmationRequired'] == true;
      setState(() {
        _emailVerified = verified;
        _emailConfirmationRequired = required;
        _emailStatusMessage = verified
            ? 'Почта подтверждена.'
            : 'Почта пока не подтверждена.';
      });
      if (showToast) _toast(context, _emailStatusMessage!);
    } finally {
      if (mounted) setState(() => _emailStatusBusy = false);
    }
  }

  Future<void> _resendEmailConfirmation() async {
    if (kIsWeb || widget.session.accessToken == 'dev-token') return;
    if (_emailStatusBusy) return;
    setState(() {
      _emailStatusBusy = true;
      _emailStatusMessage = 'Отправляем письмо подтверждения...';
    });
    try {
      final res = await _api.resendEmailConfirmation(
        accessToken: widget.session.accessToken,
      );
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        final text = res.message ?? 'Не удалось отправить письмо.';
        setState(() => _emailStatusMessage = text);
        _toast(context, text);
        return;
      }
      final data = res.data!;
      final verified = data['emailVerified'] == true;
      final delivery = (data['deliveryStatus'] ?? '').toString();
      final text = verified
          ? 'Почта уже подтверждена.'
          : delivery == 'sent'
          ? 'Письмо отправлено. Проверь почту.'
          : 'Письмо подготовлено. Отправка включится после подключения почтового сервиса.';
      setState(() {
        _emailVerified = verified;
        _emailConfirmationRequired = data['emailConfirmationRequired'] == true;
        _emailStatusMessage = text;
      });
      _toast(context, text);
    } finally {
      if (mounted) setState(() => _emailStatusBusy = false);
    }
  }

  Future<void> _refreshPhoneStatus({required bool showToast}) async {
    if (kIsWeb || widget.session.accessToken == 'dev-token') return;
    if (_phoneStatusBusy) return;
    setState(() => _phoneStatusBusy = true);
    try {
      final res = await _api.fetchPhoneStatus(
        accessToken: widget.session.accessToken,
      );
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        final text = res.message ?? 'Не удалось проверить статус телефона.';
        setState(() => _phoneStatusMessage = text);
        if (showToast) _toast(context, text);
        return;
      }
      final data = res.data!;
      final phone = (data['phone'] ?? '').toString().trim();
      final verified = data['phoneVerified'] == true;
      setState(() {
        _phone = phone.isEmpty ? null : phone;
        _phoneVerified = verified;
        _phoneStatusMessage = verified
            ? 'Телефон подтверждён.'
            : 'Телефон пока не подтверждён.';
      });
      if (showToast) _toast(context, _phoneStatusMessage!);
    } finally {
      if (mounted) setState(() => _phoneStatusBusy = false);
    }
  }

  Future<Map<String, dynamic>?> _startPhoneConfirmation(String phone) async {
    if (_phoneStatusBusy) return null;
    setState(() {
      _phoneStatusBusy = true;
      _phoneStatusMessage = 'Готовим SMS-код...';
    });
    try {
      final res = await _api.startPhoneConfirmation(
        accessToken: widget.session.accessToken,
        phone: phone,
      );
      if (!mounted) return null;
      if (!res.ok || res.data == null) {
        final text = authUserMessage(
          res.message ?? 'Не удалось отправить SMS.',
          fallback: 'Не удалось отправить SMS.',
        );
        setState(() => _phoneStatusMessage = text);
        _toast(context, text);
        return null;
      }
      final data = res.data!;
      final normalizedPhone = (data['phone'] ?? phone).toString();
      final verified = data['phoneVerified'] == true;
      final delivery = (data['deliveryStatus'] ?? '').toString();
      final text = verified
          ? 'Телефон уже подтверждён.'
          : delivery == 'sent'
          ? 'SMS-код отправлен.'
          : delivery == 'failed'
          ? 'SMS не отправилось. Проверь настройки SMS-провайдера.'
          : 'Телефон подготовлен. Реальная отправка включится после подключения SMS-провайдера.';
      setState(() {
        _phone = normalizedPhone;
        _phoneVerified = verified;
        _phoneStatusMessage = text;
      });
      _toast(context, text);
      return data;
    } finally {
      if (mounted) setState(() => _phoneStatusBusy = false);
    }
  }

  Future<bool> _verifyPhoneConfirmation(String phone, String code) async {
    if (_phoneStatusBusy) return false;
    setState(() {
      _phoneStatusBusy = true;
      _phoneStatusMessage = 'Проверяем SMS-код...';
    });
    try {
      final res = await _api.verifyPhoneConfirmation(
        accessToken: widget.session.accessToken,
        phone: phone,
        code: code,
      );
      if (!mounted) return false;
      if (!res.ok || res.data == null || res.data!['ok'] != true) {
        final status = (res.data?['status'] ?? '').toString();
        final text = status == 'expired'
            ? 'SMS-код истёк. Запроси новый код.'
            : status == 'invalid_code'
            ? 'Неверный SMS-код.'
            : res.message ?? 'Не удалось подтвердить телефон.';
        setState(() => _phoneStatusMessage = text);
        _toast(context, text);
        return false;
      }
      final verifiedPhone = (res.data!['phone'] ?? phone).toString();
      setState(() {
        _phone = verifiedPhone;
        _phoneVerified = true;
        _phoneStatusMessage = 'Телефон подтверждён.';
      });
      _toast(context, 'Телефон подтверждён.');
      return true;
    } finally {
      if (mounted) setState(() => _phoneStatusBusy = false);
    }
  }

  Future<void> _showPhoneBindingDialog() async {
    if (kIsWeb || widget.session.accessToken == 'dev-token') return;
    final phoneController = TextEditingController(text: _phone ?? '');
    final codeController = TextEditingController();
    bool codeRequested = false;
    String? activePhone = _phone;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                title: const Text('Привязать телефон'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Телефон',
                        hintText: '+7 900 000-00-00',
                      ),
                    ),
                    if (codeRequested) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Код из SMS',
                          hintText: '000000',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      _phoneStatusMessage ??
                          'SMS-вход подготовлен. После подключения провайдера код будет приходить автоматически.',
                      style: const TextStyle(
                        color: kBrandMuted,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Закрыть'),
                  ),
                  FilledButton(
                    onPressed: _phoneStatusBusy
                        ? null
                        : () async {
                            if (!codeRequested) {
                              final data = await _startPhoneConfirmation(
                                phoneController.text,
                              );
                              if (data == null) return;
                              activePhone =
                                  (data['phone'] ?? phoneController.text)
                                      .toString();
                              phoneController.text =
                                  activePhone ?? phoneController.text;
                              if (data['phoneVerified'] == true) {
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                                return;
                              }
                              if (data['deliveryStatus'] == 'sent') {
                                setDialogState(() => codeRequested = true);
                              }
                              return;
                            }

                            final ok = await _verifyPhoneConfirmation(
                              activePhone ?? phoneController.text,
                              codeController.text,
                            );
                            if (ok && dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                    child: Text(codeRequested ? 'Подтвердить' : 'Получить код'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      phoneController.dispose();
      codeController.dispose();
    }
  }

  Future<void> _loadPrefsAndApply() async {
    if (kIsWeb) return;

    try {
      final p = await _prefsStore.readPrefs();
      if (!mounted) return;

      // English UI is not shipped yet, so do not expose a fake broken switch.
      sLanguage = 'Русский';

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

      optNoAds = true;
      optSmartRouting =
          true; // временно всегда разрешаем Social Only в Windows-клиенте
      optDedicatedIp = p.optDedicatedIp;
      optAutoRenew = p.optAutoRenew;

      await _repairProvisionedConfigFromPreferredDevSource(showToast: false);
      await _cfg.ensureBaseSeededFromManagedIfMissing();
      final base = await _cfg.readBaseConfig();
      if (base != null && base.trim().isNotEmpty) {
        await _cfg.writeManagedConfig(_buildManagedConfigFromBase(base));
      }

      if (mounted) setState(() {});
    } catch (_) {
      // ignore
    } finally {
      if (!_pendingVpnResumeScheduled) {
        _pendingVpnResumeScheduled = true;
        unawaited(_resumePendingVpnActionIfNeeded());
      }
    }
  }

  Future<void> _resumePendingVpnActionIfNeeded() async {
    if (kIsWeb || !Platform.isWindows) return;

    final action = await _pendingVpnActionStore.read();
    if (action == null || action.isEmpty) return;
    await appendBlueVpnClientLog('resume pending start action=$action');

    final elevated = await isWindowsProcessElevated();
    await appendBlueVpnClientLog(
      'resume pending elevated=$elevated action=$action vpnEnabled=$vpnEnabled',
    );
    if (!elevated) return;

    await _pendingVpnActionStore.clear();
    await appendBlueVpnClientLog('resume pending cleared action=$action');

    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    if (action == 'connect' && !vpnEnabled) {
      await appendBlueVpnClientLog('resume pending invoking connect');
      await _toggleVpnReal();
      return;
    }

    if (action == 'disconnect' && vpnEnabled) {
      await appendBlueVpnClientLog('resume pending invoking disconnect');
      await _toggleVpnReal();
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
          'optNoAds': true,
          'optSmartRouting': true,
          'optDedicatedIp': optDedicatedIp,
          'optAutoRenew': optAutoRenew,
        }),
      );
    });
  }

  List<String> _selectedTariffAppCodes() {
    return selectedApps.map((e) => e.name).toList()..sort();
  }

  void _applyTariffSelectionFromServer(Map<String, dynamic> selection) {
    final packName = (selection['trafficPack'] ?? '').toString().trim();
    final nextPack = TrafficPack.values.firstWhere(
      (item) => item.name == packName,
      orElse: () => TrafficPack.gb20,
    );

    final nextGb = ((selection['trafficGb'] ?? trafficGb) as num).toDouble();
    final nextDevices = (selection['devices'] ?? devices) as int;
    final nextDedicatedIp = selection['dedicatedIp'] == true;
    final nextAutoRenew = selection['autoRenew'] == true;
    final rawApps = (selection['unlimitedApps'] as List?) ?? const [];
    final nextApps = <TariffApp>{};
    for (final item in rawApps) {
      final name = item.toString();
      final match = TariffApp.values.where((entry) => entry.name == name);
      if (match.isNotEmpty) {
        nextApps.add(match.first);
      }
    }

    setState(() {
      trafficPack = nextPack;
      trafficGb = nextGb.clamp(1.0, 500.0);
      devices = nextDevices.clamp(1, 5);
      optNoAds = true;
      optSmartRouting = true;
      optDedicatedIp = nextDedicatedIp;
      optAutoRenew = nextAutoRenew;
      selectedApps
        ..clear()
        ..addAll(nextApps);
    });
  }

  void _scheduleTariffRefresh() {
    if (kIsWeb || widget.session.accessToken == 'dev-token') return;
    _tariffDebounce?.cancel();
    _tariffDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_refreshTariffServerState(showToast: false));
    });
  }

  Future<void> _loadPendingBillingOrder() async {
    final order = await _pendingBillingOrderStore.read();
    if (!mounted || order == null) return;
    setState(() => _pendingBillingOrder = order);
    _startPendingBillingPolling();
    unawaited(_checkPendingBillingOrder(showToast: false, showBusy: false));
  }

  void _startPendingBillingPolling() {
    if (kIsWeb || widget.session.accessToken == 'dev-token') return;
    if (_pendingBillingPollTimer != null) return;
    _pendingBillingPollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || _pendingBillingOrder == null) {
        _stopPendingBillingPolling();
        return;
      }
      unawaited(_checkPendingBillingOrder(showToast: false, showBusy: false));
    });
  }

  void _stopPendingBillingPolling() {
    _pendingBillingPollTimer?.cancel();
    _pendingBillingPollTimer = null;
    _pendingBillingCheckRunning = false;
  }

  Future<void> _openPaymentUrl(String url) async {
    _startPendingBillingPolling();
    await openExternalUrl(url);
  }

  Future<void> _syncTariffFromServerSilently() async {
    if (kIsWeb || widget.session.accessToken == 'dev-token') return;
    try {
      final res = await _api.fetchSubscriptionProfile(
        accessToken: widget.session.accessToken,
      );
      if (!res.ok || res.data == null) return;

      final plan = (res.data!['planName'] ?? '').toString().trim();
      final selection = res.data!['selection'];
      final subscription = res.data!['subscription'];
      if (!mounted) return;

      if (selection is Map) {
        _applyTariffSelectionFromServer(Map<String, dynamic>.from(selection));
      }
      setState(() {
        if (plan.isNotEmpty) {
          planName = plan;
        }
        _applySubscriptionUiState(res.data!, subscription);
      });
    } catch (_) {}
  }

  void _applySubscriptionUiState(
    Map<String, dynamic> profile,
    Object? subscription,
  ) {
    Map<String, dynamic>? sub;
    if (subscription is Map) {
      sub = Map<String, dynamic>.from(subscription);
    }

    _subscriptionActive =
        profile['isActive'] == true || sub?['isActive'] == true;
    final expiresRaw = profile['expiresAt'] ?? sub?['expiresAt'];
    final expires = expiresRaw == null ? '' : expiresRaw.toString().trim();
    _subscriptionExpiresAt = expires.isEmpty ? null : expires;

    final monthlyRaw = profile['monthlyPriceRub'] ?? sub?['monthlyPriceRub'];
    _subscriptionMonthlyPriceRub = monthlyRaw is num
        ? monthlyRaw.toInt()
        : int.tryParse((monthlyRaw ?? '').toString());

    final autoRenewRaw = profile['autoRenew'] ?? sub?['autoRenew'];
    _subscriptionAutoRenew = autoRenewRaw == true;
    final paymentMethodRaw =
        profile['paymentMethodSaved'] ?? sub?['paymentMethodSaved'];
    _paymentMethodSaved = paymentMethodRaw == true;
  }

  Future<void> _cancelAutoRenew() async {
    if (kIsWeb) return;
    if (widget.session.accessToken == 'dev-token') {
      _toast(context, 'DEV-вход: отключение автопродления недоступно.');
      return;
    }

    if (mounted) setState(() => _tariffBusy = true);
    try {
      final res = await _api.cancelAutoRenew(
        accessToken: widget.session.accessToken,
      );
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        final text = res.message ?? 'Не удалось отключить автопродление.';
        setState(() => _tariffStatus = text);
        _toast(context, text);
        return;
      }

      final rawSub = res.data!['subscription'];
      final sub = rawSub is Map
          ? Map<String, dynamic>.from(rawSub)
          : <String, dynamic>{};
      final selection = sub['selection'];
      if (selection is Map) {
        _applyTariffSelectionFromServer(Map<String, dynamic>.from(selection));
      }
      setState(() {
        optAutoRenew = false;
        _applySubscriptionUiState(const <String, dynamic>{}, sub);
        _tariffStatus =
            'Автопродление отключено. Текущий оплаченный период останется активным.';
      });
      _schedulePrefsSave();
      _toast(context, 'Автопродление отключено.');
    } finally {
      if (mounted) setState(() => _tariffBusy = false);
    }
  }

  Future<void> _refreshTariffServerState({required bool showToast}) async {
    if (kIsWeb) return;
    if (widget.session.accessToken == 'dev-token') {
      if (mounted) {
        setState(() {
          _tariffCatalog = null;
          _tariffQuote = null;
          _tariffStatus = 'DEV-вход: серверный тарифный каталог недоступен.';
        });
      }
      return;
    }

    if (mounted) setState(() => _tariffBusy = true);
    try {
      final catalogRes = await _api.fetchTariffCatalog();
      final quoteRes = await _api.quoteTariff(
        trafficPack: trafficPack.name,
        trafficGb: trafficGb.round(),
        unlimitedApps: _selectedTariffAppCodes(),
        devices: devices,
        dedicatedIp: optDedicatedIp,
      );

      if (!mounted) return;

      if (!catalogRes.ok || catalogRes.data == null) {
        setState(
          () => _tariffStatus =
              catalogRes.message ?? 'Не удалось загрузить каталог тарифов.',
        );
        if (showToast) {
          _toast(context, _tariffStatus!);
        }
        return;
      }

      if (!quoteRes.ok || quoteRes.data == null) {
        setState(() {
          _tariffCatalog = catalogRes.data;
          _tariffStatus = quoteRes.message ?? 'Не удалось пересчитать тариф.';
        });
        if (showToast) {
          _toast(context, _tariffStatus!);
        }
        return;
      }

      setState(() {
        _tariffCatalog = catalogRes.data;
        _tariffQuote = quoteRes.data;
        final quote = quoteRes.data!['quote'];
        final monthly = quote is Map ? quote['monthlyPriceRub'] : null;
        _tariffStatus = monthly == null
            ? 'Цена обновлена.'
            : 'Цена обновлена: $monthly ₽/мес.';
      });

      if (showToast) {
        _toast(context, _tariffStatus!);
      }
    } finally {
      if (mounted) setState(() => _tariffBusy = false);
    }
  }

  Future<void> _createTariffOrderOnServer() async {
    if (kIsWeb) return;
    if (widget.session.accessToken == 'dev-token') {
      _toast(context, 'Сначала войди в аккаунт, чтобы подключить тариф.');
      return;
    }

    if (mounted) setState(() => _tariffBusy = true);
    try {
      final res = await _api.createBillingOrder(
        accessToken: widget.session.accessToken,
        trafficPack: trafficPack.name,
        trafficGb: trafficGb.round(),
        unlimitedApps: _selectedTariffAppCodes(),
        devices: devices,
        dedicatedIp: optDedicatedIp,
        autoRenew: optAutoRenew,
      );

      if (!mounted) return;
      if (!res.ok || res.data == null) {
        final text = res.message ?? 'Не удалось создать заказ на оплату.';
        setState(() => _tariffStatus = text);
        _toast(context, text);
        return;
      }

      final order = res.data!['order'];
      final orderMap = order is Map ? Map<String, dynamic>.from(order) : null;
      final selection = orderMap?['selection'];
      final quote = orderMap?['quote'];

      if (selection is Map) {
        _applyTariffSelectionFromServer(Map<String, dynamic>.from(selection));
      }

      setState(() {
        _tariffQuote = {
          if (selection is Map)
            'selection': Map<String, dynamic>.from(selection),
          if (quote is Map) 'quote': Map<String, dynamic>.from(quote),
          if (orderMap != null) 'order': orderMap,
        };
        if (orderMap != null) {
          _pendingBillingOrder = orderMap;
        }
        final orderId = (orderMap?['orderId'] ?? '').toString();
        _tariffStatus = orderId.isEmpty
            ? 'Заказ на оплату создан. Тариф активируется после подтверждения оплаты.'
            : 'Заказ $orderId создан. Тариф активируется после подтверждения оплаты.';
      });
      if (orderMap != null) {
        await _pendingBillingOrderStore.write(orderMap);
        _startPendingBillingPolling();
      }
      _schedulePrefsSave();
      _toast(context, 'Заказ на оплату создан.');
      final paymentUrl = (orderMap?['paymentUrl'] ?? '').toString().trim();
      if (paymentUrl.isNotEmpty) {
        await _openPaymentUrl(paymentUrl);
      }
    } finally {
      if (mounted) setState(() => _tariffBusy = false);
    }
  }

  Future<void> _checkPendingBillingOrder({
    required bool showToast,
    bool showBusy = true,
  }) async {
    if (kIsWeb) return;
    if (widget.session.accessToken == 'dev-token') {
      if (showToast) {
        _toast(context, 'DEV-вход: проверка оплаты недоступна.');
      }
      return;
    }
    if (_pendingBillingCheckRunning) return;

    final order =
        _pendingBillingOrder ?? await _pendingBillingOrderStore.read();
    final orderId = (order?['orderId'] ?? '').toString().trim();
    if (orderId.isEmpty) {
      _stopPendingBillingPolling();
      if (showToast) {
        _toast(context, 'Активного заказа на оплату нет.');
      }
      return;
    }

    _pendingBillingCheckRunning = true;
    if (showBusy && mounted) setState(() => _tariffBusy = true);
    try {
      final res = await _api.fetchBillingOrder(
        accessToken: widget.session.accessToken,
        orderId: orderId,
      );
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        final text = res.message ?? 'Не удалось проверить оплату.';
        setState(() => _tariffStatus = text);
        if (showToast) _toast(context, text);
        return;
      }

      final rawOrder = res.data!['order'];
      final freshOrder = rawOrder is Map
          ? Map<String, dynamic>.from(rawOrder)
          : <String, dynamic>{};
      final status = (freshOrder['status'] ?? '').toString().trim();

      if (status == 'activated' || status == 'paid') {
        await _pendingBillingOrderStore.clear();
        _stopPendingBillingPolling();
        setState(() {
          _pendingBillingOrder = null;
          _tariffStatus = 'Оплата подтверждена. Тариф активирован.';
        });
        await _syncTariffFromServerSilently();
        await _syncPlanSilently();
        await _refreshTariffServerState(showToast: false);
        if (showToast && mounted) {
          _toast(context, 'Оплата подтверждена, тариф активирован.');
        }
        return;
      }

      if (status == 'canceled' || status == 'expired') {
        await _pendingBillingOrderStore.clear();
        _stopPendingBillingPolling();
        setState(() {
          _pendingBillingOrder = null;
          _tariffStatus = status == 'expired'
              ? 'Срок оплаты заказа истёк. Создай новый заказ.'
              : 'Заказ отменён. Можно создать новый заказ на оплату.';
        });
        if (showToast) {
          _toast(context, 'Заказ больше не ожидает оплату.');
        }
        return;
      }

      await _pendingBillingOrderStore.write(freshOrder);
      setState(() {
        _pendingBillingOrder = freshOrder;
        _tariffStatus =
            'Заказ ещё ожидает подтверждения оплаты. Green VPN проверяет оплату автоматически.';
      });
      if (showToast) {
        _toast(context, 'Оплата пока не подтверждена.');
      }
    } finally {
      _pendingBillingCheckRunning = false;
      if (showBusy && mounted) setState(() => _tariffBusy = false);
    }
  }

  String? _readConfigField(String rawConfig, String fieldName) {
    final match = RegExp(
      '^\\s*$fieldName\\s*=\\s*(.+?)\\s*\$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(rawConfig);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? _endpointHostFromConfig(String rawConfig) {
    final endpoint = (_readConfigField(rawConfig, 'Endpoint') ?? '')
        .toLowerCase();
    if (endpoint.isEmpty) return null;

    final value = endpoint.trim();
    if (value.startsWith('[')) {
      final endBracket = value.indexOf(']');
      if (endBracket > 1) {
        return value.substring(1, endBracket);
      }
    }

    final lastColon = value.lastIndexOf(':');
    if (lastColon <= 0) return value;
    return value.substring(0, lastColon);
  }

  bool _configLooksLikeDedicatedDev1(String rawConfig) {
    final endpointHost = _endpointHostFromConfig(rawConfig);
    if (endpointHost == null || endpointHost.isEmpty) return false;

    if (rawConfig.contains('engage.cloudflareclient.com')) return false;
    if (rawConfig.contains('\n    S1 =') ||
        rawConfig.contains('\r\n    S1 =')) {
      return false;
    }

    return endpointHost == kIntelligentSmewHost;
  }

  String _normalizeDevEndpoint(String rawConfig) {
    return normalizeProvisionedEndpoint(rawConfig);
  }

  bool _configLooksLikeSupportedLocalServer(String rawConfig) {
    return _configLooksLikeDedicatedDev1(rawConfig);
  }

  String? _expectedEndpointHostForSelection() {
    if (selectedServer.isAuto) return null;
    return selectedServer.endpointHost;
  }

  bool _configMatchesSelectedServer(String rawConfig) {
    final endpointHost = _endpointHostFromConfig(rawConfig);
    if (endpointHost == null || endpointHost.isEmpty) return false;

    final expectedHost = _expectedEndpointHostForSelection();
    if (expectedHost == null) {
      return endpointHost == kIntelligentSmewHost;
    }

    return endpointHost == expectedHost;
  }

  List<String> _preferredLocalConfigCandidates() {
    if (kIsWeb || !Platform.isWindows) return const [];

    final out = <String>[];
    final seen = <String>{};

    void addCandidate(String? path) {
      if (path == null) return;
      final trimmed = path.trim();
      if (trimmed.isEmpty) return;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        out.add(trimmed);
      }
    }

    final programData = Platform.environment['ProgramData'];
    if (programData != null && programData.isNotEmpty) {
      final bluevpnDir = Directory('$programData\\BlueVPN');
      addCandidate('$programData\\BlueVPN\\BlueVPNDev1.base.conf');
      addCandidate('$programData\\BlueVPN\\BlueVPNDev1.conf');
      addCandidate('$programData\\BlueVPN\\BlueVPNDev1.real.conf');
      addCandidate('$programData\\BlueVPN\\BlueVPNDev1.seed.conf');
      addCandidate('$programData\\BlueVPN\\BlueVPN.base.conf');
      addCandidate('$programData\\BlueVPN\\BlueVPN.conf');
      addCandidate('$programData\\BlueVPN\\BlueVPN.conf.full.bak');

      final systemDrive = Platform.environment['SystemDrive'] ?? 'C:';
      addCandidate('$systemDrive\\313\\BlueVPNDev1.real.conf');

      if (bluevpnDir.existsSync()) {
        final backupDirs =
            bluevpnDir
                .listSync()
                .whereType<Directory>()
                .where(
                  (dir) =>
                      dir.path.toLowerCase().contains('\\backup_dev1_') ||
                      dir.path.toLowerCase().contains(
                        '\\backup_reseed_dev1_',
                      ) ||
                      dir.path.toLowerCase().contains('\\backup_reset_') ||
                      dir.path.toLowerCase().contains(
                        '\\backup_switch_to_warp_',
                      ),
                )
                .toList()
              ..sort((a, b) => b.path.compareTo(a.path));

        for (final dir in backupDirs) {
          addCandidate('${dir.path}\\BlueVPNDev1.conf');
          addCandidate('${dir.path}\\BlueVPNDev1.base.conf');
          addCandidate('${dir.path}\\BlueVPN.conf');
          addCandidate('${dir.path}\\BlueVPN.base.conf');
        }
      }
    }

    final resolvedExecutable = Platform.resolvedExecutable;
    if (resolvedExecutable.isNotEmpty) {
      final exeDir = File(resolvedExecutable).parent.path;
      addCandidate('$exeDir\\BlueVPNDev1.real.conf');
      addCandidate('$exeDir\\BlueVPNDev1.conf');
      addCandidate('$exeDir\\BlueVPN.conf');
    }

    final cwd = Directory.current.path;
    addCandidate('$cwd\\BlueVPNDev1.real.conf');
    addCandidate('$cwd\\BlueVPNDev1.conf');
    addCandidate('$cwd\\BlueVPN.conf');

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      addCandidate('$userProfile\\Desktop\\BlueVPNDev1.real.conf');
      addCandidate('$userProfile\\Desktop\\BlueVPNDev1.conf');
      addCandidate('$userProfile\\Downloads\\BlueVPNDev1.real.conf');
      addCandidate('$userProfile\\Downloads\\BlueVPNDev1.conf');
      addCandidate('$userProfile\\Downloads\\WARP.conf');
      addCandidate('$userProfile\\Desktop\\WARP.conf');
    }

    return out;
  }

  Future<_LocalConfigCandidate?> _findPreferredLocalConfig() async {
    for (final p in _preferredLocalConfigCandidates()) {
      final f = File(p);
      if (!f.existsSync()) continue;
      try {
        final raw = _normalizeDevEndpoint(await f.readAsString());
        if (raw.trim().isEmpty) continue;
        if (!_configLooksLikeSupportedLocalServer(raw)) continue;
        if (!_configMatchesSelectedServer(raw)) continue;
        return _LocalConfigCandidate(path: p, content: raw);
      } catch (_) {
        // ignore and try next
      }
    }
    return null;
  }

  Future<bool> _repairProvisionedConfigFromPreferredDevSource({
    required bool showToast,
  }) async {
    if (kIsWeb || !Platform.isWindows) return false;

    await _cfg.ensureBaseSeededFromManagedIfMissing();

    String? base;
    try {
      base = await _cfg.readBaseConfig();
    } catch (_) {
      base = null;
    }

    final normalizedBase = base == null ? null : _normalizeDevEndpoint(base);
    if (normalizedBase != null &&
        normalizedBase.trim().isNotEmpty &&
        _configLooksLikeSupportedLocalServer(normalizedBase) &&
        _configMatchesSelectedServer(normalizedBase)) {
      if (normalizedBase != base) {
        await _writeProvisionedConfig(normalizedBase);
      }
      return true;
    }

    final preferred = await _findPreferredLocalConfig();
    if (preferred == null || preferred.content.trim().isEmpty) return false;

    await _writeProvisionedConfig(preferred.content);

    if (showToast && mounted) {
      _toast(context, 'BlueVPNDev1 конфиг восстановлен из ${preferred.path}');
    }
    return true;
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
    return replaceAllowedIpsInConfig(configText, allowedIps);
  }

  String _buildManagedConfigFromBase(String baseConfig) {
    if (!socialOnlyEnabled) {
      return _replaceAllowedIps(baseConfig, const ['0.0.0.0/0', '::/0']);
    }

    final allowedIps = _resolveSocialAllowedIps(socialOnlyApps);
    return _replaceAllowedIps(baseConfig, allowedIps);
  }

  Future<void> _writeProvisionedConfig(String rawConfig) async {
    await _cfg.writeManagedConfig(_buildManagedConfigFromBase(rawConfig));
    try {
      await _cfg.writeBaseConfig(rawConfig);
    } catch (e) {
      await appendBlueVpnClientLog(
        'config write skipped path=${_cfg.baseConfigPath} kind=base-root error=$e',
      );
    }
  }

  Future<bool> _reuseExistingProvisionedConfig({
    required String reason,
    required bool showToast,
  }) async {
    try {
      await _cfg.ensureBaseSeededFromManagedIfMissing();
      final base = await _cfg.readBaseConfig();
      if (base == null || base.trim().isEmpty) return false;

      final normalizedBase = _normalizeDevEndpoint(base);
      if (!_configLooksLikeSupportedLocalServer(normalizedBase) ||
          !_configMatchesSelectedServer(normalizedBase)) {
        return false;
      }

      await _cfg.writeManagedConfig(
        _buildManagedConfigFromBase(normalizedBase),
      );
      await appendBlueVpnClientLog(
        'ensure config fetch failed; using existing local config: $reason',
      );
      if (showToast && mounted) {
        _toast(context, 'Использую сохранённый VPN-конфиг.');
      }
      return true;
    } catch (e) {
      await appendBlueVpnClientLog('local config fallback failed: $e');
      return false;
    }
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
    setState(() => sLanguage = 'Русский');
    _schedulePrefsSave();
  }

  Future<void> _syncVpnStatus() async {
    final wgState = _wireGuardState;
    if (wgState != null && !wgState.installed) {
      if (mounted) setState(() => vpnEnabled = false);
      return;
    }
    final on = await _vpnBackend.isConnected();
    if (mounted) setState(() => vpnEnabled = on);
  }

  bool _isDeviceAttachedConflict(String? message) {
    final raw = (message ?? '').toLowerCase();
    return raw.contains('409') &&
        raw.contains('device') &&
        raw.contains('attached') &&
        raw.contains('another user');
  }

  Future<String?> _rotateDeviceId() async {
    if (kIsWeb) return null;
    final next = await _deviceStore.rotate();
    _deviceId = next;
    return next;
  }

  Future<ApiResult<Map<String, dynamic>>> _bootstrapWithDeviceRetry({
    required bool showToastOnRotate,
  }) async {
    var did = await _ensureDeviceId();
    if (did == null || did.isEmpty) {
      return const ApiResult.err('Не удалось получить device id.');
    }

    var boot = await _api.bootstrapClient(
      accessToken: widget.session.accessToken,
      deviceId: did,
      deviceName: Platform.localHostname,
      platform: 'windows',
      appVersion: kAppVersion,
    );

    if (!_isDeviceAttachedConflict(boot.message)) {
      return boot;
    }

    did = await _rotateDeviceId();
    if (did == null || did.isEmpty) {
      return const ApiResult.err('Не удалось перевыпустить device id.');
    }

    if (showToastOnRotate && mounted) {
      _toast(
        context,
        'Устройство было привязано к старому аккаунту. Создаю новый device id...',
      );
    }

    return _api.bootstrapClient(
      accessToken: widget.session.accessToken,
      deviceId: did,
      deviceName: Platform.localHostname,
      platform: 'windows',
      appVersion: kAppVersion,
    );
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
    return _repairProvisionedConfigFromPreferredDevSource(showToast: showToast);
  }

  Future<void> _ensureProvisionedConfigSilently() async {
    if (kIsWeb) return;
    try {
      if (widget.session.accessToken == 'dev-token') {
        final repaired = await _repairProvisionedConfigFromPreferredDevSource(
          showToast: false,
        );
        if (repaired) {
          await _cfg.ensureBaseSeededFromManagedIfMissing();
          final base = await _cfg.readBaseConfig();
          if (base != null && base.trim().isNotEmpty) {
            await _cfg.writeManagedConfig(_buildManagedConfigFromBase(base));
          }
          return;
        }

        await _trySeedDevConfig(showToast: false);
        return;
      }

      final has = await _cfg.hasManagedConfig();
      if (has) {
        await _cfg.ensureBaseSeededFromManagedIfMissing();
        final base = await _cfg.readBaseConfig();
        if (base != null && base.trim().isNotEmpty) {
          await _cfg.writeManagedConfig(_buildManagedConfigFromBase(base));
        }
      }

      final boot = await _bootstrapWithDeviceRetry(showToastOnRotate: false);
      if (!boot.ok || boot.data == null) return;

      final did = await _ensureDeviceId();
      if (did == null || did.isEmpty) return;

      final sub = boot.data!['subscription'];
      if (sub is Map) {
        final p = (sub['planName'] ?? sub['planCode'] ?? '').toString().trim();
        if (p.isNotEmpty && mounted) {
          setState(() => planName = p);
        }
      }

      final res = await _api.fetchWireGuardConfig(
        accessToken: widget.session.accessToken,
        deviceId: did,
        serverId: selectedServer.id == 'auto' ? null : selectedServer.id,
      );
      if (res.ok && res.data != null) {
        await _writeProvisionedConfig(_normalizeDevEndpoint(res.data!));
      } else {
        await _reuseExistingProvisionedConfig(
          reason: res.message ?? '',
          showToast: false,
        );
      }
    } catch (_) {}
  }

  Future<bool> _ensureProvisionedConfigInteractive() async {
    if (kIsWeb) return false;
    await appendBlueVpnClientLog(
      'ensure config interactive start token=${widget.session.accessToken == "dev-token" ? "dev" : "real"} server=${selectedServer.id}',
    );

    if (widget.session.accessToken == 'dev-token') {
      final ok = await _trySeedDevConfig(showToast: true);
      await appendBlueVpnClientLog('ensure config interactive dev result=$ok');
      if (ok) return true;
      _toast(
        context,
        'Тестовый локальный режим недоступен. Войди в аккаунт, чтобы получить VPN-конфигурацию с сервера.',
      );
      return false;
    }

    final boot = await _bootstrapWithDeviceRetry(showToastOnRotate: true);
    await appendBlueVpnClientLog(
      'ensure config bootstrap ok=${boot.ok} message=${boot.message ?? ""}',
    );

    if (!boot.ok || boot.data == null) {
      _toast(context, boot.message ?? 'Не удалось пройти bootstrap.');
      return false;
    }

    final did = await _ensureDeviceId();
    await appendBlueVpnClientLog('ensure config deviceId=${did ?? "null"}');
    if (did == null || did.isEmpty) {
      _toast(context, 'Не удалось получить device id.');
      return false;
    }

    final bootMap = boot.data!;
    final sub = bootMap['subscription'];
    if (sub is Map) {
      final p = (sub['planName'] ?? sub['planCode'] ?? '').toString().trim();
      if (p.isNotEmpty && mounted) {
        setState(() => planName = p);
      }
    }

    final res = await _api.fetchWireGuardConfig(
      accessToken: widget.session.accessToken,
      deviceId: did,
      serverId: selectedServer.id == 'auto' ? null : selectedServer.id,
    );
    await appendBlueVpnClientLog(
      'ensure config fetch ok=${res.ok} message=${res.message ?? ""} bytes=${res.data?.length ?? 0}',
    );
    if (!res.ok || res.data == null || res.data!.trim().isEmpty) {
      final reused = await _reuseExistingProvisionedConfig(
        reason: res.message ?? '',
        showToast: true,
      );
      if (reused) return true;
      _toast(context, res.message ?? 'Не удалось получить конфиг с сервера.');
      return false;
    }

    await _writeProvisionedConfig(_normalizeDevEndpoint(res.data!));
    return true;
  }

  Future<void> _toggleVpnReal() async {
    await appendBlueVpnClientLog(
      'toggle requested vpnEnabled=$vpnEnabled busy=$vpnBusy cooldown=$_vpnTapCooldown',
    );
    if (vpnBusy) {
      _toast(
        context,
        vpnEnabled
            ? 'Green VPN уже отключает туннель. Подожди пару секунд.'
            : 'Green VPN уже запускает туннель. Подожди пару секунд.',
      );
      return;
    }
    if (_vpnTapCooldown) {
      _toast(
        context,
        vpnEnabled
            ? 'VPN только что переключился. Дай ему секунду спокойно зафиксироваться.'
            : 'Green VPN уже начал переключение. Повторно нажимать не нужно.',
      );
      return;
    }
    _setVpnBusyUi(
      stage: vpnEnabled ? 'Отключаем...' : 'Готовим подключение...',
      hint: vpnEnabled
          ? 'Снимаем сервис WireGuard и очищаем маршруты.'
          : 'Проверяем доступ и готовим рабочий конфиг. Повторно нажимать не нужно.',
    );

    if (kIsWeb) {
      _toast(
        context,
        'Web-режим: реальный VPN недоступен. Запусти приложение как Windows.',
      );
      _clearVpnBusyUi();
      return;
    }

    _setVpnBusyUi(
      stage: 'Проверяем системный компонент...',
      hint:
          'Green VPN использует права, выданные один раз при установке. Дополнительный UAC при запуске не нужен.',
    );
    final elevated = await isWindowsProcessElevated();
    await appendBlueVpnClientLog(
      'toggle elevated=$elevated vpnEnabled=$vpnEnabled',
    );

    try {
      if (!vpnEnabled) {
        await appendBlueVpnClientLog('toggle connect branch start');
        _setVpnBusyUi(
          stage: 'Получаем конфиг...',
          hint:
              'Регистрируем устройство на сервере и забираем конфиг именно для этого ПК.',
        );
        final ok = await _ensureProvisionedConfigInteractive();
        await appendBlueVpnClientLog('toggle connect ensureConfig=$ok');
        if (!ok) return;

        _setVpnBusyUi(
          stage: socialOnlyEnabled
              ? 'Подключаем Social Only...'
              : 'Запускаем VPN...',
          hint: socialOnlyEnabled
              ? 'Поднимаем туннель WireGuard в режиме только для выбранных приложений.'
              : 'Поднимаем туннель WireGuard и ждём честный handshake.',
        );
        final configPath = _cfg.managedConfigPath;
        await appendBlueVpnClientLog(
          'toggle connect backend start cfg=$configPath',
        );
        final res = await _vpnBackend.connect(configPath: configPath);
        await appendBlueVpnClientLog(
          'toggle connect backend ok=${res.ok} message=${res.message ?? ""}',
        );
        if (!res.ok) {
          _toast(context, res.message ?? 'Не удалось подключить VPN.');
          await _syncVpnStatus();
          return;
        }

        _setVpnBusyUi(
          stage: 'Проверяем статус...',
          hint: 'Сверяем handshake, трафик и реальное состояние туннеля.',
        );
        await _syncVpnStatus();
        await appendBlueVpnClientLog(
          'toggle connect sync done vpnEnabled=$vpnEnabled',
        );
        _startVpnTapCooldown(
          hint:
              'VPN только что включился. Кнопка разблокируется через секунду, чтобы избежать случайного двойного нажатия.',
        );
        _toast(context, 'VPN включён.');
      } else {
        await appendBlueVpnClientLog('toggle disconnect branch start');
        _setVpnBusyUi(
          stage: 'Отключаем VPN...',
          hint: 'Останавливаем сервис и аккуратно снимаем туннель.',
        );
        final res = await _vpnBackend.disconnect();
        await appendBlueVpnClientLog(
          'toggle disconnect backend ok=${res.ok} message=${res.message ?? ""}',
        );
        if (!res.ok) {
          _toast(context, res.message ?? 'Не удалось отключить VPN.');
          await _syncVpnStatus();
          final onNow = await _vpnBackend.isConnected();
          if (mounted) setState(() => vpnEnabled = onNow);

          return;
        }

        _setVpnBusyUi(
          stage: 'Проверяем статус...',
          hint: 'Убеждаемся, что интерфейс и маршруты действительно сняты.',
        );
        await _syncVpnStatus();
        await appendBlueVpnClientLog(
          'toggle disconnect sync done vpnEnabled=$vpnEnabled',
        );
        _startVpnTapCooldown(
          hint:
              'VPN только что выключился. Кнопка разблокируется через секунду, чтобы состояние успело обновиться.',
        );
        _toast(context, 'VPN выключен.');
      }
    } catch (e, st) {
      await appendBlueVpnClientLog('toggle exception=$e stack=$st');
      if (mounted) {
        _toast(context, 'Ошибка VPN: $e');
      }
      await _syncVpnStatus();
    } finally {
      _clearVpnBusyUi();
    }
  }

  Future<void> _refreshServerCatalog({required bool showToast}) async {
    if (_serverCatalogBusy) return;
    if (mounted) {
      setState(() {
        _serverCatalogBusy = true;
        if (showToast) _serverCatalogStatus = 'Обновляем список серверов...';
      });
    }
    try {
      final res = await _api.fetchServerCatalog();
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        setState(() {
          _serverCatalogStatus =
              res.message ?? 'Не удалось загрузить список серверов.';
        });
        if (showToast) _toast(context, _serverCatalogStatus!);
        return;
      }

      final rawServers = res.data!['servers'];
      final nextServers = <ServerLocation>[
        const ServerLocation(
          id: 'auto',
          title: 'Авто',
          subtitle: 'Самый здоровый endpoint из каталога',
          pingMs: null,
          isAuto: true,
          status: 'healthy',
          available: true,
        ),
      ];

      if (rawServers is List) {
        for (final item in rawServers) {
          if (item is! Map) continue;
          final parsed = ServerLocation.fromCatalogJson(
            Map<String, dynamic>.from(item),
          );
          if (parsed.id.trim().isEmpty) continue;
          nextServers.add(parsed);
        }
      }

      if (nextServers.length == 1) {
        nextServers.addAll(servers.where((s) => !s.isAuto));
      }

      final stillSelected = nextServers.any((s) => s.id == selectedServer.id);
      setState(() {
        servers = nextServers;
        if (!stillSelected) {
          selectedServer = nextServers.first;
        } else {
          selectedServer = nextServers.firstWhere(
            (s) => s.id == selectedServer.id,
            orElse: () => nextServers.first,
          );
        }
        _serverCatalogStatus =
            'Каталог серверов обновлён: ${nextServers.length - 1} endpoint.';
      });
      if (showToast) _toast(context, _serverCatalogStatus!);
    } finally {
      if (mounted) setState(() => _serverCatalogBusy = false);
    }
  }

  Future<void> _openServerPicker(BuildContext context) async {
    await _refreshServerCatalog(showToast: false);
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
                      : [
                          s.subtitle,
                          if (s.protocolLabel.isNotEmpty) s.protocolLabel,
                          if (s.pingMs != null) '${s.pingMs} ms',
                          if (s.healthScore != null) 'health ${s.healthScore}%',
                        ].where((e) => e.isNotEmpty).join(' • ');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      s.isAuto
                          ? Icons.auto_awesome_rounded
                          : (s.available
                                ? Icons.public_rounded
                                : Icons.warning_amber_rounded),
                      color: s.available ? kBrandPrimary : kBrandWarm,
                    ),
                    title: Text(
                      s.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(subtitle),
                    enabled: s.isAuto || s.available,
                    trailing: selected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: kBrandPrimary,
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: (s.isAuto || s.available)
                        ? () => Navigator.of(ctx).pop(s)
                        : null,
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
                        secondary: Icon(app.icon, color: kBrandPrimary),
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
    _tariffDebounce?.cancel();
    _vpnTapCooldownTimer?.cancel();
    _pendingBillingPollTimer?.cancel();
    super.dispose();
  }

  void _setVpnBusyUi({required String stage, required String hint}) {
    if (!mounted) return;
    setState(() {
      vpnBusy = true;
      _vpnBusyStage = stage;
      _vpnBusyHint = hint;
    });
  }

  void _clearVpnBusyUi() {
    if (!mounted) return;
    setState(() {
      vpnBusy = false;
      _vpnBusyStage = null;
      if (!_vpnTapCooldown) {
        _vpnBusyHint = null;
      }
    });
  }

  void _startVpnTapCooldown({
    Duration duration = const Duration(seconds: 2),
    required String hint,
  }) {
    _vpnTapCooldownTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _vpnTapCooldown = true;
      _vpnBusyHint = hint;
    });
    _vpnTapCooldownTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _vpnTapCooldown = false;
        if (!vpnBusy) {
          _vpnBusyHint = null;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final wireGuardState = _wireGuardState;
    final pages = <Widget>[
      VpnPage(
        planName: planName,
        vpnEnabled: vpnEnabled,
        vpnBusy: vpnBusy,
        vpnInteractionLocked: _vpnInteractionLocked,
        vpnBusyStage: _vpnBusyStage,
        vpnBusyHint: _vpnBusyHint,
        wireGuardInstalled: wireGuardState?.installed ?? true,
        wireGuardStatusText: wireGuardState?.subtitle,
        wireGuardBusy: _wireGuardBusy,
        onInstallWireGuard: _installWireGuard,
        onRefreshWireGuard: _refreshWireGuardState,
        onToggleVpn: () {
          if (wireGuardState != null && !wireGuardState.installed) {
            _toast(
              context,
              'Сначала установи WireGuard. После этого кнопка VPN заработает.',
            );
            return;
          }
          unawaited(_toggleVpnReal());
        },

        // Сервер
        selectedServer: selectedServer,
        onOpenServerPicker: () => _openServerPicker(context),

        // Соцсети
        socialOnlyEnabled: socialOnlyEnabled,
        socialOnlyAllowed: optSmartRouting,
        socialOnlyApps: socialOnlyApps,
        onToggleSocialOnly: (v) async {
          if (_vpnInteractionLocked) return;

          setState(() {
            vpnBusy = true;
            _vpnBusyStage = 'Обновляем режим...';
            _vpnBusyHint =
                'Пересобираем конфиг и аккуратно применяем новый режим трафика.';
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
              setState(() {
                vpnBusy = false;
                _vpnBusyStage = null;
                if (!_vpnTapCooldown) {
                  _vpnBusyHint = null;
                }
              });
            }
          }
        },
        onConfigureSocialApps: () async {
          if (_vpnInteractionLocked) return;
          await _openSocialAppsPicker(context);
        },

        onOpenTariff: () => goToTab(1),
      ),

      TariffPage(
        planName: planName,
        selectedApps: selectedApps,
        trafficPack: trafficPack,
        trafficGb: trafficGb,
        devices: devices,
        optNoAds: optNoAds,
        optSmartRouting: optSmartRouting,
        optDedicatedIp: optDedicatedIp,
        optAutoRenew: optAutoRenew,
        tariffCatalog: _tariffCatalog,
        tariffQuote: _tariffQuote,
        tariffStatus: _tariffStatus,
        pendingBillingOrder: _pendingBillingOrder,
        subscriptionActive: _subscriptionActive,
        subscriptionAutoRenew: _subscriptionAutoRenew,
        paymentMethodSaved: _paymentMethodSaved,
        subscriptionExpiresAt: _subscriptionExpiresAt,
        subscriptionMonthlyPriceRub: _subscriptionMonthlyPriceRub,
        tariffBusy: _tariffBusy,
        onApplyTariff: _createTariffOrderOnServer,
        onCheckPendingBillingOrder: () =>
            _checkPendingBillingOrder(showToast: true),
        onCancelAutoRenew: _cancelAutoRenew,
        onOpenPaymentUrl: _openPaymentUrl,
        onToggleApp: (app) {
          setState(() {
            if (selectedApps.contains(app)) {
              selectedApps.remove(app);
            } else {
              selectedApps.add(app);
            }
          });
          _schedulePrefsSave();
          _scheduleTariffRefresh();
        },
        onTrafficChanged: (p) {
          setState(() => trafficPack = p);
          _schedulePrefsSave();
          _scheduleTariffRefresh();
        },
        onTrafficGbChanged: (gb) {
          setState(() => trafficGb = gb);
          _schedulePrefsSave();
          _scheduleTariffRefresh();
        },
        onDevicesChanged: (v) {
          setState(() => devices = v.clamp(1, 5));
          _schedulePrefsSave();
          _scheduleTariffRefresh();
        },
        onOptNoAds: (v) {
          setState(() => optNoAds = true);
          _schedulePrefsSave();
        },
        onOptSmartRouting: (v) {
          setState(() {
            optSmartRouting = true;
          });
          _schedulePrefsSave();
        },
        onOptDedicatedIp: (v) {
          setState(() => optDedicatedIp = v);
          _schedulePrefsSave();
          _scheduleTariffRefresh();
        },
        onOptAutoRenew: (v) {
          setState(() => optAutoRenew = v);
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
          items: const ['Русский'],
          onSelect: (v) => _setLanguage(v),
        ),
        email: widget.session.email,
        emailVerified: _emailVerified,
        emailConfirmationRequired: _emailConfirmationRequired,
        emailStatusBusy: _emailStatusBusy,
        emailStatusMessage: _emailStatusMessage,
        onResendEmailConfirmation: _resendEmailConfirmation,
        onRefreshEmailStatus: () => _refreshEmailStatus(showToast: true),
        phone: _phone,
        phoneVerified: _phoneVerified,
        phoneStatusBusy: _phoneStatusBusy,
        phoneStatusMessage: _phoneStatusMessage,
        onRefreshPhoneStatus: () => _refreshPhoneStatus(showToast: true),
        onBindPhone: _showPhoneBindingDialog,
        onLogout: widget.onLogout,
        onOpenUpdates: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const UpdatesPage()));
        },
        onOpenDiagnostics: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DiagnosticsPage(
                accessToken: widget.session.accessToken,
                email: widget.session.email,
              ),
            ),
          );
        },
      ),
    ];

    return Scaffold(
      body: _DesktopShellBody(child: pages[_index]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _index = i),
        selectedItemColor: kBrandPrimary,
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
                      border: Border.all(color: const Color(0x1A08785D)),
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? kBrandText
                          : const Color(0xFFF8FBF8),
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
                              ? kBrandPrimary
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
  final bool vpnBusy;
  final bool vpnInteractionLocked;
  final String? vpnBusyStage;
  final String? vpnBusyHint;
  final bool wireGuardInstalled;
  final String? wireGuardStatusText;
  final bool wireGuardBusy;
  final Future<void> Function() onInstallWireGuard;
  final Future<void> Function() onRefreshWireGuard;
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
    required this.vpnBusy,
    required this.vpnInteractionLocked,
    required this.vpnBusyStage,
    required this.vpnBusyHint,
    required this.wireGuardInstalled,
    required this.wireGuardStatusText,
    required this.wireGuardBusy,
    required this.onInstallWireGuard,
    required this.onRefreshWireGuard,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = textColor.withOpacity(isDark ? 0.72 : 0.62);
    final statusText = vpnBusy
        ? (vpnBusyStage ?? (vpnEnabled ? 'Отключаем...' : 'Подключаем...'))
        : (vpnEnabled ? 'Включено' : 'Отключено');
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
        if (!wireGuardInstalled) ...[
          _WireGuardSetupCard(
            title: 'Установи WireGuard перед первым подключением',
            subtitle:
                wireGuardStatusText ??
                'Green VPN не сможет включать туннель, пока WireGuard не установлен.',
            busy: wireGuardBusy,
            onInstall: onInstallWireGuard,
            onRefresh: onRefreshWireGuard,
          ),
          const SizedBox(height: 12),
        ],
        _Card(
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: wireGuardInstalled && !vpnInteractionLocked
                      ? onToggleVpn
                      : null,
                  icon: vpnBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          vpnEnabled
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                  label: Text(
                    vpnBusy
                        ? (vpnEnabled
                              ? 'Отключаем VPN...'
                              : 'Подключаем VPN...')
                        : (vpnEnabled ? 'Отключить VPN' : 'Подключить VPN'),
                  ),
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
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              if (vpnBusy) ...[
                const SizedBox(height: 8),
                Text(
                  vpnBusyHint ??
                      'Подожди пару секунд. Мы уже запускаем туннель и специально блокируем повторные нажатия.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
              if (!vpnBusy && vpnBusyHint != null) ...[
                const SizedBox(height: 8),
                Text(
                  vpnBusyHint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mutedColor,
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
                    ? 'Функция активна. Выбранные приложения пойдут через VPN, остальной трафик останется обычным.'
                    : 'Функция временно недоступна для текущего режима.',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          tint: isDark ? kBrandDarkSurface : kBrandPrimarySoft,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: onOpenServerPicker,
            leading: const Icon(Icons.bolt_rounded, color: kBrandPrimary),
            title: Text(
              'Сервер',
              style: TextStyle(color: mutedColor, fontSize: 12),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    serverTitle,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    serverSub,
                    style: TextStyle(
                      color: mutedColor,
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

class _WireGuardSetupCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool busy;
  final Future<void> Function() onInstall;
  final Future<void> Function() onRefresh;

  const _WireGuardSetupCard({
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onInstall,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      tint: const Color(0xFFFFFBEB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.download_rounded, color: Color(0xFFD97706)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Подготовка Windows',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: kBrandText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: kBrandMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : () => onInstall(),
                  icon: const Icon(Icons.download_for_offline_rounded),
                  label: Text(
                    busy ? 'Установка…' : 'Установить WireGuard',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: busy ? null : () => onRefresh(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Проверить снова',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
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
          color: kBrandPrimaryDeep,
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
            Icon(Icons.star_rounded, color: kBrandWarm),
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
                      color: kBrandPrimarySoft,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: kBrandPrimarySoft),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
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
  gb5('5 ГБ', 79),
  gb20('20 ГБ', 149),
  gb50('50 ГБ', 229),
  gb100('100 ГБ', 329),
  unlimited('Безлимит', 549);

  const TrafficPack(this.title, this.basePriceRub);
  final String title;
  final int basePriceRub;
}

class TariffPage extends StatelessWidget {
  final String planName;
  final Set<TariffApp> selectedApps;
  final TrafficPack trafficPack;
  final double trafficGb;
  final int devices;

  final bool optNoAds;
  final bool optSmartRouting;
  final bool optDedicatedIp;
  final bool optAutoRenew;
  final Map<String, dynamic>? tariffCatalog;
  final Map<String, dynamic>? tariffQuote;
  final String? tariffStatus;
  final Map<String, dynamic>? pendingBillingOrder;
  final bool subscriptionActive;
  final bool subscriptionAutoRenew;
  final bool paymentMethodSaved;
  final String? subscriptionExpiresAt;
  final int? subscriptionMonthlyPriceRub;
  final bool tariffBusy;

  final void Function(TariffApp) onToggleApp;
  final void Function(TrafficPack) onTrafficChanged;
  final ValueChanged<double> onTrafficGbChanged;
  final void Function(int) onDevicesChanged;

  final void Function(bool) onOptNoAds;
  final void Function(bool) onOptSmartRouting;
  final void Function(bool) onOptDedicatedIp;
  final void Function(bool) onOptAutoRenew;
  final Future<void> Function() onApplyTariff;
  final Future<void> Function() onCheckPendingBillingOrder;
  final Future<void> Function() onCancelAutoRenew;
  final void Function(String url) onOpenPaymentUrl;

  const TariffPage({
    super.key,
    required this.planName,
    required this.selectedApps,
    required this.trafficPack,
    required this.trafficGb,
    required this.devices,
    required this.optNoAds,
    required this.optSmartRouting,
    required this.optDedicatedIp,
    required this.optAutoRenew,
    required this.tariffCatalog,
    required this.tariffQuote,
    required this.tariffStatus,
    required this.pendingBillingOrder,
    required this.subscriptionActive,
    required this.subscriptionAutoRenew,
    required this.paymentMethodSaved,
    required this.subscriptionExpiresAt,
    required this.subscriptionMonthlyPriceRub,
    required this.tariffBusy,
    required this.onToggleApp,
    required this.onTrafficChanged,
    required this.onTrafficGbChanged,
    required this.onDevicesChanged,
    required this.onOptNoAds,
    required this.onOptSmartRouting,
    required this.onOptDedicatedIp,
    required this.onOptAutoRenew,
    required this.onApplyTariff,
    required this.onCheckPendingBillingOrder,
    required this.onCancelAutoRenew,
    required this.onOpenPaymentUrl,
  });

  int _basePriceForGb(double gb) {
    final g = gb.clamp(1.0, 500.0);

    const points = <_GbPricePoint>[
      _GbPricePoint(1, 59),
      _GbPricePoint(5, 79),
      _GbPricePoint(20, 149),
      _GbPricePoint(50, 229),
      _GbPricePoint(100, 329),
      _GbPricePoint(200, 429),
      _GbPricePoint(500, 599),
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

  int _appsPriceRub() {
    if (trafficPack == TrafficPack.unlimited) return 0;
    switch (selectedApps.length) {
      case 0:
        return 0;
      case 1:
        return 15;
      case 2:
        return 25;
      case 3:
        return 35;
      case 4:
        return 45;
      case 5:
        return 55;
      default:
        return 65;
    }
  }

  int _devicesPriceRub() {
    return max(0, devices - 1) * 39;
  }

  int _extrasPriceRub() {
    return optDedicatedIp ? 149 : 0;
  }

  int _calcPriceRub() {
    final isUnlimited = trafficPack == TrafficPack.unlimited;

    final base = isUnlimited
        ? trafficPack.basePriceRub
        : _basePriceForGb(trafficGb);

    final apps = _appsPriceRub();
    final dev = _devicesPriceRub();
    final extras = _extrasPriceRub();

    final total = base + apps + dev + extras;
    return total < 0 ? 0 : total;
  }

  bool get _hasPaidPlan {
    final code = planName.trim().toLowerCase();
    if (!subscriptionActive) return false;
    return code.isNotEmpty &&
        code != 'base' &&
        code != 'trial' &&
        code != 'free';
  }

  bool get _hadPaidPlanBefore {
    final code = planName.trim().toLowerCase();
    return code.isNotEmpty &&
        code != 'base' &&
        code != 'trial' &&
        code != 'free';
  }

  String _primaryCtaText() {
    if (tariffBusy) return 'Обновляем...';
    if (_hasPaidPlan) return 'Обновить тариф';
    if (_hadPaidPlanBefore) return 'Продлить тариф';
    return 'Оплатить тариф';
  }

  String _currentPlanText() {
    if (_hasPaidPlan) {
      final price = subscriptionMonthlyPriceRub;
      final priceText = price == null ? '' : ' • $price ₽/мес';
      final expiresText = subscriptionExpiresAt == null
          ? ''
          : ' • до ${_formatCompactDate(subscriptionExpiresAt!)}';
      return '$planName$priceText$expiresText';
    }
    if (_hadPaidPlanBefore) {
      return '$planName закончился. Можно продлить или выбрать другой набор.';
    }
    return 'Активного платного тарифа пока нет.';
  }

  String _shortOrderId(Object? raw) {
    final id = (raw ?? '').toString().trim();
    if (id.isEmpty) return 'без номера';
    if (id.length <= 16) return id;
    return '${id.substring(0, 16)}…';
  }

  String _formatCompactDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.length > 10 ? raw.substring(0, 10) : raw;
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$day.$month.${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = textColor.withOpacity(isDark ? 0.72 : 0.62);
    final localPrice = _calcPriceRub();
    final appsPrice = _appsPriceRub();
    final devicesPrice = _devicesPriceRub();
    final quote = tariffQuote?['quote'];
    final serverQuote = quote is Map<String, dynamic>
        ? quote
        : (quote is Map ? Map<String, dynamic>.from(quote) : null);
    final serverPrice = serverQuote?['monthlyPriceRub'];
    final serverPlanName = (serverQuote?['planName'] ?? '').toString().trim();
    final price = serverPrice is num ? serverPrice.toInt() : localPrice;

    final appsText = selectedApps.isEmpty
        ? 'Без безлимитных приложений'
        : selectedApps.map((e) => e.title).join(', ');

    final appsDisabled = trafficPack == TrafficPack.unlimited;

    final gbInt = trafficGb.round().clamp(1, 100);
    final baseForGb = appsDisabled
        ? trafficPack.basePriceRub
        : _basePriceForGb(trafficGb);
    final primaryCta = _primaryCtaText();
    final planLine = _currentPlanText();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _PageTitle(
          title: 'Тариф',
          subtitle:
              'Собери подписку из трафика, безлимитных приложений и устройств',
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ChipButton(
                            icon: Icons.storage_rounded,
                            text: '5 ГБ',
                            selected: gbInt == 5,
                            onTap: () => onTrafficGbChanged(5.0),
                          ),
                          _ChipButton(
                            icon: Icons.storage_rounded,
                            text: '20 ГБ',
                            selected: gbInt == 20,
                            onTap: () => onTrafficGbChanged(20.0),
                          ),
                          _ChipButton(
                            icon: Icons.storage_rounded,
                            text: '50 ГБ',
                            selected: gbInt == 50,
                            onTap: () => onTrafficGbChanged(50.0),
                          ),
                          _ChipButton(
                            icon: Icons.storage_rounded,
                            text: '100 ГБ',
                            selected: gbInt == 100,
                            onTap: () => onTrafficGbChanged(100.0),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        decoration: BoxDecoration(
                          color: kBrandPrimarySoft.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: kBrandPrimary.withOpacity(0.14),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.tune_rounded,
                                  color: kBrandPrimary,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Точный объём',
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$gbInt ГБ',
                                  style: const TextStyle(
                                    color: kBrandPrimaryDeep,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: gbInt.clamp(1, 100).toDouble(),
                              min: 1,
                              max: 100,
                              divisions: 99,
                              label: '$gbInt ГБ',
                              onChanged: (value) =>
                                  onTrafficGbChanged(value.roundToDouble()),
                            ),
                          ],
                        ),
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
                style: TextStyle(
                  color: mutedColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              if (appsDisabled) ...[
                const SizedBox(height: 10),
                Text(
                  'Выбран "Безлимит" — безлимитные приложения не нужны (и отключены).',
                  style: TextStyle(
                    color: mutedColor,
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
              const _SectionTitle('Безлимитные приложения'),
              const SizedBox(height: 10),
              Text(
                appsDisabled
                    ? 'При полном безлимите приложения уже не тарифицируются отдельно.'
                    : 'Можно докупить только нужные сервисы, не переплачивая за весь безлимит.',
                style: TextStyle(
                  color: mutedColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
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
              const SizedBox(height: 12),
              Text(
                appsDisabled
                    ? 'Всё уже включено в безлимит.'
                    : 'Сейчас: $appsText${appsPrice > 0 ? ' • +$appsPrice ₽/мес' : ''}',
                style: TextStyle(
                  color: mutedColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
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
                      color: kBrandPrimarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$devices',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: kBrandPrimaryDeep,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => onDevicesChanged(devices + 1),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      devices == 1
                          ? 'Одно устройство уже входит в тариф'
                          : 'Дополнительные устройства: +$devicesPrice ₽/мес',
                      style: TextStyle(
                        color: mutedColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),
              _SwitchRow(
                title: 'Выделенный IP',
                subtitle:
                    'Для личных сервисов и стабильных доступов (+149 ₽/мес)',
                value: optDedicatedIp,
                onChanged: onOptDedicatedIp,
              ),
              const Divider(height: 18),
              _SwitchRow(
                title: 'Автопродление',
                subtitle:
                    'После первой оплаты тариф будет продлеваться автоматически, если платёжный провайдер это подтвердит',
                value: optAutoRenew,
                onChanged: onOptAutoRenew,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          tint: isDark ? kBrandDarkSurface : kBrandPrimarySoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Сейчас',
                style: TextStyle(
                  color: mutedColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                planLine,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'К оплате',
                style: TextStyle(
                  color: mutedColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$price ₽',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: kBrandPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      appsDisabled
                          ? 'безлимитный тариф'
                          : '$gbInt ГБ + выбранные опции',
                      style: TextStyle(
                        color: mutedColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (serverPlanName.isNotEmpty && serverPlanName != planName) ...[
                const SizedBox(height: 6),
                Text(
                  'Будет подключён: $serverPlanName',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _IncludedBadge(
                    icon: Icons.block_rounded,
                    text: 'Без рекламы',
                  ),
                  _IncludedBadge(
                    icon: Icons.alt_route_rounded,
                    text: 'Social Only',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                optAutoRenew
                    ? 'Цена пересчитывается автоматически. После оплаты тариф активируется сервером, а автопродление включится только после подтверждения платёжного провайдера.'
                    : 'Цена пересчитывается автоматически. После оплаты тариф активируется сервером без автопродления.',
                style: TextStyle(
                  color: mutedColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              if (_hasPaidPlan && subscriptionAutoRenew) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? kBrandDarkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: kBrandPrimary.withOpacity(isDark ? 0.28 : 0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.autorenew_rounded,
                            color: kBrandPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Автопродление включено',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        paymentMethodSaved
                            ? 'Способ оплаты сохранён у платёжного провайдера. Можно отключить автопродление, текущий период останется активным.'
                            : 'Автопродление отмечено в подписке. Сохранение способа оплаты подтвердит платёжный провайдер после production-подключения.',
                        style: TextStyle(
                          color: mutedColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: tariffBusy ? null : onCancelAutoRenew,
                          icon: const Icon(Icons.pause_circle_outline_rounded),
                          label: const Text('Отключить автопродление'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (pendingBillingOrder != null) ...[
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final paymentUrl =
                        (pendingBillingOrder!['paymentUrl'] ?? '')
                            .toString()
                            .trim();
                    final hasPaymentUrl = paymentUrl.isNotEmpty;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? kBrandDarkSurface
                            : const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: theme.colorScheme.onSurface.withOpacity(
                            isDark ? 0.16 : 0.10,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ожидает оплаты',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Заказ ${_shortOrderId(pendingBillingOrder!['orderId'])}'
                            ' • ${pendingBillingOrder!['amountRub'] ?? price} ₽'
                            ' • ${pendingBillingOrder!['status'] ?? 'pending'}',
                            style: TextStyle(
                              color: mutedColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'После оплаты можно вернуться в Green VPN. Мы проверяем статус автоматически.',
                            style: TextStyle(
                              color: mutedColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (hasPaymentUrl) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: tariffBusy
                                    ? null
                                    : () => onOpenPaymentUrl(paymentUrl),
                                icon: const Icon(Icons.open_in_browser_rounded),
                                label: const Text('Открыть оплату'),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: tariffBusy
                                  ? null
                                  : () => onCheckPendingBillingOrder(),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Проверить оплату'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              if (price != localPrice) ...[
                const SizedBox(height: 8),
                Text(
                  'Итоговая цена подтверждена сервером: $price ₽/мес.',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
              if (tariffStatus != null && tariffStatus!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  tariffStatus!,
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: tariffBusy ? null : () => onApplyTariff(),
                  icon: tariffBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payment_rounded),
                  label: Text(
                    primaryCta,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
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
  final bool emailVerified;
  final bool emailConfirmationRequired;
  final bool emailStatusBusy;
  final String? emailStatusMessage;
  final Future<void> Function() onResendEmailConfirmation;
  final Future<void> Function() onRefreshEmailStatus;
  final String? phone;
  final bool phoneVerified;
  final bool phoneStatusBusy;
  final String? phoneStatusMessage;
  final Future<void> Function() onRefreshPhoneStatus;
  final Future<void> Function() onBindPhone;
  final Future<void> Function() onLogout;
  final VoidCallback onOpenUpdates;
  final VoidCallback onOpenDiagnostics;

  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onPickLanguage,
    required this.email,
    required this.emailVerified,
    required this.emailConfirmationRequired,
    required this.emailStatusBusy,
    required this.emailStatusMessage,
    required this.onResendEmailConfirmation,
    required this.onRefreshEmailStatus,
    required this.phone,
    required this.phoneVerified,
    required this.phoneStatusBusy,
    required this.phoneStatusMessage,
    required this.onRefreshPhoneStatus,
    required this.onBindPhone,
    required this.onLogout,
    required this.onOpenUpdates,
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
                  subtitle: email.isEmpty ? 'Не указана' : email,
                  icon: Icons.alternate_email_rounded,
                  onTap: () {
                    unawaited(onRefreshEmailStatus());
                  },
                ),
                const Divider(height: 18),
                _SettingsNavRow(
                  title: 'Телефон',
                  subtitle: phone?.isNotEmpty == true ? phone! : 'Не добавлен',
                  icon: Icons.phone_iphone_rounded,
                  onTap: () {
                    unawaited(onRefreshPhoneStatus());
                    unawaited(onBindPhone());
                  },
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
                  title: 'Обновления',
                  subtitle: 'Проверить свежую версию Green VPN',
                  icon: Icons.system_update_alt_rounded,
                  onTap: onOpenUpdates,
                ),
                const Divider(height: 18),
                _SettingsActionRow(
                  title: 'Поддержка',
                  subtitle: 'Отправить закодированный отчёт в поддержку',
                  icon: Icons.health_and_safety_rounded,
                  onTap: onOpenDiagnostics,
                ),
                const Divider(height: 18),
                _SettingsActionRow(
                  title: 'О Green VPN',
                  subtitle: 'Версия $kAppVersion, Windows MVP',
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
          title: const Text(kProductName),
          content: const Text(
            'Green VPN для Windows.\n\n'
            'Версия: $kAppVersion\n'
            'Системный компонент управляет VPN-действиями, а приложение остаётся обычным пользовательским интерфейсом.\n\n'
            'Если что-то не работает, раздел “Поддержка” отправит закодированный отчёт без паролей, токенов и приватных ключей.',
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

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  final _api = const BlueVpnApi(baseUrl: kApiBaseUrl);
  final _deviceStore = DeviceIdStore();

  bool _loading = true;
  GreenVpnUpdateManifest? _manifest;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    String? clientId;
    try {
      clientId = await _deviceStore.getOrCreate();
    } catch (_) {
      clientId = null;
    }

    final res = await _api.fetchWindowsUpdateManifest(
      currentVersion: kAppVersion,
      clientId: clientId,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok && res.data != null) {
        _manifest = res.data;
      } else {
        _error = res.message ?? 'Не удалось проверить обновления.';
      }
    });
  }

  Future<void> _openDownload() async {
    final url = _manifest?.downloadUrl.trim() ?? '';
    if (url.isEmpty) return;
    await openExternalUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _manifest;
    final hasUpdate = manifest?.hasUpdate ?? false;
    final heldByRollout = manifest?.heldByRollout ?? false;
    final requiredUpdate = manifest?.required ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Обновления'),
        actions: [
          IconButton(
            tooltip: 'Проверить',
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
                _PageTitle(
                  title: hasUpdate
                      ? (requiredUpdate
                            ? 'Требуется обновление'
                            : 'Есть новая версия')
                      : 'Версия актуальна',
                  subtitle: hasUpdate
                      ? 'Скачай свежий установщик Green VPN и поставь его поверх текущей версии.'
                      : heldByRollout
                      ? 'Сервер обновлений работает. Новая версия будет предложена, когда дойдёт очередь этого устройства.'
                      : 'Green VPN проверил сервер обновлений.',
                  icon: hasUpdate
                      ? Icons.system_update_alt_rounded
                      : Icons.verified_rounded,
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  _Card(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: kBrandDanger,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else if (manifest != null) ...[
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SupportStatusLine(
                          title: 'Текущая версия',
                          ok: true,
                          value: kAppVersion,
                        ),
                        const SizedBox(height: 10),
                        _SupportStatusLine(
                          title: 'Версия на сервере',
                          ok: !hasUpdate,
                          value: manifest.latestVersion.isEmpty
                              ? 'не задана'
                              : manifest.latestVersion,
                        ),
                        if (manifest.sha256.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _SupportStatusLine(
                            title: 'Проверка файла',
                            ok: true,
                            value: 'SHA256 получен',
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (manifest.changelog.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Что изменилось',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          for (final item in manifest.changelog)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '• ',
                                    style: TextStyle(
                                      color: kBrandPrimary,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (hasUpdate) ...[
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            requiredUpdate
                                ? 'Это критическое обновление.'
                                : 'Обновление можно установить сейчас.',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            manifest.canDownload
                                ? 'После скачивания Windows попросит подтвердить установку.'
                                : 'Ссылка на скачивание пока не настроена на сервере.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.62),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kBrandPrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: manifest.canDownload
                                ? _openDownload
                                : null,
                            child: const Text('Скачать обновление'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
    );
  }
}

class BackendAdminPage extends StatefulWidget {
  final Session session;

  const BackendAdminPage({super.key, required this.session});

  @override
  State<BackendAdminPage> createState() => _BackendAdminPageState();
}

class _BackendAdminPageState extends State<BackendAdminPage> {
  final _api = const BlueVpnApi(baseUrl: kApiBaseUrl);
  final _store = AdminTokenStore();
  final _tokenCtl = TextEditingController();

  bool _busy = false;
  String? _status;
  Map<String, dynamic>? _overview;
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _billingOrders = const [];

  @override
  void initState() {
    super.initState();
    _loadSavedToken();
  }

  @override
  void dispose() {
    _tokenCtl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedToken() async {
    final token = await _store.read();
    if (!mounted) return;
    _tokenCtl.text = token ?? '';
    if (_tokenCtl.text.trim().isNotEmpty) {
      await _refresh();
    } else {
      setState(() {
        _status =
            'Вставь admin token с сервера: /opt/bluevpn/backend/data/admin_token.txt';
      });
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveToken() async {
    final token = _tokenCtl.text.trim();
    if (token.isEmpty) {
      await _store.clear();
      if (!mounted) return;
      setState(() => _status = 'Локальный admin token удалён.');
      return;
    }
    await _store.write(token);
    if (!mounted) return;
    setState(() => _status = 'Admin token сохранён локально.');
  }

  Future<void> _refresh() async {
    final token = _tokenCtl.text.trim();
    if (token.isEmpty) {
      setState(() => _status = 'Сначала вставь admin token.');
      return;
    }

    setState(() => _busy = true);
    try {
      await _store.write(token);

      final overview = await _api.adminOverview(adminToken: token);
      if (!overview.ok || overview.data == null) {
        if (!mounted) return;
        setState(() {
          _status = overview.message ?? 'Не удалось загрузить overview.';
        });
        return;
      }

      final users = await _api.adminUsers(adminToken: token);
      if (!users.ok || users.data == null) {
        if (!mounted) return;
        setState(() {
          _overview = overview.data;
          _status =
              users.message ?? 'Не удалось загрузить список пользователей.';
        });
        return;
      }

      final orders = await _api.adminBillingOrders(adminToken: token);
      if (!orders.ok || orders.data == null) {
        if (!mounted) return;
        setState(() {
          _overview = overview.data;
          _users = users.data!;
          _status = orders.message ?? 'Не удалось загрузить заказы на оплату.';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _overview = overview.data;
        _users = users.data!;
        _billingOrders = orders.data!;
        _status = 'Backend admin синхронизирован.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _subLabel(Map<String, dynamic> user) {
    final sub = user['subscription'];
    if (sub is! Map) return 'подписка неизвестна';
    final map = Map<String, dynamic>.from(sub);
    final plan = (map['planName'] ?? map['planCode'] ?? 'Unknown').toString();
    final maxDevices = (map['maxDevices'] ?? '?').toString();
    final active = map['isActive'] == true ? 'активна' : 'неактивна';
    final monthlyPrice = map['monthlyPriceRub'];
    final selection = map['selection'];
    final parts = <String>['$plan', active];
    final price = _formatRub(monthlyPrice);
    if (price != null) parts.add('$price/мес');
    final selectionText = _selectionShort(selection);
    if (selectionText != null) parts.add(selectionText);
    parts.add('лимит: $maxDevices');
    return parts.join(' • ');
  }

  String? _formatRub(Object? raw) {
    final value = raw is int ? raw : int.tryParse((raw ?? '').toString());
    if (value == null || value <= 0) return null;
    return '$value ₽';
  }

  String? _selectionShort(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final trafficPack = (map['trafficPack'] ?? '').toString().trim();
    final trafficGb = int.tryParse((map['trafficGb'] ?? '').toString()) ?? 0;
    final apps = ((map['unlimitedApps'] as List?) ?? const []).length;
    final dedicatedIp = map['dedicatedIp'] == true;
    final parts = <String>[];
    if (trafficPack == 'unlimited') {
      parts.add('безлимит');
    } else if (trafficGb > 0) {
      parts.add('$trafficGb ГБ');
    }
    if (apps > 0) {
      parts.add('apps: $apps');
    }
    if (dedicatedIp) {
      parts.add('IP');
    }
    if (parts.isEmpty) return null;
    return parts.join(' + ');
  }

  int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse((raw ?? '').toString());
  }

  String? _formatCompactDate(Object? raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    try {
      final dt = DateTime.parse(text).toLocal();
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final year = dt.year.toString();
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$day.$month.$year $hour:$minute';
    } catch (_) {
      return text;
    }
  }

  String _userLabelForOrder(Map<String, dynamic> order) {
    final userId = _asInt(order['userId']);
    if (userId == null) return 'пользователь неизвестен';
    for (final user in _users) {
      if (_asInt(user['id']) == userId) {
        final email = (user['email'] ?? '').toString().trim();
        if (email.isNotEmpty) return email;
      }
    }
    return 'user #$userId';
  }

  String _shortOrderId(Map<String, dynamic> order) {
    final id = (order['orderId'] ?? '').toString().trim();
    if (id.isEmpty) return 'заказ без номера';
    if (id.length <= 16) return id;
    return '${id.substring(0, 16)}…';
  }

  String _orderPlanLabel(Map<String, dynamic> order) {
    final quote = order['quote'];
    if (quote is Map) {
      final map = Map<String, dynamic>.from(quote);
      final plan = (map['planName'] ?? map['planCode'] ?? '').toString().trim();
      if (plan.isNotEmpty) return plan;
    }

    final selection = _selectionShort(order['selection']);
    return selection ?? 'тариф без деталей';
  }

  String _orderAmountLabel(Map<String, dynamic> order) {
    return _formatRub(order['amountRub']) ?? 'сумма неизвестна';
  }

  Future<void> _markOrderPaid(Map<String, dynamic> order) async {
    final token = _tokenCtl.text.trim();
    final orderId = (order['orderId'] ?? '').toString().trim();
    if (token.isEmpty) {
      _toast('Сначала вставь admin token.');
      return;
    }
    if (orderId.isEmpty) {
      _toast('У заказа нет order id.');
      return;
    }

    setState(() => _busy = true);
    try {
      final res = await _api.adminMarkBillingOrderPaid(
        adminToken: token,
        orderId: orderId,
      );
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        setState(() {
          _status = res.message ?? 'Не удалось подтвердить оплату.';
        });
        _toast(_status!);
        return;
      }

      _toast('Оплата подтверждена, тариф активирован.');
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;

    return Scaffold(
      appBar: AppBar(title: const Text('Backend Admin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _PageTitle(
            title: 'Backend Admin',
            subtitle: 'Скрытая панель управления пользователями и устройствами',
            icon: Icons.admin_panel_settings_rounded,
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Admin token'),
                const SizedBox(height: 10),
                TextField(
                  controller: _tokenCtl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Admin token',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _saveToken,
                        child: const Text('Сохранить токен'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _busy ? null : _refresh,
                        child: Text(_busy ? 'Обновление…' : 'Обновить'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _status ??
                      'Токен лежит на сервере: /opt/bluevpn/backend/data/admin_token.txt',
                  style: const TextStyle(
                    color: kBrandMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (overview != null) ...[
            _Card(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AdminMiniStat(
                    title: 'Версия',
                    value: (overview['version'] ?? '-').toString(),
                  ),
                  _AdminMiniStat(
                    title: 'Пользователи',
                    value: (overview['usersCount'] ?? '-').toString(),
                  ),
                  _AdminMiniStat(
                    title: 'Устройства',
                    value: (overview['devicesCount'] ?? '-').toString(),
                  ),
                  _AdminMiniStat(
                    title: 'Активные',
                    value: (overview['enabledDevicesCount'] ?? '-').toString(),
                  ),
                  _AdminMiniStat(
                    title: 'Подписки',
                    value: (overview['activeSubscriptionsCount'] ?? '-')
                        .toString(),
                  ),
                  _AdminMiniStat(
                    title: 'Заказы',
                    value: (overview['pendingBillingOrdersCount'] ?? '-')
                        .toString(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          _Card(
            tint: kBrandPrimarySoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Заказы на оплату'),
                const SizedBox(height: 10),
                if (_billingOrders.isEmpty)
                  const Text(
                    'Новых заказов нет.',
                    style: TextStyle(
                      color: kBrandMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  ..._billingOrders.map((order) {
                    final status = (order['status'] ?? '-').toString();
                    final created = _formatCompactDate(order['createdAt']);
                    final canConfirm = status == 'pending';
                    return Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.receipt_long_rounded,
                            color: kBrandPrimary,
                          ),
                          title: Text(
                            '${_orderAmountLabel(order)} • ${_orderPlanLabel(order)}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            [
                              _userLabelForOrder(order),
                              'заказ: ${_shortOrderId(order)}',
                              'статус: $status',
                              if (created != null) 'создан: $created',
                            ].join('\n'),
                          ),
                          isThreeLine: true,
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _busy || !canConfirm
                                ? null
                                : () => _markOrderPaid(order),
                            icon: const Icon(Icons.verified_rounded),
                            label: Text(
                              canConfirm ? 'Оплата получена' : 'Уже обработан',
                            ),
                          ),
                        ),
                        if (order != _billingOrders.last)
                          const Divider(height: 18),
                      ],
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Пользователи'),
                const SizedBox(height: 10),
                if (_users.isEmpty)
                  const Text(
                    'Список пока пуст или ещё не загружен.',
                    style: TextStyle(
                      color: kBrandMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  ..._users.map((user) {
                    final email = (user['email'] ?? '-').toString();
                    final deviceCount = (user['deviceCount'] ?? 0).toString();
                    final enabledDeviceCount = (user['enabledDeviceCount'] ?? 0)
                        .toString();
                    final lastSeen = _formatCompactDate(user['lastSeenAt']);
                    return Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.person_rounded,
                            color: kBrandPrimary,
                          ),
                          title: Text(
                            email,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '${_subLabel(user)} • устройств: $enabledDeviceCount/$deviceCount'
                            '${lastSeen == null ? '' : '\nБыл в сети: $lastSeen'}',
                          ),
                          isThreeLine: lastSeen != null,
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            final token = _tokenCtl.text.trim();
                            if (token.isEmpty) {
                              _toast('Сначала вставь admin token.');
                              return;
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BackendAdminUserPage(
                                  api: _api,
                                  adminToken: token,
                                  user: user,
                                ),
                              ),
                            );
                          },
                        ),
                        if (user != _users.last) const Divider(height: 14),
                      ],
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BackendAdminUserPage extends StatefulWidget {
  final BlueVpnApi api;
  final String adminToken;
  final Map<String, dynamic> user;

  const BackendAdminUserPage({
    super.key,
    required this.api,
    required this.adminToken,
    required this.user,
  });

  @override
  State<BackendAdminUserPage> createState() => _BackendAdminUserPageState();
}

class _BackendAdminUserPageState extends State<BackendAdminUserPage> {
  bool _busy = false;
  String? _status;
  List<Map<String, dynamic>> _devices = const [];
  late String _planCode;
  late String _planName;
  late int _maxDevices;
  late bool _isActive;
  Map<String, dynamic>? _catalog;
  Map<String, dynamic>? _quote;
  late String _trafficPackCode;
  late int _trafficGb;
  late bool _dedicatedIp;
  final Set<String> _unlimitedAppCodes = <String>{};
  int? _monthlyPriceRub;
  String? _expiresAt;

  @override
  void initState() {
    super.initState();
    final sub = widget.user['subscription'];
    final subMap = sub is Map<String, dynamic>
        ? sub
        : (sub is Map ? Map<String, dynamic>.from(sub) : <String, dynamic>{});
    _planCode = (subMap['planCode'] ?? 'trial').toString();
    _planName = (subMap['planName'] ?? 'Trial').toString();
    _maxDevices = (subMap['maxDevices'] is int)
        ? subMap['maxDevices'] as int
        : int.tryParse((subMap['maxDevices'] ?? '1').toString()) ?? 1;
    _isActive = subMap['isActive'] == true;
    _monthlyPriceRub = _asInt(subMap['monthlyPriceRub']);
    _expiresAt = (subMap['expiresAt'] ?? '').toString().trim();
    _applySelectionFromServer(subMap['selection']);
    _loadDevices();
    unawaited(_loadTariffCatalog());
    unawaited(_refreshQuote());
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  int get _userId {
    final raw = widget.user['id'];
    if (raw is int) return raw;
    return int.tryParse(raw.toString()) ?? 0;
  }

  int? _asInt(Object? raw) {
    if (raw is int) return raw;
    return int.tryParse((raw ?? '').toString());
  }

  void _applySelectionFromServer(Object? raw) {
    final map = raw is Map<String, dynamic>
        ? raw
        : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
    final trafficPack = (map['trafficPack'] ?? '').toString().trim();
    final trafficGb = _asInt(map['trafficGb']);
    final devices = _asInt(map['devices']);

    _trafficPackCode = trafficPack.isEmpty ? 'gb20' : trafficPack;
    _trafficGb = trafficGb == null || trafficGb <= 0 ? 20 : trafficGb;
    _dedicatedIp = map['dedicatedIp'] == true;
    if (devices != null && devices > 0) {
      _maxDevices = devices;
    }

    _unlimitedAppCodes
      ..clear()
      ..addAll(
        (((map['unlimitedApps'] as List?) ?? const []).map(
          (item) => item.toString().trim().toLowerCase(),
        )).where((item) => item.isNotEmpty),
      );
  }

  String? _formatRub(Object? raw) {
    final value = _asInt(raw);
    if (value == null || value <= 0) return null;
    return '$value ?';
  }

  String _formatDate(Object? raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return 'не задан';
    try {
      final dt = DateTime.parse(text).toLocal();
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final year = dt.year.toString();
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$day.$month.$year $hour:$minute';
    } catch (_) {
      return text;
    }
  }

  String _formatTariffSummary() {
    final parts = <String>[];
    if (_trafficPackCode == 'unlimited') {
      parts.add('Безлимит');
    } else {
      parts.add('$_trafficGb ГБ');
    }
    if (_unlimitedAppCodes.isNotEmpty) {
      parts.add('приложений: ${_unlimitedAppCodes.length}');
    }
    if (_dedicatedIp) {
      parts.add('выделенный IP');
    }
    parts.add('устройств: $_maxDevices');
    return parts.join(' • ');
  }

  String _appTitle(String code) {
    for (final app in TariffApp.values) {
      if (app.name == code) return app.title;
    }
    return code;
  }

  List<String> _catalogAppCodes() {
    final raw = (_catalog?['unlimitedApps'] as List?) ?? const [];
    final out = <String>[];
    for (final item in raw) {
      if (item is Map) {
        final code = (item['code'] ?? '').toString().trim().toLowerCase();
        if (code.isNotEmpty) out.add(code);
      }
    }
    if (out.isNotEmpty) return out;
    return TariffApp.values.map((app) => app.name).toList();
  }

  List<Map<String, dynamic>> _catalogTrafficPacks() {
    final raw = (_catalog?['trafficPacks'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _loadTariffCatalog() async {
    final res = await widget.api.fetchTariffCatalog();
    if (!mounted || !res.ok || res.data == null) return;
    setState(() => _catalog = res.data);
  }

  Future<void> _refreshQuote() async {
    final res = await widget.api.quoteTariff(
      trafficPack: _trafficPackCode,
      trafficGb: _trafficGb,
      unlimitedApps: _unlimitedAppCodes.toList(),
      devices: _maxDevices.clamp(1, 5),
      dedicatedIp: _dedicatedIp,
    );
    if (!mounted) return;
    if (!res.ok || res.data == null) {
      setState(() {
        _quote = null;
        _status = res.message ?? 'Не удалось пересчитать тариф.';
      });
      return;
    }
    setState(() => _quote = res.data);
  }

  Map<String, dynamic>? _quoteMap() {
    if (_quote == null) return null;
    final raw = _quote!['quote'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return _quote;
  }

  Future<void> _loadDevices() async {
    if (_userId <= 0) {
      setState(() => _status = 'Не удалось определить user id.');
      return;
    }

    setState(() => _busy = true);
    try {
      final res = await widget.api.adminUserDevices(
        adminToken: widget.adminToken,
        userId: _userId,
      );
      if (!res.ok || res.data == null) {
        if (!mounted) return;
        setState(
          () => _status = res.message ?? 'Не удалось загрузить устройства.',
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _devices = res.data!;
        _status = 'Данные пользователя обновлены.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSubscription() async {
    if (_userId <= 0) return;
    setState(() => _busy = true);
    try {
      final res = await widget.api.adminSetSubscription(
        adminToken: widget.adminToken,
        userId: _userId,
        planCode: _planCode,
        planName: _planName,
        maxDevices: _maxDevices.clamp(1, 100),
        isActive: _isActive,
      );
      if (!mounted) return;
      setState(() {
        _status = res.ok
            ? 'Подписка обновлена.'
            : (res.message ?? 'Не удалось обновить подписку.');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyTariffForUser() async {
    if (_userId <= 0) return;
    setState(() => _busy = true);
    try {
      final res = await widget.api.adminApplyTariff(
        adminToken: widget.adminToken,
        userId: _userId,
        trafficPack: _trafficPackCode,
        trafficGb: _trafficGb,
        unlimitedApps: _unlimitedAppCodes.toList(),
        devices: _maxDevices.clamp(1, 5),
        dedicatedIp: _dedicatedIp,
      );
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        setState(() {
          _status = res.message ?? 'Не удалось выдать тариф пользователю.';
        });
        return;
      }

      final subRaw = res.data!['subscription'];
      final subMap = subRaw is Map<String, dynamic>
          ? subRaw
          : (subRaw is Map
                ? Map<String, dynamic>.from(subRaw)
                : <String, dynamic>{});
      final selectionRaw = res.data!['selection'];
      _applySelectionFromServer(selectionRaw);

      setState(() {
        _planCode = (subMap['planCode'] ?? _planCode).toString();
        _planName = (subMap['planName'] ?? _planName).toString();
        _isActive = subMap['isActive'] == true;
        _maxDevices =
            _asInt(subMap['maxDevices'])?.clamp(1, 100) ?? _maxDevices;
        _monthlyPriceRub = _asInt(subMap['monthlyPriceRub']);
        _expiresAt = (subMap['expiresAt'] ?? '').toString().trim();
        _quote = res.data;
        _status = 'Тариф сохранён на сервере для этого пользователя.';
      });
      _toast('Тариф выдан пользователю.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleDevice(Map<String, dynamic> device, bool enable) async {
    final uid = (device['deviceUid'] ?? '').toString();
    if (uid.isEmpty) return;

    setState(() => _busy = true);
    try {
      final res = enable
          ? await widget.api.adminEnableDevice(
              adminToken: widget.adminToken,
              deviceUid: uid,
            )
          : await widget.api.adminDisableDevice(
              adminToken: widget.adminToken,
              deviceUid: uid,
              reason: 'manual_block',
            );

      if (!mounted) return;
      if (!res.ok) {
        setState(() {
          _status = res.message ?? 'Операция с устройством не удалась.';
        });
        return;
      }
      _toast(enable ? 'Устройство включено.' : 'Устройство отключено.');
      await _loadDevices();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = (widget.user['email'] ?? '-').toString();
    final quoteMap = _quoteMap();
    final displayedPlan = (quoteMap?['planName'] ?? _planName).toString();
    final displayedPrice = _formatRub(
      quoteMap?['monthlyPriceRub'] ?? _monthlyPriceRub,
    );
    final lineItems = ((quoteMap?['lineItems'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final trafficPacks = _catalogTrafficPacks();
    final appCodes = _catalogAppCodes();

    return Scaffold(
      appBar: AppBar(title: Text(email)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_status != null) ...[
            _Card(
              child: Text(
                _status!,
                style: const TextStyle(
                  color: kBrandMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Тариф по каталогу'),
                const SizedBox(height: 8),
                Text(
                  'Серверный план: $displayedPlan',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (displayedPrice != null) 'Цена: $displayedPrice/мес',
                    'Истекает: ${_formatDate(_expiresAt)}',
                  ].join(' • '),
                  style: const TextStyle(
                    color: kBrandMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatTariffSummary(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Трафик',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children:
                      (trafficPacks.isNotEmpty
                              ? trafficPacks
                              : [
                                  {'code': 'gb5', 'title': '5 ГБ', 'gb': 5},
                                  {'code': 'gb20', 'title': '20 ГБ', 'gb': 20},
                                  {'code': 'gb50', 'title': '50 ГБ', 'gb': 50},
                                  {
                                    'code': 'gb100',
                                    'title': '100 ГБ',
                                    'gb': 100,
                                  },
                                  {
                                    'code': 'unlimited',
                                    'title': 'Безлимит',
                                    'gb': 999,
                                  },
                                ])
                          .map((pack) {
                            final code = (pack['code'] ?? '').toString();
                            final title = (pack['title'] ?? code).toString();
                            final gb = _asInt(pack['gb']) ?? _trafficGb;
                            return _ChipButton(
                              icon: Icons.public_rounded,
                              text: title,
                              selected: _trafficPackCode == code,
                              onTap: _busy
                                  ? () {}
                                  : () {
                                      setState(() {
                                        _trafficPackCode = code;
                                        if (code == 'unlimited') {
                                          _trafficGb = 500;
                                          _unlimitedAppCodes.clear();
                                        } else {
                                          _trafficGb = gb.clamp(1, 500);
                                        }
                                      });
                                      unawaited(_refreshQuote());
                                    },
                            );
                          })
                          .toList(),
                ),
                if (_trafficPackCode != 'unlimited') ...[
                  const SizedBox(height: 12),
                  Text(
                    'Объём: $_trafficGb ГБ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Slider(
                    value: _trafficGb.clamp(1, 500).toDouble(),
                    min: 1,
                    max: 500,
                    divisions: 499,
                    onChanged: _busy
                        ? null
                        : (v) {
                            setState(() => _trafficGb = v.round());
                          },
                    onChangeEnd: _busy
                        ? null
                        : (_) {
                            unawaited(_refreshQuote());
                          },
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [5, 20, 50, 100]
                        .map(
                          (gb) => _ChipButton(
                            icon: Icons.speed_rounded,
                            text: '$gb ГБ',
                            selected: _trafficGb == gb,
                            onTap: _busy
                                ? () {}
                                : () {
                                    setState(() => _trafficGb = gb);
                                    unawaited(_refreshQuote());
                                  },
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Безлимитные приложения',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: appCodes.map((code) {
                    final selected = _unlimitedAppCodes.contains(code);
                    return _ChipButton(
                      icon: TariffApp.values
                          .firstWhere(
                            (app) => app.name == code,
                            orElse: () => TariffApp.telegram,
                          )
                          .icon,
                      text: _appTitle(code),
                      selected: selected,
                      onTap: _busy || _trafficPackCode == 'unlimited'
                          ? () {}
                          : () {
                              setState(() {
                                if (selected) {
                                  _unlimitedAppCodes.remove(code);
                                } else {
                                  _unlimitedAppCodes.add(code);
                                }
                              });
                              unawaited(_refreshQuote());
                            },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(
                                () =>
                                    _maxDevices = (_maxDevices - 1).clamp(1, 5),
                              );
                              unawaited(_refreshQuote());
                            },
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: kBrandPrimarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_maxDevices',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: kBrandPrimaryDeep,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(
                                () =>
                                    _maxDevices = (_maxDevices + 1).clamp(1, 5),
                              );
                              unawaited(_refreshQuote());
                            },
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Устройства в тарифе',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Выделенный IP',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: const Text('Опция для продвинутых тарифов'),
                  value: _dedicatedIp,
                  onChanged: _busy
                      ? null
                      : (v) {
                          setState(() => _dedicatedIp = v);
                          unawaited(_refreshQuote());
                        },
                ),
                const SizedBox(height: 8),
                if (quoteMap != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kBrandPrimarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Сервер считает: ${quoteMap['planName'] ?? displayedPlan}'
                          '${displayedPrice == null ? '' : ' • $displayedPrice/мес'}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        if (lineItems.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...lineItems.map((item) {
                            final title = (item['title'] ?? '-').toString();
                            final price = _formatRub(item['priceRub']) ?? '0 ₽';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '$title: $price',
                                style: const TextStyle(
                                  color: kBrandMuted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _refreshQuote,
                        child: const Text('Пересчитать'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _busy ? null : _applyTariffForUser,
                        child: const Text('Выдать тариф'),
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
                const _SectionTitle('Ручной режим доступа'),
                const SizedBox(height: 10),
                const Text(
                  'Оставляем как аварийный инструмент. Основной способ теперь — серверный тариф по каталогу выше.',
                  style: TextStyle(
                    color: kBrandMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ChipButton(
                        icon: Icons.flash_on_rounded,
                        text: 'Trial',
                        selected: _planCode == 'trial',
                        onTap: () {
                          setState(() {
                            _planCode = 'trial';
                            _planName = 'Trial';
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ChipButton(
                        icon: Icons.workspace_premium_rounded,
                        text: 'Base',
                        selected: _planCode == 'base',
                        onTap: () {
                          setState(() {
                            _planCode = 'base';
                            _planName = 'Base';
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(
                        () => _maxDevices = (_maxDevices - 1).clamp(1, 100),
                      ),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: kBrandPrimarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_maxDevices',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: kBrandPrimaryDeep,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(
                        () => _maxDevices = (_maxDevices + 1).clamp(1, 100),
                      ),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Лимит устройств',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Подписка активна',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: const Text(
                    'Если выключить, доступ к VPN будет закрыт',
                  ),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _saveSubscription,
                    child: const Text('Сохранить подписку'),
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
                Row(
                  children: [
                    const Expanded(child: _SectionTitle('Устройства')),
                    TextButton(
                      onPressed: _busy ? null : _loadDevices,
                      child: const Text('Обновить'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _status!,
                      style: const TextStyle(
                        color: kBrandMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_devices.isEmpty)
                  const Text(
                    'Устройств пока нет.',
                    style: TextStyle(
                      color: kBrandMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  ..._devices.map((device) {
                    final enabled = device['isEnabled'] == true;
                    final uid = (device['deviceUid'] ?? '-').toString();
                    final ip = (device['assignedIp'] ?? 'нет ip').toString();
                    final disabledReason = (device['disabledReason'] ?? '')
                        .toString();
                    final lastSeen = _formatDate(device['lastSeenAt']);
                    final lastConfig = _formatDate(device['lastConfigAt']);
                    return Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            enabled
                                ? Icons.devices_rounded
                                : Icons.device_unknown_rounded,
                            color: enabled ? kBrandPrimary : kBrandDanger,
                          ),
                          title: Text(
                            (device['deviceName'] ?? uid).toString(),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '$uid\n$ip • ${(device['platform'] ?? 'unknown').toString()}'
                            '\nПоследняя активность: $lastSeen'
                            '\nПоследний конфиг: $lastConfig'
                            '${disabledReason.isEmpty ? '' : '\nПричина: $disabledReason'}',
                          ),
                          isThreeLine: true,
                          trailing: TextButton(
                            onPressed: _busy
                                ? null
                                : () => _toggleDevice(device, !enabled),
                            child: Text(enabled ? 'Отключить' : 'Включить'),
                          ),
                        ),
                        if (device != _devices.last) const Divider(height: 14),
                      ],
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminMiniStat extends StatelessWidget {
  final String title;
  final String value;

  const _AdminMiniStat({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBrandPrimarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: kBrandMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: kBrandText,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
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
                        ? kBrandDarkSurface
                        : kBrandPrimarySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(leading, color: kBrandPrimary),
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

class _DesktopShellBody extends StatelessWidget {
  final Widget child;

  const _DesktopShellBody({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [kBrandDarkBg, Color(0xFF0A2019), Color(0xFF06130F)]
              : const [kBrandLightBg, Color(0xFFEFF8F2), Color(0xFFF8FBF8)],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth >= 760 ? 980.0 : 560.0;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              ),
            );
          },
        ),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = textColor.withOpacity(isDark ? 0.72 : 0.62);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isDark ? kBrandDarkSurface : kBrandPrimarySoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: kBrandPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: mutedColor,
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
    final theme = Theme.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: theme.colorScheme.onSurface,
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
                  ? kBrandDarkSurface
                  : kBrandPrimarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: kBrandPrimary),
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
                  ? kBrandDarkSurface
                  : kBrandPrimarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: kBrandPrimary),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = selected
        ? kBrandPrimary
        : (isDark ? kBrandDarkSurface : kBrandPrimarySoft);
    final fg = selected ? Colors.white : theme.colorScheme.onSurface;
    final borderColor = selected
        ? kBrandPrimary.withOpacity(0.20)
        : theme.colorScheme.onSurface.withOpacity(isDark ? 0.16 : 0.12);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
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

class _IncludedBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IncludedBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? kBrandDarkSurface : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.16 : 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: kBrandPrimary),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
                  color: isDark ? kBrandDarkSurface : kBrandPrimarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: kBrandPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.62),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    final fill = tint == null
        ? surface
        : (isDark ? Color.alphaBlend(tint!.withOpacity(0.16), surface) : tint!);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.10)
              : kBrandPrimaryDeep.withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            offset: const Offset(0, 12),
            color: isDark
                ? Colors.black.withOpacity(0.24)
                : kBrandPrimaryDeep.withOpacity(0.08),
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

class WireGuardRuntimeStatus {
  final String tunnelName;
  final String serviceName;
  final String serviceState;
  final bool interfacePresent;
  final String? configEndpoint;
  final String? activeEndpoint;
  final String configMode;
  final int? latestHandshakeEpochSeconds;
  final int rxBytes;
  final int txBytes;
  final String rawWgDump;
  final List<String> otherActiveWireGuardInterfaces;
  final List<String> otherRunningWireGuardServices;
  final String? primaryDefaultRouteAlias;

  const WireGuardRuntimeStatus({
    required this.tunnelName,
    required this.serviceName,
    required this.serviceState,
    required this.interfacePresent,
    required this.configEndpoint,
    required this.activeEndpoint,
    required this.configMode,
    required this.latestHandshakeEpochSeconds,
    required this.rxBytes,
    required this.txBytes,
    required this.rawWgDump,
    required this.otherActiveWireGuardInterfaces,
    required this.otherRunningWireGuardServices,
    required this.primaryDefaultRouteAlias,
  });

  bool get hasRecentHandshake {
    final epoch = latestHandshakeEpochSeconds;
    if (epoch == null || epoch <= 0) return false;
    final handshakeAt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    return DateTime.now().difference(handshakeAt).inSeconds <= 180;
  }

  bool get hasTraffic => rxBytes > 0 || txBytes > 0;

  bool get hasCompetingTunnel =>
      otherActiveWireGuardInterfaces.isNotEmpty ||
      otherRunningWireGuardServices.isNotEmpty;

  bool get isReallyConnected =>
      serviceState == 'running' &&
      interfacePresent &&
      hasRecentHandshake &&
      hasTraffic;

  String get bestEndpoint {
    final endpoint = activeEndpoint ?? configEndpoint;
    if (endpoint == null || endpoint.trim().isEmpty) {
      return 'не найден';
    }
    return endpoint;
  }

  String get modeLabel {
    switch (configMode) {
      case 'full_tunnel':
        return 'full tunnel';
      case 'social_only':
        return 'social only';
      default:
        return 'unknown';
    }
  }

  String get handshakeLabel {
    final epoch = latestHandshakeEpochSeconds;
    if (epoch == null || epoch <= 0) return 'нет';
    final handshakeAt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    final age = DateTime.now().difference(handshakeAt);
    if (age.inSeconds < 60) return '${age.inSeconds} сек назад';
    if (age.inMinutes < 60) return '${age.inMinutes} мин назад';
    return '${age.inHours} ч назад';
  }

  String get trafficLabel =>
      'rx ${_formatBytes(rxBytes)} / tx ${_formatBytes(txBytes)}';

  String get competingTunnelsLabel {
    final combined = <String>{
      ...otherActiveWireGuardInterfaces,
      ...otherRunningWireGuardServices,
    }.toList()..sort();
    if (combined.isEmpty) return 'none';
    return combined.join(', ');
  }

  String get routeOwnerLabel {
    final alias = primaryDefaultRouteAlias?.trim();
    if (alias == null || alias.isEmpty) return 'unknown';
    return alias;
  }

  String get routeConflictHint {
    if (hasCompetingTunnel) {
      return 'Есть другой активный WireGuard-интерфейс или сервис. Он может мешать маршрутизации и рукопожатию BlueVPNDev1.';
    }
    if (routeOwnerLabel != 'unknown' && routeOwnerLabel != tunnelName) {
      return 'Основной IPv4-маршрут сейчас принадлежит не BlueVPNDev1, а $routeOwnerLabel.';
    }
    if (routeOwnerLabel == tunnelName) {
      return 'Основной IPv4-маршрут уже у BlueVPNDev1.';
    }
    return 'Владелец основного IPv4-маршрута определить не удалось.';
  }

  String describe() {
    return 'service=$serviceState, interface=${interfacePresent ? "present" : "missing"}, handshake=$handshakeLabel, traffic=$trafficLabel, endpoint=$bestEndpoint, mode=$modeLabel, competing=$competingTunnelsLabel, primaryRoute=$routeOwnerLabel';
  }

  static String _formatBytes(int value) {
    if (value < 1024) return '$value B';
    final kb = value / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KiB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MiB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GiB';
  }

  static String _serviceNameForTunnel(String tunnelName) =>
      r'WireGuardTunnel$' + tunnelName;

  static String _psSingleQuoted(String value) => value.replaceAll("'", "''");

  static String? _readConfigField(String configText, String fieldName) {
    final match = RegExp(
      '^\\s*$fieldName\\s*=\\s*(.+?)\\s*\$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(configText);
    return match?.group(1)?.trim();
  }

  static String _detectMode(String configText) {
    final allowed = (_readConfigField(configText, 'AllowedIPs') ?? '')
        .toLowerCase();
    final isFull =
        allowed.contains('0.0.0.0/0') ||
        allowed.contains('::/0') ||
        (allowed.contains('0.0.0.0/1') && allowed.contains('128.0.0.0/1'));
    return isFull ? 'full_tunnel' : 'social_only';
  }

  static String _resolveWgExe(String wireguardExePath) {
    if (wireguardExePath.trim().isNotEmpty &&
        wireguardExePath.toLowerCase().endsWith(r'\wireguard.exe')) {
      final wgPath =
          wireguardExePath.substring(
            0,
            wireguardExePath.length - 'wireguard.exe'.length,
          ) +
          'wg.exe';
      if (File(wgPath).existsSync()) return wgPath;
    }

    final candidates = <String>[
      r'C:\Program Files\WireGuard\wg.exe',
      r'C:\Program Files (x86)\WireGuard\wg.exe',
      'wg.exe',
    ];

    for (final c in candidates) {
      if (c == 'wg.exe' || File(c).existsSync()) return c;
    }
    return 'wg.exe';
  }

  static List<String> _parseNonEmptyLines(ProcessResult result) {
    return (result.stdout ?? '')
        .toString()
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static Future<List<String>> _queryOtherActiveWireGuardInterfaces(
    String tunnelName,
  ) async {
    if (!Platform.isWindows) return const [];
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'''
$ErrorActionPreference="SilentlyContinue"
$tunnel = '__TUNNEL__'
$labels = New-Object System.Collections.Generic.List[string]
function Add-Label([string]$value) {
  if (-not [string]::IsNullOrWhiteSpace($value) -and -not $labels.Contains($value)) {
    $labels.Add($value) | Out-Null
  }
}
try {
  Get-NetAdapter -IncludeHidden |
    Where-Object {
      $_.Name -ne $tunnel -and
      ($_.Status -eq 'Up' -or $_.Status -eq 'Connected') -and
      (
        $_.InterfaceDescription -match '(?i)(WireGuard|Wintun|Amnezia|WARP|Cloudflare)' -or
        $_.Name -match '(?i)(WireGuard|Wintun|Amnezia|WARP|Cloudflare|device[0-9_]+)'
      )
    } |
    ForEach-Object { Add-Label ("adapter:" + $_.Name) }
} catch {}
try {
  Get-CimInstance Win32_NetworkAdapter |
    Where-Object {
      $_.NetEnabled -eq $true -and
      (
        $_.Name -match '(?i)(WireGuard|Wintun|Amnezia|WARP|Cloudflare)' -or
        $_.NetConnectionID -match '(?i)(WireGuard|Wintun|Amnezia|WARP|Cloudflare|device[0-9_]+)' -or
        $_.ServiceName -match '(?i)(WireGuard|Wintun|Amnezia|WARP|Cloudflare)'
      )
    } |
    ForEach-Object {
      $name = $_.NetConnectionID
      if ([string]::IsNullOrWhiteSpace($name)) { $name = $_.Name }
      if ($name -ne $tunnel) { Add-Label ("adapter:" + $name) }
    }
} catch {}
$labels | Sort-Object -Unique
'''
            .replaceAll('__TUNNEL__', _psSingleQuoted(tunnelName)),
      ], runInShell: true);
      if (res.exitCode != 0) return const [];
      return _parseNonEmptyLines(res);
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> _queryOtherRunningWireGuardServices(
    String ownServiceName,
  ) async {
    if (!Platform.isWindows) return const [];
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'''
$ErrorActionPreference="SilentlyContinue"
$ownService = '__SERVICE__'
Get-CimInstance Win32_Service |
  Where-Object {
    (
      ($_.Name -like 'WireGuardTunnel$*' -and $_.Name -ne $ownService) -or
      $_.Name -like 'AmneziaWGTunnel$*' -or
      $_.Name -match '(?i)(CloudflareWARP|Cloudflare WARP|WARP)'
    ) -and
    $_.State -eq 'Running' -and
    $_.Name -ne 'WireGuardManager' -and
    $_.Name -ne 'AmneziaWGManager'
  } |
  ForEach-Object { "service:" + $_.Name } |
  Sort-Object -Unique
'''
            .replaceAll('__SERVICE__', _psSingleQuoted(ownServiceName)),
      ], runInShell: true);
      if (res.exitCode != 0) return const [];
      return _parseNonEmptyLines(res);
    } catch (_) {
      return const [];
    }
  }

  static Future<String?> _queryPrimaryDefaultRouteAlias() async {
    if (!Platform.isWindows) return null;
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'''
$ErrorActionPreference="SilentlyContinue"
$route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' |
  Sort-Object RouteMetric, InterfaceMetric |
  Select-Object -First 1
if ($route) { $route.InterfaceAlias }
''',
      ], runInShell: true);
      if (res.exitCode != 0) return null;
      final lines = _parseNonEmptyLines(res);
      if (lines.isEmpty) return null;
      return lines.first;
    } catch (_) {
      return null;
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

  static Future<WireGuardRuntimeStatus> query({
    required String tunnelName,
    required String configPath,
    required String wireguardExePath,
  }) async {
    final serviceName = _serviceNameForTunnel(tunnelName);
    final serviceState = await _queryServiceState(serviceName);

    String? configEndpoint;
    String configMode = 'unknown';
    try {
      final configFile = File(configPath);
      if (configFile.existsSync()) {
        final rawConfig = await configFile.readAsString();
        configEndpoint = _readConfigField(rawConfig, 'Endpoint');
        configMode = _detectMode(rawConfig);
      }
    } catch (_) {}

    final otherActiveWireGuardInterfaces =
        await _queryOtherActiveWireGuardInterfaces(tunnelName);
    final otherRunningWireGuardServices =
        await _queryOtherRunningWireGuardServices(serviceName);
    final primaryDefaultRouteAlias = await _queryPrimaryDefaultRouteAlias();

    final wgExe = _resolveWgExe(wireguardExePath);
    try {
      final res = await Process.run(wgExe, [
        'show',
        tunnelName,
        'dump',
      ], runInShell: true);
      final rawWgDump =
          ((res.stdout ?? '').toString() + '\n' + (res.stderr ?? '').toString())
              .trim();

      if (res.exitCode != 0 || rawWgDump.isEmpty) {
        return WireGuardRuntimeStatus(
          tunnelName: tunnelName,
          serviceName: serviceName,
          serviceState: serviceState,
          interfacePresent: false,
          configEndpoint: configEndpoint,
          activeEndpoint: null,
          configMode: configMode,
          latestHandshakeEpochSeconds: null,
          rxBytes: 0,
          txBytes: 0,
          rawWgDump: rawWgDump,
          otherActiveWireGuardInterfaces: otherActiveWireGuardInterfaces,
          otherRunningWireGuardServices: otherRunningWireGuardServices,
          primaryDefaultRouteAlias: primaryDefaultRouteAlias,
        );
      }

      final lines = rawWgDump
          .split(RegExp(r'\r?\n'))
          .where((line) => line.trim().isNotEmpty)
          .toList();

      if (lines.length < 2) {
        return WireGuardRuntimeStatus(
          tunnelName: tunnelName,
          serviceName: serviceName,
          serviceState: serviceState,
          interfacePresent: true,
          configEndpoint: configEndpoint,
          activeEndpoint: null,
          configMode: configMode,
          latestHandshakeEpochSeconds: null,
          rxBytes: 0,
          txBytes: 0,
          rawWgDump: rawWgDump,
          otherActiveWireGuardInterfaces: otherActiveWireGuardInterfaces,
          otherRunningWireGuardServices: otherRunningWireGuardServices,
          primaryDefaultRouteAlias: primaryDefaultRouteAlias,
        );
      }

      String? activeEndpoint;
      int? latestHandshakeEpochSeconds;
      var rxBytes = 0;
      var txBytes = 0;

      for (final peerLine in lines.skip(1)) {
        final parts = peerLine.split('\t');
        if (parts.length < 7) continue;

        final offset = parts.length >= 9 && parts[0].trim() == tunnelName
            ? 1
            : 0;
        if (parts.length < offset + 7) continue;

        final peerEndpoint = parts[offset + 2].trim();
        final handshake = int.tryParse(parts[offset + 4].trim()) ?? 0;
        final rx = int.tryParse(parts[offset + 5].trim()) ?? 0;
        final tx = int.tryParse(parts[offset + 6].trim()) ?? 0;

        if (activeEndpoint == null &&
            peerEndpoint.isNotEmpty &&
            peerEndpoint != '(none)') {
          activeEndpoint = peerEndpoint;
        }

        if (latestHandshakeEpochSeconds == null ||
            handshake > latestHandshakeEpochSeconds) {
          latestHandshakeEpochSeconds = handshake > 0 ? handshake : null;
          rxBytes = rx;
          txBytes = tx;
        }
      }

      return WireGuardRuntimeStatus(
        tunnelName: tunnelName,
        serviceName: serviceName,
        serviceState: serviceState,
        interfacePresent: true,
        configEndpoint: configEndpoint,
        activeEndpoint: activeEndpoint,
        configMode: configMode,
        latestHandshakeEpochSeconds: latestHandshakeEpochSeconds,
        rxBytes: rxBytes,
        txBytes: txBytes,
        rawWgDump: rawWgDump,
        otherActiveWireGuardInterfaces: otherActiveWireGuardInterfaces,
        otherRunningWireGuardServices: otherRunningWireGuardServices,
        primaryDefaultRouteAlias: primaryDefaultRouteAlias,
      );
    } catch (e) {
      return WireGuardRuntimeStatus(
        tunnelName: tunnelName,
        serviceName: serviceName,
        serviceState: serviceState,
        interfacePresent: false,
        configEndpoint: configEndpoint,
        activeEndpoint: null,
        configMode: configMode,
        latestHandshakeEpochSeconds: null,
        rxBytes: 0,
        txBytes: 0,
        rawWgDump: 'wg.exe error: $e',
        otherActiveWireGuardInterfaces: otherActiveWireGuardInterfaces,
        otherRunningWireGuardServices: otherRunningWireGuardServices,
        primaryDefaultRouteAlias: primaryDefaultRouteAlias,
      );
    }
  }
}

class DiagnosticsPage extends StatefulWidget {
  final String accessToken;
  final String email;

  const DiagnosticsPage({
    super.key,
    required this.accessToken,
    required this.email,
  });

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final _api = const BlueVpnApi(baseUrl: kApiBaseUrl);

  bool _loading = true;
  bool _sending = false;

  String _statePath = '';
  String _configPath = '';
  bool _configExists = false;
  String _deviceUid = '';
  String? _lastSendMessage;

  bool _isAdmin = false;

  String _wgExe = '';
  bool _wgFound = false;

  WireGuardRuntimeStatus? _runtimeStatus;
  String? _fallbackReportCode;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    _statePath = BlueVpnLocalPaths.sharedStateDirSync();
    _deviceUid = '';
    try {
      final deviceFile = File('$_statePath\\device_id.txt');
      if (await deviceFile.exists()) {
        _deviceUid = (await deviceFile.readAsString()).trim();
      }
    } catch (_) {
      _deviceUid = '';
    }

    final cfg = ConfigStore();
    _configPath = cfg.managedConfigPath;
    _configExists = File(_configPath).existsSync();

    _wgExe = _resolveWireGuardExe();
    _wgFound =
        File(_wgExe).existsSync() || _wgExe.toLowerCase() == 'wireguard.exe';

    _isAdmin = await _isAdminWindows();
    _runtimeStatus = await WireGuardRuntimeStatus.query(
      tunnelName: kTunnelName,
      configPath: _configPath,
      wireguardExePath: _wgExe,
    );

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
      return out.contains('S-1-16-12288') || out.contains('S-1-16-16384');
    } catch (_) {
      return false;
    }
  }

  String _buildSupportReportCode() {
    final runtime = _runtimeStatus;
    final payload = <String, Object?>{
      'schema': 1,
      'product': kProductName,
      'appVersion': kAppVersion,
      'build': kBuildMarker,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'email': widget.email,
      'deviceUid': _deviceUid,
      'configExists': _configExists,
      'wireGuardFound': _wgFound,
      'admin': _isAdmin,
      'service': runtime?.serviceState ?? 'unknown',
      'mode': runtime?.modeLabel ?? 'unknown',
      'hasHandshake': runtime?.hasRecentHandshake ?? false,
      'hasTraffic': runtime?.hasTraffic ?? false,
      'traffic': runtime?.trafficLabel ?? 'rx 0 B / tx 0 B',
      'realTunnel': runtime?.isReallyConnected ?? false,
      'competingVpn': runtime?.competingTunnelsLabel ?? 'none',
      'routeOwner': runtime?.routeOwnerLabel ?? 'unknown',
      'routeHint': runtime?.routeConflictHint ?? '',
      'endpoint': runtime?.bestEndpoint ?? '',
    };
    final jsonBytes = utf8.encode(jsonEncode(payload));
    final packed = gzip.encode(jsonBytes);
    return 'GVPN1.${base64UrlEncode(packed)}';
  }

  String _supportSummary() {
    final runtime = _runtimeStatus;
    final parts = <String>[
      'service=${runtime?.serviceState ?? 'unknown'}',
      'mode=${runtime?.modeLabel ?? 'unknown'}',
      'handshake=${runtime?.hasRecentHandshake == true ? 'yes' : 'no'}',
      'traffic=${runtime?.trafficLabel ?? 'rx 0 B / tx 0 B'}',
      'competing=${runtime?.competingTunnelsLabel ?? 'none'}',
      'route=${runtime?.routeOwnerLabel ?? 'unknown'}',
    ];
    return parts.join(', ');
  }

  Future<void> _sendReport() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _lastSendMessage = null;
    });

    final reportCode = _buildSupportReportCode();
    final result = await _api.sendSupportReport(
      accessToken: widget.accessToken,
      report: reportCode,
      summary: _supportSummary(),
      appVersion: kAppVersion,
      deviceUid: _deviceUid,
    );

    if (!mounted) return;
    final message = result.ok
        ? 'Отчёт отправлен в поддержку.'
        : 'Не удалось отправить отчёт. Можно скопировать код и передать его поддержке.';
    setState(() {
      _sending = false;
      _lastSendMessage = message;
      _fallbackReportCode = result.ok ? null : reportCode;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyFallbackReportCode() async {
    final code = _fallbackReportCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Код отчёта скопирован.')));
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtimeStatus;
    final serviceState = runtime?.serviceState ?? 'unknown';
    final handshakeOk = runtime?.hasRecentHandshake ?? false;
    final trafficOk = runtime?.hasTraffic ?? false;
    final realTunnelOk = runtime?.isReallyConnected ?? false;
    final competingTunnels = runtime?.competingTunnelsLabel ?? 'none';
    final serviceOk = serviceState == 'running' || serviceState == 'stopped';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Поддержка'),
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
                const _PageTitle(
                  title: 'Помощь и отчёт',
                  subtitle:
                      'Если VPN не подключается или работает странно, отправь отчёт в поддержку одной кнопкой.',
                  icon: Icons.support_agent_rounded,
                ),
                const SizedBox(height: 12),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SupportStatusLine(
                        title: 'Системный компонент',
                        ok: serviceOk,
                        value: serviceOk ? 'готов' : 'нужно переустановить',
                      ),
                      const SizedBox(height: 10),
                      _SupportStatusLine(
                        title: 'VPN-конфигурация',
                        ok: _configExists,
                        value: _configExists ? 'получена' : 'ещё не получена',
                      ),
                      const SizedBox(height: 10),
                      _SupportStatusLine(
                        title: 'Подключение',
                        ok: realTunnelOk,
                        value: realTunnelOk
                            ? 'активно'
                            : handshakeOk || trafficOk
                            ? 'проверяется'
                            : 'не активно',
                      ),
                      const SizedBox(height: 10),
                      _SupportStatusLine(
                        title: 'Другие VPN',
                        ok: competingTunnels == 'none',
                        value: competingTunnels == 'none'
                            ? 'не мешают'
                            : 'обнаружен другой VPN',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Отчёт для поддержки',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'В отчёте нет пароля, токенов и приватных ключей. Он закодирован, чтобы на экране не светились технические данные.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.62),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_lastSendMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _lastSendMessage!,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                      const SizedBox(height: 14),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrandPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _sending ? null : _sendReport,
                        child: Text(
                          _sending ? 'Отправляем...' : 'Отправить отчёт',
                        ),
                      ),
                      if (_fallbackReportCode != null) ...[
                        const SizedBox(height: 10),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            side: const BorderSide(color: kBrandPrimary),
                            foregroundColor: kBrandPrimaryDeep,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _copyFallbackReportCode,
                          child: const Text('Скопировать код отчёта'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SupportStatusLine extends StatelessWidget {
  final String title;
  final bool ok;
  final String value;

  const _SupportStatusLine({
    required this.title,
    required this.ok,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.info_rounded,
          color: ok ? kBrandPrimary : kBrandWarm,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.65),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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

class _GreenVpnSystemServiceResponse {
  final bool ok;
  final int statusCode;
  final int? exitCode;
  final String? message;

  const _GreenVpnSystemServiceResponse({
    required this.ok,
    required this.statusCode,
    this.exitCode,
    this.message,
  });

  bool get unavailable => statusCode == 0;
}

class _GreenVpnSystemServiceClient {
  const _GreenVpnSystemServiceClient();

  static final Uri _baseUri = Uri.parse('http://127.0.0.1:48737');

  Future<_GreenVpnSystemServiceResponse> ping() => _request(
    'GET',
    '/ping',
    connectTimeout: const Duration(milliseconds: 700),
    responseTimeout: const Duration(seconds: 2),
  );

  Future<_GreenVpnSystemServiceResponse> connect() => _request(
    'POST',
    '/connect',
    connectTimeout: const Duration(seconds: 2),
    responseTimeout: const Duration(seconds: 130),
  );

  Future<_GreenVpnSystemServiceResponse> disconnect() => _request(
    'POST',
    '/disconnect',
    connectTimeout: const Duration(seconds: 2),
    responseTimeout: const Duration(seconds: 130),
  );

  Future<_GreenVpnSystemServiceResponse> _request(
    String method,
    String path, {
    required Duration connectTimeout,
    required Duration responseTimeout,
  }) async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final uri = _baseUri.resolve(path);
      final request = method == 'POST'
          ? await client.postUrl(uri).timeout(connectTimeout)
          : await client.getUrl(uri).timeout(connectTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (method == 'POST') {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.add(utf8.encode('{}'));
      }

      final response = await request.close().timeout(responseTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));

      Map<String, dynamic> json = const <String, dynamic>{};
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          json = decoded;
        } else if (decoded is Map) {
          json = decoded.map((key, value) => MapEntry('$key', value));
        }
      } catch (_) {}

      final ok =
          response.statusCode >= 200 &&
          response.statusCode < 300 &&
          json['ok'] == true;
      return _GreenVpnSystemServiceResponse(
        ok: ok,
        statusCode: response.statusCode,
        exitCode: _intFromJson(json['exitCode']),
        message: json['message']?.toString(),
      );
    } catch (e) {
      return _GreenVpnSystemServiceResponse(
        ok: false,
        statusCode: 0,
        message: e.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static int? _intFromJson(Object? value) {
    if (value is int) return value;
    if (value == null) return null;
    return int.tryParse(value.toString());
  }
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

  static const String _connectTaskName = 'GreenVPNConnect';
  static const String _disconnectTaskName = 'GreenVPNDisconnect';

  Future<ProcessResult> _run(String exe, List<String> args) async {
    return Process.run(exe, args, runInShell: true);
  }

  Future<bool> _scheduledVpnTaskExists(String taskName) async {
    final res = await _run('schtasks', ['/Query', '/TN', taskName]);
    return res.exitCode == 0;
  }

  Future<ProcessResult> _runScheduledVpnTask(String taskName) {
    return _run('schtasks', ['/Run', '/TN', taskName]);
  }

  Future<ProcessResult> _setTunnelServiceManualStart() {
    // WireGuard installs tunnel services as AUTO_START by default. That is bad
    // for an MVP client because a full-tunnel service can come back on reboot
    // and fight with Amnezia/WARP/other VPNs before our UI is even open.
    return _run('sc', ['config', _serviceName, 'start=', 'demand']);
  }

  Future<ProcessResult> _cleanupLingeringAdapter({
    required bool elevated,
  }) async {
    // Safety policy: do not manually remove routes/IPs or disable the Wintun
    // adapter. WireGuard owns tunnel teardown; forcing adapter mutations can
    // race with Wintun/AmneziaWG and has caused freezes on testers' machines.
    return ProcessResult(
      0,
      0,
      'adapter cleanup skipped; WireGuard service owns teardown; elevated=$elevated',
      '',
    );
  }

  String _adapterStateScript() {
    return r'''$ErrorActionPreference = "SilentlyContinue"
$tun = "__TUN__"
$adapter = Get-NetAdapter -Name $tun
$route = Get-NetRoute -InterfaceAlias $tun | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' -or $_.DestinationPrefix -eq '::/0' }
$ip = Get-NetIPAddress -InterfaceAlias $tun
if ($null -eq $adapter) { "adapter=missing" } else { "adapter=" + $adapter.Status }
if ($null -eq $route) { "route=missing" } else { "route=present" }
if ($null -eq $ip) { "ip=missing" } else { "ip=present" }
'''
        .replaceAll('__TUN__', tunnelName);
  }

  Future<String> _queryAdapterState() async {
    final res = await _run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      _adapterStateScript(),
    ]);
    return ((res.stdout ?? '').toString() +
            '\n' +
            (res.stderr ?? '').toString())
        .trim();
  }

  Future<int?> _queryServicePid() async {
    final script =
        r'''
$ErrorActionPreference = "SilentlyContinue"
$svc = Get-CimInstance Win32_Service -Filter "Name='__SVC__'"
if ($null -eq $svc) { exit 0 }
[Console]::WriteLine($svc.ProcessId)
'''
            .replaceAll('__SVC__', _serviceName.replaceAll("'", "''"));
    final res = await _run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    final raw =
        ((res.stdout ?? '').toString() + '\n' + (res.stderr ?? '').toString())
            .trim();
    return int.tryParse(raw);
  }

  Future<void> _forceKillServicePid({
    required Future<void> Function(String) log,
  }) async {
    final pid = await _queryServicePid();
    await log(
      'service pid=' +
          (pid?.toString() ?? 'none') +
          '; taskkill skipped by safety policy',
    );
  }

  bool _adapterStillBlocksTraffic(String state) {
    final raw = state.toLowerCase();
    return raw.contains('adapter=up') ||
        raw.contains('route=present') ||
        raw.contains('ip=present');
  }

  Future<bool> _waitForAdapterCleanup({
    required Future<void> Function(String) log,
    int loops = 16,
  }) async {
    for (var i = 0; i < loops; i++) {
      final state = await _queryAdapterState();
      await log(
        'adapter-state[$i] ' +
            state.replaceAll('\r', ' ').replaceAll('\n', ' | '),
      );
      if (!_adapterStillBlocksTraffic(state)) return true;
      await Future.delayed(const Duration(milliseconds: 350));
    }
    return false;
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
        ((r.stdout ?? '').toString() + '\n' + (r.stderr ?? '').toString())
            .trim();

    bool isRunningText(String out) => out.contains('RUNNING');
    Future<ProcessResult> scQueryEx() => _run('sc', ['queryex', _serviceName]);
    Future<WireGuardRuntimeStatus> runtimeStatus() =>
        WireGuardRuntimeStatus.query(
          tunnelName: tunnelName,
          configPath: configPath,
          wireguardExePath: _exe,
        );
    Future<void> prepareConfigForService() async {
      try {
        final f = File(configPath);
        if (!f.parent.existsSync()) {
          f.parent.createSync(recursive: true);
        }
        await Process.run('attrib', [
          '-H',
          '-S',
          '-R',
          f.parent.path,
        ], runInShell: true);
        await Process.run('icacls', [
          f.parent.path,
          '/inheritance:e',
          '/grant',
          '*S-1-5-11:(OI)(CI)M',
          '*S-1-5-18:(OI)(CI)F',
          '*S-1-5-32-544:(OI)(CI)F',
        ], runInShell: true);
        if (f.existsSync()) {
          await Process.run('attrib', [
            '-H',
            '-S',
            '-R',
            f.path,
          ], runInShell: true);
          await Process.run('icacls', [
            f.path,
            '/inheritance:e',
            '/grant',
            '*S-1-5-11:M',
            '*S-1-5-18:F',
            '*S-1-5-32-544:F',
          ], runInShell: true);
        }
      } catch (_) {}
    }

    Future<bool> waitRunning({int loops = 60}) async {
      for (var i = 0; i < loops; i++) {
        final q = await scQueryEx();
        final o = outOf(q);
        await log(
          'queryex(connect)[$i] ec=${q.exitCode} :: ' +
              o.replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
        if (q.exitCode == 0 && isRunningText(o)) return true;
        await Future.delayed(const Duration(milliseconds: 250));
      }
      return false;
    }

    Future<bool> isAdmin() async {
      try {
        final res = await _run('whoami', ['/groups']);
        final out =
            ((res.stdout ?? '').toString() +
            '\n' +
            (res.stderr ?? '').toString());
        return out.contains('S-1-16-12288') || out.contains('S-1-16-16384');
      } catch (_) {
        return false;
      }
    }

    try {
      await log('=== CONNECT requested ===');
      await log('service=' + _serviceName);
      await log('exe=' + _exe);
      await log('cfg=' + configPath);
      await prepareConfigForService();

      if (!File(configPath).existsSync()) {
        await log('ERROR: configPath does not exist');
        return VpnBackendResult(
          ok: false,
          message: 'Config not found: $configPath',
        );
      }

      final preflight = await WireGuardRuntimeStatus.query(
        tunnelName: tunnelName,
        configPath: configPath,
        wireguardExePath: _exe,
      );
      await log('preflight(connect) ' + preflight.describe());
      if (preflight.hasCompetingTunnel) {
        await log(
          '=== CONNECT BLOCKED: competing VPN active :: ' +
              preflight.competingTunnelsLabel,
        );
        return VpnBackendResult(
          ok: false,
          message:
              'Другой VPN уже активен: ${preflight.competingTunnelsLabel}. Green VPN не будет включаться поверх него, чтобы не сломать сеть. Отключи Amnezia/WARP/другой VPN и попробуй снова.',
        );
      }

      final q0 = await scQueryEx();
      final o0 = outOf(q0);
      await log(
        'queryex(initial) ec=${q0.exitCode} :: ' +
            o0.replaceAll('\r', ' ').replaceAll('\n', ' | '),
      );

      final admin = await isAdmin();
      await log('isAdmin=' + admin.toString());

      if (admin) {
        if (q0.exitCode == 0) {
          final stop = await _run('sc', ['stop', _serviceName]);
          await log(
            'sc stop before reinstall ec=${stop.exitCode} :: ' +
                outOf(stop).replaceAll('\r', ' ').replaceAll('\n', ' | '),
          );
          await Future.delayed(const Duration(milliseconds: 700));
          final un = await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
          await log(
            'wireguard uninstall before reinstall ec=${un.exitCode} :: ' +
                outOf(un).replaceAll('\r', ' ').replaceAll('\n', ' | '),
          );
        }

        final cleanup = await _cleanupLingeringAdapter(elevated: true);
        await log(
          'adapter cleanup before install ec=${cleanup.exitCode} :: ' +
              outOf(cleanup).replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
        final cleaned = await _waitForAdapterCleanup(log: log);
        await log(
          'adapter cleanup before install settled=' + cleaned.toString(),
        );

        final ins = await _run(_exe, ['/installtunnelservice', configPath]);
        await log(
          'wireguard install ec=${ins.exitCode} :: ' +
              outOf(ins).replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
        final manualStart = await _setTunnelServiceManualStart();
        await log(
          'sc config demand ec=${manualStart.exitCode} :: ' +
              outOf(manualStart).replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
        final st = await _run('sc', ['start', _serviceName]);
        await log(
          'sc start ec=${st.exitCode} :: ' +
              outOf(st).replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
      } else {
        final cleanup = await _cleanupLingeringAdapter(elevated: false);
        await log(
          'scheduled adapter cleanup before install ec=${cleanup.exitCode} :: ' +
              outOf(cleanup).replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
        final cleaned = await _waitForAdapterCleanup(log: log);
        await log(
          'scheduled adapter cleanup before install settled=' +
              cleaned.toString(),
        );

        var elevatedStarted = false;
        const systemService = _GreenVpnSystemServiceClient();
        final servicePing = await systemService.ping();
        await log(
          'native service ping ok=${servicePing.ok} http=${servicePing.statusCode} msg=${servicePing.message ?? ''}',
        );
        if (servicePing.ok) {
          final serviceConnect = await systemService.connect();
          await log(
            'native service connect ok=${serviceConnect.ok} http=${serviceConnect.statusCode} exit=${serviceConnect.exitCode} msg=${serviceConnect.message ?? ''}',
          );
          if (serviceConnect.ok) {
            elevatedStarted = true;
          } else if (serviceConnect.statusCode == HttpStatus.conflict ||
              serviceConnect.exitCode == 2) {
            return const VpnBackendResult(
              ok: false,
              message:
                  'Другой VPN уже активен. Green VPN не будет включаться поверх него, чтобы не сломать сеть. Отключи Amnezia/WARP/другой VPN и попробуй снова.',
            );
          }
        }

        if (!elevatedStarted) {
          await log('native service unavailable/failed; using scheduled task');
          if (!await _scheduledVpnTaskExists(_connectTaskName)) {
            await log('scheduled task missing: $_connectTaskName');
            return const VpnBackendResult(
              ok: false,
              message:
                  'Системный компонент Green VPN не установлен. Переустанови последнюю версию GreenVPN_Setup.exe один раз с правами администратора.',
            );
          }

          final elevated = await _runScheduledVpnTask(_connectTaskName);
          await log(
            'scheduled connect ec=${elevated.exitCode} :: ' +
                outOf(elevated).replaceAll('\r', ' ').replaceAll('\n', ' | '),
          );
          if (elevated.exitCode != 0) {
            return VpnBackendResult(
              ok: false,
              message:
                  'Не удалось запустить системный компонент Green VPN. Переустанови GreenVPN_Setup.exe. ${outOf(elevated)}',
            );
          }
        }
      }

      final ok = await waitRunning(loops: 60);
      if (!ok) {
        await log('=== CONNECT FAIL: not RUNNING after wait ===');
        if (await isAdmin()) {
          final un = await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
          await log(
            'wireguard uninstall after failed start ec=${un.exitCode} :: ' +
                outOf(un).replaceAll('\r', ' ').replaceAll('\n', ' | '),
          );
        } else {
          const systemService = _GreenVpnSystemServiceClient();
          final serviceDisconnect = await systemService.disconnect();
          await log(
            'native service uninstall after failed start ok=${serviceDisconnect.ok} http=${serviceDisconnect.statusCode} exit=${serviceDisconnect.exitCode} msg=${serviceDisconnect.message ?? ''}',
          );
          if (!serviceDisconnect.ok) {
            final elevated = await _runScheduledVpnTask(_disconnectTaskName);
            await log(
              'scheduled uninstall after failed start ec=${elevated.exitCode} :: ' +
                  outOf(elevated).replaceAll('\r', ' ').replaceAll('\n', ' | '),
            );
          }
        }
        return const VpnBackendResult(
          ok: false,
          message: 'VPN did not start (service not RUNNING). See backend.log',
        );
      }

      for (var i = 0; i < 35; i++) {
        final status = await runtimeStatus();
        await log('verify(connect)[$i] ' + status.describe());
        if (status.isReallyConnected) {
          await log('=== CONNECT OK ===');
          return const VpnBackendResult(ok: true);
        }
        await Future.delayed(const Duration(seconds: 1));
      }

      final status = await runtimeStatus();
      await log(
        '=== CONNECT FAIL: real tunnel not confirmed :: ' + status.describe(),
      );
      return VpnBackendResult(
        ok: false,
        message:
            'BlueVPNDev1 поднял сервис, но не подтвердил реальный handshake/traffic. ${status.describe()}. Открой Diagnostics и пришли endpoint, handshake и traffic.',
      );
    } catch (e) {
      await log('EXCEPTION(connect): ' + e.toString());
      return VpnBackendResult(
        ok: false,
        message: 'Connect error: $e (see backend.log)',
      );
    }
  }

  @override
  Future<VpnBackendResult> disconnect() async {
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
        ((r.stdout ?? '').toString() + '\n' + (r.stderr ?? '').toString())
            .trim();

    bool isStoppedText(String out) => out.contains('STOPPED');
    Future<ProcessResult> scQueryEx() => _run('sc', ['queryex', _serviceName]);

    Future<bool> waitStopped({int loops = 40}) async {
      for (var i = 0; i < loops; i++) {
        final q = await scQueryEx();
        final o = outOf(q);
        await log(
          'queryex[$i] ec=${q.exitCode} :: ' +
              o.replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
        if (q.exitCode != 0) return true;
        if (isStoppedText(o)) return true;
        await Future.delayed(const Duration(milliseconds: 250));
      }
      return false;
    }

    Future<bool> isAdmin() async {
      try {
        final res = await _run('whoami', ['/groups']);
        final out =
            ((res.stdout ?? '').toString() +
            '\n' +
            (res.stderr ?? '').toString());
        return out.contains('S-1-16-12288') || out.contains('S-1-16-16384');
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
        await log(
          'sc stop ec=${stop.exitCode} :: ' +
              outOf(stop).replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
        final un = await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
        await log(
          'wireguard uninstall ec=${un.exitCode} :: ' +
              outOf(un).replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
        final cleanup = await _cleanupLingeringAdapter(elevated: true);
        await log(
          'adapter cleanup ec=${cleanup.exitCode} :: ' +
              outOf(cleanup).replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
      } else {
        var elevatedStopped = false;
        const systemService = _GreenVpnSystemServiceClient();
        final servicePing = await systemService.ping();
        await log(
          'native service ping(disconnect) ok=${servicePing.ok} http=${servicePing.statusCode} msg=${servicePing.message ?? ''}',
        );
        if (servicePing.ok) {
          final serviceDisconnect = await systemService.disconnect();
          await log(
            'native service disconnect ok=${serviceDisconnect.ok} http=${serviceDisconnect.statusCode} exit=${serviceDisconnect.exitCode} msg=${serviceDisconnect.message ?? ''}',
          );
          elevatedStopped = serviceDisconnect.ok;
        }

        if (!elevatedStopped) {
          await log(
            'native service unavailable/failed for disconnect; using scheduled task',
          );
          if (!await _scheduledVpnTaskExists(_disconnectTaskName)) {
            await log('scheduled task missing: $_disconnectTaskName');
            return const VpnBackendResult(
              ok: false,
              message:
                  'Системный компонент Green VPN не установлен. Переустанови последнюю версию GreenVPN_Setup.exe один раз с правами администратора.',
            );
          }

          final elevated = await _runScheduledVpnTask(_disconnectTaskName);
          await log(
            'scheduled disconnect ec=${elevated.exitCode} :: ' +
                outOf(elevated).replaceAll('\r', ' ').replaceAll('\n', ' | '),
          );
          if (elevated.exitCode != 0) {
            return VpnBackendResult(
              ok: false,
              message:
                  'Не удалось запустить системное отключение Green VPN. ${outOf(elevated)}',
            );
          }
        }
        final cleanup = await _cleanupLingeringAdapter(elevated: false);
        await log(
          'scheduled adapter cleanup ec=${cleanup.exitCode} :: ' +
              outOf(cleanup).replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
      }

      final stopped = await waitStopped(loops: 40);
      if (!stopped) {
        await log(
          'disconnect stalled, retrying WireGuard uninstall without taskkill',
        );
        await _forceKillServicePid(log: log);
        final un2 = await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
        await log(
          'wireguard uninstall retry ec=${un2.exitCode} :: ' +
              outOf(un2).replaceAll('\r', ' ').replaceAll('\n', ' | '),
        );
      }

      final stoppedAfterKill = stopped || await waitStopped(loops: 20);
      if (!stoppedAfterKill) {
        await log('=== DISCONNECT FAIL: still RUNNING after safe retry ===');
        return const VpnBackendResult(
          ok: false,
          message:
              'Service still RUNNING after stop/uninstall retry. See backend.log',
        );
      }

      final cleaned = await _waitForAdapterCleanup(log: log);
      if (!cleaned) {
        await log(
          '=== DISCONNECT FAIL: adapter/default-route still present ===',
        );
        return const VpnBackendResult(
          ok: false,
          message:
              'BlueVPNDev1 всё ещё держит адаптер или маршрут после отключения. Закрой приложение, разреши UAC и повтори. См. backend.log.',
        );
      }

      await log('=== DISCONNECT OK ===');
      return const VpnBackendResult(ok: true);
    } catch (e) {
      await log('EXCEPTION: ' + e.toString());
      return VpnBackendResult(
        ok: false,
        message: 'Disconnect error: $e (see backend.log)',
      );
    }
  }

  @override
  Future<bool> isConnected() async {
    try {
      final status = await WireGuardRuntimeStatus.query(
        tunnelName: tunnelName,
        configPath:
            _lastConfigPath ?? r'C:\ProgramData\BlueVPN\BlueVPNDev1.conf',
        wireguardExePath: _exe,
      );
      return status.isReallyConnected;
    } catch (_) {
      return false;
    }
  }
}
