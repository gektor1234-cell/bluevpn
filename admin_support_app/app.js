const DEFAULT_API_BASE = 'https://api.greenvpn.pro';
const STORAGE_KEY = 'greenvpn.admin.session.v1';

const state = {
  apiBase: DEFAULT_API_BASE,
  adminToken: '',
  adminActor: '',
  adminEmail: '',
  sessionToken: '',
  authType: '',
  currentStaff: null,
  pendingAdmin2fa: null,
  permissions: [],
  roleTitle: '',
  section: 'dashboard',
  activeUserId: null,
  activeUserDetail: null,
  remotePeerSmokeBusyServerIds: new Set(),
  clientConfigSmokeBusyServerIds: new Set(),
  publicationGateBusyServerIds: new Set(),
  loaded: {
    overview: null,
    analytics: null,
    launchReadiness: null,
    advertisingReadiness: null,
    launchClosurePlan: null,
    launchOwnerPacket: null,
    readiness: null,
    siteReadiness: null,
    networkReadiness: null,
    networkSplitPlan: null,
    userAuthReadiness: null,
    adminTwoFactorReadiness: null,
    externalActions: null,
    support: [],
    supportSla: null,
    users: [],
    orders: [],
    promos: [],
    promoReadiness: null,
    billingReconciliation: null,
    billingRenewals: null,
    billingPaymentSmoke: null,
    subscriptionExpiry: null,
    auth: [],
    audit: [],
    roles: [],
    staff: [],
    incidents: [],
    incidentAssignees: [],
    alertEvents: [],
    releases: [],
    featureFlags: [],
    runbooks: [],
    supportActions: [],
    servers: [],
    supportWorkflow: null,
    supportActionWorkflow: null,
    incidentWorkflow: null,
    releaseWorkflow: null,
    featureFlagWorkflow: null,
    runbookWorkflow: null,
    serverWorkflow: null,
    serverCatalog: null,
    serverCatalogSummary: null,
    serverPublicationReadiness: null,
    serverProvisioningReadiness: null,
    serverHealth: null,
    resilienceRoutes: null,
    resilienceTransportRollout: null,
    monitoringTargets: null,
    serviceObservations: null,
    clientRouteEvents: null,
    monitoringProbes: null,
    monitoringReadiness: null,
    adminSessions: [],
    staffSessions: null,
    updateManifest: null,
    updateReadiness: null,
    monitoring: null,
    services: null,
  },
};

const $ = (id) => document.getElementById(id);

function safeText(value, fallback = '—') {
  if (value === null || value === undefined || value === '') return fallback;
  return String(value);
}

function escapeHtml(value, fallback = '—') {
  return safeText(value, fallback).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[char]));
}

function prettyJson(value) {
  try {
    return JSON.stringify(value, null, 2);
  } catch (_error) {
    return safeText(value);
  }
}

function redactApiErrorValue(value, depth = 0, key = '') {
  if (value === null || value === undefined) return value;
  if (/input|authorization|password|secret|token|private.?key|preshared.?key|api.?key/i.test(key)) {
    return '[redacted]';
  }
  if (typeof value !== 'object') return value;
  if (depth >= 3) return '[object]';
  if (Array.isArray(value)) {
    return value.slice(0, 8).map((item) => redactApiErrorValue(item, depth + 1));
  }
  return Object.fromEntries(
    Object.entries(value).map(([entryKey, entryValue]) => [
      entryKey,
      redactApiErrorValue(entryValue, depth + 1, entryKey),
    ]),
  );
}

function errorPatternCodes(value) {
  if (!value || typeof value !== 'object') return [];
  const direct = value.patternCodes || value.blockedPatternCodes || value.blockedNotePatternCodes;
  if (Array.isArray(direct)) return direct.map(String).filter(Boolean);
  if (Array.isArray(value.findings)) {
    return value.findings.map((item) => item?.code || item).map(String).filter(Boolean);
  }
  return [];
}

function formatApiErrorValue(value) {
  if (value === null || value === undefined || value === '') return '';
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) {
    return value
      .slice(0, 8)
      .map((item) => formatApiErrorValue(item))
      .filter(Boolean)
      .join('; ');
  }
  if (typeof value !== 'object') return String(value);

  const parts = [];
  const hasLocatedMessage = Array.isArray(value.loc) && value.msg;
  if (Array.isArray(value.loc) && value.msg) {
    parts.push(`${value.loc.join('.')}: ${value.msg}`);
  }
  for (const key of ['message', 'detail', 'error', 'title', 'msg']) {
    if (key === 'msg' && hasLocatedMessage) continue;
    if (typeof value[key] === 'string' && value[key].trim()) {
      parts.push(value[key].trim());
    }
  }
  if (typeof value.code === 'string' && value.code.trim()) {
    parts.push(`code=${value.code.trim()}`);
  }
  const patternCodes = errorPatternCodes(value);
  if (patternCodes.length) {
    parts.push(`blockedPatterns=${patternCodes.join(', ')}`);
  }
  const uniqueParts = [...new Set(parts)];
  if (uniqueParts.length) return uniqueParts.join('; ');
  return prettyJson(redactApiErrorValue(value));
}

function formatApiErrorDetail(data, text, fallback) {
  const detail = data?.detail ?? data?.message ?? data?.error;
  const formatted = formatApiErrorValue(detail);
  if (formatted) return formatted;
  const body = formatApiErrorValue(data);
  if (body && body !== '{}') return body;
  return text || fallback || 'Запрос не выполнен.';
}

function money(value) {
  if (value === null || value === undefined || value === '') return '—';
  return `${value} ₽`;
}

function boolLabel(value) {
  return value ? 'да' : 'нет';
}

function boolPill(value, yes = 'да', no = 'нет') {
  return `<span class="status-pill ${value ? '' : 'muted'}">${value ? yes : no}</span>`;
}

function safeNumber(value, fallback = 0) {
  const num = Number(value);
  return Number.isFinite(num) ? num : fallback;
}

function serverEndpointHost(server) {
  const endpoint = server?.endpoint;
  if (endpoint && typeof endpoint === 'object') {
    return endpoint.host || endpoint.hostname || server?.host || server?.endpointHost || '';
  }
  if (typeof endpoint === 'string' && endpoint.includes(':')) return endpoint.split(':')[0];
  return server?.host || server?.endpointHost || (typeof endpoint === 'string' ? endpoint : '');
}

function serverEndpointPort(server) {
  const endpoint = server?.endpoint;
  if (endpoint && typeof endpoint === 'object') return endpoint.port || 443;
  if (typeof endpoint === 'string' && endpoint.includes(':')) {
    const port = endpoint.split(':').pop();
    return Number(port) || server?.port || server?.endpointPort || 443;
  }
  return server?.port || server?.endpointPort || 443;
}

function serverIdentityValues(server) {
  return [server?.id, server?.serverId, server?.name, server?.host, server?.endpointHost]
    .map((value) => safeText(value, '').trim())
    .filter(Boolean);
}

function serverCapacityStatusTitle(status) {
  const normalized = safeText(status, 'green').toLowerCase();
  if (normalized === 'red') return 'перегрузка';
  if (normalized === 'yellow') return 'нагрузка растёт';
  return 'запас есть';
}

function serverCapacityPillClass(status) {
  const normalized = safeText(status, 'green').toLowerCase();
  if (normalized === 'red') return 'red';
  if (normalized === 'yellow') return 'yellow';
  return '';
}

function renderServerCapacity(server) {
  const capacity = server.capacity || {};
  const load = safeNumber(capacity.currentLoadMbps ?? server.currentLoadMbps, 0);
  const usable = safeNumber(capacity.usableBandwidthMbps ?? server.usableBandwidthMbps, 0);
  const planned = safeNumber(capacity.plannedBandwidthMbps ?? server.plannedBandwidthMbps, 0);
  const utilization = safeNumber(
    capacity.utilizationPercent ?? server.utilizationPercent,
    usable > 0 ? Math.round((load / usable) * 100) : 0,
  );
  const activeClients = safeNumber(capacity.activeClients ?? server.activeClients, 0);
  const assignedUsers = safeNumber(capacity.assignedUsers ?? server.assignedUsers, 0);
  const capacityStatus = capacity.capacityStatus || server.capacityStatus || 'green';
  const capacityScore = safeNumber(capacity.capacityScore ?? server.capacityScore, 100);
  const loadLabel = usable > 0
    ? `${load}/${usable} Мбит/с · ${utilization}%`
    : (planned > 0 ? `0/${planned} Мбит/с` : 'нагрузка —');

  return `
    <span class="status-pill ${serverCapacityPillClass(capacityStatus)}">
      ${escapeHtml(serverCapacityStatusTitle(capacityStatus))}
    </span><br>
    <strong>${escapeHtml(loadLabel)}</strong><br>
    <span class="muted">оценка ёмкости: ${escapeHtml(capacityScore)}%</span><br>
    <span class="muted">активные клиенты: ${escapeHtml(activeClients)}</span><br>
    <span class="muted">назначенные пользователи: ${escapeHtml(assignedUsers)}</span>
    ${capacity.loadUpdatedAt ? `<br><span class="muted">обновлено: ${escapeHtml(shortDate(capacity.loadUpdatedAt))}</span>` : ''}
  `;
}

const ADMIN_TEXT_TRANSLATIONS = new Map(Object.entries({
  'Request failed.': 'Запрос не выполнен.',
  'Critical Incidents': 'Критичные инциденты',
  'Critical incidents': 'Критичные инциденты',
  'production alerts': 'боевые оповещения',
  'Published releases': 'Опубликованные версии',
  'Endpoint failures 24h': 'Проблемы VPN-узлов за 24ч',
  'Auth events 24h': 'События входа за 24ч',
  'Admin alerts': 'Оповещения админки',
  'Product readiness': 'Готовность продукта',
  'Support Reports': 'Обращения в поддержку',
  'Support reports': 'Обращения в поддержку',
  'Support Actions 24h': 'Действия поддержки за 24ч',
  'Support actions 24h': 'Действия поддержки за 24ч',
  'Configure Telegram bot token and chat id for automatic incident alerts.': 'Настрой Telegram-бота и ID чата для автоматических оповещений об инцидентах.',
  'open=0, reviewPending=0, firstResponseMissing=0': 'открыто=0, ждут разбора=0, без первого ответа=0',
  'overdue=0, dueSoon=0, missingSla=0': 'просрочено=0, скоро срок=0, без SLA=0',
  'manual_mvp': 'ручной MVP',
  'service_alerts_enabled': 'оповещения по сервисам',
  'server_health_score': 'оценка здоровья серверов',
  'monitoring_probes': 'внешний мониторинг',
  'admin_alerts': 'оповещения админов',
  'updates': 'обновления',
  'owner_actions': 'действия владельца',
  'code_signing': 'подпись Windows',
  'windows_distribution_trust': 'доверенный Windows-релиз',
  'update_artifact': 'файл обновления',
  'rollback_artifact': 'файл отката',
  'Backend API': 'Сервер API',
  'Green VPN Backend': 'Сервер API Green VPN',
  'Database': 'База данных',
  'Server Catalog': 'Каталог серверов',
  'Updates': 'Обновления',
  'Payments': 'Платежи',
  'SLA queue': 'Очередь SLA',
  'Overdue / due soon': 'Просрочено / скоро срок',
  'Runbook: не найден': 'Инструкция: не найдена',
  'Runbook: not found': 'Инструкция: не найдена',
  'External probe install bundle': 'Пакет установки внешней проверки',
  'Auto-renewal readiness': 'Готовность автопродления',
  'Auto-renewal readiness not loaded yet.': 'Готовность автопродления пока не загружена.',
  'Auth flow gate зелёный.': 'Проверка входа зелёная.',
  'Methods:': 'Способы входа:',
  'Smoke steps:': 'Шаги тестового платежа:',
  'Blocks:': 'Блокеры:',
  'Expiry issues:': 'Проблемы окончания подписок:',
  'Renewal issues:': 'Проблемы автопродления:',
  'Candidates:': 'Кандидаты:',
  'Issues:': 'Проблемы:',
  'Required:': 'Требуется:',
  'Verify:': 'Проверка:',
  'Apply:': 'Применение:',
  'After apply:': 'После применения:',
  'Launch blockers:': 'Блокеры запуска:',
  'Recent problems:': 'Последние проблемы:',
  'Review': 'Проверка',
  'Decoded report для техподдержки': 'Расшифрованный отчёт для техподдержки',
  'Encoded report': 'Закодированный отчёт',
  'Endpoint': 'VPN-узел',
  'endpoint': 'VPN-узел',
  'endpoints': 'VPN-узлы',
  'Managed endpoints': 'Управляемые VPN-узлы',
  'Managed catalog': 'Управляемый каталог',
  'Provisioning gate': 'Проверка выдачи конфигов',
  'serverId contract': 'Правила выбора служебного ID сервера',
  'Bootstrap': 'Стартовая конфигурация',
  'Почему не public': 'Почему не опубликовано',
  'Summary пока не загружен.': 'Сводка пока не загружена.',
  'Readiness endpoint пока не загружен.': 'Проверка готовности пока не загружена.',
  'Provisioning readiness пока не загружен.': 'Проверка выдачи конфигов пока не загружена.',
  'No bootstrap URLs': 'Нет стартовых URL',
  'controlled agent readiness': 'готовность управляемого агента',
  'Отдельный monitoring VPS ещё не подключён': 'Отдельный VPS мониторинга ещё не подключён',
  'Покрытие endpoint': 'Покрытие VPN-узлов',
  'Внешние endpoint probes': 'Внешние проверки VPN-узлов',
  'Покрытие внешним probe': 'Покрытие внешней проверкой',
  'Наблюдений пока нет. Агент мониторинга позже начнёт присылать проверки endpoint-ов.': 'Наблюдений пока нет. Агент мониторинга позже начнёт присылать проверки VPN-узлов.',
  'Endpoint probes': 'Проверки VPN-узлов',
  'production готов': 'готов к запуску',
  'production-оповещения': 'боевые оповещения',
  'Production-платежи готовы.': 'Боевые платежи готовы.',
  'Update manifest настроен.': 'Манифест обновлений настроен.',
  'Доступно endpoint': 'Доступно VPN-узлов',
  'ok': 'ок',
  'fail': 'ошибка',
  'failed': 'ошибка',
  'warning': 'внимание',
  'todo': 'сделать',
  'clean': 'чисто',
  'attention': 'внимание',
  'overdue': 'просрочено',
  'soon': 'скоро срок',
  'needs setup': 'настроить',
  'setup': 'настроить',
  'blocked': 'заблокировано',
  'review': 'проверить',
  'guard off': 'защита выключена',
  'available': 'доступно',
  'created': 'создано',
  'verified': 'подтверждено',
  'cancelled': 'отменено',
  'succeeded': 'успешно',
  'waiting_user': 'ждём пользователя',
  'in_progress': 'в работе',
  'resolved': 'решено',
  'closed': 'закрыто',
  'legacy': 'старый режим',
  'draft': 'черновик',
  'published': 'опубликовано',
  'paused': 'пауза',
  'retired': 'выведено',
  'open': 'открыто',
  'done': 'готово',
  'noop': 'без изменений',
  'queued': 'в очереди',
  'pending': 'ожидает',
  'healthy': 'здоров',
  'degraded': 'деградация',
  'maintenance': 'обслуживание',
  'disabled': 'выключен',
  'active': 'активен',
  'inactive': 'неактивен',
  'public': 'публичный',
  'internal': 'внутренний',
  'client-safe': 'безопасно для клиента',
  'safe-gate': 'защитная проверка',
  'preparation': 'подготовка',
  'internal-only': 'только внутри',
  'not_public_candidate': 'не выбран для публикации',
  'not_public': 'не опубликован',
  'not_ready': 'не готов',
  'public_candidate': 'кандидат на публикацию',
  'client_config_ready': 'конфиг для клиента готов',
  'client_config_not_ready': 'конфиг для клиента не готов',
  'public_catalog_only': 'только опубликованные серверы',
  'capacity_aware_best_public_endpoint': 'автовыбор по нагрузке и здоровью',
  'client_selection_is_public_catalog_only': 'клиент видит только опубликованные серверы',
  'lightest_healthy_client_ready_layer': 'самый лёгкий рабочий способ подключения',
  'fresh_health_observation': 'есть свежая проверка здоровья',
  'missing_health_observation': 'нет свежей проверки здоровья',
  'overloaded': 'перегружен',
  'server_health_green': 'сервер здоров',
  'server_health_yellow': 'сервер требует внимания',
  'server_health_red': 'сервер недоступен',
  'non-secret': 'без секретов',
  'owner': 'владелец',
  'blockers': 'блокеры',
  'selection': 'выбор',
  'none': 'нет',
  'none in window': 'нет в окне проверки',
  'dry-run eligible': 'можно проверить без списания',
  'dry-run only': 'только проверка без списания',
  'safe dry-run': 'безопасная проверка',
  'smoke ok': 'тестовый платеж пройден',
  'run smoke': 'запустить тестовый платеж',
  'Requires clean payment smoke.': 'Нужен чистый тестовый платеж.',
  'expiry readiness only': 'только проверка окончания подписок',
  'not enforced': 'не включено',
  'enforced': 'включено',
  'expiring': 'скоро закончится',
  'reviewed': 'проверено',
  'Review support report': 'Проверка обращения',
  'Subscription expiry review': 'Проверка окончания подписки',
  'Expiry review reason': 'Причина проверки окончания подписки',
  'Expiry review saved for subscription': 'Проверка окончания подписки сохранена для подписки',
  'Could not save expiry review': 'Не удалось сохранить проверку окончания подписки',
  'bootstrap token': 'токен владельца',
  'Bootstrap token': 'Токен владельца',
  'bootstrap_token': 'владелец',
  'staff_session': 'сотрудник',
  'offline': 'не подключено',
  'staff': 'сотрудник',
  'status': 'статус',
  'empty': 'пусто',
  'email_code_start': 'отправка кода на почту',
  'email_code_verify': 'проверка кода с почты',
  'phone_code_start': 'отправка кода на телефон',
  'phone_code_verify': 'проверка кода с телефона',
  'password_login': 'вход по паролю',
  'staff_login': 'вход сотрудника',
  'staff_2fa_start': 'код сотрудника отправлен',
  'staff_2fa_verify': 'код сотрудника проверен',
  'legacy': 'старый режим',
  'available': 'доступно',
  'blocked': 'заблокировано',
  'sent': 'отправлено',
  'skipped': 'пропущено',
  'waiting_owner': 'ждём владельца',
  'waiting_provider': 'ждём провайдера',
  'ready_to_apply': 'готово к применению',
  'not_needed': 'не требуется',
  'new': 'новое',
  'triage': 'разбор',
  'urgent': 'срочно',
  'high': 'высокая',
  'medium': 'средняя',
  'normal': 'обычная',
  'low': 'низкая',
  'critical': 'критично',
  'investigating': 'разбираем',
  'mitigated': 'сдержан',
  'health gate': 'проверка здоровья',
  'red': 'красный',
  'yellow': 'жёлтый',
  'green': 'зелёный',
  'gray': 'серый',
  'user-agent не записан': 'данные браузера не записаны',
}));

const ADMIN_TEXT_REPLACEMENTS = [
  [/\bproduction alerts\b/gi, 'боевые оповещения'],
  [/\bmanual_mvp\b/g, 'ручной MVP'],
  [/\bservice_alerts_enabled\b/g, 'оповещения по сервисам'],
  [/\bserver_health_score\b/g, 'оценка здоровья серверов'],
  [/\bmonitoring_probes\b/g, 'внешний мониторинг'],
  [/\badmin_alerts\b/g, 'оповещения админов'],
  [/\bowner_actions\b/g, 'действия владельца'],
  [/\bcode_signing\b/g, 'подпись Windows'],
  [/\bwindows_distribution_trust\b/g, 'доверенный Windows-релиз'],
  [/\bupdate_artifact\b/g, 'файл обновления'],
  [/\brollback_artifact\b/g, 'файл отката'],
  [/\bProduction-payments\b/g, 'Боевые платежи'],
  [/\bproduction-платежи\b/gi, 'боевые платежи'],
  [/\bproduction\b/gi, 'боевой режим'],
  [/\bBackend API\b/g, 'Сервер API'],
  [/\bGreen VPN Backend\b/g, 'Сервер API Green VPN'],
  [/\bDatabase\b/g, 'База данных'],
  [/\bServer Catalog\b/g, 'Каталог серверов'],
  [/\bUpdates\b/g, 'Обновления'],
  [/\bUpdate manifest\b/g, 'Манифест обновлений'],
  [/\bPayments\b/g, 'Платежи'],
  [/\bPublished releases\b/g, 'Опубликованные версии'],
  [/\bCritical Incidents\b/g, 'Критичные инциденты'],
  [/\bCritical incidents\b/g, 'Критичные инциденты'],
  [/\bEndpoint failures 24h\b/g, 'Проблемы VPN-узлов за 24ч'],
  [/\bAuth events 24h\b/g, 'События входа за 24ч'],
  [/\bAdmin alerts\b/g, 'Оповещения админки'],
  [/\bProduct readiness\b/g, 'Готовность продукта'],
  [/\bSupport Reports\b/g, 'Обращения в поддержку'],
  [/\bSupport reports\b/g, 'Обращения в поддержку'],
  [/\bSupport Actions 24h\b/g, 'Действия поддержки за 24ч'],
  [/\bSupport actions 24h\b/g, 'Действия поддержки за 24ч'],
  [/Configure Telegram bot token and chat id for automatic incident alerts\./g, 'Настрой Telegram-бота и ID чата для автоматических оповещений об инцидентах.'],
  [/\bnot_public_candidate\b/g, 'не выбран для публикации'],
  [/\bnot_public\b/g, 'не опубликован'],
  [/\bnot_ready\b/g, 'не готов'],
  [/\bpublic_candidate\b/g, 'кандидат на публикацию'],
  [/\bclient_config_ready\b/g, 'конфиг для клиента готов'],
  [/\bclient_config_not_ready\b/g, 'конфиг для клиента не готов'],
  [/\bpublic_catalog_only\b/g, 'только опубликованные серверы'],
  [/\bcapacity_aware_best_public_endpoint\b/g, 'автовыбор по нагрузке и здоровью'],
  [/\bclient_selection_is_public_catalog_only\b/g, 'клиент видит только опубликованные серверы'],
  [/\blightest_healthy_client_ready_layer\b/g, 'самый лёгкий рабочий способ подключения'],
  [/\bfresh_health_observation\b/g, 'есть свежая проверка здоровья'],
  [/\bmissing_health_observation\b/g, 'нет свежей проверки здоровья'],
  [/\boverloaded\b/g, 'перегружен'],
  [/\bserver_health_green\b/g, 'сервер здоров'],
  [/\bserver_health_yellow\b/g, 'сервер требует внимания'],
  [/\bserver_health_red\b/g, 'сервер недоступен'],
  [/\bmanaged ready\b/g, 'управляемых готово'],
  [/\bobserved\b/g, 'наблюдений'],
  [/\bdraft\b/g, 'черновиков'],
  [/\breviewPending\b/g, 'ждут разбора'],
  [/\bfirstResponseMissing\b/g, 'без первого ответа'],
  [/\bdueSoon\b/g, 'скоро срок'],
  [/\bmissingSla\b/g, 'без SLA'],
  [/\bfailed\b/g, 'неудачных'],
  [/\bfail\b/g, 'ошибка'],
  [/\bwarning\b/g, 'внимание'],
  [/\bneeds setup\b/g, 'настроить'],
  [/\bavailable\b/g, 'доступно'],
  [/\bblocked\b/g, 'заблокировано'],
  [/\bclean\b/g, 'чисто'],
  [/\breviewPending\b/g, 'ждут разбора'],
  [/\bfirstResponseMissing\b/g, 'без первого ответа'],
  [/\bdueSoon\b/g, 'скоро срок'],
  [/\bmissingSla\b/g, 'без SLA'],
  [/\boverdue\b/g, 'просрочено'],
  [/\bEndpoint\b/g, 'VPN-узел'],
  [/\bendpoint\b/g, 'VPN-узел'],
  [/\bendpoints\b/g, 'VPN-узлы'],
  [/\bopen=/g, 'открыто='],
  [/\btotal=/g, 'всего='],
  [/\battention=/g, 'требуют внимания='],
  [/\bhigh=/g, 'высокая важность='],
  [/\bmedium=/g, 'средняя важность='],
  [/\bprovider=/g, 'провайдер='],
  [/\bsafeToRun=/g, 'можно запускать='],
  [/\bcompleted=/g, 'завершено='],
  [/\bpendingUrl=/g, 'ждут ссылки='],
  [/\bsuccessful=/g, 'успешно='],
  [/\bautoRenew=/g, 'автопродление='],
  [/\bdue=/g, 'срок='],
  [/\beligible=/g, 'подходит='],
  [/\bmissingMethod=/g, 'нет способа оплаты='],
  [/\bsmoke=/g, 'тестовый платёж='],
  [/\bactive=/g, 'активно='],
  [/\bexpiring=/g, 'скоро закончится='],
  [/\bexpired=/g, 'закончилось='],
  [/\bmanual=/g, 'вручную='],
  [/\breviewed=/g, 'проверено='],
  [/\bowner=/g, 'владелец='],
  [/\bcode=/g, 'код='],
  [/\bops=/g, 'операции='],
  [/\bfinal=/g, 'финал='],
  [/\blaunchReady=/g, 'готово к запуску='],
  [/\brisky=/g, 'риск='],
  [/\byookassaOrders=/g, 'заказы ЮKassa='],
  [/\bgreen=/g, 'зелёные='],
  [/\byellow=/g, 'жёлтые='],
  [/\bsite=/g, 'сайт='],
  [/\bdownloads:/g, 'загрузки:'],
  [/\bwindows=/g, 'Windows='],
  [/\bandroid=/g, 'Android='],
  [/\bios=/g, 'iOS='],
  [/\bprimary=/g, 'основной способ='],
  [/\bfallback=/g, 'запасной способ='],
  [/\busers=/g, 'пользователи='],
  [/\bverified24h=/g, 'подтверждений за 24ч='],
  [/\bproblems24h=/g, 'проблем за 24ч='],
  [/\bverified\b/g, 'подтверждено'],
  [/\blegacy\b/g, 'старый режим'],
  [/\boff\b/g, 'выключено'],
  [/\blogin:/g, 'последний вход:'],
  [/\blast:/g, 'последняя активность:'],
  [/\btotal\b/g, 'всего'],
  [/\bactive\b/g, 'активно'],
  [/\bnew\b/g, 'новое'],
  [/\btriage\b/g, 'разбор'],
  [/\binvestigating\b/g, 'разбираем'],
  [/\bmitigated\b/g, 'сдержан'],
  [/\bhealth gate\b/g, 'проверка здоровья'],
];

function translateAdminText(value, fallback = '') {
  const raw = safeText(value, fallback);
  if (!raw) return raw;
  if (/^(https?:\/\/|\/api\/|[A-Z0-9_]+$)/.test(raw)) return raw;
  const exact = ADMIN_TEXT_TRANSLATIONS.get(raw);
  if (exact) return exact;
  let translated = raw;
  for (const [pattern, replacement] of ADMIN_TEXT_REPLACEMENTS) {
    translated = translated.replace(pattern, replacement);
  }
  return ADMIN_TEXT_TRANSLATIONS.get(translated) || translated;
}

function escapeUi(value, fallback = '') {
  return escapeHtml(translateAdminText(value, fallback));
}

function translateAdminDom(root = document.body) {
  if (!root || typeof document === 'undefined' || typeof NodeFilter === 'undefined') return;
  const walker = document.createTreeWalker(
    root,
    NodeFilter.SHOW_TEXT,
    {
      acceptNode(node) {
        const text = node.nodeValue || '';
        if (!text.trim()) return NodeFilter.FILTER_REJECT;
        const parent = node.parentElement;
        if (!parent || parent.closest('script, style, code, pre, textarea')) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    },
  );
  const nodes = [];
  while (walker.nextNode()) {
    nodes.push(walker.currentNode);
  }
  nodes.forEach((node) => {
    const translated = translateAdminText(node.nodeValue);
    if (translated !== node.nodeValue) {
      node.nodeValue = translated;
    }
  });
}

function supportWorkflow() {
  return state.loaded.supportWorkflow || {
    statuses: ['new', 'triage', 'in_progress', 'waiting_user', 'resolved', 'closed'],
    priorities: [
      { code: 'urgent', title: 'Срочно', slaHours: 4 },
      { code: 'high', title: 'Высокий', slaHours: 12 },
      { code: 'normal', title: 'Обычный', slaHours: 24 },
      { code: 'low', title: 'Низкий', slaHours: 72 },
    ],
    categories: [
      { code: 'vpn_connect', title: 'VPN подключение' },
      { code: 'network', title: 'Сеть' },
      { code: 'auth', title: 'Вход' },
      { code: 'payment', title: 'Оплата' },
      { code: 'installer', title: 'Установщик' },
      { code: 'app_ui', title: 'Интерфейс' },
      { code: 'general', title: 'Общее' },
    ],
  };
}

function workflowTitle(group, code) {
  const items = supportWorkflow()[group] || [];
  const item = items.find((entry) => entry.code === code);
  return item?.title || code || '—';
}

function workflowOptionsHtml(items, selected, allLabel = '') {
  const options = [];
  if (allLabel) {
    options.push(`<option value="all" ${selected === 'all' ? 'selected' : ''}>${escapeHtml(allLabel)}</option>`);
  }
  for (const item of items || []) {
    options.push(`
      <option value="${escapeHtml(item.code)}" ${item.code === selected ? 'selected' : ''}>
        ${escapeUi(item.title || item.code)}
      </option>
    `);
  }
  return options.join('');
}

function simpleOptionsHtml(items, selected, allLabel = '') {
  return workflowOptionsHtml(
    (items || []).map((item) => (
      typeof item === 'string'
        ? { code: item, title: item }
        : item
    )),
    selected,
    allLabel,
  );
}

function priorityPillClass(priority) {
  if (priority === 'urgent') return 'red';
  if (priority === 'high') return 'yellow';
  if (priority === 'low') return 'muted';
  return '';
}

function slaPillClass(report) {
  if (!report?.slaDueAt || ['resolved', 'closed'].includes(report.status)) {
    return 'muted';
  }
  const dueAt = new Date(report.slaDueAt);
  if (Number.isNaN(dueAt.getTime())) return 'yellow';
  return dueAt.getTime() < Date.now() ? 'red' : '';
}

function incidentWorkflow() {
  return state.loaded.incidentWorkflow || {
    statuses: ['open', 'investigating', 'mitigated', 'resolved'],
    severities: [
      { code: 'critical', title: 'Критично', rank: 4 },
      { code: 'high', title: 'Высокая', rank: 3 },
      { code: 'medium', title: 'Средняя', rank: 2 },
      { code: 'low', title: 'Низкая', rank: 1 },
    ],
  };
}

function incidentStatusTitle(status) {
  return {
    open: 'Открыт',
    investigating: 'Разбираем',
    mitigated: 'Сдержан',
    resolved: 'Решён',
  }[status] || status || '—';
}

function incidentSeverityTitle(severity) {
  const item = (incidentWorkflow().severities || []).find((entry) => entry.code === severity);
  return item?.title || severity || '—';
}

function incidentSeverityPillClass(severity) {
  if (severity === 'critical' || severity === 'high') return 'red';
  if (severity === 'medium') return 'yellow';
  return 'muted';
}

function incidentStatusPillClass(status) {
  if (status === 'open') return 'red';
  if (status === 'investigating') return 'yellow';
  if (status === 'mitigated') return '';
  return 'muted';
}

function incidentAssigneeLabel(incident) {
  return incident.assignee || 'не назначен';
}

function currentStaffAssigneeId() {
  return state.currentStaff?.id ? Number(state.currentStaff.id) : null;
}

function currentIncidentAssigneePayload() {
  const staffId = currentStaffAssigneeId();
  if (staffId) {
    return { assigneeStaffId: staffId };
  }
  return { assignee: state.adminActor || 'support' };
}

function currentSupportAssignee() {
  return state.currentStaff?.displayName || state.currentStaff?.email || state.adminActor || 'support';
}

function incidentAssigneeOptionsHtml(currentStaffId, currentLabel = '') {
  const selected = currentStaffId ? String(currentStaffId) : '';
  const assignees = state.loaded.incidentAssignees || [];
  const options = [
    '<option value="">Не назначен</option>',
    ...(!selected && currentLabel ? [`<option value="${escapeHtml(currentLabel)}" selected>${escapeHtml(currentLabel)}</option>`] : []),
    ...assignees.map((item) => {
      const value = String(item.id);
      const label = item.label || item.displayName || item.email || `staff:${item.id}`;
      const role = item.roleTitle || item.role || '';
      return `<option value="${escapeHtml(value)}" ${value === selected ? 'selected' : ''}>${escapeHtml(label)}${role ? ` · ${escapeHtml(role)}` : ''}</option>`;
    }),
  ];
  return options.join('');
}

function incidentAssigneeUpdatePayload(value) {
  if (!value) {
    return { clearAssignee: true };
  }
  if (/^\d+$/.test(value)) {
    return { assigneeStaffId: Number(value) };
  }
  return { assignee: value };
}

function renderSupportWorkflowFilters() {
  const workflow = supportWorkflow();
  const prioritySelect = $('supportPriorityFilter');
  const categorySelect = $('supportCategoryFilter');
  if (prioritySelect) {
    const current = prioritySelect.value || 'all';
    prioritySelect.innerHTML = workflowOptionsHtml(workflow.priorities, current, 'Любой приоритет');
  }
  if (categorySelect) {
    const current = categorySelect.value || 'all';
    categorySelect.innerHTML = workflowOptionsHtml(workflow.categories, current, 'Любая категория');
  }
}

function supportActionFilterParams() {
  const rawUserId = $('supportActionUserFilter')?.value?.trim() || '';
  return {
    limit: 80,
    action: $('supportActionTypeFilter')?.value || 'all',
    status: $('supportActionStatusFilter')?.value || 'all',
    userId: /^\d+$/.test(rawUserId) ? rawUserId : '',
  };
}

function renderSupportActionFilters() {
  const workflow = supportActionsWorkflow();
  const actionSelect = $('supportActionTypeFilter');
  const statusSelect = $('supportActionStatusFilter');
  if (actionSelect) {
    const current = actionSelect.value || 'all';
    actionSelect.innerHTML = workflowOptionsHtml(
      workflow.actions || [],
      current,
      'Все действия',
    );
  }
  if (statusSelect) {
    const current = statusSelect.value || 'all';
    const statusItems = (workflow.statuses || []).map((status) => ({
      code: status,
      title: status,
    }));
    statusSelect.innerHTML = workflowOptionsHtml(statusItems, current, 'Все статусы');
  }
}

function renderIncidentFilters() {
  const workflow = incidentWorkflow();
  const statusSelect = $('incidentStatusFilter');
  const severitySelect = $('incidentSeverityFilter');
  const assigneeSelect = $('incidentAssigneeFilter');
  if (statusSelect) {
    const current = statusSelect.value || 'all';
    const statusItems = (workflow.statuses || []).map((status) => ({
      code: status,
      title: incidentStatusTitle(status),
    }));
    statusSelect.innerHTML = workflowOptionsHtml(statusItems, current, 'Все статусы');
  }
  if (severitySelect) {
    const current = severitySelect.value || 'all';
    severitySelect.innerHTML = workflowOptionsHtml(
      workflow.severities || [],
      current,
      'Любая важность',
    );
  }
  if (assigneeSelect) {
    const current = assigneeSelect.value || 'all';
    const options = [
      '<option value="all">Все исполнители</option>',
      '<option value="unassigned">Не назначены</option>',
      ...((state.loaded.incidentAssignees || []).map((item) => {
        const value = String(item.id);
        const label = item.label || item.displayName || item.email || `staff:${item.id}`;
        return `<option value="${escapeHtml(value)}" ${value === current ? 'selected' : ''}>${escapeHtml(label)}</option>`;
      })),
    ];
    assigneeSelect.innerHTML = options.join('');
  }
}

function releaseWorkflow() {
  return state.loaded.releaseWorkflow || {
    platforms: ['windows'],
    channels: ['stable', 'beta', 'internal'],
    statuses: ['draft', 'published', 'paused', 'retired'],
  };
}

function releaseChannelTitle(channel) {
  return {
    stable: 'Стабильный',
    beta: 'Тестовый',
    internal: 'Внутренний',
  }[channel] || channel || '—';
}

function releaseStatusTitle(status) {
  return {
    draft: 'Черновик',
    published: 'Опубликован',
    paused: 'На паузе',
    retired: 'Выведен',
  }[status] || status || '—';
}

function releaseStatusPillClass(status) {
  if (status === 'published') return '';
  if (status === 'paused') return 'yellow';
  if (status === 'retired') return 'red';
  return 'muted';
}

function releaseFilterParams() {
  return {
    platform: 'windows',
    channel: $('releaseChannelFilter')?.value || 'all',
    status: $('releaseStatusFilter')?.value || 'all',
    limit: 100,
  };
}

function updateReadinessFilterParams() {
  const channel = $('releaseChannelFilter')?.value || 'stable';
  return {
    platform: 'windows',
    channel: channel === 'all' ? 'stable' : channel,
  };
}

function renderReleaseFilters() {
  const workflow = releaseWorkflow();
  const channelSelect = $('releaseChannelFilter');
  const statusSelect = $('releaseStatusFilter');
  const channelInput = $('releaseChannelInput');
  const statusInput = $('releaseStatusInput');

  const channelItems = (workflow.channels || []).map((channel) => ({
    code: channel,
    title: releaseChannelTitle(channel),
  }));
  const statusItems = (workflow.statuses || []).map((status) => ({
    code: status,
    title: releaseStatusTitle(status),
  }));

  if (channelSelect) {
    const current = channelSelect.value || 'all';
    channelSelect.innerHTML = workflowOptionsHtml(channelItems, current, 'Все каналы');
  }
  if (statusSelect) {
    const current = statusSelect.value || 'all';
    statusSelect.innerHTML = workflowOptionsHtml(statusItems, current, 'Все статусы');
  }
  if (channelInput) {
    const current = channelInput.value || 'internal';
    channelInput.innerHTML = workflowOptionsHtml(channelItems, current);
    if (!channelInput.value) channelInput.value = 'internal';
  }
  if (statusInput) {
    const current = statusInput.value || 'draft';
    statusInput.innerHTML = workflowOptionsHtml(statusItems, current);
    if (!statusInput.value) statusInput.value = 'draft';
  }
}

function renderUpdateReadiness() {
  const readiness = state.loaded.updateReadiness;
  const container = $('updateReadinessSummary');
  if (!container) return;
  if (!readiness) {
    container.innerHTML = '<p class="muted">Готовность обновления пока не загружена.</p>';
    return;
  }

  const manifest = readiness.manifest || {};
  const releaseGate = readiness.latestReleaseReadiness || readiness.latestPublishedRelease?.releaseReadiness || {};
  const rollbackGate = readiness.rollbackReadiness || releaseGate.rollbackReadiness || {};
  const checks = readiness.checks || [];
  const summary = readiness.summary || {};
  const header = {
    title: readiness.productionReady
      ? 'Обновление готово к публичной раскатке'
      : 'Обновление ждёт финальный файл',
    message: `${summary.message || ''} версия=${manifest.latestVersion || '—'}, файл готов=${boolLabel(manifest.fileReady)}, HTTPS доступен=${boolLabel(manifest.publicHttpsReady)}, откат готов=${boolLabel(rollbackGate.rollbackReady)}`,
    ok: Boolean(readiness.productionReady),
    warning: !readiness.productionReady,
    pill: readiness.productionReady ? 'готово' : 'черновик',
  };
  container.innerHTML = [header, ...checks]
    .map(
      (item) => `
        <div class="check-row">
          ${statusDot(Boolean(item.ok), !item.ok || item.warning)}
          <div>
            <strong>${escapeUi(item.title || item.code)}</strong>
            <span>${escapeUi(item.message || '')}</span>
          </div>
          <span class="status-pill ${item.ok ? '' : 'yellow'}">${escapeUi(item.pill || (item.ok ? 'ok' : 'todo'))}</span>
        </div>
      `,
    )
    .join('');
}

function renderUpdateManifest() {
  const manifest = state.loaded.updateManifest;
  const container = $('updateManifestSummary');
  if (!container) return;
  if (!manifest) {
    container.innerHTML = '<p class="muted">Манифест пока не загружен.</p>';
    return;
  }

  const fileReady = manifest.fileReady !== undefined
    ? Boolean(manifest.fileReady)
    : Boolean(manifest.downloadUrl && manifest.sha256);
  const updateReadiness = state.loaded.updateReadiness || {};
  const releaseGate = updateReadiness.latestReleaseReadiness || updateReadiness.latestPublishedRelease?.releaseReadiness || {};
  const rollbackGate = updateReadiness.rollbackReadiness || releaseGate.rollbackReadiness || {};
  const items = [
    {
      title: `Последняя версия: ${manifest.latestVersion || '—'}`,
      message: `источник=${manifest.source || '—'}, канал=${manifest.channel || 'stable'}, платформа=${manifest.platform || 'windows'}`,
      ok: true,
      warning: false,
      pill: manifest.updateAvailable ? 'обновление' : 'текущая',
    },
    {
      title: 'Файл обновления',
      message: manifest.downloadUrl || 'Ссылка на загрузку ещё не опубликована',
      ok: fileReady,
      warning: !fileReady,
      pill: fileReady ? 'готово' : 'черновик',
    },
    {
      title: 'Проверка перед публикацией',
      message: `${releaseGate.summary || 'Нет опубликованной версии для проверки'} ${releaseGate.blockers?.length ? `блокеры=${releaseGate.blockers.join(', ')}` : ''}`,
      ok: Boolean(releaseGate.canPublish),
      warning: !releaseGate.canPublish,
      pill: releaseGate.canPublish ? 'готово' : 'заблокировано',
    },
    {
      title: 'План отката',
      message: `${rollbackGate.summary || 'Файл для отката ещё не настроен.'} ${rollbackGate.blockers?.length ? `блокеры=${rollbackGate.blockers.join(', ')}` : ''}`,
      ok: Boolean(rollbackGate.rollbackReady),
      warning: !rollbackGate.rollbackReady,
      pill: rollbackGate.rollbackReady ? 'готово' : 'подготовка',
    },
    {
      title: 'Обязательность и rollout',
      message: `обязательное=${manifest.required ? 'да' : 'нет'}, раскатка=${manifest.rolloutPercent ?? 100}%, подходит=${manifest.rolloutEligible ? 'да' : 'нет'}, причина=${manifest.rolloutReason || '—'}`,
      ok: !manifest.releaseBlocked,
      warning: Boolean(manifest.releaseBlocked),
      pill: manifest.required ? 'обязательно' : (manifest.releaseBlocked ? 'заблокировано' : 'необязательно'),
    },
  ];
  container.innerHTML = items
    .map(
      (item) => `
        <div class="check-row">
          ${statusDot(item.ok, item.warning)}
          <div>
            <strong>${escapeUi(item.title)}</strong>
            <span>${escapeUi(item.message)}</span>
          </div>
          <span class="status-pill ${item.ok ? '' : 'yellow'}">${escapeUi(item.pill)}</span>
        </div>
      `,
    )
    .join('');
}

function renderReleasesTable() {
  const rows = state.loaded.releases || [];
  const table = $('releasesTable');
  if (!table) return;
  const canManageUpdates = can('updates.manage');
  table.innerHTML =
    rows
      .map((release) => {
        const readiness = release.releaseReadiness || {};
        const rollbackGate = readiness.rollbackReadiness || {};
        const blockers = readiness.blockers || [];
        const warnings = readiness.warnings || [];
        const canPublish = release.status !== 'published';
        const publishBlocked = canPublish && readiness.canPublish === false;
        const canPause = release.status === 'published';
        const canRetire = release.status !== 'retired';
        return `
          <tr>
            <td>#${escapeHtml(release.id)}</td>
            <td>
              <strong>${escapeHtml(release.version)}</strong><br>
              <span class="muted">${escapeHtml(release.buildNumber)}</span>
            </td>
            <td><span class="status-pill muted">${escapeHtml(releaseChannelTitle(release.channel))}</span></td>
            <td><span class="status-pill ${releaseStatusPillClass(release.status)}">${escapeHtml(releaseStatusTitle(release.status))}</span></td>
            <td>${escapeHtml(release.rolloutPercent, '100')}%</td>
            <td>
              <span class="muted">${release.downloadUrl ? 'URL готов' : 'без URL'}</span><br>
              <span class="muted">${release.sha256 ? 'SHA256 готов' : 'без SHA256'}</span><br>
              <span class="status-pill ${readiness.canPublish ? '' : 'yellow'}">${readiness.canPublish ? 'публикация готова' : 'заблокировано'}</span>
              <span class="status-pill ${rollbackGate.rollbackReady ? '' : 'yellow'}">${rollbackGate.rollbackReady ? 'откат готов' : 'откат готовится'}</span>
              ${
                blockers.length || warnings.length
                  ? `<br><span class="muted">${escapeHtml([...blockers, ...warnings].slice(0, 2).join(', '))}</span>`
                  : ''
              }
            </td>
            <td>${escapeHtml(shortDate(release.updatedAt))}</td>
            <td>
              ${
                canManageUpdates
                  ? `<div class="row-actions">
                      <button class="small-button" data-release-edit="${escapeHtml(release.id)}">В форму</button>
                      ${
                        canPublish
                          ? `<button class="small-button" data-release-publish="${escapeHtml(release.id)}" ${publishBlocked ? 'disabled' : ''}>Опубликовать</button>`
                          : ''
                      }
                      ${
                        canPause
                          ? `<button class="small-button" data-release-pause="${escapeHtml(release.id)}">Пауза</button>`
                          : ''
                      }
                      ${
                        canRetire
                          ? `<button class="small-button danger" data-release-retire="${escapeHtml(release.id)}">Вывести</button>`
                          : ''
                      }
                    </div>`
                  : readonlyActionsHtml('updates.manage')
              }
            </td>
          </tr>
        `;
      })
      .join('') || '<tr><td colspan="8">Версий пока нет.</td></tr>';
}

function findRelease(releaseId) {
  return (state.loaded.releases || []).find((item) => Number(item.id) === Number(releaseId));
}

function fillReleaseForm(release) {
  if (!release) return;
  $('releaseVersionInput').value = release.version || '';
  $('releaseBuildInput').value = release.buildNumber || '';
  $('releaseChannelInput').value = release.channel || 'internal';
  $('releaseStatusInput').value = release.status || 'draft';
  $('releaseDownloadUrlInput').value = release.downloadUrl || '';
  $('releaseSha256Input').value = release.sha256 || '';
  $('releaseRolloutInput').value = release.rolloutPercent ?? 100;
  $('releaseMinVersionInput').value = release.minSupportedVersion || '';
  $('releaseRequiredInput').checked = Boolean(release.isRequired);
  $('releaseChangelogInput').value = (release.changelog || []).join('\n');
  $('releaseForm').dataset.releaseId = release.id;
}

function resetReleaseForm() {
  $('releaseForm').reset();
  $('releaseForm').dataset.releaseId = '';
  $('releaseChannelInput').value = 'internal';
  $('releaseStatusInput').value = 'draft';
  $('releaseRolloutInput').value = 100;
}

function releaseFormPayload(statusOverride = null) {
  const changelog = $('releaseChangelogInput')
    .value
    .split('\n')
    .map((item) => item.trim())
    .filter(Boolean);
  return {
    platform: 'windows',
    channel: $('releaseChannelInput').value || 'internal',
    version: $('releaseVersionInput').value.trim(),
    buildNumber: $('releaseBuildInput').value.trim(),
    downloadUrl: $('releaseDownloadUrlInput').value.trim(),
    sha256: $('releaseSha256Input').value.trim(),
    rolloutPercent: Number($('releaseRolloutInput').value || 100),
    minSupportedVersion: $('releaseMinVersionInput').value.trim(),
    isRequired: $('releaseRequiredInput').checked,
    changelog,
    status: statusOverride || $('releaseStatusInput').value || 'draft',
  };
}

async function saveRelease(statusOverride = null) {
  if (!requirePermission('updates.manage', 'Сохранение версии')) return;
  try {
    const form = $('releaseForm');
    const releaseId = form.dataset.releaseId;
    const payload = releaseFormPayload(statusOverride);
    const path = releaseId
      ? `/api/v1/admin/updates/releases/${encodeURIComponent(releaseId)}`
      : '/api/v1/admin/updates/releases';
    await apiPost(path, payload);
    resetReleaseForm();
    await loadDashboardData();
    setNotice('Версия сохранена.');
  } catch (error) {
    setNotice(`Не удалось сохранить версию: ${error.message}`, true);
  }
}

async function updateReleaseStatus(releaseId, status) {
  if (!requirePermission('updates.manage', 'Изменение статуса версии')) return;
  const release = findRelease(releaseId);
  if (!release) {
    setNotice('Версия не найдена в текущем списке.', true);
    return;
  }
  fillReleaseForm(release);
  await saveRelease(status);
}

function featureFlagWorkflow() {
  return state.loaded.featureFlagWorkflow || {
    scopes: [
      'global',
      'client',
      'сервер API',
      'payments',
      'auth',
      'support',
      'updates',
      'monitoring',
      'vpn',
      'experimental',
    ],
    valueExamples: {
      boolean: true,
      object: { mode: 'manual_mvp' },
    },
  };
}

function runbookWorkflow() {
  return state.loaded.runbookWorkflow || {
    categories: [
      'vpn',
      'auth',
      'payments',
      'support',
      'updates',
      'monitoring',
      'servers',
      'security',
      'incident',
      'general',
    ],
    severities: ['low', 'normal', 'high', 'critical'],
    ownerRoles: ['owner', 'admin', 'support', 'ops'],
  };
}

function runbookSeverityPillClass(severity) {
  if (severity === 'critical') return 'red';
  if (severity === 'high') return 'yellow';
  if (severity === 'low') return 'muted';
  return '';
}

function controlValueToInput(value) {
  if (value === null || value === undefined) return 'false';
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value);
  } catch (_error) {
    return String(value);
  }
}

function parseControlValue(raw) {
  const value = String(raw || '').trim();
  if (!value) return false;
  try {
    return JSON.parse(value);
  } catch (_error) {
    return value;
  }
}

function findFeatureFlag(flagId) {
  return (state.loaded.featureFlags || []).find((item) => Number(item.id) === Number(flagId));
}

function findRunbook(runbookId) {
  return (state.loaded.runbooks || []).find((item) => Number(item.id) === Number(runbookId));
}

function renderFeatureFlagControls() {
  const workflow = featureFlagWorkflow();
  const scopeSelect = $('featureFlagScopeSelect');
  if (scopeSelect) {
    const selected = scopeSelect.value || 'global';
    scopeSelect.innerHTML = simpleOptionsHtml(workflow.scopes || [], selected || 'global');
    scopeSelect.value = selected && (workflow.scopes || []).includes(selected) ? selected : 'global';
  }
}

function resetFeatureFlagForm() {
  const form = $('featureFlagForm');
  if (!form) return;
  form.reset();
  $('featureFlagIdInput').value = '';
  $('featureFlagScopeSelect').value = 'global';
  $('featureFlagRolloutInput').value = 0;
  $('featureFlagEnabledInput').checked = false;
  $('featureFlagValueInput').value = 'false';
}

function fillFeatureFlagForm(flag) {
  if (!flag) return;
  $('featureFlagIdInput').value = flag.id || '';
  $('featureFlagKeyInput').value = flag.key || '';
  $('featureFlagTitleInput').value = flag.title || '';
  $('featureFlagScopeSelect').value = flag.scope || 'global';
  $('featureFlagRolloutInput').value = flag.rolloutPercent ?? 0;
  $('featureFlagEnabledInput').checked = Boolean(flag.isEnabled);
  $('featureFlagValueInput').value = controlValueToInput(flag.value);
  $('featureFlagDescriptionInput').value = flag.description || '';
  $('featureFlagNotesInput').value = flag.notes || '';
}

function featureFlagFormPayload(enabledOverride = null) {
  return {
    key: $('featureFlagKeyInput').value.trim(),
    title: $('featureFlagTitleInput').value.trim(),
    description: $('featureFlagDescriptionInput').value.trim(),
    value: parseControlValue($('featureFlagValueInput').value),
    scope: $('featureFlagScopeSelect').value || 'global',
    isEnabled: enabledOverride === null ? $('featureFlagEnabledInput').checked : enabledOverride,
    rolloutPercent: Number($('featureFlagRolloutInput').value || 0),
    notes: $('featureFlagNotesInput').value.trim(),
  };
}

async function saveFeatureFlag(enabledOverride = null) {
  if (!requirePermission('flags.manage', 'Сохранение переключателя функции')) return;
  try {
    const flagId = $('featureFlagIdInput').value;
    const path = flagId
      ? `/api/v1/admin/feature-flags/${encodeURIComponent(flagId)}`
      : '/api/v1/admin/feature-flags';
    await apiPost(path, featureFlagFormPayload(enabledOverride));
    resetFeatureFlagForm();
    await loadDashboardData();
    setNotice('Переключатель функции сохранён.');
  } catch (error) {
    setNotice(`Не удалось сохранить переключатель функции: ${error.message}`, true);
  }
}

async function updateFeatureFlagEnabled(flagId, isEnabled) {
  const flag = findFeatureFlag(flagId);
  if (!flag) {
    setNotice('Переключатель функции не найден в текущем списке.', true);
    return;
  }
  fillFeatureFlagForm(flag);
  await saveFeatureFlag(isEnabled);
}

function renderFeatureFlags() {
  renderFeatureFlagControls();
  const table = $('featureFlagsTable');
  if (!table) return;
  const rows = state.loaded.featureFlags || [];
  const canManageFlags = can('flags.manage');
  table.innerHTML =
    rows
      .map((flag) => `
        <tr>
          <td>
            <strong>${escapeHtml(flag.key)}</strong><br>
            <span class="muted">${escapeHtml(flag.title)}</span>
          </td>
          <td><span class="status-pill muted">${escapeHtml(flag.scope)}</span></td>
          <td>${boolPill(flag.isEnabled, 'включён', 'выключен')}</td>
          <td>${escapeHtml(flag.rolloutPercent ?? 0)}%</td>
          <td><pre class="inline-code">${escapeHtml(prettyJson(flag.value))}</pre></td>
          <td>${escapeHtml(shortDate(flag.updatedAt))}</td>
          <td>
            ${
              canManageFlags
                ? `<div class="row-actions">
                    <button class="small-button" data-feature-flag-edit="${escapeHtml(flag.id)}">В форму</button>
                    ${
                      flag.isEnabled
                        ? `<button class="small-button danger" data-feature-flag-disable="${escapeHtml(flag.id)}">Выключить</button>`
                        : `<button class="small-button" data-feature-flag-enable="${escapeHtml(flag.id)}">Включить</button>`
                    }
                  </div>`
                : readonlyActionsHtml('flags.manage')
            }
          </td>
        </tr>
      `)
      .join('') || '<tr><td colspan="7">Переключатели функций ещё не загружены. Сервер создаст базовый набор на старте.</td></tr>';
}

function renderRunbookControls() {
  const workflow = runbookWorkflow();
  const categorySelect = $('runbookCategorySelect');
  const severitySelect = $('runbookSeveritySelect');
  if (categorySelect) {
    const selected = categorySelect.value || 'general';
    categorySelect.innerHTML = simpleOptionsHtml(workflow.categories || [], selected || 'general');
    categorySelect.value = selected && (workflow.categories || []).includes(selected) ? selected : 'general';
  }
  if (severitySelect) {
    const selected = severitySelect.value || 'normal';
    severitySelect.innerHTML = simpleOptionsHtml(workflow.severities || [], selected || 'normal');
    severitySelect.value = selected && (workflow.severities || []).includes(selected) ? selected : 'normal';
  }
}

function resetRunbookForm() {
  const form = $('runbookForm');
  if (!form) return;
  form.reset();
  $('runbookIdInput').value = '';
  $('runbookCategorySelect').value = 'general';
  $('runbookSeveritySelect').value = 'normal';
  $('runbookActiveInput').checked = true;
}

function fillRunbookForm(runbook) {
  if (!runbook) return;
  $('runbookIdInput').value = runbook.id || '';
  $('runbookKeyInput').value = runbook.key || '';
  $('runbookTitleInput').value = runbook.title || '';
  $('runbookCategorySelect').value = runbook.category || 'general';
  $('runbookSeveritySelect').value = runbook.severity || 'normal';
  $('runbookOwnerRoleInput').value = runbook.ownerRole || '';
  $('runbookActiveInput').checked = Boolean(runbook.isActive);
  $('runbookSummaryInput').value = runbook.summary || '';
  $('runbookStepsInput').value = (runbook.steps || []).join('\n');
}

function runbookFormPayload(activeOverride = null) {
  const steps = $('runbookStepsInput')
    .value
    .split('\n')
    .map((step) => step.trim())
    .filter(Boolean);
  return {
    key: $('runbookKeyInput').value.trim(),
    title: $('runbookTitleInput').value.trim(),
    category: $('runbookCategorySelect').value || 'general',
    severity: $('runbookSeveritySelect').value || 'normal',
    summary: $('runbookSummaryInput').value.trim(),
    steps,
    ownerRole: $('runbookOwnerRoleInput').value.trim(),
    isActive: activeOverride === null ? $('runbookActiveInput').checked : activeOverride,
  };
}

async function saveRunbook(activeOverride = null) {
  if (!requirePermission('runbooks.manage', 'Сохранение инструкции')) return;
  try {
    const runbookId = $('runbookIdInput').value;
    const path = runbookId
      ? `/api/v1/admin/runbooks/${encodeURIComponent(runbookId)}`
      : '/api/v1/admin/runbooks';
    await apiPost(path, runbookFormPayload(activeOverride));
    resetRunbookForm();
    await loadDashboardData();
    setNotice('Инструкция сохранена.');
  } catch (error) {
    setNotice(`Не удалось сохранить инструкцию: ${error.message}`, true);
  }
}

async function updateRunbookActive(runbookId, isActive) {
  const runbook = findRunbook(runbookId);
  if (!runbook) {
    setNotice('Инструкция не найдена в текущем списке.', true);
    return;
  }
  fillRunbookForm(runbook);
  await saveRunbook(isActive);
}

function renderRunbooks() {
  renderRunbookControls();
  const table = $('runbooksTable');
  if (!table) return;
  const rows = state.loaded.runbooks || [];
  const canManageRunbooks = can('runbooks.manage');
  table.innerHTML =
    rows
      .map((runbook) => `
        <tr>
          <td>
            <strong>${escapeHtml(runbook.key)}</strong><br>
            <span class="muted">${escapeUi(runbook.title)}</span>
          </td>
          <td><span class="status-pill muted">${escapeUi(runbook.category)}</span></td>
          <td><span class="status-pill ${runbookSeverityPillClass(runbook.severity)}">${escapeUi(runbook.severity)}</span></td>
          <td>${escapeHtml(runbook.ownerRole || '—')}</td>
          <td>
            <strong>${escapeHtml((runbook.steps || []).length)} шагов</strong><br>
            <span class="muted">${escapeUi(runbook.summary || 'Без краткого описания')}</span>
          </td>
          <td>${escapeHtml(shortDate(runbook.updatedAt))}</td>
          <td>
            ${
              canManageRunbooks
                ? `<div class="row-actions">
                    <button class="small-button" data-runbook-edit="${escapeHtml(runbook.id)}">В форму</button>
                    ${
                      runbook.isActive
                        ? `<button class="small-button danger" data-runbook-archive="${escapeHtml(runbook.id)}">Архив</button>`
                        : `<button class="small-button" data-runbook-activate="${escapeHtml(runbook.id)}">Активировать</button>`
                    }
                  </div>`
                : readonlyActionsHtml('runbooks.manage')
            }
          </td>
        </tr>
      `)
      .join('') || '<tr><td colspan="7">Инструкции ещё не загружены. Сервер создаст базовый набор на старте.</td></tr>';
}

function serverWorkflow() {
  return state.loaded.serverWorkflow || {
    statuses: ['draft', 'healthy', 'degraded', 'maintenance', 'disabled'],
    protocols: [
      'wireguard_udp',
      'wireguard_tcp',
      'amneziawg',
      'openvpn_tcp',
      'shadowsocks',
      'hysteria2',
      'trojan_tls',
      'vless_reality',
      'masque_udp',
    ],
    transports: ['udp', 'tcp', 'tls', 'quic', 'http3', 'reality', 'masque'],
    clientConfigProfiles: [
      { code: 'none', title: 'Не выдавать клиентам' },
      { code: 'builtin_wg0', title: 'Текущий сервер API wg0' },
      { code: 'remote_ssh_wg0', title: 'Удалённый WireGuard wg0' },
    ],
    publicMode: 'admin_preparation',
  };
}

function serverStatusTitle(status) {
  return {
    draft: 'Черновик',
    healthy: 'Здоров',
    degraded: 'Деградация',
    maintenance: 'Обслуживание',
    disabled: 'Отключён',
  }[status] || status || '—';
}

function serverStatusPillClass(status) {
  if (status === 'healthy') return '';
  if (status === 'degraded' || status === 'maintenance') return 'yellow';
  if (status === 'disabled') return 'red';
  return 'muted';
}

function serverHealthStatusTitle(status) {
  return {
    healthy: 'Здоров',
    degraded: 'Деградация',
    down: 'Упал',
    unknown: 'Неизвестно',
  }[status] || status || '—';
}

function serverHealthStatusPillClass(status) {
  if (status === 'healthy') return '';
  if (status === 'degraded') return 'yellow';
  if (status === 'down') return 'red';
  return 'muted';
}

function serverProtocolTitle(protocol) {
  return {
    wireguard_udp: 'WireGuard UDP',
    wireguard_tcp: 'WireGuard поверх TCP',
    amneziawg: 'AmneziaWG',
    openvpn_tcp: 'OpenVPN TCP/443',
    shadowsocks: 'Shadowsocks AEAD',
    hysteria2: 'Hysteria2 QUIC',
    trojan_tls: 'Trojan TLS',
    vless_reality: 'VLESS REALITY',
    masque_udp: 'MASQUE CONNECT-UDP',
  }[protocol] || protocol || '—';
}

function serverTransportTitle(transport) {
  return {
    udp: 'UDP',
    tcp: 'TCP',
    tls: 'TLS',
    quic: 'QUIC',
    http3: 'HTTP/3',
    reality: 'REALITY',
    masque: 'MASQUE',
  }[transport] || transport || '—';
}

function serverClientConfigProfileTitle(profile) {
  return {
    none: 'Не выдавать клиентам',
    builtin_wg0: 'Текущий сервер API wg0',
    remote_ssh_wg0: 'Удалённый WireGuard wg0',
  }[profile] || profile || '—';
}

function serverFilterParams() {
  return {
    status: $('serverStatusFilter')?.value || 'all',
    active: $('serverActiveFilter')?.value || 'all',
    public: $('serverPublicFilter')?.value || 'all',
    limit: 100,
  };
}

function serverHealthFilterParams() {
  return {
    endpointId: $('serverHealthEndpointFilter')?.value?.trim() || '',
    status: $('serverHealthStatusFilter')?.value || 'all',
    limit: 120,
  };
}

function renderServerFilters() {
  const workflow = serverWorkflow();
  const statusSelect = $('serverStatusFilter');
  const statusInput = $('serverStatusInput');
  const protocolInput = $('serverProtocolInput');
  const transportInput = $('serverTransportInput');
  const clientConfigProfileInput = $('serverClientConfigProfileInput');

  const statusItems = (workflow.statuses || []).map((status) => ({
    code: status,
    title: serverStatusTitle(status),
  }));
  const protocolItems = (workflow.protocols || []).map((protocol) => ({
    code: protocol,
    title: serverProtocolTitle(protocol),
  }));
  const transportItems = (workflow.transports || []).map((transport) => ({
    code: transport,
    title: serverTransportTitle(transport),
  }));
  const clientConfigProfileItems = (workflow.clientConfigProfiles || []).map((profile) => (
    typeof profile === 'string'
      ? { code: profile, title: serverClientConfigProfileTitle(profile) }
      : {
          code: profile.code || profile.id || 'none',
          title: profile.title || serverClientConfigProfileTitle(profile.code || profile.id),
        }
  ));

  if (statusSelect) {
    const current = statusSelect.value || 'all';
    statusSelect.innerHTML = workflowOptionsHtml(statusItems, current, 'Все статусы');
  }
  if (statusInput) {
    const current = statusInput.value || 'draft';
    statusInput.innerHTML = workflowOptionsHtml(statusItems, current);
    if (!statusInput.value) statusInput.value = 'draft';
  }
  if (protocolInput) {
    const current = protocolInput.value || 'wireguard_udp';
    protocolInput.innerHTML = workflowOptionsHtml(protocolItems, current);
    if (!protocolInput.value) protocolInput.value = 'wireguard_udp';
  }
  if (transportInput) {
    const current = transportInput.value || 'udp';
    transportInput.innerHTML = workflowOptionsHtml(transportItems, current);
    if (!transportInput.value) transportInput.value = 'udp';
  }
  if (clientConfigProfileInput) {
    const current = clientConfigProfileInput.value || 'none';
    clientConfigProfileInput.innerHTML = workflowOptionsHtml(clientConfigProfileItems, current);
    if (!clientConfigProfileInput.value) clientConfigProfileInput.value = 'none';
  }
}

function serverPublicEligibility(server) {
  return server.publicEligibility || {
    eligible: Boolean(server.publicEligible),
    blockers: server.publicBlockers || [],
    healthyObservations24h: server.healthyObservations24h || 0,
    failedObservations24h: server.failedObservations24h || 0,
    latestObservationAt: server.latestObservationAt || null,
    latestObservationStatus: server.latestObservationStatus || null,
  };
}

function renderServerEligibility(server) {
  const eligibility = serverPublicEligibility(server);
  const blockers = eligibility.blockers || [];
  const visibleBlockers = blockers.slice(0, 3);
  const blockerHtml = visibleBlockers.length
    ? visibleBlockers
        .map((blocker) => `
          <span class="muted">${escapeHtml(blocker.code)}: ${escapeUi(blocker.message)}</span>
        `)
        .join('<br>')
    : '<span class="muted">Готов к публикации после следующей релизной проверки.</span>';
  const more = blockers.length > visibleBlockers.length
    ? `<br><span class="muted">ещё ${blockers.length - visibleBlockers.length}</span>`
    : '';

  return `
    <span class="status-pill ${eligibility.eligible ? '' : 'yellow'}">
      ${eligibility.eligible ? 'можно' : 'нельзя'}
    </span><br>
    ${blockerHtml}${more}<br>
    <span class="muted">
      здоровых проверок за 24ч: ${escapeHtml(eligibility.healthyObservations24h || 0)} /
      сбоев за 24ч: ${escapeHtml(eligibility.failedObservations24h || 0)}
    </span>
  `;
}

function renderServerCatalogSummary() {
  const catalog = state.loaded.serverCatalog;
  const summary = state.loaded.serverCatalogSummary;
  const publication = state.loaded.serverPublicationReadiness;
  const provisioning = state.loaded.serverProvisioningReadiness;
  const workflow = serverWorkflow();
  const routePayload = state.loaded.resilienceRoutes || {};
  const transportRollout = state.loaded.resilienceTransportRollout?.rollout || {};
  const resilience = routePayload.resilience || catalog?.resilience || {};
  const routeDecision = routePayload.routeDecision || resilience.routeDecision || {};
  const selectedRoute = routeDecision.selected || {};
  const routeChain = routeDecision.fallbackChain || [];
  const targetRouteMatrix = routePayload.targetRouteMatrix || {};
  const container = $('serverCatalogSummary');
  if (!container) return;
  if (!catalog) {
    container.innerHTML = '<p class="muted">Каталог серверов пока не загружен.</p>';
    return;
  }

  const managed = catalog.managedCatalog || {};
  const servers = catalog.servers || [];
  const items = [
    {
      title: `Публичный каталог v${catalog.version || '—'}`,
      message: `${servers.length} клиентских VPN-узлов, по умолчанию=${catalog.defaultServerId || '—'}`,
      ok: true,
      warning: false,
      pill: 'client-safe',
    },
    {
      title: 'Управляемые VPN-узлы',
      message: summary
        ? `${summary.managedTotal || 0} всего, ${summary.managedClientConfigReady || 0} с готовым конфигом, ${summary.managedPublicEligible || 0} можно публиковать`
        : 'Сводка пока не загружена.',
      ok: !summary || Number(summary.managedPublicEligible || 0) === 0,
      warning: Boolean(summary && Number(summary.managedPublicCandidates || 0) > 0),
      pill: summary?.mode || 'safe-gate',
    },
    {
      title: 'Управляемый каталог',
      message: managed.message || workflow.publicSafety || 'Готовим внутренний список серверов.',
      ok: true,
      warning: true,
      pill: managed.mode || workflow.publicMode || 'preparation',
    },
    {
      title: 'Проверка перед публикацией',
      message: publication
        ? publication.clientImpact || `${publication.blockedManagedEntries?.length || 0} VPN-узлов заблокировано`
        : 'Проверка готовности пока не загружена.',
      ok: Boolean(publication?.publicCatalogUnchanged),
      warning: !publication?.canPublishManagedEndpoints,
      pill: publication?.canPublishManagedEndpoints ? 'проверить' : 'безопасный блок',
    },
    {
      title: 'Проверка выдачи конфигов',
      message: provisioning
        ? provisioning.summary?.message || `принятые серверы=${(provisioning.clientConfigContract?.acceptedServerIds || []).join(', ')}`
        : 'Проверка выдачи конфигов пока не загружена.',
      ok: Boolean(provisioning?.safeForCurrentClient),
      warning: !provisioning?.currentEndpointConfigReady || !provisioning?.multiEndpointProvisioningReady,
      pill: provisioning?.multiEndpointProvisioningReady ? 'несколько узлов' : 'только публичный',
    },
    {
      title: 'Стартовая конфигурация',
      message: (catalog.bootstrap?.apiBaseUrls || []).join(', ') || 'Нет стартовых URL API',
      ok: Boolean(catalog.bootstrap?.apiBaseUrls?.length),
      warning: !catalog.bootstrap?.apiBaseUrls?.length,
      pill: 'api',
    },
  ];
  if (selectedRoute.protocol) {
    const selectedLayer = routeChain.find((item) => item.code === selectedRoute.protocol) || {};
    const routeReady = Boolean(selectedLayer.autoEligible);
    const selectedClientFeedback = selectedLayer.clientFeedback || {};
    const chainPreview = routeChain
      .slice(0, 5)
      .map((item) => {
        const status = item.autoEligible
          ? 'готов'
          : (item.clientReady && item.publicEndpointReady ? `оценка ${item.score || 0}` : 'ждёт подготовки');
        return `${serverProtocolTitle(item.code)}: ${status}`;
      })
      .join(' | ');
    items.splice(1, 0, {
      title: 'Автовыбор маршрута',
      message: `${serverProtocolTitle(selectedRoute.protocol)}; оценка ${selectedRoute.score || 0}/100; источник=${selectedRoute.signalSource || '—'}. Клиентских сигналов: ${selectedClientFeedback.observed || 0}, успешных: ${selectedClientFeedback.ok || 0}, сбоев: ${selectedClientFeedback.failed || 0}. ${selectedRoute.reason || ''}`,
      ok: routeReady || selectedRoute.protocol === 'wireguard_udp',
      warning: !routeReady,
      pill: routeDecision.selectionPolicy || 'авто',
    });
    items.splice(2, 0, {
      title: 'Цепочка обхода',
      message: chainPreview || 'Слои маршрутизации пока не загружены.',
      ok: Boolean(routeChain.length),
      warning: routeChain.some((item) => !item.clientReady || !item.publicEndpointReady),
      pill: `${routeChain.length || 0} слоёв`,
    });
    if (targetRouteMatrix.rows?.length) {
      const missing = Number(targetRouteMatrix.targetsMissingSignal || 0);
      const covered = Number(targetRouteMatrix.targetsCovered || 0);
      const total = Number(targetRouteMatrix.targetsTotal || targetRouteMatrix.rows.length || 0);
      const preview = targetRouteMatrix.rows
        .slice(0, 4)
        .map((row) => `${row.title || row.targetId}: ${serverProtocolTitle(row.selectedProtocol)} / ${row.selectedStatus || 'нет сигнала'}`)
        .join(' | ');
      items.splice(3, 0, {
        title: 'Проверка сервисов по маршрутам',
        message: `${covered}/${total} обязательных сервисов имеют живой маршрут. ${preview}`,
        ok: missing === 0,
        warning: missing > 0,
        pill: targetRouteMatrix.mode || 'target-aware',
      });
    }
  }
  if (transportRollout.profiles?.length) {
    const summaryText = transportRollout.summary?.message || 'План выдачи транспортов загружен.';
    const readyCount = Number(transportRollout.summary?.ready || 0);
    const totalCount = Number(transportRollout.summary?.total || transportRollout.profiles.length || 0);
    const next = transportRollout.nextCandidate || {};
    const firstBlocker = (next.blockers || [])[0] || {};
    const nextDetail = firstBlocker.detail || next.nextAction || 'нужна подготовка';
    const nextDetailSuffix = /[.!?]$/.test(nextDetail.trim()) ? '' : '.';
    const canaryCommand = next.canaryScript ? ` Подготовка canary: ${next.canaryScript}.` : '';
    const validationCommand = next.validationScript ? ` Проверка canary: ${next.validationScript}.` : '';
    items.splice(3, 0, {
      title: 'Готовность протоколов',
      message: `${summaryText} Сейчас готовы: ${readyCount}/${totalCount}.`,
      ok: true,
      warning: true,
      pill: transportRollout.mode || 'guarded',
    });
    items.splice(4, 0, {
      title: 'Следующий слой обхода',
      message: next.code
        ? `${serverProtocolTitle(next.code)}: ${nextDetail}${nextDetailSuffix}${canaryCommand}${validationCommand}`
        : 'Все заведённые слои прошли rollout gate.',
      ok: !next.code,
      warning: Boolean(next.code),
      pill: next.risk || 'план',
    });
  }
  const blockerSummary = summary?.blockersByCode
    ? Object.entries(summary.blockersByCode)
        .sort((a, b) => Number(b[1]) - Number(a[1]))
        .slice(0, 5)
        .map(([code, count]) => `${code}: ${count}`)
        .join(', ')
    : '';
  if (blockerSummary) {
    items.push({
      title: 'Почему не опубликовано',
      message: blockerSummary,
      ok: true,
      warning: true,
      pill: 'blockers',
    });
  }
  if (publication?.nextActions?.length) {
    const firstAction = publication.nextActions[0];
    items.push({
      title: 'Следующий шаг по серверам',
      message: `${firstAction.title || firstAction.code}: ${firstAction.detail || ''}`,
      ok: true,
      warning: true,
      pill: firstAction.owner || 'владелец',
    });
  }
  if (provisioning?.newServerOnboardingPlan) {
    const plan = provisioning.newServerOnboardingPlan;
    const firstExample = (plan.recommendedExamples || [])[0] || {};
    const phaseSummary = (plan.phases || [])
      .slice(0, 4)
      .map((phase) => `${phase.title || phase.code}: ${phase.status || 'planned'}`)
      .join(' | ');
    const ownerInputSummary = (plan.ownerInputs || [])
      .filter((item) => !item.secret)
      .slice(0, 4)
      .map((item) => item.name)
      .join(', ');
    items.push({
      title: 'Новый VPS',
      message: firstExample.hostname
        ? `Черновик: ${firstExample.serverId} -> ${firstExample.hostname}; создание через ${plan.draftCreationEndpoint || 'безопасную ручку черновика'}`
        : plan.clientImpact || 'Новый сервер готовим только как внутренний черновик.',
      ok: Boolean(plan.safeToCreateInternalDraft),
      warning: !plan.productionReady,
      pill: plan.mode || 'internal-only',
    });
    items.push({
      title: 'План подключения VPS',
      message: phaseSummary || 'План ещё не загружен.',
      ok: Boolean(plan.safeToCreateInternalDraft),
      warning: true,
      pill: `${(plan.phases || []).length} фаз`,
    });
    if (ownerInputSummary) {
      items.push({
        title: 'Что нужно от владельца',
        message: ownerInputSummary,
        ok: true,
        warning: true,
      pill: 'без секретов',
      });
    }
  }
  if (provisioning?.selectionCases?.length) {
    const blocked = provisioning.selectionCases
      .filter((item) => !item.allowed)
      .map((item) => `${item.requestServerId}: ${item.reason}`)
      .join(', ');
    items.push({
      title: 'Правила выбора серверов',
      message: blocked || 'Все сценарии выбора разрешены.',
      ok: Boolean(provisioning.safeForCurrentClient),
      warning: Boolean(blocked),
      pill: provisioning.clientConfigContract?.selectionPolicy || 'выбор',
    });
  }
  container.innerHTML = items
    .map(
      (item) => `
        <div class="check-row">
          ${statusDot(item.ok, item.warning)}
          <div>
            <strong>${escapeUi(item.title)}</strong>
            <span>${escapeUi(item.message)}</span>
          </div>
          <span class="status-pill ${item.warning ? 'yellow' : ''}">${escapeUi(item.pill)}</span>
        </div>
      `,
    )
    .join('');
}

function parseTimeMs(value) {
  if (!value) return 0;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function serverPublicCatalogIds() {
  const catalogServers = state.loaded.serverCatalog?.servers || [];
  const ids = new Set();
  catalogServers.forEach((server) => {
    serverIdentityValues(server).forEach((value) => {
      if (value !== null && value !== undefined && value !== '') ids.add(String(value));
    });
  });
  return ids;
}

function latestServerHealthByEndpoint() {
  const output = new Map();
  const summaryLatest = state.loaded.serverHealth?.summary?.latestByEndpoint || [];
  const observations = state.loaded.serverHealth?.observations || [];
  [...summaryLatest, ...observations].forEach((item) => {
    const endpointId = item.endpointId || item.serverId || item.server_id;
    if (!endpointId) return;
    const key = String(endpointId);
    const timestamp = parseTimeMs(item.observedAt || item.createdAt || item.created_at);
    const current = output.get(key);
    const currentTimestamp = parseTimeMs(current?.observedAt || current?.createdAt || current?.created_at);
    if (!current || timestamp >= currentTimestamp) output.set(key, item);
  });
  return output;
}

function latestClientRouteByEndpoint() {
  const output = new Map();
  const events = state.loaded.clientRouteEvents?.events || [];
  events.forEach((event) => {
    const endpointId = event.serverId || event.server_id;
    if (!endpointId) return;
    const key = String(endpointId);
    const timestamp = parseTimeMs(event.createdAt || event.created_at);
    const current = output.get(key);
    const currentTimestamp = parseTimeMs(current?.createdAt || current?.created_at);
    if (!current || timestamp >= currentTimestamp) output.set(key, event);
  });
  return output;
}

function serverSignalFor(server, map) {
  const identities = serverIdentityValues(server).map((value) => String(value));
  for (const identity of identities) {
    if (map.has(identity)) return map.get(identity);
  }
  return null;
}

function serverCatalogChannel(server, publicCatalogIds) {
  const identities = serverIdentityValues(server).map((value) => String(value));
  const isInClientCatalog = identities.some((value) => publicCatalogIds.has(value));
  if (isInClientCatalog) {
    return {
      title: 'Client catalog',
      hint: 'Visible to apps now',
      pillClass: '',
    };
  }
  if (server.isPublic) {
    return {
      title: 'Candidate',
      hint: 'Prepared for publication gate',
      pillClass: 'yellow',
    };
  }
  return {
    title: 'Internal',
    hint: 'Hidden from client catalog',
    pillClass: 'muted',
  };
}

function serverOperationsStatus(server, latestHealth, latestRoute) {
  const blockers = [];
  if (!server.isActive) blockers.push('disabled in admin');
  if (server.status && server.status !== 'healthy') blockers.push(`status=${server.status}`);
  if (!server.clientConfigReady) blockers.push('client config not ready');
  if (latestHealth?.status && latestHealth.status !== 'healthy') {
    blockers.push(`health=${latestHealth.status}`);
  }
  if (latestRoute && latestRoute.ok === false) {
    blockers.push(`client=${latestRoute.stage || 'route event failed'}`);
  }
  const publicBlockers = server.publicBlockers || server.publicEligibility?.blockers || [];
  publicBlockers.slice(0, 2).forEach((blocker) => {
    blockers.push(blocker.message || blocker.code || 'publication blocker');
  });

  const hardBlock = !server.isActive || !server.clientConfigReady || latestHealth?.status === 'down';
  if (!blockers.length) {
    return {
      title: 'Ready',
      pillClass: '',
      blockers,
    };
  }
  return {
    title: hardBlock ? 'Blocked' : 'Attention',
    pillClass: hardBlock ? 'red' : 'yellow',
    blockers,
  };
}

function renderSignalValue(label, value, hint = '') {
  return `
    <div class="node-signal">
      <span>${escapeUi(label)}</span>
      <strong>${escapeHtml(value)}</strong>
      ${hint ? `<small>${escapeUi(hint)}</small>` : ''}
    </div>
  `;
}

function renderServerOperationsOverview() {
  const summaryContainer = $('serverOperationsSummary');
  const overviewContainer = $('serverOperationsOverview');
  if (!summaryContainer || !overviewContainer) return;

  const servers = state.loaded.servers || [];
  const healthSummary = state.loaded.serverHealth?.summary || {};
  const clientSummary = state.loaded.clientRouteEvents?.summary || {};
  const serviceSummary = state.loaded.serviceObservations?.summary || {};
  const publicCatalogIds = serverPublicCatalogIds();
  const latestHealth = latestServerHealthByEndpoint();
  const latestRoutes = latestClientRouteByEndpoint();
  const cards = servers.map((server) => {
    const health = serverSignalFor(server, latestHealth);
    const route = serverSignalFor(server, latestRoutes);
    const channel = serverCatalogChannel(server, publicCatalogIds);
    const status = serverOperationsStatus(server, health, route);
    return { server, health, route, channel, status };
  });
  const clientVisible = cards.filter((item) => item.channel.title === 'Client catalog').length;
  const ready = cards.filter((item) => item.status.title === 'Ready').length;
  const attention = cards.length - ready;
  const probeCoverage = healthSummary.externalProbeReadiness || {};

  summaryContainer.innerHTML = [
    ['Managed nodes', cards.length, `${clientVisible} in client catalog`],
    ['Ready nodes', ready, 'Active, config-ready, no latest red signals'],
    ['Needs attention', attention, `${healthSummary.problemEndpoints || 0} server-health problems`],
    ['Client route failures', clientSummary.failed || 0, 'Recent Windows/Android route-events'],
    [
      'External probe coverage',
      `${(probeCoverage.coveredEndpointIds || []).length}/${(probeCoverage.requiredEndpointIds || []).length}`,
      `${probeCoverage.activeExternalProbeAgents || 0} active probe agents`,
    ],
    ['Service observations', serviceSummary.totalObservations || 0, `${serviceSummary.problemTargets || 0} problem targets`],
  ]
    .map(([label, value, hint]) => `
      <div class="metric-card">
        <span>${escapeUi(label)}</span>
        <strong>${escapeHtml(value)}</strong>
        <p>${escapeUi(hint)}</p>
      </div>
    `)
    .join('');

  overviewContainer.innerHTML = cards
    .map(({ server, health, route, channel, status }) => {
      const endpoint = `${server.host || 'host'}:${server.port || 'port'}`;
      const latency = server.latencyMs === null || server.latencyMs === undefined
        ? 'latency unknown'
        : `${server.latencyMs} ms`;
      const healthStatus = health?.status || server.latestObservationStatus || 'unknown';
      const healthTime = health?.observedAt || health?.createdAt || server.latestObservationAt;
      const routeStage = route?.stage ? clientRouteStageTitle(route.stage) : 'no client event';
      const routeResult = !route ? 'unknown' : route.ok ? 'OK' : 'failed';
      const routeClass = !route ? 'muted' : route.ok ? '' : 'red';
      const configTitle = server.clientConfigReady ? 'ready' : 'not ready';
      const configClass = server.clientConfigReady ? '' : 'red';
      const capacity = server.capacity || {};
      const activeClients = safeNumber(capacity.activeClients ?? server.activeClients, 0);
      const assignedUsers = safeNumber(capacity.assignedUsers ?? server.assignedUsers, 0);
      const loadMbps = safeNumber(capacity.currentLoadMbps ?? server.currentLoadMbps, 0);
      const usableMbps = safeNumber(capacity.usableBandwidthMbps ?? server.usableBandwidthMbps, 0);
      const capacityHint = usableMbps > 0
        ? `${loadMbps}/${usableMbps} Mbps`
        : `users=${assignedUsers}`;
      const blockersHtml = status.blockers.length
        ? `<div class="node-blockers">
            ${status.blockers.slice(0, 5).map((item) => `<span>${escapeUi(item)}</span>`).join('')}
          </div>`
        : '<div class="node-blockers ok"><span>No blockers from loaded signals.</span></div>';
      return `
        <article class="node-card ${status.pillClass}">
          <div class="node-card-head">
            <div>
              <strong>${escapeHtml(server.title || server.serverId || server.id)}</strong>
              <span>${escapeHtml([server.country, server.city, server.provider].filter(Boolean).join(' / ') || 'location unknown')}</span>
            </div>
            <span class="status-pill ${status.pillClass}">${escapeUi(status.title)}</span>
          </div>
          <div class="node-card-meta">
            <code>${escapeHtml(server.serverId || server.id)}</code>
            <span>${escapeHtml(endpoint)}</span>
            <span>${escapeHtml(serverProtocolTitle(server.protocol))}</span>
          </div>
          <div class="node-signal-grid">
            ${renderSignalValue('Catalog', channel.title, channel.hint)}
            ${renderSignalValue('Config', configTitle, server.clientConfigProfileTitle || serverClientConfigProfileTitle(server.clientConfigProfile))}
            ${renderSignalValue('Health', serverHealthStatusTitle(healthStatus), healthTime ? shortDate(healthTime) : 'no probe yet')}
            ${renderSignalValue('Client route', routeResult, routeStage)}
            ${renderSignalValue('Score', `${server.healthScore ?? 0}%`, latency)}
            ${renderSignalValue('Capacity', `${activeClients} active`, `${capacityHint}; selection=${server.selectionScore ?? 0}`)}
          </div>
          <div class="node-pill-row">
            <span class="status-pill ${channel.pillClass}">${escapeUi(channel.title)}</span>
            <span class="status-pill ${configClass}">${escapeUi(`config ${configTitle}`)}</span>
            <span class="status-pill ${serverHealthStatusPillClass(healthStatus)}">${escapeHtml(serverHealthStatusTitle(healthStatus))}</span>
            <span class="status-pill ${routeClass}">${escapeUi(`client ${routeResult}`)}</span>
          </div>
          ${blockersHtml}
        </article>
      `;
    })
    .join('') || '<p class="muted">No managed VPN nodes loaded yet.</p>';
}

function renderServersTable() {
  const rows = state.loaded.servers || [];
  const table = $('serversTable');
  if (!table) return;
  const canManageServers = can('servers.manage');
  table.innerHTML =
    rows
      .map((server) => {
        const canManageThisServer = canManageServers && !server.publicCatalogOnly;
        return `
        <tr>
          <td>
            #${escapeHtml(server.id)}<br>
            <span class="muted">${escapeHtml(server.serverId)}</span>
          </td>
          <td>
            <strong>${escapeHtml(server.title)}</strong><br>
            <span class="muted">${escapeHtml([server.country, server.city].filter(Boolean).join(', '))}</span>
          </td>
          <td>
            <strong>${escapeHtml(server.host)}:${escapeHtml(server.port)}</strong><br>
            <span class="muted">${escapeUi(server.provider)}</span>
          </td>
          <td>
            ${escapeHtml(serverProtocolTitle(server.protocol))}<br>
            <span class="muted">${escapeHtml(serverTransportTitle(server.transport))}</span><br>
            <span class="muted">конфиг: ${escapeHtml(server.clientConfigProfileTitle || serverClientConfigProfileTitle(server.clientConfigProfile))}</span>
          </td>
          <td><span class="status-pill ${serverStatusPillClass(server.status)}">${escapeHtml(serverStatusTitle(server.status))}</span></td>
          <td>
            <strong>${escapeHtml(server.healthScore, '0')}%</strong><br>
            <span class="muted">${server.latencyMs === null || server.latencyMs === undefined ? 'задержка —' : `${escapeHtml(server.latencyMs)} мс`}</span>
          </td>
          <td>${renderServerCapacity(server)}</td>
          <td>
            ${boolPill(server.isActive, 'активен', 'выключен')}
            ${boolPill(server.isPublic, 'кандидат', 'внутренний')}
            ${boolPill(server.clientConfigReady, 'конфиг готов', 'конфиг не готов')}
            ${
              server.publicationPausedAt
                ? `<br><span class="status-pill yellow">автопауза</span><br>
                   <span class="muted">${escapeUi(server.publicationPausedReason || 'проверка здоровья')}</span>`
                : ''
            }
            <br>
            ${renderServerEligibility(server)}
          </td>
          <td>
            ${
              server.publicCatalogOnly
                ? '<span class="muted">из клиентского каталога</span>'
                : canManageThisServer
                ? `<div class="row-actions">
                    <button class="small-button" data-server-edit="${escapeHtml(server.id)}">В форму</button>
                    <button class="small-button" data-server-healthy="${escapeHtml(server.id)}">Здоров</button>
                    ${
                      server.clientConfigProfile === 'remote_ssh_wg0'
                        ? `<button
                            class="small-button"
                            data-server-remote-smoke="${escapeHtml(server.id)}"
                            ${state.remotePeerSmokeBusyServerIds.has(server.serverId) ? 'disabled' : ''}
                            title="Проверить, что сервер API может добавить и удалить временный WireGuard peer на этом удалённом узле"
                          >Проверка peer</button>`
                        : ''
                    }
                    ${
                      server.clientConfigProfile === 'remote_ssh_wg0'
                        ? `<button
                            class="small-button"
                            data-server-client-config-smoke="${escapeHtml(server.id)}"
                            ${state.clientConfigSmokeBusyServerIds.has(server.serverId) ? 'disabled' : ''}
                            title="Проверить, что сервер API собирает клиентский конфиг для этого удалённого узла и удаляет временный peer"
                          >Тест конфига</button>`
                        : ''
                    }
                    ${
                      server.serverId !== 'current_wg0'
                        ? server.isPublic
                          ? `<button
                              class="small-button danger"
                              data-server-unpublish="${escapeHtml(server.id)}"
                              ${state.publicationGateBusyServerIds.has(server.serverId) ? 'disabled' : ''}
                              title="Скрыть VPN-узел из клиентского каталога без удаления записи"
                            >Скрыть</button>`
                          : `<button
                              class="small-button"
                              data-server-publish="${escapeHtml(server.id)}"
                              ${state.publicationGateBusyServerIds.has(server.serverId) ? 'disabled' : ''}
                              title="Проверить допуск к публикации и открыть VPN-узел клиентам только если все проверки зелёные"
                            >Открыть клиентам</button>`
                        : ''
                    }
                    <button class="small-button danger" data-server-disable="${escapeHtml(server.id)}">Отключить</button>
                  </div>`
                : readonlyActionsHtml('servers.manage')
            }
          </td>
        </tr>
      `;
      })
      .join('') || '<tr><td colspan="9">Серверы не загрузились. Нажмите «Обновить»; если строка останется пустой, проверьте доступ к API и каталог серверов.</td></tr>';
}

function renderServerHealth() {
  const health = state.loaded.serverHealth;
  const summary = health?.summary || {};
  const external = summary.externalProbeReadiness || {};
  const summaryContainer = $('serverHealthSummary');
  const readinessContainer = $('serverHealthProbeReadiness');
  const table = $('serverHealthTable');
  if (!summaryContainer || !table) return;

  const cards = [
    ['VPN-узлов под наблюдением', summary.endpointsObserved || 0, `${summary.totalObservations || 0} наблюдений`],
    ['Здоровые', summary.healthyEndpoints || 0, 'последний статус: здоров'],
    ['Проблемные', summary.problemEndpoints || 0, `${summary.failed24h || 0} проблем за 24ч`],
    [
      'Средняя задержка',
      summary.averageHealthyLatencyMs === null || summary.averageHealthyLatencyMs === undefined
        ? '—'
        : `${summary.averageHealthyLatencyMs} мс`,
      'по последним здоровым наблюдениям',
    ],
    [
      'Внешние проверки VPN-узлов',
      `${external.activeExternalProbeAgents || 0}/${external.externalProbeAgentsTotal || 0}`,
      external.summary?.message || 'Отдельный monitoring VPS ещё не подключён',
    ],
    [
      'Покрытие VPN-узлов',
      `${(external.coveredEndpointIds || []).length}/${(external.requiredEndpointIds || []).length}`,
      (external.missingEndpointIds || []).length
        ? `нет: ${(external.missingEndpointIds || []).join(', ')}`
        : 'VPN-узлы с готовым конфигом покрыты',
    ],
  ];

  summaryContainer.innerHTML = cards
    .map(([label, value, hint]) => `
      <div class="metric-card">
        <span>${escapeUi(label)}</span>
        <strong>${escapeHtml(value)}</strong>
        <p>${escapeUi(hint)}</p>
      </div>
    `)
    .join('');

  if (readinessContainer) {
    const operatorPlan = external.operatorPlan || {};
    const runOnceCommands = operatorPlan.runOnceCommands || external.runOnceCommands || [];
    const missingActions = external.missingCoverageActions || operatorPlan.missingCoverageActions || [];
    const installBundle = operatorPlan.installBundle || {};
    const verifySteps = operatorPlan.verifySteps || [];
    readinessContainer.innerHTML = runOnceCommands.length
      ? `
        <div class="external-action-card ${external.productionReady ? 'ready' : 'pending'}">
          <div class="external-action-head">
            ${statusDot(Boolean(external.productionReady), !external.productionReady)}
            <div>
              <strong>Покрытие внешней проверкой</strong>
              <span>${escapeUi(operatorPlan.tokenPolicy || external.tokenPolicy || 'Админский ключ только через stdin или файл токена вне репозитория.')}</span>
            </div>
            <span class="status-pill ${external.productionReady ? '' : 'yellow'}">${external.productionReady ? 'готово' : 'нужно наблюдение'}</span>
          </div>
          <div class="external-action-meta">
            <span>Разовый запуск:</span>
            <div class="code-list">
              ${runOnceCommands
                .map((item) => `<code>${escapeHtml(item.command || item)}</code>`)
                .join('')}
            </div>
          </div>
          <div class="external-action-meta">
            <span>Timer:</span>
            <div class="code-list"><code>${escapeHtml(installBundle.command || operatorPlan.systemdInstallCommand || 'bash scripts/monitoring/install_probe_systemd.sh --server-health --token-stdin')}</code></div>
          </div>
          <div class="external-action-meta">
            <span>Проверить:</span>
            <div class="pill-list">
              ${verifySteps.map((step) => `<span class="muted">${escapeUi(step)}</span>`).join('')}
            </div>
          </div>
          ${
            missingActions.length
              ? `<div class="external-action-meta">
                  <span>Закрыть:</span>
                  <div class="pill-list">
                    ${missingActions.map((item) => `<span class="status-pill yellow">${escapeHtml(item.endpointId || item)}</span>`).join('')}
                  </div>
                </div>`
              : ''
          }
        </div>
      `
      : '';
  }

  const observations = health?.observations || [];
  table.innerHTML =
    observations
      .map((item) => {
        const score = item.details?.score;
        const scoreText = score === null || score === undefined ? '' : `Оценка: ${score}/100`;
        return `
          <tr>
            <td>
              <strong>${escapeHtml(item.endpointId)}</strong><br>
              <span class="muted">${escapeHtml(item.protocol || 'протокол —')} / ${escapeHtml(item.transport || 'транспорт —')}</span>
            </td>
            <td>
              ${escapeHtml(item.probeId || 'probe —')}<br>
              <span class="muted">${escapeHtml(item.probeRegion || 'регион —')}</span>
            </td>
            <td><span class="status-pill ${serverHealthStatusPillClass(item.status)}">${escapeHtml(serverHealthStatusTitle(item.status))}</span></td>
            <td>${escapeHtml(item.target || '—')}</td>
            <td>
              ${item.latencyMs === null || item.latencyMs === undefined ? '—' : `${escapeHtml(item.latencyMs)} мс`}<br>
              <span class="muted">потери ${item.packetLossPercent === null || item.packetLossPercent === undefined ? '—' : `${escapeHtml(item.packetLossPercent)}%`}</span>
            </td>
            <td>
              ${escapeUi(item.message || item.errorCode || '—')}<br>
              <span class="muted">${escapeUi(scoreText || item.errorCode || '')}</span>
            </td>
            <td>${escapeHtml(shortDate(item.observedAt))}</td>
          </tr>
        `;
      })
      .join('') || '<tr><td colspan="7">Наблюдений пока нет. Агент мониторинга позже начнёт присылать проверки VPN-узлов.</td></tr>';
}

function findServerEntry(serverId) {
  return (state.loaded.servers || []).find((item) => Number(item.id) === Number(serverId));
}

function fillServerForm(server) {
  if (!server) return;
  $('serverIdInput').value = server.serverId || '';
  $('serverTitleInput').value = server.title || '';
  $('serverSubtitleInput').value = server.subtitle || '';
  $('serverCountryInput').value = server.country || '';
  $('serverCityInput').value = server.city || '';
  $('serverProviderInput').value = server.provider || '';
  $('serverHostInput').value = server.host || '';
  $('serverPortInput').value = server.port || 443;
  $('serverProtocolInput').value = server.protocol || 'wireguard_udp';
  $('serverTransportInput').value = server.transport || 'udp';
  $('serverClientConfigProfileInput').value = server.clientConfigProfile || 'none';
  $('serverStatusInput').value = server.status || 'draft';
  $('serverHealthInput').value = server.healthScore ?? 0;
  $('serverLatencyInput').value = server.latencyMs ?? '';
  $('serverPriorityInput').value = server.priority ?? 100;
  $('serverActiveInput').checked = Boolean(server.isActive);
  $('serverPublicInput').checked = Boolean(server.isPublic);
  $('serverNotesInput').value = server.notes || '';
  $('serverForm').dataset.serverEntryId = server.id;
}

function resetServerForm() {
  $('serverForm').reset();
  $('serverForm').dataset.serverEntryId = '';
  $('serverPortInput').value = 443;
  $('serverProtocolInput').value = 'wireguard_udp';
  $('serverTransportInput').value = 'udp';
  $('serverClientConfigProfileInput').value = 'none';
  $('serverStatusInput').value = 'draft';
  $('serverHealthInput').value = 0;
  $('serverPriorityInput').value = 100;
}

function serverFormPayload(statusOverride = null) {
  const latencyRaw = $('serverLatencyInput').value;
  return {
    serverId: $('serverIdInput').value.trim(),
    title: $('serverTitleInput').value.trim(),
    subtitle: $('serverSubtitleInput').value.trim(),
    country: $('serverCountryInput').value.trim(),
    city: $('serverCityInput').value.trim(),
    provider: $('serverProviderInput').value.trim(),
    host: $('serverHostInput').value.trim(),
    port: Number($('serverPortInput').value || 443),
    protocol: $('serverProtocolInput').value || 'wireguard_udp',
    transport: $('serverTransportInput').value || 'udp',
    clientConfigProfile: $('serverClientConfigProfileInput').value || 'none',
    status: statusOverride || $('serverStatusInput').value || 'draft',
    healthScore: Number($('serverHealthInput').value || 0),
    latencyMs: latencyRaw === '' ? null : Number(latencyRaw),
    priority: Number($('serverPriorityInput').value || 100),
    isActive: $('serverActiveInput').checked,
    isPublic: $('serverPublicInput').checked,
    notes: $('serverNotesInput').value.trim(),
  };
}

function plannedServerDraftPayload() {
  const plan = state.loaded.serverProvisioningReadiness?.newServerOnboardingPlan || {};
  const examples = plan.recommendedExamples || [];
  const existingIds = new Set((state.loaded.servers || []).map((server) => server.serverId));
  const candidates = examples
    .map((example) => example.safeDraftPayload || null)
    .filter((payload) => payload?.serverId && !existingIds.has(payload.serverId));
  const fallback = plan.safeDraftPayloadExample || null;
  if (fallback?.serverId && !existingIds.has(fallback.serverId)) {
    candidates.push(fallback);
  }
  const candidate = candidates[0] || null;
  if (!candidate) return null;
  return {
    ...candidate,
    notes: [
      candidate.notes || '',
      'Создано из плана подключения новых VPS. Безопасный режим: не публичный, выключен, без выдачи клиентского конфига.',
    ].filter(Boolean).join('\n'),
  };
}

async function createPlannedServerDraft() {
  if (!requirePermission('servers.manage', 'Создание черновика нового VPS')) return;
  const plan = state.loaded.serverProvisioningReadiness?.newServerOnboardingPlan || {};
  if (!plan.safeToCreateInternalDraft) {
    setNotice('Черновик нового VPS пока заблокирован: нужно сначала вернуть каталог серверов в безопасное состояние.', true);
    return;
  }
  const payload = plannedServerDraftPayload();
  if (!payload) {
    setNotice('Все рекомендованные черновики уже есть во внутреннем каталоге.', true);
    return;
  }
  try {
    const endpoint = plan.draftCreationEndpoint
      || state.loaded.serverWorkflow?.safeDraftCreation?.endpoint
      || '/api/v1/admin/server-catalog/draft-from-plan';
    const result = await apiPost(endpoint, payload);
    await loadDashboardData();
    setNotice(result.message || `Черновик ${payload.serverId} создан во внутреннем каталоге.`);
  } catch (error) {
    setNotice(`Не удалось создать черновик нового VPS: ${error.message}`, true);
  }
}

async function saveServerEntry(statusOverride = null) {
  if (!requirePermission('servers.manage', 'Сохранение VPN-узла')) return;
  try {
    const form = $('serverForm');
    const entryId = form.dataset.serverEntryId;
    const payload = serverFormPayload(statusOverride);
    const path = entryId
      ? `/api/v1/admin/server-catalog/${encodeURIComponent(entryId)}`
      : '/api/v1/admin/server-catalog';
    await apiPost(path, payload);
    resetServerForm();
    await loadDashboardData();
    setNotice('VPN-узел сохранён. Он пока не выдаётся клиентам.');
  } catch (error) {
    setNotice(`Не удалось сохранить VPN-узел: ${error.message}`, true);
  }
}

async function updateServerEntryStatus(entryId, status) {
  if (!requirePermission('servers.manage', 'Изменение VPN-узла')) return;
  const server = findServerEntry(entryId);
  if (!server) {
    setNotice('VPN-узел не найден в текущем списке.', true);
    return;
  }
  fillServerForm(server);
  if (status === 'healthy') {
    $('serverActiveInput').checked = true;
    $('serverHealthInput').value = Math.max(Number($('serverHealthInput').value || 0), 80);
  }
  if (status === 'disabled') {
    $('serverActiveInput').checked = false;
    $('serverHealthInput').value = 0;
  }
  await saveServerEntry(status);
}

async function runRemotePeerSmoke(entryId) {
  if (!requirePermission('servers.manage', 'Проверка удалённого VPN-узла')) return;
  const server = findServerEntry(entryId);
  if (!server) {
    setNotice('VPN-узел не найден в текущем списке.', true);
    return;
  }
  if (server.clientConfigProfile !== 'remote_ssh_wg0') {
    setNotice('Проверка peer доступна только для удалённых WireGuard-узлов с профилем remote_ssh_wg0.', true);
    return;
  }
  const serverId = server.serverId;
  if (!serverId) {
    setNotice('У VPN-узла нет служебного ID, проверку запускать нельзя.', true);
    return;
  }
  if (state.remotePeerSmokeBusyServerIds.has(serverId)) return;

  state.remotePeerSmokeBusyServerIds.add(serverId);
  renderServersTable();
  setNotice(`Запускаю проверку peer для ${serverId}: сервер API добавит временный WireGuard peer и сразу удалит его.`);
  try {
    const result = await apiPost(`/api/v1/admin/server-catalog/${encodeURIComponent(serverId)}/remote-peer-smoke`, {});
    let noticeMessage = '';
    let noticeIsError = false;
    if (result.ok) {
      noticeMessage = `Проверка peer ${serverId} прошла: временный peer добавлен, найден и удалён. Узел ${result.endpoint || server.host} готов к выдаче клиентских конфигов.`;
    } else {
      const firstBlocker = (result.blockers || [])[0] || {};
      const detail = result.message || firstBlocker.message || result.errorCode || 'подробности не вернулись';
      noticeMessage = `Проверка peer ${serverId} не прошла: ${detail}`;
      noticeIsError = true;
    }
    try {
      await loadDashboardData();
    } catch (refreshError) {
      noticeMessage = `${noticeMessage} Данные админки не обновились автоматически: ${refreshError.message}`;
      noticeIsError = true;
    }
    setNotice(noticeMessage, noticeIsError);
  } catch (error) {
    setNotice(`Не удалось выполнить проверку peer для ${serverId}: ${error.message}`, true);
  } finally {
    state.remotePeerSmokeBusyServerIds.delete(serverId);
    renderServersTable();
  }
}

async function runClientConfigSmoke(entryId) {
  if (!requirePermission('servers.manage', 'Проверка клиентского конфига')) return;
  const server = findServerEntry(entryId);
  if (!server) {
    setNotice('VPN-узел не найден в текущем списке.', true);
    return;
  }
  if (server.clientConfigProfile !== 'remote_ssh_wg0') {
    setNotice('Тест конфига доступен только для удалённых WireGuard-узлов с профилем remote_ssh_wg0.', true);
    return;
  }
  const serverId = server.serverId;
  if (!serverId) {
    setNotice('У VPN-узла нет serverId, тест конфига запускать нельзя.', true);
    return;
  }
  if (state.clientConfigSmokeBusyServerIds.has(serverId)) return;

  state.clientConfigSmokeBusyServerIds.add(serverId);
  renderServersTable();
  setNotice(`Запускаю тест конфига для ${serverId}: сервер API соберёт WireGuard-конфиг без возврата ключей и удалит временный peer.`);
  try {
    const result = await apiPost(`/api/v1/admin/server-catalog/${encodeURIComponent(serverId)}/client-config-smoke`, {});
    let noticeMessage = '';
    let noticeIsError = false;
    if (result.ok) {
      noticeMessage = `Тест конфига ${serverId} прошёл: endpoint ${result.endpoint || server.host}, форма конфига собрана (${result.configTextBytes || 0} байт), временный peer удалён.`;
    } else {
      const firstBlocker = (result.blockers || [])[0] || {};
      const detail = result.message || firstBlocker.message || result.errorCode || 'подробности не вернулись';
      noticeMessage = `Тест конфига ${serverId} не прошёл: ${detail}`;
      noticeIsError = true;
    }
    try {
      await loadDashboardData();
    } catch (refreshError) {
      noticeMessage = `${noticeMessage} Данные админки не обновились автоматически: ${refreshError.message}`;
      noticeIsError = true;
    }
    setNotice(noticeMessage, noticeIsError);
  } catch (error) {
    setNotice(`Не удалось выполнить тест конфига для ${serverId}: ${error.message}`, true);
  } finally {
    state.clientConfigSmokeBusyServerIds.delete(serverId);
    renderServersTable();
  }
}

function publicationBlockerSummary(blockers) {
  const list = Array.isArray(blockers) ? blockers : [];
  if (!list.length) return 'блокеров нет';
  return list
    .slice(0, 5)
    .map((item) => item.message || item.code || 'проверка не пройдена')
    .join('; ');
}

async function publishServerEntry(entryId) {
  if (!requirePermission('servers.manage', 'Открытие VPN-узла клиентам')) return;
  const server = findServerEntry(entryId);
  if (!server) {
    setNotice('VPN-узел не найден в текущем списке.', true);
    return;
  }
  const serverId = server.serverId;
  if (!serverId) {
    setNotice('У VPN-узла нет служебного ID, допуск к публикации запустить нельзя.', true);
    return;
  }
  if (state.publicationGateBusyServerIds.has(serverId)) return;

  state.publicationGateBusyServerIds.add(serverId);
  renderServersTable();
  setNotice(`Проверяю допуск к публикации для ${serverId}: здоровье, мониторинг, профиль конфига и готовность к выдаче клиентам.`);
  try {
    const preview = await apiGet(`/api/v1/admin/server-catalog/${encodeURIComponent(serverId)}/publication-gate`);
    if (!preview.canPublish) {
      setNotice(`Открывать ${serverId} клиентам пока нельзя: ${publicationBlockerSummary(preview.blockers)}`, true);
      return;
    }
    const confirmed = confirm(`Открыть VPN-узел ${serverId} клиентам? Он появится в клиентском каталоге Green VPN.`);
    if (!confirmed) {
      setNotice(`Публикация ${serverId} отменена. Узел остался скрытым от клиентов.`);
      return;
    }
    const result = await apiPost(`/api/v1/admin/server-catalog/${encodeURIComponent(serverId)}/publish`, {});
    await loadDashboardData();
    setNotice(result.message || `VPN-узел ${serverId} открыт клиентам.`);
  } catch (error) {
    setNotice(`Не удалось открыть VPN-узел ${serverId} клиентам: ${error.message}`, true);
  } finally {
    state.publicationGateBusyServerIds.delete(serverId);
    renderServersTable();
  }
}

async function unpublishServerEntry(entryId) {
  if (!requirePermission('servers.manage', 'Скрытие VPN-узла из клиентского каталога')) return;
  const server = findServerEntry(entryId);
  if (!server) {
    setNotice('VPN-узел не найден в текущем списке.', true);
    return;
  }
  const serverId = server.serverId;
  if (!serverId) {
    setNotice('У VPN-узла нет служебного ID, скрыть его через допуск к публикации нельзя.', true);
    return;
  }
  if (state.publicationGateBusyServerIds.has(serverId)) return;
  const confirmed = confirm(`Скрыть VPN-узел ${serverId} из клиентского каталога? Уже подключённые клиенты не удаляются, но новые выдачи перестанут выбирать этот узел.`);
  if (!confirmed) return;

  state.publicationGateBusyServerIds.add(serverId);
  renderServersTable();
  setNotice(`Скрываю ${serverId} из клиентского каталога.`);
  try {
    const result = await apiPost(`/api/v1/admin/server-catalog/${encodeURIComponent(serverId)}/unpublish`, {});
    await loadDashboardData();
    setNotice(result.message || `VPN-узел ${serverId} скрыт из клиентского каталога.`);
  } catch (error) {
    setNotice(`Не удалось скрыть VPN-узел ${serverId}: ${error.message}`, true);
  } finally {
    state.publicationGateBusyServerIds.delete(serverId);
    renderServersTable();
  }
}

async function seedCurrentServerEndpoint() {
  if (!requirePermission('servers.manage', 'Добавление текущего VPN-узла')) return;
  try {
    const result = await apiPost('/api/v1/admin/server-catalog/seed-current', {});
    await loadDashboardData();
    setNotice(result.message || 'Текущий VPN-узел добавлен во внутренний каталог.');
  } catch (error) {
    setNotice(`Не удалось добавить текущий VPN-узел: ${error.message}`, true);
  }
}

async function probeCurrentServerEndpoint() {
  if (!requirePermission('monitoring.manage', 'Проверка текущего VPN-узла')) return;
  try {
    const result = await apiPost('/api/v1/admin/server-health/probe-current', {});
    await loadDashboardData();
    setNotice(result.message || 'Проверка текущего VPN-узла завершена.');
  } catch (error) {
    setNotice(`Не удалось проверить текущий VPN-узел: ${error.message}`, true);
  }
}

function monitoringTargetWorkflow() {
  return state.loaded.monitoringTargets?.workflow
    || state.loaded.monitoringTargets?.summary?.workflow
    || {
      targetStatuses: ['active', 'paused', 'disabled'],
      targetTypes: [
        'web',
        'api',
        'dns',
        'tcp',
        'tls',
        'media',
        'throughput',
        'youtube_media',
        'telegram',
        'discord',
        'youtube',
        'payment',
        'update',
        'bootstrap',
        'social',
      ],
      observationStatuses: ['green', 'yellow', 'red', 'unknown'],
      agentMode: 'admin_internal',
    };
}

function monitoringTargetStatusTitle(status) {
  return {
    active: 'Активна',
    paused: 'Пауза',
    disabled: 'Отключена',
  }[status] || status || '—';
}

function monitoringTargetStatusPillClass(status) {
  if (status === 'active') return '';
  if (status === 'paused') return 'yellow';
  if (status === 'disabled') return 'red';
  return 'muted';
}

function monitoringTargetTypeTitle(type) {
  return {
    web: 'Web',
    api: 'API',
    dns: 'DNS',
    tcp: 'TCP',
    tls: 'TLS',
    media: 'Media throughput',
    throughput: 'Throughput',
    youtube_media: 'YouTube video',
    telegram: 'Telegram',
    discord: 'Discord',
    youtube: 'YouTube',
    payment: 'Payment',
    update: 'Обновление',
    bootstrap: 'Стартовая настройка',
    social: 'Social',
  }[type] || type || '—';
}

function serviceObservationStatusTitle(status) {
  return {
    green: 'Работает',
    yellow: 'Деградация',
    red: 'Недоступно',
    unknown: 'Неизвестно',
  }[status] || status || '—';
}

function serviceObservationStatusPillClass(status) {
  if (status === 'green') return '';
  if (status === 'yellow') return 'yellow';
  if (status === 'red') return 'red';
  return 'muted';
}

function decimalText(value, digits = 1) {
  if (value === null || value === undefined || value === '') return '—';
  const number = Number(value);
  if (!Number.isFinite(number)) return '—';
  return number.toLocaleString('ru-RU', {
    minimumFractionDigits: 0,
    maximumFractionDigits: digits,
  });
}

function serviceObservationQualityHtml(item) {
  const details = item?.details || {};
  const hasThroughput = details.throughputMbps !== undefined && details.throughputMbps !== null;
  const failureMode = details.failureMode || '';
  const severity = details.severity || '';
  const mediaHost = details.mediaHost || details.media?.mediaHost || '';
  if (!hasThroughput && !failureMode && !mediaHost) {
    return '<span class="muted">—</span>';
  }
  const throughput = hasThroughput
    ? `<strong>${escapeHtml(decimalText(details.throughputMbps, 2))} Мбит/с</strong>`
    : '';
  const threshold = details.minGreenMbps
    ? `<span class="muted">зелёный порог ${escapeHtml(decimalText(details.minGreenMbps, 1))} Мбит/с</span>`
    : '';
  const mode = failureMode
    ? `<span class="status-pill ${failureMode === 'blocked_or_unreachable' ? 'red' : 'yellow'}">${escapeHtml(failureMode)}</span>`
    : '';
  const severityText = severity && severity !== 'normal'
    ? `<span class="muted">${escapeHtml(severity)}</span>`
    : '';
  const hostText = mediaHost
    ? `<span class="muted">${escapeHtml(mediaHost)}</span>`
    : '';
  return [throughput, mode, threshold, severityText, hostText].filter(Boolean).join('<br>');
}

function monitoringTargetFilterParams() {
  return {
    status: $('monitoringTargetStatusFilter')?.value || 'all',
    service: $('monitoringTargetServiceFilter')?.value?.trim() || '',
    limit: 200,
  };
}

function serviceObservationFilterParams() {
  return {
    targetId: $('serviceObservationTargetFilter')?.value?.trim() || '',
    status: $('serviceObservationStatusFilter')?.value || 'all',
    limit: 100,
  };
}

function clientRouteEventFilterParams() {
  const stage = $('clientRouteStageFilter')?.value || 'all';
  const ok = $('clientRouteOkFilter')?.value || 'all';
  const params = {
    serverId: $('clientRouteServerFilter')?.value?.trim() || '',
    limit: 100,
  };
  if (stage !== 'all') params.stage = stage;
  if (ok === 'true' || ok === 'false') params.ok = ok;
  return params;
}

function clientRouteStageTitle(stage) {
  return {
    bootstrap: 'Bootstrap',
    config_fetch: 'Получение конфига',
    connect: 'Подключение',
    handshake: 'Handshake/traffic',
    connected: 'Подключено',
    network_probe: 'Проверка маршрута',
    disconnect: 'Отключение',
    unknown: 'Неизвестно',
  }[stage] || stage || '—';
}

function clientRouteEventPillClass(event) {
  const details = event?.details || {};
  if (!event?.ok) return 'red';
  if (details.status === 'yellow' || details.failoverRecommended) return 'yellow';
  return '';
}

function clientRouteEventQualityHtml(event) {
  const details = event?.details || {};
  const parts = [];
  if (details.targetId) {
    parts.push(`<strong>${escapeHtml(details.targetId)}</strong>`);
  }
  if (details.status) {
    parts.push(`<span class="status-pill ${serviceObservationStatusPillClass(details.status)}">${escapeHtml(serviceObservationStatusTitle(details.status))}</span>`);
  }
  if (details.throughputMbps !== undefined && details.throughputMbps !== null) {
    const thresholds = [
      details.greenMbps ? `green ${decimalText(details.greenMbps, 1)}` : '',
      details.yellowMbps ? `yellow ${decimalText(details.yellowMbps, 1)}` : '',
    ].filter(Boolean).join(' / ');
    parts.push(`<span>${escapeHtml(decimalText(details.throughputMbps, 2))} Mbps${thresholds ? ` <span class="muted">(${escapeHtml(thresholds)})</span>` : ''}</span>`);
  }
  if (details.sampleHost) {
    parts.push(`<span class="muted">${escapeHtml(details.sampleHost)}</span>`);
  }
  if (details.httpStatus !== undefined && details.httpStatus !== null) {
    parts.push(`<span class="muted">HTTP ${escapeHtml(details.httpStatus)}</span>`);
  }
  if (details.failoverRecommended) {
    parts.push('<span class="status-pill yellow">failover</span>');
  }
  if (details.attempt !== undefined || details.candidates !== undefined) {
    parts.push(`<span class="muted">attempt ${escapeHtml(details.attempt ?? '—')} / ${escapeHtml(details.candidates ?? '—')}</span>`);
  }
  if (Array.isArray(details.selectedSocialApps) && details.selectedSocialApps.length) {
    parts.push(`<span class="muted">${escapeHtml(details.selectedSocialApps.join(', '))}</span>`);
  }
  return parts.length ? parts.join('<br>') : '<span class="muted">—</span>';
}

function renderMonitoringTargetFilters() {
  const workflow = monitoringTargetWorkflow();
  const statusSelect = $('monitoringTargetStatusFilter');
  const statusInput = $('monitoringTargetStatusInput');
  const typeInput = $('monitoringTargetTypeInput');
  const statusItems = (workflow.targetStatuses || []).map((status) => ({
    code: status,
    title: monitoringTargetStatusTitle(status),
  }));
  const typeItems = (workflow.targetTypes || []).map((type) => ({
    code: type,
    title: monitoringTargetTypeTitle(type),
  }));

  if (statusSelect) {
    const current = statusSelect.value || 'all';
    statusSelect.innerHTML = workflowOptionsHtml(statusItems, current, 'Все статусы');
  }
  if (statusInput) {
    const current = statusInput.value || 'active';
    statusInput.innerHTML = workflowOptionsHtml(statusItems, current);
    if (!statusInput.value) statusInput.value = 'active';
  }
  if (typeInput) {
    const current = typeInput.value || 'web';
    typeInput.innerHTML = workflowOptionsHtml(typeItems, current);
    if (!typeInput.value) typeInput.value = 'web';
  }
}

function renderManagedMonitoring() {
  renderMonitoringTargetFilters();

  const targetsPayload = state.loaded.monitoringTargets || {};
  const observationsPayload = state.loaded.serviceObservations || {};
  const clientRoutePayload = state.loaded.clientRouteEvents || {};
  const probesPayload = state.loaded.monitoringProbes || {};
  const readinessPayload = state.loaded.monitoringReadiness || {};
  const routePayload = state.loaded.resilienceRoutes || {};
  const routeDecision = routePayload.routeDecision || {};
  const selectedRoute = routeDecision.selected || {};
  const selectedLayer = (routeDecision.fallbackChain || []).find((item) => item.code === selectedRoute.protocol) || {};
  const selectedClientFeedback = selectedLayer.clientFeedback || {};
  const routeSignal = routeDecision.routeObservationSignal || {};
  const summary = observationsPayload.summary || targetsPayload.summary || {};
  const probeSummary = probesPayload.summary || summary;
  const probeReadiness = readinessPayload.readiness || probeSummary.probeReadiness || summary.probeReadiness || {};
  const probeInstallBundle = probeReadiness.installBundle || readinessPayload.installBundle || {};
  const staleAfterMinutes = Math.round((probeReadiness.staleAfterSeconds || probeSummary.workflow?.probeStaleAfterSeconds || 900) / 60);
  const targetSummaryContainer = $('monitoringTargetsSummary');
  const observationSummaryContainer = $('serviceObservationSummary');
  const clientRouteSummaryContainer = $('clientRouteEventsSummary');
  const probeSummaryContainer = $('monitoringProbeAgentsSummary');
  const probeInstallBundleContainer = $('monitoringProbeInstallBundle');
  const targetTable = $('monitoringTargetsTable');
  const observationTable = $('serviceObservationsTable');
  const clientRouteTable = $('clientRouteEventsTable');
  const probeTable = $('monitoringProbeAgentsTable');
  if (!targetSummaryContainer || !observationSummaryContainer || !targetTable || !observationTable) {
    return;
  }
  const canManageMonitoring = can('monitoring.manage');

  const targetCards = [
    ['Целей', summary.targetTotal || 0, `${summary.activeTargets || 0} активны`],
    ['Проверялись', summary.targetsObserved || 0, `${summary.totalObservations || 0} наблюдений`],
    ['Зелёные', summary.greenTargets || 0, 'последний статус зелёный'],
    ['Проблемные', summary.problemTargets || 0, `${summary.failed24h || 0} жёлтых/красных за 24ч`],
  ];

  targetSummaryContainer.innerHTML = targetCards
    .map(([label, value, hint]) => `
      <div class="metric-card">
        <span>${escapeUi(label)}</span>
        <strong>${escapeHtml(value)}</strong>
        <p>${escapeUi(hint)}</p>
      </div>
    `)
    .join('');

  const qualitySignals = summary.serviceQuality?.signals || [];
  const qualityCards = qualitySignals.slice(0, 3).map((signal) => {
    const throughput = signal.throughputMbps === null || signal.throughputMbps === undefined
      ? serviceObservationStatusTitle(signal.status)
      : `${decimalText(signal.throughputMbps, 2)} Мбит/с`;
    const hint = [
      signal.failureMode || serviceObservationStatusTitle(signal.status),
      signal.minGreenMbps ? `зелёный от ${decimalText(signal.minGreenMbps, 1)} Мбит/с` : '',
      signal.probeRegion || signal.probeId || '',
    ].filter(Boolean).join(' · ');
    return [`Качество: ${signal.targetId}`, throughput, hint || signal.message || 'последний media-сигнал'];
  });

  observationSummaryContainer.innerHTML = [
    [
      'Средняя задержка',
      summary.averageGreenLatencyMs === null || summary.averageGreenLatencyMs === undefined
        ? '—'
        : `${summary.averageGreenLatencyMs} мс`,
      'только зелёные последние проверки',
    ],
    ['Зелёные сейчас', summary.greenTargets || 0, 'работает штатно'],
    ['Проблемные сейчас', summary.problemTargets || 0, 'нужна реакция'],
    ['Сбои за 24ч', summary.failed24h || 0, 'жёлтые/красные события'],
    ...qualityCards,
  ]
    .map(([label, value, hint]) => `
      <div class="metric-card">
        <span>${escapeHtml(label)}</span>
        <strong>${escapeHtml(value)}</strong>
        <p>${escapeHtml(hint)}</p>
      </div>
    `)
    .join('');

  const latestByTarget = new Map(
    (summary.latestByTarget || []).map((item) => [item.targetId, item]),
  );
  const targets = targetsPayload.targets || [];
  targetTable.innerHTML =
    targets
      .map((target) => {
        const latest = latestByTarget.get(target.targetId);
        const endpoint = target.url || [target.host, target.port].filter(Boolean).join(':') || target.path || '—';
        return `
          <tr>
            <td>
              <strong>${escapeUi(target.title)}</strong><br>
              <span class="muted">${escapeHtml(target.targetId)}</span>
            </td>
            <td>
              ${escapeHtml(target.service)}<br>
              <span class="muted">${escapeHtml(monitoringTargetTypeTitle(target.targetType))}</span>
            </td>
            <td>
              ${escapeHtml(endpoint)}<br>
              <span class="muted">ожидается ${escapeUi(target.expectedStatus || '—')}</span>
            </td>
            <td>
              ${escapeHtml(target.intervalSeconds)} сек<br>
              <span class="muted">таймаут ${escapeHtml(target.timeoutSeconds)} сек</span>
            </td>
            <td>
              <span class="status-pill ${monitoringTargetStatusPillClass(target.status)}">${escapeHtml(monitoringTargetStatusTitle(target.status))}</span><br>
              <span class="muted">
                последнее: ${latest ? escapeHtml(serviceObservationStatusTitle(latest.status)) : '—'}
              </span>
            </td>
            <td>
              ${
                canManageMonitoring
                  ? `<div class="row-actions">
                      <button class="small-button" data-monitoring-target-edit="${escapeHtml(target.targetId)}">В форму</button>
                      <button class="small-button" data-monitoring-target-active="${escapeHtml(target.targetId)}">Включить</button>
                      <button class="small-button" data-monitoring-target-pause="${escapeHtml(target.targetId)}">Пауза</button>
                      <button class="small-button danger" data-monitoring-target-disable="${escapeHtml(target.targetId)}">Отключить</button>
                    </div>`
                  : readonlyActionsHtml('monitoring.manage')
              }
            </td>
          </tr>
        `;
      })
      .join('') || '<tr><td colspan="6">Целей мониторинга пока нет. Сервер добавит базовые цели при старте.</td></tr>';

  if (probeSummaryContainer && probeTable) {
    const requiredTotal = (probeReadiness.requiredTargetIds || []).length;
    const coveredRequired = probeReadiness.coveredRequiredTargets || 0;
    const readinessSummary = probeReadiness.summary || {};
    probeSummaryContainer.innerHTML = [
      [
        'Автовыбор маршрута',
        selectedRoute.protocol ? serverProtocolTitle(selectedRoute.protocol) : '—',
        selectedRoute.score === undefined
          ? 'сервер API ещё не выбрал маршрут'
          : `оценка ${selectedRoute.score}/100, ${selectedRoute.reason || 'самый лёгкий рабочий слой'}`,
      ],
      [
        'Сигналы маршрутов',
        routeSignal.freshObservations || 0,
        `свежие наблюдения для выбора способа подключения`,
      ],
      [
        'Сигналы клиентов',
        selectedClientFeedback.observed || 0,
        `успешных ${selectedClientFeedback.ok || 0}, сбоев ${selectedClientFeedback.failed || 0}`,
      ],
      [
        'Готовность внешних проверок',
        probeReadiness.productionReady ? 'готово' : 'настройка',
        readinessSummary.message || 'готовность управляемого агента проверки',
      ],
      [
        'Покрытие целей',
        requiredTotal ? `${coveredRequired}/${requiredTotal}` : '—',
        'YouTube/Discord/Telegram/API',
      ],
      ['Агенты проверки', probeSummary.probeAgentsTotal || 0, `${probeSummary.activeProbeAgents || 0} активны`],
      ['Молчат', probeSummary.staleProbeAgents || 0, `нет наблюдений ${staleAfterMinutes}+ минут`],
      ['С проблемами', probeSummary.problemProbeAgents || 0, 'жёлтый/красный статус за 24ч или последний'],
      ['Проблемные цели', probeSummary.failed24h || 0, 'события сервисов за сутки'],
    ]
      .map(([label, value, hint]) => `
        <div class="metric-card">
          <span>${escapeUi(label)}</span>
          <strong>${escapeHtml(value)}</strong>
          <p>${escapeUi(hint)}</p>
        </div>
      `)
      .join('');

    if (probeInstallBundleContainer) {
      const ownerInputs = (probeInstallBundle.ownerInputs || [])
        .map((item) => {
          const title = item.name || 'поле';
          const suffix = item.secret ? ' · секрет' : '';
          return `<span class="status-pill ${item.secret ? 'red' : 'muted'}">${escapeHtml(title)}${escapeHtml(suffix)}</span>`;
        })
        .join('');
      const verifySteps = (probeInstallBundle.verifySteps || [])
        .map((step) => `<span class="muted">${escapeUi(step)}</span>`)
        .join('');
      const requiredTargets = (probeInstallBundle.requiredTargetIds || [])
        .map((targetId) => `<span class="status-pill muted">${escapeHtml(targetId)}</span>`)
        .join('');
      probeInstallBundleContainer.innerHTML = probeInstallBundle.installCommand
        ? `
          <div class="external-action-card ${probeReadiness.productionReady ? 'ready' : 'pending'}">
            <div class="external-action-head">
              ${statusDot(Boolean(probeReadiness.productionReady), !probeReadiness.productionReady)}
              <div>
                <strong>Пакет установки внешней проверки</strong>
                <span>${escapeUi(probeInstallBundle.tokenPolicy || 'Админский ключ остаётся только на сервере проверки.')}</span>
              </div>
              <span class="status-pill ${probeReadiness.productionReady ? '' : 'yellow'}">${probeReadiness.productionReady ? 'готово' : 'нужен VPS'}</span>
            </div>
            <div class="external-action-meta">
              <span>Установка:</span>
              <div class="code-list"><code>${escapeHtml(probeInstallBundle.installCommand)}</code></div>
            </div>
            <div class="external-action-meta">
              <span>Что нужно от владельца:</span>
              <div class="pill-list">${ownerInputs || '<span class="muted">нет</span>'}</div>
            </div>
            <div class="external-action-meta">
              <span>Обязательные цели:</span>
              <div class="pill-list">${requiredTargets || '<span class="muted">нет</span>'}</div>
            </div>
            <div class="external-action-meta">
              <span>Проверить:</span>
              <div>${verifySteps || '<span class="muted">смотри готовность мониторинга</span>'}</div>
            </div>
          </div>
        `
        : '';
    }

    const probes = probesPayload.probes || probeSummary.probeAgents || [];
    probeTable.innerHTML =
      probes
        .map((probe) => {
          const status = probe.isStale ? 'yellow' : (probe.lastStatus || 'unknown');
          const statusText = probe.isStale
            ? 'Молчит'
            : serviceObservationStatusTitle(probe.lastStatus || 'unknown');
          return `
            <tr>
              <td>
                <strong>${escapeHtml(probe.probeId)}</strong><br>
                <span class="muted">${escapeHtml(probe.probeRegion || 'регион —')}</span>
              </td>
              <td>
                <span class="status-pill ${serviceObservationStatusPillClass(status)}">${escapeHtml(statusText)}</span><br>
                <span class="muted">последний сигнал: ${escapeHtml(shortDate(probe.lastSeenAt))}</span>
              </td>
              <td>
                ${escapeHtml(probe.observations24h || 0)} / ${escapeHtml(probe.totalObservations || 0)}<br>
                <span class="muted">${escapeHtml(probe.targetsObserved || 0)} целей</span>
              </td>
              <td>
                ${escapeHtml(probe.problems24h || 0)} за 24ч<br>
                <span class="muted">красных ${escapeHtml(probe.redTotal || 0)}, жёлтых ${escapeHtml(probe.yellowTotal || 0)}</span>
              </td>
              <td>
                ${escapeHtml(probe.lastTargetId || '—')}<br>
                <span class="muted">${probe.lastLatencyMs === null || probe.lastLatencyMs === undefined ? '—' : `${escapeHtml(probe.lastLatencyMs)} мс`}</span>
              </td>
              <td>${escapeHtml(probe.lastMessage || '—')}</td>
            </tr>
          `;
        })
        .join('') || '<tr><td colspan="6">Агенты проверки пока не присылали наблюдения. Позже внешняя проверка будет запускаться отдельным скриптом без хранения токена в репозитории.</td></tr>';
  }

  const observations = observationsPayload.observations || [];
  observationTable.innerHTML =
    observations
      .map((item) => `
        <tr>
          <td>
            <strong>${escapeHtml(item.targetId)}</strong><br>
            <span class="muted">${escapeUi(item.errorCode || '')}</span>
          </td>
          <td>
            ${escapeHtml(item.probeId || 'probe —')}<br>
            <span class="muted">${escapeHtml(item.probeRegion || 'регион —')}</span>
          </td>
          <td><span class="status-pill ${serviceObservationStatusPillClass(item.status)}">${escapeHtml(serviceObservationStatusTitle(item.status))}</span></td>
          <td>${item.latencyMs === null || item.latencyMs === undefined ? '—' : `${escapeHtml(item.latencyMs)} мс`}</td>
          <td>${serviceObservationQualityHtml(item)}</td>
          <td>${escapeUi(item.message || '—')}</td>
          <td>${escapeHtml(shortDate(item.observedAt || item.createdAt))}</td>
        </tr>
      `)
      .join('') || '<tr><td colspan="7">Наблюдений сервисов пока нет. Проверяющий сервер начнёт писать их позже.</td></tr>';
  renderClientRouteEventsPanel(clientRoutePayload, clientRouteSummaryContainer, clientRouteTable);
}

function renderClientRouteEventsPanel(clientRoutePayload, clientRouteSummaryContainer, clientRouteTable) {
  if (!clientRouteSummaryContainer || !clientRouteTable) return;
  const clientSummary = clientRoutePayload.summary || {};
  const clientRouteDecision = clientRoutePayload.routeDecision || {};
  const clientSelected = clientRouteDecision.selected || {};
  clientRouteSummaryContainer.innerHTML = [
    ['Клиентские сигналы', clientSummary.observed || 0, 'проверки маршрута от Windows/Android'],
    ['Успешные', clientSummary.ok || 0, 'клиент увидел рабочий маршрут'],
    ['Проблемы', clientSummary.failed || 0, 'нужен failover или ручная проверка'],
    [
      'Оценка клиента',
      clientSummary.score === null || clientSummary.score === undefined ? '—' : `${clientSummary.score}/100`,
      clientSummary.confidence ? `уверенность ${clientSummary.confidence}` : 'по последним client route-events',
    ],
    [
      'Auto route',
      clientSelected.protocol ? serverProtocolTitle(clientSelected.protocol) : '—',
      clientSelected.reason || 'решение backend route selector',
    ],
  ]
    .map(([label, value, hint]) => `
      <div class="metric-card">
        <span>${escapeHtml(label)}</span>
        <strong>${escapeHtml(value)}</strong>
        <p>${escapeHtml(hint)}</p>
      </div>
    `)
    .join('');

  const clientEvents = clientRoutePayload.events || [];
  clientRouteTable.innerHTML = clientEvents
    .map((event) => {
      const protocol = event.protocol ? serverProtocolTitle(event.protocol) : '—';
      const serverId = event.serverId || event.server_id || '—';
      const resultText = event.ok ? 'OK' : 'Проблема';
      const details = event.details || {};
      return `
        <tr>
          <td>
            <strong>${escapeHtml(serverId)}</strong><br>
            <span class="muted">${escapeHtml(protocol)}</span>
          </td>
          <td>${escapeHtml(clientRouteStageTitle(event.stage))}</td>
          <td><span class="status-pill ${clientRouteEventPillClass(event)}">${escapeHtml(resultText)}</span></td>
          <td>${clientRouteEventQualityHtml(event)}</td>
          <td>
            ${escapeHtml(event.message || details.message || '—')}<br>
            <span class="muted">${escapeHtml(event.clientPlatform || event.platform || '')}</span>
          </td>
          <td>${escapeHtml(shortDate(event.createdAt || event.created_at))}</td>
        </tr>
      `;
    })
    .join('') || '<tr><td colspan="6">Клиентских route-events пока нет. Они появятся после подключений свежих Windows/Android 0.2.10.</td></tr>';
}

function findMonitoringTarget(targetId) {
  return (state.loaded.monitoringTargets?.targets || [])
    .find((item) => item.targetId === targetId);
}

function resetMonitoringTargetForm() {
  const form = $('monitoringTargetForm');
  if (!form) return;
  form.reset();
  form.dataset.targetId = '';
  $('monitoringTargetTypeInput').value = 'web';
  $('monitoringTargetStatusInput').value = 'active';
  $('monitoringTargetTimeoutInput').value = 8;
  $('monitoringTargetIntervalInput').value = 300;
  $('monitoringTargetPublicImpactInput').checked = true;
}

function fillMonitoringTargetForm(target) {
  if (!target) return;
  const form = $('monitoringTargetForm');
  form.dataset.targetId = target.targetId;
  $('monitoringTargetIdInput').value = target.targetId || '';
  $('monitoringTargetTitleInput').value = target.title || '';
  $('monitoringTargetServiceInput').value = target.service || '';
  $('monitoringTargetTypeInput').value = target.targetType || 'web';
  $('monitoringTargetStatusInput').value = target.status || 'active';
  $('monitoringTargetUrlInput').value = target.url || '';
  $('monitoringTargetHostInput').value = target.host || '';
  $('monitoringTargetPortInput').value = target.port ?? '';
  $('monitoringTargetExpectedInput').value = target.expectedStatus ?? '';
  $('monitoringTargetTimeoutInput').value = target.timeoutSeconds ?? 8;
  $('monitoringTargetIntervalInput').value = target.intervalSeconds ?? 300;
  $('monitoringTargetPathInput').value = target.path || '';
  $('monitoringTargetTagsInput').value = (target.tags || []).join(', ');
  $('monitoringTargetNotesInput').value = target.notes || '';
  $('monitoringTargetPublicImpactInput').checked = target.publicImpact !== false;
}

function monitoringTargetFormPayload(statusOverride = null) {
  const portRaw = $('monitoringTargetPortInput').value;
  const expectedRaw = $('monitoringTargetExpectedInput').value;
  return {
    targetId: $('monitoringTargetIdInput').value.trim(),
    title: $('monitoringTargetTitleInput').value.trim(),
    service: $('monitoringTargetServiceInput').value.trim(),
    targetType: $('monitoringTargetTypeInput').value || 'web',
    url: $('monitoringTargetUrlInput').value.trim(),
    host: $('monitoringTargetHostInput').value.trim(),
    port: portRaw === '' ? null : Number(portRaw),
    path: $('monitoringTargetPathInput').value.trim(),
    expectedStatus: expectedRaw === '' ? null : Number(expectedRaw),
    timeoutSeconds: Number($('monitoringTargetTimeoutInput').value || 8),
    intervalSeconds: Number($('monitoringTargetIntervalInput').value || 300),
    status: statusOverride || $('monitoringTargetStatusInput').value || 'active',
    tags: ($('monitoringTargetTagsInput').value || '')
      .split(/[,\n;]+/)
      .map((item) => item.trim())
      .filter(Boolean),
    notes: $('monitoringTargetNotesInput').value.trim(),
    publicImpact: $('monitoringTargetPublicImpactInput').checked,
  };
}

async function saveMonitoringTarget(statusOverride = null) {
  if (!requirePermission('monitoring.manage', 'Сохранение цели мониторинга')) return;
  try {
    const form = $('monitoringTargetForm');
    const existingTargetId = form.dataset.targetId;
    const payload = monitoringTargetFormPayload(statusOverride);
    const path = existingTargetId
      ? `/api/v1/admin/monitoring/targets/${encodeURIComponent(existingTargetId)}`
      : '/api/v1/admin/monitoring/targets';
    await apiPost(path, payload);
    resetMonitoringTargetForm();
    await loadDashboardData();
    setNotice('Цель мониторинга сохранена.');
  } catch (error) {
    setNotice(`Не удалось сохранить цель мониторинга: ${error.message}`, true);
  }
}

async function seedDefaultMonitoringTargets() {
  if (!requirePermission('monitoring.manage', 'Обновление базовых целей мониторинга')) return;
  try {
    const result = await apiPost('/api/v1/admin/monitoring/targets/seed-defaults', {});
    await loadDashboardData();
    setNotice(`Базовые цели обновлены: ${result.seededTargets?.length || 0}.`);
  } catch (error) {
    setNotice(`Не удалось обновить базовые цели: ${error.message}`, true);
  }
}

async function updateMonitoringTargetStatus(targetId, status) {
  if (!requirePermission('monitoring.manage', 'Изменение цели мониторинга')) return;
  const target = findMonitoringTarget(targetId);
  if (!target) {
    setNotice('Цель мониторинга не найдена в текущем списке.', true);
    return;
  }
  fillMonitoringTargetForm(target);
  await saveMonitoringTarget(status);
}

function encodeQuery(params) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params || {})) {
    if (value !== null && value !== undefined && String(value).trim() !== '') {
      search.set(key, String(value).trim());
    }
  }
  const query = search.toString();
  return query ? `?${query}` : '';
}

function supportFilterParams() {
  const status = $('supportStatusFilter').value || 'all';
  const priority = $('supportPriorityFilter')?.value || 'all';
  const category = $('supportCategoryFilter')?.value || 'all';
  const assignedTo = $('supportAssignedFilter')?.value?.trim() || '';
  const raw = $('supportSearchInput')?.value?.trim() || '';
  const params = { status, priority, category, limit: 80 };
  if (assignedTo) params.assignedTo = assignedTo;
  if (!raw) return params;
  if (/^\d+$/.test(raw)) {
    params.userId = raw;
  } else if (raw.includes('@')) {
    params.email = raw;
  } else {
    params.deviceUid = raw;
  }
  return params;
}

function incidentFilterParams() {
  return {
    status: $('incidentStatusFilter')?.value || 'all',
    severity: $('incidentSeverityFilter')?.value || 'all',
    assignee: $('incidentAssigneeFilter')?.value || 'all',
    limit: 100,
  };
}

function userFilterParams() {
  return {
    limit: 100,
    q: $('userSearchInput')?.value?.trim() || '',
  };
}

function authFilterParams() {
  return {
    limit: 80,
    eventType: $('authTypeFilter')?.value || 'all',
    status: $('authStatusFilter')?.value || 'all',
    contact: $('authSearchInput')?.value?.trim() || '',
  };
}

function debounce(fn, delay = 350) {
  let timeoutId = null;
  return (...args) => {
    window.clearTimeout(timeoutId);
    timeoutId = window.setTimeout(() => fn(...args), delay);
  };
}

function renderReportComments(comments = []) {
  if (!comments.length) {
    return '<p class="muted">Комментариев поддержки пока нет.</p>';
  }
  return comments
    .map(
      (comment) => `
        <article class="comment-card">
          <div class="comment-card-head">
            <strong>${escapeHtml(comment.author || 'support')}</strong>
            <span>${escapeHtml(shortDate(comment.createdAt))}</span>
          </div>
          <p>${escapeHtml(comment.body)}</p>
          <span class="muted">IP: ${escapeHtml(comment.requestIp)}</span>
        </article>
      `,
    )
    .join('');
}

function shortDate(value) {
  if (!value) return '—';
  try {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return date.toLocaleString('ru-RU');
  } catch (_error) {
    return String(value);
  }
}

function setNotice(message, isError = false) {
  const notice = $('notice');
  notice.textContent = message || '';
  notice.classList.toggle('hidden', !message);
  notice.classList.toggle('error', Boolean(isError));
}

function setSidebarStatus(text, mode = 'muted') {
  const pill = $('sidebarStatus');
  pill.textContent = text;
  pill.className = `status-pill ${mode}`;
}

function normalizeApiBase(value) {
  const trimmed = String(value || '').trim().replace(/\/+$/, '');
  return trimmed || DEFAULT_API_BASE;
}

function saveSession(remember) {
  if (!remember) {
    localStorage.removeItem(STORAGE_KEY);
    return;
  }
  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify({
      apiBase: state.apiBase,
      adminToken: state.adminToken,
      adminActor: state.adminActor,
      adminEmail: state.adminEmail,
      sessionToken: state.sessionToken,
      authType: state.authType,
      currentStaff: state.currentStaff,
      permissions: state.permissions,
      roleTitle: state.roleTitle,
      savedAt: new Date().toISOString(),
    }),
  );
}

function loadSession() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return;
    const parsed = JSON.parse(raw);
    state.apiBase = normalizeApiBase(parsed.apiBase);
    state.adminToken = String(parsed.adminToken || '');
    state.adminActor = String(parsed.adminActor || '');
    state.adminEmail = String(parsed.adminEmail || '');
    state.sessionToken = String(parsed.sessionToken || '');
    state.authType = String(parsed.authType || '');
    state.currentStaff = parsed.currentStaff || null;
    state.permissions = Array.isArray(parsed.permissions) ? parsed.permissions : [];
    state.roleTitle = String(parsed.roleTitle || '');
  } catch (_error) {
    localStorage.removeItem(STORAGE_KEY);
  }
}

function adminHeaders(baseHeaders = {}) {
  const headers = { ...baseHeaders };
  if (state.sessionToken) {
    headers.Authorization = `Bearer ${state.sessionToken}`;
  } else if (state.adminToken) {
    headers['X-Admin-Token'] = state.adminToken;
  }
  if (state.adminActor) {
    headers['X-Admin-Actor'] = state.adminActor;
  }
  return headers;
}

function hasAdminCredential() {
  return Boolean(state.sessionToken || state.adminToken);
}

const PERMISSION_LABELS = {
  'dashboard.read': 'просмотр обзора',
  'analytics.read': 'просмотр аналитики',
  'incidents.read': 'просмотр инцидентов',
  'incidents.manage': 'управление инцидентами',
  'support.read': 'просмотр поддержки',
  'support.manage': 'управление обращениями',
  'support_actions.read': 'просмотр действий поддержки',
  'support_actions.manage': 'выполнение действий поддержки',
  'users.read': 'просмотр пользователей',
  'users.manage': 'управление пользователями',
  'devices.manage': 'управление устройствами',
  'billing.read': 'просмотр платежей',
  'billing.manage': 'управление платежами',
  'audit.read': 'просмотр аудита и входов',
  'staff.manage': 'управление командой',
  'updates.read': 'просмотр обновлений',
  'updates.manage': 'управление обновлениями',
  'flags.manage': 'управление флагами',
  'runbooks.manage': 'управление инструкциями',
  'monitoring.read': 'просмотр мониторинга',
  'monitoring.manage': 'управление мониторингом',
  'servers.read': 'просмотр серверов',
  'servers.manage': 'управление серверами',
  'readiness.read': 'просмотр готовности',
  'readiness.manage': 'управление готовностью',
};

function permissionLabel(permission) {
  return PERMISSION_LABELS[permission] || permission || 'действие';
}

function can(permission) {
  if (!permission) return true;
  if (state.authType === 'bootstrap_token' && state.adminToken) return true;
  return state.permissions.includes(permission);
}

function requirePermission(permission, actionTitle = 'Действие') {
  if (can(permission)) return true;
  setNotice(`${actionTitle}: у текущей роли нет права «${permissionLabel(permission)}».`, true);
  return false;
}

function readonlyActionsHtml(permission) {
  return `
    <span class="status-pill muted" title="Нужно право: ${escapeHtml(permissionLabel(permission))}">
      только чтение
    </span>
  `;
}

function setPermissionLock(element, locked, permission) {
  if (!element) return;
  const existingBanner = element.querySelector('[data-permission-banner]');
  if (locked && !existingBanner) {
    const banner = document.createElement('div');
    banner.dataset.permissionBanner = '1';
    banner.className = 'permission-banner';
    banner.textContent = `Текущая роль может смотреть этот раздел, но не менять данные. Нужно право: ${permissionLabel(permission)}.`;
    element.prepend(banner);
  } else if (!locked && existingBanner) {
    existingBanner.remove();
  }

  element.classList.toggle('permission-locked', locked);
  element.querySelectorAll('input, select, textarea, button').forEach((control) => {
    control.disabled = locked;
  });
}

function syncPermissionControls() {
  [
    ['releaseForm', 'updates.manage'],
    ['featureFlagForm', 'flags.manage'],
    ['runbookForm', 'runbooks.manage'],
    ['serverForm', 'servers.manage'],
    ['monitoringTargetForm', 'monitoring.manage'],
    ['staffForm', 'staff.manage'],
  ].forEach(([id, permission]) => {
    setPermissionLock($(id), hasAdminCredential() && !can(permission), permission);
  });

  const testAlertsButton = $('testAlertsButton');
  if (testAlertsButton) {
    testAlertsButton.disabled = hasAdminCredential() && !can('incidents.manage');
    testAlertsButton.title = can('incidents.manage')
      ? ''
      : `Нужно право: ${permissionLabel('incidents.manage')}`;
  }
  const createPlannedServerDraftButton = $('createPlannedServerDraftButton');
  if (createPlannedServerDraftButton) {
    createPlannedServerDraftButton.disabled = hasAdminCredential() && !can('servers.manage');
    createPlannedServerDraftButton.title = can('servers.manage')
      ? 'Создать безопасный внутренний черновик нового сервера из плана подключения'
      : `Нужно право: ${permissionLabel('servers.manage')}`;
  }
  const seedCurrentServerButton = $('seedCurrentServerButton');
  if (seedCurrentServerButton) {
    seedCurrentServerButton.disabled = hasAdminCredential() && !can('servers.manage');
    seedCurrentServerButton.title = can('servers.manage')
      ? 'Добавить текущий рабочий WireGuard VPN-узел во внутренний каталог'
      : `Нужно право: ${permissionLabel('servers.manage')}`;
  }
  const probeCurrentServerButton = $('probeCurrentServerButton');
  if (probeCurrentServerButton) {
    probeCurrentServerButton.disabled = hasAdminCredential() && !can('monitoring.manage');
    probeCurrentServerButton.title = can('monitoring.manage')
      ? 'Запустить серверную проверку текущего WireGuard VPN-узла'
      : `Нужно право: ${permissionLabel('monitoring.manage')}`;
  }
  const seedDefaultMonitoringTargetsButton = $('seedDefaultMonitoringTargetsButton');
  if (seedDefaultMonitoringTargetsButton) {
    seedDefaultMonitoringTargetsButton.disabled = hasAdminCredential() && !can('monitoring.manage');
    seedDefaultMonitoringTargetsButton.title = can('monitoring.manage')
      ? 'Обновить встроенные цели API/YouTube/Discord/Telegram без удаления кастомных целей'
      : `Нужно право: ${permissionLabel('monitoring.manage')}`;
  }
}

function sectionPermission(section) {
  const button = document.querySelector(`.nav-link[data-section="${section}"]`);
  return button?.dataset.permission || '';
}

function firstAllowedSection() {
  const firstButton = [...document.querySelectorAll('.nav-link')]
    .find((button) => can(button.dataset.permission || ''));
  return firstButton?.dataset.section || 'dashboard';
}

function setAdminContext(authPayload) {
  const auth = authPayload?.auth || authPayload || {};
  state.authType = auth.authType || state.authType;
  state.currentStaff = auth.staff || state.currentStaff;
  state.permissions = Array.isArray(auth.permissions) ? auth.permissions : state.permissions;
  state.roleTitle = auth.roleTitle || auth.role?.title || state.roleTitle;
  if (state.currentStaff?.email) {
    state.adminEmail = state.currentStaff.email;
    state.adminActor = state.currentStaff.displayName || state.currentStaff.email;
  }
}

function currentAdminLabel() {
  if (state.currentStaff?.email) {
    return `${state.currentStaff.email} · ${state.roleTitle || state.currentStaff.role || 'staff'}`;
  }
  return state.adminActor || (state.adminToken ? 'владелец' : 'не подключено');
}

function applyAuthUi() {
  const authenticated = hasAdminCredential();
  document.querySelector('.shell')?.classList.toggle('auth-locked', !authenticated);
  $('loginPanel')?.classList.toggle('hidden', authenticated);
  $('logoutButton')?.classList.toggle('hidden', !authenticated);
  $('refreshButton')?.classList.toggle('hidden', !authenticated);
  $('openLoginButton')?.classList.toggle('hidden', authenticated);
  if ($('openLoginButton')) {
    $('openLoginButton').textContent = 'Войти';
  }
  document.querySelectorAll('.nav-link').forEach((button) => {
    const allowed = can(button.dataset.permission || '');
    button.classList.toggle('hidden', !authenticated || !allowed);
    button.disabled = !authenticated || !allowed;
  });
  if (authenticated && !can(sectionPermission(state.section))) {
    state.section = firstAllowedSection();
    switchSection(state.section);
  }
  syncPermissionControls();
}

async function refreshAdminContext() {
  const result = await apiGet('/api/v1/admin/auth/me');
  setAdminContext(result);
  return result;
}

function addAllowedRequest(requests, key, permission, factory) {
  if (can(permission)) {
    requests[key] = factory();
  }
}

function resetLoadedData() {
  Object.assign(state.loaded, {
    overview: null,
    analytics: null,
    launchReadiness: null,
    advertisingReadiness: null,
    launchClosurePlan: null,
    launchOwnerPacket: null,
    readiness: null,
    siteReadiness: null,
    networkReadiness: null,
    networkSplitPlan: null,
    userAuthReadiness: null,
    adminTwoFactorReadiness: null,
    externalActions: null,
    support: [],
    supportSla: null,
    users: [],
    orders: [],
    promos: [],
    promoReadiness: null,
    billingReconciliation: null,
    billingRenewals: null,
    billingPaymentSmoke: null,
    subscriptionExpiry: null,
    auth: [],
    audit: [],
    roles: [],
    staff: [],
    incidents: [],
    incidentAssignees: [],
    alertEvents: [],
    releases: [],
    featureFlags: [],
    runbooks: [],
    supportActions: [],
    servers: [],
    supportWorkflow: null,
    supportActionWorkflow: null,
    incidentWorkflow: null,
    releaseWorkflow: null,
    featureFlagWorkflow: null,
    runbookWorkflow: null,
    serverWorkflow: null,
    serverCatalog: null,
    serverCatalogSummary: null,
    serverPublicationReadiness: null,
    serverProvisioningReadiness: null,
    serverHealth: null,
    resilienceRoutes: null,
    monitoringTargets: null,
    serviceObservations: null,
    clientRouteEvents: null,
    monitoringProbes: null,
    monitoringReadiness: null,
    adminSessions: [],
    staffSessions: null,
    updateManifest: null,
    updateReadiness: null,
    monitoring: null,
    services: null,
  });
}

async function apiGet(path, admin = true) {
  const headers = { Accept: 'application/json' };
  if (admin && (state.sessionToken || state.adminToken)) {
    Object.assign(headers, adminHeaders());
  }
  const response = await fetch(`${state.apiBase}${path}`, { headers });
  const text = await response.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch (_error) {
    data = { raw: text };
  }
  if (!response.ok) {
    const detail = formatApiErrorDetail(data, text, response.statusText);
    throw new Error(`${response.status}: ${detail}`);
  }
  return data;
}

async function apiPost(path, body = {}, admin = true) {
  const headers = {
    Accept: 'application/json',
    'Content-Type': 'application/json',
  };
  if (admin && (state.sessionToken || state.adminToken)) {
    Object.assign(headers, adminHeaders());
  }
  const response = await fetch(`${state.apiBase}${path}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
  const text = await response.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch (_error) {
    data = { raw: text };
  }
  if (!response.ok) {
    const detail = formatApiErrorDetail(data, text, response.statusText);
    throw new Error(`${response.status}: ${detail}`);
  }
  return data;
}

function renderMetrics(overview) {
  const metrics = [
    ['Пользователи', overview?.usersCount],
    ['Устройства', overview?.devicesCount],
    ['Активные подписки', overview?.activeSubscriptionsCount],
    ['Ожидают оплату', overview?.pendingBillingOrdersCount],
    ['Обращения в поддержку', overview?.openSupportReportsCount],
    ['Действия поддержки за 24ч', overview?.supportActions24hCount],
    ['Инциденты', overview?.openIncidentsCount],
  ];
  $('metricGrid').innerHTML = metrics
    .map(
      ([label, value]) => `
        <div class="metric-card">
          <span>${escapeHtml(label)}</span>
          <strong>${escapeHtml(value, '0')}</strong>
        </div>
      `,
    )
    .join('');
}

function renderAccountSecurity() {
  const isStaffSession = state.authType === 'staff_session' && state.currentStaff;
  const authTitle = isStaffSession
    ? state.currentStaff.displayName || state.currentStaff.email
    : (state.authType === 'bootstrap_token' ? 'Владелец' : 'Не подключено');
  const authHint = isStaffSession
    ? `${state.currentStaff.email} · ${state.roleTitle || state.currentStaff.role || 'роль'}`
    : 'Для ежедневной работы используется почта сотрудника и пароль.';
  const twoFactorLabel = isStaffSession
    ? (state.currentStaff.twoFactorEnabled ? 'Почтовый код включён' : 'Почтовый код выключен')
    : 'Код по почте только для сотрудников';
  const twoFactorHint = state.loaded.adminTwoFactorReadiness
    ? `сотрудников с кодом: ${state.loaded.adminTwoFactorReadiness.enabledStaffCount || 0}/${state.loaded.adminTwoFactorReadiness.totalStaffCount || 0}`
    : 'статус загрузится вместе с разделом команды';
  $('accountSecuritySummary').innerHTML = `
    <div class="status-row">
      ${statusDot(Boolean(hasAdminCredential()), state.authType === 'bootstrap_token')}
      <div>
        <strong>${escapeHtml(authTitle)}</strong>
        <span>${escapeHtml(authHint)}</span>
      </div>
      <span class="status-pill ${isStaffSession ? '' : 'yellow'}">${escapeUi(isStaffSession ? 'сотрудник' : (state.authType === 'bootstrap_token' ? 'владелец' : 'нет входа'))}</span>
    </div>
    <div class="status-row">
      ${statusDot(Boolean(isStaffSession && state.currentStaff.twoFactorEnabled), isStaffSession && !state.currentStaff.twoFactorEnabled)}
      <div>
        <strong>${escapeHtml(twoFactorLabel)}</strong>
        <span>${escapeHtml(twoFactorHint)}</span>
      </div>
      <span class="status-pill ${isStaffSession && state.currentStaff.twoFactorEnabled ? '' : 'yellow'}">код по почте</span>
    </div>
  `;

  $('passwordChangeForm')?.classList.toggle('hidden', !isStaffSession);
  const sessions = state.loaded.adminSessions || [];
  if (!isStaffSession) {
    $('adminSessionsList').innerHTML = `
      <div class="status-row">
        ${statusDot(false, true)}
        <div>
          <strong>Сессии сотрудников доступны после входа по почте</strong>
          <span>Войди как сотрудник, чтобы видеть активные входы и менять свой пароль.</span>
        </div>
        <span class="status-pill yellow">только владелец</span>
      </div>
    `;
    return;
  }

  $('adminSessionsList').innerHTML = sessions
    .map((session) => {
      const revoked = Boolean(session.revokedAt);
      const status = session.isCurrent ? 'текущая' : (revoked ? 'отозвана' : 'активна');
      const pillClass = session.isCurrent ? '' : (revoked ? 'muted' : 'yellow');
      const action = !session.isCurrent && !revoked
        ? `<button class="small-button danger" data-admin-session-revoke="${escapeHtml(session.sessionId)}">Отозвать</button>`
        : `<span class="status-pill ${pillClass}">${escapeHtml(status)}</span>`;
      return `
        <div class="status-row">
          ${statusDot(!revoked, !session.isCurrent)}
          <div>
            <strong>${escapeHtml(session.sessionId)}</strong>
            <span>
              ${escapeHtml(session.requestIp || 'ip неизвестен')} ·
              вход ${escapeHtml(shortDate(session.createdAt))} ·
              активность ${escapeHtml(shortDate(session.lastSeenAt))}
            </span>
            <span>${escapeHtml(session.userAgent || 'данные браузера не записаны')}</span>
          </div>
          ${action}
        </div>
      `;
    })
    .join('') || `
      <div class="status-row">
        ${statusDot(false, true)}
        <div>
          <strong>Сессии пока не загружены</strong>
          <span>Обнови данные после входа сотрудником.</span>
        </div>
        <span class="status-pill muted">пусто</span>
      </div>
    `;
}

function numberText(value) {
  if (value === null || value === undefined || value === '') return '0';
  return new Intl.NumberFormat('ru-RU').format(Number(value) || 0);
}

function percentText(value) {
  if (value === null || value === undefined || value === '') return '0%';
  return `${String(value).replace('.', ',')}%`;
}

function analyticsRow(label, value, hint = '', pillClass = 'muted') {
  return `
    <div class="status-row">
      ${statusDot(pillClass !== 'red', pillClass === 'yellow')}
      <div>
        <strong>${escapeUi(label)}</strong>
        <span>${escapeUi(hint, '')}</span>
      </div>
      <span class="status-pill ${escapeHtml(pillClass)}">${escapeUi(value, '0')}</span>
    </div>
  `;
}

function renderBreakdown(title, items) {
  const rows = Object.entries(items || {})
    .map(([key, value]) => `
      <tr>
        <td>${escapeUi(key)}</td>
        <td>${escapeHtml(numberText(value))}</td>
      </tr>
    `)
    .join('');
  return `
    <div class="detail-card">
      <strong>${escapeUi(title)}</strong>
      <table class="mini-table">
        <tbody>${rows || '<tr><td colspan="2">Нет данных</td></tr>'}</tbody>
      </table>
    </div>
  `;
}

function renderTrendTable(title, series, suffix = '') {
  const rows = (series || [])
    .map((point) => `
      <tr>
        <td>${escapeHtml(point.day)}</td>
        <td>${escapeHtml(numberText(point.value))}${escapeHtml(suffix, '')}</td>
      </tr>
    `)
    .join('');
  return `
    <div class="detail-card">
      <strong>${escapeUi(title)}</strong>
      <table class="mini-table">
        <tbody>${rows || '<tr><td colspan="2">Нет данных</td></tr>'}</tbody>
      </table>
    </div>
  `;
}

function renderAnalytics() {
  const analytics = state.loaded.analytics;
  if (!analytics) {
    $('analyticsKpiGrid').innerHTML = '';
    $('analyticsBusinessPanel').innerHTML = '<p class="muted">Аналитика ещё не загружена.</p>';
    $('analyticsFinancePanel').innerHTML = '<p class="muted">Аналитика ещё не загружена.</p>';
    $('analyticsSupportPanel').innerHTML = '<p class="muted">Аналитика ещё не загружена.</p>';
    $('analyticsOpsPanel').innerHTML = '<p class="muted">Аналитика ещё не загружена.</p>';
    $('analyticsTrendsPanel').innerHTML = '';
    return;
  }

  const users = analytics.business?.users || {};
  const devices = analytics.business?.devices || {};
  const subscriptions = analytics.business?.subscriptions || {};
  const orders = analytics.business?.orders || {};
  const conversion = analytics.business?.conversion || {};
  const support = analytics.support || {};
  const incidents = analytics.incidents || {};
  const updates = analytics.updates || {};
  const servers = analytics.servers || {};
  const auth = analytics.auth || {};
  const readiness = analytics.readiness || {};

  const kpis = [
    ['Пользователи', numberText(users.total), `+${numberText(users.created7d)} за 7 дней`],
    ['Активные подписки', numberText(subscriptions.active), `${numberText(subscriptions.paid)} платных`],
    ['Выручка', money(orders.grossRevenueRub), `${money(orders.paid30dRub)} за 30 дней`],
    ['Ожидают оплату', money(orders.pendingRevenueRub), `${numberText(orders.pending)} заказов`],
    ['Открытая поддержка', numberText(support.openTotal), `${numberText(support.overdueSla)} просрочено`],
    ['Инциденты', numberText(incidents.openTotal), `${numberText(incidents.criticalOpen)} критичных`],
  ];

  $('analyticsKpiGrid').innerHTML = kpis
    .map(([label, value, hint]) => `
      <div class="metric-card">
        <span>${escapeHtml(label)}</span>
        <strong>${escapeHtml(value)}</strong>
        <p class="muted">${escapeHtml(hint)}</p>
      </div>
    `)
    .join('');

  $('analyticsBusinessPanel').innerHTML = [
    analyticsRow('Новые аккаунты за 30 дней', numberText(users.created30d), `${percentText(users.emailVerifiedSharePercent)} с подтверждённой почтой`),
    analyticsRow('Телефон подтверждён', numberText(users.phoneVerified), `${percentText(users.phoneVerifiedSharePercent)} от пользователей`),
    analyticsRow('Устройства', `${numberText(devices.enabled)} / ${numberText(devices.total)}`, `${numberText(devices.configIssued)} получили конфиг`),
    analyticsRow('Конверсия в оплату', percentText(conversion.paidUserSharePercent), `${numberText(conversion.usersWithPaidOrders)} пользователей с оплатой`),
    analyticsRow('Истекают за 7 дней', numberText(subscriptions.expires7d), 'нужно продление или ручной контакт', subscriptions.expires7d > 0 ? 'yellow' : 'muted'),
  ].join('');

  $('analyticsFinancePanel').innerHTML = [
    analyticsRow('Всего заказов', numberText(orders.total), `${numberText(orders.activated)} активировано`),
    analyticsRow('Оплачено, но не активировано', numberText(orders.paid), 'ручной контроль на старте', orders.paid > 0 ? 'yellow' : 'muted'),
    analyticsRow('Средний оплаченный заказ', money(orders.averagePaidOrderRub), 'по оплаченным и активированным заказам'),
    analyticsRow('Ошибочные/отменённые', `${numberText(orders.failed)} / ${numberText(orders.cancelled)}`, 'ошибочные / отменённые', (orders.failed || orders.cancelled) ? 'yellow' : 'muted'),
    renderBreakdown('Заказы по статусам', {
      pending: orders.pending,
      paid: orders.paid,
      activated: orders.activated,
      failed: orders.failed,
      cancelled: orders.cancelled,
    }),
  ].join('');

  $('analyticsSupportPanel').innerHTML = [
    analyticsRow('Новые отчёты за 7 дней', numberText(support.created7d), `${numberText(support.resolved7d)} закрыто`),
    analyticsRow('SLA просрочено', numberText(support.overdueSla), 'нужно смотреть первым', support.overdueSla > 0 ? 'red' : 'muted'),
    analyticsRow('Без первого ответа', numberText(support.firstResponseMissing), 'важно для поддержки', support.firstResponseMissing > 0 ? 'yellow' : 'muted'),
    renderBreakdown('По приоритетам', support.byPriority),
    renderBreakdown('По категориям', support.byCategory),
  ].join('');

  $('analyticsOpsPanel').innerHTML = [
    analyticsRow('Критичные инциденты', numberText(incidents.criticalOpen), 'боевые оповещения', incidents.criticalOpen > 0 ? 'red' : 'muted'),
    analyticsRow('Опубликованные версии', numberText(updates.published), `${numberText(updates.draft)} черновиков`),
    analyticsRow('Публичные VPN-узлы', numberText(servers.publicServers), `${numberText(servers.managedPublicReady)} управляемых готово`),
    analyticsRow('Проблемы VPN-узлов за 24ч', numberText(servers.healthFailures24h), `${numberText(servers.healthEndpointsObserved)} наблюдений`, servers.healthFailures24h > 0 ? 'yellow' : 'muted'),
    analyticsRow('События входа за 24ч', numberText(auth.events24h), `${numberText(auth.failed24h)} неудачных`, auth.failed24h > 0 ? 'yellow' : 'muted'),
    analyticsRow('Оповещения админки', readiness.alerts?.ready ? 'готово' : 'нужна настройка', readiness.alerts?.message || 'Оповещения Telegram об инцидентах'),
    analyticsRow('Готовность продукта', readiness.product?.productionReady ? 'готово' : 'нужна настройка', readiness.product?.summary?.message || ''),
    renderBreakdown('Серверы по протоколам', servers.byProtocol),
  ].join('');

  $('analyticsTrendsPanel').innerHTML = [
    renderTrendTable('Новые пользователи', analytics.timeseries?.users),
    renderTrendTable('Заказы', analytics.timeseries?.ordersCount),
    renderTrendTable('Выручка, ₽', analytics.timeseries?.ordersRevenue),
    renderTrendTable('Обращения в поддержку', analytics.timeseries?.supportReports),
  ].join('');
}

function statusDot(ok, warning = false) {
  if (ok) return '<span class="dot"></span>';
  if (warning) return '<span class="dot yellow"></span>';
  return '<span class="dot red"></span>';
}

function renderAdvertisingReadiness() {
  const payload = state.loaded.advertisingReadiness;
  const containers = [
    $('advertisingReadinessSummary'),
    $('readinessAdvertisingReadiness'),
  ].filter(Boolean);
  if (!containers.length) return;

  if (!payload) {
    containers.forEach((container) => {
      container.innerHTML = '<p class="muted">Готовность к рекламе пока не загружена.</p>';
    });
    return;
  }

  const summary = payload.summary || {};
  const publicReady = Boolean(payload.publicAdvertisingReady);
  const paidReady = Boolean(payload.paidTrafficReady);
  const demoReady = Boolean(payload.privateDemoReady);
  const pillClass = paidReady ? '' : publicReady || demoReady ? 'yellow' : 'red';
  const stateLabel = paidReady
    ? 'можно рекламировать'
    : publicReady
      ? 'можно ограниченно'
      : demoReady
        ? 'только личный показ'
        : 'нельзя рекламировать';
  const blockers = [
    ...(payload.publicAdBlockers || []),
    ...(payload.paidTrafficBlockers || []),
  ];
  const uniqueBlockers = blockers.filter((item, index, list) => (
    list.findIndex((candidate) => candidate.code === item.code) === index
  ));
  const blockersHtml = uniqueBlockers.length
    ? `
      <div class="check-list compact-list">
        ${uniqueBlockers.slice(0, 5).map((gate) => `
          <div class="check-row">
            ${statusDot(false, gate.severity !== 'critical')}
            <div>
              <strong>${escapeUi(gate.title || gate.code)}</strong>
              <span>${escapeUi(gate.nextAction || gate.message)}</span>
            </div>
            <span class="status-pill ${gate.severity === 'critical' ? 'red' : 'yellow'}">${gate.severity === 'critical' ? 'блокер' : 'проверить'}</span>
          </div>
        `).join('')}
      </div>
    `
    : '';

  const html = `
    <div class="status-row">
      ${statusDot(paidReady, publicReady || demoReady)}
      <div>
        <strong>${escapeUi(summary.message, 'Готовность к рекламе')}</strong>
        <span>
          публичная реклама: ${publicReady ? 'да' : 'нет'}
          · платный трафик: ${paidReady ? 'да' : 'нет'}
          · личный показ: ${demoReady ? 'да' : 'нет'}
        </span>
        ${summary.nextAction ? `<span>${escapeUi(summary.nextAction)}</span>` : ''}
      </div>
      <span class="status-pill ${pillClass}">${stateLabel}</span>
    </div>
    ${blockersHtml}
  `;

  containers.forEach((container) => {
    container.innerHTML = html;
  });
}

function renderLaunchReadiness() {
  const payload = state.loaded.launchReadiness;
  const containers = [
    $('launchReadinessSummary'),
    $('readinessLaunchReadiness'),
  ].filter(Boolean);
  if (!containers.length) return;

  if (!payload) {
    containers.forEach((container) => {
      container.innerHTML = '<p class="muted">Сводка готовности к запуску пока не загружена.</p>';
    });
    return;
  }

  const summary = payload.summary || {};
  const critical = payload.criticalBlockers || [];
  const warnings = payload.warnings || [];
  const pending = [...critical, ...warnings];
  const publicReady = Boolean(payload.publicLaunchReady);
  const productionReady = Boolean(payload.productionReady);
  const stateLabel = productionReady
    ? 'готово'
    : publicReady
      ? 'предупреждения'
      : 'критично';
  const pillClass = productionReady ? '' : publicReady ? 'yellow' : 'red';
  const nextAction = summary.nextCriticalAction || summary.nextWarningAction || 'Критичных действий не осталось.';

  const pendingHtml = pending.length
    ? `
      <div class="check-list compact-list">
        ${pending.slice(0, 6).map((gate) => `
          <div class="check-row">
            ${statusDot(false, gate.severity !== 'critical')}
            <div>
              <strong>${escapeUi(gate.title)}</strong>
              <span>${escapeUi(gate.nextAction || gate.message)}</span>
            </div>
            <span class="status-pill ${gate.severity === 'critical' ? 'red' : 'yellow'}">
              ${gate.severity === 'critical' ? 'критично' : 'предупреждение'}
            </span>
          </div>
        `).join('')}
      </div>
    `
    : '<p class="muted">Все проверки запуска зелёные.</p>';

  const ownerActions = payload.nextOwnerActions || [];
  const ownerHtml = ownerActions.length
    ? `<div class="mini-list">${ownerActions.slice(0, 4).map((action) => `<span>${escapeUi(action.title || action.code)}: ${escapeUi(action.ownerStatusTitle || action.status)}</span>`).join('')}</div>`
    : '';

  const html = `
    <div class="status-row">
      ${statusDot(productionReady, publicReady && !productionReady)}
      <div>
        <strong>${escapeUi(summary.message, 'Нет данных по запуску')}</strong>
        <span>
          Готово: ${escapeHtml(summary.ready, '0')}/${escapeHtml(summary.total, '0')}
          · критично: ${escapeHtml(summary.critical, '0')}
          · предупреждения: ${escapeHtml(summary.warnings, '0')}
        </span>
        <span>${escapeUi(nextAction)}</span>
      </div>
      <span class="status-pill ${pillClass}">${stateLabel}</span>
    </div>
    ${pendingHtml}
    ${ownerHtml}
  `;

  containers.forEach((container) => {
    container.innerHTML = html;
  });
}

function renderLaunchClosurePlan() {
  const plan = state.loaded.launchClosurePlan || state.loaded.overview?.launchClosurePlan;
  const containers = [
    $('launchClosurePlanSummary'),
    $('readinessClosurePlan'),
  ].filter(Boolean);
  if (!containers.length) return;

  if (!plan) {
    containers.forEach((container) => {
      container.innerHTML = '<p class="muted">План закрытия запуска пока не загружен.</p>';
    });
    return;
  }

  const summary = plan.summary || {};
  const ownerInputs = plan.ownerInputsNeeded || [];
  const codeOwned = plan.codeOwnedActions || [];
  const operational = plan.operationalReviewActions || [];
  const finalHandoff = plan.finalHandoffOnlyActions || [];
  const nextAutonomous = plan.nextAutonomousActions || [];
  const ownerHtml = ownerInputs
    .slice(0, 5)
    .map((item) => `
      <span class="status-pill ${item.secretInputExpected ? 'red' : 'yellow'}">
        ${escapeUi(item.title || item.code)}${item.secretInputExpected ? ' · секрет' : ''}
      </span>
    `)
    .join('');
  const autonomousHtml = nextAutonomous
    .slice(0, 5)
    .map((item) => `<span class="status-pill yellow">${escapeUi(item.title || item.code)}</span>`)
    .join('');
  const finalHtml = finalHandoff
    .slice(0, 3)
    .map((item) => `<span class="status-pill muted">${escapeUi(item.title || item.code)}</span>`)
    .join('');

  const html = `
    <div class="status-row">
      ${statusDot(Boolean(plan.productionReady), plan.publicLaunchReady || summary.ownerBlocked > 0)}
      <div>
        <strong>${escapeUi(summary.message, 'План закрытия запуска')}</strong>
        <span>
          готово=${escapeHtml(summary.ready, '0')}/${escapeHtml(summary.total, '0')},
          владелец=${escapeHtml(summary.ownerBlocked, '0')},
          код=${escapeHtml(summary.codeOwned, '0')},
          операции=${escapeHtml(summary.operationalReview, '0')},
          финал=${escapeHtml(summary.finalHandoffOnly, '0')}
        </span>
        ${
          summary.nextAutonomousAction
            ? `<span>${escapeUi(summary.nextAutonomousAction)}</span>`
            : ''
        }
      </div>
      <span class="status-pill ${plan.productionReady ? '' : summary.ownerBlocked ? 'red' : 'yellow'}">
        ${escapeUi(plan.state || 'pending')}
      </span>
    </div>
    <div class="external-action-meta">
      <span>Что нужно от владельца:</span>
      <div class="pill-list">${ownerHtml || '<span class="muted">нет</span>'}</div>
    </div>
    <div class="external-action-meta">
      <span>Автономно/операции:</span>
      <div class="pill-list">${autonomousHtml || '<span class="muted">нет ближайшего блокера по коду</span>'}</div>
    </div>
    <div class="external-action-meta">
      <span>Финальная передача:</span>
      <div class="pill-list">${finalHtml || '<span class="muted">нет</span>'}</div>
    </div>
    <p class="muted">${escapeHtml(plan.policy?.secretPolicy || 'Секретные значения никогда не возвращаются в админку.')}</p>
  `;

  containers.forEach((container) => {
    container.innerHTML = html;
  });
}

function renderOwnerLaunchPacket() {
  const packet = state.loaded.launchOwnerPacket;
  const container = $('ownerLaunchPacketSummary');
  if (!container) return;

  if (!packet) {
    container.innerHTML = '<p class="muted">Пакет запуска для владельца пока не загружен.</p>';
    return;
  }

  const summary = packet.summary || {};
  const commands = packet.commands || [];
  const ownerBlockers = packet.ownerBlockers || [];
  const ownerActions = packet.ownerActions || [];
  const checks = packet.afterApplyChecks || [];
  const commandsHtml = commands
    .map((command) => `
      <div class="external-action-meta">
        <span>${escapeUi(command.title || command.code)}:</span>
        <div>
          <div class="code-list"><code>${escapeHtml(command.command)}</code></div>
          <span class="status-pill ${command.secret ? 'red' : 'muted'}">${command.secret ? 'ввод секрета' : 'без секрета'}</span>
          <span class="status-pill ${command.mutationFree ? 'muted' : 'yellow'}">${command.mutationFree ? 'без изменений' : 'применяет изменения'}</span>
          <span class="muted">${escapeHtml(command.when || '')}</span>
        </div>
      </div>
    `)
    .join('');
  const ownerBlockersHtml = ownerBlockers
    .slice(0, 6)
    .map((item) => `
      <span class="status-pill ${item.secretInputExpected ? 'red' : 'yellow'}">
        ${escapeUi(item.title || item.code)}${item.secretInputExpected ? ' · секрет' : ''}
      </span>
    `)
    .join('');
  const ownerActionsHtml = ownerActions
    .slice(0, 6)
    .map((action) => {
      const inputs = (action.ownerInputs || [])
        .slice(0, 5)
        .map((item) => `<span class="status-pill ${item.secret ? 'red' : 'muted'}">${escapeUi(item.name || item.envKey || 'поле')}${item.secret ? ' · секрет' : ''}</span>`)
        .join('');
      return `
        <div class="check-row">
          ${statusDot(Boolean(action.ready), !action.ready)}
          <div>
            <strong>${escapeUi(action.title || action.code)}</strong>
            <span>${escapeUi(action.ownerAction || action.message || '')}</span>
            <div class="pill-list">${inputs || '<span class="muted">от владельца ничего не требуется</span>'}</div>
          </div>
          <span class="status-pill ${action.secretInputExpected ? 'red' : 'yellow'}">${action.secretInputExpected ? 'секрет' : 'владелец'}</span>
        </div>
      `;
    })
    .join('');
  const checksHtml = checks
    .slice(0, 10)
    .map((check) => `<span class="status-pill muted">${escapeUi(check)}</span>`)
    .join('');

  container.innerHTML = `
    <div class="external-action-card ${packet.publicLaunchReady ? 'ready' : 'pending'}">
      <div class="external-action-head">
        ${statusDot(Boolean(packet.productionReady), Boolean(packet.publicLaunchReady) || summary.ownerBlocked > 0)}
        <div>
        <strong>${escapeUi(summary.message, 'Пакет запуска для владельца')}</strong>
          <span>
            команды=${escapeHtml(summary.commands, '0')},
            действия владельца=${escapeHtml(summary.pendingOwnerActions, '0')},
            dns=${escapeHtml(summary.dnsRecords, '0')},
            безопасные значения=${escapeHtml(summary.safeDefaults, '0')}
          </span>
        </div>
        <span class="status-pill ${packet.safeNoSecretExposure ? '' : 'red'}">${packet.safeNoSecretExposure ? 'без секретов' : 'проверить'}</span>
      </div>
      ${commandsHtml || '<p class="muted">Команды пакета владельца пока не загружены.</p>'}
      <div class="external-action-meta">
        <span>Блокеры запуска:</span>
        <div class="pill-list">${ownerBlockersHtml || '<span class="muted">нет</span>'}</div>
      </div>
      ${
        ownerActionsHtml
          ? `<div class="check-list compact-list">${ownerActionsHtml}</div>`
          : '<p class="muted">Все действия владельца закрыты.</p>'
      }
      <div class="external-action-meta">
        <span>После применения:</span>
        <div class="pill-list">${checksHtml || '<span class="muted">смотри самопроверку готовности</span>'}</div>
      </div>
      <p class="muted">${escapeHtml(packet.policy?.secretPolicy || 'Секретные значения никогда не возвращаются в админку.')}</p>
    </div>
  `;
}

function renderSiteReadiness() {
  const site =
    state.loaded.siteReadiness ||
    state.loaded.readiness?.publicSiteReadiness ||
    state.loaded.overview?.publicSiteReadiness;
  const containers = [
    $('siteReadinessSummary'),
    $('readinessSiteReadiness'),
  ].filter(Boolean);
  if (!containers.length) return;

  if (!site) {
    containers.forEach((container) => {
      container.innerHTML = '<p class="muted">Готовность публичного сайта пока не загружена.</p>';
    });
    return;
  }

  const summary = site.summary || {};
  const failedChecks = (site.checks || []).filter((check) => !check.ok);
  const downloads = site.downloadTargets || {};
  const yookassa = site.yookassaUrls || {};
  const bannedMatches = site.bannedPhraseMatches || [];
  const html = `
    <div class="status-row">
      ${statusDot(Boolean(site.productionReady), !site.productionReady)}
      <div>
        <strong>${escapeUi(summary.message, 'Готовность публичного сайта')}</strong>
        <span>
          сайт=${escapeHtml(site.siteUrl || '—')}
          · зелёные=${escapeHtml(summary.green, '0')}
          · жёлтые=${escapeHtml(summary.yellow, '0')}
        </span>
        <span>
          загрузки: Windows=${boolLabel(downloads.windowsConfigured)},
          Android=${boolLabel(downloads.androidConfigured)},
          iOS=${boolLabel(downloads.iosConfigured)}
        </span>
        <span>
          YooKassa: ${escapeHtml(yookassa.returnUrl || 'return URL не задан')}
          · ${escapeHtml(yookassa.webhookUrl || 'webhook URL не задан')}
        </span>
      </div>
      <span class="status-pill ${site.productionReady ? '' : 'yellow'}">
        ${site.productionReady ? 'сайт готов' : 'нужно действие'}
      </span>
    </div>
    ${
      bannedMatches.length
        ? `<div class="mini-list danger-text">${bannedMatches.map((item) => `<span>${escapeHtml(item.path)}: ${escapeHtml(item.phrase)}</span>`).join('')}</div>`
        : ''
    }
    ${
      failedChecks.length
        ? `<div class="check-list compact-list">${
            failedChecks.slice(0, 8).map((check) => `
              <div class="check-row">
                  ${statusDot(false, true)}
                <div>
                  <strong>${escapeUi(check.title || check.code)}</strong>
                  <span>${escapeUi(check.message)}</span>
                </div>
                <span class="status-pill yellow">нужно действие</span>
              </div>
            `).join('')
          }</div>`
        : '<p class="muted">Проверка публичного сайта зелёная.</p>'
    }
  `;

  containers.forEach((container) => {
    container.innerHTML = html;
  });
}

function renderServiceStatus() {
  const monitoring = state.loaded.monitoring;
  const services = state.loaded.services;
  const checks = [];

  if (monitoring?.checks) {
    for (const check of monitoring.checks) {
      checks.push({
        title: check.title || check.code,
        message: check.message || check.value || '',
        ok: Boolean(check.ok),
        warning: check.status === 'yellow',
      });
    }
  }

  if (services?.checks) {
    for (const check of services.checks) {
      checks.push({
        title: check.title || check.code,
        message: check.message || check.url || '',
        ok: Boolean(check.ok),
        warning: check.status === 'yellow',
      });
    }
  }

  $('serviceStatusList').innerHTML =
    checks
      .slice(0, 10)
      .map(
        (check) => `
          <div class="status-row">
            ${statusDot(check.ok, check.warning)}
            <div>
              <strong>${escapeUi(check.title)}</strong>
              <span>${escapeUi(check.message, '')}</span>
            </div>
            <span class="status-pill ${check.ok ? '' : check.warning ? 'yellow' : 'red'}">
              ${check.ok ? 'ок' : check.warning ? 'внимание' : 'ошибка'}
            </span>
          </div>
        `,
      )
      .join('') || '<p class="muted">Нет данных мониторинга.</p>';
}

function renderNetworkReadiness() {
  const network = state.loaded.networkReadiness || state.loaded.overview?.apiVpnEndpointSeparationReadiness;
  const containers = [
    $('networkReadinessSummary'),
    $('readinessNetworkReadiness'),
  ].filter(Boolean);
  if (!containers.length) return;

  if (!network) {
    containers.forEach((container) => {
      container.innerHTML = '<p class="muted">Проверка разделения сайта и VPN-узла ещё не загружена.</p>';
    });
    return;
  }

  const overlap = network.overlapIps || [];
  const apiHosts = network.publicApiHosts || [];
  const apiIps = Object.entries(network.publicApiHostIps || {})
    .map(([host, ips]) => `${host}: ${(ips || []).join(', ') || 'не резолвится'}`)
    .join('; ');
  const checks = network.checks || [];
  const checkTitles = {
    public_api_https: 'Публичные URL работают через HTTPS',
    public_api_dns_resolves: 'DNS сайта/API резолвится',
    vpn_endpoint_resolves: 'VPN-узел резолвится',
    api_vpn_ip_split: 'Сайт/API и VPN-узел на разных IP',
  };
  const primaryMessage = network.productionReady
    ? 'Сайт/API отделены от VPN-узла.'
    : 'Сайт/API сейчас используют тот же IP, что и VPN-узел.';
  const requiredActions = network.requiredActions || [];
  const splitPayload = state.loaded.networkSplitPlan || {};
  const migrationPlan = network.migrationPlan || splitPayload.migrationPlan || splitPayload;
  const phases = migrationPlan?.phases || [];
  const dnsRecords = migrationPlan?.dnsRecords || [];
  const targetArchitecture = migrationPlan?.targetArchitecture || {};
  const preflight = migrationPlan?.preflight || {};
  const planHtml = migrationPlan?.targetArchitecture
    ? `
      <div class="check-list compact-list">
        <div class="check-row">
          ${statusDot(Boolean(migrationPlan.ready), Boolean(migrationPlan.requiresOwnerAction))}
          <div>
            <strong>План разделения API/сайта и VPN</strong>
            <span>
              API: ${escapeHtml(targetArchitecture.publicApiHost || 'api.greenvpn.pro')}
              · VPN: ${escapeHtml(targetArchitecture.vpnEndpointHost || 'nl1.vpn.greenvpn.pro')}
              -> ${escapeHtml(targetArchitecture.vpnEndpointTarget || '—')}
            </span>
          </div>
          <span class="status-pill ${migrationPlan.ready ? '' : 'yellow'}">
            ${migrationPlan.ready ? 'готово' : 'есть шаги'}
          </span>
        </div>
        ${phases.slice(0, 5).map((phase) => `
          <div class="check-row">
            ${statusDot(phase.status === 'done', phase.status !== 'blocked')}
            <div>
              <strong>${escapeUi(phase.title || phase.code)}</strong>
              <span>${escapeUi(phase.details || '')}</span>
            </div>
            <span class="status-pill ${phase.status === 'blocked' ? 'red' : phase.status === 'done' ? '' : 'yellow'}">
              ${escapeUi(phase.status || 'pending')}
            </span>
          </div>
        `).join('')}
      </div>
      ${
        dnsRecords.length
          ? `<div class="mini-list">${dnsRecords.map((record) => `
              <span>
                DNS ${escapeHtml(record.name)} -> ${escapeHtml(record.target)}
                (${escapeUi(record.status)})
              </span>
            `).join('')}</div>`
          : ''
      }
      ${
        preflight.command
          ? `<div class="external-action-meta">
              <span>Предварительная проверка:</span>
              <div class="code-list"><code>${escapeHtml(preflight.command)}</code></div>
            </div>
            <p class="muted">${escapeUi(preflight.when || 'Запустить после подготовки отдельного API/site IP и DNS endpoint.')}</p>`
          : ''
      }
    `
    : '';

  const html = `
    <div class="status-row">
      ${statusDot(Boolean(network.productionReady), !network.productionReady)}
      <div>
        <strong>${escapeHtml(primaryMessage)}</strong>
        <span>
          API: ${escapeHtml(apiHosts.join(', ') || '—')}
          · VPN-узел: ${escapeHtml(network.vpnEndpointHost || '—')}
        </span>
        <span>
          IP API: ${escapeHtml(apiIps || '—')}
          · IP VPN-узла: ${escapeHtml((network.vpnEndpointIps || []).join(', ') || '—')}
        </span>
        ${
          overlap.length
            ? `<span class="danger-text">Пересечение IP: ${escapeHtml(overlap.join(', '))}</span>`
            : ''
        }
      </div>
      <span class="status-pill ${network.productionReady ? '' : 'red'}">
        ${network.productionReady ? 'готово' : 'разделить IP'}
      </span>
    </div>
    ${
      requiredActions.length
        ? `<div class="mini-list">${requiredActions.map((action) => `<span>${escapeUi(action)}</span>`).join('')}</div>`
        : ''
    }
    ${planHtml}
    ${
      checks.length
        ? `<div class="check-list compact-list">${
            checks.map((check) => `
              <div class="check-row">
                  ${statusDot(Boolean(check.ok), !check.ok)}
                  <div>
                    <strong>${escapeUi(checkTitles[check.code] || check.code)}</strong>
                    <span>${escapeUi(check.message)}</span>
                  </div>
                  <span class="status-pill ${check.ok ? '' : 'yellow'}">${check.ok ? 'ок' : 'нужно действие'}</span>
                </div>
              `).join('')
          }</div>`
        : ''
    }
  `;

  containers.forEach((container) => {
    container.innerHTML = html;
  });
}

function renderReadiness() {
  const readiness = state.loaded.readiness;
  const summary = readiness?.summary;
  $('readinessSummary').innerHTML = `
    <div class="status-row">
      ${statusDot(Boolean(readiness?.productionReady), summary?.yellow > 0)}
      <div>
        <strong>${escapeUi(summary?.message, 'Нет данных')}</strong>
              <span>зелёные=${escapeHtml(summary?.green, '0')}, жёлтые=${escapeHtml(summary?.yellow, '0')}</span>
      </div>
      <span class="status-pill ${readiness?.productionReady ? '' : 'yellow'}">
        ${readiness?.productionReady ? 'готово к запуску' : 'нужна настройка'}
      </span>
    </div>
  `;

  const checks = readiness?.checks || [];
  $('readinessList').innerHTML =
    checks
      .map(
        (check) => `
          <div class="check-row">
            ${statusDot(Boolean(check.ok), !check.ok)}
            <div>
              <strong>${escapeUi(check.title)}</strong>
              <span>${escapeUi(check.message)}</span>
            </div>
            <span class="status-pill ${check.ok ? '' : 'yellow'}">${check.ok ? 'готово' : 'нужно действие'}</span>
          </div>
        `,
      )
      .join('') || '<p>Список проверок пока пуст.</p>';

  renderExternalActions();
  renderAlertEvents();
}

function alertStatusPillClass(status) {
  if (status === 'sent') return '';
  if (status === 'skipped') return 'yellow';
  return status === 'failed' ? 'red' : 'muted';
}

function renderAlertEvents() {
  const container = $('alertEventsList');
  if (!container) return;
  const events = state.loaded.alertEvents || [];
  container.innerHTML =
    events
      .map(
        (event) => `
          <div class="status-row">
            ${statusDot(event.status === 'sent', event.status === 'skipped')}
            <div>
              <strong>#${escapeHtml(event.id)} · ${escapeHtml(event.incidentKey || `incident:${event.incidentId}`)}</strong>
              <span>${escapeUi(event.reason || 'оповещение')} · ${escapeUi(event.provider)} · ${escapeHtml(shortDate(event.createdAt))}</span>
              <span class="muted">${escapeUi(event.error || event.messagePreview || '')}</span>
            </div>
            <span class="status-pill ${alertStatusPillClass(event.status)}">${escapeUi(event.status)}</span>
          </div>
        `,
      )
      .join('') || '<p class="muted">История оповещений пока пустая.</p>';
}

function ownerActionWorkflow() {
  const workflow = state.loaded.externalActions?.workflow;
  if (workflow?.statuses?.length) return workflow;
  return {
    statuses: [
      { code: 'todo', title: 'Нужно сделать' },
      { code: 'in_progress', title: 'В работе' },
      { code: 'waiting_owner', title: 'Ждём владельца' },
      { code: 'waiting_provider', title: 'Ждём провайдера' },
      { code: 'ready_to_apply', title: 'Данные готовы' },
      { code: 'done', title: 'Закрыто' },
      { code: 'blocked', title: 'Заблокировано' },
      { code: 'not_needed', title: 'Не требуется' },
    ],
  };
}

function ownerActionStatusTitle(status) {
  const item = ownerActionWorkflow().statuses.find((entry) => entry.code === status);
  return item?.title || status || 'Нужно сделать';
}

function ownerActionStatusPillClass(status) {
  if (status === 'done' || status === 'not_needed' || status === 'ready_to_apply') return '';
  if (status === 'blocked') return 'red';
  if (status === 'in_progress' || status === 'waiting_provider' || status === 'waiting_owner') return 'yellow';
  return 'muted';
}

function ownerActionStatusOptions(selected) {
  return workflowOptionsHtml(ownerActionWorkflow().statuses, selected || 'todo');
}

const OWNER_NOTE_CLIENT_SECRET_PATTERNS = [
  ['private_key_block', /-----BEGIN [A-Z ]*PRIVATE KEY-----/i],
  ['wireguard_private_key_assignment', /\[interface\][\s\S]{0,800}\bprivate\s*key\b\s*=/i],
  ['key_assignment', /\b(private\s*key|preshared\s*key|wireguard\s*private\s*key)\b\s*[:=]/i],
  ['auth_header', /\bbearer\s+[A-Za-z0-9._~+/=-]{10,}/i],
  ['sensitive_assignment', /\b(authorization|x-admin-token|password|secret|token|api[_-]?key|api[_-]?id|chat[_-]?id)\b\s*[:=]\s*\S+/i],
  ['sensitive_env_assignment', /\b[A-Z0-9_]*(?:SECRET|TOKEN|PASSWORD|PRIVATE_KEY|PRESHARED_KEY|BOT_TOKEN|API_KEY|API_ID|CHAT_ID)[A-Z0-9_]*\s*[:=]\s*\S+/],
];

function ownerNoteSecretFindings(note) {
  const text = safeText(note, '').trim();
  if (!text) return [];
  return OWNER_NOTE_CLIENT_SECRET_PATTERNS
    .filter(([, pattern]) => pattern.test(text))
    .map(([code]) => code);
}

function ownerNoteGuardHint(findings = []) {
  if (!findings.length) {
    return 'Ключи, токены, пароли и секреты провайдеров вводить только через серверный env-скрипт.';
  }
  return `Похоже на секретные данные: ${findings.slice(0, 5).join(', ')}. Удали значения из заметки.`;
}

function renderExternalActions() {
  const payload = state.loaded.externalActions;
  const list = $('externalActionsList');
  if (!list) return;

  const actions = payload?.actions || [];
  const summary = payload?.summary;
  const blocking = payload?.blockingSummary || {};
  const ownerPolicy = payload?.ownerActionPolicy || payload?.workflow?.policy || {};
  const bundle = payload?.setupBundle || {};
  const canManageReadiness = can('readiness.manage');
  if (!actions.length) {
    list.innerHTML = '<p class="muted">Чеклист внешних сервисов пока не загружен.</p>';
    return;
  }

  const summaryHtml = `
    <div class="check-row external-summary">
      ${statusDot(Boolean(payload?.productionReady), !payload?.productionReady)}
      <div>
        <strong>${escapeUi(summary?.message, 'Внешние действия не загружены')}</strong>
        <span>готово=${escapeHtml(summary?.ready, '0')}, ожидает=${escapeHtml(summary?.pending, '0')}, владелец сделал=${escapeHtml(summary?.ownerDone, '0')}, заблокировано=${escapeHtml(summary?.ownerBlocked, '0')}, расхождений=${escapeHtml(summary?.doneButBackendNotReady, '0')}</span>
      </div>
      <span class="status-pill ${payload?.productionReady ? '' : 'yellow'}">
        ${payload?.productionReady ? 'готово' : 'нужно действие'}
      </span>
    </div>
  `;

  const ownerPolicyHtml = `
    <div class="check-row external-summary">
      ${statusDot(Boolean(blocking.safeToProceed), !blocking.safeToProceed)}
      <div>
        <strong>Журнал действий владельца</strong>
        <span>готово к применению=${escapeHtml((blocking.readyToApplyCodes || []).length, '0')}, ждёт=${escapeHtml((blocking.waitingCodes || []).length, '0')}, нет заметок=${escapeHtml((blocking.missingOwnerNoteCodes || []).length, '0')}</span>
        <span>защита заметок=${ownerPolicy.serverEnforced ? 'на сервере' : 'только текст'}, заблокированных шаблонов=${escapeHtml((ownerPolicy.blockedNotePatternCodes || []).length, '0')}</span>
      </div>
      <span class="status-pill ${ownerPolicy.serverEnforced ? (blocking.safeToProceed ? '' : 'yellow') : 'red'}">${ownerPolicy.serverEnforced ? (blocking.safeToProceed ? 'чисто' : 'проверить') : 'защита выключена'}</span>
    </div>
    <p class="muted">${escapeHtml(ownerPolicy.secretPolicy || 'В заметках владельца нельзя хранить секреты.')}</p>
  `;

  const setupBundleHtml = bundle.applyCommand || bundle.readinessCommand
    ? `
      <div class="external-action-card ready">
        <div class="external-action-head">
          ${statusDot(true, false)}
          <div>
            <strong>Пакет настройки владельца</strong>
            <span>${escapeHtml(bundle.secretPolicy || 'Секреты хранятся только на сервере.')}</span>
          </div>
          <span class="status-pill">env только на сервере</span>
        </div>
        <div class="external-action-meta">
          <span>Применить:</span>
          <div class="code-list"><code>${escapeHtml(bundle.applyCommand || '')}</code></div>
        </div>
        <div class="external-action-meta">
          <span>Проверить:</span>
          <div class="code-list"><code>${escapeHtml(bundle.readinessCommand || '')}</code></div>
        </div>
        <div class="external-action-meta">
          <span>DNS:</span>
          <div class="pill-list">
            ${(bundle.dnsRecords || [])
              .map((record) => `<span class="status-pill muted">${escapeUi(record.type)} ${escapeHtml(record.host)}</span>`)
              .join('') || '<span class="muted">нет</span>'}
          </div>
        </div>
      </div>
    `
    : '';

  const actionsHtml = actions
    .map((action) => {
      const envKeys = (action.envKeys || [])
        .map((key) => `<code>${escapeHtml(key)}</code>`)
        .join('');
      const blocks = (action.blocks || [])
        .map((item) => `<span class="status-pill muted">${escapeUi(item)}</span>`)
        .join('');
      const ownerInputs = (action.ownerInputs || [])
        .map((item) => {
          const title = item.name || item.envKey || 'поле';
          const suffix = item.secret ? ' · секрет' : (item.optional ? ' · необязательно' : '');
          const hint = item.example ? ` title="${escapeHtml(item.example)}"` : '';
          return `<span class="status-pill ${item.secret ? 'red' : 'muted'}"${hint}>${escapeHtml(title)}${escapeHtml(suffix)}</span>`;
        })
        .join('');
      const applySteps = (action.applySteps || [])
        .map((step) => `<span class="muted">${escapeUi(step)}</span>`)
        .join('');
      const verifySteps = (action.verifySteps || [])
        .map((step) => `<span class="muted">${escapeUi(step)}</span>`)
        .join('');
      const ownerStatus = action.ownerStatus || (action.ready ? 'done' : 'todo');
      const ownerNote = action.ownerNote || '';
      const ownerMeta = action.ownerUpdatedAt
        ? `Обновил: ${escapeHtml(action.ownerUpdatedBy, 'admin')} · ${escapeHtml(shortDate(action.ownerUpdatedAt))}`
        : 'Статус владельца ещё не сохранялся.';
      const noteFindings = ownerNoteSecretFindings(ownerNote);
      const ownerControl = canManageReadiness
        ? `
          <div class="owner-action-control">
            <label>
              Статус подключения
              <select data-owner-action-status="${escapeHtml(action.code)}">
                ${ownerActionStatusOptions(ownerStatus)}
              </select>
            </label>
            <label>
              Заметка без секретов
              <textarea data-owner-action-note="${escapeHtml(action.code)}" placeholder="Например: домен куплен, MX/SPF/DKIM внесены, ждём распространение DNS.">${escapeHtml(ownerNote, '')}</textarea>
              <span class="muted">${escapeHtml(ownerNoteGuardHint(noteFindings))}</span>
            </label>
            <button class="small-button" data-owner-action-save="${escapeHtml(action.code)}">Сохранить статус</button>
          </div>
        `
        : `
          <div class="owner-action-note">
            <span class="muted">${escapeHtml(ownerNote || 'Заметки владельца пока нет.')}</span>
          </div>
        `;
      return `
        <div class="external-action-card ${action.ready ? 'ready' : 'pending'}" data-owner-action-card="${escapeHtml(action.code)}">
          <div class="external-action-head">
            ${statusDot(Boolean(action.ready), !action.ready)}
            <div>
              <strong>${escapeUi(action.title)}</strong>
              <span>${escapeUi(action.message || action.ownerAction)}</span>
            </div>
            <div class="external-action-badges">
              <span class="status-pill ${action.ready ? '' : 'yellow'}">${action.ready ? 'готово' : 'ждёт владельца'}</span>
              <span class="status-pill ${ownerActionStatusPillClass(ownerStatus)}">${escapeHtml(ownerActionStatusTitle(ownerStatus))}</span>
              ${action.secret ? '<span class="status-pill red">секрет</span>' : '<span class="status-pill muted">без секрета</span>'}
            </div>
          </div>
          <p>${escapeUi(action.ownerAction)}</p>
          <div class="external-action-meta">
            <span>Переменные окружения:</span>
            <div class="code-list">${envKeys || '<span class="muted">нет</span>'}</div>
          </div>
          <div class="external-action-meta">
            <span>Блокирует:</span>
            <div class="pill-list">${blocks || '<span class="muted">ничего</span>'}</div>
          </div>
          <div class="external-action-meta">
            <span>Что нужно от владельца:</span>
            <div class="pill-list">${ownerInputs || '<span class="muted">нет</span>'}</div>
          </div>
          <div class="external-action-meta">
            <span>Применить:</span>
            <div>${applySteps || '<span class="muted">смотри пакет настройки</span>'}</div>
          </div>
          <div class="external-action-meta">
            <span>Проверить:</span>
            <div>${verifySteps || '<span class="muted">смотри проверку готовности</span>'}</div>
          </div>
          <div class="external-action-meta">
            <span>Владелец:</span>
            <div>${ownerMeta}</div>
          </div>
          ${ownerControl}
        </div>
      `;
    })
    .join('');

  list.innerHTML = `
    ${summaryHtml}
    ${ownerPolicyHtml}
    ${setupBundleHtml}
    <p class="muted">${escapeUi(payload.secretPolicy, '')}</p>
    ${actionsHtml}
  `;
}

async function saveOwnerActionStatus(code) {
  if (!requirePermission('readiness.manage', 'Сохранение внешнего действия')) return;
  const card = document.querySelector(`[data-owner-action-card="${code}"]`);
  const statusInput = card?.querySelector(`[data-owner-action-status="${code}"]`);
  const noteInput = card?.querySelector(`[data-owner-action-note="${code}"]`);
  if (!statusInput) {
    setNotice('Не удалось найти форму внешнего действия.', true);
    return;
  }
  const note = noteInput?.value || '';
  const noteFindings = ownerNoteSecretFindings(note);
  if (noteFindings.length) {
    setNotice(`Заметка похожа на секретные данные (${noteFindings.slice(0, 5).join(', ')}). Удали значение и оставь только статус.`, true);
    noteInput?.focus();
    return;
  }
  try {
    const result = await apiPost(`/api/v1/admin/external-actions/${encodeURIComponent(code)}`, {
      status: statusInput.value,
      note,
    });
    state.loaded.externalActions = result.checklist || state.loaded.externalActions;
    renderExternalActions();
    setNotice('Статус внешнего подключения сохранён.');
  } catch (error) {
    setNotice(`Не удалось сохранить статус: ${error.message}`, true);
  }
}

function renderSupportTable() {
  const rows = state.loaded.support || [];
  const canManageSupport = can('support.manage');
  $('supportTable').innerHTML =
    rows
      .map(
        (report) => `
          <tr>
            <td>#${escapeHtml(report.id)}</td>
            <td>
              <strong>${escapeHtml(report.email)}</strong><br>
              <span class="muted">${escapeHtml(report.deviceUid)}</span>
            </td>
            <td>${escapeHtml(report.summary)}</td>
            <td><span class="status-pill muted">${escapeHtml(workflowTitle('categories', report.category))}</span></td>
            <td><span class="status-pill ${priorityPillClass(report.priority)}">${escapeHtml(workflowTitle('priorities', report.priority))}</span></td>
            <td>
              <span class="status-pill ${report.reviewPending ? 'yellow' : 'muted'}">${escapeUi(report.status)}</span><br>
              <span class="muted">
                ${report.reviewedAt ? `просмотрено: ${escapeHtml(shortDate(report.reviewedAt))}` : 'первый ответ нужен'}
                ${report.assignedTo ? `<br>исполнитель: ${escapeHtml(report.assignedTo)}` : ''}
              </span>
            </td>
            <td><span class="status-pill ${slaPillClass(report)}">${escapeHtml(shortDate(report.slaDueAt))}</span></td>
            <td>${escapeHtml(shortDate(report.createdAt))}</td>
            <td>
              <div class="row-actions">
                <button class="small-button" data-report-open="${report.id}">Открыть</button>
                ${
                  canManageSupport
                    ? `${report.reviewPending ? `<button class="small-button" data-report-review="${report.id}">В работу</button>` : ''}
                       <button class="small-button" data-report-resolve="${report.id}">Решено</button>`
                    : ''
                }
              </div>
            </td>
          </tr>
        `,
      )
      .join('') || '<tr><td colspan="9">Отчётов нет.</td></tr>';
}

function renderSupportActionsOverview() {
  const container = $('supportActionsList');
  if (!container) return;
  container.innerHTML = renderSupportActions(state.loaded.supportActions || []);
}

function renderSupportSlaSummary() {
  const container = $('supportSlaSummary');
  if (!container) return;
  const sla = state.loaded.supportSla;
  if (!sla) {
    container.innerHTML = '<p class="muted">Очередь SLA пока не загружена.</p>';
    return;
  }
  const summary = sla.summary || {};
  const items = [
    {
      title: 'Очередь SLA',
      message: `открыто=${numberText(summary.open)}, ждут разбора=${numberText(summary.reviewPending)}, без первого ответа=${numberText(summary.firstResponseMissing)}`,
      ok: !sla.attentionRequired,
      warning: Boolean(sla.attentionRequired),
      pill: sla.attentionRequired ? 'нужно внимание' : 'чисто',
    },
    {
      title: 'Просрочено / скоро срок',
      message: `просрочено=${numberText(summary.overdue)}, скоро срок=${numberText(summary.dueSoon)}, без SLA=${numberText(summary.missingSla)}`,
      ok: !summary.overdue && !summary.dueSoon && !summary.missingSla,
      warning: Boolean(summary.overdue || summary.dueSoon || summary.missingSla),
      pill: summary.overdue ? 'просрочено' : (summary.dueSoon ? 'скоро срок' : 'норма'),
    },
  ];
  container.innerHTML = items
    .map(
      (item) => `
        <div class="check-row">
          ${statusDot(item.ok, item.warning)}
          <div>
            <strong>${escapeUi(item.title)}</strong>
            <span>${escapeUi(item.message)}</span>
          </div>
          <span class="status-pill ${item.ok ? '' : 'yellow'}">${escapeUi(item.pill)}</span>
        </div>
      `,
    )
    .join('');
}

function incidentRunbooksHtml(incident) {
  const runbooks = (incident.suggestedRunbooks || []).slice(0, 3);
  if (!runbooks.length) {
    return '<span class="muted">Runbook: не найден</span>';
  }
  return runbooks
    .map((runbook) => `<span class="status-pill muted">${escapeUi(runbook.key || runbook.title)}</span>`)
    .join(' ');
}

function renderIncidentsTable() {
  const rows = state.loaded.incidents || [];
  const canManageIncidents = can('incidents.manage');
  $('incidentsTable').innerHTML =
    rows
      .map((incident) => {
        const canResolve = incident.status !== 'resolved';
        return `
          <tr>
            <td>#${escapeHtml(incident.id)}</td>
            <td><span class="status-pill ${incidentSeverityPillClass(incident.severity)}">${escapeHtml(incidentSeverityTitle(incident.severity))}</span></td>
            <td><span class="status-pill ${incidentStatusPillClass(incident.status)}">${escapeHtml(incidentStatusTitle(incident.status))}</span></td>
            <td>
              <strong>${escapeHtml(incident.affectedService || incident.source)}</strong><br>
              <span class="muted">${escapeHtml(incident.affectedEndpoint || incident.incidentKey)}</span>
            </td>
            <td>
              <strong>${escapeUi(incident.title)}</strong><br>
              <span class="muted">${escapeUi(incident.summary)}</span><br>
              ${incidentRunbooksHtml(incident)}
            </td>
            <td>
              <strong>${escapeHtml(incidentAssigneeLabel(incident))}</strong><br>
              <span class="muted">${incident.assignedAt ? `назначен: ${escapeHtml(shortDate(incident.assignedAt))}` : 'ответственный не выбран'}</span>
              ${
                canManageIncidents
                  ? `<select data-incident-assignee="${escapeHtml(incident.id)}">${incidentAssigneeOptionsHtml(incident.assigneeStaffId, incident.assignee || '')}</select>`
                  : ''
              }
            </td>
            <td>${escapeHtml(shortDate(incident.lastSeenAt))}</td>
            <td>
              ${incident.lastAlertAt ? escapeHtml(shortDate(incident.lastAlertAt)) : '—'}<br>
              <span class="muted">${escapeHtml(incident.lastAlertStatus || incident.lastAlertError || '')}</span>
            </td>
            <td>
              ${
                canManageIncidents
                  ? `<div class="row-actions">
                      ${
                        canResolve
                          ? `<button class="small-button" data-incident-investigate="${escapeHtml(incident.id)}">В работу</button>
                             <button class="small-button" data-incident-resolve="${escapeHtml(incident.id)}">Решено</button>`
                          : `<button class="small-button" data-incident-open="${escapeHtml(incident.id)}">Открыть</button>`
                      }
                    </div>`
                  : readonlyActionsHtml('incidents.manage')
              }
            </td>
          </tr>
        `;
      })
      .join('') || '<tr><td colspan="9">Открытых инцидентов нет.</td></tr>';
}

function renderSubscriptionExpirySummary() {
  const container = $('subscriptionExpirySummary');
  if (!container) return;
  const expiry = state.loaded.subscriptionExpiry || {};
  const summary = expiry.summary || {};
  const issueCounts = expiry.issueCounts || {};
  const candidates = expiry.candidates || [];
  const issuePills = Object.entries(issueCounts)
    .map(([code, count]) => `<span class="status-pill ${count ? 'yellow' : 'muted'}">${escapeHtml(code)}: ${escapeHtml(count)}</span>`)
    .join('');
  const candidatePreview = candidates
    .slice(0, 5)
    .map((candidate) => {
      const label = candidate.blockingIssueCodes?.length
        ? candidate.blockingIssueCodes.join(', ')
        : (candidate.expiringWithinWindow ? 'expiring' : 'review');
      const reviewButton =
        candidate.requiresManualReview && can('billing.manage')
          ? `<button class="small-button inline-button" type="button" data-expiry-review="${escapeHtml(candidate.subscriptionId)}">Проверить</button>`
          : '';
      const reviewed = candidate.reviewedForExpiry ? 'проверено · ' : '';
      return `<span class="status-pill ${candidate.requiresManualReview ? 'yellow' : 'muted'}">#${escapeHtml(candidate.userId)} · ${escapeHtml(reviewed + label)} ${reviewButton}</span>`;
    })
    .join('');

  container.innerHTML = expiry.ok
    ? `
      <div class="check-row">
        ${statusDot(expiry.safeToEnableExpiryEnforcement, expiry.requiresAttention || !expiry.productionPaymentReady || !expiry.paymentSmokeReady)}
        <div>
          <strong>${escapeUi(summary.message, 'Готовность окончания подписок')}</strong>
          <span>
            активно=${escapeHtml(summary.activeNow, '0')},
            скоро закончится=${escapeHtml(summary.expiringWithinWindow, '0')},
            закончилось=${escapeHtml(summary.expired, '0')},
            вручную=${escapeHtml(summary.paidExpiringWithoutAutoRenew, '0')},
            проверено=${escapeHtml(summary.reviewedMissingRetentionContact, '0')},
            тестовый платёж=${boolLabel(expiry.paymentSmokeCompleted)}
          </span>
        </div>
        <span class="status-pill ${expiry.safeToEnableExpiryEnforcement ? '' : 'yellow'}">
          ${expiry.subscriptionEnforcementCurrentlyEnabled ? 'включено' : 'не включено'}
        </span>
      </div>
      <div class="external-action-meta">
        <span>Проблемы окончания подписок:</span>
        <div class="pill-list">${issuePills || '<span class="muted">нет</span>'}</div>
      </div>
      <div class="external-action-meta">
        <span>Кандидаты на проверку:</span>
        <div class="pill-list">${candidatePreview || '<span class="muted">нет в окне проверки</span>'}</div>
      </div>
      <p class="muted">
        ${escapeUi(expiry.policy?.mode, 'только проверка окончания подписок')}.
        ${expiry.policy?.requiresPaymentSmoke ? 'Нужен чистый тестовый платёж.' : ''}
        ${escapeHtml(expiry.policy?.safePaymentMethodExposure, '')}
      </p>
    `
    : '<p class="muted">Готовность окончания подписок пока не загружена.</p>';
}

function renderUsersTable() {
  const rows = state.loaded.users || [];
  $('usersTable').innerHTML =
    rows
      .map(
        (user) => `
          <tr>
            <td>#${escapeHtml(user.id)}</td>
            <td>${escapeHtml(user.email)}</td>
            <td>${escapeHtml(user.phone)}</td>
            <td>${boolLabel(user.emailVerified)}</td>
            <td>${boolLabel(user.phoneVerified)}</td>
            <td>
              ${escapeHtml(shortDate(user.createdAt))}<br>
              <span class="muted">устройства: ${escapeHtml(user.enabledDeviceCount, '0')}/${escapeHtml(user.deviceCount, '0')}</span>
            </td>
            <td>
              <button class="small-button" data-user-open="${safeText(user.id)}">Открыть</button>
            </td>
          </tr>
        `,
      )
      .join('') || '<tr><td colspan="7">Пользователей нет.</td></tr>';
}

function orderPlanLabel(order) {
  const quote = order?.quote || {};
  const selection = order?.selection || {};
  return (
    quote.planName ||
    quote.title ||
    selection.planName ||
    selection.trafficPack ||
    selection.trafficGb ||
    order.planName ||
    order.trafficPack ||
    '—'
  );
}

function findPromoCode(code) {
  const normalized = String(code || '').trim().toUpperCase();
  return (state.loaded.promos || []).find((promo) => promo.code === normalized) || null;
}

function promoDiscountLabel(promo) {
  if (!promo) return '—';
  if (promo.discountType === 'fixed') return `${escapeHtml(money(promo.discountValue))}`;
  return `${escapeHtml(promo.discountValue)}%`;
}

function promoPlansLabel(promo) {
  const plans = promo?.appliesToPlanCodes || [];
  if (!plans.length) return 'все тарифы';
  const titles = {
    starter: 'Старт',
    base: 'База',
    plus: 'Плюс',
    unlimited: 'Безлимит',
  };
  return plans.map((code) => titles[code] || code).join(', ');
}

function promoDateTimeValue(value) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value).slice(0, 16);
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 16);
}

function promoDateTimeToIso(value) {
  const raw = String(value || '').trim();
  if (!raw) return null;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? raw : date.toISOString();
}

function fillPromoForm(promo) {
  if (!promo) return;
  $('promoCodeInput').value = promo.code || '';
  $('promoTitleInput').value = promo.title || '';
  $('promoTypeInput').value = promo.discountType || 'percent';
  $('promoValueInput').value = promo.discountValue || 10;
  $('promoLimitInput').value = promo.maxRedemptions || '';
  $('promoStartsInput').value = promoDateTimeValue(promo.startsAt);
  $('promoExpiresInput').value = promoDateTimeValue(promo.expiresAt);
  $('promoPlansInput').value = (promo.appliesToPlanCodes || []).join(', ');
  $('promoNotesInput').value = promo.notes || '';
  $('promoActiveInput').checked = Boolean(promo.isActive);
}

function promoFormPayload() {
  const planCodes = $('promoPlansInput').value
    .split(',')
    .map((code) => code.trim().toLowerCase())
    .filter(Boolean);
  const limit = Number($('promoLimitInput').value || 0);
  return {
    code: $('promoCodeInput').value,
    title: $('promoTitleInput').value || null,
    discountType: $('promoTypeInput').value || 'percent',
    discountValue: Number($('promoValueInput').value || 0),
    maxRedemptions: limit > 0 ? limit : null,
    startsAt: promoDateTimeToIso($('promoStartsInput').value),
    expiresAt: promoDateTimeToIso($('promoExpiresInput').value),
    isActive: $('promoActiveInput').checked,
    appliesToPlanCodes: planCodes,
    notes: $('promoNotesInput').value || null,
  };
}

function recommendedStartPromoPayload() {
  const recommended = state.loaded.promoReadiness?.recommendedCampaigns?.find(
    (campaign) => campaign.code === 'START20',
  );
  const payload = recommended?.payload || {};
  const now = new Date();
  const expires = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
  return {
    code: payload.code || 'START20',
    title: payload.title || 'Стартовая акция для первых пользователей',
    discountType: payload.discountType || 'percent',
    discountValue: payload.discountValue || 20,
    maxRedemptions: payload.maxRedemptions || 100,
    startsAt: payload.startsAt || now.toISOString(),
    expiresAt: payload.expiresAt || expires.toISOString(),
    isActive: Boolean(payload.isActive),
    appliesToPlanCodes: payload.appliesToPlanCodes || ['starter', 'base', 'plus'],
    notes:
      payload.notes ||
      'Черновик первой акции: включать только после проверки оплаты, сайта и поддержки.',
  };
}

function fillRecommendedStartPromoForm() {
  fillPromoForm(recommendedStartPromoPayload());
  setNotice('Форма заполнена безопасным черновиком START20. Он не активируется, пока ты не включишь его вручную.');
}

async function createRecommendedStartPromoDraft() {
  if (!requirePermission('billing.manage', 'Создание черновика акции')) return;
  try {
    const result = await apiPost('/api/v1/admin/billing/promos/draft-start-campaign', {});
    state.loaded.promos = result.promos || [];
    state.loaded.promoReadiness = result.readiness || state.loaded.promoReadiness;
    fillPromoForm(result.promo || recommendedStartPromoPayload());
    renderPromoCodes();
    setNotice('Черновик START20 создан выключенным. Перед публикацией проверь даты, лимит и тарифы.');
  } catch (error) {
    setNotice(`Не удалось создать черновик START20: ${error.message}`, true);
  }
}

async function savePromoCode() {
  if (!requirePermission('billing.manage', 'Сохранение акции')) return;
  try {
    const result = await apiPost('/api/v1/admin/billing/promos', promoFormPayload());
    state.loaded.promos = result.promos || [];
    try {
      state.loaded.promoReadiness = await apiGet('/api/v1/admin/billing/promos/readiness');
    } catch (_) {
      state.loaded.promoReadiness = state.loaded.promoReadiness;
    }
    renderPromoCodes();
    setNotice('Акция сохранена.');
  } catch (error) {
    setNotice(`Не удалось сохранить акцию: ${error.message}`, true);
  }
}

async function setPromoActive(code, active) {
  if (!requirePermission('billing.manage', 'Управление акцией')) return;
  try {
    const action = active ? 'activate' : 'deactivate';
    const result = await apiPost(`/api/v1/admin/billing/promos/${encodeURIComponent(code)}/${action}`, {});
    state.loaded.promos = result.promos || [];
    try {
      state.loaded.promoReadiness = await apiGet('/api/v1/admin/billing/promos/readiness');
    } catch (_) {
      state.loaded.promoReadiness = state.loaded.promoReadiness;
    }
    renderPromoCodes();
    setNotice(active ? 'Акция включена.' : 'Акция выключена.');
  } catch (error) {
    setNotice(`Не удалось изменить акцию: ${error.message}`, true);
  }
}

async function reviewSubscriptionExpiry(subscriptionId) {
  if (!requirePermission('billing.manage', 'Проверка окончания подписки')) return;
  const candidate = (state.loaded.subscriptionExpiry?.candidates || []).find(
    (item) => String(item.subscriptionId) === String(subscriptionId),
  );
  const defaultReason = 'Проверена пробная/бесплатная подписка без подтверждённого контакта; автосписание не запускаем, подписка закончится естественно.';
  const reason = window.prompt('Причина проверки окончания подписки', defaultReason);
  if (!reason || !reason.trim()) return;
  try {
    const result = await apiPost(`/api/v1/admin/subscriptions/${encodeURIComponent(subscriptionId)}/expiry-review`, {
      status: 'reviewed',
      reason: reason.trim(),
    });
    state.loaded.subscriptionExpiry = result.readiness || state.loaded.subscriptionExpiry;
    try {
      state.loaded.launchClosurePlan = await apiGet('/api/v1/admin/launch/closure-plan');
    } catch (_) {
      state.loaded.launchClosurePlan = state.loaded.launchClosurePlan;
    }
    renderSubscriptionExpirySummary();
    renderLaunchClosurePlan();
    setNotice(`Проверка окончания подписки сохранена для подписки #${escapeHtml(candidate?.subscriptionId || subscriptionId)}.`);
  } catch (error) {
    setNotice(`Не удалось сохранить проверку окончания подписки: ${error.message}`, true);
  }
}

function renderPromoCodes() {
  const container = $('promoList');
  if (!container) return;
  const readiness = state.loaded.promoReadiness || {};
  const readinessSummary = readiness.summary || {};
  const readinessContainer = $('promoReadinessSummary');
  if (readinessContainer) {
    const issuePills = Object.entries(readiness.issueCounts || {})
      .map(([code, count]) => `<span class="status-pill ${count ? 'yellow' : 'muted'}">${escapeHtml(code)}: ${escapeHtml(count)}</span>`)
      .join('');
    const attentionPreview = (readiness.attentionPromos || [])
      .slice(0, 5)
      .map((promo) => `<span class="status-pill yellow">${escapeHtml(promo.code)} · ${escapeHtml((promo.blockingIssueCodes || []).join(', '))}</span>`)
      .join('');
    const recommended = readiness.recommendedCampaigns?.[0];
    readinessContainer.innerHTML = readiness.ok
      ? `
        <div class="check-row">
          ${statusDot(readiness.safeToRunLaunchCampaign, readiness.requiresAttention)}
          <div>
            <strong>${escapeUi(readinessSummary.message, 'Готовность стартовой акции')}</strong>
            <span>
              всего=${escapeHtml(readinessSummary.total, '0')},
              активно=${escapeHtml(readinessSummary.active, '0')},
              готово к запуску=${escapeHtml(readinessSummary.launchReady, '0')},
              риск=${escapeHtml(readinessSummary.activeRisky, '0')}
            </span>
          </div>
          <span class="status-pill ${readiness.safeToRunLaunchCampaign ? '' : 'yellow'}">
            ${readiness.safeToRunLaunchCampaign ? 'готово' : 'подготовить'}
          </span>
        </div>
        <div class="external-action-meta">
          <span>Риски:</span>
          <div class="pill-list">${issuePills || '<span class="muted">нет</span>'}</div>
        </div>
        <div class="external-action-meta">
          <span>Проверить:</span>
          <div class="pill-list">${attentionPreview || '<span class="muted">нет активных рискованных акций</span>'}</div>
        </div>
        <p class="muted">
          Рекомендация: ${escapeHtml(recommended?.code || 'START20')} ·
          ${escapeHtml(recommended?.purpose || 'ограниченная первая акция')}.
          ${escapeHtml(readiness.policy?.activation || '')}
        </p>
      `
      : '<p class="muted">Готовность акций пока не загружена.</p>';
  }
  const promos = state.loaded.promos || [];
  container.innerHTML =
    promos
      .map((promo) => {
        const currentClass = promo.isCurrent ? '' : 'yellow';
        const activeLabel = promo.isActive ? 'включена' : 'выключена';
        const limitLabel = promo.maxRedemptions
          ? `${escapeHtml(promo.redeemedCount, '0')}/${escapeHtml(promo.maxRedemptions)}`
          : `${escapeHtml(promo.redeemedCount, '0')}/без лимита`;
        return `
          <div class="check-row">
            ${statusDot(promo.isCurrent, !promo.isCurrent)}
            <div>
              <strong>${escapeHtml(promo.code)}</strong>
              <span>
                ${escapeUi(promo.title || 'Без названия')} · скидка ${promoDiscountLabel(promo)}
              </span>
              <span>
                тарифы: ${escapeHtml(promoPlansLabel(promo))};
                использовано: ${limitLabel};
                статус: ${escapeUi(promo.statusReason)}
              </span>
            </div>
            <span class="status-pill ${currentClass}">${activeLabel}</span>
            <button class="small-button" type="button" data-promo-edit="${escapeHtml(promo.code)}">Править</button>
            <button
              class="small-button ${promo.isActive ? 'danger' : ''}"
              type="button"
              data-promo-${promo.isActive ? 'deactivate' : 'activate'}="${escapeHtml(promo.code)}"
            >
              ${promo.isActive ? 'Выключить' : 'Включить'}
            </button>
          </div>
        `;
      })
      .join('') || '<p class="muted">Акций пока нет.</p>';
}

function renderOrdersTable() {
  const rows = state.loaded.orders || [];
  const reconciliation = state.loaded.billingReconciliation || {};
  const paymentSmoke = state.loaded.billingPaymentSmoke || {};
  const renewals = state.loaded.billingRenewals || {};
  const summary = reconciliation.summary || {};
  const issueCounts = reconciliation.issueCounts || {};
  const attentionOrders = reconciliation.attentionOrders || [];
  const renewalSummary = renewals.summary || {};
  const renewalIssueCounts = renewals.issueCounts || {};
  const renewalCandidates = renewals.candidates || [];
  const issuePills = Object.entries(issueCounts)
    .map(([code, count]) => `<span class="status-pill ${count ? 'yellow' : 'muted'}">${escapeHtml(code)}: ${escapeHtml(count)}</span>`)
    .join('');
  const attentionPreview = attentionOrders
    .slice(0, 5)
    .map((order) => `<span class="status-pill yellow">${escapeHtml(order.orderId)} · ${(order.issues || []).map((issue) => issue.code).join(', ')}</span>`)
    .join('');
  const renewalIssuePills = Object.entries(renewalIssueCounts)
    .map(([code, count]) => `<span class="status-pill ${count ? 'yellow' : 'muted'}">${escapeHtml(code)}: ${escapeHtml(count)}</span>`)
    .join('');
  const renewalPreview = renewalCandidates
    .slice(0, 5)
    .map((candidate) => {
      const issues = candidate.blockingIssueCodes?.length
        ? candidate.blockingIssueCodes.join(', ')
        : (candidate.chargeEligibleDryRun ? 'dry-run eligible' : 'review');
      return `<span class="status-pill ${candidate.chargeEligibleDryRun ? '' : 'yellow'}">${escapeHtml(candidate.email || candidate.userId)} · ${escapeHtml(issues)}</span>`;
    })
    .join('');
  const reconciliationContainer = $('billingReconciliationSummary');
  if (reconciliationContainer) {
    reconciliationContainer.innerHTML = reconciliation.ok
      ? `
        <div class="check-row">
          ${statusDot(!reconciliation.requiresAttention, reconciliation.requiresAttention)}
          <div>
            <strong>${escapeUi(summary.message, 'Сверка платежей')}</strong>
            <span>
              всего=${escapeHtml(summary.total, '0')},
              требуют внимания=${escapeHtml(summary.ordersWithAttention, '0')},
              высокая важность=${escapeHtml(summary.high, '0')},
              средняя важность=${escapeHtml(summary.medium, '0')}
            </span>
          </div>
          <span class="status-pill ${reconciliation.requiresAttention ? 'yellow' : ''}">
            ${reconciliation.requiresAttention ? 'проверить' : 'чисто'}
          </span>
        </div>
        <div class="external-action-meta">
          <span>Проблемы:</span>
          <div class="pill-list">${issuePills || '<span class="muted">нет</span>'}</div>
        </div>
        <div class="external-action-meta">
          <span>Заказы:</span>
          <div class="pill-list">${attentionPreview || '<span class="muted">нет</span>'}</div>
        </div>
        <p class="muted">${escapeHtml(reconciliation.manualActivationPolicy || '')}</p>
      `
      : '<p class="muted">Сверка платежей пока не загружена.</p>';
  }
  const smokeContainer = $('billingPaymentSmokeSummary');
  if (smokeContainer) {
    const smokeSummary = paymentSmoke.summary || {};
    const smokeChecks = paymentSmoke.checks || [];
    const failedSmokeChecks = smokeChecks.filter((check) => !check.ok);
    const smokeSteps = paymentSmoke.smokeSteps || [];
    const smokePolicy = paymentSmoke.policy || {};
    const stepPreview = smokeSteps
      .slice(0, 5)
      .map((step) => `<span class="status-pill ${step.status === 'done' ? '' : step.status === 'blocked' ? 'red' : 'yellow'}">${escapeUi(step.code)}: ${escapeUi(step.status)}</span>`)
      .join('');
    smokeContainer.innerHTML = paymentSmoke.ok
      ? `
        <div class="check-row">
          ${statusDot(Boolean(paymentSmoke.productionReady), Boolean(paymentSmoke.safeToRunSmoke))}
          <div>
            <strong>${escapeHtml(smokeSummary.message, 'Готовность тестового платежа')}</strong>
            <span>
              провайдер=${escapeUi(paymentSmoke.provider || '—')},
              можно запускать=${boolLabel(paymentSmoke.safeToRunSmoke)},
              завершено=${boolLabel(paymentSmoke.smokeCompleted)}
            </span>
            <span>
              заказы ЮKassa=${escapeHtml(smokeSummary.yookassaOrdersTotal, '0')},
              ждут ссылки=${escapeHtml(smokeSummary.pendingWithPaymentUrl, '0')},
              успешно=${escapeHtml(smokeSummary.successfulSmokeCandidates, '0')}
            </span>
          </div>
          <span class="status-pill ${paymentSmoke.productionReady ? '' : paymentSmoke.safeToRunSmoke ? 'yellow' : 'red'}">
            ${paymentSmoke.productionReady ? 'тестовый платёж пройден' : paymentSmoke.safeToRunSmoke ? 'запустить тестовый платёж' : 'заблокировано'}
          </span>
        </div>
        <div class="external-action-meta">
          <span>Шаги тестового платежа:</span>
          <div class="pill-list">${stepPreview || '<span class="muted">нет</span>'}</div>
        </div>
        ${
          failedSmokeChecks.length
            ? `<div class="external-action-meta">
                <span>Блокеры:</span>
                <div class="pill-list">${
                  failedSmokeChecks.map((check) => `<span class="status-pill ${check.code === 'payment_production_ready' || check.code === 'site_payment_urls_ready' ? 'red' : 'yellow'}">${escapeHtml(check.code)}</span>`).join('')
                }</div>
              </div>`
            : ''
        }
        <p class="muted">
          ${escapeHtml(smokePolicy.noSyntheticActivation || '')}
          ${escapeHtml(smokePolicy.activationSource || '')}
        </p>
      `
      : '<p class="muted">Готовность тестового платежа пока не загружена.</p>';
  }
  const renewalContainer = $('billingRenewalSummary');
  if (renewalContainer) {
    renewalContainer.innerHTML = renewals.ok
      ? `
        <div class="check-row">
          ${statusDot(renewals.safeToEnableAutoRenewalCharges, renewals.requiresAttention || !renewals.productionPaymentReady || !renewals.paymentSmokeReady)}
          <div>
            <strong>${escapeHtml(renewalSummary.message, 'Готовность автопродления')}</strong>
            <span>
              автопродление=${escapeHtml(renewalSummary.autoRenewSubscriptions, '0')},
              срок=${escapeHtml(renewalSummary.dueWithinWindow, '0')},
              подходит=${escapeHtml(renewalSummary.chargeEligibleDryRun, '0')},
              нет способа оплаты=${escapeHtml(renewalSummary.missingPaymentMethod, '0')},
              тестовый платёж=${boolLabel(renewals.paymentSmokeCompleted)}
            </span>
          </div>
          <span class="status-pill ${renewals.safeToEnableAutoRenewalCharges ? '' : 'yellow'}">
            ${renewals.safeToEnableAutoRenewalCharges ? 'безопасная проверка' : 'заблокировано'}
          </span>
        </div>
        <div class="external-action-meta">
          <span>Проблемы автопродления:</span>
          <div class="pill-list">${renewalIssuePills || '<span class="muted">нет</span>'}</div>
        </div>
        <div class="external-action-meta">
          <span>Кандидаты на проверку:</span>
          <div class="pill-list">${renewalPreview || '<span class="muted">нет в окне проверки</span>'}</div>
        </div>
        <p class="muted">
          ${escapeUi(renewals.policy?.automaticChargeExecution, 'только проверка без списания')}.
          ${renewals.policy?.requiresPaymentSmoke ? 'Нужен чистый тестовый платеж.' : ''}
          ${escapeHtml(renewals.policy?.safePaymentMethodExposure, '')}
        </p>
      `
      : '<p class="muted">Готовность автопродления пока не загружена.</p>';
  }
  $('ordersTable').innerHTML =
    rows
      .map(
        (order) => `
          <tr>
            <td>${escapeHtml(order.orderId || order.id)}</td>
            <td>${escapeHtml(order.email || order.userId)}</td>
            <td>
              ${escapeHtml(money(order.priceRub || order.amountRub))}
              ${
                order.discountRub
                  ? `<br><span class="muted">скидка ${escapeHtml(money(order.discountRub))} ${escapeHtml(order.promoCode || '')}</span>`
                  : '<br><span class="muted">без акции</span>'
              }
            </td>
            <td><span class="status-pill muted">${escapeUi(order.status)}</span></td>
            <td>${escapeHtml(orderPlanLabel(order))}</td>
            <td>${escapeHtml(shortDate(order.createdAt))}</td>
          </tr>
        `,
      )
      .join('') || '<tr><td colspan="6">Заказов нет.</td></tr>';
}

function renderAuthTable() {
  renderUserAuthReadiness();
  const rows = state.loaded.auth || [];
  $('authTable').innerHTML =
    rows
      .map(
        (event) => `
          <tr>
            <td>#${escapeHtml(event.id)}</td>
            <td>${escapeUi(event.eventType)}</td>
            <td><span class="status-pill ${event.status === 'verified' ? '' : event.status === 'created' ? 'yellow' : 'red'}">${escapeUi(event.status)}</span></td>
            <td>${escapeHtml(event.email || event.phone)}</td>
            <td>${escapeHtml(event.requestIp)}</td>
            <td>${escapeHtml(shortDate(event.createdAt))}</td>
          </tr>
        `,
      )
      .join('') || '<tr><td colspan="6">Событий нет.</td></tr>';
}

function renderUserAuthReadiness() {
  const container = $('authReadinessSummary');
  if (!container) return;
  const auth =
    state.loaded.userAuthReadiness ||
    state.loaded.readiness?.userAuthFlowReadiness ||
    state.loaded.overview?.userAuthFlowReadiness;
  if (!auth) {
    container.innerHTML = '<p class="muted">Готовность входа пользователей пока не загружена.</p>';
    return;
  }

  const summary = auth.summary || {};
  const methods = auth.methods || [];
  const checks = auth.checks || [];
  const problems = auth.recentProblemEvents || [];
  const methodPills = methods
    .map((method) => {
      const label = method.legacy
        ? `${method.code}: старый режим`
        : `${method.code}: ${method.available ? 'доступно' : 'заблокировано'}`;
      const pillClass = method.productionReady ? '' : method.available ? 'yellow' : 'red';
      return `<span class="status-pill ${pillClass}">${escapeHtml(label)}</span>`;
    })
    .join('');
  const failedChecks = checks
    .filter((check) => !check.ok)
    .map((check) => `
      <div class="check-row">
        ${statusDot(false, true)}
        <div>
          <strong>${escapeUi(check.title || check.code)}</strong>
          <span>${escapeUi(check.message)}</span>
        </div>
        <span class="status-pill yellow">нужно действие</span>
      </div>
    `)
    .join('');
  const problemPills = problems
    .slice(0, 6)
    .map((event) => `<span class="status-pill yellow">#${escapeHtml(event.id)} ${escapeUi(event.eventType)}: ${escapeUi(event.status)}</span>`)
    .join('');

  container.innerHTML = `
    <div class="check-row">
        ${statusDot(Boolean(auth.productionReady), !auth.productionReady)}
      <div>
        <strong>${escapeUi(summary.message, 'Готовность входа по коду')}</strong>
        <span>
          основной способ=${escapeHtml(auth.primaryMethod || '—')},
          запасной способ=${escapeHtml(auth.fallbackMethod || '—')},
          пользователей=${escapeHtml(summary.usersTotal, '0')},
          подтверждений за 24ч=${escapeHtml(summary.verified24h, '0')},
          проблем за 24ч=${escapeHtml(summary.problem24h, '0')}
        </span>
      </div>
      <span class="status-pill ${auth.productionReady ? '' : 'yellow'}">${auth.productionReady ? 'готово' : 'настройка'}</span>
    </div>
    <div class="external-action-meta">
      <span>Способы входа:</span>
      <div class="pill-list">${methodPills || '<span class="muted">нет</span>'}</div>
    </div>
    ${
      failedChecks
        ? `<div class="check-list compact-list">${failedChecks}</div>`
        : '<p class="muted">Проверка входа зелёная.</p>'
    }
    ${
      problemPills
        ? `<div class="external-action-meta"><span>Последние проблемы:</span><div class="pill-list">${problemPills}</div></div>`
        : ''
    }
    <p class="muted">${escapeHtml(auth.policy?.secretExposure || 'Проверка готовности не раскрывает секреты входа.')}</p>
  `;
}

function renderStaffTools() {
  const roles = state.loaded.roles || [];
  const roleSelect = $('staffRoleInput');
  if (roleSelect) {
    const current = roleSelect.value || 'support';
    roleSelect.innerHTML = roles
      .map(
        (role) => `
          <option value="${escapeHtml(role.code)}" ${role.code === current ? 'selected' : ''}>
            ${escapeHtml(role.title)}
          </option>
        `,
      )
      .join('');
    if (!roleSelect.value && roles.some((role) => role.code === 'support')) {
      roleSelect.value = 'support';
    }
  }

  $('roleList').innerHTML =
    roles
      .map(
        (role) => `
          <div class="check-row">
            <span class="dot"></span>
            <div>
              <strong>${escapeHtml(role.title)}</strong>
              <span>${escapeHtml((role.permissions || []).map(permissionLabel).join(', ') || '—')}</span>
            </div>
            <span class="status-pill muted">${escapeHtml(role.code)}</span>
          </div>
        `,
      )
      .join('') || '<p class="muted">Роли пока не загружены.</p>';
}

function renderStaffTable() {
  const rows = state.loaded.staff || [];
  const canManageStaff = can('staff.manage');
  $('staffTable').innerHTML =
    rows
      .map((staff) => {
        const activeSessions = Number(staff.activeSessionCount || 0);
        return `
          <tr>
            <td>#${escapeHtml(staff.id)}</td>
            <td>
              <strong>${escapeHtml(staff.displayName || staff.email)}</strong><br>
              <span class="muted">${escapeHtml(staff.email)}</span>
            </td>
            <td>
              ${escapeHtml(staff.roleTitle || staff.role)}<br>
              <span class="muted">код роли: ${escapeHtml(staff.role)}</span>
            </td>
            <td>${boolPill(staff.isActive, 'активен', 'выключен')}</td>
            <td>
              ${boolPill(staff.twoFactorEnabled, 'код по почте', 'выключен')}
              <br><span class="muted">${escapeHtml(shortDate(staff.twoFactorSetAt))}</span>
            </td>
            <td>
              ${boolPill(staff.hasPassword, 'задан', 'нет')}
              <br><span class="muted">последний вход: ${escapeHtml(shortDate(staff.lastLoginAt))}</span>
            </td>
            <td>
              <strong>${escapeHtml(activeSessions)}</strong> активных<br>
              <span class="muted">последняя активность: ${escapeHtml(shortDate(staff.lastSessionSeenAt))}</span><br>
              ${
                canManageStaff
                  ? `<button class="small-button" data-staff-sessions="${escapeHtml(staff.id)}">Сессии</button>`
                  : readonlyActionsHtml('staff.manage')
              }
            </td>
            <td>${escapeHtml(shortDate(staff.updatedAt))}</td>
            <td>
              ${
                canManageStaff
                  ? `<button
                      class="small-button ${staff.isActive ? 'danger' : ''}"
                      data-staff-toggle="${escapeHtml(staff.id)}"
                      data-staff-active="${staff.isActive ? '0' : '1'}"
                    >
                      ${staff.isActive ? 'Выключить' : 'Включить'}
                    </button>`
                  : readonlyActionsHtml('staff.manage')
              }
            </td>
          </tr>
        `;
      })
      .join('') || '<tr><td colspan="9">Команда пока пустая.</td></tr>';
  renderStaffTools();
  renderStaffSessionsPanel();
}

function renderStaffSessionsPanel() {
  const container = $('staffSessionsPanel');
  if (!container) return;
  const data = state.loaded.staffSessions;
  if (!data) {
    container.innerHTML = '<p class="muted">Выбери сотрудника в таблице, чтобы посмотреть его активные входы.</p>';
    return;
  }
  const staff = data.staff || {};
  const sessions = data.sessions || [];
  const staffId = staff.id;
  const canRevokeAll = sessions.some((session) => !session.revokedAt && !session.isCurrent);
  container.innerHTML = `
    <div class="check-row">
      ${statusDot(true, false)}
      <div>
        <strong>Входы сотрудника: ${escapeHtml(staff.displayName || staff.email || staffId)}</strong>
        <span>всего=${escapeHtml(sessions.length)}, активно=${escapeHtml(staff.activeSessionCount || 0)}</span>
      </div>
      ${
        canRevokeAll
          ? `<button class="small-button danger" data-staff-sessions-revoke-all="${escapeHtml(staffId)}">Сбросить все</button>`
          : '<span class="status-pill muted">нет активных чужих</span>'
      }
    </div>
    ${sessions
      .map((session) => {
        const revoked = Boolean(session.revokedAt);
        const active = !revoked;
        const title = session.isCurrent ? 'текущая' : revoked ? 'отозвана' : 'активна';
        const action = active && !session.isCurrent
          ? `<button class="small-button danger" data-staff-session-revoke="${escapeHtml(staffId)}" data-session-id="${escapeHtml(session.sessionId)}">Отозвать</button>`
          : `<span class="status-pill ${session.isCurrent ? '' : 'muted'}">${escapeHtml(title)}</span>`;
        return `
          <div class="status-row">
            ${statusDot(active, !session.isCurrent)}
            <div>
              <strong>${escapeHtml(session.sessionId)}</strong>
              <span>
                ${escapeHtml(session.requestIp || 'ip неизвестен')} ·
                вход ${escapeHtml(shortDate(session.createdAt))} ·
                активность ${escapeHtml(shortDate(session.lastSeenAt))}
              </span>
            <span>${escapeHtml(session.userAgent || 'данные браузера не записаны')}</span>
            </div>
            ${action}
          </div>
        `;
      })
      .join('') || '<p class="muted">У сотрудника пока нет активных входов.</p>'}
  `;
}

function renderAuditTable() {
  const rows = state.loaded.audit || [];
  $('auditTable').innerHTML =
    rows
      .map(
        (event) => `
          <tr>
            <td>#${escapeHtml(event.id)}</td>
            <td>${escapeHtml(event.actor)}</td>
            <td>${escapeHtml(event.action)}</td>
            <td>
              <strong>${escapeHtml(event.targetType)}</strong><br>
              <span class="muted">${escapeHtml(event.targetId)}</span>
            </td>
            <td>${escapeHtml(event.requestIp)}</td>
            <td>${escapeHtml(shortDate(event.createdAt))}</td>
            <td><pre class="inline-code">${escapeHtml(prettyJson(event.details || {}))}</pre></td>
          </tr>
        `,
      )
      .join('') || '<tr><td colspan="7">Журнал действий пока пуст.</td></tr>';
}

function renderAll() {
  $('sidebarApiBase').textContent = 'Green VPN';
  applyAuthUi();
  renderMetrics(state.loaded.overview || {});
  renderAccountSecurity();
  renderAnalytics();
  renderServiceStatus();
  renderAdvertisingReadiness();
  renderLaunchReadiness();
  renderLaunchClosurePlan();
  renderOwnerLaunchPacket();
  renderSiteReadiness();
  renderNetworkReadiness();
  renderReadiness();
  renderIncidentFilters();
  renderIncidentsTable();
  renderSupportWorkflowFilters();
  renderSupportActionFilters();
  renderSupportSlaSummary();
  renderSupportTable();
  renderSupportActionsOverview();
  renderSubscriptionExpirySummary();
  renderUsersTable();
  renderOrdersTable();
  renderPromoCodes();
  renderAuthTable();
  renderStaffTable();
  renderAuditTable();
  renderReleaseFilters();
  renderUpdateReadiness();
  renderUpdateManifest();
  renderReleasesTable();
  renderFeatureFlags();
  renderRunbooks();
  renderServerFilters();
  renderServerCatalogSummary();
  renderServerOperationsOverview();
  renderServersTable();
  renderServerHealth();
  renderManagedMonitoring();
  renderAdmin2faPrompt();
  translateAdminDom(document.querySelector('.main'));
}

async function loginWithStaffSession(email, password, actor) {
  const result = await apiPost(
    '/api/v1/admin/auth/login',
    {
      email,
      password,
      actor,
    },
    false,
  );
  if (result?.twoFactorRequired) {
    state.pendingAdmin2fa = {
      email,
      actor,
      challengeId: result.challengeId || '',
      expiresAt: result.expiresAt || '',
      maskedEmail: result.email || email,
    };
    renderAdmin2faPrompt();
    setNotice('Код подтверждения отправлен на почту сотрудника.');
    return { pending: true };
  }
  await finishStaffLogin(result, email, actor);
  return { pending: false };
}

async function finishStaffLogin(result, email, actor) {
  state.sessionToken = String(result.sessionToken || '');
  state.adminToken = '';
  state.authType = result.authType || 'staff_session';
  state.currentStaff = result.staff || null;
  state.permissions = Array.isArray(result.role?.permissions) ? result.role.permissions : [];
  state.roleTitle = result.role?.title || '';
  state.adminEmail = email;
  state.adminActor = actor || result.staff?.displayName || result.staff?.email || email;
  if (!state.sessionToken) {
    throw new Error('Сервер не вернул сессию администратора.');
  }
  const me = await apiGet('/api/v1/admin/auth/me');
  setAdminContext(me);
  state.pendingAdmin2fa = null;
  renderAdmin2faPrompt();
}

function renderAdmin2faPrompt() {
  const panel = $('admin2faPanel');
  if (!panel) return;
  const pending = state.pendingAdmin2fa;
  panel.classList.toggle('hidden', !pending);
  const codeInput = $('admin2faCodeInput');
  if (pending) {
    $('admin2faHint').textContent = `Код отправлен на ${pending.maskedEmail || pending.email}. Действует до ${shortDate(pending.expiresAt)}.`;
    window.setTimeout(() => codeInput?.focus(), 0);
  } else if (codeInput) {
    codeInput.value = '';
  }
}

function cancelAdminTwoFactor() {
  state.pendingAdmin2fa = null;
  renderAdmin2faPrompt();
  setNotice('Ввод кода отменён.');
}

async function verifyAdminTwoFactor() {
  const pending = state.pendingAdmin2fa;
  if (!pending?.challengeId) {
    setNotice('Сначала запроси код входа сотрудника.', true);
    return false;
  }
  const code = $('admin2faCodeInput').value.trim();
  if (!/^\d{6}$/.test(code)) {
    setNotice('Введи 6 цифр из письма.', true);
    return false;
  }
  const result = await apiPost(
    '/api/v1/admin/auth/2fa/verify',
    {
      email: pending.email,
      challengeId: pending.challengeId,
      code,
      actor: pending.actor,
    },
    false,
  );
  await finishStaffLogin(result, pending.email, pending.actor);
  saveSession($('rememberTokenInput').checked);
  $('loginPanel').classList.add('hidden');
  $('adminPasswordInput').value = '';
  $('admin2faCodeInput').value = '';
  applyAuthUi();
  await loadDashboardData();
  setNotice('Вход подтверждён.');
  return true;
}

async function loginWithBootstrapToken(token, actor) {
  state.adminToken = token;
  state.sessionToken = '';
  state.authType = 'bootstrap_token';
  state.currentStaff = null;
  state.adminActor = actor || 'admin_token';
  const result = await apiGet('/api/v1/admin/auth/me');
  setAdminContext(result);
  state.authType = result.auth?.authType || 'bootstrap_token';
}

async function logoutAdmin() {
  try {
    if (hasAdminCredential()) {
      await apiPost('/api/v1/admin/auth/logout', {});
    }
  } catch (_error) {
    // Локальный выход всё равно должен сработать, даже если backend недоступен.
  }
  state.adminToken = '';
  state.sessionToken = '';
  state.authType = '';
  state.currentStaff = null;
  state.pendingAdmin2fa = null;
  state.permissions = [];
  state.roleTitle = '';
  localStorage.removeItem(STORAGE_KEY);
  $('adminTokenInput').value = '';
  $('adminPasswordInput').value = '';
  renderAdmin2faPrompt();
  $('loginPanel').classList.remove('hidden');
  applyAuthUi();
  setSidebarStatus('не подключено', 'muted');
  setNotice('Вы вышли из админской панели.');
}

async function changeCurrentPassword() {
  try {
    const currentPassword = $('currentPasswordInput').value;
    const newPassword = $('newPasswordInput').value;
    await apiPost('/api/v1/admin/auth/password/change', {
      currentPassword,
      newPassword,
    });
    $('currentPasswordInput').value = '';
    $('newPasswordInput').value = '';
    await loadDashboardData();
    setNotice('Пароль изменён. Другие активные сессии сброшены.');
  } catch (error) {
    setNotice(`Не удалось сменить пароль: ${error.message}`, true);
  }
}

async function revokeOtherAdminSessions() {
  try {
    const result = await apiPost('/api/v1/admin/auth/sessions/revoke-others', {});
    await loadDashboardData();
    setNotice(`Другие сессии сброшены: ${escapeHtml(result.revokedOtherSessions, '0')}.`);
  } catch (error) {
    setNotice(`Не удалось сбросить другие сессии: ${error.message}`, true);
  }
}

async function revokeAdminSession(sessionId) {
  try {
    await apiPost('/api/v1/admin/auth/sessions/revoke', { sessionId });
    await loadDashboardData();
    setNotice('Сессия отозвана.');
  } catch (error) {
    setNotice(`Не удалось отозвать сессию: ${error.message}`, true);
  }
}

async function openStaffSessions(staffId) {
  if (!requirePermission('staff.manage', 'Просмотр входов сотрудника')) return;
  try {
    const result = await apiGet(`/api/v1/admin/staff/${encodeURIComponent(staffId)}/sessions`);
    state.loaded.staffSessions = result;
    renderStaffSessionsPanel();
    setNotice('Сессии сотрудников загружены.');
  } catch (error) {
    setNotice(`Не удалось загрузить входы сотрудника: ${error.message}`, true);
  }
}

async function revokeStaffSession(staffId, sessionId) {
  if (!requirePermission('staff.manage', 'Отзыв входа сотрудника')) return;
  try {
    await apiPost(`/api/v1/admin/staff/${encodeURIComponent(staffId)}/sessions/revoke`, { sessionId });
    await openStaffSessions(staffId);
    await loadDashboardData();
    setNotice('Сессия сотрудника отозвана.');
  } catch (error) {
    setNotice(`Не удалось отозвать вход сотрудника: ${error.message}`, true);
  }
}

async function revokeAllStaffSessions(staffId) {
  if (!requirePermission('staff.manage', 'Сброс входов сотрудника')) return;
  if (!window.confirm('Сбросить все активные входы выбранного сотрудника?')) return;
  try {
    const result = await apiPost(`/api/v1/admin/staff/${encodeURIComponent(staffId)}/sessions/revoke-all`, {});
    await openStaffSessions(staffId);
    await loadDashboardData();
    setNotice(`Сессии сотрудников сброшены: ${escapeHtml(result.revokedSessions, '0')}.`);
  } catch (error) {
    setNotice(`Не удалось сбросить входы сотрудника: ${error.message}`, true);
  }
}

async function loadDashboardData() {
  if (!hasAdminCredential()) {
    setSidebarStatus('нужен вход', 'muted');
    setNotice('Войди по почте сотрудника и паролю, чтобы открыть внутреннюю панель.', true);
    return;
  }

  setNotice('Загружаю данные админки...');
  setSidebarStatus('загрузка', 'yellow');

  try {
    await refreshAdminContext();
  } catch (error) {
    state.adminToken = '';
    state.sessionToken = '';
    state.authType = '';
    state.currentStaff = null;
    state.permissions = [];
    state.roleTitle = '';
    localStorage.removeItem(STORAGE_KEY);
    applyAuthUi();
    setSidebarStatus('нужен вход', 'yellow');
    setNotice(`Админская сессия недоступна: ${error.message}. Войди заново.`, true);
    $('loginPanel').classList.remove('hidden');
    return;
  }

  resetLoadedData();
  const requests = {};
  if (state.sessionToken) {
    requests.adminSessions = apiGet('/api/v1/admin/auth/sessions');
  }
  addAllowedRequest(requests, 'overview', 'dashboard.read', () => apiGet('/api/v1/admin/overview'));
  addAllowedRequest(requests, 'analytics', 'analytics.read', () => apiGet('/api/v1/admin/analytics/summary'));
  addAllowedRequest(requests, 'launchReadiness', 'readiness.read', () => apiGet('/api/v1/admin/launch/readiness'));
  addAllowedRequest(requests, 'advertisingReadiness', 'readiness.read', () => apiGet('/api/v1/admin/launch/advertising-readiness'));
  addAllowedRequest(requests, 'launchClosurePlan', 'readiness.read', () => apiGet('/api/v1/admin/launch/closure-plan'));
  addAllowedRequest(requests, 'launchOwnerPacket', 'readiness.read', () => apiGet('/api/v1/admin/launch/owner-packet'));
  addAllowedRequest(requests, 'readiness', 'readiness.read', () => apiGet('/api/v1/admin/readiness'));
  addAllowedRequest(requests, 'siteReadiness', 'readiness.read', () => apiGet('/api/v1/admin/site/readiness'));
  addAllowedRequest(requests, 'networkReadiness', 'readiness.read', () => apiGet('/api/v1/admin/network/readiness'));
  addAllowedRequest(requests, 'networkSplitPlan', 'readiness.read', () => apiGet('/api/v1/admin/network/split-plan'));
  addAllowedRequest(requests, 'userAuthReadiness', 'readiness.read', () => apiGet('/api/v1/admin/auth/user-flow/readiness?limit=10'));
  addAllowedRequest(requests, 'adminTwoFactorReadiness', 'staff.manage', () => apiGet('/api/v1/admin/auth/2fa/readiness'));
  addAllowedRequest(requests, 'externalActions', 'readiness.read', () => apiGet('/api/v1/admin/external-actions'));
  addAllowedRequest(requests, 'support', 'support.read', () => apiGet(`/api/v1/admin/support/reports${encodeQuery(supportFilterParams())}`));
  addAllowedRequest(requests, 'supportSla', 'support.read', () => apiGet('/api/v1/admin/support/sla?limit=25'));
  addAllowedRequest(requests, 'users', 'users.read', () => apiGet(`/api/v1/admin/users${encodeQuery(userFilterParams())}`));
  addAllowedRequest(requests, 'subscriptionExpiry', 'billing.read', () => apiGet('/api/v1/admin/subscriptions/expiry-readiness?limit=25'));
  addAllowedRequest(requests, 'orders', 'billing.read', () => apiGet('/api/v1/admin/billing/orders?status=all'));
  addAllowedRequest(requests, 'billingPromos', 'billing.read', () => apiGet('/api/v1/admin/billing/promos'));
  addAllowedRequest(requests, 'billingPromoReadiness', 'billing.read', () => apiGet('/api/v1/admin/billing/promos/readiness'));
  addAllowedRequest(requests, 'billingPaymentSmoke', 'billing.read', () => apiGet('/api/v1/admin/billing/payment-smoke/readiness?limit=10'));
  addAllowedRequest(requests, 'billingRenewals', 'billing.read', () => apiGet('/api/v1/admin/billing/renewals/readiness?limit=25'));
  addAllowedRequest(requests, 'auth', 'audit.read', () => apiGet(`/api/v1/admin/auth/events${encodeQuery(authFilterParams())}`));
  addAllowedRequest(requests, 'audit', 'audit.read', () => apiGet('/api/v1/admin/audit?limit=80'));
  addAllowedRequest(requests, 'roles', 'staff.manage', () => apiGet('/api/v1/admin/roles'));
  addAllowedRequest(requests, 'staff', 'staff.manage', () => apiGet('/api/v1/admin/staff'));
  addAllowedRequest(requests, 'supportWorkflow', 'support.read', () => apiGet('/api/v1/admin/support/workflow'));
  addAllowedRequest(requests, 'supportActions', 'support_actions.read', () => apiGet(`/api/v1/admin/support/actions${encodeQuery(supportActionFilterParams())}`));
  addAllowedRequest(requests, 'supportActionWorkflow', 'support_actions.read', () => apiGet('/api/v1/admin/support/actions/workflow'));
  addAllowedRequest(requests, 'incidents', 'incidents.read', () => apiGet(`/api/v1/admin/incidents${encodeQuery(incidentFilterParams())}`));
  addAllowedRequest(requests, 'alertEvents', 'incidents.read', () => apiGet('/api/v1/admin/alerts/events?limit=40'));
  addAllowedRequest(requests, 'updateReadiness', 'updates.read', () => apiGet(`/api/v1/admin/updates/readiness${encodeQuery(updateReadinessFilterParams())}`));
  addAllowedRequest(requests, 'releases', 'updates.read', () => apiGet(`/api/v1/admin/updates/releases${encodeQuery(releaseFilterParams())}`));
  addAllowedRequest(requests, 'servers', 'servers.read', () => apiGet(`/api/v1/admin/server-catalog${encodeQuery(serverFilterParams())}`));
  addAllowedRequest(requests, 'serverPublicationReadiness', 'servers.read', () => apiGet('/api/v1/admin/server-catalog/publication-readiness'));
  addAllowedRequest(requests, 'serverProvisioningReadiness', 'servers.read', () => apiGet('/api/v1/admin/server-catalog/provisioning-readiness'));
  addAllowedRequest(requests, 'serverHealth', 'monitoring.read', () => apiGet(`/api/v1/admin/server-health${encodeQuery(serverHealthFilterParams())}`));
  addAllowedRequest(requests, 'resilienceRoutes', 'monitoring.read', () => apiGet('/api/v1/admin/resilience/routes'));
  addAllowedRequest(requests, 'resilienceTransportRollout', 'monitoring.read', () => apiGet('/api/v1/admin/resilience/transport-rollout'));
  addAllowedRequest(requests, 'monitoringTargets', 'monitoring.read', () => apiGet(`/api/v1/admin/monitoring/targets${encodeQuery(monitoringTargetFilterParams())}`));
  addAllowedRequest(requests, 'serviceObservations', 'monitoring.read', () => apiGet(`/api/v1/admin/monitoring/service-observations${encodeQuery(serviceObservationFilterParams())}`));
  addAllowedRequest(requests, 'clientRouteEvents', 'monitoring.read', () => apiGet(`/api/v1/admin/resilience/client-route-events${encodeQuery(clientRouteEventFilterParams())}`));
  addAllowedRequest(requests, 'monitoringProbes', 'monitoring.read', () => apiGet('/api/v1/admin/monitoring/probes?limit=100'));
  addAllowedRequest(requests, 'monitoringReadiness', 'monitoring.read', () => apiGet('/api/v1/admin/monitoring/readiness'));
  addAllowedRequest(requests, 'monitoring', 'dashboard.read', () => apiGet('/api/v1/monitoring/status', false));
  addAllowedRequest(requests, 'services', 'monitoring.read', () => apiGet('/api/v1/monitoring/services', false));

  const entries = await Promise.allSettled(
    Object.entries(requests).map(async ([key, promise]) => [key, await promise]),
  );

  const errors = [];
  for (const result of entries) {
    if (result.status === 'fulfilled') {
      const [key, value] = result.value;
      if (key === 'support') state.loaded.support = value.reports || [];
      else if (key === 'supportSla') state.loaded.supportSla = value;
      else if (key === 'users') state.loaded.users = value.users || [];
      else if (key === 'subscriptionExpiry') state.loaded.subscriptionExpiry = value;
      else if (key === 'orders') {
        state.loaded.orders = value.orders || [];
        state.loaded.billingReconciliation = value.reconciliation || state.loaded.billingReconciliation;
        state.loaded.promos = value.promos || state.loaded.promos;
      }
      else if (key === 'siteReadiness') state.loaded.siteReadiness = value;
      else if (key === 'launchClosurePlan') state.loaded.launchClosurePlan = value;
      else if (key === 'launchOwnerPacket') state.loaded.launchOwnerPacket = value;
      else if (key === 'userAuthReadiness') state.loaded.userAuthReadiness = value;
      else if (key === 'billingPromos') state.loaded.promos = value.promos || [];
      else if (key === 'billingPromoReadiness') state.loaded.promoReadiness = value;
      else if (key === 'billingPaymentSmoke') state.loaded.billingPaymentSmoke = value;
      else if (key === 'billingRenewals') state.loaded.billingRenewals = value;
      else if (key === 'auth') state.loaded.auth = value.events || [];
      else if (key === 'audit') state.loaded.audit = value.events || [];
      else if (key === 'roles') state.loaded.roles = value.roles || [];
      else if (key === 'staff') state.loaded.staff = value.staff || [];
      else if (key === 'adminSessions') state.loaded.adminSessions = value.sessions || [];
      else if (key === 'supportWorkflow') state.loaded.supportWorkflow = value;
      else if (key === 'supportActions') {
        state.loaded.supportActions = value.actions || [];
        state.loaded.supportActionWorkflow = value.workflow || state.loaded.supportActionWorkflow;
      }
      else if (key === 'supportActionWorkflow') state.loaded.supportActionWorkflow = value;
      else if (key === 'incidents') {
        state.loaded.incidents = value.incidents || [];
        state.loaded.incidentWorkflow = value.workflow || null;
        state.loaded.incidentAssignees = value.assignees || state.loaded.incidentAssignees || [];
      }
      else if (key === 'alertEvents') state.loaded.alertEvents = value.events || [];
      else if (key === 'updateReadiness') {
        state.loaded.updateReadiness = value;
        state.loaded.updateManifest = value.manifest || state.loaded.updateManifest;
      }
      else if (key === 'releases') {
        state.loaded.releases = value.releases || [];
        state.loaded.releaseWorkflow = value.workflow || null;
        state.loaded.updateManifest = value.manifest || null;
        state.loaded.updateReadiness = value.readiness || state.loaded.updateReadiness;
      }
      else if (key === 'featureFlags') {
        state.loaded.featureFlags = value.flags || [];
        state.loaded.featureFlagWorkflow = value.workflow || null;
      }
      else if (key === 'runbooks') {
        state.loaded.runbooks = value.runbooks || [];
        state.loaded.runbookWorkflow = value.workflow || null;
      }
      else if (key === 'servers') {
        const managedRows = Array.isArray(value.managedEntries) ? value.managedEntries : [];
        const directRows = Array.isArray(value.servers) ? value.servers : [];
        const catalogRows = Array.isArray(value.publicCatalog?.servers)
          ? value.publicCatalog.servers.map((server) => {
            const id = server.id || server.serverId || server.name || server.host || server.endpointHost;
            const capacity = server.capacity || {};
            return {
              ...server,
              id,
              serverId: server.serverId || id,
              title: server.title || server.name || server.city || id || 'VPN-сервер',
              host: serverEndpointHost(server),
              port: serverEndpointPort(server),
              provider: server.provider || 'Green VPN',
              protocol: server.protocol || 'wireguard_udp',
              transport: server.transport || 'udp_443',
              status: server.status || (server.healthy === false ? 'degraded' : 'ready'),
              healthScore: server.healthScore ?? server.score ?? 100,
              isActive: server.isActive ?? true,
              isPublic: server.isPublic ?? true,
              clientConfigReady: server.clientConfigReady ?? true,
              capacity,
              activeClients: capacity.activeClients ?? server.activeClients ?? 0,
              assignedUsers: capacity.assignedUsers ?? server.assignedUsers ?? 0,
              publicCatalogOnly: true,
            };
          })
          : [];
        const primaryRows = managedRows.length ? managedRows : directRows;
        const knownIds = new Set(primaryRows.flatMap(serverIdentityValues));
        const fallbackRows = catalogRows.filter((server) => (
          !serverIdentityValues(server).some((id) => knownIds.has(id))
        ));
        state.loaded.servers = [...primaryRows, ...fallbackRows];
        state.loaded.serverWorkflow = value.workflow || null;
        state.loaded.serverCatalog = value.publicCatalog || null;
        state.loaded.serverCatalogSummary = value.summary || null;
      }
      else if (key === 'serverPublicationReadiness') state.loaded.serverPublicationReadiness = value;
      else if (key === 'serverProvisioningReadiness') state.loaded.serverProvisioningReadiness = value;
      else if (key === 'monitoringTargets') {
        state.loaded.monitoringTargets = value;
      }
      else if (key === 'serviceObservations') {
        state.loaded.serviceObservations = value;
      }
      else if (key === 'clientRouteEvents') {
        state.loaded.clientRouteEvents = value;
      }
      else if (key === 'monitoringProbes') {
        state.loaded.monitoringProbes = value;
      }
      else state.loaded[key] = value;
    } else {
      errors.push(result.reason?.message || String(result.reason));
    }
  }

  renderAll();
  if (errors.length) {
    setSidebarStatus('частично', 'yellow');
    setNotice(`Часть данных не загрузилась: ${errors.join(' | ')}`, true);
  } else {
    setSidebarStatus(currentAdminLabel(), '');
    setNotice('Данные обновлены.');
  }
}

function switchSection(section) {
  if (!hasAdminCredential()) {
    state.section = 'dashboard';
    setNotice('Сначала войди в админку.', true);
    return;
  }
  if (hasAdminCredential() && !can(sectionPermission(section))) {
    setNotice('У этой роли нет доступа к выбранному разделу.', true);
    section = firstAllowedSection();
  }
  state.section = section;
  const titles = {
    dashboard: 'Обзор',
    analytics: 'Аналитика',
    incidents: 'Инциденты',
    support: 'Поддержка',
    users: 'Пользователи',
    orders: 'Платежи',
    auth: 'Входы',
    staff: 'Команда',
    audit: 'Аудит',
    updates: 'Обновления',
    flags: 'Флаги',
    runbooks: 'Инструкции',
    monitoring: 'Мониторинг',
    servers: 'Серверы',
    readiness: 'Готовность',
  };
  $('pageTitle').textContent = titles[section] || 'Обзор';
  document.querySelectorAll('.nav-link').forEach((button) => {
    button.classList.toggle('active', button.dataset.section === section);
  });
  document.querySelectorAll('.content-section').forEach((sectionEl) => {
    sectionEl.classList.remove('active');
  });
  $(`${section}Section`).classList.add('active');
}

async function openReport(reportId) {
  try {
    const [reportResult, decodedResult, commentsResult] = await Promise.allSettled([
      apiGet(`/api/v1/admin/support/reports/${reportId}`),
      apiGet(`/api/v1/admin/support/reports/${reportId}/decoded`),
      apiGet(`/api/v1/admin/support/reports/${reportId}/comments`),
    ]);
    if (reportResult.status !== 'fulfilled') {
      throw reportResult.reason;
    }
    const response = reportResult.value;
    const report = response.report;
    const decoded =
      decodedResult.status === 'fulfilled'
        ? decodedResult.value.decoded
        : null;
    const decodedError =
      decodedResult.status === 'rejected'
        ? decodedResult.reason?.message || String(decodedResult.reason)
        : '';
    const comments =
      commentsResult.status === 'fulfilled'
        ? commentsResult.value.comments || []
        : [];
    const workflow = supportWorkflow();
    const statusOptions = workflowOptionsHtml(
      workflow.statuses.map((status) => ({ code: status, title: status })),
      report.status,
    );
    const priorityOptions = workflowOptionsHtml(workflow.priorities, report.priority || 'normal');
    const categoryOptions = workflowOptionsHtml(workflow.categories, report.category || 'general');
    const canManageSupport = can('support.manage');
    $('reportDialogTitle').textContent = `Отчёт #${report.id}`;
    $('reportDialogBody').innerHTML = `
      <div class="status-row">
        <span class="dot yellow"></span>
        <div>
          <strong>${escapeHtml(report.summary)}</strong>
          <span>${escapeHtml(report.email)} · ${shortDate(report.createdAt)}</span>
        </div>
        <span class="status-pill ${priorityPillClass(report.priority)}">${escapeHtml(workflowTitle('priorities', report.priority))}</span>
      </div>
      <div class="detail-grid compact-grid">
        <section class="detail-card">
          <p class="eyebrow">Категория</p>
          <strong>${escapeHtml(workflowTitle('categories', report.category))}</strong>
          <span class="muted">${escapeHtml(report.triageReason, 'Автотриаж не оставил пояснение.')}</span>
        </section>
        <section class="detail-card">
          <p class="eyebrow">SLA</p>
          <strong>${escapeHtml(shortDate(report.slaDueAt))}</strong>
          <span class="muted">Первый ответ: ${escapeHtml(shortDate(report.firstResponseAt))}</span>
        </section>
        <section class="detail-card">
          <p class="eyebrow">Проверка</p>
          <strong>${report.reviewedAt ? escapeHtml(shortDate(report.reviewedAt)) : 'Нужен первый просмотр'}</strong>
          <span class="muted">${escapeHtml(report.reviewedBy || report.assignedTo || 'исполнитель не назначен')}</span>
        </section>
      </div>
      <label>
        Статус
        <select id="reportStatusSelect" ${canManageSupport ? '' : 'disabled'}>
          ${statusOptions}
        </select>
      </label>
      <div class="form-row stretch">
        <label>
          Приоритет
          <select id="reportPrioritySelect" ${canManageSupport ? '' : 'disabled'}>
            ${priorityOptions}
          </select>
        </label>
        <label>
          Категория
          <select id="reportCategorySelect" ${canManageSupport ? '' : 'disabled'}>
            ${categoryOptions}
          </select>
        </label>
      </div>
      <label>
        SLA до
        <input id="reportSlaInput" ${canManageSupport ? '' : 'disabled'} value="${escapeHtml(report.slaDueAt, '')}">
        <span class="muted">Можно оставить как есть или вставить ISO-время, если SLA нужно вручную перенести.</span>
      </label>
      <label>
        Исполнитель
        <input id="reportAssignedInput" ${canManageSupport ? '' : 'disabled'} value="${escapeHtml(report.assignedTo, '')}">
      </label>
      <label>
        Заметка поддержки
        <textarea id="reportNoteInput" ${canManageSupport ? '' : 'disabled'}>${escapeHtml(report.adminNote, '')}</textarea>
      </label>
      ${
        canManageSupport
          ? `<div class="row-actions">
              ${report.reviewPending ? '<button class="primary-button" id="reviewReportButton">Взять в работу</button>' : ''}
              <button class="primary-button" id="saveReportStatusButton">Сохранить статус</button>
            </div>`
          : readonlyActionsHtml('support.manage')
      }
      <div class="comment-block">
        <p class="eyebrow">Комментарии поддержки</p>
        <div class="comment-list">${renderReportComments(comments)}</div>
        <label>
          Новый комментарий
          <textarea id="reportCommentInput" ${canManageSupport ? '' : 'disabled'} placeholder="Что проверили, что сделали, что ждём от пользователя"></textarea>
        </label>
        ${
          canManageSupport
            ? '<button class="ghost-button" id="addReportCommentButton">Добавить комментарий</button>'
            : ''
        }
      </div>
      <div>
        <p class="eyebrow">Расшифрованный отчёт для техподдержки</p>
        <pre class="report-code">${decoded ? escapeHtml(prettyJson(decoded)) : escapeHtml(decodedError || 'Расшифрованный отчёт пока недоступен.')}</pre>
      </div>
      <div>
        <p class="eyebrow">Исходный отчёт</p>
        <pre class="report-code compact">${escapeHtml(report.report)}</pre>
      </div>
    `;
    if (canManageSupport) {
      $('reviewReportButton')?.addEventListener('click', async () => {
        if (!requirePermission('support.manage', 'Проверка обращения')) return;
        await apiPost(`/api/v1/admin/support/reports/${report.id}/review`, {
          assignedTo: $('reportAssignedInput').value || currentSupportAssignee(),
          note: $('reportNoteInput').value || 'Отчёт взят в работу из админки Green VPN.',
        });
        await loadDashboardData();
        await openReport(report.id);
      });
      $('saveReportStatusButton').addEventListener('click', async () => {
        if (!requirePermission('support.manage', 'Сохранение обращения')) return;
        await apiPost(`/api/v1/admin/support/reports/${report.id}/status`, {
          status: $('reportStatusSelect').value,
          priority: $('reportPrioritySelect').value,
          category: $('reportCategorySelect').value,
          slaDueAt: $('reportSlaInput').value,
          note: $('reportNoteInput').value,
          assignedTo: $('reportAssignedInput').value,
        });
        await loadDashboardData();
        $('reportDialog').close();
      });
      $('addReportCommentButton').addEventListener('click', async () => {
        if (!requirePermission('support.manage', 'Комментарий к обращению')) return;
        const body = $('reportCommentInput').value.trim();
        if (!body) {
          setNotice('Комментарий пустой, добавлять нечего.', true);
          return;
        }
        await apiPost(`/api/v1/admin/support/reports/${report.id}/comments`, {
          body,
          author: state.adminActor || 'support',
        });
        await openReport(report.id);
        await loadDashboardData();
      });
    }
    if (!$('reportDialog').open) {
      $('reportDialog').showModal();
    }
    translateAdminDom($('reportDialog'));
  } catch (error) {
    setNotice(`Не удалось открыть отчёт: ${error.message}`, true);
  }
}

async function reviewReport(reportId) {
  if (!requirePermission('support.manage', 'Проверка обращения')) return;
  try {
    await apiPost(`/api/v1/admin/support/reports/${reportId}/review`, {
      assignedTo: currentSupportAssignee(),
      note: 'Отчёт взят в работу из админки Green VPN.',
    });
    await loadDashboardData();
    setNotice('Отчёт взят в работу.');
  } catch (error) {
    setNotice(`Не удалось взять отчёт в работу: ${error.message}`, true);
  }
}

async function resolveReport(reportId) {
  if (!requirePermission('support.manage', 'Закрытие обращения')) return;
  try {
    await apiPost(`/api/v1/admin/support/reports/${reportId}/status`, {
      status: 'resolved',
      note: 'Отмечено решённым из админки Green VPN.',
    });
    await loadDashboardData();
  } catch (error) {
    setNotice(`Не удалось закрыть отчёт: ${error.message}`, true);
  }
}

async function updateIncident(incidentId, payload) {
  if (!requirePermission('incidents.manage', 'Изменение инцидента')) return;
  try {
    await apiPost(`/api/v1/admin/incidents/${encodeURIComponent(incidentId)}`, payload);
    await loadDashboardData();
    setNotice('Инцидент обновлён.');
  } catch (error) {
    setNotice(`Не удалось обновить инцидент: ${error.message}`, true);
  }
}

async function assignIncident(incidentId, assigneeValue) {
  const payload = incidentAssigneeUpdatePayload(assigneeValue);
  await updateIncident(incidentId, {
    ...payload,
    note: assigneeValue ? 'Ответственный назначен из админки Green VPN.' : 'Ответственный снят из админки Green VPN.',
  });
}

function renderMiniOrders(orders = []) {
  if (!orders.length) return '<p class="muted">Заказов пока нет.</p>';
  return `
    <table class="mini-table">
      <thead>
        <tr>
          <th>Заказ</th>
          <th>Сумма</th>
          <th>Статус</th>
          <th>Создан</th>
        </tr>
      </thead>
      <tbody>
        ${orders
          .map(
            (order) => `
              <tr>
                <td>${escapeHtml(order.orderId || order.id)}</td>
                <td>${escapeHtml(money(order.priceRub || order.amountRub))}</td>
                <td>${escapeUi(order.status)}</td>
                <td>${escapeHtml(shortDate(order.createdAt))}</td>
              </tr>
            `,
          )
          .join('')}
      </tbody>
    </table>
  `;
}

function renderMiniReports(reports = []) {
  if (!reports.length) return '<p class="muted">Обращений пока нет.</p>';
  return `
    <table class="mini-table">
      <thead>
        <tr>
          <th>ID</th>
          <th>Сводка</th>
          <th>Статус</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        ${reports
          .map(
            (report) => `
              <tr>
                <td>#${escapeHtml(report.id)}</td>
                <td>${escapeHtml(report.summary)}</td>
                <td>${escapeUi(report.status)}</td>
                <td><button class="small-button" data-report-open="${escapeHtml(report.id)}">Открыть</button></td>
              </tr>
            `,
          )
          .join('')}
      </tbody>
    </table>
  `;
}

function supportActionsWorkflow() {
  return state.loaded.supportActionWorkflow || {
    actions: [
      {
        code: 'reset_user_sessions',
        title: 'Сбросить сессии пользователя',
        requiresDevice: false,
        requiresReason: true,
        danger: true,
        confirmationText: 'Сбросить все сессии пользователя? Он войдёт заново.',
        description: 'Пользователь войдёт заново на устройствах.',
      },
      {
        code: 'request_config_refresh',
        title: 'Запросить обновление конфига',
        requiresDevice: false,
        requiresReason: false,
        danger: false,
        description: 'Помечает устройство или все устройства для саппортной проверки конфига.',
      },
      {
        code: 'clear_config_refresh',
        title: 'Снять запрос обновления конфига',
        requiresDevice: false,
        requiresReason: false,
        danger: false,
        description: 'Очищает саппортную пометку обновления конфига.',
      },
      {
        code: 'disable_device',
        title: 'Отключить устройство',
        requiresDevice: true,
        requiresReason: true,
        danger: true,
        confirmationText: 'Отключить выбранное устройство пользователя?',
        description: 'Отключает конкретное устройство без удаления аккаунта.',
      },
      {
        code: 'enable_device',
        title: 'Включить устройство',
        requiresDevice: true,
        requiresReason: false,
        danger: false,
        description: 'Возвращает конкретное устройство в активное состояние.',
      },
      {
        code: 'add_support_note',
        title: 'Добавить внутреннюю заметку',
        requiresDevice: false,
        requiresReason: true,
        danger: false,
        description: 'Фиксирует заметку в истории действий без изменения аккаунта.',
      },
      {
        code: 'grant_support_trial_3d',
        title: 'Выдать пробный доступ на 3 дня',
        requiresDevice: false,
        requiresReason: true,
        danger: false,
        confirmationText: 'Выдать пользователю временный пробный доступ на 3 дня?',
        description: 'Продлевает пробный доступ на 3 дня и не перезаписывает активную платную подписку.',
      },
    ],
    statuses: ['queued', 'done', 'failed', 'noop'],
  };
}

function supportActionByCode(actionCode) {
  return (supportActionsWorkflow().actions || []).find((action) => action.code === actionCode);
}

function supportActionTitle(actionCode) {
  const action = supportActionByCode(actionCode);
  return action?.title || actionCode || 'Действие';
}

function supportActionStatusClass(status) {
  if (status === 'done') return '';
  if (status === 'noop' || status === 'queued') return 'yellow';
  if (status === 'failed') return 'red';
  return 'muted';
}

function supportActionResultValue(value) {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'object') {
    try {
      return JSON.stringify(value);
    } catch (_) {
      return String(value);
    }
  }
  return String(value);
}

function renderSupportActions(actions = []) {
  if (!can('support_actions.read')) return readonlyActionsHtml('support_actions.read');
  if (!actions.length) return '<p class="muted">Действий поддержки пока нет.</p>';
  return `
    <table class="mini-table">
      <thead>
        <tr>
          <th>Действие</th>
          <th>Статус</th>
          <th>Устройство</th>
          <th>Кто</th>
          <th>Когда</th>
        </tr>
      </thead>
      <tbody>
        ${actions
          .map((action) => {
            const result = action.result ? Object.entries(action.result)
              .map(([key, value]) => `${key}: ${supportActionResultValue(value)}`)
              .join('; ') : '';
            return `
              <tr>
                <td>
                  <strong>${escapeHtml(supportActionTitle(action.action))}</strong><br>
                  <span class="muted">${escapeHtml(action.reason || result || 'Без комментария')}</span>
                </td>
                <td><span class="status-pill ${supportActionStatusClass(action.status)}">${escapeUi(action.status)}</span></td>
                <td>${escapeHtml(action.deviceUid)}</td>
                <td>${escapeHtml(action.requestedBy)}</td>
                <td>${escapeHtml(shortDate(action.createdAt))}</td>
              </tr>
            `;
          })
          .join('')}
      </tbody>
    </table>
  `;
}

function renderSupportActionPanel(user, devices = [], actions = []) {
  if (!can('support_actions.read')) return readonlyActionsHtml('support_actions.read');
  const workflow = supportActionsWorkflow();
  const canManageSupportActions = can('support_actions.manage');
  const actionOptions = (workflow.actions || [])
    .map((action) => `
      <option value="${escapeHtml(action.code)}">
        ${escapeUi(action.danger ? `${action.title} · осторожно` : action.title)}
      </option>
    `)
    .join('');
  const deviceOptions = [
    '<option value="">Все устройства / не требуется</option>',
    ...devices.map((device) => `
      <option value="${escapeHtml(device.deviceUid)}">
        ${escapeHtml(device.deviceName || 'Windows device')} · ${escapeHtml(device.deviceUid)}
      </option>
    `),
  ].join('');

  return `
    <div class="support-action-panel">
      <div class="comment-block">
        <div class="detail-card-head">
          <div>
            <strong>Быстрое действие поддержки</strong>
            <span>Действия пишутся в аудит и не показывают секреты, токены или WireGuard private keys.</span>
          </div>
          <span class="status-pill muted">Пользователь #${escapeHtml(user.id)}</span>
        </div>
        ${
          canManageSupportActions
            ? `
                <div class="form-row stretch">
                  <label>
                    Что сделать
                    <select id="supportActionSelect">${actionOptions}</select>
                  </label>
                  <label>
                    Устройство
                    <select id="supportActionDeviceSelect">${deviceOptions}</select>
                  </label>
                </div>
                <label>
                  Причина / заметка для истории
                  <textarea id="supportActionReasonInput" placeholder="Например: пользователь сообщил, что новый ПК не получает конфиг"></textarea>
                </label>
                <div class="row-actions left">
                  <button class="primary-button" type="button" data-support-action-run="${escapeHtml(user.id)}">
                    Выполнить действие
                  </button>
                </div>
              `
            : readonlyActionsHtml('support_actions.manage')
        }
      </div>
      <div>
        <p class="eyebrow">История действий</p>
        ${renderSupportActions(actions)}
      </div>
    </div>
  `;
}

function renderDeviceCards(devices = []) {
  if (!devices.length) return '<p class="muted">У пользователя пока нет устройств.</p>';
  const canManageDevices = can('devices.manage');
  return `
    <div class="device-grid">
      ${devices
        .map((device) => {
          const isEnabled = Boolean(device.isEnabled);
          return `
            <article class="detail-card">
              <div class="detail-card-head">
                <div>
                  <strong>${escapeHtml(device.deviceName || 'Windows device')}</strong>
                  <span>${escapeHtml(device.deviceUid)}</span>
                </div>
                ${boolPill(isEnabled, 'включено', 'выключено')}
              </div>
              <div class="detail-meta">
                <span>Платформа: ${escapeHtml(device.platform)}</span>
                <span>Версия приложения: ${escapeHtml(device.appVersion)}</span>
                <span>IP: ${escapeHtml(device.assignedIp)}</span>
                <span>Последний сигнал: ${escapeHtml(shortDate(device.lastSeenAt))}</span>
                <span>Последний конфиг: ${escapeHtml(shortDate(device.lastConfigAt))}</span>
                <span>Запрос обновления конфига: ${
                  device.supportConfigRefreshRequestedAt
                    ? `${escapeHtml(shortDate(device.supportConfigRefreshRequestedAt))} · ${escapeHtml(device.supportConfigRefreshReason)}`
                    : 'нет'
                }</span>
                <span>Обновление применено: ${
                  device.supportConfigRefreshAppliedAt
                    ? `${escapeHtml(shortDate(device.supportConfigRefreshAppliedAt))} · ${escapeHtml(device.supportConfigRefreshAppliedReason)}`
                    : 'нет'
                }</span>
                <span>Причина отключения: ${escapeHtml(device.disabledReason)}</span>
              </div>
              <div class="row-actions left">
                ${
                  canManageDevices
                    ? (
                        isEnabled
                          ? `<button class="small-button danger" data-device-disable="${escapeHtml(device.deviceUid)}">Отключить</button>`
                          : `<button class="small-button" data-device-enable="${escapeHtml(device.deviceUid)}">Включить</button>`
                      )
                    : readonlyActionsHtml('devices.manage')
                }
              </div>
            </article>
          `;
        })
        .join('')}
    </div>
  `;
}

function renderUserPaymentSummary(subscription = {}, orders = []) {
  const latestOrder = orders[0] || null;
  return `
    <section class="detail-card">
      <p class="eyebrow">Деньги</p>
      <h3>${escapeHtml(subscription.planName || 'Платной подписки нет')}</h3>
      <div class="detail-meta">
        <span>Подписка активна: ${boolLabel(subscription.isActive)}</span>
        <span>Действует до: ${escapeHtml(shortDate(subscription.expiresAt))}</span>
        <span>Автопродление: ${boolLabel(subscription.autoRenew)}</span>
        <span>Последний заказ: ${latestOrder ? escapeHtml(latestOrder.orderId || latestOrder.id) : 'нет'}</span>
        <span>Статус заказа: ${latestOrder ? escapeUi(latestOrder.status) : '—'}</span>
        <span>Сумма заказа: ${latestOrder ? escapeHtml(money(latestOrder.priceRub || latestOrder.amountRub)) : '—'}</span>
      </div>
      <div class="row-actions left">
        <button class="small-button" type="button" data-user-open-billing>Открыть раздел платежей</button>
      </div>
    </section>
  `;
}

function renderUserOperatorActions(user, devices = []) {
  const canManageUsers = can('users.manage');
  const canManageDevices = can('devices.manage');
  const canManageSupport = can('support_actions.manage');
  const enabledDevices = devices.filter((device) => device.isEnabled);
  return `
    <section class="detail-card danger-zone">
      <p class="eyebrow">Управление аккаунтом</p>
      <h3>Быстрые действия администратора</h3>
      <div class="detail-meta">
        <span>Все действия попадают в журнал. Секреты, пароли и WireGuard private keys здесь не показываются.</span>
        <span>Полное удаление стирает аккаунт, устройства, заказы, коды входа, обращения и внутренние действия поддержки.</span>
      </div>
      <div class="operator-action-grid">
        <button class="small-button" type="button" data-user-reset-sessions="${escapeHtml(user.id)}" ${canManageSupport ? '' : 'disabled'}>
          Сбросить входы
        </button>
        <button class="small-button" type="button" data-user-refresh-configs="${escapeHtml(user.id)}" ${canManageSupport ? '' : 'disabled'}>
          Обновить конфиги
        </button>
        <button class="small-button danger" type="button" data-user-disable-all-devices="${escapeHtml(user.id)}" ${canManageDevices && enabledDevices.length ? '' : 'disabled'}>
          Отключить все устройства
        </button>
        <button class="small-button danger" type="button" data-user-delete="${escapeHtml(user.id)}" ${canManageUsers ? '' : 'disabled'}>
          Удалить аккаунт
        </button>
      </div>
      <p class="muted compact-note">
        Если кнопка неактивна, у текущей роли нет нужного права или у пользователя нет активных устройств.
      </p>
    </section>
  `;
}

async function openUser(userId) {
  try {
    state.activeUserId = userId;
    const response = await apiGet(`/api/v1/admin/users/${userId}`);
    state.activeUserDetail = response;
    const user = response.user;
    const subscription = response.subscription || user.subscription || {};
    $('userDialogTitle').textContent = `${user.email || user.phone || `Пользователь #${user.id}`}`;
    $('userDialogBody').innerHTML = `
      <div class="detail-grid">
        <section class="detail-card">
          <p class="eyebrow">Аккаунт</p>
          <h3>${escapeHtml(user.email || 'Email не указан')}</h3>
          <div class="detail-meta">
            <span>ID: #${escapeHtml(user.id)}</span>
            <span>Телефон: ${escapeHtml(user.phone)}</span>
            <span>Почта подтверждена: ${boolLabel(user.emailVerified)}</span>
            <span>Телефон подтверждён: ${boolLabel(user.phoneVerified)}</span>
            <span>Создан: ${escapeHtml(shortDate(user.createdAt))}</span>
          </div>
        </section>
        ${renderUserPaymentSummary(subscription, response.orders || [])}
      </div>
      ${renderUserOperatorActions(user, response.devices || [])}
      <section>
        <p class="eyebrow">Устройства</p>
        ${renderDeviceCards(response.devices || [])}
      </section>
      <section>
        <p class="eyebrow">Последние заказы</p>
        ${renderMiniOrders(response.orders || [])}
      </section>
      <section>
        <p class="eyebrow">Последние обращения</p>
        ${renderMiniReports(response.supportReports || [])}
      </section>
      <section>
        <p class="eyebrow">Действия поддержки</p>
        ${renderSupportActionPanel(user, response.devices || [], response.supportActions || [])}
      </section>
    `;
    if (!$('userDialog').open) {
      $('userDialog').showModal();
    }
    translateAdminDom($('userDialog'));
  } catch (error) {
    setNotice(`Не удалось открыть пользователя: ${error.message}`, true);
  }
}

async function performSupportAction(userId) {
  if (!requirePermission('support_actions.manage', 'Действие поддержки')) return;
  const action = $('supportActionSelect')?.value || '';
  const deviceUid = $('supportActionDeviceSelect')?.value || '';
  const reason = $('supportActionReasonInput')?.value || '';
  const actionMeta = supportActionByCode(action);
  if (!action) {
    setNotice('Выбери действие поддержки.', true);
    return;
  }
  if (actionMeta?.requiresDevice && !deviceUid) {
    setNotice('Для этого действия нужно выбрать конкретное устройство.', true);
    return;
  }
  if (actionMeta?.requiresReason && reason.trim().length < 8) {
    setNotice('Для этого действия нужна понятная причина в истории поддержки.', true);
    return;
  }
  if (actionMeta?.danger || actionMeta?.confirmationText) {
    const confirmed = window.confirm(actionMeta.confirmationText || `Выполнить действие: ${supportActionTitle(action)}?`);
    if (!confirmed) {
      setNotice('Действие отменено.');
      return;
    }
  }
  try {
    await apiPost(`/api/v1/admin/users/${encodeURIComponent(userId)}/support-actions`, {
      action,
      deviceUid: deviceUid || null,
      reason,
      note: reason,
    });
    await openUser(userId);
    await loadDashboardData();
    setNotice(`Действие выполнено: ${supportActionTitle(action)}.`);
  } catch (error) {
    setNotice(`Не удалось выполнить действие поддержки: ${error.message}`, true);
  }
}

async function toggleDevice(deviceUid, enabled) {
  if (!requirePermission('devices.manage', 'Изменение устройства')) return;
  try {
    const path = enabled
      ? `/api/v1/admin/devices/${encodeURIComponent(deviceUid)}/enable`
      : `/api/v1/admin/devices/${encodeURIComponent(deviceUid)}/disable`;
    await apiPost(path, {
      reason: enabled ? 'support_manual_enable' : 'support_manual_disable',
    });
    if (state.activeUserId) {
      await openUser(state.activeUserId);
    }
    await loadDashboardData();
  } catch (error) {
    setNotice(`Не удалось изменить устройство: ${error.message}`, true);
  }
}

async function runQuickUserSupportAction(userId, action, reason, deviceUid = null) {
  if (!requirePermission('support_actions.manage', 'Действие с пользователем')) return;
  try {
    await apiPost(`/api/v1/admin/users/${encodeURIComponent(userId)}/support-actions`, {
      action,
      deviceUid,
      reason,
      note: reason,
    });
    if (state.activeUserId) {
      await openUser(state.activeUserId);
    }
    await loadDashboardData();
    setNotice(`Готово: ${supportActionTitle(action)}.`);
  } catch (error) {
    setNotice(`Не удалось выполнить действие: ${error.message}`, true);
  }
}

async function resetUserSessions(userId) {
  const confirmed = window.confirm('Сбросить все входы пользователя? Он войдёт заново.');
  if (!confirmed) return;
  await runQuickUserSupportAction(userId, 'reset_user_sessions', 'Сброс сессий из карточки пользователя.');
}

async function refreshUserConfigs(userId) {
  await runQuickUserSupportAction(userId, 'request_config_refresh', 'Запрос обновления конфигов из карточки пользователя.');
}

async function disableAllUserDevices(userId) {
  if (!requirePermission('devices.manage', 'Отключение устройств пользователя')) return;
  const devices = (state.activeUserDetail?.devices || []).filter((device) => device.isEnabled);
  if (!devices.length) {
    setNotice('У пользователя нет активных устройств.');
    return;
  }
  const confirmed = window.confirm(`Отключить все активные устройства пользователя (${devices.length} шт.)?`);
  if (!confirmed) return;
  try {
    for (const device of devices) {
      await apiPost(`/api/v1/admin/devices/${encodeURIComponent(device.deviceUid)}/disable`, {
        reason: 'Отключение всех устройств из карточки пользователя.',
      });
    }
    if (state.activeUserId) {
      await openUser(state.activeUserId);
    }
    await loadDashboardData();
    setNotice(`Отключено устройств: ${devices.length}.`);
  } catch (error) {
    setNotice(`Не удалось отключить устройства: ${error.message}`, true);
  }
}

async function deleteUserRecord(userId) {
  if (!requirePermission('users.manage', 'Удаление пользователя')) return;
  const detail = state.activeUserDetail || {};
  const user = detail.user || {};
  const email = user.email || '';
  const confirmEmail = email
    ? window.prompt(`Для удаления введи почту пользователя: ${email}`)
    : window.prompt('У пользователя нет почты. Для удаления введи слово DELETE.');
  if (confirmEmail === null) return;
  if (email && confirmEmail.trim().toLowerCase() !== email.trim().toLowerCase()) {
    setNotice('Почта не совпала. Удаление отменено.', true);
    return;
  }
  if (!email && confirmEmail.trim() !== 'DELETE') {
    setNotice('Подтверждение не совпало. Удаление отменено.', true);
    return;
  }
  const reason = window.prompt('Причина удаления для журнала:', 'Очистка тестового аккаунта перед запуском.');
  if (reason === null) return;
  if (reason.trim().length < 8) {
    setNotice('Причина удаления должна быть понятной: минимум 8 символов.', true);
    return;
  }
  const finalConfirm = window.confirm('Последнее подтверждение: удалить аккаунт и связанные записи без восстановления?');
  if (!finalConfirm) return;

  try {
    const result = await apiPost(`/api/v1/admin/users/${encodeURIComponent(userId)}/delete`, {
      confirmEmail: email || null,
      reason: reason.trim(),
    });
    state.activeUserId = null;
    state.activeUserDetail = null;
    $('userDialog')?.close();
    await loadDashboardData();
    setNotice(`Пользователь удалён. Таблиц очищено: ${Object.keys(result.deleted || {}).length}.`);
  } catch (error) {
    setNotice(`Не удалось удалить пользователя: ${error.message}`, true);
  }
}

async function toggleStaffActive(staffId, isActive) {
  if (!requirePermission('staff.manage', 'Изменение сотрудника')) return;
  try {
    const staff = (state.loaded.staff || []).find((item) => Number(item.id) === Number(staffId));
    await apiPost(`/api/v1/admin/staff/${encodeURIComponent(staffId)}`, {
      displayName: staff?.displayName || '',
      role: staff?.role || 'support',
      isActive,
      twoFactorEnabled: Boolean(staff?.twoFactorEnabled),
    });
    await loadDashboardData();
    setNotice(isActive ? 'Сотрудник включён.' : 'Сотрудник выключен.');
  } catch (error) {
    setNotice(`Не удалось изменить сотрудника: ${error.message}`, true);
  }
}

async function testAdminAlert() {
  if (!requirePermission('incidents.manage', 'Тестовый alert')) return;
  try {
    const result = await apiPost('/api/v1/admin/alerts/test', {});
    await loadDashboardData();
    setNotice(`Тестовое оповещение Telegram отправлено: ${safeText(result?.result?.status, 'ok')}.`);
  } catch (error) {
    setNotice(`Оповещение Telegram пока не готово: ${error.message}`, true);
  }
}

function bindEvents() {
  $('loginForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    try {
      state.apiBase = normalizeApiBase($('apiBaseInput')?.value || DEFAULT_API_BASE);
      if (state.pendingAdmin2fa) {
        await verifyAdminTwoFactor();
        return;
      }
      const email = $('adminEmailInput').value.trim().toLowerCase();
      const password = $('adminPasswordInput').value;
      const actor = $('adminActorInput')?.value.trim() || email || 'staff';
      if (email && password) {
        const loginResult = await loginWithStaffSession(email, password, actor);
        if (loginResult?.pending) return;
      } else {
        setNotice('Введите почту и пароль сотрудника.', true);
        return;
      }
      saveSession($('rememberTokenInput').checked);
      $('loginPanel').classList.add('hidden');
      $('adminPasswordInput').value = '';
      applyAuthUi();
      await loadDashboardData();
    } catch (error) {
      setNotice(`Не удалось войти: ${error.message}`, true);
      setSidebarStatus('ошибка входа', 'red');
    }
  });

  $('openLoginButton').addEventListener('click', () => {
    $('loginPanel').classList.toggle('hidden');
  });
  $('logoutButton')?.addEventListener('click', logoutAdmin);
  $('admin2faVerifyButton')?.addEventListener('click', async () => {
    try {
      await verifyAdminTwoFactor();
    } catch (error) {
      setNotice(`Не удалось подтвердить код: ${error.message}`, true);
      setSidebarStatus('ошибка 2FA', 'red');
    }
  });
  $('admin2faCancelButton')?.addEventListener('click', cancelAdminTwoFactor);
  $('passwordChangeForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    await changeCurrentPassword();
  });
  $('revokeOtherSessionsButton')?.addEventListener('click', revokeOtherAdminSessions);

  $('refreshButton').addEventListener('click', loadDashboardData);
  $('testAlertsButton')?.addEventListener('click', testAdminAlert);
  $('supportStatusFilter').addEventListener('change', loadDashboardData);
  $('supportPriorityFilter')?.addEventListener('change', loadDashboardData);
  $('supportCategoryFilter')?.addEventListener('change', loadDashboardData);
  $('supportActionTypeFilter')?.addEventListener('change', loadDashboardData);
  $('supportActionStatusFilter')?.addEventListener('change', loadDashboardData);
  $('incidentStatusFilter')?.addEventListener('change', loadDashboardData);
  $('incidentSeverityFilter')?.addEventListener('change', loadDashboardData);
  $('incidentAssigneeFilter')?.addEventListener('change', loadDashboardData);
  $('authTypeFilter')?.addEventListener('change', loadDashboardData);
  $('authStatusFilter')?.addEventListener('change', loadDashboardData);
  $('releaseChannelFilter')?.addEventListener('change', loadDashboardData);
  $('releaseStatusFilter')?.addEventListener('change', loadDashboardData);
  $('serverStatusFilter')?.addEventListener('change', loadDashboardData);
  $('serverActiveFilter')?.addEventListener('change', loadDashboardData);
  $('serverPublicFilter')?.addEventListener('change', loadDashboardData);
  $('serverHealthStatusFilter')?.addEventListener('change', loadDashboardData);
  const delayedReload = debounce(loadDashboardData, 350);
  $('supportSearchInput')?.addEventListener('input', delayedReload);
  $('supportAssignedFilter')?.addEventListener('input', delayedReload);
  $('supportActionUserFilter')?.addEventListener('input', delayedReload);
  $('userSearchInput')?.addEventListener('input', delayedReload);
  $('authSearchInput')?.addEventListener('input', delayedReload);
  $('serverHealthEndpointFilter')?.addEventListener('input', delayedReload);
  $('monitoringTargetStatusFilter')?.addEventListener('change', loadDashboardData);
  $('monitoringTargetServiceFilter')?.addEventListener('input', delayedReload);
  $('serviceObservationStatusFilter')?.addEventListener('change', loadDashboardData);
  $('serviceObservationTargetFilter')?.addEventListener('input', delayedReload);
  $('clientRouteStageFilter')?.addEventListener('change', loadDashboardData);
  $('clientRouteOkFilter')?.addEventListener('change', loadDashboardData);
  $('clientRouteServerFilter')?.addEventListener('input', delayedReload);
  $('releaseForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    await saveRelease();
  });
  $('featureFlagForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    await saveFeatureFlag();
  });
  $('resetFeatureFlagForm')?.addEventListener('click', resetFeatureFlagForm);
  $('promoForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    await savePromoCode();
  });
  $('promoFillStartButton')?.addEventListener('click', fillRecommendedStartPromoForm);
  $('promoDraftStartButton')?.addEventListener('click', createRecommendedStartPromoDraft);
  $('runbookForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    await saveRunbook();
  });
  $('resetRunbookForm')?.addEventListener('click', resetRunbookForm);
  $('serverForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    await saveServerEntry();
  });
  $('createPlannedServerDraftButton')?.addEventListener('click', createPlannedServerDraft);
  $('seedCurrentServerButton')?.addEventListener('click', seedCurrentServerEndpoint);
  $('probeCurrentServerButton')?.addEventListener('click', probeCurrentServerEndpoint);
  $('seedDefaultMonitoringTargetsButton')?.addEventListener('click', seedDefaultMonitoringTargets);
  $('monitoringTargetForm')?.addEventListener('submit', async (event) => {
    event.preventDefault();
    await saveMonitoringTarget();
  });
  $('resetMonitoringTargetForm')?.addEventListener('click', resetMonitoringTargetForm);
  $('staffForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!requirePermission('staff.manage', 'Сохранение сотрудника')) return;
    try {
      await apiPost('/api/v1/admin/staff', {
        email: $('staffEmailInput').value,
        displayName: $('staffNameInput').value,
        role: $('staffRoleInput').value || 'support',
        isActive: $('staffActiveInput').checked,
        twoFactorEnabled: $('staffTwoFactorInput').checked,
        temporaryPassword: $('staffPasswordInput').value,
      });
      $('staffEmailInput').value = '';
      $('staffNameInput').value = '';
      $('staffPasswordInput').value = '';
      $('staffRoleInput').value = 'support';
      $('staffActiveInput').checked = true;
      $('staffTwoFactorInput').checked = false;
      await loadDashboardData();
      setNotice('Сотрудник сохранён.');
    } catch (error) {
      setNotice(`Не удалось сохранить сотрудника: ${error.message}`, true);
    }
  });

  document.querySelectorAll('.nav-link').forEach((button) => {
    button.addEventListener('click', () => switchSection(button.dataset.section));
  });

  document.body.addEventListener('change', (event) => {
    const assigneeSelect = event.target.closest('[data-incident-assignee]');
    if (assigneeSelect) {
      assignIncident(assigneeSelect.dataset.incidentAssignee, assigneeSelect.value);
    }
  });

  document.body.addEventListener('click', (event) => {
    const promoEditButton = event.target.closest('[data-promo-edit]');
    if (promoEditButton) {
      fillPromoForm(findPromoCode(promoEditButton.dataset.promoEdit));
      setNotice('Акция загружена в форму.');
      return;
    }
    const promoActivateButton = event.target.closest('[data-promo-activate]');
    if (promoActivateButton) {
      setPromoActive(promoActivateButton.dataset.promoActivate, true);
      return;
    }
    const promoDeactivateButton = event.target.closest('[data-promo-deactivate]');
    if (promoDeactivateButton) {
      setPromoActive(promoDeactivateButton.dataset.promoDeactivate, false);
      return;
    }
    const expiryReviewButton = event.target.closest('[data-expiry-review]');
    if (expiryReviewButton) {
      reviewSubscriptionExpiry(expiryReviewButton.dataset.expiryReview);
      return;
    }
    const openButton = event.target.closest('[data-report-open]');
    if (openButton) {
      openReport(openButton.dataset.reportOpen);
      return;
    }
    const sessionRevokeButton = event.target.closest('[data-admin-session-revoke]');
    if (sessionRevokeButton) {
      revokeAdminSession(sessionRevokeButton.dataset.adminSessionRevoke);
      return;
    }
    const staffSessionsButton = event.target.closest('[data-staff-sessions]');
    if (staffSessionsButton) {
      openStaffSessions(staffSessionsButton.dataset.staffSessions);
      return;
    }
    const staffSessionRevokeButton = event.target.closest('[data-staff-session-revoke]');
    if (staffSessionRevokeButton) {
      revokeStaffSession(
        staffSessionRevokeButton.dataset.staffSessionRevoke,
        staffSessionRevokeButton.dataset.sessionId,
      );
      return;
    }
    const staffSessionsRevokeAllButton = event.target.closest('[data-staff-sessions-revoke-all]');
    if (staffSessionsRevokeAllButton) {
      revokeAllStaffSessions(staffSessionsRevokeAllButton.dataset.staffSessionsRevokeAll);
      return;
    }
    const resolveButton = event.target.closest('[data-report-resolve]');
    if (resolveButton) {
      resolveReport(resolveButton.dataset.reportResolve);
      return;
    }
    const reviewButton = event.target.closest('[data-report-review]');
    if (reviewButton) {
      reviewReport(reviewButton.dataset.reportReview);
      return;
    }
    const incidentInvestigateButton = event.target.closest('[data-incident-investigate]');
    if (incidentInvestigateButton) {
      updateIncident(incidentInvestigateButton.dataset.incidentInvestigate, {
        status: 'investigating',
        ...currentIncidentAssigneePayload(),
        note: 'Инцидент взят в работу из админки Green VPN.',
      });
      return;
    }
    const incidentResolveButton = event.target.closest('[data-incident-resolve]');
    if (incidentResolveButton) {
      updateIncident(incidentResolveButton.dataset.incidentResolve, {
        status: 'resolved',
        ...currentIncidentAssigneePayload(),
        note: 'Инцидент закрыт вручную из админки Green VPN.',
      });
      return;
    }
    const incidentOpenButton = event.target.closest('[data-incident-open]');
    if (incidentOpenButton) {
      updateIncident(incidentOpenButton.dataset.incidentOpen, {
        status: 'open',
        ...currentIncidentAssigneePayload(),
        note: 'Инцидент переоткрыт вручную из админки Green VPN.',
      });
      return;
    }
    const userButton = event.target.closest('[data-user-open]');
    if (userButton) {
      openUser(userButton.dataset.userOpen);
      return;
    }
    const disableDeviceButton = event.target.closest('[data-device-disable]');
    if (disableDeviceButton) {
      toggleDevice(disableDeviceButton.dataset.deviceDisable, false);
      return;
    }
    const enableDeviceButton = event.target.closest('[data-device-enable]');
    if (enableDeviceButton) {
      toggleDevice(enableDeviceButton.dataset.deviceEnable, true);
      return;
    }
    const supportActionRunButton = event.target.closest('[data-support-action-run]');
    if (supportActionRunButton) {
      performSupportAction(supportActionRunButton.dataset.supportActionRun);
      return;
    }
    const userResetSessionsButton = event.target.closest('[data-user-reset-sessions]');
    if (userResetSessionsButton) {
      resetUserSessions(userResetSessionsButton.dataset.userResetSessions);
      return;
    }
    const userRefreshConfigsButton = event.target.closest('[data-user-refresh-configs]');
    if (userRefreshConfigsButton) {
      refreshUserConfigs(userRefreshConfigsButton.dataset.userRefreshConfigs);
      return;
    }
    const userDisableAllDevicesButton = event.target.closest('[data-user-disable-all-devices]');
    if (userDisableAllDevicesButton) {
      disableAllUserDevices(userDisableAllDevicesButton.dataset.userDisableAllDevices);
      return;
    }
    const userDeleteButton = event.target.closest('[data-user-delete]');
    if (userDeleteButton) {
      deleteUserRecord(userDeleteButton.dataset.userDelete);
      return;
    }
    const userOpenBillingButton = event.target.closest('[data-user-open-billing]');
    if (userOpenBillingButton) {
      $('userDialog')?.close();
      switchSection('orders');
      setNotice('Раздел платежей открыт. Последние платежи выбранного пользователя также видны в его карточке.');
      return;
    }
    const ownerActionSaveButton = event.target.closest('[data-owner-action-save]');
    if (ownerActionSaveButton) {
      saveOwnerActionStatus(ownerActionSaveButton.dataset.ownerActionSave);
      return;
    }
    const staffToggleButton = event.target.closest('[data-staff-toggle]');
    if (staffToggleButton) {
      toggleStaffActive(
        Number(staffToggleButton.dataset.staffToggle),
        staffToggleButton.dataset.staffActive === '1',
      );
      return;
    }
    const releaseEditButton = event.target.closest('[data-release-edit]');
    if (releaseEditButton) {
      if (!requirePermission('updates.manage', 'Редактирование версии')) return;
      fillReleaseForm(findRelease(releaseEditButton.dataset.releaseEdit));
      setNotice('Версия загружена в форму. Можно поправить поля и сохранить.');
      return;
    }
    const releasePublishButton = event.target.closest('[data-release-publish]');
    if (releasePublishButton) {
      updateReleaseStatus(releasePublishButton.dataset.releasePublish, 'published');
      return;
    }
    const releasePauseButton = event.target.closest('[data-release-pause]');
    if (releasePauseButton) {
      updateReleaseStatus(releasePauseButton.dataset.releasePause, 'paused');
      return;
    }
    const releaseRetireButton = event.target.closest('[data-release-retire]');
    if (releaseRetireButton) {
      updateReleaseStatus(releaseRetireButton.dataset.releaseRetire, 'retired');
      return;
    }

    const featureFlagEditButton = event.target.closest('[data-feature-flag-edit]');
    if (featureFlagEditButton) {
      if (!requirePermission('flags.manage', 'Редактирование переключателя функции')) return;
      fillFeatureFlagForm(findFeatureFlag(featureFlagEditButton.dataset.featureFlagEdit));
      setNotice('Переключатель функции загружен в форму. Можно поправить поля и сохранить.');
      return;
    }
    const featureFlagEnableButton = event.target.closest('[data-feature-flag-enable]');
    if (featureFlagEnableButton) {
      updateFeatureFlagEnabled(featureFlagEnableButton.dataset.featureFlagEnable, true);
      return;
    }
    const featureFlagDisableButton = event.target.closest('[data-feature-flag-disable]');
    if (featureFlagDisableButton) {
      updateFeatureFlagEnabled(featureFlagDisableButton.dataset.featureFlagDisable, false);
      return;
    }

    const runbookEditButton = event.target.closest('[data-runbook-edit]');
    if (runbookEditButton) {
      if (!requirePermission('runbooks.manage', 'Редактирование инструкции')) return;
      fillRunbookForm(findRunbook(runbookEditButton.dataset.runbookEdit));
      setNotice('Инструкция загружена в форму. Можно поправить поля и сохранить.');
      return;
    }
    const runbookActivateButton = event.target.closest('[data-runbook-activate]');
    if (runbookActivateButton) {
      updateRunbookActive(runbookActivateButton.dataset.runbookActivate, true);
      return;
    }
    const runbookArchiveButton = event.target.closest('[data-runbook-archive]');
    if (runbookArchiveButton) {
      updateRunbookActive(runbookArchiveButton.dataset.runbookArchive, false);
      return;
    }

    const serverEditButton = event.target.closest('[data-server-edit]');
    if (serverEditButton) {
      if (!requirePermission('servers.manage', 'Редактирование VPN-узла')) return;
      fillServerForm(findServerEntry(serverEditButton.dataset.serverEdit));
      setNotice('VPN-узел загружен в форму. Можно поправить поля и сохранить.');
      return;
    }
    const serverHealthyButton = event.target.closest('[data-server-healthy]');
    if (serverHealthyButton) {
      updateServerEntryStatus(serverHealthyButton.dataset.serverHealthy, 'healthy');
      return;
    }
    const serverRemoteSmokeButton = event.target.closest('[data-server-remote-smoke]');
    if (serverRemoteSmokeButton) {
      runRemotePeerSmoke(serverRemoteSmokeButton.dataset.serverRemoteSmoke);
      return;
    }
    const serverClientConfigSmokeButton = event.target.closest('[data-server-client-config-smoke]');
    if (serverClientConfigSmokeButton) {
      runClientConfigSmoke(serverClientConfigSmokeButton.dataset.serverClientConfigSmoke);
      return;
    }
    const serverPublishButton = event.target.closest('[data-server-publish]');
    if (serverPublishButton) {
      publishServerEntry(serverPublishButton.dataset.serverPublish);
      return;
    }
    const serverUnpublishButton = event.target.closest('[data-server-unpublish]');
    if (serverUnpublishButton) {
      unpublishServerEntry(serverUnpublishButton.dataset.serverUnpublish);
      return;
    }
    const serverDisableButton = event.target.closest('[data-server-disable]');
    if (serverDisableButton) {
      updateServerEntryStatus(serverDisableButton.dataset.serverDisable, 'disabled');
      return;
    }

    const monitoringTargetEditButton = event.target.closest('[data-monitoring-target-edit]');
    if (monitoringTargetEditButton) {
      if (!requirePermission('monitoring.manage', 'Редактирование цели мониторинга')) return;
      fillMonitoringTargetForm(findMonitoringTarget(monitoringTargetEditButton.dataset.monitoringTargetEdit));
      setNotice('Цель мониторинга загружена в форму. Можно поправить поля и сохранить.');
      return;
    }
    const monitoringTargetActiveButton = event.target.closest('[data-monitoring-target-active]');
    if (monitoringTargetActiveButton) {
      updateMonitoringTargetStatus(monitoringTargetActiveButton.dataset.monitoringTargetActive, 'active');
      return;
    }
    const monitoringTargetPauseButton = event.target.closest('[data-monitoring-target-pause]');
    if (monitoringTargetPauseButton) {
      updateMonitoringTargetStatus(monitoringTargetPauseButton.dataset.monitoringTargetPause, 'paused');
      return;
    }
    const monitoringTargetDisableButton = event.target.closest('[data-monitoring-target-disable]');
    if (monitoringTargetDisableButton) {
      updateMonitoringTargetStatus(monitoringTargetDisableButton.dataset.monitoringTargetDisable, 'disabled');
    }
  });

  $('closeReportDialog').addEventListener('click', () => $('reportDialog').close());
  $('closeUserDialog').addEventListener('click', () => {
    $('userDialog').close();
    state.activeUserId = null;
    state.activeUserDetail = null;
  });
  $('userDialog')?.addEventListener('close', () => {
    state.activeUserId = null;
    state.activeUserDetail = null;
  });
}

function init() {
  loadSession();
  $('apiBaseInput').value = state.apiBase || DEFAULT_API_BASE;
  $('adminEmailInput').value = state.adminEmail;
  $('adminTokenInput').value = '';
  $('adminActorInput').value = state.adminActor || state.adminEmail || '';
  $('sidebarApiBase').textContent = 'Green VPN';
  bindEvents();
  renderAll();
  applyAuthUi();
  if (hasAdminCredential()) {
    $('loginPanel').classList.add('hidden');
    loadDashboardData();
  } else {
    setSidebarStatus('не подключено', 'muted');
  }
}

init();
