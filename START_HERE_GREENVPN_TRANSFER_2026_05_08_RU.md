# Green VPN: перенос проекта на другой компьютер

Дата handoff: 2026-05-08
Основной репозиторий на старом ПК: `C:\Users\gekto\projects\bluevpn`
Видимый бренд продукта: `Green VPN`

Этот файл нужен, чтобы на новом ноутбуке открыть Codex и продолжить проект почти как из старого чата. Он специально написан как сопроводительное письмо: что открыть, что нельзя ломать, где текущее состояние, какие артефакты есть, что уже сделано и какие пункты остались.

## Самое короткое начало на новом ноутбуке

1. Распаковать переносной архив в удобную папку. Желательно итоговый путь:

   `C:\Users\gekto\projects\bluevpn`

2. Открыть Codex именно в папке проекта:

   `C:\Users\gekto\projects\bluevpn`

3. В новый Codex-чат вставить сообщение из следующего блока.

## Сообщение для вставки в новый Codex

```text
Продолжаем проект Green VPN после переноса на новый ноутбук.

Репозиторий: C:\Users\gekto\projects\bluevpn

Сначала прочитай:
- START_HERE_GREENVPN_TRANSFER_2026_05_08_RU.md
- docs\CURRENT_HANDOFF.md
- docs\RELEASE_STATE.md
- docs\NEW_CHAT_HANDOFF_2026_05_07\README_RU.md
- docs\NEW_CHAT_HANDOFF_2026_05_07\13_NEXT_DEVELOPMENT_TASKS_RU.md

Обязательно сначала выполни git status --short и не делай destructive cleanup.

Критические правила:
- Видимый бренд: Green VPN.
- Внутренние имена пока не переименовывать: BlueVPNDev1, WireGuardTunnel$BlueVPNDev1, C:\ProgramData\BlueVPN.
- Не трогать Friendly Linnet/personal server, Amnezia, WARP и чужие VPN.
- Origin backend/VPN server: 37.220.85.211.
- API/domain: greenvpn.pro, https://api.greenvpn.pro.
- API proxy server: 72.56.32.197.
- VPN endpoint host: nl1.vpn.greenvpn.pro -> 37.220.85.211.
- Пароли, admin token, SMTP/SMS/YooKassa secrets и WireGuard private keys не писать в repo и не выводить в чат.
- Не делать git reset --hard, git checkout -- или destructive cleanup без прямого разрешения владельца.
- Новый installer не собирать до финального handoff или явной просьбы остановиться и тестировать.

Текущий live backend: 0.9.69.
Последний стабильный rollback installer: C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe
SHA256: 71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87

Если локального архива не хватает, GitHub snapshot должен быть на ветке green-vpn-transfer-20260508 репозитория https://github.com/gektor1234-cell/bluevpn.git.

Продолжай разработку по текущему плану. Главные оставшиеся блокеры: внешний monitoring probe host/token placement, Telegram admin alerts через server-only env, final Windows installer/update artifact. Не активируй START20 и strict enforcement до финальной release/update readiness.
```

## Что это за проект

Green VPN - Windows-first VPN клиент на Flutter с backend на Python/FastAPI, отдельной внутренней admin/support web app и Windows installer/update/diagnostics tooling.

Публичный бренд должен быть `Green VPN`. Внутри исторически осталось много `BlueVPN`: это нормально и пока не переименовывается, потому что эти имена завязаны на WireGuard tunnel, Windows service/task paths и state/config root.

Главные локальные части:

- Flutter user client: `lib\main.dart`, `lib\screens`, `lib\services`.
- Windows runner/tray/service integration: `windows\runner`, `windows\green_vpn_service`.
- Backend source: `backend_live\app\main.py`.
- Backend deploy scripts: `scripts\deploy_backend_wsl.sh`, `scripts\windows\deploy_backend_wsl.ps1`.
- Separate admin/support app: `admin_support_app`.
- Monitoring/probe scripts: `scripts\monitoring`, `scripts\windows\run_monitoring_probe_once.ps1`.
- Release/installer scripts: `scripts\windows\build_installer.ps1`, `scripts\windows\bluevpn_release_gate.ps1`.
- Handoff/docs: `docs`.

