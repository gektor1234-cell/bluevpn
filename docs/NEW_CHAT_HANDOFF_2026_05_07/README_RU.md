# Green VPN: пакет передачи в новый чат от 2026-05-07

Этот каталог создан, чтобы новый Codex-чат продолжил текущую работу почти без разрыва контекста.

Главная идея: новый чат не должен перечитывать весь старый диалог. Он сначала читает этот пакет, затем точечно открывает код и большие документы.

## Как использовать

1. Открой новый чат Codex в этом же проекте.
2. Первым сообщением вставь текст из:
   `C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07\01_START_MESSAGE_RU.md`
3. Попроси новый чат прочитать пакет в таком порядке:
   - `00_COVER_LETTER_RU.md`
   - `02_WORKFLOW_AND_COMMUNICATION_RU.md`
   - `03_PROJECT_STATE_RU.md`
   - `04_NON_NEGOTIABLE_RULES_RU.md`
   - `06_YOOKASSA_AND_PAYMENTS_RU.md`
   - `13_NEXT_DEVELOPMENT_TASKS_RU.md`
   - `14_TEST_AND_DEPLOY_COMMANDS_RU.md`
4. Если новой задаче нужны детали, открыть нужный тематический файл из этого каталога.
5. Большие файлы `CURRENT_HANDOFF.md`, `RELEASE_STATE.md`, `GREENVPN_MASTER_PLAN.md` и `DEVELOPMENT_PROTOCOL.md` читать только точечно.

## Что внутри

- `00_COVER_LETTER_RU.md` - сопроводительное письмо: как мы общаемся, как работаем автономно и пошагово.
- `01_START_MESSAGE_RU.md` - готовое первое сообщение для нового чата.
- `02_WORKFLOW_AND_COMMUNICATION_RU.md` - рабочий протокол: автономные сессии, интерактивные внешние сервисы, отчеты.
- `03_PROJECT_STATE_RU.md` - текущее состояние проекта.
- `04_NON_NEGOTIABLE_RULES_RU.md` - правила, которые нельзя нарушать.
- `05_RELEASE_AND_ROLLBACK_RU.md` - installer, rollback и политика сборок.
- `06_YOOKASSA_AND_PAYMENTS_RU.md` - текущий статус ЮKassa и точные безопасные шаги подключения.
- `07_EXTERNAL_SERVICES_OWNER_ACTIONS_RU.md` - внешние сервисы: домен, почта, SMS, Telegram, VPS.
- `08_PUBLIC_SITE_LEGAL_BUSINESS_RU.md` - публичный сайт, легальные страницы, бизнес-позиционирование.
- `09_BACKEND_ADMIN_MONITORING_RU.md` - backend/admin monitoring, health scoring, probes.
- `10_SERVER_CATALOG_NETWORK_SPLIT_RU.md` - server catalog, новые VPS, API/VPN IP split.
- `11_USER_APP_INSTALLER_RU.md` - Windows-клиент, service, installer, clean test flow.
- `12_ADMIN_SUPPORT_APP_RU.md` - отдельная admin/support app.
- `13_NEXT_DEVELOPMENT_TASKS_RU.md` - ближайшие задачи после переноса.
- `14_TEST_AND_DEPLOY_COMMANDS_RU.md` - команды проверки, деплоя, readiness.
- `15_SECRET_HANDLING_RU.md` - политика секретов.
- `16_CONTEXT_HYGIENE_RU.md` - как снова не раздуть контекст.

## Самая короткая суть

Green VPN - Windows-first Flutter VPN-клиент с backend/admin/support tooling. Видимый бренд: `Green VPN`.

Текущий backend live: `0.9.67`.

Public site readiness live: `GET /api/v1/admin/site/readiness` green (`bannedPhraseMatches=0`).

Payment smoke readiness live: `GET /api/v1/admin/billing/payment-smoke/readiness`; currently blocked until YooKassa production keys are applied through safe env.

Billing renewals/expiry readiness require clean payment smoke before any safe-enable signal.

Payment launch safety CLI: `scripts\windows\check_payment_launch_safety.ps1`; owner packet command: `payment_launch_safety`.

Monitoring probe plan CLI: `scripts\windows\get_monitoring_probe_plan.ps1`; owner packet command: `monitoring_probe_plan`.

User auth flow readiness live: `GET /api/v1/admin/auth/user-flow/readiness` green (`phone_code` primary, `email_code` fallback, no codes/tokens exposed).

Launch closure plan live: `GET /api/v1/admin/launch/closure-plan`; support SLA is clean and inactive `START20` draft exists. Launch gates now have no unblocked autonomous next item; remaining items are owner/final/payment-dependent.

Owner launch packet live: `GET /api/v1/admin/launch/owner-packet`; gives owner-facing commands/inputs/checks without returning secret values.

Owner launch packet CLI: `scripts\windows\get_owner_launch_packet.ps1`; по умолчанию читает admin token только на сервере через SSH and prints a sanitized summary/JSON.

Owner-action notes are server-guarded: `POST /api/v1/admin/external-actions/{action_code}` rejects secret-looking notes before DB/audit writes and does not echo submitted values.

API/VPN split-plan live includes a mutation-free preflight command via `scripts\windows\check_api_vpn_split_preflight.ps1`; запускать после появления отдельного API/site IP или reverse proxy.

Separate admin/support app locally prechecks owner notes before POST, formats structured API errors without `[object Object]`, and renders the owner launch packet.

Текущий сервер/API: `37.220.85.211`, `https://api.greenvpn.pro`.

ЮKassa, по словам владельца, теперь активна в кабинете. Следующий шаг - безопасно применить `YOOKASSA_SHOP_ID` и `YOOKASSA_SECRET_KEY` через env-скрипт, не записывая secret key в чат или репозиторий.

Главный технический красный блокер перед публичным запуском: `api.greenvpn.pro` и VPN endpoint пока сидят на одном IP `37.220.85.211`. Для production нужно разделить API/site IP и VPN endpoint IP.

## Старый чат

Старый текущий чат можно использовать только как аварийный архив:

- если этот пакет и docs противоречат друг другу;
- если нужно восстановить точную историю решения;
- если пользователь прямо просит свериться со старым диалогом.

Не читать старую переписку по умолчанию.
