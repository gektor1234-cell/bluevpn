# Green VPN Payments RU MVP

Цель: пользователь выбирает тариф в Green VPN, оплачивает его российским способом оплаты, а сервер сам активирует подписку и при необходимости продлевает её.

## MVP сейчас

- Клиент создаёт заказ через `/api/v1/billing/orders`.
- Заказ получает статус `pending`.
- Если ЮKassa не настроена, backend остаётся в ручном MVP-режиме.
- Если ЮKassa настроена, backend создаёт платёж и возвращает `paymentUrl`.
- Webhook активирует тариф только после проверки order metadata, payment id, суммы и валюты.
- В production-режиме webhook не доверяет входящему телу на слово: backend берёт `payment_id` из webhook и сам запрашивает платёж у ЮKassa API.

- Admin reconciliation показывает paid-not-activated, stale pending и другие несостыковки до того, как пользователь напишет в поддержку.

## Целевая схема

1. Пользователь выбирает тариф и опцию `Автопродление`.
2. Backend создаёт order в BlueVPN DB.
3. Backend создаёт платёж у провайдера, например ЮKassa.
4. Приложение открывает платёжную ссылку или встроенный checkout.
5. Провайдер отправляет webhook на backend.
6. Backend получает webhook как сигнал, затем запрашивает актуальный платёж у ЮKassa API по `payment_id`.
7. Если платёж успешен, backend активирует тариф.
8. Если `autoRenew=true`, backend сохраняет только provider payment method id, а не данные карты.
9. Планировщик backend заранее создаёт следующий платёж и продлевает подписку после успешного webhook.

После оплаты ЮKassa может вернуть пользователя на:

```text
https://api.greenvpn.pro/payment/return
```

Эта страница уже есть в backend. Она не активирует тариф сама, а только объясняет пользователю, что можно вернуться в Green VPN. Активация всё равно идёт через webhook и проверку payment id.

Клиент Green VPN автоматически проверяет pending-заказ после создания/открытия оплаты. Кнопка `Проверить оплату` остаётся запасным ручным действием.

## ЮKassa env

На сервере нужно задать:

```bash
YOOKASSA_SHOP_ID=...
YOOKASSA_SECRET_KEY=...
GREENVPN_PUBLIC_BASE_URL=https://api.greenvpn.pro
YOOKASSA_RETURN_URL=https://api.greenvpn.pro/payment/return
YOOKASSA_WEBHOOK_URL=https://api.greenvpn.pro/api/v1/billing/yookassa/webhook
```

Secrets вводить только через:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\configure_backend_env_wsl.ps1
```

Если `YOOKASSA_SHOP_ID` или `YOOKASSA_SECRET_KEY` не заданы, Green VPN автоматически остаётся в ручном MVP-режиме: заказ создаётся, но `paymentUrl` пустой, а тариф активируется кнопкой `Оплата получена` в админке.

Webhook URL для ЮKassa:

```text
https://api.greenvpn.pro/api/v1/billing/yookassa/webhook
```

Проверка готовности production-платежей:

```text
GET /api/v1/admin/billing/readiness
```

Проверка расхождений заказов/активаций:

```text
GET /api/v1/admin/billing/reconciliation
```

Проверка готовности minimal production smoke:

```text
GET /api/v1/admin/billing/payment-smoke/readiness
```

Этот endpoint не выводит секреты провайдера. Он показывает issue counts, attention orders и policy ручной активации. `failed` / `canceled` / `cancelled` order нельзя активировать через обычный `mark-paid`; нужно создать новый order или принять отдельное owner/admin решение.

Backend `0.9.65` also makes auto-renewal and subscription expiry safe-enable signals depend on clean payment smoke:

```text
GET /api/v1/admin/billing/renewals/readiness
GET /api/v1/admin/subscriptions/expiry-readiness
```

Even after production YooKassa keys are configured, these endpoints must stay unsafe until `/api/v1/admin/billing/payment-smoke/readiness` confirms provider-backed activation.

Backend `0.9.66` adds a sanitized local helper for the combined check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_payment_launch_safety.ps1
```

`/healthz` также отдаёт `paymentsProductionReady`. Это `true` только когда заданы ключи ЮKassa, production HTTPS return URL, webhook URL/public base URL и HTTPS YooKassa API base.

## Рекомендуемый порядок

1. Оставить ручное подтверждение как fallback для тестов.
2. Подключить ЮKassa как основной российский provider.
3. Добавить таблицу `payment_methods` для provider ids.
4. Добавить endpoint webhook `/api/v1/billing/yookassa/webhook`.
5. Добавить фоновый renew job для подписок, истекающих в ближайшие сутки.
6. Добавить реальный домен + HTTPS.
7. Зарегистрировать webhook URL в ЮKassa.
8. Проверить реальный `payment.succeeded` webhook на тестовом платеже.

## Важно по безопасности

- Не хранить номера карт, CVV и банковские данные в BlueVPN.
- Хранить только `provider`, `providerPaymentId`, `providerPaymentMethodId`, статус и сумму.
- Webhook должен быть идемпотентным: повторный webhook не должен повторно продлевать тариф.
- В production-режиме не активировать тариф только по входящему webhook JSON; обязательно сверяться с ЮKassa API по `payment_id`.
- Любое автопродление должно быть выключаемым пользователем.
