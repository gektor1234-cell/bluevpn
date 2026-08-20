# Green VPN Fusion: mandatory stable rollout

Дата фиксации: 2026-08-20 MSK.

## Итог

Владелец явно разрешил публикацию на основной сайт и обязательное обновление.
Stable production успешно переведен на Android `0.4.6+2026082001`, Windows
`0.4.6+4636` и backend `0.9.156-mandatory-update.1` сначала на fallback
`176.113.81.35`, затем на primary `72.56.32.197`.

Оба stable/public-product manifest возвращают `required=true`,
`minSupportedVersion=0.4.6`, `rolloutPercent=100` и `fileReady=true`. Запросы
старых stable-клиентов Android и Windows с версией `0.4.5` получают HTTP `426`,
текущая `0.4.6` получает HTTP `200`, а update manifest остается доступен с
HTTP `200`. `productionPublished=true`.

Source candidate: `57ec795eef371767b4cecf6cbe1561c7896fb70f`.
Physical-harness hardening: `5986975a93297feaa1faf9ac165470a8a6c7031d`.

## Exact artifacts

Build root:
`C:\BlueVPN_Builds\fusion_production_promotion_20260820_b4636_mandatory_update_v1`.

| Компонент | Размер | SHA-256 | Статус |
|---|---:|---|---|
| Android APK | `56351293` | `1D2D4015C4D1DD33E8CD31010F672AD901CBB09BE4065AF186980DF1E98F2210` | signed |
| Windows installer | `52809216` | `EAD00F9094D1749C9FB9ECFC5ADC7322E015552F66A40BDDFBD19D3DA15111DB` | `NotSigned` |
| backend bundle | `278091` | `2FAD96945FF80A35E1558537D0A3B90FA166694D867FAD4D2D9A60BD08E7C91D` | no secrets |

Windows packaged payload:

| Файл | Размер | SHA-256 |
|---|---:|---|
| `greenvpn.exe` | `149504` | `F77B99E09EF46E67EB6FFB4B9E420503A5800B3A70157DD8F5802EEB87C8A722` |
| `app.so` | `7046064` | `E0B95D5E3FC0EB24E2EB72C332280C1701AD602AFCD89E53AE98D164186032F6` |
| `greenvpn_service.exe` | `117760` | `0A97ACC9B157A9095B8D65E916E3D4C449927504B5408CA16E9E117D3CBC44F4` |

Package audit содержит `66` payload entries и `0` errors. Исходные build
manifests сохранены без изменения с `productionPublished=false`: это
неизменяемая pre-deploy provenance, а не текущий production status.

## Physical acceptance

Android exact in-place smoke:
`C:\BlueVPN_Builds\fusion_production_android_smoke_20260820_b4636_mandatory_update_v4`.
Установленные bytes совпали с APK; версия стала `0.4.6+2026082001`; API вернул
`200`, YouTube `204`, crash buffer чистый, VPN в конце отключен. Main evidence
`android-direct-release-physical.json`: `1842` bytes, SHA-256
`49D613FF1DFAA39D5D9135114A5BD490B56FED75CD87B1C5E1C9DA6BE11F50A6`.

Windows exact delayed detached smoke:
`C:\BlueVPN_Builds\fusion_production_windows_mode_smoke_20260820_b4636_mandatory_update_v3`.
Проверены exact install `0.4.6+4636`, paid owner, authoritative
`full -> applications -> full`, один foreground candidate, data-plane probe и
privileged takeover. Direct, explicit SOCKS5 и selected-executable fingerprints
получены без сохранения raw addresses. Selected egress отличался от direct,
совпал с dedicated VPN `5.129.216.42`; selected YouTube вернул `204`; IPv6 leak
не обнаружен. Returned-full egress совпал с исходным full VPN.

Diagnostics визуально показывает `Подключение: активно`. Full и returned-full
содержат `Пауза`, `Сменить подключение`, `Диагностика` и `Детали`, не раскрывая
public IP, protocol или route. Cleanup восстановил exact external Amnezia, API
`200` и YouTube `204`; metric `42739`, failsafes, Green tunnel и process-router
не остались; exact install сохранен.

