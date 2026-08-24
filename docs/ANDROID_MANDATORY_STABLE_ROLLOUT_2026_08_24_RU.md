# Green VPN Android: mandatory stable rollout

Дата фиксации: 2026-08-24 MSK.

## Итог

Владелец явно разрешил полную публикацию Android `0.4.7+2026082401` с
обязательным обновлением. Exact signed APK опубликован сначала на fallback
`176.113.81.35`, затем на primary `72.56.32.197`. Stable и public-product
manifest на обоих production control planes возвращают `required=true`,
`minSupportedVersion=0.4.7`, `rolloutPercent=100` и `fileReady=true`.

Старый Android stable `0.4.6` получает HTTP `426`, текущий `0.4.7` получает
HTTP `200`, update manifest остаётся доступен с HTTP `200`.
`productionPublished=true`.

## Exact artifact

| Поле | Значение |
|---|---|
| Version | `0.4.7+2026082401` |
| Application ID | `pro.greenvpn.app` |
| Размер | `56362397` bytes |
| SHA-256 | `4BA46905702F7A42DD46F768119050FF7F36A31869A2986C0928BBC6F40E5ED2` |
| Подпись | release signed |
| Signer SHA-256 | `1EA2C985890E9010AA3B76AEE676624EC45398FD86A5E40DD95C76CDFC6A0FBC` |

Immutable source artifact:
`C:\BlueVPN_Builds\android_regression_candidate_20260824_v4\GreenVPN_Android_0.4.7_2026082401.apk`.

Source fix: `be72d1325a568fe56cb4d10ecff03c823e5b780e`.
Acceptance evidence/harness: `8a1b010e3872351169a8e6a5cbd124f20ca2567c`.
Полное pre-publication physical acceptance описано в
`ANDROID_RUNTIME_REGRESSION_ACCEPTANCE_2026_08_24_RU.md`.

## Deployment и rollback

На каждом control plane APK и `install_android_stable_release.sh` были
переданы в отдельный root-only staging, повторно проверены по размеру и SHA,
затем publisher прошёл dry-run и apply. Использовался только Android
stable-only publisher; publisher, затрагивающий paid-beta, не запускался.

| Узел | Rollback directory |
|---|---|
| fallback | `/root/greenvpn-android-stable-release-backups/20260824T174755Z-ruvds-0.4.7-2026082401` |
| primary | `/root/greenvpn-android-stable-release-backups/20260824T175102Z-timeweb-0.4.7-2026082401` |

После завершения временные staging directories удалены; rollback directories
сохранены.

## Final verification

- Stable и public-product Android manifests на обоих узлах совпадают по
  version/build/SHA/size и обязательной политике.
- Primary и fallback публично отдают exact APK bytes.
- Повторное скачивание всех восьми production/paid-beta Android/Windows
  артефактов прошло `8/8` по SHA-256.
- Обе production SQLite базы имеют `PRAGMA quick_check=ok`; опубликованные
  Android и Windows release rows идентичны на обоих узлах.
- Явный sync выполнен primary, затем fallback: exit `0`, `Result=success`.
- Production backend, paid-beta backend, DB sync timers и service-probe timers
  активны на обоих control planes.
- Strict public invariant verifier прошёл `12/12`: `8` artifact bodies и `4`
  backend checks. Report `fusion-public-invariants.json`: `7613` bytes,
  SHA-256 `2B08C8D4A84943D150E80FB8D3A14FFA4F6AEC418B941D496634C6213DDF4F98`.
- Source validation после записи production state: `flutter analyze` clean,
  `138` Flutter tests passed (`14` intentional skips), PowerShell parsers clean,
  release gate `0` warnings / `0` errors. Gate log: `102233` bytes, SHA-256
  `1717D62D9BE2F58CD52CD1BC5728BCCAF5984CD9FFF66AA15A4E682681A488CF`.
- Windows stable остался `0.4.6+4636`, SHA-256
  `EAD00F9094D1749C9FB9ECFC5ADC7322E015552F66A40BDDFBD19D3DA15111DB`.
- Paid-beta Android и Windows остались byte-for-byte неизменными.

Evidence root:
`C:\BlueVPN_Builds\android_production_rollout_20260824_v1`.
Machine-readable summary: `production-rollout-summary.json`, `3120` bytes,
SHA-256 `196D85234380CCB6480531CF1AC2C941D15A063CDB5FF6FF99178971AB718B66`.

## Границы

Backend code/runtime version, Windows client, paid-beta, billing, advertising и
VPN data-plane configuration не менялись. Friendly Linnet `5.129.237.163` не
контактировался и не изменялся. Windows по-прежнему `NotSigned`; успешная
Android публикация не меняет его Authenticode/SmartScreen статус.
