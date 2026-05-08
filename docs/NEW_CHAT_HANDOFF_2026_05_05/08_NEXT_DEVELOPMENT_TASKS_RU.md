# Следующие задачи разработки

Работать строго по мастер-плану. Не смешивать пользовательский UI, backend admin, payments и monitoring без причины.

## Текущий ближайший шаг

Стабилизировать health scoring и server catalog.

### Summary

Завершаем текущий этап плана: внутренний мониторинг endpoint и оценка здоровья серверов для админки.

Пользовательский VPN-клиент и installer не трогать, потому что изменения относятся к backend/admin support app.

Публичный клиентский catalog остаётся безопасным и не начинает выдавать managed endpoints пользователям.

### Key Changes

- Проверить и зафиксировать backend `0.9.11` на `37.220.85.211`.
- Использовать правильный публичный URL catalog: `GET /api/v1/catalog/servers`, а не `/api/v1/server-catalog`.
- Довести admin health flow:
  - `GET /api/v1/admin/server-catalog`
  - `GET /api/v1/admin/server-health`
  - `POST /api/v1/admin/server-health/probe-current`
- В админке оставить русские формулировки:
  - `Наблюдения здоровья`
  - `Оценка здоровья`
  - `Проверить текущий endpoint`
  - `Задержка`, `потери`, `статус`, `score`
- Health scoring должен быть внутренним:
  - проверяет `wg0`, конфиг, peer/handshake, UDP endpoint;
  - не пишет ключи, токены, приватные конфиги;
  - сохраняет только безопасные технические признаки и score `0-100`.
- Managed server catalog не публиковать клиентам автоматически:
  - `current_wg0` может быть виден в админке;
  - пользовательский VPN продолжает получать только безопасный builtin catalog до отдельного решения.

### Test Plan

- Локально:
  - `python -m py_compile backend_live\app\main.py`
  - JS syntax check для `admin_support_app\app.js`
- На сервере:
  - deploy backend через `scripts/windows/deploy_backend_wsl.ps1`
  - проверить `/healthz` -> `version: 0.9.11`
  - проверить `/api/v1/catalog/servers` -> `ok: true`
  - проверить admin health endpoints с admin token без вывода токена в чат/логи
- В админке:
  - открыть `http://127.0.0.1:8090/`
  - подключить API
  - нажать `Проверить текущий endpoint`
  - убедиться, что появились русские health observations и score
- Документация:
  - обновить `CURRENT_HANDOFF.md`
  - обновить `RELEASE_STATE.md`
  - отметить в `GREENVPN_MASTER_PLAN.md`, что server-side health scoring для `current_wg0` добавлен

## После текущего шага

### 1. Support report: “Отправить отчет”

Цель:

- пользователь нажимает `Отправить отчет`;
- backend получает безопасный encoded report;
- admin_support_app показывает report;
- нет секретов;
- обычный пользователь не видит технические данные.

Backend:

- `POST /api/v1/support/reports`;
- storage reports;
- admin list/detail;
- report status;
- assigned_to later.

Client:

- заменить copy-first flow на send-first flow;
- fallback “скопировать код отчёта”, если сеть недоступна.

Admin:

- список reports;
- фильтр по user/device/status;
- decode/safe render;
- actions: mark reviewed, mark resolved.

### 2. Auth rewrite groundwork

Цель:

- телефон/SMS как первичный вход;
- email-code как вторичный;
- old password login не ломать резко, но постепенно увести в legacy.

Backend:

- `auth/challenge/start`;
- `auth/challenge/verify`;
- email code store;
- phone code store;
- rate limits;
- resend limits;
- expiry;
- no secrets in logs.

Client:

- стартовый экран “Телефон” + “Войти по email”;
- кодовые поля;
- понятные ошибки.

### 3. External services readiness

Цель:

- backend уже готов к SMTP/SMS/YooKassa env;
- владелец потом просто даёт env/secrets;
- включение занимает мало действий.

Сделать:

- readiness endpoint;
- env check;
- docs;
- safe setup script;
- no secrets in repo.

### 4. Admin support app v1

Цель:

- отдельная внутренняя админка;
- пользователи;
- устройства;
- support reports;
- payments/orders;
- monitoring;
- audit;
- updates.

Не добавлять это в обычный VPN-клиент.

### 5. Updater production groundwork

Цель:

- manifest;
- SHA256;
- required update;
- optional update;
- admin release view;
- no silent dangerous update until signing.

### 6. Payments production after owner data

Цель:

- YooKassa production;
- webhook;
- payment activation only after confirmation;
- cancellation auto-renew;
- admin reconciliation.

Не блокировать разработку ожиданием YooKassa secrets.

## Как брать задачи

Можно брать 2-3 задачи за раз только если:

- они из одного слоя;
- не требуют противоречивых изменений;
- не ломают пользовательский installer;
- можно проверить локально.

Нельзя брать одновременно:

- auth UI rewrite + installer service rewrite + payment backend;
- production payment secrets + public release;
- user client UI + admin app + server deploy без ясной причины.

## Что писать в конце каждого отчёта

Нужно указывать:

- что сделано;
- какие файлы изменены;
- что проверено;
- что не проверено;
- нужен ли новый installer;
- что требуется от владельца;
- прогресс по плану:
  - общий мастер-план;
  - Windows MVP;
  - monitoring/resilience;
  - auth;
  - payments;
  - admin/support.