## Секреты и доступы

В репозиторий, GitHub, docs и чат нельзя писать реальные значения:

- admin token;
- YooKassa secret key;
- SMTP пароль/app password;
- SMS provider key;
- Telegram bot token/chat id;
- WireGuard private keys;
- SSH private keys;
- root passwords.

В проекте могут встречаться имена переменных вроде `YOOKASSA_SECRET_KEY`, `ADMIN_TOKEN`, `PRIVATE_KEY`. Это не значит, что в файле лежит реальный секрет. Реальные значения должны жить только в server-only env или на конкретном сервере/host в защищенном файле.

Если новый ноутбук не умеет деплоить по SSH, это нормально: SSH ключи не должны автоматически попадать в GitHub или обычный handoff. Для deploy доступа нужно отдельно и безопасно перенести/настроить ключи или пользоваться тем ПК, где ключи уже настроены.

## Текущее состояние инфраструктуры

### Домены и IP

- Root/site:
  - `greenvpn.pro -> 95.163.244.138`
  - `www.greenvpn.pro -> 95.163.244.138`
- Public API:
  - `api.greenvpn.pro -> 72.56.32.197`
- VPN endpoint:
  - `nl1.vpn.greenvpn.pro -> 37.220.85.211`

### Серверы

- Origin backend/VPN server: `37.220.85.211`.
- API reverse proxy: Timeweb Cloud `Friendly Cetus`, IP `72.56.32.197`.
- API proxy terminates HTTPS for `api.greenvpn.pro` through nginx + Let's Encrypt and proxies to origin `https://37.220.85.211`.
- Let's Encrypt cert for `api.greenvpn.pro` expires `2026-08-06`.
- SSH password auth on new proxy was disabled after password appeared in chat; key login remains.

### Backend

- Current live backend: `0.9.69`.
- YooKassa production env is configured server-side.
- One real minimal YooKassa payment for `149 RUB` succeeded and backend activated it through provider-backed sync.
- API/VPN split preflight is green.
- Payment launch safety is green.
- Strict subscription access enforcement remains disabled by env until final launch decision.

## Текущее состояние Windows installer/builds

Не собирать новый installer просто так. Последнее правило владельца: новый installer только на финальном handoff или по явной просьбе остановиться и тестировать.

Последний известный issued installer:

- `C:\BlueVPN_Builds\GreenVPN_Setup.exe`
- `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`
- named copy: `C:\BlueVPN_Builds\GreenVPN_Setup_SupportReportFallback_20260505.exe`
- SHA256: `5F88E078B4E8EE4519D29F6A92FF58A738CA1DD5F1E26ED108864390BAE39D01`

Главный стабильный rollback:

- `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`
- SHA256: `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`

Почему rollback важен: это stable payment-confirmation baseline. Если очередной эксперимент ломает установку/connect/auth, сначала возвращаться к этому якорю.

## GitHub recovery

Remote:

`https://github.com/gektor1234-cell/bluevpn.git`

Переносочный snapshot должен быть запушен на ветку:

`green-vpn-transfer-20260508`

На новом ноутбуке, если архив не используется:

```powershell
cd C:\Users\gekto\projects
git clone -b green-vpn-transfer-20260508 https://github.com/gektor1234-cell/bluevpn.git bluevpn
cd C:\Users\gekto\projects\bluevpn
git status --short
```

Важно: GitHub snapshot содержит исходники/docs/scripts/admin/backend. Build cache, `.dart_tool`, Flutter ephemeral files и Python bytecode не должны быть нужны: они регенерируются. Полный ZIP-архив на старом ПК содержит больше локального состояния.

## Полный план разработки и статус

### 0. Неприкосновенные правила

