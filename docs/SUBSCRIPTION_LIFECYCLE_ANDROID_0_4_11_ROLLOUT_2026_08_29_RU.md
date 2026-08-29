# Green VPN Android 0.4.11: строгий жизненный цикл подписки

Дата: 2026-08-29 MSK.

## Итог

Обязательная stable-версия Android `0.4.11+2026082901` опубликована на обоих
production-узлах. Backend `0.9.165-subscription-lifecycle.2` уже работает на
fallback и primary. Stable Windows остаётся `0.4.6+4636`; Windows candidate
`0.4.6+4637` не опубликован и не подписан. Paid-beta не изменялся.

## Исправление

Исходный commit: `50691989c6c2a2abe53b38ff4cb7d1e51eb87584`.

- Backend остаётся единственным источником истины по началу и окончанию платного
  доступа.
- Повторная покупка во время активного периода является продлением и начинается
  с текущего `expiresAt`.
- После email-входа клиент сбрасывает гостевой quote и запрашивает новый расчёт
  уже с восстановленной paid-сессией.
- Устаревший guest/purchase quote не может включить кнопку оплаты для активной
  подписки; CTA становится доступен только для точного extension quote.
- Экран тарифа показывает текущий оплаченный период и точные даты следующего
  периода до подтверждения продления.
- Серверный expiry timer логически и физически завершает истёкшие права, ведёт
  историю и повторяет незавершённый отзыв peer без продления доступа.
- Admin API, web и PowerShell helper поддерживают историю, выдачу и отзыв
  подписки с обязательной причиной.

Автоматические списания остаются выключенными. Текущий manual NPD-контур не
выдаёт `autoRenew=true`; этот rollout не создавал платёж и не выполнял списание.

## Артефакт и проверки

- APK:
  `C:\BlueVPN_Builds\subscription_lifecycle_20260829_android_stable_v3\GreenVPN_Android_0.4.11_2026082901.apk`.
- SHA-256:
  `2E32B2807BDD3C2F4168C56140B535F383BB1F463F6E82F2FEF705F5C01BBB13`.
- Размер: `56371965` bytes.
- Signer SHA-256:
  `1EA2C985890E9010AA3B76AEE676624EC45398FD86A5E40DD95C76CDFC6A0FBC`.
- Независимая сборка в root `_v4` совпала побайтно.
- APK Signature Scheme v2 verified; 16 KB compatibility passed для всех `23`
  native libraries.
- `flutter analyze`: no issues.
- Default Flutter suite: `141` passed, `15` intentional skips.
- Fusion production UI suite: `14` passed, `4` intentional skips.
- Отдельная public-product auto-renew/lifecycle регрессия passed.
- Release gate: warnings `0`, errors `0`.

## Физическая проверка

На физическом `SM-A530F` выполнены два раздельных сценария без создания заказа и
без сетевого перехода Green VPN.

Paid-сессия в side-by-side package показала:

- текущий тариф `Green VPN — 1 месяц • 249 ₽ за период`;
- оплаченный доступ `12.05.2026` - `09.09.2026`;
- следующий период `09.09.2026` - `09.10.2026`;
- CTA `Продлить 1 месяц за 249 ₽`.

Evidence:
`C:\BlueVPN_Builds\subscription_lifecycle_20260829_android_side_by_side_v2`.

Production package после in-place установки сохранил free-сессию и показал:

- статус `Бесплатный`;
- новый оплачиваемый период `29.08.2026` - `28.09.2026`;
- CTA `Оплатить 1 месяц за 249 ₽`.

Evidence:
`C:\BlueVPN_Builds\subscription_lifecycle_20260829_android_stable_v3`.

Установленный `base.apk` совпал с кандидатом. Финально на телефоне остался только
`pro.greenvpn.app` версии `0.4.11+2026082901`; временный side-by-side package
удалён, активного VPN-интерфейса нет.

## Production-публикация

Публикация выполнена только через `install_android_stable_release.sh`, сначала
fallback `176.113.81.35`, затем primary `72.56.32.197`, с dry-run перед apply.

- Fallback rollback:
  `/root/greenvpn-android-stable-release-backups/20260829T041956Z-ruvds-0.4.11-2026082901`.
- Primary rollback:
  `/root/greenvpn-android-stable-release-backups/20260829T042133Z-timeweb-0.4.11-2026082901`.

Оба stable/public-product manifest имеют `required=true`, rollout `100%` и
`minSupportedVersion=0.4.11`. Android `0.4.10` получает HTTP `426`, Android
`0.4.11` и update manifest получают HTTP `200`. Оба скачанных APK имеют точные
SHA-256 и размер кандидата.

Strict public invariants прошли `12/12`. Stable Windows, оба paid-beta клиента и
paid-beta backend остались точными прежними артефактами. Report:

`C:\BlueVPN_Builds\subscription_lifecycle_20260829_production_verification_v1\fusion-public-invariants-final.json`

SHA-256 report:
`C879C1CBC817D173CD780CA1D01A4C8B7D70B1E57402BEB05402B3B6982EE6C9`.

Канонический release gate теперь различает платформенные publication flags:
Android может быть опубликован при оставшемся за owner gate Windows candidate,
но aggregate `productionPublished` не становится true до публикации обеих
платформ. Финальный gate: warnings `0`, errors `0`; log SHA-256
`6D21A787AEA0DABAA613867B19EE73C3A18A442F24623353006F34B6B27044E8`.

## Runtime после публикации

- На обоих узлах failed units: `0`; nginx config: `ok`.
- Stable и paid-beta БД: `PRAGMA quick_check=ok`.
- Secret-safe lifecycle summaries primary/fallback совпали побайтно, SHA-256
  `B0636604055580D0427D86A8427DB27744738505D7665624F22F6B8E7AFBB1C9`.
- Stable БД: `67` subscriptions, из них `65` active `free_quota`, `1` active
  expiring `green_30d`, `1` inactive expiring `green_30d`; pending peer
  revocations: `0`.
- `greenvpn-subscription-expiry.timer` и `greenvpn-db-sync.timer` включены и
  ожидают следующий запуск на обоих узлах; последние services завершились с
  `Result=success`, `ExecMainStatus=0`.
- Последний expiry run на каждом узле: `candidates=0 changed=0 peer_failed=0`.
- Временные staging и audit-файлы удалены; rollback-каталоги сохранены.

Полный secret-safe evidence root:
`C:\BlueVPN_Builds\subscription_lifecycle_20260829_production_verification_v1`.

## Оставшиеся границы

Этот rollout завершает Android lifecycle и обязательное stable-обновление. Он
не включает автоматические списания и не публикует unsigned Windows candidate
`0.4.6+4637`. Реальный платёж требует отдельного action-time подтверждения и не
нужен для доказательства исправленного UI/lifecycle.
