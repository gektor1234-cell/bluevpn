import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/main.dart';

void main() {
  final publicProductSkip =
      !kPublicProductBuild || kTrialOnlyNoAdsBuild || kPaidBetaCustomerUi;

  test('new local preferences require explicit auto-renew opt-in', () {
    expect(Prefs.defaults().optAutoRenew, isFalse);
  });

  testWidgets(
    'settings exposes one auto-renew entry and opens its own page',
    (tester) async {
      var cancelCalls = 0;
      var tariffCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPage(
              themeMode: ThemeMode.light,
              onThemeModeChanged: (_) {},
              email: 'user@example.com',
              isGuest: false,
              emailVerified: true,
              emailConfirmationRequired: false,
              emailStatusBusy: false,
              emailStatusMessage: null,
              onResendEmailConfirmation: () async {},
              onRefreshEmailStatus: () async {},
              hasPaidEntitlement: true,
              subscriptionAutoRenew: true,
              paymentMethodSaved: true,
              onOpenTariff: () => tariffCalls += 1,
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
      expect(
        find.byKey(const Key('auto_renew_settings_switch')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('auto_renew_settings_switch')));
      await tester.pumpAndSettle();

      expect(cancelCalls, 1);
      expect(find.text('Отключено'), findsOneWidget);
      expect(find.text('Карта не привязана'), findsOneWidget);

      await tester.tap(find.byKey(const Key('auto_renew_settings_switch')));
      await tester.pumpAndSettle();

      expect(tariffCalls, 1);
      expect(find.byType(AutoRenewSettingsPage), findsNothing);
    },
    skip: publicProductSkip,
  );

  testWidgets(
    'tariff keeps auto-renew out of the plan list and asks at checkout',
    (tester) async {
      var optInCalls = 0;
      bool? requestedAutoRenew;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TariffPage(
              planName: 'Бесплатный',
              freeTierActive: true,
              selectedApps: <TariffApp>{},
              trafficPack: TrafficPack.gb20,
              trafficGb: 20,
              devices: 1,
              optNoAds: true,
              optSmartRouting: true,
              optDedicatedIp: false,
              optAutoRenew: false,
              tariffCatalog: const <String, dynamic>{
                'paidSalesEnabled': true,
                'paymentsProductionReady': true,
                'autoRenew': true,
                'plans': <Map<String, dynamic>>[
                  {
                    'code': 'green_30d',
                    'title': '1 месяц',
                    'periodDays': 30,
                    'priceRub': 249,
                    'effectiveMonthlyRub': 249,
                    'discountPercent': 0,
                  },
                ],
              },
              tariffQuote: null,
              tariffStatus: null,
              pendingBillingOrder: null,
              subscriptionActive: true,
              subscriptionAutoRenew: false,
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
              onOptAutoRenew: (_) => optInCalls += 1,
              onCancelAutoRenew: () async => true,
              onApplyTariff: (autoRenew) async {
                requestedAutoRenew = autoRenew;
              },
              onCheckPendingBillingOrder: () async {},
              onOpenPaymentUrl: (_) {},
              onPublicBillingPlanChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Автопродление'), findsNothing);
      expect(find.text('Продление вручную'), findsNothing);

      final paymentButton = find.byKey(const Key('start_payment_button'));
      await tester.scrollUntilVisible(paymentButton, 220);
      await tester.tap(paymentButton);
      await tester.pumpAndSettle();

      final consent = find.byKey(const Key('auto_renew_checkout_consent'));
      expect(consent, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(consent).value, isFalse);
      expect(requestedAutoRenew, isNull);

      await tester.tap(consent);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(consent).value, isTrue);

      await tester.tap(find.byKey(const Key('confirm_payment_button')));
      await tester.pumpAndSettle();

      expect(optInCalls, 0);
      expect(requestedAutoRenew, isTrue);
    },
    skip: publicProductSkip,
  );

  testWidgets('guest account settings expose a dedicated restore action', (
    tester,
  ) async {
    var restoreCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
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
            onRestoreAccess: () => restoreCalls += 1,
            onCancelAutoRenew: () async => false,
            onLogout: () async {},
            onOpenUpdates: () {},
            onOpenDiagnostics: () {},
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('restore_access_settings')),
      160,
    );
    expect(find.text('Войти в аккаунт'), findsOneWidget);
    expect(find.text('Восстановить уже оплаченную подписку'), findsOneWidget);
    await tester.tap(find.text('Войти в аккаунт'));
    await tester.pump();
    expect(restoreCalls, 1);
  });
}
