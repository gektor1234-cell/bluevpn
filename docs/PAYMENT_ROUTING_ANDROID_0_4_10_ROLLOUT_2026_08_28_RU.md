# Green VPN Android 0.4.10: payment-routing hotfix

Дата: 2026-08-28 MSK.

## Итог

Обязательная stable-версия Android `0.4.10+2026082804` опубликована на обоих
production-узлах. Backend `0.9.164-autorenew-checkout.1`, Windows
`0.4.6+4636` и paid-beta не изменялись. Канонический
`release_contract.json` отмечает production-публикацию как завершённую.

## Причина ошибки

Клиент `0.4.9` запрашивал каталог тарифов через гонку primary и fallback API.
Fallback часто отвечал первым. Он намеренно работает в read-only режиме и
корректно возвращает `paidSalesEnabled=false`, поэтому приложение показывало
`Оплата временно недоступна`, хотя primary был готов принимать платежи.

Это не был отказ YooKassa. Ошибка находилась в выборе API клиентом.

## Исправление

- Source commit: `0a47e07af795a446a1f24dffa46c8ee198cac809`.
- Каталог тарифов предпочитает primary; fallback допускается только после
  retriable-ошибки и остаётся fail-closed.
- Checkout email, quote, создание/чтение заказа и отмена автопродления идут
  только через primary billing writer.
- `test/payment_api_routing_test.dart` поднимает два локальных API и доказывает,
  что публичный платёжный путь не обращается к fallback.

## Артефакт и проверки

- APK:
  `C:\BlueVPN_Builds\android_payment_routing_release_20260828_b2026082804_v1\GreenVPN_Android_0.4.10_2026082804.apk`.
- SHA-256:
  `E12E609C38B1B05879999404E7BE0230E0111E1FB28B660EBBFF940769BACA46`.
- Размер: `56365761` bytes.
- Signer SHA-256:
  `1EA2C985890E9010AA3B76AEE676624EC45398FD86A5E40DD95C76CDFC6A0FBC`.
- Две независимые signed-сборки совпали побайтно; APK Signature Scheme v2
  verified; 16 KB compatibility passed для всех `23` native libraries.
- `flutter analyze`: no issues.
- Полный Flutter suite: `140` passed, `14` intentional platform skips.

## Физическая проверка

На устройстве `R9WT10CDC2J` выполнено in-place обновление до точных
`0.4.10+2026082804`. Экран тарифа показал активную кнопку
`Оплатить 249 ₽ за 1 месяц` (`enabled=true`, `clickable=true`). Внешний
WireGuard оставался владельцем VPN-сессии. Green VPN не переключал сеть и не
создавал платёжный заказ.

Evidence:

- `C:\BlueVPN_Builds\android_payment_routing_release_20260828_b2026082804_v1\physical-tariff.png`;
- `C:\BlueVPN_Builds\android_payment_routing_release_20260828_b2026082804_v1\physical-tariff.xml`.

## Production-публикация

Stable Android опубликован с `required=true`, rollout `100%` и
`minSupportedVersion=0.4.10`, сначала fallback, затем primary.

- Fallback backup:
  `/root/greenvpn-android-stable-release-backups/20260828T172017Z-ruvds-0.4.10-2026082804`.
- Primary backup:
  `/root/greenvpn-android-stable-release-backups/20260828T172426Z-timeweb-0.4.10-2026082804`.

Оба manifest и оба скачанных APK совпадают по версии, build, SHA-256 и размеру.
Android `0.4.9` получает HTTP `426`; `0.4.10` и update manifest получают HTTP
`200`. Primary сообщает `paidSalesEnabled=true` и `paymentsProductionReady=true`;
fallback сохраняет `false/false` и read-only поведение.

Strict invariant report прошёл `12/12`:

`C:\BlueVPN_Builds\android_payment_routing_release_20260828_b2026082804_v1\production-verification\fusion-public-invariants-defaults-final.json`

SHA-256 отчёта:
`9BA4755E46117E1C6004F8D1208EE72A772A393754D3185E0918A35D01629F1E`.
Проверка публичных manifest/download прошла `10/10`, `2/2`, `8/8`; отчёт
`public-download-manifests-final.json`, SHA-256
`43BC2748E6111E1C517FCB151D4297BF828D5AAAC41C6ACF149E2FF14E80E93B`.
Финальный release gate завершился с warnings/errors `0/0`; лог SHA-256
`19D864BD0D58B7EF1C853DFC501F02DE5E8EE5779F501492EE06CA4D88D1E118`.
Обе БД вернули `quick_check=ok`; production services и timers активны, связанных
failed units нет. Windows и paid-beta остались побайтно неизменными.

## Ограничение проверки

В этом hotfix-прогоне реальная оплата не создавалась. Уже ранее завершённый
owner-approved цикл YooKassa подтвердил оплату, официальный NPD-чек, активацию,
полный возврат, rollback доступа и чек отмены. Автоматические списания остаются
выключенными.
