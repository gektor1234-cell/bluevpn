import 'dart:convert';

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
  final internal = RegExp(
    r'preview|\bbeta\b|wireguard|amnezia|hysteria|vless|naive|dnstt|ruvds|timeweb|backend|/api/|forced disconnect|transport',
    caseSensitive: false,
  );
  final cleaned = rawItems
      .map((item) => item.trim().replaceFirst(RegExp(r'^[•*-]+\s*'), ''))
      .where((item) => item.isNotEmpty && !internal.hasMatch(item))
      .toList(growable: false);
  if (cleaned.isNotEmpty || rawItems.isEmpty) return cleaned;
  return const ['Улучшены стабильность подключения и обновление приложения.'];
}

const List<String> greenVpnFixedPublicBillingPlanCodes = <String>[
  'green_30d',
  'green_90d',
  'green_180d',
];

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
}) {
  if (!allowed) return 'Функция временно недоступна для текущего режима.';
  if (enabled) {
    return 'Функция активна. Выбранные приложения пойдут через VPN, '
        'остальной трафик останется обычным.';
  }
  return 'Функция выключена. При подключении весь трафик пойдёт через VPN.';
}
