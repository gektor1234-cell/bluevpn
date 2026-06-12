# Green VPN Master Plan

Последнее обновление: 2026-05-10

Этот документ фиксирует общий план разработки Green VPN, чтобы продолжать проект с любого аккаунта Codex без потери контекста.

## Жесткая привязка к разработке

Этот мастер-план является обязательной дорожной картой проекта. Рабочий регламент движения по нему вынесен в:

`C:\Users\gekto\projects\bluevpn\docs\DEVELOPMENT_PROTOCOL.md`

Правило проекта: каждый следующий крупный пункт делается только после того, как предыдущий пункт стал стабильным, проверенным и забетонированным rollback-версией. Если после эксперимента что-то ломается, сначала возвращаемся к последнему rollback anchor из `RELEASE_STATE.md`, потом продолжаем с того же пункта плана.

Текущий стабильный rollback anchor:

- `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`
- SHA256: `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`

Текущий этап: отдельное admin/support приложение и серверный слой поддержки поверх уже подготовленных external-services readiness. Simple updater, server catalog, basic monitoring endpoint, internal-only service availability checks, backend YooKassa safety checks, production payment readiness, payment confirmation flow, billing reconciliation guard, email-confirmation foundation, SMS/phone foundation, auth challenge endpoints, phone-first/email-code/password-legacy auth UI source, filtered auth-event support tooling, coded support reports with send-first/fallback-copy flow and backend decode redaction hardening, admin analytics, support SLA queue, incidents with runbook suggestions, staff assignment and alert outbox, managed monitoring targets, refreshable default monitoring targets, server health observations with admin filters, service observation filters, current endpoint health scoring, monitoring-details sanitization, controlled service-probe readiness endpoint/admin cards with external probe install bundle, update release readiness guard/admin cards with channel-aware readiness, per-release publication gate and rollback publication guard, external owner-actions checklist/workflow with safe setup bundle and owner-action audit guard, Telegram alert readiness, feature flags, runbooks, staff-session inventory/revocation, support-action reason/confirmation guard, safe support actions including 3-day support trial and next-config-fetch WireGuard config refresh/reissue, staged update rollout, safe server-catalog publication gate, server-catalog auto-pause for bad public candidates, admin publication filter, managed endpoint client-config readiness, new economics/capacity plan, tariff speed classes, capacity-aware sticky endpoint assignment and WireGuard peer rate-limit planning are now in source. Production payments/email/SMS/alerts mostly need external credentials and provider activation: YooKassa production keys, Yandex 360 SMTP mailbox/app password, SMS.ru API key, Telegram bot/chat id, DMARC, monitoring VPS, final HTTPS/public-domain checks, and final installer artifact URL/SHA256 plus rollback artifact URL/SHA256. Admin/support app is now being expanded with readiness, monitoring, incident, support and endpoint-resilience tooling, while the normal user app stays clean. New test installers are now final-only: do not rebuild after every intermediate step; clean the installed Green VPN copy only immediately before issuing the next final installer.

Текущее решение от 2026-05-10: мобильное приложение не начинать сейчас. Сначала закрываем весь общий слой, который потом будет использоваться мобильным клиентом: backend/API, auth, billing, server catalog, monitoring, Windows client/service, public site, admin/support app, release/update/trust контур и документацию. Мобильный клиент идет последней фазой, когда эти контракты стабилизированы и не требуют постоянных переделок.

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
- Старый Defender/Yandex-flagged публичный установщик снят с выдачи и находится в серверном карантине. Временный unsigned hardened installer снова опубликован по прямой просьбе владельца: `https://greenvpn.pro/downloads/GreenVPN_Setup_HiddenInstaller_20260509.exe`, SHA256 `5A25D68A2CAFC1D68719D552C51FCD997E733ED48D6B22C46CD5CE8027E0C9CE`. Эта сборка использует RemoteSigned, single-instance guard и скрытый installer PowerShell, чтобы не держать синюю консоль на экране. Финальный публичный релиз Windows все еще блокируется не функциональностью VPN, а trust/reputation цепочкой установщика.
- Live admin/backend очищены перед стартом: тестовые пользователи, устройства, подписки, заказы, токены, support/auth/audit/incident/promo/update-smoke данные удалены; тестовые WireGuard peers сняты; инженерные разделы `Флаги` и `Инструкции` скрыты из MVP-админки.
- Source-level Windows protection strengthened for the next installer: local `GreenVPNService` privileged endpoints require installer-created `C:\ProgramData\BlueVPN\service_token`, connect/disconnect are POST-only, the client sends `X-GreenVPN-Local-Token`, and support doctor reports redact secrets before output.
- External monitoring is no longer only planned: a controlled probe is installed on `72.56.32.197`, stores the admin token only in `/etc/greenvpn-monitoring/admin_token`, and covers public service targets plus `current_wg0` external endpoint health.
- Current launch closure after shared-layer cleanup: `codeOwned=0`; remaining work is owner/final/operational, not hidden unfinished backend code. Code Signing/Trusted Signing remains the correct future trust path for a polished cold-audience Windows release, but the owner deferred that purchase on 2026-05-11 until the project has recovered current costs and can pay for signing from profit. Current monetization work therefore proceeds without buying Code Signing.
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
17. Installer trust, public build и reputation workflow. Code Signing остается будущим trust-шагом после окупаемости, не текущей покупкой.

