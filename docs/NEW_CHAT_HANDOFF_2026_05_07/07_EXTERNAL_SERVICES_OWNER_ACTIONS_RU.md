# Внешние сервисы владельца

Основной подробный файл:

`C:\Users\gekto\projects\bluevpn\docs\EXTERNAL_SERVICES_CHECKLIST_RU.md`

## Уже сделано

- Домен `greenvpn.pro` куплен.
- `api.greenvpn.pro` настроен и используется как public API/site.
- HTTPS на `api.greenvpn.pro` работает server-side.
- Yandex 360 organization: `Green VPN`.
- Почтовые ящики были созданы:
  - `no-reply@greenvpn.pro`
  - `support@greenvpn.pro`
  - `postmaster@greenvpn.pro`
- SMTP Yandex 360 был применен через safe env.
- SMS.ru был подключен через safe env.
- DMARC TXT был добавлен в DNS по ходу предыдущей настройки.
- ЮKassa теперь активна в кабинете владельца, но backend еще ждет production keys.

## Что еще может потребоваться

### ЮKassa

Сейчас ближайший внешний шаг:

- применить `YOOKASSA_SHOP_ID`;
- применить `YOOKASSA_SECRET_KEY` через safe env script;
- добавить/проверить webhook events `payment.succeeded`, `payment.canceled`.

### Telegram alerts

Еще не финализировано, если владелец не предоставил bot token/chat id.

Нужно позже:

- создать Telegram bot через BotFather;
- создать private chat/group;
- добавить bot;
- получить chat id;
- применить через safe env script.

### API/VPN endpoint split

Перед публичным запуском нужен отдельный API/site IP или reverse proxy:

- `api.greenvpn.pro` не должен указывать на тот же IP, что VPN endpoint;
- текущий VPN endpoint лучше оформить как `nl1.vpn.greenvpn.pro -> 37.220.85.211`.

### Monitoring VPS

Позже нужен отдельный маленький VPS не на основном backend/VPN server.

Цель: внешний probe будет проверять API, service targets, server-health и писать observations в backend.

## Как работать с внешними сервисами

Если пользователь рядом:

1. Дать ему один шаг.
2. Дождаться результата.
3. Проверить readiness.
4. Записать состояние в docs.

Если пользователь ушел:

- не блокироваться на внешнем сервисе;
- зафиксировать owner action;
- продолжить кодовые задачи.
