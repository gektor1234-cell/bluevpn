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
  loaded: {
    overview: null,
    analytics: null,
    launchReadiness: null,
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
    monitoringTargets: null,
    serviceObservations: null,
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
  return text || fallback || 'Request failed.';
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
        ${escapeHtml(item.title || item.code)}
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
    stable: 'Stable',
    beta: 'Beta',
    internal: 'Internal',
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
    container.innerHTML = '<p class="muted">Release readiness пока не загружен.</p>';
    return;
  }

  const manifest = readiness.manifest || {};
  const releaseGate = readiness.latestReleaseReadiness || readiness.latestPublishedRelease?.releaseReadiness || {};
  const rollbackGate = readiness.rollbackReadiness || releaseGate.rollbackReadiness || {};
  const checks = readiness.checks || [];
  const summary = readiness.summary || {};
  const header = {
    title: readiness.productionReady
      ? 'Updater готов к публичному rollout'
      : 'Updater ждёт финальный артефакт',
    message: `${summary.message || ''} latest=${manifest.latestVersion || '—'}, fileReady=${boolLabel(manifest.fileReady)}, publicHttps=${boolLabel(manifest.publicHttpsReady)}, rollback=${boolLabel(rollbackGate.rollbackReady)}`,
    ok: Boolean(readiness.productionReady),
    warning: !readiness.productionReady,
    pill: readiness.productionReady ? 'ready' : 'draft',
  };
  container.innerHTML = [header, ...checks]
    .map(
      (item) => `
        <div class="check-row">
          ${statusDot(Boolean(item.ok), !item.ok || item.warning)}
          <div>
            <strong>${escapeHtml(item.title || item.code)}</strong>
            <span>${escapeHtml(item.message || '')}</span>
          </div>
          <span class="status-pill ${item.ok ? '' : 'yellow'}">${escapeHtml(item.pill || (item.ok ? 'ok' : 'todo'))}</span>
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
    container.innerHTML = '<p class="muted">Manifest пока не загружен.</p>';
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
      pill: manifest.updateAvailable ? 'update' : 'current',
    },
    {
      title: 'Файл обновления',
      message: manifest.downloadUrl || 'Ссылка на загрузку ещё не опубликована',
      ok: fileReady,
      warning: !fileReady,
      pill: fileReady ? 'ready' : 'draft',
    },
    {
      title: 'Publication gate',
      message: `${releaseGate.summary || 'Нет опубликованного release для проверки'} ${releaseGate.blockers?.length ? `blockers=${releaseGate.blockers.join(', ')}` : ''}`,
      ok: Boolean(releaseGate.canPublish),
      warning: !releaseGate.canPublish,
      pill: releaseGate.canPublish ? 'ready' : 'blocked',
    },
    {
      title: 'Rollback plan',
      message: `${rollbackGate.summary || 'No rollback artifact is configured yet.'} ${rollbackGate.blockers?.length ? `blockers=${rollbackGate.blockers.join(', ')}` : ''}`,
      ok: Boolean(rollbackGate.rollbackReady),
      warning: !rollbackGate.rollbackReady,
      pill: rollbackGate.rollbackReady ? 'ready' : 'staged',
    },
    {
      title: 'Обязательность и rollout',
      message: `обязательное=${manifest.required ? 'да' : 'нет'}, rollout=${manifest.rolloutPercent ?? 100}%, подходит=${manifest.rolloutEligible ? 'да' : 'нет'}, причина=${manifest.rolloutReason || '—'}`,
      ok: !manifest.releaseBlocked,
      warning: Boolean(manifest.releaseBlocked),
      pill: manifest.required ? 'required' : (manifest.releaseBlocked ? 'blocked' : 'optional'),
    },
  ];
  container.innerHTML = items
    .map(
      (item) => `
        <div class="check-row">
          ${statusDot(item.ok, item.warning)}
          <div>
            <strong>${escapeHtml(item.title)}</strong>
            <span>${escapeHtml(item.message)}</span>
          </div>
          <span class="status-pill ${item.ok ? '' : 'yellow'}">${escapeHtml(item.pill)}</span>
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
              <span class="status-pill ${readiness.canPublish ? '' : 'yellow'}">${readiness.canPublish ? 'gate ready' : 'blocked'}</span>
              <span class="status-pill ${rollbackGate.rollbackReady ? '' : 'yellow'}">${rollbackGate.rollbackReady ? 'rollback ready' : 'rollback staged'}</span>
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
      .join('') || '<tr><td colspan="8">Release-версий пока нет.</td></tr>';
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
  if (!requirePermission('updates.manage', 'Сохранение release')) return;
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
    setNotice('Release сохранён.');
  } catch (error) {
    setNotice(`Не удалось сохранить release: ${error.message}`, true);
  }
}

