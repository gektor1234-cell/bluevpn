# Green VPN Admin Console

Отдельная внутренняя панель для администратора и техподдержки. Это не пользовательский клиент Green VPN.

## Что умеет сейчас

- Подключается к backend через `https://api.greenvpn.pro` или другой API base URL.
- Принимает `admin_token` вручную и хранит его только в браузере администратора, если включена галочка.
- Показывает обзор пользователей, устройств, подписок, pending-заказов и support reports.
- Показывает production readiness: платежи, email, SMS, updates, server catalog, monitoring.
- Показывает отчёты поддержки и позволяет менять их статус.
- Даёт быстрые действия поддержки из карточки пользователя: сброс сессий, запрос refresh/reissue config, отключение/включение устройства и внутренняя заметка.
- Показывает историю этих действий и пишет их в audit; секреты, токены, WireGuard private keys и содержимое конфигов не отображаются.
- Показывает события входа по email/phone code.
- Показывает базовый мониторинг backend/WireGuard/важных сервисов.
- Показывает внутренние инциденты, созданные из мониторинга.
- Управляет внутренним managed server catalog: новые страны, протоколы, статусы и endpoint-кандидаты.
- Показывает internal server health observations по endpoint: статус, probe region, protocol, latency, packet loss и message.
- Показывает внутреннюю аналитику: пользователи, выручка, заказы, support, incidents, readiness, trends.
- Управляет внутренними monitoring targets для YouTube, Discord, Telegram, API, updates, payments, bootstrap и будущих Social Only проверок.
- Показывает service availability observations по target: green/yellow/red/unknown, probe region, latency, message.
- Использует service availability observations для внутренних incidents, чтобы поддержка видела проблему раньше пользователя.
- Управляет внутренними feature flags: scope, rollout, JSON value, enabled/disabled.
- Управляет release-записями и staged rollout обновлений: published/draft/paused/retired, required/min version, SHA256, download URL и rollout percent.
- Preview manifest показывает, попадёт ли admin-preview устройство в rollout, и почему обновление доступно или удержано.
- Хранит runbooks для техподдержки и ops: пошаговые инструкции по VPN, auth, billing, monitoring, server и installer проблемам.
- Ведёт owner workflow по внешним сервисам: можно отмечать DMARC/SMTP/SMS.ru/YooKassa/Telegram/monitoring VPS как `в работе`, `ждёт владельца`, `готово к применению`, `сделано` или `заблокировано`.
- Owner workflow не подменяет реальные readiness-проверки. Если секреты/DNS/HTTPS ещё не настроены, production readiness останется красной даже при ручной отметке `сделано`.
- Не публикует новые managed endpoint в пользовательский catalog автоматически; публичный клиентский catalog остаётся безопасно ограниченным проверенным сервером, пока мы явно не включим публикацию.
- Показывает publication gate для managed server catalog: почему endpoint ещё нельзя отдавать пользователям, какие blockers остались, и какой следующий ops/Codex/admin шаг нужен.

## Как запускать локально

Вариант без сервера:

1. Открыть `index.html` в браузере.
2. Вставить API base URL.
3. Вставить admin token.
4. Нажать `Войти`.

Вариант через локальный static server:

```powershell
cd C:\Users\gekto\projects\bluevpn\admin_support_app
python -m http.server 8090
```

Потом открыть:

```text
http://127.0.0.1:8090
```

## Важно по безопасности

- Не писать `admin_token` в этот каталог.
- Не коммитить скриншоты с токеном.
- Для production лучше выдавать отдельные роли вместо одного общего admin token.
- Staff auth/RBAC уже подготовлены. Bootstrap admin token должен оставаться только аварийным owner-доступом.
- Server health и service availability данные являются внутренними. Они не должны появляться в обычном пользовательском Green VPN UI.
- Monitoring targets пока управляются вручную в админке; автоматический probe runner нужно запускать только на контролируемых нами agents.
- Feature flags и runbooks являются внутренним инструментом. Не открывать их в публичном Green VPN и не хранить в них секреты.
- Owner action notes не являются секретным хранилищем. Не писать туда admin token, SMTP password, SMS API keys, YooKassa secret key, SSH password или приватные WireGuard ключи.
