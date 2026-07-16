import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  final publicProductSkip =
      !kPublicProductBuild || kTrialOnlyNoAdsBuild || kPaidBetaCustomerUi;

  testWidgets(
    'settings exposes one auto-renew entry and opens its own page',
    (tester) async {
      var cancelCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPage(
              themeMode: ThemeMode.light,
              onThemeModeChanged: (_) {},
              language: 'Русский',
              onPickLanguage: () {},
              email: 'user@example.com',
              emailVerified: true,
              emailConfirmationRequired: false,
              emailStatusBusy: false,
              emailStatusMessage: null,
              onResendEmailConfirmation: () async {},
              onRefreshEmailStatus: () async {},
              phone: null,
              phoneVerified: false,
              phoneStatusBusy: false,
              phoneStatusMessage: null,
              onRefreshPhoneStatus: () async {},
              onBindPhone: () async {},
              subscriptionActive: true,
              subscriptionAutoRenew: true,
              paymentMethodSaved: true,
              onOpenTariff: () {},
              onCancelAutoRenew: () async {
                cancelCalls += 1;
                return true;
              },
              onLogout: () async {},
              onOpenUpdates: () {},
              onOpenDiagnostics: () {},
            ),
          ),
        ),
      );

      final autoRenewEntry = find.text('Автопродление');
      await tester.scrollUntilVisible(autoRenewEntry, 160);
      expect(autoRenewEntry, findsOneWidget);
      expect(find.text('Основная карта для подписки'), findsNothing);
      expect(
        find.textContaining('Карта добавляется во время оплаты'),
        findsNothing,
      );
      expect(find.text('Добавить карту'), findsNothing);
      expect(find.text('Сменить карту'), findsNothing);

      await tester.tap(autoRenewEntry);
      await tester.pumpAndSettle();

      expect(find.byType(AutoRenewSettingsPage), findsOneWidget);
      expect(find.text('Карта привязана'), findsOneWidget);
      expect(find.text('Отключить автопродление'), findsOneWidget);

      await tester.tap(find.text('Отключить автопродление'));
      await tester.pumpAndSettle();

      expect(cancelCalls, 1);
      expect(find.text('Отключено'), findsOneWidget);
      expect(find.text('Карта не привязана'), findsOneWidget);
      expect(find.text('Отключить автопродление'), findsNothing);
    },
    skip: publicProductSkip,
  );

  testWidgets(
    'tariff keeps purchase opt-in but has no active-subscription cancel action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TariffPage(
              planName: 'Green VPN — 1 месяц',
              selectedApps: <TariffApp>{},
              trafficPack: TrafficPack.gb20,
              trafficGb: 20,
              devices: 1,
              optNoAds: true,
              optSmartRouting: true,
              optDedicatedIp: false,
              optAutoRenew: true,
              tariffCatalog: null,
              tariffQuote: null,
              tariffStatus: null,
              pendingBillingOrder: null,
              subscriptionActive: true,
              subscriptionExpiresAt: '2026-09-09T01:21:57Z',
              subscriptionMonthlyPriceRub: 249,
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
              onApplyTariff: () async {},
              onCheckPendingBillingOrder: () async {},
              onOpenPaymentUrl: (_) {},
              onPublicBillingPlanChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Автопродление'), findsOneWidget);
      expect(find.text('Отключить автопродление'), findsNothing);
    },
    skip: publicProductSkip,
  );
}