async function updateReleaseStatus(releaseId, status) {
  if (!requirePermission('updates.manage', 'Изменение статуса release')) return;
  const release = findRelease(releaseId);
  if (!release) {
    setNotice('Release не найден в текущем списке.', true);
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
      'backend',
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
  if (!requirePermission('flags.manage', 'Сохранение feature flag')) return;
  try {
    const flagId = $('featureFlagIdInput').value;
    const path = flagId
      ? `/api/v1/admin/feature-flags/${encodeURIComponent(flagId)}`
      : '/api/v1/admin/feature-flags';
    await apiPost(path, featureFlagFormPayload(enabledOverride));
    resetFeatureFlagForm();
    await loadDashboardData();
    setNotice('Feature flag сохранён.');
  } catch (error) {
    setNotice(`Не удалось сохранить feature flag: ${error.message}`, true);
  }
}

async function updateFeatureFlagEnabled(flagId, isEnabled) {
  const flag = findFeatureFlag(flagId);
  if (!flag) {
    setNotice('Feature flag не найден в текущем списке.', true);
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
          <td>${boolPill(flag.isEnabled, 'enabled', 'disabled')}</td>
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
      .join('') || '<tr><td colspan="7">Feature flags ещё не загружены. Backend создаст базовый набор на старте.</td></tr>';
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
            <span class="muted">${escapeHtml(runbook.title)}</span>
          </td>
          <td><span class="status-pill muted">${escapeHtml(runbook.category)}</span></td>
          <td><span class="status-pill ${runbookSeverityPillClass(runbook.severity)}">${escapeHtml(runbook.severity)}</span></td>
          <td>${escapeHtml(runbook.ownerRole || '—')}</td>
          <td>
            <strong>${escapeHtml((runbook.steps || []).length)} шагов</strong><br>
            <span class="muted">${escapeHtml(runbook.summary || 'Без краткого описания')}</span>
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
      .join('') || '<tr><td colspan="7">Runbooks ещё не загружены. Backend создаст базовые инструкции на старте.</td></tr>';
}

function serverWorkflow() {
  return state.loaded.serverWorkflow || {
    statuses: ['draft', 'healthy', 'degraded', 'maintenance', 'disabled'],
    protocols: [
      'wireguard_udp',
      'wireguard_tcp',
      'openvpn_tcp',
      'shadowsocks',
      'hysteria2',
      'stealth',
    ],
    transports: ['udp', 'tcp', 'tls', 'quic', 'http3'],
    clientConfigProfiles: [
      { code: 'none', title: 'Не выдавать клиентам' },
      { code: 'builtin_wg0', title: 'Текущий backend wg0' },
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
    wireguard_tcp: 'WireGuard TCP',
    openvpn_tcp: 'OpenVPN TCP',
    shadowsocks: 'Shadowsocks',
    hysteria2: 'Hysteria2',
    stealth: 'Stealth',
  }[protocol] || protocol || '—';
}

function serverTransportTitle(transport) {
  return {
    udp: 'UDP',
    tcp: 'TCP',
    tls: 'TLS',
    quic: 'QUIC',
    http3: 'HTTP/3',
  }[transport] || transport || '—';
}

function serverClientConfigProfileTitle(profile) {
  return {
    none: 'Не выдавать клиентам',
    builtin_wg0: 'Текущий backend wg0',
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
          <span class="muted">${escapeHtml(blocker.code)}: ${escapeHtml(blocker.message)}</span>
        `)
        .join('<br>')
    : '<span class="muted">Готов к публикации после следующего release gate.</span>';
  const more = blockers.length > visibleBlockers.length
    ? `<br><span class="muted">ещё ${blockers.length - visibleBlockers.length}</span>`
    : '';

  return `
    <span class="status-pill ${eligibility.eligible ? '' : 'yellow'}">
      ${eligibility.eligible ? 'eligible' : 'blocked'}
    </span><br>
    ${blockerHtml}${more}<br>
    <span class="muted">
      health24=${escapeHtml(eligibility.healthyObservations24h || 0)} /
      fail24=${escapeHtml(eligibility.failedObservations24h || 0)}
    </span>
  `;
}

function renderServerCatalogSummary() {
  const catalog = state.loaded.serverCatalog;
  const summary = state.loaded.serverCatalogSummary;
  const publication = state.loaded.serverPublicationReadiness;
  const provisioning = state.loaded.serverProvisioningReadiness;
  const workflow = serverWorkflow();
  const container = $('serverCatalogSummary');
  if (!container) return;
  if (!catalog) {
    container.innerHTML = '<p class="muted">Catalog пока не загружен.</p>';
    return;
  }

  const managed = catalog.managedCatalog || {};
  const servers = catalog.servers || [];
  const items = [
    {
      title: `Публичный catalog v${catalog.version || '—'}`,
      message: `${servers.length} клиентских endpoint, default=${catalog.defaultServerId || '—'}`,
      ok: true,
      warning: false,
      pill: 'client-safe',
    },
    {
      title: 'Managed endpoints',
      message: summary
        ? `${summary.managedTotal || 0} всего, ${summary.managedClientConfigReady || 0} config-ready, ${summary.managedPublicEligible || 0} eligible`
        : 'Summary пока не загружен.',
      ok: !summary || Number(summary.managedPublicEligible || 0) === 0,
      warning: Boolean(summary && Number(summary.managedPublicCandidates || 0) > 0),
      pill: summary?.mode || 'safe-gate',
    },
    {
      title: 'Managed catalog',
      message: managed.message || workflow.publicSafety || 'Готовим внутренний список серверов.',
      ok: true,
      warning: true,
      pill: managed.mode || workflow.publicMode || 'preparation',
    },
    {
      title: 'Publication gate',
      message: publication
        ? publication.clientImpact || `${publication.blockedManagedEntries?.length || 0} endpoint blocked`
        : 'Readiness endpoint пока не загружен.',
      ok: Boolean(publication?.publicCatalogUnchanged),
      warning: !publication?.canPublishManagedEndpoints,
      pill: publication?.canPublishManagedEndpoints ? 'review' : 'safe-block',
    },
    {
      title: 'Provisioning gate',
      message: provisioning
        ? provisioning.summary?.message || `accepted=${(provisioning.clientConfigContract?.acceptedServerIds || []).join(', ')}`
        : 'Provisioning readiness пока не загружен.',
      ok: Boolean(provisioning?.safeForCurrentClient),
      warning: !provisioning?.currentEndpointConfigReady || !provisioning?.multiEndpointProvisioningReady,
      pill: provisioning?.multiEndpointProvisioningReady ? 'multi-endpoint' : 'public-only',
    },
    {
      title: 'Bootstrap',
      message: (catalog.bootstrap?.apiBaseUrls || []).join(', ') || 'Нет bootstrap URLs',
      ok: Boolean(catalog.bootstrap?.apiBaseUrls?.length),
      warning: !catalog.bootstrap?.apiBaseUrls?.length,
      pill: 'api',
    },
  ];
  const blockerSummary = summary?.blockersByCode
    ? Object.entries(summary.blockersByCode)
        .sort((a, b) => Number(b[1]) - Number(a[1]))
        .slice(0, 5)
        .map(([code, count]) => `${code}: ${count}`)
        .join(', ')
    : '';
  if (blockerSummary) {
    items.push({
      title: 'Почему не public',
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
      pill: firstAction.owner || 'owner',
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
        ? `Черновик: ${firstExample.serverId} -> ${firstExample.hostname}; создание через ${plan.draftCreationEndpoint || 'safe draft endpoint'}`
        : plan.clientImpact || 'Новый VPS готовим только как внутренний draft.',
      ok: Boolean(plan.safeToCreateInternalDraft),
      warning: !plan.productionReady,
      pill: plan.mode || 'internal-only',
    });
    items.push({
      title: 'План подключения VPS',
      message: phaseSummary || 'План ещё не загружен.',
      ok: Boolean(plan.safeToCreateInternalDraft),
      warning: true,
      pill: `${(plan.phases || []).length} phases`,
    });
    if (ownerInputSummary) {
      items.push({
        title: 'Что нужно от владельца',
        message: ownerInputSummary,
        ok: true,
        warning: true,
        pill: 'non-secret',
      });
    }
  }
  if (provisioning?.selectionCases?.length) {
    const blocked = provisioning.selectionCases
      .filter((item) => !item.allowed)
      .map((item) => `${item.requestServerId}: ${item.reason}`)
      .join(', ');
    items.push({
      title: 'serverId contract',
      message: blocked || 'Все selection cases разрешены.',
      ok: Boolean(provisioning.safeForCurrentClient),
      warning: Boolean(blocked),
      pill: provisioning.clientConfigContract?.selectionPolicy || 'selection',
    });
  }
  container.innerHTML = items
    .map(
      (item) => `
        <div class="check-row">
          ${statusDot(item.ok, item.warning)}
          <div>
            <strong>${escapeHtml(item.title)}</strong>
            <span>${escapeHtml(item.message)}</span>
          </div>
          <span class="status-pill ${item.warning ? 'yellow' : ''}">${escapeHtml(item.pill)}</span>
        </div>
      `,
    )
    .join('');
}

function renderServersTable() {
  const rows = state.loaded.servers || [];
  const table = $('serversTable');
  if (!table) return;
  const canManageServers = can('servers.manage');
  table.innerHTML =
    rows
      .map((server) => `
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
            <span class="muted">${escapeHtml(server.provider)}</span>
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
          <td>
            ${boolPill(server.isActive, 'активен', 'выключен')}
            ${boolPill(server.isPublic, 'кандидат', 'внутренний')}
            ${boolPill(server.clientConfigReady, 'конфиг готов', 'конфиг не готов')}
            ${
              server.publicationPausedAt
                ? `<br><span class="status-pill yellow">auto-paused</span><br>
                   <span class="muted">${escapeHtml(server.publicationPausedReason || 'health gate')}</span>`
                : ''
            }
            <br>
            ${renderServerEligibility(server)}
          </td>
          <td>
            ${
              canManageServers
                ? `<div class="row-actions">
                    <button class="small-button" data-server-edit="${escapeHtml(server.id)}">В форму</button>
                    <button class="small-button" data-server-healthy="${escapeHtml(server.id)}">Здоров</button>
                    <button class="small-button danger" data-server-disable="${escapeHtml(server.id)}">Отключить</button>
                  </div>`
                : readonlyActionsHtml('servers.manage')
            }
          </td>
        </tr>
      `)
      .join('') || '<tr><td colspan="8">Управляемых серверов пока нет. Можно добавить первый draft.</td></tr>';
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
    ['Endpoint под наблюдением', summary.endpointsObserved || 0, `${summary.totalObservations || 0} наблюдений`],
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
      'Внешние endpoint probes',
      `${external.activeExternalProbeAgents || 0}/${external.externalProbeAgentsTotal || 0}`,
      external.summary?.message || 'Отдельный monitoring VPS ещё не подключён',
    ],
    [
      'Покрытие endpoint',
      `${(external.coveredEndpointIds || []).length}/${(external.requiredEndpointIds || []).length}`,
      (external.missingEndpointIds || []).length
        ? `нет: ${(external.missingEndpointIds || []).join(', ')}`
        : 'config-ready endpoint покрыты',
    ],
  ];

  summaryContainer.innerHTML = cards
    .map(([label, value, hint]) => `
      <div class="metric-card">
        <span>${escapeHtml(label)}</span>
        <strong>${escapeHtml(value)}</strong>
        <p>${escapeHtml(hint)}</p>
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
              <strong>Покрытие внешним probe</strong>
              <span>${escapeHtml(operatorPlan.tokenPolicy || external.tokenPolicy || 'Admin token только через stdin или token file вне репозитория.')}</span>
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
              ${verifySteps.map((step) => `<span class="muted">${escapeHtml(step)}</span>`).join('')}
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
              ${escapeHtml(item.message || item.errorCode || '—')}<br>
              <span class="muted">${escapeHtml(scoreText || item.errorCode || '')}</span>
            </td>
            <td>${escapeHtml(shortDate(item.observedAt))}</td>
          </tr>
        `;
      })
      .join('') || '<tr><td colspan="7">Наблюдений пока нет. Агент мониторинга позже начнёт присылать проверки endpoint-ов.</td></tr>';
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
    setNotice('Черновик нового VPS пока заблокирован: нужно сначала вернуть server catalog в безопасное состояние.', true);
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
  if (!requirePermission('servers.manage', 'Сохранение endpoint')) return;
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
    setNotice('Endpoint сохранён. Он пока не выдаётся клиентам.');
  } catch (error) {
    setNotice(`Не удалось сохранить endpoint: ${error.message}`, true);
  }
}

async function updateServerEntryStatus(entryId, status) {
  if (!requirePermission('servers.manage', 'Изменение endpoint')) return;
  const server = findServerEntry(entryId);
  if (!server) {
    setNotice('Endpoint не найден в текущем списке.', true);
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

async function seedCurrentServerEndpoint() {
  if (!requirePermission('servers.manage', 'Добавление текущего endpoint')) return;
  try {
    const result = await apiPost('/api/v1/admin/server-catalog/seed-current', {});
    await loadDashboardData();
    setNotice(result.message || 'Текущий endpoint добавлен во внутренний catalog.');
  } catch (error) {
    setNotice(`Не удалось добавить текущий endpoint: ${error.message}`, true);
  }
}

async function probeCurrentServerEndpoint() {
  if (!requirePermission('monitoring.manage', 'Проверка текущего endpoint')) return;
  try {
    const result = await apiPost('/api/v1/admin/server-health/probe-current', {});
    await loadDashboardData();
    setNotice(result.message || 'Проверка текущего endpoint завершена.');
  } catch (error) {
    setNotice(`Не удалось проверить текущий endpoint: ${error.message}`, true);
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
    telegram: 'Telegram',
    discord: 'Discord',
    youtube: 'YouTube',
    payment: 'Payment',
    update: 'Update',
    bootstrap: 'Bootstrap',
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
  const probesPayload = state.loaded.monitoringProbes || {};
  const readinessPayload = state.loaded.monitoringReadiness || {};
  const summary = observationsPayload.summary || targetsPayload.summary || {};
  const probeSummary = probesPayload.summary || summary;
  const probeReadiness = readinessPayload.readiness || probeSummary.probeReadiness || summary.probeReadiness || {};
  const probeInstallBundle = probeReadiness.installBundle || readinessPayload.installBundle || {};
  const staleAfterMinutes = Math.round((probeReadiness.staleAfterSeconds || probeSummary.workflow?.probeStaleAfterSeconds || 900) / 60);
  const targetSummaryContainer = $('monitoringTargetsSummary');
  const observationSummaryContainer = $('serviceObservationSummary');
  const probeSummaryContainer = $('monitoringProbeAgentsSummary');
  const probeInstallBundleContainer = $('monitoringProbeInstallBundle');
  const targetTable = $('monitoringTargetsTable');
  const observationTable = $('serviceObservationsTable');
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
        <span>${escapeHtml(label)}</span>
        <strong>${escapeHtml(value)}</strong>
        <p>${escapeHtml(hint)}</p>
      </div>
    `)
    .join('');

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
              <strong>${escapeHtml(target.title)}</strong><br>
              <span class="muted">${escapeHtml(target.targetId)}</span>
            </td>
            <td>
              ${escapeHtml(target.service)}<br>
              <span class="muted">${escapeHtml(monitoringTargetTypeTitle(target.targetType))}</span>
            </td>
            <td>
              ${escapeHtml(endpoint)}<br>
              <span class="muted">expected ${escapeHtml(target.expectedStatus || '—')}</span>
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
      .join('') || '<tr><td colspan="6">Целей мониторинга пока нет. Backend seed добавит базовые цели при старте.</td></tr>';

  if (probeSummaryContainer && probeTable) {
    const requiredTotal = (probeReadiness.requiredTargetIds || []).length;
    const coveredRequired = probeReadiness.coveredRequiredTargets || 0;
    const readinessSummary = probeReadiness.summary || {};
    probeSummaryContainer.innerHTML = [
      [
        'Готовность probes',
        probeReadiness.productionReady ? 'готово' : 'настройка',
        readinessSummary.message || 'controlled agent readiness',
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
          <span>${escapeHtml(label)}</span>
          <strong>${escapeHtml(value)}</strong>
          <p>${escapeHtml(hint)}</p>
        </div>
      `)
      .join('');

    if (probeInstallBundleContainer) {
      const ownerInputs = (probeInstallBundle.ownerInputs || [])
        .map((item) => {
          const title = item.name || 'input';
          const suffix = item.secret ? ' · secret' : '';
          return `<span class="status-pill ${item.secret ? 'red' : 'muted'}">${escapeHtml(title)}${escapeHtml(suffix)}</span>`;
        })
        .join('');
      const verifySteps = (probeInstallBundle.verifySteps || [])
        .map((step) => `<span class="muted">${escapeHtml(step)}</span>`)
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
                <strong>External probe install bundle</strong>
                <span>${escapeHtml(probeInstallBundle.tokenPolicy || 'Admin token stays only on the probe VPS.')}</span>
              </div>
              <span class="status-pill ${probeReadiness.productionReady ? '' : 'yellow'}">${probeReadiness.productionReady ? 'ready' : 'needs VPS'}</span>
            </div>
            <div class="external-action-meta">
              <span>Install:</span>
              <div class="code-list"><code>${escapeHtml(probeInstallBundle.installCommand)}</code></div>
            </div>
            <div class="external-action-meta">
              <span>Owner input:</span>
              <div class="pill-list">${ownerInputs || '<span class="muted">none</span>'}</div>
            </div>
            <div class="external-action-meta">
              <span>Required:</span>
              <div class="pill-list">${requiredTargets || '<span class="muted">none</span>'}</div>
            </div>
            <div class="external-action-meta">
              <span>Verify:</span>
              <div>${verifySteps || '<span class="muted">see monitoring readiness</span>'}</div>
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
        .join('') || '<tr><td colspan="6">Агенты проверки пока не присылали наблюдения. Позже внешний probe будет запускаться отдельным скриптом без хранения токена в репозитории.</td></tr>';
  }

  const observations = observationsPayload.observations || [];
  observationTable.innerHTML =
    observations
      .map((item) => `
        <tr>
          <td>
            <strong>${escapeHtml(item.targetId)}</strong><br>
            <span class="muted">${escapeHtml(item.errorCode || '')}</span>
          </td>
          <td>
            ${escapeHtml(item.probeId || 'probe —')}<br>
            <span class="muted">${escapeHtml(item.probeRegion || 'регион —')}</span>
          </td>
          <td><span class="status-pill ${serviceObservationStatusPillClass(item.status)}">${escapeHtml(serviceObservationStatusTitle(item.status))}</span></td>
          <td>${item.latencyMs === null || item.latencyMs === undefined ? '—' : `${escapeHtml(item.latencyMs)} мс`}</td>
          <td>${escapeHtml(item.message || '—')}</td>
          <td>${escapeHtml(shortDate(item.observedAt || item.createdAt))}</td>
        </tr>
      `)
      .join('') || '<tr><td colspan="6">Наблюдений сервисов пока нет. Monitoring agent начнёт писать их позже.</td></tr>';
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

function can(permission) {
  if (!permission) return true;
  if (state.authType === 'bootstrap_token' && state.adminToken) return true;
  return state.permissions.includes(permission);
}

function requirePermission(permission, actionTitle = 'Действие') {
  if (can(permission)) return true;
  setNotice(`${actionTitle}: у текущей роли нет права ${permission}.`, true);
  return false;
}

function readonlyActionsHtml(permission) {
  return `
    <span class="status-pill muted" title="Нужно право ${escapeHtml(permission)}">
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
    banner.textContent = `Текущая роль может смотреть этот раздел, но не менять данные. Нужно право ${permission}.`;
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
      : 'Нужно право incidents.manage';
  }
  const createPlannedServerDraftButton = $('createPlannedServerDraftButton');
  if (createPlannedServerDraftButton) {
    createPlannedServerDraftButton.disabled = hasAdminCredential() && !can('servers.manage');
    createPlannedServerDraftButton.title = can('servers.manage')
      ? 'Создать безопасный внутренний draft нового VPS из плана подключения'
      : 'Нужно право servers.manage';
  }
  const seedCurrentServerButton = $('seedCurrentServerButton');
  if (seedCurrentServerButton) {
    seedCurrentServerButton.disabled = hasAdminCredential() && !can('servers.manage');
    seedCurrentServerButton.title = can('servers.manage')
      ? 'Добавить текущий рабочий WireGuard endpoint во внутренний catalog'
      : 'Нужно право servers.manage';
  }
  const probeCurrentServerButton = $('probeCurrentServerButton');
  if (probeCurrentServerButton) {
    probeCurrentServerButton.disabled = hasAdminCredential() && !can('monitoring.manage');
    probeCurrentServerButton.title = can('monitoring.manage')
      ? 'Запустить server-side проверку текущего WireGuard endpoint'
      : 'Нужно право monitoring.manage';
  }
  const seedDefaultMonitoringTargetsButton = $('seedDefaultMonitoringTargetsButton');
  if (seedDefaultMonitoringTargetsButton) {
    seedDefaultMonitoringTargetsButton.disabled = hasAdminCredential() && !can('monitoring.manage');
    seedDefaultMonitoringTargetsButton.title = can('monitoring.manage')
      ? 'Обновить встроенные цели API/YouTube/Discord/Telegram без удаления кастомных целей'
      : 'Нужно право monitoring.manage';
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
  return state.adminActor || (state.adminToken ? 'bootstrap token' : 'не подключено');
}

function applyAuthUi() {
  $('logoutButton')?.classList.toggle('hidden', !hasAdminCredential());
  $('openLoginButton').textContent = hasAdminCredential() ? 'Сменить вход' : 'Вход / API';
  document.querySelectorAll('.nav-link').forEach((button) => {
    const allowed = can(button.dataset.permission || '');
    button.classList.toggle('hidden', hasAdminCredential() && !allowed);
    button.disabled = hasAdminCredential() && !allowed;
  });
  if (hasAdminCredential() && !can(sectionPermission(state.section))) {
    state.section = firstAllowedSection();
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
    monitoringTargets: null,
    serviceObservations: null,
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
    ['Support reports', overview?.openSupportReportsCount],
    ['Support actions 24h', overview?.supportActions24hCount],
    ['Инциденты', overview?.openIncidentsCount],
    ['Флаги', overview?.activeFeatureFlagsCount],
    ['Инструкции', overview?.activeRunbooksCount],
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
    : (state.authType === 'bootstrap_token' ? 'Bootstrap token' : 'Не подключено');
  const authHint = isStaffSession
    ? `${state.currentStaff.email} · ${state.roleTitle || state.currentStaff.role || 'роль'}`
    : 'Аварийный owner-доступ. Для ежедневной работы лучше создать сотрудника и войти по email/паролю.';
  const twoFactorLabel = isStaffSession
    ? (state.currentStaff.twoFactorEnabled ? '2FA включён' : '2FA выключен')
    : '2FA только для staff-сессий';
  const twoFactorHint = state.loaded.adminTwoFactorReadiness
    ? `staff: ${state.loaded.adminTwoFactorReadiness.enabledStaffCount || 0}/${state.loaded.adminTwoFactorReadiness.totalStaffCount || 0}`
    : 'status загрузится вместе с разделом команды';
  $('accountSecuritySummary').innerHTML = `
    <div class="status-row">
      ${statusDot(Boolean(hasAdminCredential()), state.authType === 'bootstrap_token')}
      <div>
        <strong>${escapeHtml(authTitle)}</strong>
        <span>${escapeHtml(authHint)}</span>
      </div>
      <span class="status-pill ${isStaffSession ? '' : 'yellow'}">${escapeHtml(state.authType || 'offline')}</span>
    </div>
    <div class="status-row">
      ${statusDot(Boolean(isStaffSession && state.currentStaff.twoFactorEnabled), isStaffSession && !state.currentStaff.twoFactorEnabled)}
      <div>
        <strong>${escapeHtml(twoFactorLabel)}</strong>
        <span>${escapeHtml(twoFactorHint)}</span>
      </div>
      <span class="status-pill ${isStaffSession && state.currentStaff.twoFactorEnabled ? '' : 'yellow'}">email code</span>
    </div>
  `;

  $('passwordChangeForm')?.classList.toggle('hidden', !isStaffSession);
  const sessions = state.loaded.adminSessions || [];
  if (!isStaffSession) {
    $('adminSessionsList').innerHTML = `
      <div class="status-row">
        ${statusDot(false, true)}
        <div>
          <strong>Сессии сотрудников недоступны для bootstrap token</strong>
          <span>Войди сотрудником, чтобы видеть активные входы и менять свой пароль.</span>
        </div>
        <span class="status-pill yellow">owner only</span>
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
            <span>${escapeHtml(session.userAgent || 'user-agent не записан')}</span>
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
        <span class="status-pill muted">empty</span>
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
        <strong>${escapeHtml(label)}</strong>
        <span>${escapeHtml(hint, '')}</span>
      </div>
      <span class="status-pill ${escapeHtml(pillClass)}">${escapeHtml(value, '0')}</span>
    </div>
  `;
}

function renderBreakdown(title, items) {
  const rows = Object.entries(items || {})
    .map(([key, value]) => `
      <tr>
        <td>${escapeHtml(key)}</td>
        <td>${escapeHtml(numberText(value))}</td>
      </tr>
    `)
    .join('');
  return `
    <div class="detail-card">
      <strong>${escapeHtml(title)}</strong>
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
      <strong>${escapeHtml(title)}</strong>
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
    ['Инциденты', numberText(incidents.openTotal), `${numberText(incidents.criticalOpen)} critical`],
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
    analyticsRow('Новые аккаунты за 30 дней', numberText(users.created30d), `${percentText(users.emailVerifiedSharePercent)} email verified`),
    analyticsRow('Телефон подтверждён', numberText(users.phoneVerified), `${percentText(users.phoneVerifiedSharePercent)} от пользователей`),
    analyticsRow('Устройства', `${numberText(devices.enabled)} / ${numberText(devices.total)}`, `${numberText(devices.configIssued)} получили конфиг`),
    analyticsRow('Конверсия в оплату', percentText(conversion.paidUserSharePercent), `${numberText(conversion.usersWithPaidOrders)} пользователей с оплатой`),
    analyticsRow('Истекают за 7 дней', numberText(subscriptions.expires7d), 'нужно будет продление/retention', subscriptions.expires7d > 0 ? 'yellow' : 'muted'),
  ].join('');

  $('analyticsFinancePanel').innerHTML = [
    analyticsRow('Всего заказов', numberText(orders.total), `${numberText(orders.activated)} активировано`),
    analyticsRow('Оплачено, но не активировано', numberText(orders.paid), 'ручной контроль на MVP', orders.paid > 0 ? 'yellow' : 'muted'),
    analyticsRow('Средний оплаченный заказ', money(orders.averagePaidOrderRub), 'по paid/activated'),
    analyticsRow('Ошибочные/отменённые', `${numberText(orders.failed)} / ${numberText(orders.cancelled)}`, 'failed / cancelled', (orders.failed || orders.cancelled) ? 'yellow' : 'muted'),
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
    analyticsRow('Critical incidents', numberText(incidents.criticalOpen), 'production alerts', incidents.criticalOpen > 0 ? 'red' : 'muted'),
    analyticsRow('Published releases', numberText(updates.published), `${numberText(updates.draft)} draft`),
    analyticsRow('Публичные VPN endpoints', numberText(servers.publicServers), `${numberText(servers.managedPublicReady)} managed ready`),
    analyticsRow('Endpoint failures 24h', numberText(servers.healthFailures24h), `${numberText(servers.healthEndpointsObserved)} observed`, servers.healthFailures24h > 0 ? 'yellow' : 'muted'),
    analyticsRow('Auth events 24h', numberText(auth.events24h), `${numberText(auth.failed24h)} failed`, auth.failed24h > 0 ? 'yellow' : 'muted'),
    analyticsRow('Admin alerts', readiness.alerts?.ready ? 'ready' : 'needs setup', readiness.alerts?.message || 'Telegram incident alerts'),
    analyticsRow('Product readiness', readiness.product?.productionReady ? 'ready' : 'needs setup', readiness.product?.summary?.message || ''),
    renderBreakdown('Серверы по протоколам', servers.byProtocol),
  ].join('');

  $('analyticsTrendsPanel').innerHTML = [
    renderTrendTable('Новые пользователи', analytics.timeseries?.users),
    renderTrendTable('Заказы', analytics.timeseries?.ordersCount),
    renderTrendTable('Выручка, ₽', analytics.timeseries?.ordersRevenue),
    renderTrendTable('Support reports', analytics.timeseries?.supportReports),
  ].join('');
}

function statusDot(ok, warning = false) {
  if (ok) return '<span class="dot"></span>';
  if (warning) return '<span class="dot yellow"></span>';
  return '<span class="dot red"></span>';
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
              <strong>${escapeHtml(gate.title)}</strong>
              <span>${escapeHtml(gate.nextAction || gate.message)}</span>
            </div>
            <span class="status-pill ${gate.severity === 'critical' ? 'red' : 'yellow'}">
              ${gate.severity === 'critical' ? 'критично' : 'предупреждение'}
            </span>
          </div>
        `).join('')}
      </div>
    `
    : '<p class="muted">Все launch-gates зелёные.</p>';

  const ownerActions = payload.nextOwnerActions || [];
  const ownerHtml = ownerActions.length
    ? `<div class="mini-list">${ownerActions.slice(0, 4).map((action) => `<span>${escapeHtml(action.title || action.code)}: ${escapeHtml(action.ownerStatusTitle || action.status)}</span>`).join('')}</div>`
    : '';

  const html = `
    <div class="status-row">
      ${statusDot(productionReady, publicReady && !productionReady)}
      <div>
        <strong>${escapeHtml(summary.message, 'Нет данных по запуску')}</strong>
        <span>
          Готово: ${escapeHtml(summary.ready, '0')}/${escapeHtml(summary.total, '0')}
          · критично: ${escapeHtml(summary.critical, '0')}
          · предупреждения: ${escapeHtml(summary.warnings, '0')}
        </span>
        <span>${escapeHtml(nextAction)}</span>
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
      container.innerHTML = '<p class="muted">Launch closure plan пока не загружен.</p>';
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
        ${escapeHtml(item.title || item.code)}${item.secretInputExpected ? ' · secret' : ''}
      </span>
    `)
    .join('');
  const autonomousHtml = nextAutonomous
    .slice(0, 5)
    .map((item) => `<span class="status-pill yellow">${escapeHtml(item.title || item.code)}</span>`)
    .join('');
  const finalHtml = finalHandoff
    .slice(0, 3)
    .map((item) => `<span class="status-pill muted">${escapeHtml(item.title || item.code)}</span>`)
    .join('');

  const html = `
    <div class="status-row">
      ${statusDot(Boolean(plan.productionReady), plan.publicLaunchReady || summary.ownerBlocked > 0)}
      <div>
        <strong>${escapeHtml(summary.message, 'Launch closure plan')}</strong>
        <span>
          ready=${escapeHtml(summary.ready, '0')}/${escapeHtml(summary.total, '0')},
          owner=${escapeHtml(summary.ownerBlocked, '0')},
          code=${escapeHtml(summary.codeOwned, '0')},
          ops=${escapeHtml(summary.operationalReview, '0')},
          final=${escapeHtml(summary.finalHandoffOnly, '0')}
        </span>
        ${
          summary.nextAutonomousAction
            ? `<span>${escapeHtml(summary.nextAutonomousAction)}</span>`
            : ''
        }
      </div>
      <span class="status-pill ${plan.productionReady ? '' : summary.ownerBlocked ? 'red' : 'yellow'}">
        ${escapeHtml(plan.state || 'pending')}
      </span>
    </div>
    <div class="external-action-meta">
      <span>Owner inputs:</span>
      <div class="pill-list">${ownerHtml || '<span class="muted">none</span>'}</div>
    </div>
    <div class="external-action-meta">
      <span>Autonomous/ops:</span>
      <div class="pill-list">${autonomousHtml || '<span class="muted">no code-owned gate at the top</span>'}</div>
    </div>
    <div class="external-action-meta">
      <span>Final handoff:</span>
      <div class="pill-list">${finalHtml || '<span class="muted">none</span>'}</div>
    </div>
    <p class="muted">${escapeHtml(plan.policy?.secretPolicy || 'Secret values are never returned.')}</p>
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
    container.innerHTML = '<p class="muted">Owner launch packet пока не загружен.</p>';
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
        <span>${escapeHtml(command.title || command.code)}:</span>
        <div>
          <div class="code-list"><code>${escapeHtml(command.command)}</code></div>
          <span class="status-pill ${command.secret ? 'red' : 'muted'}">${command.secret ? 'secret input' : 'no secret'}</span>
          <span class="status-pill ${command.mutationFree ? 'muted' : 'yellow'}">${command.mutationFree ? 'mutation-free' : 'applies changes'}</span>
          <span class="muted">${escapeHtml(command.when || '')}</span>
        </div>
      </div>
    `)
    .join('');
  const ownerBlockersHtml = ownerBlockers
    .slice(0, 6)
    .map((item) => `
      <span class="status-pill ${item.secretInputExpected ? 'red' : 'yellow'}">
        ${escapeHtml(item.title || item.code)}${item.secretInputExpected ? ' · secret' : ''}
      </span>
    `)
    .join('');
  const ownerActionsHtml = ownerActions
    .slice(0, 6)
    .map((action) => {
      const inputs = (action.ownerInputs || [])
        .slice(0, 5)
        .map((item) => `<span class="status-pill ${item.secret ? 'red' : 'muted'}">${escapeHtml(item.name || item.envKey || 'input')}${item.secret ? ' · secret' : ''}</span>`)
        .join('');
      return `
        <div class="check-row">
          ${statusDot(Boolean(action.ready), !action.ready)}
          <div>
            <strong>${escapeHtml(action.title || action.code)}</strong>
            <span>${escapeHtml(action.ownerAction || action.message || '')}</span>
            <div class="pill-list">${inputs || '<span class="muted">owner input не требуется</span>'}</div>
          </div>
          <span class="status-pill ${action.secretInputExpected ? 'red' : 'yellow'}">${action.secretInputExpected ? 'secret' : 'owner'}</span>
        </div>
      `;
    })
    .join('');
  const checksHtml = checks
    .slice(0, 10)
    .map((check) => `<span class="status-pill muted">${escapeHtml(check)}</span>`)
    .join('');

  container.innerHTML = `
    <div class="external-action-card ${packet.publicLaunchReady ? 'ready' : 'pending'}">
      <div class="external-action-head">
        ${statusDot(Boolean(packet.productionReady), Boolean(packet.publicLaunchReady) || summary.ownerBlocked > 0)}
        <div>
          <strong>${escapeHtml(summary.message, 'Owner launch packet')}</strong>
          <span>
            commands=${escapeHtml(summary.commands, '0')},
            ownerActions=${escapeHtml(summary.pendingOwnerActions, '0')},
            dns=${escapeHtml(summary.dnsRecords, '0')},
            safeDefaults=${escapeHtml(summary.safeDefaults, '0')}
          </span>
        </div>
        <span class="status-pill ${packet.safeNoSecretExposure ? '' : 'red'}">${packet.safeNoSecretExposure ? 'no secrets' : 'review'}</span>
      </div>
      ${commandsHtml || '<p class="muted">Команды owner packet пока не загружены.</p>'}
      <div class="external-action-meta">
        <span>Launch blockers:</span>
        <div class="pill-list">${ownerBlockersHtml || '<span class="muted">none</span>'}</div>
      </div>
      ${
        ownerActionsHtml
          ? `<div class="check-list compact-list">${ownerActionsHtml}</div>`
          : '<p class="muted">Все owner actions закрыты.</p>'
      }
      <div class="external-action-meta">
        <span>After apply:</span>
        <div class="pill-list">${checksHtml || '<span class="muted">see readiness self-check</span>'}</div>
      </div>
      <p class="muted">${escapeHtml(packet.policy?.secretPolicy || 'Secret values are never returned.')}</p>
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
      container.innerHTML = '<p class="muted">Public site readiness пока не загружен.</p>';
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
        <strong>${escapeHtml(summary.message, 'Public site readiness')}</strong>
        <span>
          site=${escapeHtml(site.siteUrl || '—')}
          · green=${escapeHtml(summary.green, '0')}
          · yellow=${escapeHtml(summary.yellow, '0')}
        </span>
        <span>
          downloads: windows=${boolLabel(downloads.windowsConfigured)},
          android=${boolLabel(downloads.androidConfigured)},
          ios=${boolLabel(downloads.iosConfigured)}
        </span>
        <span>
          YooKassa: ${escapeHtml(yookassa.returnUrl || 'return URL не задан')}
          · ${escapeHtml(yookassa.webhookUrl || 'webhook URL не задан')}
        </span>
      </div>
      <span class="status-pill ${site.productionReady ? '' : 'yellow'}">
        ${site.productionReady ? 'site ready' : 'needs action'}
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
                  <strong>${escapeHtml(check.title || check.code)}</strong>
                  <span>${escapeHtml(check.message)}</span>
                </div>
                <span class="status-pill yellow">нужно действие</span>
              </div>
            `).join('')
          }</div>`
        : '<p class="muted">Public site gate зелёный.</p>'
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
              <strong>${escapeHtml(check.title)}</strong>
              <span>${escapeHtml(check.message, '')}</span>
            </div>
            <span class="status-pill ${check.ok ? '' : check.warning ? 'yellow' : 'red'}">
              ${check.ok ? 'ok' : check.warning ? 'warning' : 'fail'}
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
      container.innerHTML = '<p class="muted">Проверка разделения сайта и VPN endpoint ещё не загружена.</p>';
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
    vpn_endpoint_resolves: 'VPN endpoint резолвится',
    api_vpn_ip_split: 'Сайт/API и VPN endpoint на разных IP',
  };
  const primaryMessage = network.productionReady
    ? 'Сайт/API отделены от VPN endpoint.'
    : 'Сайт/API сейчас используют тот же IP, что и VPN endpoint.';
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
              <strong>${escapeHtml(phase.title || phase.code)}</strong>
              <span>${escapeHtml(phase.details || '')}</span>
            </div>
            <span class="status-pill ${phase.status === 'blocked' ? 'red' : phase.status === 'done' ? '' : 'yellow'}">
              ${escapeHtml(phase.status || 'pending')}
            </span>
          </div>
        `).join('')}
      </div>
      ${
        dnsRecords.length
          ? `<div class="mini-list">${dnsRecords.map((record) => `
              <span>
                DNS ${escapeHtml(record.name)} -> ${escapeHtml(record.target)}
                (${escapeHtml(record.status)})
              </span>
            `).join('')}</div>`
          : ''
      }
      ${
        preflight.command
          ? `<div class="external-action-meta">
              <span>Preflight:</span>
              <div class="code-list"><code>${escapeHtml(preflight.command)}</code></div>
            </div>
            <p class="muted">${escapeHtml(preflight.when || 'Запустить после подготовки отдельного API/site IP и DNS endpoint.')}</p>`
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
          · VPN endpoint: ${escapeHtml(network.vpnEndpointHost || '—')}
        </span>
        <span>
          IP API: ${escapeHtml(apiIps || '—')}
          · IP endpoint: ${escapeHtml((network.vpnEndpointIps || []).join(', ') || '—')}
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
        ? `<div class="mini-list">${requiredActions.map((action) => `<span>${escapeHtml(action)}</span>`).join('')}</div>`
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
                  <strong>${escapeHtml(checkTitles[check.code] || check.code)}</strong>
                  <span>${escapeHtml(check.message)}</span>
                </div>
                <span class="status-pill ${check.ok ? '' : 'yellow'}">${check.ok ? 'ok' : 'нужно действие'}</span>
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
              <strong>${escapeHtml(summary?.message, 'Нет данных')}</strong>
              <span>green=${escapeHtml(summary?.green, '0')}, yellow=${escapeHtml(summary?.yellow, '0')}</span>
      </div>
      <span class="status-pill ${readiness?.productionReady ? '' : 'yellow'}">
        ${readiness?.productionReady ? 'production ready' : 'needs setup'}
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
              <strong>${escapeHtml(check.title)}</strong>
              <span>${escapeHtml(check.message)}</span>
            </div>
            <span class="status-pill ${check.ok ? '' : 'yellow'}">${check.ok ? 'готово' : 'нужно действие'}</span>
          </div>
        `,
      )
      .join('') || '<p>Checklist пока пуст.</p>';

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
              <span>${escapeHtml(event.reason || 'alert')} · ${escapeHtml(event.provider)} · ${escapeHtml(shortDate(event.createdAt))}</span>
              <span class="muted">${escapeHtml(event.error || event.messagePreview || '')}</span>
            </div>
            <span class="status-pill ${alertStatusPillClass(event.status)}">${escapeHtml(event.status)}</span>
          </div>
        `,
      )
      .join('') || '<p class="muted">Alert history пока пуст.</p>';
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
    return 'Ключи, tokens, passwords и provider secrets вводить только через server env script.';
  }
  return `Похоже на secret material: ${findings.slice(0, 5).join(', ')}. Удали значения из заметки.`;
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
        <strong>${escapeHtml(summary?.message, 'Внешние действия не загружены')}</strong>
        <span>ready=${escapeHtml(summary?.ready, '0')}, pending=${escapeHtml(summary?.pending, '0')}, ownerDone=${escapeHtml(summary?.ownerDone, '0')}, blocked=${escapeHtml(summary?.ownerBlocked, '0')}, doneMismatch=${escapeHtml(summary?.doneButBackendNotReady, '0')}</span>
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
        <strong>Owner action audit</strong>
        <span>readyToApply=${escapeHtml((blocking.readyToApplyCodes || []).length, '0')}, waiting=${escapeHtml((blocking.waitingCodes || []).length, '0')}, missingNotes=${escapeHtml((blocking.missingOwnerNoteCodes || []).length, '0')}</span>
        <span>noteGuard=${ownerPolicy.serverEnforced ? 'server-enforced' : 'text-only'}, blockedPatterns=${escapeHtml((ownerPolicy.blockedNotePatternCodes || []).length, '0')}</span>
      </div>
      <span class="status-pill ${ownerPolicy.serverEnforced ? (blocking.safeToProceed ? '' : 'yellow') : 'red'}">${ownerPolicy.serverEnforced ? (blocking.safeToProceed ? 'clean' : 'review') : 'guard off'}</span>
    </div>
    <p class="muted">${escapeHtml(ownerPolicy.secretPolicy || 'Owner notes must not contain secrets.')}</p>
  `;

  const setupBundleHtml = bundle.applyCommand || bundle.readinessCommand
    ? `
      <div class="external-action-card ready">
        <div class="external-action-head">
          ${statusDot(true, false)}
          <div>
            <strong>Owner setup bundle</strong>
            <span>${escapeHtml(bundle.secretPolicy || 'Secrets stay on the server only.')}</span>
          </div>
          <span class="status-pill">server-only env</span>
        </div>
        <div class="external-action-meta">
          <span>Apply:</span>
          <div class="code-list"><code>${escapeHtml(bundle.applyCommand || '')}</code></div>
        </div>
        <div class="external-action-meta">
          <span>Verify:</span>
          <div class="code-list"><code>${escapeHtml(bundle.readinessCommand || '')}</code></div>
        </div>
        <div class="external-action-meta">
          <span>DNS:</span>
          <div class="pill-list">
            ${(bundle.dnsRecords || [])
              .map((record) => `<span class="status-pill muted">${escapeHtml(record.type)} ${escapeHtml(record.host)}</span>`)
              .join('') || '<span class="muted">none</span>'}
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
        .map((item) => `<span class="status-pill muted">${escapeHtml(item)}</span>`)
        .join('');
      const ownerInputs = (action.ownerInputs || [])
        .map((item) => {
          const title = item.name || item.envKey || 'input';
          const suffix = item.secret ? ' · secret' : (item.optional ? ' · optional' : '');
          const hint = item.example ? ` title="${escapeHtml(item.example)}"` : '';
          return `<span class="status-pill ${item.secret ? 'red' : 'muted'}"${hint}>${escapeHtml(title)}${escapeHtml(suffix)}</span>`;
        })
        .join('');
      const applySteps = (action.applySteps || [])
        .map((step) => `<span class="muted">${escapeHtml(step)}</span>`)
        .join('');
      const verifySteps = (action.verifySteps || [])
        .map((step) => `<span class="muted">${escapeHtml(step)}</span>`)
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
              <textarea data-owner-action-note="${escapeHtml(action.code)}" placeholder="Например: домен куплен, MX/SPF/DKIM внесены, ждём propagation DNS.">${escapeHtml(ownerNote, '')}</textarea>
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
              <strong>${escapeHtml(action.title)}</strong>
              <span>${escapeHtml(action.message || action.ownerAction)}</span>
            </div>
            <div class="external-action-badges">
              <span class="status-pill ${action.ready ? '' : 'yellow'}">${action.ready ? 'готово' : 'ждёт владельца'}</span>
              <span class="status-pill ${ownerActionStatusPillClass(ownerStatus)}">${escapeHtml(ownerActionStatusTitle(ownerStatus))}</span>
              ${action.secret ? '<span class="status-pill red">секрет</span>' : '<span class="status-pill muted">без секрета</span>'}
            </div>
          </div>
          <p>${escapeHtml(action.ownerAction)}</p>
          <div class="external-action-meta">
            <span>Env:</span>
            <div class="code-list">${envKeys || '<span class="muted">нет</span>'}</div>
          </div>
          <div class="external-action-meta">
            <span>Блокирует:</span>
            <div class="pill-list">${blocks || '<span class="muted">ничего</span>'}</div>
          </div>
          <div class="external-action-meta">
            <span>Owner input:</span>
            <div class="pill-list">${ownerInputs || '<span class="muted">none</span>'}</div>
          </div>
          <div class="external-action-meta">
            <span>Apply:</span>
            <div>${applySteps || '<span class="muted">see setup bundle</span>'}</div>
          </div>
          <div class="external-action-meta">
            <span>Verify:</span>
            <div>${verifySteps || '<span class="muted">see readiness checker</span>'}</div>
          </div>
          <div class="external-action-meta">
            <span>Owner:</span>
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
    <p class="muted">${escapeHtml(payload.secretPolicy, '')}</p>
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
    setNotice(`Заметка похожа на secret material (${noteFindings.slice(0, 5).join(', ')}). Удали значение и оставь только статус.`, true);
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
              <span class="status-pill ${report.reviewPending ? 'yellow' : 'muted'}">${escapeHtml(report.status)}</span><br>
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
    container.innerHTML = '<p class="muted">SLA queue not loaded yet.</p>';
    return;
  }
  const summary = sla.summary || {};
  const items = [
    {
      title: 'SLA queue',
      message: `open=${numberText(summary.open)}, reviewPending=${numberText(summary.reviewPending)}, firstResponseMissing=${numberText(summary.firstResponseMissing)}`,
      ok: !sla.attentionRequired,
      warning: Boolean(sla.attentionRequired),
      pill: sla.attentionRequired ? 'attention' : 'clean',
    },
    {
      title: 'Overdue / due soon',
      message: `overdue=${numberText(summary.overdue)}, dueSoon=${numberText(summary.dueSoon)}, missingSla=${numberText(summary.missingSla)}`,
      ok: !summary.overdue && !summary.dueSoon && !summary.missingSla,
      warning: Boolean(summary.overdue || summary.dueSoon || summary.missingSla),
      pill: summary.overdue ? 'overdue' : (summary.dueSoon ? 'soon' : 'ok'),
    },
  ];
  container.innerHTML = items
    .map(
      (item) => `
        <div class="check-row">
          ${statusDot(item.ok, item.warning)}
          <div>
            <strong>${escapeHtml(item.title)}</strong>
            <span>${escapeHtml(item.message)}</span>
          </div>
          <span class="status-pill ${item.ok ? '' : 'yellow'}">${escapeHtml(item.pill)}</span>
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
    .map((runbook) => `<span class="status-pill muted">${escapeHtml(runbook.key || runbook.title)}</span>`)
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
              <strong>${escapeHtml(incident.title)}</strong><br>
              <span class="muted">${escapeHtml(incident.summary)}</span><br>
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
          ? `<button class="small-button inline-button" type="button" data-expiry-review="${escapeHtml(candidate.subscriptionId)}">Review</button>`
          : '';
      const reviewed = candidate.reviewedForExpiry ? 'reviewed · ' : '';
      return `<span class="status-pill ${candidate.requiresManualReview ? 'yellow' : 'muted'}">#${escapeHtml(candidate.userId)} · ${escapeHtml(reviewed + label)} ${reviewButton}</span>`;
    })
    .join('');

  container.innerHTML = expiry.ok
    ? `
      <div class="check-row">
        ${statusDot(expiry.safeToEnableExpiryEnforcement, expiry.requiresAttention || !expiry.productionPaymentReady || !expiry.paymentSmokeReady)}
        <div>
          <strong>${escapeHtml(summary.message, 'Subscription expiry readiness')}</strong>
          <span>
            active=${escapeHtml(summary.activeNow, '0')},
            expiring=${escapeHtml(summary.expiringWithinWindow, '0')},
            expired=${escapeHtml(summary.expired, '0')},
            manual=${escapeHtml(summary.paidExpiringWithoutAutoRenew, '0')},
            reviewed=${escapeHtml(summary.reviewedMissingRetentionContact, '0')},
            smoke=${boolLabel(expiry.paymentSmokeCompleted)}
          </span>
        </div>
        <span class="status-pill ${expiry.safeToEnableExpiryEnforcement ? '' : 'yellow'}">
          ${expiry.subscriptionEnforcementCurrentlyEnabled ? 'enforced' : 'not enforced'}
        </span>
      </div>
      <div class="external-action-meta">
        <span>Expiry issues:</span>
        <div class="pill-list">${issuePills || '<span class="muted">none</span>'}</div>
      </div>
      <div class="external-action-meta">
        <span>Candidates:</span>
        <div class="pill-list">${candidatePreview || '<span class="muted">none in window</span>'}</div>
      </div>
      <p class="muted">
        ${escapeHtml(expiry.policy?.mode, 'expiry readiness only')}.
        ${expiry.policy?.requiresPaymentSmoke ? 'Requires clean payment smoke.' : ''}
        ${escapeHtml(expiry.policy?.safePaymentMethodExposure, '')}
      </p>
    `
    : '<p class="muted">Subscription expiry readiness not loaded yet.</p>';
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
              <span class="muted">devices: ${escapeHtml(user.enabledDeviceCount, '0')}/${escapeHtml(user.deviceCount, '0')}</span>
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
  if (!requirePermission('billing.manage', 'Subscription expiry review')) return;
  const candidate = (state.loaded.subscriptionExpiry?.candidates || []).find(
    (item) => String(item.subscriptionId) === String(subscriptionId),
  );
  const defaultReason = 'Reviewed trial/free expiry without verified contact; no automatic charge is attempted and natural expiry is allowed.';
  const reason = window.prompt('Expiry review reason', defaultReason);
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
    setNotice(`Expiry review saved for subscription #${escapeHtml(candidate?.subscriptionId || subscriptionId)}.`);
  } catch (error) {
    setNotice(`Could not save expiry review: ${error.message}`, true);
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
            <strong>${escapeHtml(readinessSummary.message, 'Готовность стартовой акции')}</strong>
            <span>
              total=${escapeHtml(readinessSummary.total, '0')},
              active=${escapeHtml(readinessSummary.active, '0')},
              launchReady=${escapeHtml(readinessSummary.launchReady, '0')},
              risky=${escapeHtml(readinessSummary.activeRisky, '0')}
            </span>
          </div>
          <span class="status-pill ${readiness.safeToRunLaunchCampaign ? '' : 'yellow'}">
            ${readiness.safeToRunLaunchCampaign ? 'готово' : 'подготовить'}
          </span>
        </div>
        <div class="external-action-meta">
          <span>Риски:</span>
          <div class="pill-list">${issuePills || '<span class="muted">none</span>'}</div>
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
                ${escapeHtml(promo.title || 'Без названия')} · скидка ${promoDiscountLabel(promo)}
              </span>
              <span>
                тарифы: ${escapeHtml(promoPlansLabel(promo))};
                использовано: ${limitLabel};
                статус: ${escapeHtml(promo.statusReason)}
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
      return `<span class="status-pill ${candidate.chargeEligibleDryRun ? '' : 'yellow'}">${escapeHtml(candidate.email || candidate.userId)} В· ${escapeHtml(issues)}</span>`;
    })
    .join('');
  const reconciliationContainer = $('billingReconciliationSummary');
  if (reconciliationContainer) {
    reconciliationContainer.innerHTML = reconciliation.ok
      ? `
        <div class="check-row">
          ${statusDot(!reconciliation.requiresAttention, reconciliation.requiresAttention)}
          <div>
            <strong>${escapeHtml(summary.message, 'Billing reconciliation')}</strong>
            <span>
              total=${escapeHtml(summary.total, '0')},
              attention=${escapeHtml(summary.ordersWithAttention, '0')},
              high=${escapeHtml(summary.high, '0')},
              medium=${escapeHtml(summary.medium, '0')}
            </span>
          </div>
          <span class="status-pill ${reconciliation.requiresAttention ? 'yellow' : ''}">
            ${reconciliation.requiresAttention ? 'review' : 'clean'}
          </span>
        </div>
        <div class="external-action-meta">
          <span>Issues:</span>
          <div class="pill-list">${issuePills || '<span class="muted">none</span>'}</div>
        </div>
        <div class="external-action-meta">
          <span>Orders:</span>
          <div class="pill-list">${attentionPreview || '<span class="muted">none</span>'}</div>
        </div>
        <p class="muted">${escapeHtml(reconciliation.manualActivationPolicy || '')}</p>
      `
      : '<p class="muted">Billing reconciliation пока не загружен.</p>';
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
      .map((step) => `<span class="status-pill ${step.status === 'done' ? '' : step.status === 'blocked' ? 'red' : 'yellow'}">${escapeHtml(step.code)}: ${escapeHtml(step.status)}</span>`)
      .join('');
    smokeContainer.innerHTML = paymentSmoke.ok
      ? `
        <div class="check-row">
          ${statusDot(Boolean(paymentSmoke.productionReady), Boolean(paymentSmoke.safeToRunSmoke))}
          <div>
            <strong>${escapeHtml(smokeSummary.message, 'Payment smoke readiness')}</strong>
            <span>
              provider=${escapeHtml(paymentSmoke.provider || '—')},
              safeToRun=${boolLabel(paymentSmoke.safeToRunSmoke)},
              completed=${boolLabel(paymentSmoke.smokeCompleted)}
            </span>
            <span>
              yookassaOrders=${escapeHtml(smokeSummary.yookassaOrdersTotal, '0')},
              pendingUrl=${escapeHtml(smokeSummary.pendingWithPaymentUrl, '0')},
              successful=${escapeHtml(smokeSummary.successfulSmokeCandidates, '0')}
            </span>
          </div>
          <span class="status-pill ${paymentSmoke.productionReady ? '' : paymentSmoke.safeToRunSmoke ? 'yellow' : 'red'}">
            ${paymentSmoke.productionReady ? 'smoke ok' : paymentSmoke.safeToRunSmoke ? 'run smoke' : 'blocked'}
          </span>
        </div>
        <div class="external-action-meta">
          <span>Smoke steps:</span>
          <div class="pill-list">${stepPreview || '<span class="muted">none</span>'}</div>
        </div>
        ${
          failedSmokeChecks.length
            ? `<div class="external-action-meta">
                <span>Blocks:</span>
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
      : '<p class="muted">Payment smoke readiness пока не загружен.</p>';
  }
  const renewalContainer = $('billingRenewalSummary');
  if (renewalContainer) {
    renewalContainer.innerHTML = renewals.ok
      ? `
        <div class="check-row">
          ${statusDot(renewals.safeToEnableAutoRenewalCharges, renewals.requiresAttention || !renewals.productionPaymentReady || !renewals.paymentSmokeReady)}
          <div>
            <strong>${escapeHtml(renewalSummary.message, 'Auto-renewal readiness')}</strong>
            <span>
              autoRenew=${escapeHtml(renewalSummary.autoRenewSubscriptions, '0')},
              due=${escapeHtml(renewalSummary.dueWithinWindow, '0')},
              eligible=${escapeHtml(renewalSummary.chargeEligibleDryRun, '0')},
              missingMethod=${escapeHtml(renewalSummary.missingPaymentMethod, '0')},
              smoke=${boolLabel(renewals.paymentSmokeCompleted)}
            </span>
          </div>
          <span class="status-pill ${renewals.safeToEnableAutoRenewalCharges ? '' : 'yellow'}">
            ${renewals.safeToEnableAutoRenewalCharges ? 'safe dry-run' : 'blocked'}
          </span>
        </div>
        <div class="external-action-meta">
          <span>Renewal issues:</span>
          <div class="pill-list">${renewalIssuePills || '<span class="muted">none</span>'}</div>
        </div>
        <div class="external-action-meta">
          <span>Candidates:</span>
          <div class="pill-list">${renewalPreview || '<span class="muted">none in window</span>'}</div>
        </div>
        <p class="muted">
          ${escapeHtml(renewals.policy?.automaticChargeExecution, 'dry-run only')}.
          ${renewals.policy?.requiresPaymentSmoke ? 'Requires clean payment smoke.' : ''}
          ${escapeHtml(renewals.policy?.safePaymentMethodExposure, '')}
        </p>
      `
      : '<p class="muted">Auto-renewal readiness not loaded yet.</p>';
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
            <td><span class="status-pill muted">${escapeHtml(order.status)}</span></td>
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
            <td>${escapeHtml(event.eventType)}</td>
            <td><span class="status-pill ${event.status === 'verified' ? '' : event.status === 'created' ? 'yellow' : 'red'}">${escapeHtml(event.status)}</span></td>
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
    container.innerHTML = '<p class="muted">User auth readiness пока не загружен.</p>';
    return;
  }

  const summary = auth.summary || {};
  const methods = auth.methods || [];
  const checks = auth.checks || [];
  const problems = auth.recentProblemEvents || [];
  const methodPills = methods
    .map((method) => {
      const label = method.legacy
        ? `${method.code}: legacy`
        : `${method.code}: ${method.available ? 'available' : 'blocked'}`;
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
          <strong>${escapeHtml(check.title || check.code)}</strong>
          <span>${escapeHtml(check.message)}</span>
        </div>
        <span class="status-pill yellow">нужно действие</span>
      </div>
    `)
    .join('');
  const problemPills = problems
    .slice(0, 6)
    .map((event) => `<span class="status-pill yellow">#${escapeHtml(event.id)} ${escapeHtml(event.eventType)}:${escapeHtml(event.status)}</span>`)
    .join('');

  container.innerHTML = `
    <div class="check-row">
      ${statusDot(Boolean(auth.productionReady), !auth.productionReady)}
      <div>
        <strong>${escapeHtml(summary.message, 'Code-first auth readiness')}</strong>
        <span>
          primary=${escapeHtml(auth.primaryMethod || '—')},
          fallback=${escapeHtml(auth.fallbackMethod || '—')},
          users=${escapeHtml(summary.usersTotal, '0')},
          verified24h=${escapeHtml(summary.verified24h, '0')},
          problems24h=${escapeHtml(summary.problem24h, '0')}
        </span>
      </div>
      <span class="status-pill ${auth.productionReady ? '' : 'yellow'}">${auth.productionReady ? 'готово' : 'настройка'}</span>
    </div>
    <div class="external-action-meta">
      <span>Methods:</span>
      <div class="pill-list">${methodPills || '<span class="muted">none</span>'}</div>
    </div>
    ${
      failedChecks
        ? `<div class="check-list compact-list">${failedChecks}</div>`
        : '<p class="muted">Auth flow gate зелёный.</p>'
    }
    ${
      problemPills
        ? `<div class="external-action-meta"><span>Recent problems:</span><div class="pill-list">${problemPills}</div></div>`
        : ''
    }
    <p class="muted">${escapeHtml(auth.policy?.secretExposure || 'No auth secrets are exposed by readiness.')}</p>
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
              <span>${escapeHtml(role.permissions?.join(', ') || '—')}</span>
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
              <span class="muted">${escapeHtml(staff.role)}</span>
            </td>
            <td>${boolPill(staff.isActive, 'активен', 'выключен')}</td>
            <td>
              ${boolPill(staff.twoFactorEnabled, 'email', 'off')}
              <br><span class="muted">${escapeHtml(shortDate(staff.twoFactorSetAt))}</span>
            </td>
            <td>
              ${boolPill(staff.hasPassword, 'задан', 'нет')}
              <br><span class="muted">login: ${escapeHtml(shortDate(staff.lastLoginAt))}</span>
            </td>
            <td>
              <strong>${escapeHtml(activeSessions)}</strong> активных<br>
              <span class="muted">last: ${escapeHtml(shortDate(staff.lastSessionSeenAt))}</span><br>
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
    container.innerHTML = '<p class="muted">Выбери сотрудника в таблице, чтобы посмотреть его staff sessions.</p>';
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
        <strong>Sessions: ${escapeHtml(staff.displayName || staff.email || staffId)}</strong>
        <span>${escapeHtml(sessions.length)} total, active ${escapeHtml(staff.activeSessionCount || 0)}</span>
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
              <span>${escapeHtml(session.userAgent || 'user-agent не записан')}</span>
            </div>
            ${action}
          </div>
        `;
      })
      .join('') || '<p class="muted">У сотрудника пока нет sessions.</p>'}
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
  $('sidebarApiBase').textContent = state.apiBase;
  applyAuthUi();
  renderMetrics(state.loaded.overview || {});
  renderAccountSecurity();
  renderAnalytics();
  renderServiceStatus();
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
  renderServersTable();
  renderServerHealth();
  renderManagedMonitoring();
  renderAdmin2faPrompt();
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
    throw new Error('Backend не вернул admin session token.');
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
  if (!requirePermission('staff.manage', 'Просмотр staff sessions')) return;
  try {
    const result = await apiGet(`/api/v1/admin/staff/${encodeURIComponent(staffId)}/sessions`);
    state.loaded.staffSessions = result;
    renderStaffSessionsPanel();
    setNotice('Staff sessions загружены.');
  } catch (error) {
    setNotice(`Не удалось загрузить staff sessions: ${error.message}`, true);
  }
}

