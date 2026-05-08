# Admin/support app

## Назначение

Отдельное приложение для внутренней работы:

- главный админ;
- администратор;
- техподдержка;
- бухгалтерия/финансы;
- ops/developer.

Это не часть пользовательского Green VPN UI.

## Папка

`C:\Users\gekto\projects\bluevpn\admin_support_app`

Файлы:

- `index.html`
- `styles.css`
- `app.js`
- `README.md`

Локальный просмотр:

`http://127.0.0.1:8090/`

## Текущий UI

Стиль:

- Green VPN;
- светлый fintech-green;
- крупные карточки;
- спокойная авторизация;
- русские названия разделов;
- понятные статусы.

Разделы:

- Обзор.
- Аналитика.
- Инциденты.
- Поддержка.
- Пользователи.
- Платежи.
- Входы.
- Команда.
- Аудит.
- Обновления.
- Мониторинг.
- Серверы.
- Готовность.

## Login/API connect

Сейчас internal MVP:

- API base URL вводится вручную;
- admin token вводится вручную;
- token не хранится в repo;
- можно помнить в браузере только для локального admin computer, но production позже должен уйти в нормальный auth.

Default API:

`https://api.greenvpn.pro`

## Что должно уметь

### Overview

- users count;
- devices count;
- active subscriptions;
- pending payments;
- support reports;
- incidents;
- release readiness.

### Monitoring

- server catalog;
- health observations;
- health score;
- current endpoint probe;
- latency;
- packet loss;
- status;
- reasons;
- recommendation.

### Support

- reports list;
- report detail;
- user/device lookup;
- safe diagnostics;
- mark reviewed/resolved;
- no private keys.

### Users

- find by email/phone/device id;
- account status;
- devices;
- subscription;
- last login;
- support history.

### Payments

- orders;
- payment statuses;
- manual mark paid only where allowed;
- future YooKassa reconciliation.

### Updates

- current app version;
- latest installer;
- required/optional update;
- staged rollout later.

### Audit

- admin actions;
- support actions;
- sensitive operations.

## Чего не делать

- Не переносить эту админку в пользовательский клиент.
- Не выводить admin token на экран после ввода.
- Не показывать private WireGuard configs.
- Не делать опасные destructive actions без confirmation.

## Следующие улучшения

- Подключить live admin endpoints стабильнее.
- Довести server health flow.
- Добавить support reports.
- Добавить users/devices search.
- Добавить audit events.
- Добавить readiness page for SMTP/SMS/YooKassa.
- Добавить role model позже.
