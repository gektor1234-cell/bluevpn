import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  const fusionEnabled = bool.fromEnvironment('GREENVPN_FUSION_UI_ENABLED');

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
        androidExternalVpnActive: false,
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
        enabled: true,
        allowed: true,
        selectedTitles: const ['Discord', 'Telegram', 'YouTube'],
        onToggle: (_) {},
        onConfigure: () => configured = true,
        onOpenTariff: () {},
      ),
    );

    expect(find.byKey(const Key('fusion_mode_page')), findsOneWidget);
    expect(find.text('Discord'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Сервисы'), findsNothing);
    expect(find.text('Приложения'), findsNothing);

    await tester.tap(find.byKey(const Key('fusion_mode_configure_button')));
    expect(configured, isTrue);
    expect(tester.takeException(), isNull);
  }, skip: !fusionEnabled);
}
