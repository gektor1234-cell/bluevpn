# Green VPN Admin / Support App

Дата: 2026-05-06

Это первый отдельный внутренний интерфейс для администратора и техподдержки. Он специально вынесен из обычного пользовательского клиента Green VPN.

## Где лежит

```text
C:\Users\gekto\projects\bluevpn\admin_support_app
```

Файлы:

- `index.html` - разметка админки.
- `styles.css` - визуальная система в стиле Green VPN.
- `app.js` - подключение к backend API.
- `README.md` - короткая локальная инструкция.

## Что уже есть

- Отдельный экран подключения API.
- Поле `API base URL`, по умолчанию `https://api.greenvpn.pro`.
- Основной вход сотрудника по email и паролю.
- Bootstrap `Admin token` оставлен как аварийный/owner-способ на время разработки; токен не хранится в репозитории.
- Админка получает короткоживущую staff-сессию и дальше отправляет `Authorization: Bearer <sessionToken>`.
- Интерфейс скрывает разделы, на которые у текущей роли нет прав.
- `Запомнить на этом компьютере` теперь выключено по умолчанию, чтобы случайно не сохранять bootstrap token/session token в браузере.
- Обзор пользователей, устройств, активных подписок, pending-заказов и support reports.
- Раздел техподдержки с пользовательскими отчётами.
- Поиск обращений по email, user id и device id.
- Просмотр encoded `GVPN1.` отчёта.
- Серверный decode `GVPN1.` отчёта в человекочитаемый JSON для поддержки.
- Дополнительная redaction-проверка при decode: если в отчёт случайно попадут поля или значения, похожие на `token`, `password`, `privateKey`, `secret`, WireGuard keys или provider credentials, они будут скрыты до показа поддержке.
- Смена статуса support report: `new`, `triage`, `in_progress`, `waiting_user`, `resolved`, `closed`.
- Быстрое действие `В работу` для support report фиксирует `reviewedAt/reviewedBy`, первый ответ и исполнителя, затем пишет audit.
- Авто-разбор новых обращений по категориям и приоритетам:
  - категории: VPN/connect, сеть, auth, платежи, installer, UI, общее;
  - приоритеты: срочно, высокий, обычный, низкий;
  - SLA due time для первого уровня реакции.
- Фильтры обращений по статусу, приоритету, категории и назначенному оператору.
- В карточке обращения поддержка может менять статус, приоритет, категорию, SLA и назначенного оператора.
- Комментарии поддержки внутри обращения: что проверили, что сделали, что ждём от пользователя.
- Первое действие поддержки фиксирует `first_response_at` для будущей SLA-аналитики.
- Раздел пользователей.
- Поиск пользователей по email, телефону и device id.
- Карточка пользователя: аккаунт, телефон/email verification, подписка, устройства, заказы, последние обращения.
- Ручное отключение/включение устройства пользователя из карточки поддержки.
- Быстрые действия поддержки в карточке пользователя:
  - сбросить user sessions;
  - запросить refresh/reissue config для одного устройства или всех устройств пользователя;
  - снять запрос refresh/reissue config;
  - отключить конкретное устройство;
  - включить конкретное устройство;
  - добавить внутреннюю заметку.
- История быстрых действий поддержки отображается в карточке пользователя и пишется в backend audit.
- Быстрые действия не показывают и не возвращают пароли, токены, WireGuard private keys или содержимое конфигов.
- Запрос `request_config_refresh` теперь реально применяется при следующей выдаче `/api/v1/client/config`: backend перевыпускает клиентские WireGuard keys/PSK, заменяет peer, очищает marker и показывает в карточке устройства время/причину последнего применения.
- Фильтрация support reports на backend по `status`, `userId`, `email`, `deviceUid`.
- Раздел заказов.
- Фильтр заказов `all` теперь действительно показывает все заказы, а не ищет статус `all`.
- Раздел заказов показывает billing reconciliation summary:
  - paid-but-not-activated;
  - paid_at без activated_at;
  - старые pending-заказы;
  - YooKassa payment creation gaps;
  - несостыковки terminal status/payment markers.
