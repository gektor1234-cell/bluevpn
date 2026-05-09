# Следующие задачи разработки

## Сейчас

Если владелец рядом и готов дать внешние данные, идти так:

1. Подключить ЮKassa production keys через safe env, когда владелец готов.
2. Проверить billing readiness.
3. Проверить test payment/order flow, если ЮKassa кабинет позволяет.
4. Зафиксировать результат в `CURRENT_HANDOFF.md` и `RELEASE_STATE.md`.

Если владельца нет, ЮKassa/новый IP/Telegram secrets считаются owner-blocked. Тогда работать дальше по безопасным admin tooling/network split/docs задачам без вывода секретов и без сборки нового installer.

## Уже закрыто после переноса

### Public site readiness gate

Готово и задеплоено в backend `0.9.57`:

- `GET /api/v1/admin/site/readiness`;
- проверяет legal pages, pricing/download buttons, safe public wording, YooKassa required URLs, banned public phrases;
- live self-check green: `productionReady=true`, `bannedPhraseMatches=0`.

### Payment smoke readiness gate

Готово и задеплоено в backend `0.9.58`:

- `GET /api/v1/admin/billing/payment-smoke/readiness`;
- показывает, можно ли запускать минимальный YooKassa smoke;
- сейчас `safeToRunSmoke=false` до применения `YOOKASSA_SHOP_ID` и `YOOKASSA_SECRET_KEY` через safe env;
- не создает заказы, не вызывает YooKassa и не раскрывает provider payment method ids.

### User auth flow readiness gate

Готово и задеплоено в backend `0.9.59`:

- `GET /api/v1/admin/auth/user-flow/readiness`;
- проверяет code-first auth contract: `phone_code` primary, `email_code` fallback, legacy email/password only;
- проверяет SMS/email delivery, code policy, auth-code pepper и `DEV_AUTH_CODES=0`;
- live self-check green: `productionReady=true`, `publicAuthReady=true`, `codesExposed=false`, `tokensExposed=false`.

### Launch closure plan gate

Готово и задеплоено в backend `0.9.60`, уточнено в `0.9.61`:

- `GET /api/v1/admin/launch/closure-plan`;
- разделяет оставшиеся launch gates на owner-blocked, final-handoff-only, autonomous code work и operational review;
- live self-check after cleanup: `ownerBlocked=5`, `codeOwned=2`, `operationalReview=3`, `finalHandoffOnly=1`, `nextAutonomousActions=0`, `secretValuesExposed=false`;
- `support_sla` очищен от smoke reports;
- inactive `START20` draft создан, activation ждать до `payments` + `updates`.

### Owner-action note secret guard

Готово и задеплоено в backend `0.9.62`:

- `POST /api/v1/admin/external-actions/{action_code}` теперь отклоняет заметки с private keys, bearer/admin tokens, password/secret/provider-key/env assignments до записи в DB/audit;
- ошибка возвращает только pattern codes и не эхоить значения;
- `GET /api/v1/admin/external-actions` отдаёт `ownerActionPolicy.serverEnforced=true`;
- admin/support app показывает состояние note guard;
- live negative test с fake `YOOKASSA_SECRET_KEY=...` вернул HTTP `400`, fake value не вернулся в ответе.

### API/VPN split preflight tooling

Готово и задеплоено в backend `0.9.63`:

- добавлен `scripts\windows\check_api_vpn_split_preflight.ps1`;
- скрипт secret-free и mutation-free, поддерживает `-Json`;
- проверяет HTTPS API URL, DNS API/VPN host, expected IP, пересечение API/VPN IP и `/healthz`;
- `GET /api/v1/admin/network/split-plan` отдаёт preflight metadata и готовую команду;
- admin/support app показывает preflight command в network readiness;
- live self-check подтверждает `hasPreflight=true`, `preflightMutationFree=true`, `preflightUsesScript=true`, `preflightJsonReady=true`.

### Admin/support app owner-note UX guard

Готово локально в separate `admin_support_app`; backend version не менялась и остаётся `0.9.63`:

- `apiGet`/`apiPost` больше не показывают structured API errors как `[object Object]`;
- fallback форматирование API errors редактирует sensitive keys вроде `input`, `password`, `secret`, `token`, private keys;
- owner-action note textarea проверяет obvious secret material до отправки на backend;
- QuickJS syntax и targeted runtime checks прошли.

### Owner launch packet endpoint

Готово и задеплоено в backend `0.9.64`:

