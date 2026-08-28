# Green VPN Backend Admin API

Текущее серверное администрирование Green VPN доступно через admin endpoint'ы на backend `37.220.85.211:8000`.

## Где лежит admin token

Токен администратора создаётся на сервере автоматически при старте backend:

- `/opt/bluevpn/backend/data/admin_token.txt`

Его не нужно хранить в репозитории.

## Auth model

С 2026-05-05 backend поддерживает две admin-auth модели.

### 1. Bootstrap admin token

Используется только для первичной настройки, аварийного входа и owner-действий во время разработки:

```text
X-Admin-Token: <admin token>
```

или:

```text
Authorization: Bearer <admin token>
```

Bootstrap token получает права роли `owner`, но его нельзя хранить в репозитории, документах, скриншотах или публичных логах.

### 2. Staff session

Основной режим для отдельного admin/support приложения:

```text
POST /api/v1/admin/auth/login
{
  "email": "support@greenvpn.pro",
  "password": "temporary-or-personal-password",
  "actor": "Имя оператора"
}
```

Backend возвращает `sessionToken`. Дальше admin app отправляет:

```text
Authorization: Bearer <sessionToken>
```

Backend хранит только SHA256 hash session token. Открытый token остаётся только в браузере администратора, если он сам включил `Запомнить на этом компьютере`.

Дополнительные endpoints:

```text
GET  /api/v1/admin/auth/me
POST /api/v1/admin/auth/logout
```

Staff-пароли:

- задаются через временный пароль в `POST /api/v1/admin/staff`;
- не возвращаются через API;
- хранятся как PBKDF2-SHA256 hash с солью;
- minimum length: 10 символов.

## RBAC

Backend теперь проверяет permission matrix на admin endpoints.

Роли:

- `owner`
- `admin`
- `support`
- `finance`
- `readonly`

Основные permissions:

- `dashboard.read`
- `analytics.read`
- `users.read`
- `users.manage`
- `devices.manage`
- `support.read`
- `support.manage`
- `support_actions.read`
- `support_actions.manage`
- `billing.read`
- `billing.manage`
- `staff.manage`
- `audit.read`
- `readiness.read`
- `readiness.manage`
- `monitoring.read`
- `monitoring.manage`
- `incidents.read`
- `incidents.manage`
- `updates.read`
- `updates.manage`
- `flags.read`
- `flags.manage`
- `runbooks.read`
- `runbooks.manage`
- `servers.read`
- `servers.manage`

Bootstrap token пока считается `owner`. Staff session получает права по роли сотрудника.

## Feature Flags И Runbooks

С версии backend source `0.9.4` подготовлен внутренний слой безопасного управления продуктом без нового релиза клиента на каждый мелкий переключатель.

Feature flags:

- endpoint list: `GET /api/v1/admin/feature-flags`;
- create: `POST /api/v1/admin/feature-flags`;
- update: `POST /api/v1/admin/feature-flags/{flag_id}`;
- permissions: `flags.read`, `flags.manage`;
- scopes: `global`, `windows`, `backend`, `billing`, `support`, `monitoring`, `rollout`;
- value хранится как JSON-строка, но через API отдаётся уже распарсенным объектом;
- дефолтные флаги создаются на старте backend и не попадают в публичный клиентский API автоматически.

Runbooks:

- endpoint list: `GET /api/v1/admin/runbooks`;
- create: `POST /api/v1/admin/runbooks`;
- update: `POST /api/v1/admin/runbooks/{runbook_id}`;
- permissions: `runbooks.read`, `runbooks.manage`;
- categories: `vpn`, `auth`, `billing`, `monitoring`, `server`, `installer`, `support`, `general`;
- severity: `critical`, `high`, `normal`, `low`;
- steps хранятся как список безопасных текстовых шагов;
- дефолтные инструкции создаются на старте backend для типовых ситуаций поддержки.

Задача этого слоя: дать админке управляемые флаги, ручные операционные инструкции и быстрые действия поддержки/ops без возвращения dev/admin-кнопок в пользовательский Green VPN.

## Updates / Staged Rollout

С версии backend source `0.9.7` update manifest поддерживает стабильный staged rollout по устройству.

Public endpoints:

- Windows client manifest: `GET /api/v1/updates/windows?currentVersion=<version>&clientId=<device_id>`;
- generic manifest: `GET /api/v1/updates/manifest?platform=windows&channel=stable&currentVersion=<version>&clientId=<device_id>`.

