# Green VPN Master Plan

Последнее обновление: 2026-05-05

Этот документ фиксирует общий план разработки Green VPN, чтобы продолжать проект с любого аккаунта Codex без потери контекста.

## Жесткая привязка к разработке

Этот мастер-план является обязательной дорожной картой проекта. Рабочий регламент движения по нему вынесен в:

`C:\Users\gekto\projects\bluevpn\docs\DEVELOPMENT_PROTOCOL.md`

Правило проекта: каждый следующий крупный пункт делается только после того, как предыдущий пункт стал стабильным, проверенным и забетонированным rollback-версией. Если после эксперимента что-то ломается, сначала возвращаемся к последнему rollback anchor из `RELEASE_STATE.md`, потом продолжаем с того же пункта плана.

Текущий стабильный rollback anchor:

- `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`
- SHA256: `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`

Текущий этап: отдельное admin/support приложение и серверный слой поддержки поверх уже подготовленных external-services readiness. Simple updater, server catalog, basic monitoring endpoint, internal-only service availability checks, backend YooKassa safety checks, production payment readiness, payment confirmation flow, billing reconciliation guard, email-confirmation foundation, SMS/phone foundation, auth challenge endpoints, phone-first/email-code/password-legacy auth UI source, filtered auth-event support tooling, coded support reports with send-first/fallback-copy flow and backend decode redaction hardening, admin analytics, support SLA queue, incidents with runbook suggestions, staff assignment and alert outbox, managed monitoring targets, refreshable default monitoring targets, server health observations with admin filters, service observation filters, current endpoint health scoring, monitoring-details sanitization, controlled service-probe readiness endpoint/admin cards with external probe install bundle, update release readiness guard/admin cards with channel-aware readiness, per-release publication gate and rollback publication guard, external owner-actions checklist/workflow with safe setup bundle and owner-action audit guard, Telegram alert readiness, feature flags, runbooks, staff-session inventory/revocation, support-action reason/confirmation guard, safe support actions including 3-day support trial and next-config-fetch WireGuard config refresh/reissue, staged update rollout, safe server-catalog publication gate, server-catalog auto-pause for bad public candidates, admin publication filter and managed endpoint client-config readiness are now in place. Production payments/email/SMS/alerts mostly need external credentials and provider activation: YooKassa production keys, Yandex 360 SMTP mailbox/app password, SMS.ru API key, Telegram bot/chat id, DMARC, monitoring VPS, final HTTPS/public-domain checks, and final installer artifact URL/SHA256 plus rollback artifact URL/SHA256. Admin/support app is now being expanded with readiness, monitoring, incident, support and endpoint-resilience tooling, while the normal user app stays clean. New test installers are now final-only: do not rebuild after every intermediate step; clean the installed Green VPN copy only immediately before issuing the next final installer.

## Главная цель

Сделать продаваемый Windows-first VPN-клиент, который пользователь может скачать одним установщиком, установить, зарегистрироваться/войти, нажать одну кнопку и получить рабочий VPN. После стабильного Windows MVP двигаемся к оплатам, подпискам, Android/iOS, админскому приложению, мониторингу и масштабированию.

## Жесткие инварианты

- Не ломать рабочий WireGuard/WARP-туннель, ключи, peer'ы и config-flow.
- Внутренний dev/prod tunnel пока остается `BlueVPNDev1`.
- Windows service name пока остается `WireGuardTunnel$BlueVPNDev1`.
- Машинные config/state paths пока остаются в `C:\ProgramData\BlueVPN`.
- Видимый бренд может быть `Green VPN`, но внутренние технические имена не переименовывать без отдельной миграции.
- Не трогать Friendly Linnet/personal server. Это личный сервер пользователя, не часть разработки.
- Рабочий dev/prod backend/VPN сервер: `37.220.85.211`.
- Не хранить пароли, admin tokens, YooKassa keys, SSH secrets и приватные WireGuard-ключи в репозитории.
- Не делать большой rewrite ради красоты. Сначала стабилизация MVP, потом точечный рефакторинг.

## Текущее продуктовое состояние