- `GET /api/v1/admin/launch/owner-packet`;
- `scripts\windows\get_owner_launch_packet.ps1`;
- собирает owner-facing commands, pending owner actions, DNS records, safe defaults and after-apply checks в одном payload;
- secret values не возвращаются: endpoint может называть env keys/provider fields, но не их значения;
- admin/support app показывает owner packet card в разделе `Готовность`;
- readiness checker проверяет endpoint, `noSecretValues=true`, `safeNoSecretExposure=true`, наличие split preflight и отсутствие secret-value markers;
- CLI по умолчанию читает admin token только на сервере через SSH и печатает sanitized summary/JSON;
- live self-check: backend `0.9.64`, owner-packet HTTP `200`, `commands=3`, `ownerActions=3`, `ownerBlockers=5`, `secretValuesExposed=false`;
- QuickJS render smoke подтверждает, что admin card показывает launch blockers без secret values.

### Payment-dependent renewal/expiry guard

Готово и задеплоено в backend `0.9.65`:

- `/api/v1/admin/billing/renewals/readiness` требует clean payment smoke перед `safeToEnableAutoRenewalCharges=true`;
- `/api/v1/admin/subscriptions/expiry-readiness` требует clean payment smoke перед `safeToEnableExpiryEnforcement=true`;
- оба endpoint отдают `paymentSmokeCompleted`, `paymentSmokeReady`, `policy.requiresPaymentSmoke=true`;
- admin/support app показывает payment-smoke dependency в renewal/expiry cards;
- live self-check: renewal `paymentSmokeReady=false`, `safeToEnableAutoRenewalCharges=false`, `requiresPaymentSmoke=true`; expiry `paymentSmokeReady=false`, `safeToEnableExpiryEnforcement=false`, `requiresPaymentSmoke=true`.

### Payment launch safety CLI

Готово и задеплоено в backend `0.9.66`:

- добавлен `scripts\windows\check_payment_launch_safety.ps1`;
- CLI читает admin token только на сервере через SSH по умолчанию;
- проверяет billing readiness, payment smoke, renewals and subscription expiry;
- owner packet теперь содержит mutation-free команду `payment_launch_safety`, live `commands=4`;
- live run: `safeForAutomaticBilling=false` до production YooKassa/payment smoke; forbidden markers не выводятся.

### Monitoring probe plan CLI

Готово и задеплоено в backend `0.9.67`:

- добавлен `scripts\windows\get_monitoring_probe_plan.ps1`;
- CLI читает admin token только на сервере через SSH по умолчанию;
- проверяет monitoring readiness и server-health external probe readiness;
- owner packet теперь содержит mutation-free команду `monitoring_probe_plan`, live `commands=5`;
- live run: `installCommandUsesTokenStdin=true`, `installCommandUsesServerHealth=true`, `hasOperatorPlan=true`, `safeToProceed=false`.

## Ближайшие оставшиеся задачи

### 1. Payment production smoke

После применения ЮKassa keys:

- проверить `GET /api/v1/admin/billing/payment-smoke/readiness`;
- создать тестовый/минимальный order;
- проверить, что payment URL создается;
- проверить return page;
- проверить webhook или ручную проверку payment state;
- убедиться, что тариф активируется только после подтверждения.

### 2. API/VPN endpoint split

Нужен отдельный IP/reverse proxy для API/site. Пока это главный red blocker.

Preflight tooling уже готов. После появления нового API/site IP нужно запустить команду из `GET /api/v1/admin/network/split-plan` или:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_api_vpn_split_preflight.ps1 -ApiBase https://api.greenvpn.pro -VpnEndpointHost nl1.vpn.greenvpn.pro -ExpectedVpnIp 37.220.85.211 -ExpectedApiIp <new-api-site-ip> -Json
```

### 3. Admin/support app polish

- `support_sla` queue уже clean;
- payment smoke readiness уже показан в платежах;
- держать site readiness видимым и зелёным;
- owner actions уже понятнее: closure plan + owner packet + external actions + server-enforced note guard + client-side note precheck;
- дальше полировать только то, что снижает риск перед owner/payment/network split;
- не раскрывать secrets.

### 4. User auth/account polish

- readiness gate уже зеленый;
- дальше только UX polish, если появятся реальные проблемы в клиенте или событиях входа.

### 5. Final installer/update readiness

Только ближе к финалу:

- final Windows installer;
- update URL;
- SHA256;
- rollback URL/SHA256;
- fresh install test.

### 6. Owner input verification from 2026-05-08

- `email` owner-action is now `done` and live-ready; external-actions has no `waitingCodes`.
- Still pending: `payments`, `updates`, `admin_alerts`.
- Missing values were checked without printing secrets:
  - YooKassa `YOOKASSA_SHOP_ID` / `YOOKASSA_SECRET_KEY` are not in local/server env;
  - Telegram alert bot token/chat id are not in local/server env;
  - final update/rollback artifact env values are not in local/server env.
- `95.163.244.138` is not currently usable by Codex for autonomous reverse-proxy/probe setup: SSH port `22` is refused.
- Do not activate `START20`, auto-renewals or strict expiry enforcement until production payments, payment smoke and update readiness are green.
- Do not build a new installer before final handoff or explicit test request.

### 7. YooKassa production env from 2026-05-08

- YooKassa production env is applied; backend billing readiness is green.
- `payments` external action is now `done/ready`; still pending externally: `updates`, `admin_alerts`.
- One minimal YooKassa smoke order was paid and verified through YooKassa API; backend activated it through provider-backed sync.
- Payment smoke is green.
- Old synthetic pending renewal-conflict order was canceled; current renewal readiness is clean and `safeToEnableAutoRenewalCharges=true`.
- Keep strict expiry enforcement disabled until the 2 expiring trial/free subscriptions without verified retention contact are reviewed.
- Keep `START20` inactive until final launch/update readiness is green.

### 8. API/VPN split and expiry review from 2026-05-08

- API/VPN split is done and green:
  - `api.greenvpn.pro -> 72.56.32.197`;
  - `nl1.vpn.greenvpn.pro -> 37.220.85.211`;
  - preflight `green=7`, `yellow=0`, `red=0`.
- New Timeweb proxy `Friendly Cetus` / `72.56.32.197` runs nginx + Let's Encrypt for `api.greenvpn.pro` and proxies to origin `https://37.220.85.211`.
- Backend source/live is now `0.9.69`.
- Added audited expiry-review flow:
  - DB table `subscription_expiry_reviews`;
  - `POST /api/v1/admin/subscriptions/{subscription_id}/expiry-review`;
  - admin/support app review action;
  - secret-pattern rejection for review notes.