- Backend endpoint `GET /api/v1/admin/billing/reconciliation` доступен роли с `billing.read`.
- Backend endpoint `GET /api/v1/admin/billing/renewals/readiness` доступен роли с `billing.read` и показывает dry-run auto-renewal readiness: upcoming candidates, missing saved payment method, pending auto-renew conflicts, YooKassa production blocker, and boolean `hasProviderPaymentMethod` without raw provider payment method ids.
- Backend endpoint `GET /api/v1/admin/subscriptions/expiry-readiness` доступен роли с `billing.read` и показывает dry-run subscription expiry readiness: expired-active rows, expiring manual paid subscriptions, missing retention contact, auto-renew blockers, and no raw provider payment method ids.
- Startup backfill deactivates only expired non-paid trial/support rows; paid plans are not silently changed and stay visible for manual review.
- Manual `mark-paid` activation больше не активирует `failed` / `canceled` / `cancelled` order; для таких случаев нужен новый order или отдельное осознанное решение владельца.
- Раздел заказов теперь включает внутреннюю панель акций и промокодов.
- Акции поддерживают процентную скидку или фиксированную скидку в рублях, лимит использований, даты начала/окончания, ограничение по тарифам и внутреннюю заметку.
- Backend хранит original amount, discount amount и promo code в billing order, а успешное применение фиксирует redemption без вывода платёжных секретов.
- Раздел акций теперь показывает готовность стартовой кампании: слишком большую/вечную скидку, отсутствие лимита, просроченные даты, отсутствие ограничения по тарифам и другие риски перед рекламой.
- Для первого запуска подготовлена безопасная акция `START20`: рекомендуемая скидка 20%, лимит 100 использований, окно 30 дней, тарифы `starter/base/plus`.
- Кнопка `Заполнить START20` только заполняет форму в админке, а `Черновик START20` создаёт неактивный черновик через backend; акция не включается сама и не даёт пользователям скидку до ручной активации.
- Раздел событий входа по email/phone code.
- Фильтр событий входа поддерживает `too_many_attempts`, чтобы видеть lockout после перебора кода.
- Раздел `Аудит`: журнал ручных действий поддержки/админа с action, target, IP, временем и details.
- Поле `Кто работает` для указания оператора, чтобы действия в audit не выглядели как безличный `admin_token`.
- Раздел `Команда`.
- Подготовленная ролевая модель: `owner`, `admin`, `support`, `finance`, `readonly`.
- Список сотрудников внутренней команды.
- Добавление/обновление сотрудника по email, имени и роли.
- Включение/выключение внутреннего сотрудника.
- Задание временного пароля сотруднику без сохранения открытого пароля.
- Backend хранит только PBKDF2-SHA256 hash пароля с солью.
- Сотрудник может входить без общего admin token.
- Owner/admin может открыть sessions конкретного сотрудника, отозвать одну session или сбросить все активные sessions сотрудника. Текущая собственная session не отзывается случайно через revoke-all.
- В staff/session UI показываются только короткие public session id, IP, user-agent, время входа и последняя активность; raw session token не возвращается.
- Backend проверяет права на admin endpoints по permission matrix:
  - `support.read` / `support.manage`;
  - `support_actions.read` / `support_actions.manage`;
  - `users.read` / `devices.manage`;
  - `billing.read` / `billing.manage`;
  - `staff.manage`;
  - `audit.read`;
  - `readiness.read`;
  - `monitoring.read` / `monitoring.manage`;
  - `incidents.read` / `incidents.manage`;
  - `updates.read` / `updates.manage`;
  - `servers.read` / `servers.manage`.
