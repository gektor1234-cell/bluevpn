# Green VPN: платежи для НПД

Последнее обновление: 2026-08-25.

## Текущее решение

- Владелец подтвердил действующий статус плательщика НПД (самозанятый).
- Для новых продаж выбран `Robokassa` с чековым контуром «Робочеки СМЗ».
- Старый контур YooKassa остаётся в коде только для совместимости и сверки старых заказов. Новые продажи на него не переключать.
- Production-продажи, возвраты и автоматические списания остаются выключенными, пока не завершены партнёрская привязка НПД и один реальный payment/refund smoke.
- Timeweb является единственным billing-writer. RUVDS принимает read/auth трафик, но отклоняет платёжные callback и не выполняет возвраты или автосписания.

## Как проходит оплата

1. Подтверждённый email создаёт billing order со статусом `pending`.
2. Backend восстанавливает уже созданный счёт по `InvId`, если предыдущий ответ Robokassa потерялся. Повторный CreateInvoice при неопределённом результате не выполняется.
3. Новый счёт создаётся через Robokassa Invoice API с позицией услуги и данными для «Робочеков СМЗ».
4. Приложение открывает только HTTPS URL на домене Robokassa.
5. ResultURL является сигналом, а не доказательством оплаты.
6. Backend самостоятельно проверяет Invoice и OpStateExt.
7. Тариф активируется только при точной сумме, `Invoice=Paid`, `Result=0`, `State=100` и непустом `OpKey`.
8. Повторный ResultURL идемпотентен и не продлевает подписку второй раз.

Публичные URL:

```text
Return URL: https://api.greenvpn.pro/payment/return
Result URL: https://api.greenvpn.pro/api/v1/billing/robokassa/result
```

## Возврат

- Поддерживается только полный guarded refund по исходному `OpKey`.
- Password3 хранится только в root-owned server env.
- Неопределённый ответ CreateRefund никогда не повторяется автоматически: заказ переводится в ручную сверку.
- Права пользователя откатываются только после авторитетного статуса `finished`.
- В запрос передаются позиции для чека возврата «Робочеков СМЗ».
- Неизвестный статус провайдера не считается успешным возвратом.

## Server-only env

Секретные значения нельзя писать в Git, документы, owner notes или чат.

```text
GREENVPN_PAYMENT_PROVIDER=robokassa
ROBOKASSA_MERCHANT_LOGIN=<server-only>
ROBOKASSA_PASSWORD1=<server-only>
ROBOKASSA_PASSWORD2=<server-only>
ROBOKASSA_PASSWORD3=<server-only>
ROBOKASSA_RETURN_URL=https://api.greenvpn.pro/payment/return
ROBOKASSA_RESULT_URL=https://api.greenvpn.pro/api/v1/billing/robokassa/result
GREENVPN_ROBOKASSA_NPD_PARTNER_CONFIRMED=1
GREENVPN_TAX_RECEIPT_MODE=robokassa_npd
GREENVPN_TAX_RECEIPT_WORKFLOW_CONFIRMED=1
GREENVPN_TAX_RECEIPT_PAYMENT_SUBJECT=service
GREENVPN_TAX_RECEIPT_PAYMENT_MODE=full_payment
```

До реального smoke обязательно:

```text
GREENVPN_PAID_SALES_ENABLED=0
GREENVPN_REFUND_EXECUTION_ENABLED=0
GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED=0
GREENVPN_ROBOKASSA_RECURRING_ENABLED=0
```

Writer-флаги на Timeweb могут быть `1` только на соответствующем этапе. На RUVDS они всегда `0`:

```text
GREENVPN_PUBLIC_PRODUCT_BILLING_PRIMARY
GREENVPN_PAID_BETA_BILLING_PRIMARY
GREENVPN_REFUND_BILLING_PRIMARY
GREENVPN_AUTO_RENEWAL_BILLING_PRIMARY
```

Безопасный helper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\configure_backend_env_wsl.ps1 -ServerHost 72.56.32.197
```

Fallback настраивается отдельным запуском с `-ServerHost 176.113.81.35`.

## Что ещё требует внешнего действия

1. Непосредственно перед переходом подтвердить передачу ИНН и referral-данных партнёру Robokassa/оператору чеков.
2. Завершить магазин и «Робочеки СМЗ» в кабинете Robokassa.
3. Ввести MerchantLogin и Password1/2/3 через server-only helper.
4. С отдельным подтверждением провести один небольшой реальный платёж.
5. Проверить активацию, чек НПД, затем выполнить полный возврат и проверить чек возврата/откат прав.
6. Только после зелёной сверки включить продажи на primary. Автосписания остаются отдельным будущим gate.

## Проверки

```text
GET /api/v1/admin/billing/readiness
GET /api/v1/admin/billing/payment-smoke/readiness
GET /api/v1/admin/billing/refunds/readiness
GET /api/v1/admin/billing/reconciliation
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_payment_launch_safety.ps1
```

Готовность нельзя выводить только из `/healthz`: нужны provider readiness, точная DB-сверка, primary/fallback роли, реальный платёж, реальный возврат и чековый результат.

## Официальные контракты Robokassa

- Invoice API: https://docs.robokassa.ru/ru/invoice-api
- ResultURL: https://docs.robokassa.ru/ru/notifications-and-redirects
- OpStateExt: https://docs.robokassa.ru/ru/xml-interfaces
- Refund API: https://docs.robokassa.ru/ru/refund-api
- OpenAPI: https://docs.robokassa.ru/openapi/robokassa.yaml