- Видимый бренд Green VPN - сделано, но постоянно проверять.
- Internal names `BlueVPNDev1`, `WireGuardTunnel$BlueVPNDev1`, `C:\ProgramData\BlueVPN` не переименовывать - сделано/активное правило.
- Не трогать Friendly Linnet, Amnezia, WARP, чужие VPN - сделано/активное правило.
- Секреты не писать в repo/chat - сделано/активное правило.
- No reset/checkout/destructive cleanup без команды - сделано/активное правило.

### 1. Windows MVP core

- Flutter Windows app foundation - сделано.
- WireGuard connect/disconnect - сделано.
- Managed config path under `C:\ProgramData\BlueVPN` - сделано.
- Native service candidate `GreenVPNService` and scheduled task fallback - сделано.
- Tray/background/autostart - сделано.
- Boot conflict guard against other VPNs - сделано.
- Cleanup/uninstaller/boot repair scripts - сделано.

### 2. User app cleanup

- Visible brand cleanup to Green VPN - сделано.
- Remove normal user access to Backend Admin/dev login - сделано.
- Support report instead of raw diagnostics - сделано.
- Updates screen foundation - сделано.
- Server picker from backend catalog - сделано.
- Tariff screen cleanup and traffic packages/slider - сделано.
- Final UX smoke after newest source changes - не сделано до финального installer.

### 3. Auth/account

- Email/password legacy auth - сделано.
- Phone-first auth UI and email-code fallback - сделано в source/backend.
- Auth challenge backend wrappers - сделано.
- Auth events/filtering in admin - сделано.
- SMS.ru production delivery - частично готово, env/provider owner-blocked.
- Final installed-client auth test - не сделано до финального installer.

### 4. Tariffs/billing UI

- Trial/free/paid tariff concepts - сделано.
- User order creation flow - сделано.
- Hosted payment return page/polling - сделано.
- Auto-renew cancel UX foundation - сделано.
- Hide cluttered order history from normal user tariff UI - сделано.
- Final public tariff smoke in fresh installer - не сделано до финального installer.

### 5. YooKassa/payments

- YooKassa integration and validation hardening - сделано.
- Production server-only env configured - сделано.
- Real minimal payment smoke succeeded - сделано.
- Provider-backed activation verified - сделано.
- Payment launch safety green - сделано.
- Automatic billing safety green - сделано.
- Do not print or store YooKassa secret values - сделано/активное правило.

### 6. Public site/docs/download

- Domain `greenvpn.pro` exists - сделано.
- Root/www point to site IP - сделано.
- Public API domain exists - сделано.
- Site readiness gate backend/admin - сделано.
- Public legal pages/offers/privacy/download polish - частично, финальная проверка нужна.
- Public download/update artifact - не сделано до финального installer/update readiness.

### 7. API/VPN split

- Problem identified: API/site and VPN endpoint cannot share same public IP for launch risk - сделано.
- New API proxy server created - сделано.
- DNS `api.greenvpn.pro -> 72.56.32.197` - сделано.
- DNS `nl1.vpn.greenvpn.pro -> 37.220.85.211` - сделано.
- Backend endpoint host moved to `nl1.vpn.greenvpn.pro` - сделано.
- Preflight green - сделано.
- Long-term multi-IP/multi-ASN strategy - не сделано.

### 8. Admin/support app

- Separate admin/support app exists - сделано.
- Staff sessions/RBAC - сделано.
- Incidents, analytics, runbooks, feature flags - сделано.
- Support actions and audit - сделано.
- Owner-action checklist and note secret guard - сделано.
- Billing, renewal, expiry readiness panels - сделано.
- Expiry review action - сделано.
- Final role/security polish - частично.

### 9. Monitoring/alerts

- Internal monitoring targets and observations - сделано.
- Server health observations - сделано.
- Monitoring details sanitization - сделано.
- Incident sync groundwork - сделано.
- External monitoring probe installer/plan - сделано.
- Real separate external probe host/token placement - не сделано, owner/action blocker.
- Telegram admin alerts env/token/chat id - не сделано, owner/action blocker.