- Раздел `Инциденты`.
- Автоматическое создание внутренних инцидентов из мониторинга backend/WireGuard/catalog/payments/updates и service checks.
- Автоматическое закрытие инцидентов, когда соответствующая проверка снова становится зелёной.
- Инциденты показывают подсказки релевантных runbook по платежам, входу, VPN/WireGuard, серверам/API/catalog, мониторингу и обновлениям.
- Инциденты можно назначать на активных сотрудников через safe assignee dropdown; support-роль видит список исполнителей без полного доступа к управлению командой.
- Фильтры инцидентов по статусу и важности.
- Фильтры инцидентов включают исполнителя и `Не назначены`.
- Readiness/alerts section показывает историю последних incident alerts из внутреннего outbox.
- Пока Telegram bot token/chat id не настроены, high/critical incidents пишут `skipped/manual_mvp` events без секретов; после настройки будут видны `sent`/`failed`.
- Ручные действия поддержки по инцидентам:
  - взять в работу;
  - отметить решённым;
  - открыть снова.
- Инцидентные действия попадают в audit с actor из `X-Admin-Actor`.
- Раздел `Серверы`.
- Просмотр текущего публичного catalog, который пока выдаёт клиентам только проверенный `intelligent_smew`.
- Внутренний managed catalog для подготовки новых стран, провайдеров, протоколов и fallback endpoint без публикации их пользователям.
- Статусы endpoint: `draft`, `healthy`, `degraded`, `maintenance`, `disabled`.
- Подготовленные протоколы и транспорты: WireGuard UDP/TCP, OpenVPN TCP, Shadowsocks, Hysteria2, stealth, UDP/TCP/TLS/QUIC/HTTP3.
- Ручное добавление/обновление internal server entry.
- Быстрое действие `Healthy` для готового endpoint.
- Быстрое действие `Disable` для endpoint, который нельзя выдавать пользователям.
- Public/client catalog пока не меняется автоматически от managed entries. Это специально, чтобы не сломать рабочий VPN до закупки и проверки новых серверов.
- Внутренние server health observations: probe region, protocol, transport, status, latency, packet loss и message по endpoint.
- Health observations могут обновлять health/status/latency internal managed endpoint, но не меняют пользовательскую маршрутизацию без отдельного safe-rollout слоя.
- `GET /api/v1/admin/server-health` показывает `externalProbeReadiness`: нужен ли внешний monitoring VPS, какие config-ready endpoints обязательны, покрыт ли `current_wg0`, свежие ли внешние observations и есть ли degraded/down за 24 часа.
- Раздел `Серверы -> Наблюдения здоровья` показывает external endpoint probes и покрытие обязательных endpoint; без отдельного VPS это ожидаемо остаётся не production-ready.
- Раздел `Серверы -> Каталог серверов` теперь может создать безопасный внутренний черновик нового VPS через `POST /api/v1/admin/server-catalog/draft-from-plan`: запись всегда остается `draft`, `isPublic=false`, `isActive=false`, `clientConfigProfile=none` и не попадает в пользовательский каталог.
- В таблице `Серверы -> Управляемые серверы` у записей с профилем `remote_ssh_wg0` есть кнопка `Peer-smoke`: backend временно добавляет WireGuard peer на удалённый `wg0`, проверяет наличие peer, удаляет его и показывает только безопасный результат.
- С 2026-05-15 таблица `Серверы -> Управляемые серверы` показывает отдельную колонку нагрузки: текущая/доступная ёмкость, оценка capacity, active clients и assigned users.
- Там же есть кнопка `Тест конфига`: backend собирает форму клиентского WireGuard-конфига для выбранного remote-узла, проверяет временный peer и удаляет его; сам конфиг и ключи в ответ не возвращаются.
- Там же есть безопасные действия `Открыть клиентам` и `Скрыть`: перед публикацией backend делает dry-run publication gate и не даст открыть узел, если здоровье, мониторинг или выдача конфига не готовы.
- Controlled probe runner `scripts/monitoring/service_probe.py --server-health` умеет присылать безопасные endpoint observations вместе с service availability observations; payload не содержит токены, пароли, WireGuard private keys или raw config.
- Degraded/down server-health observations теперь открывают внутренний incident `server-health:<endpointId>`, а healthy observation закрывает его; инцидент виден в разделе `Инциденты` и получает runbook-подсказки/alert outbox как остальные monitoring incidents.
- Если managed endpoint был отмечен кандидатом в публичный catalog, но новая health observation стала `down`/`degraded` или score упал ниже порога публикации, backend автоматически снимает public-candidate флаг, пишет причину `auto-paused` и audit event.
- Раздел `Аналитика`.
- Бизнес-метрики: пользователи, заказы, gross revenue, paid/manual orders.
- Support/incident-метрики: открытые обращения, urgent/high SLA, открытые incident, критичные incident.
- Readiness-метрики: payments, email, SMS, update manifest, server catalog, monitoring.
- Trend-метрики за 14 дней для пользователей, заказов, выручки и support reports.
- Production readiness checklist.
- Мониторинг backend/WireGuard/важных сервисов.
- Раздел `Мониторинг`.
- Управляемые monitoring targets для внутренних проверок:
  - YouTube;
  - Discord;
  - Telegram;
  - Green VPN API;
  - production API/bootstrap domain;
  - update manifest;
  - payment return page;
  - future Social Only targets.