Admin endpoints:

- list + preview manifest: `GET /api/v1/admin/updates/releases`;
- create/upsert release: `POST /api/v1/admin/updates/releases`;
- update release by id: `POST /api/v1/admin/updates/releases/{release_id}`;
- permissions: `updates.read`, `updates.manage`.

Manifest теперь возвращает:

- `updateAvailable` - можно ли этому устройству сейчас предложить обновление;
- `baseUpdateAvailable` - существует ли более новая версия без учёта rollout;
- `rolloutEligible` - попало ли устройство в rollout bucket;
- `rolloutBucket` - стабильный bucket `0..99` по `clientId`, если он нужен;
- `rolloutReason` - `current_or_newer`, `required`, `full_rollout`, `rollout_zero`, `client_id_missing`, `bucket_match`, `bucket_holdback`;
- `rolloutPercent` - процент выката из release record.

Важное правило: пользовательский клиент должен доверять `updateAvailable`, а не просто сравнивать строки версий. Это позволяет публиковать release на `5%`, `25%`, `100%`, делать holdback и не показывать обновление всем пользователям одновременно.

## Support Actions

С версии backend source `0.9.5` добавлен внутренний слой безопасных быстрых действий техподдержки по пользователю.

Endpoints:

- workflow: `GET /api/v1/admin/support/actions/workflow`;
- list/history: `GET /api/v1/admin/support/actions`;
- run action: `POST /api/v1/admin/users/{user_id}/support-actions`;
- permissions: `support_actions.read`, `support_actions.manage`.

Подготовленные действия:

- `reset_user_sessions` - сбросить активные user sessions, чтобы пользователь вошёл заново;
- `request_config_refresh` - поставить саппортную пометку, что устройству или всем устройствам пользователя нужен refresh/reissue config;
- `clear_config_refresh` - снять саппортную пометку refresh/reissue config;
- `disable_device` - отключить конкретное устройство;
- `enable_device` - вернуть конкретное устройство в активное состояние;
- `add_support_note` - записать внутреннюю заметку без изменения аккаунта.

Все действия пишутся в `admin_support_actions` и в `admin_audit_log`. Они не возвращают пароли, токены, WireGuard private keys или содержимое конфигов. Текущая версия намеренно не меняет `BlueVPNDev1`, `WireGuardTunnel$BlueVPNDev1` и `C:\ProgramData\BlueVPN`; это support/admin слой над существующим рабочим VPN-контуром.

## External Owner Actions

С версии backend source `0.9.6` внешний checklist готовности стал не просто статическим списком, а управляемым рабочим журналом для владельца/админа.

Endpoints:

- checklist: `GET /api/v1/admin/external-actions`;
- update owner status: `POST /api/v1/admin/external-actions/{action_code}`;
- permissions: `readiness.read`, `readiness.manage`.

Поддержанные owner statuses:

- `todo` - нужно сделать;
- `in_progress` - в работе;
- `waiting_owner` - ждёт владельца;
- `waiting_provider` - ждёт провайдера;
- `ready_to_apply` - данные готовы, можно подключать;
- `done` - сделано;
- `blocked` - заблокировано;
- `not_needed` - не нужно.

Важно: owner status не подменяет реальные readiness-проверки. Например, если пункт помечен как `done`, но SMTP/DNS/YooKassa env ещё не зелёные, `productionReady` останется `false`. Это сделано специально, чтобы мы могли вести рабочий список внешних действий, но не включить production-режим по ошибке.

Все изменения owner status пишутся в `admin_owner_action_statuses` и `admin_audit_log`. В заметках нельзя хранить пароли, SMTP-пароли, SMS API keys, YooKassa secret key, SSH-пароли, `admin_token` или любые приватные ключи.

## Launch Owner Packet

С версии backend source/live `0.9.64` есть единый read-only пакет для owner-facing запуска.

Endpoint:

- packet: `GET /api/v1/admin/launch/owner-packet`;
- permission: `readiness.read`.

Payload содержит owner-facing commands, pending owner actions, non-secret DNS records, safe defaults, API/VPN split preflight metadata and after-apply checks.

С backend `0.9.66` owner packet also includes mutation-free `payment_launch_safety`, backed by `scripts\windows\check_payment_launch_safety.ps1`.

С backend `0.9.67` owner packet also includes mutation-free `monitoring_probe_plan`, backed by `scripts\windows\get_monitoring_probe_plan.ps1`.

Secret policy:

- endpoint может называть env keys/provider fields;
- secret values не возвращаются;
- `safeNoSecretExposure=true`;
- `policy.noSecretValues=true`.

CLI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\get_owner_launch_packet.ps1
```

По умолчанию CLI читает admin token только на сервере через SSH и печатает sanitized summary/JSON.

## Что уже работает

- `POST /api/v1/admin/auth/login`
- `GET /api/v1/admin/auth/me`
- `POST /api/v1/admin/auth/logout`
- `GET /api/v1/admin/roles`
- `GET /api/v1/admin/staff`
- `POST /api/v1/admin/staff`
- `POST /api/v1/admin/staff/{staff_id}`
- `GET /api/v1/admin/feature-flags`
- `POST /api/v1/admin/feature-flags`
- `POST /api/v1/admin/feature-flags/{flag_id}`
- `GET /api/v1/admin/runbooks`
- `POST /api/v1/admin/runbooks`
- `POST /api/v1/admin/runbooks/{runbook_id}`
- `GET /api/v1/admin/support/actions/workflow`
- `GET /api/v1/admin/support/actions`
- `POST /api/v1/admin/users/{user_id}/support-actions`
- `GET /api/v1/admin/external-actions`
- `POST /api/v1/admin/external-actions/{action_code}`
- `GET /api/v1/admin/launch/owner-packet`
- `GET /api/v1/admin/overview`
- `GET /api/v1/admin/users`
- `GET /api/v1/admin/users/{user_id}/devices`
- `POST /api/v1/admin/devices/{device_uid}/disable`
- `POST /api/v1/admin/devices/{device_uid}/enable`
- `POST /api/v1/admin/users/{user_id}/subscription`
- `GET /api/v1/admin/users/{user_id}/subscription-history`
- `POST /api/v1/admin/users/{user_id}/subscription/grant`
- `POST /api/v1/admin/users/{user_id}/subscription/revoke`
- `GET /api/v1/admin/subscriptions/expiry-readiness`
- `POST /api/v1/admin/subscriptions/expiry/run`
- `GET /api/v1/me/devices`

## Что хранится на сервере

- пользователи
- password hash
- bearer tokens
- устройства
- назначенные IP
- WireGuard ключи устройства
- preshared key
- подписка пользователя
- флаги блокировки устройства
- время последней активности устройства
- время последней выдачи конфига

## PowerShell helper

Для Windows добавлен helper:

- [bluevpn_admin_api.ps1](C:/Users/gekto/projects/bluevpn/scripts/windows/bluevpn_admin_api.ps1)

Примеры:

```powershell
$env:BLUEVPN_ADMIN_TOKEN="PUT_TOKEN_HERE"

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_admin_api.ps1 -Action Overview

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_admin_api.ps1 -Action ListUsers

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_admin_api.ps1 -Action ListUserDevices -UserId 7

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_admin_api.ps1 -Action DisableDevice -DeviceUid win_xxx -Reason "manual_block"

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_admin_api.ps1 -Action EnableDevice -DeviceUid win_xxx

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_admin_api.ps1 -Action SubscriptionHistory -UserId 7

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_admin_api.ps1 -Action GrantSubscription -UserId 7 -DurationDays 30 -Reason "support grant approved by owner"

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_admin_api.ps1 -Action RevokeSubscription -UserId 7 -Reason "owner requested access revocation"
```

Для обычной выдачи и отзыва используйте только `GrantSubscription` и
`RevokeSubscription`. Они не сокращают действующий оплаченный период, не включают
автопродление, удаляют VPN peer при отзыве и записывают полную историю. Причина
минимум из 8 символов обязательна. `SetSubscription` и `ApplyTariff` сохранены
для совместимости и аварийных операций; `ApplyTariff` также требует причину и
всегда применяет `autoRenew=false`.

## Added in v0.4.x

- `POST /api/v1/admin/users/{user_id}/tariff/apply`

This endpoint applies the same server-side tariff model that the client uses:

- traffic pack / GB
- unlimited apps
- device count
- dedicated IP

The backend calculates the final monthly price, saves the normalized selection,
updates the user's active subscription, and returns the resulting quote and
subscription state.

## Как это влияет на продукт

Теперь backend уже не просто выдаёт конфиг, а начинает становиться системой управления:

- можно видеть пользователей;
- можно видеть устройства;
- можно отключать отдельное устройство;
- можно менять лимит устройств и план;
- отключённое устройство больше не получает рабочий конфиг.