- Windows Flutter app собирается и запускается.
- VPN connect/disconnect уже работает на реальном WireGuard tunnel.
- Social Only режим работает и маршрутизирует выбранные соцсети/приложения через VPN.
- Есть cloud backend на dev-сервере.
- Есть регистрация, вход, session/device model, тарифы, quote/order/payment-заготовка.
- Есть установщик `GreenVPN_Setup.exe`.
- Внешний бренд переводится с BlueVPN на Green VPN, но внутренний tunnel остается `BlueVPNDev1`.

## Ближайший порядок разработки

1. Убрать Backend Admin из обычного пользовательского приложения.
2. Упростить диагностику до кнопки "Скопировать отчет для поддержки".
3. Тарифы: убрать лишние блоки, confusing counters и dev wording.
4. Simple updater: проверка версии, ссылка на установщик, sha256, обязательное/необязательное обновление.
5. Simple server catalog: backend выдает список серверов, портов, протоколов и health.
6. Basic monitoring endpoint: backend health, WireGuard health, payment health.
7. Проверки доступа к YouTube/Discord/Telegram через VPN раньше жалоб пользователей.
8. Production payments: домен, HTTPS, YooKassa production keys, webhooks.
9. Email confirmation.
10. SMS/phone auth.
11. Separate admin/support app: users, devices, reports, billing, readiness, roles.
12. Social login: VK ID, Google, Telegram login позже.
13. First resilience layer: несколько стран/серверов, fallback endpoints.
14. Protocol fallback: WireGuard primary, TCP/443 fallback later.
15. Advanced anti-blocking/resilience.
16. Ads/free mode: без тарифа пользователь смотрит одну непропускаемую рекламу перед connect.
17. Code signing и public build.

## Windows Service Plan

Цель: пользователь не должен каждый раз запускать Green VPN "от имени администратора".

План:

- Installer один раз просит UAC.
- Installer устанавливает `Green VPN Service` под LocalSystem.
- Service управляет WireGuard, config write, ACL, handshake/traffic diagnostics.
- Flutter UI запускается обычным пользователем.
- UI общается с service через localhost/named pipe.
- Service выполняет connect/disconnect/status/provision-config.
- UI показывает прогресс и не дает double click ломать connect/disconnect.

Минимальный API service:

- `GET /status`
- `POST /connect`
- `POST /disconnect`
- `POST /provision-config`
- `GET /diagnostics`
- `POST /support-report`

## Tray/Autostart Plan

- При закрытии окна Green VPN уходит в tray, а не завершает процесс.
- В tray menu:
  - Open Green VPN
  - Connect VPN
  - Disconnect VPN
  - Status
  - Exit
- Exit явно спрашивает подтверждение, если VPN подключен.
- Autostart включается installer'ом.
- Service стартует автоматически, UI/tray стартует при входе пользователя.

## Auth Plan

Нужно полностью привести вход/регистрацию в нормальный consumer-flow:

- Primary flow: `Телефон` -> SMS code -> immediate app login and VPN warmup.
- Secondary flow: `Email-код` -> email code -> immediate app login and VPN warmup.
- Legacy fallback: `Пароль` keeps password login/register until phone/email delivery is production-ready.
- При переключении вкладок поля и ошибки не смешиваются.
- После успешной регистрации/входа сразу вход в приложение или явный экран "подтверди email", если позже включим обязательное подтверждение.
- Ошибки показываются человеческим языком:
  - "Этот email уже зарегистрирован"
  - "Неверный email или пароль"
  - "Нет связи с сервером"
  - "Сессия истекла, войдите снова"
- Технические exceptions не показывать обычному пользователю.
- Добавить password reset.
- Добавить email confirmation.
- SMS/phone auth now has backend/client groundwork; production readiness still depends on SMS provider credentials.
- Потом добавить VK ID/Google/Telegram login.

## User App Cleanup

Перед публичной сборкой убрать или спрятать:

- Backend Admin.
- Dev login/dev bypass.
- Dev-only diagnostics.
- Raw backend errors.
- Raw config paths, endpoint keys, tokens.

