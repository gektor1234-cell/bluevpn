# Green VPN External Services Checklist

Последнее обновление: 2026-05-07

Этот файл нужен, чтобы внешние сервисы подключались одним коротким циклом: ты оформляешь сервис, берёшь нужные значения, передаёшь их Codex, а backend/UI уже готовы их принять. Секреты, пароли, API-ключи и токены в этот файл не писать.

## Главное Правило

- В репозиторий нельзя писать пароли, токены, `admin_token`, SMTP-пароли, SMS API keys, YooKassa secret key, SSH-пароли и WireGuard private keys.
- Все реальные секреты должны попадать только на сервер в `/etc/bluevpn/backend.env`.
- Для безопасной загрузки секретов на сервер используй:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\configure_backend_env_wsl.ps1
```

Скрипт спросит значения интерактивно, отправит их по SSH на `37.220.85.211`, подключит `/etc/bluevpn/backend.env` к systemd и перезапустит `bluevpn-backend`.

## Уже Куплено / Настроено

- Домен: `greenvpn.pro`.
- API-домен: `api.greenvpn.pro`.
- Текущий backend/VPN сервер: `37.220.85.211`.
- Сейчас `api.greenvpn.pro` ещё указывает на `37.220.85.211`; это рабочий dev/prod-вариант, но не финальная production-схема.
- Для публичного запуска API/сайт должны жить на отдельном публичном IP, который не совпадает с VPN endpoint `37.220.85.211`. Иначе клиент с full-tunnel VPN может заблокировать доступ браузера к собственному сайту/API.
- DNS для домена и `www` сейчас указывает на `95.163.244.138`; это можно использовать как отдельный сайт/лендинг или заменить будущим reverse proxy.
- Yandex 360 организация: `Green VPN`.
- Yandex 360 domain ownership TXT уже был добавлен: `yandex-verification:5583d6225f64e34e`.
- MX уже был добавлен: `@ -> mx.yandex.net.`, priority `10`.
- SPF уже был добавлен: `@ TXT v=spf1 redirect=_spf.yandex.net`.
- DKIM TXT для `mail._domainkey` был добавлен, но после добавления нужно дождаться DNS propagation и проверить в Yandex 360.
- DMARC уже добавлен и server-side readiness видит `_dmarc.greenvpn.pro` green.
- Backend source/live server `0.9.67` уже умеет отдавать admin checklist внешних действий, хранить ручные owner statuses, показывать readiness для alerts/monitoring, держать safe publication gate для managed server catalog, показывать external endpoint probe readiness, показывать API/VPN endpoint split readiness, показывать owner launch packet, показывать payment launch safety, показывать monitoring probe plan, показывать dry-run auto-renewal readiness и dry-run subscription expiry readiness без raw payment method ids.
- Auto-renewal и subscription expiry safe-enable signals теперь требуют clean payment smoke, не только наличие production YooKassa keys.
- Checklist в admin/support app теперь отдаёт safe setup bundle: apply command, readiness command, ожидаемые публичные DNS records, safe defaults и per-action `ownerInputs`/`applySteps`/`verifySteps` без секретных значений.
- Owner packet CLI: `scripts\windows\get_owner_launch_packet.ps1`.

## Owner Workflow В Админке

В отдельной admin/support app checklist внешних действий теперь можно вести как рабочую доску:

- `нужно сделать`;
- `в работе`;
- `ждёт владельца`;
- `ждёт провайдера`;
- `готово к применению`;
- `сделано`;
- `заблокировано`;
- `не нужно`.

Это нужно, чтобы владелец один раз подготовил все внешние сервисы, а Codex потом быстро подключил готовые значения через server-only env без повторного выяснения контекста.

Важно:

- ручная отметка не включает production-ready сама по себе;
- production-ready становится зелёным только после реальных DNS/env/HTTPS/provider-проверок;
- заметки в owner workflow не должны содержать секреты;
- реальные пароли/ключи всё равно вводятся только через `configure_backend_env_wsl.ps1` и попадают только в `/etc/bluevpn/backend.env` на сервере.
- подсказки `ownerInputs` в админке нужны только как список того, что владелец должен подготовить; секретные значения туда не вставлять.

## 1. Email Confirmation / Почта

Цель: backend умеет отправлять письма Green VPN с домена `greenvpn.pro`. Сейчас это база для email-кодов входа/регистрации и будущих уведомлений; старую отдельную пользовательскую кнопку `Подтвердить почту` из обычных настроек убрали.

Что уже готово в коде:

- Backend endpoints: `/api/v1/auth/email/status`, `/api/v1/auth/email/resend`, `/api/v1/auth/email/verify`.
- Backend readiness: `/api/v1/admin/email/readiness`.
- Client UI: Settings -> Account показывает почту в простом виде без лишней технической кнопки.
- Без SMTP приложение не ломается: письмо попадает в safe `not_configured` режим.

Что нужно сделать вручную:

1. В Yandex 360 создай ящик `no-reply@greenvpn.pro`.
2. Подтверди, что MX/SPF/DKIM зелёные в Yandex 360.
3. Подтверди, что DMARC уже есть в DNS:

```text
Type: TXT
Host/Subdomain: _dmarc
Value: v=DMARC1; p=none; rua=mailto:postmaster@greenvpn.pro; adkim=s; aspf=s
```

4. Создай ящики или алиасы `support@greenvpn.pro` и `postmaster@greenvpn.pro`.
5. Создай пароль приложения или SMTP-пароль для `no-reply@greenvpn.pro`.
6. Запусти env-скрипт и выбери `Configure Yandex 360 SMTP email confirmation now?`.

Что скрипт пропишет на сервер:

```text
GREENVPN_PUBLIC_BASE_URL=https://api.greenvpn.pro
GREENVPN_EMAIL_PUBLIC_BASE_URL=https://api.greenvpn.pro
GREENVPN_SMTP_HOST=smtp.yandex.ru
GREENVPN_SMTP_PORT=465
GREENVPN_SMTP_USERNAME=no-reply@greenvpn.pro
GREENVPN_SMTP_PASSWORD=<секрет, только на сервере>
GREENVPN_SMTP_FROM=Green VPN <no-reply@greenvpn.pro>
GREENVPN_SMTP_USE_TLS=1
GREENVPN_EMAIL_CONFIRMATION_REQUIRED=0
GREENVPN_EMAIL_CONFIRMATION_TTL_HOURS=24
```

Почему `GREENVPN_EMAIL_CONFIRMATION_REQUIRED=0` сначала: письмо уже будет отправляться, но VPN/login не будут ломаться, пока мы не проверили доставку. Когда доставка стабильно работает, переключим на `1`.

Официальные ссылки:

- [Yandex 360 для бизнеса](https://360.yandex.ru/business/)
- [Yandex Mail clients / SMTP](https://yandex.ru/support/mail/mail-clients/others.html)

## 2. Phone / SMS Auth

Цель: пользователь сможет добавить телефон, получить SMS-код и позже входить/восстанавливать доступ через телефон. В публичном UI телефон показывается одной простой строкой без дубля `Привязать телефон`.

Что уже готово в коде:

- Backend env/readiness для SMS.
- Backend tables: `phone_confirmations`, `sms_outbox`.
- Backend endpoints: `/api/v1/auth/phone/status`, `/api/v1/auth/phone/start`, `/api/v1/auth/phone/verify`.
- Client UI: Settings -> Account показывает телефон одной строкой; диалог кода остаётся подготовленным внутри приложения.
- SMS-коды в базе хранятся хешем, не открытым текстом.
- `sms_outbox` не сохраняет реальный код в теле SMS, только маску `******`.
- Без SMS-провайдера приложение не ломается: режим `manual_mvp` / `not_configured`.

Первый поддержанный провайдер: `SMS.ru`.

Что нужно сделать вручную:

1. Зарегистрируйся или войди в SMS.ru.
2. Пополни баланс минимально для теста.
3. Получи `api_id`.
4. Если хочешь красивое имя отправителя, отдельно согласуй sender name, например `GreenVPN`. Если sender name ещё не согласован, оставь поле пустым.
5. Запусти env-скрипт и выбери `Configure SMS.ru phone confirmation now?`.

Что скрипт пропишет на сервер:

```text
GREENVPN_SMS_PROVIDER=smsru
GREENVPN_SMS_RU_API_ID=<секрет, только на сервере>
GREENVPN_SMS_FROM=<опционально, только если sender name согласован>
GREENVPN_SMS_RU_TEST_MODE=0
GREENVPN_SMS_CODE_PEPPER=<длинный случайный секрет, только на сервере>
GREENVPN_SMS_CONFIRMATION_TTL_MINUTES=10
GREENVPN_SMS_RESEND_COOLDOWN_SECONDS=60
```

Официальные ссылки:

- [SMS.ru API](https://sms.ru/api)
- [SMS.ru](https://sms.ru/)

## 3. Production Payments / YooKassa

Цель: пользователь нажимает `Оплатить тариф`, backend создаёт платёж в YooKassa, пользователь оплачивает, webhook подтверждает оплату, тариф активируется только после реального подтверждения.

Что уже готово в коде:

- Backend создаёт billing order.
- Public direct tariff activation закрыт.
- YooKassa payment creation уже есть.
- Hosted payment return page уже есть: `https://api.greenvpn.pro/payment/return`.
- Webhook endpoint уже есть: `https://api.greenvpn.pro/api/v1/billing/yookassa/webhook`.
- Webhook в production mode дополнительно подтягивает платёж из YooKassa API и сверяет order id, amount и currency.
- Client умеет открывать payment URL и автоматически опрашивать pending order.
- Admin/backend now has dry-run auto-renewal readiness at `/api/v1/admin/billing/renewals/readiness`: it flags missing saved payment methods, pending renewal conflicts and YooKassa production blockers without charging users or exposing provider payment method ids.
- Admin/backend now has dry-run subscription expiry readiness at `/api/v1/admin/subscriptions/expiry-readiness`: it flags expired-active rows, expiring manual subscriptions, retention contact gaps and auto-renew blockers before subscription enforcement is enabled.
- Expired non-paid trial/support rows are backfilled to inactive on startup; paid plans are not silently changed.

