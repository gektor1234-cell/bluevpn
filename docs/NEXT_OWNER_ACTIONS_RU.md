# Green VPN Next Owner Actions

Последнее обновление: 2026-08-02 МСК

Этот файл фиксирует только действия, которые после полной автономной проверки
действительно остались за владельцем. Старые setup-подробности ниже сохранены
как справка, но текущий список в следующем разделе имеет приоритет.

## Канонический чеклист владельца из девяти пунктов

Этот список нельзя сокращать или объединять при отчёте о закрытии проекта.

| № | Действие владельца | Текущий статус |
|---:|---|---|
| 1 | Определить конечную модель `v1` | **Готово 2026-08-02:** бесплатный direct-download VPN; монетизация перенесена на следующий этап |
| 2 | Оформить Authenticode Code Signing/Trusted Signing | Не выполнено; требуется только для будущего доверенного массового Windows-релиза |
| 3 | Принять legal/tax/KYC решения для продаж | Не выполнено; не относится к бесплатной `v1` |
| 4 | Разрешить реальные денежные операции | Не разрешено; refunds и auto-renew charges выключены |
| 5 | Оформить аккаунты Google Play/RuStore | Не выполнено; direct-download `v1` этим не блокируется |
| 6 | Оформить рекламного провайдера | Не выполнено; реклама выключена и не входит в `v1` |
| 7 | Оплатить второй резервный `dnstt`-сервер | Для текущей `v1` не требуется; только отдельное будущее решение |
| 8 | Дать production go/no-go | Для текущей бесплатной версии уже дано и выполнено; для каждой будущей подписанной, платной или рекламной версии требуется новое разрешение |
| 9 | Провести финальную пользовательскую приёмку | Ожидается для формального закрытия `v1` |

## Что блокирует формальное закрытие текущей v1

Инженерных и внешних сервисных блокеров у бесплатного direct-download релиза
нет. Android `0.3.19+2026072914` и Windows `0.3.26+3105` опубликованы как
optional на обоих control plane. Windows остаётся честно `NotSigned`; принятый
риск SmartScreen не блокирует direct-download. После решения по модели продукта
остаётся пункт 9: финальная пользовательская приёмка.

Для будущего доверенного Windows-релиза нужен пункт 2. После получения
сертификата Codex самостоятельно подпишет, соберёт, физически проверит и
опубликует higher-version successor только после нового пункта 8.

Для будущих платных продаж нужны пункты 3 и 4. Сейчас sales, refunds, tax
confirmation и renewal charges безопасно выключены.

Инженерная цепочка подписи, canary, атомарной публикации на оба control plane,
exact-download проверки и rollback уже подготовлена.

Telegram-бот, автопродление, промо, бесплатная квота и rewarded-реклама являются
необязательными будущими бизнес-решениями, а не блокерами релиза. SMTP alerts
уже физически отправляются; денежные и ограничивающие функции остаются
выключенными.

Не требуют повторения до изменения соответствующего кода: прежний реальный
платёж, email-код, восстановление аккаунта, Android/Windows tunnel smoke, SMTP,
YooKassa, DNS/HTTPS, внешний мониторинг, публикация Android `0.3.19`, Windows
`0.3.26` и проверка обоих зеркал.

## Главное правило

- Не писать сюда реальные пароли, токены, SMTP password, `admin_token`, YooKassa secret key, SMS API key, SSH password и WireGuard private keys.
- Секреты подключаются только в root-owned env соответствующих control plane;
  текущие production-узлы: Timeweb Moscow `72.56.32.197` и RUVDS Moscow
  `176.113.81.35`. `37.220.85.211` является VPN-узлом, а не production API
  control plane.
- Рабочий скрипт подключения:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\configure_backend_env_wsl.ps1 -ServerHost 72.56.32.197
```

Mutating env helper больше не выбирает сервер по умолчанию. Для Timeweb нужно
явно добавить `-ServerHost 72.56.32.197`, для RUVDS —
`-ServerHost 176.113.81.35`; изменения выполняются по одному control plane с
проверкой второго и rollback.
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

Статус 2026-08-02: **provider-интеграция и прежний реальный payment smoke
подтверждены, но продажи не разрешены**. Кабинет активен, production key
установлен только в root-owned env обоих control plane, provider API, webhook,
реальный платёж, чек и активация проверены. Текущий
`productionPaymentReady=false` является ожидаемым policy state: sales,
tax-confirmation, refund execution и renewal charges выключены. Повторный
платёж до решения владельца о коммерческом запуске не нужен.

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
- `/api/v1/admin/billing/readiness` отвечает и подтверждает установленного
  provider, но остаётся `productionReady=false`, пока денежные gates выключены;
- `/api/v1/admin/billing/payment-smoke/readiness` подтверждает
  `smokeCompleted=true`, один успешный provider-backed кандидат и отсутствие
  synthetic activation;
- `/api/v1/admin/billing/renewals/readiness` остаётся readiness-only:
  `paymentSmokeReady=false`, реальное автоматическое списание выключено до
  отдельного решения владельца и нового разрешённого smoke;
- новые клиенты и backend используют auto-renew только как явный opt-in;
  существующая оплаченная подписка не изменялась;
- `BLUEVPN_ENFORCE_SUBSCRIPTION_ACCESS` остаётся выключенным; бесплатный
  permanent-Free доступ не зависит от истечения подписки;
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

Android `0.3.19+2026072914` и Windows `0.3.26+3105` имеют точные
primary/fallback bytes и серверные rollback-каталоги. Текущий Windows SHA-256:
`1E5505E73B735A00E1C7C44BD1919F96F98EA8DC5F03497205EA39E89AAE00F6`.
Stable и `public-product` manifest на обоих control plane возвращают
`fileReady=true`; текущая публичная проверка манифестов и загрузок проходит
`20/20`, public surface — `31/31`.

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

Статус: **внешний блокер только доверенного массового Windows-релиза**.
Текущий бесплатный direct-download релиз уже опубликован и этим не блокируется.

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

- SMTP/email-code production-ready; YooKassa provider настроен и проверен,
  однако денежные gates и продажи выключены;
- phone/SMS flow удалён из продуктового контракта;
- если нет Telegram token, alerts остаются manual MVP;
- rollback готов; без Windows signing холодная массовая дистрибуция остаётся
  осознанным SmartScreen/reputation риском;
- реклама, автосписания, промо и hard expiry включаются только отдельным
  решением владельца после соответствующего smoke.
