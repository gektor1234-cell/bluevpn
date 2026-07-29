# Green VPN Next Owner Actions

Последнее обновление: 2026-07-29 МСК

Этот файл фиксирует только действия, которые после полной автономной проверки
действительно остались за владельцем. Старые setup-подробности ниже сохранены
как справка, но текущий список в следующем разделе имеет приоритет.

## Что действительно осталось владельцу

Для бесплатного direct-download релиза:

1. **Windows trust:** оформить Authenticode Code Signing/Trusted Signing с
   доступным закрытым ключом. Это не лицензия Windows 10/11. Сертификат должен
   поддерживать Code Signing EKU и работать с `signtool.exe`.
2. **Production go/no-go:** отдельно разрешить публикацию точного `0.3.19`
   после подписи Windows и выполнить короткий финальный пользовательский smoke.
   До этой команды public Android `0.3.15` и Windows `0.3.17` остаются без
   изменений.

Только если будут включаться платные продажи:

3. **Legal/tax/KYC:** подтвердить юридический/налоговый статус, допустимый
   способ формирования чека, правила возврата и требуемые договоры/KYC.
4. **Money movement:** отдельно разрешить реальный refund или auto-renew smoke,
   если эти функции действительно будут включаться. Сейчас sales, refunds,
   tax confirmation и renewal charges безопасно выключены.

После пунктов 1-2 инженерная цепочка подписи, canary, атомарной публикации на
оба control plane, exact-download проверки и rollback уже подготовлена.

Telegram-бот, автопродление, промо, бесплатная квота и rewarded-реклама являются
необязательными будущими бизнес-решениями, а не блокерами релиза. SMTP alerts
уже физически отправляются; денежные и ограничивающие функции остаются
выключенными.

Не требуют повторения до изменения соответствующего кода: прежний реальный
платёж, email-код, восстановление аккаунта, Android/Windows tunnel smoke, SMTP,
YooKassa, DNS/HTTPS, внешний мониторинг, публикация Android `0.3.15` и проверка
обоих зеркал.

## Главное правило

- Не писать сюда реальные пароли, токены, SMTP password, `admin_token`, YooKassa secret key, SMS API key, SSH password и WireGuard private keys.
- Секреты подключаются только в root-owned env соответствующих control plane;
  текущие production-узлы: Timeweb Moscow `72.56.32.197` и RUVDS Moscow
  `176.113.81.35`. `37.220.85.211` является VPN-узлом, а не production API
  control plane.
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

Статус: **готово**, owner action не требуется. Запись опубликована и readiness
green.

Где: REG.RU -> `greenvpn.pro` -> DNS-серверы и управление зоной -> добавить TXT.

Добавить запись:

```text
Type: TXT
Subdomain/Host: _dmarc
Value: v=DMARC1; p=none; rua=mailto:postmaster@greenvpn.pro; adkim=s; aspf=s
```

Почему это нужно: без DMARC почта может хуже проходить anti-spam проверки. Сейчас readiness checker видит запись.

## 2. Yandex 360 почта

Статус: **готово**, owner action не требуется. Production email/SMTP
readiness green, физический email-code flow и восстановление доступа прошли.

Уже есть:

- домен `greenvpn.pro`;
- Yandex 360 org `Green VPN`;
- MX `@ -> mx.yandex.net`;
- SPF `v=spf1 redirect=_spf.yandex.net`;
- DKIM TXT добавлен;
- domain ownership TXT добавлен.
- рабочий `no-reply` SMTP подключён только через server-side env;
- support/postmaster и доменная доставка проверены;
- `/api/v1/admin/email/readiness` production-ready.

Пароль повторно не передавать и не ротировать без причины.

## 3. Guest-first вход

Телефон и SMS исключены из целевого сценария. Никаких аккаунтов SMS-провайдера,
ключей или тестовых отправок от владельца не требуется.

Статус: **готово**. Физически проверены чистая установка без регистрации,
email перед оплатой и отдельное восстановление подписки по email на Android и
Windows. Повторный OTP или платёж для очередного smoke не нужен.

## 4. YooKassa production

Статус 2026-07-27: **ручная production-оплата готова**. Кабинет активен,
production key установлен только в root-owned env обоих control plane,
provider API, webhook, реальный платёж, чек и активация проверены. Повторный
платёж для smoke не нужен.

Webhook в кабинете проверен 2026-07-11:

```text
URL: https://api.greenvpn.pro/api/v1/billing/yookassa/webhook
Events: payment.succeeded, payment.canceled
```

Дополнительно включены `payment.waiting_for_capture`, `payment_method.active` и `refund.succeeded`.

- если YooKassa спрашивает return URL:

```text
https://api.greenvpn.pro/payment/return
```

Повторно передавать `shopId` или `secretKey` в чат не нужно. При следующей ротации ключ обновляется только через защищённый server-only процесс.

Уже проверено:

- YooKassa env записан только на серверы, backend перезапущен;
- provider API и реальный order/payment/activation прошли;
- Timeweb остаётся единственным billing writer, оплаченный результат синхронизирован на RUVDS;
- `/api/v1/admin/billing/readiness` готов к текущему ручному платёжному сценарию;
- `/api/v1/admin/billing/renewals/readiness` green для dry-run, но реальное
  автоматическое списание намеренно выключено до отдельного решения владельца;
- новые клиенты и backend используют auto-renew только как явный opt-in;
  существующая оплаченная подписка не изменялась;
- `BLUEVPN_ENFORCE_SUBSCRIPTION_ACCESS` остаётся выключенным: три ближайших
  истечения являются гостевыми Trial без email, expired-active строк нет;
- возврат и отмена реального платежа остаются owner/payment-provider gate:
  автоматизация не должна инициировать движение денег.

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

Статус: **готово**, новый VPS сейчас покупать не требуется.

- Два probe-agent покрывают все шесть обязательных targets.
- Все три опубликованных VPN endpoint имеют healthy coverage.
- Production monitoring readiness green.
- Usage reporters London/NL1/NL2 работают отдельно и не меняют VPN routing.

Telegram-доставка alert остаётся отдельным необязательным owner action из
раздела 5. Новый независимый probe VPS можно добавить позже для географической
избыточности, но это не текущий release-блокер.

## 7. Update artifact and rollback artifact

Статус: **готово**.

Android `0.3.14` имеет точные primary/fallback bytes и серверные rollback
каталоги. Для Windows `0.3.13` предыдущий рабочий installer `0.3.12`,
SHA-256
`79F5E201F8F798906C9A7FF5F837B9C5AD08B4890DEB3DF0B7F3F2E3C4EC0FE7`,
опубликован как rollback на обоих зеркалах. Protected readiness на обоих
control plane: `productionReady=true`, `rollbackReady=true`, blockers/warnings
пусты.

При следующей финальной сборке значения обновляются аналогично:

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

Статус: **текущий критический блокер массового Windows-релиза**.

Нужно будет:

- купить code signing certificate;
- настроить подпись `GreenVPN_Setup.exe`;
- настроить подпись `greenvpn.exe` и service executable;
- обновить build pipeline.

Backend, Android и физический Windows smoke это не блокирует, но без подписи
нельзя считать распространение Windows готовым для холодной аудитории:
SmartScreen/reputation warning остаётся ожидаемым.

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

- SMTP/email-code и YooKassa уже production-ready;
- phone/SMS flow удалён из продуктового контракта;
- если нет Telegram token, alerts остаются manual MVP;
- без Windows signing и rollback массовый Windows launch остаётся закрыт;
- реклама, автосписания, промо и hard expiry включаются только отдельным
  решением владельца после соответствующего smoke.