## Installer Trust / Public Build Plan

Цель: Green VPN должен устанавливаться как нормальный коммерческий Windows VPN, а не выглядеть для Defender, SmartScreen и браузеров как неизвестный самораспаковывающийся скриптовый пакет.

Что делают нормальные VPN:

- Подписывают все Windows-бинарники через Code Signing: installer/MSI/EXE, главный app executable, service executable и DLL. Статус: не сделано; покупка OV Code Signing или Microsoft Trusted Signing отложена владельцем до окупаемости проекта.
- Используют публичную подпись издателя, чтобы Windows показывал нормального publisher, а не `Unknown Publisher`. Статус: не сделано.
- Не используют SSL-сертификат сайта для подписи `.exe`: SSL нужен только HTTPS, code signing - отдельный тип сертификата. Статус: зафиксировано в плане.
- Хранят приватный ключ подписи в HSM/cloud signing/token, а не в репозитории и не в чате. Статус: правило зафиксировано.
- Собирают установщик через более доверенный pipeline: MSI/WiX/NSIS/MSIX или подписанный installer, без VBS/wscript/скрытого PowerShell/ExecutionPolicy Bypass/scheduled-task bootstrap. Статус: частично сделано; подозрительные паттерны уже убраны из текущего installer pipeline, `ExecutionPolicy Bypass` заменен на `RemoteSigned`, переход на MSI/WiX остается желательным следующим hardening шагом.
- Не допускают несколько UI-инстансов одного VPN-клиента. Статус: сделано; Windows runner использует single-instance mutex и restore уже открытого окна.
- Драйверы и низкоуровневые сетевые компоненты используют через доверенный путь: WireGuard остается отдельным проверенным компонентом, мы не трогаем чужие VPN и не ставим свой неподписанный драйвер. Статус: сделано для текущего MVP.
- Набирают репутацию SmartScreen/Defender по подписанному издателю и хэшу файла. Статус: не сделано; начнется только после подписанного публичного build.
- Отправляют false positive в Microsoft Security Intelligence и Yandex Browser/Protect, если файл ошибочно блокируется. Статус: не сделано для нового build; старый flagged installer снят с публичной выдачи.
- Не просят пользователей отключать Defender/браузерную защиту. Статус: правило зафиксировано.

Жесткий релизный порядок:

1. Получить OV Code Signing certificate или настроить Microsoft Trusted Signing. Статус: отложено до окупаемости и прибыли, которая покрывает эту покупку.
2. Установить сертификат/токен/cloud signing на build-машине. Статус: ожидает владельца.
3. Получить только thumbprint сертификата, без паролей, PIN и приватных ключей. Статус: ожидает владельца.
4. Подписать `greenvpn.exe`, `greenvpn_service.exe`, DLL/EXE в release-папке и финальный installer/MSI/EXE. Статус: не сделано.
5. Проверить подписи Authenticode и release gate. Статус: скрипт подписи усилен; есть verify-only, expected publisher, required artifact names, SHA256/Authenticode JSON report и release-gate parser check; реальная подпись не сделана.
6. Перед локальным install/test удалить только Green VPN с ПК пользователя безопасным cleanup-скриптом. Статус: правило активно.
7. Проверить новый подписанный файл Defender/Yandex/SmartScreen насколько возможно. Статус: не сделано.
8. Отправить false positive submission для нового подписанного файла, если защита все еще ругается. Статус: не сделано.
9. Только после этого считать публичную кнопку скачивания финальным trusted release. Статус: временно опубликован unsigned hardened build 2026-05-09 по прямой просьбе владельца; сайт ведет на `https://greenvpn.pro/downloads/GreenVPN_Setup_HiddenInstaller_20260509.exe`; финальный signed release не сделан.

