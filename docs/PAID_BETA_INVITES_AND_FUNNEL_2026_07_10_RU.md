# Green VPN: beta-инвайты и воронка

Дата: 2026-07-10. Статус: реализовано и проверено только локально. Production backend, production DB, основной сайт и stable-клиенты не изменены.

## Модель

- Закрытая cohort: `paid_beta_v1`.
- Персональный код по умолчанию имеет одно использование и срок 30 дней.
- Claim выдаёт идемпотентный 3-дневный Trial на 2 устройства.
- Первый оплачиваемый период по инвайту: 149 RUB за 30 дней.
- Следующий период: 299 RUB за 30 дней.
- Реклама и session timer в beta-scope выключены.
- Автопродление выключено.

## Хранение

- Открытый код формата `GREEN-XXXX-XXXX-XXXX` возвращается только в ответе на admin create.
- В SQLite хранится HMAC-SHA256, рассчитанный с `GREENVPN_PAID_BETA_INVITE_PEPPER`.
- В списках и funnel открытый код и hash не возвращаются.
- В репозитории нет рабочих кодов и значения pepper.
- Таблицы: `beta_invites`, `beta_invite_redemptions`, `beta_funnel_events`.
- `billing_orders.beta_invite_public_id` связывает скидку с первым заказом, но не раскрывается клиенту.

## API

Admin, только `billing.manage`/`billing.read`:

- `POST /api/v1/admin/paid-beta/invites/batch` - создать 1-50 кодов; открытые коды видны один раз.
- `GET /api/v1/admin/paid-beta/invites` - безопасный список без кодов и hash.
- `POST /api/v1/admin/paid-beta/invites/{invite_id}/deactivate` - запретить новые claim без отзыва уже выданного доступа.
- `GET /api/v1/admin/paid-beta/funnel` - этапы, конверсия, источники и последние события.

Beta-клиент, только точные marker/channel и bearer session:

- `POST /api/v1/paid-beta/invite/claim` - применить персональный код.
- `POST /api/v1/paid-beta/events` - разрешены только `app_open` и подтверждённое клиентом `vpn_connected`.
- `POST /api/v1/subscription/quote` с bearer - показывает 149 RUB только владельцу неиспользованного инвайта.

## Идемпотентность

- Повторный claim того же кода тем же пользователем не расходует лимит второй раз.
- Другой код после claim к аккаунту не привязывается.
- Повторное создание заказа до оплаты возвращает существующий pending order.
- Отменённый заказ освобождает персональную скидку для новой попытки.
- После активации redemption становится `converted`, поэтому продление рассчитывается по 299 RUB.
- Статус `activating` не даёт webhook и polling одновременно продлить подписку дважды.

## Funnel

Сервер фиксирует `invite_created`, `invite_claimed`, `bootstrap_allowed`, `bootstrap_denied`, `order_created`, `payment_canceled`, `payment_activated`. Beta-клиент отправляет `app_open` и `vpn_connected` только после подтверждения реального подключения.

Admin summary считает уникальных пользователей на этапах, конверсию claim -> payment, order -> payment, payment -> connection и разбивку claim/converted по `source`.

## Проверки

- 20 backend/DB-sync unit tests: OK.
- Конкурентная активация: тариф применяется один раз.
- Flutter analyze: compile-ошибок нет; остаются прежние lint warnings проекта.
- Flutter smoke test: OK.
- Локальный HTTP-contract через временный `uvicorn`: register -> admin invite -> claim -> quote 149 -> event -> funnel: OK.
- Временные тесты используют отдельную SQLite-БД и не обращаются к production.

## Ограничение двух SQLite-узлов

State sync переносит инвайты, redemptions и события по устойчивым natural keys и `updated_at`. Однако два полностью независимых SQLite-узла не могут обеспечить глобальную блокировку при строго одновременном claim одного кода до обмена состоянием.

Для закрытой beta используются персональные одноразовые коды, один код на одного человека. Primary обслуживает обычный поток, fallback нужен только при отказе primary, а интервал sync должен быть минимальным. Перед массовой выдачей кодов потребуется общий transactional storage либо единый write-authority для claim/payment.
