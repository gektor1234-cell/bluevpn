# Green VPN: ЮKassa и чеки НПД

Последнее обновление: 2026-08-27.

Это текущий платёжный контракт Green VPN. Prodamus и Robokassa остаются в
коде и старых evidence-документах только как исторические адаптеры и варианты
rollback. Новые продажи должны использовать ЮKassa и чек самозанятого из
официального сервиса ФНС «Мой налог».

## Текущий статус

- Backend-контур `0.9.159-yookassa-npd-manual.2` реализован и покрыт
  регрессионными тестами.
- Оплата сама по себе больше не активирует тариф: после подтверждения ЮKassa
  заказ получает статус `paid_receipt_pending`.
- Тариф активируется только после регистрации дохода в «Мой налог» и успешной
  отправки покупателю официальной ссылки на чек ФНС.
- Полный возврат сразу откатывает права, но остаётся в статусе
  `refund_receipt_pending`, пока чек не аннулирован в «Мой налог» и письмо не
  доставлено.
- Автопродление в ручном режиме НПД принудительно выключено.
- Публичные продажи остаются закрытыми до одного реального платежа, чека,
  полного возврата, аннулирования чека и проверки письма.

## Почему чек отправляется по email

ФНС разрешает передать чек покупателю в электронной форме на телефон или
email, показать QR-код либо распечатать. Источником чека остаётся «Мой налог»:

- https://npd.nalog.ru/
- https://npd.nalog.ru/faq/

Квитанция платёжного провайдера не заменяет налоговый чек. Backend Green VPN
не рисует собственный чек: письмо и защищённая страница содержат ссылку на
официальный чек `https://lknpd.nalog.ru/.../receipt/...`.

## Продажа

1. Backend создаёт платёж ЮKassa без объекта `receipt` и без сохранения способа
   оплаты.
2. Webhook или проверка API подтверждает точный ID заказа, сумму, валюту и
   успешный статус ЮKassa.
3. Заказ становится `paid_receipt_pending`; тариф ещё не активен.
4. Оператор регистрирует доход в «Мой налог» и получает официальную ссылку ФНС.
5. В админке оператор нажимает «Добавить чек ФНС», повторяет ID заказа, сумму и
   вставляет ссылку.
6. Backend повторно проверяет платёж в ЮKassa, принимает только HTTPS-домен
   `lknpd.nalog.ru`, сохраняет односторонний токен страницы и отправляет email.
7. Только после статуса email `sent` backend активирует тариф.

Защищённый endpoint:

```text
POST /api/v1/admin/billing/orders/{order_id}/npd-receipt-confirm
```

## Полный возврат

1. Возврат выполняется только на основном billing-узле через API ЮKassa.
2. После подтверждения полного возврата backend откатывает только права,
   созданные этим заказом, и очищает автопродление.
3. Заказ становится `refund_receipt_pending`.
4. Оператор аннулирует исходный доход в «Мой налог» и вставляет официальную
   ссылку на аннулирование через действие «Добавить аннулирование».
5. Backend повторно проверяет возврат ЮKassa, отправляет письмо и только затем
   фиксирует итоговый статус `refunded`.

Защищённый endpoint:

```text
POST /api/v1/admin/billing/orders/{order_id}/npd-refund-receipt-confirm
```

Частичные возвраты в этом контракте не используются.

## Production env

Секреты хранятся только в root-owned server env и никогда не попадают в Git,
документы или логи.

```text
GREENVPN_PAYMENT_PROVIDER=yookassa
YOOKASSA_SHOP_ID=<server-only>
YOOKASSA_SECRET_KEY=<server-only>
YOOKASSA_API_BASE=https://api.yookassa.ru/v3
YOOKASSA_RETURN_URL=https://api.greenvpn.pro/payment/return
YOOKASSA_WEBHOOK_URL=https://api.greenvpn.pro/api/v1/billing/yookassa/webhook

GREENVPN_TAX_RECEIPT_MODE=yookassa_npd_manual
GREENVPN_TAX_RECEIPT_WORKFLOW_CONFIRMED=1
GREENVPN_NPD_RECEIPT_ALLOWED_HOSTS=lknpd.nalog.ru
GREENVPN_NPD_RECEIPT_MANUAL_OPERATOR_CONFIRMED=0

GREENVPN_PAID_SALES_ENABLED=0
GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED=0
GREENVPN_AUTO_RENEWAL_BILLING_PRIMARY=0
GREENVPN_REFUND_WORKFLOW_CONFIRMED=0
GREENVPN_REFUND_EXECUTION_ENABLED=0
```

`GREENVPN_NPD_RECEIPT_MANUAL_OPERATOR_CONFIRMED=1` означает не наличие кода, а
реально назначенного человека, который обработает каждый платёж и возврат без
задержки. Этот флаг нельзя включать формально.

Primary billing-writer: `72.56.32.197`. Fallback `176.113.81.35` принимает
публичный трафик, но не создаёт платежи, не обрабатывает callback как writer,
не выполняет возвраты и автосписания.

## Контрольный платёж

1. Развернуть backend на fallback, затем на primary с флагом
   `--select-yookassa-npd-manual-fail-closed`.
2. Проверить, что продажи закрыты, provider=`yookassa`, mode=
   `yookassa_npd_manual`, SMTP готов, автосписания выключены.
3. Назначить оператора и включить только operator/refund-флаги на primary.
4. Создать один заказ на подтверждённый email и оплатить его реальной картой.
5. Проверить `paid_receipt_pending`, зарегистрировать доход в «Мой налог»,
   сохранить ссылку и убедиться, что письмо дошло, а тариф активирован.
6. Выполнить полный возврат, проверить откат прав, аннулировать доход в
   «Мой налог», отправить второе письмо и получить `refunded`.
7. Проверить reconciliation, SMTP outbox, БД, primary/fallback и отсутствие
   сохранённого способа оплаты.
8. Только после этого включить `GREENVPN_PAID_SALES_ENABLED=1` на primary.

## Проверки

```text
GET /healthz
GET /api/v1/admin/billing/readiness
GET /api/v1/admin/billing/payment-smoke/readiness
POST /api/v1/admin/billing/payment-smoke
GET /api/v1/admin/billing/refunds/readiness
GET /api/v1/admin/billing/reconciliation
```

`/healthz` или HTTP 200 сами по себе не доказывают готовность продаж. Нужна вся
цепочка: реальный платёж, чек ФНС, email, активация, полный возврат,
аннулирование чека, откат прав и чистая сверка.
