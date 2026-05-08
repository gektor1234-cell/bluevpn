# Green VPN Next Owner Actions

Последнее обновление: 2026-05-08

Этот файл фиксирует только те действия, которые реально должен сделать владелец проекта вне кода: купить сервис, создать аккаунт, включить настройку, получить ключ или подтвердить домен. Код и backend уже подготовлены так, чтобы эти данные можно было подключить коротким server-only env-деплоем без записи секретов в репозиторий.

## Главное правило

- Не писать сюда реальные пароли, токены, SMTP password, `admin_token`, YooKassa secret key, SMS API key, SSH password и WireGuard private keys.
- Все секреты подключаются только на сервер `37.220.85.211` через `/etc/bluevpn/backend.env`.
- Рабочий скрипт подключения:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\configure_backend_env_wsl.ps1
```
- В admin/support app раздел `Готовность` теперь показывает safe setup bundle: что дать владельцу, какой env-скрипт запускать, какие DNS-записи ожидать и какими endpoint/checker-командами всё проверить.
- Owner launch packet можно получить отдельно:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\get_owner_launch_packet.ps1
```

По умолчанию admin token остаётся на сервере; скрипт печатает только sanitized summary.
- Поля со статусом external actions можно использовать как трекер, но реальные пароли/токены туда не писать.

## 1. DMARC для домена

Статус: добавлено и проверяется green.

Где: REG.RU -> `greenvpn.pro` -> DNS-серверы и управление зоной -> добавить TXT.

Добавить запись:

```text
Type: TXT
Subdomain/Host: _dmarc
Value: v=DMARC1; p=none; rua=mailto:postmaster@greenvpn.pro; adkim=s; aspf=s
```

Почему это нужно: без DMARC почта может хуже проходить anti-spam проверки. Сейчас readiness checker видит запись.

## 2. Yandex 360 почта

Статус: частично сделано.

Уже есть:

- домен `greenvpn.pro`;
- Yandex 360 org `Green VPN`;
- MX `@ -> mx.yandex.net`;
- SPF `v=spf1 redirect=_spf.yandex.net`;
- DKIM TXT добавлен;
- domain ownership TXT добавлен.

Нужно сделать:

- создать ящик `no-reply@greenvpn.pro`;
- создать ящик или alias `support@greenvpn.pro`;
- создать ящик или alias `postmaster@greenvpn.pro`;
- сгенерировать SMTP/app password для `no-reply@greenvpn.pro`;
- передать Codex только mailbox и app password, чтобы он применил это на сервере через env-скрипт.

Что передать Codex:

```text
SMTP mailbox: no-reply@greenvpn.pro
SMTP app password: <секрет>
Support mailbox: support@greenvpn.pro
Postmaster mailbox: postmaster@greenvpn.pro
```

Что Codex должен сделать после получения:

- записать SMTP env только на сервер;
- перезапустить backend;
- проверить `/api/v1/admin/email/readiness`;
- проверить email-code flow;
- не коммитить пароль и не писать его в docs.

## 3. SMS.ru

Статус: ждёт аккаунт/API key.

Нужно сделать:

- зарегистрироваться или войти в SMS.ru;
- пополнить минимальный тестовый баланс;
- получить `api_id`;
- опционально согласовать sender name `GreenVPN`, но это можно позже.

Что передать Codex:

```text
SMS.ru api_id: <секрет>
Sender name: <пусто или согласованное имя>
```

Что Codex должен сделать после получения:

- записать SMS env только на сервер;
- убедиться, что `GREENVPN_SMS_CODE_PEPPER` задан;
- перезапустить backend;
- проверить `/api/v1/admin/sms/readiness`;
- проверить phone-code start/verify на тестовом номере, если владелец разрешит тестовую SMS.

## 4. YooKassa production

Статус: кабинет владельца активен, backend ждёт production `shopId` и `secretKey` через server-only env.

Нужно сделать:

- оформить магазин YooKassa;
- получить `shopId`;
- получить `secretKey`;
- добавить webhook:

```text
URL: https://api.greenvpn.pro/api/v1/billing/yookassa/webhook
Events: payment.succeeded, payment.canceled
```

- если YooKassa спрашивает return URL:

```text
https://api.greenvpn.pro/payment/return
```

Что передать Codex:

```text
YOOKASSA_SHOP_ID: <значение>
YOOKASSA_SECRET_KEY: <секрет>
```

Что Codex должен сделать после получения:

- записать YooKassa env только на сервер;
- перезапустить backend;
- проверить `/api/v1/admin/billing/readiness`;
- проверить `/api/v1/admin/billing/renewals/readiness`: auto-renewal charges должны оставаться blocked/dry-run, пока production YooKassa readiness не green и pending renewal conflicts не разобраны;
- проверить `/api/v1/admin/subscriptions/expiry-readiness`: `BLUEVPN_ENFORCE_SUBSCRIPTION_ACCESS` не включать, пока expired-active rows и expiring retention blockers не разобраны;
- с backend `0.9.65` оба safe-enable сигнала (`safeToEnableAutoRenewalCharges`, `safeToEnableExpiryEnforcement`) также должны ждать clean payment smoke;
- создать тестовый order/payment в разрешённом тестовом/production режиме;
- проверить, что тариф активируется только после подтверждения YooKassa.