Подробный runbook: `C:\Users\gekto\projects\bluevpn\docs\INSTALLER_TRUST_AND_AV_FALSE_POSITIVE_RU.md`.

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
- Service privileged endpoints must not be triggerable by a browser GET. Source now requires local token auth for `/status`, `/connect`, `/disconnect`; `/connect` and `/disconnect` are POST-only. `/ping` stays unauthenticated for health only.
- Installer creates a hidden random `C:\ProgramData\BlueVPN\service_token`; token values must never be printed or committed.
- Installed tools include read-only `check_windows_network_protection.ps1` for route/DNS/IPv6/competing-VPN checks without mutating the machine.

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

- Актуальная стратегия с 2026-05-11 описана в `C:\Users\gekto\projects\bluevpn\docs\UNIT_ECONOMICS_AND_CAPACITY_RU.md`; старые цены считать историей.
- Публичная идея: Green VPN можно начать бесплатно, если смотреть рекламу; платный тариф убирает ожидание/рекламу и даёт больше трафика, скорость, устройств и приоритет.
- Backend source `0.9.81` уже содержит новую сетку: `Лёгкий` 199 руб/мес / 50 ГБ, `Оптимальный` 349 руб/мес / 150 ГБ, `Активный` 549 руб/мес / 350 ГБ, `Максимум` 799 руб/мес / 800 ГБ fair-use.
- Quote должен отдавать не только цену, но и `trafficLimitGb`, `speedSustainedMbps`, `speedBurstMbps`, `priorityClass`, `fairUsePolicy`, `rateLimitPolicy`.
- Убрать непонятный маленький counter/square с цифрами `1/2/3/4/5`.
- Есть unlimited app options: YouTube, Telegram, Discord, Instagram etc.
- Любой платный тариф автоматически убирает рекламу.
- Отдельная опция "Без рекламы" не должна быть платной, если выбран любой тариф.
- Если у пользователя нет активного тарифа: button `Оплатить тариф`.
- Если тариф уже активен и пользователь добавляет опции/гигабайты: button `Обновить тариф` или `Добавить к тарифу`.
- Цена считается сервером, клиент только отображает quote.
- Никакой бесплатной активации тарифа через UI. Только order -> provider payment -> webhook -> activate subscription.
- Серверный выбор endpoint должен учитывать ёмкость узла и не отправлять новых пользователей на красный перегруженный endpoint.
- Скорость должна ограничиваться на VPN-узле по внутреннему VPN-IP через `tc`; скрипт `scripts/server/apply_wg_peer_rate_limits.sh` dry-run-first и требует отдельного `--apply` на сервере.
- Нагрузка VPN-узла должна попадать в backend через безопасный репортёр `scripts/server/report_vpn_capacity.sh`; systemd-таймер для него готовится через `scripts/server/install_vpn_capacity_reporter_systemd.sh` и тоже dry-run-first.

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

