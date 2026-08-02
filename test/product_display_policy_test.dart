import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/product_display_policy.dart';

void main() {
  test('internal lifecycle names never reach public plan UI', () {
    expect(greenVpnPublicPlanTitle('Beta'), 'Подписка');
    expect(greenVpnPublicPlanTitle('Beta Trial'), 'Пробный период');
    expect(greenVpnPublicPlanTitle('preview'), 'Тариф');
  });

  test('fixed public subscription codes use customer-facing periods', () {
    expect(greenVpnPublicPlanTitle('green_30d'), '1 месяц');
    expect(greenVpnPublicPlanTitle('green_90d'), '3 месяца');
    expect(greenVpnPublicPlanTitle('green_180d'), '6 месяцев');
    expect(greenVpnPublicBillingPeriodTitle('green_30d', 30), '1 месяц');
    expect(greenVpnPublicBillingPeriodTitle('green_90d', 90), '3 месяца');
    expect(greenVpnPublicBillingPeriodTitle('green_180d', 180), '6 месяцев');
  });

  test('public version hides internal release channel suffixes', () {
    expect(greenVpnPublicVersionTitle('0.3.0-final-preview.2'), '0.3.0');
    expect(greenVpnPublicVersionTitle('0.3.0-paid-beta.12'), '0.3.0');
    expect(greenVpnPublicVersionTitle('1.4.7'), '1.4.7');
  });

  test('public changelog hides rollout and transport internals', () {
    expect(
      greenVpnPublicChangelog(const [
        'Android: migrate preview users to stable 0.2.44',
        'WireGuard transport updated',
      ]),
      const ['Улучшены стабильность подключения и обновление приложения.'],
    );
    expect(
      greenVpnPublicChangelog(const ['Исправлено восстановление сессии']),
      const ['Исправлено восстановление сессии'],
    );
  });

  test('public changelog localizes known Windows release notes', () {
    expect(
      greenVpnPublicChangelog(const [
        'Windows: cleaner server list',
        'Windows: hide provider/protocol/health details',
        'Windows: generic VPN wording',
        'Unknown English release note',
      ]),
      const [
        'Упрощён выбор сервера.',
        'Убраны лишние технические детали.',
        'Улучшены тексты интерфейса.',
      ],
    );
  });

  test('obsolete billing plan codes fall back to a real public option', () {
    expect(
      greenVpnNormalizePublicBillingPlanCode('paid_beta_30d'),
      'green_30d',
    );
    expect(
      greenVpnNormalizePublicBillingPlanCode(
        'missing',
        availableCodes: const ['green_90d', 'green_180d'],
      ),
      'green_90d',
    );
    expect(greenVpnNormalizePublicBillingPlanCode('green_180d'), 'green_180d');
  });

  test('fixed billing plan catalog detection ignores unrelated plans', () {
    expect(
      greenVpnFixedBillingPlanCodesFromCatalog(const {
        'plans': [
          {'code': 'green_30d'},
          {'code': 'green_90d'},
          {'code': 'green_180d'},
          {'code': 'legacy_plan'},
        ],
      }),
      greenVpnFixedPublicBillingPlanCodes,
    );
    expect(
      greenVpnCatalogHasFixedBillingPlans(const {
        'plans': [
          {'code': 'green_30d'},
        ],
      }),
      isTrue,
    );
    expect(
      greenVpnCatalogHasFixedBillingPlans(const {
        'plan': {'code': 'paid_beta_30d'},
      }),
      isFalse,
    );
  });

  test('server selection never silently enables auto-renew', () {
    expect(
      greenVpnSelectionAutoRenewEnabled(const {
        'policyMode': 'public_product',
      }, paidBetaBuild: false),
      isFalse,
    );
    expect(
      greenVpnSelectionAutoRenewEnabled(const {
        'policyMode': 'legacy',
        'autoRenew': false,
      }, paidBetaBuild: false),
      isFalse,
    );
    expect(
      greenVpnSelectionAutoRenewEnabled(const {
        'policyMode': 'public_product',
        'autoRenew': true,
      }, paidBetaBuild: false),
      isTrue,
    );
    expect(
      greenVpnSelectionAutoRenewEnabled(const {
        'policyMode': 'public_product',
        'autoRenew': true,
      }, paidBetaBuild: true),
      isFalse,
    );
  });

  test('ordinary plan names remain readable', () {
    expect(greenVpnPublicPlanTitle('Premium'), 'Premium');
    expect(greenVpnPublicPlanTitle('Base'), 'Базовый');
  });

  test('paid entitlement excludes free and trial plans', () {
    expect(
      greenVpnHasPaidEntitlement(
        isActive: true,
        planCode: 'green_30d',
        monthlyPriceRub: 249,
      ),
      isTrue,
    );
    expect(
      greenVpnHasPaidEntitlement(
        isActive: true,
        planCode: 'trial',
        monthlyPriceRub: 0,
      ),
      isFalse,
    );
    expect(
      greenVpnHasPaidEntitlement(isActive: true, planName: 'Базовый'),
      isFalse,
    );
    expect(
      greenVpnHasPaidEntitlement(
        isActive: true,
        planCode: 'free_quota',
        monthlyPriceRub: 0,
      ),
      isFalse,
    );
    expect(
      greenVpnHasPaidEntitlement(
        isActive: false,
        planCode: 'green_30d',
        monthlyPriceRub: 249,
      ),
      isFalse,
    );
  });

  test('free tier state and quota presentation follow server payload', () {
    expect(
      greenVpnIsFreeTierSubscription(const {
        'planCode': 'free_quota',
        'isActive': true,
      }),
      isTrue,
    );
    expect(
      greenVpnTrafficUsageSummary(const {
        'usedGb': 1.25,
        'trafficLimitGb': 3,
        'remainingGb': 1.75,
        'overLimit': false,
      }),
      '1.3 из 3 ГБ • осталось 1.8 ГБ',
    );
    expect(
      greenVpnTrafficUsageProgress(const {'usedGb': 1.5, 'trafficLimitGb': 3}),
      0.5,
    );
    expect(
      greenVpnTrafficUsageSummary(const {'usedGb': 12, 'trafficLimitGb': null}),
      contains('лимит временно отключён'),
    );
    expect(
      greenVpnIsFreeQuotaExhaustedMessage(
        'Бесплатный лимит на этот месяц исчерпан.',
      ),
      isTrue,
    );
  });

  test('social-only description matches the actual switch state', () {
    expect(
      greenVpnSocialOnlyStatusText(allowed: true, enabled: false),
      contains('выключена'),
    );
    expect(
      greenVpnSocialOnlyStatusText(allowed: true, enabled: true),
      contains('активна'),
    );
    expect(
      greenVpnSocialOnlyStatusText(allowed: false, enabled: false),
      contains('по подписке'),
    );
    expect(
      greenVpnSocialOnlyStatusText(
        allowed: false,
        enabled: false,
        permanentFreeBuild: true,
      ),
      isNot(contains('подписк')),
    );
    expect(
      greenVpnSocialOnlyStatusText(
        allowed: true,
        enabled: true,
        usesApplications: false,
      ),
      contains('Выбранные сервисы'),
    );
    expect(
      greenVpnSocialOnlyStatusText(
        allowed: true,
        enabled: true,
        usesMixedSelection: true,
      ),
      contains('сервисы, программы и сайты'),
    );
  });

  test('expired sessions recover guests without forcing account login', () {
    expect(
      greenVpnExpiredSessionAction(isGuest: true),
      GreenVpnExpiredSessionAction.refreshGuest,
    );
    expect(
      greenVpnExpiredSessionAction(isGuest: false),
      GreenVpnExpiredSessionAction.requireAccountSignIn,
    );
  });

  test('public errors keep useful text and remove backend internals', () {
    expect(
      greenVpnPublicErrorMessage(
        rawError: 'Ошибка сервера (400)',
        responseBody:
            '{"detail":{"code":"public_plan_invalid","message":"Выбранный срок подписки недоступен."}}',
        statusCode: 400,
      ),
      'Выбранный срок подписки недоступен.',
    );
    expect(
      greenVpnPublicErrorMessage(
        rawError: 'Ошибка сервера (409)',
        responseBody:
            '{"detail":{"code":"paid_beta_client_required","message":"Открой оплату в beta-версии Green VPN."}}',
        statusCode: 409,
      ),
      'Эта версия приложения устарела. Установите последнее обновление и повторите оплату.',
    );
    expect(
      greenVpnPublicErrorMessage(
        rawError: 'Ошибка сервера (403)',
        responseBody:
            '{"detail":{"code":"premium_feature_required","message":"internal"}}',
        statusCode: 403,
      ),
      'Режим «Только для соцсетей» доступен по подписке.',
    );
    expect(
      greenVpnPublicErrorMessage(
        rawError: 'Ошибка сервера (403)',
        responseBody:
            '{"detail":{"code":"free_quota_exhausted","message":"internal"}}',
        statusCode: 403,
      ),
      contains('Бесплатный лимит'),
    );
    expect(
      greenVpnPublicErrorMessage(
        rawError:
            'SocketException: failed host lookup, uri = https://api.greenvpn.pro/api/v1/test',
      ),
      contains('Проверьте интернет'),
    );
    expect(
      greenVpnPublicErrorMessage(
        rawError: 'WireGuard endpoint failed at https://internal.example/api/x',
      ),
      isNot(contains('WireGuard')),
    );
    for (final internal in <String>[
      r'C:\ProgramData\GreenVPN\client.conf',
      'endpoint 88.218.250.86 failed',
      'backend server=nl2 protocol=hysteria2',
      'Beta preview route failed',
    ]) {
      final visible = greenVpnPublicErrorMessage(rawError: internal);
      expect(visible, 'Не удалось выполнить действие. Повторите попытку.');
    }
  });
}