## 5. Telegram alerts

Статус: backend/admin готовы, нужны bot token и chat id.

Нужно сделать:

- открыть `https://t.me/BotFather`;
- создать bot через `/newbot`;
- создать приватную группу или чат для Green VPN alerts;
- добавить bot в этот чат;
- получить bot token и chat id.

Что передать Codex:

```text
GREENVPN_TELEGRAM_ALERT_BOT_TOKEN: <секрет>
GREENVPN_TELEGRAM_ALERT_CHAT_ID: <значение>
GREENVPN_ADMIN_ALERT_MIN_SEVERITY: high
```

Что Codex должен сделать после получения:

- записать alert env только на сервер;
- перезапустить backend;
- проверить `/api/v1/admin/alerts/readiness`;
- нажать/вызвать test alert;
- убедиться, что инциденты показывают last alert status.

## 6. Monitoring VPS

Статус: нужен отдельный маленький сервер позже.

Зачем: основной сервер не должен быть единственной точкой проверки самого себя. Отдельный probe будет видеть, жив ли API/VPN/YouTube/Discord/Telegram через наши маршруты.

Минимально купить:

- 1 дешёвый VPS у другого провайдера;
- регион: Германия, Финляндия, Швеция или Польша;
- Linux с systemd.

Что передать Codex:

```text
Monitoring VPS host/IP: <значение>
SSH user: <значение>
Probe id: probe-eu-1
Probe region: eu
```

Что Codex должен сделать:

- установить `service_probe.py` через `install_probe_systemd.sh`;
- сохранить admin token только на probe machine;
- включить systemd timer;
- проверить, что observations появляются в `/api/v1/admin/monitoring/service-observations`;
- проверить, что endpoint observations появляются в `/api/v1/admin/server-health`, а `current_wg0` получает внешнее healthy-покрытие;
- не менять пользовательский VPN-routing.

Подсказка: раздел `Мониторинг` в admin/support app теперь показывает готовый external probe install bundle: команду с `--token-stdin` и `--server-health`, required targets, required endpoint coverage и verify steps. Admin token всё равно вводится только на probe VPS, не в docs и не в заметки.

Разовый Windows-запуск для диагностики с текущей машины теперь тоже подготовлен, но token всё равно вводится только через stdin:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\run_monitoring_probe_once.ps1 -ServerHealth -AdminTokenFromStdin
```

Production-вариант остаётся отдельный monitoring VPS с systemd timer, чтобы проверка `current_wg0` шла не с backend/VPN-сервера.

## 7. Update artifact and rollback artifact

Статус: backend/admin готовы, installer не собирается до финального handoff или явного запроса на тест.

Что нужно будет передать Codex только после финальной сборки:

```text
GREENVPN_LATEST_VERSION: <значение>
GREENVPN_UPDATE_URL: <public HTTPS URL final GreenVPN_Setup.exe>
GREENVPN_UPDATE_SHA256: <64 hex>
GREENVPN_ROLLBACK_VERSION: <предыдущая рабочая версия>
GREENVPN_ROLLBACK_URL: <public HTTPS URL rollback GreenVPN_Setup.exe>
GREENVPN_ROLLBACK_SHA256: <64 hex>
```

Правило rollout:

- stable `rolloutPercent >= 100` и `isRequired=true` теперь блокируются, пока rollback readiness не green;
- staged rollout ниже 100% можно подготовить заранее, но admin readiness будет считать его не production-ready без rollback;
- значения не секретные, но писать их нужно только после финальной сборки и публикации артефактов.

## 8. Code signing certificate

Статус: позже, ближе к публичной сборке.

Нужно будет:

- купить code signing certificate;
- настроить подпись `GreenVPN_Setup.exe`;
- настроить подпись `greenvpn.exe` и service executable;
- обновить build pipeline.

Это не блокирует текущий backend/admin этап.

## 9. Проверить всё одним скриптом

Обычная проверка:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\check_external_services_readiness.ps1
```

Расширенная проверка через сервер без вывода `admin_token`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck
```

JSON-режим:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\check_external_services_readiness.ps1 -Json -ServerAdminSelfCheck
```

Owner launch packet summary:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\get_owner_launch_packet.ps1
```

## Текущий принцип разработки

Отсутствие внешнего сервиса не должно тормозить код:

- если нет SMTP, email-code flow остаётся в safe/manual readiness;
- если нет SMS.ru, phone-code flow остаётся prepared/manual;
- если нет YooKassa keys, billing остаётся manual MVP, но бесплатная активация тарифа через public API закрыта;
- если нет Telegram token, alerts остаются manual MVP;
- если нет monitoring VPS, probe installer готов, а backend/admin продолжают развиваться.
