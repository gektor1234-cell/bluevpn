# Green VPN Next Owner Actions

Последнее обновление: 2026-08-26 МСК

> Платёжный маршрут изменён с Robokassa на Prodamus. Текущий статус и ровно
> семь этапов зафиксированы в `PAYMENTS_RU.md`; старые разделы Robokassa ниже
> являются исторической справкой и не должны применяться.

Этот файл фиксирует только действия, которые после полной автономной проверки
действительно остались за владельцем. Старые setup-подробности ниже сохранены
как справка, но текущий список в следующем разделе имеет приоритет.

## Канонический чеклист владельца из девяти пунктов

Этот список нельзя сокращать или объединять при отчёте о закрытии проекта.

| № | Действие владельца | Текущий статус |
|---:|---|---|
| 1 | Определить конечную модель `v1` | **Готово 2026-08-02:** бесплатный direct-download VPN; монетизация перенесена на следующий этап |
| 2 | Оформить Authenticode Code Signing/Trusted Signing | **Перенесено 2026-08-02:** при текущем статусе владельца нет доступного проверенного публично доверенного маршрута выпуска; вернуться после оформления ИП/юрлица либо выбора Microsoft Store |
| 3 | Принять legal/tax/KYC решения для продаж | **Частично готово:** активный НПД подтверждён, короткая заявка Prodamus отправлена; остаются расширенная анкета, одобрение и партнёрская привязка |
| 4 | Разрешить реальные денежные операции | Коммерческий запуск одобрен в принципе; перед конкретным реальным платежом и возвратом требуется отдельное подтверждение непосредственно в момент операции |
| 5 | Оформить аккаунты Google Play/RuStore | Не выполнено; direct-download `v1` этим не блокируется |
| 6 | Оформить рекламного провайдера | Не выполнено; реклама выключена и не входит в `v1` |
| 7 | Оплатить второй резервный `dnstt`-сервер | Для текущей `v1` не требуется; только отдельное будущее решение |
| 8 | Дать production go/no-go | Для текущей бесплатной версии уже дано и выполнено; для каждой будущей подписанной, платной или рекламной версии требуется новое разрешение |
| 9 | Провести финальную пользовательскую приёмку | Ожидается для формального закрытия `v1` |

## Что блокирует формальное закрытие текущей v1

Инженерных и внешних сервисных блокеров у бесплатного direct-download релиза
нет. Android `0.4.7+2026082401` и Windows `0.4.6+4636` опубликованы как
mandatory stable на обоих control plane. Windows остаётся честно `NotSigned`; принятый
риск SmartScreen не блокирует direct-download. После решения по модели продукта
остаётся пункт 9: финальная пользовательская приёмка.

Для будущего доверенного Windows-релиза нужен пункт 2. На 2026-08-02 проверено:
GlobalSign Russia выпускает Code Signing только ИП и юридическим лицам,
Microsoft Artifact Signing Public Trust не принимает заявителей из России, а
Certum приостановил продажи и выпуск гражданам и организациям РФ. Поэтому
пункт осознанно перенесён, а не потерян. Актуальность условий нужно проверить
повторно перед будущей покупкой. После появления доступного сертификата Codex
самостоятельно подпишет, соберёт, физически проверит и опубликует
higher-version successor только после нового пункта 8.

Для платных продаж нужно завершить пункты 3 и 4. Сейчас sales, refunds и
renewal charges безопасно выключены; включать их до реального payment/refund
smoke нельзя.

Инженерная цепочка подписи, canary, атомарной публикации на оба control plane,
exact-download проверки и rollback уже подготовлена.

Telegram-бот, автопродление, промо, бесплатная квота и rewarded-реклама являются
необязательными будущими бизнес-решениями, а не блокерами релиза. SMTP alerts
уже физически отправляются; денежные и ограничивающие функции остаются
выключенными.

Не требуют повторения до изменения соответствующего кода: email-код,
восстановление аккаунта, Android/Windows tunnel smoke, SMTP, DNS/HTTPS,
внешний мониторинг и проверка обоих зеркал. Старый YooKassa smoke не заменяет
обязательный новый smoke выбранного Robokassa + НПД контура.

## Главное правило

- Не писать сюда реальные пароли, токены, SMTP password, `admin_token`, Robokassa Password1/2/3, старый YooKassa secret key, SSH password и WireGuard private keys.
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

## 4. Robokassa + НПД production

Статус 2026-08-25: **активный НПД подтверждён владельцем, инженерный контур
готов, но внешнее подключение и реальные денежные проверки не завершены**.
`productionPaymentReady=false` является правильным fail-closed состоянием.

Codex уже сделал без движения денег:

- Invoice API, ResultURL, авторитетную проверку Invoice + OpStateExt;
- точную сверку суммы, `InvId`, `State=100` и `OpKey`;
- NПД-позиции для «Робочеков СМЗ»;
- guarded full refund и откат прав;
- защиту от дублей при неопределённом CreateInvoice/CreateRefund;
- запрет платёжных callback на fallback;
- server-only env helper и readiness checks.

Что требует действия владельца/провайдера:

1. Непосредственно перед переходом подтвердить передачу ИНН и referral-данных
   партнёру Robokassa/оператору чеков.
2. Завершить магазин и «Робочеки СМЗ» в кабинете Robokassa.
3. Ввести MerchantLogin и Password1/2/3 только через защищённый env helper.
4. Отдельно разрешить один реальный платёж и один полный возврат.

Публичные URL:

```text
Return URL: https://api.greenvpn.pro/payment/return
Result URL: https://api.greenvpn.pro/api/v1/billing/robokassa/result
```

Timeweb должен оставаться единственным billing writer. На RUVDS writer-флаги
всегда `0`. Продажи и возвраты включаются только после зелёного smoke;
автосписания остаются отдельным будущим gate.

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

Android `0.4.7+2026082401` и Windows `0.4.6+4636` являются текущими
mandatory stable версиями по `release_contract.json`. Точные SHA/size берутся
из актуальных primary/fallback manifests, а не копируются в эту памятку.

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

- SMTP/email-code production-ready; Robokassa + НПД готов в коде, однако
  внешняя партнёрская привязка, payment/refund smoke и денежные gates ещё не завершены;
- phone/SMS flow удалён из продуктового контракта;
- если нет Telegram token, alerts остаются manual MVP;
- rollback готов; без Windows signing холодная массовая дистрибуция остаётся
  осознанным SmartScreen/reputation риском;
- реклама, автосписания, промо и hard expiry включаются только отдельным
  решением владельца после соответствующего smoke.
