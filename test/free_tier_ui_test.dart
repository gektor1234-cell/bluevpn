import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  const paidBetaBuild = bool.fromEnvironment('GREENVPN_PAID_BETA_BUILD');
  const fusionEnabled = kFusionUiEnabled;
  const usage = <String, dynamic>{
    'usedGb': 2.4,
    'trafficLimitGb': 3,
    'remainingGb': 0.6,
    'overLimit': false,
  };

  Widget tariffApp() {
    return MaterialApp(
      home: Scaffold(
        body: TariffPage(
          planName: 'Бесплатный',
          freeTierActive: true,
          trafficUsage: usage,
          isGuest: true,
          onRestoreAccess: () {},
          selectedApps: const <TariffApp>{},
          trafficPack: TrafficPack.gb20,
          trafficGb: 20,
          devices: 1,
          optNoAds: true,
          optSmartRouting: false,
          optDedicatedIp: false,
          optAutoRenew: false,
          tariffCatalog: const <String, dynamic>{
            'plan': <String, dynamic>{
              'priceRub': 299,
              'inviteFirstPeriodPriceRub': 149,
            },
          },
          tariffQuote: const <String, dynamic>{},
          tariffStatus: null,
          pendingBillingOrder: null,
          subscriptionActive: true,
          subscriptionExpiresAt: null,
          subscriptionMonthlyPriceRub: 0,
          publicBillingPlanCode: 'green_30d',
          tariffBusy: false,
          onClaimPaidBetaInvite: () async {},
          onToggleApp: (_) {},
          onTrafficChanged: (_) {},
          onTrafficGbChanged: (_) {},
          onDevicesChanged: (_) {},
          onOptNoAds: (_) {},
          onOptSmartRouting: (_) {},
          onOptDedicatedIp: (_) {},
          onOptAutoRenew: (_) {},
          onCancelAutoRenew: () async => true,
          onApplyTariff: () async {},
          onCheckPendingBillingOrder: () async {},
          onOpenPaymentUrl: (_) {},
          onPublicBillingPlanChanged: (_) {},
        ),
      ),
    );
  }

  Widget fixedPlansTariffApp({
    String planName = 'Бесплатный',
    bool freeTierActive = true,
    String? subscriptionExpiresAt,
    bool paidSalesEnabled = true,
    bool autoRenewAvailable = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TariffPage(
          planName: planName,
          freeTierActive: freeTierActive,
          trafficUsage: usage,
          isGuest: true,
          onRestoreAccess: () {},
          selectedApps: const <TariffApp>{},
          trafficPack: TrafficPack.gb20,
          trafficGb: 20,
          devices: 1,
          optNoAds: true,
          optSmartRouting: false,
          optDedicatedIp: false,
          optAutoRenew: false,
          tariffCatalog: <String, dynamic>{
            'paidSalesEnabled': paidSalesEnabled,
            'paymentsProductionReady': paidSalesEnabled,
            'autoRenew': autoRenewAvailable,
            'checkoutMessage': paidSalesEnabled
                ? 'Оплата доступна.'
                : 'Оплата временно недоступна. Бесплатный тариф продолжает работать.',
            'plans': const <Map<String, dynamic>>[
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
            ],
          },
          tariffQuote: const <String, dynamic>{},
          tariffStatus: null,
          pendingBillingOrder: null,
          subscriptionActive: true,
          subscriptionExpiresAt: subscriptionExpiresAt,
          subscriptionMonthlyPriceRub: 0,
          publicBillingPlanCode: 'green_30d',
          tariffBusy: false,
          onClaimPaidBetaInvite: () async {},
          onToggleApp: (_) {},
          onTrafficChanged: (_) {},
          onTrafficGbChanged: (_) {},
          onDevicesChanged: (_) {},
          onOptNoAds: (_) {},
          onOptSmartRouting: (_) {},
          onOptDedicatedIp: (_) {},
          onOptAutoRenew: (_) {},
          onCancelAutoRenew: () async => true,
          onApplyTariff: () async {},
          onCheckPendingBillingOrder: () async {},
          onOpenPaymentUrl: (_) {},
          onPublicBillingPlanChanged: (_) {},
        ),
      ),
    );
  }

  Widget vpnApp({String planName = 'Бесплатный', bool freeTierActive = true}) {
    return MaterialApp(
      home: Scaffold(
        body: VpnPage(
          planName: planName,
          freeTierActive: freeTierActive,
          trafficUsage: usage,
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
          selectedServer: const ServerLocation(
            id: 'auto',
            title: 'Автоматически',
            subtitle: '',
            isAuto: true,
          ),
          onOpenServerPicker: () {},
          socialOnlyEnabled: false,
          socialOnlyAllowed: false,
          socialOnlyApps: const <SocialApp>{},
          socialOnlyCustomPackages: const <String>{},
          socialOnlyWindowsApplications: const <String>{},
          socialOnlyWindowsSites: const <String>{},
          socialOnlyCustomLabels: const <String, String>{},
          socialOnlyWindowsApplicationLabels: const <String, String>{},
          onToggleSocialOnly: (_) {},
          onConfigureSocialApps: () {},
        ),
      ),
    );
  }

  Future<void> pumpAt(WidgetTester tester, Size size, Widget app) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });

  testWidgets(
    'paid-beta free tier fits narrow and desktop tariff views',
    (tester) async {
      await pumpAt(tester, const Size(390, 844), tariffApp());
      expect(find.text('Бесплатный тариф'), findsOneWidget);
      expect(find.textContaining('2.4 из 3 ГБ'), findsOneWidget);

      await pumpAt(tester, const Size(1280, 800), tariffApp());
      expect(find.text('Бесплатный тариф'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !paidBetaBuild,
  );

  testWidgets(
    'paid-beta renders all fixed subscription plans from the server catalog',
    (tester) async {
      await pumpAt(tester, const Size(1280, 900), fixedPlansTariffApp());
      expect(find.text('Тариф'), findsOneWidget);
      expect(find.text('249 ₽'), findsWidgets);
      expect(find.text('649 ₽'), findsOneWidget);
      expect(find.text('1099 ₽'), findsOneWidget);
      expect(find.text('Beta на 30 дней'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    skip: !paidBetaBuild,
  );

  testWidgets('free quota summary fits the VPN tariff control', (tester) async {
    await pumpAt(tester, const Size(390, 844), vpnApp());
    expect(find.textContaining('2.4 из 3 ГБ'), findsOneWidget);

    await pumpAt(tester, const Size(1280, 800), vpnApp());
    expect(find.textContaining('осталось 0.6 ГБ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !paidBetaBuild);

  testWidgets('guest can restore an existing subscription without paying', (
    tester,
  ) async {
    await pumpAt(tester, const Size(390, 844), vpnApp());
    expect(find.byKey(const Key('restore_access_home')), findsOneWidget);
    expect(find.text('Уже есть подписка?'), findsOneWidget);

    await pumpAt(tester, const Size(390, 844), fixedPlansTariffApp());
    expect(find.byKey(const Key('restore_access_tariff')), findsOneWidget);
    expect(find.text('Уже оплачивали подписку?'), findsOneWidget);
    expect(find.text('Войти по email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest access is labelled free instead of trial', (tester) async {
    await pumpAt(
      tester,
      const Size(390, 844),
      vpnApp(planName: 'Beta Trial', freeTierActive: false),
    );
    expect(
      fusionEnabled
          ? find.text('Бесплатный')
          : find.textContaining('Текущий: Бесплатный'),
      fusionEnabled ? findsWidgets : findsOneWidget,
    );
    expect(find.textContaining('Пробный период'), findsNothing);

    await pumpAt(
      tester,
      const Size(390, 844),
      fixedPlansTariffApp(
        planName: 'Beta Trial',
        freeTierActive: false,
        subscriptionExpiresAt: '2026-07-28T00:00:00Z',
      ),
    );
    expect(find.text('Бесплатный тариф'), findsOneWidget);
    expect(find.textContaining('Пробный период'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkout is visibly disabled when server sales gate is closed', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(390, 844),
      fixedPlansTariffApp(paidSalesEnabled: false),
    );
    final paymentButton = find.byKey(const Key('start_payment_button'));
    await tester.scrollUntilVisible(paymentButton, 220);
    final button = tester.widget<ElevatedButton>(paymentButton);
    expect(button.onPressed, isNull);
    expect(
      find.text(
        'Оплата временно недоступна. Бесплатный тариф продолжает работать.',
      ),
      findsWidgets,
    );
  });

  testWidgets('manual NPD catalog does not offer unavailable auto-renew', (
    tester,
  ) async {
    await pumpAt(tester, const Size(390, 844), fixedPlansTariffApp());

    expect(find.text('Автопродление'), findsNothing);
    expect(find.text('Продление вручную'), findsOneWidget);
    expect(
      find.textContaining('только после вашего подтверждения'),
      findsOneWidget,
    );
  });
}
