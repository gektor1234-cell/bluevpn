# Green VPN Prodamus NPD Backend Deploy

Дата: 2026-08-26 MSK.

## Результат

На fallback `176.113.81.35`, затем на primary `72.56.32.197` развёрнут
backend `0.9.158-prodamus-npd.2`. Prodamus выбран production-провайдером, но
весь денежный контур намеренно оставлен fail-closed: ключей и боевой формы ещё
нет, продажи, чеки, возвраты и автосписания выключены.

Клиентские приложения, основной сайт, stable/paid-beta manifests и download-
файлы не менялись. Friendly Linnet `5.129.237.163` не затрагивался.

## Точный пакет

| Поле | Значение |
|---|---|
| Source commit | `445dd15967c57a879fc9bc91a61509a69b7ecec8` |
| Release id | `public-product-backend-prodamus-npd-20260826-r2` |
| Backend version | `0.9.158-prodamus-npd.2` |
| Archive size | `295414` |
| Archive SHA-256 | `8531A35742698233498FE27977BC4FFA8A2AA8AFA60ABB269B59C9D193C8EB77` |
| Manifest files | `8/8` exact |
| Contains secrets | `false` |
| Changes clients/site | `false/false` |

Локальный пакет:

`C:\BlueVPN_Builds\prodamus_npd_backend_20260826_r2\public-product-backend-prodamus-npd-20260826-r2.tar.gz`

## Реализованный контракт

- одноразовое создание подписанной Prodamus payment-link без автоматического
  повтора неоднозначного запроса;
- run-scope reconciliation для ссылки, которая могла быть создана, но не была
  получена клиентом;
- HMAC-SHA256 с рекурсивной сортировкой payload и отдельной проверкой demo;
- активация только по точному signed notification с совпадением заказа, суммы,
  валюты, магазина, `SYS` и единственной позиции услуги;
- идемпотентная повторная доставка notification;
- запрет ручной admin-активации Prodamus;
- guarded полный возврат после ручной проверки статуса и возвратного чека в
  кабинете Prodamus;
- атомарная фиксация возврата, очистка платёжного метода и откат entitlement,
  если права не менялись после исходной оплаты;
- отдельный provider-smoke, который не переиспользует pending-заказ другого
  провайдера и не открывает публичные продажи;
- smoke-evidence распознаёт только Prodamus-активацию с НПД-статусом
  `submitted_by_prodamus_npd` и без автопродления.

## Локальные проверки

- backend tests: `207/207` passed;
- Flutter tests: `138` passed, `14` intentionally skipped;
- `flutter analyze`: no issues;
- Python, Bash и PowerShell parser checks: passed;
- release gate: warnings `0`, errors `0`;
- current tracked/untracked secret scan: passed, `1236` files;
- полный history-scan отдельно показывает только два старых совпадения одного
  и того же известного test-fixture `expired/renewed guest token` в историческом
  `test/auth_ui_test.dart`; production credentials там нет, история не
  переписывалась.

## Production apply

На обоих узлах архив проверен по SHA-256, затем выполнены dry-run и apply
штатного `install_public_product_backend_release.sh` с явным
`--select-prodamus-fail-closed`. Installer создал root-only backup и сохранил
автоматический rollback-on-error.

| Узел | Финальный rollback |
|---|---|
| fallback | `/root/greenvpn-public-product-backups/20260826T073613Z-ruvds-0.9.158-prodamus-npd.2` |
| primary | `/root/greenvpn-public-product-backups/20260826T073715Z-timeweb-0.9.158-prodamus-npd.2` |

Промежуточный `.1` был безопасно развёрнут и затем заменён `.2`, который
исправляет только точное Prodamus smoke-evidence и текст диагностического
контракта. Его rollback-копии также сохранены на обоих узлах.

После финального apply:

- `bluevpn-backend.service` и `greenvpn-db-sync.timer` active;
- обе production DB: `PRAGMA quick_check=ok`;
- schema содержит `refund_receipt_provider_id`;
- explicit sync primary, затем fallback: `Result=success`, exit `0`;
- business counts совпадают: users `66`, subscriptions `66`, billing orders
  `3`, replication tombstones `99`.

## Fail-closed состояние

На обоих узлах:

```text
GREENVPN_PAYMENT_PROVIDER=prodamus
GREENVPN_PAID_SALES_ENABLED=0
PRODAMUS_NPD_PARTNER_CONFIRMED=0
PRODAMUS_LIVE_MODE_CONFIRMED=0
PRODAMUS_REFUND_SMOKE_CONFIRMED=0
PRODAMUS_RECURRING_ENABLED=0
GREENVPN_TAX_RECEIPT_MODE=disabled
GREENVPN_TAX_RECEIPT_WORKFLOW_CONFIRMED=0
GREENVPN_REFUND_WORKFLOW_CONFIRMED=0
GREENVPN_REFUND_EXECUTION_ENABLED=0
GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED=0
```

`PRODAMUS_PAYFORM_URL`, `PRODAMUS_SYS` и `PRODAMUS_SECRET_KEY` отсутствуют.
Primary возвращает `503` до разбора неподготовленного Prodamus callback.
Fallback возвращает `billing_callback_primary_required` до разбора тела и не
может изменять денежное состояние.

Защищённый readiness на primary подтверждает:

- provider `prodamus`;
- `billing_production_ready=false`;
- `smoke_safe=false`, `smoke_completed=false`;
- точный activation source: HMAC-signed Prodamus notification;
- `email_production_ready=true`.

## Публичная проверка

Machine-readable report:

`C:\BlueVPN_Builds\prodamus_npd_backend_20260826_r2\public-verification.json`

Report size `7601`, SHA-256
`A8493F21AC7B4B1D1F844E0ADCCB8546EFC9B0841DF42ECDB0F1271FA6EA8F06`.

Результаты:

- strict verifier `12/12`;
- primary/fallback stable backend: `0.9.158-prodamus-npd.2`;
- paid-beta backend остался `0.9.154-fusion-actions.1`;
- stable Android остался `0.4.7+2026082401`, SHA-256
  `4BA46905702F7A42DD46F768119050FF7F36A31869A2986C0928BBC6F40E5ED2`;
- stable Windows остался `0.4.6+4636`, SHA-256
  `EAD00F9094D1749C9FB9ECFC5ADC7322E015552F66A40BDDFBD19D3DA15111DB`;
- все восемь stable/paid-beta downloads на primary/fallback совпали с
  manifest по размеру и SHA-256;
- платные продажи выключены на всех четырёх backend-поверхностях.

## Семь этапов: фактический остаток

| № | Этап | Статус после этого deploy |
|---:|---|---|
| 1 | Заявка Prodamus | Короткая заявка отправлена; расширенная анкета на шаге 1 ожидает персональные данные и обязательные согласия владельца |
| 2 | Одобрение Green VPN | Ожидается после полной анкеты; не подменяется технической готовностью |
| 3 | Связка с «Мой налог» | Выполняется после выдачи рабочей формы; подтверждение партнёра делает владелец в НПД |
| 4 | Backend-адаптер | Реализован, протестирован и развёрнут на обоих production-узлах |
| 5 | Production-конфигурация | Prodamus выбран fail-closed; ключи/форма/SYS будут внесены только после одобрения |
| 6 | Платёж + чек + полный возврат | Заблокирован этапами 2, 3 и боевыми ключами; требует отдельного реального списания владельца |
| 7 | Продажи | Не включены; включаются только после полного пункта 6; автопродление остаётся отдельным gate |