- Статусы target: `active`, `paused`, `disabled`.
- Типы target: `web`, `api`, `dns`, `tcp`, `tls`, `telegram`, `discord`, `youtube`, `payment`, `update`, `bootstrap`, `social`.
- Service availability observations по target:
  - `green` - работает;
  - `yellow` - деградация;
  - `red` - недоступно;
  - `unknown` - нет уверенного результата.
- Observations хранят probe id, probe region, latency, error code, message и sanitized details.
- Красные/жёлтые service observations могут создавать или переоткрывать внутренние инциденты, зелёные могут закрывать соответствующий инцидент.
- Это только внутренняя админская функция. В обычном пользовательском Green VPN не должно быть экрана `Состояние сервисов` или похожей технической витрины.
- Внутренний checklist внешних действий, который backend отдаёт через `/api/v1/admin/external-actions`:
  - домен/API/HTTPS;
  - Yandex 360 SMTP;
  - SMS.ru;
  - YooKassa;
  - update hosting;
  - server catalog;
  - monitoring probes;
  - Telegram alerts.
- Checklist показывает, что уже готово, что ждёт внешних данных от владельца, какие env-переменные нужны, какие пункты блокируют production-ready режим и где нельзя хранить секреты.
- Checklist теперь показывает безопасный owner setup bundle: команду применения server-only env, команду проверки readiness, ожидаемые публичные DNS-записи и safe defaults без секретных значений.
- Каждый внешний пункт показывает `ownerInputs`, `applySteps` и `verifySteps`; секретные поля помечены как `secret`, но реальные значения туда не попадают.
- Checklist теперь поддерживает ручной owner workflow: `нужно сделать`, `в работе`, `ждёт владельца`, `ждёт провайдера`, `готово к применению`, `сделано`, `заблокировано`, `не нужно`.
- Owner workflow нужен, чтобы не терять состояние внешних задач: домен, DMARC, SMTP, SMS.ru, YooKassa, update hosting, monitoring VPS и Telegram alerts.
- Ручная отметка `сделано` не включает production-ready сама по себе; backend всё равно ждёт реальные DNS/env/HTTPS/provider-проверки.
- Заметки owner workflow хранят только безопасный операционный контекст. Пароли, токены, `admin_token`, SMTP-пароли, SMS API keys, YooKassa secret key и SSH-пароли туда писать нельзя.
- Telegram incident alerts подготовлены как server-only интеграция:
  - readiness endpoint `/api/v1/admin/alerts/readiness`;
  - test endpoint `/api/v1/admin/alerts/test`;
  - кнопка `Проверить Telegram alert` в админке;
  - последние попытки отправки видны в таблице инцидентов.