- Public client catalog starts with proven builtin `intelligent_smew`; it can now include only managed endpoints that pass the safe public gate: active, public candidate, healthy, fresh external observation, config-ready and current-client-ready.
- Internal managed catalog can now store endpoint protocol, transport, health and client config profile.
- Current working endpoint `current_wg0` can be seeded internally as `builtin_wg0` / config-ready, but remains `isPublic: false`.
- Admin-only provisioning readiness now documents the client `serverId` contract: only `auto` and public catalog ids are accepted, `current_wg0` is internal-only, and multi-endpoint provisioning remains locked until separate peer/config rules and rollout gates exist.
- Server-side `probe-current` now creates safe health observations and score `0-100` for `current_wg0` without exposing keys, tokens or private configs.
- External endpoint-probe readiness is now prepared: the controlled probe runner can run with `--server-health`, post safe endpoint observations, and `GET /api/v1/admin/server-health` reports whether external probes cover config-ready endpoints such as `current_wg0`.
- Monitoring observation `details` are sanitized server-side on write/read so malformed probes cannot persist private keys, tokens, passwords or raw WireGuard configs in admin storage.
- If a managed endpoint is marked public candidate and then receives a bad/low-score health observation, backend auto-pauses publication by clearing `is_public`, recording the reason, and writing admin audit.
- Degraded/down server-health observations now open/reopen internal incidents keyed by endpoint; healthy observations resolve them, so endpoint scoring feeds the support incident dashboard and alert outbox.
- Backend now exposes `/api/v1/catalog/resilience` and embeds the same resilience policy into `/api/v1/catalog/servers` and `/api/v1/client/bootstrap`.
- Windows client auto-selection now ranks current-client-ready WireGuard UDP endpoints by health/latency and, in `Авто`, tries the next available endpoint if the first candidate cannot fetch config or connect.
- Backend `0.9.75` adds the adaptive control plane: external route probes and real client route events are blended into `routeDecision.selected`, so the server can choose the lightest healthy route before heavier fallbacks are considered.
- Windows client source now posts no-secret route telemetry (`config_fetch`, `connect`, `handshake`, `connected`) and, in `Авто`, gives priority to the backend-selected current-client-ready route.
- External monitoring probe is installed on the separate Timeweb VPS `72.56.32.197` with `--server-health` and `--route-health`; live probes currently confirm `wireguard_udp` for the published endpoint.
- Planned transports remain guarded: the catalog can describe `wireguard_tcp`, `amneziawg`, `openvpn_tcp`, `shadowsocks`, `hysteria2`, `trojan_tls`, `vless_reality`, `masque_udp`, but the public client must not receive them until the matching server daemon, client engine and release-gate checks exist.
- Backend `0.9.76` adds guarded transport rollout readiness: each transport now has explicit Windows engine, server daemon, public endpoint and route-health gates, with `safeToExposePlannedTransports=false` until the gates pass.
- Source now contains first `wireguard_tcp` canary tooling (`scripts/server/install_wireguard_tcp_canary.sh`): dry-run by default, separate-node oriented, guarded from current production host, and not live until client/server/probe gates pass.
- Backend `0.9.78` adds target-aware route coverage: protected `GET /api/v1/admin/resilience/target-matrix` shows which required services are covered by which route, and route-health observations now open/resolve internal incidents automatically.
- Controlled probe tooling accepts repeatable `--route-candidate endpointId=...,protocol=...,transport=...` for future canary transports, but those candidates must only be used after the probe host really sends checks through that tunnel/proxy path.
- Backend `0.9.79` adds generic guarded canary service tooling (`scripts/server/install_transport_canary_service.sh`) and exposes `canaryScript` per rollout profile. This prepares AmneziaWG, OpenVPN TCP, Shadowsocks, Hysteria2, Trojan TLS, VLESS REALITY and MASQUE as future canary services without publishing them to users.
- Backend `0.9.80` adds sanitized canary readiness validation (`scripts/server/check_transport_canary_readiness.sh`) and exposes `validationScript` per rollout profile. This gives the operator a safe pre-probe check before any canary route is considered for external route-health.
- No anti-blocking system is literally unblockable; the product goal is fast detection, least-heavy working route selection, safe fallback and clean rollback without exposing private keys or breaking unrelated VPN software.
- Next missing resilience pieces are real additional VPN/canary nodes, operator-provided trusted binaries/configs, and Windows client engines beyond WireGuard UDP before any managed endpoint/protocol is made visible to users.

Протоколы по слоям:

- WireGuard UDP primary.
- WireGuard alternate ports.
- AmneziaWG as the first WireGuard-family DPI-resilience candidate.
- TCP/443 fallback: OpenVPN TCP or another stable tunnel.
- Shadowsocks AEAD as lightweight proxy/fallback.
- Hysteria2/QUIC as high-performance fallback.
- Trojan TLS and VLESS/REALITY-like stealth later if needed.
- MASQUE/CONNECT-UDP later if ecosystem is ready.
- Control plane order: start with the lightest current-client-ready healthy route, use client/probe telemetry to detect breakage, then move through heavier fallbacks only when the lighter route is stale/degraded/down.

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
- Service-probe readiness now reports missing/stale agents and required target coverage; the first external probe on `72.56.32.197` is installed and production monitoring coverage is green.
- Server-health readiness now separately reports external probe coverage for config-ready endpoints; `current_wg0` has fresh healthy observations from the external probe.
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
- Local Windows doctor report redacts tokens, passwords, private keys, authorization/cookie material and emails before output/save.
- Release gate enforces local-service token markers, POST-only mutating endpoints, installer token creation, packaged network checker and doctor privacy markers.

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