Обычному пользователю можно оставить только:

- VPN tab.
- Tariff tab.
- Tasks/bonus tab if needed.
- Settings.
- Support report button.
- Logout.

## Support Report Plan

Обычный пользователь не должен видеть техническую диагностику.

Нужна кнопка:

- "Отправить отчёт"
- fallback "Скопировать код отчёта", только если отправка на backend не сработала

Отчет должен быть закодирован/зашифрован так, чтобы:

- пользователь не видел endpoints, keys, tokens, внутренние paths;
- поддержка могла расшифровать через admin/support tool;
- отчет содержал app version, OS, service status, handshake state, traffic counters, last errors, route hints.

## Tariffs Plan

Тарифная логика:

- Перед публичным релизом сверить финальные цены и публичное позиционирование с `C:\Users\gekto\projects\bluevpn\docs\BUSINESS_PRICING_STRATEGY_RU.md`.
- Текущие цены в backend можно считать техническим/test-каталогом, а не окончательной публичной экономикой.
- Базовая публичная стратегия: `Старт` 149 руб/мес, `Стандарт` 299 руб/мес как главный тариф, `Плюс` 449 руб/мес, `Максимум` 699 руб/мес с fair-use вместо безлимита без ограничений.
- Есть GB packs: `5 ГБ`, `20 ГБ`, `30 ГБ`, `100 ГБ`.
- Убрать непонятный маленький counter/square с цифрами `1/2/3/4/5`.
- Есть unlimited app options: YouTube, Telegram, Discord, Instagram etc.
- Любой платный тариф автоматически убирает рекламу.
- Отдельная опция "Без рекламы" не должна быть платной, если выбран любой тариф.
- Если у пользователя нет активного тарифа: button `Оплатить тариф`.
- Если тариф уже активен и пользователь добавляет опции/гигабайты: button `Обновить тариф` или `Добавить к тарифу`.
- Цена считается сервером, клиент только отображает quote.
- Никакой бесплатной активации тарифа через UI. Только order -> provider payment -> webhook -> activate subscription.

## Payments Plan

Для России приоритетно использовать российские способы оплаты.

Порядок:

- Домен и HTTPS.
- YooKassa production shop.
- Backend creates order.
- Client opens payment URL.
- YooKassa webhook confirms payment.
- Backend activates subscription only after confirmed payment.
- Billing reconciliation flags paid-not-activated, stale pending orders and unsafe terminal-order markers before production payments go live.
- Auto-renewal readiness is now dry-run in admin/backend: it flags missing saved payment methods, pending renewal-order conflicts and YooKassa production blockers without charging users or exposing provider payment method ids.
- Client refreshes subscription state.
- Add payment history.
- Add cancel auto-renewal.
- Add change plan/upgrade.
- Add subscription expiry enforcement.
- Subscription expiry readiness is now available before enforcement: expired-active rows, expiring manual subscriptions, retention contact gaps and auto-renew blockers are visible in admin without cutting users off.
- Expired non-paid trial/support rows are safely backfilled to inactive; paid plans are not silently deactivated by the backfill.
- Add scheduled auto-renewal later.

## Separate Admin/Support App

Нужно отдельное приложение/панель для админов и поддержки, не внутри обычного user app.

Роли:

- Root admin: полный доступ.
- Admin: управление пользователями, тарифами, устройствами, серверами.
- Support: поиск пользователя, диагностика, next-config-fetch reissue config, reset device/session, ручные fixes.
- Finance: платежи, возвраты, invoices.
- Read-only: просмотр статистики.

Root/admin функции:

- revenue, MRR, active subscriptions, churn, conversion.
- users/devices/subscriptions/orders/payments.
- dry-run auto-renewal readiness before any scheduled renewal charging is enabled.
- dry-run subscription expiry readiness before `BLUEVPN_ENFORCE_SUBSCRIPTION_ACCESS` is enabled.
- server health, endpoint health, WireGuard health.
- manual feature flags.
- plan/tariff management.
- revoke/disable user/device.
- force config refresh.

Support функции:

- декодировать support report.
- найти пользователя по email/phone/device id.
- reset session/device.
- reissue WireGuard config on next successful `/api/v1/client/config` after support request.
- посмотреть последние ошибки connect/auth/payment.
- фильтровать события входа по телефону/email/status/contact для поддержки phone/email-code auth.
- брать support report в работу с фиксацией `reviewedAt/reviewedBy`, первого ответа и audit.
- выдать временный trial/промокод. Сейчас есть безопасный `grant_support_trial_3d`: продлевает support trial на 3 дня и не перезаписывает активную платную подписку.

## Updater Plan

Нужна система обновлений, потому что клиент придется часто улучшать.

Cheap MVP:

- Backend endpoint `/api/v1/updates/windows`.
- Admin readiness endpoint `/api/v1/admin/updates/readiness`.
- Response: latestVersion, downloadUrl, sha256, required, configuredRequired, fileReady, publicHttpsReady, releaseBlocked, changelog.
- Admin response also exposes `rollbackReadiness`; stable 100% rollout and required updates are blocked until rollback artifact/readiness is green.
- Client checks on startup and from settings.
- Optional update: показать кнопку "Обновить".
- Required update: не давать продолжить без обновления.
- Backend must suppress effective `required` when the final installer URL/SHA256 is missing.
- Published stable releases require public HTTPS download URL and SHA256.
- Installer заменяет старую версию, не ломая state/config.

Later:

- signed update manifest.
- staged rollout 5/25/100%.
- rollback flag.
- multiple channels: stable/beta/dev.
- code signing.
- separate server catalog updates without app update.

## Resilience / Anti-Blocking Plan

Важно: не обещать "физически невозможно заблокировать". Реальная цель - сделать отказоустойчивый VPN, который переживает обычные блокировки IP/портов/UDP/DNS/API/provider/country.

Принцип: не должно быть single point of failure.

Что нужно:

- Несколько серверов в разных странах.
- Несколько hosting providers/ASN.
- Несколько портов.
- Несколько протоколов.
- Fallback API/bootstrap endpoints.
- Signed server catalog.
- Health scoring.
- Managed endpoint config-readiness: an endpoint must explicitly have a client config profile before it can ever be considered publishable.
- Safe publication gate: internal/admin catalog entries remain hidden from users until health, config readiness and rollout rules are green.
- Auto server switch.
- DNS leak protection.
- IPv6 leak protection.
- Kill switch later.

Current resilience groundwork:

- Public client catalog is intentionally still limited to proven builtin `intelligent_smew`.
- Internal managed catalog can now store endpoint protocol, transport, health and client config profile.
- Current working endpoint `current_wg0` can be seeded internally as `builtin_wg0` / config-ready, but remains `isPublic: false`.
- Admin-only provisioning readiness now documents the client `serverId` contract: only `auto` and public catalog ids are accepted, `current_wg0` is internal-only, and multi-endpoint provisioning remains locked until separate peer/config rules and rollout gates exist.
- Server-side `probe-current` now creates safe health observations and score `0-100` for `current_wg0` without exposing keys, tokens or private configs.
- External endpoint-probe readiness is now prepared: the controlled probe runner can run with `--server-health`, post safe endpoint observations, and `GET /api/v1/admin/server-health` reports whether external probes cover config-ready endpoints such as `current_wg0`.
- Monitoring observation `details` are sanitized server-side on write/read so malformed probes cannot persist private keys, tokens, passwords or raw WireGuard configs in admin storage.
- If a managed endpoint is marked public candidate and then receives a bad/low-score health observation, backend auto-pauses publication by clearing `is_public`, recording the reason, and writing admin audit.
- Degraded/down server-health observations now open/reopen internal incidents keyed by endpoint; healthy observations resolve them, so endpoint scoring feeds the support incident dashboard and alert outbox.
- Next missing piece: install the external monitoring probe on a separate VPS, then build real peer/config provisioning for additional servers before any managed endpoint is made visible to users.

Протоколы по слоям:

