# Green VPN: Prodamus и НПД

Последнее обновление: 2026-08-26.

Этот файл является текущим платёжным контрактом. Старые разделы про Robokassa
и YooKassa в других документах считаются историческими и не используются для
новых продаж.

## Семь этапов

| № | Этап | Текущий статус |
|---:|---|---|
| 1 | Подать заявку Prodamus | Короткая заявка отправлена; расширенная анкета открыта и ожидает ввода владельцем адреса регистрации, паспортных данных и принятия условий непосредственно в кабинете |
| 2 | Получить одобрение Green VPN | Ожидается проверка и явное одобрение Prodamus; до него нельзя считать форму боевой |
| 3 | Связать Prodamus с «Мой налог» | Заблокировано до рабочего режима формы; затем ИНН подаётся в настройках Prodamus, а запрос подтверждается владельцем в «Мой налог» |
| 4 | Реализовать backend-адаптер | Реализован fail-closed адаптер, signed notification, идемпотентная активация, reconciliation и guarded full refund |
| 5 | Настроить production | Скрипты и env-контракт готовы; реальные URL/ключ/SYS не устанавливаются до одобрения и остаются только в root-owned server env |
| 6 | Реальный платёж и полный возврат | Выполняется только после этапов 2, 3 и 5: один платёж, signed notification, активация, НПД-чек, полный возврат, возвратный чек и откат прав |
| 7 | Открыть продажи | Заблокировано до зелёного этапа 6; автопродление остаётся выключенным отдельным будущим контуром |

## Границы

- Основной billing-writer только Timeweb `72.56.32.197`.
- Fallback `176.113.81.35` отклоняет платёжные callbacks до разбора тела и не
  создаёт платежи, возвраты или автосписания.
- `urlSuccess` возвращает пользователя, но не подтверждает оплату.
- Активация разрешена только после notification с валидным `Sign` и точным
  совпадением магазина, `SYS`, номера заказа, суммы и единственной позиции.
- Демо-форма и демо-подпись всегда отклоняются.
- Неопределённый результат создания ссылки не повторяется автоматически:
  заказ уходит в reconciliation, чтобы исключить повторную оплату.
- Ручная admin-активация Prodamus запрещена.
- Возврат в Prodamus выполняется через кабинет. Backend принимает подтверждение
  только после статуса «Возвращён» и наличия возвратного чека, затем одной DB-
  транзакцией фиксирует полный возврат и откатывает права, если entitlement не
  менялся после исходной активации.
- Частичный возврат в этом контракте не используется.
- Автопродление и рекуррентные платежи выключены.

## Публичные URL

```text
Return URL:        https://api.greenvpn.pro/payment/return
Success URL:       https://api.greenvpn.pro/payment/return
Notification URL: https://api.greenvpn.pro/api/v1/billing/prodamus/notification
```

## Server-only env

Секреты нельзя писать в Git, документы, owner notes или чат.

```text
GREENVPN_PAYMENT_PROVIDER=prodamus
PRODAMUS_PAYFORM_URL=https://<магазин>.payform.ru
PRODAMUS_SECRET_KEY=<server-only>
PRODAMUS_SYS=<согласованный Prodamus код>
PRODAMUS_RETURN_URL=https://api.greenvpn.pro/payment/return
PRODAMUS_SUCCESS_URL=https://api.greenvpn.pro/payment/return
PRODAMUS_NOTIFICATION_URL=https://api.greenvpn.pro/api/v1/billing/prodamus/notification
PRODAMUS_NPD_PARTNER_CONFIRMED=1
PRODAMUS_LIVE_MODE_CONFIRMED=1
GREENVPN_TAX_RECEIPT_MODE=prodamus_npd
GREENVPN_TAX_RECEIPT_WORKFLOW_CONFIRMED=1
GREENVPN_TAX_RECEIPT_PAYMENT_SUBJECT=service
GREENVPN_TAX_RECEIPT_PAYMENT_MODE=full_payment
```

До успешного payment/refund smoke:

```text
GREENVPN_PAID_SALES_ENABLED=0
PRODAMUS_REFUND_SMOKE_CONFIRMED=0
PRODAMUS_RECURRING_ENABLED=0
GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED=0
GREENVPN_AUTO_RENEWAL_BILLING_PRIMARY=0
```

Для контролируемого refund-smoke только на primary временно требуется готовая
политика возврата:

```text
GREENVPN_REFUND_WORKFLOW_CONFIRMED=1
GREENVPN_REFUND_EXECUTION_ENABLED=1
GREENVPN_REFUND_BILLING_PRIMARY=1
```

После подтверждённого полного возврата и возвратного чека:

```text
PRODAMUS_REFUND_SMOKE_CONFIRMED=1
GREENVPN_PAID_SALES_ENABLED=1
```

На fallback writer-флаги всегда `0`.

## Безопасная настройка

Primary:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\configure_backend_env_wsl.ps1 -ServerHost 72.56.32.197
```

Fallback настраивается отдельным запуском с `-ServerHost 176.113.81.35`, но
денежные writer-флаги на нём не включаются.

## Контрольный платёж и возврат

1. Убедиться, что форма в рабочем режиме и Prodamus подтверждён партнёром в
   «Мой налог».
2. Проверить `/api/v1/admin/billing/readiness` при закрытых публичных продажах.
3. Через защищённый endpoint `/api/v1/admin/billing/prodamus/payment-smoke`
   создать ровно один заказ на подтверждённого тестового пользователя.
4. Владелец самостоятельно оплачивает ссылку. Backend не вводит банковские
   данные, коды и не подтверждает списание.
5. Проверить signed notification, статус `activated`, точную сумму и чек дохода
   в НПД.
6. В кабинете Prodamus оформить полный возврат. Дождаться статуса «Возвращён» и
   возвратного чека.
7. Через защищённый endpoint
   `/api/v1/admin/billing/orders/{order_id}/prodamus-refund-confirm` передать
   точный order ID, сумму, ID возврата и ссылку/номер чека.
8. Проверить статус `refunded`, `refund_entitlement_status=rolled_back`, чек
   возврата и отсутствие сохранённого способа оплаты.
9. Только после этого включить `PRODAMUS_REFUND_SMOKE_CONFIRMED=1`, а затем
   `GREENVPN_PAID_SALES_ENABLED=1` на primary.

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

`/healthz` не доказывает готовность платежей. Нужны provider readiness,
сверка primary/fallback, реальный signed payment, чек дохода, полный возврат,
возвратный чек и откат прав.

## Официальные инструкции Prodamus

- Самостоятельная интеграция и HMAC:
  https://help.prodamus.ru/payform/integracii/rest-api/instrukcii-dlya-samostoyatelnaya-integracii-servisov
- Уведомления об оплате:
  https://help.prodamus.ru/payform/uvedomleniya/kak-ustroena-otpravka-uvedomlenii-ob-oplate
- Интеграция с «Мой налог»:
  https://help.prodamus.ru/payform/nachalo-raboty-s-prodamus/kak-samozanyatym-integrirovat-prodamus-s-prilozheniem-moi-nalog
- Полный возврат:
  https://help.prodamus.ru/payform/vozvraty-platezhei/sformirovat-zayavku-na-vozvrat