Что нужно сделать вручную:

1. Оформить магазин в YooKassa.
2. Получить `shopId`.
3. Получить `secretKey`.
4. В кабинете YooKassa добавить webhook:

```text
URL: https://api.greenvpn.pro/api/v1/billing/yookassa/webhook
Events: payment.succeeded, payment.canceled
```

5. Указать return URL, если YooKassa просит:

```text
https://api.greenvpn.pro/payment/return
```

6. Запустить env-скрипт и выбрать `Configure YooKassa production payments now?`.

Что скрипт пропишет на сервер:

```text
YOOKASSA_SHOP_ID=<секрет/идентификатор магазина, только на сервере>
YOOKASSA_SECRET_KEY=<секрет, только на сервере>
YOOKASSA_API_BASE=https://api.yookassa.ru/v3
YOOKASSA_RETURN_URL=https://api.greenvpn.pro/payment/return
YOOKASSA_WEBHOOK_URL=https://api.greenvpn.pro/api/v1/billing/yookassa/webhook
GREENVPN_PUBLIC_BASE_URL=https://api.greenvpn.pro
```

Официальные ссылки:

- [YooKassa API Quick Start](https://yookassa.ru/developers/payment-acceptance/getting-started/quick-start)
- [YooKassa Webhooks](https://yookassa.ru/developers/using-api/webhooks)

## 4. Domain / DNS / HTTPS

Цель: пользователь и платёжные провайдеры работают не с IP, а с нормальным HTTPS-доменом.

Текущие DNS-записи, которые должны быть в финальной production-схеме:

```text
A     api              <отдельный public API/site IP, не 37.220.85.211>
A     nl1.vpn          37.220.85.211
MX    @                mx.yandex.net.     priority 10
TXT   @                v=spf1 redirect=_spf.yandex.net
TXT   _dmarc           v=DMARC1; p=none; rua=mailto:postmaster@greenvpn.pro; adkim=s; aspf=s
TXT   mail._domainkey  <DKIM value from Yandex 360>
TXT   @                yandex-verification:5583d6225f64e34e
```

Важно:

- До покупки/настройки отдельного API/site IP текущая запись `A api -> 37.220.85.211` допустима для разработки.
- Перед публичным запуском `api.greenvpn.pro` должен вести на HTTPS reverse proxy/API, который не использует тот же IP, что VPN endpoint.
- VPN endpoint лучше вынести на отдельное имя, например `nl1.vpn.greenvpn.pro -> 37.220.85.211`, а будущие локации оформлять как `de1.vpn.greenvpn.pro`, `kz1.vpn.greenvpn.pro` и так далее.
- `greenvpn.pro` и `www.greenvpn.pro` можно держать как публичный сайт/лендинг; они тоже не должны требовать подключения к тому же IP, через который идёт VPN endpoint.
- HTTPS на текущем backend уже включён через nginx + Let's Encrypt для `api.greenvpn.pro`; перед production YooKassa/email-required режимом всё равно проверяй `/healthz` по HTTPS.
- Если Windows-хост открывает сайт без VPN, но не открывает с включённым full-tunnel VPN, это ожидаемый симптом общей IP-точки API и VPN endpoint. Решение: разделить API/site IP и VPN endpoint IP.

Официальные ссылки:

- [REG.RU DNS help](https://help.reg.ru/support/dns-servery-i-nastroyka-zony/resursnyye-zapisi)
- [REG.RU domain control panel](https://www.reg.ru/user/account/)

## 5. Telegram Alerts Для Админки

Цель: если monitoring/инциденты видят красную проблему, админ получает alert раньше, чем пользователь напишет в поддержку.

Что уже готово в коде:

- Backend readiness: `/api/v1/admin/alerts/readiness`.
- Backend test endpoint: `/api/v1/admin/alerts/test`.
- Инциденты хранят последнюю попытку alert: `lastAlertAt`, `lastAlertStatus`, `lastAlertError`.
- Admin/support app показывает readiness и кнопку `Проверить Telegram alert`.
- Без Telegram credentials система остаётся в `manual_mvp` и не ломает monitoring/support.

Что нужно сделать вручную:

1. В Telegram открыть [BotFather](https://t.me/BotFather).
2. Создать bot командой `/newbot`.
3. Сохранить bot token, но не писать его в репозиторий и не вставлять в документы.
4. Создать приватный чат/группу для алертов Green VPN.
5. Добавить туда бота.
6. Получить `chat_id`. Самый простой вариант: временно написать боту/в группу сообщение и проверить `getUpdates`, либо использовать безопасный helper позже.
7. Запустить env-скрипт и выбрать настройку Telegram alerts.

Что скрипт пропишет на сервер:

```text
GREENVPN_ADMIN_ALERTS_ENABLED=1
GREENVPN_ADMIN_ALERT_MIN_SEVERITY=high
GREENVPN_TELEGRAM_ALERT_BOT_TOKEN=<секрет, только на сервере>
GREENVPN_TELEGRAM_ALERT_CHAT_ID=<секрет/идентификатор, только на сервере>
GREENVPN_TELEGRAM_ALERT_TIMEOUT=10
```

После подключения проверить:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck
```

И в отдельной admin/support app нажать `Проверить Telegram alert`.

## 6. Monitoring Probe VPS

Цель: отдельный controlled monitoring agent будет регулярно проверять YouTube/Discord/Telegram/API/update/payment targets и писать observations в backend.

Что уже готово в коде:

- Probe runner: `C:\Users\gekto\projects\bluevpn\scripts\monitoring\service_probe.py`.
- systemd installer: `C:\Users\gekto\projects\bluevpn\scripts\monitoring\install_probe_systemd.sh`.
- Backend endpoints:
  - `/api/v1/admin/monitoring/targets`;
  - `/api/v1/admin/monitoring/service-observations`;
  - `/api/v1/admin/monitoring/probes`;
  - `/api/v1/admin/server-health`;
  - `/api/v1/admin/server-health/observations`.
- Admin/support app уже показывает external probe install bundle из `/api/v1/admin/monitoring/readiness`: команда установки с `--token-stdin` и `--server-health`, token path, required targets, required endpoint coverage и verify steps без секретных значений.

Что нужно сделать вручную позже:

1. Купить маленький monitoring VPS у провайдера, отличного от основного VPN/backend сервера.
2. Лучше первая дешёвая точка: Германия, Финляндия, Швеция или Польша.
3. Дать Codex SSH host/IP и способ входа.
4. Не присылать пароль в docs. Если пароль нужен для одноразовой настройки, использовать его только в интерактивной сессии.

Команда установки probe на monitoring VPS будет примерно такой:

```bash
bash scripts/monitoring/install_probe_systemd.sh \
  --api-base https://api.greenvpn.pro \
  --probe-id probe-eu-1 \
  --probe-region eu \
  --server-health \
  --token-stdin
```

`admin_token` будет сохранён только на probe-машине в:

```text
/etc/greenvpn-monitoring/admin_token
```

Права файла:

```text
600
```

## 7. Readiness Checker

Для проверки всего внешнего контура с Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\check_external_services_readiness.ps1
```

Расширенная проверка с server-side admin self-check без вывода `admin_token`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck
```

JSON-режим для копирования в отчёт:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\check_external_services_readiness.ps1 -Json -ServerAdminSelfCheck
```

Текущее ожидаемое состояние:

- `DNS A api.greenvpn.pro` должен быть green.
- `API/VPN endpoint split` сейчас ожидаемо red, пока `api.greenvpn.pro` и VPN endpoint используют один IP `37.220.85.211`.
- `DNS MX greenvpn.pro` должен быть green.
- `DNS SPF` должен быть green.
- `DNS DKIM` должен быть green после propagation.
- `DNS DMARC` должен быть green: `_dmarc` запись уже добавлена.
- `Server self-check API HTTPS` должен быть green, если nginx/certbot/backend на сервере живы.
- Локальная проверка `https://api.greenvpn.pro` может быть red при включённом full-tunnel VPN из-за общей IP-точки API и VPN endpoint. Если server-side check green, это не backend outage, но перед публичным запуском IP нужно разделить.

## 8. Что Передавать Codex Потом

Передавать можно только когда сервис уже оформлен. Не нужно заранее писать значения в docs.

Минимальный набор для email:

```text
SMTP mailbox: no-reply@greenvpn.pro
SMTP app password: <секрет>
```

Минимальный набор для SMS:

```text
SMS.ru api_id: <секрет>
Sender name: <если согласован, иначе пусто>
```

Минимальный набор для YooKassa:

```text
YOOKASSA_SHOP_ID: <значение>
YOOKASSA_SECRET_KEY: <секрет>
```

Минимальный набор для Telegram alerts:

```text
GREENVPN_TELEGRAM_ALERT_BOT_TOKEN: <секрет>
GREENVPN_TELEGRAM_ALERT_CHAT_ID: <значение>
GREENVPN_ADMIN_ALERT_MIN_SEVERITY: high
```

Минимальный набор для monitoring VPS:

```text
Monitoring VPS IP/host: <значение>
SSH user: <значение>
Probe region: <например eu/de/fi/se/pl>
```

Минимальный набор для final updater/rollback после финальной сборки installer:

```text
GREENVPN_LATEST_VERSION: <значение>
GREENVPN_UPDATE_URL: <public HTTPS URL final GreenVPN_Setup.exe>
GREENVPN_UPDATE_SHA256: <64 hex>
GREENVPN_ROLLBACK_VERSION: <предыдущая рабочая версия>
GREENVPN_ROLLBACK_URL: <public HTTPS URL rollback GreenVPN_Setup.exe>
GREENVPN_ROLLBACK_SHA256: <64 hex>
```

Если передаёшь это Codex в чат, Codex должен применить значения на сервер через env/systemd и не записывать их в репозиторий.

## 9. Проверки После Подключения

Backend health:

```powershell
wsl bash -lc "curl -fsS https://api.greenvpn.pro/healthz"
```

Email readiness:

```powershell
wsl bash -lc "curl -fsS -H 'X-Admin-Token: <admin_token>' https://api.greenvpn.pro/api/v1/admin/email/readiness"
```

SMS readiness:

```powershell
wsl bash -lc "curl -fsS -H 'X-Admin-Token: <admin_token>' https://api.greenvpn.pro/api/v1/admin/sms/readiness"
```

YooKassa readiness:

```powershell
wsl bash -lc "curl -fsS -H 'X-Admin-Token: <admin_token>' https://api.greenvpn.pro/api/v1/admin/billing/readiness"
```

Auto-renewal dry-run readiness:

```powershell
wsl bash -lc "curl -fsS -H 'X-Admin-Token: <admin_token>' https://api.greenvpn.pro/api/v1/admin/billing/renewals/readiness"
```

Subscription expiry dry-run readiness:

```powershell
wsl bash -lc "curl -fsS -H 'X-Admin-Token: <admin_token>' https://api.greenvpn.pro/api/v1/admin/subscriptions/expiry-readiness"
```

External actions checklist:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck
```

`admin_token` в docs не писать. Если нужно проверить readiness, вводим его только временно в терминале/сессии.

## 10. Не Блокирует Разработку

Если каких-то внешних значений пока нет:

- Email остаётся в `not_configured/manual_mvp` режиме.
- SMS остаётся в `manual_mvp` режиме.
- YooKassa остаётся в manual MVP billing mode.
- Telegram alerts остаются в manual MVP mode.
- Monitoring probe можно не ставить, пока нет отдельного VPS.
- Final update/rollback artifacts можно не публиковать до финального installer; backend/admin уже блокируют опасный full/required rollout без rollback.
- UI/backend продолжают развиваться.

То есть отсутствие внешнего сервиса не должно стопорить разработку. Мы пишем код заранее, а реальные секреты подключаем одним коротким env-деплоем, когда они готовы.
