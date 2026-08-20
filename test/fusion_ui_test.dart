import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  const fusionEnabled = kFusionUiEnabled;

  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });

  testWidgets(
    'Fusion VPN surface fits phone and desktop and exposes primary actions',
    (tester) async {
      var diagnosticsOpened = false;
      var selectedModeRequested = false;

      Widget page() => VpnPage(
        planName: 'Бесплатный',
        freeTierActive: true,
        trafficUsage: const <String, dynamic>{
          'usedGb': 0.4,
          'trafficLimitGb': 3,
          'remainingGb': 2.6,
          'overLimit': false,
        },
        isGuest: true,
        onRestoreAccess: () {},
        vpnEnabled: false,
        externalVpnActive: false,
        vpnBusy: false,
        vpnInteractionLocked: false,
        vpnBusyStage: null,
        vpnBusyHint: null,
        wireGuardInstalled: true,
        wireGuardStatusText: null,
        wireGuardBusy: false,
        onInstallWireGuard: () async {},
        onRefreshWireGuard: () async {},
        onToggleVpn: () {},
        onOpenTariff: () {},
        onOpenDiagnostics: () => diagnosticsOpened = true,
        selectedServer: const ServerLocation(
          id: 'auto',
          title: 'Автоматически',
          subtitle: '',
          isAuto: true,
        ),
        onOpenServerPicker: () {},
        socialOnlyEnabled: false,
        socialOnlyAllowed: true,
        socialOnlyApps: const <SocialApp>{SocialApp.youtube},
        socialOnlyCustomPackages: const <String>{},
        socialOnlyWindowsApplications: const <String>{},
        socialOnlyWindowsSites: const <String>{},
        socialOnlyCustomLabels: const <String, String>{},
        socialOnlyWindowsApplicationLabels: const <String, String>{},
        onToggleSocialOnly: (enabled) {
          selectedModeRequested = enabled;
        },
        onConfigureSocialApps: () {},
      );

      await pumpAt(tester, const Size(390, 844), page());
      expect(find.byKey(const Key('fusion_vpn_page')), findsOneWidget);
      expect(find.byKey(const Key('fusion_connect_button')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('fusion_diagnostics_button')),
        160,
      );
      await tester.tap(find.byKey(const Key('fusion_diagnostics_button')));
      expect(diagnosticsOpened, isTrue);

      await tester.scrollUntilVisible(
        find.byKey(const Key('fusion_mode_selected')),
        160,
      );
      await tester.tap(find.byKey(const Key('fusion_mode_selected')));
      expect(selectedModeRequested, isTrue);
      expect(tester.takeException(), isNull);

      await pumpAt(tester, const Size(1280, 800), page());
      expect(find.byKey(const Key('fusion_vpn_page')), findsOneWidget);
      expect(find.text('Что направить через VPN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !fusionEnabled,
  );

  testWidgets('Fusion mode page keeps one unified selected list', (
    tester,
  ) async {
    var configured = false;
    await pumpAt(
      tester,
      const Size(390, 844),
      FusionModePage(
        allowed: true,
        selectedTitles: const ['Discord', 'Telegram', 'YouTube'],
        onConfigure: () => configured = true,
        onOpenTariff: () {},
      ),
    );

    expect(find.byKey(const Key('fusion_mode_page')), findsOneWidget);
    expect(find.text('Discord'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Выбранные приложения и сайты'), findsOneWidget);
    expect(find.byKey(const Key('fusion_mode_page_full')), findsNothing);
    expect(find.byKey(const Key('fusion_mode_page_selected')), findsNothing);
    expect(find.text('Сервисы'), findsNothing);
    expect(find.text('Приложения'), findsNothing);

    await tester.tap(find.byKey(const Key('fusion_mode_configure_button')));
    expect(configured, isTrue);
    expect(tester.takeException(), isNull);
  }, skip: !fusionEnabled);

  testWidgets(
    'Settings hides the unavailable one-item language picker',
    (tester) async {
      await pumpAt(
        tester,
        const Size(390, 844),
        SettingsPage(
          themeMode: ThemeMode.light,
          onThemeModeChanged: (_) {},
          email: '',
          isGuest: true,
          emailVerified: false,
          emailConfirmationRequired: false,
          emailStatusBusy: false,
          emailStatusMessage: null,
          onResendEmailConfirmation: () async {},
          onRefreshEmailStatus: () async {},
          hasPaidEntitlement: false,
          subscriptionAutoRenew: false,
          paymentMethodSaved: false,
          onOpenTariff: () {},
          onRestoreAccess: () {},
          onCancelAutoRenew: () async => true,
          onLogout: () async {},
          onOpenUpdates: () {},
          onOpenDiagnostics: () {},
        ),
      );

      expect(find.text('Тёмная тема'), findsOneWidget);
      expect(find.text('Язык'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    skip: !fusionEnabled,
  );

  testWidgets('Legacy settings can still expose the language row', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(390, 844),
      SettingsPage(
        themeMode: ThemeMode.light,
        onThemeModeChanged: (_) {},
        language: 'Русский',
        onPickLanguage: () {},
        showLanguage: true,
        email: '',
        isGuest: true,
        emailVerified: false,
        emailConfirmationRequired: false,
        emailStatusBusy: false,
        emailStatusMessage: null,
        onResendEmailConfirmation: () async {},
        onRefreshEmailStatus: () async {},
        hasPaidEntitlement: false,
        subscriptionAutoRenew: false,
        paymentMethodSaved: false,
        onOpenTariff: () {},
        onRestoreAccess: () {},
        onCancelAutoRenew: () async => true,
        onLogout: () async {},
        onOpenUpdates: () {},
        onOpenDiagnostics: () {},
      ),
    );

    expect(find.text('Язык'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Paid beta settings distinguish free access from a paid entitlement',
    (tester) async {
      await pumpAt(
        tester,
        const Size(390, 844),
        SettingsPage(
          themeMode: ThemeMode.light,
          onThemeModeChanged: (_) {},
          email: '',
          isGuest: true,
          emailVerified: false,
          emailConfirmationRequired: false,
          emailStatusBusy: false,
          emailStatusMessage: null,
          onResendEmailConfirmation: () async {},
          onRefreshEmailStatus: () async {},
          hasPaidEntitlement: false,
          subscriptionAutoRenew: false,
          paymentMethodSaved: false,
          onOpenTariff: () {},
          onRestoreAccess: () {},
          onCancelAutoRenew: () async => true,
          onLogout: () async {},
          onOpenUpdates: () {},
          onOpenDiagnostics: () {},
        ),
      );

      expect(find.text('Тарифы и доступ'), findsOneWidget);
      expect(
        find.text('Выбрать тариф или восстановить доступ'),
        findsOneWidget,
      );
      expect(find.text('Текущий доступ и оплата'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    skip: !fusionEnabled || !kPaidBetaCustomerUi,
  );

  testWidgets(
    'Fusion connected state exposes actions and useful details',
    (tester) async {
      var pauseOpened = false;
      var routeChanged = false;
      const route = ServerLocation(
        id: 'nl-fast',
        title: 'Нидерланды',
        subtitle: 'Амстердам',
        protocolLabel: 'WireGuard',
      );

      await pumpAt(
        tester,
        const Size(360, 800),
        VpnPage(
          planName: 'Бесплатный',
          freeTierActive: true,
          trafficUsage: const <String, dynamic>{
            'usedGb': 0.4,
            'trafficLimitGb': 3,
            'remainingGb': 2.6,
            'overLimit': false,
          },
          isGuest: true,
          vpnEnabled: true,
          externalVpnActive: false,
          vpnBusy: false,
          vpnInteractionLocked: false,
          vpnBusyStage: null,
          vpnBusyHint: null,
          wireGuardInstalled: true,
          wireGuardStatusText: null,
          wireGuardBusy: false,
          onInstallWireGuard: () async {},
          onRefreshWireGuard: () async {},
          onToggleVpn: () {},
          connectionActionsEnabled: true,
          connectionDetailsEnabled: true,
          onOpenPause: () => pauseOpened = true,
          onChangeRoute: () => routeChanged = true,
          activeConnectionRoute: route,
          connectionStartedAt: DateTime.now().subtract(
            const Duration(minutes: 2),
          ),
          connectionLatencyMs: 42,
          onOpenTariff: () {},
          onOpenDiagnostics: () {},
          selectedServer: const ServerLocation(
            id: 'auto',
            title: 'Автоматически',
            subtitle: '',
            isAuto: true,
          ),
          onOpenServerPicker: () {},
          socialOnlyEnabled: false,
          socialOnlyAllowed: true,
          socialOnlyApps: const <SocialApp>{SocialApp.youtube},
          socialOnlyCustomPackages: const <String>{},
          socialOnlyWindowsApplications: const <String>{},
          socialOnlyWindowsSites: const <String>{},
          socialOnlyCustomLabels: const <String, String>{},
          socialOnlyWindowsApplicationLabels: const <String, String>{},
          onToggleSocialOnly: (_) {},
          onConfigureSocialApps: () {},
        ),
      );

      expect(find.text('Защита активна'), findsOneWidget);
      expect(
        find.byKey(const Key('fusion_connected_check_icon')),
        findsOneWidget,
      );
      final diagnosticsLabel = tester.widget<Text>(find.text('Диагностика'));
      expect(diagnosticsLabel.maxLines, 1);
      expect(diagnosticsLabel.softWrap, isFalse);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Диагностика'))
            .didExceedMaxLines,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('fusion_pause_button')));
      await tester.tap(find.byKey(const Key('fusion_change_route_button')));
      expect(pauseOpened, isTrue);
      expect(routeChanged, isTrue);

      await tester.tap(find.byKey(const Key('fusion_details_button')));
      await tester.pumpAndSettle();
      expect(find.text('Детали соединения'), findsOneWidget);
      expect(find.text('42 мс'), findsOneWidget);
      expect(find.text('Публичный IP'), findsNothing);
      expect(find.text('203.0.113.7'), findsNothing);
      expect(find.text('Маршрут'), findsNothing);
      expect(find.text('WireGuard'), findsNothing);
      expect(find.text('Сменить подключение'), findsOneWidget);
      expect(find.text('Подключение контролируется'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !fusionEnabled,
  );

  testWidgets(
    'Fusion names selective protection without implying device-wide coverage',
    (tester) async {
      await pumpAt(
        tester,
        const Size(1100, 900),
        VpnPage(
          isGuest: false,
          planName: 'Премиум',
          trafficUsage: const <String, dynamic>{},
          vpnEnabled: true,
          windowsProtectionConfirmed: true,
          externalVpnActive: false,
          vpnBusy: false,
          vpnInteractionLocked: false,
          vpnBusyStage: null,
          vpnBusyHint: null,
          wireGuardInstalled: true,
          wireGuardStatusText: 'Установлен',
          wireGuardBusy: false,
          onInstallWireGuard: () async {},
          onRefreshWireGuard: () async {},
          onToggleVpn: () {},
          onOpenTariff: () {},
          selectedServer: const ServerLocation(
            id: 'auto',
            title: 'Авто',
            subtitle: 'Автовыбор',
            isAuto: true,
          ),
          onOpenServerPicker: () {},
          socialOnlyEnabled: true,
          socialOnlyAllowed: true,
          socialOnlyApps: const <SocialApp>{SocialApp.youtube},
          socialOnlyCustomPackages: const <String>{},
          socialOnlyWindowsApplications: const <String>{},
          socialOnlyWindowsSites: const <String>{'chatgpt.com'},
          socialOnlyCustomLabels: const <String, String>{},
          socialOnlyWindowsApplicationLabels: const <String, String>{},
          onToggleSocialOnly: (_) {},
          onConfigureSocialApps: () {},
        ),
      );

      expect(find.text('Выбранное защищено'), findsOneWidget);
      expect(find.text('ВЫБРАННОЕ ЗАЩИЩЕНО'), findsOneWidget);
      expect(
        find.text('Весь интернет проходит через Green VPN.'),
        findsNothing,
      );
    },
    skip: !fusionEnabled,
  );

  testWidgets(
    'Fusion does not claim protection until Windows confirms active mode',
    (tester) async {
      await pumpAt(
        tester,
        const Size(390, 844),
        VpnPage(
          planName: 'Premium',
          vpnEnabled: true,
          windowsProtectionConfirmed: false,
          externalVpnActive: false,
          vpnBusy: false,
          vpnInteractionLocked: false,
          vpnBusyStage: null,
          vpnBusyHint: null,
          wireGuardInstalled: true,
          wireGuardStatusText: null,
          wireGuardBusy: false,
          onInstallWireGuard: () async {},
          onRefreshWireGuard: () async {},
          onToggleVpn: () {},
          connectionDetailsEnabled: true,
          onOpenTariff: () {},
          onOpenDiagnostics: () {},
          selectedServer: const ServerLocation(
            id: 'auto',
            title: 'Автоматически',
            subtitle: '',
            isAuto: true,
          ),
          onOpenServerPicker: () {},
          socialOnlyEnabled: true,
          socialOnlyAllowed: true,
          socialOnlyApps: const <SocialApp>{SocialApp.youtube},
          socialOnlyCustomPackages: const <String>{},
          socialOnlyWindowsApplications: const <String>{},
          socialOnlyWindowsSites: const <String>{},
          socialOnlyCustomLabels: const <String, String>{},
          socialOnlyWindowsApplicationLabels: const <String, String>{},
          onToggleSocialOnly: (_) {},
          onConfigureSocialApps: () {},
        ),
      );

      expect(find.text('Проверяем защиту'), findsOneWidget);
      expect(
        find.byKey(const Key('fusion_connected_check_icon')),
        findsNothing,
      );
      expect(find.byKey(const Key('fusion_details_button')), findsNothing);
      expect(find.text('ЗАЩИЩЕНО'), findsNothing);
      expect(find.text('ПРОВЕРКА'), findsOneWidget);
    },
    skip: !fusionEnabled,
  );

  testWidgets(
    'Fusion prioritizes a competing VPN warning over pending Green status',
    (tester) async {
      await pumpAt(
        tester,
        const Size(390, 844),
        VpnPage(
          planName: 'Premium',
          vpnEnabled: true,
          windowsProtectionConfirmed: false,
          externalVpnActive: true,
          vpnBusy: false,
          vpnInteractionLocked: false,
          vpnBusyStage: null,
          vpnBusyHint: null,
          wireGuardInstalled: true,
          wireGuardStatusText: null,
          wireGuardBusy: false,
          onInstallWireGuard: () async {},
          onRefreshWireGuard: () async {},
          onToggleVpn: () {},
          onOpenTariff: () {},
          onOpenDiagnostics: () {},
          selectedServer: const ServerLocation(
            id: 'auto',
            title: 'Автоматически',
            subtitle: '',
            isAuto: true,
          ),
          onOpenServerPicker: () {},
          socialOnlyEnabled: false,
          socialOnlyAllowed: true,
          socialOnlyApps: const <SocialApp>{SocialApp.youtube},
          socialOnlyCustomPackages: const <String>{},
          socialOnlyWindowsApplications: const <String>{},
          socialOnlyWindowsSites: const <String>{},
          socialOnlyCustomLabels: const <String, String>{},
          socialOnlyWindowsApplicationLabels: const <String, String>{},
          onToggleSocialOnly: (_) {},
          onConfigureSocialApps: () {},
        ),
      );

      expect(find.text('Конфликт VPN'), findsOneWidget);
      expect(find.text('ДРУГОЙ VPN'), findsOneWidget);
      expect(find.text('Проверяем защиту'), findsNothing);
      expect(find.text('ЗАЩИЩЕНО'), findsNothing);
      expect(
        find.byKey(const Key('fusion_connected_check_icon')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
    skip: !fusionEnabled,
  );

  test('connected route restoration prefers authoritative Android runtime', () {
    final now = DateTime.utc(2026, 8, 11, 7);
    const nl = ServerLocation(
      id: 'nl-route',
      title: 'Нидерланды',
      subtitle: 'Амстердам',
    );
    const london = ServerLocation(
      id: 'gb-route',
      title: 'Лондон',
      subtitle: 'Великобритания',
    );

    final route = greenVpnResolveConnectedServerRoute(
      servers: const [nl, london],
      activeRoute: nl,
      runtimeDesired: true,
      runtimeServerId: london.id,
      runtimeProtocol: london.protocolCode,
      cachedServerId: nl.id,
      cachedProtocol: nl.protocolCode,
      cachedAt: now,
      selectedRoute: const ServerLocation(
        id: 'auto',
        title: 'Авто',
        subtitle: 'Автовыбор',
        isAuto: true,
      ),
      now: now,
    );

    expect(route?.id, london.id);
  });

  test('connected route restoration survives Android process recreation', () {
    final now = DateTime.utc(2026, 8, 11, 7);
    const london = ServerLocation(
      id: 'gb-route',
      title: 'Лондон',
      subtitle: 'Великобритания',
    );

    final restored = greenVpnResolveConnectedServerRoute(
      servers: const [london],
      cachedServerId: london.id,
      cachedProtocol: london.protocolCode,
      cachedAt: now.subtract(const Duration(minutes: 5)),
      selectedRoute: const ServerLocation(
        id: 'auto',
        title: 'Авто',
        subtitle: 'Автовыбор',
        isAuto: true,
      ),
      now: now,
    );
    final stale = greenVpnResolveConnectedServerRoute(
      servers: const [london],
      cachedServerId: london.id,
      cachedProtocol: london.protocolCode,
      cachedAt: now.subtract(const Duration(hours: 25)),
      selectedRoute: const ServerLocation(
        id: 'auto',
        title: 'Авто',
        subtitle: 'Автовыбор',
        isAuto: true,
      ),
      now: now,
    );

    expect(restored?.id, london.id);
    expect(stale, isNull);
  });
}
