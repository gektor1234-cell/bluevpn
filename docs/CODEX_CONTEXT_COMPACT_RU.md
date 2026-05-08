# Green VPN Compact Context

Последнее обновление: 2026-05-07

Этот файл - короткое ядро контекста для Codex. Самый свежий переносной пакет теперь лежит здесь:

`C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07`

В новой сессии сначала читать этот пакет, особенно `00_COVER_LETTER_RU.md` и `02_WORKFLOW_AND_COMMUNICATION_RU.md`, затем этот compact context. Большие документы открывать точечно, только если текущая задача реально требует деталей.

## Контекст-Режим

1. Не перечитывать весь старый чат.
2. Не просить пользователя заново вставлять огромный мастер-план.
3. Не открывать сразу `CURRENT_HANDOFF.md`, `RELEASE_STATE.md` и `GREENVPN_MASTER_PLAN.md` целиком.
4. Сначала прочитать этот файл, потом выполнить `git status --short`.
5. Скриншоты из чата считать историческим шумом, если пользователь прямо не просит разобрать конкретный новый скриншот.
6. После каждого стабильного этапа обновлять этот файл кратко: версия, что сделано, что проверено, следующий шаг.

Большие документы:

- `docs\GREENVPN_MASTER_PLAN.md` - полный продуктовый план.
- `docs\DEVELOPMENT_PROTOCOL.md` - правила движения по плану.
- `docs\CURRENT_HANDOFF.md` - подробный handoff.
- `docs\RELEASE_STATE.md` - история релизов/кандидатов/проверок.
- `docs\EXTERNAL_SERVICES_CHECKLIST_RU.md` - действия владельца: домен, почта, SMS, YooKassa, Telegram, VPS.

## Жесткие Инварианты

- Видимый бренд: Green VPN.
- Windows-first Flutter VPN-client, цель - продаваемый Windows MVP.
- Внутренние имена пока не переименовывать:
  - `BlueVPNDev1`;
  - `WireGuardTunnel$BlueVPNDev1`;
  - `C:\ProgramData\BlueVPN`.
- Не трогать Friendly Linnet/personal server.
- Не трогать Amnezia, WARP и чужие WireGuard-туннели.
- Рабочий dev/prod server: `37.220.85.211`.
- Public domain/API: `greenvpn.pro`, `https://api.greenvpn.pro`.
- Не писать в repo пароли, admin token, YooKassa keys, SMTP passwords, SMS keys, SSH secrets, WireGuard private keys.
- Не делать `git reset --hard`, `git checkout --`, destructive cleanup без прямого разрешения пользователя.
- Worktree грязный и содержит много незакоммиченных изменений. Не откатывать чужие правки.

## Rollback И Installer

Текущий стабильный rollback:

- `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`
- SHA256: `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`

Текущий публичный installer:

- `C:\BlueVPN_Builds\GreenVPN_Setup.exe`
- `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`

Не пересобирать installer, если меняется только backend/admin-support app.

## Что Уже Есть

- Windows Flutter app запускается как Green VPN.
- VPN connect/disconnect работает через native `GreenVPNService`.
- UI не должен каждый раз просить UAC.
- Scheduled tasks остаются fallback-слоем.
- Tray/background/autostart уже есть.
- Social Only работал и его нельзя ломать.
- Регистрация/вход есть; backend auth-flow readiness live зелёный, дальше только точечный UX polish при необходимости.
- User UI очищен от `Backend Admin` и грубой dev-диагностики.
- Support report groundwork есть.
- Simple updater/staged rollout groundwork есть.
- Backend на сервере живой.
- Production domain/HTTPS для `api.greenvpn.pro` уже подняты.
- Payment/YooKassa readiness есть, но production keys/webhook требуют внешних действий.
- Email/SMS readiness есть, но реальные SMTP/SMS credentials должны быть только server-side.
- Отдельное `admin_support_app` существует и развивается отдельно от пользовательского клиента.
- Incidents, analytics, monitoring targets, managed catalog, health observations, feature flags, runbooks, safe support actions уже частично реализованы.

## Последний Закрытый Этап

Backend/admin live version: `0.9.67`.

Последние закрытые backend/admin этапы:

- launch readiness aggregator;
- API/VPN endpoint split readiness and split plan;
- new VPS onboarding plan;
- external server-health probe operator plan;
- safe VPS draft workflow;
- public site/download/legal cleanup;
- promo campaign readiness with safe inactive `START20` draft flow;
- protected public site readiness gate: `GET /api/v1/admin/site/readiness`;
- protected payment smoke readiness gate: `GET /api/v1/admin/billing/payment-smoke/readiness`;
- protected user auth flow readiness gate: `GET /api/v1/admin/auth/user-flow/readiness`;
- protected launch closure plan: `GET /api/v1/admin/launch/closure-plan`;
- protected owner launch packet: `GET /api/v1/admin/launch/owner-packet`;
- owner launch packet CLI: `scripts\windows\get_owner_launch_packet.ps1`;
- server-enforced owner-action note secret guard for `POST /api/v1/admin/external-actions/{action_code}`;
- API/VPN split preflight script and split-plan metadata: `scripts\windows\check_api_vpn_split_preflight.ps1`.
- separate admin/support app owner-note client precheck, structured API error formatting and owner packet card.

ЮKassa в кабинете владельца, по последнему сообщению, теперь активна. Backend еще нужно подключить к production payments через server-only env:

- `YOOKASSA_SHOP_ID`;
- `YOOKASSA_SECRET_KEY`.

`YOOKASSA_SECRET_KEY` не писать в чат/docs/repo.

Текущий главный red blocker перед public release: `api.greenvpn.pro` и VPN endpoint используют один IP `37.220.85.211`.

## Текущий Прогресс

- Общий мастер-план: примерно `39%`.
- Windows MVP: примерно `85%`.
- Monitoring/resilience layer: примерно `52%`.

## Ближайший Следующий Шаг

1. Подключить ЮKassa production env безопасным скриптом, когда владелец готов:
   - `scripts\windows\configure_backend_env_wsl.ps1`;
   - `YOOKASSA_SHOP_ID`;
   - `YOOKASSA_SECRET_KEY` только в терминал, не в чат.
2. Проверить billing/readiness and payment smoke:
   - live `/api/v1/admin/billing/payment-smoke/readiness` уже есть;
   - сейчас `safeToRunSmoke=false` до ввода ЮKassa production keys.
3. Продолжить admin/support app polish, monitoring и network split.
   - auth readiness live уже `productionReady=true`, `publicAuthReady=true`.
   - `support_sla` очищен от исторических smoke reports.
   - inactive `START20` draft создан; activation ждать до payments/update readiness.
   - closure plan live теперь `canContinueAutonomously=false` по launch gates; оставшееся завязано на owner/final/payment-dependent items.
   - owner-action notes теперь server-guarded: fake `YOOKASSA_SECRET_KEY=...` блокируется HTTP `400`, значения не эхоятся.
- owner launch packet live отдаёт owner-facing commands/inputs/checks без secret values.
- `get_owner_launch_packet.ps1` печатает sanitized summary/JSON, admin token остаётся на сервере.
- billing renewals/expiry readiness теперь требуют clean payment smoke перед `safeToEnableAutoRenewalCharges=true` или `safeToEnableExpiryEnforcement=true`.
- payment launch safety CLI: `scripts\windows\check_payment_launch_safety.ps1`; owner packet includes `payment_launch_safety`.
- monitoring probe plan CLI: `scripts\windows\get_monitoring_probe_plan.ps1`; owner packet includes `monitoring_probe_plan`.
- network split-plan live отдаёт mutation-free preflight command; запускать после появления отдельного API/site IP.
   - admin/support app локально ловит obvious secret material в owner notes до POST и форматирует structured API errors без `[object Object]`.
4. Держать public site readiness зелёным; live `/api/v1/admin/site/readiness` уже `productionReady=true`.

## Команды

```powershell
cd C:\Users\gekto\projects\bluevpn
git status --short
python -m py_compile backend_live\app\main.py
```

```powershell
@'
import json, pathlib, quickjs
code = pathlib.Path('admin_support_app/app.js').read_text(encoding='utf-8')
ctx = quickjs.Context()
ctx.eval('new Function(' + json.dumps(code) + ')')
print('quickjs app.js syntax ok')
'@ | python -
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\deploy_backend_wsl.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json
```

Build user installer only when client changed:

```powershell
flutter build windows --release -t .\lib\main.dart
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_release_gate.ps1 -StrictPaymentGate
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build_installer.ps1
```

## Нельзя

- Не хранить secrets в файлах.
- Не выводить admin token в чат/логи.
- Не удалять Amnezia/WARP/чужие VPN.
- Не публиковать managed catalog пользователям без отдельного решения.
- Не вставлять admin/support tooling обратно в пользовательский Green VPN.
- Не читать огромные документы без причины.
