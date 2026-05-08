# Текущее состояние проекта

## База

- Репозиторий: `C:\Users\gekto\projects\bluevpn`
- Видимый бренд: `Green VPN`
- Историческое внутреннее имя в коде и runtime: `BlueVPN`
- Backend/live server: `37.220.85.211`
- Public API/site: `https://api.greenvpn.pro`
- Основной backend source: `C:\Users\gekto\projects\bluevpn\backend_live\app\main.py`
- Admin/support app: `C:\Users\gekto\projects\bluevpn\admin_support_app`
- Windows client: `C:\Users\gekto\projects\bluevpn\lib`
- Windows service: `C:\Users\gekto\projects\bluevpn\windows\green_vpn_service`

## Git/worktree

Worktree грязный. Это ожидаемо.

Перед любой работой обязательно:

```powershell
cd C:\Users\gekto\projects\bluevpn
git status --short
```

Не откатывать чужие изменения.

## Backend

Последняя подтвержденная live версия: `0.9.67`.

Что уже есть:

- auth, user account, billing groundwork;
- YooKassa payment creation/webhook logic;
- email/SMS readiness;
- admin/support app API;
- staff sessions/RBAC/2FA;
- support reports/comments/audit;
- server catalog and health scoring;
- monitoring probes and incident sync;
- launch readiness aggregator;
- protected public site readiness at `GET /api/v1/admin/site/readiness`;
- protected payment smoke readiness at `GET /api/v1/admin/billing/payment-smoke/readiness`;
- protected user auth flow readiness at `GET /api/v1/admin/auth/user-flow/readiness`;
- protected launch closure plan at `GET /api/v1/admin/launch/closure-plan`;
- protected owner launch packet at `GET /api/v1/admin/launch/owner-packet`;
- payment-dependent renewals/expiry guards require clean payment smoke before safe-enable signals;
- payment launch safety CLI at `scripts\windows\check_payment_launch_safety.ps1`;
- monitoring probe plan CLI at `scripts\windows\get_monitoring_probe_plan.ps1`;
- server-enforced owner-action note secret guard for `POST /api/v1/admin/external-actions/{action_code}`;
- API/VPN split-plan preflight tooling via `scripts\windows\check_api_vpn_split_preflight.ps1`;
- public site/legal/download pages;
- promo campaign readiness with safe `START20` draft flow.
  - inactive `START20` draft уже создан; activation ждать до payment/update readiness.

2026-05-08 owner-input verification:

- live owner-action `email` was aligned to `done`; external-actions now reports `waitingCodes=[]`;
- pending external actions are `payments`, `updates`, `admin_alerts`;
- YooKassa production keys, Telegram alert values and final update/rollback artifact env are not present in local Windows env or server `/etc/bluevpn/backend.env`;
- closure plan remains `canContinueAutonomously=false`: remaining work is owner/final/payment-dependent, not an unblocked code task;
- current separate site IP candidate `95.163.244.138` refuses SSH on port `22`, so Codex cannot autonomously turn it into the API reverse proxy or monitoring host;
- no backend deploy/restart or installer build was done for this verification.

2026-05-08 YooKassa update:

- YooKassa production env was applied server-side; do not repeat or print the secret value.
- Backend now reports `paymentsProductionReady=true` and billing readiness `provider=yookassa`, `productionReady=true`.
- External action `payments` is now `done/ready`; pending external actions are `updates` and `admin_alerts`.
- One minimal YooKassa smoke order was paid and verified by authoritative YooKassa API fetch.
- Payment smoke is green: `safeToRunSmoke=true`, `smokeCompleted=true`, `successfulSmokeCandidates=1`.
- Old synthetic `codex_payments_...@greenvpn.local` pending order was canceled; renewal readiness is now clean: `safeToEnableAutoRenewalCharges=true`.
- Strict expiry enforcement still stays disabled: 2 expiring trial/free subscriptions lack verified retention contact.
- Closure plan now reports `ready=11`, `pending=7`, `codeOwned=1`, `ownerBlocked=4`; API/VPN split remains the main red blocker.

2026-05-08 API/VPN split and expiry review update:

- Supersedes the older same-IP blocker note below: API/site and VPN endpoint are now split.
- `api.greenvpn.pro -> 72.56.32.197` through Timeweb reverse proxy `Friendly Cetus`.
- `nl1.vpn.greenvpn.pro -> 37.220.85.211` for the current WireGuard/VPN endpoint.
- New proxy nginx terminates HTTPS and proxies to origin `https://37.220.85.211`; Let's Encrypt cert expires `2026-08-06`.
- Backend env now uses `BLUEVPN_ENDPOINT_HOST=nl1.vpn.greenvpn.pro`; internal names stay `BlueVPNDev1`, `WireGuardTunnel$BlueVPNDev1`, `C:\ProgramData\BlueVPN`.
- SSH password auth on the new proxy is disabled; use key login only.
- Split preflight is green: `green=7`, `yellow=0`, `red=0`; network readiness is `productionReady=true`.
- Backend/source/live server advanced to `0.9.69`.
- Added audited `subscription_expiry_reviews` and `POST /api/v1/admin/subscriptions/{subscription_id}/expiry-review`.
- Two current trial/free expiry candidates were reviewed without printing contacts; expiry readiness is now clean, but strict enforcement remains off by env.
- Payment launch safety is now green: `safeForAutomaticBilling=True`.
- Closure plan now reports `ready=13`, `pending=5`, `ownerBlocked=3`, `codeOwned=0`, `operationalReview=1`, `finalHandoffOnly=1`, `critical=1`, `warnings=4`, `canContinueAutonomously=false`.
- Remaining blockers: external monitoring probe, Telegram admin alerts, final installer/update artifact, and manual `START20` activation after release readiness.
- No public Windows installer was rebuilt.

## Public site

Текущий публичный сайт живет на:

- `https://api.greenvpn.pro/`
- `https://api.greenvpn.pro/download/windows`
- `https://api.greenvpn.pro/download/android`
- `https://api.greenvpn.pro/download/ios`
- `https://api.greenvpn.pro/legal/requisites`
- `https://api.greenvpn.pro/legal/offer`
- `https://api.greenvpn.pro/legal/privacy`
- `https://api.greenvpn.pro/legal/acceptable-use`
- `https://api.greenvpn.pro/legal/refunds`
- `https://api.greenvpn.pro/payment/return`

Сайт уже очищался от внутренней MVP/release-gate терминологии. Он должен позиционировать продукт как защищенное и стабильное подключение, а не как обход блокировок.

## Главный production-блокер

`api.greenvpn.pro` и текущий VPN endpoint сейчас используют один IP `37.220.85.211`.

Это допустимо для разработки, но плохо для публичного запуска: при full-tunnel VPN Windows может блокировать доступ к собственному API/site.

Нужно разделить:

- API/site на отдельный IP или reverse proxy;
- VPN endpoint на отдельный host, например `nl1.vpn.greenvpn.pro -> 37.220.85.211`.

Preflight tooling уже есть: `GET /api/v1/admin/network/split-plan` отдаёт mutation-free команду для `scripts\windows\check_api_vpn_split_preflight.ps1`. Команду запускать после появления отдельного API/site IP или reverse proxy.

## ЮKassa

По последнему сообщению владельца, кабинет ЮKassa теперь активен. Backend еще нужно подключить к production keys через server-only env.

Не записывать `YOOKASSA_SECRET_KEY` в чат или docs.

Детали в:

`C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07\06_YOOKASSA_AND_PAYMENTS_RU.md`
