# Обработка секретов

Этот проект уже содержит backend, платежи, почту, SMS, VPN-конфиги и admin API. Поэтому секреты - отдельный строгий слой.

## Секреты

Секретами считаются:

- SSH password;
- root password;
- admin token;
- session token;
- device token;
- YooKassa secret key;
- SMTP password;
- SMS API key;
- Telegram bot token;
- WireGuard private key;
- preshared key;
- full private WireGuard config;
- database passwords;
- production env files.

## Нельзя

Нельзя:

- писать секреты в repo;
- писать секреты в docs;
- печатать секреты в чат;
- логировать секреты;
- сохранять секреты в generated reports;
- добавлять секреты в installer;
- добавлять секреты в frontend JS;
- использовать admin token как hardcoded value.

## Можно

Можно:

- ссылаться на имена env-переменных;
- писать placeholder вроде `<YOOKASSA_SECRET_KEY>`;
- читать секрет из environment на сервере;
- использовать `Read-Host -AsSecureString`;
- использовать локальный `.env` вне git, если он в `.gitignore` и не попадает в docs;
- писать safe readiness checks без вывода значения.

## Backend env

Ожидаемые env-переменные:

- `YOOKASSA_SHOP_ID`
- `YOOKASSA_SECRET_KEY`
- `YOOKASSA_RETURN_URL`
- `YOOKASSA_WEBHOOK_URL`
- `GREENVPN_SMTP_HOST`
- `GREENVPN_SMTP_PORT`
- `GREENVPN_SMTP_USERNAME`
- `GREENVPN_SMTP_PASSWORD`
- `GREENVPN_SMTP_FROM`
- `GREENVPN_SMTP_USE_TLS`
- `GREENVPN_SMS_PROVIDER`
- `GREENVPN_SMS_RU_API_ID`
- `GREENVPN_SMS_CODE_PEPPER`
- `GREENVPN_SMS_FROM`
- `GREENVPN_SMS_RU_TEST_MODE`
- `GREENVPN_TELEGRAM_ALERT_BOT_TOKEN`
- `GREENVPN_TELEGRAM_ALERT_CHAT_ID`
- `GREENVPN_ADMIN_ALERTS_ENABLED`
- `GREENVPN_ADMIN_ALERT_MIN_SEVERITY`
- `BLUEVPN_ADMIN_TOKEN` или серверный файл `backend/data/admin_token.txt`

Фактические значения не писать.

## Support reports

Support report не должен содержать:

- private keys;
- tokens;
- passwords;
- raw config;
- exact personal sensitive data без необходимости.

Можно содержать:

- masked email;
- masked phone;
- device id hash;
- app version;
- OS;
- safe tunnel status;
- safe endpoint id;
- handshake age;
- traffic counters;
- error code;
- timestamp.

## Admin app

Admin support app может принимать admin token вручную, но:

- не хранить token в repo;
- не коммитить token;
- не печатать token в console logs;
- не делать screenshots с видимым token.

Production future:

- normal admin auth;
- roles;
- audit;
- short-lived sessions;
- MFA.