- Если Telegram token/chat id не заданы, админка показывает `manual_mvp`, но backend и пользовательское приложение не ломаются.
- Раздел `Флаги`.
- Внутренние feature flags для безопасного включения/выключения функций без нового релиза клиента.
- Флаги имеют scope, rollout percent, JSON value, заметки и статус enabled/disabled.
- Флаги не публикуются в обычный пользовательский клиент автоматически; это internal/admin слой для rollout и ops.
- Раздел `Обновления`.
- Release-записи поддерживают draft/published/paused/retired, stable/beta/internal, download URL, SHA256, min supported version, required update и rollout percent.
- Preview manifest теперь показывает staged rollout decision: `updateAvailable`, `rolloutEligible`, `rolloutReason`.
- Пользовательский Green VPN доверяет серверному `updateAvailable`, поэтому можно выкатывать новую версию постепенно и не показывать её всем устройствам одновременно.
- Release table показывает per-release publication gate: готовность URL/SHA256, public HTTPS, blockers/warnings и можно ли публиковать.
- Backend всё равно остаётся authoritative: publish без final artifact/public HTTPS/SHA256 блокируется, даже если UI устарел.
- Раздел `Инструкции`.
- Runbooks для техподдержки/ops: VPN не подключается, нет handshake, оплата прошла без тарифа, падение API, деградация важного сервиса.
- Runbook содержит категорию, важность, роль владельца и пошаговый чеклист.
- Активные runbooks автоматически предлагаются в карточках инцидентов, чтобы поддержка сразу видела ближайший рабочий чеклист.
- Runbooks являются внутренним инструментом поддержки и не должны появляться в пользовательском Green VPN.
- Controlled monitoring probe runner подготовлен:
  - `C:\Users\gekto\projects\bluevpn\scripts\monitoring\service_probe.py`;
  - `C:\Users\gekto\projects\bluevpn\scripts\monitoring\install_probe_systemd.sh`.
- Probe runner читает managed monitoring targets с backend, проверяет DNS/TCP/TLS/HTTP и отправляет sanitized observations обратно в backend.
- Установщик probe хранит admin token только на probe-сервере в `/etc/greenvpn-monitoring/admin_token` с правами `600`, не в репозитории.
- `GET /api/v1/admin/monitoring/readiness` отдаёт safe install bundle для первого внешнего monitoring VPS: команда установки, `--token-stdin`, token path, required targets, owner inputs, apply steps и verify steps без секретных значений.
- Панель `Агенты мониторинга` показывает этот install bundle, чтобы после покупки VPS установка не требовала нового выяснения контекста.
- Readiness checker подготовлен:
  - `C:\Users\gekto\projects\bluevpn\scripts\windows\check_external_services_readiness.ps1`;
  - умеет проверять DNS, API health, backend HTTPS со стороны самого сервера и защищённые admin endpoints через server-side self-check без вывода `admin_token`.
  - server-side self-check также покрывает staff list/session inventory и проверяет наличие staff-session revoke routes без отзыва живых sessions.
  - server-side self-check проверяет, что external-actions checklist содержит setup bundle, owner inputs и verify steps.
  - server-side self-check проверяет, что monitoring readiness содержит external probe install bundle и команду с `--token-stdin`.
  - DNS ошибки теперь показывают ожидаемое публичное значение, например для `_dmarc.greenvpn.pro`, без привязки к секретам.

## Как запускать

Самый простой способ:

```text
Открыть C:\Users\gekto\projects\bluevpn\admin_support_app\index.html в браузере.
```

Более стабильный способ через локальный static server:

```powershell
cd C:\Users\gekto\projects\bluevpn\admin_support_app
python -m http.server 8090
```

Открыть:

```text
http://127.0.0.1:8090
```

## Что нужно для входа

Основной режим:

1. Войти bootstrap admin token только владельцу/главному админу.
2. Открыть раздел `Команда`.
3. Создать сотрудника или обновить существующего.
4. Задать роль и временный пароль минимум 10 символов.
5. Сотрудник входит по email + паролю.
6. После входа админка работает через session token, а не через общий bootstrap token.

Bootstrap `admin_token` нужен только для начальной настройки или аварийного восстановления доступа. Его нельзя писать в документы, коммиты, скриншоты и чат без необходимости.

Ожидаемый API:

```text
https://api.greenvpn.pro
```

Если API-домен временно недоступен с локальной машины, можно использовать:

```text
http://37.220.85.211:8000
```

## Backend endpoints

Админка использует:

```text
POST /api/v1/admin/auth/login
GET  /api/v1/admin/auth/me
POST /api/v1/admin/auth/logout
GET  /api/v1/admin/overview
GET  /api/v1/admin/readiness
GET  /api/v1/admin/external-actions
POST /api/v1/admin/external-actions/{action_code}
GET  /api/v1/admin/updates/readiness
GET  /api/v1/admin/updates/releases
POST /api/v1/admin/updates/releases
POST /api/v1/admin/updates/releases/{release_id}
GET  /api/v1/admin/billing/reconciliation
GET  /api/v1/admin/billing/renewals/readiness
GET  /api/v1/admin/subscriptions/expiry-readiness
GET  /api/v1/admin/support/reports
GET  /api/v1/admin/support/reports/{report_id}
GET  /api/v1/admin/support/reports/{report_id}/decoded
POST /api/v1/admin/support/reports/{report_id}/review
POST /api/v1/admin/support/reports/{report_id}/status
GET  /api/v1/admin/support/reports/{report_id}/comments
POST /api/v1/admin/support/reports/{report_id}/comments
GET  /api/v1/admin/support/workflow
GET  /api/v1/admin/support/sla
GET  /api/v1/admin/support/actions/workflow
GET  /api/v1/admin/support/actions
POST /api/v1/admin/users/{user_id}/support-actions
GET  /api/v1/admin/audit
GET  /api/v1/admin/roles
GET  /api/v1/admin/staff
POST /api/v1/admin/staff
POST /api/v1/admin/staff/{staff_id}
GET  /api/v1/admin/feature-flags
POST /api/v1/admin/feature-flags
POST /api/v1/admin/feature-flags/{flag_id}
GET  /api/v1/admin/runbooks
POST /api/v1/admin/runbooks
POST /api/v1/admin/runbooks/{runbook_id}
GET  /api/v1/admin/incidents
POST /api/v1/admin/incidents/{incident_id}
GET  /api/v1/admin/server-catalog
GET  /api/v1/admin/server-catalog/publication-readiness
GET  /api/v1/admin/server-catalog/provisioning-readiness
GET  /api/v1/admin/server-catalog/{server_id}/publication-gate
POST /api/v1/admin/server-catalog/{server_id}/remote-peer-smoke
POST /api/v1/admin/server-catalog/{server_id}/client-config-smoke
POST /api/v1/admin/server-catalog/{server_id}/publish
POST /api/v1/admin/server-catalog/{server_id}/unpublish
POST /api/v1/admin/server-catalog/draft-from-plan
POST /api/v1/admin/server-catalog
POST /api/v1/admin/server-catalog/{entry_id}
GET  /api/v1/admin/server-health
POST /api/v1/admin/server-health/observations
GET  /api/v1/admin/monitoring/targets
POST /api/v1/admin/monitoring/targets
POST /api/v1/admin/monitoring/targets/{target_id}
GET  /api/v1/admin/monitoring/service-observations
GET  /api/v1/admin/monitoring/probes
POST /api/v1/admin/monitoring/service-observations
GET  /api/v1/admin/alerts/readiness
POST /api/v1/admin/alerts/test
GET  /api/v1/admin/analytics/summary
GET  /api/v1/admin/users
GET  /api/v1/admin/users/{user_id}
GET  /api/v1/admin/users/{user_id}/devices
POST /api/v1/admin/devices/{device_uid}/disable
POST /api/v1/admin/devices/{device_uid}/enable
GET  /api/v1/admin/billing/orders
GET  /api/v1/admin/billing/promos
POST /api/v1/admin/billing/promos
GET  /api/v1/admin/billing/promos/readiness
POST /api/v1/admin/billing/promos/draft-start-campaign
POST /api/v1/admin/billing/promos/{code}/activate
POST /api/v1/admin/billing/promos/{code}/deactivate
GET  /api/v1/admin/auth/events
GET  /api/v1/monitoring/status
GET  /api/v1/monitoring/services
```

Админские endpoints принимают один из двух способов авторизации.

Основной staff login:

```text
Authorization: Bearer <admin session token>
```