async function revokeStaffSession(staffId, sessionId) {
  if (!requirePermission('staff.manage', 'Отзыв staff session')) return;
  try {
    await apiPost(`/api/v1/admin/staff/${encodeURIComponent(staffId)}/sessions/revoke`, { sessionId });
    await openStaffSessions(staffId);
    await loadDashboardData();
    setNotice('Staff session отозвана.');
  } catch (error) {
    setNotice(`Не удалось отозвать staff session: ${error.message}`, true);
  }
}

async function revokeAllStaffSessions(staffId) {
  if (!requirePermission('staff.manage', 'Сброс staff sessions')) return;
  if (!window.confirm('Сбросить все активные sessions выбранного сотрудника?')) return;
  try {
    const result = await apiPost(`/api/v1/admin/staff/${encodeURIComponent(staffId)}/sessions/revoke-all`, {});
    await openStaffSessions(staffId);
    await loadDashboardData();
    setNotice(`Staff sessions сброшены: ${escapeHtml(result.revokedSessions, '0')}.`);
  } catch (error) {
    setNotice(`Не удалось сбросить staff sessions: ${error.message}`, true);
  }
}

async function loadDashboardData() {
  if (!hasAdminCredential()) {
    setSidebarStatus('нужен токен', 'muted');
    setNotice('Войди сотрудником или вставь bootstrap admin token, чтобы открыть внутреннюю панель.', true);
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
  addAllowedRequest(requests, 'featureFlags', 'flags.read', () => apiGet('/api/v1/admin/feature-flags'));
  addAllowedRequest(requests, 'runbooks', 'runbooks.read', () => apiGet('/api/v1/admin/runbooks'));
  addAllowedRequest(requests, 'servers', 'servers.read', () => apiGet(`/api/v1/admin/server-catalog${encodeQuery(serverFilterParams())}`));
  addAllowedRequest(requests, 'serverPublicationReadiness', 'servers.read', () => apiGet('/api/v1/admin/server-catalog/publication-readiness'));
  addAllowedRequest(requests, 'serverProvisioningReadiness', 'servers.read', () => apiGet('/api/v1/admin/server-catalog/provisioning-readiness'));
  addAllowedRequest(requests, 'serverHealth', 'monitoring.read', () => apiGet(`/api/v1/admin/server-health${encodeQuery(serverHealthFilterParams())}`));
  addAllowedRequest(requests, 'monitoringTargets', 'monitoring.read', () => apiGet(`/api/v1/admin/monitoring/targets${encodeQuery(monitoringTargetFilterParams())}`));
  addAllowedRequest(requests, 'serviceObservations', 'monitoring.read', () => apiGet(`/api/v1/admin/monitoring/service-observations${encodeQuery(serviceObservationFilterParams())}`));
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
        state.loaded.servers = value.managedEntries || [];
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
          <p class="eyebrow">Review</p>
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
        <p class="eyebrow">Decoded report для техподдержки</p>
        <pre class="report-code">${decoded ? escapeHtml(prettyJson(decoded)) : escapeHtml(decodedError || 'Decoded report пока недоступен.')}</pre>
      </div>
      <div>
        <p class="eyebrow">Encoded report</p>
        <pre class="report-code compact">${escapeHtml(report.report)}</pre>
      </div>
    `;
    if (canManageSupport) {
      $('reviewReportButton')?.addEventListener('click', async () => {
        if (!requirePermission('support.manage', 'Review support report')) return;
        await apiPost(`/api/v1/admin/support/reports/${report.id}/review`, {
          assignedTo: $('reportAssignedInput').value || currentSupportAssignee(),
          note: $('reportNoteInput').value || 'Отчёт взят в работу из Green VPN Admin Console.',
        });
        await loadDashboardData();
        await openReport(report.id);
      });
      $('saveReportStatusButton').addEventListener('click', async () => {
        if (!requirePermission('support.manage', 'Сохранение support report')) return;
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
        if (!requirePermission('support.manage', 'Комментарий support report')) return;
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
  } catch (error) {
    setNotice(`Не удалось открыть отчёт: ${error.message}`, true);
  }
}

async function reviewReport(reportId) {
  if (!requirePermission('support.manage', 'Review support report')) return;
  try {
    await apiPost(`/api/v1/admin/support/reports/${reportId}/review`, {
      assignedTo: currentSupportAssignee(),
      note: 'Отчёт взят в работу из Green VPN Admin Console.',
    });
    await loadDashboardData();
    setNotice('Отчёт взят в работу.');
  } catch (error) {
    setNotice(`Не удалось взять отчёт в работу: ${error.message}`, true);
  }
}

async function resolveReport(reportId) {
  if (!requirePermission('support.manage', 'Закрытие support report')) return;
  try {
    await apiPost(`/api/v1/admin/support/reports/${reportId}/status`, {
      status: 'resolved',
      note: 'Marked as resolved from Green VPN Admin Console.',
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
    note: assigneeValue ? 'Ответственный назначен из Green VPN Admin Console.' : 'Ответственный снят из Green VPN Admin Console.',
  });
}

function renderMiniOrders(orders = []) {
  if (!orders.length) return '<p class="muted">Заказов пока нет.</p>';
  return `
    <table class="mini-table">
      <thead>
        <tr>
          <th>Order</th>
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
                <td>${escapeHtml(order.status)}</td>
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
                <td>${escapeHtml(report.status)}</td>
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
        title: 'Выдать support trial на 3 дня',
        requiresDevice: false,
        requiresReason: true,
        danger: false,
        confirmationText: 'Выдать пользователю временный support trial на 3 дня?',
        description: 'Продлевает trial/support_trial на 3 дня и не перезаписывает активную платную подписку.',
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
                <td><span class="status-pill ${supportActionStatusClass(action.status)}">${escapeHtml(action.status)}</span></td>
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
        ${escapeHtml(action.danger ? `${action.title} · осторожно` : action.title)}
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
          <span class="status-pill muted">User #${escapeHtml(user.id)}</span>
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
                <span>Platform: ${escapeHtml(device.platform)}</span>
                <span>App: ${escapeHtml(device.appVersion)}</span>
                <span>IP: ${escapeHtml(device.assignedIp)}</span>
                <span>Last seen: ${escapeHtml(shortDate(device.lastSeenAt))}</span>
                <span>Last config: ${escapeHtml(shortDate(device.lastConfigAt))}</span>
                <span>Config refresh: ${
                  device.supportConfigRefreshRequestedAt
                    ? `${escapeHtml(shortDate(device.supportConfigRefreshRequestedAt))} · ${escapeHtml(device.supportConfigRefreshReason)}`
                    : 'нет'
                }</span>
                <span>Refresh applied: ${
                  device.supportConfigRefreshAppliedAt
                    ? `${escapeHtml(shortDate(device.supportConfigRefreshAppliedAt))} · ${escapeHtml(device.supportConfigRefreshAppliedReason)}`
                    : 'нет'
                }</span>
                <span>Reason: ${escapeHtml(device.disabledReason)}</span>
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

async function openUser(userId) {
  try {
    state.activeUserId = userId;
    const response = await apiGet(`/api/v1/admin/users/${userId}`);
    const user = response.user;
    const subscription = response.subscription || user.subscription || {};
    $('userDialogTitle').textContent = `${user.email || user.phone || `User #${user.id}`}`;
    $('userDialogBody').innerHTML = `
      <div class="detail-grid">
        <section class="detail-card">
          <p class="eyebrow">Аккаунт</p>
          <h3>${escapeHtml(user.email || 'Email не указан')}</h3>
          <div class="detail-meta">
            <span>ID: #${escapeHtml(user.id)}</span>
            <span>Телефон: ${escapeHtml(user.phone)}</span>
            <span>Email verified: ${boolLabel(user.emailVerified)}</span>
            <span>Phone verified: ${boolLabel(user.phoneVerified)}</span>
            <span>Создан: ${escapeHtml(shortDate(user.createdAt))}</span>
          </div>
        </section>
        <section class="detail-card">
          <p class="eyebrow">Подписка</p>
          <h3>${escapeHtml(subscription.planName || 'Нет активного тарифа')}</h3>
          <div class="detail-meta">
            <span>Активна: ${boolLabel(subscription.isActive)}</span>
            <span>До: ${escapeHtml(shortDate(subscription.expiresAt))}</span>
            <span>Устройств: ${escapeHtml(subscription.maxDevices)}</span>
            <span>Автопродление: ${boolLabel(subscription.autoRenew)}</span>
          </div>
        </section>
      </div>
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
    setNotice(`Тестовый Telegram alert отправлен: ${safeText(result?.result?.status, 'ok')}.`);
  } catch (error) {
    setNotice(`Telegram alert пока не готов: ${error.message}`, true);
  }
}

function bindEvents() {
  $('loginForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    try {
      state.apiBase = normalizeApiBase($('apiBaseInput').value);
      if (state.pendingAdmin2fa) {
        await verifyAdminTwoFactor();
        return;
      }
      const email = $('adminEmailInput').value.trim().toLowerCase();
      const password = $('adminPasswordInput').value;
      const bootstrapToken = $('adminTokenInput').value.trim();
      const actor = $('adminActorInput').value.trim();
      if (email && password) {
        const loginResult = await loginWithStaffSession(email, password, actor);
        if (loginResult?.pending) return;
      } else if (bootstrapToken) {
        await loginWithBootstrapToken(bootstrapToken, actor);
      } else {
        setNotice('Введи email+пароль сотрудника или bootstrap admin token.', true);
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
        note: 'Инцидент взят в работу из Green VPN Admin Console.',
      });
      return;
    }
    const incidentResolveButton = event.target.closest('[data-incident-resolve]');
    if (incidentResolveButton) {
      updateIncident(incidentResolveButton.dataset.incidentResolve, {
        status: 'resolved',
        ...currentIncidentAssigneePayload(),
        note: 'Инцидент закрыт вручную из Green VPN Admin Console.',
      });
      return;
    }
    const incidentOpenButton = event.target.closest('[data-incident-open]');
    if (incidentOpenButton) {
      updateIncident(incidentOpenButton.dataset.incidentOpen, {
        status: 'open',
        ...currentIncidentAssigneePayload(),
        note: 'Инцидент переоткрыт вручную из Green VPN Admin Console.',
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
      if (!requirePermission('updates.manage', 'Редактирование release')) return;
      fillReleaseForm(findRelease(releaseEditButton.dataset.releaseEdit));
      setNotice('Release загружен в форму. Можно поправить поля и сохранить.');
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
      if (!requirePermission('flags.manage', 'Редактирование feature flag')) return;
      fillFeatureFlagForm(findFeatureFlag(featureFlagEditButton.dataset.featureFlagEdit));
      setNotice('Feature flag загружен в форму. Можно поправить поля и сохранить.');
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
      if (!requirePermission('servers.manage', 'Редактирование endpoint')) return;
      fillServerForm(findServerEntry(serverEditButton.dataset.serverEdit));
      setNotice('Endpoint загружен в форму. Можно поправить поля и сохранить.');
      return;
    }
    const serverHealthyButton = event.target.closest('[data-server-healthy]');
    if (serverHealthyButton) {
      updateServerEntryStatus(serverHealthyButton.dataset.serverHealthy, 'healthy');
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
  $('closeUserDialog').addEventListener('click', () => $('userDialog').close());
}

function init() {
  loadSession();
  $('apiBaseInput').value = state.apiBase;
  $('adminEmailInput').value = state.adminEmail;
  $('adminTokenInput').value = state.adminToken;
  $('adminActorInput').value = state.adminActor;
  $('sidebarApiBase').textContent = state.apiBase;
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