- WireGuard UDP primary.
- WireGuard alternate ports.
- TCP/443 fallback: OpenVPN TCP or another stable tunnel.
- Shadowsocks AEAD as lightweight proxy/fallback.
- Hysteria2/QUIC as high-performance fallback.
- Trojan/VLESS/REALITY-like stealth later if needed.
- MASQUE/CONNECT-UDP later if ecosystem is ready.

Server geography:

- Сейчас: Netherlands/dev `37.220.85.211`.
- Next cheap layer: Germany + Sweden/Finland.
- Then: Poland/Baltics/France/UK/Turkey/Georgia/Kazakhstan/US depending on cost and user geography.

## Monitoring Plan

Нужно узнавать о проблемах раньше пользователей.

Cheap MVP monitoring:

- One monitoring VPS outside main server.
- Checks every 1-5 minutes.
- Backend health check.
- WireGuard handshake test.
- Test routes to YouTube, Telegram, Discord, Instagram.
- Alert to Telegram/admin when red.
- Admin alert readiness/test button.
- Server-side protected readiness self-check without exposing admin token.
- External owner setup bundle: admin readiness shows owner inputs, apply steps, verify steps, expected public DNS and server-only env commands without secret values.
- Controlled monitoring probe runner for a separate VPS.
- Monitoring readiness now includes external probe install bundle with `--token-stdin`, `--server-health`, `/etc/greenvpn-monitoring/admin_token`, required service targets, required endpoint coverage and verification commands.
- Service-probe readiness now reports missing/stale agents and required target coverage; production monitoring remains blocked until the external monitoring VPS is installed.
- Server-health readiness now separately reports external probe coverage for config-ready endpoints; production endpoint readiness remains blocked until a separate monitoring VPS sends fresh healthy observations for `current_wg0`.
- Incident cards now suggest active runbooks by category/source/service text so support can move from alert to checklist faster.
- Endpoint health incidents are now generated from server-health observations, not only from service availability observations.
- Incidents can now be assigned to active staff members without exposing staff session tokens or requiring full staff-management access.
- Incident alert attempts now have an internal no-secret history/outbox, so Telegram delivery can be enabled later without losing alert observability.
- Updater releases now have per-release publication gates so draft records can be prepared early while public rollout remains blocked until final HTTPS artifact and SHA256 exist.

Better monitoring:

- Multiple probes in different countries/providers.
- Direct vs VPN comparison.
- DNS resolution checks.
- TCP/TLS checks.
- HTTP/headless browser checks.
- Per-endpoint score.
- Auto remove bad endpoint from catalog.
- Admin dashboard: green/yellow/red map.

## Infrastructure To Buy Later

Near:

- Germany VPS.
- Sweden or Finland VPS.
- Small monitoring VPS.
- Domain.
- HTTPS certificates.
- Email service.
- SMS provider for Russia.
- YooKassa account.

Later:

- 3-5 more countries.
- 2-3 hosting providers.
- Spare IP pool.
- Object storage for installers/releases.
- Grafana/Prometheus/alerts.
- Code signing certificate.

## Security Plan

- No secrets in repository.
- Protect local tokens/session/device state.
- Do not show raw exceptions to users.
- Signed update manifest.
- Code signing installer/exe.
- Backend rate limits; email/phone auth-code verify now has per-code attempt counting and temporary lockout.
- Device limits.
- Revocation support; support-triggered config refresh now rotates client WireGuard keys/PSK on next config fetch and audits the application.
- Separate user app and admin/support app.
- Staff session inventory/revocation for the separate admin/support app without exposing raw session tokens.
- Encrypted/coded support reports.
- Server-side redaction for monitoring/probe details before storage and admin rendering.

## Public Release Checklist

- VPN connect/disconnect stable without admin UI launch.
- Tray/background stable.
- Autostart stable.
- Login/register stable.
- No dev/admin UI in user app.
- Human-readable errors.
- Installer branded Green VPN.
- Shortcut name/icon Green VPN.
- Update check available.
- Payment order/webhook activation.
- Support report.
- Terms/privacy/service rules/refund policy.
- Basic monitoring and alerting.
- Code signing if budget allows.