Main Windows summary: `49291` bytes, SHA-256
`5D2512BE87DEA8CA68EE46C4B5A241ED4E14BB50B7F4FFE880C60C165FAABFC5`.
Diagnostics screenshot: `69799` bytes, SHA-256
`8869AC30F22348C42691E484BBED34F360B7779123F8F6ED88C5005B9C6AFD1F`.

## Production deployment

На каждом узле bundle и оба клиента были переданы в root-only staging и
повторно проверены по SHA-256. Backend, Android stable и Windows stable прошли
отдельные dry-run и apply. Применялись только
`install_public_product_backend_release.sh`,
`install_android_stable_release.sh` и `install_windows_stable_release.sh`.
Publisher, затрагивающий Android paid-beta, не использовался.

Atomic rollback directories:

| Узел | Backend | Android | Windows |
|---|---|---|---|
| fallback | `/root/greenvpn-public-product-backups/20260820T143928Z-ruvds-0.9.156-mandatory-update.1` | `/root/greenvpn-android-stable-release-backups/20260820T144430Z-ruvds-0.4.6-2026082001` | `/root/greenvpn-windows-stable-release-backups/20260820T144507Z-ruvds-0.4.6-4636` |
| primary | `/root/greenvpn-public-product-backups/20260820T144327Z-timeweb-0.9.156-mandatory-update.1` | `/root/greenvpn-android-stable-release-backups/20260820T144629Z-timeweb-0.4.6-2026082001` | `/root/greenvpn-windows-stable-release-backups/20260820T144700Z-timeweb-0.4.6-4636` |

## Final verification

- Both public health endpoints return backend
  `0.9.156-mandatory-update.1`, HTTP `200`.
- Stable and public-product Android manifests return exact build
  `2026082001`, APK SHA/size, `required=true` and minimum `0.4.6`.
- Stable and public-product Windows manifests return exact build `4636`,
  installer SHA/size, `required=true` and minimum `0.4.6`.
- Four independent public downloads from primary and fallback matched the exact
  Android and Windows bytes. Evidence root:
  `C:\BlueVPN_Builds\fusion_production_public_verification_20260820_b4636_mandatory_update_v1`.
- Machine-readable rollout summary: `production-rollout-summary.json`, `3666`
  bytes, SHA-256
  `DBF0A7D9300A957094AE400D4CE2C2F7CB20D9B7B3DCA1AF633F3B92804ABC49`.
- Both production SQLite databases return `PRAGMA quick_check=ok`; backend and
  paid-beta services are active; sync timers are active.
- Explicit post-release sync completed primary then fallback with exit `0`,
  `Result=success`, no conflicts and no errors. A final post-sync verification
  repeated exact manifests, 426/200 enforcement, hashes and database checks.
- Source validation after recording the publication: Flutter analyze clean;
  `137` Flutter tests passed with `14` intentional skips; backend `187/187`;
  release gate `0` warnings / `0` errors; public manifest audit `ok=true`;
  strict artifact/backend verification `12/12` (`8` bodies and `4` health
  checks).
- Final release-gate log:
  `C:\BlueVPN_Builds\fusion_production_promotion_20260820_b4636_mandatory_update_v1\final-release-gate.log`,
  `102028` bytes, SHA-256
  `B8F39D567892A6E042AEE26DF9CEC27D5B00C6514DAB20C18F332951633CF939`.

## Isolation and remaining limits

Paid-beta backend remains `0.9.154-fusion-actions.1`. Paid-beta Android remains
`56340949` bytes with SHA-256
`F2FF98B569C574910CEB4ED7BA18EBC33FD54013A1DD15DE808DEC69986F883D`;
paid-beta Windows remains `55497728` bytes with SHA-256
`B882DB6EEF672C21786608888431126FAFC997EC6D7C5CEADB6CA16DD0AEC4B3`.
Host-specific paid-beta manifest bytes also remained unchanged.

Windows `0.4.6+4636` is still `NotSigned`; SmartScreen/reputation warnings are a
known accepted limitation, not a hidden success claim. Paid sales, refunds,
auto-renew, advertising and forced-disconnect gates remain disabled. Friendly
Linnet `5.129.237.163` was not contacted or modified.