Аварийный/bootstrap режим:

```text
X-Admin-Token: <admin token>
```

Админка также может передавать:

```text
X-Admin-Actor: <operator email/name>
```

Это не заменяет авторизацию. Это MVP-атрибуция действий для audit, чтобы до полноценного входа сотрудников было видно, кто сделал ручное действие.

## Безопасность

- Раздел `Обновления` показывает publication gate и rollback readiness. Stable full rollout (`rolloutPercent >= 100`) и required update должны ждать готовый rollback artifact; staged rollout можно готовить заранее без сборки нового installer.
- Раздел `Готовность` / external owner actions показывает owner-action audit: статусы ожидания/блокировки/ручного закрытия требуют заметку без секретов, а ручное `done` до зелёного backend readiness выделяется отдельно.
- External owner action notes дополнительно проверяются в браузере перед отправкой: очевидные private keys, bearer/admin tokens, password/secret/provider env assignments блокируются без вывода значения.
- API errors в admin app форматируются человекочитаемо; structured `detail` больше не отображается как `[object Object]`, а чувствительные поля вроде `input`, `password`, `secret`, `token` и private keys редактируются в fallback JSON.
- Раздел `Готовность` показывает owner launch packet из `GET /api/v1/admin/launch/owner-packet`: команды с метками `secret`/`mutationFree`, pending owner inputs и after-apply checks без secret values.
- Раздел `Поддержка` показывает SLA queue над таблицей обращений: overdue/due soon/missing SLA, missing first response и review-pending.
- Раздел `Платежи` показывает dry-run auto-renewal readiness; raw provider payment method ids не возвращаются в admin API.
- Раздел `Пользователи` показывает dry-run subscription expiry readiness перед включением subscription enforcement.
- В репозитории нет `admin_token`.
- В репозитории нет staff-паролей.
- Staff-пароли не возвращаются через API.
- Temporary password приходит на backend один раз и хранится только как hash.
- Staff session token хранится на backend только как SHA256 hash.
- Staff session self-service уже закрыт release/readiness guards: сотрудник может сменить пароль, увидеть свои sessions, отозвать отдельную чужую session и сбросить остальные sessions без bootstrap token.
- В админке нет cookie-based auth, поэтому CORS не завязан на browser cookies.
- Backend разрешает CORS для админки через `GREENVPN_ADMIN_CORS_ORIGINS`.
- Для текущего MVP значение по умолчанию `*`, потому что админка может запускаться локально как `file://` или `http://127.0.0.1`.
- Ролевая матрица уже применяется на backend endpoints.
- Общий bootstrap `admin_token` остаётся только как аварийный режим и должен использоваться минимально.

## Следующие шаги

- Добавить смену временного пароля самим сотрудником.
- Добавить более удобные owner-only bulk actions в раздел `Команда`.
- Добавить 2FA для сотрудников админки.
- Добавить отдельные владельческие actions, которые доступны только роли `owner`.
- Добавить отдельную кнопку ручной немедленной перевыдачи config без ожидания следующего client config fetch, если она понадобится поддержке.
- Более глубокий support workflow: категории проблем, SLA, комментарии и история действий.
- История обращений.
- Финансовая аналитика и графики.
- Incident dashboard для мониторинга YouTube/Discord/Telegram уже начат; runbook-подсказки, назначение ответственных и внутренний alert outbox уже связаны с инцидентами, дальше нужна реальная Telegram-доставка после bot token/chat id.
- Managed server catalog уже связан с health/config-readiness и provisioning gate; дальше нужен отдельный multi-endpoint peer/config слой перед публикацией дополнительных endpoint в клиентский catalog.
- Поставить первый controlled monitoring probe runner на отдельный маленький VPS, когда будет выбран monitoring-сервер.
- Подключить Telegram bot token/chat id через server-only env, затем включить `GREENVPN_ADMIN_ALERTS_ENABLED=1`.
- Добавить email/internal banner alerts после проверки Telegram alert flow.
- Дальше развить safe-rollout правила: canary/rollout percent для managed endpoint после закупки новых серверов и внешних probes.