- The 2 current trial/free expiry candidates were reviewed through the new endpoint; expiry readiness is clean.
- `check_payment_launch_safety.ps1` now reports `safeForAutomaticBilling=True`.
- Strict enforcement remains disabled by env; do not turn it on before final launch decision.
- Closure plan now has no code-owned blocker:
  - `ready=13`;
  - `pending=5`;
  - `ownerBlocked=3`;
  - `codeOwned=0`;
  - `operationalReview=1`;
  - `finalHandoffOnly=1`;
  - `critical=1`;
  - `warnings=4`.
- `canContinueAutonomously=false`; inactive `START20` is only a hold until final release/update readiness.
- Remaining actions:
  - owner: install a separate external monitoring probe / token placement;
  - owner: Telegram admin alert bot token and chat id through server-only env;
  - final-only: build/publish final Windows installer/update artifact with SHA256 and rollback;
  - operational: keep inactive `START20` draft until payment/release/update readiness is green, then activate manually.
- No public Windows installer was rebuilt.

### 9. Public site/admin hosting from 2026-05-09

- Public root/www DNS was moved to the Timeweb proxy:
  - `greenvpn.pro -> 72.56.32.197`;
  - `www.greenvpn.pro -> 72.56.32.197`.
- The proxy now hosts the public site and current installer download:
  - `https://greenvpn.pro/`;
  - `https://www.greenvpn.pro/`;
  - `https://greenvpn.pro/downloads/GreenVPN_Setup.exe`.
- The static admin/support app is temporarily available at:
  - `https://greenvpn.pro/admin/`;
  - `https://www.greenvpn.pro/admin/`.
- Admin UI is protected by nginx Basic Auth:
  - unauthenticated `https://greenvpn.pro/admin/` returns HTTP `401`;
  - authenticated smoke returns HTTP `200`;
  - one-time credential files are root-only on `72.56.32.197`: `/root/greenvpn-admin-basic-auth-onetime.txt` and `/root/greenvpn-admin-owner-login-onetime.txt`.
- Backend staff login is usable for the owner account:
  - owner staff role is `owner`;
  - server-generated password is not in repo/docs/chat;
  - live login smoke returned `authType=staff_session`.
- Admin email 2FA is implemented and server-only pepper is configured, but mandatory 2FA is temporarily off:
  - `37.220.85.211` could not reach Yandex SMTP directly;
  - `72.56.32.197` now runs restricted `greenvpn-yandex-smtp-relay.service` for Yandex SMTP, source-limited to `37.220.85.211`;
  - origin uses `smtp.yandex.ru:2587` through the relay;
  - Yandex currently rejects the stored app password with `535 authentication failed`, so owner must rotate/apply the Yandex 360 SMTP app password through safe server env before re-enabling mandatory admin 2FA.
- A separate admin virtual host is prepared for `admin.greenvpn.pro`; owner still needs to add DNS:
  - `A admin -> 72.56.32.197`.
- `api.greenvpn.pro` remains separate and continues proxying to origin backend `37.220.85.211`.
- Capacity on `72.56.32.197` is enough for MVP public site/admin/download/API proxy: load `0.00`, about `344 MiB` RAM used, about `1.6 GiB` available, disk `2.1 GiB / 38 GiB`.
- Keep VPN endpoint traffic on `37.220.85.211`; do not move VPN to this site/API proxy server.

## Если пользователь уйдет надолго

Брать задачи сверху вниз. Если ЮKassa, новый IP или secrets требуют владельца, записать blocker и идти дальше по admin tooling/network split docs.
