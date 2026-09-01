# Green VPN Windows 0.4.7: standby transition rollout

Дата фиксации: 2026-09-01 MSK.

## Итог

Windows stable обновлён до обязательного `0.4.7+4640` сначала на fallback
`176.113.81.35`, затем на primary `72.56.32.197`. Android, production backend
и paid-beta контур не изменялись. Friendly Linnet `5.129.237.163` не
использовался и не изменялся.

Точный source commit:
`7e24fc2d1ef4f41d0a3c22aac213d415f7c1d035`.

## Исправленная причина

В отклонённом `+4639` переход `applications -> full` завершался rollback.
`_disarmWindowsRuntimeFailover` отправлял отдельный `/standby/cancel`
непосредственно перед privileged `/disconnect`, хотя `/disconnect` уже сам
выполняет cancel и join standby probe под общей сериализацией. Два запроса
конкурировали за task gate, поэтому переключение могло завершиться до
disconnect.

В `+4640` непосредственные переходы передают владение cancellation следующему
privileged disconnect. Отдельный cancel сохранён только для фонового disarm.
Добавлены sanitised internal markers результата cancel, disconnect и ошибки
применения режима. Пользовательские кнопки, надписи и экран диагностики не
менялись.

Релиз также включает предыдущую защиту от ложного competitor takeover:
устаревшие Green-owned `GreenVPNTransportPreviewStandbyProbe` и
`BlueVPNDev1StandbyProbe` удаляются до проверки другого VPN и при
установке/удалении. Support report расширен локальными service/adapter/runtime
маркерами без паролей, токенов, приватных ключей и raw network identifiers.

## Точный кандидат

Build root:
`C:\BlueVPN_Builds\windows_standby_transition_20260901_v047_b4640_v1`.

| Компонент | Размер | SHA-256 |
|---|---:|---|
| `GreenVPN_Setup_0.4.7.exe` | `54060032` | `BC65E3D8B1E6060C59C48547C674877A213B527365F7063AAF4D1D007A8B5F2B` |
| `greenvpn.exe` | `149504` | `98F5A16AC81FF23EF5E67CCD2DF7AAB4F5E33442B373606A5D212ADDE0A466FF` |
| `app.so` | `7127984` | `AAD5F443B1B251669261CF57CFE9F66DA349556348A37703D4C8B29280069A5C` |
| `greenvpn_service.exe` | `119808` | `7D32E91A0F98A91C4B5D9EFB3E866FE8F0D804D05AB5FC16AECC3A962288492B` |

Installer status: `NotSigned`. Package audit: `success=true`, `66` payload
entries, `0` errors. Audit SHA-256:
`B6EA8F077A604BCC551E14602D3B59814834FE1EC42C79CDD0F566DEF6EB17FD`.

До сборки прошли Flutter analyze, `149` тестов с `15` намеренными skips,
Fusion policy tests (`14` passed, `4` skipped), PowerShell parser и release
gate с `0` warnings / `0` errors.

## Physical acceptance

Evidence root:
`C:\BlueVPN_Builds\windows_standby_transition_smoke_20260901_v047_b4640_v1`.

Runner использовал задержку `120` секунд, независимый deadman `900` секунд,
`finally` recovery и защищённый внешний профиль
`AmneziaWGTunnel$maxim_pc_full`. Повторного runner не запускалось.

Проверено:

- точная установка `0.4.7+4640` и все payload SHA/size;
- paid owner session и один foreground candidate за `16.534` секунды;
- полный data plane в режиме `full`;
- `full -> applications -> full` с согласованными UI/service/registry state;
- direct, explicit SOCKS и selected-executable fingerprints без сохранения raw
  адресов;
- selected egress отличается от direct и совпадает с dedicated London VPN;
- selected YouTube возвращает `204`, IPv6 leak не обнаружен;
- returned-full egress совпадает с исходным full VPN;
- authenticated disconnect, удаление process router и служебных маршрутов;
- финальный Amnezia/API/YouTube baseline и сохранение exact install.

Скриншоты просмотрены вручную. Full и returned-full показывают
`Защита активна`, содержат `Пауза`, `Сменить подключение`, `Диагностика` и
`Детали`, не показывают public IP, protocol или route. Selected показывает
`Выбранное защищено`. Diagnostics явно показывает `Подключение: активно`.

Main summary: `49018` bytes, SHA-256
`7D90A15A453641CC4DAF112F6A49E5187A0415FB012790CBB98D7ECD0F413566`.
Diagnostics screenshot: `60551` bytes, SHA-256
`96F50D4D23F1BAD712B4745DC7BC3BF6CB5824791CC9B7EC7BAA0EF75BB8F286`.
Final recovery: `1347` bytes, SHA-256
`B6DDCC9AF51394CAE6A2A7136C84C2F464211899A3E6BFE25566A7A6059AD0A6`.

## Production rollout

Использован только `install_windows_stable_release.sh` с `required=1` и
`min-supported-version=0.4.7`: dry-run, затем apply на каждом узле.

Rollback directories:

- fallback:
  `/root/greenvpn-windows-stable-release-backups/20260901T082551Z-ruvds-0.4.7-4640`;
- primary:
  `/root/greenvpn-windows-stable-release-backups/20260901T082837Z-timeweb-0.4.7-4640`.

Временные root-only staging directories удалены после проверки. Rollback
сохранён.

## Финальная проверка

- stable и public-product Windows manifests на обоих узлах содержат
  `0.4.7+4640`, exact SHA/size, `required=true`, rollout `100%`, minimum
  `0.4.7` и `fileReady=true`;
- Windows `0.4.6` получает HTTP `426`, `0.4.7` получает `200`, update manifest
  получает `200` на обоих доменах;
- оба публичных Windows installer совпадают с кандидатом;
- Android stable остаётся `0.4.12+2026083003` с прежними SHA/size;
- paid-beta Android/Windows и backend остаются точными прежними версиями и
  bytes;
- stable backend остаётся `0.9.165-subscription-lifecycle.2`;
- strict public verification после sync: `12/12`;
- обе production DB: `PRAGMA quick_check=ok`;
- явный DB sync на primary, затем fallback: `Result=success`,
  `ExecMainStatus=0`;
- failed units: `0` на обоих узлах.

Post-sync report:
`C:\BlueVPN_Builds\windows_standby_transition_production_verification_20260901_v047_b4640_v1\fusion-public-invariants-post-sync.json`,
`5044` bytes, SHA-256
`E317C4F4F32906F245E778501C635D766088E4B8E5C7A165C16F6076B99BE078`.

Финальный release gate после обновления publication contract: `0` warnings,
`0` errors. Log: `108481` bytes, SHA-256
`D09B39CAEA689CBA9DE5E6BBCFB7E9034F590E4FDF85EF98C942581D9C6E6E68`.

## Оставшаяся граница

Windows installer по-прежнему не подписан. Следующий отдельный релизный шаг,
не блокирующий текущую обязательную публикацию, — Authenticode code signing и
проверка SmartScreen для нового, более высокого Windows build.
