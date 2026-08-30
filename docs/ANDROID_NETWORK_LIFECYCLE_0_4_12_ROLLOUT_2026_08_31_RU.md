# Green VPN Android 0.4.12: network lifecycle и mandatory rollout

Дата: 2026-08-31 MSK.

## Итог

Подписанный Android `0.4.12+2026083003` опубликован как обязательный stable
release на fallback и primary. Minimum supported version равен `0.4.12`,
rollout равен `100%`, обновление нельзя пропустить в клиенте. Backend, Windows
и paid-beta не изменялись.

## Исправление

Исходный commit:
`2856529cd3921031f1a7730d8762f1ee563c4402`.

- Native snapshot состояния VPN больше не вызывает `VpnService.prepare()` и
  не меняет системное владение VPN во время обычного status read.
- Явно полученное VPN-разрешение сохраняется, а competing/denied состояния
  сбрасывают его без скрытого повторного запроса.
- Автоматический monitor запрашивает разрешение только при отсутствии другого
  системного VPN.
- При takeover другим VPN Green VPN сначала отмечает себя неактивным, затем
  очищает собственный engine, терминально отменяет recovery и не возвращает
  себе VPN slot после отключения конкурента.
- Foreground coordinator проверяет competing VPN до и во время config, connect
  и route-probe фаз; первоначальное действие пользователя допускает явный
  takeover, автоматическое восстановление не допускает его.
- Offline start остаётся в durable waiting state, а уже подключённый VPN не
  уничтожается при временной потере underlying network.
- Защищённый route probe привязан к VPN network и не может ошибочно подтвердить
  прямой маршрут.

## Артефакт и автоматические проверки

- APK:
  `C:\BlueVPN_Builds\android_network_lifecycle_20260831_0.4.12_2026083003_v1\GreenVPN_Android_0.4.12_2026083003.apk`.
- Version: `0.4.12+2026083003`.
- Application ID: `pro.greenvpn.app`.
- Размер: `56404945` bytes.
- SHA-256:
  `1B476663062586B3BF1F90BC5A32FB617F99A3CF25455BBF8D9CAC9D250782C0`.
- Signer SHA-256:
  `1EA2C985890E9010AA3B76AEE676624EC45398FD86A5E40DD95C76CDFC6A0FBC`.
- APK Signature Scheme v2 verified.
- Все `23` native libraries совместимы с 16 KB page size.
- Android native unit tests passed.
- `flutter analyze --no-pub`: no issues.
- Flutter suite: `144` passed, `15` intentional skips.
- Release gate: warnings `0`, errors `0`.
- Final release-gate log SHA-256:
  `3E6C1EED387DE0D83AAA0E8916132EB13ACDA8B0347E2EA62A680AB713C9A93C`.

## Физическая проверка

Телефон: `SM-A530F`, Android 9, serial `5200a9245e93c461`.

Direct release evidence:
`C:\BlueVPN_Builds\android_network_lifecycle_physical_20260831_0.4.12_2026083003_v1`.

- Exact in-place upgrade и установленный `base.apk` совпали с кандидатом.
- Direct egress: `109.252.21.231`; protected egress: `88.218.250.86`.
- Production API: `200`; YouTube: `204`.
- Connect: `14486 ms`; background data-plane сохранился.
- Crash buffer чистый; финально VPN отключён.
- Report SHA-256:
  `A7B228BFC805AE7196E832708953C545823FB7EAC844D0B54A06023708BEBDDB`.

Полная lifecycle-матрица:
`C:\BlueVPN_Builds\android_network_lifecycle_acceptance_20260831_0.4.12_2026083003_v1`.

- Background-immediate connect завершился за `7855 ms`, protected egress/API/
  YouTube подтверждены.
- Offline start показал durable waiting notification, не создавал VPN до
  возврата сети и восстановился без второго нажатия за `19578 ms`.
- При потере сети подключённый VPN оставался активным на контрольных точках
  `5/10/15 s`, показывал preserved-tunnel notification и восстановил data-plane
  без второго нажатия.
- Competing probe VPN получил системный VPN slot. Green VPN зафиксировал
  `runtime_failover_disarmed reason=competing_vpn_active` и не восстановился
  автоматически после остановки конкурента.
- Wi-Fi и mobile data возвращены в исходное состояние; финально активного VPN
  нет. Состояние телефонии до и после совпадает.
- Все пять screenshots визуально проверены; offline-restored кадр корректно
  показывает `ЗАЩИЩЕНО` и `Защита активна`.
- Report SHA-256:
  `1F0214FF9194DAA543484675EEBFB8C8A9A0770E02A42D2656307F9C64420550`.

## Production-публикация

Использовался только `install_android_stable_release.sh`. Публикация выполнена
fallback-first/primary-second; на каждом узле dry-run предшествовал apply.

- Fallback rollback:
  `/root/greenvpn-android-stable-release-backups/20260830T214331Z-ruvds-0.4.12-2026083003`.
- Primary rollback:
  `/root/greenvpn-android-stable-release-backups/20260830T214542Z-timeweb-0.4.12-2026083003`.

Оба stable/public-product manifest публикуют exact version/build/SHA/size,
`required=true`, `minSupportedVersion=0.4.12` и rollout `100%`. Android
`0.4.11` получает HTTP `426`; Android `0.4.12` и update manifest получают
HTTP `200`.

До публикации и после неё strict public invariants прошли `12/12`. Stable
Windows `0.4.6+4636`, paid-beta Android/Windows и paid-beta backend остались
побайтно прежними. Evidence root:

`C:\BlueVPN_Builds\android_network_lifecycle_production_rollout_20260831_0.4.12_2026083003_v1`.

- Pre-public report SHA-256:
  `51B548262A7ACC337EF6FAD5E594B43C2CA8BF44F3F0282FDC1D0800153A668E`.
- Post-public report SHA-256:
  `1C6B9A03CF9EB56D60FE0E28A9C5CE010A06945BFCA5D1E706EBD6E9C3DAF62B`.

## Runtime после публикации

- На обоих узлах failed units: `0`; nginx config: valid.
- Stable и paid-beta databases: `PRAGMA quick_check=ok`.
- Android release rows на обоих узлах: published, required, rollout `100%`,
  minimum `0.4.12`, exact SHA/size.
- Stable Windows release rows не изменились.
- Subscription summaries совпадают: `65` active free, `1` active fixed-term,
  `1` inactive fixed-term; pending peer revocations: `0`.
- DB-sync и subscription-expiry timers включены и находятся в waiting state;
  latest service results are successful.

## Оставшиеся границы

Android network lifecycle и mandatory rollout завершены. Aggregate
`productionPublished` в `release_contract.json` остаётся `false`, потому что
unsigned Windows candidate `0.4.6+4637` не опубликован; platform-specific
`androidProductionPublished` равен `true`. Автоматические списания остаются
выключенными в manual NPD-контуре.
