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

  test('ordinary plan names remain readable', () {
    expect(greenVpnPublicPlanTitle('Premium'), 'Premium');
    expect(greenVpnPublicPlanTitle('Base'), 'Базовый');
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
      contains('недоступна'),
    );
    expect(
      greenVpnSocialOnlyStatusText(
        allowed: true,
        enabled: true,
        usesApplications: false,
      ),
      contains('Выбранные сервисы'),
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
