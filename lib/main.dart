// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'runtime_config.dart';
import 'services/fusion_connection_status_policy.dart';
import 'services/product_display_policy.dart';
import 'services/route_failure_cooldown.dart';
import 'services/server_location_policy.dart';
import 'services/single_flight_operation.dart';
import 'services/transport_preview_policy.dart';
import 'services/windows_dpapi.dart';
import 'services/windows_selective_routing_service.dart';
import 'services/windows_vpn_status_policy.dart';

/*
  Green VPN — режим "как пользовательский продукт":
  - Первый запуск: регистрация/вход (через сервер)
  - Дальше: авто-вход по сохранённой сессии
  - Пользователь НЕ видит: конфиги/папки/импорт/экспорт/профили
  - Конфиг выдаёт сервер (provision), хранится внутри AppData (скрыто)

  ВАЖНО: в VPN-экране НЕТ карточки "Профиль" (дырка закрыта).
*/

const String kTunnelName = greenVpnTunnelName;
const String kProductName = greenVpnProductName;
const String kIntelligentSmewHost = '37.220.85.211';
const String kAppVersion = String.fromEnvironment(
  'GREENVPN_APP_VERSION',
  defaultValue: '0.2.23-trial-only-android-vpn-takeover',
);
const bool kTrialOnlyNoAdsBuild = bool.fromEnvironment(
  'GREENVPN_TRIAL_ONLY_NO_ADS_BUILD',
  defaultValue: true,
);
const bool kPaidBetaBuild = bool.fromEnvironment(
  'GREENVPN_PAID_BETA_BUILD',
  defaultValue: false,
);
const bool kPublicProductBuild = bool.fromEnvironment(
  'GREENVPN_PUBLIC_PRODUCT_BUILD',
  defaultValue: false,
);
const bool kStoreDistributionBuild = bool.fromEnvironment(
  'GREENVPN_STORE_DISTRIBUTION_BUILD',
  defaultValue: false,
);
const bool kFusionUiRequested = bool.fromEnvironment(
  'GREENVPN_FUSION_UI_ENABLED',
  defaultValue: false,
);
const bool kFusionProductionPromotionCandidate = bool.fromEnvironment(
  'GREENVPN_FUSION_PRODUCTION_PROMOTION_CANDIDATE',
  defaultValue: false,
);
const bool kSelfUpdateEnabled = !kStoreDistributionBuild;
const bool kPaidBetaCustomerUi = kPaidBetaBuild && !kPublicProductBuild;
const bool kFusionUiEnabled =
    kFusionUiRequested &&
    (kPaidBetaCustomerUi ||
        (kPublicProductBuild && kFusionProductionPromotionCandidate));
const String kPaidBetaClientMarker = String.fromEnvironment(
  'GREENVPN_PAID_BETA_CLIENT_MARKER',
  defaultValue: 'green-vpn-paid-beta-v1',
);
const String kPaidBetaReleaseChannel = 'paid-beta';
const String kPublicProductClientMarker = String.fromEnvironment(
  'GREENVPN_PUBLIC_PRODUCT_CLIENT_MARKER',
  defaultValue: 'green-vpn-public-product-v1',
);
const String kPublicProductReleaseChannel = 'public-product';
const String kUpdateChannelOverride = String.fromEnvironment(
  'GREENVPN_UPDATE_CHANNEL',
  defaultValue: '',
);
const bool kAwg2PreviewEnabled = bool.fromEnvironment(
  'GREENVPN_AWG2_PREVIEW_ENABLED',
  defaultValue: false,
);
const bool kHysteria2PreviewEnabled = bool.fromEnvironment(
  'GREENVPN_HYSTERIA2_PREVIEW_ENABLED',
  defaultValue: false,
);
const bool kVlessRealityPreviewEnabled = bool.fromEnvironment(
  'GREENVPN_VLESS_REALITY_PREVIEW_ENABLED',
  defaultValue: false,
);
const bool kNaiveHttpsPreviewEnabled = bool.fromEnvironment(
  'GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED',
  defaultValue: false,
);
const bool kDnsttPreviewEnabled = bool.fromEnvironment(
  'GREENVPN_DNSTT_PREVIEW_ENABLED',
  defaultValue: false,
);
const List<String> kSupportedVpnProtocols = <String>[
  'wireguard_udp',
  if (kAwg2PreviewEnabled) 'amneziawg',
  if (kHysteria2PreviewEnabled) 'hysteria2',
  if (kVlessRealityPreviewEnabled) 'vless_reality',
  if (kNaiveHttpsPreviewEnabled) 'naive_https',
  if (kDnsttPreviewEnabled) 'dnstt',
];
const bool kTransportPreviewFallbackEnabled =
    kAwg2PreviewEnabled ||
    kHysteria2PreviewEnabled ||
    kVlessRealityPreviewEnabled ||
    kNaiveHttpsPreviewEnabled ||
    kDnsttPreviewEnabled;
const bool kRewardedAdsRuntimeAvailable = false;
const bool kAdsDisabledBuild =
    kTrialOnlyNoAdsBuild ||
    kPaidBetaBuild ||
    kStoreDistributionBuild ||
    !kRewardedAdsRuntimeAvailable;
const bool kYandexRewardedAdsEnabled = bool.fromEnvironment(
  'GREENVPN_YANDEX_REWARDED_ADS_ENABLED',
  defaultValue: false,
);
const bool kYandexRewardedAdsUseDemo = bool.fromEnvironment(
  'GREENVPN_YANDEX_REWARDED_ADS_DEMO',
  defaultValue: false,
);
const String kYandexRewardedAdUnitId = String.fromEnvironment(
  'GREENVPN_YANDEX_REWARDED_AD_UNIT_ID',
  defaultValue: '',
);
const String kYandexRewardedDemoAdUnitId = 'demo-rewarded-yandex';

const String kApiBaseUrl = String.fromEnvironment(
  'BLUEVPN_API_BASE_URL',
  defaultValue: 'https://api.greenvpn.pro',
);
const String kApiFallbackBaseUrls = String.fromEnvironment(
  'BLUEVPN_API_BASE_URLS',
  defaultValue: 'https://176-113-81-35.sslip.io',
);

const String kBuildMarker = 'bluevpn-safety-runtime-20260428-2355';
const MethodChannel kAndroidPlatformChannel = MethodChannel(
  'green_vpn/android_vpn',
);
const MethodChannel kWindowsWindowChannel = MethodChannel(
  'green_vpn/windows_window',
);

const String kFusionConnectionActionsFlag = 'fusion.connection_actions';
const String kFusionLocationMemoryFlag = 'fusion.location_memory';
const String kFusionConnectionDetailsFlag = 'fusion.connection_details';
const String kFusionWindowsCloseBehaviorFlag = 'fusion.windows_close_behavior';
const String kFusionFriendlyErrorsFlag = 'fusion.friendly_errors';
const Set<String> kFusionRequiredPublicProductFeatures = <String>{
  kFusionConnectionActionsFlag,
  kFusionConnectionDetailsFlag,
};

bool fusionClientFeatureEnabled({
  required String key,
  required Map<String, bool> serverFeatures,
  required bool fusionUiEnabled,
  required bool publicProductBuild,
  required bool productionPromotionCandidate,
  required bool developerSession,
}) {
  if (!fusionUiEnabled) return false;
  if (developerSession) return true;
  if (publicProductBuild &&
      productionPromotionCandidate &&
      kFusionRequiredPublicProductFeatures.contains(key)) {
    return true;
  }
  return serverFeatures[key] == true;
}

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

enum WindowsCloseBehavior {
  minimizeToTray('minimize_to_tray', 'Сворачивать в трей'),
  ask('ask', 'Спрашивать при закрытии'),
  disconnectAndExit('disconnect_and_exit', 'Отключать VPN и выходить');

  const WindowsCloseBehavior(this.code, this.title);

  final String code;
  final String title;

  static WindowsCloseBehavior fromCode(String? value) {
    final clean = (value ?? '').trim().toLowerCase();
    return values.firstWhere(
      (item) => item.code == clean,
      orElse: () => WindowsCloseBehavior.minimizeToTray,
    );
  }
}

void _noopSettingsAction() {}

String greenVpnClientPlatform() {
  if (kIsWeb) return 'web';
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return Platform.operatingSystem;
}

String greenVpnClientPlatformTitle() {
  switch (greenVpnClientPlatform()) {
    case 'android':
      return 'Android';
    case 'windows':
      return 'Windows';
    case 'ios':
      return 'iOS';
    case 'macos':
      return 'macOS';
    case 'linux':
      return 'Linux';
    case 'web':
      return 'Web';
    default:
      return greenVpnClientPlatform();
  }
}

bool greenVpnShouldOpenSavedSessionDirectly({
  required bool hasSession,
  required bool isWeb,
  required bool isAndroid,
  required bool isWindows,
}) {
  return hasSession && !isWeb && (isAndroid || isWindows);
}

bool greenVpnShouldRotateAutoReplacedDevice(Map<String, dynamic>? bootstrap) {
  if (bootstrap == null || bootstrap['reason'] != 'device_disabled') {
    return false;
  }
  final device = bootstrap['device'];
  return device is Map &&
      device['isEnabled'] != true &&
      device['disabledReason'] == 'auto_replaced_by_new_device';
}

bool greenVpnIsDeviceAttachedConflict(String? message) {
  final raw = (message ?? '').trim().toLowerCase();
  if (raw.isEmpty) return false;
  final english =
      raw.contains('device') &&
      raw.contains('attached') &&
      raw.contains('another user');
  final russian =
      raw.contains('устройство') &&
      raw.contains('привязан') &&
      raw.contains('друг') &&
      (raw.contains('аккаунт') || raw.contains('пользовател'));
  return english || russian;
}

bool greenVpnUpdateManifestMatchesCurrentPlatform(
  GreenVpnUpdateManifest manifest,
) {
  final platform = manifest.platform.trim().toLowerCase();
  return platform.isEmpty || platform == greenVpnClientPlatform();
}

bool greenVpnUpdatePromptCanBeDismissed(GreenVpnUpdateManifest manifest) {
  return !manifest.required;
}

String greenVpnUpdateChannel() {
  final override = kUpdateChannelOverride.trim().toLowerCase();
  if (override.isNotEmpty) return override;
  if (kPaidBetaBuild) return kPaidBetaReleaseChannel;
  final version = kAppVersion.toLowerCase();
  if (version.contains('preview') || version.contains('adgate')) {
    return 'preview';
  }
  return 'stable';
}

String greenVpnCatalogChannelForBuild({
  required bool publicProductBuild,
  required bool paidBetaBuild,
  required String updateChannel,
}) {
  if (publicProductBuild) return kPublicProductReleaseChannel;
  if (paidBetaBuild) return kPaidBetaReleaseChannel;
  return updateChannel.trim();
}

String greenVpnCatalogChannel() => greenVpnCatalogChannelForBuild(
  publicProductBuild: kPublicProductBuild,
  paidBetaBuild: kPaidBetaBuild,
  updateChannel: greenVpnUpdateChannel(),
);

String greenVpnNormalizeBaseUrl(String value) {
  var normalized = value.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

List<String> greenVpnApiBaseUrls() {
  final urls = <String>[];
  final seen = <String>{};

  void add(String value) {
    final normalized = greenVpnNormalizeBaseUrl(value);
    if (normalized.isEmpty) return;
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return;
    if (seen.add(normalized)) {
      urls.add(normalized);
    }
  }

  add(kApiBaseUrl);
  for (final item in kApiFallbackBaseUrls.split(',')) {
    add(item);
  }

  return urls.isEmpty ? <String>['https://api.greenvpn.pro'] : urls;
}

int greenVpnIntValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

Map<String, Object?> greenVpnSafeAndroidVpnStatus(Map<String, dynamic> status) {
  final rawRunningTunnels = status['runningTunnels'];
  final runningTunnelNames = rawRunningTunnels is Iterable
      ? rawRunningTunnels.map((item) => item.toString()).toList()
      : <String>[];
  return <String, Object?>{
    'ok': status['ok'] == true,
    'connected': status['connected'] == true,
    'ownTunnelRunning': status['ownTunnelRunning'] == true,
    'systemVpnActive': status['systemVpnActive'] == true,
    'systemVpnActiveWithoutOwnTunnel':
        status['systemVpnActiveWithoutOwnTunnel'] == true,
    'externalVpnActive':
        status['externalVpnActive'] == true ||
        status['systemVpnActiveWithoutOwnTunnel'] == true,
    'state': (status['state'] ?? '').toString(),
    'rxBytes': greenVpnIntValue(status['rxBytes']),
    'txBytes': greenVpnIntValue(status['txBytes']),
    'version': (status['version'] ?? '').toString(),
    'runningTunnels': runningTunnelNames.length,
    'runningTunnelNames': runningTunnelNames,
    'nativeTunnelName': (status['nativeTunnelName'] ?? '').toString(),
    'requestedTunnelName': (status['requestedTunnelName'] ?? '').toString(),
    'lastGreenVpnActive': status['lastGreenVpnActive'] == true,
    'lastGreenVpnActiveAgeMs': greenVpnIntValue(
      status['lastGreenVpnActiveAgeMs'],
    ),
    'ownTunnelSource': (status['ownTunnelSource'] ?? '').toString(),
    'statusError': (status['statusError'] ?? '').toString(),
  };
}

String greenVpnClientDeviceName() {
  if (kIsWeb) return 'Web';
  try {
    final host = Platform.localHostname.trim();
    if (host.isNotEmpty) return host;
  } catch (_) {}
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iPhone';
  return greenVpnClientPlatform();
}

bool get greenVpnHasNativeVpnBackend {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isAndroid;
}

bool greenVpnIsAdRewardRequiredMessage(String? message) {
  if (kAdsDisabledBuild) return false;
  final raw = (message ?? '').toLowerCase();
  return raw.contains('ad_reward_required') ||
      raw.contains('нужно посмотреть рекламу') ||
      raw.contains('реклама перед подключением');
}

bool greenVpnIsInvalidSessionMessage(String? message) {
  final raw = (message ?? '').toLowerCase();
  if (raw.isEmpty) return false;
  if (raw.contains('session expired') ||
      raw.contains('сессия истекла') ||
      raw.contains('сессия недействительна') ||
      raw.contains('некорректная сессия')) {
    return true;
  }
  final has401 =
      raw.contains('401') ||
      raw.contains('unauthorized') ||
      raw.contains('not authenticated');
  if (!has401) return false;
  return raw.contains('некорректный токен') ||
      raw.contains('invalid token') ||
      raw.contains('bad token') ||
      raw.contains('token') ||
      raw.contains('unauthorized') ||
      raw.contains('not authenticated');
}

String greenVpnAdChallengeTokenFromRewardUrl(String rewardUrl) {
  try {
    return Uri.parse(rewardUrl).queryParameters['t']?.trim() ?? '';
  } catch (_) {
    return '';
  }
}

String greenVpnAndroidYandexRewardedAdUnitId(Map<String, dynamic> bootMap) {
  if (!kRewardedAdsRuntimeAvailable) return '';
  if (kAdsDisabledBuild) return '';
  if (kIsWeb || !Platform.isAndroid || !kYandexRewardedAdsEnabled) return '';
  if (kYandexRewardedAdsUseDemo) return kYandexRewardedDemoAdUnitId;

  final adGateRaw = bootMap['adGate'];
  if (adGateRaw is Map) {
    final adGate = Map<String, dynamic>.from(adGateRaw);
    final androidRewardedRaw = adGate['androidRewarded'];
    if (androidRewardedRaw is Map) {
      final androidRewarded = Map<String, dynamic>.from(androidRewardedRaw);
      if (androidRewarded['enabled'] == true) {
        final serverAdUnitId = (androidRewarded['adUnitId'] ?? '')
            .toString()
            .trim();
        if (serverAdUnitId.isNotEmpty) return serverAdUnitId;
      }
    }
  }

  return kYandexRewardedAdUnitId.trim();
}

bool get greenVpnNeedsExternalWireGuardInstall {
  if (kIsWeb) return false;
  return Platform.isWindows;
}

class _LocalConfigCandidate {
  final String path;
  final String content;

  const _LocalConfigCandidate({required this.path, required this.content});
}

class GreenVpnYandexRewardedAds {
  const GreenVpnYandexRewardedAds._();

  static Future<bool> showRewardedAd({
    required String adUnitId,
    required Future<void> Function(String message) log,
    Future<void> Function()? onRewarded,
  }) async {
    await log('rewarded ads are not included in this release');
    return false;
  }
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
        dividerColor: scheme.onSurface.withValues(alpha: isDark ? 0.18 : 0.10),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark ? kBrandDarkSurface : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: scheme.onSurface.withValues(alpha: isDark ? 0.18 : 0.12),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: scheme.onSurface.withValues(alpha: isDark ? 0.18 : 0.12),
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
            disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.10),
            disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.42),
            elevation: 0,
            shadowColor: kBrandPrimary.withValues(alpha: 0.22),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? Colors.white : kBrandPrimaryDeep,
            side: BorderSide(
              color: scheme.onSurface.withValues(alpha: isDark ? 0.22 : 0.16),
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
                : scheme.onSurface.withValues(alpha: isDark ? 0.18 : 0.12),
          ),
          trackOutlineColor: WidgetStatePropertyAll(
            scheme.onSurface.withValues(alpha: isDark ? 0.22 : 0.12),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: kBrandPrimary,
          inactiveTrackColor: kBrandPrimary.withValues(
            alpha: isDark ? 0.20 : 0.16,
          ),
          thumbColor: kBrandPrimary,
          overlayColor: kBrandPrimary.withValues(alpha: 0.14),
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
  final DeviceIdStore _deviceStore = DeviceIdStore();
  final BlueVpnApi _api = const BlueVpnApi(baseUrl: kApiBaseUrl);
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
      setState(
        () => _loadingStage = Platform.isAndroid
            ? 'Проверяем мобильный VPN-слой...'
            : 'Проверяем системный компонент...',
      );
    }
    await _resumeStartupDisconnectIfNeeded();
    if (mounted) {
      setState(() => _loadingStage = 'Проверяем сохранённую сессию...');
    }
    var s = await _sessionStore.read();
    await appendBlueVpnClientLog(
      'bootstrap session=${s == null ? "none" : "present"}',
    );
    if (s == null && !kIsWeb) {
      if (mounted) {
        setState(() => _loadingStage = 'Создаём бесплатный профиль...');
      }
      try {
        final deviceUid = await _deviceStore.getOrCreate();
        final guest = await _api.createGuestSession(
          deviceUid: deviceUid,
          deviceName: greenVpnClientDeviceName(),
          platform: greenVpnClientPlatform(),
          appVersion: kAppVersion,
        );
        if (guest.ok && guest.data != null) {
          s = guest.data!;
          await _sessionStore.write(s);
          await appendBlueVpnClientLog('guest session created and persisted');
        } else {
          await appendBlueVpnClientLog(
            'guest session unavailable message=${guest.message ?? ""}',
          );
        }
      } catch (e) {
        await appendBlueVpnClientLog(
          'guest session bootstrap failed type=${e.runtimeType}',
        );
      }
    }
    if (s != null) {
      await _prepareWindowsFullTunnelConfig();
    }
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
      _openSessionDirectly = greenVpnShouldOpenSavedSessionDirectly(
        hasSession: s != null,
        isWeb: kIsWeb,
        isAndroid: !kIsWeb && Platform.isAndroid,
        isWindows: !kIsWeb && Platform.isWindows,
      );
      _loading = false;
    });
  }

  Future<void> _prepareWindowsFullTunnelConfig() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final prefs = await PrefsStore().readPrefs();
      if (prefs.socialOnlyEnabled) return;

      final configStore = ConfigStore();
      await configStore.ensureBaseSeededFromManagedIfMissing();
      final baseConfig = await configStore.readBaseConfig();
      if (baseConfig == null || baseConfig.trim().isEmpty) return;

      await configStore.writeManagedConfig(
        preserveFullTunnelAllowedIps(baseConfig),
      );
      await appendBlueVpnClientLog(
        'bootstrap prepared Windows native full-tunnel kill switch',
      );
    } catch (e) {
      await appendBlueVpnClientLog(
        'bootstrap Windows full-tunnel preparation failed: $e',
      );
    }
  }

  Future<void> _resumeStartupDisconnectIfNeeded() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      try {
        final status = await WireGuardAndroidBackend.statusSnapshot(
          tunnelName: kTunnelName,
        );
        final connected =
            status['connected'] == true ||
            (status['state'] ?? '').toString().toLowerCase() == 'up';
        await appendBlueVpnClientLog(
          "android startup vpn status connected=$connected state=${status['state'] ?? ""}",
        );
        if (!connected) {
          final backend = VpnBackend.createDefault(tunnelName: kTunnelName);
          final res = await backend.disconnect();
          await appendBlueVpnClientLog(
            'android startup stale vpn disconnect ok=${res.ok} message=${res.message ?? ""}',
          );
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      } catch (e) {
        await appendBlueVpnClientLog(
          'android startup stale vpn cleanup failed=$e',
        );
      }
      return;
    }
    if (!Platform.isWindows) return;
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
    try {
      await _sessionStore.write(s);
      await appendBlueVpnClientLog('session persisted after auth');
    } catch (e, st) {
      await appendBlueVpnClientLog(
        'session persist failed after auth: $e stack=$st',
      );
    }
    if (!mounted) return;
    setState(() {
      _session = s;
      _openSessionDirectly = true;
    });
  }

  Future<void> _onSessionChanged(Session s) => _onAuthSuccess(s);

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
      onSessionChanged: _onSessionChanged,
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
    final mutedColor = textColor.withValues(alpha: 0.62);

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
                  border: Border.all(
                    color: kBrandPrimary.withValues(alpha: 0.14),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kBrandPrimaryDeep.withValues(
                        alpha: isDark ? 0.22 : 0.10,
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
                        backgroundColor: kBrandPrimary.withValues(alpha: 0.10),
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
                      'Обычно это занимает пару секунд. Если система готовит VPN-компонент, приложение само продолжит загрузку.',
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
  final String apiBaseUrl;
  final bool isGuest;
  final bool emailVerified;
  final bool emailConfirmationRequired;

  const Session({
    required this.accessToken,
    required this.email,
    this.apiBaseUrl = '',
    this.isGuest = false,
    this.emailVerified = false,
    this.emailConfirmationRequired = false,
  });

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'email': email,
    'apiBaseUrl': apiBaseUrl,
    'isGuest': isGuest,
    'emailVerified': emailVerified,
    'emailConfirmationRequired': emailConfirmationRequired,
  };

  static Session fromJson(Map<String, dynamic> json) {
    return Session(
      accessToken: (json['accessToken'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      apiBaseUrl: greenVpnNormalizeBaseUrl(
        (json['apiBaseUrl'] ?? '').toString(),
      ),
      isGuest: json['isGuest'] == true,
      emailVerified: json['emailVerified'] == true,
      emailConfirmationRequired: json['emailConfirmationRequired'] == true,
    );
  }

  Session copyWith({
    String? accessToken,
    String? email,
    String? apiBaseUrl,
    bool? isGuest,
    bool? emailVerified,
    bool? emailConfirmationRequired,
  }) {
    return Session(
      accessToken: accessToken ?? this.accessToken,
      email: email ?? this.email,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      isGuest: isGuest ?? this.isGuest,
      emailVerified: emailVerified ?? this.emailVerified,
      emailConfirmationRequired:
          emailConfirmationRequired ?? this.emailConfirmationRequired,
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

  static Future<void> _runIcacls(List<String> arguments) async {
    final result = await Process.run('icacls', arguments, runInShell: true);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Failed to protect local Windows state',
        arguments.isEmpty ? null : arguments.first,
      );
    }
  }

  static Future<void> _prepareProtectedSharedPath(
    String path, {
    required bool directory,
  }) async {
    final userSid = await _currentUserSid();
    if (userSid == null) {
      throw FileSystemException('Windows account SID is unavailable', path);
    }
    final grants = directory
        ? [
            '*$userSid:(OI)(CI)M',
            '*S-1-5-18:(OI)(CI)F',
            '*S-1-5-32-544:(OI)(CI)F',
          ]
        : ['*$userSid:M', '*S-1-5-18:F', '*S-1-5-32-544:F'];

    // Seed trusted access before removing inherited and legacy broad grants.
    await _runIcacls([path, '/grant:r', ...grants]);
    await _runIcacls([path, '/inheritance:r']);
    await _runIcacls([
      path,
      '/remove:g',
      '*S-1-1-0',
      '*S-1-5-11',
      '*S-1-5-32-545',
    ]);
    await _runIcacls([path, '/grant:r', ...grants]);
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
        final dir = Directory('$programData\\$greenVpnProgramDataSubdir');
        if (dir.existsSync()) {
          await _prepareProtectedSharedPath(dir.path, directory: true);
        }
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
      'RemoteSigned',
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
    final nativeProtected = WindowsDpapi.protectString(plain);
    if (nativeProtected != null && nativeProtected.trim().isNotEmpty) {
      return nativeProtected;
    }
    try {
      const script = r'''
Add-Type -AssemblyName System.Security
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
    final nativePlain = WindowsDpapi.unprotectString(encrypted);
    if (nativePlain != null) return nativePlain;
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

  static Future<void> preparePrivateFileForWrite(String path) async {
    if (kIsWeb || !Platform.isWindows || path.trim().isEmpty) return;
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      await Process.run('attrib', [
        '-h',
        '-s',
        '-r',
        file.path,
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
      await _prepareProtectedSharedPath(dir.path, directory: true);
    } catch (_) {}
  }

  static Future<void> prepareSharedStateFile(String path) async {
    if (kIsWeb || !Platform.isWindows || path.trim().isEmpty) return;
    await repairSharedStateFileAcl(path);
  }

  static Future<bool> repairSharedStateFileAcl(String path) async {
    if (kIsWeb || !Platform.isWindows || path.trim().isEmpty) return false;
    try {
      await Process.run('attrib', ['+h', path], runInShell: true);
      await _prepareProtectedSharedPath(path, directory: false);
      return true;
    } catch (_) {
      return false;
    }
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
      await _prepareProtectedSharedPath(dir.path, directory: true);
    } catch (_) {}
  }

  static Future<void> prepareSharedConfigFile(String path) async {
    if (kIsWeb || !Platform.isWindows || path.trim().isEmpty) return;
    try {
      final f = File(path);
      if (!f.existsSync()) return;
      await Process.run('attrib', ['-H', '-S', '-R', path], runInShell: true);
      await _prepareProtectedSharedPath(path, directory: false);
    } catch (_) {}
  }
}

class BlueVpnLocalPaths {
  const BlueVpnLocalPaths._();

  static String sharedStateDirSync() {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return '${Directory.systemTemp.parent.path}${Platform.pathSeparator}files${Platform.pathSeparator}greenvpn_state';
    }
    if (!Platform.isWindows) {
      return '${Directory.systemTemp.path}${Platform.pathSeparator}greenvpn_state';
    }
    return '${greenVpnProgramDataRootSync()}\\state';
  }

  static String userStateDirSync() {
    if (kIsWeb) return '';
    if (!Platform.isWindows) {
      return sharedStateDirSync();
    }
    return '${greenVpnUserDataRootSync()}\\state';
  }

  static Future<String> userStateDir() async {
    if (kIsWeb) return '';
    final dir = Directory(userStateDirSync());
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    if (Platform.isWindows) {
      await WindowsLocalSecurity.hardenPath(dir.path, directory: true);
    }
    return dir.path;
  }

  static Future<String> sharedStateDir() async {
    if (kIsWeb) return '';
    if (!Platform.isWindows) {
      final dir = Directory(sharedStateDirSync());
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir.path;
    }

    final dir = Directory(sharedStateDirSync());
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    await WindowsLocalSecurity.prepareSharedStateDirectory(dir.path);
    return dir.path;
  }

  static Future<List<Directory>> legacyStateDirs() async {
    if (kIsWeb) return const <Directory>[];
    if (Platform.isAndroid) {
      final oldTempState = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}greenvpn_state',
      );
      return oldTempState.existsSync()
          ? <Directory>[oldTempState]
          : const <Directory>[];
    }
    if (!Platform.isWindows) return const <Directory>[];
    if (greenVpnWindowsRuntimeIsIsolated) return const <Directory>[];
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
      addPath('$appData\\GreenVPN\\state');
      addPath('$appData\\GreenVPN');
      addPath('$appData\\BlueVPN');
    }

    final programData = Platform.environment['ProgramData'];
    if (programData != null && programData.trim().isNotEmpty) {
      addPath('$programData\\BlueVPN\\state');
      addPath('$programData\\BlueVPN');
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
      final normal = File('${dir.path}${Platform.pathSeparator}$fileName');
      if (normal.existsSync()) return normal;
      if (Platform.isAndroid) {
        // Older Android builds used a Windows separator, creating a sibling
        // filename that contained a literal backslash.
        final malformedLegacy = File('${dir.path}\\$fileName');
        if (malformedLegacy.existsSync()) return malformedLegacy;
      }
    }
    return null;
  }

  static bool isSharedStatePath(String path) {
    final shared = sharedStateDirSync().toLowerCase();
    if (shared.isEmpty) return false;
    final candidate = path.toLowerCase();
    return candidate == shared ||
        candidate.startsWith('$shared\\') ||
        candidate.startsWith('$shared/');
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
      return await WindowsLocalSecurity.unprotectString(raw) ?? raw;
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
        await WindowsLocalSecurity.prepareSharedStateDirectory(dir.path);
      } else {
        await WindowsLocalSecurity.hardenPath(dir.path, directory: true);
      }
      await WindowsLocalSecurity.preparePrivateFileForWrite(file.path);

      if (encrypted && !kIsWeb && Platform.isWindows) {
        final protected = await WindowsLocalSecurity.protectString(value);
        if (protected != null && protected.trim().isNotEmpty) {
          await file.writeAsString(protected);
          if (BlueVpnLocalPaths.isSharedStatePath(file.path)) {
            await WindowsLocalSecurity.prepareSharedStateFile(file.path);
          } else {
            await WindowsLocalSecurity.hardenPath(file.path);
          }
          return;
        }
      }

      await file.writeAsString(value);
      if (BlueVpnLocalPaths.isSharedStatePath(file.path)) {
        await WindowsLocalSecurity.prepareSharedStateFile(file.path);
      } else {
        await WindowsLocalSecurity.hardenPath(file.path);
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
  static const String _mobileSessionKey = 'greenvpn_mobile_session_v1';

  bool get _usesMobileSecureStore {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  Future<String> _appDirPath() async {
    if (!kIsWeb && Platform.isWindows) {
      return BlueVpnLocalPaths.userStateDir();
    }
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

  Future<String?> _readMobileSession() async {
    if (!_usesMobileSecureStore) return null;
    try {
      return await kAndroidPlatformChannel.invokeMethod<String>('secureRead', {
        'key': _mobileSessionKey,
      });
    } catch (e) {
      await appendBlueVpnClientLog('mobile session secure read failed: $e');
      return null;
    }
  }

  Future<void> _writeMobileSession(String raw) async {
    if (!_usesMobileSecureStore) return;
    try {
      await kAndroidPlatformChannel.invokeMethod<void>('secureWrite', {
        'key': _mobileSessionKey,
        'value': raw,
      });
    } catch (e) {
      await appendBlueVpnClientLog('mobile session secure write failed: $e');
    }
  }

  Future<void> _deleteMobileSession() async {
    if (!_usesMobileSecureStore) return;
    try {
      await kAndroidPlatformChannel.invokeMethod<void>('secureDelete', {
        'key': _mobileSessionKey,
      });
    } catch (e) {
      await appendBlueVpnClientLog('mobile session secure delete failed: $e');
    }
  }

  Future<Session?> read() async {
    if (kIsWeb) return null;
    try {
      var raw = await _readMobileSession();
      final secure = await _secureFile();
      raw ??= await secure.readString();
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
      var s = Session.fromJson(jsonMap);
      if (s.accessToken.isEmpty) return null;
      if (s.apiBaseUrl.isEmpty) {
        final primaryApiBase = greenVpnApiBaseUrls().first;
        s = s.copyWith(apiBaseUrl: primaryApiBase);
        await appendBlueVpnClientLog(
          'session api base migrated to $primaryApiBase',
        );
      }
      BlueVpnApi.rememberSession(s);
      try {
        await write(s);
      } catch (e) {
        // A best-effort storage migration must not invalidate a session that
        // was already read and parsed successfully.
        await appendBlueVpnClientLog(
          'session storage migration skipped type=${e.runtimeType}',
        );
      }
      return s;
    } catch (e) {
      await appendBlueVpnClientLog('session read failed type=${e.runtimeType}');
      return null;
    }
  }

  Future<void> write(Session session) async {
    if (kIsWeb) return;
    BlueVpnApi.rememberSession(session);
    final raw = jsonEncode(session.toJson());
    if (_usesMobileSecureStore) {
      await _writeMobileSession(raw);
      return;
    }
    try {
      final f = await _secureFile();
      await f.writeString(raw);
      return;
    } catch (_) {
      final legacy = await _file();
      await legacy.writeAsString(raw);
      if (BlueVpnLocalPaths.isSharedStatePath(legacy.path)) {
        unawaited(
          WindowsLocalSecurity.prepareSharedStateDirectory(legacy.parent.path),
        );
        unawaited(WindowsLocalSecurity.prepareSharedStateFile(legacy.path));
      } else {
        unawaited(
          WindowsLocalSecurity.hardenPath(legacy.parent.path, directory: true),
        );
        unawaited(WindowsLocalSecurity.hardenPath(legacy.path));
      }
    }
  }

  Future<void> clear() async {
    if (kIsWeb) return;
    BlueVpnApi.forgetAllSessions();
    try {
      await _deleteMobileSession();
      final f = await _file();
      if (f.existsSync()) f.deleteSync();
      await (await _secureFile()).delete();
    } catch (_) {}
  }
}

class DeviceIdStore {
  static const String _mobileDeviceIdKey = 'greenvpn_mobile_device_id_v1';

  bool get _usesMobileSecureStore {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

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

  Future<String?> _readMobileDeviceId() async {
    if (!_usesMobileSecureStore) return null;
    try {
      final raw = await kAndroidPlatformChannel.invokeMethod<String>(
        'secureRead',
        {'key': _mobileDeviceIdKey},
      );
      final id = raw?.trim();
      if (id == null || id.length < 8) return null;
      return id;
    } catch (e) {
      await appendBlueVpnClientLog('mobile device id secure read failed: $e');
      return null;
    }
  }

  Future<void> _writeMobileDeviceId(String id) async {
    if (!_usesMobileSecureStore) return;
    try {
      await kAndroidPlatformChannel.invokeMethod<void>('secureWrite', {
        'key': _mobileDeviceIdKey,
        'value': id,
      });
    } catch (e) {
      await appendBlueVpnClientLog('mobile device id secure write failed: $e');
    }
  }

  Future<void> _deleteMobileDeviceId() async {
    if (!_usesMobileSecureStore) return;
    try {
      await kAndroidPlatformChannel.invokeMethod<void>('secureDelete', {
        'key': _mobileDeviceIdKey,
      });
    } catch (e) {
      await appendBlueVpnClientLog('mobile device id secure delete failed: $e');
    }
  }

  Future<String?> read() async {
    if (kIsWeb) return null;
    try {
      final mobileId = await _readMobileDeviceId();
      if (mobileId != null) return mobileId;

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
      await _writeMobileDeviceId(s);
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
        await _writeMobileDeviceId(s);
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
    if (_usesMobileSecureStore) {
      await _writeMobileDeviceId(id);
      return id;
    }
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
    if (_usesMobileSecureStore) {
      await _writeMobileDeviceId(id);
      return id;
    }
    final f = await _file();
    try {
      await WindowsLocalSecurity.preparePrivateFileForWrite(f.path);
      await f.writeAsString(id);
    } on FileSystemException {
      await WindowsLocalSecurity.prepareSharedStateDirectory(f.parent.path);
      await WindowsLocalSecurity.preparePrivateFileForWrite(f.path);
      await f.writeAsString(id);
    }
    await WindowsLocalSecurity.prepareSharedStateDirectory(f.parent.path);
    await WindowsLocalSecurity.prepareSharedStateFile(f.path);
    return id;
  }

  Future<void> clear() async {
    if (kIsWeb) return;
    await _deleteMobileDeviceId();
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
      await WindowsLocalSecurity.preparePrivateFileForWrite(f.path);
      await f.writeAsString(normalized);
      await WindowsLocalSecurity.prepareSharedStateDirectory(f.parent.path);
      await WindowsLocalSecurity.prepareSharedStateFile(f.path);
      return;
    } on FileSystemException {
      await WindowsLocalSecurity.repairBlueVpnLocalAcls();
      final f = await _file();
      await WindowsLocalSecurity.preparePrivateFileForWrite(f.path);
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

Future<void> _greenVpnAuthLogWriteTail = Future<void>.value();

Future<void> _appendGreenVpnAuthLogLineNow(String line) async {
  final file = File(greenVpnAuthLogPathSync());
  final existedBeforeWrite = file.existsSync();
  var repairedExistingAcl = false;
  try {
    await file.writeAsString(line, mode: FileMode.append);
  } on FileSystemException {
    await WindowsLocalSecurity.prepareSharedStateDirectory(file.parent.path);
    repairedExistingAcl = await WindowsLocalSecurity.repairSharedStateFileAcl(
      file.path,
    );
    await file.writeAsString(line, mode: FileMode.append);
  }
  if (!existedBeforeWrite && !repairedExistingAcl) {
    await WindowsLocalSecurity.prepareSharedStateFile(file.path);
  }
}

Future<void> appendGreenVpnAuthLogLine(String message) {
  if (kIsWeb || !Platform.isWindows) return Future<void>.value();
  final timestamp = DateTime.now().toIso8601String();
  final line = '[$timestamp] $message\n';
  final write = _greenVpnAuthLogWriteTail.then((_) async {
    try {
      await _appendGreenVpnAuthLogLineNow(line);
    } catch (_) {}
  });
  _greenVpnAuthLogWriteTail = write;
  return write;
}

Future<void> appendBlueVpnClientLog(String message) =>
    appendGreenVpnAuthLogLine('UI $message');

Future<bool> isWindowsProcessElevated() async {
  if (kIsWeb || !Platform.isWindows) return false;
  try {
    final res = await Process.run('whoami', ['/groups'], runInShell: true);
    final out = ('${res.stdout ?? ''}\n${res.stderr ?? ''}');
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
    await WindowsLocalSecurity.repairSharedStateFileAcl(
      greenVpnAuthLogPathSync(),
    );

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
    if (installed) return 'Системный компонент установлен.';
    if (!kIsWeb && Platform.isIOS) {
      return 'iOS-версия требует Apple Network Extension. Интерфейс готов, реальное подключение включим после Apple Developer.';
    }
    if (wingetAvailable) {
      return 'Системный компонент не установлен. Green VPN может поставить его автоматически.';
    }
    return 'Системный компонент не установлен. Понадобится ручная установка.';
  }
}

class WireGuardInstallResult {
  final bool ok;
  final String message;

  const WireGuardInstallResult({required this.ok, required this.message});
}

String resolveWireGuardExePathShared() {
  if (!kIsWeb && Platform.isAndroid) return 'Встроенный WireGuard для Android';
  if (!kIsWeb && Platform.isIOS) return 'iOS Network Extension не настроен';
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
  if (!kIsWeb && Platform.isAndroid) {
    return const WireGuardInstallState(
      installed: true,
      wingetAvailable: false,
      exePath: 'Встроенный WireGuard для Android',
    );
  }
  if (!kIsWeb && Platform.isIOS) {
    return const WireGuardInstallState(
      installed: false,
      wingetAvailable: false,
      exePath: 'iOS Network Extension не настроен',
    );
  }
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
  if (kIsWeb) return;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return;
  if (Platform.isAndroid) {
    try {
      await kAndroidPlatformChannel.invokeMethod<Object?>('openUrl', {
        'url': trimmed,
      });
    } catch (_) {}
    return;
  }
  if (!Platform.isWindows) return;
  try {
    await Process.start('cmd', ['/c', 'start', '', trimmed], runInShell: true);
  } catch (_) {}
}

Future<WireGuardInstallResult> installWireGuardForWindows() async {
  if (!kIsWeb && Platform.isAndroid) {
    return const WireGuardInstallResult(
      ok: true,
      message: 'На Android всё уже встроено в Green VPN.',
    );
  }
  if (!kIsWeb && Platform.isIOS) {
    return const WireGuardInstallResult(
      ok: false,
      message:
          'iOS VPN требует Apple Developer и Network Extension entitlement. Интерфейс уже подготовлен.',
    );
  }
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
          'winget не найден. Открыл страницу установки системного компонента в браузере.',
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
      'RemoteSigned',
      '-Command',
      script,
    ], runInShell: true);

    final check = await probeWireGuardInstall();
    if (check.installed) {
      return WireGuardInstallResult(
        ok: true,
        message: 'Системный компонент установлен.',
      );
    }

    final stderr = (res.stderr ?? '').toString().trim();
    return WireGuardInstallResult(
      ok: false,
      message: stderr.isNotEmpty
          ? 'Установка не завершилась: $stderr'
          : 'Системный компонент пока не найден после установки. Нажми "Проверить снова".',
    );
  } catch (e) {
    return WireGuardInstallResult(
      ok: false,
      message: 'Не удалось запустить установку системного компонента: $e',
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
  final List<String> socialOnlyCustomPackages; // Android package names
  final List<String> socialOnlyWindowsApplications; // Absolute .exe paths
  final List<String> socialOnlyWindowsSites; // Normalized host names

  final List<String> selectedApps; // TariffApp.name
  final String trafficPack; // TrafficPack.name
  final double trafficGb;
  final int devices;

  final bool optNoAds;
  final bool optSmartRouting;
  final bool optDedicatedIp;
  final bool optAutoRenew;
  final String lastSuccessfulRouteId;
  final String lastSuccessfulRouteProtocol;
  final String lastSuccessfulRouteAt;
  final List<String> favoriteLocationIds;
  final List<String> recentLocationIds;
  final String vpnPauseUntil;
  final String windowsCloseBehavior;

  const Prefs({
    required this.themeMode,
    required this.language,
    required this.serverId,
    required this.socialOnlyEnabled,
    required this.socialOnlyApps,
    required this.socialOnlyCustomPackages,
    required this.socialOnlyWindowsApplications,
    required this.socialOnlyWindowsSites,
    required this.selectedApps,
    required this.trafficPack,
    required this.trafficGb,
    required this.devices,
    required this.optNoAds,
    required this.optSmartRouting,
    required this.optDedicatedIp,
    required this.optAutoRenew,
    required this.lastSuccessfulRouteId,
    required this.lastSuccessfulRouteProtocol,
    required this.lastSuccessfulRouteAt,
    required this.favoriteLocationIds,
    required this.recentLocationIds,
    required this.vpnPauseUntil,
    required this.windowsCloseBehavior,
  });

  static Prefs defaults() => const Prefs(
    themeMode: 'light',
    language: 'Русский',
    serverId: 'auto',
    socialOnlyEnabled: false,
    socialOnlyApps: ['telegram', 'instagram'],
    socialOnlyCustomPackages: [],
    socialOnlyWindowsApplications: [],
    socialOnlyWindowsSites: [],
    selectedApps: [],
    trafficPack: 'gb20',
    trafficGb: 20,
    devices: 1,
    optNoAds: true,
    optSmartRouting: true,
    optDedicatedIp: false,
    optAutoRenew: false,
    lastSuccessfulRouteId: '',
    lastSuccessfulRouteProtocol: '',
    lastSuccessfulRouteAt: '',
    favoriteLocationIds: [],
    recentLocationIds: [],
    vpnPauseUntil: '',
    windowsCloseBehavior: 'minimize_to_tray',
  );

  Prefs copyWith({
    String? themeMode,
    String? language,
    String? serverId,
    bool? socialOnlyEnabled,
    List<String>? socialOnlyApps,
    List<String>? socialOnlyCustomPackages,
    List<String>? socialOnlyWindowsApplications,
    List<String>? socialOnlyWindowsSites,
    List<String>? selectedApps,
    String? trafficPack,
    double? trafficGb,
    int? devices,
    bool? optNoAds,
    bool? optSmartRouting,
    bool? optDedicatedIp,
    bool? optAutoRenew,
    String? lastSuccessfulRouteId,
    String? lastSuccessfulRouteProtocol,
    String? lastSuccessfulRouteAt,
    List<String>? favoriteLocationIds,
    List<String>? recentLocationIds,
    String? vpnPauseUntil,
    String? windowsCloseBehavior,
  }) {
    return Prefs(
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      serverId: serverId ?? this.serverId,
      socialOnlyEnabled: socialOnlyEnabled ?? this.socialOnlyEnabled,
      socialOnlyApps: socialOnlyApps ?? this.socialOnlyApps,
      socialOnlyCustomPackages:
          socialOnlyCustomPackages ?? this.socialOnlyCustomPackages,
      socialOnlyWindowsApplications:
          socialOnlyWindowsApplications ?? this.socialOnlyWindowsApplications,
      socialOnlyWindowsSites:
          socialOnlyWindowsSites ?? this.socialOnlyWindowsSites,
      selectedApps: selectedApps ?? this.selectedApps,
      trafficPack: trafficPack ?? this.trafficPack,
      trafficGb: trafficGb ?? this.trafficGb,
      devices: devices ?? this.devices,
      optNoAds: optNoAds ?? this.optNoAds,
      optSmartRouting: optSmartRouting ?? this.optSmartRouting,
      optDedicatedIp: optDedicatedIp ?? this.optDedicatedIp,
      optAutoRenew: optAutoRenew ?? this.optAutoRenew,
      lastSuccessfulRouteId:
          lastSuccessfulRouteId ?? this.lastSuccessfulRouteId,
      lastSuccessfulRouteProtocol:
          lastSuccessfulRouteProtocol ?? this.lastSuccessfulRouteProtocol,
      lastSuccessfulRouteAt:
          lastSuccessfulRouteAt ?? this.lastSuccessfulRouteAt,
      favoriteLocationIds: favoriteLocationIds ?? this.favoriteLocationIds,
      recentLocationIds: recentLocationIds ?? this.recentLocationIds,
      vpnPauseUntil: vpnPauseUntil ?? this.vpnPauseUntil,
      windowsCloseBehavior: windowsCloseBehavior ?? this.windowsCloseBehavior,
    );
  }

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'language': language,
    'serverId': serverId,
    'socialOnlyEnabled': socialOnlyEnabled,
    'socialOnlyApps': socialOnlyApps,
    'socialOnlyCustomPackages': socialOnlyCustomPackages,
    'socialOnlyWindowsApplications': socialOnlyWindowsApplications,
    'socialOnlyWindowsSites': socialOnlyWindowsSites,
    'selectedApps': selectedApps,
    'trafficPack': trafficPack,
    'trafficGb': trafficGb,
    'devices': devices,
    'optNoAds': optNoAds,
    'optSmartRouting': optSmartRouting,
    'optDedicatedIp': optDedicatedIp,
    'optAutoRenew': optAutoRenew,
    'lastSuccessfulRouteId': lastSuccessfulRouteId,
    'lastSuccessfulRouteProtocol': lastSuccessfulRouteProtocol,
    'lastSuccessfulRouteAt': lastSuccessfulRouteAt,
    'favoriteLocationIds': favoriteLocationIds,
    'recentLocationIds': recentLocationIds,
    'vpnPauseUntil': vpnPauseUntil,
    'windowsCloseBehavior': windowsCloseBehavior,
  };

  static Prefs fromJson(Map<String, dynamic> map) {
    final d = Prefs.defaults();

    String s0(String k, String def) {
      final v = map[k];
      if (v == null) return def;
      final s = v.toString().trim();
      return s.isEmpty ? def : s;
    }

    bool b(String k, bool def) {
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

    int i(String k, int def) {
      final v = map[k];
      if (v is int) return v;
      if (v is num) return v.round();
      if (v is String) return int.tryParse(v) ?? def;
      return def;
    }

    double d0(String k, double def) {
      final v = map[k];
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? def;
      return def;
    }

    List<String> ls(String k, List<String> def) {
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

    final theme = s0('themeMode', d.themeMode);
    final safeTheme = (theme == 'dark' || theme == 'light')
        ? theme
        : d.themeMode;

    return d.copyWith(
      themeMode: safeTheme,
      language: s0('language', d.language),
      serverId: s0('serverId', d.serverId),
      socialOnlyEnabled: b('socialOnlyEnabled', d.socialOnlyEnabled),
      socialOnlyApps: ls('socialOnlyApps', d.socialOnlyApps),
      socialOnlyCustomPackages: ls(
        'socialOnlyCustomPackages',
        d.socialOnlyCustomPackages,
      ),
      socialOnlyWindowsApplications: ls(
        'socialOnlyWindowsApplications',
        d.socialOnlyWindowsApplications,
      ),
      socialOnlyWindowsSites: ls(
        'socialOnlyWindowsSites',
        d.socialOnlyWindowsSites,
      ),
      selectedApps: ls('selectedApps', d.selectedApps),
      trafficPack: s0('trafficPack', d.trafficPack),
      trafficGb: d0('trafficGb', d.trafficGb).clamp(1.0, 800.0),
      devices: i('devices', d.devices).clamp(1, 5),
      optNoAds: b('optNoAds', d.optNoAds),
      optSmartRouting: b('optSmartRouting', d.optSmartRouting),
      optDedicatedIp: b('optDedicatedIp', d.optDedicatedIp),
      optAutoRenew: b('optAutoRenew', d.optAutoRenew),
      lastSuccessfulRouteId: s0(
        'lastSuccessfulRouteId',
        d.lastSuccessfulRouteId,
      ),
      lastSuccessfulRouteProtocol: s0(
        'lastSuccessfulRouteProtocol',
        d.lastSuccessfulRouteProtocol,
      ),
      lastSuccessfulRouteAt: s0(
        'lastSuccessfulRouteAt',
        d.lastSuccessfulRouteAt,
      ),
      favoriteLocationIds: ls('favoriteLocationIds', d.favoriteLocationIds),
      recentLocationIds: ls('recentLocationIds', d.recentLocationIds),
      vpnPauseUntil: s0('vpnPauseUntil', d.vpnPauseUntil),
      windowsCloseBehavior: WindowsCloseBehavior.fromCode(
        s0('windowsCloseBehavior', d.windowsCloseBehavior),
      ).code,
    );
  }
}

class PrefsStore {
  Future<String> _appDirPath() async {
    return BlueVpnLocalPaths.userStateDir();
  }

  Future<File> _file() async {
    final dir = await _appDirPath();
    return File('$dir${Platform.pathSeparator}prefs.json');
  }

  Future<Map<String, dynamic>> _readMap() async {
    if (kIsWeb) return <String, dynamic>{};
    try {
      final f = await _file();
      String? raw;
      var readFromLegacy = false;
      if (f.existsSync()) {
        raw = await f.readAsString();
      } else {
        final legacy = await BlueVpnLocalPaths.firstLegacyFile('prefs.json');
        readFromLegacy = legacy != null;
        raw = await legacy?.readAsString();
      }
      if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        if (readFromLegacy) await _writeMap(decoded);
        return decoded;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeMap(Map<String, dynamic> map) async {
    if (kIsWeb) return;
    final f = await _file();
    if (Platform.isWindows) {
      await WindowsLocalSecurity.preparePrivateFileForWrite(f.path);
    }
    await f.writeAsString(jsonEncode(map));
    if (Platform.isWindows) {
      await WindowsLocalSecurity.hardenPath(f.path);
    }
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

class WindowsStandbyProofStore {
  Future<File> _file() async {
    final dir = await BlueVpnLocalPaths.userStateDir();
    return File('$dir${Platform.pathSeparator}standby_routes.json');
  }

  Future<Map<String, GreenVpnStandbyRouteProof>> read() async {
    if (kIsWeb || !Platform.isWindows) {
      return <String, GreenVpnStandbyRouteProof>{};
    }
    try {
      final file = await _file();
      if (!file.existsSync()) return <String, GreenVpnStandbyRouteProof>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['schema'] != 1) {
        return <String, GreenVpnStandbyRouteProof>{};
      }
      final rawProofs = decoded['proofs'];
      if (rawProofs is! List) return <String, GreenVpnStandbyRouteProof>{};
      final proofs = <String, GreenVpnStandbyRouteProof>{};
      for (final raw in rawProofs.take(64)) {
        if (raw is! Map) continue;
        final proof = GreenVpnStandbyRouteProof.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (proof != null && proof.key.isNotEmpty) {
          proofs[proof.key] = proof;
        }
      }
      return proofs;
    } catch (_) {
      return <String, GreenVpnStandbyRouteProof>{};
    }
  }

  Future<void> write(Map<String, GreenVpnStandbyRouteProof> proofs) async {
    if (kIsWeb || !Platform.isWindows) return;
    final file = await _file();
    final temp = File('${file.path}.tmp');
    final ordered = proofs.values.toList()
      ..sort((left, right) => right.verifiedAt.compareTo(left.verifiedAt));
    await WindowsLocalSecurity.preparePrivateFileForWrite(temp.path);
    await temp.writeAsString(
      jsonEncode(<String, dynamic>{
        'schema': 1,
        'proofs': ordered.take(64).map((proof) => proof.toJson()).toList(),
      }),
      flush: true,
    );
    if (file.existsSync()) {
      await WindowsLocalSecurity.preparePrivateFileForWrite(file.path);
      await file.delete();
    }
    await temp.rename(file.path);
    await WindowsLocalSecurity.hardenPath(file.path);
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

class WireGuardConfigResponse {
  final String configText;
  final String protocol;
  final String serverId;
  final String serverName;
  final Map<String, dynamic> endpointAssignment;
  final Map<String, dynamic> adGate;

  const WireGuardConfigResponse({
    required this.configText,
    required this.protocol,
    required this.serverId,
    required this.serverName,
    required this.endpointAssignment,
    required this.adGate,
  });

  static WireGuardConfigResponse fromJson(Map<String, dynamic> json) {
    final assignment = json['endpointAssignment'];
    final server = json['server'];
    final serverMap = server is Map
        ? Map<String, dynamic>.from(server)
        : const <String, dynamic>{};
    final assignmentMap = assignment is Map
        ? Map<String, dynamic>.from(assignment)
        : const <String, dynamic>{};
    final adGateRaw = json['adGate'];
    final adGateMap = adGateRaw is Map
        ? Map<String, dynamic>.from(adGateRaw)
        : const <String, dynamic>{};
    final id =
        (json['serverId'] ?? serverMap['id'] ?? assignmentMap['serverId'] ?? '')
            .toString()
            .trim();
    final name = (serverMap['name'] ?? serverMap['title'] ?? id)
        .toString()
        .trim();
    return WireGuardConfigResponse(
      configText: (json['configText'] ?? json['config'] ?? '').toString(),
      protocol: (json['protocol'] ?? 'wireguard_udp')
          .toString()
          .trim()
          .toLowerCase(),
      serverId: id,
      serverName: name,
      endpointAssignment: assignmentMap,
      adGate: adGateMap,
    );
  }
}

class GreenVpnUpdateManifest {
  final String platform;
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
    required this.platform,
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
      platform: (json['platform'] ?? greenVpnClientPlatform()).toString(),
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

  return greenVpnPublicErrorMessage(rawError: text, fallback: fallback);
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

typedef GreenVpnEndpointLookup =
    Future<List<InternetAddress>> Function(String host);

Future<String> resolveWireGuardEndpointToIpv4(
  String rawConfig, {
  String? fallbackIpv4,
  GreenVpnEndpointLookup? lookup,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final endpointMatch = RegExp(
    r'(^\s*Endpoint\s*=\s*)([^\s:\[\]]+)(:(\d{1,5})\s*$)',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(rawConfig);
  if (endpointMatch == null) {
    throw const FormatException(
      'WireGuard endpoint must contain a host and port.',
    );
  }

  final host = endpointMatch.group(2)!.trim();
  final port = int.tryParse(endpointMatch.group(4)!);
  if (port == null || port < 1 || port > 65535) {
    throw const FormatException('WireGuard endpoint port is invalid.');
  }

  final literal = InternetAddress.tryParse(host);
  if (literal != null) {
    if (literal.type != InternetAddressType.IPv4) {
      throw const FormatException('WireGuard endpoint must resolve to IPv4.');
    }
    return rawConfig;
  }

  String? resolvedIpv4;
  final fallback = InternetAddress.tryParse((fallbackIpv4 ?? '').trim());
  if (fallback?.type == InternetAddressType.IPv4) {
    resolvedIpv4 = fallback!.address;
  } else {
    final resolver =
        lookup ??
        (String value) =>
            InternetAddress.lookup(value, type: InternetAddressType.IPv4);
    final addresses = await resolver(host).timeout(timeout);
    for (final address in addresses) {
      if (address.type == InternetAddressType.IPv4) {
        resolvedIpv4 = address.address;
        break;
      }
    }
  }
  if (resolvedIpv4 == null) {
    throw SocketException('WireGuard endpoint has no IPv4 address: $host');
  }

  return rawConfig.replaceRange(
    endpointMatch.start,
    endpointMatch.end,
    '${endpointMatch.group(1)}$resolvedIpv4${endpointMatch.group(3)}',
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

List<String> readAllowedIpsFromConfig(String configText) {
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

String? readWireGuardConfigField(String configText, String fieldName) {
  final escapedField = RegExp.escape(fieldName);
  final match = RegExp(
    '^\\s*$escapedField\\s*=\\s*(.+?)\\s*\$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(configText);
  return match?.group(1)?.trim();
}

List<String> resolveFullTunnelAllowedIps(
  List<String> baseAllowedIps, {
  required bool windows,
}) {
  if (windows) {
    // WireGuard for Windows enables its DNS/IPv6 leak-prevention firewall only
    // for an exact /0 route. Split-default /1 routes do not enable it.
    return const ['0.0.0.0/0', '::/0'];
  }
  return baseAllowedIps.isEmpty
      ? const ['0.0.0.0/1', '128.0.0.0/1']
      : baseAllowedIps;
}

String preserveFullTunnelAllowedIps(String baseConfig) {
  final allowedIps = resolveFullTunnelAllowedIps(
    readAllowedIpsFromConfig(baseConfig),
    windows: !kIsWeb && Platform.isWindows,
  );
  return replaceAllowedIpsInConfig(baseConfig, allowedIps);
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

  String _buildManagedConfig(String baseConfig) {
    return preserveFullTunnelAllowedIps(baseConfig);
  }

  Future<void> _writeProvisionedConfig(String rawConfig) async {
    var preparedConfig = rawConfig;
    if (!kIsWeb && Platform.isWindows) {
      preparedConfig = await resolveWireGuardEndpointToIpv4(preparedConfig);
    }
    await cfg.writeManagedConfig(_buildManagedConfig(preparedConfig));
    try {
      await cfg.writeBaseConfig(preparedConfig);
    } catch (e) {
      await appendBlueVpnClientLog(
        'config write skipped path=${cfg.baseConfigPath} kind=base-auth error=$e',
      );
    }
  }

  Future<bool> _reuseLocalConfigIfPresent(String reason) async {
    if (greenVpnIsFreeQuotaExhaustedMessage(reason)) {
      await appendBlueVpnClientLog(
        'auth local config fallback blocked by free quota',
      );
      return false;
    }
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
    if (kIsWeb || !greenVpnHasNativeVpnBackend) {
      return const ProvisioningWarmupResult(ok: true);
    }
    if (session.accessToken == 'dev-token') {
      return const ProvisioningWarmupResult(ok: true);
    }

    var deviceId = await deviceStore.getOrCreate();
    var boot = await api.bootstrapClient(
      accessToken: session.accessToken,
      deviceId: deviceId,
      deviceName: greenVpnClientDeviceName(),
      platform: greenVpnClientPlatform(),
      appVersion: kAppVersion,
    );

    if (greenVpnIsDeviceAttachedConflict(boot.message)) {
      deviceId = await deviceStore.rotate();
      boot = await api.bootstrapClient(
        accessToken: session.accessToken,
        deviceId: deviceId,
        deviceName: greenVpnClientDeviceName(),
        platform: greenVpnClientPlatform(),
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

    if (!cfgRes.ok ||
        cfgRes.data == null ||
        cfgRes.data!.configText.trim().isEmpty) {
      if (greenVpnIsFreeQuotaExhaustedMessage(cfgRes.message)) {
        await appendBlueVpnClientLog(
          'auth warmup config fetch blocked by free quota',
        );
        return ProvisioningWarmupResult(ok: true, planName: planName);
      }
      if (greenVpnIsAdRewardRequiredMessage(cfgRes.message)) {
        await appendBlueVpnClientLog(
          'auth warmup config fetch blocked by ad gate',
        );
        return ProvisioningWarmupResult(ok: true, planName: planName);
      }
      final reused = await _reuseLocalConfigIfPresent(cfgRes.message ?? '');
      if (reused) {
        return ProvisioningWarmupResult(ok: true, planName: planName);
      }
      return ProvisioningWarmupResult(
        ok: false,
        message: cfgRes.message ?? 'Не удалось подготовить VPN-подключение.',
      );
    }

    await _writeProvisionedConfig(
      normalizeProvisionedEndpoint(cfgRes.data!.configText),
    );
    return ProvisioningWarmupResult(ok: true, planName: planName);
  }
}

class GreenVpnHttpStatusException implements Exception {
  final int statusCode;
  final String body;
  final Uri? uri;
  final String? message;

  const GreenVpnHttpStatusException({
    required this.statusCode,
    required this.body,
    this.uri,
    this.message,
  });

  bool get isRetriable =>
      statusCode == HttpStatus.requestTimeout || statusCode >= 500;

  @override
  String toString() {
    final text = (message ?? 'HTTP status $statusCode: $body').trim();
    if (uri == null) return text;
    return '$text, uri = $uri';
  }
}

String greenVpnApiUserMessage(
  Object error, {
  String fallback = 'Не удалось связаться с сервисом.',
}) {
  if (error is GreenVpnHttpStatusException) {
    return greenVpnPublicErrorMessage(
      rawError: error.toString(),
      responseBody: error.body,
      statusCode: error.statusCode,
      fallback: fallback,
    );
  }
  return greenVpnPublicErrorMessage(
    rawError: error.toString(),
    fallback: fallback,
  );
}

class BlueVpnApi {
  final String baseUrl;
  final List<String> fallbackBaseUrls;
  const BlueVpnApi({required this.baseUrl, this.fallbackBaseUrls = const []});

  static const int _wslRelayPort = 18000;
  static Uri? _cachedWslRelayUri;
  static Future<Uri?>? _wslRelayStartFuture;
  static Process? _wslRelayProcess;
  static const Duration _apiBaseFailureCooldown = Duration(minutes: 3);
  static final Map<String, DateTime> _apiBaseCooldownUntil =
      <String, DateTime>{};
  static String? _lastSuccessfulApiBaseUrl;
  static String? _pendingAuthApiBaseUrl;
  static final Map<String, String> _sessionApiBaseByAccessToken =
      <String, String>{};

  static String? _normalizeApiBaseUrl(String? value) {
    final normalized = greenVpnNormalizeBaseUrl(value ?? '');
    if (normalized.isEmpty) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return null;
    return normalized;
  }

  static void rememberSession(Session session) {
    final token = session.accessToken.trim();
    final apiBase = _normalizeApiBaseUrl(session.apiBaseUrl);
    if (token.isEmpty || apiBase == null) return;
    _sessionApiBaseByAccessToken[token] = apiBase;
    _lastSuccessfulApiBaseUrl = apiBase;
  }

  static void forgetAllSessions() {
    _sessionApiBaseByAccessToken.clear();
    _pendingAuthApiBaseUrl = null;
  }

  Uri _uFor(String resolvedBaseUrl, String path) =>
      Uri.parse('$resolvedBaseUrl$path');

  String _primaryBaseUrl() {
    final urls = _apiBaseUrls();
    return urls.isEmpty ? greenVpnNormalizeBaseUrl(baseUrl) : urls.first;
  }

  List<String> _apiBaseUrls() {
    final urls = <String>[];
    final seen = <String>{};

    void add(String value) {
      final normalized = greenVpnNormalizeBaseUrl(value);
      if (normalized.isEmpty) return;
      final uri = Uri.tryParse(normalized);
      if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return;
      if (seen.add(normalized)) urls.add(normalized);
    }

    add(baseUrl);
    for (final item in greenVpnApiBaseUrls()) {
      add(item);
    }
    for (final item in fallbackBaseUrls) {
      add(item);
    }

    return urls;
  }

  HttpClient _client({bool direct = true}) {
    final client = HttpClient();
    if (direct) {
      client.findProxy = (_) => 'DIRECT';
    }
    client.connectionTimeout = const Duration(seconds: 8);
    return client;
  }

  HttpClient _probeClient() {
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(milliseconds: 1200);
    return client;
  }

  bool _isRetriableNetworkError(Object error) {
    if (error is GreenVpnHttpStatusException) {
      return error.isRetriable;
    }
    return error is SocketException ||
        error is HttpException ||
        error is TimeoutException;
  }

  bool _isApiBaseCoolingDown(String baseUrl) {
    final until = _apiBaseCooldownUntil[baseUrl];
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _apiBaseCooldownUntil.remove(baseUrl);
    return false;
  }

  void _markApiBaseFailure(
    String baseUrl,
    Object error, {
    required bool retriable,
  }) {
    if (!retriable || _apiBaseUrls().length <= 1) return;
    _apiBaseCooldownUntil[baseUrl] = DateTime.now().add(
      _apiBaseFailureCooldown,
    );
  }

  void _markApiBaseSuccess(String baseUrl) {
    _apiBaseCooldownUntil.remove(baseUrl);
    _lastSuccessfulApiBaseUrl = baseUrl;
  }

  String? _preferredApiBaseUrlForBearer(String? bearerToken) {
    final token = (bearerToken ?? '').trim();
    if (token.isEmpty) return null;
    final remembered = _normalizeApiBaseUrl(
      _sessionApiBaseByAccessToken[token],
    );
    if (remembered == null) return null;
    return _apiBaseUrls().contains(remembered) ? remembered : null;
  }

  List<String> _orderedApiBaseUrlsForRetry({String? preferredBaseUrl}) {
    final urls = _apiBaseUrls();
    if (urls.length <= 1) return urls;

    final ordered = <String>[];
    final seen = <String>{};

    void add(String value) {
      if (seen.add(value)) ordered.add(value);
    }

    final preferred = _normalizeApiBaseUrl(preferredBaseUrl);
    if (preferred != null && urls.contains(preferred)) {
      add(preferred);
    }

    final lastGood = _lastSuccessfulApiBaseUrl;
    if (lastGood != null &&
        urls.contains(lastGood) &&
        lastGood != preferred &&
        !_isApiBaseCoolingDown(lastGood)) {
      add(lastGood);
    }

    for (final url in urls) {
      if (!_isApiBaseCoolingDown(url)) add(url);
    }
    for (final url in urls) {
      add(url);
    }

    return ordered;
  }

  Future<String?> _quickHealthyApiBaseUrl(List<String> candidates) async {
    final liveCandidates = candidates
        .where((baseUrl) => !_isApiBaseCoolingDown(baseUrl))
        .toList(growable: false);
    if (liveCandidates.length <= 1) return null;

    final completer = Completer<String?>();
    var pending = liveCandidates.length;

    Future<void> probe(String baseUrl) async {
      final client = _probeClient();
      try {
        final req = await client.getUrl(_uFor(baseUrl, '/healthz'));
        final res = await req.close().timeout(
          const Duration(milliseconds: 1600),
        );
        await res.drain<void>().timeout(const Duration(milliseconds: 500));
        if (res.statusCode >= 200 &&
            res.statusCode < 300 &&
            !completer.isCompleted) {
          completer.complete(baseUrl);
        }
      } catch (_) {
        // The normal HTTP retry path will produce the user-visible error.
      } finally {
        client.close(force: true);
        pending -= 1;
        if (pending <= 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }
    }

    for (final baseUrl in liveCandidates) {
      unawaited(probe(baseUrl));
    }

    return completer.future.timeout(
      const Duration(milliseconds: 1800),
      onTimeout: () => null,
    );
  }

  bool _isWindowsDevBackend() {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final uri = Uri.parse(_primaryBaseUrl());
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
      final uri = Uri.parse(_primaryBaseUrl());
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

    final primaryUri = Uri.parse(_primaryBaseUrl());
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
    action, {
    String? preferredBaseUrl,
    bool allowApiBaseFailover = true,
    Duration? totalBudget,
  }) async {
    Object? lastError;
    final retryWatch = Stopwatch()..start();
    final normalizedPreferredBaseUrl = _normalizeApiBaseUrl(preferredBaseUrl);

    Future<T> runAction(
      HttpClient client,
      bool direct,
      String resolvedBaseUrl,
    ) {
      final budget = totalBudget;
      if (budget == null) return action(client, direct, resolvedBaseUrl);
      final remaining = budget - retryWatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('HTTP retry budget exceeded', budget);
      }
      return action(client, direct, resolvedBaseUrl).timeout(remaining);
    }

    final preferredRelay = await _preferredRelayUriIfNeeded();
    if (preferredRelay != null) {
      final client = _client(direct: false);
      try {
        await _authLog('HTTP preferred WSL relay base=$preferredRelay');
        return await runAction(client, false, preferredRelay.toString());
      } catch (e) {
        lastError = e;
      } finally {
        client.close(force: true);
      }
    }

    final initialCandidates = allowApiBaseFailover
        ? _orderedApiBaseUrlsForRetry(
            preferredBaseUrl: normalizedPreferredBaseUrl,
          )
        : <String>[normalizedPreferredBaseUrl ?? _primaryBaseUrl()];
    final preferredHealthyBase =
        allowApiBaseFailover && normalizedPreferredBaseUrl == null
        ? await _quickHealthyApiBaseUrl(initialCandidates)
        : null;
    final retryBases = <String>[];
    if (preferredHealthyBase != null) {
      retryBases.add(preferredHealthyBase);
    }
    retryBases.addAll(initialCandidates);
    final seenRetryBases = <String>{};

    for (final candidateBaseUrl in retryBases) {
      if (!seenRetryBases.add(candidateBaseUrl)) continue;
      for (final direct in const [true, false]) {
        final client = _client(direct: direct);
        try {
          final result = await runAction(client, direct, candidateBaseUrl);
          _markApiBaseSuccess(candidateBaseUrl);
          return result;
        } catch (e) {
          lastError = e;
          final retriable = _isRetriableNetworkError(e);
          _markApiBaseFailure(candidateBaseUrl, e, retriable: retriable);
          if (!retriable) {
            if (normalizedPreferredBaseUrl != null) {
              rethrow;
            }
            break;
          }
          await _authLog(
            'HTTP retry candidate failed base=$candidateBaseUrl route=${direct ? 'direct' : 'system'} error=$e',
          );
          if (_apiBaseUrls().length > 1) {
            break;
          }
        } finally {
          client.close(force: true);
        }
      }
    }

    if (lastError != null && _isRetriableNetworkError(lastError)) {
      final relayUri = await _ensureWslRelayUri();
      if (relayUri != null) {
        final client = _client(direct: false);
        try {
          await _authLog('HTTP retry via WSL relay base=$relayUri');
          return await runAction(client, false, relayUri.toString());
        } finally {
          client.close(force: true);
        }
      }
    }

    throw lastError ?? Exception('Unknown HTTP retry failure');
  }

  Future<void> _authLog(String s) => appendGreenVpnAuthLogLine(s);

  Future<String> _tcpPreflight(String path) async {
    final urls = _orderedApiBaseUrlsForRetry();
    final baseUrl = urls.isEmpty ? _primaryBaseUrl() : urls.first;
    final uri = _uFor(baseUrl, path);
    try {
      final socket = await Socket.connect(
        uri.host,
        uri.port,
        timeout: const Duration(seconds: 5),
      );
      final remote = '${socket.remoteAddress.address}:${socket.remotePort}';
      await socket.close();
      return 'tcp=ok remote=$remote';
    } catch (e) {
      return 'tcp=fail error=$e';
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

  Future<ApiResult<Session>> createGuestSession({
    required String deviceUid,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    return _postSession('/api/v1/auth/guest', {
      'deviceUid': deviceUid,
      'deviceName': ?deviceName,
      'platform': ?platform,
      'appVersion': ?appVersion,
      if (kPaidBetaCustomerUi) 'clientMarker': kPaidBetaClientMarker,
      if (kPaidBetaCustomerUi) 'releaseChannel': kPaidBetaReleaseChannel,
      if (kPublicProductBuild) 'clientMarker': kPublicProductClientMarker,
      if (kPublicProductBuild) 'releaseChannel': kPublicProductReleaseChannel,
    });
  }

  Future<ApiResult<Map<String, dynamic>>> startEmailCodeAuth({
    required String email,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/auth/email/code/start',
      payload: {'email': email},
      onSuccessBaseUrl: (baseUrl) {
        _pendingAuthApiBaseUrl = _normalizeApiBaseUrl(baseUrl);
      },
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
    return _postSession(
      '/api/v1/auth/email/code/verify',
      {
        'email': email,
        'code': code,
        'deviceUid': ?deviceUid,
        'deviceName': ?deviceName,
        'platform': ?platform,
        'appVersion': ?appVersion,
      },
      preferredApiBaseUrl: _pendingAuthApiBaseUrl,
    );
  }

  Future<ApiResult<Map<String, dynamic>>> startAuthChallenge({
    required String method,
    String? email,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/auth/challenge/start',
      payload: {'method': method, 'email': ?email},
      onSuccessBaseUrl: (baseUrl) {
        _pendingAuthApiBaseUrl = _normalizeApiBaseUrl(baseUrl);
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
    String? email,
    String? deviceUid,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    return _postSession('/api/v1/auth/challenge/verify', {
      'method': method,
      'code': code,
      'email': ?email,
      'deviceUid': ?deviceUid,
      'deviceName': ?deviceName,
      'platform': ?platform,
      'appVersion': ?appVersion,
    }, preferredApiBaseUrl: _pendingAuthApiBaseUrl);
  }

  Future<ApiResult<Map<String, dynamic>>> startCheckoutEmail({
    required String accessToken,
    required String email,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/auth/checkout/email/start',
      bearerToken: accessToken,
      preferredBaseUrl: _primaryBaseUrl(),
      allowApiBaseFailover: false,
      payload: {'email': email},
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err(
        'Некорректный ответ auth/checkout/email/start.',
      );
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Session>> verifyCheckoutEmail({
    required String accessToken,
    required String email,
    required String code,
    String? deviceUid,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    return _postSession(
      '/api/v1/auth/checkout/email/verify',
      {
        'email': email,
        'code': code,
        'deviceUid': ?deviceUid,
        'deviceName': ?deviceName,
        'platform': ?platform,
        'appVersion': ?appVersion,
        if (kPaidBetaCustomerUi) 'clientMarker': kPaidBetaClientMarker,
        if (kPaidBetaCustomerUi) 'releaseChannel': kPaidBetaReleaseChannel,
        if (kPublicProductBuild) 'clientMarker': kPublicProductClientMarker,
        if (kPublicProductBuild) 'releaseChannel': kPublicProductReleaseChannel,
      },
      preferredApiBaseUrl: _primaryBaseUrl(),
      bearerToken: accessToken,
      allowApiBaseFailover: false,
    );
  }

  Future<ApiResult<Map<String, dynamic>>> startAccessEmail({
    required String accessToken,
    required String email,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/auth/access/email/start',
      bearerToken: accessToken,
      payload: {'email': email},
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ auth/access/email/start.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Session>> verifyAccessEmail({
    required String accessToken,
    required String email,
    required String code,
    String? deviceUid,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    return _postSession(
      '/api/v1/auth/access/email/verify',
      {
        'email': email,
        'code': code,
        'deviceUid': ?deviceUid,
        'deviceName': ?deviceName,
        'platform': ?platform,
        'appVersion': ?appVersion,
      },
      preferredApiBaseUrl: _preferredApiBaseUrlForBearer(accessToken),
      bearerToken: accessToken,
    );
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
        final res = await req.close().timeout(const Duration(seconds: 8));
        final body = await utf8
            .decodeStream(res)
            .timeout(const Duration(seconds: 5));

        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw GreenVpnHttpStatusException(
            statusCode: res.statusCode,
            body: body,
            uri: uri,
            message: 'Ошибка сервера (${res.statusCode}): $body',
          );
        }
        return body;
      }, preferredBaseUrl: _preferredApiBaseUrlForBearer(accessToken));

      {
        final jsonMap = Map<String, dynamic>.from(jsonDecode(body) as Map);
        final p = (jsonMap['planName'] ?? jsonMap['planCode'] ?? 'Base')
            .toString();
        return ApiResult.ok(p.isEmpty ? 'Base' : p);
      }
    } catch (e) {
      return ApiResult.err(greenVpnApiUserMessage(e));
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
    final query = <String, String>{
      if (kPublicProductBuild) 'clientMarker': kPublicProductClientMarker,
      if (kPublicProductBuild) 'releaseChannel': kPublicProductReleaseChannel,
      if (kPaidBetaCustomerUi) 'clientMarker': kPaidBetaClientMarker,
      if (kPaidBetaCustomerUi) 'releaseChannel': kPaidBetaReleaseChannel,
    };
    final path = Uri(
      path: '/api/v1/catalog/tariffs',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    final res = await _jsonRequest(
      method: 'GET',
      path: path,
      preferredBaseUrl: _primaryBaseUrl(),
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

  Future<ApiResult<Map<String, dynamic>>> fetchServerCatalog({
    String? releaseChannel,
  }) async {
    final channel = (releaseChannel ?? greenVpnCatalogChannel()).trim();
    final path =
        '/api/v1/catalog/servers?channel=${Uri.encodeQueryComponent(channel)}'
        '&currentVersion=${Uri.encodeQueryComponent(kAppVersion)}';
    final res = await _jsonRequest(method: 'GET', path: path);
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
    return fetchUpdateManifest(
      platform: 'windows',
      currentVersion: currentVersion,
      clientId: clientId,
    );
  }

  Future<ApiResult<GreenVpnUpdateManifest>> fetchUpdateManifest({
    required String platform,
    required String currentVersion,
    String channel = 'stable',
    String? clientId,
  }) async {
    final query = <String, String>{
      'platform': platform,
      'channel': channel,
      'currentVersion': currentVersion,
      if ((clientId ?? '').trim().isNotEmpty) 'clientId': clientId!.trim(),
    };
    final path = Uri(
      path: '/api/v1/updates/manifest',
      queryParameters: query,
    ).toString();
    final res = await _jsonRequest(method: 'GET', path: path);
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ updates/manifest.');
    }
    final map = Map<String, dynamic>.from(res.data as Map);
    final rawManifest = map['manifest'];
    final manifest = rawManifest is Map
        ? Map<String, dynamic>.from(rawManifest)
        : map;
    return ApiResult.ok(GreenVpnUpdateManifest.fromJson(manifest));
  }

  Future<ApiResult<Map<String, dynamic>>> quoteTariff({
    String? accessToken,
    String? billingPlanCode,
    required String trafficPack,
    required int trafficGb,
    required List<String> unlimitedApps,
    required int devices,
    required bool dedicatedIp,
  }) async {
    final usesFixedBillingPlan =
        billingPlanCode != null && billingPlanCode.trim().isNotEmpty;
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/subscription/quote',
      bearerToken: accessToken,
      preferredBaseUrl: _primaryBaseUrl(),
      allowApiBaseFailover: false,
      payload: {
        'trafficPack': trafficPack,
        'trafficGb': trafficGb,
        'unlimitedApps': unlimitedApps,
        'devices': devices,
        'dedicatedIp': dedicatedIp,
        'billingPlanCode': ?billingPlanCode,
        if (kPublicProductBuild ||
            (kPaidBetaCustomerUi && usesFixedBillingPlan))
          'clientMarker': kPublicProductClientMarker,
        if (kPublicProductBuild ||
            (kPaidBetaCustomerUi && usesFixedBillingPlan))
          'releaseChannel': kPublicProductReleaseChannel,
        if (kPaidBetaCustomerUi && !usesFixedBillingPlan)
          'clientMarker': kPaidBetaClientMarker,
        if (kPaidBetaCustomerUi && !usesFixedBillingPlan)
          'releaseChannel': kPaidBetaReleaseChannel,
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
    String? billingPlanCode,
    required String trafficPack,
    required int trafficGb,
    required List<String> unlimitedApps,
    required int devices,
    required bool dedicatedIp,
    required bool autoRenew,
    required bool renewalAcknowledged,
    int? expectedSubscriptionRevision,
    String? expectedSubscriptionExpiresAt,
  }) async {
    final usesFixedBillingPlan =
        billingPlanCode != null && billingPlanCode.trim().isNotEmpty;
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/billing/orders',
      bearerToken: accessToken,
      preferredBaseUrl: _primaryBaseUrl(),
      allowApiBaseFailover: false,
      payload: {
        'trafficPack': trafficPack,
        'trafficGb': trafficGb,
        'unlimitedApps': unlimitedApps,
        'devices': devices,
        'dedicatedIp': dedicatedIp,
        'autoRenew': autoRenew,
        'renewalAcknowledged': renewalAcknowledged,
        'expectedSubscriptionRevision': ?expectedSubscriptionRevision,
        'expectedSubscriptionExpiresAt': ?expectedSubscriptionExpiresAt,
        'billingPlanCode': ?billingPlanCode,
        if (kPublicProductBuild ||
            (kPaidBetaCustomerUi && usesFixedBillingPlan))
          'clientMarker': kPublicProductClientMarker,
        if (kPublicProductBuild ||
            (kPaidBetaCustomerUi && usesFixedBillingPlan))
          'releaseChannel': kPublicProductReleaseChannel,
        if (kPaidBetaCustomerUi && !usesFixedBillingPlan)
          'clientMarker': kPaidBetaClientMarker,
        if (kPaidBetaCustomerUi && !usesFixedBillingPlan)
          'releaseChannel': kPaidBetaReleaseChannel,
      },
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ billing/orders.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> claimPaidBetaInvite({
    required String accessToken,
    required String code,
    required String deviceId,
    required String platform,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/paid-beta/invite/claim',
      bearerToken: accessToken,
      payload: {
        'code': code,
        'deviceUid': deviceId,
        'platform': platform,
        'appVersion': kAppVersion,
        'clientMarker': kPaidBetaClientMarker,
        'releaseChannel': kPaidBetaReleaseChannel,
      },
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ paid-beta/invite/claim.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> postPaidBetaEvent({
    required String accessToken,
    required String eventType,
    required String deviceId,
    required String platform,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/paid-beta/events',
      bearerToken: accessToken,
      payload: {
        'eventType': eventType,
        'deviceUid': deviceId,
        'platform': platform,
        'appVersion': kAppVersion,
        'clientMarker': kPaidBetaClientMarker,
        'releaseChannel': kPaidBetaReleaseChannel,
      },
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ paid-beta/events.');
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
      preferredBaseUrl: _primaryBaseUrl(),
      allowApiBaseFailover: false,
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
      preferredBaseUrl: _primaryBaseUrl(),
      allowApiBaseFailover: false,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ auto-renew/cancel.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> startAdChallenge({
    required String accessToken,
    required String deviceId,
    required String platform,
    String provider = 'auto',
    String appVersion = kAppVersion,
  }) async {
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/ads/challenges/start',
      bearerToken: accessToken,
      payload: {
        'deviceUid': deviceId,
        'platform': platform,
        'provider': provider,
        'appVersion': appVersion,
      },
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ ads/challenges/start.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> completeAdChallenge({
    required String challengeId,
    required String token,
  }) async {
    final encoded = Uri.encodeComponent(challengeId.trim());
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/ads/challenges/$encoded/complete',
      payload: {'token': token},
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ ads/challenge complete.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> fetchAdChallenge({
    required String accessToken,
    required String challengeId,
  }) async {
    final encoded = Uri.encodeComponent(challengeId.trim());
    final res = await _jsonRequest(
      method: 'GET',
      path: '/api/v1/ads/challenges/$encoded',
      bearerToken: accessToken,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ ads/challenge.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Map<String, dynamic>>> bootstrapClient({
    required String accessToken,
    required String deviceId,
    required String deviceName,
    String platform = 'windows',
    String appVersion = '0.1.0',
    String? releaseChannel,
    Duration? requestBudget,
  }) async {
    try {
      final body = await _withHttpRetry<String>(
        (client, _, resolvedBaseUrl) async {
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
              'releaseChannel': releaseChannel ?? greenVpnUpdateChannel(),
              'supportedProtocols': kSupportedVpnProtocols,
              if (kPaidBetaBuild) 'clientMarker': kPaidBetaClientMarker,
            }),
          );

          final res = await req.close().timeout(const Duration(seconds: 8));
          final body = await utf8
              .decodeStream(res)
              .timeout(const Duration(seconds: 5));
          if (res.statusCode < 200 || res.statusCode >= 300) {
            throw GreenVpnHttpStatusException(
              statusCode: res.statusCode,
              body: body,
              uri: uri,
              message: 'Ошибка bootstrap (${res.statusCode}): $body',
            );
          }
          return body;
        },
        preferredBaseUrl: _preferredApiBaseUrlForBearer(accessToken),
        totalBudget: requestBudget,
      );

      {
        final jsonMap = Map<String, dynamic>.from(jsonDecode(body) as Map);
        return ApiResult.ok(jsonMap);
      }
    } catch (e) {
      return ApiResult.err(
        greenVpnApiUserMessage(
          e,
          fallback: 'Не удалось подготовить приложение. Повторите попытку.',
        ),
      );
    }
  }

  Future<ApiResult<WireGuardConfigResponse>> fetchWireGuardConfig({
    required String accessToken,
    String? deviceId,
    String? serverId,
    String? releaseChannel,
    String mode = 'full',
    Duration? requestBudget,
  }) async {
    try {
      if (deviceId == null || deviceId.trim().isEmpty) {
        return const ApiResult.err('Отсутствует device id.');
      }

      final body = await _withHttpRetry<String>(
        (client, _, resolvedBaseUrl) async {
          final uri = _uFor(resolvedBaseUrl, '/api/v1/client/config');
          final req = await client.postUrl(uri);
          req.headers.contentType = ContentType.json;
          req.headers.set('Authorization', 'Bearer $accessToken');
          final payload = <String, dynamic>{
            'deviceUid': deviceId,
            'mode': mode == 'social_only' ? 'social_only' : 'full',
            'releaseChannel': releaseChannel ?? greenVpnUpdateChannel(),
            'supportedProtocols': kSupportedVpnProtocols,
            if (kPaidBetaBuild) 'clientMarker': kPaidBetaClientMarker,
          };
          if (serverId != null && serverId.trim().isNotEmpty) {
            payload['serverId'] = serverId.trim();
          }
          req.write(jsonEncode(payload));

          final res = await req.close().timeout(const Duration(seconds: 12));
          final body = await utf8
              .decodeStream(res)
              .timeout(const Duration(seconds: 6));
          if (res.statusCode < 200 || res.statusCode >= 300) {
            throw GreenVpnHttpStatusException(
              statusCode: res.statusCode,
              body: body,
              uri: uri,
              message: 'Ошибка сервера (${res.statusCode}): $body',
            );
          }
          return body;
        },
        preferredBaseUrl: _preferredApiBaseUrlForBearer(accessToken),
        totalBudget: requestBudget,
      );

      {
        final trimmed = body.trim();
        if (trimmed.isEmpty) {
          return const ApiResult.err('Сервер вернул пустой конфиг.');
        }

        final jsonMap = Map<String, dynamic>.from(jsonDecode(trimmed) as Map);
        final config = WireGuardConfigResponse.fromJson(jsonMap);
        if (config.configText.trim().isEmpty) {
          return const ApiResult.err('Сервер вернул пустой configText.');
        }
        return ApiResult.ok(config);
      }
    } catch (e) {
      return ApiResult.err(
        greenVpnApiUserMessage(
          e,
          fallback: 'Не удалось подготовить VPN-подключение.',
        ),
      );
    }
  }

  Future<ApiResult<Map<String, dynamic>>> postClientRouteEvent({
    required String accessToken,
    required String deviceId,
    required String serverId,
    required String protocol,
    String transport = 'udp',
    required String stage,
    required bool ok,
    int? latencyMs,
    String? errorCode,
    String? message,
    Map<String, dynamic>? details,
  }) async {
    final cleanDeviceId = deviceId.trim();
    if (cleanDeviceId.isEmpty) {
      return const ApiResult.err('Отсутствует device id.');
    }
    final payload = <String, dynamic>{
      'deviceUid': cleanDeviceId,
      'serverId': serverId.trim().isEmpty ? 'auto' : serverId.trim(),
      'protocol': protocol.trim().isEmpty ? 'wireguard_udp' : protocol.trim(),
      'transport': transport.trim().isEmpty ? 'udp' : transport.trim(),
      'stage': stage,
      'ok': ok,
      'appVersion': kAppVersion,
      'latencyMs': ?latencyMs,
      if ((errorCode ?? '').trim().isNotEmpty) 'errorCode': errorCode!.trim(),
      if ((message ?? '').trim().isNotEmpty) 'message': message!.trim(),
      if (details != null && details.isNotEmpty) 'details': details,
    };
    final res = await _jsonRequest(
      method: 'POST',
      path: '/api/v1/client/route-events',
      bearerToken: accessToken,
      payload: payload,
    );
    if (!res.ok) return ApiResult.err(res.message);
    if (res.data is! Map) {
      return const ApiResult.err('Некорректный ответ client/route-events.');
    }
    return ApiResult.ok(Map<String, dynamic>.from(res.data as Map));
  }

  Future<ApiResult<Session>> _postSession(
    String path,
    Map<String, dynamic> payload, {
    String? preferredApiBaseUrl,
    String? bearerToken,
    bool allowApiBaseFailover = true,
  }) async {
    try {
      await _authLog('POST $path email=${payload['email'] ?? ''}');
      unawaited(_tcpPreflight(path).then(_authLog));
      String? sessionApiBaseUrl;
      final body = await _withHttpRetry<String>(
        (client, direct, resolvedBaseUrl) async {
          final uri = _uFor(resolvedBaseUrl, path);
          final req = await client.postUrl(uri);
          req.headers.contentType = ContentType.json;
          if ((bearerToken ?? '').isNotEmpty) {
            req.headers.set('Authorization', 'Bearer $bearerToken');
          }
          req.write(jsonEncode(payload));

          final res = await req.close().timeout(const Duration(seconds: 8));
          final body = await utf8
              .decodeStream(res)
              .timeout(const Duration(seconds: 5));
          await _authLog(
            'HTTP $path status=${res.statusCode} route=${direct ? 'direct' : 'system'} base=$resolvedBaseUrl',
          );
          if (res.statusCode < 200 || res.statusCode >= 300) {
            final friendly = _friendlyAuthError(
              path: path,
              statusCode: res.statusCode,
              body: body,
            );
            throw GreenVpnHttpStatusException(
              statusCode: res.statusCode,
              body: body,
              uri: uri,
              message: friendly ?? 'Ошибка сервера (${res.statusCode}): $body',
            );
          }
          sessionApiBaseUrl = _normalizeApiBaseUrl(resolvedBaseUrl);
          return body;
        },
        preferredBaseUrl: preferredApiBaseUrl,
        allowApiBaseFailover: allowApiBaseFailover,
      );

      {
        final jsonMap = jsonDecode(body) as Map<String, dynamic>;
        final token = (jsonMap['accessToken'] ?? '').toString();
        final email = (jsonMap['email'] ?? payload['email'] ?? '').toString();

        if (token.isEmpty) {
          return const ApiResult.err('Сервер не вернул accessToken.');
        }
        final session = Session(
          accessToken: token,
          email: email,
          apiBaseUrl: sessionApiBaseUrl ?? _primaryBaseUrl(),
          isGuest: jsonMap['isGuest'] == true,
          emailVerified: jsonMap['emailVerified'] == true,
          emailConfirmationRequired:
              jsonMap['emailConfirmationRequired'] == true,
        );
        rememberSession(session);
        _pendingAuthApiBaseUrl = null;
        return ApiResult.ok(session);
      }
    } catch (e) {
      await _authLog('HTTP $path exception=$e');
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
        path.endsWith('/auth/checkout/email/verify') ||
        path.endsWith('/auth/access/email/verify')) {
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
    String? preferredBaseUrl,
    bool allowApiBaseFailover = true,
    void Function(String baseUrl)? onSuccessBaseUrl,
  }) async {
    try {
      await _authLog('API $method $path start');
      final body = await _withHttpRetry<String>(
        (client, direct, resolvedBaseUrl) async {
          final uri = _uFor(resolvedBaseUrl, path);
          final req = method == 'GET'
              ? await client.getUrl(uri)
              : await client.postUrl(uri);

          req.headers.set(
            HttpHeaders.userAgentHeader,
            'GreenVPN/$kAppVersion (${greenVpnClientPlatform()}; flutter)',
          );
          req.headers.set('X-GreenVPN-Platform', greenVpnClientPlatform());
          req.headers.set('X-GreenVPN-Version', kAppVersion);
          req.headers.set(
            'X-GreenVPN-Release-Channel',
            greenVpnUpdateChannel(),
          );
          req.headers.set(
            'X-GreenVPN-Supported-Protocols',
            kSupportedVpnProtocols.join(','),
          );
          if (bearerToken != null && bearerToken.trim().isNotEmpty) {
            req.headers.set('Authorization', 'Bearer $bearerToken');
          }
          if (adminToken != null && adminToken.trim().isNotEmpty) {
            req.headers.set('X-Admin-Token', adminToken.trim());
          }
          if (payload != null) {
            req.headers.contentType = ContentType.json;
            req.write(jsonEncode(payload));
          }

          final res = await req.close().timeout(const Duration(seconds: 8));
          final body = await utf8
              .decodeStream(res)
              .timeout(const Duration(seconds: 5));
          await _authLog(
            'API $method $path status=${res.statusCode} route=${direct ? 'direct' : 'system'} base=$resolvedBaseUrl',
          );
          if (res.statusCode < 200 || res.statusCode >= 300) {
            throw GreenVpnHttpStatusException(
              statusCode: res.statusCode,
              body: body,
              uri: uri,
              message: 'Ошибка сервера (${res.statusCode}): $body',
            );
          }
          onSuccessBaseUrl?.call(resolvedBaseUrl);
          return body;
        },
        preferredBaseUrl:
            preferredBaseUrl ?? _preferredApiBaseUrlForBearer(bearerToken),
        allowApiBaseFailover: allowApiBaseFailover,
      );

      if (body.trim().isEmpty) {
        return const ApiResult.ok(<String, dynamic>{});
      }

      return ApiResult.ok(jsonDecode(body));
    } catch (e) {
      await _authLog('API $method $path exception=$e');
      return ApiResult.err(greenVpnApiUserMessage(e));
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
    required String reason,
    String? expiresAt,
  }) async {
    final payload = <String, dynamic>{
      'planCode': planCode,
      'planName': planName,
      'maxDevices': maxDevices,
      'isActive': isActive,
      'reason': reason.trim(),
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
    required String reason,
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
        'autoRenew': false,
        'adminReason': reason.trim(),
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
  static const _mobileManagedConfigKey = 'greenvpn_mobile_managed_config_v1';
  static const _mobileManagedProtocolKey =
      'greenvpn_mobile_managed_protocol_v1';
  static const _mobileManagedRouteIdKey = 'greenvpn_mobile_managed_route_id_v1';
  static const _mobileBaseConfigKey = 'greenvpn_mobile_base_config_v1';
  static const _mobileServerBaseConfigPrefix =
      'greenvpn_mobile_base_config_server_v1_';
  static const _mobileConfigChannel = MethodChannel('green_vpn/android_vpn');
  static String? _mobileManagedConfig;
  static String _mobileManagedProtocol = 'wireguard_udp';
  static String _mobileManagedRouteId = '';
  static String? _mobileBaseConfig;
  static final Map<String, String?> _mobileServerBaseConfigs = {};

  bool get _usesMobileSecureConfig =>
      !kIsWeb && !Platform.isWindows && (Platform.isAndroid || Platform.isIOS);

  Future<String?> _readMobileConfig(String key) async {
    if (!Platform.isAndroid) {
      if (key == _mobileManagedConfigKey) return _mobileManagedConfig;
      if (key == _mobileManagedProtocolKey) return _mobileManagedProtocol;
      if (key == _mobileManagedRouteIdKey) return _mobileManagedRouteId;
      return _mobileBaseConfig;
    }
    try {
      final value = await _mobileConfigChannel.invokeMethod<String>(
        'secureRead',
        {'key': key},
      );
      if (key == _mobileManagedConfigKey) {
        _mobileManagedConfig = value;
      } else if (key == _mobileManagedProtocolKey) {
        final normalized = (value ?? '').trim().toLowerCase();
        if (normalized.isNotEmpty) _mobileManagedProtocol = normalized;
      } else if (key == _mobileManagedRouteIdKey) {
        _mobileManagedRouteId = greenVpnNormalizeManagedRouteId(value ?? '');
      } else if (key == _mobileBaseConfigKey) {
        _mobileBaseConfig = value;
      }
      return value;
    } catch (e) {
      await appendBlueVpnClientLog('mobile config secure read failed: $e');
      if (key == _mobileManagedConfigKey) return _mobileManagedConfig;
      if (key == _mobileManagedProtocolKey) return _mobileManagedProtocol;
      if (key == _mobileManagedRouteIdKey) return _mobileManagedRouteId;
      return _mobileBaseConfig;
    }
  }

  Future<void> _writeMobileConfig(String key, String content) async {
    if (key == _mobileManagedConfigKey) {
      _mobileManagedConfig = content;
    } else if (key == _mobileManagedProtocolKey) {
      _mobileManagedProtocol = content.trim().toLowerCase();
    } else if (key == _mobileManagedRouteIdKey) {
      _mobileManagedRouteId = greenVpnNormalizeManagedRouteId(content);
    } else if (key == _mobileBaseConfigKey) {
      _mobileBaseConfig = content;
    }
    if (!Platform.isAndroid) return;
    try {
      await _mobileConfigChannel.invokeMethod<void>('secureWrite', {
        'key': key,
        'value': content,
      });
    } catch (e) {
      await appendBlueVpnClientLog('mobile config secure write failed: $e');
    }
  }

  Future<void> _deleteMobileConfig(String key) async {
    if (key == _mobileManagedConfigKey) {
      _mobileManagedConfig = null;
    } else if (key == _mobileManagedProtocolKey) {
      _mobileManagedProtocol = 'wireguard_udp';
    } else if (key == _mobileManagedRouteIdKey) {
      _mobileManagedRouteId = '';
    } else if (key == _mobileBaseConfigKey) {
      _mobileBaseConfig = null;
    }
    if (!Platform.isAndroid) return;
    try {
      await _mobileConfigChannel.invokeMethod<void>('secureDelete', {
        'key': key,
      });
    } catch (e) {
      await appendBlueVpnClientLog('mobile config secure delete failed: $e');
    }
  }

  String _safeServerCacheKey(String serverId) {
    final safe = serverId.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_.-]+'),
      '_',
    );
    return safe.isEmpty ? 'auto' : safe;
  }

  String _mobileServerBaseConfigKey(String serverId) {
    return '$_mobileServerBaseConfigPrefix${_safeServerCacheKey(serverId)}';
  }

  Future<String?> _readMobileServerBaseConfig(String serverId) async {
    final key = _mobileServerBaseConfigKey(serverId);
    if (!Platform.isAndroid) {
      return _mobileServerBaseConfigs[key];
    }
    try {
      final value = await _mobileConfigChannel.invokeMethod<String>(
        'secureRead',
        {'key': key},
      );
      _mobileServerBaseConfigs[key] = value;
      return value;
    } catch (e) {
      await appendBlueVpnClientLog(
        'mobile server config secure read failed server=$serverId error=$e',
      );
      return _mobileServerBaseConfigs[key];
    }
  }

  Future<void> _writeMobileServerBaseConfig(
    String serverId,
    String content,
  ) async {
    final key = _mobileServerBaseConfigKey(serverId);
    _mobileServerBaseConfigs[key] = content;
    if (!Platform.isAndroid) return;
    try {
      await _mobileConfigChannel.invokeMethod<void>('secureWrite', {
        'key': key,
        'value': content,
      });
    } catch (e) {
      await appendBlueVpnClientLog(
        'mobile server config secure write failed server=$serverId error=$e',
      );
    }
  }

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
    if (_usesMobileSecureConfig) return 'greenvpn://mobile/managed.conf';
    if (!Platform.isWindows) return '';
    return greenVpnManagedConfigPathSync();
  }

  // Hidden base config received from server/dev seed. We never apply it directly.
  String get baseConfigPath {
    if (kIsWeb) return '';
    if (_usesMobileSecureConfig) return 'greenvpn://mobile/base.conf';
    if (!Platform.isWindows) return '';
    return greenVpnBaseConfigPathSync();
  }

  String serverBaseConfigPath(String serverId) {
    if (kIsWeb) return '';
    if (_usesMobileSecureConfig) {
      return 'greenvpn://mobile/server/${_safeServerCacheKey(serverId)}.conf';
    }
    if (!Platform.isWindows) return '';
    return '${greenVpnProgramDataRootSync()}\\server-cache\\${_safeServerCacheKey(serverId)}.base.conf';
  }

  Future<bool> hasManagedConfig() async {
    return _runConfigIo(() async {
      if (kIsWeb) return false;
      if (_usesMobileSecureConfig) {
        final config = await _readMobileConfig(_mobileManagedConfigKey);
        return (config ?? '').trim().isNotEmpty;
      }
      final p = managedConfigPath;
      if (p.isEmpty) return false;
      return File(p).existsSync();
    });
  }

  Future<bool> hasBaseConfig() async {
    return _runConfigIo(() async {
      if (kIsWeb) return false;
      if (_usesMobileSecureConfig) {
        final config = await _readMobileConfig(_mobileBaseConfigKey);
        return (config ?? '').trim().isNotEmpty;
      }
      final p = baseConfigPath;
      if (p.isEmpty) return false;
      return File(p).existsSync();
    });
  }

  Future<String?> readManagedConfig() async {
    return _runConfigIo(() async {
      if (kIsWeb) return null;
      if (_usesMobileSecureConfig) {
        return _readMobileConfig(_mobileManagedConfigKey);
      }
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
    if (_usesMobileSecureConfig) {
      return _readMobileConfig(_mobileManagedConfigKey);
    }
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
      if (_usesMobileSecureConfig) {
        await _writeMobileConfig(_mobileManagedConfigKey, content);
        return;
      }
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

  Future<String> readManagedProtocol() async {
    if (kIsWeb) return 'wireguard_udp';
    if (_usesMobileSecureConfig) {
      final value = await _readMobileConfig(_mobileManagedProtocolKey);
      final normalized = (value ?? '').trim().toLowerCase();
      if (normalized.isNotEmpty) _mobileManagedProtocol = normalized;
      return _mobileManagedProtocol;
    }
    if (Platform.isWindows) {
      final path = '$managedConfigPath.protocol';
      final file = File(path);
      if (file.existsSync()) {
        final normalized = (await file.readAsString()).trim().toLowerCase();
        if (normalized.isNotEmpty) _mobileManagedProtocol = normalized;
      }
    }
    return _mobileManagedProtocol;
  }

  Future<void> writeManagedProtocol(String protocol) async {
    final normalized = protocol.trim().toLowerCase();
    _mobileManagedProtocol = normalized.isEmpty ? 'wireguard_udp' : normalized;
    if (kIsWeb) return;
    if (_usesMobileSecureConfig) {
      await _writeMobileConfig(
        _mobileManagedProtocolKey,
        _mobileManagedProtocol,
      );
      return;
    }
    if (Platform.isWindows) {
      final file = File('$managedConfigPath.protocol');
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      await WindowsLocalSecurity.prepareSharedConfigDirectory(file.parent.path);
      if (file.existsSync()) {
        await WindowsLocalSecurity.prepareSharedConfigFile(file.path);
      }
      await file.writeAsString(_mobileManagedProtocol, flush: true);
      await WindowsLocalSecurity.prepareSharedConfigFile(file.path);
    }
  }

  Future<String> readManagedRouteId() async {
    if (kIsWeb) return '';
    if (_usesMobileSecureConfig) {
      final value = await _readMobileConfig(_mobileManagedRouteIdKey);
      _mobileManagedRouteId = greenVpnNormalizeManagedRouteId(value ?? '');
      return _mobileManagedRouteId;
    }
    if (Platform.isWindows) {
      final file = File('$managedConfigPath.route_id');
      if (file.existsSync()) {
        try {
          final value = await file.readAsString();
          _mobileManagedRouteId = greenVpnNormalizeManagedRouteId(value);
        } on FileSystemException {
          _mobileManagedRouteId = '';
        }
      }
    }
    return _mobileManagedRouteId;
  }

  Future<void> writeManagedRouteId(String routeId) async {
    _mobileManagedRouteId = greenVpnNormalizeManagedRouteId(routeId);
    if (kIsWeb) return;
    if (_usesMobileSecureConfig) {
      await _writeMobileConfig(_mobileManagedRouteIdKey, _mobileManagedRouteId);
      return;
    }
    if (Platform.isWindows) {
      final file = File('$managedConfigPath.route_id');
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      await WindowsLocalSecurity.prepareSharedConfigDirectory(file.parent.path);
      if (file.existsSync()) {
        await WindowsLocalSecurity.prepareSharedConfigFile(file.path);
      }
      await file.writeAsString(_mobileManagedRouteId, flush: true);
      await WindowsLocalSecurity.prepareSharedConfigFile(file.path);
    }
  }

  Future<void> writeWindowsRoutingPolicy({
    required bool applicationsOnly,
    required Iterable<String> applicationPaths,
    required Iterable<String> destinationCidrs,
  }) async {
    if (kIsWeb || !Platform.isWindows) return;

    final normalized =
        applicationPaths
            .map((value) => value.trim())
            .where(isValidWindowsApplicationPath)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (normalized.length > maxWindowsVpnApplications) {
      throw StateError(
        'Можно выбрать не более $maxWindowsVpnApplications приложений.',
      );
    }
    final normalizedDestinations =
        destinationCidrs
            .map((value) => value.trim())
            .where(isValidWindowsVpnDestinationCidr)
            .toSet()
            .toList()
          ..sort();
    if (normalizedDestinations.length > maxWindowsVpnDestinationCidrs) {
      throw StateError('Для выбранных сайтов получено слишком много адресов.');
    }
    if (applicationsOnly &&
        normalized.isEmpty &&
        normalizedDestinations.isEmpty) {
      throw StateError('Выбери хотя бы один сервис, программу или сайт.');
    }

    await _runConfigIo(() async {
      final root = Directory(greenVpnProgramDataRootSync());
      if (!root.existsSync()) root.createSync(recursive: true);
      await WindowsLocalSecurity.prepareSharedConfigDirectory(root.path);

      final appsFile = File(greenVpnWindowsRoutingAppsPathSync());
      final payload = jsonEncode({
        'schemaVersion': 2,
        'applications': normalized,
        'destinationCidrs': normalizedDestinations,
        'proxy': {
          'host': _windowsApplicationProxyHost,
          'port': _windowsApplicationProxyPort,
        },
      });
      await appsFile.writeAsString(payload, flush: true);
      await WindowsLocalSecurity.prepareSharedConfigFile(appsFile.path);

      final modeFile = File(greenVpnWindowsRoutingModePathSync());
      await modeFile.writeAsString(
        applicationsOnly ? 'applications\n' : 'full\n',
        flush: true,
      );
      await WindowsLocalSecurity.prepareSharedConfigFile(modeFile.path);
    });
  }

  Future<void> writeBaseConfig(String content) async {
    await _runConfigIo(() async {
      if (kIsWeb) return;
      if (_usesMobileSecureConfig) {
        await _writeMobileConfig(_mobileBaseConfigKey, content);
        return;
      }
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

  Future<void> writeBaseConfigForServer(String serverId, String content) async {
    final key = _safeServerCacheKey(serverId);
    if (key == 'auto' || content.trim().isEmpty) return;
    await _runConfigIo(() async {
      if (kIsWeb) return;
      if (_usesMobileSecureConfig) {
        await _writeMobileServerBaseConfig(key, content);
        return;
      }
      final p = serverBaseConfigPath(key);
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
          'config write retry path=${f.path} kind=server-base server=$key',
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
      if (_usesMobileSecureConfig) {
        final base = await _readMobileConfig(_mobileBaseConfigKey);
        if ((base ?? '').trim().isNotEmpty) return base;
        return _readMobileConfig(_mobileManagedConfigKey);
      }
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

  Future<String?> readBaseConfigForServer(String serverId) async {
    final key = _safeServerCacheKey(serverId);
    if (key == 'auto') return null;
    return _runConfigIo(() async {
      if (kIsWeb) return null;
      if (_usesMobileSecureConfig) {
        return _readMobileServerBaseConfig(key);
      }
      final p = serverBaseConfigPath(key);
      if (p.isEmpty) return null;
      final f = File(p);
      if (!f.existsSync()) return null;
      await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
      await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
      try {
        return await f.readAsString();
      } on FileSystemException {
        await appendBlueVpnClientLog(
          'config read retry path=${f.path} kind=server-base server=$key',
        );
        await WindowsLocalSecurity.repairBlueVpnLocalAcls();
        await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
        await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
        return f.existsSync() ? await f.readAsString() : null;
      }
    });
  }

  Future<DateTime?> baseConfigModifiedAtForServer(String serverId) async {
    final key = _safeServerCacheKey(serverId);
    if (kIsWeb || !Platform.isWindows || key == 'auto') return null;
    return _runConfigIo(() async {
      final path = serverBaseConfigPath(key);
      if (path.isEmpty) return null;
      final file = File(path);
      if (!file.existsSync()) return null;
      try {
        return (await file.stat()).modified.toUtc();
      } catch (_) {
        return null;
      }
    });
  }

  DateTime? baseConfigModifiedAtForServerSync(String serverId) {
    final key = _safeServerCacheKey(serverId);
    if (kIsWeb || !Platform.isWindows || key == 'auto') return null;
    final path = serverBaseConfigPath(key);
    if (path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      return file.statSync().modified.toUtc();
    } catch (_) {
      return null;
    }
  }

  Future<void> ensureBaseSeededFromManagedIfMissing() async {
    await _runConfigIo(() async {
      if (kIsWeb) return;
      if (_usesMobileSecureConfig) {
        final base = await _readMobileConfig(_mobileBaseConfigKey);
        final managed = await _readMobileConfig(_mobileManagedConfigKey);
        if ((base ?? '').trim().isEmpty && (managed ?? '').trim().isNotEmpty) {
          await _writeMobileConfig(_mobileBaseConfigKey, managed!);
        }
        return;
      }
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
      if (_usesMobileSecureConfig) {
        await _deleteMobileConfig(_mobileManagedConfigKey);
        await _deleteMobileConfig(_mobileManagedProtocolKey);
        await _deleteMobileConfig(_mobileManagedRouteIdKey);
        await _deleteMobileConfig(_mobileBaseConfigKey);
        return;
      }

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
        for (final sidecarPath in <String>[
          '$managed.protocol',
          '$managed.route_id',
        ]) {
          final sidecar = File(sidecarPath);
          if (!sidecar.existsSync()) continue;
          try {
            await WindowsLocalSecurity.prepareSharedConfigFile(sidecar.path);
            await sidecar.delete();
          } on FileSystemException {
            await WindowsLocalSecurity.repairBlueVpnLocalAcls();
            await WindowsLocalSecurity.prepareSharedConfigFile(sidecar.path);
            if (sidecar.existsSync()) await sidecar.delete();
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
  final BlueVpnApi? api;
  final bool probeWireGuardOnStart;
  final bool prepareWindowsNetworkForAuth;
  final bool authLoggingEnabled;
  final String? authDeviceIdOverride;

  const AuthPage({
    super.key,
    required this.onAuthSuccess,
    this.api,
    this.probeWireGuardOnStart = true,
    this.prepareWindowsNetworkForAuth = true,
    this.authLoggingEnabled = true,
    this.authDeviceIdOverride,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final BlueVpnApi _api;
  final _deviceStore = DeviceIdStore();
  int _activeAuthTabIndex = 0;

  final _emailCodeEmail = TextEditingController();
  final _emailCode = TextEditingController();
  final _legacyEmail = TextEditingController();
  final _legacyPassword = TextEditingController();

  bool _busy = false;
  String? _authStatus;
  String? _activeEmailCodeAddress;
  bool _emailCodeRequested = false;
  WireGuardInstallState? _wireGuardState;
  bool _wireGuardBusy = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? const BlueVpnApi(baseUrl: kApiBaseUrl);
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_handleAuthTabChanged);
    if (widget.probeWireGuardOnStart) {
      unawaited(_refreshWireGuardState());
    }
  }

  void _handleAuthTabChanged() {
    if (!mounted || _activeAuthTabIndex == _tabs.index) return;
    setState(() {
      _activeAuthTabIndex = _tabs.index;
      _authStatus = null;
    });
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }

  @override
  void dispose() {
    _tabs.removeListener(_handleAuthTabChanged);
    _tabs.dispose();
    _emailCodeEmail.dispose();
    _emailCode.dispose();
    _legacyEmail.dispose();
    _legacyPassword.dispose();
    super.dispose();
  }

  void _toast(String text) {
    final visibleText = kPublicProductBuild
        ? greenVpnPublicErrorMessage(rawError: text)
        : text;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(visibleText)));
  }

  void _setAuthStatus(String? text) {
    if (!mounted) return;
    setState(() => _authStatus = text);
  }

  Future<void> _authLog(String text) async {
    if (!widget.authLoggingEnabled) return;
    await appendGreenVpnAuthLogLine(text);
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
    if (!widget.prepareWindowsNetworkForAuth) return true;
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
    if (widget.authDeviceIdOverride != null) {
      return widget.authDeviceIdOverride;
    }
    if (kIsWeb) return 'web';
    try {
      return await _deviceStore.getOrCreate();
    } catch (e, st) {
      await _authLog('device id for auth exception=$e stack=$st');
      return null;
    }
  }

  String get _deviceNameForAuth => greenVpnClientDeviceName();

  String get _platformForAuth => greenVpnClientPlatform();

  String _challengeDeliveryMessage({
    required String delivery,
    required bool deliveryReady,
  }) {
    if (delivery == 'sent') return 'Код отправлен на email.';
    if (delivery == 'failed' || !deliveryReady) {
      return 'Email сейчас недоступен. Попробуй позже или войди по паролю.';
    }
    return 'Код подготовлен. Проверь email.';
  }

  Future<void> _startChallenge() async {
    if (_busy) return;

    final contact = _emailCodeEmail.text.trim();
    if (contact.isEmpty || !contact.contains('@')) {
      _toast('Введи корректный email.');
      return;
    }

    setState(() => _busy = true);
    try {
      await _authLog('challenge start method=email_code');
      final networkReady = await _prepareNetworkForAuth(
        'email_challenge_start',
      );
      if (!networkReady) return;

      _setAuthStatus('Отправляем код...');
      final res = await _api.startAuthChallenge(
        method: 'email_code',
        email: contact,
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
      final normalized = (data['email'] ?? contact).toString();
      final delivery = (data['deliveryStatus'] ?? '').toString();
      final deliveryReady = data['deliveryReady'] == true;
      final message = _challengeDeliveryMessage(
        delivery: delivery,
        deliveryReady: deliveryReady,
      );
      final canEnterCode = delivery != 'failed' && deliveryReady;

      if (!mounted) return;
      setState(() {
        _authStatus = message;
        _activeEmailCodeAddress = normalized;
        _emailCodeEmail.text = normalized;
        _emailCode.clear();
        _emailCodeRequested = canEnterCode;
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

  Future<void> _verifyChallenge() async {
    if (_busy) return;

    final contact = (_activeEmailCodeAddress ?? _emailCodeEmail.text).trim();
    final code = _emailCode.text.trim();
    if (contact.isEmpty) {
      _toast('Введи email.');
      return;
    }
    if (code.isEmpty) {
      _toast('Введи код.');
      return;
    }

    setState(() => _busy = true);
    try {
      await _authLog('challenge verify method=email_code');
      final networkReady = await _prepareNetworkForAuth(
        'email_challenge_verify',
      );
      if (!networkReady) return;

      final deviceId = await _deviceIdForAuth();
      _setAuthStatus('Проверяем код...');
      final res = await _api.verifyAuthChallenge(
        method: 'email_code',
        email: contact,
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

      await _completeAuth(res.data!);
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

      await _completeAuth(res.data!);
    } catch (e, st) {
      await _authLog('legacy auth exception=$e stack=$st');
      final text = authUserMessage(e, fallback: 'Ошибка входа.');
      _setAuthStatus(text);
      _toast(text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeAuth(Session session) async {
    await _authLog('auth config warmup deferred until home screen');
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

  Widget _buildEmailCodeAuthForm() {
    return Column(
      children: [
        TextField(
          key: const Key('auth_email_contact'),
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
          autofillHints: const [AutofillHints.email],
          onChanged: (_) {
            if (!_emailCodeRequested) return;
            setState(() {
              _activeEmailCodeAddress = null;
              _emailCodeRequested = false;
              _emailCode.clear();
              _authStatus = null;
            });
          },
          onSubmitted: (_) {
            if (!_busy && !_emailCodeRequested) {
              unawaited(_startChallenge());
            }
          },
        ),
        if (_emailCodeRequested) ...[
          const SizedBox(height: 10),
          TextField(
            key: const Key('auth_email_code'),
            controller: _emailCode,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: const InputDecoration(
              labelText: 'Код из письма',
              hintText: '0000',
              border: OutlineInputBorder(),
            ),
            autofillHints: const [AutofillHints.oneTimeCode],
            onSubmitted: (_) {
              if (!_busy) unawaited(_verifyChallenge());
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
                    ? _verifyChallenge()
                    : _startChallenge(),
        ),
        if (_emailCodeRequested) ...[
          const SizedBox(height: 8),
          _buildResendButton(
            label: 'Получить новый код',
            onPressed: _busy ? null : _startChallenge,
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
      case 0:
        return _buildEmailCodeAuthForm();
      case 1:
        return _buildLegacyPasswordForm();
      default:
        return _buildEmailCodeAuthForm();
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
                                        'Восстановить доступ',
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
                                title: 'Нужен системный компонент',
                                subtitle:
                                    'Green VPN установит компонент для подключения.',
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
                                Tab(text: 'Email'),
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
                                        .withValues(alpha: 0.72),
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

class RestoreAccessDialog extends StatefulWidget {
  final BlueVpnApi api;
  final Session session;
  final String? initialEmail;
  final String? deviceUidOverride;
  final Future<Session?> Function()? renewGuestSession;

  const RestoreAccessDialog({
    super.key,
    required this.api,
    required this.session,
    this.initialEmail,
    this.deviceUidOverride,
    this.renewGuestSession,
  });

  @override
  State<RestoreAccessDialog> createState() => _RestoreAccessDialogState();
}

class _RestoreAccessDialogState extends State<RestoreAccessDialog> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _deviceStore = DeviceIdStore();
  bool _busy = false;
  bool _codeRequested = false;
  String? _status;
  late Session _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _email.text = widget.initialEmail?.trim() ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final email = _email.text.trim();
    if (_busy || email.isEmpty || !email.contains('@')) {
      setState(() => _status = 'Введите корректный email.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Отправляем код...';
    });
    try {
      var res = await widget.api.startAccessEmail(
        accessToken: _session.accessToken,
        email: email,
      );
      if (!res.ok &&
          greenVpnIsInvalidSessionMessage(res.message) &&
          widget.renewGuestSession != null) {
        if (mounted) {
          setState(() => _status = 'Обновляем бесплатный профиль...');
        }
        final renewed = await widget.renewGuestSession!();
        if (renewed != null) {
          _session = renewed;
          res = await widget.api.startAccessEmail(
            accessToken: _session.accessToken,
            email: email,
          );
        }
      }
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        setState(
          () => _status = authUserMessage(
            res.message ?? 'Не удалось отправить код.',
            fallback: 'Не удалось отправить код.',
          ),
        );
        return;
      }
      final delivery = (res.data!['deliveryStatus'] ?? '').toString();
      final ready = res.data!['deliveryReady'] == true;
      setState(() {
        _codeRequested = delivery == 'sent' && ready;
        _code.clear();
        _status = _codeRequested
            ? 'Код отправлен на email.'
            : 'Не удалось отправить код. Попробуйте позже.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final email = _email.text.trim();
    final code = _code.text.trim();
    if (_busy || code.isEmpty) {
      setState(() => _status = 'Введите код из письма.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Входим в аккаунт...';
    });
    try {
      final deviceUid =
          widget.deviceUidOverride ?? await _deviceStore.getOrCreate();
      final res = await widget.api.verifyAccessEmail(
        accessToken: _session.accessToken,
        email: email,
        code: code,
        deviceUid: deviceUid,
        deviceName: greenVpnClientDeviceName(),
        platform: greenVpnClientPlatform(),
        appVersion: kAppVersion,
      );
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        setState(
          () => _status = authUserMessage(
            res.message ?? 'Код не подошёл или уже истёк.',
            fallback: 'Код не подошёл или уже истёк.',
          ),
        );
        return;
      }
      Navigator.of(context).pop(res.data);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Войти в аккаунт'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Используйте email, к которому привязана подписка. '
              'После входа Green VPN проверит доступ и восстановит его на этом устройстве.',
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('restore_access_email'),
              controller: _email,
              enabled: !_busy && !_codeRequested,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (!_codeRequested) unawaited(_start());
              },
            ),
            if (_codeRequested) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('restore_access_code'),
                controller: _code,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: 'Код из письма',
                  hintText: '0000',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => unawaited(_verify()),
              ),
            ],
            if ((_status ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _status!,
                style: const TextStyle(
                  color: kBrandMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : _codeRequested
              ? _verify
              : _start,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _codeRequested
                      ? Icons.login_rounded
                      : Icons.mark_email_read_rounded,
                ),
          label: Text(_codeRequested ? 'Войти' : 'Получить код'),
        ),
      ],
    );
  }
}

class CheckoutEmailDialog extends StatefulWidget {
  final BlueVpnApi api;
  final Session session;
  final String? initialEmail;
  final String? deviceUidOverride;

  const CheckoutEmailDialog({
    super.key,
    required this.api,
    required this.session,
    this.initialEmail,
    this.deviceUidOverride,
  });

  @override
  State<CheckoutEmailDialog> createState() => _CheckoutEmailDialogState();
}

class _CheckoutEmailDialogState extends State<CheckoutEmailDialog> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _deviceStore = DeviceIdStore();
  bool _busy = false;
  bool _codeRequested = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail?.trim() ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final email = _email.text.trim();
    if (_busy || email.isEmpty || !email.contains('@')) {
      setState(() => _status = 'Введите корректный email.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Отправляем код...';
    });
    try {
      final res = await widget.api.startCheckoutEmail(
        accessToken: widget.session.accessToken,
        email: email,
      );
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        setState(() => _status = res.message ?? 'Не удалось отправить код.');
        return;
      }
      final delivery = (res.data!['deliveryStatus'] ?? '').toString();
      final ready = res.data!['deliveryReady'] == true;
      setState(() {
        _codeRequested = delivery == 'sent' && ready;
        _code.clear();
        _status = _codeRequested
            ? 'Код отправлен на email.'
            : 'Не удалось отправить код. Попробуйте позже.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final email = _email.text.trim();
    final code = _code.text.trim();
    if (_busy || code.isEmpty) {
      setState(() => _status = 'Введите код из письма.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Подтверждаем email...';
    });
    try {
      final deviceUid =
          widget.deviceUidOverride ?? await _deviceStore.getOrCreate();
      final res = await widget.api.verifyCheckoutEmail(
        accessToken: widget.session.accessToken,
        email: email,
        code: code,
        deviceUid: deviceUid,
        deviceName: greenVpnClientDeviceName(),
        platform: greenVpnClientPlatform(),
        appVersion: kAppVersion,
      );
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        setState(
          () => _status = res.message ?? 'Код не подошёл или уже истёк.',
        );
        return;
      }
      Navigator.of(context).pop(res.data);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Email для оплаты'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'На этот адрес придут подтверждение оплаты и уведомления о продлении. '
              'Он также позволит войти на другом устройстве.',
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('checkout_email'),
              controller: _email,
              enabled: !_busy && !_codeRequested,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (!_codeRequested) unawaited(_start());
              },
            ),
            if (_codeRequested) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('checkout_email_code'),
                controller: _code,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: 'Код из письма',
                  hintText: '0000',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => unawaited(_verify()),
              ),
            ],
            if ((_status ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _status!,
                style: const TextStyle(
                  color: kBrandMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : _codeRequested
              ? _verify
              : _start,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _codeRequested
                      ? Icons.check_rounded
                      : Icons.mark_email_read_rounded,
                ),
          label: Text(_codeRequested ? 'Подтвердить' : 'Получить код'),
        ),
      ],
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
  final String protocolCode;
  final bool clientConfigReady;
  final String accessTier;

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
    this.protocolCode = 'wireguard_udp',
    this.clientConfigReady = true,
    this.accessTier = 'free',
  });

  bool get isCurrentClientReady =>
      available &&
      clientConfigReady &&
      kSupportedVpnProtocols.contains(protocolCode);

  bool get requiresPaidSubscription =>
      greenVpnServerRequiresPaidSubscription(accessTier);

  String get publicLocationId =>
      greenVpnServerLocationId(serverId: id, country: country, city: city);

  String get publicLocationTitle => greenVpnServerLocationTitle(
    serverTitle: title,
    country: country,
    city: city,
  );

  static ServerLocation fromCatalogJson(Map<String, dynamic> json) {
    final endpoint = json['endpoint'];
    final endpointMap = endpoint is Map
        ? Map<String, dynamic>.from(endpoint)
        : <String, dynamic>{};
    final protocols = json['protocols'];
    String protocolLabel = 'WireGuard';
    String protocolCode = 'wireguard_udp';
    if (protocols is List && protocols.isNotEmpty && protocols.first is Map) {
      final first = Map<String, dynamic>.from(protocols.first as Map);
      protocolLabel = (first['title'] ?? first['code'] ?? protocolLabel)
          .toString();
      protocolCode = (first['code'] ?? protocolCode).toString();
    }
    final latencyRaw = json['latencyMs'];
    final scoreRaw = json['healthScore'];
    final country = (json['country'] ?? '').toString();
    final city = (json['city'] ?? '').toString();
    final defaultSubtitle = [
      if (city.isNotEmpty) city,
      if (country.isNotEmpty) country,
    ].join(' • ');
    return ServerLocation(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? 'Локация Green VPN').toString(),
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
      protocolCode: protocolCode,
      clientConfigReady: json['clientConfigReady'] != false,
      accessTier: greenVpnNormalizeServerAccessTier(
        (json['accessTier'] ?? 'free').toString(),
      ),
    );
  }
}

String greenVpnPublicServerTitle(ServerLocation server) {
  if (server.isAuto) return server.title;
  var text = server.publicLocationTitle.trim();
  text = text
      .replaceAll(RegExp(r'\bRU\s*VDS\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bRUVDS\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bTimeWeb\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bWireGuard\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bwireguard_udp\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bendpoint\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bhidden\s+test\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bVPN[-\s]*node\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s+#'), ' #')
      .trim();
  text = text.replaceAll(RegExp(r'^[\s\-•]+|[\s\-•]+$'), '').trim();
  if (text.isEmpty || text.toLowerCase() == 'green vpn') return 'Локация';
  return text;
}

ServerLocation? greenVpnResolveConnectedServerRoute({
  required Iterable<ServerLocation> servers,
  ServerLocation? activeRoute,
  bool runtimeDesired = false,
  String runtimeServerId = '',
  String runtimeProtocol = '',
  String cachedServerId = '',
  String cachedProtocol = '',
  DateTime? cachedAt,
  ServerLocation? selectedRoute,
  DateTime? now,
}) {
  ServerLocation? findRoute(String id, String protocol) {
    final normalizedId = greenVpnNormalizeManagedRouteId(id);
    final normalizedProtocol = protocol.trim().toLowerCase();
    if (normalizedId.isEmpty) return null;
    for (final server in servers) {
      if (server.isAuto ||
          greenVpnNormalizeManagedRouteId(server.id) != normalizedId) {
        continue;
      }
      if (normalizedProtocol.isNotEmpty &&
          server.protocolCode.trim().toLowerCase() != normalizedProtocol) {
        continue;
      }
      return server;
    }
    return null;
  }

  if (runtimeDesired) {
    final runtimeRoute = findRoute(runtimeServerId, runtimeProtocol);
    if (runtimeRoute != null) return runtimeRoute;
  }

  if (activeRoute != null && !activeRoute.isAuto) return activeRoute;

  final cachedRoute = findRoute(cachedServerId, cachedProtocol);
  final currentTime = now ?? DateTime.now().toUtc();
  if (cachedRoute != null &&
      greenVpnIsFreshPreferredRoute(
        candidateId: cachedRoute.id,
        candidateProtocol: cachedRoute.protocolCode,
        preferredId: cachedServerId,
        preferredProtocol: cachedProtocol,
        preferredAt: cachedAt,
        now: currentTime,
      )) {
    return cachedRoute;
  }

  if (selectedRoute != null && !selectedRoute.isAuto) return selectedRoute;
  return null;
}

String greenVpnConnectionRouteKey(ServerLocation? route) {
  if (route == null || route.isAuto) return '';
  return '${greenVpnNormalizeManagedRouteId(route.id)}|${route.protocolCode.trim().toLowerCase()}';
}

String greenVpnPublicServerSubtitle(
  ServerLocation server, {
  bool includeUnavailable = false,
}) {
  if (server.isAuto) return 'Автовыбор';
  if (includeUnavailable && !server.isCurrentClientReady) {
    return '${greenVpnPublicLatencyLabel(server.pingMs)} • недоступен';
  }
  return greenVpnPublicLatencyLabel(server.pingMs);
}

class ProvisionedConfigResult {
  final bool ok;
  final String? message;
  final ServerLocation? server;

  const ProvisionedConfigResult.ok(this.server) : ok = true, message = null;

  const ProvisionedConfigResult.err(this.message) : ok = false, server = null;
}

class PostConnectProbeResult {
  final bool ok;
  final String target;
  final int? statusCode;
  final int latencyMs;
  final String? error;

  const PostConnectProbeResult({
    required this.ok,
    required this.target,
    this.statusCode,
    required this.latencyMs,
    this.error,
  });
}

class _GreenVpnWindowsRuntimeSnapshot {
  final GreenVpnWindowsManagedTunnelState tunnelState;
  final GreenVpnWindowsRoutingMode routingMode;
  final bool processRouterRequired;
  final bool protectionConfirmed;
  final bool externalVpnActive;
  final bool externalVpnStateKnown;

  const _GreenVpnWindowsRuntimeSnapshot({
    required this.tunnelState,
    required this.routingMode,
    required this.processRouterRequired,
    required this.protectionConfirmed,
    required this.externalVpnActive,
    required this.externalVpnStateKnown,
  });
}

class _RoutingPreferenceSnapshot {
  final bool socialOnlyEnabled;
  final bool preferenceRequested;
  final Set<SocialApp> apps;
  final Set<String> customPackages;
  final Set<String> windowsApplications;
  final Set<String> windowsSites;
  final List<String> windowsDestinationCidrs;
  final ServerLocation? runtimeRoute;

  const _RoutingPreferenceSnapshot({
    required this.socialOnlyEnabled,
    required this.preferenceRequested,
    required this.apps,
    required this.customPackages,
    required this.windowsApplications,
    required this.windowsSites,
    required this.windowsDestinationCidrs,
    required this.runtimeRoute,
  });
}

enum SocialApp {
  telegram('Telegram', Icons.send_rounded),
  vk('VK', Icons.people_alt_rounded),
  instagram('Instagram', Icons.photo_camera_rounded),
  tiktok('TikTok', Icons.music_note_rounded),
  discord('Discord', Icons.forum_rounded),
  youtube('YouTube', Icons.play_circle_fill_rounded);

  const SocialApp(this.title, this.icon);
  final String title;
  final IconData icon;
}

final RegExp _androidPackageNamePattern = RegExp(
  r'^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$',
);

bool _isValidAndroidPackageName(String value) {
  final clean = value.trim();
  return clean.length <= 255 && _androidPackageNamePattern.hasMatch(clean);
}

const String _windowsApplicationProxyHost = '10.10.0.1';
const int _windowsApplicationProxyPort = 1080;

class _AndroidLaunchableApp {
  final String packageName;
  final String label;
  final bool system;

  const _AndroidLaunchableApp({
    required this.packageName,
    required this.label,
    required this.system,
  });

  static _AndroidLaunchableApp? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final packageName = (raw['packageName'] ?? '').toString().trim();
    if (!_isValidAndroidPackageName(packageName)) return null;
    final rawLabel = (raw['label'] ?? '').toString().trim();
    return _AndroidLaunchableApp(
      packageName: packageName,
      label: rawLabel.isEmpty ? packageName : rawLabel,
      system: raw['system'] == true,
    );
  }
}

class _FusionTrafficChoice {
  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onToggle;

  const _FusionTrafficChoice({
    required this.id,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.selected,
    required this.onToggle,
  });
}

class RootShell extends StatefulWidget {
  final ThemeMode themeMode;
  final void Function(ThemeMode mode) onThemeModeChanged;

  final Session session;
  final Future<void> Function() onLogout;
  final Future<void> Function(Session session) onSessionChanged;

  const RootShell({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.session,
    required this.onLogout,
    required this.onSessionChanged,
  });

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  final _api = const BlueVpnApi(baseUrl: kApiBaseUrl);
  final _cfg = ConfigStore();
  final _pendingBillingOrderStore = PendingBillingOrderStore();
  final RouteFailureCooldown _routeFailureCooldown = RouteFailureCooldown();
  final WindowsStandbyProofStore _windowsStandbyProofStore =
      WindowsStandbyProofStore();

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

  static const Map<SocialApp, List<String>> _socialDomains = {
    SocialApp.telegram: ['telegram.org', 't.me'],
    SocialApp.vk: [
      'vk.com',
      'vk.ru',
      'vkvideo.ru',
      'userapi.com',
      'vkuseraudio.net',
      'vkuserlive.net',
      'vkcdnservice.com',
    ],
    SocialApp.instagram: ['instagram.com', 'cdninstagram.com'],
    SocialApp.tiktok: ['tiktok.com', 'tiktokcdn.com', 'tiktokv.com'],
    SocialApp.discord: [
      'discord.com',
      'discord.gg',
      'discordapp.com',
      'discordapp.net',
    ],
    SocialApp.youtube: [
      'youtube.com',
      'youtu.be',
      'googlevideo.com',
      'ytimg.com',
    ],
  };

  static const Map<SocialApp, List<String>> _androidSocialPackageNames = {
    SocialApp.telegram: [
      'org.telegram.messenger',
      'org.telegram.messenger.web',
      'org.thunderdog.challegram',
    ],
    SocialApp.vk: ['com.vkontakte.android'],
    SocialApp.instagram: ['com.instagram.android'],
    SocialApp.youtube: ['com.google.android.youtube'],
    SocialApp.discord: ['com.discord'],
    SocialApp.tiktok: ['com.zhiliaoapp.musically'],
  };

  static const Map<String, List<String>> _serverEndpointAliases = {
    'intelligent_smew': ['37.220.85.211', 'nl1.vpn.greenvpn.pro'],
    'tw-7879598-nl1': ['5.129.216.42', 'nl2.vpn.greenvpn.pro'],
    'ruvds-2584554-ld8': ['88.218.250.86'],
  };

  static List<ServerLocation> _fallbackServerCatalogForCurrentChannel() {
    final list = <ServerLocation>[
      const ServerLocation(
        id: 'auto',
        title: 'Авто',
        subtitle: 'Автовыбор локации',
        pingMs: null,
        isAuto: true,
        status: 'healthy',
        available: true,
        clientConfigReady: true,
      ),
      const ServerLocation(
        id: 'intelligent_smew',
        title: 'Netherlands #1',
        subtitle: 'Netherlands',
        endpointHost: 'nl1.vpn.greenvpn.pro',
        pingMs: 44,
        country: 'NL',
        city: 'Amsterdam',
        status: 'healthy',
        available: true,
        healthScore: 100,
        clientConfigReady: true,
      ),
      const ServerLocation(
        id: 'tw-7879598-nl1',
        title: 'Netherlands #2',
        subtitle: 'Netherlands',
        endpointHost: 'nl2.vpn.greenvpn.pro',
        pingMs: 58,
        country: 'NL',
        city: 'Amsterdam',
        status: 'healthy',
        available: true,
        healthScore: 100,
        clientConfigReady: true,
      ),
      const ServerLocation(
        id: 'ruvds-2584554-ld8',
        title: 'London #1',
        subtitle: 'United Kingdom',
        endpointHost: '88.218.250.86',
        pingMs: 0,
        country: 'GB',
        city: 'London',
        status: 'maintenance',
        available: false,
        healthScore: 0,
        clientConfigReady: false,
      ),
    ];

    return list;
  }

  static List<ServerLocation> _mergeServerCatalogs(
    List<ServerLocation> primary,
    List<ServerLocation> secondary,
  ) {
    final merged = <ServerLocation>[];
    final seen = <String>{};

    void add(ServerLocation server) {
      final id = server.id.trim();
      if (id.isEmpty || !seen.add(id)) return;
      merged.add(server);
    }

    for (final server in primary) {
      add(server);
    }
    for (final server in secondary) {
      add(server);
    }

    if (!seen.contains('auto')) {
      merged.insert(
        0,
        const ServerLocation(
          id: 'auto',
          title: 'Авто',
          subtitle: 'Автовыбор локации',
          isAuto: true,
          status: 'healthy',
          available: true,
          clientConfigReady: true,
        ),
      );
    }

    return merged;
  }

  int _index = 0;
  Future<void> _fusionUiDiagnosticWriteTail = Future<void>.value();
  bool _fusionUiDiagnosticScheduled = false;
  int _fusionUiDiagnosticSequence = 0;

  // VPN state
  bool vpnEnabled = false;
  bool vpnBusy = false;
  bool _externalVpnActive = false;
  bool _windowsProtectionConfirmed = false;
  bool _windowsFullTunnelDataPlaneConfirmed = false;

  // "Только для соцсетей"
  bool socialOnlyEnabled = false;
  bool _socialOnlyPreferenceRequested = false;
  final Set<SocialApp> socialOnlyApps = {
    SocialApp.telegram,
    SocialApp.instagram,
  };
  final Set<String> socialOnlyCustomPackages = <String>{};
  final Set<String> socialOnlyWindowsApplications = <String>{};
  final Set<String> socialOnlyWindowsSites = <String>{};
  final Map<String, String> _androidInstalledAppLabels = <String, String>{};
  final Map<String, String> _windowsInstalledAppLabels = <String, String>{};
  List<String> _windowsSelectiveDestinationCidrs = const <String>[];

  // Сервер
  List<ServerLocation> servers = _fallbackServerCatalogForCurrentChannel();

  ServerLocation selectedServer = const ServerLocation(
    id: 'auto',
    title: 'Авто',
    subtitle: 'Автовыбор локации',
    pingMs: null,
    isAuto: true,
  );
  String _persistedServerId = 'auto';

  String _serverSelectionKey(ServerLocation server) =>
      server.isAuto ? 'auto' : server.publicLocationId;

  bool _serverMatchesSelection(ServerLocation server, String selection) {
    final normalized = selection.trim();
    if (normalized.isEmpty || normalized == 'auto') return server.isAuto;
    return server.id == normalized || server.publicLocationId == normalized;
  }

  // ===== TARIFF STATE =====
  final Set<TariffApp> selectedApps = {};
  TrafficPack trafficPack = TrafficPack.gb20; // "режим" (по ГБ / безлимит)
  double trafficGb = 20; // любой объём ГБ
  int devices = kPaidBetaBuild ? 2 : 1;
  String _publicBillingPlanCode = 'green_30d';

  bool optNoAds = true;
  bool optSmartRouting = true; // этим флагом управляем доступностью "соцсетей"
  bool optDedicatedIp = false;
  bool optAutoRenew = false;

  // Legacy builds retain the existing single-language settings row.
  String sLanguage = 'Русский';

  // Local prefs (persist UI settings)
  final PrefsStore _prefsStore = PrefsStore();
  final PendingVpnActionStore _pendingVpnActionStore = PendingVpnActionStore();
  Timer? _prefsDebounce;
  Timer? _tariffDebounce;
  Timer? _vpnTapCooldownTimer;
  Timer? _pendingBillingPollTimer;
  Timer? _freeAdSessionTimer;
  Timer? _windowsRuntimeFailoverTimer;
  Timer? _windowsRouteMaintenanceTimer;
  Timer? _windowsStatusReconciliationTimer;
  Timer? _vpnPauseTimer;
  Timer? _connectionUiTimer;
  int _androidPauseResumePollCount = 0;
  ServerLocation? _activeWindowsRuntimeRoute;
  ServerLocation? _activeConnectionRoute;
  int _windowsRuntimeFailoverEpoch = 0;
  int _windowsRuntimeFailureCount = 0;
  DateTime? _windowsRuntimeLastHealthyAt;
  DateTime? _windowsRuntimeRecoveryProofCutoff;
  bool _windowsRuntimeProbeRunning = false;
  bool _windowsRuntimeRecoveryRunning = false;
  bool _windowsRuntimeRestoreRunning = false;
  bool _windowsStandbyCycleRunning = false;
  bool _windowsStandbyProofsLoaded = false;
  final Map<String, GreenVpnStandbyRouteProof> _windowsStandbyProofs =
      <String, GreenVpnStandbyRouteProof>{};
  final Map<String, DateTime> _windowsStandbyRetryAfter = <String, DateTime>{};
  int _vpnStatusSyncEpoch = 0;
  bool _prefsLoaded = false;
  WireGuardInstallState? _wireGuardState;
  bool _wireGuardBusy = false;
  bool _tariffBusy = false;
  bool _serverCatalogBusy = false;
  final SingleFlightOperation _serverCatalogRefresh = SingleFlightOperation();
  Map<String, dynamic>? _tariffCatalog;
  Map<String, dynamic>? _tariffQuote;
  String? _tariffStatus;
  String? _serverCatalogStatus;
  String? _adaptiveRouteServerId;
  String? _adaptiveRouteProtocol;
  int? _adaptiveRouteScore;
  String _lastSuccessfulRouteId = '';
  String _lastSuccessfulRouteProtocol = '';
  DateTime? _lastSuccessfulRouteAt;
  bool _subscriptionActive = false;
  bool _paidSubscriptionActive = false;
  bool _subscriptionEntitlementResolved = false;
  String _subscriptionPlanCode = 'base';
  String? _paidSubscriptionPlanName;
  String _paidSubscriptionStatus = 'inactive';
  bool _freeTierActive = false;
  Map<String, dynamic> _trafficUsage = <String, dynamic>{};
  int _subscriptionMaxDevices = kPaidBetaBuild ? 2 : 1;
  bool _subscriptionAutoRenew = false;
  bool _paymentMethodSaved = false;
  String? _subscriptionAccessStartsAt;
  String? _subscriptionExpiresAt;
  int _subscriptionRevision = 0;
  int? _subscriptionMonthlyPriceRub;
  bool _vpnTapCooldown = false;
  bool _pendingBillingCheckRunning = false;
  String? _vpnBusyStage;
  String? _vpnBusyHint;
  DateTime? _vpnPausedUntil;
  DateTime? _connectionStartedAt;
  int? _activeConnectionLatencyMs;
  final Set<String> _favoriteLocationIds = <String>{};
  final List<String> _recentLocationIds = <String>[];
  WindowsCloseBehavior _windowsCloseBehavior =
      WindowsCloseBehavior.minimizeToTray;
  Map<String, bool> _clientFeatures = const <String, bool>{};
  bool _pendingVpnResumeScheduled = false;
  Map<String, dynamic>? _pendingBillingOrder;
  late bool _emailVerified;
  late bool _emailConfirmationRequired;
  bool _emailStatusBusy = false;
  String? _emailStatusMessage;
  bool _updateCheckBusy = false;
  bool _forcedUpdateRouteOpen = false;
  String? _updatePromptVersionInFlight;
  bool _sessionInvalidationInProgress = false;
  static const String _freeAdSessionExpiryPrefsKey =
      'greenvpn.free_ad_session.expires_at';

  void goToTab(int i) => setState(() => _index = i);

  void _scheduleFusionUiDiagnostic() {
    if (kIsWeb ||
        !Platform.isWindows ||
        !kFusionUiEnabled ||
        greenVpnFusionUiDiagnosticPathSync() == null ||
        _fusionUiDiagnosticScheduled) {
      return;
    }
    _fusionUiDiagnosticScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fusionUiDiagnosticScheduled = false;
      if (mounted) unawaited(_writeFusionUiDiagnostic());
    });
  }

  Future<void> _writeFusionUiDiagnostic() async {
    final path = greenVpnFusionUiDiagnosticPathSync();
    if (path == null || !mounted) return;
    final paused = _vpnPausePending;
    final presentation = greenVpnFusionConnectionPresentation(
      vpnEnabled: vpnEnabled,
      windowsProtectionConfirmed: _windowsProtectionConfirmed,
      externalVpnActive: _externalVpnActive,
      socialOnlyEnabled: socialOnlyEnabled,
      vpnBusy: vpnBusy,
      vpnBusyStage: _vpnBusyStage,
      vpnBusyHint: _vpnBusyHint,
      paused: paused,
      pausedUntil: _vpnPausedUntil,
    );
    final sequence = ++_fusionUiDiagnosticSequence;
    final snapshot = <String, dynamic>{
      'schemaVersion': 1,
      'sequence': sequence,
      'updatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'appVersion': kAppVersion,
      'runtimeScope': greenVpnWindowsRuntimeScope,
      'publicProductBuild': kPublicProductBuild,
      'paidBetaBuild': kPaidBetaBuild,
      'fusionProductionCandidate': kFusionProductionPromotionCandidate,
      'currentPage': switch (_index) {
        0 => 'vpn',
        1 => 'mode',
        _ => 'settings',
      },
      'vpnEnabled': vpnEnabled,
      'vpnBusy': vpnBusy,
      'windowsProtectionConfirmed': _windowsProtectionConfirmed,
      'windowsFullTunnelDataPlaneConfirmed':
          _windowsFullTunnelDataPlaneConfirmed,
      'processRouterRequired': _windowsProcessRouterRequired,
      'externalVpnActive': _externalVpnActive,
      'socialOnlyEnabled': socialOnlyEnabled,
      'selectedTrafficCount': _selectedTrafficTitles().length,
      'paidEntitlement': _hasPaidSubscriptionEntitlement,
      'protectionActive': presentation.protectionActive,
      'connectedCheckVisible': presentation.connectedCheckVisible,
      'statusKey': presentation.statusKey,
      'statusText': presentation.statusText,
      'statusDetail': presentation.statusDetail,
      'badgeText': presentation.badgeText,
    };
    final previous = _fusionUiDiagnosticWriteTail;
    final next = () async {
      try {
        await previous;
      } catch (_) {}
      try {
        final target = File(path);
        await target.parent.create(recursive: true);
        final temporary = File('$path.$sequence.tmp');
        await temporary.writeAsString(jsonEncode(snapshot), flush: true);
        if (await target.exists()) await target.delete();
        await temporary.rename(path);
      } catch (error) {
        await appendBlueVpnClientLog(
          'fusion ui diagnostic write failed type=${error.runtimeType}',
        );
      }
    }();
    _fusionUiDiagnosticWriteTail = next;
    await next;
  }

  bool get _vpnInteractionLocked => vpnBusy || _vpnTapCooldown;

  bool _clientFeatureEnabled(String key) {
    return fusionClientFeatureEnabled(
      key: key,
      serverFeatures: _clientFeatures,
      fusionUiEnabled: kFusionUiEnabled,
      publicProductBuild: kPublicProductBuild,
      productionPromotionCandidate: kFusionProductionPromotionCandidate,
      developerSession: widget.session.accessToken == 'dev-token',
    );
  }

  bool get _vpnPauseActive {
    final until = _vpnPausedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  bool get _vpnPausePending => _vpnPausedUntil != null && !vpnEnabled;

  void _applyClientFeatures(Object? raw) {
    final next = <String, bool>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key.toString().trim();
        if (key.isNotEmpty) next[key] = entry.value == true;
      }
    }
    _clientFeatures = Map<String, bool>.unmodifiable(next);
  }

  Future<void> _applyWindowsCloseBehavior() async {
    if (kIsWeb || !Platform.isWindows) return;
    final effectiveBehavior =
        _clientFeatureEnabled(kFusionWindowsCloseBehaviorFlag)
        ? _windowsCloseBehavior
        : WindowsCloseBehavior.minimizeToTray;
    try {
      await kWindowsWindowChannel.invokeMethod<void>('setCloseBehavior', {
        'behavior': effectiveBehavior.code,
      });
    } catch (error) {
      await appendBlueVpnClientLog(
        'windows close behavior apply failed error=$error',
      );
    }
  }

  Future<void> _setWindowsCloseBehavior(WindowsCloseBehavior behavior) async {
    if (_windowsCloseBehavior == behavior) return;
    setState(() => _windowsCloseBehavior = behavior);
    _schedulePrefsSave();
    await _applyWindowsCloseBehavior();
  }

  void _startConnectionUiTimer() {
    _connectionUiTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !vpnEnabled) return;
      setState(() {});
    });
  }

  void _stopConnectionUiTimer() {
    _connectionUiTimer?.cancel();
    _connectionUiTimer = null;
  }

  void _rememberLocation(ServerLocation? route) {
    if (route == null || route.isAuto) return;
    final locationId = route.publicLocationId.trim();
    if (locationId.isEmpty) return;
    _recentLocationIds
      ..remove(locationId)
      ..insert(0, locationId);
    if (_recentLocationIds.length > 8) {
      _recentLocationIds.removeRange(8, _recentLocationIds.length);
    }
    _schedulePrefsSave();
  }

  void _toggleFavoriteLocation(ServerLocation route) {
    if (route.isAuto) return;
    final locationId = route.publicLocationId.trim();
    if (locationId.isEmpty) return;
    setState(() {
      if (!_favoriteLocationIds.add(locationId)) {
        _favoriteLocationIds.remove(locationId);
      }
    });
    _schedulePrefsSave();
  }

  void _trackConnectionState(
    bool connected, {
    ServerLocation? route,
    int? latencyMs,
  }) {
    if (!kFusionUiEnabled || !mounted) return;
    if (connected) {
      final effectiveRoute = route ?? _activeConnectionRoute;
      final previousRouteKey = _connectionRouteKey(_activeConnectionRoute);
      final effectiveRouteKey = _connectionRouteKey(effectiveRoute);
      final routeChanged =
          previousRouteKey.isNotEmpty &&
          effectiveRouteKey.isNotEmpty &&
          previousRouteKey != effectiveRouteKey;
      setState(() {
        _connectionStartedAt ??= DateTime.now();
        if (effectiveRoute != null) _activeConnectionRoute = effectiveRoute;
        if (routeChanged) {
          _activeConnectionLatencyMs = latencyMs != null && latencyMs >= 0
              ? latencyMs
              : effectiveRoute?.pingMs;
        } else if (latencyMs != null && latencyMs >= 0) {
          _activeConnectionLatencyMs = latencyMs;
        } else {
          _activeConnectionLatencyMs ??= effectiveRoute?.pingMs;
        }
      });
      _startConnectionUiTimer();
      _rememberLocation(effectiveRoute);
      return;
    }

    if (_connectionStartedAt == null &&
        _activeConnectionRoute == null &&
        _activeConnectionLatencyMs == null) {
      return;
    }
    _stopConnectionUiTimer();
    setState(() {
      _connectionStartedAt = null;
      _activeConnectionRoute = null;
      _activeConnectionLatencyMs = null;
    });
  }

  String _connectionRouteKey(ServerLocation? route) {
    return greenVpnConnectionRouteKey(route);
  }

  Future<ServerLocation?> _resolveAndroidConnectedRoute() async {
    Map<String, dynamic> runtimeStatus = const <String, dynamic>{};
    try {
      runtimeStatus =
          await kAndroidPlatformChannel.invokeMapMethod<String, dynamic>(
            'runtimeFailoverStatus',
          ) ??
          const <String, dynamic>{};
    } catch (error) {
      await appendBlueVpnClientLog(
        'android connected route runtime status failed error=$error',
      );
    }

    final route = greenVpnResolveConnectedServerRoute(
      servers: servers,
      activeRoute: _activeConnectionRoute,
      runtimeDesired: runtimeStatus['desired'] == true,
      runtimeServerId: (runtimeStatus['serverId'] ?? '').toString(),
      runtimeProtocol: (runtimeStatus['protocol'] ?? '').toString(),
      cachedServerId: _lastSuccessfulRouteId,
      cachedProtocol: _lastSuccessfulRouteProtocol,
      cachedAt: _lastSuccessfulRouteAt,
      selectedRoute: selectedServer,
      now: DateTime.now().toUtc(),
    );
    if (route != null && route.id != _activeConnectionRoute?.id) {
      await appendBlueVpnClientLog(
        'android connected route restored server=${route.id} protocol=${route.protocolCode} runtimeDesired=${runtimeStatus['desired'] == true}',
      );
    }
    return route;
  }

  Future<bool> _cancelAndroidPauseResume() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final response = await kAndroidPlatformChannel
          .invokeMapMethod<String, dynamic>('cancelRuntimeResume');
      return response?['ok'] == true;
    } catch (error) {
      await appendBlueVpnClientLog(
        'android pause resume cancel failed error=$error',
      );
      return false;
    }
  }

  Future<bool> _scheduleAndroidPauseResume(
    DateTime until,
    ServerLocation? route,
  ) async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final response = await kAndroidPlatformChannel
          .invokeMapMethod<String, dynamic>('scheduleRuntimeResume', {
            'resumeAtMs': until.millisecondsSinceEpoch,
            'serverId': route?.id ?? '',
            'protocol': route?.protocolCode ?? 'wireguard_udp',
          });
      return response?['ok'] == true;
    } catch (error) {
      await appendBlueVpnClientLog(
        'android pause resume schedule failed error=$error',
      );
      return false;
    }
  }

  void _armVpnPauseTimer() {
    _vpnPauseTimer?.cancel();
    _vpnPauseTimer = null;
    final until = _vpnPausedUntil;
    if (until == null) return;
    final delay = until.difference(DateTime.now());
    if (delay <= Duration.zero) {
      unawaited(_resumeVpnAfterPause(automatic: true));
      return;
    }
    _vpnPauseTimer = Timer(delay, () {
      unawaited(_resumeVpnAfterPause(automatic: true));
    });
  }

  Future<void> _pauseVpn(Duration duration) async {
    if (!_clientFeatureEnabled(kFusionConnectionActionsFlag) ||
        !vpnEnabled ||
        _vpnInteractionLocked) {
      return;
    }
    final route =
        _activeConnectionRoute ??
        _activeWindowsRuntimeRoute ??
        _connectCandidatesForCurrentSelection().firstOrNull;
    final until = DateTime.now().add(duration);
    _androidPauseResumePollCount = 0;
    setState(() => _vpnPausedUntil = until);
    _schedulePrefsSave();
    await _toggleVpnReal();
    if (!mounted) return;
    if (vpnEnabled) {
      setState(() => _vpnPausedUntil = null);
      _schedulePrefsSave();
      _toast(context, 'Не удалось приостановить VPN. Подключение сохранено.');
      return;
    }
    final scheduled = await _scheduleAndroidPauseResume(until, route);
    if (!mounted) return;
    if (!scheduled && !kIsWeb && Platform.isAndroid) {
      setState(() => _vpnPausedUntil = null);
      _schedulePrefsSave();
      _toast(
        context,
        'Android не смог запланировать автозапуск. VPN оставлен выключенным.',
      );
      return;
    }
    _armVpnPauseTimer();
    final minutes = duration.inMinutes;
    _toast(context, 'VPN приостановлен на $minutes мин.');
  }

  Future<void> _resumeVpnAfterPause({required bool automatic}) async {
    final hadPause = _vpnPausedUntil != null;
    _vpnPauseTimer?.cancel();
    _vpnPauseTimer = null;
    if (!hadPause) return;

    if (!kIsWeb && Platform.isAndroid && automatic) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _syncVpnStatus(source: 'android_pause_elapsed');
      if (!mounted) return;
      if (!vpnEnabled) {
        _androidPauseResumePollCount += 1;
        if (_androidPauseResumePollCount >= 60) {
          await appendBlueVpnClientLog(
            'android pause resume UI polling stopped after five minutes',
          );
          final cancelled = await _cancelAndroidPauseResume();
          if (!cancelled) {
            _vpnPauseTimer = Timer(const Duration(seconds: 5), () {
              unawaited(_resumeVpnAfterPause(automatic: true));
            });
            return;
          }
          if (mounted) {
            setState(() => _vpnPausedUntil = null);
            _schedulePrefsSave();
            _toast(
              context,
              'Не удалось автоматически возобновить VPN. Нажмите кнопку подключения.',
            );
          }
          return;
        }
        _vpnPauseTimer = Timer(const Duration(seconds: 5), () {
          unawaited(_resumeVpnAfterPause(automatic: true));
        });
        return;
      }
    } else {
      _androidPauseResumePollCount = 0;
      final cancelled = await _cancelAndroidPauseResume();
      if (!cancelled) {
        if (mounted) {
          _toast(
            context,
            'Не удалось отменить автозапуск. Повторите через несколько секунд.',
          );
        }
        return;
      }
      if (!kIsWeb && Platform.isAndroid) {
        await _syncVpnStatus(source: 'android_pause_manual_resume');
        if (!mounted) return;
      }
      if (!vpnEnabled) {
        setState(() => _vpnPausedUntil = null);
        _schedulePrefsSave();
        await _toggleVpnReal();
        if (!mounted || !vpnEnabled) return;
      }
    }

    if (mounted) setState(() => _vpnPausedUntil = null);
    _androidPauseResumePollCount = 0;
    _schedulePrefsSave();
    if (!automatic && mounted) _toast(context, 'VPN возобновлён.');
  }

  Future<void> _openVpnPauseMenu() async {
    if (!_clientFeatureEnabled(kFusionConnectionActionsFlag)) return;
    if (_vpnPauseActive) {
      await _resumeVpnAfterPause(automatic: false);
      return;
    }
    if (!vpnEnabled) return;
    final duration = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Приостановить VPN',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'VPN включится автоматически.',
                style: TextStyle(
                  color: Theme.of(
                    ctx,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              for (final minutes in const <int>[5, 30, 60])
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text('$minutes минут'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      Navigator.of(ctx).pop(Duration(minutes: minutes)),
                ),
            ],
          ),
        ),
      ),
    );
    if (duration != null) await _pauseVpn(duration);
  }

  Future<void> _changeRouteAutomatically() async {
    if (!_clientFeatureEnabled(kFusionConnectionActionsFlag) ||
        !vpnEnabled ||
        _vpnInteractionLocked) {
      return;
    }
    await _refreshServerCatalog(showToast: false);
    if (!mounted) return;
    final activeLocation =
        (_activeConnectionRoute ?? selectedServer).publicLocationId;
    final alternatives = _serverPickerLocations()
        .where(
          (route) =>
              !route.isAuto &&
              route.isCurrentClientReady &&
              (!route.requiresPaidSubscription ||
                  _hasPaidSubscriptionEntitlement) &&
              route.publicLocationId != activeLocation,
        )
        .toList();
    if (alternatives.isEmpty) {
      _toast(context, 'Сейчас нет другой готовой локации.');
      return;
    }
    final originalSelection = selectedServer;
    final originalPersistedId = _persistedServerId;
    try {
      await _selectServerAndReconnectIfNeeded(
        alternatives.first,
        persistSelection: false,
      );
    } finally {
      if (mounted) {
        setState(() => selectedServer = originalSelection);
        _persistedServerId = originalPersistedId;
        _schedulePrefsSave();
      }
    }
  }

  bool get _hasPaidSubscriptionEntitlement => greenVpnHasPaidEntitlement(
    isActive: _subscriptionActive,
    planCode: _subscriptionPlanCode,
    planName: planName,
    monthlyPriceRub: _subscriptionMonthlyPriceRub,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vpnBackend = VpnBackend.createDefault(tunnelName: kTunnelName);
    _emailVerified = widget.session.emailVerified;
    _emailConfirmationRequired = widget.session.emailConfirmationRequired;

    unawaited(() async {
      await _loadPrefsAndApply();
      await _syncVpnStatus(source: 'startup_after_prefs');
    }());
    if (kPaidBetaBuild) {
      unawaited(_recordPaidBetaEvent('app_open'));
    }

    if (!kIsWeb && Platform.isWindows) {
      unawaited(_loadWindowsStandbyProofs());
      _windowsStatusReconciliationTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) {
          if (mounted &&
              _prefsLoaded &&
              !vpnBusy &&
              !_windowsRuntimeRecoveryRunning) {
            unawaited(_syncVpnStatus(source: 'windows_periodic'));
          }
        },
      );
    }
    unawaited(_restoreFreeAdSessionTimer());
    _ensureProvisionedConfigSilently();
    _syncPlanSilently();
    _syncTariffFromServerSilently();
    _loadPendingBillingOrder();
    _refreshTariffServerState(showToast: false);
    _refreshServerCatalog(showToast: false);
    if (!widget.session.isGuest) {
      _refreshEmailStatus(showToast: false);
    }
    unawaited(_refreshWireGuardState());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkRequiredUpdateSilently());
    });
  }

  @override
  void didUpdateWidget(covariant RootShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.accessToken == widget.session.accessToken) return;
    _emailVerified = widget.session.emailVerified;
    _emailConfirmationRequired = widget.session.emailConfirmationRequired;
    _emailStatusMessage = widget.session.isGuest
        ? null
        : widget.session.emailVerified
        ? 'Почта подтверждена.'
        : 'Почта пока не подтверждена.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppResumed());
      unawaited(_restoreFreeAdSessionTimer());
      unawaited(_checkRequiredUpdateSilently());
    }
  }

  Future<void> _handleAppResumed() async {
    if (!kIsWeb && Platform.isWindows) {
      await _syncVpnStatus(source: 'windows_resume');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted && !vpnBusy) {
        await _syncVpnStatus(source: 'windows_resume_retry');
      }
      return;
    }
    if (kIsWeb || !Platform.isAndroid) {
      await _syncVpnStatus(source: 'app_resume');
      return;
    }
    if (vpnBusy) return;
    final wasEnabledBeforeResume = vpnEnabled;
    try {
      final status = await WireGuardAndroidBackend.statusSnapshot(
        tunnelName: kTunnelName,
      );
      final connected = _androidStatusLooksLikeOwnTunnel(status);
      final systemVpnActive = status['systemVpnActive'] == true;
      final externalVpnActive = _androidStatusLooksLikeExternalVpn(status);
      await appendBlueVpnClientLog(
        'android resume vpn status connected=$connected systemVpnActive=$systemVpnActive externalVpnActive=$externalVpnActive wasEnabled=$wasEnabledBeforeResume state=${status['state'] ?? ""} status=$status',
      );
      if (connected) {
        final activeRoute = await _resolveAndroidConnectedRoute();
        if (!mounted) return;
        if (mounted) {
          setState(() {
            vpnEnabled = true;
            _externalVpnActive = false;
          });
          _trackConnectionState(true, route: activeRoute);
        }
        return;
      }

      if (externalVpnActive || systemVpnActive) {
        if (mounted) {
          setState(() {
            vpnEnabled = false;
            _externalVpnActive = true;
          });
          _trackConnectionState(false);
        }
        await appendBlueVpnClientLog(
          'android resume detected external system VPN without confirmed own tunnel',
        );
        return;
      }

      await _syncVpnStatus(source: 'android_resume');
      await appendBlueVpnClientLog(
        'android resume sync done vpnEnabled=$vpnEnabled',
      );
    } catch (e) {
      await appendBlueVpnClientLog('android resume status sync failed=$e');
      await _syncVpnStatus(source: 'android_resume_error');
    }
  }

  void _toast(BuildContext context, String text) {
    final friendlyErrorsEnabled =
        kPublicProductBuild || _clientFeatureEnabled(kFusionFriendlyErrorsFlag);
    final visibleText = friendlyErrorsEnabled
        ? greenVpnPublicErrorMessage(
            rawError: text,
            fallback: 'Не удалось выполнить действие. Попробуйте ещё раз.',
          )
        : text;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(visibleText)));
  }

  String _safeSessionInvalidationReason(String? message) {
    final raw = (message ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.isEmpty) return 'empty';
    if (raw.length <= 180) return raw;
    return '${raw.substring(0, 180)}...';
  }

  Future<Session?> _renewGuestSession({
    required String source,
    bool showToast = false,
  }) async {
    if (!widget.session.isGuest) return widget.session;
    try {
      final deviceUid = await _ensureDeviceId();
      if (deviceUid == null || deviceUid.isEmpty) {
        throw StateError('device_uid_unavailable');
      }
      final result = await _api.createGuestSession(
        deviceUid: deviceUid,
        deviceName: greenVpnClientDeviceName(),
        platform: greenVpnClientPlatform(),
        appVersion: kAppVersion,
      );
      if (!result.ok || result.data == null) {
        await appendBlueVpnClientLog(
          'guest session refresh failed source=$source message=${result.message ?? ""}',
        );
        if (showToast && mounted) {
          _toast(
            context,
            'Не удалось обновить бесплатный профиль. Повторите попытку.',
          );
        }
        return null;
      }

      final session = result.data!;
      await widget.onSessionChanged(session);
      await appendBlueVpnClientLog('guest session refreshed source=$source');
      if (showToast && mounted) {
        _toast(context, 'Бесплатный профиль обновлён.');
      }
      return session;
    } catch (e) {
      await appendBlueVpnClientLog(
        'guest session refresh exception source=$source type=${e.runtimeType}',
      );
      if (showToast && mounted) {
        _toast(
          context,
          'Не удалось обновить бесплатный профиль. Повторите попытку.',
        );
      }
      return null;
    }
  }

  Future<void> _handleInvalidSession({
    required String source,
    String? message,
    bool logout = true,
    bool disconnectVpn = false,
    bool clearManagedConfig = false,
    bool showToast = true,
  }) async {
    if (_sessionInvalidationInProgress) return;
    _sessionInvalidationInProgress = true;
    try {
      final expiredSessionAction = greenVpnExpiredSessionAction(
        isGuest: widget.session.isGuest,
      );
      if (logout &&
          expiredSessionAction == GreenVpnExpiredSessionAction.refreshGuest) {
        final renewed = await _renewGuestSession(
          source: source,
          showToast: showToast,
        );
        if (renewed != null) return;
        return;
      }

      final reason = _safeSessionInvalidationReason(message);
      await appendBlueVpnClientLog(
        'invalid session detected source=$source logout=$logout disconnectVpn=$disconnectVpn reason=$reason',
      );

      _prefsDebounce?.cancel();
      _tariffDebounce?.cancel();
      _vpnTapCooldownTimer?.cancel();
      _stopPendingBillingPolling();
      _cancelFreeAdSessionTimer();

      try {
        await _pendingVpnActionStore.clear();
      } catch (_) {}
      if (clearManagedConfig) {
        try {
          await _cfg.deleteManagedConfig();
        } catch (_) {}
      }
      if (disconnectVpn) {
        _disarmWindowsRuntimeFailover(reason: 'session_invalidation');
        try {
          await _vpnBackend.disconnect().timeout(const Duration(seconds: 8));
        } catch (e) {
          await appendBlueVpnClientLog(
            'invalid session tunnel cleanup failed source=$source error=$e',
          );
        }
      }

      if (mounted) {
        setState(() {
          if (disconnectVpn) {
            vpnEnabled = false;
            _externalVpnActive = false;
          }
          vpnBusy = false;
          _vpnBusyStage = null;
          _vpnBusyHint = null;
        });
        if (showToast) _toast(context, 'Сессия истекла. Войди снова.');
      }

      if (logout) {
        await widget.onLogout();
      } else {
        await _syncVpnStatus();
      }
    } finally {
      _sessionInvalidationInProgress = false;
    }
  }

  Future<void> _noteInvalidSession({
    required String source,
    String? message,
    bool showToast = false,
  }) async {
    final reason = _safeSessionInvalidationReason(message);
    await appendBlueVpnClientLog(
      'invalid session ignored source=$source reason=$reason',
    );
    if (showToast && mounted) {
      _toast(context, 'Не удалось обновить аккаунт. VPN продолжает работать.');
    }
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
      if (greenVpnIsInvalidSessionMessage(res.message)) {
        if (!showToast) {
          await _noteInvalidSession(
            source: 'email_status',
            message: res.message,
          );
          return;
        }
        await _handleInvalidSession(
          source: 'email_status',
          message: res.message,
        );
        return;
      }
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
      if (greenVpnIsInvalidSessionMessage(res.message)) {
        await _handleInvalidSession(
          source: 'email_confirmation_resend',
          message: res.message,
        );
        return;
      }
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

  Future<void> _loadPrefsAndApply() async {
    if (kIsWeb) return;

    try {
      final p = await _prefsStore.readPrefs();
      if (!mounted) return;

      // English UI is not shipped yet, so the legacy row remains Russian-only.
      sLanguage = 'Русский';

      // Apply server
      _persistedServerId = p.serverId.trim().isEmpty
          ? 'auto'
          : p.serverId.trim();
      final matchingServers = servers.where(
        (s) => _serverMatchesSelection(s, _persistedServerId),
      );
      if (matchingServers.isNotEmpty) {
        selectedServer = matchingServers.first;
      }
      _lastSuccessfulRouteId = greenVpnNormalizeManagedRouteId(
        p.lastSuccessfulRouteId,
      );
      _lastSuccessfulRouteProtocol = p.lastSuccessfulRouteProtocol
          .trim()
          .toLowerCase();
      _lastSuccessfulRouteAt = DateTime.tryParse(
        p.lastSuccessfulRouteAt,
      )?.toUtc();
      _favoriteLocationIds.clear();
      _recentLocationIds.clear();
      _vpnPausedUntil = null;
      _windowsCloseBehavior = WindowsCloseBehavior.minimizeToTray;
      if (kFusionUiEnabled) {
        _favoriteLocationIds.addAll(
          p.favoriteLocationIds
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .take(24),
        );
        _recentLocationIds.addAll(
          p.recentLocationIds
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .take(8),
        );
        _vpnPausedUntil = DateTime.tryParse(p.vpnPauseUntil)?.toLocal();
        _windowsCloseBehavior = WindowsCloseBehavior.fromCode(
          p.windowsCloseBehavior,
        );
      }

      // Apply social-only
      _socialOnlyPreferenceRequested = p.socialOnlyEnabled;
      socialOnlyEnabled =
          p.socialOnlyEnabled && _hasPaidSubscriptionEntitlement;
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
      socialOnlyCustomPackages
        ..clear()
        ..addAll(
          p.socialOnlyCustomPackages
              .map((value) => value.trim())
              .where(_isValidAndroidPackageName),
        );
      if (Platform.isAndroid && socialOnlyCustomPackages.isNotEmpty) {
        try {
          await _loadAndroidLaunchableApps();
        } catch (_) {
          // Stored package names remain usable even if Android hides an app label.
        }
      }
      socialOnlyWindowsApplications
        ..clear()
        ..addAll(
          p.socialOnlyWindowsApplications
              .map((value) => value.trim())
              .where(isValidWindowsApplicationPath)
              .take(maxWindowsVpnApplications),
        );
      socialOnlyWindowsSites
        ..clear()
        ..addAll(
          p.socialOnlyWindowsSites
              .map(normalizeWindowsVpnSite)
              .whereType<String>()
              .take(maxWindowsVpnSites),
        );
      if (Platform.isWindows &&
          socialOnlyEnabled &&
          socialOnlyApps.isEmpty &&
          socialOnlyWindowsApplications.isEmpty &&
          socialOnlyWindowsSites.isEmpty) {
        // An empty selective policy must never look enabled to the user.
        socialOnlyEnabled = false;
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

      trafficPack = kPaidBetaBuild
          ? TrafficPack.gb20
          : TrafficPack.values.firstWhere(
              (e) => e.name == p.trafficPack,
              orElse: () => TrafficPack.gb20,
            );
      trafficGb = kPaidBetaBuild ? 20 : p.trafficGb.clamp(1.0, 800.0);
      devices = kPaidBetaBuild ? 2 : p.devices.clamp(1, 5);

      optNoAds = true;
      optSmartRouting =
          true; // временно всегда разрешаем режим соцсетей в Windows-клиенте
      optDedicatedIp = (kPaidBetaBuild || kPublicProductBuild)
          ? false
          : p.optDedicatedIp;
      optAutoRenew =
          kPaidBetaBuild || (kPublicProductBuild && widget.session.isGuest)
          ? false
          : p.optAutoRenew;

      await _syncWindowsRoutingPolicy();
      if (!kPublicProductBuild && !kPaidBetaBuild) {
        await _repairProvisionedConfigFromPreferredDevSource(showToast: false);
      }
      await _cfg.ensureBaseSeededFromManagedIfMissing();
      if (kIsWeb || !Platform.isWindows) {
        final base = await _cfg.readBaseConfig();
        if (base != null && base.trim().isNotEmpty) {
          await _cfg.writeManagedConfig(_buildManagedConfigFromBase(base));
        }
      }

      if (mounted) setState(() {});
      await _applyWindowsCloseBehavior();
      if (kFusionUiEnabled) _armVpnPauseTimer();
    } catch (_) {
      // ignore
    } finally {
      _prefsLoaded = true;
      if (mounted && vpnEnabled) {
        if (!kIsWeb && Platform.isAndroid) {
          unawaited(() async {
            final activeRoute = await _resolveAndroidConnectedRoute();
            if (mounted && vpnEnabled) {
              _trackConnectionState(true, route: activeRoute);
            }
          }());
        } else {
          unawaited(
            _restoreWindowsRuntimeFailoverIfPossible(source: 'prefs_loaded'),
          );
        }
      }
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
    _persistedServerId = _serverSelectionKey(selectedServer);
    _prefsDebounce?.cancel();
    _prefsDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(
        _prefsStore.patch({
          'language': sLanguage,
          'serverId': _persistedServerId,
          'socialOnlyEnabled': socialOnlyEnabled,
          'socialOnlyApps': socialOnlyApps.map((e) => e.name).toList(),
          'socialOnlyCustomPackages': socialOnlyCustomPackages.toList()..sort(),
          'socialOnlyWindowsApplications':
              socialOnlyWindowsApplications.toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
          'socialOnlyWindowsSites': socialOnlyWindowsSites.toList()..sort(),
          'selectedApps': selectedApps.map((e) => e.name).toList(),
          'trafficPack': trafficPack.name,
          'trafficGb': trafficGb,
          'devices': devices,
          'optNoAds': true,
          'optSmartRouting': true,
          'optDedicatedIp': optDedicatedIp,
          'optAutoRenew': optAutoRenew,
          'lastSuccessfulRouteId': _lastSuccessfulRouteId,
          'lastSuccessfulRouteProtocol': _lastSuccessfulRouteProtocol,
          'lastSuccessfulRouteAt':
              _lastSuccessfulRouteAt?.toUtc().toIso8601String() ?? '',
          'favoriteLocationIds': _favoriteLocationIds.toList()..sort(),
          'recentLocationIds': _recentLocationIds.take(8).toList(),
          'vpnPauseUntil': _vpnPausedUntil?.toUtc().toIso8601String() ?? '',
          'windowsCloseBehavior': _windowsCloseBehavior.code,
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
      final nextBillingPlanCode = (selection['planCode'] ?? '')
          .toString()
          .trim();
      if (greenVpnFixedPublicBillingPlanCodes.contains(nextBillingPlanCode)) {
        _publicBillingPlanCode = greenVpnNormalizePublicBillingPlanCode(
          nextBillingPlanCode,
        );
      }
      trafficPack = nextPack;
      trafficGb = nextGb.clamp(1.0, 800.0);
      devices = kPaidBetaBuild ? 2 : nextDevices.clamp(1, 5);
      optNoAds = true;
      optSmartRouting = true;
      optDedicatedIp = (kPaidBetaBuild || kPublicProductBuild)
          ? false
          : nextDedicatedIp;
      optAutoRenew = greenVpnSelectionAutoRenewEnabled(
        selection,
        paidBetaBuild: kPaidBetaBuild,
      );
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
      if (greenVpnIsInvalidSessionMessage(res.message)) {
        await _noteInvalidSession(
          source: 'subscription_profile',
          message: res.message,
        );
        return;
      }
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
      await _reconcileSubscriptionEntitlements();
    } catch (_) {}
  }

  void _applySubscriptionUiState(
    Map<String, dynamic> profile,
    Object? subscription, {
    Object? trafficUsage,
  }) {
    Map<String, dynamic>? sub;
    if (subscription is Map) {
      sub = Map<String, dynamic>.from(subscription);
    }
    final paidSubscriptionRaw = profile['paidSubscription'];
    final paidSub = paidSubscriptionRaw is Map
        ? Map<String, dynamic>.from(paidSubscriptionRaw)
        : null;
    final lifecycleSub = paidSub ?? sub;

    _freeTierActive = greenVpnIsFreeTierSubscription(
      profile,
      subscription: sub,
    );
    _subscriptionActive =
        profile['isActive'] == true || sub?['isActive'] == true;
    _subscriptionEntitlementResolved = true;
    final planCodeRaw = profile['planCode'] ?? sub?['planCode'];
    final nextPlanCode = (planCodeRaw ?? '').toString().trim().toLowerCase();
    _subscriptionPlanCode = nextPlanCode.isEmpty ? 'base' : nextPlanCode;
    _paidSubscriptionActive = lifecycleSub?['isActive'] == true;
    final paidPlanName = (lifecycleSub?['planName'] ?? '').toString().trim();
    _paidSubscriptionPlanName = paidPlanName.isEmpty ? null : paidPlanName;
    final paidStatus = (lifecycleSub?['status'] ?? '').toString().trim();
    _paidSubscriptionStatus = paidStatus.isEmpty
        ? (_paidSubscriptionActive ? 'active' : 'inactive')
        : paidStatus;
    final accessStartsRaw = lifecycleSub?['accessStartsAt'];
    final accessStarts = accessStartsRaw == null
        ? ''
        : accessStartsRaw.toString().trim();
    _subscriptionAccessStartsAt = accessStarts.isEmpty ? null : accessStarts;
    final expiresRaw = lifecycleSub?['expiresAt'];
    final expires = expiresRaw == null ? '' : expiresRaw.toString().trim();
    _subscriptionExpiresAt = expires.isEmpty ? null : expires;
    final revisionRaw = lifecycleSub?['revision'];
    _subscriptionRevision = revisionRaw is num
        ? revisionRaw.toInt()
        : int.tryParse((revisionRaw ?? '').toString()) ?? 0;

    final monthlyRaw = lifecycleSub?['monthlyPriceRub'];
    _subscriptionMonthlyPriceRub = monthlyRaw is num
        ? monthlyRaw.toInt()
        : int.tryParse((monthlyRaw ?? '').toString());
    final maxDevicesRaw = lifecycleSub?['maxDevices'];
    final parsedMaxDevices = maxDevicesRaw is num
        ? maxDevicesRaw.toInt()
        : int.tryParse((maxDevicesRaw ?? '').toString());
    if (parsedMaxDevices != null && parsedMaxDevices > 0) {
      _subscriptionMaxDevices = parsedMaxDevices;
    }

    final autoRenewRaw = lifecycleSub?['autoRenew'];
    _subscriptionAutoRenew = autoRenewRaw == true;
    final paymentMethodRaw = lifecycleSub?['paymentMethodSaved'];
    _paymentMethodSaved = paymentMethodRaw == true;

    final rawTrafficUsage = trafficUsage ?? profile['trafficUsage'];
    if (rawTrafficUsage is Map) {
      _trafficUsage = Map<String, dynamic>.from(rawTrafficUsage);
    } else if (!_freeTierActive) {
      _trafficUsage = <String, dynamic>{};
    }
  }

  Future<void> _reconcileSubscriptionEntitlements() async {
    if (!mounted) return;
    if (!_subscriptionEntitlementResolved) return;
    final paid = _hasPaidSubscriptionEntitlement;
    final shouldEnableSocial = paid && _socialOnlyPreferenceRequested;
    final socialModeChanged = socialOnlyEnabled != shouldEnableSocial;

    ServerLocation? replacementServer;
    if (!paid &&
        !selectedServer.isAuto &&
        selectedServer.requiresPaidSubscription) {
      final freeCandidates =
          servers
              .where(
                (server) =>
                    !server.isAuto &&
                    server.isCurrentClientReady &&
                    !server.requiresPaidSubscription &&
                    server.publicLocationId == selectedServer.publicLocationId,
              )
              .toList()
            ..sort(_compareServerConnectionCandidates);
      replacementServer =
          freeCandidates.firstOrNull ??
          servers.where((server) => server.isAuto).firstOrNull;
    }

    if (!socialModeChanged && replacementServer == null) return;
    final previousRouting = _captureRoutingPreference();
    final wasConnected = vpnEnabled;
    _prefsDebounce?.cancel();
    setState(() {
      socialOnlyEnabled = shouldEnableSocial;
      if (!paid) _socialOnlyPreferenceRequested = false;
      if (replacementServer != null) {
        selectedServer = replacementServer;
        _persistedServerId = _serverSelectionKey(replacementServer);
      }
    });
    if (socialModeChanged) {
      try {
        final applied = await _applyCurrentConfigMode(
          reconnectIfNeeded: vpnEnabled,
          showToastOnSuccess: false,
        );
        if (!applied) {
          throw StateError(
            'Subscription routing mode was not confirmed by the system.',
          );
        }
      } catch (e) {
        await appendBlueVpnClientLog(
          'premium entitlement config reconcile failed error=$e',
        );
        if (shouldEnableSocial) {
          await _restoreRoutingPreferenceAfterFailure(
            snapshot: previousRouting,
            wasConnected: wasConnected,
          );
          return;
        }
        await _failClosedRoutingPreference(
          reason: 'entitlement_full_mode_not_confirmed',
        );
        return;
      }
    }
    _schedulePrefsSave();
  }

  Future<bool> _cancelAutoRenew() async {
    if (kIsWeb) return false;
    if (widget.session.accessToken == 'dev-token') {
      _toast(context, 'DEV-вход: отключение автопродления недоступно.');
      return false;
    }

    if (mounted) setState(() => _tariffBusy = true);
    try {
      final res = await _api.cancelAutoRenew(
        accessToken: widget.session.accessToken,
      );
      if (!mounted) return false;
      if (!res.ok || res.data == null) {
        final text = res.message ?? 'Не удалось отключить автопродление.';
        setState(() => _tariffStatus = text);
        _toast(context, text);
        return false;
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
      await _reconcileSubscriptionEntitlements();
      if (!mounted) return false;
      _schedulePrefsSave();
      _toast(context, 'Автопродление отключено.');
      return true;
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
      final fixedPlanCodes = greenVpnFixedBillingPlanCodesFromCatalog(
        catalogRes.data,
      );
      final usesFixedBillingPlans =
          kPublicProductBuild || fixedPlanCodes.isNotEmpty;
      final quoteRes = await _api.quoteTariff(
        accessToken: widget.session.accessToken,
        billingPlanCode: usesFixedBillingPlans
            ? greenVpnNormalizePublicBillingPlanCode(
                _publicBillingPlanCode,
                availableCodes: fixedPlanCodes.isEmpty
                    ? greenVpnFixedPublicBillingPlanCodes
                    : fixedPlanCodes,
              )
            : null,
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
        _tariffStatus = greenVpnTariffRefreshStatus(
          usesFixedBillingPlans: usesFixedBillingPlans,
          monthlyPriceRub: monthly,
        );
      });

      if (showToast) {
        _toast(context, _tariffStatus!);
      }
    } finally {
      if (mounted) setState(() => _tariffBusy = false);
    }
  }

  Future<void> _claimPaidBetaInvite() async {
    if (!kPaidBetaBuild || kIsWeb) return;
    var inviteCode = '';
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Beta-инвайт'),
        content: TextField(
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Код',
            hintText: 'GREEN-XXXX-XXXX-XXXX',
            prefixIcon: Icon(Icons.key_rounded),
          ),
          onChanged: (value) => inviteCode = value,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(inviteCode),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Применить'),
          ),
        ],
      ),
    );
    final code = (submitted ?? '').trim();
    if (code.isEmpty || !mounted) return;

    setState(() => _tariffBusy = true);
    try {
      final deviceId = await _ensureDeviceId();
      if (deviceId == null || deviceId.isEmpty) {
        if (mounted) _toast(context, 'Не удалось определить устройство.');
        return;
      }
      final res = await _api.claimPaidBetaInvite(
        accessToken: widget.session.accessToken,
        code: code,
        deviceId: deviceId,
        platform: greenVpnClientPlatform(),
      );
      if (greenVpnIsInvalidSessionMessage(res.message)) {
        await _noteInvalidSession(
          source: 'paid_beta_invite',
          message: res.message,
        );
        return;
      }
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        final message = res.message ?? 'Не удалось применить beta-инвайт.';
        setState(() => _tariffStatus = message);
        _toast(context, message);
        return;
      }

      final rawSubscription = res.data!['subscription'];
      final subscription = rawSubscription is Map
          ? Map<String, dynamic>.from(rawSubscription)
          : <String, dynamic>{};
      setState(() {
        final nextPlan = (subscription['planName'] ?? '').toString().trim();
        if (nextPlan.isNotEmpty) planName = nextPlan;
        _applySubscriptionUiState(const <String, dynamic>{}, subscription);
      });
      await _reconcileSubscriptionEntitlements();
      await _refreshTariffServerState(showToast: false);
      if (!mounted) return;
      setState(() {
        _tariffStatus = 'Инвайт применён. Первый период доступен за 149 ₽.';
      });
      unawaited(_ensureProvisionedConfigSilently());
      _toast(context, 'Beta-инвайт применён.');
    } finally {
      if (mounted) setState(() => _tariffBusy = false);
    }
  }

  Future<void> _createTariffOrderOnServer({
    required bool autoRenew,
    required bool renewalAcknowledged,
  }) async {
    if (kIsWeb) return;
    if (kTrialOnlyNoAdsBuild && !kPaidBetaBuild) {
      setState(() {
        _tariffStatus =
            'В этой версии Green VPN работает Trial без оплаты и рекламы.';
        _pendingBillingOrder = null;
      });
      _toast(context, 'Trial-версия работает без оплаты и рекламы.');
      return;
    }
    if (_tariffCatalog?['paidSalesEnabled'] != true ||
        _tariffCatalog?['paymentsProductionReady'] != true) {
      final message = (_tariffCatalog?['checkoutMessage'] ?? '')
          .toString()
          .trim();
      final text = message.isEmpty
          ? 'Оплата временно недоступна. Бесплатный тариф продолжает работать.'
          : message;
      if (mounted) {
        setState(() => _tariffStatus = text);
        _toast(context, text);
      }
      return;
    }
    if (widget.session.accessToken == 'dev-token') {
      _toast(context, 'Сначала войди в аккаунт, чтобы подключить тариф.');
      return;
    }

    final paymentSession = await _ensurePaymentSession();
    if (paymentSession == null || !mounted) return;

    if (mounted) setState(() => _tariffBusy = true);
    try {
      final fixedPlanCodes = greenVpnFixedBillingPlanCodesFromCatalog(
        _tariffCatalog,
      );
      final usesFixedBillingPlans =
          kPublicProductBuild || fixedPlanCodes.isNotEmpty;
      final purchasePreviewRaw = _tariffQuote?['purchasePreview'];
      final purchasePreview = purchasePreviewRaw is Map
          ? Map<String, dynamic>.from(purchasePreviewRaw)
          : const <String, dynamic>{};
      final expectedRevisionRaw =
          purchasePreview['expectedSubscriptionRevision'];
      final expectedRevision = expectedRevisionRaw is num
          ? expectedRevisionRaw.toInt()
          : int.tryParse((expectedRevisionRaw ?? '').toString());
      final expectedExpiry =
          (purchasePreview['expectedSubscriptionExpiresAt'] ?? '')
              .toString()
              .trim();
      final res = await _api.createBillingOrder(
        accessToken: paymentSession.accessToken,
        billingPlanCode: usesFixedBillingPlans
            ? greenVpnNormalizePublicBillingPlanCode(
                _publicBillingPlanCode,
                availableCodes: fixedPlanCodes.isEmpty
                    ? greenVpnFixedPublicBillingPlanCodes
                    : fixedPlanCodes,
              )
            : null,
        trafficPack: trafficPack.name,
        trafficGb: trafficGb.round(),
        unlimitedApps: _selectedTariffAppCodes(),
        devices: devices,
        dedicatedIp: optDedicatedIp,
        autoRenew: autoRenew,
        renewalAcknowledged: renewalAcknowledged,
        expectedSubscriptionRevision: renewalAcknowledged
            ? expectedRevision
            : null,
        expectedSubscriptionExpiresAt:
            renewalAcknowledged && expectedExpiry.isNotEmpty
            ? expectedExpiry
            : null,
      );

      if (!mounted) return;
      if (!res.ok || res.data == null) {
        final text = res.message ?? 'Не удалось создать заказ на оплату.';
        setState(() => _tariffStatus = text);
        _toast(context, text);
        await _refreshTariffServerState(showToast: false);
        if (mounted) setState(() => _tariffStatus = text);
        return;
      }

      final order = res.data!['order'];
      final orderMap = order is Map ? Map<String, dynamic>.from(order) : null;
      final selection = orderMap?['selection'];
      final quote = orderMap?['quote'];
      final orderPreview = orderMap?['purchasePreview'];

      if (selection is Map) {
        _applyTariffSelectionFromServer(Map<String, dynamic>.from(selection));
      }

      setState(() {
        _tariffQuote = {
          if (selection is Map)
            'selection': Map<String, dynamic>.from(selection),
          if (quote is Map) 'quote': Map<String, dynamic>.from(quote),
          if (orderPreview is Map)
            'purchasePreview': Map<String, dynamic>.from(orderPreview),
          'order': ?orderMap,
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
        if (!mounted) return;
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

  Future<Session?> _ensurePaymentSession() async {
    if (!widget.session.isGuest && widget.session.emailVerified) {
      return widget.session;
    }
    var checkoutSession = widget.session;
    if (checkoutSession.isGuest) {
      final renewed = await _renewGuestSession(
        source: 'checkout_open',
        showToast: false,
      );
      if (renewed == null || !mounted) {
        if (mounted) {
          _toast(
            context,
            'Не удалось подготовить бесплатный профиль. Повторите попытку.',
          );
        }
        return null;
      }
      checkoutSession = renewed;
    }
    final session = await showDialog<Session>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CheckoutEmailDialog(
        api: _api,
        session: checkoutSession,
        initialEmail: checkoutSession.email,
      ),
    );
    if (session == null || !mounted) return null;

    await widget.onSessionChanged(session);
    if (!mounted) return null;
    setState(() {
      _emailVerified = session.emailVerified;
      _emailConfirmationRequired = session.emailConfirmationRequired;
      _emailStatusMessage = session.emailVerified
          ? 'Почта подтверждена.'
          : 'Почта пока не подтверждена.';
    });

    final profile = await _api.fetchSubscriptionProfile(
      accessToken: session.accessToken,
    );
    if (!mounted) return null;
    if (profile.ok && profile.data != null) {
      final data = profile.data!;
      final subscription = data['subscription'];
      final plan = (data['planName'] ?? '').toString().trim();
      setState(() {
        if (plan.isNotEmpty) planName = plan;
        _applySubscriptionUiState(data, subscription);
      });
      await _reconcileSubscriptionEntitlements();
      if (!mounted) return null;
      if (_hasPaidSubscriptionEntitlement) {
        _toast(context, 'Доступ по этому email восстановлен.');
        return null;
      }
    }

    return session;
  }

  Future<void> _openRestoreAccess() async {
    if (!widget.session.isGuest) {
      _toast(context, 'Вы уже вошли в аккаунт.');
      return;
    }

    unawaited(appendBlueVpnClientLog('access restore dialog requested'));
    final session = await showDialog<Session>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RestoreAccessDialog(
        api: _api,
        session: widget.session,
        initialEmail: widget.session.email,
        renewGuestSession: () => _renewGuestSession(
          source: 'access_restore_retry',
          showToast: false,
        ),
      ),
    );
    if (session == null || !mounted) return;

    await widget.onSessionChanged(session);
    if (!mounted) return;
    setState(() {
      _emailVerified = session.emailVerified;
      _emailConfirmationRequired = session.emailConfirmationRequired;
      _emailStatusMessage = session.emailVerified
          ? 'Почта подтверждена.'
          : 'Почта пока не подтверждена.';
    });

    final profile = await _api.fetchSubscriptionProfile(
      accessToken: session.accessToken,
    );
    if (!mounted) return;
    if (!profile.ok || profile.data == null) {
      _toast(
        context,
        'Вход выполнен, но подписку пока не удалось проверить. Повторите позже.',
      );
      return;
    }

    final data = profile.data!;
    final subscription = data['subscription'];
    final plan = (data['planName'] ?? '').toString().trim();
    setState(() {
      if (plan.isNotEmpty) planName = plan;
      _applySubscriptionUiState(data, subscription);
    });
    await _reconcileSubscriptionEntitlements();
    if (!mounted) return;

    _toast(
      context,
      _hasPaidSubscriptionEntitlement
          ? 'Подписка восстановлена на этом устройстве.'
          : 'Вход выполнен. Активной подписки у аккаунта нет.',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_syncPlanSilently());
      unawaited(_refreshServerCatalog(showToast: false));
    });
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
    if (!mounted) return;
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

      if (status == 'activated') {
        await _pendingBillingOrderStore.clear();
        if (!mounted) return;
        _stopPendingBillingPolling();
        setState(() {
          _pendingBillingOrder = null;
          _tariffStatus = 'Оплата подтверждена. Тариф активирован.';
        });
        await _syncTariffFromServerSilently();
        await _syncPlanSilently();
        await _refreshTariffServerState(showToast: false);
        if (!mounted) return;
        if (showToast && mounted) {
          _toast(context, 'Оплата подтверждена, тариф активирован.');
        }
        return;
      }

      if (status == 'paid_receipt_pending') {
        await _pendingBillingOrderStore.write(freshOrder);
        if (!mounted) return;
        setState(() {
          _pendingBillingOrder = freshOrder;
          _tariffStatus =
              'Оплата подтверждена. Чек регистрируется в ФНС и будет отправлен на email. Тариф активируется после отправки чека.';
        });
        if (showToast) {
          _toast(context, 'Оплата подтверждена. Оформляем и отправляем чек.');
        }
        return;
      }

      if (status == 'canceled' || status == 'expired') {
        await _pendingBillingOrderStore.clear();
        if (!mounted) return;
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
      if (!mounted) return;
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

  String _normalizeDevEndpoint(String rawConfig) {
    return normalizeProvisionedEndpoint(rawConfig);
  }

  String? _knownIpv4EndpointForServer(ServerLocation? server) {
    if (server == null) return null;
    for (final host in _knownEndpointHostsForServer(server)) {
      final address = InternetAddress.tryParse(host);
      if (address?.type == InternetAddressType.IPv4) {
        return address!.address;
      }
    }
    return null;
  }

  Future<String> _prepareProvisionedConfigForPlatform(
    String rawConfig, {
    ServerLocation? server,
  }) async {
    final normalized = _normalizeDevEndpoint(rawConfig);
    if (kIsWeb || !Platform.isWindows) return normalized;
    final protocol = server?.protocolCode ?? 'wireguard_udp';
    if (protocol != 'wireguard_udp' && protocol != 'amneziawg') {
      return normalized;
    }
    return resolveWireGuardEndpointToIpv4(
      normalized,
      fallbackIpv4: _knownIpv4EndpointForServer(server),
    );
  }

  Set<String> _knownEndpointHostsForServer(ServerLocation server) {
    final hosts = <String>{};

    void addHost(String? host) {
      final value = (host ?? '').trim().toLowerCase();
      if (value.isNotEmpty) hosts.add(value);
    }

    addHost(server.endpointHost);
    for (final alias in _serverEndpointAliases[server.id] ?? const <String>[]) {
      addHost(alias);
    }
    return hosts;
  }

  Set<String> _knownEndpointHostsForAllServers() {
    final hosts = <String>{};
    for (final server in servers) {
      if (server.isAuto) continue;
      hosts.addAll(_knownEndpointHostsForServer(server));
    }
    for (final aliases in _serverEndpointAliases.values) {
      for (final alias in aliases) {
        final value = alias.trim().toLowerCase();
        if (value.isNotEmpty) hosts.add(value);
      }
    }
    hosts.add(kIntelligentSmewHost);
    return hosts;
  }

  bool _configLooksLikeSupportedLocalServer(String rawConfig) {
    final endpointHost = _endpointHostFromConfig(rawConfig);
    if (endpointHost == null || endpointHost.isEmpty) return false;

    if (rawConfig.contains('engage.cloudflareclient.com')) return false;
    if (rawConfig.contains('\n    S1 =') ||
        rawConfig.contains('\r\n    S1 =')) {
      return false;
    }

    return _knownEndpointHostsForAllServers().contains(endpointHost);
  }

  String? _expectedEndpointHostForServer(ServerLocation server) {
    if (server.isAuto) return null;
    return server.endpointHost;
  }

  bool _configMatchesServer(ServerLocation server, String rawConfig) {
    final endpointHost = _endpointHostFromConfig(rawConfig);
    if (endpointHost == null || endpointHost.isEmpty) return false;

    final expectedHost = _expectedEndpointHostForServer(server);
    if (expectedHost == null) {
      return _knownEndpointHostsForAllServers().contains(endpointHost);
    }

    final expectedHosts = _knownEndpointHostsForServer(server);
    expectedHosts.add(expectedHost.trim().toLowerCase());
    return expectedHosts.contains(endpointHost);
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

    if (greenVpnWindowsRuntimeIsIsolated) {
      final root = greenVpnProgramDataRootSync();
      addCandidate(greenVpnBaseConfigPathSync());
      addCandidate(greenVpnManagedConfigPathSync());
      addCandidate('$root\\$greenVpnTunnelName.real.conf');
      addCandidate('$root\\$greenVpnTunnelName.seed.conf');
      return out;
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

  Future<_LocalConfigCandidate?> _findPreferredLocalConfig({
    ServerLocation? serverOverride,
  }) async {
    final effectiveServer = serverOverride ?? selectedServer;
    for (final p in _preferredLocalConfigCandidates()) {
      final f = File(p);
      if (!f.existsSync()) continue;
      try {
        final raw = _normalizeDevEndpoint(await f.readAsString());
        if (raw.trim().isEmpty) continue;
        if (!_configLooksLikeSupportedLocalServer(raw)) continue;
        if (!_configMatchesServer(effectiveServer, raw)) continue;
        return _LocalConfigCandidate(path: p, content: raw);
      } catch (_) {
        // ignore and try next
      }
    }
    return null;
  }

  Future<bool> _repairProvisionedConfigFromPreferredDevSource({
    required bool showToast,
    ServerLocation? serverOverride,
  }) async {
    if (kIsWeb || !Platform.isWindows) return false;
    final effectiveServer = serverOverride ?? selectedServer;

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
        _configMatchesServer(effectiveServer, normalizedBase)) {
      if (normalizedBase != base) {
        await _writeProvisionedConfig(normalizedBase, server: effectiveServer);
      }
      return true;
    }

    final preferred = await _findPreferredLocalConfig(
      serverOverride: effectiveServer,
    );
    if (preferred == null || preferred.content.trim().isEmpty) return false;

    await _writeProvisionedConfig(preferred.content, server: effectiveServer);

    if (showToast && mounted) {
      _toast(context, '$kTunnelName конфиг восстановлен из ${preferred.path}');
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

  List<String> _resolveAndroidSocialPackageNames(Set<SocialApp> apps) {
    final out = <String>{};
    for (final app in apps) {
      final packages = _androidSocialPackageNames[app];
      if (packages != null) {
        out.addAll(packages);
      }
    }
    final list = out.toList()..sort();
    return list;
  }

  String _removeWireGuardInterfaceField(String configText, String fieldName) {
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

  String _setWireGuardInterfaceCsvField(
    String configText,
    String fieldName,
    List<String> values,
  ) {
    final cleaned = _removeWireGuardInterfaceField(configText, fieldName);
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

  String _buildAndroidSocialOnlyConfig(String baseConfig) {
    final packageNames = <String>{
      ..._resolveAndroidSocialPackageNames(socialOnlyApps),
      ...socialOnlyCustomPackages.where(_isValidAndroidPackageName),
    }.toList()..sort();
    if (packageNames.isEmpty) {
      packageNames.addAll(
        _androidSocialPackageNames[SocialApp.telegram] ?? const <String>[],
      );
    }
    final fullTunnelConfig = preserveFullTunnelAllowedIps(baseConfig);
    final withoutExcluded = _removeWireGuardInterfaceField(
      fullTunnelConfig,
      'ExcludedApplications',
    );
    return _setWireGuardInterfaceCsvField(
      withoutExcluded,
      'IncludedApplications',
      packageNames,
    );
  }

  String _buildWindowsApplicationOnlyConfig(String baseConfig) {
    final withoutIncluded = _removeWireGuardInterfaceField(
      baseConfig,
      'IncludedApplications',
    );
    final withoutExcluded = _removeWireGuardInterfaceField(
      withoutIncluded,
      'ExcludedApplications',
    );
    final allowedIps = <String>{
      if (socialOnlyWindowsApplications.isNotEmpty)
        '$_windowsApplicationProxyHost/32',
      ..._windowsSelectiveDestinationCidrs,
    }.toList()..sort();
    if (allowedIps.isEmpty) {
      throw StateError('Выбери хотя бы один сервис, программу или сайт.');
    }
    return _replaceAllowedIps(withoutExcluded, allowedIps);
  }

  Future<void> _syncWindowsRoutingPolicy() async {
    if (kIsWeb || !Platform.isWindows) return;
    final destinations = <String>{};
    if (socialOnlyEnabled) {
      final domains = <String>{...socialOnlyWindowsSites};
      for (final app in socialOnlyApps) {
        destinations.addAll(_socialAllowedIps[app] ?? const <String>[]);
        domains.addAll(_socialDomains[app] ?? const <String>[]);
      }
      final resolution = await resolveWindowsVpnSites(domains);
      final unresolvedCustomSites = resolution.unresolvedSites
          .where(socialOnlyWindowsSites.contains)
          .toList();
      if (unresolvedCustomSites.isNotEmpty) {
        throw StateError(
          'Не удалось найти сайт: ${unresolvedCustomSites.first}. Проверь адрес и интернет.',
        );
      }
      destinations.addAll(resolution.ipv4Cidrs);
    }
    final normalizedDestinations =
        destinations.where(isValidWindowsVpnDestinationCidr).toList()..sort();
    _windowsSelectiveDestinationCidrs = normalizedDestinations;
    await _cfg.writeWindowsRoutingPolicy(
      applicationsOnly: socialOnlyEnabled,
      applicationPaths: socialOnlyWindowsApplications,
      destinationCidrs: normalizedDestinations,
    );
  }

  String _buildManagedConfigFromBase(String baseConfig) {
    if (!socialOnlyEnabled) {
      final fullTunnel = preserveFullTunnelAllowedIps(baseConfig);
      final withoutIncluded = _removeWireGuardInterfaceField(
        fullTunnel,
        'IncludedApplications',
      );
      return _removeWireGuardInterfaceField(
        withoutIncluded,
        'ExcludedApplications',
      );
    }

    if (!kIsWeb && Platform.isAndroid) {
      return _buildAndroidSocialOnlyConfig(baseConfig);
    }

    if (!kIsWeb && Platform.isWindows) {
      return _buildWindowsApplicationOnlyConfig(baseConfig);
    }

    final allowedIps = _resolveSocialAllowedIps(socialOnlyApps);
    return _replaceAllowedIps(baseConfig, allowedIps);
  }

  Future<void> _writeProvisionedConfig(
    String rawConfig, {
    ServerLocation? server,
  }) async {
    final preparedConfig = await _prepareProvisionedConfigForPlatform(
      rawConfig,
      server: server,
    );
    await _syncWindowsRoutingPolicy();
    final protocol = server?.protocolCode ?? 'wireguard_udp';
    await _cfg.writeManagedConfig(
      greenVpnTransportRequiresFullTunnel(protocol)
          ? preparedConfig
          : _buildManagedConfigFromBase(preparedConfig),
    );
    await _cfg.writeManagedProtocol(server?.protocolCode ?? 'wireguard_udp');
    await _cfg.writeManagedRouteId(server?.id ?? '');
    try {
      await _cfg.writeBaseConfig(preparedConfig);
    } catch (e) {
      await appendBlueVpnClientLog(
        'config write skipped path=${_cfg.baseConfigPath} kind=base-root error=$e',
      );
    }
    final effectiveServer = server;
    if (effectiveServer != null && !effectiveServer.isAuto) {
      try {
        await _cfg.writeBaseConfigForServer(effectiveServer.id, preparedConfig);
      } catch (e) {
        await appendBlueVpnClientLog(
          'config write skipped kind=server-cache server=${effectiveServer.id} error=$e',
        );
      }
    }
  }

  Future<bool> _reuseExistingProvisionedConfig({
    required String reason,
    required bool showToast,
    ServerLocation? serverOverride,
  }) async {
    if (greenVpnIsFreeQuotaExhaustedMessage(reason)) {
      await appendBlueVpnClientLog(
        'local config fallback blocked by free quota: $reason',
      );
      if (showToast && mounted) {
        _toast(
          context,
          'Бесплатный лимит исчерпан. Открой тариф или дождись нового месяца.',
        );
      }
      return false;
    }
    if (greenVpnIsAdRewardRequiredMessage(reason)) {
      await appendBlueVpnClientLog(
        'local config fallback blocked by ad gate: $reason',
      );
      if (showToast && mounted) {
        _toast(
          context,
          'Для бесплатного подключения сначала посмотри рекламу.',
        );
      }
      return false;
    }
    try {
      final effectiveServer = serverOverride ?? selectedServer;
      if (!kIsWeb && Platform.isAndroid && !effectiveServer.isAuto) {
        await appendBlueVpnClientLog(
          'local config fallback blocked on android manual server=${effectiveServer.id}: $reason',
        );
        return false;
      }
      await _cfg.ensureBaseSeededFromManagedIfMissing();
      final serverBase = effectiveServer.isAuto
          ? null
          : await _cfg.readBaseConfigForServer(effectiveServer.id);
      final base = ((serverBase ?? '').trim().isNotEmpty)
          ? serverBase
          : await _cfg.readBaseConfig();
      if (base == null || base.trim().isEmpty) return false;

      final normalizedBase = _normalizeDevEndpoint(base);
      if (!_configLooksLikeSupportedLocalServer(normalizedBase) ||
          !_configMatchesServer(effectiveServer, normalizedBase)) {
        return false;
      }

      await _cfg.writeManagedConfig(
        _buildManagedConfigFromBase(normalizedBase),
      );
      await _cfg.writeManagedProtocol(effectiveServer.protocolCode);
      await _cfg.writeManagedRouteId(
        effectiveServer.isAuto ? '' : effectiveServer.id,
      );
      try {
        await _cfg.writeBaseConfig(normalizedBase);
        if (!effectiveServer.isAuto) {
          await _cfg.writeBaseConfigForServer(
            effectiveServer.id,
            normalizedBase,
          );
        }
      } catch (e) {
        await appendBlueVpnClientLog(
          'local config fallback cache refresh skipped server=${effectiveServer.id} error=$e',
        );
      }
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

  bool get _windowsProcessRouterRequired =>
      socialOnlyEnabled && socialOnlyWindowsApplications.isNotEmpty;

  _RoutingPreferenceSnapshot _captureRoutingPreference() {
    return _RoutingPreferenceSnapshot(
      socialOnlyEnabled: socialOnlyEnabled,
      preferenceRequested: _socialOnlyPreferenceRequested,
      apps: Set<SocialApp>.from(socialOnlyApps),
      customPackages: Set<String>.from(socialOnlyCustomPackages),
      windowsApplications: Set<String>.from(socialOnlyWindowsApplications),
      windowsSites: Set<String>.from(socialOnlyWindowsSites),
      windowsDestinationCidrs: List<String>.from(
        _windowsSelectiveDestinationCidrs,
      ),
      runtimeRoute: _activeWindowsRuntimeRoute ?? _activeConnectionRoute,
    );
  }

  void _restoreRoutingPreferenceInMemory(_RoutingPreferenceSnapshot snapshot) {
    socialOnlyEnabled = snapshot.socialOnlyEnabled;
    _socialOnlyPreferenceRequested = snapshot.preferenceRequested;
    socialOnlyApps
      ..clear()
      ..addAll(snapshot.apps);
    socialOnlyCustomPackages
      ..clear()
      ..addAll(snapshot.customPackages);
    socialOnlyWindowsApplications
      ..clear()
      ..addAll(snapshot.windowsApplications);
    socialOnlyWindowsSites
      ..clear()
      ..addAll(snapshot.windowsSites);
    _windowsSelectiveDestinationCidrs = List<String>.from(
      snapshot.windowsDestinationCidrs,
    );
  }

  Future<void> _writeCurrentRoutingConfig() async {
    await _syncWindowsRoutingPolicy();
    await _cfg.ensureBaseSeededFromManagedIfMissing();
    final base = await _cfg.readBaseConfig();
    if (base != null && base.trim().isNotEmpty) {
      await _cfg.writeManagedConfig(_buildManagedConfigFromBase(base));
    }
  }

  ServerLocation? _windowsApplicationProxyRoute() {
    return greenVpnWindowsApplicationProxyRoutes<ServerLocation>(
          candidates: servers.where(
            (server) =>
                !server.isAuto &&
                server.isCurrentClientReady &&
                (_hasPaidSubscriptionEntitlement ||
                    !server.requiresPaidSubscription),
          ),
          serverIdOf: (server) => server.id,
          protocolOf: (server) => server.protocolCode,
        ).firstOrNull ??
        greenVpnWindowsApplicationProxyRoutes<ServerLocation>(
          candidates: _fallbackServerCatalogForCurrentChannel(),
          serverIdOf: (server) => server.id,
          protocolOf: (server) => server.protocolCode,
        ).firstOrNull;
  }

  Future<bool> _activateCachedWindowsRoute(ServerLocation route) async {
    final cached = await _cfg.readBaseConfigForServer(route.id);
    if (cached == null ||
        cached.trim().isEmpty ||
        !_configMatchesServer(route, cached)) {
      await appendBlueVpnClientLog(
        'routing mode cached route unavailable server=${route.id} protocol=${route.protocolCode}',
      );
      return false;
    }
    await _cfg.writeBaseConfig(cached);
    await _cfg.writeManagedConfig(
      greenVpnTransportRequiresFullTunnel(route.protocolCode)
          ? cached
          : _buildManagedConfigFromBase(cached),
    );
    await _cfg.writeManagedProtocol(route.protocolCode);
    await _cfg.writeManagedRouteId(route.id);
    return true;
  }

  Future<ServerLocation?> _prepareWindowsRoutingModeRoute() async {
    if (kIsWeb || !Platform.isWindows) return null;
    if (_windowsProcessRouterRequired) {
      final route = _windowsApplicationProxyRoute();
      if (route == null) {
        throw StateError(
          'Режим для выбранных программ сейчас недоступен. Текущее подключение сохранено.',
        );
      }
      final provisioned = await _ensureProvisionedConfigInteractive(
        serverOverride: route,
        requireExactServer: true,
      );
      if (!provisioned.ok || provisioned.server == null) {
        throw StateError(
          provisioned.message ??
              'Не удалось подготовить режим для выбранных программ.',
        );
      }
      return provisioned.server;
    }

    final route = _fullModeRouteForCurrentSelection();
    if (route == null) {
      throw StateError('Не удалось подобрать рабочую локацию для VPN.');
    }
    if (await _activateCachedWindowsRoute(route)) return route;
    final provisioned = await _ensureProvisionedConfigInteractive(
      serverOverride: route,
      requireExactServer: !route.isAuto,
    );
    if (!provisioned.ok || provisioned.server == null) {
      throw StateError(
        provisioned.message ?? 'Не удалось подготовить обычный режим VPN.',
      );
    }
    return provisioned.server;
  }

  ServerLocation? _fullModeRouteForCurrentSelection() {
    final usable =
        servers
            .where(
              (server) =>
                  !server.isAuto &&
                  server.isCurrentClientReady &&
                  (_hasPaidSubscriptionEntitlement ||
                      !server.requiresPaidSubscription),
            )
            .toList()
          ..sort(_compareServerConnectionCandidates);
    return greenVpnPreferredFullModeRoute<ServerLocation>(
      candidates: usable,
      automatic: selectedServer.isAuto,
      selectedLocationId: selectedServer.publicLocationId,
      selectedRouteId: selectedServer.id,
      activeRoute: _activeConnectionRoute,
      locationIdOf: (server) => server.publicLocationId,
      routeIdOf: (server) => server.id,
    );
  }

  Future<_GreenVpnWindowsRuntimeSnapshot> _readWindowsRuntimeSnapshot() async {
    const service = _GreenVpnSystemServiceClient();
    final response = await service.status();
    final tunnelState = greenVpnClassifyWindowsManagedTunnelStatus(
      requestOk: response.ok,
      data: response.data,
    );
    final routingMode = greenVpnClassifyWindowsRoutingMode(
      requestOk: response.ok,
      data: response.data,
    );
    final processRouterRequired =
        response.data['processRouterRequired'] == true;
    final externalVpnActive = response.data['externalVpnActive'] == true;
    final externalVpnStateKnown =
        response.ok && response.data['externalVpnStateKnown'] == true;
    final authoritativeMode = greenVpnAuthoritativeActiveRoutingMode(
      requestOk: response.ok,
      data: response.data,
      processRouterRequired: processRouterRequired,
    );
    return _GreenVpnWindowsRuntimeSnapshot(
      tunnelState: tunnelState,
      routingMode: routingMode,
      processRouterRequired: processRouterRequired,
      protectionConfirmed: authoritativeMode != null,
      externalVpnActive: externalVpnActive,
      externalVpnStateKnown: externalVpnStateKnown,
    );
  }

  Future<bool> _windowsRequestedRoutingModeIsConfirmed({
    bool? applicationsOnly,
    bool? processRouterRequired,
  }) async {
    const service = _GreenVpnSystemServiceClient();
    final response = await service.status();
    return greenVpnWindowsRoutingModeIsConfirmed(
      requestOk: response.ok,
      data: response.data,
      applicationsOnly: applicationsOnly ?? socialOnlyEnabled,
      processRouterRequired:
          processRouterRequired ?? _windowsProcessRouterRequired,
    );
  }

  Future<bool> _failClosedRoutingPreference({required String reason}) async {
    _disarmWindowsRuntimeFailover(reason: 'routing_mode_fail_closed');
    var disconnectAccepted = false;
    try {
      final off = await _vpnBackend.disconnect();
      disconnectAccepted = off.ok;
      if (!off.ok) {
        await appendBlueVpnClientLog(
          'routing preference fail-closed disconnect rejected reason=$reason message=${off.message ?? ""}',
        );
      }
    } catch (error) {
      await appendBlueVpnClientLog(
        'routing preference fail-closed disconnect failed reason=$reason error=$error',
      );
    }
    await _syncVpnStatus(source: 'routing_mode_fail_closed');
    var disconnected = !vpnEnabled;
    if (!kIsWeb && Platform.isWindows) {
      final snapshot = await _readWindowsManagedTunnelState();
      disconnected =
          snapshot.tunnelState ==
          GreenVpnWindowsManagedTunnelState.disconnected;
    }
    await appendBlueVpnClientLog(
      'routing preference fail-closed completed reason=$reason accepted=$disconnectAccepted disconnected=$disconnected',
    );
    _schedulePrefsSave();
    return disconnected;
  }

  Future<bool> _restoreRoutingPreferenceAfterFailure({
    required _RoutingPreferenceSnapshot snapshot,
    required bool wasConnected,
  }) async {
    if (!mounted) return false;
    _disarmWindowsRuntimeFailover(reason: 'routing_mode_rollback');
    setState(() => _restoreRoutingPreferenceInMemory(snapshot));
    try {
      if (!kIsWeb && Platform.isWindows && snapshot.runtimeRoute != null) {
        if (!await _activateCachedWindowsRoute(snapshot.runtimeRoute!)) {
          final restoredConfig = await _ensureProvisionedConfigInteractive(
            serverOverride: snapshot.runtimeRoute,
            requireExactServer: true,
          );
          if (!restoredConfig.ok) {
            throw StateError('Не удалось подготовить предыдущий маршрут.');
          }
        }
      } else {
        await _writeCurrentRoutingConfig();
      }
      if (wasConnected) {
        final alreadyRestored = !kIsWeb && Platform.isWindows
            ? await _windowsRequestedRoutingModeIsConfirmed()
            : false;
        if (!alreadyRestored) {
          final off = await _vpnBackend.disconnect();
          if (!off.ok) {
            throw StateError(
              off.message ?? 'Не удалось остановить новый режим.',
            );
          }
          final on = await _vpnBackend.connect(
            configPath: _cfg.managedConfigPath,
          );
          if (!on.ok) {
            throw StateError(
              on.message ?? 'Не удалось восстановить предыдущий режим.',
            );
          }
        }
        if (!kIsWeb && Platform.isWindows) {
          final confirmed = alreadyRestored
              ? true
              : await _windowsRequestedRoutingModeIsConfirmed();
          if (!confirmed) {
            throw StateError(
              'Служба не подтвердила восстановленный режим защиты.',
            );
          }
          if (!snapshot.socialOnlyEnabled && snapshot.runtimeRoute != null) {
            await _armRuntimeFailover(snapshot.runtimeRoute!);
          }
        }
      }
      await _syncVpnStatus(source: 'routing_mode_rollback');
      await appendBlueVpnClientLog(
        'routing preference rollback completed connectedBefore=$wasConnected mode=${snapshot.socialOnlyEnabled ? "applications" : "full"}',
      );
      return true;
    } catch (error) {
      await appendBlueVpnClientLog(
        'routing preference rollback failed connectedBefore=$wasConnected error=$error',
      );
      await _failClosedRoutingPreference(reason: 'rollback_failed');
      return false;
    } finally {
      _schedulePrefsSave();
    }
  }

  Future<bool> _applyCurrentConfigMode({
    required bool reconnectIfNeeded,
    required bool showToastOnSuccess,
  }) async {
    final requestedApplicationsOnly = socialOnlyEnabled;
    final requestedProcessRouterRequired = _windowsProcessRouterRequired;
    await _syncWindowsRoutingPolicy();
    await _cfg.ensureBaseSeededFromManagedIfMissing();

    ServerLocation? preparedWindowsRoute;
    if (!kIsWeb && Platform.isWindows && reconnectIfNeeded && vpnEnabled) {
      preparedWindowsRoute = await _prepareWindowsRoutingModeRoute();
      if (!mounted) return false;
    }

    final base = await _cfg.readBaseConfig();
    if (!mounted) return false;
    if (base == null || base.trim().isEmpty) {
      if (reconnectIfNeeded && vpnEnabled) {
        if (showToastOnSuccess) {
          _toast(context, 'Нет сохранённой конфигурации для смены режима.');
        }
        return false;
      }
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
    if (!mounted) return false;

    if (reconnectIfNeeded && vpnEnabled) {
      if (!kIsWeb && Platform.isAndroid) {
        final applied = await _vpnBackend.connect(
          configPath: _cfg.managedConfigPath,
        );
        if (!mounted) return false;
        if (!applied.ok) {
          _toast(
            context,
            applied.message ?? 'Не удалось применить список приложений.',
          );
          await _syncVpnStatus();
          return false;
        }
      } else {
        final runtimeRoute =
            preparedWindowsRoute ??
            _activeWindowsRuntimeRoute ??
            _activeConnectionRoute;
        _disarmWindowsRuntimeFailover(reason: 'routing_mode_reconnect');
        final off = await _vpnBackend.disconnect();
        if (!mounted) return false;
        if (!off.ok) {
          _toast(context, off.message ?? 'Не удалось переподключить VPN.');
          await _syncVpnStatus();
          return false;
        }

        final on = await _vpnBackend.connect(
          configPath: _cfg.managedConfigPath,
        );
        if (!mounted) return false;
        if (!on.ok) {
          _toast(context, on.message ?? 'Не удалось заново подключить VPN.');
          await _syncVpnStatus();
          return false;
        }
        if (!socialOnlyEnabled && runtimeRoute != null) {
          await _armRuntimeFailover(runtimeRoute);
        }
        if (runtimeRoute != null) {
          _trackConnectionState(true, route: runtimeRoute);
        }
      }

      await _syncVpnStatus(source: 'routing_mode_apply');
      if (!mounted) return false;
      var modeConfirmed = !kIsWeb && Platform.isWindows
          ? await _windowsRequestedRoutingModeIsConfirmed(
              applicationsOnly: requestedApplicationsOnly,
              processRouterRequired: requestedProcessRouterRequired,
            )
          : vpnEnabled;
      if (!modeConfirmed && !kIsWeb && Platform.isWindows) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return false;
        modeConfirmed = await _windowsRequestedRoutingModeIsConfirmed(
          applicationsOnly: requestedApplicationsOnly,
          processRouterRequired: requestedProcessRouterRequired,
        );
      }
      if (!mounted) return false;
      if (!vpnEnabled || !modeConfirmed) {
        _toast(
          context,
          !kIsWeb && Platform.isWindows
              ? 'Windows не подтвердила новый режим защиты.'
              : 'Android не подтвердил новое VPN-подключение.',
        );
        return false;
      }
      if (!kIsWeb &&
          Platform.isWindows &&
          !requestedApplicationsOnly &&
          _windowsRuntimeFailoverTimer == null) {
        await _restoreWindowsRuntimeFailoverIfPossible(
          source: 'routing_mode_apply',
        );
      }
      if (!kIsWeb &&
          Platform.isAndroid &&
          !requestedApplicationsOnly &&
          _activeConnectionRoute != null) {
        await _armRuntimeFailover(_activeConnectionRoute!);
      }
    }

    if (!mounted) return false;
    if (showToastOnSuccess) {
      _toast(
        context,
        socialOnlyEnabled
            ? 'Режим «Только выбранное» применён.'
            : (!kIsWeb && Platform.isWindows
                  ? 'Режим «Весь интернет» применён. Проверяем защиту.'
                  : 'Обычный режим восстановлен.'),
      );
    }

    return true;
  }

  void _setLanguage(String value) {
    setState(() => sLanguage = 'Русский');
    _schedulePrefsSave();
  }

  Future<_GreenVpnWindowsRuntimeSnapshot>
  _readWindowsManagedTunnelState() async {
    final snapshot = await _readWindowsRuntimeSnapshot();
    if (snapshot.tunnelState != GreenVpnWindowsManagedTunnelState.unknown) {
      return snapshot;
    }
    if (await _vpnBackend.isConnected()) {
      return const _GreenVpnWindowsRuntimeSnapshot(
        tunnelState: GreenVpnWindowsManagedTunnelState.connected,
        routingMode: GreenVpnWindowsRoutingMode.unknown,
        processRouterRequired: false,
        protectionConfirmed: false,
        externalVpnActive: false,
        externalVpnStateKnown: false,
      );
    }
    return const _GreenVpnWindowsRuntimeSnapshot(
      tunnelState: GreenVpnWindowsManagedTunnelState.unknown,
      routingMode: GreenVpnWindowsRoutingMode.unknown,
      processRouterRequired: false,
      protectionConfirmed: false,
      externalVpnActive: false,
      externalVpnStateKnown: false,
    );
  }

  Future<void> _syncVpnStatus({String source = 'unspecified'}) async {
    final syncEpoch = ++_vpnStatusSyncEpoch;
    if (!kIsWeb && Platform.isWindows) {
      final snapshot = await _readWindowsManagedTunnelState();
      if (!mounted || syncEpoch != _vpnStatusSyncEpoch) return;
      final state = snapshot.tunnelState;
      if (state == GreenVpnWindowsManagedTunnelState.unknown) {
        if (_windowsProtectionConfirmed ||
            _windowsFullTunnelDataPlaneConfirmed) {
          setState(() {
            _windowsProtectionConfirmed = false;
            _windowsFullTunnelDataPlaneConfirmed = false;
          });
        }
        await appendBlueVpnClientLog(
          'windows status sync source=$source result=unknown preserved=$vpnEnabled protectionConfirmed=false',
        );
        return;
      }
      final on = state == GreenVpnWindowsManagedTunnelState.connected;
      final authoritativeMode = on && snapshot.protectionConfirmed
          ? snapshot.routingMode
          : GreenVpnWindowsRoutingMode.unknown;
      if (authoritativeMode != GreenVpnWindowsRoutingMode.full) {
        _windowsFullTunnelDataPlaneConfirmed = false;
      }
      final actualSocialOnly =
          authoritativeMode == GreenVpnWindowsRoutingMode.applications;
      final effectiveProtectionConfirmed =
          greenVpnWindowsUiProtectionIsConfirmed(
            systemStateConfirmed: snapshot.protectionConfirmed,
            routingMode: authoritativeMode,
            fullTunnelDataPlaneConfirmed: _windowsFullTunnelDataPlaneConfirmed,
          );
      final activeRuntimeRoute = _activeWindowsRuntimeRoute;
      final recoverUnexpectedDisconnect =
          greenVpnShouldRecoverUnexpectedWindowsDisconnect(
            reportedConnected: on,
            vpnEnabled: vpnEnabled,
            monitorArmed:
                activeRuntimeRoute != null &&
                _windowsRuntimeFailoverTimer != null,
            recoveryRunning: _windowsRuntimeRecoveryRunning,
            vpnBusy: vpnBusy,
          );
      if (recoverUnexpectedDisconnect && activeRuntimeRoute != null) {
        if (_windowsProtectionConfirmed ||
            _windowsFullTunnelDataPlaneConfirmed) {
          setState(() {
            _windowsProtectionConfirmed = false;
            _windowsFullTunnelDataPlaneConfirmed = false;
          });
        }
        await appendBlueVpnClientLog(
          'windows status sync source=$source connected=false preserved=true protectionConfirmed=false reason=runtime_failover_armed',
        );
        unawaited(
          _pollWindowsRuntimeFailover(
            activeRuntimeRoute,
            _windowsRuntimeFailoverEpoch,
          ),
        );
        return;
      }
      final changed =
          vpnEnabled != on ||
          _windowsProtectionConfirmed != effectiveProtectionConfirmed ||
          _externalVpnActive != snapshot.externalVpnActive ||
          (authoritativeMode != GreenVpnWindowsRoutingMode.unknown &&
              socialOnlyEnabled != actualSocialOnly);
      if (changed) {
        final previous = vpnEnabled;
        setState(() {
          vpnEnabled = on;
          _windowsProtectionConfirmed = effectiveProtectionConfirmed;
          if (authoritativeMode != GreenVpnWindowsRoutingMode.unknown) {
            socialOnlyEnabled = actualSocialOnly;
            _socialOnlyPreferenceRequested = actualSocialOnly;
          }
          _externalVpnActive = snapshot.externalVpnActive;
        });
        if (authoritativeMode != GreenVpnWindowsRoutingMode.unknown) {
          _schedulePrefsSave();
        }
        await appendBlueVpnClientLog(
          'windows status sync source=$source connected=$on systemProtected=${snapshot.protectionConfirmed} dataPlane=$_windowsFullTunnelDataPlaneConfirmed protected=$effectiveProtectionConfirmed mode=${snapshot.routingMode.name} externalVpn=${snapshot.externalVpnActive} externalVpnKnown=${snapshot.externalVpnStateKnown} previous=$previous',
        );
      }
      if (on) {
        await _restoreWindowsRuntimeFailoverIfPossible(source: 'status_sync');
      } else if (_activeWindowsRuntimeRoute != null ||
          _windowsRuntimeFailoverTimer != null) {
        _disarmWindowsRuntimeFailover(reason: 'status_disconnected');
      }
      _trackConnectionState(
        on,
        route: _activeWindowsRuntimeRoute ?? _activeConnectionRoute,
      );
      return;
    }

    final wgState = _wireGuardState;
    if (wgState != null && !wgState.installed) {
      if (mounted) {
        setState(() {
          vpnEnabled = false;
          _externalVpnActive = false;
        });
        _trackConnectionState(false);
      }
      return;
    }
    if (!kIsWeb && Platform.isAndroid) {
      final status = await WireGuardAndroidBackend.statusSnapshot(
        tunnelName: kTunnelName,
      );
      final own = _androidStatusLooksLikeOwnTunnel(status);
      final external = _androidStatusLooksLikeExternalVpn(status);
      final activeRoute = own ? await _resolveAndroidConnectedRoute() : null;
      if (!mounted || syncEpoch != _vpnStatusSyncEpoch) return;
      await appendBlueVpnClientLog(
        'android sync status ownTunnel=$own externalVpn=$external status=$status',
      );
      setState(() {
        vpnEnabled = own;
        _externalVpnActive = external;
      });
      _trackConnectionState(own, route: activeRoute);
      return;
    }
    final on = await _vpnBackend.isConnected();
    if (mounted) {
      setState(() {
        vpnEnabled = on;
        _externalVpnActive = false;
      });
      if (on) {
        await _restoreWindowsRuntimeFailoverIfPossible(source: 'status_sync');
      } else if (_activeWindowsRuntimeRoute != null ||
          _windowsRuntimeFailoverTimer != null) {
        _disarmWindowsRuntimeFailover(reason: 'status_disconnected');
      }
      _trackConnectionState(
        on,
        route: _activeWindowsRuntimeRoute ?? _activeConnectionRoute,
      );
    }
  }

  bool _androidStatusLooksLikeOwnTunnel(Map<String, dynamic> status) {
    final state = (status['state'] ?? '').toString().toLowerCase();
    if (status['connected'] == true ||
        status['ownTunnelRunning'] == true ||
        state == 'up') {
      return true;
    }
    if (status['systemVpnActive'] == true &&
        (status['lastGreenVpnActive'] == true ||
            status['ownTunnelSource'] == 'marker')) {
      return true;
    }
    final nativeTunnelName = (status['nativeTunnelName'] ?? '').toString();
    final expectedNames = <String>{
      kTunnelName,
      if (nativeTunnelName.isNotEmpty) nativeTunnelName,
      'GreenVPN',
    };
    final running = status['runningTunnels'];
    if (running is Iterable) {
      return running.any((item) => expectedNames.contains(item.toString()));
    }
    return false;
  }

  bool _androidStatusLooksLikeExternalVpn(Map<String, dynamic> status) {
    if (_androidStatusLooksLikeOwnTunnel(status)) return false;
    return status['externalVpnActive'] == true ||
        status['systemVpnActiveWithoutOwnTunnel'] == true ||
        status['systemVpnActive'] == true;
  }

  Future<void> _prepareAndroidControlPlaneAccess(String reason) async {
    if (kIsWeb || !Platform.isAndroid || vpnEnabled) return;
    try {
      final status = await WireGuardAndroidBackend.statusSnapshot(
        tunnelName: kTunnelName,
      );
      final ownTunnel = _androidStatusLooksLikeOwnTunnel(status);
      final systemVpnActive = status['systemVpnActive'] == true;
      final externalVpnActive = _androidStatusLooksLikeExternalVpn(status);
      await appendBlueVpnClientLog(
        'android control-plane preflight reason=$reason ownTunnel=$ownTunnel systemVpnActive=$systemVpnActive externalVpnActive=$externalVpnActive status=$status',
      );
      if (!ownTunnel) {
        if (mounted && externalVpnActive) {
          setState(() {
            vpnEnabled = false;
            _externalVpnActive = true;
          });
        }
        return;
      }
      await _recoverAndroidStaleVpnForNetwork('preflight_$reason');
      return;
    } catch (e) {
      await appendBlueVpnClientLog(
        'android control-plane preflight failed reason=$reason error=$e',
      );
      return;
    }
  }

  Future<void> _prepareAndroidConnectControlPlane(String reason) async {
    if (kIsWeb || !Platform.isAndroid || vpnEnabled) return;
    try {
      final status = await WireGuardAndroidBackend.statusSnapshot(
        tunnelName: kTunnelName,
      );
      final ownTunnel = _androidStatusLooksLikeOwnTunnel(status);
      final systemVpnActive = status['systemVpnActive'] == true;
      final externalVpnActive = _androidStatusLooksLikeExternalVpn(status);
      await appendBlueVpnClientLog(
        'android connect preflight reason=$reason ownTunnel=$ownTunnel systemVpnActive=$systemVpnActive externalVpnActive=$externalVpnActive status=$status',
      );
      if (ownTunnel) {
        await _recoverAndroidStaleVpnForNetwork('connect_preflight_$reason');
        return;
      }
      if (!systemVpnActive) return;
      if (mounted && externalVpnActive) {
        setState(() => _externalVpnActive = true);
      }
      await appendBlueVpnClientLog(
        'android connect preflight external vpn is active; next real connect will request Green VPN takeover with fresh config',
      );
    } catch (e) {
      await appendBlueVpnClientLog(
        'android connect preflight failed reason=$reason error=$e',
      );
    }
  }

  bool _isAndroidNetworkFailureMessage(String? message) {
    if (kIsWeb || !Platform.isAndroid) return false;
    final raw = (message ?? '').toLowerCase();
    if (raw.isEmpty) return false;
    return raw.contains('socketexception') ||
        raw.contains('timed out') ||
        raw.contains('timeout') ||
        raw.contains('timeoutexception') ||
        raw.contains('future not completed') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection reset') ||
        raw.contains('connection refused') ||
        raw.contains('network is unreachable') ||
        raw.contains('api.greenvpn.pro');
  }

  Future<bool> _recoverAndroidStaleVpnForNetwork(String reason) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    await appendBlueVpnClientLog(
      'android stale vpn recovery start reason=$reason',
    );
    try {
      final before = await WireGuardAndroidBackend.statusSnapshot(
        tunnelName: kTunnelName,
      );
      await appendBlueVpnClientLog('android stale vpn recovery before=$before');
    } catch (e) {
      await appendBlueVpnClientLog(
        'android stale vpn recovery before failed=$e',
      );
    }

    final off = await _vpnBackend.disconnect();
    await appendBlueVpnClientLog(
      'android stale vpn recovery disconnect ok=${off.ok} message=${off.message ?? ""}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 900));

    try {
      final after = await WireGuardAndroidBackend.statusSnapshot(
        tunnelName: kTunnelName,
      );
      await appendBlueVpnClientLog('android stale vpn recovery after=$after');
    } catch (e) {
      await appendBlueVpnClientLog(
        'android stale vpn recovery after failed=$e',
      );
    }
    await _syncVpnStatus();
    return off.ok;
  }

  Future<String?> _rotateDeviceId() async {
    if (kIsWeb) return null;
    final next = await _deviceStore.rotate();
    _deviceId = next;
    return next;
  }

  Future<ApiResult<Map<String, dynamic>>> _bootstrapWithDeviceRetry({
    required bool showToastOnRotate,
    Duration? totalBudget,
  }) async {
    final budgetWatch = Stopwatch()..start();
    Duration? remainingBudget() {
      final budget = totalBudget;
      if (budget == null) return null;
      final remaining = budget - budgetWatch.elapsed;
      return remaining > Duration.zero ? remaining : Duration.zero;
    }

    Future<ApiResult<Map<String, dynamic>>> requestBootstrap(String deviceId) {
      final remaining = remainingBudget();
      if (remaining == Duration.zero) {
        return Future.value(
          const ApiResult.err(
            'Сеть не ответила вовремя. Проверь связь и повтори подключение.',
          ),
        );
      }
      return _api.bootstrapClient(
        accessToken: widget.session.accessToken,
        deviceId: deviceId,
        deviceName: greenVpnClientDeviceName(),
        platform: greenVpnClientPlatform(),
        appVersion: kAppVersion,
        requestBudget: remaining,
      );
    }

    var did = await _ensureDeviceId();
    if (did == null || did.isEmpty) {
      return const ApiResult.err('Не удалось получить device id.');
    }

    var boot = await requestBootstrap(did);

    if (!boot.ok &&
        _isAndroidNetworkFailureMessage(boot.message) &&
        (remainingBudget() == null ||
            remainingBudget()! > const Duration(seconds: 2))) {
      await _recoverAndroidStaleVpnForNetwork(
        boot.message ?? 'bootstrap_network_failure',
      );
      boot = await requestBootstrap(did);
    }

    final attachedToAnotherUser = greenVpnIsDeviceAttachedConflict(
      boot.message,
    );
    final autoReplaced = greenVpnShouldRotateAutoReplacedDevice(boot.data);
    if (!attachedToAnotherUser && !autoReplaced) {
      return boot;
    }

    did = await _rotateDeviceId();
    if (did == null || did.isEmpty) {
      return const ApiResult.err('Не удалось перевыпустить device id.');
    }

    if (showToastOnRotate && mounted) {
      _toast(
        context,
        autoReplaced
            ? 'Обновляем регистрацию этого устройства...'
            : 'Устройство было привязано к другому аккаунту. Обновляем регистрацию...',
      );
    }

    boot = await requestBootstrap(did);
    if (!boot.ok &&
        _isAndroidNetworkFailureMessage(boot.message) &&
        (remainingBudget() == null ||
            remainingBudget()! > const Duration(seconds: 2))) {
      await _recoverAndroidStaleVpnForNetwork(
        boot.message ?? 'bootstrap_rotated_network_failure',
      );
      boot = await requestBootstrap(did);
    }
    return boot;
  }

  Future<String?> _ensureDeviceId() async {
    if (kIsWeb) return null;
    _deviceId ??= await _deviceStore.getOrCreate();
    return _deviceId;
  }

  Future<void> _recordPaidBetaEvent(String eventType) async {
    if (!kPaidBetaBuild ||
        kIsWeb ||
        widget.session.accessToken == 'dev-token') {
      return;
    }
    try {
      final deviceId = await _ensureDeviceId();
      if (deviceId == null || deviceId.isEmpty) return;
      await _api.postPaidBetaEvent(
        accessToken: widget.session.accessToken,
        eventType: eventType,
        deviceId: deviceId,
        platform: greenVpnClientPlatform(),
      );
    } catch (_) {}
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
      if (greenVpnIsInvalidSessionMessage(res.message)) {
        await _noteInvalidSession(source: 'plan', message: res.message);
        return;
      }
      if (res.ok && res.data != null && mounted) {
        setState(() => planName = res.data!);
      }
    } catch (_) {}
  }

  Future<bool> _trySeedDevConfig({
    required bool showToast,
    ServerLocation? serverOverride,
  }) async {
    return _repairProvisionedConfigFromPreferredDevSource(
      showToast: showToast,
      serverOverride: serverOverride,
    );
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
      if (greenVpnIsInvalidSessionMessage(boot.message)) {
        await _noteInvalidSession(
          source: 'silent_bootstrap',
          message: boot.message,
        );
        return;
      }
      if (!boot.ok || boot.data == null) return;

      if (mounted) {
        setState(() => _applyClientFeatures(boot.data!['clientFeatures']));
        await _applyWindowsCloseBehavior();
      }

      final did = await _ensureDeviceId();
      if (did == null || did.isEmpty) return;

      final sub = boot.data!['subscription'];
      if (sub is Map) {
        final subMap = Map<String, dynamic>.from(sub);
        final p = (subMap['planName'] ?? subMap['planCode'] ?? '')
            .toString()
            .trim();
        if (mounted) {
          setState(() {
            if (p.isNotEmpty) planName = p;
            _applySubscriptionUiState(
              const <String, dynamic>{},
              subMap,
              trafficUsage: boot.data!['trafficUsage'],
            );
          });
          await _reconcileSubscriptionEntitlements();
        }
      }

      var res = await _api.fetchWireGuardConfig(
        accessToken: widget.session.accessToken,
        deviceId: did,
        serverId: selectedServer.id == 'auto' ? null : selectedServer.id,
        mode: socialOnlyEnabled ? 'social_only' : 'full',
      );
      if (!res.ok && _isAndroidNetworkFailureMessage(res.message)) {
        await _recoverAndroidStaleVpnForNetwork(
          res.message ?? 'silent_config_network_failure',
        );
        res = await _api.fetchWireGuardConfig(
          accessToken: widget.session.accessToken,
          deviceId: did,
          serverId: selectedServer.id == 'auto' ? null : selectedServer.id,
          mode: socialOnlyEnabled ? 'social_only' : 'full',
        );
      }
      if (greenVpnIsInvalidSessionMessage(res.message)) {
        await _noteInvalidSession(
          source: 'silent_config',
          message: res.message,
        );
        return;
      }
      if (res.ok && res.data != null) {
        final provisionedServer = _serverFromConfigResponse(
          res.data!,
          fallback: selectedServer,
        );
        await _writeProvisionedConfig(
          _normalizeDevEndpoint(res.data!.configText),
          server: provisionedServer,
        );
      } else {
        await _reuseExistingProvisionedConfig(
          reason: res.message ?? '',
          showToast: false,
          serverOverride: selectedServer,
        );
      }
    } catch (_) {}
  }

  bool _bootAdGateRequiresReward(Map<String, dynamic> bootMap) {
    if (kAdsDisabledBuild) return false;
    final adGateRaw = bootMap['adGate'];
    if (adGateRaw is! Map) return false;
    final adGate = Map<String, dynamic>.from(adGateRaw);
    return adGate['enabled'] == true && adGate['required'] == true;
  }

  Map<String, dynamic>? _asStringMap(Object? raw) {
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  DateTime? _parseServerDateTime(Object? raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text.replaceFirst('Z', '+00:00'))?.toUtc();
  }

  void _scheduleFreeAdSessionFromAdGate(
    Map<String, dynamic> adGate, {
    required String source,
  }) {
    if (kAdsDisabledBuild || adGate['enabled'] != true) {
      _cancelFreeAdSessionTimer();
      return;
    }
    if (adGate['sessionTimerEnabled'] == false) {
      _cancelFreeAdSessionTimer();
      unawaited(
        appendBlueVpnClientLog(
          'free ad session timer disabled by server source=$source',
        ),
      );
      return;
    }

    final consumedGrant = _asStringMap(adGate['consumedGrant']);
    final grant = consumedGrant ?? _asStringMap(adGate['grant']);
    final expiresAt = _parseServerDateTime(
      consumedGrant?['sessionExpiresAt'] ??
          consumedGrant?['expiresAt'] ??
          grant?['sessionExpiresAt'] ??
          grant?['expiresAt'] ??
          adGate['sessionExpiresAt'],
    );
    if (expiresAt == null) return;

    final delay = expiresAt.difference(DateTime.now().toUtc());
    if (delay <= const Duration(seconds: 5)) {
      unawaited(_expireFreeAdSession(source: '$source:already_expired'));
      return;
    }

    _freeAdSessionTimer?.cancel();
    _freeAdSessionTimer = Timer(delay, () {
      unawaited(_expireFreeAdSession(source: source));
    });
    unawaited(_storeFreeAdSessionExpiry(expiresAt));
    unawaited(
      appendBlueVpnClientLog(
        'free ad session timer scheduled source=$source seconds=${delay.inSeconds} expiresAt=${expiresAt.toIso8601String()}',
      ),
    );
  }

  void _cancelFreeAdSessionTimer() {
    _freeAdSessionTimer?.cancel();
    _freeAdSessionTimer = null;
    unawaited(_clearStoredFreeAdSessionExpiry());
  }

  Future<void> _storeFreeAdSessionExpiry(DateTime expiresAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _freeAdSessionExpiryPrefsKey,
        expiresAt.toUtc().toIso8601String(),
      );
    } catch (_) {}
  }

  Future<void> _clearStoredFreeAdSessionExpiry() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_freeAdSessionExpiryPrefsKey);
    } catch (_) {}
  }

  Future<void> _restoreFreeAdSessionTimer() async {
    if (!mounted || kAdsDisabledBuild) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final expiresAt = _parseServerDateTime(
        prefs.getString(_freeAdSessionExpiryPrefsKey),
      );
      if (expiresAt == null) return;
      final delay = expiresAt.difference(DateTime.now().toUtc());
      if (delay <= const Duration(seconds: 5)) {
        final connected = await _vpnBackend.isConnected();
        if (connected || vpnEnabled) {
          await _expireFreeAdSession(source: 'restore:expired');
        } else {
          await _clearStoredFreeAdSessionExpiry();
        }
        return;
      }
      _freeAdSessionTimer?.cancel();
      _freeAdSessionTimer = Timer(delay, () {
        unawaited(_expireFreeAdSession(source: 'restore'));
      });
      await appendBlueVpnClientLog(
        'free ad session timer restored seconds=${delay.inSeconds} expiresAt=${expiresAt.toIso8601String()}',
      );
    } catch (e) {
      await appendBlueVpnClientLog('free ad session restore failed error=$e');
    }
  }

  Future<void> _expireFreeAdSession({required String source}) async {
    if (!mounted || kAdsDisabledBuild) return;
    if (vpnBusy) {
      _freeAdSessionTimer?.cancel();
      _freeAdSessionTimer = Timer(const Duration(seconds: 15), () {
        unawaited(_expireFreeAdSession(source: '$source:retry'));
      });
      return;
    }

    await appendBlueVpnClientLog('free ad session expired source=$source');
    final connected = await _vpnBackend.isConnected();
    if (!connected && !vpnEnabled) {
      _cancelFreeAdSessionTimer();
      return;
    }
    _setVpnBusyUi(
      stage: 'Бесплатная сессия закончилась...',
      hint:
          'Отключаем VPN. Для нового подключения нужно снова посмотреть рекламу.',
    );
    try {
      _disarmWindowsRuntimeFailover(reason: 'free_session_expired');
      final res = await _vpnBackend.disconnect();
      await appendBlueVpnClientLog(
        'free ad session disconnect ok=${res.ok} message=${res.message ?? ""}',
      );
      await _syncVpnStatus();
      if (!mounted) return;
      setState(() => vpnEnabled = false);
      _toast(
        context,
        'Бесплатная сессия закончилась. Для нового подключения посмотри рекламу.',
      );
    } finally {
      _cancelFreeAdSessionTimer();
      _clearVpnBusyUi();
    }
  }

  Future<bool> _waitForAdChallengeCompletion(String challengeId) async {
    for (var attempt = 0; attempt < 45; attempt++) {
      if (!mounted) return false;
      await Future.delayed(const Duration(seconds: 2));
      final res = await _api.fetchAdChallenge(
        accessToken: widget.session.accessToken,
        challengeId: challengeId,
      );
      if (!res.ok || res.data == null) continue;
      final challengeRaw = res.data!['challenge'];
      if (challengeRaw is! Map) continue;
      final challenge = Map<String, dynamic>.from(challengeRaw);
      final status = (challenge['status'] ?? '').toString().toLowerCase();
      if (status == 'completed') return true;
      if (status == 'expired') return false;
    }
    return false;
  }

  Future<bool> _completeAndroidYandexRewardedChallenge({
    required String adUnitId,
    required String challengeId,
    required String rewardUrl,
    Future<void> Function()? onRewardGranted,
  }) async {
    final token = greenVpnAdChallengeTokenFromRewardUrl(rewardUrl);
    if (token.isEmpty) {
      _toast(context, 'Сервер не вернул подтверждающий код рекламы.');
      return false;
    }

    _setVpnBusyUi(
      stage: 'Показываем рекламу...',
      hint:
          'Досмотри видео до зачёта награды. После этого Green VPN продолжит подключение.',
    );

    Future<ApiResult<Map<String, dynamic>>>? completeFuture;
    var rewardGrantedCallbackStarted = false;

    Future<ApiResult<Map<String, dynamic>>> completeChallenge() {
      completeFuture ??= _api.completeAdChallenge(
        challengeId: challengeId,
        token: token,
      );
      return completeFuture!;
    }

    Future<void> completeAndPrepareConfig() async {
      final complete = await completeChallenge();
      if (!complete.ok) {
        await appendBlueVpnClientLog(
          'Yandex rewarded early complete failed: ${complete.message ?? ""}',
        );
        return;
      }
      final callback = onRewardGranted;
      if (callback == null || rewardGrantedCallbackStarted) return;
      rewardGrantedCallbackStarted = true;
      unawaited(callback());
    }

    final rewarded = await GreenVpnYandexRewardedAds.showRewardedAd(
      adUnitId: adUnitId,
      log: appendBlueVpnClientLog,
      onRewarded: completeAndPrepareConfig,
    );
    if (!mounted) return false;
    if (!rewarded) {
      _toast(
        context,
        'Реклама не была засчитана. Попробуй подключиться ещё раз.',
      );
      return false;
    }

    final complete = await completeChallenge();
    if (!mounted) return false;
    if (!complete.ok) {
      _toast(
        context,
        complete.message ?? 'Реклама показана, но сервер не засчитал доступ.',
      );
      return false;
    }

    final callback = onRewardGranted;
    if (callback != null && !rewardGrantedCallbackStarted) {
      rewardGrantedCallbackStarted = true;
      unawaited(callback());
    }

    return true;
  }

  Future<bool> _ensureAdRewardForConnect(
    Map<String, dynamic> bootMap,
    String deviceId, {
    Future<void> Function()? onRewardGranted,
  }) async {
    if (kAdsDisabledBuild) return true;
    if (!_bootAdGateRequiresReward(bootMap)) return true;
    final yandexRewardedAdUnitId = greenVpnAndroidYandexRewardedAdUnitId(
      bootMap,
    );

    _setVpnBusyUi(
      stage: 'Нужно посмотреть рекламу...',
      hint:
          'Бесплатный режим требует рекламный просмотр перед подключением. Платный тариф подключается без рекламы.',
    );

    final start = await _api.startAdChallenge(
      accessToken: widget.session.accessToken,
      deviceId: deviceId,
      platform: greenVpnClientPlatform(),
      provider: yandexRewardedAdUnitId.isNotEmpty
          ? 'yandex_mobile_ads'
          : (!kIsWeb && Platform.isWindows ? 'yandex_web_rewarded' : 'auto'),
      appVersion: kAppVersion,
    );
    if (!mounted) return false;

    if (!start.ok || start.data == null) {
      if (greenVpnIsInvalidSessionMessage(start.message)) {
        await _handleInvalidSession(
          source: 'ad_challenge_start',
          message: start.message,
        );
        return false;
      }
      _toast(
        context,
        start.message ?? 'Не удалось подготовить рекламный просмотр.',
      );
      return false;
    }

    final challengeRaw = start.data!['challenge'];
    if (challengeRaw == null) {
      return true;
    }
    if (challengeRaw is! Map) {
      _toast(context, 'Сервер вернул некорректный рекламный challenge.');
      return false;
    }

    final challenge = Map<String, dynamic>.from(challengeRaw);
    final challengeId = (challenge['challengeId'] ?? '').toString().trim();
    final rewardUrl = (challenge['rewardUrl'] ?? '').toString().trim();
    if (challengeId.isEmpty || rewardUrl.isEmpty) {
      _toast(context, 'Сервер не вернул ссылку на рекламный просмотр.');
      return false;
    }

    if (yandexRewardedAdUnitId.isNotEmpty) {
      return _completeAndroidYandexRewardedChallenge(
        adUnitId: yandexRewardedAdUnitId,
        challengeId: challengeId,
        rewardUrl: rewardUrl,
        onRewardGranted: onRewardGranted,
      );
    }

    await openExternalUrl(rewardUrl);
    if (!mounted) return false;
    _toast(
      context,
      Platform.isAndroid
          ? 'Открыл рекламный экран. После зачёта вернись в Green VPN.'
          : 'Открыл рекламный экран в браузере.',
    );

    _setVpnBusyUi(
      stage: 'Ждём зачёт рекламы...',
      hint:
          'Когда рекламный экран засчитает просмотр, Green VPN продолжит подключение автоматически.',
    );

    final completed = await _waitForAdChallengeCompletion(challengeId);
    if (!mounted) return false;
    if (!completed) {
      _toast(
        context,
        'Реклама не засчиталась. Нажми подключение ещё раз и повтори просмотр.',
      );
      return false;
    }

    final callback = onRewardGranted;
    if (callback != null) {
      unawaited(callback());
    }

    return true;
  }

  Future<ApiResult<WireGuardConfigResponse>> _fetchWireGuardConfigWithRecovery(
    String deviceId,
    ServerLocation effectiveServer, {
    required String source,
    Duration? totalBudget,
  }) async {
    final budgetWatch = Stopwatch()..start();
    Duration? remainingBudget() {
      final budget = totalBudget;
      if (budget == null) return null;
      final remaining = budget - budgetWatch.elapsed;
      return remaining > Duration.zero ? remaining : Duration.zero;
    }

    Future<ApiResult<WireGuardConfigResponse>> requestConfig() {
      final remaining = remainingBudget();
      if (remaining == Duration.zero) {
        return Future.value(
          const ApiResult.err(
            'Сеть не ответила вовремя. Проверь связь и повтори подключение.',
          ),
        );
      }
      return _api.fetchWireGuardConfig(
        accessToken: widget.session.accessToken,
        deviceId: deviceId,
        serverId: effectiveServer.isAuto ? null : effectiveServer.id,
        mode: socialOnlyEnabled ? 'social_only' : 'full',
        requestBudget: remaining,
      );
    }

    var res = await requestConfig();
    if (!res.ok &&
        _isAndroidNetworkFailureMessage(res.message) &&
        (remainingBudget() == null ||
            remainingBudget()! > const Duration(seconds: 2))) {
      await _recoverAndroidStaleVpnForNetwork(
        res.message ?? '${source}_network_failure',
      );
      res = await requestConfig();
    }
    await appendBlueVpnClientLog(
      'ensure config fetch source=$source ok=${res.ok} message=${res.message ?? ""} bytes=${res.data?.configText.length ?? 0} server=${res.data?.serverId ?? ""}',
    );
    return res;
  }

  Future<ProvisionedConfigResult> _ensureProvisionedConfigInteractive({
    ServerLocation? serverOverride,
    bool requireExactServer = false,
    bool boundedAndroidNetwork = false,
  }) async {
    if (kIsWeb) return const ProvisionedConfigResult.err('web_unavailable');
    final effectiveServer = serverOverride ?? selectedServer;
    await appendBlueVpnClientLog(
      'ensure config interactive start token=${widget.session.accessToken == "dev-token" ? "dev" : "real"} server=${effectiveServer.id}',
    );
    await _prepareAndroidConnectControlPlane('interactive_config');

    if (widget.session.accessToken == 'dev-token') {
      final ok = await _trySeedDevConfig(
        showToast: true,
        serverOverride: effectiveServer,
      );
      await appendBlueVpnClientLog('ensure config interactive dev result=$ok');
      if (!mounted) {
        return const ProvisionedConfigResult.err('screen_closed');
      }
      if (ok && !requireExactServer) {
        return ProvisionedConfigResult.ok(effectiveServer);
      }
      if (ok && requireExactServer) {
        final base = await _cfg.readBaseConfigForServer(effectiveServer.id);
        if (!mounted) {
          return const ProvisionedConfigResult.err('screen_closed');
        }
        if (base != null &&
            base.trim().isNotEmpty &&
            _configMatchesServer(effectiveServer, base)) {
          return ProvisionedConfigResult.ok(effectiveServer);
        }
      }
      _toast(
        context,
        'Тестовый локальный режим недоступен. Войди в аккаунт, чтобы получить VPN-конфигурацию с сервера.',
      );
      return const ProvisionedConfigResult.err('dev_config_unavailable');
    }

    final useAndroidBudget =
        boundedAndroidNetwork && !kIsWeb && Platform.isAndroid;
    final boot = await _bootstrapWithDeviceRetry(
      showToastOnRotate: true,
      totalBudget: useAndroidBudget ? const Duration(seconds: 10) : null,
    );
    await appendBlueVpnClientLog(
      'ensure config bootstrap ok=${boot.ok} message=${boot.message ?? ""}',
    );
    if (!mounted) {
      return const ProvisionedConfigResult.err('screen_closed');
    }

    if (!boot.ok || boot.data == null) {
      if (greenVpnIsInvalidSessionMessage(boot.message)) {
        await _handleInvalidSession(
          source: 'interactive_bootstrap',
          message: boot.message,
        );
        return ProvisionedConfigResult.err('invalid_session');
      }
      final reused = await _reuseExistingProvisionedConfig(
        reason: boot.message ?? '',
        showToast: true,
        serverOverride: effectiveServer,
      );
      if (reused && !requireExactServer) {
        return ProvisionedConfigResult.ok(effectiveServer);
      }
      if (!mounted) {
        return const ProvisionedConfigResult.err('screen_closed');
      }
      _toast(context, boot.message ?? 'Не удалось пройти bootstrap.');
      return ProvisionedConfigResult.err(boot.message);
    }

    final did = await _ensureDeviceId();
    await appendBlueVpnClientLog('ensure config deviceId=${did ?? "null"}');
    if (!mounted) {
      return const ProvisionedConfigResult.err('screen_closed');
    }
    if (did == null || did.isEmpty) {
      _toast(context, 'Не удалось получить device id.');
      return const ProvisionedConfigResult.err('device_id_missing');
    }

    final bootMap = boot.data!;
    setState(() => _applyClientFeatures(bootMap['clientFeatures']));
    await _applyWindowsCloseBehavior();
    if (!mounted) {
      return const ProvisionedConfigResult.err('screen_closed');
    }
    final sub = bootMap['subscription'];
    if (sub is Map) {
      final subMap = Map<String, dynamic>.from(sub);
      final p = (subMap['planName'] ?? subMap['planCode'] ?? '')
          .toString()
          .trim();
      if (mounted) {
        setState(() {
          if (p.isNotEmpty) planName = p;
          _applySubscriptionUiState(
            const <String, dynamic>{},
            subMap,
            trafficUsage: bootMap['trafficUsage'],
          );
        });
        await _reconcileSubscriptionEntitlements();
      }
    }

    if (kPaidBetaCustomerUi && bootMap['canConnect'] != true) {
      final reason = (bootMap['reason'] ?? '').toString().trim();
      final message = switch (reason) {
        'beta_cohort_required' =>
          'Для закрытой beta нужен персональный инвайт.',
        'subscription_inactive' =>
          'Beta Trial закончился. Открой тариф и оплати следующий период.',
        'free_quota_exhausted' =>
          'Бесплатный лимит на этот месяц исчерпан. Открой тариф или дождись нового месяца.',
        'device_limit_exceeded' =>
          _freeTierActive
              ? 'Бесплатный тариф: устройств не больше $_subscriptionMaxDevices.'
              : 'Достигнут лимит beta: не больше двух устройств.',
        'device_disabled' => 'Это устройство отключено в аккаунте.',
        _ => 'Beta-доступ сейчас недоступен.',
      };
      if (mounted) {
        _openTariff();
        _toast(context, message);
      }
      return ProvisionedConfigResult.err(
        reason.isEmpty ? 'paid_beta_access_denied' : reason,
      );
    }

    Future<ApiResult<WireGuardConfigResponse>>? prefetchedConfig;
    Future<void> startConfigPrefetchAfterAdReward() async {
      if (prefetchedConfig != null) return;
      prefetchedConfig = _fetchWireGuardConfigWithRecovery(
        did,
        effectiveServer,
        source: 'ad_reward_prefetch',
        totalBudget: useAndroidBudget ? const Duration(seconds: 12) : null,
      );
      await appendBlueVpnClientLog(
        'ensure config prefetch started after ad reward server=${effectiveServer.id}',
      );
    }

    final adReady = await _ensureAdRewardForConnect(
      bootMap,
      did,
      onRewardGranted: startConfigPrefetchAfterAdReward,
    );
    if (!adReady) {
      return const ProvisionedConfigResult.err('ad_reward_required');
    }

    final res =
        await (prefetchedConfig ??
            _fetchWireGuardConfigWithRecovery(
              did,
              effectiveServer,
              source: 'interactive_config',
              totalBudget: useAndroidBudget
                  ? const Duration(seconds: 12)
                  : null,
            ));
    if (!mounted) {
      return const ProvisionedConfigResult.err('screen_closed');
    }
    if (!res.ok || res.data == null || res.data!.configText.trim().isEmpty) {
      if (greenVpnIsInvalidSessionMessage(res.message)) {
        await _handleInvalidSession(
          source: 'interactive_config',
          message: res.message,
        );
        return ProvisionedConfigResult.err('invalid_session');
      }
      if (greenVpnIsAdRewardRequiredMessage(res.message)) {
        _toast(
          context,
          'Для бесплатного подключения сначала посмотри рекламу.',
        );
        return ProvisionedConfigResult.err(res.message);
      }
      if (greenVpnIsFreeQuotaExhaustedMessage(res.message)) {
        if (mounted) {
          _openTariff();
          _toast(
            context,
            'Бесплатный лимит исчерпан. Открой тариф или дождись нового месяца.',
          );
        }
        return ProvisionedConfigResult.err(res.message);
      }
      final reused = await _reuseExistingProvisionedConfig(
        reason: res.message ?? '',
        showToast: true,
        serverOverride: effectiveServer,
      );
      if (reused && !requireExactServer) {
        return ProvisionedConfigResult.ok(effectiveServer);
      }
      if (!mounted) {
        return const ProvisionedConfigResult.err('screen_closed');
      }
      _toast(context, res.message ?? 'Не удалось получить конфиг с сервера.');
      return ProvisionedConfigResult.err(res.message);
    }

    final provisionedServer = _serverFromConfigResponse(
      res.data!,
      fallback: effectiveServer,
    );
    if (!effectiveServer.isAuto &&
        provisionedServer.publicLocationId !=
            effectiveServer.publicLocationId) {
      await appendBlueVpnClientLog(
        'manual location reassignment rejected requested=${effectiveServer.id} actual=${provisionedServer.id}',
      );
      return const ProvisionedConfigResult.err(
        'Выбранная локация сейчас недоступна.',
      );
    }
    if (requireExactServer &&
        (provisionedServer.id != effectiveServer.id ||
            provisionedServer.protocolCode.trim().toLowerCase() !=
                effectiveServer.protocolCode.trim().toLowerCase())) {
      await appendBlueVpnClientLog(
        'exact route reassignment rejected requested=${effectiveServer.id}/${effectiveServer.protocolCode} actual=${provisionedServer.id}/${provisionedServer.protocolCode}',
      );
      return const ProvisionedConfigResult.err(
        'Нужный маршрут сейчас недоступен. Текущее подключение сохранено.',
      );
    }
    _scheduleFreeAdSessionFromAdGate(
      res.data!.adGate,
      source: 'interactive_config',
    );
    try {
      await _writeProvisionedConfig(
        res.data!.configText,
        server: provisionedServer,
      );
    } catch (error) {
      await appendBlueVpnClientLog(
        'ensure config endpoint preparation failed server=${provisionedServer.id} error=$error',
      );
      return const ProvisionedConfigResult.err(
        'Не удалось подготовить адрес VPN-сервера.',
      );
    }
    return ProvisionedConfigResult.ok(provisionedServer);
  }

  ServerLocation _serverFromConfigResponse(
    WireGuardConfigResponse config, {
    required ServerLocation fallback,
  }) {
    final actualId = config.serverId.trim();
    if (actualId.isEmpty || actualId == 'auto') return fallback;
    for (final server in servers) {
      if (server.id == actualId) return server;
    }
    if (fallback.id == actualId) return fallback;
    final title = config.serverName.trim().isNotEmpty
        ? config.serverName.trim()
        : actualId;
    return ServerLocation(
      id: actualId,
      title: title,
      subtitle: 'Выбрана рабочая локация',
      isAuto: false,
      status: 'healthy',
      available: true,
      clientConfigReady: true,
      protocolCode: config.protocol.isEmpty
          ? fallback.protocolCode
          : config.protocol,
      protocolLabel: config.protocol == 'amneziawg'
          ? 'Защищённый режим'
          : greenVpnTransportRequiresFullTunnel(config.protocol)
          ? 'Резервный режим'
          : fallback.protocolLabel,
    );
  }

  ServerLocation _backendAutoCandidate() {
    final routeId = (_adaptiveRouteServerId ?? '').trim();
    if (routeId.isNotEmpty) {
      for (final server in servers) {
        if (server.id == routeId && server.isCurrentClientReady) {
          return server;
        }
      }
    }
    return const ServerLocation(
      id: 'auto',
      title: 'Авто-подбор',
      subtitle: 'Автовыбор локации',
      isAuto: true,
      status: 'healthy',
      available: true,
      clientConfigReady: true,
    );
  }

  int _serverConnectScore(ServerLocation server) {
    final health = server.healthScore ?? 50;
    final latencyPenalty = server.pingMs == null
        ? 0
        : (server.pingMs! / 25).round().clamp(0, 40);
    final readinessBonus = server.isCurrentClientReady ? 20 : 0;
    final routeScoreBonus = ((_adaptiveRouteScore ?? 0) / 10).round().clamp(
      0,
      10,
    );
    final routeBonus =
        _adaptiveRouteServerId != null &&
            _adaptiveRouteServerId == server.id &&
            (_adaptiveRouteProtocol == null ||
                _adaptiveRouteProtocol == server.protocolCode)
        ? 30 + routeScoreBonus
        : 0;
    return health + readinessBonus + routeBonus - latencyPenalty;
  }

  String _routeCooldownKey(ServerLocation server) =>
      '${server.id.trim()}|${server.protocolCode.trim()}';

  void _recordRouteFailure(ServerLocation server, String stage) {
    if (!kTransportPreviewFallbackEnabled || server.isAuto) return;
    final key = _routeCooldownKey(server);
    final duration = _routeFailureCooldown.recordFailure(key);
    final failedPreferredRoute =
        !kIsWeb &&
        (Platform.isWindows || (Platform.isAndroid && kFusionUiEnabled)) &&
        stage != 'config_fetch' &&
        server.id == _lastSuccessfulRouteId &&
        server.protocolCode == _lastSuccessfulRouteProtocol;
    if (failedPreferredRoute) {
      _lastSuccessfulRouteId = '';
      _lastSuccessfulRouteProtocol = '';
      _lastSuccessfulRouteAt = null;
      _schedulePrefsSave();
    }
    unawaited(
      appendBlueVpnClientLog(
        'route cooldown started server=${server.id} protocol=${server.protocolCode} stage=$stage failures=${_routeFailureCooldown.failureCount(key)} seconds=${duration.inSeconds} clearedPreferred=$failedPreferredRoute',
      ),
    );
  }

  Future<void> _recordRouteSuccess(ServerLocation server) async {
    if (!kTransportPreviewFallbackEnabled || server.isAuto) return;
    _routeFailureCooldown.recordSuccess(_routeCooldownKey(server));
    if (!kIsWeb &&
        (Platform.isWindows || (Platform.isAndroid && kFusionUiEnabled))) {
      final routeId = greenVpnNormalizeManagedRouteId(server.id);
      final protocol = server.protocolCode.trim().toLowerCase();
      final confirmedAt = DateTime.now().toUtc();
      if (greenVpnIsFreshPreferredRoute(
        candidateId: routeId,
        candidateProtocol: protocol,
        preferredId: _lastSuccessfulRouteId,
        preferredProtocol: _lastSuccessfulRouteProtocol,
        preferredAt: _lastSuccessfulRouteAt,
        now: confirmedAt,
      )) {
        return;
      }
      try {
        await _prefsStore.patch({
          'lastSuccessfulRouteId': routeId,
          'lastSuccessfulRouteProtocol': protocol,
          'lastSuccessfulRouteAt': confirmedAt.toIso8601String(),
        });
        _lastSuccessfulRouteId = routeId;
        _lastSuccessfulRouteProtocol = protocol;
        _lastSuccessfulRouteAt = confirmedAt;
      } catch (error) {
        await appendBlueVpnClientLog(
          'route success cache persistence failed server=${server.id} error=$error',
        );
      }
    }
  }

  Future<void> _loadWindowsStandbyProofs() async {
    if (kIsWeb || !Platform.isWindows || _windowsStandbyProofsLoaded) return;
    final now = DateTime.now().toUtc();
    final loaded = await _windowsStandbyProofStore.read();
    loaded.removeWhere((_, proof) {
      final age = now.difference(proof.verifiedAt.toUtc());
      return age.isNegative || age > const Duration(hours: 24);
    });
    _windowsStandbyProofs
      ..clear()
      ..addAll(loaded);
    _windowsStandbyProofsLoaded = true;
    await appendBlueVpnClientLog(
      'windows standby proofs loaded count=${loaded.length}',
    );
  }

  bool _hasFreshWindowsStandbyProof(
    ServerLocation candidate, {
    required DateTime now,
    DateTime? verifiedNotAfter,
  }) {
    final key = greenVpnStandbyRouteKey(candidate.id, candidate.protocolCode);
    if (key.isEmpty) return false;
    final proof = _windowsStandbyProofs[key];
    return proof?.isFreshForPreparedConfig(
          now,
          _cfg.baseConfigModifiedAtForServerSync(candidate.id),
          verifiedNotAfter: verifiedNotAfter,
        ) ??
        false;
  }

  String _newWindowsStandbyRequestId() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      growable: false,
    ).join();
  }

  bool _standbyConfigMatchesCandidate(
    ServerLocation candidate,
    String rawConfig,
  ) {
    final protocol = candidate.protocolCode.trim().toLowerCase();
    if (protocol == 'wireguard_udp' || protocol == 'amneziawg') {
      return _configMatchesServer(candidate, rawConfig);
    }
    final expectedHosts = _knownEndpointHostsForServer(candidate)
      ..add((candidate.endpointHost ?? '').trim().toLowerCase());
    expectedHosts.removeWhere((value) => value.isEmpty);
    try {
      String endpoint = '';
      if (protocol == 'hysteria2') {
        endpoint =
            RegExp(
              r'^\s*server\s*:\s*([^\s:]+):\d+\s*$',
              multiLine: true,
              caseSensitive: false,
            ).firstMatch(rawConfig)?.group(1)?.trim().toLowerCase() ??
            '';
      } else if (protocol == 'vless_reality') {
        final root = jsonDecode(rawConfig) as Map;
        endpoint = root['outbounds'][0]['settings']['vnext'][0]['address']
            .toString()
            .trim()
            .toLowerCase();
      } else if (protocol == 'naive_https') {
        final root = jsonDecode(rawConfig) as Map;
        endpoint = (root['endpointIp'] ?? '').toString().trim().toLowerCase();
        if (endpoint.isEmpty) {
          endpoint =
              Uri.tryParse(
                (root['proxy'] ?? '').toString(),
              )?.host.toLowerCase() ??
              '';
        }
      } else if (protocol == 'dnstt') {
        final root = jsonDecode(rawConfig) as Map;
        endpoint = (root['expectedEgress'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
      }
      return endpoint.isNotEmpty && expectedHosts.contains(endpoint);
    } catch (_) {
      return false;
    }
  }

  Future<DateTime?> _prepareWindowsStandbyConfig(
    ServerLocation candidate,
  ) async {
    var cached = await _cfg.readBaseConfigForServer(candidate.id);
    var cachedAt = await _cfg.baseConfigModifiedAtForServer(candidate.id);
    var cachedValid =
        (cached ?? '').trim().isNotEmpty &&
        _standbyConfigMatchesCandidate(candidate, cached!);
    final now = DateTime.now().toUtc();
    if (cachedValid &&
        !greenVpnShouldRefreshStandbyConfig(cachedAt: cachedAt, now: now)) {
      return cachedAt;
    }

    if (widget.session.accessToken != 'dev-token') {
      final deviceId = await _ensureDeviceId();
      if (deviceId != null && deviceId.isNotEmpty) {
        final response = await _fetchWireGuardConfigWithRecovery(
          deviceId,
          candidate,
          source: 'windows_standby_prefetch',
        );
        if (response.ok &&
            response.data != null &&
            response.data!.configText.trim().isNotEmpty) {
          final actualId = response.data!.serverId.trim();
          final actualProtocol = response.data!.protocol.trim().toLowerCase();
          if (actualId == candidate.id &&
              (actualProtocol.isEmpty ||
                  actualProtocol == candidate.protocolCode.toLowerCase())) {
            final prepared = await _prepareProvisionedConfigForPlatform(
              response.data!.configText,
              server: candidate,
            );
            if (_standbyConfigMatchesCandidate(candidate, prepared)) {
              await _cfg.writeBaseConfigForServer(candidate.id, prepared);
              cached = prepared;
              cachedAt = await _cfg.baseConfigModifiedAtForServer(candidate.id);
              cachedValid = true;
              await appendBlueVpnClientLog(
                'windows standby config cached server=${candidate.id} protocol=${candidate.protocolCode}',
              );
            } else {
              await appendBlueVpnClientLog(
                'windows standby config rejected server=${candidate.id} reason=endpoint_mismatch',
              );
            }
          } else {
            await appendBlueVpnClientLog(
              'windows standby config rejected requested=${candidate.id}/${candidate.protocolCode} actual=$actualId/$actualProtocol',
            );
          }
        } else {
          await appendBlueVpnClientLog(
            'windows standby config refresh failed server=${candidate.id} message=${response.message ?? ""} cachedFallback=$cachedValid',
          );
        }
      }
    }
    return cachedValid ? cachedAt : null;
  }

  Future<bool> _probeWindowsStandbyRoute(
    ServerLocation candidate, {
    required DateTime preparedAt,
    required int epoch,
  }) async {
    final requestId = _newWindowsStandbyRequestId();
    final requestFile = File(greenVpnStandbyProbeRequestPathSync());
    final resultFile = File(greenVpnStandbyProbeResultPathSync());
    try {
      if (resultFile.existsSync()) {
        await WindowsLocalSecurity.preparePrivateFileForWrite(resultFile.path);
        await resultFile.delete();
      }
      await requestFile.writeAsString(
        jsonEncode(<String, dynamic>{
          'schema': 1,
          'requestId': requestId,
          'routeId': candidate.id,
          'protocol': candidate.protocolCode.trim().toLowerCase(),
        }),
        flush: true,
      );
      await WindowsLocalSecurity.prepareSharedConfigFile(requestFile.path);
      const service = _GreenVpnSystemServiceClient();
      final response = await service.probeStandby();
      if (!mounted ||
          epoch != _windowsRuntimeFailoverEpoch ||
          !vpnEnabled ||
          !greenVpnCanAcceptWindowsStandbyProof(
            runtimeFailureCount: _windowsRuntimeFailureCount,
            recoveryRunning: _windowsRuntimeRecoveryRunning,
          )) {
        return false;
      }
      if (!resultFile.existsSync()) {
        await appendBlueVpnClientLog(
          'windows standby probe missing result server=${candidate.id} http=${response.statusCode}',
        );
        return false;
      }
      final decoded = jsonDecode(await resultFile.readAsString());
      if (decoded is! Map) return false;
      final result = Map<String, dynamic>.from(decoded);
      final resultRequestId = (result['requestId'] ?? '').toString();
      final resultRouteId = (result['routeId'] ?? '').toString();
      final resultProtocol = (result['protocol'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (resultRequestId != requestId ||
          resultRouteId != candidate.id ||
          resultProtocol != candidate.protocolCode.trim().toLowerCase()) {
        await appendBlueVpnClientLog(
          'windows standby probe rejected server=${candidate.id} reason=result_identity_mismatch',
        );
        return false;
      }
      final cancelled = result['cancelled'] == true;
      final success =
          response.ok &&
          result['success'] == true &&
          result['cleanupOk'] == true;
      if (!success) {
        if (!cancelled) {
          _windowsStandbyRetryAfter[greenVpnStandbyRouteKey(
            candidate.id,
            candidate.protocolCode,
          )] = DateTime.now().toUtc().add(
            greenVpnStandbyFailureRetryDelay,
          );
        }
        await appendBlueVpnClientLog(
          'windows standby probe failed server=${candidate.id} protocol=${candidate.protocolCode} cancelled=$cancelled code=${result['errorCode'] ?? "unknown"}',
        );
        return false;
      }
      final kindName = (result['proofKind'] ?? '').toString();
      GreenVpnStandbyProofKind? kind;
      for (final value in GreenVpnStandbyProofKind.values) {
        if (value.name == kindName) {
          kind = value;
          break;
        }
      }
      final verifiedAt = DateTime.tryParse(
        (result['verifiedAt'] ?? '').toString(),
      );
      final latencyMs = switch (result['latencyMs']) {
        int value => value,
        num value => value.round(),
        final value => int.tryParse(value?.toString() ?? ''),
      };
      if (kind == null ||
          verifiedAt == null ||
          latencyMs == null ||
          latencyMs < 0) {
        return false;
      }
      final proof = GreenVpnStandbyRouteProof(
        routeId: candidate.id,
        protocol: candidate.protocolCode.trim().toLowerCase(),
        kind: kind,
        preparedAt: preparedAt.toUtc(),
        verifiedAt: verifiedAt.toUtc(),
        latencyMs: latencyMs,
      );
      if (!greenVpnCanAcceptWindowsStandbyProof(
        runtimeFailureCount: _windowsRuntimeFailureCount,
        recoveryRunning: _windowsRuntimeRecoveryRunning,
      )) {
        await appendBlueVpnClientLog(
          'windows standby proof discarded server=${candidate.id} reason=active_route_unhealthy',
        );
        return false;
      }
      _windowsStandbyProofs[proof.key] = proof;
      _windowsStandbyRetryAfter.remove(proof.key);
      await _windowsStandbyProofStore.write(_windowsStandbyProofs);
      await appendBlueVpnClientLog(
        'windows standby probe confirmed server=${candidate.id} protocol=${candidate.protocolCode} proof=${kind.name} ms=$latencyMs youtube=${result['youtubeStatus'] ?? 0}',
      );
      unawaited(
        _reportRouteEvent(
          candidate,
          stage: 'standby_probe',
          ok: true,
          latencyMs: latencyMs,
          details: <String, dynamic>{
            'proof': kind.name,
            'youtubeStatus': result['youtubeStatus'],
            'cleanupOk': true,
          },
        ),
      );
      return true;
    } catch (error) {
      await appendBlueVpnClientLog(
        'windows standby probe exception server=${candidate.id} error=$error',
      );
      return false;
    } finally {
      try {
        if (requestFile.existsSync()) {
          await WindowsLocalSecurity.preparePrivateFileForWrite(
            requestFile.path,
          );
          await requestFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _runWindowsStandbyCycle(
    ServerLocation activeRoute,
    int epoch,
  ) async {
    if (kIsWeb ||
        !Platform.isWindows ||
        !mounted ||
        !vpnEnabled ||
        vpnBusy ||
        _windowsRuntimeRecoveryRunning ||
        _windowsStandbyCycleRunning ||
        !greenVpnCanAcceptWindowsStandbyProof(
          runtimeFailureCount: _windowsRuntimeFailureCount,
          recoveryRunning: _windowsRuntimeRecoveryRunning,
        ) ||
        epoch != _windowsRuntimeFailoverEpoch ||
        socialOnlyEnabled ||
        _socialOnlyPreferenceRequested) {
      return;
    }
    final now = DateTime.now().toUtc();
    if (!greenVpnIsFreshPreferredRoute(
      candidateId: activeRoute.id,
      candidateProtocol: activeRoute.protocolCode,
      preferredId: _lastSuccessfulRouteId,
      preferredProtocol: _lastSuccessfulRouteProtocol,
      preferredAt: _lastSuccessfulRouteAt,
      now: now,
    )) {
      return;
    }
    _windowsStandbyCycleRunning = true;
    try {
      await _loadWindowsStandbyProofs();
      final activeKey = _routeCooldownKey(activeRoute);
      final candidates = _connectCandidatesForCurrentSelection();
      final seen = <String>{};
      final eligible = candidates
          .where((candidate) => _routeCooldownKey(candidate) != activeKey)
          .map(
            (candidate) =>
                '${greenVpnNormalizeManagedRouteId(candidate.id)}/${candidate.protocolCode.trim().toLowerCase()}',
          )
          .toSet()
          .toList(growable: false);
      await appendBlueVpnClientLog(
        'windows standby cycle started active=${activeRoute.id}/${activeRoute.protocolCode} eligible=${eligible.join(",")}',
      );
      var checked = 0;
      for (final candidate in candidates) {
        final key = greenVpnStandbyRouteKey(
          candidate.id,
          candidate.protocolCode,
        );
        if (key.isEmpty || key == activeKey || !seen.add(key)) continue;
        if (!mounted ||
            !vpnEnabled ||
            vpnBusy ||
            _windowsRuntimeRecoveryRunning ||
            !greenVpnCanAcceptWindowsStandbyProof(
              runtimeFailureCount: _windowsRuntimeFailureCount,
              recoveryRunning: _windowsRuntimeRecoveryRunning,
            ) ||
            epoch != _windowsRuntimeFailoverEpoch) {
          return;
        }
        if (_hasFreshWindowsStandbyProof(
          candidate,
          now: DateTime.now().toUtc(),
        )) {
          continue;
        }
        final retryAfter = _windowsStandbyRetryAfter[key];
        if (retryAfter != null && retryAfter.isAfter(DateTime.now().toUtc())) {
          continue;
        }
        final preparedAt = await _prepareWindowsStandbyConfig(candidate);
        if (preparedAt == null) {
          _windowsStandbyRetryAfter[key] = DateTime.now().toUtc().add(
            greenVpnStandbyFailureRetryDelay,
          );
          continue;
        }
        await _probeWindowsStandbyRoute(
          candidate,
          preparedAt: preparedAt,
          epoch: epoch,
        );
        checked += 1;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (mounted && epoch == _windowsRuntimeFailoverEpoch) {
        final completedAt = DateTime.now().toUtc();
        final freshCount = candidates
            .where(
              (candidate) =>
                  _hasFreshWindowsStandbyProof(candidate, now: completedAt),
            )
            .length;
        await appendBlueVpnClientLog(
          'windows standby cycle complete active=${activeRoute.id} checked=$checked fresh=$freshCount candidates=${candidates.length}',
        );
      }
    } finally {
      _windowsStandbyCycleRunning = false;
    }
  }

  void _cancelWindowsStandbyProbe({required String reason}) {
    if (kIsWeb || !Platform.isWindows) return;
    unawaited(() async {
      const service = _GreenVpnSystemServiceClient();
      final response = await service.cancelStandbyProbe();
      await appendBlueVpnClientLog(
        'windows standby cancel reason=$reason ok=${response.ok}',
      );
    }());
  }

  void _disarmWindowsRuntimeFailover({required String reason}) {
    final hadMonitor =
        _windowsRuntimeFailoverTimer != null ||
        _activeWindowsRuntimeRoute != null;
    _windowsRuntimeFailoverTimer?.cancel();
    _windowsRuntimeFailoverTimer = null;
    _windowsRouteMaintenanceTimer?.cancel();
    _windowsRouteMaintenanceTimer = null;
    _activeWindowsRuntimeRoute = null;
    _windowsRuntimeFailureCount = 0;
    _windowsRuntimeLastHealthyAt = null;
    _windowsFullTunnelDataPlaneConfirmed = false;
    _windowsRuntimeRecoveryProofCutoff = null;
    _windowsRuntimeFailoverEpoch += 1;
    _cancelWindowsStandbyProbe(reason: reason);
    if (hadMonitor) {
      unawaited(
        appendBlueVpnClientLog(
          'windows runtime failover disarmed reason=$reason',
        ),
      );
    }
  }

  Future<void> _armRuntimeFailover(ServerLocation server) async {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (!greenVpnShouldArmRuntimeFailover(
      previewEnabled: kTransportPreviewFallbackEnabled,
      isAndroid: isAndroid,
      isWindows: isWindows,
      serverIsAuto: server.isAuto,
      socialOnlyEnabled:
          socialOnlyEnabled || (isWindows && _socialOnlyPreferenceRequested),
    )) {
      if (isWindows) {
        _disarmWindowsRuntimeFailover(reason: 'policy_not_eligible');
      }
      return;
    }

    if (isAndroid) {
      try {
        final raw = await kAndroidPlatformChannel
            .invokeMapMethod<String, dynamic>('armRuntimeFailover', {
              'serverId': server.id,
              'protocol': server.protocolCode,
            });
        await appendBlueVpnClientLog(
          'runtime failover armed ok=${raw?['ok'] == true} server=${server.id}',
        );
      } catch (error) {
        await appendBlueVpnClientLog(
          'runtime failover arm failed server=${server.id} error=$error',
        );
      }
      return;
    }

    _disarmWindowsRuntimeFailover(reason: 'rearm');
    _activeWindowsRuntimeRoute = server;
    final epoch = _windowsRuntimeFailoverEpoch;
    _windowsRuntimeFailoverTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_pollWindowsRuntimeFailover(server, epoch)),
    );
    _windowsRouteMaintenanceTimer = Timer.periodic(const Duration(minutes: 1), (
      _,
    ) {
      if (mounted &&
          vpnEnabled &&
          !vpnBusy &&
          !_serverCatalogBusy &&
          epoch == _windowsRuntimeFailoverEpoch) {
        _refreshConnectionOptionsAfterConnect(server);
      }
    });
    unawaited(_runInitialWindowsRuntimeChecks(server, epoch));
    await appendBlueVpnClientLog(
      'windows runtime failover armed server=${server.id} protocol=${server.protocolCode} intervalSeconds=5 initialChecksSeconds=2,5 catalogRefreshSeconds=60 threshold=$greenVpnRuntimeFailoverFailureThreshold',
    );
  }

  Future<void> _runInitialWindowsRuntimeChecks(
    ServerLocation server,
    int epoch,
  ) async {
    for (final delay in const <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 3),
    ]) {
      await Future<void>.delayed(delay);
      if (!mounted ||
          !vpnEnabled ||
          vpnBusy ||
          epoch != _windowsRuntimeFailoverEpoch ||
          _windowsRuntimeRecoveryRunning) {
        return;
      }
      await _pollWindowsRuntimeFailover(server, epoch);
    }
  }

  Future<void> _restoreWindowsRuntimeFailoverIfPossible({
    required String source,
  }) async {
    if (kIsWeb ||
        !Platform.isWindows ||
        !mounted ||
        !_prefsLoaded ||
        !vpnEnabled ||
        _windowsRuntimeRestoreRunning ||
        _windowsRuntimeRecoveryRunning ||
        _windowsRuntimeFailoverTimer != null ||
        _activeWindowsRuntimeRoute != null ||
        socialOnlyEnabled ||
        _socialOnlyPreferenceRequested) {
      return;
    }

    _windowsRuntimeRestoreRunning = true;
    try {
      final routeId = greenVpnNormalizeManagedRouteId(
        await _cfg.readManagedRouteId(),
      );
      final protocol = (await _cfg.readManagedProtocol()).trim().toLowerCase();
      if (routeId.isEmpty || protocol.isEmpty) {
        await appendBlueVpnClientLog(
          'windows runtime failover restore skipped source=$source reason=missing_route_metadata',
        );
        return;
      }

      final matches = servers.where(
        (server) =>
            !server.isAuto &&
            server.id == routeId &&
            server.protocolCode.trim().toLowerCase() == protocol &&
            server.isCurrentClientReady,
      );
      if (matches.isEmpty) {
        await appendBlueVpnClientLog(
          'windows runtime failover restore deferred source=$source route=$routeId protocol=$protocol reason=catalog_route_missing',
        );
        return;
      }

      final route = matches.first;
      await _armRuntimeFailover(route);
      _trackConnectionState(true, route: route, latencyMs: route.pingMs);
      await appendBlueVpnClientLog(
        'windows runtime failover restored source=$source server=${route.id} protocol=${route.protocolCode}',
      );
    } catch (error) {
      await appendBlueVpnClientLog(
        'windows runtime failover restore failed source=$source error=$error',
      );
    } finally {
      _windowsRuntimeRestoreRunning = false;
    }
  }

  Future<void> _pollWindowsRuntimeFailover(
    ServerLocation server,
    int epoch,
  ) async {
    if (kIsWeb ||
        !Platform.isWindows ||
        !mounted ||
        epoch != _windowsRuntimeFailoverEpoch ||
        _windowsRuntimeProbeRunning ||
        _windowsRuntimeRecoveryRunning ||
        vpnBusy ||
        !vpnEnabled) {
      return;
    }
    final active = _activeWindowsRuntimeRoute;
    if (active == null ||
        _routeCooldownKey(active) != _routeCooldownKey(server)) {
      return;
    }

    _windowsRuntimeProbeRunning = true;
    var backendConnected = false;
    late PostConnectProbeResult probe;
    Object? statusError;
    try {
      final probeFuture = _probeConnectedTunnelRoute(server);
      try {
        backendConnected = await _vpnBackend.isConnected().timeout(
          const Duration(seconds: 5),
        );
      } catch (error) {
        statusError = error;
      }
      probe = await probeFuture;
    } finally {
      _windowsRuntimeProbeRunning = false;
    }

    if (!mounted ||
        epoch != _windowsRuntimeFailoverEpoch ||
        vpnBusy ||
        _windowsRuntimeRecoveryRunning) {
      return;
    }

    final routeHealthy = greenVpnRuntimeRouteHealthy(
      backendConnected: backendConnected,
      dataPlaneProbeOk: probe.ok,
    );
    final previousFailureCount = _windowsRuntimeFailureCount;
    _windowsRuntimeFailureCount = greenVpnNextRuntimeFailoverFailureCount(
      currentFailureCount: _windowsRuntimeFailureCount,
      routeHealthy: routeHealthy,
    );
    if (routeHealthy) {
      _windowsRuntimeLastHealthyAt = DateTime.now().toUtc();
      final confirmationChanged = !_windowsFullTunnelDataPlaneConfirmed;
      _windowsFullTunnelDataPlaneConfirmed = true;
      if (confirmationChanged) {
        await _syncVpnStatus(source: 'windows_data_plane_healthy');
        if (!mounted || epoch != _windowsRuntimeFailoverEpoch) return;
        if (!_windowsProtectionConfirmed) {
          _windowsFullTunnelDataPlaneConfirmed = false;
          await appendBlueVpnClientLog(
            'windows data-plane proof rejected by authoritative system status server=${server.id}',
          );
          return;
        }
      }
      await _recordRouteSuccess(server);
      unawaited(_runWindowsStandbyCycle(server, epoch));
      if (previousFailureCount > 0) {
        await appendBlueVpnClientLog(
          'windows runtime probe recovered server=${server.id} previousFailures=$previousFailureCount',
        );
      }
      return;
    }

    if (_windowsFullTunnelDataPlaneConfirmed) {
      _windowsFullTunnelDataPlaneConfirmed = false;
      await _syncVpnStatus(source: 'windows_data_plane_unhealthy');
      if (!mounted || epoch != _windowsRuntimeFailoverEpoch) return;
    }
    if (previousFailureCount == 0) {
      _cancelWindowsStandbyProbe(reason: 'runtime_probe_unhealthy');
    }

    final errorCode = probe.statusCode == null
        ? 'runtime_youtube_probe_failed'
        : 'runtime_youtube_http_${probe.statusCode}';
    await appendBlueVpnClientLog(
      'windows runtime probe failed server=${server.id} protocol=${server.protocolCode} failures=$_windowsRuntimeFailureCount connected=$backendConnected status=${probe.statusCode} statusError=${statusError ?? ""} probeError=${probe.error ?? ""}',
    );
    unawaited(
      _reportRouteEvent(
        server,
        stage: 'post_connect_probe',
        ok: false,
        latencyMs: probe.latencyMs,
        errorCode: errorCode,
        message: 'Активный Windows-маршрут перестал подтверждать работу.',
        details: {
          'failureCount': _windowsRuntimeFailureCount,
          'backendConnected': backendConnected,
          'target': probe.target,
          'statusCode': probe.statusCode,
          'statusError': statusError?.toString(),
          'probeError': probe.error,
        },
      ),
    );
    if (!greenVpnShouldTriggerRuntimeFailover(_windowsRuntimeFailureCount)) {
      return;
    }

    await _loadWindowsStandbyProofs();
    final recoveryProofCutoff = _windowsRuntimeLastHealthyAt;
    _recordRouteFailure(server, 'runtime_probe');
    _windowsRuntimeRecoveryRunning = true;
    _disarmWindowsRuntimeFailover(reason: 'failure_threshold');
    _windowsRuntimeRecoveryProofCutoff = recoveryProofCutoff;
    var handedOffToConnect = false;
    try {
      _setVpnBusyUi(
        stage: 'Восстанавливаем VPN...',
        hint:
            '${greenVpnPublicServerTitle(server)} перестал отвечать. Полностью останавливаем маршрут перед безопасным переходом.',
      );
      final stopped = await _stopFailedRouteBeforeFallback(
        server,
        stage: 'runtime_probe_failed',
      );
      if (!mounted) return;
      if (!stopped) {
        _toast(
          context,
          'Не удалось подтвердить полную остановку предыдущего маршрута. '
          'Автовосстановление остановлено без запуска другого туннеля.',
        );
        return;
      }

      _vpnTapCooldownTimer?.cancel();
      setState(() {
        vpnEnabled = false;
        _vpnTapCooldown = false;
        _vpnBusyHint = null;
      });
      _clearVpnBusyUi();
      await appendBlueVpnClientLog(
        'windows runtime failover clean-down confirmed server=${server.id}; starting ordered reconnect',
      );
      handedOffToConnect = true;
      await _toggleVpnReal();
    } catch (error, stack) {
      await appendBlueVpnClientLog(
        'windows runtime failover exception server=${server.id} error=$error stack=$stack',
      );
      if (mounted) {
        _toast(
          context,
          'Автовосстановление не завершилось. VPN оставлен выключенным.',
        );
      }
    } finally {
      _windowsRuntimeRecoveryRunning = false;
      _windowsRuntimeRecoveryProofCutoff = null;
      if (!handedOffToConnect) {
        _clearVpnBusyUi();
      }
    }
  }

  int _compareServerConnectionCandidates(ServerLocation a, ServerLocation b) {
    if (a.isCurrentClientReady != b.isCurrentClientReady) {
      return a.isCurrentClientReady ? -1 : 1;
    }
    if (kTransportPreviewFallbackEnabled) {
      final now = DateTime.now();
      return greenVpnCompareTransportPreviewCandidates(
        leftProtocol: a.protocolCode,
        rightProtocol: b.protocolCode,
        leftCooldownUntil: _routeFailureCooldown.coolingUntil(
          _routeCooldownKey(a),
          now: now,
        ),
        rightCooldownUntil: _routeFailureCooldown.coolingUntil(
          _routeCooldownKey(b),
          now: now,
        ),
        leftScore: _serverConnectScore(a),
        rightScore: _serverConnectScore(b),
        leftPingMs: a.pingMs,
        rightPingMs: b.pingMs,
        leftTitle: a.title,
        rightTitle: b.title,
        leftWasRecentlySuccessful:
            !kIsWeb &&
            (Platform.isWindows || Platform.isAndroid) &&
            greenVpnIsFreshPreferredRoute(
              candidateId: a.id,
              candidateProtocol: a.protocolCode,
              preferredId: _lastSuccessfulRouteId,
              preferredProtocol: _lastSuccessfulRouteProtocol,
              preferredAt: _lastSuccessfulRouteAt,
              now: now,
            ),
        rightWasRecentlySuccessful:
            !kIsWeb &&
            (Platform.isWindows || Platform.isAndroid) &&
            greenVpnIsFreshPreferredRoute(
              candidateId: b.id,
              candidateProtocol: b.protocolCode,
              preferredId: _lastSuccessfulRouteId,
              preferredProtocol: _lastSuccessfulRouteProtocol,
              preferredAt: _lastSuccessfulRouteAt,
              now: now,
            ),
        leftHasFreshStandbyProof:
            !kIsWeb &&
            Platform.isWindows &&
            _windowsRuntimeRecoveryRunning &&
            _hasFreshWindowsStandbyProof(a, now: now),
        rightHasFreshStandbyProof:
            !kIsWeb &&
            Platform.isWindows &&
            _windowsRuntimeRecoveryRunning &&
            _hasFreshWindowsStandbyProof(b, now: now),
      );
    }
    final byScore = _serverConnectScore(b).compareTo(_serverConnectScore(a));
    if (byScore != 0) return byScore;
    final ap = a.pingMs ?? 999999;
    final bp = b.pingMs ?? 999999;
    final byPing = ap.compareTo(bp);
    if (byPing != 0) return byPing;
    return a.title.compareTo(b.title);
  }

  List<ServerLocation> _serverPickerLocations() {
    final auto = servers.where((server) => server.isAuto).firstOrNull;
    final routes = servers.where((server) => !server.isAuto).toList()
      ..sort((left, right) {
        if (!_hasPaidSubscriptionEntitlement &&
            left.requiresPaidSubscription != right.requiresPaidSubscription) {
          return left.requiresPaidSubscription ? 1 : -1;
        }
        return _compareServerConnectionCandidates(left, right);
      });
    return greenVpnVisibleLocationRepresentatives<ServerLocation>(
      candidates: <ServerLocation>[
        auto ??
            const ServerLocation(
              id: 'auto',
              title: 'Авто',
              subtitle: 'Автовыбор',
              isAuto: true,
              status: 'healthy',
              available: true,
              clientConfigReady: true,
            ),
        ...routes,
      ],
      isAutomatic: (server) => server.isAuto,
      isReady: (server) => server.isCurrentClientReady,
      locationIdOf: (server) => server.publicLocationId,
    );
  }

  List<ServerLocation> _connectCandidatesForCurrentSelection() {
    final windowsRecoveryRequiresProof =
        !kIsWeb && Platform.isWindows && _windowsRuntimeRecoveryRunning;
    var usable =
        servers
            .where(
              (server) =>
                  !server.isAuto &&
                  server.isCurrentClientReady &&
                  (_hasPaidSubscriptionEntitlement ||
                      !server.requiresPaidSubscription) &&
                  !(socialOnlyEnabled &&
                      greenVpnTransportRequiresFullTunnel(server.protocolCode)),
            )
            .toList()
          ..sort(_compareServerConnectionCandidates);

    if (!kIsWeb && Platform.isWindows && _windowsProcessRouterRequired) {
      return greenVpnWindowsApplicationProxyRoutes<ServerLocation>(
        candidates: usable,
        serverIdOf: (server) => server.id,
        protocolOf: (server) => server.protocolCode,
      );
    }

    if (windowsRecoveryRequiresProof) {
      final now = DateTime.now().toUtc();
      final proofCutoff = _windowsRuntimeRecoveryProofCutoff;
      usable = greenVpnWindowsRecoveryCandidates<ServerLocation>(
        candidates: usable,
        recoveryRunning: true,
        hasFreshStandbyProof: (candidate) =>
            proofCutoff != null &&
            _hasFreshWindowsStandbyProof(
              candidate,
              now: now,
              verifiedNotAfter: proofCutoff,
            ),
      );
    }

    if (selectedServer.isAuto) {
      if (usable.isNotEmpty) return usable;
      return windowsRecoveryRequiresProof
          ? const <ServerLocation>[]
          : <ServerLocation>[_backendAutoCandidate()];
    }

    final selectedLocationCandidates = greenVpnInternalCandidatesForLocation(
      candidates: usable,
      automatic: false,
      selectedLocationId: selectedServer.publicLocationId,
      selectedRouteId: selectedServer.id,
      locationIdOf: (server) => server.publicLocationId,
      routeIdOf: (server) => server.id,
    );
    if (selectedLocationCandidates.isNotEmpty) {
      return selectedLocationCandidates;
    }
    if (windowsRecoveryRequiresProof) return const <ServerLocation>[];
    return selectedServer.isCurrentClientReady &&
            (_hasPaidSubscriptionEntitlement ||
                !selectedServer.requiresPaidSubscription)
        ? <ServerLocation>[selectedServer]
        : const <ServerLocation>[];
  }

  Future<ServerLocation?> _immediateCachedForegroundCandidate(
    List<ServerLocation> candidates,
  ) async {
    final isWindows = !kIsWeb && Platform.isWindows;
    final isAndroid = !kIsWeb && Platform.isAndroid;
    if ((!isWindows && !isAndroid) ||
        (isWindows && (socialOnlyEnabled || _socialOnlyPreferenceRequested)) ||
        candidates.isEmpty) {
      return null;
    }
    final now = DateTime.now().toUtc();
    final preferredCandidate = candidates
        .where(
          (candidate) => greenVpnIsFreshPreferredRoute(
            candidateId: candidate.id,
            candidateProtocol: candidate.protocolCode,
            preferredId: _lastSuccessfulRouteId,
            preferredProtocol: _lastSuccessfulRouteProtocol,
            preferredAt: _lastSuccessfulRouteAt,
            now: now,
          ),
        )
        .firstOrNull;
    if (preferredCandidate == null) {
      await appendBlueVpnClientLog(
        'immediate cached connect unavailable reason=no_fresh_preferred_route preferredRoute=$_lastSuccessfulRouteId preferredProtocol=$_lastSuccessfulRouteProtocol',
      );
      return null;
    }
    final managedMetadata = await Future.wait<String>([
      _cfg.readManagedRouteId(),
      _cfg.readManagedProtocol(),
    ]);
    final managedRouteId = managedMetadata[0];
    final managedProtocol = managedMetadata[1];
    final hasManagedConfig = await _cfg.hasManagedConfig();
    final serverBase = await _cfg.readBaseConfigForServer(
      preferredCandidate.id,
    );
    final hasCandidateCache =
        hasManagedConfig || (serverBase ?? '').trim().isNotEmpty;
    if (greenVpnCanUseImmediateCachedRoute(
      isWindows: isWindows,
      isAndroid: isAndroid,
      socialOnlyEnabled: socialOnlyEnabled,
      hasManagedConfig: hasCandidateCache,
      candidateId: preferredCandidate.id,
      candidateProtocol: preferredCandidate.protocolCode,
      managedRouteId: managedRouteId,
      managedProtocol: managedProtocol,
      preferredId: _lastSuccessfulRouteId,
      preferredProtocol: _lastSuccessfulRouteProtocol,
      preferredAt: _lastSuccessfulRouteAt,
      now: now,
    )) {
      try {
        String? cachedConfig;
        if (isAndroid) {
          if (serverBase == null ||
              serverBase.trim().isEmpty ||
              !_configMatchesServer(preferredCandidate, serverBase)) {
            await appendBlueVpnClientLog(
              'immediate cached connect rejected server=${preferredCandidate.id} reason=route_config_mismatch',
            );
            return null;
          }
          await _writeProvisionedConfig(serverBase, server: preferredCandidate);
          cachedConfig = await _cfg.readManagedConfig();
          await appendBlueVpnClientLog(
            'immediate cached connect rebuilt Android mode from exact server cache server=${preferredCandidate.id} socialOnly=$socialOnlyEnabled',
          );
        } else {
          cachedConfig = hasManagedConfig
              ? await _cfg.readManagedConfig()
              : null;
          final managedMatchesCandidate =
              cachedConfig != null &&
              cachedConfig.trim().isNotEmpty &&
              _configMatchesServer(preferredCandidate, cachedConfig);
          if (!managedMatchesCandidate) {
            if (serverBase == null ||
                serverBase.trim().isEmpty ||
                !_configMatchesServer(preferredCandidate, serverBase)) {
              await appendBlueVpnClientLog(
                'immediate cached connect rejected server=${preferredCandidate.id} reason=route_config_mismatch',
              );
              return null;
            }
            await _writeProvisionedConfig(
              serverBase,
              server: preferredCandidate,
            );
            cachedConfig = await _cfg.readManagedConfig();
            await appendBlueVpnClientLog(
              'immediate cached connect restored exact server cache server=${preferredCandidate.id}',
            );
          }
        }
        if (cachedConfig == null || cachedConfig.trim().isEmpty) {
          return null;
        }
        final preparedConfig = await _prepareProvisionedConfigForPlatform(
          cachedConfig,
          server: preferredCandidate,
        );
        if (preparedConfig != cachedConfig) {
          await _writeProvisionedConfig(
            preparedConfig,
            server: preferredCandidate,
          );
          await appendBlueVpnClientLog(
            'immediate cached connect normalized endpoint server=${preferredCandidate.id}',
          );
        }
      } catch (error) {
        await appendBlueVpnClientLog(
          'immediate cached connect rejected server=${preferredCandidate.id} error=$error',
        );
        return null;
      }
      await appendBlueVpnClientLog(
        'immediate cached connect ready server=${preferredCandidate.id} protocol=${preferredCandidate.protocolCode}',
      );
      return preferredCandidate;
    }
    await appendBlueVpnClientLog(
      'immediate cached connect unavailable managedRoute=$managedRouteId managedProtocol=$managedProtocol preferredRoute=$_lastSuccessfulRouteId preferredProtocol=$_lastSuccessfulRouteProtocol',
    );
    return null;
  }

  void _refreshConnectionOptionsAfterConnect(ServerLocation activeRoute) {
    if (kIsWeb || !Platform.isWindows) return;
    unawaited(_refreshConnectionOptionsAfterConnectAsync(activeRoute));
  }

  Future<void> _refreshConnectionOptionsAfterConnectAsync(
    ServerLocation activeRoute,
  ) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted || !vpnEnabled) return;
    try {
      await appendBlueVpnClientLog(
        'background route refresh start active=${activeRoute.id}',
      );
      await _refreshServerCatalog(showToast: false);
      if (!mounted || !vpnEnabled) return;
      unawaited(
        _runWindowsStandbyCycle(activeRoute, _windowsRuntimeFailoverEpoch),
      );
      await appendBlueVpnClientLog(
        'background route refresh complete active=${activeRoute.id} candidates=${_connectCandidatesForCurrentSelection().length}',
      );
    } catch (error) {
      await appendBlueVpnClientLog(
        'background route refresh failed active=${activeRoute.id} error=$error',
      );
    }
  }

  String _serverUnsupportedReason(ServerLocation server) {
    if (server.requiresPaidSubscription && !_hasPaidSubscriptionEntitlement) {
      return 'эта локация доступна по подписке';
    }
    if (!server.available) return 'локация сейчас недоступна';
    if (!server.clientConfigReady) {
      return 'подключение к этой локации ещё не готово';
    }
    if (!kSupportedVpnProtocols.contains(server.protocolCode)) {
      return 'этот способ подключения пока недоступен в текущей версии';
    }
    if (socialOnlyEnabled &&
        greenVpnTransportRequiresFullTunnel(server.protocolCode)) {
      return 'этот резервный режим доступен только для полного подключения';
    }
    return 'локацию пока нельзя использовать в текущей версии';
  }

  Future<void> _reportRouteEvent(
    ServerLocation server, {
    required String stage,
    required bool ok,
    int? latencyMs,
    String? errorCode,
    String? message,
    Map<String, dynamic>? details,
  }) async {
    if (widget.session.accessToken == 'dev-token') return;
    try {
      final did = await _ensureDeviceId();
      if (did == null || did.isEmpty) return;
      final res = await _api.postClientRouteEvent(
        accessToken: widget.session.accessToken,
        deviceId: did,
        serverId: server.isAuto ? 'auto' : server.id,
        protocol: server.protocolCode,
        transport: server.protocolCode == 'wireguard_udp' ? 'udp' : 'auto',
        stage: stage,
        ok: ok,
        latencyMs: latencyMs,
        errorCode: errorCode,
        message: message,
        details: details,
      );
      if (!res.ok) {
        if (greenVpnIsInvalidSessionMessage(res.message)) {
          await _noteInvalidSession(
            source: 'route_event',
            message: res.message,
          );
          return;
        }
        await appendBlueVpnClientLog(
          'route event failed stage=$stage server=${server.id} message=${res.message ?? ""}',
        );
      }
    } catch (e) {
      await appendBlueVpnClientLog(
        'route event exception stage=$stage server=${server.id} error=$e',
      );
    }
  }

  Future<bool> _stopFailedRouteBeforeFallback(
    ServerLocation server, {
    required String stage,
  }) async {
    final watch = Stopwatch()..start();
    VpnBackendResult? disconnectResult;
    Object? disconnectError;
    try {
      disconnectResult = await _vpnBackend.disconnect().timeout(
        !kIsWeb && Platform.isAndroid
            ? const Duration(seconds: 8)
            : const Duration(seconds: 130),
      );
    } catch (e) {
      disconnectError = e;
    }

    var stillConnected = true;
    Object? statusError;
    try {
      final statusTimeout = !kIsWeb && Platform.isAndroid
          ? const Duration(seconds: 2)
          : const Duration(seconds: 5);
      final statusAttempts = !kIsWeb && Platform.isAndroid ? 2 : 4;
      stillConnected = await _vpnBackend.isConnected().timeout(statusTimeout);
      for (
        var attempt = 0;
        stillConnected && attempt < statusAttempts;
        attempt += 1
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        stillConnected = await _vpnBackend.isConnected().timeout(statusTimeout);
      }
    } catch (e) {
      statusError = e;
      stillConnected = true;
    }
    watch.stop();

    final stopped = disconnectResult?.ok == true && !stillConnected;
    await appendBlueVpnClientLog(
      'fallback cleanup stage=$stage server=${server.id} '
      'disconnectOk=${disconnectResult?.ok ?? false} stopped=$stopped '
      'disconnectMessage=${disconnectResult?.message ?? ""} '
      'disconnectError=${disconnectError ?? ""} statusError=${statusError ?? ""}',
    );
    unawaited(
      _reportRouteEvent(
        server,
        stage: '${stage}_disconnect',
        ok: stopped,
        latencyMs: watch.elapsedMilliseconds,
        errorCode: stopped ? null : 'previous_route_still_active',
        message: stopped
            ? 'Предыдущий маршрут полностью остановлен перед fallback.'
            : 'Не удалось подтвердить остановку предыдущего маршрута.',
        details: {
          'disconnectCallOk': disconnectResult?.ok ?? false,
          'disconnectError': disconnectError?.toString(),
          'statusError': statusError?.toString(),
        },
      ),
    );
    await _syncVpnStatus();
    return stopped;
  }

  bool get _shouldRunPostConnectProbe =>
      !kIsWeb && greenVpnHasNativeVpnBackend && !socialOnlyEnabled;

  Future<PostConnectProbeResult> _probeConnectedTunnelRoute(
    ServerLocation server,
  ) async {
    if (Platform.isAndroid) {
      var attempt = 1;
      while (true) {
        await Future<void>.delayed(greenVpnStartupRouteProbeDelay(attempt));
        PostConnectProbeResult result;
        try {
          final raw = await kAndroidPlatformChannel
              .invokeMethod<Object?>('probeConnectedRoute', {
                'protocol': server.protocolCode,
              })
              .timeout(const Duration(seconds: 22));
          final response = raw is Map
              ? raw.map((key, value) => MapEntry('$key', value))
              : const <String, dynamic>{};
          result = PostConnectProbeResult(
            ok: response['ok'] == true,
            target: (response['target'] ?? '').toString(),
            statusCode: (response['statusCode'] as num?)?.toInt(),
            latencyMs: (response['latencyMs'] as num?)?.toInt() ?? 0,
            error: (response['error'] ?? '').toString(),
          );
        } catch (e) {
          result = PostConnectProbeResult(
            ok: false,
            target: 'android_native_route_probe',
            latencyMs: 0,
            error: e.toString(),
          );
        }
        await appendBlueVpnClientLog(
          'post connect Android probe server=${server.id} protocol=${server.protocolCode} attempt=$attempt target=${result.target} status=${result.statusCode} ok=${result.ok} ms=${result.latencyMs} error=${result.error ?? ''}',
        );
        if (result.ok ||
            !greenVpnShouldRetryStartupRouteProbe(
              attempt: attempt,
              latencyMs: result.latencyMs,
            )) {
          return result;
        }
        attempt += 1;
      }
    }

    final targets = <Uri>[
      Uri.parse('https://www.youtube.com/generate_204'),
      Uri.parse('https://i.ytimg.com/generate_204'),
    ];
    Future<PostConnectProbeResult> probeTarget(Uri uri) async {
      final watch = Stopwatch()..start();
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 7));
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'GreenVPN/$kAppVersion route-check',
        );
        final response = await request.close().timeout(
          const Duration(seconds: 8),
        );
        await response.drain<void>().timeout(const Duration(seconds: 2));
        watch.stop();
        final latencyMs = watch.elapsedMilliseconds;
        final ok = response.statusCode >= 200 && response.statusCode < 400;
        await appendBlueVpnClientLog(
          'post connect probe server=${server.id} target=$uri status=${response.statusCode} ok=$ok ms=$latencyMs',
        );
        return PostConnectProbeResult(
          ok: ok,
          target: uri.toString(),
          statusCode: response.statusCode,
          latencyMs: latencyMs,
          error: ok ? null : 'http_${response.statusCode}',
        );
      } catch (e) {
        watch.stop();
        final latencyMs = watch.elapsedMilliseconds;
        await appendBlueVpnClientLog(
          'post connect probe failed server=${server.id} target=$uri error=$e ms=$latencyMs',
        );
        return PostConnectProbeResult(
          ok: false,
          target: uri.toString(),
          latencyMs: latencyMs,
          error: e.toString(),
        );
      } finally {
        client.close(force: true);
      }
    }

    final completer = Completer<PostConnectProbeResult>();
    var remaining = targets.length;
    PostConnectProbeResult? lastFailure;
    for (final target in targets) {
      probeTarget(target).then((result) {
        if (completer.isCompleted) return;
        if (result.ok) {
          completer.complete(result);
          return;
        }
        lastFailure = result;
        remaining -= 1;
        if (remaining == 0) {
          completer.complete(lastFailure!);
        }
      });
    }
    return completer.future;
  }

  Future<void> _verifyAndroidConnectedRouteInBackground(
    ServerLocation server,
  ) async {
    final probe = await _probeConnectedTunnelRoute(server);
    if (!mounted) return;
    final activeRoute = _activeConnectionRoute;
    final stillCurrent =
        vpnEnabled &&
        activeRoute != null &&
        activeRoute.id == server.id &&
        activeRoute.protocolCode == server.protocolCode;
    if (!stillCurrent) {
      await appendBlueVpnClientLog(
        'background Android post connect probe ignored stale server=${server.id}',
      );
      return;
    }
    unawaited(
      _reportRouteEvent(
        server,
        stage: 'post_connect_probe',
        ok: probe.ok,
        latencyMs: probe.latencyMs,
        errorCode: probe.ok
            ? null
            : (probe.statusCode == null
                  ? 'youtube_probe_failed'
                  : 'youtube_http_${probe.statusCode}'),
        message: probe.ok
            ? 'YouTube route confirmed after Android VPN connect.'
            : 'Android VPN поднялся, проверка Интернета продолжится надзором.',
        details: {
          'background': true,
          'target': probe.target,
          'statusCode': probe.statusCode,
          'error': probe.error,
        },
      ),
    );
    if (probe.ok) {
      await _recordRouteSuccess(server);
      await appendBlueVpnClientLog(
        'background Android post connect probe accepted server=${server.id}',
      );
    } else {
      _recordRouteFailure(server, 'post_connect_probe');
      await appendBlueVpnClientLog(
        'background Android post connect probe failed server=${server.id}; runtime supervision remains authoritative',
      );
    }
  }

  Future<void> _toggleVpnReal() async {
    final toggleWatch = Stopwatch()..start();
    await appendBlueVpnClientLog(
      'toggle requested vpnEnabled=$vpnEnabled busy=$vpnBusy cooldown=$_vpnTapCooldown',
    );
    if (!mounted) return;
    if (vpnBusy) {
      _toast(
        context,
        vpnEnabled
            ? 'Green VPN уже отключается. Подожди пару секунд.'
            : 'Green VPN уже запускает подключение. Подожди пару секунд.',
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
          ? 'Останавливаем VPN и очищаем маршруты.'
          : 'Проверяем доступ и готовим рабочий конфиг. Повторно нажимать не нужно.',
    );

    if (kIsWeb) {
      _toast(
        context,
        'Web-режим: реальный VPN недоступен. Установи приложение на Windows или Android.',
      );
      _clearVpnBusyUi();
      return;
    }
    if (!greenVpnHasNativeVpnBackend) {
      _toast(
        context,
        'На этой платформе реальный VPN пока не включён. Следующий шаг для iOS — Apple Developer и Network Extension.',
      );
      _clearVpnBusyUi();
      return;
    }

    _setVpnBusyUi(
      stage: Platform.isAndroid
          ? 'Проверяем разрешение Android...'
          : 'Проверяем системный компонент...',
      hint: Platform.isAndroid
          ? 'Android может один раз показать системное окно с разрешением VPN.'
          : 'Green VPN использует права, выданные один раз при установке. Дополнительный UAC при запуске не нужен.',
    );
    await appendBlueVpnClientLog(
      'toggle native preflight platform=${Platform.operatingSystem} vpnEnabled=$vpnEnabled',
    );
    if (!mounted) return;

    try {
      if (!vpnEnabled) {
        await appendBlueVpnClientLog('toggle connect branch start');
        await _prepareAndroidConnectControlPlane('toggle_connect');
        if (!mounted) return;
        var candidates = _connectCandidatesForCurrentSelection();
        if (candidates.isEmpty) {
          await _refreshServerCatalog(showToast: false);
          if (!mounted) return;
          candidates = _connectCandidatesForCurrentSelection();
        }
        if (candidates.isEmpty) {
          final reason = _serverUnsupportedReason(selectedServer);
          _toast(context, 'Эту локацию пока нельзя подключить: $reason.');
          return;
        }
        final immediateCachedCandidate =
            await _immediateCachedForegroundCandidate(candidates);
        if (!mounted) return;
        if (!kIsWeb && Platform.isWindows) {
          if (!_windowsRuntimeRecoveryRunning) {
            final immediateCachedIndex = immediateCachedCandidate == null
                ? null
                : candidates.indexWhere(
                    (candidate) =>
                        candidate.id == immediateCachedCandidate.id &&
                        candidate.protocolCode ==
                            immediateCachedCandidate.protocolCode,
                  );
            final primaryIndex = greenVpnWindowsForegroundCandidateIndex(
              protocols: candidates
                  .map((candidate) => candidate.protocolCode)
                  .toList(growable: false),
              immediateCachedIndex:
                  immediateCachedIndex != null && immediateCachedIndex >= 0
                  ? immediateCachedIndex
                  : null,
            );
            if (primaryIndex >= 0) {
              final primary = candidates[primaryIndex];
              candidates = <ServerLocation>[primary];
              await appendBlueVpnClientLog(
                'windows foreground connect selected single primary server=${primary.id} protocol=${primary.protocolCode} cached=${immediateCachedCandidate != null && primary.id == immediateCachedCandidate.id && primary.protocolCode == immediateCachedCandidate.protocolCode}',
              );
            }
          } else {
            await appendBlueVpnClientLog(
              'windows background recovery retained ordered candidates=${candidates.length}',
            );
          }
        } else if (!kIsWeb && Platform.isAndroid) {
          if (immediateCachedCandidate != null &&
              (candidates.first.id != immediateCachedCandidate.id ||
                  candidates.first.protocolCode !=
                      immediateCachedCandidate.protocolCode)) {
            candidates = <ServerLocation>[
              immediateCachedCandidate,
              ...candidates.where(
                (candidate) =>
                    candidate.id != immediateCachedCandidate.id ||
                    candidate.protocolCode !=
                        immediateCachedCandidate.protocolCode,
              ),
            ];
          }
          candidates = greenVpnAndroidForegroundCandidates(candidates);
          await appendBlueVpnClientLog(
            'android foreground connect bounded candidates=${candidates.length} cached=${immediateCachedCandidate != null}',
          );
        }

        String? lastError;
        for (var i = 0; i < candidates.length; i++) {
          var candidate = candidates[i];
          final canTryNext = i < candidates.length - 1;
          final useImmediateCachedConfig =
              i == 0 &&
              immediateCachedCandidate != null &&
              candidate.id == immediateCachedCandidate.id &&
              candidate.protocolCode == immediateCachedCandidate.protocolCode;
          await appendBlueVpnClientLog(
            'toggle connect candidate ${i + 1}/${candidates.length} id=${candidate.id} protocol=${candidate.protocolCode} score=${_serverConnectScore(candidate)}',
          );

          final configFetchWatch = Stopwatch()..start();
          final ProvisionedConfigResult provisioned;
          if (useImmediateCachedConfig) {
            _setVpnBusyUi(
              stage: 'Запускаем VPN...',
              hint:
                  'Сразу используем последний проверенный маршрут ${greenVpnPublicServerTitle(candidate)}.',
            );
            await appendBlueVpnClientLog(
              'toggle connect using immediate cached config server=${candidate.id}',
            );
            provisioned = ProvisionedConfigResult.ok(candidate);
          } else {
            _setVpnBusyUi(
              stage: 'Получаем конфиг...',
              hint:
                  'Пробуем ${greenVpnPublicServerTitle(candidate)}: готовим подключение именно для этого устройства.',
            );
            provisioned = await _ensureProvisionedConfigInteractive(
              serverOverride: candidate,
              boundedAndroidNetwork: !kIsWeb && Platform.isAndroid,
            );
          }
          configFetchWatch.stop();
          final ok = provisioned.ok;
          if (ok &&
              provisioned.server != null &&
              provisioned.server!.id != candidate.id) {
            await appendBlueVpnClientLog(
              'toggle connect backend reassigned server ${candidate.id} -> ${provisioned.server!.id}',
            );
            candidate = provisioned.server!;
          }
          await appendBlueVpnClientLog(
            'toggle connect ensureConfig server=${candidate.id} ok=$ok',
          );
          if (!mounted) return;
          unawaited(
            _reportRouteEvent(
              candidate,
              stage: 'config_fetch',
              ok: ok,
              latencyMs: configFetchWatch.elapsedMilliseconds,
              errorCode: ok ? null : 'config_fetch_failed',
              message: ok ? null : 'Не удалось получить конфиг для VPN-узла.',
              details: {
                'attempt': i + 1,
                'candidates': candidates.length,
                'autoMode': selectedServer.isAuto,
                'source': useImmediateCachedConfig
                    ? 'immediate_cache'
                    : 'provisioned',
              },
            ),
          );
          if (!ok) {
            _recordRouteFailure(candidate, 'config_fetch');
            lastError =
                'не удалось получить конфиг для ${greenVpnPublicServerTitle(candidate)}';
            if (canTryNext) continue;
            _toast(context, 'Не удалось получить VPN-конфиг.');
            return;
          }

          _setVpnBusyUi(
            stage: socialOnlyEnabled
                ? 'Подключаем режим соцсетей...'
                : 'Запускаем VPN...',
            hint: socialOnlyEnabled
                ? 'Подключаем VPN только для выбранных приложений.'
                : 'Запускаем VPN и проверяем подключение.',
          );
          final configPath = _cfg.managedConfigPath;
          await _syncWindowsRoutingPolicy();
          await appendBlueVpnClientLog(
            'toggle connect backend start server=${candidate.id} cfg=$configPath',
          );
          final connectWatch = Stopwatch()..start();
          final res = await _vpnBackend.connect(configPath: configPath);
          connectWatch.stop();
          await appendBlueVpnClientLog(
            'toggle connect backend server=${candidate.id} ok=${res.ok} message=${res.message ?? ""}',
          );
          if (!mounted) return;
          final competingVpnActive = greenVpnIsCompetingVpnFailureMessage(
            res.message,
          );
          unawaited(
            _reportRouteEvent(
              candidate,
              stage: 'connect',
              ok: res.ok,
              latencyMs: connectWatch.elapsedMilliseconds,
              errorCode: res.ok
                  ? null
                  : (competingVpnActive
                        ? 'competing_vpn_active'
                        : 'connect_failed'),
              message: res.message,
              details: {
                'attempt': i + 1,
                'candidates': candidates.length,
                'autoMode': selectedServer.isAuto,
              },
            ),
          );
          if (!res.ok) {
            if (!competingVpnActive) {
              _recordRouteFailure(candidate, 'connect');
            }
            lastError =
                res.message ??
                'не удалось подключить ${greenVpnPublicServerTitle(candidate)}';
            final stopped = await _stopFailedRouteBeforeFallback(
              candidate,
              stage: 'connect_failed',
            );
            if (!mounted) return;
            if (!stopped) {
              _toast(
                context,
                'Не удалось полностью остановить предыдущий маршрут. '
                'Автопереключение остановлено.',
              );
              return;
            }
            if (competingVpnActive) {
              _toast(
                context,
                res.message ??
                    'Другой VPN уже активен. Отключи его и попробуй снова.',
              );
              return;
            }
            if (canTryNext) {
              _setVpnBusyUi(
                stage: 'Пробуем запасной узел...',
                hint:
                    '${greenVpnPublicServerTitle(candidate)} не отвечает. Green VPN автоматически пробует следующий доступный вариант.',
              );
              continue;
            }
            _toast(context, res.message ?? 'Не удалось подключить VPN.');
            return;
          }

          if (!kIsWeb && Platform.isWindows) {
            setState(() {
              _windowsProtectionConfirmed = false;
              _windowsFullTunnelDataPlaneConfirmed = false;
              _externalVpnActive = false;
            });
            await _syncVpnStatus(source: 'toggle_connect');
          } else {
            _setVpnBusyUi(
              stage: 'Проверяем статус...',
              hint: 'Проверяем подключение и состояние VPN.',
            );
            await _syncVpnStatus();
          }
          await appendBlueVpnClientLog(
            'toggle connect sync done server=${candidate.id} vpnEnabled=$vpnEnabled',
          );
          if (!mounted) return;
          unawaited(
            _reportRouteEvent(
              candidate,
              stage: vpnEnabled ? 'connected' : 'handshake',
              ok: vpnEnabled,
              errorCode: vpnEnabled ? null : 'handshake_not_confirmed',
              message: vpnEnabled
                  ? 'VPN подключён и подтверждён клиентом.'
                  : 'Туннель не закрепился после запуска.',
              details: {
                'attempt': i + 1,
                'candidates': candidates.length,
                'autoMode': selectedServer.isAuto,
              },
            ),
          );
          if (!vpnEnabled) {
            _recordRouteFailure(candidate, 'handshake');
            lastError =
                'VPN не подтвердился после запуска ${greenVpnPublicServerTitle(candidate)}';
            final stopped = await _stopFailedRouteBeforeFallback(
              candidate,
              stage: 'handshake_failed',
            );
            if (!mounted) return;
            if (!stopped) {
              _toast(
                context,
                'Не удалось полностью остановить неподтверждённый маршрут. '
                'Автопереключение остановлено.',
              );
              return;
            }
            if (canTryNext) continue;
            _toast(context, 'VPN запустился, но статус не подтвердился.');
            return;
          }
          unawaited(
            appendBlueVpnClientLog(
              'toggle tunnel confirmed server=${candidate.id} clickToTunnelMs=${toggleWatch.elapsedMilliseconds}',
            ),
          );
          var connectionLatencyMs = candidate.pingMs;

          if (greenVpnShouldBlockForegroundForPostConnectProbe(
            probeRequested: _shouldRunPostConnectProbe,
            isWindows: !kIsWeb && Platform.isWindows,
            isAndroid: !kIsWeb && Platform.isAndroid,
          )) {
            _setVpnBusyUi(
              stage: 'Проверяем YouTube...',
              hint: 'VPN включён. Проверяем, что YouTube открывается.',
            );
            final probe = await _probeConnectedTunnelRoute(candidate);
            connectionLatencyMs = probe.latencyMs;
            if (!mounted) return;
            unawaited(
              _reportRouteEvent(
                candidate,
                stage: 'post_connect_probe',
                ok: probe.ok,
                latencyMs: probe.latencyMs,
                errorCode: probe.ok
                    ? null
                    : (probe.statusCode == null
                          ? 'youtube_probe_failed'
                          : 'youtube_http_${probe.statusCode}'),
                message: probe.ok
                    ? 'YouTube route confirmed after VPN connect.'
                    : 'VPN поднялся, но YouTube не открылся через этот узел.',
                details: {
                  'attempt': i + 1,
                  'candidates': candidates.length,
                  'autoMode': selectedServer.isAuto,
                  'target': probe.target,
                  'statusCode': probe.statusCode,
                  'error': probe.error,
                },
              ),
            );
            if (!probe.ok) {
              _recordRouteFailure(candidate, 'post_connect_probe');
              lastError =
                  'YouTube не открылся через ${greenVpnPublicServerTitle(candidate)}';
              await appendBlueVpnClientLog(
                'post connect probe rejected server=${candidate.id}; disconnecting before next candidate',
              );
              final stopped = await _stopFailedRouteBeforeFallback(
                candidate,
                stage: 'post_connect_probe_failed',
              );
              if (!mounted) return;
              if (!stopped) {
                _toast(
                  context,
                  'Не удалось полностью остановить нерабочий маршрут. '
                  'Автопереключение остановлено.',
                );
                return;
              }
              if (canTryNext) {
                _setVpnBusyUi(
                  stage: 'Пробуем запасной узел...',
                  hint:
                      '${greenVpnPublicServerTitle(candidate)} не открывает YouTube. Пробуем следующий доступный вариант.',
                );
                continue;
              }
              _toast(
                context,
                'VPN включился, но YouTube не работает. Подключение остановлено.',
              );
              return;
            }
            unawaited(
              appendBlueVpnClientLog(
                'toggle YouTube confirmed server=${candidate.id} clickToYoutubeMs=${toggleWatch.elapsedMilliseconds}',
              ),
            );
          }

          await appendBlueVpnClientLog(
            !kIsWeb && (Platform.isWindows || Platform.isAndroid)
                ? 'foreground connect accepted system tunnel server=${candidate.id}; Internet checks continue in background'
                : 'post connect checks accepted tunnel server=${candidate.id}',
          );
          if (!mounted) return;
          if (kIsWeb || (!Platform.isWindows && !Platform.isAndroid)) {
            await _recordRouteSuccess(candidate);
          }
          if (!mounted) return;
          unawaited(_armRuntimeFailover(candidate));
          _trackConnectionState(
            true,
            route: candidate,
            latencyMs: connectionLatencyMs,
          );
          if (!kIsWeb && Platform.isAndroid && _shouldRunPostConnectProbe) {
            unawaited(_verifyAndroidConnectedRouteInBackground(candidate));
          }
          _refreshConnectionOptionsAfterConnect(candidate);
          if (kPaidBetaBuild) {
            unawaited(_recordPaidBetaEvent('vpn_connected'));
          }
          _startVpnTapCooldown(
            hint:
                'VPN только что включился. Кнопка разблокируется через секунду, чтобы избежать случайного двойного нажатия.',
          );
          _toast(
            context,
            selectedServer.isAuto
                ? 'VPN включён через ${greenVpnPublicServerTitle(candidate)}.'
                : 'VPN включён.',
          );
          return;
        }

        if (!mounted) return;
        _toast(
          context,
          lastError == null
              ? 'Не удалось подобрать рабочую локацию.'
              : 'Не удалось подобрать рабочую локацию: $lastError.',
        );
      } else {
        await appendBlueVpnClientLog('toggle disconnect branch start');
        _disarmWindowsRuntimeFailover(reason: 'user_disconnect');
        _setVpnBusyUi(
          stage: 'Отключаем VPN...',
          hint: 'Останавливаем VPN и аккуратно снимаем подключение.',
        );
        final res = await _vpnBackend.disconnect();
        await appendBlueVpnClientLog(
          'toggle disconnect backend ok=${res.ok} message=${res.message ?? ""}',
        );
        if (!mounted) return;
        if (!res.ok) {
          _toast(context, res.message ?? 'Не удалось отключить VPN.');
          await _syncVpnStatus();
          final onNow = await _vpnBackend.isConnected();
          if (mounted) setState(() => vpnEnabled = onNow);

          return;
        }
        _cancelFreeAdSessionTimer();

        _setVpnBusyUi(
          stage: 'Проверяем статус...',
          hint: 'Убеждаемся, что интерфейс и маршруты действительно сняты.',
        );
        await _syncVpnStatus();
        await appendBlueVpnClientLog(
          'toggle disconnect sync done vpnEnabled=$vpnEnabled',
        );
        if (!mounted) return;
        _trackConnectionState(false);
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

  Future<void> _refreshServerCatalog({required bool showToast}) {
    return _serverCatalogRefresh.run(
      () => _refreshServerCatalogOnce(showToast: showToast),
    );
  }

  Future<void> _refreshServerCatalogOnce({required bool showToast}) async {
    if (mounted) {
      setState(() {
        _serverCatalogBusy = true;
        if (showToast) _serverCatalogStatus = 'Обновляем список локаций...';
      });
    }
    try {
      var res = await _api.fetchServerCatalog();
      if (!res.ok && _isAndroidNetworkFailureMessage(res.message)) {
        await _recoverAndroidStaleVpnForNetwork(
          res.message ?? 'server_catalog_network_failure',
        );
        res = await _api.fetchServerCatalog();
      }
      if (!mounted) return;
      if (!res.ok || res.data == null) {
        final fallbackServers = _mergeServerCatalogs(
          _fallbackServerCatalogForCurrentChannel(),
          servers.where((s) => !s.isAuto).toList(),
        );
        final desiredServerId = _persistedServerId.trim().isEmpty
            ? selectedServer.id
            : _persistedServerId;
        final stillSelected = fallbackServers.any(
          (s) => _serverMatchesSelection(s, desiredServerId),
        );
        setState(() {
          servers = fallbackServers;
          final fallbackSelected = stillSelected
              ? fallbackServers.firstWhere(
                  (s) => _serverMatchesSelection(s, desiredServerId),
                  orElse: () => fallbackServers.first,
                )
              : fallbackServers.first;
          selectedServer =
              fallbackSelected.isAuto || fallbackSelected.isCurrentClientReady
              ? fallbackSelected
              : fallbackServers.first;
          _adaptiveRouteServerId = null;
          _adaptiveRouteProtocol = null;
          _adaptiveRouteScore = null;
          _serverCatalogStatus =
              'Не удалось обновить список локаций. Используется сохранённый список.';
        });
        if (showToast) _toast(context, _serverCatalogStatus!);
        await _restoreWindowsRuntimeFailoverIfPossible(
          source: 'catalog_fallback',
        );
        return;
      }

      final rawServers = res.data!['servers'];
      final resilience = res.data!['resilience'];
      final resilienceMap = resilience is Map
          ? Map<String, dynamic>.from(resilience)
          : <String, dynamic>{};
      final routeDecision = resilienceMap['routeDecision'];
      final routeDecisionMap = routeDecision is Map
          ? Map<String, dynamic>.from(routeDecision)
          : <String, dynamic>{};
      final selectedRoute = routeDecisionMap['selected'];
      final selectedRouteMap = selectedRoute is Map
          ? Map<String, dynamic>.from(selectedRoute)
          : <String, dynamic>{};
      final selectedRouteServerId = (selectedRouteMap['serverId'] ?? '')
          .toString()
          .trim();
      final selectedRouteProtocol = (selectedRouteMap['protocol'] ?? '')
          .toString()
          .trim();
      final selectedRouteScoreRaw = selectedRouteMap['score'];
      final nextServers = <ServerLocation>[
        const ServerLocation(
          id: 'auto',
          title: 'Авто',
          subtitle: 'Автовыбор локации',
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
        final fallbackServers = _fallbackServerCatalogForCurrentChannel().where(
          (s) => !s.isAuto,
        );
        nextServers.addAll(
          _mergeServerCatalogs(
            fallbackServers.toList(),
            servers.where((s) => !s.isAuto).toList(),
          ).where((s) => !s.isAuto),
        );
      }

      final desiredServerId = _persistedServerId.trim().isEmpty
          ? selectedServer.id
          : _persistedServerId;
      final stillSelected = nextServers.any(
        (s) => _serverMatchesSelection(s, desiredServerId),
      );
      setState(() {
        servers = nextServers;
        _adaptiveRouteServerId = selectedRouteServerId.isEmpty
            ? null
            : selectedRouteServerId;
        _adaptiveRouteProtocol = selectedRouteProtocol.isEmpty
            ? null
            : selectedRouteProtocol;
        _adaptiveRouteScore = selectedRouteScoreRaw is num
            ? selectedRouteScoreRaw.toInt()
            : null;
        final nextSelected = stillSelected
            ? nextServers.firstWhere(
                (s) => _serverMatchesSelection(s, desiredServerId),
                orElse: () => nextServers.first,
              )
            : nextServers.first;
        selectedServer =
            nextSelected.isAuto || nextSelected.isCurrentClientReady
            ? nextSelected
            : nextServers.first;
        _serverCatalogStatus = 'Список локаций обновлён.';
      });
      await _reconcileSubscriptionEntitlements();
      if (!mounted) return;
      if (showToast) _toast(context, _serverCatalogStatus!);
      await _restoreWindowsRuntimeFailoverIfPossible(source: 'catalog_refresh');
    } finally {
      if (mounted) setState(() => _serverCatalogBusy = false);
    }
  }

  Future<void> _openServerPicker(BuildContext context) async {
    await _prepareAndroidControlPlaneAccess('server_picker');
    await _refreshServerCatalog(showToast: false);
    if (!context.mounted) return;
    final pickerServers = _serverPickerLocations();
    final automaticLatencyMs = _backendAutoCandidate().pingMs;
    final searchController = TextEditingController();
    ServerLocation? picked;
    try {
      picked = await showDialog<ServerLocation>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) {
            final memoryEnabled = _clientFeatureEnabled(
              kFusionLocationMemoryFlag,
            );
            final query = searchController.text.trim().toLowerCase();
            bool matches(ServerLocation server) {
              if (query.isEmpty) return true;
              final haystack = <String>[
                greenVpnPublicServerTitle(server),
                greenVpnPublicServerSubtitle(server),
                server.country,
                server.city,
              ].join(' ').toLowerCase();
              return haystack.contains(query);
            }

            final visible = pickerServers.where(matches).toList();
            final favorites = visible
                .where(
                  (server) =>
                      memoryEnabled &&
                      !server.isAuto &&
                      _favoriteLocationIds.contains(server.publicLocationId),
                )
                .toList();
            final recent =
                visible
                    .where(
                      (server) =>
                          memoryEnabled &&
                          !server.isAuto &&
                          !_favoriteLocationIds.contains(
                            server.publicLocationId,
                          ) &&
                          _recentLocationIds.contains(server.publicLocationId),
                    )
                    .toList()
                  ..sort(
                    (left, right) => _recentLocationIds
                        .indexOf(left.publicLocationId)
                        .compareTo(
                          _recentLocationIds.indexOf(right.publicLocationId),
                        ),
                  );
            final other = visible
                .where(
                  (server) =>
                      !server.isAuto &&
                      !favorites.contains(server) &&
                      !recent.contains(server),
                )
                .toList();
            final automatic = visible.where((server) => server.isAuto).toList();

            Widget sectionTitle(String title) => Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: kBrandMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            );

            Widget locationTile(ServerLocation server) {
              final locked =
                  server.requiresPaidSubscription &&
                  !_hasPaidSubscriptionEntitlement;
              final selected = server.isAuto
                  ? selectedServer.isAuto
                  : !selectedServer.isAuto &&
                        server.publicLocationId ==
                            selectedServer.publicLocationId;
              final latency = greenVpnPublicLatencyLabel(
                server.isAuto ? automaticLatencyMs : server.pingMs,
              );
              final subtitle = locked ? '$latency • По подписке' : latency;
              final favorite = _favoriteLocationIds.contains(
                server.publicLocationId,
              );
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  server.isAuto
                      ? Icons.auto_awesome_rounded
                      : locked
                      ? Icons.lock_rounded
                      : server.isCurrentClientReady
                      ? Icons.public_rounded
                      : Icons.warning_amber_rounded,
                  color: locked
                      ? kBrandWarm
                      : server.isAuto || server.isCurrentClientReady
                      ? kBrandPrimary
                      : kBrandWarm,
                ),
                title: Text(
                  greenVpnPublicServerTitle(server),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(subtitle),
                trailing: server.isAuto
                    ? Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.chevron_right_rounded,
                        color: selected ? kBrandPrimary : null,
                      )
                    : !memoryEnabled
                    ? Icon(
                        locked
                            ? Icons.lock_outline_rounded
                            : selected
                            ? Icons.check_circle_rounded
                            : Icons.chevron_right_rounded,
                        color: selected ? kBrandPrimary : null,
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key(
                              'fusion_location_favorite_${server.publicLocationId}',
                            ),
                            tooltip: favorite
                                ? 'Убрать из избранного'
                                : 'В избранное',
                            onPressed: () {
                              _toggleFavoriteLocation(server);
                              setLocal(() {});
                            },
                            icon: Icon(
                              favorite
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: favorite ? kBrandWarm : null,
                            ),
                          ),
                          Icon(
                            locked
                                ? Icons.lock_outline_rounded
                                : selected
                                ? Icons.check_circle_rounded
                                : Icons.chevron_right_rounded,
                            color: selected ? kBrandPrimary : null,
                          ),
                        ],
                      ),
                onTap: () {
                  if (locked) {
                    Navigator.of(ctx).pop();
                    _openTariff();
                    _toast(context, 'Эта локация доступна по подписке.');
                    return;
                  }
                  Navigator.of(ctx).pop(server);
                },
              );
            }

            final sections = <Widget>[
              for (final server in automatic) locationTile(server),
              if (favorites.isNotEmpty) sectionTitle('Избранное'),
              for (final server in favorites) locationTile(server),
              if (recent.isNotEmpty) sectionTitle('Недавние'),
              for (final server in recent) locationTile(server),
              if (other.isNotEmpty) sectionTitle('Все локации'),
              for (final server in other) locationTile(server),
            ];

            return AlertDialog(
              title: const Text('Выбор локации'),
              content: SizedBox(
                width: 440,
                height: min(MediaQuery.of(ctx).size.height * 0.68, 620.0),
                child: Column(
                  children: [
                    if (memoryEnabled) ...[
                      TextField(
                        key: const Key('fusion_location_search'),
                        controller: searchController,
                        onChanged: (_) => setLocal(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Поиск локации',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: sections.isEmpty
                          ? const Center(child: Text('Ничего не найдено'))
                          : ListView(children: sections),
                    ),
                  ],
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
        ),
      );
    } finally {
      searchController.dispose();
    }

    if (picked != null) {
      await _selectServerAndReconnectIfNeeded(picked);
    }
  }

  Future<void> _selectServerAndReconnectIfNeeded(
    ServerLocation picked, {
    bool persistSelection = true,
  }) async {
    if (picked.requiresPaidSubscription && !_hasPaidSubscriptionEntitlement) {
      _openTariff();
      _toast(context, 'Эта локация доступна по подписке.');
      return;
    }
    if (vpnBusy) {
      _toast(
        context,
        'Green VPN уже переключает подключение. Подожди пару секунд.',
      );
      return;
    }

    setState(() => selectedServer = picked);
    if (persistSelection) {
      _persistedServerId = _serverSelectionKey(picked);
      _schedulePrefsSave();
    }

    await _syncVpnStatus();
    if (!mounted) return;
    if (!vpnEnabled) {
      unawaited(_cfg.deleteManagedConfig());
      return;
    }

    _setVpnBusyUi(
      stage: 'Переключаем сервер...',
      hint: 'Останавливаем текущее подключение и запускаем VPN заново.',
    );
    _disarmWindowsRuntimeFailover(reason: 'server_switch');

    try {
      await appendBlueVpnClientLog(
        'server switch start requested=${picked.id} title=${picked.title}',
      );

      final stoppedCurrent = await _stopFailedRouteBeforeFallback(
        picked,
        stage: 'switch_start',
      );
      if (!mounted) return;
      if (!stoppedCurrent) {
        _toast(
          context,
          'Не удалось полностью остановить текущий VPN. '
          'Переключение отменено.',
        );
        return;
      }
      final candidates = _connectCandidatesForCurrentSelection().isNotEmpty
          ? _connectCandidatesForCurrentSelection()
          : <ServerLocation>[picked];
      String? lastError;

      for (var i = 0; i < candidates.length; i++) {
        var candidate = candidates[i];
        final canTryNext = i < candidates.length - 1;
        _setVpnBusyUi(
          stage: 'Получаем конфиг...',
          hint: candidate.isAuto
              ? 'Подбираем подходящую локацию и готовим подключение.'
              : 'Готовим подключение для ${greenVpnPublicServerTitle(candidate)}.',
        );

        final configWatch = Stopwatch()..start();
        final provisioned = await _ensureProvisionedConfigInteractive(
          serverOverride: candidate,
          boundedAndroidNetwork: !kIsWeb && Platform.isAndroid,
        );
        configWatch.stop();
        final effectiveServer = provisioned.server ?? candidate;
        if (provisioned.ok && effectiveServer.id != candidate.id) {
          candidate = effectiveServer;
        }
        await appendBlueVpnClientLog(
          'server switch config ok=${provisioned.ok} requested=${picked.id} candidate=${candidate.id} effective=${effectiveServer.id}',
        );
        if (!mounted) return;
        unawaited(
          _reportRouteEvent(
            effectiveServer,
            stage: 'switch_config_fetch',
            ok: provisioned.ok,
            latencyMs: configWatch.elapsedMilliseconds,
            errorCode: provisioned.ok ? null : 'config_fetch_failed',
            message: provisioned.message,
            details: {
              'requestedServerId': picked.id,
              'attempt': i + 1,
              'candidates': candidates.length,
            },
          ),
        );
        if (!provisioned.ok) {
          lastError =
              'не удалось получить конфиг для ${greenVpnPublicServerTitle(candidate)}';
          await _syncVpnStatus();
          if (!mounted) return;
          if (canTryNext) continue;
          break;
        }

        if (effectiveServer.id != selectedServer.id) {
          setState(() => selectedServer = effectiveServer);
          if (persistSelection) _schedulePrefsSave();
        }

        _setVpnBusyUi(
          stage: 'Запускаем VPN...',
          hint:
              'Запускаем VPN через ${greenVpnPublicServerTitle(effectiveServer)}.',
        );
        final connectWatch = Stopwatch()..start();
        final on = await _vpnBackend.connect(
          configPath: _cfg.managedConfigPath,
        );
        connectWatch.stop();
        await appendBlueVpnClientLog(
          'server switch connect ok=${on.ok} server=${effectiveServer.id} message=${on.message ?? ""}',
        );
        unawaited(
          _reportRouteEvent(
            effectiveServer,
            stage: 'switch_connect',
            ok: on.ok,
            latencyMs: connectWatch.elapsedMilliseconds,
            errorCode: on.ok ? null : 'connect_failed',
            message: on.message,
            details: {
              'requestedServerId': picked.id,
              'attempt': i + 1,
              'candidates': candidates.length,
            },
          ),
        );
        await _syncVpnStatus();
        if (!mounted) return;
        if (!on.ok) {
          lastError =
              on.message ??
              'не удалось подключить ${greenVpnPublicServerTitle(effectiveServer)}';
          final stopped = await _stopFailedRouteBeforeFallback(
            effectiveServer,
            stage: 'switch_connect_failed',
          );
          if (!mounted) return;
          if (!stopped) {
            _toast(
              context,
              'Не удалось полностью остановить предыдущий маршрут. '
              'Переключение отменено.',
            );
            return;
          }
          if (canTryNext) continue;
          break;
        }
        if (!vpnEnabled) {
          lastError =
              'VPN не подтвердился через ${greenVpnPublicServerTitle(effectiveServer)}';
          final stopped = await _stopFailedRouteBeforeFallback(
            effectiveServer,
            stage: 'switch_handshake_failed',
          );
          if (!mounted) return;
          if (!stopped) {
            _toast(
              context,
              'Не удалось полностью остановить неподтверждённый маршрут. '
              'Переключение отменено.',
            );
            return;
          }
          if (canTryNext) continue;
          break;
        }

        var connectionLatencyMs = effectiveServer.pingMs;
        if (_shouldRunPostConnectProbe) {
          _setVpnBusyUi(
            stage: 'Проверяем YouTube...',
            hint: 'VPN включён. Проверяем, что YouTube открывается.',
          );
          final probe = await _probeConnectedTunnelRoute(effectiveServer);
          connectionLatencyMs = probe.latencyMs;
          if (!mounted) return;
          unawaited(
            _reportRouteEvent(
              effectiveServer,
              stage: 'switch_post_connect_probe',
              ok: probe.ok,
              latencyMs: probe.latencyMs,
              errorCode: probe.ok
                  ? null
                  : (probe.statusCode == null
                        ? 'youtube_probe_failed'
                        : 'youtube_http_${probe.statusCode}'),
              message: probe.ok
                  ? 'YouTube route confirmed after server switch.'
                  : 'VPN поднялся, но YouTube не открылся через этот узел.',
              details: {
                'requestedServerId': picked.id,
                'attempt': i + 1,
                'candidates': candidates.length,
                'target': probe.target,
                'statusCode': probe.statusCode,
                'error': probe.error,
              },
            ),
          );
          if (!probe.ok) {
            lastError =
                'YouTube не открылся через ${greenVpnPublicServerTitle(effectiveServer)}';
            await appendBlueVpnClientLog(
              'server switch post connect probe rejected server=${effectiveServer.id}; disconnecting before next candidate',
            );
            final stopped = await _stopFailedRouteBeforeFallback(
              effectiveServer,
              stage: 'switch_post_connect_probe_failed',
            );
            if (!mounted) return;
            if (!stopped) {
              _toast(
                context,
                'Не удалось полностью остановить нерабочий маршрут. '
                'Переключение отменено.',
              );
              return;
            }
            if (canTryNext) continue;
            break;
          }
        }

        await _recordRouteSuccess(effectiveServer);
        await _armRuntimeFailover(effectiveServer);
        _trackConnectionState(
          true,
          route: effectiveServer,
          latencyMs: connectionLatencyMs,
        );
        if (!mounted) return;

        _startVpnTapCooldown(
          hint:
              'VPN только что переключился. Кнопка разблокируется через секунду.',
        );
        _toast(
          context,
          'VPN переключён на ${greenVpnPublicServerTitle(effectiveServer)}.',
        );
        return;
      }

      if (!mounted) return;
      _toast(
        context,
        lastError == null
            ? 'Не удалось переключить локацию.'
            : 'Не удалось переключить локацию: $lastError.',
      );
    } catch (e, st) {
      await appendBlueVpnClientLog('server switch exception=$e stack=$st');
      await _syncVpnStatus();
      if (mounted) _toast(context, 'Ошибка переключения сервера: $e');
    } finally {
      _clearVpnBusyUi();
    }
  }

  Future<List<_AndroidLaunchableApp>> _loadAndroidLaunchableApps() async {
    if (kIsWeb || !Platform.isAndroid) return const <_AndroidLaunchableApp>[];

    final raw = await kAndroidPlatformChannel.invokeMethod<List<dynamic>>(
      'listInstalledApps',
    );
    final byPackage = <String, _AndroidLaunchableApp>{};
    for (final item in raw ?? const <dynamic>[]) {
      final app = _AndroidLaunchableApp.fromPlatform(item);
      if (app != null) byPackage[app.packageName] = app;
    }
    final apps = byPackage.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    _androidInstalledAppLabels
      ..clear()
      ..addEntries(apps.map((app) => MapEntry(app.packageName, app.label)));
    return apps;
  }

  Future<Set<String>?> _openInstalledAppsPicker(
    BuildContext context,
    Set<String> current,
  ) async {
    final apps = await _loadAndroidLaunchableApps();
    if (!mounted || !context.mounted) return null;
    if (apps.isEmpty) {
      _toast(context, 'Android не вернул список установленных приложений.');
      return null;
    }

    final presetPackages = _androidSocialPackageNames.values
        .expand((packages) => packages)
        .toSet();
    final available = apps
        .where((app) => !presetPackages.contains(app.packageName))
        .toList();
    final selected = Set<String>.from(current);
    final searchController = TextEditingController();

    try {
      return await showDialog<Set<String>>(
        context: context,
        builder: (ctx) {
          var query = '';
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              final normalizedQuery = query.trim().toLowerCase();
              final filtered = normalizedQuery.isEmpty
                  ? available
                  : available.where((app) {
                      return app.label.toLowerCase().contains(
                            normalizedQuery,
                          ) ||
                          app.packageName.toLowerCase().contains(
                            normalizedQuery,
                          );
                    }).toList();
              return AlertDialog(
                title: const Text('Добавить приложение'),
                content: SizedBox(
                  width: 460,
                  height: min(MediaQuery.of(ctx).size.height * 0.62, 540.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: searchController,
                        autofocus: true,
                        onChanged: (value) => setLocal(() => query = value),
                        decoration: const InputDecoration(
                          hintText: 'Поиск',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('Ничего не найдено'))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (ctx, index) {
                                  final app = filtered[index];
                                  return CheckboxListTile(
                                    value: selected.contains(app.packageName),
                                    onChanged: (value) {
                                      setLocal(() {
                                        if (value == true) {
                                          selected.add(app.packageName);
                                        } else {
                                          selected.remove(app.packageName);
                                        }
                                      });
                                    },
                                    title: Text(
                                      app.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    secondary: const Icon(Icons.apps_rounded),
                                    controlAffinity:
                                        ListTileControlAffinity.trailing,
                                    contentPadding: EdgeInsets.zero,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Отмена'),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        Navigator.of(ctx).pop(Set<String>.from(selected)),
                    child: const Text('Добавить'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      searchController.dispose();
    }
  }

  Future<List<WindowsLaunchableApp>> _loadWindowsLaunchableApps() async {
    if (kIsWeb || !Platform.isWindows) {
      return const <WindowsLaunchableApp>[];
    }
    final apps = await listWindowsLaunchableApps();
    _windowsInstalledAppLabels
      ..clear()
      ..addEntries(apps.map((app) => MapEntry(app.path, app.label)));
    return apps;
  }

  Future<Set<String>?> _openWindowsInstalledAppsPicker(
    BuildContext context,
    Set<String> current,
  ) async {
    final apps = await _loadWindowsLaunchableApps();
    if (!mounted || !context.mounted) return null;
    if (apps.isEmpty) {
      _toast(context, 'Windows не вернул список установленных программ.');
      return null;
    }

    final selected = Set<String>.from(current);
    final searchController = TextEditingController();
    try {
      return await showDialog<Set<String>>(
        context: context,
        builder: (ctx) {
          var query = '';
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              final normalizedQuery = query.trim().toLowerCase();
              final filtered = normalizedQuery.isEmpty
                  ? apps
                  : apps.where((app) {
                      return app.label.toLowerCase().contains(
                            normalizedQuery,
                          ) ||
                          windowsApplicationLabel(
                            app.path,
                          ).toLowerCase().contains(normalizedQuery);
                    }).toList();
              return AlertDialog(
                title: const Text('Установленные программы'),
                content: SizedBox(
                  width: 520,
                  height: min(MediaQuery.of(ctx).size.height * 0.68, 580.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: searchController,
                        autofocus: true,
                        onChanged: (value) => setLocal(() => query = value),
                        decoration: const InputDecoration(
                          hintText: 'Найти программу',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('Ничего не найдено'))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (ctx, index) {
                                  final app = filtered[index];
                                  return CheckboxListTile(
                                    value: selected.contains(app.path),
                                    onChanged: (value) {
                                      setLocal(() {
                                        if (value == true) {
                                          if (selected.length <
                                              maxWindowsVpnApplications) {
                                            selected.add(app.path);
                                          }
                                        } else {
                                          selected.remove(app.path);
                                        }
                                      });
                                    },
                                    title: Text(
                                      app.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    secondary: const Icon(Icons.apps_rounded),
                                    controlAffinity:
                                        ListTileControlAffinity.trailing,
                                    contentPadding: EdgeInsets.zero,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Отмена'),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        Navigator.of(ctx).pop(Set<String>.from(selected)),
                    child: const Text('Готово'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      searchController.dispose();
    }
  }

  Future<String?> _openWindowsSitePicker(BuildContext context) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) {
          var busy = false;
          String? error;
          return StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
              title: const Text('Добавить сайт'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Вставь адрес сайта, например vk.com.'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      enabled: !busy,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: 'example.com',
                        prefixIcon: const Icon(Icons.language_rounded),
                        errorText: error,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final site = normalizeWindowsVpnSite(controller.text);
                          if (site == null) {
                            setLocal(() => error = 'Проверь адрес сайта');
                            return;
                          }
                          setLocal(() {
                            busy = true;
                            error = null;
                          });
                          WindowsSiteResolution resolution;
                          try {
                            resolution = await resolveWindowsVpnSites([site]);
                          } catch (_) {
                            if (ctx.mounted) {
                              setLocal(() {
                                busy = false;
                                error = 'Не удалось проверить сайт';
                              });
                            }
                            return;
                          }
                          if (!ctx.mounted) return;
                          if (resolution.ipv4Cidrs.isEmpty) {
                            setLocal(() {
                              busy = false;
                              error = 'Сайт не найден';
                            });
                            return;
                          }
                          Navigator.of(ctx).pop(site);
                        },
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Добавить'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _commitSocialOnlySelection({
    required BuildContext context,
    required Set<SocialApp> presets,
    required Set<String> androidPackages,
    required Set<String> windowsApplications,
    required Set<String> windowsSites,
  }) async {
    final previous = _captureRoutingPreference();
    final wasConnected = vpnEnabled;
    _prefsDebounce?.cancel();
    setState(() {
      socialOnlyApps
        ..clear()
        ..addAll(presets);
      socialOnlyCustomPackages
        ..clear()
        ..addAll(androidPackages);
      socialOnlyWindowsApplications
        ..clear()
        ..addAll(windowsApplications);
      socialOnlyWindowsSites
        ..clear()
        ..addAll(windowsSites);
    });

    if (!socialOnlyEnabled) {
      _schedulePrefsSave();
      return;
    }
    if (mounted) {
      setState(() {
        vpnBusy = true;
        _vpnBusyStage = 'Применяем выбранный список...';
        _vpnBusyHint = wasConnected
            ? 'Переподключаем VPN с новым набором сервисов и программ.'
            : 'Сохраняем набор сервисов и программ.';
      });
    }
    try {
      final applied = await _applyCurrentConfigMode(
        reconnectIfNeeded: true,
        showToastOnSuccess: true,
      );
      if (!applied) {
        throw StateError('Новый список не был подтверждён системой.');
      }
      _schedulePrefsSave();
    } catch (e) {
      final restored = await _restoreRoutingPreferenceAfterFailure(
        snapshot: previous,
        wasConnected: wasConnected,
      );
      if (context.mounted) {
        _toast(
          context,
          restored
              ? '${e.toString().replaceFirst('Bad state: ', '')} Предыдущий список восстановлен.'
              : '${e.toString().replaceFirst('Bad state: ', '')} Не удалось восстановить список; фактическое состояние показано на главном экране.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          vpnBusy = false;
          _vpnBusyStage = null;
          if (!_vpnTapCooldown) _vpnBusyHint = null;
        });
      }
    }
  }

  Future<void> _openFusionSocialAppsPicker(BuildContext context) async {
    final tempPresets = Set<SocialApp>.from(socialOnlyApps);
    final usesAndroidApplications = !kIsWeb && Platform.isAndroid;
    final usesWindowsApplications = !kIsWeb && Platform.isWindows;
    final tempCustomPackages = usesAndroidApplications
        ? Set<String>.from(socialOnlyCustomPackages)
        : <String>{};
    final tempWindowsApplications = usesWindowsApplications
        ? Set<String>.from(socialOnlyWindowsApplications)
        : <String>{};
    final tempWindowsSites = usesWindowsApplications
        ? Set<String>.from(socialOnlyWindowsSites)
        : <String>{};

    final picked = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final choices =
              <_FusionTrafficChoice>[
                for (final app in SocialApp.values)
                  _FusionTrafficChoice(
                    id: 'preset_${app.name}',
                    title: app.title,
                    icon: app.icon,
                    selected: tempPresets.contains(app),
                    onToggle: () => setLocal(() {
                      if (!tempPresets.add(app)) tempPresets.remove(app);
                    }),
                  ),
                for (final packageName in tempCustomPackages)
                  _FusionTrafficChoice(
                    id: 'android_$packageName',
                    title:
                        _androidInstalledAppLabels[packageName] ?? packageName,
                    subtitle: packageName,
                    icon: Icons.apps_rounded,
                    selected: true,
                    onToggle: () =>
                        setLocal(() => tempCustomPackages.remove(packageName)),
                  ),
                for (final path in tempWindowsApplications)
                  _FusionTrafficChoice(
                    id: 'windows_$path',
                    title:
                        _windowsInstalledAppLabels[path] ??
                        windowsApplicationLabel(path),
                    subtitle: path,
                    icon: Icons.apps_rounded,
                    selected: true,
                    onToggle: () =>
                        setLocal(() => tempWindowsApplications.remove(path)),
                  ),
                for (final site in tempWindowsSites)
                  _FusionTrafficChoice(
                    id: 'site_$site',
                    title: site,
                    icon: Icons.language_rounded,
                    selected: true,
                    onToggle: () =>
                        setLocal(() => tempWindowsSites.remove(site)),
                  ),
              ]..sort(
                (a, b) =>
                    a.title.toLowerCase().compareTo(b.title.toLowerCase()),
              );
          final selectedCount =
              tempPresets.length +
              tempCustomPackages.length +
              tempWindowsApplications.length +
              tempWindowsSites.length;

          Future<void> addAndroidApplications() async {
            try {
              final selected = await _openInstalledAppsPicker(
                ctx,
                tempCustomPackages,
              );
              if (selected == null || !ctx.mounted) return;
              setLocal(() {
                tempCustomPackages
                  ..clear()
                  ..addAll(selected);
              });
            } catch (e) {
              if (ctx.mounted) {
                _toast(ctx, 'Не удалось открыть список приложений: $e');
              }
            }
          }

          Future<void> addWindowsApplications() async {
            try {
              final selected = await _openWindowsInstalledAppsPicker(
                ctx,
                tempWindowsApplications,
              );
              if (selected == null || !ctx.mounted) return;
              setLocal(() {
                tempWindowsApplications
                  ..clear()
                  ..addAll(selected);
              });
            } catch (e) {
              if (ctx.mounted) {
                _toast(ctx, 'Не удалось открыть список программ: $e');
              }
            }
          }

          Future<void> addWindowsSite() async {
            try {
              final site = await _openWindowsSitePicker(ctx);
              if (site == null || !ctx.mounted) return;
              setLocal(() => tempWindowsSites.add(site));
            } catch (e) {
              if (ctx.mounted) _toast(ctx, 'Не удалось добавить сайт: $e');
            }
          }

          Future<void> addWindowsExecutablesManually() async {
            try {
              final result = await FilePicker.platform.pickFiles(
                dialogTitle: 'Выбери файл программы',
                type: FileType.custom,
                allowedExtensions: const ['exe'],
                allowMultiple: true,
              );
              if (result == null || !ctx.mounted) return;
              final paths = result.paths
                  .whereType<String>()
                  .map((value) => value.trim())
                  .where(isValidWindowsApplicationPath)
                  .where((value) => File(value).existsSync())
                  .toSet();
              if (paths.isEmpty) {
                _toast(ctx, 'Не удалось определить выбранную программу.');
                return;
              }
              if (tempWindowsApplications.length + paths.length >
                  maxWindowsVpnApplications) {
                _toast(
                  ctx,
                  'Можно выбрать не более $maxWindowsVpnApplications приложений.',
                );
                return;
              }
              setLocal(() => tempWindowsApplications.addAll(paths));
            } catch (e) {
              if (ctx.mounted) _toast(ctx, 'Не удалось выбрать программу: $e');
            }
          }

          return AlertDialog(
            key: const Key('fusion_selected_traffic_dialog'),
            title: const Text('Только выбранное'),
            content: SizedBox(
              width: usesWindowsApplications ? 590 : 470,
              height: min(MediaQuery.of(ctx).size.height * 0.68, 610.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Выберите всё, что должно работать через VPN. Остальной интернет останется без VPN.',
                  ),
                  const SizedBox(height: 12),
                  if (usesAndroidApplications)
                    OutlinedButton.icon(
                      key: const Key('fusion_add_android_app'),
                      onPressed: addAndroidApplications,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Добавить приложение'),
                    ),
                  if (usesWindowsApplications)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('fusion_add_windows_program'),
                          onPressed:
                              tempWindowsApplications.length >=
                                  maxWindowsVpnApplications
                              ? null
                              : addWindowsApplications,
                          icon: const Icon(Icons.search_rounded),
                          label: const Text('Добавить программу'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('fusion_add_windows_site'),
                          onPressed:
                              tempWindowsSites.length >= maxWindowsVpnSites
                              ? null
                              : addWindowsSite,
                          icon: const Icon(Icons.add_link_rounded),
                          label: const Text('Добавить сайт'),
                        ),
                        TextButton.icon(
                          key: const Key('fusion_manual_windows_exe'),
                          onPressed:
                              tempWindowsApplications.length >=
                                  maxWindowsVpnApplications
                              ? null
                              : addWindowsExecutablesManually,
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('Выбрать EXE'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'Выбрано: $selectedCount',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.separated(
                      itemCount: choices.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final choice = choices[index];
                        return CheckboxListTile(
                          key: Key('fusion_traffic_choice_${choice.id}'),
                          value: choice.selected,
                          onChanged: (_) => choice.onToggle(),
                          secondary: Icon(choice.icon, color: kBrandPrimary),
                          title: Text(
                            choice.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: choice.subtitle == null
                              ? null
                              : Text(
                                  choice.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          controlAffinity: ListTileControlAffinity.trailing,
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                key: const Key('fusion_selected_traffic_done'),
                onPressed: () {
                  if (selectedCount == 0) {
                    _toast(ctx, 'Выберите хотя бы один пункт.');
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                child: const Text('Готово'),
              ),
            ],
          );
        },
      ),
    );

    if (picked != true || !context.mounted) return;
    await _commitSocialOnlySelection(
      context: context,
      presets: tempPresets,
      androidPackages: tempCustomPackages,
      windowsApplications: tempWindowsApplications,
      windowsSites: tempWindowsSites,
    );
  }

  Future<void> _openSocialAppsPicker(BuildContext context) async {
    if (kFusionUiEnabled) {
      await _openFusionSocialAppsPicker(context);
      return;
    }
    final tempPresets = Set<SocialApp>.from(socialOnlyApps);
    final usesAndroidApplications = !kIsWeb && Platform.isAndroid;
    final usesWindowsApplications = !kIsWeb && Platform.isWindows;
    final usesApplications = usesAndroidApplications || usesWindowsApplications;
    final tempCustomPackages = usesAndroidApplications
        ? Set<String>.from(socialOnlyCustomPackages)
        : <String>{};
    final tempWindowsApplications = usesWindowsApplications
        ? Set<String>.from(socialOnlyWindowsApplications)
        : <String>{};
    final tempWindowsSites = usesWindowsApplications
        ? Set<String>.from(socialOnlyWindowsSites)
        : <String>{};

    final picked = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final sortedCustomPackages = tempCustomPackages.toList()
              ..sort(
                (a, b) => (_androidInstalledAppLabels[a] ?? a)
                    .toLowerCase()
                    .compareTo(
                      (_androidInstalledAppLabels[b] ?? b).toLowerCase(),
                    ),
              );
            final sortedWindowsApplications = tempWindowsApplications.toList()
              ..sort(
                (a, b) =>
                    (_windowsInstalledAppLabels[a] ??
                            windowsApplicationLabel(a))
                        .toLowerCase()
                        .compareTo(
                          (_windowsInstalledAppLabels[b] ??
                                  windowsApplicationLabel(b))
                              .toLowerCase(),
                        ),
              );
            final sortedWindowsSites = tempWindowsSites.toList()..sort();
            return AlertDialog(
              title: Text(
                usesWindowsApplications
                    ? 'Что работает через VPN'
                    : (usesApplications
                          ? 'Приложения через VPN'
                          : 'Сервисы через VPN'),
              ),
              content: SizedBox(
                width: usesWindowsApplications ? 560 : 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (usesWindowsApplications) ...[
                        const Text(
                          'Выбери готовый сервис, установленную программу или сайт. Остальной интернет останется без VPN.',
                        ),
                        const SizedBox(height: 16),
                      ],
                      ...[
                        Text(
                          'Готовые сервисы',
                          style: Theme.of(ctx).textTheme.labelLarge,
                        ),
                        ...SocialApp.values.map((app) {
                          return CheckboxListTile(
                            value: tempPresets.contains(app),
                            onChanged: (v) {
                              setLocal(() {
                                if (v == true) {
                                  tempPresets.add(app);
                                } else {
                                  tempPresets.remove(app);
                                }
                              });
                            },
                            title: Text(app.title),
                            secondary: Icon(app.icon, color: kBrandPrimary),
                            controlAffinity: ListTileControlAffinity.trailing,
                            contentPadding: EdgeInsets.zero,
                          );
                        }),
                      ],
                      if (tempCustomPackages.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Добавленные',
                          style: Theme.of(ctx).textTheme.labelLarge,
                        ),
                        ...sortedCustomPackages.map(
                          (packageName) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.apps_rounded),
                            title: Text(
                              _androidInstalledAppLabels[packageName] ??
                                  packageName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'Убрать',
                              onPressed: () => setLocal(
                                () => tempCustomPackages.remove(packageName),
                              ),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ),
                      ],
                      if (!kIsWeb && Platform.isAndroid) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final selected = await _openInstalledAppsPicker(
                                  ctx,
                                  tempCustomPackages,
                                );
                                if (selected == null || !ctx.mounted) return;
                                setLocal(() {
                                  tempCustomPackages
                                    ..clear()
                                    ..addAll(selected);
                                });
                              } catch (e) {
                                if (ctx.mounted) {
                                  _toast(
                                    ctx,
                                    'Не удалось открыть список приложений: $e',
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Добавить приложение'),
                          ),
                        ),
                      ],
                      if (usesWindowsApplications) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Мои программы',
                          style: Theme.of(ctx).textTheme.labelLarge,
                        ),
                        ...sortedWindowsApplications.map(
                          (path) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.apps_rounded),
                            title: Text(
                              _windowsInstalledAppLabels[path] ??
                                  windowsApplicationLabel(path),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'Убрать',
                              onPressed: () => setLocal(
                                () => tempWindowsApplications.remove(path),
                              ),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final selected =
                                    await _openWindowsInstalledAppsPicker(
                                      ctx,
                                      tempWindowsApplications,
                                    );
                                if (selected == null || !ctx.mounted) return;
                                setLocal(() {
                                  tempWindowsApplications
                                    ..clear()
                                    ..addAll(selected);
                                });
                              } catch (e) {
                                if (ctx.mounted) {
                                  _toast(
                                    ctx,
                                    'Не удалось открыть список программ: $e',
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.search_rounded),
                            label: const Text('Найти установленную программу'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () async {
                              try {
                                final result = await FilePicker.platform
                                    .pickFiles(
                                      dialogTitle: 'Выбери файл программы',
                                      type: FileType.custom,
                                      allowedExtensions: const ['exe'],
                                      allowMultiple: true,
                                    );
                                if (result == null || !ctx.mounted) return;
                                final pickedPaths = result.paths
                                    .whereType<String>()
                                    .map((value) => value.trim())
                                    .where(isValidWindowsApplicationPath)
                                    .where((value) => File(value).existsSync())
                                    .toSet();
                                if (pickedPaths.isEmpty) {
                                  _toast(
                                    ctx,
                                    'Не удалось определить программу в выбранном файле.',
                                  );
                                  return;
                                }
                                if (tempWindowsApplications.length +
                                        pickedPaths.length >
                                    maxWindowsVpnApplications) {
                                  _toast(
                                    ctx,
                                    'Можно выбрать не более $maxWindowsVpnApplications приложений.',
                                  );
                                  return;
                                }
                                setLocal(
                                  () => tempWindowsApplications.addAll(
                                    pickedPaths,
                                  ),
                                );
                              } catch (e) {
                                if (ctx.mounted) {
                                  _toast(
                                    ctx,
                                    'Не удалось выбрать приложение: $e',
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('Выбрать файл вручную'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Мои сайты',
                          style: Theme.of(ctx).textTheme.labelLarge,
                        ),
                        ...sortedWindowsSites.map(
                          (site) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.language_rounded),
                            title: Text(
                              site,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'Убрать',
                              onPressed: () =>
                                  setLocal(() => tempWindowsSites.remove(site)),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed:
                                tempWindowsSites.length >= maxWindowsVpnSites
                                ? null
                                : () async {
                                    try {
                                      final site = await _openWindowsSitePicker(
                                        ctx,
                                      );
                                      if (site == null || !ctx.mounted) return;
                                      setLocal(
                                        () => tempWindowsSites.add(site),
                                      );
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        _toast(
                                          ctx,
                                          'Не удалось добавить сайт: $e',
                                        );
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Добавить сайт'),
                          ),
                        ),
                      ],
                    ],
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
                    if (usesWindowsApplications &&
                        tempPresets.isEmpty &&
                        tempWindowsApplications.isEmpty &&
                        tempWindowsSites.isEmpty) {
                      _toast(ctx, 'Выбери сервис, программу или сайт.');
                      return;
                    }
                    if (!usesWindowsApplications &&
                        tempPresets.isEmpty &&
                        tempCustomPackages.isEmpty) {
                      _toast(
                        ctx,
                        usesApplications
                            ? 'Выбери хотя бы одно приложение.'
                            : 'Выбери хотя бы один сервис.',
                      );
                      return;
                    }
                    Navigator.of(ctx).pop(true);
                  },
                  child: const Text('Готово'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != true || !context.mounted) return;
    await _commitSocialOnlySelection(
      context: context,
      presets: tempPresets,
      androidPackages: tempCustomPackages,
      windowsApplications: tempWindowsApplications,
      windowsSites: tempWindowsSites,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prefsDebounce?.cancel();
    _tariffDebounce?.cancel();
    _vpnTapCooldownTimer?.cancel();
    _pendingBillingPollTimer?.cancel();
    _freeAdSessionTimer?.cancel();
    _vpnPauseTimer?.cancel();
    _connectionUiTimer?.cancel();
    _windowsStatusReconciliationTimer?.cancel();
    _disarmWindowsRuntimeFailover(reason: 'dispose');
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

  Future<void> _checkRequiredUpdateSilently() async {
    if (!kSelfUpdateEnabled) return;
    if (_updateCheckBusy || _forcedUpdateRouteOpen) return;
    if (kIsWeb) return;

    _updateCheckBusy = true;
    try {
      String? clientId;
      try {
        clientId = await _deviceStore.getOrCreate();
      } catch (_) {
        clientId = null;
      }

      final res = await _api.fetchUpdateManifest(
        platform: greenVpnClientPlatform(),
        channel: greenVpnUpdateChannel(),
        currentVersion: kAppVersion,
        clientId: clientId,
      );
      final manifest = res.data;
      if (!mounted ||
          !res.ok ||
          manifest == null ||
          !manifest.hasUpdate ||
          !greenVpnUpdateManifestMatchesCurrentPlatform(manifest)) {
        return;
      }

      if (await _isUpdatePromptDismissed(manifest)) return;
      await _openForcedUpdateRoute(manifest);
    } finally {
      _updateCheckBusy = false;
    }
  }

  String _updatePromptDismissKey(GreenVpnUpdateManifest manifest) {
    return 'greenvpn.update_prompt.dismissed.'
        '${manifest.platform}.${greenVpnUpdateChannel()}';
  }

  Future<bool> _isUpdatePromptDismissed(GreenVpnUpdateManifest manifest) async {
    if (!greenVpnUpdatePromptCanBeDismissed(manifest)) return false;
    if (manifest.latestVersion.trim().isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_updatePromptDismissKey(manifest)) ==
        manifest.latestVersion.trim();
  }

  Future<void> _dismissUpdatePrompt(GreenVpnUpdateManifest manifest) async {
    if (!greenVpnUpdatePromptCanBeDismissed(manifest)) return;
    final latest = manifest.latestVersion.trim();
    if (latest.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_updatePromptDismissKey(manifest), latest);
  }

  Future<void> _openForcedUpdateRoute(GreenVpnUpdateManifest manifest) async {
    if (_forcedUpdateRouteOpen || !mounted) return;
    if (_updatePromptVersionInFlight == manifest.latestVersion) return;
    _forcedUpdateRouteOpen = true;
    _updatePromptVersionInFlight = manifest.latestVersion;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          final platformTitle = manifest.platform == 'android'
              ? 'Android'
              : manifest.platform == 'windows'
              ? 'Windows'
              : manifest.platform.toUpperCase();
          final displayedVersion = kPublicProductBuild
              ? greenVpnPublicVersionTitle(manifest.latestVersion)
              : manifest.latestVersion;
          final displayedChangelog = kPublicProductBuild
              ? greenVpnPublicChangelog(manifest.changelog)
              : manifest.changelog;
          return PopScope(
            canPop: greenVpnUpdatePromptCanBeDismissed(manifest),
            child: Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                  Icons.system_update_alt_rounded,
                                  color: kBrandPrimary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      manifest.required
                                          ? 'Важное обновление'
                                          : 'Доступно обновление',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$platformTitle · $displayedVersion',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.62),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            manifest.required
                                ? 'Чтобы продолжить пользоваться Green VPN, установите это обновление.'
                                : 'Можно продолжить пользоваться приложением, но лучше поставить свежую версию.',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.72,
                              ),
                              fontWeight: FontWeight.w600,
                              height: 1.28,
                            ),
                          ),
                          if (displayedChangelog.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            for (final item in displayedChangelog.take(3))
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
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kBrandPrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: !manifest.canDownload
                                ? null
                                : () {
                                    Navigator.of(dialogContext).pop();
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => UpdatesPage(
                                          initialManifest: manifest,
                                          autoStart: true,
                                          forceRequired: manifest.required,
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Обновить'),
                          ),
                        ],
                      ),
                    ),
                    if (greenVpnUpdatePromptCanBeDismissed(manifest))
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          tooltip: 'Закрыть',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          onPressed: () async {
                            await _dismissUpdatePrompt(manifest);
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _forcedUpdateRouteOpen = false;
      _updatePromptVersionInFlight = null;
    }
  }

  void _openDiagnosticsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiagnosticsPage(
          accessToken: widget.session.accessToken,
          email: widget.session.email,
          windowsFullTunnelDataPlaneConfirmed:
              _windowsFullTunnelDataPlaneConfirmed,
        ),
      ),
    );
  }

  List<String> _selectedTrafficTitles() {
    final titles = <String>[
      ...socialOnlyApps.map((app) => app.title),
      if (!kIsWeb && Platform.isAndroid)
        ...socialOnlyCustomPackages.map(
          (packageName) =>
              _androidInstalledAppLabels[packageName] ?? packageName,
        ),
      if (!kIsWeb && Platform.isWindows)
        ...socialOnlyWindowsApplications.map(
          (path) =>
              _windowsInstalledAppLabels[path] ?? windowsApplicationLabel(path),
        ),
      if (!kIsWeb && Platform.isWindows) ...socialOnlyWindowsSites,
    ];
    titles.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return titles;
  }

  Future<void> _toggleSocialOnlyMode(bool enabled) async {
    if (_vpnInteractionLocked) return;
    if (enabled == socialOnlyEnabled) return;
    if (!_hasPaidSubscriptionEntitlement) {
      _openTariff();
      _toast(context, 'Режим «Только выбранное» доступен по подписке.');
      return;
    }

    final noSelection =
        socialOnlyApps.isEmpty &&
        socialOnlyCustomPackages.isEmpty &&
        socialOnlyWindowsApplications.isEmpty &&
        socialOnlyWindowsSites.isEmpty;
    final shouldOpenPicker =
        enabled &&
        noSelection &&
        !kIsWeb &&
        (Platform.isWindows || (kFusionUiEnabled && Platform.isAndroid));
    if (shouldOpenPicker) {
      await _openSocialAppsPicker(context);
      if (!mounted || _selectedTrafficTitles().isEmpty) return;
    }

    final previous = _captureRoutingPreference();
    final wasConnected = vpnEnabled;
    await appendBlueVpnClientLog(
      'routing preference requested from=${previous.socialOnlyEnabled ? "applications" : "full"} to=${enabled ? "applications" : "full"} connected=$wasConnected',
    );
    _prefsDebounce?.cancel();
    setState(() {
      vpnBusy = true;
      _vpnBusyStage = 'Обновляем режим...';
      _vpnBusyHint =
          'Пересобираем конфиг и аккуратно применяем новый режим трафика.';
      socialOnlyEnabled = enabled;
      _socialOnlyPreferenceRequested = enabled;
    });

    try {
      final applied = await _applyCurrentConfigMode(
        reconnectIfNeeded: true,
        showToastOnSuccess: true,
      );
      if (!applied) {
        throw StateError('Новый режим не был подтверждён системой.');
      }
      _schedulePrefsSave();
      await appendBlueVpnClientLog(
        'routing preference confirmed mode=${enabled ? "applications" : "full"} connected=$vpnEnabled protected=$_windowsProtectionConfirmed',
      );
    } catch (e) {
      await appendBlueVpnClientLog(
        'routing preference apply failed requested=${enabled ? "applications" : "full"} type=${e.runtimeType}',
      );
      final restored = await _restoreRoutingPreferenceAfterFailure(
        snapshot: previous,
        wasConnected: wasConnected,
      );
      if (mounted) {
        _toast(
          context,
          restored
              ? '${e.toString().replaceFirst('Bad state: ', '')} Предыдущий режим восстановлен.'
              : '${e.toString().replaceFirst('Bad state: ', '')} Не удалось восстановить режим; фактическое состояние показано на главном экране.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          vpnBusy = false;
          _vpnBusyStage = null;
          if (!_vpnTapCooldown) _vpnBusyHint = null;
        });
      }
    }
  }

  Future<void> _configureSocialOnlyTraffic() async {
    if (_vpnInteractionLocked) return;
    if (!_hasPaidSubscriptionEntitlement) {
      _openTariff();
      _toast(context, 'Выбор приложений и сайтов доступен по подписке.');
      return;
    }
    await _openSocialAppsPicker(context);
  }

  Widget _buildTariffPage({VoidCallback? refresh}) {
    void changed(VoidCallback callback) {
      callback();
      refresh?.call();
    }

    Future<void> changedAsync(Future<void> Function() callback) async {
      await callback();
      refresh?.call();
    }

    return TariffPage(
      planName: _paidSubscriptionPlanName ?? planName,
      freeTierActive: _freeTierActive,
      trafficUsage: _trafficUsage,
      isGuest: widget.session.isGuest,
      onRestoreAccess: () => unawaited(changedAsync(_openRestoreAccess)),
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
      subscriptionActive: _paidSubscriptionActive,
      subscriptionAutoRenew: _subscriptionAutoRenew,
      subscriptionMaxDevices: _subscriptionMaxDevices,
      subscriptionAccessStartsAt: _subscriptionAccessStartsAt,
      subscriptionExpiresAt: _subscriptionExpiresAt,
      subscriptionStatus: _paidSubscriptionStatus,
      subscriptionRevision: _subscriptionRevision,
      subscriptionMonthlyPriceRub: _subscriptionMonthlyPriceRub,
      publicBillingPlanCode: _publicBillingPlanCode,
      tariffBusy: _tariffBusy,
      onClaimPaidBetaInvite: () => changedAsync(_claimPaidBetaInvite),
      onApplyTariff: (autoRenew, renewalAcknowledged) => changedAsync(
        () => _createTariffOrderOnServer(
          autoRenew: autoRenew,
          renewalAcknowledged: renewalAcknowledged,
        ),
      ),
      onCheckPendingBillingOrder: () =>
          changedAsync(() => _checkPendingBillingOrder(showToast: true)),
      onOpenPaymentUrl: _openPaymentUrl,
      onPublicBillingPlanChanged: (code) => changed(() {
        setState(() {
          _publicBillingPlanCode = code;
          _tariffQuote = null;
          _tariffBusy = true;
        });
        _scheduleTariffRefresh();
      }),
      onToggleApp: (app) => changed(() {
        setState(() {
          if (selectedApps.contains(app)) {
            selectedApps.remove(app);
          } else {
            selectedApps.add(app);
          }
        });
        _schedulePrefsSave();
        _scheduleTariffRefresh();
      }),
      onTrafficChanged: (pack) => changed(() {
        setState(() => trafficPack = pack);
        _schedulePrefsSave();
        _scheduleTariffRefresh();
      }),
      onTrafficGbChanged: (gb) => changed(() {
        setState(() => trafficGb = gb);
        _schedulePrefsSave();
        _scheduleTariffRefresh();
      }),
      onDevicesChanged: (value) => changed(() {
        setState(() => devices = value.clamp(1, 5));
        _schedulePrefsSave();
        _scheduleTariffRefresh();
      }),
      onOptNoAds: (_) => changed(() {
        setState(() => optNoAds = true);
        _schedulePrefsSave();
      }),
      onOptSmartRouting: (_) => changed(() {
        setState(() => optSmartRouting = true);
        _schedulePrefsSave();
      }),
      onOptDedicatedIp: (value) => changed(() {
        setState(() => optDedicatedIp = value);
        _schedulePrefsSave();
        _scheduleTariffRefresh();
      }),
      onCancelAutoRenew: () async {
        final pending = _cancelAutoRenew();
        refresh?.call();
        try {
          return await pending;
        } finally {
          refresh?.call();
        }
      },
      onOptAutoRenew: (value) => changed(() {
        setState(() => optAutoRenew = value);
        _schedulePrefsSave();
        _scheduleTariffRefresh();
      }),
    );
  }

  void _openTariff() {
    if (!kFusionUiEnabled) {
      goToTab(1);
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (routeContext) => Scaffold(
            appBar: AppBar(title: const Text('Тариф')),
            body: StatefulBuilder(
              builder: (routeContext, setRouteState) {
                return _DesktopShellBody(
                  child: _buildTariffPage(
                    refresh: () {
                      if (routeContext.mounted) setRouteState(() {});
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleFusionUiDiagnostic();
    final wireGuardState = _wireGuardState;
    final pages = <Widget>[
      VpnPage(
        planName: planName,
        freeTierActive: _freeTierActive,
        trafficUsage: _trafficUsage,
        isGuest: widget.session.isGuest,
        onRestoreAccess: () => unawaited(_openRestoreAccess()),
        vpnEnabled: vpnEnabled,
        windowsProtectionConfirmed:
            kIsWeb || !Platform.isWindows || _windowsProtectionConfirmed,
        externalVpnActive: _externalVpnActive,
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
              'Сначала установи системный компонент. После этого кнопка VPN заработает.',
            );
            return;
          }
          if (_vpnPausePending) {
            unawaited(_resumeVpnAfterPause(automatic: false));
          } else {
            unawaited(_toggleVpnReal());
          }
        },
        connectionActionsEnabled: _clientFeatureEnabled(
          kFusionConnectionActionsFlag,
        ),
        connectionDetailsEnabled: _clientFeatureEnabled(
          kFusionConnectionDetailsFlag,
        ),
        vpnPaused: _vpnPausePending,
        vpnPausedUntil: _vpnPausedUntil,
        onOpenPause: () => unawaited(_openVpnPauseMenu()),
        onChangeRoute: () => unawaited(_changeRouteAutomatically()),
        activeConnectionRoute: _activeConnectionRoute,
        connectionStartedAt: _connectionStartedAt,
        connectionLatencyMs: _activeConnectionLatencyMs,

        // Сервер
        selectedServer: selectedServer,
        onOpenServerPicker: () => _openServerPicker(context),

        // Соцсети
        socialOnlyEnabled: socialOnlyEnabled,
        socialOnlyAllowed: _hasPaidSubscriptionEntitlement,
        socialOnlyApps: socialOnlyApps,
        socialOnlyCustomPackages: socialOnlyCustomPackages,
        socialOnlyWindowsApplications: socialOnlyWindowsApplications,
        socialOnlyWindowsSites: socialOnlyWindowsSites,
        socialOnlyCustomLabels: _androidInstalledAppLabels,
        socialOnlyWindowsApplicationLabels: _windowsInstalledAppLabels,
        onToggleSocialOnly: _toggleSocialOnlyMode,
        onConfigureSocialApps: _configureSocialOnlyTraffic,
        onOpenDiagnostics: _openDiagnosticsPage,
        onOpenTariff: _openTariff,
      ),

      kFusionUiEnabled
          ? FusionModePage(
              allowed: _hasPaidSubscriptionEntitlement,
              selectedTitles: _selectedTrafficTitles(),
              onConfigure: _configureSocialOnlyTraffic,
              onOpenTariff: _openTariff,
            )
          : _buildTariffPage(),

      SettingsPage(
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        language: sLanguage,
        onPickLanguage: () => _pickOne(
          context,
          title: 'Язык',
          current: sLanguage,
          items: const ['Русский'],
          onSelect: _setLanguage,
        ),
        email: widget.session.email,
        isGuest: widget.session.isGuest,
        emailVerified: _emailVerified,
        emailConfirmationRequired: _emailConfirmationRequired,
        emailStatusBusy: _emailStatusBusy,
        emailStatusMessage: _emailStatusMessage,
        onResendEmailConfirmation: _resendEmailConfirmation,
        onRefreshEmailStatus: () => _refreshEmailStatus(showToast: true),
        hasPaidEntitlement: _hasPaidSubscriptionEntitlement,
        subscriptionAutoRenew: _subscriptionAutoRenew,
        paymentMethodSaved: _paymentMethodSaved,
        onOpenTariff: _openTariff,
        onRestoreAccess: () => unawaited(_openRestoreAccess()),
        onCancelAutoRenew: _cancelAutoRenew,
        onLogout: widget.onLogout,
        onOpenUpdates: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const UpdatesPage()));
        },
        onOpenDiagnostics: _openDiagnosticsPage,
        showWindowsCloseBehavior:
            !kIsWeb &&
            Platform.isWindows &&
            _clientFeatureEnabled(kFusionWindowsCloseBehaviorFlag),
        windowsCloseBehavior: _windowsCloseBehavior,
        onPickWindowsCloseBehavior: () => _pickOne(
          context,
          title: 'Закрытие окна',
          current: _windowsCloseBehavior.title,
          items: WindowsCloseBehavior.values
              .map((item) => item.title)
              .toList(growable: false),
          onSelect: (title) {
            final selected = WindowsCloseBehavior.values.firstWhere(
              (item) => item.title == title,
              orElse: () => WindowsCloseBehavior.minimizeToTray,
            );
            unawaited(_setWindowsCloseBehavior(selected));
          },
        ),
      ),
    ];
    final currentIndex = _index.clamp(0, pages.length - 1).toInt();

    return Scaffold(
      body: _DesktopShellBody(child: pages[currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
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
            icon: Icon(
              kFusionUiEnabled ? Icons.route_rounded : Icons.star_rounded,
            ),
            label: kFusionUiEnabled
                ? 'Выбранное'
                : kStoreDistributionBuild
                ? 'Доступ'
                : kTrialOnlyNoAdsBuild
                ? 'Trial'
                : 'Тариф',
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
              separatorBuilder: (_, _) => const SizedBox(height: 10),
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
                                ).colorScheme.onSurface.withValues(alpha: 0.35),
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

class FusionModePage extends StatelessWidget {
  final bool allowed;
  final List<String> selectedTitles;
  final VoidCallback onConfigure;
  final VoidCallback onOpenTariff;

  const FusionModePage({
    super.key,
    required this.allowed,
    required this.selectedTitles,
    required this.onConfigure,
    required this.onOpenTariff,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.62);

    return ListView(
      key: const Key('fusion_mode_page'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Выбранные приложения и сайты',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(
          'Настройте список для режима «Только выбранное».',
          style: TextStyle(color: muted, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD7E3DC)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Текущий список',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    '${selectedTitles.length}',
                    style: const TextStyle(
                      color: kBrandPrimaryDeep,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (selectedTitles.isEmpty)
                Text(
                  'Список пока пуст.',
                  style: TextStyle(color: muted, fontWeight: FontWeight.w700),
                )
              else
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final title in selectedTitles.take(12))
                      Chip(label: Text(title)),
                    if (selectedTitles.length > 12)
                      Chip(label: Text('+${selectedTitles.length - 12}')),
                  ],
                ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                key: const Key('fusion_mode_configure_button'),
                onPressed: allowed ? onConfigure : onOpenTariff,
                icon: Icon(
                  allowed ? Icons.add_rounded : Icons.lock_outline_rounded,
                ),
                label: Text(allowed ? 'Настроить список' : 'Открыть тарифы'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* =========================
   VPN PAGE
   ========================= */

class VpnPage extends StatelessWidget {
  final String planName;
  final bool freeTierActive;
  final Map<String, dynamic> trafficUsage;
  final bool isGuest;
  final VoidCallback? onRestoreAccess;
  final bool vpnEnabled;
  final bool windowsProtectionConfirmed;
  final bool externalVpnActive;
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
  final bool connectionActionsEnabled;
  final bool connectionDetailsEnabled;
  final bool vpnPaused;
  final DateTime? vpnPausedUntil;
  final VoidCallback? onOpenPause;
  final VoidCallback? onChangeRoute;
  final ServerLocation? activeConnectionRoute;
  final DateTime? connectionStartedAt;
  final int? connectionLatencyMs;
  final VoidCallback onOpenTariff;
  final VoidCallback? onOpenDiagnostics;
  final ServerLocation selectedServer;
  final VoidCallback onOpenServerPicker;
  final bool socialOnlyEnabled;
  final bool socialOnlyAllowed;
  final Set<SocialApp> socialOnlyApps;
  final Set<String> socialOnlyCustomPackages;
  final Set<String> socialOnlyWindowsApplications;
  final Set<String> socialOnlyWindowsSites;
  final Map<String, String> socialOnlyCustomLabels;
  final Map<String, String> socialOnlyWindowsApplicationLabels;
  final ValueChanged<bool> onToggleSocialOnly;
  final VoidCallback onConfigureSocialApps;

  const VpnPage({
    super.key,
    required this.planName,
    this.freeTierActive = false,
    this.trafficUsage = const <String, dynamic>{},
    this.isGuest = false,
    this.onRestoreAccess,
    required this.vpnEnabled,
    this.windowsProtectionConfirmed = true,
    required this.externalVpnActive,
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
    this.connectionActionsEnabled = false,
    this.connectionDetailsEnabled = false,
    this.vpnPaused = false,
    this.vpnPausedUntil,
    this.onOpenPause,
    this.onChangeRoute,
    this.activeConnectionRoute,
    this.connectionStartedAt,
    this.connectionLatencyMs,
    required this.onOpenTariff,
    this.onOpenDiagnostics,
    required this.selectedServer,
    required this.onOpenServerPicker,
    required this.socialOnlyEnabled,
    required this.socialOnlyAllowed,
    required this.socialOnlyApps,
    required this.socialOnlyCustomPackages,
    required this.socialOnlyWindowsApplications,
    required this.socialOnlyWindowsSites,
    required this.socialOnlyCustomLabels,
    required this.socialOnlyWindowsApplicationLabels,
    required this.onToggleSocialOnly,
    required this.onConfigureSocialApps,
  });

  @override
  Widget build(BuildContext context) {
    if (kFusionUiEnabled) return _buildFusion(context);
    return _buildLegacy(context);
  }

  Widget _buildFusion(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = textColor.withValues(alpha: isDark ? 0.72 : 0.62);
    final usesAndroidApplications = !kIsWeb && Platform.isAndroid;
    final usesWindowsApplications = !kIsWeb && Platform.isWindows;
    final selectedTitles = <String>[
      ...socialOnlyApps.map((app) => app.title),
      if (usesAndroidApplications)
        ...socialOnlyCustomPackages.map(
          (packageName) => socialOnlyCustomLabels[packageName] ?? packageName,
        ),
      if (usesWindowsApplications)
        ...socialOnlyWindowsApplications.map(
          (path) =>
              socialOnlyWindowsApplicationLabels[path] ??
              windowsApplicationLabel(path),
        ),
      if (usesWindowsApplications) ...socialOnlyWindowsSites,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final paused = vpnPaused && !vpnEnabled;
    final connectionPresentation = greenVpnFusionConnectionPresentation(
      vpnEnabled: vpnEnabled,
      windowsProtectionConfirmed: windowsProtectionConfirmed,
      externalVpnActive: externalVpnActive,
      socialOnlyEnabled: socialOnlyEnabled,
      vpnBusy: vpnBusy,
      vpnBusyStage: vpnBusyStage,
      vpnBusyHint: vpnBusyHint,
      paused: paused,
      pausedUntil: vpnPausedUntil,
    );
    final protectionActive = connectionPresentation.protectionActive;
    final statusText = connectionPresentation.statusText;
    final statusDetail = connectionPresentation.statusDetail;
    final displayedRoute = vpnEnabled && activeConnectionRoute != null
        ? activeConnectionRoute!
        : selectedServer;
    final serverTitle = displayedRoute.isAuto
        ? 'Самая быстрая локация'
        : greenVpnPublicServerTitle(displayedRoute);
    final serverSubtitle = greenVpnPublicServerSubtitle(displayedRoute);
    final displayedPlanName = isGuest
        ? 'Бесплатный'
        : kPublicProductBuild
        ? greenVpnPublicPlanTitle(planName)
        : planName;
    final freeUsageSummary = freeTierActive
        ? greenVpnTrafficUsageSummary(trafficUsage)
        : null;

    Widget surface({required Widget child, EdgeInsetsGeometry? padding}) {
      return Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF10271F) : const Color(0xFFF9FCFA),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : const Color(0xFFD7E3DC),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      );
    }

    Widget compactActionButton({
      required Key buttonKey,
      required VoidCallback? onPressed,
      required IconData icon,
      required String label,
    }) {
      return OutlinedButton(
        key: buttonKey,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, softWrap: false),
              ),
            ),
          ],
        ),
      );
    }

    Widget connectionPanel() {
      final powerColor = paused
          ? kBrandWarm
          : externalVpnActive
          ? kBrandWarm
          : protectionActive
          ? kBrandPrimaryDeep
          : kBrandPrimary;
      return surface(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: protectionActive
                              ? kBrandPrimarySoft
                              : paused
                              ? const Color(0xFFFFF4D6)
                              : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : const Color(0xFFEEF3F0)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          connectionPresentation.badgeText,
                          style: TextStyle(
                            color: protectionActive
                                ? kBrandPrimaryDeep
                                : paused
                                ? const Color(0xFF9A6700)
                                : mutedColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          if (connectionPresentation.connectedCheckVisible) ...[
                            Container(
                              key: const Key('fusion_connected_check_icon'),
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                color: kBrandPrimary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 9),
                          ],
                          Expanded(
                            child: Text(
                              statusText,
                              key: const Key('fusion_connection_status'),
                              style: TextStyle(
                                color: protectionActive && !vpnBusy
                                    ? kBrandPrimaryDeep
                                    : textColor,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        statusDetail,
                        style: TextStyle(
                          color: mutedColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Semantics(
                  button: true,
                  label: vpnEnabled
                      ? 'Отключить VPN'
                      : paused
                      ? 'Возобновить VPN'
                      : 'Подключить VPN',
                  child: InkWell(
                    key: const Key('fusion_connect_button'),
                    onTap: wireGuardInstalled && !vpnInteractionLocked
                        ? onToggleVpn
                        : null,
                    borderRadius: BorderRadius.circular(56),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 94,
                      height: 94,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: powerColor.withValues(alpha: 0.12),
                        border: Border.all(
                          color: powerColor.withValues(alpha: 0.42),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: powerColor,
                          ),
                          child: vpnBusy
                              ? const Padding(
                                  padding: EdgeInsets.all(21),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  vpnEnabled
                                      ? Icons.stop_rounded
                                      : paused
                                      ? Icons.play_arrow_rounded
                                      : Icons.power_settings_new_rounded,
                                  color: Colors.white,
                                  size: 31,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            InkWell(
              key: const Key('fusion_location_button'),
              onTap: onOpenServerPicker,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF1F6F3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFD7E3DC),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDF1F4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          displayedRoute.isAuto
                              ? 'A'
                              : serverTitle.characters.first,
                          style: const TextStyle(
                            color: Color(0xFF087A8C),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              serverTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (serverSubtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                serverSubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: mutedColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (displayedRoute.isAuto &&
                          constraints.maxWidth >= 360) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: kBrandPrimarySoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'АВТО',
                            style: TextStyle(
                              color: kBrandPrimaryDeep,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded, color: mutedColor),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (connectionActionsEnabled && vpnEnabled) ...[
              Row(
                children: [
                  Expanded(
                    child: compactActionButton(
                      buttonKey: const Key('fusion_pause_button'),
                      onPressed: vpnInteractionLocked ? null : onOpenPause,
                      icon: Icons.timer_outlined,
                      label: 'Пауза',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: compactActionButton(
                      buttonKey: const Key('fusion_change_route_button'),
                      onPressed: vpnInteractionLocked ? null : onChangeRoute,
                      icon: Icons.sync_alt_rounded,
                      label: 'Сменить подключение',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: compactActionButton(
                    buttonKey: const Key('fusion_diagnostics_button'),
                    onPressed: onOpenDiagnostics,
                    icon: Icons.health_and_safety_outlined,
                    label: 'Диагностика',
                  ),
                ),
                if (protectionActive && connectionDetailsEnabled) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: compactActionButton(
                      buttonKey: const Key('fusion_details_button'),
                      onPressed: () => _showFusionConnectionDetails(
                        context,
                        serverTitle: serverTitle,
                        modeTitle: socialOnlyEnabled
                            ? 'Только выбранное'
                            : 'Весь интернет',
                        connectedAt: connectionStartedAt,
                        latencyMs: connectionLatencyMs,
                        trafficUsage: trafficUsage,
                      ),
                      icon: Icons.info_outline_rounded,
                      label: 'Детали',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    Widget modePanel() {
      final selectedCount = selectedTitles.length;
      return surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'РЕЖИМ ЗАЩИТЫ',
                        style: TextStyle(
                          color: kBrandMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Что направить через VPN',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.tune_rounded, color: kBrandPrimary),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFEEF3F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _FusionModeChoice(
                      key: const Key('fusion_mode_full'),
                      selected: !socialOnlyEnabled,
                      icon: Icons.public_rounded,
                      label: 'Весь интернет',
                      onTap: () => onToggleSocialOnly(false),
                    ),
                  ),
                  Expanded(
                    child: _FusionModeChoice(
                      key: const Key('fusion_mode_selected'),
                      selected: socialOnlyEnabled,
                      icon: socialOnlyAllowed
                          ? Icons.auto_awesome_rounded
                          : Icons.lock_outline_rounded,
                      label: 'Только выбранное',
                      onTap: () => onToggleSocialOnly(true),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : const Color(0xFFF4F8F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFD7E3DC),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        socialOnlyEnabled
                            ? Icons.auto_awesome_rounded
                            : Icons.public_rounded,
                        color: kBrandPrimary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              protectionActive
                                  ? (socialOnlyEnabled
                                        ? 'Только выбранное защищено'
                                        : 'Весь интернет защищён')
                                  : (socialOnlyEnabled
                                        ? 'Будут защищены выбранные'
                                        : 'Будет защищён весь интернет'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              protectionActive
                                  ? (socialOnlyEnabled
                                        ? 'Через VPN направляется: $selectedCount.'
                                        : 'Трафик всего устройства проходит через VPN.')
                                  : (socialOnlyEnabled
                                        ? 'Выбрано: $selectedCount. Включите VPN, чтобы применить режим.'
                                        : 'Включите VPN, чтобы защитить трафик устройства.'),
                              style: TextStyle(
                                color: mutedColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (socialOnlyEnabled) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('fusion_configure_selected_button'),
                      onPressed: onConfigureSocialApps,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(
                        usesWindowsApplications
                            ? 'Выбрать программы и сайты'
                            : 'Выбрать приложения',
                      ),
                    ),
                    if (selectedTitles.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: selectedTitles.take(5).map((title) {
                          return Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(title, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF123126)
                    : const Color(0xFFEAF7F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    protectionActive
                        ? Icons.shield_rounded
                        : Icons.radar_rounded,
                    color: kBrandPrimary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          protectionActive
                              ? 'Подключение контролируется'
                              : vpnEnabled
                              ? 'Подтверждаем подключение'
                              : 'Автовыбор готов к запуску',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          protectionActive
                              ? 'При сбое Green VPN выполнит безопасное переключение.'
                              : vpnEnabled
                              ? 'Защита появится после подтверждения фактического режима.'
                              : 'Подключится первый доступный вариант.',
                          style: TextStyle(
                            color: mutedColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              key: const Key('fusion_tariff_button'),
              onTap: onOpenTariff,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2D291D)
                      : const Color(0xFFFFF8E9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF655A39)
                        : const Color(0xFFE8D3A5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFB7791F)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayedPlanName,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            freeUsageSummary ?? 'Открыть управление тарифом',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mutedColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: mutedColor),
                  ],
                ),
              ),
            ),
            if (!kStoreDistributionBuild &&
                isGuest &&
                onRestoreAccess != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('restore_access_home'),
                onPressed: onRestoreAccess,
                icon: const Icon(Icons.login_rounded),
                label: const Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Уже есть подписка?',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text('Войти по email', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return ListView(
          key: const Key('fusion_vpn_page'),
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: kBrandPrimaryDeep,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.shield_outlined, color: Colors.white),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Green VPN',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onOpenTariff,
                  icon: const Icon(Icons.star_outline_rounded, size: 18),
                  label: Text(displayedPlanName),
                ),
              ],
            ),
            if (!wireGuardInstalled) ...[
              const SizedBox(height: 12),
              _WireGuardSetupCard(
                title: 'Установите системный компонент перед подключением',
                subtitle:
                    wireGuardStatusText ??
                    'Green VPN установит компонент, необходимый для подключения.',
                busy: wireGuardBusy,
                onInstall: onInstallWireGuard,
                onRefresh: onRefreshWireGuard,
              ),
            ],
            const SizedBox(height: 14),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: connectionPanel()),
                  const SizedBox(width: 12),
                  Expanded(flex: 4, child: modePanel()),
                ],
              )
            else ...[
              connectionPanel(),
              const SizedBox(height: 12),
              modePanel(),
            ],
          ],
        );
      },
    );
  }

  static String _formatConnectionDuration(DateTime? connectedAt) {
    if (connectedAt == null) return 'Определяется...';
    final elapsed = DateTime.now().difference(connectedAt);
    final safeSeconds = max(0, elapsed.inSeconds);
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds % 3600) ~/ 60;
    final seconds = safeSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _showFusionConnectionDetails(
    BuildContext context, {
    required String serverTitle,
    required String modeTitle,
    required DateTime? connectedAt,
    required int? latencyMs,
    required Map<String, dynamic> trafficUsage,
  }) async {
    final trafficSummary = greenVpnTrafficUsageSummary(trafficUsage);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Детали соединения',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              const _FusionDetailRow(
                label: 'Состояние',
                value: '✓ Защита активна',
              ),
              _FusionDetailRow(label: 'Локация', value: serverTitle),
              _FusionDetailRow(label: 'Режим', value: modeTitle),
              _FusionDetailRow(
                label: 'Время подключения',
                value: _formatConnectionDuration(connectedAt),
              ),
              _FusionDetailRow(
                label: 'Задержка',
                value: latencyMs == null ? 'Определяется...' : '$latencyMs мс',
              ),
              _FusionDetailRow(label: 'Трафик за месяц', value: trafficSummary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegacy(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = textColor.withValues(alpha: isDark ? 0.72 : 0.62);
    final usesAndroidApplications = !kIsWeb && Platform.isAndroid;
    final usesWindowsApplications = !kIsWeb && Platform.isWindows;
    final usesApplications = usesAndroidApplications || usesWindowsApplications;
    final statusText = vpnBusy
        ? (vpnBusyStage ?? (vpnEnabled ? 'Отключаем...' : 'Подключаем...'))
        : (vpnEnabled
              ? 'Включено'
              : (externalVpnActive ? 'Другой VPN активен' : 'Отключено'));
    final serverTitle = selectedServer.isAuto
        ? 'Самая быстрая локация'
        : greenVpnPublicServerTitle(selectedServer);
    final serverSub = greenVpnPublicServerSubtitle(selectedServer);
    final selectedAppTitles = <String>[
      ...socialOnlyApps.map((app) => app.title),
      if (usesAndroidApplications)
        ...socialOnlyCustomPackages.map(
          (packageName) => socialOnlyCustomLabels[packageName] ?? packageName,
        ),
      if (usesWindowsApplications)
        ...socialOnlyWindowsApplications.map(
          (path) =>
              socialOnlyWindowsApplicationLabels[path] ??
              windowsApplicationLabel(path),
        ),
      if (usesWindowsApplications) ...socialOnlyWindowsSites,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final appsText = selectedAppTitles.isEmpty
        ? 'Не выбрано'
        : selectedAppTitles.join(', ');
    final displayedPlanName = isGuest
        ? 'Бесплатный'
        : kPublicProductBuild
        ? greenVpnPublicPlanTitle(planName)
        : planName;
    final freeUsageSummary = freeTierActive
        ? greenVpnTrafficUsageSummary(trafficUsage)
        : null;
    final freeUsageProgress = freeTierActive
        ? greenVpnTrafficUsageProgress(trafficUsage)
        : null;

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
                    Text(
                      kStoreDistributionBuild ? 'Доступ' : 'Тариф',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      freeUsageSummary ??
                          (kStoreDistributionBuild
                              ? 'Бесплатный VPN без регистрации'
                              : 'Текущий: $displayedPlanName • открыть тариф'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (freeUsageProgress != null) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: freeUsageProgress,
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
        if (!kStoreDistributionBuild && isGuest && onRestoreAccess != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('restore_access_home'),
            onPressed: onRestoreAccess,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.login_rounded),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Уже есть подписка?',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 2),
                      Text('Войти по email', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (!wireGuardInstalled) ...[
          _WireGuardSetupCard(
            title: 'Установи системный компонент перед первым подключением',
            subtitle:
                'Green VPN установит компонент, который нужен для подключения.',
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
                        : (vpnEnabled
                              ? 'Отключить VPN'
                              : (externalVpnActive
                                    ? 'Переключить на Green VPN'
                                    : 'Подключить VPN')),
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
              if (!vpnBusy && externalVpnActive) ...[
                const SizedBox(height: 8),
                Text(
                  'Сейчас Android держит VPN вне Green VPN. Нажми кнопку выше, чтобы переключиться на Green VPN.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
              if (vpnBusy) ...[
                const SizedBox(height: 8),
                Text(
                  vpnBusyHint ??
                      'Подожди пару секунд. Мы уже запускаем VPN и специально блокируем повторные нажатия.',
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
                title: Text(
                  usesApplications
                      ? 'Только для соц. сетей'
                      : 'Только для выбранных сервисов',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  socialOnlyEnabled
                      ? 'Через VPN: $appsText'
                      : (usesWindowsApplications
                            ? 'Выбери сервисы, программы или сайты'
                            : usesApplications
                            ? 'Выбери приложения, которые должны идти через VPN'
                            : 'Выбери сервисы, которые должны идти через VPN'),
                  style: const TextStyle(fontSize: 12),
                ),
                value: socialOnlyEnabled,
                onChanged: onToggleSocialOnly,
                secondary: socialOnlyAllowed
                    ? null
                    : const Icon(Icons.lock_rounded, color: kBrandWarm),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onConfigureSocialApps,
                  icon: Icon(
                    socialOnlyAllowed
                        ? Icons.tune_rounded
                        : Icons.lock_outline_rounded,
                  ),
                  label: Text(
                    !socialOnlyAllowed
                        ? (kStoreDistributionBuild
                              ? 'Недоступно в бесплатной версии'
                              : 'Доступно по подписке')
                        : usesApplications
                        ? (usesWindowsApplications
                              ? 'Выбрать сервисы, программы и сайты'
                              : 'Настроить приложения')
                        : 'Настроить сервисы',
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
                greenVpnSocialOnlyStatusText(
                  allowed: socialOnlyAllowed,
                  enabled: socialOnlyEnabled,
                  usesApplications: usesApplications,
                  usesMixedSelection: usesWindowsApplications,
                  permanentFreeBuild: kStoreDistributionBuild,
                ),
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
                  if (serverSub.isNotEmpty) ...[
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

class _FusionModeChoice extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FusionModeChoice({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 7,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected
                  ? kBrandPrimaryDeep
                  : theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.62),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FusionDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _FusionDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
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
                    busy ? 'Установка…' : 'Установить',
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
  gb20('20 ГБ', 119),
  gb50('50 ГБ', 149),
  gb150('150 ГБ', 199),
  gb350('350 ГБ', 259),
  unlimited('Безлимит', 299);

  const TrafficPack(this.title, this.basePriceRub);
  final String title;
  final int basePriceRub;
}

class TariffPage extends StatelessWidget {
  final String planName;
  final bool freeTierActive;
  final Map<String, dynamic> trafficUsage;
  final bool isGuest;
  final VoidCallback? onRestoreAccess;
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
  final int subscriptionMaxDevices;
  final String? subscriptionAccessStartsAt;
  final String? subscriptionExpiresAt;
  final String subscriptionStatus;
  final int subscriptionRevision;
  final int? subscriptionMonthlyPriceRub;
  final String publicBillingPlanCode;
  final bool tariffBusy;

  final void Function(TariffApp) onToggleApp;
  final void Function(TrafficPack) onTrafficChanged;
  final ValueChanged<double> onTrafficGbChanged;
  final void Function(int) onDevicesChanged;

  final void Function(bool) onOptNoAds;
  final void Function(bool) onOptSmartRouting;
  final void Function(bool) onOptDedicatedIp;
  final void Function(bool) onOptAutoRenew;
  final Future<bool> Function() onCancelAutoRenew;
  final Future<void> Function(bool autoRenew, bool renewalAcknowledged)
  onApplyTariff;
  final Future<void> Function() onClaimPaidBetaInvite;
  final Future<void> Function() onCheckPendingBillingOrder;
  final void Function(String url) onOpenPaymentUrl;
  final ValueChanged<String> onPublicBillingPlanChanged;

  const TariffPage({
    super.key,
    required this.planName,
    this.freeTierActive = false,
    this.trafficUsage = const <String, dynamic>{},
    this.isGuest = false,
    this.onRestoreAccess,
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
    this.subscriptionAutoRenew = false,
    this.subscriptionMaxDevices = 1,
    this.subscriptionAccessStartsAt,
    required this.subscriptionExpiresAt,
    this.subscriptionStatus = 'inactive',
    this.subscriptionRevision = 0,
    required this.subscriptionMonthlyPriceRub,
    required this.publicBillingPlanCode,
    required this.tariffBusy,
    required this.onClaimPaidBetaInvite,
    required this.onToggleApp,
    required this.onTrafficChanged,
    required this.onTrafficGbChanged,
    required this.onDevicesChanged,
    required this.onOptNoAds,
    required this.onOptSmartRouting,
    required this.onOptDedicatedIp,
    required this.onOptAutoRenew,
    required this.onCancelAutoRenew,
    required this.onApplyTariff,
    required this.onCheckPendingBillingOrder,
    required this.onOpenPaymentUrl,
    required this.onPublicBillingPlanChanged,
  });

  Widget _buildRestoreAccessButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Уже оплачивали подписку?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('restore_access_tariff'),
            onPressed: onRestoreAccess,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.login_rounded),
            label: const Text(
              'Войти по email',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmPublicCheckout(
    BuildContext context, {
    required int priceRub,
    required int periodDays,
    required String periodTitle,
    required bool autoRenewAvailable,
    bool? initialAutoRenew,
  }) async {
    final previewRaw = tariffQuote?['purchasePreview'];
    final preview = previewRaw is Map
        ? Map<String, dynamic>.from(previewRaw)
        : const <String, dynamic>{};
    final previewKind = (preview['kind'] ?? '').toString().trim().toLowerCase();
    final requiresAcknowledgement = preview['requiresAcknowledgement'] == true;
    final periodStartsAt = (preview['periodStartsAt'] ?? '').toString().trim();
    final periodEndsAt = (preview['periodEndsAt'] ?? '').toString().trim();
    final isExtension = previewKind == 'extension' && requiresAcknowledgement;
    var autoRenewConsent = initialAutoRenew ?? subscriptionAutoRenew;
    final confirmedAutoRenew = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            isExtension ? 'Продление подписки' : 'Подтверждение оплаты',
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'К оплате: $priceRub ₽ за $periodTitle.',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (subscriptionActive && subscriptionExpiresAt != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Текущий доступ действует до '
                    '${_formatCompactDate(subscriptionExpiresAt!)}.',
                  ),
                ],
                if (periodStartsAt.isNotEmpty && periodEndsAt.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${isExtension ? 'Следующий' : 'Оплачиваемый'} период: '
                    'с ${_formatCompactDate(periodStartsAt)} '
                    'по ${_formatCompactDate(periodEndsAt)}.',
                    key: const Key('checkout_period_preview'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
                if (requiresAcknowledgement) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Оплата не заменит текущий период: новый срок начнётся '
                    'после его окончания.',
                  ),
                ],
                const SizedBox(height: 12),
                if (subscriptionAutoRenew)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.autorenew_rounded),
                    title: Text(
                      'Автопродление уже включено',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      'Ручная оплата добавит отдельный следующий период. '
                      'Автопродление можно отключить в настройках.',
                    ),
                  )
                else if (autoRenewAvailable)
                  CheckboxListTile(
                    key: const Key('auto_renew_checkout_consent'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: autoRenewConsent,
                    onChanged: (value) =>
                        setDialogState(() => autoRenewConsent = value == true),
                    title: const Text(
                      'Подключить автопродление',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      'Сохранить способ оплаты и списывать $priceRub ₽ каждые '
                      '$periodDays дней. Отключить можно в настройках.',
                    ),
                  )
                else
                  const Text(
                    'Автопродление для этого способа оплаты недоступно.',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              key: const Key('confirm_payment_button'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(autoRenewConsent),
              child: const Text('Перейти к оплате'),
            ),
          ],
        ),
      ),
    );
    if (confirmedAutoRenew == null) return;
    await onApplyTariff(confirmedAutoRenew, requiresAcknowledgement);
  }

  int _basePriceForGb(double gb) {
    final g = gb.clamp(1.0, 800.0);

    const points = <_GbPricePoint>[
      _GbPricePoint(1, 99),
      _GbPricePoint(5, 99),
      _GbPricePoint(20, 119),
      _GbPricePoint(50, 149),
      _GbPricePoint(150, 199),
      _GbPricePoint(350, 259),
      _GbPricePoint(800, 299),
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
    return selectedApps.fold<int>(0, (sum, app) => sum + _appPriceRub(app));
  }

  int _appPriceRub(TariffApp app) {
    switch (app) {
      case TariffApp.youtube:
      case TariffApp.netflix:
        return 29;
      case TariffApp.telegram:
      case TariffApp.tiktok:
      case TariffApp.instagram:
        return 29;
      case TariffApp.discord:
        return 19;
      case TariffApp.steam:
        return 10;
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
    if (freeTierActive) return false;
    final code = planName.trim().toLowerCase();
    if (!subscriptionActive) return false;
    if (kPaidBetaBuild && code.contains('trial')) return false;
    if ((subscriptionMonthlyPriceRub ?? 0) <= 0) return false;
    return code.isNotEmpty &&
        code != 'base' &&
        code != 'trial' &&
        code != 'free';
  }

  bool get _hadPaidPlanBefore {
    final code = planName.trim().toLowerCase();
    if ((subscriptionMonthlyPriceRub ?? 0) <= 0) return false;
    if (code.contains('trial')) return false;
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
    final displayedPlanName = kPublicProductBuild
        ? greenVpnPublicPlanTitle(planName)
        : planName;
    if (_hasPaidPlan) {
      final price = subscriptionMonthlyPriceRub;
      final priceText = price == null ? '' : ' • $price ₽ за период';
      return '$displayedPlanName$priceText';
    }
    if (_hadPaidPlanBefore) {
      final ended = subscriptionExpiresAt == null
          ? ''
          : ' ${_formatCompactDate(subscriptionExpiresAt!)}';
      return '$displayedPlanName завершён$ended. Можно оформить новый период.';
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

  Future<void> _openPublicProductConfigurator(BuildContext context) async {
    var draftTrafficGb = trafficGb.round().clamp(1, 315);
    var draftDevices = devices.clamp(1, 5);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final trafficCost = _basePriceForGb(draftTrafficGb.toDouble());
          final devicesCost = max(0, draftDevices - 1) * 39;
          final used = trafficCost + devicesCost;
          final remaining = 249 - used;
          final overBudget = remaining < 0;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Настроить тариф',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    overBudget
                        ? 'Превышение: ${-remaining} ₽'
                        : 'Использовано $used ₽ из 249 ₽ • осталось $remaining ₽',
                    style: TextStyle(
                      color: overBudget
                          ? Theme.of(context).colorScheme.error
                          : kBrandPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (used / 249).clamp(0.0, 1.0),
                    minHeight: 8,
                    color: overBudget
                        ? Theme.of(context).colorScheme.error
                        : kBrandPrimary,
                    backgroundColor: kBrandPrimarySoft,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.data_usage_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Трафик: $draftTrafficGb ГБ',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        '$trafficCost ₽',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  Slider(
                    value: draftTrafficGb.toDouble(),
                    min: 1,
                    max: 315,
                    divisions: 314,
                    label: '$draftTrafficGb ГБ',
                    onChanged: (value) =>
                        setSheetState(() => draftTrafficGb = value.round()),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Icon(Icons.devices_rounded),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Устройства',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Убрать устройство',
                        onPressed: draftDevices <= 1
                            ? null
                            : () => setSheetState(() => draftDevices -= 1),
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '$draftDevices',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Добавить устройство',
                        onPressed: draftDevices >= 5
                            ? null
                            : () => setSheetState(() => draftDevices += 1),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 34),
                    child: Text(
                      draftDevices == 1
                          ? 'Одно устройство входит в тариф'
                          : 'Дополнительные устройства: +$devicesCost ₽ из бюджета',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: overBudget
                          ? null
                          : () {
                              onTrafficChanged(TrafficPack.gb20);
                              onTrafficGbChanged(draftTrafficGb.toDouble());
                              onDevicesChanged(draftDevices);
                              Navigator.of(sheetContext).pop();
                            },
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Применить настройку'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFixedPublicProduct(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = textColor.withValues(alpha: isDark ? 0.72 : 0.62);
    final usesApplications = !kIsWeb && Platform.isAndroid;
    final paidSalesAvailable =
        tariffCatalog?['paidSalesEnabled'] == true &&
        tariffCatalog?['paymentsProductionReady'] == true;
    final autoRenewAvailable = tariffCatalog?['autoRenew'] == true;
    final checkoutMessage = (tariffCatalog?['checkoutMessage'] ?? '')
        .toString()
        .trim();
    final rawPlans = (tariffCatalog?['plans'] as List?) ?? const [];
    final plans = rawPlans
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (plans.isEmpty) {
      plans.addAll(const [
        {
          'code': 'green_30d',
          'title': '1 месяц',
          'periodDays': 30,
          'priceRub': 249,
          'effectiveMonthlyRub': 249,
          'discountPercent': 0,
        },
        {
          'code': 'green_90d',
          'title': '3 месяца',
          'periodDays': 90,
          'priceRub': 649,
          'effectiveMonthlyRub': 216,
          'discountPercent': 13,
        },
        {
          'code': 'green_180d',
          'title': '6 месяцев',
          'periodDays': 180,
          'priceRub': 1099,
          'effectiveMonthlyRub': 183,
          'discountPercent': 26,
        },
      ]);
    }

    final effectiveSelectedPlanCode = greenVpnNormalizePublicBillingPlanCode(
      publicBillingPlanCode,
      availableCodes: plans.map((plan) => (plan['code'] ?? '').toString()),
    );
    final selectedPlan = plans.firstWhere(
      (plan) => plan['code'] == effectiveSelectedPlanCode,
      orElse: () => plans.first,
    );
    final selectedPrice = (selectedPlan['priceRub'] as num?)?.toInt() ?? 249;
    final selectedDays = (selectedPlan['periodDays'] as num?)?.toInt() ?? 30;
    final selectedPeriodTitle = greenVpnPublicBillingPeriodTitle(
      effectiveSelectedPlanCode,
      selectedDays,
    );
    final purchasePreviewRaw = tariffQuote?['purchasePreview'];
    final purchasePreview = purchasePreviewRaw is Map
        ? Map<String, dynamic>.from(purchasePreviewRaw)
        : const <String, dynamic>{};
    final purchaseKind = (purchasePreview['kind'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final previewStartsAt = (purchasePreview['periodStartsAt'] ?? '')
        .toString()
        .trim();
    final previewEndsAt = (purchasePreview['periodEndsAt'] ?? '')
        .toString()
        .trim();
    final purchaseAction = switch (purchaseKind) {
      'extension' => 'Продлить',
      'reactivation' => 'Возобновить',
      _ => 'Оплатить',
    };
    final quoteSelectionRaw = tariffQuote?['selection'];
    final quoteSelection = quoteSelectionRaw is Map
        ? Map<String, dynamic>.from(quoteSelectionRaw)
        : const <String, dynamic>{};
    final quotePlanCode = (quoteSelection['planCode'] ?? '').toString().trim();
    final exactQuoteReady =
        quotePlanCode == effectiveSelectedPlanCode &&
        previewStartsAt.isNotEmpty &&
        previewEndsAt.isNotEmpty;
    final pendingStatus = (pendingBillingOrder?['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final hasPendingOrder =
        pendingBillingOrder != null &&
        !{
          'activated',
          'canceled',
          'cancelled',
          'failed',
        }.contains(pendingStatus);
    final currentPlan = isGuest
        ? 'Бесплатный тариф'
        : _hasPaidPlan
        ? _currentPlanText()
        : freeTierActive
        ? 'Бесплатный тариф'
        : subscriptionActive
        ? 'Пробный период активен'
        : 'Пробный период завершён';

    Widget planOption(Map<String, dynamic> plan) {
      final code = (plan['code'] ?? '').toString();
      final title = (plan['title'] ?? '').toString();
      final price = (plan['priceRub'] as num?)?.toInt() ?? 0;
      final monthly = (plan['effectiveMonthlyRub'] as num?)?.toInt() ?? price;
      final discount = (plan['discountPercent'] as num?)?.toInt() ?? 0;
      final selected = code == effectiveSelectedPlanCode;
      final enabled = !tariffBusy && !hasPendingOrder;
      final monthlyText = discount > 0
          ? '$monthly ₽ в месяц, выгода $discount%'
          : '$monthly ₽ в месяц';
      return Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: '$title. $monthlyText. Стоимость $price ₽',
        excludeSemantics: true,
        child: InkWell(
          onTap: enabled ? () => onPublicBillingPlanChanged(code) : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? kBrandPrimary : theme.dividerColor,
                width: selected ? 2 : 1,
              ),
              color: selected
                  ? kBrandPrimary.withValues(alpha: isDark ? 0.14 : 0.08)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? kBrandPrimary : mutedColor,
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
                      const SizedBox(height: 3),
                      Text(
                        discount > 0
                            ? '$monthly ₽ в месяц • выгода $discount%'
                            : '$monthly ₽ в месяц',
                        style: TextStyle(
                          color: mutedColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$price ₽',
                  style: TextStyle(
                    color: selected ? kBrandPrimary : textColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _PageTitle(
          title: 'Тариф',
          subtitle: 'Выберите срок подписки',
          icon: Icons.workspace_premium_rounded,
        ),
        const SizedBox(height: 12),
        _Card(
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
              const SizedBox(height: 6),
              Text(
                currentPlan,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              if (_hasPaidPlan &&
                  subscriptionAccessStartsAt != null &&
                  subscriptionExpiresAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Оплаченный доступ: с '
                  '${_formatCompactDate(subscriptionAccessStartsAt!)} по '
                  '${_formatCompactDate(subscriptionExpiresAt!)}.',
                  key: const Key('active_subscription_period'),
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (_hasPaidPlan && subscriptionAutoRenew) ...[
                const SizedBox(height: 6),
                Text(
                  'Автопродление включено.',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (!_hasPaidPlan &&
                  _hadPaidPlanBefore &&
                  subscriptionStatus == 'expired' &&
                  subscriptionExpiresAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Последний оплаченный период завершился '
                  '${_formatCompactDate(subscriptionExpiresAt!)}.',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ] else if (!_hasPaidPlan &&
                  _hadPaidPlanBefore &&
                  subscriptionStatus == 'inactive') ...[
                const SizedBox(height: 6),
                Text(
                  'Платная подписка отключена.',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (!isGuest &&
                  !freeTierActive &&
                  !_hasPaidPlan &&
                  !_hadPaidPlanBefore &&
                  subscriptionExpiresAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Пробный период до ${_formatCompactDate(subscriptionExpiresAt!)}',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (isGuest && onRestoreAccess != null) ...[
                const Divider(height: 24),
                _buildRestoreAccessButton(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Срок подписки'),
              const SizedBox(height: 10),
              for (var index = 0; index < plans.length; index++) ...[
                planOption(plans[index]),
                if (index != plans.length - 1) const SizedBox(height: 8),
              ],
              if (previewStartsAt.isNotEmpty && previewEndsAt.isNotEmpty) ...[
                const Divider(height: 28),
                Text(
                  purchaseKind == 'extension'
                      ? 'Следующий оплачиваемый период'
                      : 'Оплачиваемый период',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'С ${_formatCompactDate(previewStartsAt)} по '
                  '${_formatCompactDate(previewEndsAt)} • $selectedPrice ₽',
                  key: const Key('tariff_period_preview'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (purchaseKind == 'extension') ...[
                  const SizedBox(height: 5),
                  Text(
                    'Текущая подписка не изменится: этот срок добавится после неё.',
                    style: TextStyle(
                      color: mutedColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const _IncludedBadge(
                    icon: Icons.block_rounded,
                    text: 'Без рекламы',
                  ),
                  _IncludedBadge(
                    icon: Icons.alt_route_rounded,
                    text: usesApplications
                        ? 'Только для выбранных приложений'
                        : 'Только для выбранных сервисов',
                  ),
                ],
              ),
            ],
          ),
        ),
        if (hasPendingOrder) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  pendingStatus == 'paid_receipt_pending'
                      ? 'Чек оформляется'
                      : 'Ожидает оплаты',
                ),
                const SizedBox(height: 6),
                Text(
                  'Заказ ${_shortOrderId(pendingBillingOrder!['orderId'])} • '
                  '${pendingBillingOrder!['amountRub'] ?? selectedPrice} ₽',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (pendingStatus != 'paid_receipt_pending' &&
                    (pendingBillingOrder!['paymentUrl'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: tariffBusy
                          ? null
                          : () => onOpenPaymentUrl(
                              pendingBillingOrder!['paymentUrl'].toString(),
                            ),
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
                    label: Text(
                      pendingStatus == 'paid_receipt_pending'
                          ? 'Проверить статус'
                          : 'Проверить оплату',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (tariffStatus != null && tariffStatus!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            tariffStatus!,
            style: TextStyle(color: mutedColor, fontWeight: FontWeight.w700),
          ),
        ],
        if (!paidSalesAvailable) ...[
          const SizedBox(height: 10),
          Text(
            checkoutMessage.isEmpty
                ? 'Оплата временно недоступна. Бесплатный тариф продолжает работать.'
                : checkoutMessage,
            style: TextStyle(color: mutedColor, fontWeight: FontWeight.w700),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const Key('start_payment_button'),
            onPressed:
                tariffBusy ||
                    hasPendingOrder ||
                    !paidSalesAvailable ||
                    !exactQuoteReady
                ? null
                : () => unawaited(
                    _confirmPublicCheckout(
                      context,
                      priceRub: selectedPrice,
                      periodDays: selectedDays,
                      periodTitle: selectedPeriodTitle,
                      autoRenewAvailable: autoRenewAvailable,
                    ),
                  ),
            icon: tariffBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.payment_rounded),
            label: Text(
              paidSalesAvailable && exactQuoteReady
                  ? '$purchaseAction $selectedPeriodTitle за $selectedPrice ₽'
                  : paidSalesAvailable
                  ? 'Обновляем срок подписки...'
                  : 'Оплата временно недоступна',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 110),
      ],
    );
  }

  // Archived configurable tariff UI. Kept for a possible post-launch experiment.
  // ignore: unused_element
  Widget _buildPublicProduct(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = textColor.withValues(alpha: isDark ? 0.72 : 0.62);
    final quoteRaw = tariffQuote?['quote'];
    final quote = quoteRaw is Map
        ? Map<String, dynamic>.from(quoteRaw)
        : <String, dynamic>{};
    final catalogPlanRaw = tariffCatalog?['plan'];
    final catalogPlan = catalogPlanRaw is Map
        ? Map<String, dynamic>.from(catalogPlanRaw)
        : <String, dynamic>{};
    final priceRaw = quote['monthlyPriceRub'] ?? catalogPlan['priceRub'];
    final price = priceRaw is num ? priceRaw.toInt() : 249;
    final originalRaw = quote['originalMonthlyPriceRub'];
    final originalPrice = originalRaw is num ? originalRaw.toInt() : 249;
    final usedRaw = quote['configurationUsedRub'];
    final used = usedRaw is num
        ? usedRaw.toInt()
        : _basePriceForGb(trafficGb) + _devicesPriceRub();
    final remaining = max(0, 249 - used);
    final selectedTraffic =
        (quote['trafficGb'] as num?)?.toInt() ??
        trafficGb.round().clamp(1, 315);
    final selectedDevices = (quote['devices'] as num?)?.toInt() ?? devices;
    final selectedPreset = (quote['presetCode'] ?? 'custom').toString();
    final pendingStatus = (pendingBillingOrder?['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final hasPendingOrder =
        pendingBillingOrder != null &&
        !{
          'activated',
          'canceled',
          'cancelled',
          'failed',
        }.contains(pendingStatus);
    final currentPlan = freeTierActive
        ? 'Бесплатный тариф'
        : _hasPaidPlan
        ? _currentPlanText()
        : subscriptionActive
        ? 'Trial активен'
        : 'Trial завершён';
    void applyPreset(double gb, int deviceCount) {
      onTrafficChanged(TrafficPack.gb20);
      onTrafficGbChanged(gb);
      onDevicesChanged(deviceCount);
    }

    Widget presetButton({
      required String code,
      required String title,
      required String subtitle,
      required IconData icon,
      required double gb,
      required int deviceCount,
    }) {
      final selected = selectedPreset == code;
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: tariffBusy ? null : () => applyPreset(gb, deviceCount),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            side: BorderSide(
              color: selected ? kBrandPrimary : theme.dividerColor,
              width: selected ? 2 : 1,
            ),
          ),
          icon: Icon(icon, color: selected ? kBrandPrimary : mutedColor),
          label: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
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
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _PageTitle(
          title: 'Тариф',
          subtitle: 'Готовый набор или своя настройка в одном бюджете',
          icon: Icons.tune_rounded,
        ),
        const SizedBox(height: 12),
        _Card(
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
              const SizedBox(height: 6),
              Text(
                currentPlan,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              if (!_hasPaidPlan && subscriptionExpiresAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Trial до ${_formatCompactDate(subscriptionExpiresAt!)}',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (isGuest && onRestoreAccess != null) ...[
                const Divider(height: 24),
                _buildRestoreAccessButton(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          tint: isDark ? kBrandDarkSurface : kBrandPrimarySoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Green VPN на 30 дней'),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$price ₽',
                    style: const TextStyle(
                      color: kBrandPrimary,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      'за 30 дней',
                      style: TextStyle(
                        color: mutedColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (originalPrice > price) ...[
                const SizedBox(height: 4),
                Text(
                  'Первый период вместо $originalPrice ₽',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _IncludedBadge(
                    icon: Icons.block_rounded,
                    text: 'Без рекламы',
                  ),
                  _IncludedBadge(
                    icon: Icons.alt_route_rounded,
                    text: 'Умное подключение',
                  ),
                  _IncludedBadge(
                    icon: Icons.event_repeat_rounded,
                    text: 'Без автопродления',
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
              const _SectionTitle('Готовые наборы'),
              const SizedBox(height: 10),
              presetButton(
                code: 'devices',
                title: 'Больше устройств',
                subtitle: '50 ГБ • 3 устройства',
                icon: Icons.devices_rounded,
                gb: 50,
                deviceCount: 3,
              ),
              const SizedBox(height: 8),
              presetButton(
                code: 'balanced',
                title: 'Баланс',
                subtitle: '150 ГБ • 2 устройства',
                icon: Icons.balance_rounded,
                gb: 150,
                deviceCount: 2,
              ),
              const SizedBox(height: 8),
              presetButton(
                code: 'traffic',
                title: 'Больше трафика',
                subtitle: '315 ГБ • 1 устройство',
                icon: Icons.data_usage_rounded,
                gb: 315,
                deviceCount: 1,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Своя настройка'),
              const SizedBox(height: 8),
              Text(
                '$selectedTraffic ГБ • $selectedDevices ${selectedDevices == 1 ? 'устройство' : 'устройства'}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Использовано $used ₽ из 249 ₽ • осталось $remaining ₽',
                style: TextStyle(
                  color: mutedColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (used / 249).clamp(0.0, 1.0),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                color: kBrandPrimary,
                backgroundColor: kBrandPrimarySoft,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: tariffBusy
                      ? null
                      : () => _openPublicProductConfigurator(context),
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Настроить тариф'),
                ),
              ),
            ],
          ),
        ),
        if (hasPendingOrder) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  pendingStatus == 'paid_receipt_pending'
                      ? 'Чек оформляется'
                      : 'Ожидает оплаты',
                ),
                const SizedBox(height: 6),
                Text(
                  'Заказ ${_shortOrderId(pendingBillingOrder!['orderId'])} • '
                  '${pendingBillingOrder!['amountRub'] ?? price} ₽',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (pendingStatus != 'paid_receipt_pending' &&
                    (pendingBillingOrder!['paymentUrl'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: tariffBusy
                          ? null
                          : () => onOpenPaymentUrl(
                              pendingBillingOrder!['paymentUrl'].toString(),
                            ),
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
                    label: Text(
                      pendingStatus == 'paid_receipt_pending'
                          ? 'Проверить статус'
                          : 'Проверить оплату',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (tariffStatus != null && tariffStatus!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            tariffStatus!,
            style: TextStyle(color: mutedColor, fontWeight: FontWeight.w700),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: tariffBusy || hasPendingOrder
                ? null
                : () => unawaited(
                    _confirmPublicCheckout(
                      context,
                      priceRub: price,
                      periodDays: 30,
                      periodTitle: '30 дней',
                      autoRenewAvailable: true,
                      initialAutoRenew: optAutoRenew,
                    ),
                  ),
            icon: tariffBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.payment_rounded),
            label: Text(
              _hasPaidPlan ? 'Продлить на 30 дней' : 'Перейти к оплате',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 110),
      ],
    );
  }

  Widget _buildPaidBeta(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = textColor.withValues(alpha: isDark ? 0.72 : 0.62);
    final quoteRaw = tariffQuote?['quote'];
    final quote = quoteRaw is Map
        ? Map<String, dynamic>.from(quoteRaw)
        : <String, dynamic>{};
    final catalogPlanRaw = tariffCatalog?['plan'];
    final catalogPlan = catalogPlanRaw is Map
        ? Map<String, dynamic>.from(catalogPlanRaw)
        : <String, dynamic>{};
    final priceRaw = quote['monthlyPriceRub'] ?? catalogPlan['priceRub'];
    final price = priceRaw is num ? priceRaw.toInt() : 299;
    final originalRaw = quote['originalMonthlyPriceRub'];
    final originalPrice = originalRaw is num ? originalRaw.toInt() : price;
    final inviteRaw = catalogPlan['inviteFirstPeriodPriceRub'];
    final invitePrice = inviteRaw is num ? inviteRaw.toInt() : 149;
    final betaOfferRaw = tariffQuote?['betaOffer'];
    final betaOffer = betaOfferRaw is Map
        ? Map<String, dynamic>.from(betaOfferRaw)
        : <String, dynamic>{};
    final inviteApplied = quote['inviteApplied'] == true;
    final inviteClaimed = betaOffer['inviteClaimed'] == true;
    final pendingStatus = (pendingBillingOrder?['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final hasPendingOrder =
        pendingBillingOrder != null &&
        !{
          'activated',
          'canceled',
          'cancelled',
          'failed',
        }.contains(pendingStatus);
    final currentPlan = freeTierActive
        ? 'Бесплатный тариф'
        : _hasPaidPlan
        ? _currentPlanText()
        : subscriptionActive
        ? 'Trial активен'
        : 'Trial завершён';
    final freeUsageProgress = freeTierActive
        ? greenVpnTrafficUsageProgress(trafficUsage)
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _PageTitle(
          title: 'Beta',
          subtitle: 'Закрытый тест тарифа Green VPN',
          icon: Icons.science_rounded,
        ),
        const SizedBox(height: 12),
        _Card(
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
              const SizedBox(height: 6),
              Text(
                currentPlan,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              if (freeTierActive) ...[
                const SizedBox(height: 8),
                Text(
                  greenVpnTrafficUsageSummary(trafficUsage),
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (freeUsageProgress != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: freeUsageProgress,
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Устройств: $subscriptionMaxDevices • обычное подключение • без рекламы',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
              if (!_hasPaidPlan &&
                  !freeTierActive &&
                  subscriptionExpiresAt != null &&
                  subscriptionExpiresAt!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Trial до ${_formatCompactDate(subscriptionExpiresAt!)}',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (isGuest && onRestoreAccess != null) ...[
                const Divider(height: 24),
                _buildRestoreAccessButton(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          tint: isDark ? kBrandDarkSurface : kBrandPrimarySoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Beta на 30 дней'),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$price ₽',
                    style: const TextStyle(
                      color: kBrandPrimary,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      'за 30 дней',
                      style: TextStyle(
                        color: mutedColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (originalPrice > price) ...[
                const SizedBox(height: 4),
                Text(
                  'Обычная цена $originalPrice ₽',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _IncludedBadge(
                    icon: Icons.devices_rounded,
                    text: '2 устройства',
                  ),
                  _IncludedBadge(
                    icon: Icons.block_rounded,
                    text: 'Без рекламы',
                  ),
                  _IncludedBadge(
                    icon: Icons.event_repeat_rounded,
                    text: 'Без автопродления',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                inviteApplied
                    ? 'Персональный инвайт применён: первый период $invitePrice ₽.'
                    : inviteClaimed
                    ? 'Персональная цена первого периода уже использована.'
                    : 'Первый период по персональному beta-инвайту: $invitePrice ₽.',
                style: TextStyle(
                  color: mutedColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              if (!inviteClaimed) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: tariffBusy
                        ? null
                        : () => onClaimPaidBetaInvite(),
                    icon: const Icon(Icons.key_rounded),
                    label: const Text('Ввести beta-инвайт'),
                  ),
                ),
              ],
              if (hasPendingOrder) ...[
                const Divider(height: 24),
                Text(
                  pendingStatus == 'paid_receipt_pending'
                      ? 'Чек оформляется'
                      : 'Ожидает оплаты',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Заказ ${_shortOrderId(pendingBillingOrder!['orderId'])} • '
                  '${pendingBillingOrder!['amountRub'] ?? price} ₽',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                if (pendingStatus != 'paid_receipt_pending' &&
                    (pendingBillingOrder!['paymentUrl'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: tariffBusy
                          ? null
                          : () => onOpenPaymentUrl(
                              pendingBillingOrder!['paymentUrl'].toString(),
                            ),
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
                    label: Text(
                      pendingStatus == 'paid_receipt_pending'
                          ? 'Проверить статус'
                          : 'Проверить оплату',
                    ),
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
                  onPressed: tariffBusy || hasPendingOrder
                      ? null
                      : () => unawaited(
                          _confirmPublicCheckout(
                            context,
                            priceRub: price,
                            periodDays: 30,
                            periodTitle: '30 дней',
                            autoRenewAvailable: false,
                            initialAutoRenew: false,
                          ),
                        ),
                  icon: tariffBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payment_rounded),
                  label: Text(
                    _hasPaidPlan ? 'Продлить на 30 дней' : 'Перейти к оплате',
                    style: const TextStyle(fontWeight: FontWeight.w900),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = textColor.withValues(alpha: isDark ? 0.72 : 0.62);

    if (kStoreDistributionBuild) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _PageTitle(
            title: 'Бесплатный доступ',
            subtitle: 'Green VPN работает без оплаты и рекламы',
            icon: Icons.verified_user_rounded,
          ),
          const SizedBox(height: 12),
          _Card(
            tint: isDark ? kBrandDarkSurface : kBrandPrimarySoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Включено в приложение',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _IncludedBadge(
                      icon: Icons.vpn_key_rounded,
                      text: 'VPN-доступ',
                    ),
                    _IncludedBadge(
                      icon: Icons.person_off_rounded,
                      text: 'Без регистрации',
                    ),
                    _IncludedBadge(
                      icon: Icons.block_rounded,
                      text: 'Без рекламы',
                    ),
                    _IncludedBadge(
                      icon: Icons.system_update_rounded,
                      text: 'Обновления через магазин',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Подключение доступно сразу после установки. Лимиты и доступные локации управляются сервисом Green VPN.',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 110),
        ],
      );
    }

    if (kPublicProductBuild ||
        greenVpnCatalogHasFixedBillingPlans(tariffCatalog)) {
      return _buildFixedPublicProduct(context);
    }

    if (kPaidBetaCustomerUi) {
      return _buildPaidBeta(context);
    }

    if (kTrialOnlyNoAdsBuild) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _PageTitle(
            title: 'Trial',
            subtitle: 'Тестовый доступ Green VPN без рекламы и оплаты',
            icon: Icons.star_rounded,
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
                const SizedBox(height: 6),
                Text(
                  subscriptionActive ? 'Trial активен' : 'Trial не активен',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                if (subscriptionExpiresAt != null &&
                    subscriptionExpiresAt!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Доступ до ${_formatCompactDate(subscriptionExpiresAt!)}',
                    style: TextStyle(
                      color: mutedColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _IncludedBadge(
                      icon: Icons.vpn_key_rounded,
                      text: 'VPN-доступ',
                    ),
                    _IncludedBadge(
                      icon: Icons.alt_route_rounded,
                      text: 'Соцсети',
                    ),
                    _IncludedBadge(
                      icon: Icons.dashboard_customize_rounded,
                      text: 'Плитка Android',
                    ),
                    _IncludedBadge(
                      icon: Icons.block_rounded,
                      text: 'Без рекламы',
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
                const _SectionTitle('Режим'),
                const SizedBox(height: 8),
                Text(
                  'Эта сборка использует обычный Trial-контур: подключение работает без рекламного просмотра, без заказов и без платёжных экранов.',
                  style: TextStyle(
                    color: mutedColor,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 110),
        ],
      );
    }

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

    final gbInt = trafficGb.round().clamp(1, 350);
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
              'Настрой подписку под свои сценарии, приложения и устройства',
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
                            text: '150 ГБ',
                            selected: gbInt == 150,
                            onTap: () => onTrafficGbChanged(150.0),
                          ),
                          _ChipButton(
                            icon: Icons.storage_rounded,
                            text: '350 ГБ',
                            selected: gbInt == 350,
                            onTap: () => onTrafficGbChanged(350.0),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF091F18)
                              : kBrandPrimarySoft.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isDark
                                ? kBrandPrimary.withValues(alpha: 0.38)
                                : kBrandPrimary.withValues(alpha: 0.14),
                          ),
                          boxShadow: isDark
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                  ),
                                ]
                              : null,
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
                                  style: TextStyle(
                                    color: isDark
                                        ? kBrandPrimary
                                        : kBrandPrimaryDeep,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: kBrandPrimary,
                                inactiveTrackColor: isDark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : kBrandPrimary.withValues(alpha: 0.18),
                                thumbColor: kBrandPrimary,
                                overlayColor: kBrandPrimary.withValues(
                                  alpha: 0.14,
                                ),
                                valueIndicatorColor: isDark
                                    ? const Color(0xFF123528)
                                    : kBrandPrimary,
                                valueIndicatorTextStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              child: Slider(
                                value: gbInt.clamp(1, 350).toDouble(),
                                min: 1,
                                max: 350,
                                divisions: 349,
                                label: '$gbInt ГБ',
                                onChanged: (value) =>
                                    onTrafficGbChanged(value.roundToDouble()),
                              ),
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
                    text: 'Соцсети',
                  ),
                  _IncludedBadge(
                    icon: Icons.dashboard_customize_rounded,
                    text: 'Плитка в шторке',
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
              if (pendingBillingOrder != null) ...[
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final paymentUrl =
                        (pendingBillingOrder!['paymentUrl'] ?? '')
                            .toString()
                            .trim();
                    final receiptPending =
                        (pendingBillingOrder!['status'] ?? '')
                            .toString()
                            .trim()
                            .toLowerCase() ==
                        'paid_receipt_pending';
                    final hasPaymentUrl =
                        paymentUrl.isNotEmpty && !receiptPending;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? kBrandDarkSurface
                            : const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: isDark ? 0.16 : 0.10,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            receiptPending
                                ? 'Чек оформляется'
                                : 'Ожидает оплаты',
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
                            receiptPending
                                ? 'Оплата подтверждена. Тариф активируется после регистрации и отправки чека на email.'
                                : 'После оплаты можно вернуться в Green VPN. Мы проверяем статус автоматически.',
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
                              label: Text(
                                receiptPending
                                    ? 'Проверить статус'
                                    : 'Проверить оплату',
                              ),
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
                  onPressed: tariffBusy
                      ? null
                      : () => unawaited(
                          _confirmPublicCheckout(
                            context,
                            priceRub: price,
                            periodDays: 30,
                            periodTitle: '30 дней',
                            autoRenewAvailable: true,
                            initialAutoRenew: optAutoRenew,
                          ),
                        ),
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

class SettingsPage extends StatelessWidget {
  final ThemeMode themeMode;
  final void Function(ThemeMode mode) onThemeModeChanged;
  final String language;
  final VoidCallback onPickLanguage;
  final bool showLanguage;

  final String email;
  final bool isGuest;
  final bool emailVerified;
  final bool emailConfirmationRequired;
  final bool emailStatusBusy;
  final String? emailStatusMessage;
  final Future<void> Function() onResendEmailConfirmation;
  final Future<void> Function() onRefreshEmailStatus;
  final bool hasPaidEntitlement;
  final bool subscriptionAutoRenew;
  final bool paymentMethodSaved;
  final VoidCallback onOpenTariff;
  final VoidCallback? onRestoreAccess;
  final Future<bool> Function() onCancelAutoRenew;
  final Future<void> Function() onLogout;
  final VoidCallback onOpenUpdates;
  final VoidCallback onOpenDiagnostics;
  final bool showWindowsCloseBehavior;
  final WindowsCloseBehavior windowsCloseBehavior;
  final VoidCallback onPickWindowsCloseBehavior;

  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.language = 'Русский',
    this.onPickLanguage = _noopSettingsAction,
    this.showLanguage = !kFusionUiEnabled,
    required this.email,
    required this.isGuest,
    required this.emailVerified,
    required this.emailConfirmationRequired,
    required this.emailStatusBusy,
    required this.emailStatusMessage,
    required this.onResendEmailConfirmation,
    required this.onRefreshEmailStatus,
    required this.hasPaidEntitlement,
    required this.subscriptionAutoRenew,
    required this.paymentMethodSaved,
    required this.onOpenTariff,
    this.onRestoreAccess,
    required this.onCancelAutoRenew,
    required this.onLogout,
    required this.onOpenUpdates,
    required this.onOpenDiagnostics,
    this.showWindowsCloseBehavior = false,
    this.windowsCloseBehavior = WindowsCloseBehavior.minimizeToTray,
    this.onPickWindowsCloseBehavior = _noopSettingsAction,
  });

  void _openAutoRenewSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AutoRenewSettingsPage(
          autoRenewEnabled: subscriptionAutoRenew,
          paymentMethodSaved: paymentMethodSaved,
          onEnableAutoRenew: () {
            Navigator.of(context).pop();
            onOpenTariff();
          },
          onCancelAutoRenew: onCancelAutoRenew,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeMode == ThemeMode.dark;
    final displayedVersion = kPublicProductBuild
        ? greenVpnPublicVersionTitle(kAppVersion)
        : kAppVersion;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          _PageTitle(
            title: 'Настройки',
            subtitle: kTrialOnlyNoAdsBuild && !kPaidBetaBuild
                ? 'Аккаунт и параметры приложения'
                : 'Аккаунт, оплата и параметры приложения',
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
                if (showLanguage) ...[
                  const Divider(height: 18),
                  _SettingsNavRow(
                    title: 'Язык',
                    subtitle: language,
                    icon: Icons.language_rounded,
                    onTap: onPickLanguage,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (showWindowsCloseBehavior) ...[
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Поведение Windows'),
                  const SizedBox(height: 8),
                  _SettingsNavRow(
                    key: const Key('fusion_windows_close_behavior'),
                    title: 'Закрытие окна',
                    subtitle: windowsCloseBehavior.title,
                    icon: Icons.close_fullscreen_rounded,
                    onTap: onPickWindowsCloseBehavior,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (kPaidBetaCustomerUi) ...[
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Доступ и оплата'),
                  const SizedBox(height: 8),
                  _SettingsNavRow(
                    title: 'Тарифы и доступ',
                    subtitle: hasPaidEntitlement
                        ? 'Текущий доступ и оплата'
                        : 'Выбрать тариф или восстановить доступ',
                    icon: Icons.payment_rounded,
                    onTap: onOpenTariff,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Автопродление выключено. Новое списание создаётся только вручную.',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else if (!kTrialOnlyNoAdsBuild) ...[
            _Card(
              child: _SettingsNavRow(
                title: 'Автопродление',
                subtitle: subscriptionAutoRenew ? 'Включено' : 'Отключено',
                icon: Icons.autorenew_rounded,
                onTap: () => _openAutoRenewSettings(context),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Аккаунт'),
                const SizedBox(height: 8),
                if (isGuest)
                  Column(
                    children: [
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.person_outline_rounded),
                        title: Text('Бесплатный профиль'),
                        subtitle: Text('Без регистрации'),
                      ),
                      if (!kStoreDistributionBuild &&
                          onRestoreAccess != null) ...[
                        const Divider(height: 18),
                        KeyedSubtree(
                          key: const Key('restore_access_settings'),
                          child: _SettingsActionRow(
                            title: 'Войти в аккаунт',
                            subtitle: 'Восстановить уже оплаченную подписку',
                            icon: Icons.login_rounded,
                            onTap: onRestoreAccess!,
                          ),
                        ),
                      ],
                    ],
                  )
                else ...[
                  _SettingsNavRow(
                    title: 'Почта',
                    subtitle: email.isEmpty ? 'Не указана' : email,
                    icon: Icons.alternate_email_rounded,
                    onTap: () => unawaited(onRefreshEmailStatus()),
                  ),
                  const Divider(height: 18),
                  _SettingsActionRow(
                    title: 'Выйти',
                    subtitle: 'Сбросить сессию на этом устройстве',
                    icon: Icons.logout_rounded,
                    onTap: () => onLogout(),
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
                const _SectionTitle('О приложении'),
                const SizedBox(height: 8),
                if (kSelfUpdateEnabled) ...[
                  _SettingsActionRow(
                    title: 'Обновления',
                    subtitle: 'Проверить свежую версию Green VPN',
                    icon: Icons.system_update_alt_rounded,
                    onTap: onOpenUpdates,
                  ),
                  const Divider(height: 18),
                ],
                _SettingsActionRow(
                  title: 'Поддержка',
                  subtitle: 'Отправить диагностический отчёт в поддержку',
                  icon: Icons.health_and_safety_rounded,
                  onTap: onOpenDiagnostics,
                ),
                const Divider(height: 18),
                _SettingsActionRow(
                  title: 'О Green VPN',
                  subtitle:
                      'Версия $displayedVersion для ${greenVpnClientPlatformTitle()}',
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
    final displayedVersion = kPublicProductBuild
        ? greenVpnPublicVersionTitle(kAppVersion)
        : kAppVersion;
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(kProductName),
          content: Text(
            'Green VPN для Windows и Android.\n\n'
            'Версия: $displayedVersion\n\n'
            'Если что-то не работает, раздел “Поддержка” отправит диагностический отчёт без паролей, токенов и приватных ключей.',
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

class AutoRenewSettingsPage extends StatefulWidget {
  final bool autoRenewEnabled;
  final bool paymentMethodSaved;
  final VoidCallback onEnableAutoRenew;
  final Future<bool> Function() onCancelAutoRenew;

  const AutoRenewSettingsPage({
    super.key,
    required this.autoRenewEnabled,
    required this.paymentMethodSaved,
    required this.onEnableAutoRenew,
    required this.onCancelAutoRenew,
  });

  @override
  State<AutoRenewSettingsPage> createState() => _AutoRenewSettingsPageState();
}

class _AutoRenewSettingsPageState extends State<AutoRenewSettingsPage> {
  late bool _autoRenewEnabled;
  late bool _paymentMethodSaved;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _autoRenewEnabled = widget.autoRenewEnabled;
    _paymentMethodSaved = widget.paymentMethodSaved;
  }

  Future<void> _cancelAutoRenew() async {
    if (_busy || !_autoRenewEnabled) return;
    setState(() {
      _busy = true;
      _status = null;
    });

    var cancelled = false;
    try {
      cancelled = await widget.onCancelAutoRenew();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отключить автопродление.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (cancelled) {
            _autoRenewEnabled = false;
            _paymentMethodSaved = false;
            _status = 'Автопродление отключено.';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final mutedColor = textColor.withValues(alpha: isDark ? 0.72 : 0.62);

    return Scaffold(
      appBar: AppBar(title: const Text('Автопродление')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Card(
                  child: SwitchListTile.adaptive(
                    key: const Key('auto_renew_settings_switch'),
                    contentPadding: EdgeInsets.zero,
                    value: _autoRenewEnabled,
                    onChanged: _busy
                        ? null
                        : (enabled) {
                            if (enabled) {
                              widget.onEnableAutoRenew();
                            } else {
                              unawaited(_cancelAutoRenew());
                            }
                          },
                    secondary: Icon(
                      Icons.autorenew_rounded,
                      color: _autoRenewEnabled ? kBrandPrimary : mutedColor,
                    ),
                    title: Text(
                      _autoRenewEnabled ? 'Включено' : 'Отключено',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    subtitle: Text(
                      _autoRenewEnabled
                          ? 'Подписка продлевается автоматически.'
                          : 'Включение подтверждается при следующей оплате.',
                      style: TextStyle(
                        color: mutedColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle('Способ оплаты'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.credit_card_rounded,
                            color: _paymentMethodSaved
                                ? kBrandPrimary
                                : mutedColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _paymentMethodSaved
                                  ? 'Карта привязана'
                                  : 'Карта не привязана',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_status != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _status!,
                          style: const TextStyle(
                            color: kBrandPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UpdatesPage extends StatefulWidget {
  final bool forceRequired;
  final GreenVpnUpdateManifest? initialManifest;
  final bool autoStart;

  const UpdatesPage({
    super.key,
    this.forceRequired = false,
    this.initialManifest,
    this.autoStart = false,
  });

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  static const _staleUpdateCacheAge = Duration(hours: 12);
  static const _postInstallCleanupDelay = Duration(minutes: 30);

  final _api = const BlueVpnApi(baseUrl: kApiBaseUrl);
  final _deviceStore = DeviceIdStore();

  bool _loading = true;
  bool _downloading = false;
  double? _downloadProgress;
  String? _downloadStatus;
  String? _downloadError;
  GreenVpnUpdateManifest? _manifest;
  String? _error;
  bool _autoStartConsumed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_cleanupStaleUpdateCache());
    final initial = widget.initialManifest;
    if (initial != null) {
      _loading = false;
      _manifest = initial;
    } else {
      _refresh();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoStartUpdate();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _downloadStatus = null;
      _downloadError = null;
    });

    String? clientId;
    try {
      clientId = await _deviceStore.getOrCreate();
    } catch (_) {
      clientId = null;
    }

    final res = await _api.fetchUpdateManifest(
      platform: greenVpnClientPlatform(),
      channel: greenVpnUpdateChannel(),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoStartUpdate();
    });
  }

  String get _platform => greenVpnClientPlatform();

  String get _platformTitle => greenVpnClientPlatformTitle();

  String get _expectedUpdateExtension {
    if (!kIsWeb && Platform.isAndroid) return '.apk';
    if (!kIsWeb && Platform.isWindows) return '.exe';
    return '';
  }

  bool get _showManualDownloadLink => false;

  String get _installHint {
    if (!kIsWeb && Platform.isAndroid) {
      return 'Обновление скачается внутри Green VPN, затем Android откроет системную установку.';
    }
    if (!kIsWeb && Platform.isWindows) {
      return 'Установщик скачается внутри Green VPN и запустится автоматически.';
    }
    return 'Green VPN скачает файл обновления для этой платформы.';
  }

  bool _downloadLooksPlatformSpecific(String url) {
    final expected = _expectedUpdateExtension;
    if (expected.isEmpty) return true;
    final uri = Uri.tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    return path.endsWith(expected);
  }

  void _maybeAutoStartUpdate() {
    if (!mounted || !widget.autoStart || _autoStartConsumed || _downloading) {
      return;
    }
    final manifest = _manifest;
    if (manifest == null ||
        !manifest.hasUpdate ||
        !manifest.canDownload ||
        !_downloadLooksPlatformSpecific(manifest.downloadUrl)) {
      return;
    }
    _autoStartConsumed = true;
    unawaited(_downloadAndInstall());
  }

  String _safeUpdateFileName(Uri uri) {
    final expected = _expectedUpdateExtension;
    var name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    name = Uri.decodeComponent(name).trim();
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (name.isEmpty ||
        (expected.isNotEmpty && !name.toLowerCase().endsWith(expected))) {
      name = 'GreenVPN_Update$expected';
    }
    return name;
  }

  Future<Directory> _updateDownloadDirectory() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final path = await kAndroidPlatformChannel.invokeMethod<String>(
          'getUpdateCacheDir',
        );
        if (path != null && path.trim().isNotEmpty) {
          final dir = Directory(path.trim());
          await dir.create(recursive: true);
          return dir;
        }
      } catch (_) {
        // Fall back to the generic temp directory; installation will still be blocked if Android cannot share it.
      }
    }

    final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}GreenVPNUpdates',
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<bool> _downloadedFileMatchesManifest(
    File file,
    GreenVpnUpdateManifest manifest,
  ) async {
    if (!await file.exists()) return false;
    final expectedSha = manifest.sha256.trim().toUpperCase();
    if (expectedSha.isEmpty) {
      return (await file.length()) > 0;
    }
    final actualSha = (await crypto.sha256.bind(file.openRead()).first)
        .toString()
        .toUpperCase();
    return actualSha == expectedSha;
  }

  Future<void> _cleanupOldUpdateFiles(
    Directory dir, {
    String? keepPath,
    String? tempPath,
    Duration minAge = Duration.zero,
  }) async {
    try {
      final now = DateTime.now();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (entity.path == keepPath || entity.path == tempPath) continue;
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.apk') ||
            lower.endsWith('.exe') ||
            lower.endsWith('.download')) {
          if (minAge > Duration.zero) {
            final stat = await entity.stat();
            if (now.difference(stat.modified) < minAge) continue;
          }
          await entity.delete();
        }
      }
    } catch (_) {
      // Cleanup is best effort; a locked stale file must not block the update.
    }
  }

  Future<void> _cleanupStaleUpdateCache() async {
    if (kIsWeb) return;
    try {
      final dir = await _updateDownloadDirectory();
      await _cleanupOldUpdateFiles(dir, minAge: _staleUpdateCacheAge);
    } catch (_) {
      // Cache cleanup must never block the update screen.
    }
  }

  void _schedulePostInstallUpdateCacheCleanup() {
    if (kIsWeb) return;
    unawaited(
      Future<void>.delayed(_postInstallCleanupDelay, () async {
        try {
          final dir = await _updateDownloadDirectory();
          await _cleanupOldUpdateFiles(
            dir,
            minAge: const Duration(minutes: 10),
          );
        } catch (_) {
          // Best effort only.
        }
      }),
    );
  }

  Future<File> _downloadUpdateFile(GreenVpnUpdateManifest manifest) async {
    final url = manifest.downloadUrl.trim();
    if (!greenVpnUpdateManifestMatchesCurrentPlatform(manifest)) {
      throw Exception(
        'Update manifest is for ${manifest.platform}, but this device is $_platformTitle.',
      );
    }
    if (url.isEmpty) {
      throw Exception('Ссылка на обновление не настроена.');
    }
    if (!_downloadLooksPlatformSpecific(url)) {
      throw Exception(
        'Сервер отдал файл не для $_platformTitle. Ожидался $_expectedUpdateExtension.',
      );
    }

    final uri = Uri.parse(url);
    final schemeAllowed = kPublicProductBuild
        ? uri.scheme == 'https'
        : uri.scheme == 'https' || uri.scheme == 'http';
    if (!schemeAllowed || uri.host.trim().isEmpty) {
      throw Exception('Некорректная ссылка обновления.');
    }

    final dir = await _updateDownloadDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}${_safeUpdateFileName(uri)}',
    );
    final temp = File('${file.path}.download');
    await _cleanupOldUpdateFiles(dir, keepPath: file.path, tempPath: temp.path);
    if (await _downloadedFileMatchesManifest(file, manifest)) {
      if (mounted) {
        setState(
          () => _downloadStatus = 'Файл уже скачан. Запускаю установку...',
        );
      }
      return file;
    }
    if (await file.exists()) {
      await file.delete();
    }
    if (await temp.exists()) {
      await temp.delete();
    }

    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'GreenVPN/$kAppVersion ($_platform; updater)',
      );
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Сервер обновлений вернул HTTP ${response.statusCode}.',
        );
      }

      sink = temp.openWrite();
      var downloaded = 0;
      final total = response.contentLength;
      await for (final chunk in response) {
        downloaded += chunk.length;
        sink.add(chunk);
        if (mounted && total > 0) {
          setState(() {
            _downloadProgress = downloaded / total;
            _downloadStatus =
                'Скачивание: ${(downloaded / 1024 / 1024).toStringAsFixed(1)} из ${(total / 1024 / 1024).toStringAsFixed(1)} МБ';
          });
        }
      }
      await sink.close();
      sink = null;
    } finally {
      client.close(force: true);
      await sink?.close();
    }

    final expectedSha = manifest.sha256.trim().toUpperCase();
    if (expectedSha.isNotEmpty) {
      if (mounted) {
        setState(() => _downloadStatus = 'Проверка файла обновления...');
      }
      final actualSha = (await crypto.sha256.bind(temp.openRead()).first)
          .toString()
          .toUpperCase();
      if (actualSha != expectedSha) {
        await temp.delete();
        throw Exception('Проверка файла не пройдена. Установка остановлена.');
      }
    }

    if (await file.exists()) {
      await file.delete();
    }
    return temp.rename(file.path);
  }

  Future<void> _installDownloadedUpdate(File file) async {
    if (!kIsWeb && Platform.isAndroid) {
      final result = await kAndroidPlatformChannel.invokeMethod('installApk', {
        'path': file.path,
      });
      final map = result is Map ? Map<String, dynamic>.from(result) : {};
      final ok = map['ok'] == true;
      if (!ok) {
        throw Exception(
          (map['message'] ?? 'Android не открыл установку APK.').toString(),
        );
      }
      return;
    }

    if (!kIsWeb && Platform.isWindows) {
      await Process.start(
        file.path,
        const <String>[],
        mode: ProcessStartMode.detached,
      );
      return;
    }

    await openExternalUrl(file.uri.toString());
  }

  Future<void> _downloadAndInstall() async {
    final manifest = _manifest;
    if (manifest == null || _downloading) return;

    setState(() {
      _downloading = true;
      _downloadProgress = null;
      _downloadStatus = 'Подготовка обновления для $_platformTitle...';
      _downloadError = null;
    });

    try {
      final file = await _downloadUpdateFile(manifest);
      if (mounted) {
        setState(() => _downloadStatus = 'Файл скачан. Запускаю установку...');
      }
      await _installDownloadedUpdate(file);
      _schedulePostInstallUpdateCacheCleanup();
      if (!mounted) return;
      setState(() {
        _downloadStatus = !kIsWeb && Platform.isAndroid
            ? 'Открыта системная установка.'
            : 'Установщик запущен.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadError = authUserMessage(
          error,
          fallback: 'Не удалось установить обновление.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _manifest;
    final displayedCurrentVersion = kPublicProductBuild
        ? greenVpnPublicVersionTitle(kAppVersion)
        : kAppVersion;
    final displayedChangelog = manifest == null
        ? const <String>[]
        : kPublicProductBuild
        ? greenVpnPublicChangelog(manifest.changelog)
        : manifest.changelog;
    final displayedServerVersion = manifest == null
        ? ''
        : kPublicProductBuild
        ? greenVpnPublicVersionTitle(manifest.latestVersion)
        : manifest.latestVersion;
    final hasUpdate = manifest?.hasUpdate ?? false;
    final heldByRollout = manifest?.heldByRollout ?? false;
    final requiredUpdate = manifest?.required ?? false;
    final forceLocked = widget.forceRequired && (_loading || hasUpdate);

    return PopScope(
      canPop: !forceLocked,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !forceLocked,
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
                        ? 'Новая версия будет установлена для $_platformTitle.'
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
                            value: displayedCurrentVersion,
                          ),
                          const SizedBox(height: 10),
                          _SupportStatusLine(
                            title: 'Платформа',
                            ok: true,
                            value: _platformTitle,
                          ),
                          const SizedBox(height: 10),
                          _SupportStatusLine(
                            title: 'Версия на сервере',
                            ok: !hasUpdate,
                            value: manifest.latestVersion.isEmpty
                                ? 'не задана'
                                : displayedServerVersion,
                          ),
                          if (manifest.sha256.trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _SupportStatusLine(
                              title: 'Проверка файла',
                              ok: true,
                              value: 'Включена',
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (displayedChangelog.isNotEmpty) ...[
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
                            for (final item in displayedChangelog)
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              manifest.canDownload
                                  ? _installHint
                                  : 'Ссылка на скачивание пока не настроена на сервере.',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.62),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!_downloadLooksPlatformSpecific(
                              manifest.downloadUrl,
                            )) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Сервер обновлений вернул файл не для этой платформы. Установка заблокирована.',
                                style: TextStyle(
                                  color: kBrandDanger,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                            if (_downloadProgress != null) ...[
                              const SizedBox(height: 12),
                              LinearProgressIndicator(value: _downloadProgress),
                            ],
                            if (_downloadStatus != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _downloadStatus!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (_downloadError != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _downloadError!,
                                style: const TextStyle(
                                  color: kBrandDanger,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kBrandPrimary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed:
                                  manifest.canDownload &&
                                      _downloadLooksPlatformSpecific(
                                        manifest.downloadUrl,
                                      ) &&
                                      !_downloading
                                  ? _downloadAndInstall
                                  : null,
                              child: Text(
                                _downloading
                                    ? 'Обновление загружается...'
                                    : 'Обновить Green VPN',
                              ),
                            ),
                            if (_showManualDownloadLink &&
                                manifest.canDownload) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: null,
                                child: const Text('Открыть ссылку вручную'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
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
    final parts = <String>[plan, active];
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
  final _reasonCtl = TextEditingController();

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

  @override
  void dispose() {
    _reasonCtl.dispose();
    super.dispose();
  }

  String? _adminReason() {
    final reason = _reasonCtl.text.trim();
    if (reason.length >= 8) return reason;
    setState(() => _status = 'Укажите причину изменения: минимум 8 символов.');
    return null;
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
    final reason = _adminReason();
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      final res = await widget.api.adminSetSubscription(
        adminToken: widget.adminToken,
        userId: _userId,
        planCode: _planCode,
        planName: _planName,
        maxDevices: _maxDevices.clamp(1, 100),
        isActive: _isActive,
        expiresAt: _expiresAt,
        reason: reason,
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
    final reason = _adminReason();
    if (reason == null) return;
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
        reason: reason,
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
                                    'code': 'gb150',
                                    'title': '150 ГБ',
                                    'gb': 150,
                                  },
                                  {
                                    'code': 'gb350',
                                    'title': '350 ГБ',
                                    'gb': 350,
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
                                          _trafficGb = 800;
                                          _unlimitedAppCodes.clear();
                                        } else {
                                          _trafficGb = gb.clamp(1, 800);
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
                    value: _trafficGb.clamp(1, 800).toDouble(),
                    min: 1,
                    max: 800,
                    divisions: 799,
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
                    children: [5, 50, 150, 350]
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
                TextField(
                  controller: _reasonCtl,
                  minLines: 1,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Причина изменения',
                    hintText: 'Например: продление по обращению пользователя',
                  ),
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
                const _SectionTitle('Ручное управление доступом'),
                const SizedBox(height: 10),
                const Text(
                  'Служебный режим для поддержки. Основной способ — серверный тариф по каталогу выше.',
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
                        text: 'Пробный',
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
                        text: 'Базовый',
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
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
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
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
    final mutedColor = textColor.withValues(alpha: isDark ? 0.72 : 0.62);
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
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: InkWell(
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ],
        ),
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

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: InkWell(
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ],
        ),
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
        ? kBrandPrimary.withValues(alpha: 0.20)
        : theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.16 : 0.12);

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
          color: theme.colorScheme.onSurface.withValues(
            alpha: isDark ? 0.16 : 0.10,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: kBrandPrimary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              softWrap: true,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
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
        : (isDark
              ? Color.alphaBlend(tint!.withValues(alpha: 0.16), surface)
              : tint!);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : kBrandPrimaryDeep.withValues(alpha: 0.10),
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            offset: const Offset(0, 12),
            color: isDark
                ? Colors.black.withValues(alpha: 0.24)
                : kBrandPrimaryDeep.withValues(alpha: 0.08),
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
      return 'Есть другой активный VPN-интерфейс или сервис. Он может мешать подключению Green VPN.';
    }
    if (routeOwnerLabel != 'unknown' && routeOwnerLabel != tunnelName) {
      return 'Основной IPv4-маршрут сейчас принадлежит не $kTunnelName, а $routeOwnerLabel.';
    }
    if (routeOwnerLabel == tunnelName) {
      return 'Основной IPv4-маршрут уже у $kTunnelName.';
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
          '${wireguardExePath.substring(0, wireguardExePath.length - 'wireguard.exe'.length)}wg.exe';
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
      final res = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
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
      ], runInShell: false);
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
      final res = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
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
      ], runInShell: false);
      if (res.exitCode != 0) return const [];
      return _parseNonEmptyLines(res);
    } catch (_) {
      return const [];
    }
  }

  static Future<String?> _queryPrimaryDefaultRouteAlias() async {
    if (!Platform.isWindows) return null;
    try {
      final res = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''
$ErrorActionPreference="SilentlyContinue"
$route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' |
  Sort-Object RouteMetric, InterfaceMetric |
  Select-Object -First 1
if ($route) { $route.InterfaceAlias }
''',
      ], runInShell: false);
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
    bool includeEnvironmentDiagnostics = true,
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

    final otherActiveWireGuardInterfaces = includeEnvironmentDiagnostics
        ? await _queryOtherActiveWireGuardInterfaces(tunnelName)
        : const <String>[];
    final otherRunningWireGuardServices = includeEnvironmentDiagnostics
        ? await _queryOtherRunningWireGuardServices(serviceName)
        : const <String>[];
    final primaryDefaultRouteAlias = includeEnvironmentDiagnostics
        ? await _queryPrimaryDefaultRouteAlias()
        : null;

    final wgExe = _resolveWgExe(wireguardExePath);
    try {
      final res = await Process.run(wgExe, [
        'show',
        tunnelName,
        'dump',
      ], runInShell: true);
      final rawWgDump = ('${res.stdout ?? ''}\n${res.stderr ?? ''}').trim();

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
  final bool windowsFullTunnelDataPlaneConfirmed;

  const DiagnosticsPage({
    super.key,
    required this.accessToken,
    required this.email,
    required this.windowsFullTunnelDataPlaneConfirmed,
  });

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final _api = const BlueVpnApi(baseUrl: kApiBaseUrl);
  final _windowsSystemService = const _GreenVpnSystemServiceClient();

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
  _GreenVpnSystemServiceResponse? _windowsSystemStatus;
  Map<String, dynamic> _androidVpnStatus = const <String, dynamic>{};
  String? _fallbackReportCode;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    final cfg = ConfigStore();
    _runtimeStatus = null;
    _windowsSystemStatus = null;
    _androidVpnStatus = const <String, dynamic>{};

    if (!kIsWeb && Platform.isAndroid) {
      _statePath = 'Android secure storage';
      _deviceUid = (await DeviceIdStore().read()) ?? '';
      _configPath = cfg.managedConfigPath;
      _configExists = await cfg.hasManagedConfig();
      _wgExe = 'Android WireGuard GoBackend';
      _wgFound = true;
      _isAdmin = false;
      _androidVpnStatus = await WireGuardAndroidBackend.statusSnapshot();

      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

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

    _configPath = cfg.managedConfigPath;
    _configExists = File(_configPath).existsSync();

    _wgExe = _resolveWireGuardExe();
    _wgFound =
        File(_wgExe).existsSync() || _wgExe.toLowerCase() == 'wireguard.exe';

    _isAdmin = await _isAdminWindows();
    final windowsSystemStatus = !kIsWeb && Platform.isWindows
        ? await _windowsSystemService.status()
        : null;
    _runtimeStatus = await WireGuardRuntimeStatus.query(
      tunnelName: kTunnelName,
      configPath: _configPath,
      wireguardExePath: _wgExe,
    );
    _windowsSystemStatus = windowsSystemStatus;

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

  bool get _isAndroidDiagnostics => !kIsWeb && Platform.isAndroid;

  bool get _isWindowsDiagnostics => !kIsWeb && Platform.isWindows;

  GreenVpnWindowsDiagnosticsConnectionState _windowsConnectionState(
    WireGuardRuntimeStatus? runtime,
  ) {
    final status = _windowsSystemStatus;
    return greenVpnWindowsDiagnosticsConnectionState(
      requestOk: status?.ok == true,
      data: status?.data ?? const <String, dynamic>{},
      fullTunnelDataPlaneConfirmed: widget.windowsFullTunnelDataPlaneConfirmed,
      legacyConnected: runtime?.isReallyConnected == true,
      legacyActivity:
          runtime?.hasRecentHandshake == true || runtime?.hasTraffic == true,
    );
  }

  String _windowsModeLabel(WireGuardRuntimeStatus? runtime) {
    final status = _windowsSystemStatus;
    final mode = greenVpnClassifyWindowsRoutingMode(
      requestOk: status?.ok == true,
      data: status?.data ?? const <String, dynamic>{},
    );
    return switch (mode) {
      GreenVpnWindowsRoutingMode.full => 'full tunnel',
      GreenVpnWindowsRoutingMode.applications => 'selected applications',
      GreenVpnWindowsRoutingMode.unknown => runtime?.modeLabel ?? 'unknown',
    };
  }

  Map<String, Object?>? _androidSupportFields() {
    if (!_isAndroidDiagnostics) return null;
    final safe = greenVpnSafeAndroidVpnStatus(_androidVpnStatus);
    final connected =
        safe['connected'] == true ||
        safe['ownTunnelRunning'] == true ||
        safe['state'] == 'up';
    final systemVpnActive = safe['systemVpnActive'] == true;
    final externalVpnActive =
        safe['externalVpnActive'] == true ||
        safe['systemVpnActiveWithoutOwnTunnel'] == true ||
        (systemVpnActive && !connected);
    final rxBytes = greenVpnIntValue(safe['rxBytes']);
    final txBytes = greenVpnIntValue(safe['txBytes']);
    final hasTraffic = rxBytes > 0 || txBytes > 0;
    return <String, Object?>{
      'service': 'android_vpn_service',
      'mode': connected
          ? 'android_wireguard'
          : (externalVpnActive ? 'android_external_vpn' : 'android_down'),
      'hasHandshake': connected && hasTraffic,
      'hasTraffic': hasTraffic,
      'traffic':
          'rx ${WireGuardRuntimeStatus._formatBytes(rxBytes)} / tx ${WireGuardRuntimeStatus._formatBytes(txBytes)}',
      'realTunnel': connected,
      'competingVpn': externalVpnActive ? 'external_vpn_active' : 'none',
      'routeOwner': connected
          ? 'green_vpn_android_vpn_service'
          : (externalVpnActive ? 'android_system_external_vpn' : 'unknown'),
      'routeHint': connected
          ? 'Android VpnService is active. Use route events for YouTube reachability.'
          : (externalVpnActive
                ? 'Another Android VPN is active. Green VPN must take over before route checks are valid.'
                : 'Android VpnService is not active.'),
      'endpoint': 'android-native',
      'androidStatus': safe,
    };
  }

  Future<String> _buildSupportReportCode() async {
    final runtime = _runtimeStatus;
    final android = _androidSupportFields();
    final windowsConnectionState = _isWindowsDiagnostics
        ? _windowsConnectionState(runtime)
        : null;
    final windowsRealTunnel = windowsConnectionState == null
        ? null
        : windowsConnectionState ==
              GreenVpnWindowsDiagnosticsConnectionState.active;
    final windowsMode = _isWindowsDiagnostics
        ? _windowsModeLabel(runtime)
        : null;
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
      'service': android?['service'] ?? runtime?.serviceState ?? 'unknown',
      'mode':
          android?['mode'] ?? windowsMode ?? runtime?.modeLabel ?? 'unknown',
      'hasHandshake':
          android?['hasHandshake'] ?? runtime?.hasRecentHandshake ?? false,
      'hasTraffic': android?['hasTraffic'] ?? runtime?.hasTraffic ?? false,
      'traffic':
          android?['traffic'] ?? runtime?.trafficLabel ?? 'rx 0 B / tx 0 B',
      'realTunnel':
          android?['realTunnel'] ??
          windowsRealTunnel ??
          runtime?.isReallyConnected ??
          false,
      'competingVpn':
          android?['competingVpn'] ?? runtime?.competingTunnelsLabel ?? 'none',
      'routeOwner':
          android?['routeOwner'] ?? runtime?.routeOwnerLabel ?? 'unknown',
      'routeHint': android?['routeHint'] ?? runtime?.routeConflictHint ?? '',
      'endpoint': android?['endpoint'] ?? runtime?.bestEndpoint ?? '',
      if (android?['androidStatus'] != null)
        'androidStatus': android?['androidStatus'],
    };
    final jsonBytes = utf8.encode(jsonEncode(payload));
    final packed = gzip.encode(jsonBytes);
    return 'GVPN1.${base64UrlEncode(packed)}';
  }

  String _supportSummary() {
    final runtime = _runtimeStatus;
    final android = _androidSupportFields();
    final windowsConnectionState = _isWindowsDiagnostics
        ? _windowsConnectionState(runtime)
        : null;
    final windowsMode = _isWindowsDiagnostics
        ? _windowsModeLabel(runtime)
        : null;
    final parts = <String>[
      'service=${android?['service'] ?? runtime?.serviceState ?? 'unknown'}',
      'mode=${android?['mode'] ?? windowsMode ?? runtime?.modeLabel ?? 'unknown'}',
      if (windowsConnectionState != null)
        'connection=${windowsConnectionState.name}',
      'handshake=${(android?['hasHandshake'] ?? runtime?.hasRecentHandshake ?? false) == true ? 'yes' : 'no'}',
      'traffic=${android?['traffic'] ?? runtime?.trafficLabel ?? 'rx 0 B / tx 0 B'}',
      'competing=${android?['competingVpn'] ?? runtime?.competingTunnelsLabel ?? 'none'}',
      'route=${android?['routeOwner'] ?? runtime?.routeOwnerLabel ?? 'unknown'}',
    ];
    return parts.join(', ');
  }

  Future<void> _sendReport() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _lastSendMessage = null;
    });

    final reportCode = await _buildSupportReportCode();
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
    final android = _androidSupportFields();
    final serviceState =
        (android?['service'] ?? runtime?.serviceState ?? 'unknown').toString();
    final handshakeOk =
        (android?['hasHandshake'] ?? runtime?.hasRecentHandshake ?? false) ==
        true;
    final trafficOk =
        (android?['hasTraffic'] ?? runtime?.hasTraffic ?? false) == true;
    final realTunnelOk =
        (android?['realTunnel'] ??
            (_isWindowsDiagnostics
                ? _windowsConnectionState(runtime) ==
                      GreenVpnWindowsDiagnosticsConnectionState.active
                : runtime?.isReallyConnected) ??
            false) ==
        true;
    final windowsConnectionState = _isWindowsDiagnostics
        ? _windowsConnectionState(runtime)
        : null;
    final connectionChecking =
        windowsConnectionState ==
            GreenVpnWindowsDiagnosticsConnectionState.checking ||
        (windowsConnectionState == null &&
            !realTunnelOk &&
            (handshakeOk || trafficOk));
    final connectionUnknown =
        windowsConnectionState ==
        GreenVpnWindowsDiagnosticsConnectionState.unknown;
    final competingTunnels =
        (android?['competingVpn'] ?? runtime?.competingTunnelsLabel ?? 'none')
            .toString();
    final serviceOk = _isAndroidDiagnostics
        ? _wgFound
        : serviceState == 'running' || serviceState == 'stopped';

    return Scaffold(
      appBar: AppBar(
        title: Text(kFusionUiEnabled ? 'Диагностика' : 'Поддержка'),
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
                _PageTitle(
                  title: kFusionUiEnabled
                      ? 'Диагностика и отчёт'
                      : 'Помощь и отчёт',
                  subtitle:
                      'Если VPN не подключается или работает странно, отправь отчёт в поддержку одной кнопкой.',
                  icon: kFusionUiEnabled
                      ? Icons.health_and_safety_outlined
                      : Icons.support_agent_rounded,
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
                            : connectionChecking
                            ? 'проверяется'
                            : connectionUnknown
                            ? 'не удалось проверить'
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
                          ).colorScheme.onSurface.withValues(alpha: 0.62),
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
    final valueStyle = TextStyle(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
      fontWeight: FontWeight.w800,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.info_rounded,
          color: ok ? kBrandPrimary : kBrandWarm,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                softWrap: true,
                overflow: TextOverflow.visible,
                style: valueStyle,
              ),
            ],
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
      if (kTransportPreviewFallbackEnabled) {
        return WindowsTransportPreviewBackend(tunnelName: tunnelName);
      }
      return WireGuardWindowsBackend(tunnelName: tunnelName);
    }
    if (Platform.isAndroid) {
      return WireGuardAndroidBackend(tunnelName: tunnelName);
    }
    return const UnsupportedVpnBackend(
      reason:
          'На этой платформе реальное VPN-подключение пока не включено. Android уже поддерживается, iOS требует Apple Network Extension.',
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

class WireGuardAndroidBackend extends VpnBackend {
  static const MethodChannel _channel = MethodChannel('green_vpn/android_vpn');

  final String tunnelName;

  const WireGuardAndroidBackend({required this.tunnelName});

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    try {
      final config = await ConfigStore().readManagedConfig();
      if (config == null || config.trim().isEmpty) {
        return const VpnBackendResult(
          ok: false,
          message:
              'VPN-конфиг ещё не получен. Войди в аккаунт и попробуй подключиться снова.',
        );
      }

      final response = await _invokeMap('connect', {
        'name': tunnelName,
        'config': config,
        'protocol': await ConfigStore().readManagedProtocol(),
      });
      return VpnBackendResult(
        ok: response['ok'] == true,
        message: _messageFromNative(response),
      );
    } catch (e) {
      return VpnBackendResult(ok: false, message: 'Android VPN не ответил: $e');
    }
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    try {
      final response = await _invokeMap('disconnect', {'name': tunnelName});
      return VpnBackendResult(
        ok: response['ok'] == true,
        message: _messageFromNative(response),
      );
    } catch (e) {
      return VpnBackendResult(
        ok: false,
        message: 'Android VPN не выключился: $e',
      );
    }
  }

  @override
  Future<bool> isConnected() async {
    try {
      final response = await _invokeMap('status', {'name': tunnelName});
      return statusLooksConnected(response, tunnelName: tunnelName);
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> statusSnapshot({
    String tunnelName = kTunnelName,
  }) async {
    try {
      return await _invokeMap('status', {'name': tunnelName});
    } catch (e) {
      return <String, dynamic>{
        'ok': false,
        'connected': false,
        'state': 'unknown',
        'error': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> _invokeMap(
    String method,
    Map<String, Object?> args,
  ) async {
    final raw = await _channel.invokeMethod<Object?>(method, args);
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry('$key', value));
    }
    return const <String, dynamic>{};
  }

  static bool statusLooksConnected(
    Map<String, dynamic> status, {
    String tunnelName = kTunnelName,
  }) {
    final state = (status['state'] ?? '').toString().toLowerCase();
    if (status['connected'] == true ||
        status['ownTunnelRunning'] == true ||
        state == 'up') {
      return true;
    }
    if (status['systemVpnActive'] == true &&
        (status['lastGreenVpnActive'] == true ||
            status['ownTunnelSource'] == 'marker')) {
      return true;
    }
    final nativeTunnelName = (status['nativeTunnelName'] ?? '').toString();
    final expectedNames = <String>{
      tunnelName,
      if (nativeTunnelName.isNotEmpty) nativeTunnelName,
      'GreenVPN',
    };
    final running = status['runningTunnels'];
    if (running is Iterable) {
      return running.any((item) => expectedNames.contains(item.toString()));
    }
    return false;
  }

  static String? _messageFromNative(Map<String, dynamic> response) {
    final message = (response['message'] ?? '').toString().trim();
    return message.isEmpty ? null : message;
  }
}

class _GreenVpnSystemServiceResponse {
  final bool ok;
  final int statusCode;
  final int? exitCode;
  final String? message;
  final Map<String, dynamic> data;

  const _GreenVpnSystemServiceResponse({
    required this.ok,
    required this.statusCode,
    this.exitCode,
    this.message,
    this.data = const <String, dynamic>{},
  });

  bool get unavailable => statusCode == 0;
}

class _GreenVpnSystemServiceClient {
  const _GreenVpnSystemServiceClient();

  static final Uri _baseUri = Uri.parse(
    'http://127.0.0.1:$greenVpnLocalServicePort',
  );
  static const String _localTokenHeader = 'X-GreenVPN-Local-Token';

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

  Future<_GreenVpnSystemServiceResponse> status() => _request(
    'GET',
    '/status',
    connectTimeout: const Duration(milliseconds: 700),
    responseTimeout: const Duration(seconds: 3),
  );

  Future<_GreenVpnSystemServiceResponse> probeStandby() => _request(
    'POST',
    '/standby/probe',
    connectTimeout: const Duration(seconds: 2),
    responseTimeout: const Duration(seconds: 65),
  );

  Future<_GreenVpnSystemServiceResponse> cancelStandbyProbe() => _request(
    'POST',
    '/standby/cancel',
    connectTimeout: const Duration(seconds: 2),
    responseTimeout: const Duration(seconds: 5),
  );

  Future<_GreenVpnSystemServiceResponse> _request(
    String method,
    String path, {
    required Duration connectTimeout,
    required Duration responseTimeout,
  }) async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final token = await _readLocalToken();
      if (_requiresLocalToken(path) && token == null) {
        return const _GreenVpnSystemServiceResponse(
          ok: false,
          statusCode: 0,
          message:
              'Локальный системный компонент Green VPN установлен без защитного токена. Переустанови последнюю версию GreenVPN_Setup.exe один раз с правами администратора.',
        );
      }

      final uri = _baseUri.resolve(path);
      final request = method == 'POST'
          ? await client.postUrl(uri).timeout(connectTimeout)
          : await client.getUrl(uri).timeout(connectTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null) {
        request.headers.set(_localTokenHeader, token);
      }
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
        data: json,
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

  static bool _requiresLocalToken(String path) {
    final lower = path.toLowerCase();
    return lower == '/connect' ||
        lower == '/disconnect' ||
        lower == '/status' ||
        lower == '/standby/probe' ||
        lower == '/standby/cancel';
  }

  static Future<String?> _readLocalToken() async {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      final file = File(greenVpnServiceTokenPathSync());
      if (!file.existsSync()) return null;
      final token = (await file.readAsString()).trim();
      if (token.length < 24) return null;
      return token;
    } catch (_) {
      return null;
    }
  }
}

class WindowsTransportPreviewBackend extends VpnBackend {
  final WireGuardWindowsBackend _wireGuard;
  final AmneziaWgWindowsPreviewBackend _amneziaWg;
  final SystemServiceWindowsPreviewBackend _hysteria2;
  final SystemServiceWindowsPreviewBackend _vlessReality;
  final SystemServiceWindowsPreviewBackend _naiveHttps;
  final SystemServiceWindowsPreviewBackend _dnstt;

  WindowsTransportPreviewBackend({required String tunnelName})
    : _wireGuard = WireGuardWindowsBackend(tunnelName: tunnelName),
      _amneziaWg = AmneziaWgWindowsPreviewBackend(tunnelName: tunnelName),
      _hysteria2 = const SystemServiceWindowsPreviewBackend(
        protocol: 'hysteria2',
        enabled: kHysteria2PreviewEnabled,
      ),
      _vlessReality = const SystemServiceWindowsPreviewBackend(
        protocol: 'vless_reality',
        enabled: kVlessRealityPreviewEnabled,
      ),
      _naiveHttps = const SystemServiceWindowsPreviewBackend(
        protocol: 'naive_https',
        enabled: kNaiveHttpsPreviewEnabled,
      ),
      _dnstt = const SystemServiceWindowsPreviewBackend(
        protocol: 'dnstt',
        enabled: kDnsttPreviewEnabled,
      );

  Future<String> _managedProtocol(String configPath) async {
    try {
      final sidecar = File('$configPath.protocol');
      if (!sidecar.existsSync()) return 'wireguard_udp';
      final value = (await sidecar.readAsString()).trim().toLowerCase();
      return value.isEmpty ? 'wireguard_udp' : value;
    } catch (_) {
      return 'wireguard_udp';
    }
  }

  Future<bool> _waitForServiceCleanDown(
    _GreenVpnSystemServiceClient service,
  ) async {
    const componentStateKeys = <String>[
      'tunnelState',
      'wireGuardState',
      'amneziaWgState',
      'hysteriaClientState',
      'hysteriaTunState',
      'vlessClientState',
      'vlessTunState',
      'naiveClientState',
      'naiveTunState',
      'dnsttClientState',
      'dnsttTunState',
    ];
    for (var attempt = 0; attempt < 40; attempt += 1) {
      final status = await service.status();
      if (status.ok) {
        final anyRunning = componentStateKeys.any(
          (key) => status.data[key]?.toString().toLowerCase() == 'running',
        );
        if (!anyRunning) return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    final protocol = await _managedProtocol(configPath);
    if (protocol == 'amneziawg') {
      return _amneziaWg.connect(configPath: configPath);
    }
    if (protocol == 'hysteria2') {
      return _hysteria2.connect(configPath: configPath);
    }
    if (protocol == 'vless_reality') {
      return _vlessReality.connect(configPath: configPath);
    }
    if (protocol == 'naive_https') {
      return _naiveHttps.connect(configPath: configPath);
    }
    if (protocol == 'dnstt') {
      return _dnstt.connect(configPath: configPath);
    }
    if (protocol != 'wireguard_udp') {
      return VpnBackendResult(
        ok: false,
        message: 'Unsupported Windows preview transport: $protocol',
      );
    }
    return _wireGuard.connect(configPath: configPath);
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    const service = _GreenVpnSystemServiceClient();
    final ping = await service.ping();
    if (!ping.ok) {
      return const VpnBackendResult(
        ok: false,
        message:
            'Системный компонент Green VPN не отвечает. Автоматическая очистка всех транспортов остановлена. Переустанови последнюю версию GreenVPN_Setup.exe один раз с правами администратора.',
      );
    }

    final response = await service.disconnect();
    if (!response.ok) {
      return VpnBackendResult(
        ok: false,
        message:
            response.message ??
            'Системный компонент не смог полностью остановить VPN.',
      );
    }
    if (!await _waitForServiceCleanDown(service)) {
      return const VpnBackendResult(
        ok: false,
        message:
            'Один из компонентов VPN остался активен после остановки. Другой маршрут не будет запущен.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  @override
  Future<bool> isConnected() async {
    const service = _GreenVpnSystemServiceClient();
    final status = await service.status();
    final managedState = greenVpnClassifyWindowsManagedTunnelStatus(
      requestOk: status.ok,
      data: status.data,
    );
    if (managedState == GreenVpnWindowsManagedTunnelState.connected) {
      return true;
    }
    if (managedState == GreenVpnWindowsManagedTunnelState.disconnected) {
      return false;
    }
    if (await _dnstt.isConnected()) return true;
    if (await _naiveHttps.isConnected()) return true;
    if (await _vlessReality.isConnected()) return true;
    if (await _hysteria2.isConnected()) return true;
    if (await _amneziaWg.isConnected()) return true;
    return _wireGuard.isConnected();
  }
}

class SystemServiceWindowsPreviewBackend extends VpnBackend {
  final String protocol;
  final bool enabled;

  const SystemServiceWindowsPreviewBackend({
    required this.protocol,
    required this.enabled,
  });

  Future<bool> _waitForState(bool running) async {
    const service = _GreenVpnSystemServiceClient();
    for (var attempt = 0; attempt < 80; attempt++) {
      final status = await service.status();
      final isRunning =
          status.ok &&
          status.data['protocol'] == protocol &&
          status.data['tunnelState'] == 'running';
      if (isRunning == running) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    if (!enabled) {
      return const VpnBackendResult(
        ok: false,
        message: 'Резервный Windows preview отключён в этой сборке.',
      );
    }
    if (!File(configPath).existsSync()) {
      return const VpnBackendResult(
        ok: false,
        message: 'Конфиг резервного подключения отсутствует.',
      );
    }
    const service = _GreenVpnSystemServiceClient();
    final ping = await service.ping();
    if (!ping.ok) {
      return const VpnBackendResult(
        ok: false,
        message:
            'Системный компонент preview недоступен. Переустанови preview один раз с правами администратора.',
      );
    }
    final response = await service.connect();
    if (!response.ok) {
      return VpnBackendResult(
        ok: false,
        message:
            response.statusCode == HttpStatus.conflict || response.exitCode == 2
            ? 'Green VPN не смог автоматически остановить другой активный VPN. Закрой его вручную и повтори подключение.'
            : (response.message ?? 'Резервное подключение не запустилось.'),
      );
    }
    if (!await _waitForState(true)) {
      await service.disconnect();
      return const VpnBackendResult(
        ok: false,
        message: 'Резервное подключение не подтвердило рабочее состояние.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    const service = _GreenVpnSystemServiceClient();
    final response = await service.disconnect();
    if (!response.ok) {
      return VpnBackendResult(
        ok: false,
        message: response.message ?? 'Не удалось отключить резервный режим.',
      );
    }
    if (!await _waitForState(false)) {
      return const VpnBackendResult(
        ok: false,
        message: 'Резервный режим не завершился полностью.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  @override
  Future<bool> isConnected() async {
    const service = _GreenVpnSystemServiceClient();
    final status = await service.status();
    return status.ok &&
        status.data['protocol'] == protocol &&
        status.data['tunnelState'] == 'running';
  }
}

class AmneziaWgWindowsPreviewBackend extends VpnBackend {
  final String tunnelName;

  const AmneziaWgWindowsPreviewBackend({required this.tunnelName});

  String get _serviceName => r'AmneziaWGTunnel$' + tunnelName;

  Future<ProcessResult> _run(String executable, List<String> arguments) {
    return Process.run(executable, arguments, runInShell: true);
  }

  bool _serviceOutputLooksRunning(ProcessResult result) {
    if (result.exitCode != 0) return false;
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return RegExp(r'state\s*:\s*4\b').hasMatch(output) ||
        output.contains('running');
  }

  Future<bool> _serviceRunning() async {
    try {
      return _serviceOutputLooksRunning(
        await _run('sc.exe', ['query', _serviceName]),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _waitForService({required bool running}) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      final current = await _serviceRunning();
      if (current == running) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<void> _log(String message) async {
    try {
      final file = File(greenVpnBackendLogPathSync());
      await file.writeAsString(
        '[${DateTime.now().toIso8601String()}] windows-awg2 $message\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    if (!kAwg2PreviewEnabled) {
      return const VpnBackendResult(
        ok: false,
        message: 'AWG2 Windows preview is disabled in this build.',
      );
    }
    if (!File(configPath).existsSync()) {
      return VpnBackendResult(
        ok: false,
        message: 'Config not found: $configPath',
      );
    }

    const service = _GreenVpnSystemServiceClient();
    final ping = await service.ping();
    await _log(
      'connect ping ok=${ping.ok} http=${ping.statusCode} service=$_serviceName',
    );
    if (!ping.ok) {
      return const VpnBackendResult(
        ok: false,
        message:
            'Windows transport preview service is unavailable. Reinstall the preview package once with administrator rights.',
      );
    }

    final response = await service.connect();
    await _log(
      'connect response ok=${response.ok} http=${response.statusCode} exit=${response.exitCode}',
    );
    if (!response.ok) {
      return VpnBackendResult(
        ok: false,
        message:
            response.statusCode == HttpStatus.conflict || response.exitCode == 2
            ? 'Green VPN could not stop the active VPN automatically. Close it manually and try again.'
            : (response.message ?? 'Windows AWG2 preview connect failed.'),
      );
    }
    if (!await _waitForService(running: true)) {
      return const VpnBackendResult(
        ok: false,
        message: 'AWG2 tunnel service did not reach Running state.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    const service = _GreenVpnSystemServiceClient();
    final ping = await service.ping();
    if (!ping.ok) {
      return const VpnBackendResult(
        ok: false,
        message: 'Windows transport preview service is unavailable.',
      );
    }
    final response = await service.disconnect();
    await _log(
      'disconnect response ok=${response.ok} http=${response.statusCode} exit=${response.exitCode}',
    );
    if (!response.ok) {
      return VpnBackendResult(
        ok: false,
        message: response.message ?? 'Windows AWG2 preview disconnect failed.',
      );
    }
    if (!await _waitForService(running: false)) {
      return const VpnBackendResult(
        ok: false,
        message: 'AWG2 tunnel service is still running after disconnect.',
      );
    }
    return const VpnBackendResult(ok: true);
  }

  @override
  Future<bool> isConnected() => _serviceRunning();
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

  bool _applicationRoutingRequested() {
    try {
      final mode = File(
        greenVpnWindowsRoutingModePathSync(),
      ).readAsStringSync().trim().toLowerCase();
      return mode == 'applications';
    } catch (_) {
      return false;
    }
  }

  bool _processRouterRequired() {
    try {
      final raw = File(greenVpnWindowsRoutingAppsPathSync()).readAsStringSync();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return true;
      final applications = decoded['applications'];
      return applications is! List || applications.isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _processRouterIsReady({
    required Future<void> Function(String) log,
  }) async {
    if (!_applicationRoutingRequested()) return true;
    const systemService = _GreenVpnSystemServiceClient();
    final response = await systemService.status();
    final routingMode = response.data['routingMode']?.toString() ?? '';
    final routerState = response.data['processRouterState']?.toString() ?? '';
    final routerRequired = _processRouterRequired();
    await log(
      'application routing status ok=${response.ok} mode=$routingMode router=$routerState required=$routerRequired',
    );
    return response.ok &&
        routingMode == 'applications' &&
        (!routerRequired || routerState == 'running');
  }

  Future<ProcessResult> _run(String exe, List<String> args) async {
    return Process.run(exe, args, runInShell: true);
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
      'RemoteSigned',
      '-Command',
      _adapterStateScript(),
    ]);
    return ('${res.stdout ?? ''}\n${res.stderr ?? ''}').trim();
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
      'RemoteSigned',
      '-Command',
      script,
    ]);
    final raw = ('${res.stdout ?? ''}\n${res.stderr ?? ''}').trim();
    return int.tryParse(raw);
  }

  Future<void> _forceKillServicePid({
    required Future<void> Function(String) log,
  }) async {
    final pid = await _queryServicePid();
    await log(
      'service pid=${pid?.toString() ?? 'none'}; taskkill skipped by safety policy',
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
        'adapter-state[$i] ${state.replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
      );
      if (!_adapterStillBlocksTraffic(state)) return true;
      await Future.delayed(const Duration(milliseconds: 350));
    }
    return false;
  }

  @override
  Future<VpnBackendResult> connect({required String configPath}) async {
    _lastConfigPath = configPath;
    final logFile = File(greenVpnBackendLogPathSync());

    Future<void> log(String s) async {
      try {
        final ts = DateTime.now().toIso8601String();
        await logFile.writeAsString('[$ts] $s\n', mode: FileMode.append);
      } catch (_) {}
    }

    String outOf(ProcessResult r) =>
        ('${r.stdout ?? ''}\n${r.stderr ?? ''}').trim();

    bool isRunningText(String out) => out.contains('RUNNING');
    Future<ProcessResult> scQueryEx() => _run('sc', ['queryex', _serviceName]);
    Future<WireGuardRuntimeStatus> runtimeStatus({
      bool includeEnvironmentDiagnostics = true,
    }) => WireGuardRuntimeStatus.query(
      tunnelName: tunnelName,
      configPath: configPath,
      wireguardExePath: _exe,
      includeEnvironmentDiagnostics: includeEnvironmentDiagnostics,
    );
    Future<void> prepareConfigForService() async {
      try {
        final f = File(configPath);
        if (!f.parent.existsSync()) {
          f.parent.createSync(recursive: true);
        }
        await WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path);
        if (f.existsSync()) {
          await WindowsLocalSecurity.prepareSharedConfigFile(f.path);
        }
      } catch (_) {}
    }

    Future<bool> waitRunning({int loops = 60}) async {
      for (var i = 0; i < loops; i++) {
        final q = await scQueryEx();
        final o = outOf(q);
        await log(
          'queryex(connect)[$i] ec=${q.exitCode} :: ${o.replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
        );
        if (q.exitCode == 0 && isRunningText(o)) return true;
        await Future.delayed(const Duration(milliseconds: 250));
      }
      return false;
    }

    Future<bool> isAdmin() async {
      try {
        final res = await _run('whoami', ['/groups']);
        final out = ('${res.stdout ?? ''}\n${res.stderr ?? ''}');
        return out.contains('S-1-16-12288') || out.contains('S-1-16-16384');
      } catch (_) {
        return false;
      }
    }

    try {
      await log('=== CONNECT requested ===');
      await log('service=$_serviceName');
      await log('exe=$_exe');
      await log('cfg=$configPath');

      if (!File(configPath).existsSync()) {
        await log('ERROR: configPath does not exist');
        return VpnBackendResult(
          ok: false,
          message: 'Config not found: $configPath',
        );
      }

      var startedBySystemService = false;
      const systemService = _GreenVpnSystemServiceClient();
      final servicePing = await systemService.ping();
      await log(
        'native service fast-path ping ok=${servicePing.ok} http=${servicePing.statusCode} msg=${servicePing.message ?? ''}',
      );
      if (servicePing.ok) {
        final serviceConnect = await systemService.connect();
        await log(
          'native service fast-path connect ok=${serviceConnect.ok} http=${serviceConnect.statusCode} exit=${serviceConnect.exitCode} msg=${serviceConnect.message ?? ''}',
        );
        if (serviceConnect.ok) {
          startedBySystemService = true;
        } else if (serviceConnect.statusCode == HttpStatus.conflict ||
            serviceConnect.exitCode == 2) {
          return const VpnBackendResult(
            ok: false,
            message:
                'Green VPN не смог автоматически остановить другой активный VPN. Закрой его вручную и повтори подключение.',
          );
        } else {
          return const VpnBackendResult(
            ok: false,
            message:
                'Системный компонент Green VPN не смог запустить подключение. Переустанови последнюю версию GreenVPN_Setup.exe.',
          );
        }
      }

      if (!startedBySystemService) {
        await prepareConfigForService();
        final preflight = await WireGuardRuntimeStatus.query(
          tunnelName: tunnelName,
          configPath: configPath,
          wireguardExePath: _exe,
        );
        await log('direct fallback preflight(connect) ${preflight.describe()}');
        if (preflight.hasCompetingTunnel) {
          await log(
            '=== CONNECT TAKEOVER: competing VPN active :: ${preflight.competingTunnelsLabel}',
          );
        }

        final q0 = await scQueryEx();
        final o0 = outOf(q0);
        await log(
          'direct fallback queryex(initial) ec=${q0.exitCode} :: ${o0.replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
        );
        final admin = await isAdmin();
        final applicationRoutingRequested = _applicationRoutingRequested();
        await log('direct fallback isAdmin=$admin');
        await log(
          'direct fallback applicationRoutingRequested=$applicationRoutingRequested',
        );
        if (!admin ||
            applicationRoutingRequested ||
            preflight.hasCompetingTunnel) {
          await log(
            'native service unavailable; guarded direct fallback is not eligible',
          );
          return const VpnBackendResult(
            ok: false,
            message:
                'Системный компонент Green VPN не отвечает. Переустанови последнюю версию GreenVPN_Setup.exe один раз с правами администратора.',
          );
        }

        if (q0.exitCode == 0) {
          final stop = await _run('sc', ['stop', _serviceName]);
          await log(
            'direct fallback sc stop before reinstall ec=${stop.exitCode} :: ${outOf(stop).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
          );
          await Future.delayed(const Duration(milliseconds: 700));
          final un = await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
          await log(
            'direct fallback wireguard uninstall before reinstall ec=${un.exitCode} :: ${outOf(un).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
          );
        }

        final cleanup = await _cleanupLingeringAdapter(elevated: true);
        await log(
          'direct fallback adapter cleanup before install ec=${cleanup.exitCode} :: ${outOf(cleanup).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
        );
        final cleaned = await _waitForAdapterCleanup(log: log);
        await log('direct fallback adapter cleanup settled=$cleaned');
        final ins = await _run(_exe, ['/installtunnelservice', configPath]);
        await log(
          'direct fallback wireguard install ec=${ins.exitCode} :: ${outOf(ins).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
        );
        final manualStart = await _setTunnelServiceManualStart();
        await log(
          'direct fallback sc config demand ec=${manualStart.exitCode} :: ${outOf(manualStart).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
        );
        final st = await _run('sc', ['start', _serviceName]);
        await log(
          'direct fallback sc start ec=${st.exitCode} :: ${outOf(st).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
        );
      }

      if (startedBySystemService) {
        await log(
          '=== CONNECT OK: privileged task confirmed tunnel service running; deep verification moved to background ===',
        );
        return const VpnBackendResult(ok: true);
      }

      final ok = await waitRunning(loops: 60);
      if (!ok) {
        await log('=== CONNECT FAIL: not RUNNING after wait ===');
        if (await isAdmin()) {
          final un = await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
          await log(
            'wireguard uninstall after failed start ec=${un.exitCode} :: ${outOf(un).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
          );
        } else {
          const systemService = _GreenVpnSystemServiceClient();
          final serviceDisconnect = await systemService.disconnect();
          await log(
            'native service uninstall after failed start ok=${serviceDisconnect.ok} http=${serviceDisconnect.statusCode} exit=${serviceDisconnect.exitCode} msg=${serviceDisconnect.message ?? ''}',
          );
          if (!serviceDisconnect.ok) {
            await log(
              'native service uninstall after failed start did not complete',
            );
          }
        }
        return const VpnBackendResult(
          ok: false,
          message: 'VPN did not start (service not RUNNING). See backend.log',
        );
      }

      final confirmationWatch = Stopwatch()..start();
      var verificationAttempt = 0;
      var consecutiveMissingInterfaceChecks = 0;
      while (greenVpnShouldContinueWindowsWireGuardConfirmation(
        elapsed: confirmationWatch.elapsed,
        consecutiveMissingInterfaceChecks: consecutiveMissingInterfaceChecks,
      )) {
        final status = await runtimeStatus(
          includeEnvironmentDiagnostics: false,
        );
        if (status.serviceState == 'running' && !status.interfacePresent) {
          consecutiveMissingInterfaceChecks += 1;
        } else {
          consecutiveMissingInterfaceChecks = 0;
        }
        await log(
          'verify(connect)[$verificationAttempt] elapsedMs=${confirmationWatch.elapsedMilliseconds} missingInterfaceChecks=$consecutiveMissingInterfaceChecks ${status.describe()}',
        );
        if (status.isReallyConnected && await _processRouterIsReady(log: log)) {
          await log('=== CONNECT OK ===');
          return const VpnBackendResult(ok: true);
        }
        verificationAttempt += 1;
        if (!greenVpnShouldContinueWindowsWireGuardConfirmation(
          elapsed: confirmationWatch.elapsed,
          consecutiveMissingInterfaceChecks: consecutiveMissingInterfaceChecks,
        )) {
          break;
        }
        final remaining =
            greenVpnWindowsWireGuardConfirmationBudget -
            confirmationWatch.elapsed;
        final delay =
            remaining < greenVpnWindowsWireGuardConfirmationPollInterval
            ? remaining
            : greenVpnWindowsWireGuardConfirmationPollInterval;
        if (delay > Duration.zero) {
          await Future.delayed(delay);
        }
      }

      final status = await runtimeStatus();
      await log(
        '=== CONNECT FAIL: real tunnel not confirmed checks=$verificationAttempt elapsedMs=${confirmationWatch.elapsedMilliseconds} missingInterfaceChecks=$consecutiveMissingInterfaceChecks :: ${status.describe()}',
      );
      if (_applicationRoutingRequested()) {
        const systemService = _GreenVpnSystemServiceClient();
        final serviceDisconnect = await systemService.disconnect();
        await log(
          'application routing fail-safe disconnect ok=${serviceDisconnect.ok} http=${serviceDisconnect.statusCode} exit=${serviceDisconnect.exitCode}',
        );
      }
      return VpnBackendResult(
        ok: false,
        message:
            'VPN запустился, но подключение не подтвердилось. Открой диагностику и отправь отчёт в поддержку.',
      );
    } catch (e) {
      await log('EXCEPTION(connect): $e');
      return VpnBackendResult(
        ok: false,
        message: 'Connect error: $e (see backend.log)',
      );
    }
  }

  @override
  Future<VpnBackendResult> disconnect() async {
    final logFile = File(greenVpnBackendLogPathSync());

    Future<void> log(String s) async {
      try {
        final ts = DateTime.now().toIso8601String();
        await logFile.writeAsString('[$ts] $s\n', mode: FileMode.append);
      } catch (_) {}
    }

    String outOf(ProcessResult r) =>
        ('${r.stdout ?? ''}\n${r.stderr ?? ''}').trim();

    bool isStoppedText(String out) => out.contains('STOPPED');
    Future<ProcessResult> scQueryEx() => _run('sc', ['queryex', _serviceName]);

    Future<bool> waitStopped({int loops = 40}) async {
      for (var i = 0; i < loops; i++) {
        final q = await scQueryEx();
        final o = outOf(q);
        await log(
          'queryex[$i] ec=${q.exitCode} :: ${o.replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
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
        final out = ('${res.stdout ?? ''}\n${res.stderr ?? ''}');
        return out.contains('S-1-16-12288') || out.contains('S-1-16-16384');
      } catch (_) {
        return false;
      }
    }

    try {
      await log('=== DISCONNECT requested ===');
      await log('service=$_serviceName');
      final admin = await isAdmin();
      await log('isAdmin=$admin');

      if (admin) {
        final stop = await _run('sc', ['stop', _serviceName]);
        await log(
          'sc stop ec=${stop.exitCode} :: ${outOf(stop).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
        );
        final un = await _run(_exe, ['/uninstalltunnelservice', tunnelName]);
        await log(
          'wireguard uninstall ec=${un.exitCode} :: ${outOf(un).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
        );
        final cleanup = await _cleanupLingeringAdapter(elevated: true);
        await log(
          'adapter cleanup ec=${cleanup.exitCode} :: ${outOf(cleanup).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
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
            'native service unavailable/failed for disconnect; scheduled task fallback is disabled',
          );
          return const VpnBackendResult(
            ok: false,
            message:
                'Системный компонент Green VPN не отвечает. Переустанови последнюю версию GreenVPN_Setup.exe один раз с правами администратора.',
          );
        }
        final cleanup = await _cleanupLingeringAdapter(elevated: false);
        await log(
          'scheduled adapter cleanup ec=${cleanup.exitCode} :: ${outOf(cleanup).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
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
          'wireguard uninstall retry ec=${un2.exitCode} :: ${outOf(un2).replaceAll('\r', ' ').replaceAll('\n', ' | ')}',
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
              '$kTunnelName всё ещё держит адаптер или маршрут после отключения. Закрой приложение, разреши UAC и повтори. См. backend.log.',
        );
      }

      await log('=== DISCONNECT OK ===');
      return const VpnBackendResult(ok: true);
    } catch (e) {
      await log('EXCEPTION: $e');
      return VpnBackendResult(
        ok: false,
        message: 'Disconnect error: $e (see backend.log)',
      );
    }
  }

  @override
  Future<bool> isConnected() async {
    try {
      const service = _GreenVpnSystemServiceClient();
      final serviceStatus = await service.status();
      final managedState = greenVpnClassifyWindowsManagedTunnelStatus(
        requestOk: serviceStatus.ok,
        data: serviceStatus.data,
      );
      if (managedState == GreenVpnWindowsManagedTunnelState.connected) {
        return true;
      }
      if (managedState == GreenVpnWindowsManagedTunnelState.disconnected) {
        return false;
      }
      final status = await WireGuardRuntimeStatus.query(
        tunnelName: tunnelName,
        configPath: _lastConfigPath ?? greenVpnManagedConfigPathSync(),
        wireguardExePath: _exe,
      );
      if (!status.isReallyConnected) return false;
      if (!_applicationRoutingRequested()) return true;
      Future<void> ignoreLog(String _) async {}
      return _processRouterIsReady(log: ignoreLog);
    } catch (_) {
      return false;
    }
  }
}
