# Green VPN YooKassa Manual NPD Backend Deploy

Дата: 2026-08-27 MSK.

## Результат

На fallback `176.113.81.35`, затем на primary `72.56.32.197` развёрнут
stable backend `0.9.159-yookassa-npd-manual.2`. YooKassa снова является
выбранным провайдером, а чековый режим переключён на ручной НПД через
официальный чек ФНС из «Мой налог».

Денежный контур намеренно остаётся fail-closed. Продажи, подтверждение
оператора, выполнение возвратов и автоматические списания выключены. Клиенты,
основной сайт, stable/paid-beta manifests и download-файлы не менялись.
Friendly Linnet `5.129.237.163` не затрагивался.

## Точный пакет

| Поле | Значение |
|---|---|
| Source commit | `a955a2a0adc30f2a4b1f139c77ed574fd9e19256` |
| Release id | `public-product-backend-yookassa-npd-manual-20260827-r2` |
| Backend version | `0.9.159-yookassa-npd-manual.2` |
| Archive size | `301964` |
| Archive SHA-256 | `6098E961B783392EA9ABC7C396E4B4BF15FFB26C44CC6382EA641AB1F64D1116` |
| Contains secrets | `false` |
| Changes clients/site | `false/false` |

Локальный пакет:

`C:\BlueVPN_Builds\yookassa_npd_manual_backend_20260827_r2\public-product-backend-yookassa-npd-manual-20260827-r2.tar.gz`

## Реализованный контракт

- YooKassa подтверждает только факт оплаты; YooKassa receipt payload и
  сохранение платёжного метода в ручном НПД-режиме не используются;
- успешная оплата переводит заказ в `paid_receipt_pending`, не меняя доступ;
- admin принимает только HTTPS-ссылку на официальный чек с allowlisted host
  `lknpd.nalog.ru` и path, содержащим `/receipt/`;
- перед подтверждением backend повторно получает платёж из YooKassa и сверяет
  provider id, заказ, сумму, валюту и статус `succeeded/paid`;
- чек отправляется на email пользователя; доступ активируется только при
  delivery status `sent`;
- SMTP failure оставляет заказ и доступ fail-closed, а безопасный retry
  повторяет доставку без повторной активации;
- публичная страница чека использует случайный token, хранит только SHA-256
  token hash, отдаёт `no-store/noindex` и ведёт на официальный чек ФНС;
- публичный order status скрывает receipt URL, delivery error и provider ids;
- полный возврат сразу откатывает entitlement по снимку исходного заказа;
- возврат остаётся `refund_receipt_pending`, пока оператор не добавит
  официальный чек аннулирования и email не будет отправлен;
- автосписания в ручном НПД-режиме запрещены;
- smoke-кандидат обязан совпадать с текущим provider и точным текущим
  `taxReceipt.mode`.

## Локальные проверки

- backend discovery: `211/211` passed;
- Flutter: `138` passed, `14` platform-specific skipped;
- `flutter analyze`: no issues;
- Python, JavaScript, Bash и PowerShell parser checks: passed;
- current tracked/untracked secret scan: passed, `1236` files;
- release gate: warnings `0`, errors `0`.

## Production apply

На каждом узле архив проверен по SHA-256, затем выполнены dry-run и apply
штатного `install_public_product_backend_release.sh` с явным
`--select-yookassa-npd-manual-fail-closed`. Installer использовал production-only
DB, создал root-only backup и сохранял rollback-on-error.

Финальные rollback roots:

| Узел | Backup |
|---|---|
| fallback | `/root/greenvpn-public-product-backups/20260827T120800Z-ruvds-0.9.159-yookassa-npd-manual.2` |
| primary | `/root/greenvpn-public-product-backups/20260827T120859Z-timeweb-0.9.159-yookassa-npd-manual.2` |

Промежуточная `.1` была безопасно установлена при закрытых продажах. После
protected readiness обнаружено, что старый `yookassa_54fz` smoke мог считаться
успешным для нового режима. Исправленная `.2` была собрана из нового commit и
заменила `.1`. Её rollback-копии сохранены отдельно:

- fallback `.1`: `/root/greenvpn-public-product-backups/20260827T115733Z-ruvds-0.9.159-yookassa-npd-manual.1`;
- primary `.1`: `/root/greenvpn-public-product-backups/20260827T115950Z-timeweb-0.9.159-yookassa-npd-manual.1`.

## Admin static

На primary развёрнуты exact static files:

| Файл | SHA-256 |
|---|---|
| `index.html` | `083AACF891FC177DD1E81744108450F1CD3BC3197C68737A6AA690EB71C2B31E` |
| `app.js` | `993FFC9F285E7D2015C3E1F8B49659F5E8B5F8B87A84B49B0EDA8528C8C40DF7` |
| `styles.css` | `680AF9D1F48F8A042A0C592A987EB9077E8264EFE3C26AA7629ADD8CDB344A82` |

Admin получил действия `Добавить чек ФНС` и `Добавить аннулирование`.
`nginx -t` прошёл; внешний admin остаётся защищённым и возвращает `401` без
аутентификации. Rollback:

`/root/greenvpn-admin-static-backups/20260827T120343Z-yookassa-npd-manual-20260827-r1`.

## Production-состояние

На обоих stable-узлах:

```text
GREENVPN_PAYMENT_PROVIDER=yookassa
GREENVPN_PAID_SALES_ENABLED=0
GREENVPN_TAX_RECEIPT_MODE=yookassa_npd_manual
GREENVPN_TAX_RECEIPT_WORKFLOW_CONFIRMED=1
GREENVPN_NPD_RECEIPT_MANUAL_OPERATOR_CONFIRMED=0
GREENVPN_REFUND_WORKFLOW_CONFIRMED=0
GREENVPN_REFUND_EXECUTION_ENABLED=0
GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED=0
```

YooKassa и SMTP server-only параметры присутствуют на обоих узлах. Проверка
фиксировала только булевы признаки наличия; значения не выводились.

Primary имеет `GREENVPN_PUBLIC_PRODUCT_BILLING_PRIMARY=1`, fallback — `0`.
Оба backend service и sync timer active. После явного sync primary, затем
fallback оба запуска завершились `Result=success`, exit `0`.

Обе production DB:

```text
quick_check=ok
users=66
subscriptions=66
billing_orders=3
replication_tombstones=99
```

## Внешняя проверка

- primary и fallback stable health: `0.9.159-yookassa-npd-manual.2`;
- primary и fallback paid-beta: неизменный `0.9.154-fusion-actions.1`;
- protected payment safety:
  `productionPaymentReady=false`, `safeToRunSmoke=false`,
  `smokeCompleted=false`, `successfulSmokeCandidates=0`;
- external readiness: `10` green, `2` intentional yellow, `0` red; yellow
  соответствуют явно пропущенному server self-check и отсутствию local admin
  token в read-only запуске;
- current Android update manifest `200`, old update manifest тоже `200`;
- current primary/fallback catalog `200`, old Android catalog `426`;
- неизвестный receipt token: `404`;
- admin без аутентификации: `401`.

## Что осталось до продаж

1. Назначить реального оператора НПД, который обязуется регистрировать каждую
   оплату и каждое аннулирование в «Мой налог».
2. В контролируемом окне включить только readiness для одного реального smoke,
   не открывая массовые продажи.
3. Выполнить один небольшой реальный YooKassa-платёж владельца.
4. Зарегистрировать доход в «Мой налог», добавить официальный чек ФНС через
   admin и подтвердить получение email; только после этого доступ должен стать
   активным.
5. Выполнить полный возврат YooKassa, аннулировать доход в «Мой налог», добавить
   официальный чек аннулирования и подтвердить email и откат entitlement.
6. Зафиксировать новый successful smoke именно для
   `yookassa_npd_manual`. Только после этого отдельно включать
   `GREENVPN_PAID_SALES_ENABLED=1`.

Автоматические списания не входят в этот запуск и остаются выключенными.
