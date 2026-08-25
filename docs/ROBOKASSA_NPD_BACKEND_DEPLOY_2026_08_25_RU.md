# Green VPN Robokassa NPD Backend Deploy

Дата: 2026-08-25 MSK.

## Результат

На fallback `176.113.81.35`, затем на primary `72.56.32.197` развёрнут
backend `0.9.157-robokassa-npd.1`. Клиентские приложения, сайт, stable и
paid-beta артефакты не менялись. Friendly Linnet `5.129.237.163` не затрагивался.

Новый backend содержит:

- Robokassa Invoice API и HTTPS-host validation;
- атомарный запрет повторного `CreateInvoice` после неоднозначного ответа;
- ResultURL с точной подписью, суммой и `InvId`;
- авторитетную активацию только после Invoice `Paid`, OpStateExt `Result=0`,
  `State=100` и непустого `OpKey`;
- позиции услуги для «Робочеков СМЗ»;
- полный guarded refund с Password3, чековой позицией и откатом прав;
- ручную сверку вместо автоматического повтора неоднозначного возврата;
- запрет payment callback и provider polling с изменением БД на fallback.

## Точный пакет

| Поле | Значение |
|---|---|
| Source commit | `5fa411a4e1157543ff57cb04aef27ffadff79785` |
| Release id | `public-product-backend-robokassa-npd-20260825-r1` |
| Backend version | `0.9.157-robokassa-npd.1` |
| Archive size | `287550` |
| Archive SHA-256 | `011C6B0E83A8AA0D29CD828892754EC63EA80E752682544B4FBF14DDD92C96A8` |
| Contains secrets | `false` |
| Changes clients/site | `false/false` |

Локальный пакет:

`C:\BlueVPN_Builds\robokassa_npd_backend_20260825_r1\public-product-backend-robokassa-npd-20260825-r1.tar.gz`

## Локальные проверки

- backend unit/discovery: `198` passed;
- Flutter: `138` passed, `14` intentionally skipped;
- `flutter analyze`: no issues;
- Python, Bash и PowerShell parser checks: passed;
- tracked secret scan: passed;
- release gate: warnings `0`, errors `0`.

## Production apply

Оба узла получили одинаковый архив и независимо проверили его SHA-256. На
каждом узле прошли dry-run и apply штатного
`install_public_product_backend_release.sh` с production-only DB, backup и
rollback-on-error.

Rollback roots:

| Узел | Backup |
|---|---|
| fallback | `/root/greenvpn-public-product-backups/20260825T165802Z-ruvds-0.9.157-robokassa-npd.1` |
| primary | `/root/greenvpn-public-product-backups/20260825T165937Z-timeweb-0.9.157-robokassa-npd.1` |

После apply:

- `bluevpn-backend.service` и `greenvpn-db-sync.timer` active;
- обе production DB: `PRAGMA quick_check=ok`;
- колонка `provider_create_attempted_at` присутствует;
- explicit sync primary, затем fallback: `Result=success`, exit `0`;
- business counts совпадают: users `66`, subscriptions `66`, billing orders
  `3`, replication tombstones `99`.

## Публичная проверка

Machine-readable report:

`C:\BlueVPN_Builds\robokassa_npd_backend_20260825_r1\public-verification.json`

Report size `7604`, SHA-256
`96EAE86E04042B0DE32B582DA27F00F6B638477104A0742504902FB38362ADA1`.

Результаты:

- strict verifier `12/12`;
- primary/fallback stable backend: `0.9.157-robokassa-npd.1`;
- paid-beta backend остался `0.9.154-fusion-actions.1`;
- stable Android остался `0.4.7+2026082401`, SHA-256
  `4BA46905702F7A42DD46F768119050FF7F36A31869A2986C0928BBC6F40E5ED2`;
- stable Windows остался `0.4.6+4636`, SHA-256
  `EAD00F9094D1749C9FB9ECFC5ADC7322E015552F66A40BDDFBD19D3DA15111DB`;
- все восемь stable/paid-beta загрузок primary/fallback совпали с manifest;
- external readiness: `12` green, `0` yellow, `0` red;
- email/auth readiness на обоих stable backend остаётся true.

## Fail-closed состояние

На обоих узлах:

- `GREENVPN_PAID_SALES_ENABLED=0`;
- `GREENVPN_REFUND_EXECUTION_ENABLED=0`;
- `GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED=0`;
- `GREENVPN_ROBOKASSA_NPD_PARTNER_CONFIRMED=0`;
- Robokassa MerchantLogin/Password1/2/3 отсутствуют;
- `paymentsProductionReady=false`.

Fallback имеет все writer-флаги `0` и возвращает
`503 billing_callback_primary_required` до разбора callback. Primary сохраняет
writer-роль, но без ключей возвращает `503 Robokassa не настроена`.

## Оставшиеся внешние gates

1. Непосредственно перед переходом подтвердить передачу ИНН и referral-данных
   партнёру Robokassa/оператору чеков.
2. Завершить Robokassa и «Робочеки СМЗ», получить MerchantLogin и
   Password1/2/3.
3. Передать значения только server-only helper; не писать их в чат или Git.
4. С отдельным подтверждением провести один небольшой реальный платёж и полный
   возврат, проверить оба чека и откат прав.
5. Только после зелёного smoke включить продажи на primary. Автосписания
   остаются отдельным будущим gate.
