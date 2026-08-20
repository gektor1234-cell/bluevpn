import 'dart:convert';

const Set<String> greenVpnFreePlanCodes = <String>{
  '',
  'base',
  'trial',
  'free',
  'free_quota',
  'free_start',
  'support_trial',
  'базовый',
  'бесплатный',
  'пробный период',
};

enum GreenVpnExpiredSessionAction { refreshGuest, requireAccountSignIn }

GreenVpnExpiredSessionAction greenVpnExpiredSessionAction({
  required bool isGuest,
}) => isGuest
    ? GreenVpnExpiredSessionAction.refreshGuest
    : GreenVpnExpiredSessionAction.requireAccountSignIn;

bool greenVpnHasPaidEntitlement({
  required bool isActive,
  String? planCode,
  String? planName,
  int? monthlyPriceRub,
}) {
  if (!isActive) return false;
  final code =
      (planCode?.trim().isNotEmpty == true ? planCode : planName)
          ?.trim()
          .toLowerCase() ??
      '';
  if (greenVpnFreePlanCodes.contains(code) || code.contains('trial')) {
    return false;
  }
  if (monthlyPriceRub != null && monthlyPriceRub <= 0) return false;
  return true;
}

bool greenVpnIsFreeTierSubscription(
  Map<String, dynamic> profile, {
  Object? subscription,
}) {
  final sub = subscription is Map
      ? Map<String, dynamic>.from(subscription)
      : const <String, dynamic>{};
  final planCode = (profile['planCode'] ?? sub['planCode'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  return profile['isFreeTier'] == true ||
      sub['isFreeTier'] == true ||
      planCode == 'free_quota';
}

bool greenVpnIsFreeQuotaExhaustedMessage(String? message) {
  final raw = (message ?? '').trim().toLowerCase();
  return raw.contains('free_quota_exhausted') ||
      (raw.contains('бесплатн') &&
          raw.contains('лимит') &&
          raw.contains('исчерпан'));
}

double? greenVpnTrafficUsageProgress(Map<String, dynamic> usage) {
  final used = double.tryParse((usage['usedGb'] ?? '').toString());
  final limit = double.tryParse((usage['trafficLimitGb'] ?? '').toString());
  if (used == null || limit == null || limit <= 0) return null;
  return (used / limit).clamp(0.0, 1.0);
}

String greenVpnTrafficUsageSummary(Map<String, dynamic> usage) {
  String formatGb(Object? raw) {
    final value = double.tryParse((raw ?? '').toString()) ?? 0;
    if ((value - value.round()).abs() < 0.05) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  final used = formatGb(usage['usedGb']);
  final limitRaw = usage['trafficLimitGb'];
  if (limitRaw == null || limitRaw.toString().trim().isEmpty) {
    return 'Использовано $used ГБ • лимит временно отключён';
  }
  final limit = formatGb(limitRaw);
  if (usage['overLimit'] == true) {
    return 'Лимит исчерпан • $used из $limit ГБ';
  }
  final remaining = formatGb(usage['remainingGb']);
  return '$used из $limit ГБ • осталось $remaining ГБ';
}

String greenVpnPublicPlanTitle(String rawPlanName) {
  final raw = rawPlanName.trim();
  final code = raw.toLowerCase();

  if (code.isEmpty || code == 'base' || code == 'free') return 'Базовый';
  if (code.contains('trial')) return 'Пробный период';
  if (code.contains('beta')) return 'Подписка';

  switch (code) {
    case 'green_30d':
      return '1 месяц';
    case 'green_90d':
      return '3 месяца';
    case 'green_180d':
      return '6 месяцев';
  }

  final cleaned = raw
      .replaceAll(RegExp(r'\bbeta\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\btrial\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bpreview\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? 'Тариф' : cleaned;
}

String greenVpnPublicVersionTitle(String rawVersion) {
  final raw = rawVersion.trim();
  final semanticVersion = RegExp(r'^\d+\.\d+\.\d+').firstMatch(raw);
  if (semanticVersion != null) return semanticVersion.group(0)!;

  final cleaned = raw
      .replaceAll(
        RegExp(r'[-_.]?(?:paid[-_.]?)?beta.*$', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'[-_.]?preview.*$', caseSensitive: false), '')
      .trim();
  return cleaned.isEmpty ? raw : cleaned;
}

List<String> greenVpnPublicChangelog(Iterable<String> rawItems) {
  const localizedItems = <String, String>{
    'windows: cleaner server list': 'Упрощён выбор сервера.',
    'windows: hide provider/protocol/health details':
        'Убраны лишние технические детали.',
    'windows: generic vpn wording': 'Улучшены тексты интерфейса.',
  };
  final internal = RegExp(
    r'preview|\bbeta\b|wireguard|amnezia|hysteria|vless|naive|dnstt|ruvds|timeweb|backend|/api/|forced disconnect|transport',
    caseSensitive: false,
  );
  final cleaned = rawItems
      .map((item) => item.trim().replaceFirst(RegExp(r'^[•*-]+\s*'), ''))
      .where((item) => item.isNotEmpty && !internal.hasMatch(item))
      .map(
        (item) =>
            localizedItems[item.toLowerCase()] ??
            (RegExp(r'[А-Яа-яЁё]').hasMatch(item) ? item : ''),
      )
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (cleaned.isNotEmpty || rawItems.isEmpty) return cleaned;
  return const ['Улучшены стабильность подключения и обновление приложения.'];
}

const List<String> greenVpnFixedPublicBillingPlanCodes = <String>[
  'green_30d',
  'green_90d',
  'green_180d',
];

List<String> greenVpnFixedBillingPlanCodesFromCatalog(
  Map<String, dynamic>? catalog,
) {
  final rawPlans = catalog?['plans'];
  if (rawPlans is! List) return const <String>[];

  return rawPlans
      .whereType<Map>()
      .map((plan) => (plan['code'] ?? '').toString().trim())
      .where(greenVpnFixedPublicBillingPlanCodes.contains)
      .toSet()
      .toList(growable: false);
}

bool greenVpnCatalogHasFixedBillingPlans(Map<String, dynamic>? catalog) =>
    greenVpnFixedBillingPlanCodesFromCatalog(catalog).isNotEmpty;

String greenVpnTariffRefreshStatus({
  required bool usesFixedBillingPlans,
  Object? monthlyPriceRub,
}) {
  if (usesFixedBillingPlans) return 'Тарифы обновлены.';
  if (monthlyPriceRub == null) return 'Цена обновлена.';
  return 'Цена обновлена: $monthlyPriceRub ₽/мес.';
}

String greenVpnPublicBillingPeriodTitle(String rawPlanCode, int periodDays) {
  switch (rawPlanCode.trim()) {
    case 'green_30d':
      return '1 месяц';
    case 'green_90d':
      return '3 месяца';
    case 'green_180d':
      return '6 месяцев';
  }
  return '$periodDays дней';
}

String greenVpnNormalizePublicBillingPlanCode(
  String rawCode, {
  Iterable<String> availableCodes = greenVpnFixedPublicBillingPlanCodes,
}) {
  final available = availableCodes
      .map((code) => code.trim())
      .where((code) => code.isNotEmpty)
      .toList(growable: false);
  if (available.isEmpty) return greenVpnFixedPublicBillingPlanCodes.first;

  final requested = rawCode.trim();
  return available.contains(requested) ? requested : available.first;
}

bool greenVpnSelectionAutoRenewEnabled(
  Map<String, dynamic> selection, {
  required bool paidBetaBuild,
}) {
  if (paidBetaBuild) return false;
  return selection['autoRenew'] == true;
}

String greenVpnPublicErrorMessage({
  required String rawError,
  String? responseBody,
  int? statusCode,
  String fallback = 'Не удалось выполнить действие. Повторите попытку.',
}) {
  String? responseMessage;
  String? responseCode;
  final body = responseBody?.trim() ?? '';
  if (body.isNotEmpty) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is Map) {
          responseCode = (detail['code'] ?? '').toString().trim();
          responseMessage = (detail['message'] ?? '').toString().trim();
        } else if (detail is String) {
          responseMessage = detail.trim();
        }
        responseMessage ??= (decoded['message'] ?? '').toString().trim();
      }
    } catch (_) {}
  }

  if (responseCode == 'paid_beta_client_required') {
    return 'Эта версия приложения устарела. Установите последнее обновление и повторите оплату.';
  }
  if (responseCode == 'client_update_required') {
    return 'Чтобы продолжить пользоваться Green VPN, установите обязательное обновление.';
  }
  if (responseCode == 'premium_feature_required') {
    return 'Режим «Только для соцсетей» доступен по подписке.';
  }
  if (responseCode == 'premium_server_required') {
    return 'Эта локация доступна по подписке.';
  }
  if (responseCode == 'free_quota_exhausted') {
    return 'Бесплатный лимит на этот месяц исчерпан. Откройте тариф или дождитесь нового месяца.';
  }

  if (statusCode == 401) return 'Сессия истекла. Войдите снова.';
  if (statusCode == 403) return 'Это действие сейчас недоступно.';
  if (statusCode == 404) return 'Сервис временно недоступен.';
  if (statusCode == 408 || statusCode == 504) {
    return 'Сервис не ответил вовремя. Повторите попытку.';
  }
  if (statusCode == 429) {
    return 'Слишком много запросов. Подождите немного и повторите попытку.';
  }
  if (statusCode != null && statusCode >= 500) {
    return 'Сервис временно недоступен. Повторите попытку позже.';
  }

  var candidate = (responseMessage ?? rawError).trim();
  candidate = candidate
      .replaceFirst(RegExp(r'^Ошибка сети:\s*', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^Exception:\s*', caseSensitive: false), '')
      .replaceFirst(RegExp(r',\s*uri\s*=.*$', caseSensitive: false), '')
      .trim();
  final lower = candidate.toLowerCase();

  if (lower.contains('timed out') ||
      lower.contains('timeoutexception') ||
      lower.contains('future not completed')) {
    return 'Сервис не ответил вовремя. Повторите попытку.';
  }
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection reset') ||
      lower.contains('handshakeexception')) {
    return 'Не удалось связаться с сервисом. Проверьте интернет и повторите попытку.';
  }
  if (lower.contains('competing_vpn') ||
      lower.contains('competing vpn') ||
      lower.contains('another vpn') ||
      lower.contains('другой vpn')) {
    return 'На устройстве активен другой VPN. Отключите его и повторите подключение.';
  }
  if (lower.contains('previous_route_still_active') ||
      lower.contains('previous route') ||
      lower.contains('не удалось полностью остановить')) {
    return 'Не удалось безопасно сменить маршрут. Отключите VPN и попробуйте ещё раз.';
  }
  if (lower.contains('vpn_permission_required') ||
      lower.contains('не выдал разрешение на vpn')) {
    return 'Разрешите Green VPN создать VPN-подключение в системном окне Android.';
  }

  final containsInternalDetails = RegExp(
    r'https?://|\buri\b|/api/|\{.*\}|[a-z]:\\|(?:\d{1,3}\.){3}\d{1,3}|wireguard|amnezia|hysteria|vless|naive|dnstt|ruvds|timeweb|sslip|exception|endpoint|backend|\bpreview\b|\bbeta\b|\bserver\s*=|\bprotocol\s*=',
    caseSensitive: false,
  ).hasMatch(candidate);
  if (candidate.isEmpty || candidate.length > 240 || containsInternalDetails) {
    return fallback;
  }
  return candidate;
}

String greenVpnSocialOnlyStatusText({
  required bool allowed,
  required bool enabled,
  bool usesApplications = true,
  bool usesMixedSelection = false,
  bool permanentFreeBuild = false,
}) {
  if (!allowed) {
    if (permanentFreeBuild) {
      return 'Функция пока недоступна. Бесплатный режим работает с обычным подключением.';
    }
    return 'Доступно по подписке. Бесплатный режим работает с обычным подключением.';
  }
  if (enabled) {
    final selectedKind = usesMixedSelection
        ? 'сервисы, программы и сайты'
        : (usesApplications ? 'приложения' : 'сервисы');
    return 'Функция активна. Выбранные $selectedKind пойдут через VPN, '
        'остальной трафик останется обычным.';
  }
  return 'Функция выключена. При подключении весь трафик пойдёт через VPN.';
}
