# ЮKassa и платежи

## Текущий статус

По последнему сообщению владельца, ЮKassa в кабинете теперь активна и готова к выдаче данных.

Backend пока не должен считаться payment production ready, пока на сервер не применены:

- `YOOKASSA_SHOP_ID`
- `YOOKASSA_SECRET_KEY`

`YOOKASSA_SECRET_KEY` нельзя писать в чат или docs.

## Уже готово в коде

Backend умеет:

- создавать billing order;
- создавать платеж в YooKassa, когда keys настроены;
- открывать hosted payment URL;
- принимать webhook;
- сверять order id, amount, currency;
- в production mode подтягивать платеж из YooKassa API перед активацией тарифа;
- активировать тариф только после реального подтверждения платежа.

Public URLs:

- return URL: `https://api.greenvpn.pro/payment/return`
- webhook URL: `https://api.greenvpn.pro/api/v1/billing/yookassa/webhook`

Admin readiness:

- `GET /api/v1/admin/billing/readiness`
- `GET /api/v1/admin/billing/renewals/readiness`
- `GET /api/v1/admin/launch/readiness`

## Что нужно от владельца

Нужно взять в кабинете ЮKassa:

- `shopId`
- `secretKey`

`shopId` можно сказать в чате, если удобно. `secretKey` лучше не вставлять в чат вообще.

## Безопасный способ применить

В PowerShell:

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\configure_backend_env_wsl.ps1
```

На вопрос:

```text
Configure YooKassa production payments now? [y/N]:
```

ответить:

```text
y
```

Дальше ввести:

```text
YOOKASSA_SHOP_ID: <shopId из кабинета>
YOOKASSA_SECRET_KEY: <secretKey из кабинета, не в чат>
```

Все остальные вопросы, если они уже настроены и не нужны:

```text
n
```

Скрипт отправляет значения только на сервер в:

`/etc/bluevpn/backend.env`

и не записывает секреты в репозиторий.

## Что настроить в ЮKassa

Webhook:

```text
URL: https://api.greenvpn.pro/api/v1/billing/yookassa/webhook
Events: payment.succeeded, payment.canceled
```

Return URL, если кабинет просит:

```text
https://api.greenvpn.pro/payment/return
```

Site URL для анкеты:

```text
https://api.greenvpn.pro
```

Requisites URL:

```text
https://api.greenvpn.pro/legal/requisites
```

## Проверка после применения

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json
```

Ожидаемый результат после правильного применения:

- `paymentsProductionReady=true` в `/healthz`;
- YooKassa readiness green;
- общий readiness все еще может быть red из-за API/VPN endpoint split.

## Важное

Не включать auto-renewal charges, required subscription enforcement или публичную рекламную кампанию только из-за того, что ЮKassa стала active. Сначала нужен тестовый платеж, webhook smoke и проверка активации тарифа.
