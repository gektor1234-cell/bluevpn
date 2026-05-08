# Внешние сервисы: что должен сделать владелец

Этот файл нужен, чтобы не тормозить разработку. Всё, что можно подготовить в коде без секретов, делает Codex. Всё, где нужен аккаунт/оплата/личный доступ, делает владелец и потом передаёт только нужные данные безопасно.

## Уже есть

Домен:

`greenvpn.pro`

Регистратор:

Reg.ru

API DNS:

`api.greenvpn.pro -> 37.220.85.211`

Корпоративная почта:

Yandex 360 подключается/подключена.

## Нужно от владельца: домен и DNS

Проверить в Reg.ru:

- `A @ -> 95.163.244.138`
- `A www -> 95.163.244.138`
- `A api -> 37.220.85.211`
- MX `@ -> mx.yandex.net`, priority `10`
- SPF TXT `@ -> v=spf1 redirect=_spf.yandex.net`
- DKIM TXT `mail._domainkey -> значение из Яндекс 360`
- Yandex verification TXT `@ -> yandex-verification:...`

Codex может проверять DNS публично, но не должен хранить логины/пароли Reg.ru.

## Нужно от владельца: почта

Цель:

- отправка email-кодов входа;
- служебные письма;
- support notifications;
- payment notifications later.

Нужно выбрать/настроить:

- Yandex 360 SMTP для домена;
- mailbox, например `support@greenvpn.pro`, `noreply@greenvpn.pro`;
- SMTP host, port, username;
- app password или SMTP password.

Секреты передавать только как временный ввод, не писать в repo.

Код должен использовать env:

- `GREENVPN_SMTP_HOST`
- `GREENVPN_SMTP_PORT`
- `GREENVPN_SMTP_USERNAME`
- `GREENVPN_SMTP_PASSWORD`
- `GREENVPN_SMTP_FROM`
- `GREENVPN_SMTP_USE_TLS`

## Нужно от владельца: SMS

Цель:

- вход по телефону через SMS-код;
- привязка телефона.

Нужно выбрать провайдера:

- SMS.ru;
- SMS Aero;
- МТС/Tele2/B2B provider;
- другой российский SMS provider.

Код должен быть готов к env:

- `GREENVPN_SMS_PROVIDER`
- `GREENVPN_SMS_RU_API_ID`
- `GREENVPN_SMS_CODE_PEPPER`
- `GREENVPN_SMS_FROM`
- `GREENVPN_SMS_RU_TEST_MODE`

Секреты не в repo.

## Нужно от владельца: YooKassa

Цель:

- production payments;
- webhook payment.succeeded;
- автопродление позже.

Нужно:

- аккаунт YooKassa;
- shop id;
- secret key;
- webhook URL на `https://api.greenvpn.pro/...`;
- проверить договор/юридические документы.

Код должен использовать env:

- `YOOKASSA_SHOP_ID`
- `YOOKASSA_SECRET_KEY`
- `YOOKASSA_RETURN_URL`
- `YOOKASSA_WEBHOOK_URL`
- `YOOKASSA_API_BASE`, если понадобится нестандартный API endpoint.

## Нужно от владельца: code signing

Не срочно, но нужно перед публичным релизом.

Варианты:

- OV code signing certificate;
- EV code signing certificate;
- позже MSIX/App Installer signing.

Цель:

- Windows меньше пугает пользователя;
- installer выглядит довереннее;
- updater может проверять подпись.

## Нужно от владельца: дополнительные серверы

Дешёвый следующий слой:

- 1 VPS Германия;
- 1 VPS Швеция или Финляндия;
- 1 маленький monitoring VPS.

Требования:

- разные провайдеры желательно;
- Ubuntu/Debian;
- root SSH или sudo;
- публичный IPv4;
- возможность UDP;
- не использовать Friendly personal server.

Codex может подготовить install scripts и deploy scripts, но покупку/доступы даёт владелец.

## Нужно от владельца: Telegram alert bot

Для мониторинга:

- создать Telegram bot через BotFather;
- получить bot token;
- получить chat id для alerts.

Env:

- `GREENVPN_TELEGRAM_ALERT_BOT_TOKEN`
- `GREENVPN_TELEGRAM_ALERT_CHAT_ID`
- `GREENVPN_ADMIN_ALERTS_ENABLED`
- `GREENVPN_ADMIN_ALERT_MIN_SEVERITY`

Секреты не в repo.

## Правило

Если от владельца нужно действие, Codex должен писать:

`Нужно от тебя`

и давать короткую пошаговую инструкцию, но разработка не должна останавливаться, если можно подготовить код без этих данных.