### 10. Updates/final installer

- Update manifest foundation - сделано.
- Staged rollout readiness - сделано.
- SHA256/update metadata groundwork - сделано.
- Final Windows installer after all readiness - не сделано.
- Final update/rollback URLs/artifacts - не сделано.
- Code signing - не сделано.

### 11. START20 promo

- Inactive START20 draft exists - сделано.
- Secret-safe owner-action state around promo - сделано.
- Manual activation after payment/release/update readiness - не сделано intentionally.

### 12. Multi-server resilience

- Managed server catalog storage - сделано.
- Health scoring/readiness gates - сделано.
- Public catalog still exposes only proven current endpoint - сделано intentionally.
- Real second VPN endpoint provisioning - не сделано.
- Managed endpoint peer/config automation - не сделано.
- Multi-region/multi-ASN rollout rules - не сделано.

### 13. Protocol fallback / anti-blocking

- WireGuard UDP primary path - сделано.
- Social Only/split-tunnel mode foundation - сделано.
- Server catalog health gate - сделано.
- AmneziaWG fallback - не сделано.
- OpenVPN with TLS masking/Cloak/stunnel fallback - не сделано.
- Shadowsocks/Outline fallback - не сделано.
- Xray/VLESS/REALITY fallback - не сделано.
- Trojan/gRPC/WebSocket/XHTTP variants - не сделано.
- Hysteria2/TUIC QUIC-like fallback - не сделано.
- MASQUE/CONNECT-UDP research layer - не сделано.
- Tor transports as emergency bootstrap idea - не сделано.
- Active probing defense - не сделано.
- Signed emergency catalog/bootstrap endpoints - не сделано.
- DNS/IPv6 leak protection hardening - не сделано.
- Kill switch - не сделано.

Рекомендованный порядок антиблокировки после мониторинга/final installer: сначала Xray/VLESS REALITY или AmneziaWG как реальный fallback, затем Shadowsocks/Outline/OpenVPN+Cloak, затем экспериментальные QUIC/MASQUE layers. Не делать один "магический" протокол; строить слой fallback + monitoring + catalog rollout.

### 14. Mobile

- Mobile plan exists conceptually - частично.
- Mobile app/services - не сделано.
- Mobile payment SDK/key flow - не сделано.
- Mobile anti-blocking UX - не сделано.

### 15. Free/Ads mode

- Free/trial concepts exist - частично.
- Ads-backed mode - не сделано.
- Rewarded/free traffic accounting - не сделано.

### 16. Security/public build

- Secret guards in owner notes/review notes/monitoring details - сделано.
- Payment validation hardening - сделано.
- Admin RBAC/session groundwork - сделано.
- Code signing - не сделано.
- Public privacy/offer/legal polish - частично.
- Final clean install/reinstall/update/rollback test - не сделано.

## Что было закрыто 2026-05-08

- YooKassa production env подключена через server-only env.
- Минимальный live payment `149 RUB` прошел успешно.
- Backend активировал order через provider-backed sync.
- Старый synthetic pending renewal-conflict order был отменен.
- `check_payment_launch_safety.ps1` стал зеленым:
  - `productionPaymentReady=True`;
  - `safeToRunSmoke=True`;
  - `smokeCompleted=True`;
  - `renewalSafeToEnableCharges=True`;
  - `expirySafeToEnableEnforcement=True`;
  - `safeForAutomaticBilling=True`.
- Создан API reverse proxy `72.56.32.197`.
- DNS split сделан:
  - `api.greenvpn.pro -> 72.56.32.197`;
  - `nl1.vpn.greenvpn.pro -> 37.220.85.211`.
- API/VPN split preflight green: `green=7`, `yellow=0`, `red=0`.
- Added subscription expiry review flow:
  - DB table `subscription_expiry_reviews`;
  - `POST /api/v1/admin/subscriptions/{subscription_id}/expiry-review`;
  - admin/support app review action;
  - secret-pattern rejection for review notes.
