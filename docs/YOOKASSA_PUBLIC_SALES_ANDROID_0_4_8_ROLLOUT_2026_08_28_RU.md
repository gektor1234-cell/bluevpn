# Green VPN: публичные ручные продажи и Android 0.4.8

Дата фиксации: 2026-08-28 MSK.

## Итог

Владелец явно разрешил production-публикацию ручных продаж и обязательное
обновление Android. Публичный billing работает только на primary
`72.56.32.197`; fallback `176.113.81.35` остаётся read-only и не создаёт
платежи. Автоматические списания выключены. Stable Android
`0.4.8+2026082802` опубликован на обоих control plane с
`required=true`, `minSupportedVersion=0.4.8` и rollout `100%`.

`productionPublished=true` в каноническом `release_contract.json`. Поле
`productionPublished=false` в immutable build manifest означает только то,
что APK был собран как pre-publication candidate до отдельного owner-approved
deploy.

## Exact source и артефакты

Exact candidate source commit:
`ab85e03585dd66b73191dd2103a037fe476b6d3a`.

| Артефакт | Version | Размер | SHA-256 |
|---|---|---:|---|
| Backend bundle | `0.9.163-yookassa-public-sales.1` | `304907` | `9E36F6610B335EC124C8662671A89247230E81C9D13E84C266399D802A4453B4` |
| Android APK | `0.4.8+2026082802` | `56362705` | `61B471ABCB0232676369FE3D59355AB4D411703E8EF408F28633279056C56DAF` |

Backend bundle:
`C:\BlueVPN_Builds\yookassa_public_sales_backend_20260828_r1\public-product-backend-yookassa-public-sales-20260828-r1.tar.gz`.

Signed APK:
`C:\BlueVPN_Builds\android_payment_release_20260828_b2026082802_manual_renewal_v1\GreenVPN_Android_0.4.8_2026082802.apk`.

APK Signature Scheme v2 verification passed. Signer certificate SHA-256:
`1EA2C985890E9010AA3B76AEE676624EC45398FD86A5E40DD95C76CDFC6A0FBC`.
The 16 KB compatibility audit passed for all packaged native libraries.

## Payment/refund acceptance

Один owner-approved контрольный платёж `249 RUB` прошёл полный ручной НПД
контур:

1. YooKassa подтвердила оплату; заказ остался без доступа до чека ФНС.
2. Доход зарегистрирован в «Мой налог», официальная ссылка на чек принята
   backend и письмо доставлено.
3. Полный возврат выполнен ровно один раз; созданные заказом права отозваны,
   `autoRenew=false`.
4. Доход аннулирован в «Мой налог», ссылка на аннулирование принята и второе
   письмо доставлено.
5. Итоговые состояния: order `refunded`, refund `succeeded`, receipt
   `cancellation_registered`, entitlement `rolled_back`, reconciliation clean.

Платёжные идентификаторы, адрес покупателя и ссылки на чеки не записаны в Git.
Второй платёж не создавался. Completed refund smoke candidates: `1`.

После acceptance primary promotion прошёл dry-run и apply. Rollback directory:
`/root/greenvpn-public-sales-backups/20260828T151043Z-enabled`.
Primary отдаёт `paidSalesEnabled=true`; fallback и paid-beta отдают `false`.
Refund execution разрешён только primary. Automatic renewal charges остаются
выключенными на всех контурах.

## Android mandatory rollout

Использовался только `install_android_stable_release.sh`; publisher, который
может изменить paid-beta, не запускался. Публикация выполнена fallback first,
primary second.

| Узел | Rollback directory |
|---|---|
| fallback | `/root/greenvpn-android-stable-release-backups/20260828T151453Z-ruvds-0.4.8-2026082802` |
| primary | `/root/greenvpn-android-stable-release-backups/20260828T151644Z-timeweb-0.4.8-2026082802` |

Final external verification:

- оба stable/public-product manifests содержат exact version/build/SHA/size,
  `required=true`, `minSupportedVersion=0.4.8`, rollout `100%` и
  `fileReady=true`;
- Android `0.4.7` получает HTTP `426`, Android `0.4.8` получает HTTP `200`,
  update manifest получает HTTP `200`;
- primary и fallback downloads повторно скачаны и совпали с exact APK SHA/size;
- stable Windows остался `0.4.6+4636`, `52809216` bytes, SHA-256
  `EAD00F9094D1749C9FB9ECFC5ADC7322E015552F66A40BDDFBD19D3DA15111DB`;
- paid-beta Android/Windows/backend остались byte-for-byte неизменными;
- обе production DB прошли `PRAGMA quick_check=ok`, sync и service/timer health.

## Physical Android acceptance

Exact APK установлен на физический Android поверх stable package
`pro.greenvpn.app`. Проверены package version `0.4.8`, build `2026082802`,
главный экран и экран тарифа. UI показывает ручное продление, а кнопка
`Оплатить 249 ₽ за 1 месяц` доступна (`clickable=true`, `enabled=true`); текста
о временной недоступности оплаты нет. Кнопка не нажималась, поэтому второй
платёж не создавался.

Внешний WireGuard оставался владельцем Android VPN до, во время и после
проверки. Green VPN не перехватывал VPN ownership и сетевой переход не
выполнялся.

Local evidence:

- `C:\BlueVPN_Builds\android_payment_release_20260828_b2026082802_manual_renewal_v1\physical-final\green-vpn-final-main.png`;
- `C:\BlueVPN_Builds\android_payment_release_20260828_b2026082802_manual_renewal_v1\physical-final\green-vpn-final-tariff.png`;
- `C:\BlueVPN_Builds\android_payment_release_20260828_b2026082802_manual_renewal_v1\physical-final\green-vpn-final-tariff.xml`.

## Validation и границы

До публикации прошли `flutter analyze`, `139` Flutter tests (`14` intentional
platform skips), `219` backend tests, policy tests, deterministic build checks,
secret scan и release gate с warnings/errors `0/0`. После записи production
metadata повторно прошли PowerShell parsers, manifest/download checker, strict
public invariant verifier `12/12`, release gate `0/0`, `flutter analyze`, все
`139` Flutter tests и все `219` backend tests. Secret scan с untracked evidence
также clean.

Strict report:
`C:\BlueVPN_Builds\android_payment_release_20260828_b2026082802_manual_renewal_v1\production-verification\fusion-public-invariants-final.json`,
`7805` bytes, SHA-256
`25B663696ADA675716492EDB504789490EE278EDF731339BEF92081E6A57D629`.

Windows client/VPN, paid-beta, advertising и Friendly Linnet
`5.129.237.163` не изменялись. Windows installer остаётся `NotSigned`; этот
rollout не меняет его SmartScreen/Authenticode статус.