- Two trial/free expiry candidates were reviewed; strict enforcement remains off.
- Backend live/source reached `0.9.69`.
- Docs updated: `CURRENT_HANDOFF.md`, `RELEASE_STATE.md`, new handoff package entries.

## Что осталось прямо сейчас

1. External monitoring probe host/token placement.
   - Нужен отдельный маленький VPS/probe host, который будет снаружи проверять API, сервисы и VPN endpoint.
   - Токен должен лежать на probe host, например `/etc/greenvpn-monitoring/admin_token`, mode `600`.
   - Не класть token в repo/chat.

2. Telegram admin alerts.
   - Нужны Telegram bot token и chat id.
   - Вводить только через server-only env/configure script.

3. Final installer/update artifact.
   - Только после готовности monitoring/admin-alert/update gates.
   - Собрать финальный installer.
   - Посчитать SHA256.
   - Сохранить rollback.
   - Обновить release docs.

4. START20.
   - Draft inactive.
   - Активировать вручную только после финальной release/update readiness.

5. Anti-blocking fallback.
   - После базового public launch safety выбрать первый fallback: AmneziaWG или Xray/VLESS REALITY.
   - Добавлять через managed catalog, health scoring, rollout gates и emergency catalog.

## Проверочные команды

```powershell
cd C:\Users\gekto\projects\bluevpn
git status --short
```

```powershell
cd C:\Users\gekto\projects\bluevpn
python -m py_compile .\backend_live\app\main.py
```

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_api_vpn_split_preflight.ps1 -ApiBase https://api.greenvpn.pro -VpnEndpointHost nl1.vpn.greenvpn.pro -ExpectedVpnIp 37.220.85.211 -ExpectedApiIp 72.56.32.197 -Json
```

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_payment_launch_safety.ps1 -Json
```

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\get_monitoring_probe_plan.ps1 -Json
```

Installer build commands are intentionally not first-step commands. Use them only at final handoff or owner test request:

```powershell
cd C:\Users\gekto\projects\bluevpn
flutter build windows --release -t .\lib\main.dart
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_release_gate.ps1 -StrictPaymentGate
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build_installer.ps1
```

## Частые ловушки

- Не считать отсутствие локального admin token на ноутбуке backend failure. Многие readiness scripts умеют читать token server-side через SSH; если SSH не настроен, это отдельная access setup задача.
- Не трогать `Friendly Linnet` и чужие VPN.
- Не удалять WireGuard целиком.
- Не удалять Amnezia/WARP.
- Не переименовывать `BlueVPNDev1`.
- Не активировать strict subscription enforcement без финального решения.
- Не публиковать managed endpoints в public catalog, пока нет реального peer/config provisioning.
- Не включать `START20`, пока нет final update/download readiness.
- Не коммитить secrets и не копировать их в handoff.

## Где искать подробности

В первую очередь:

- `docs\CURRENT_HANDOFF.md`
- `docs\RELEASE_STATE.md`
- `docs\NEW_CHAT_HANDOFF_2026_05_07\README_RU.md`
- `docs\NEW_CHAT_HANDOFF_2026_05_07\13_NEXT_DEVELOPMENT_TASKS_RU.md`
- `docs\DEVELOPMENT_PROTOCOL.md`

Большие docs открывать точечно:

- `docs\CODEX_CONTEXT_COMPACT_RU.md`
- `docs\GREENVPN_MASTER_PLAN.md`
- `docs\EXTERNAL_SERVICES_CHECKLIST_RU.md`
- `docs\PAYMENTS_RU.md`
- `docs\BACKEND_ADMIN_API.md`

## Тон работы

Владелец ожидает, что Codex работает автономно, если данных достаточно: не останавливается после одного маленького пункта, доводит логический шаг до конца, проверяет, документирует, не ломает rollback и не просит лишнего. Если требуется внешний секрет/кабинет/provider действие, это явно записывается как owner-blocked, а Codex идет дальше по безопасным задачам.
