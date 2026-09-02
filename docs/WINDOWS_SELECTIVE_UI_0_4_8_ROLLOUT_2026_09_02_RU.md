# Green VPN Windows 0.4.8: selective UI rollout

Дата фиксации: 2026-09-02 MSK.

## Итог

Windows stable обновлён до обязательного `0.4.8+4641` сначала на fallback
`176.113.81.35`, затем на primary `72.56.32.197`. Android, production backend
и paid-beta контур не изменялись. Friendly Linnet `5.129.237.163` не
использовался и не изменялся.

Точный source commit кандидата:
`f89317d575f86e539f207c30ac09036ec9054ac8`. Метаданные публикации:
`49a7e2e4ea680de99c70ffe52b5b02365c70caaf`. Оба commit опубликованы до
production rollout.

## Исправления

- Windows-каталог приложений объединяет классические ярлыки, App Paths,
  uninstall registrations и приложения Microsoft Store/MSIX текущего
  пользователя. Поиск работает по видимому названию, пути и package identity;
  специальных исключений для ChatGPT, Codex или других продуктов нет.
- Окно выбора локации защищено single-flight guard и не дублируется от
  повторных нажатий.
- Нажатие `Только выбранное` открывает вкладку и настройку списка, не меняя
  текущий VPN-режим. Новый режим применяется только после `Готово`, затем UI
  возвращается на главный экран.

## Точный кандидат

Build root:
`C:\BlueVPN_Builds\windows_selective_ui_20260902_v048_b4641_v1`.

| Компонент | Размер | SHA-256 |
|---|---:|---|
| `GreenVPN_Setup_0.4.8.exe` | `52839424` | `357EDA90DB1E58793385DABFACBB0C110FC6ECECF41B895F5EE343400CBF5A21` |
| `greenvpn.exe` | `149504` | `CBB4C5416F26480490831EE331508207E522957BE2860BC32B42FFB86CCE5976` |
| `app.so` | `7127984` | `1E4004ED6AAE1CF263DAF1CAB1A273D76F6CC9998153A38FA67EEB42AED15906` |
| `greenvpn_service.exe` | `119808` | `BD8AEADCDD974D6452659110ADE464D5001CA2F82A4321AF844CD370D22106ED` |
| `GreenVPN.ProxyBridge.Cli.exe` | `204288` | `6C215C7975E3CBEE086DE0EE2F3226FAE84F35A7B0A2FFD432FC346EF56A0569` |
| `GreenVPN.ProxyBridge.Core.dll` | `231424` | `B4759403D1550594A6032DA4869C6666B234B88868ED19D8A1FD38372B7349CE` |

Installer status: `NotSigned`. Package audit: `success=true`, `66` payload
entries, `0` errors. Audit SHA-256:
`386E2DF1388F45EA528E90A8BE26839B8A6B4CDB2B6BC383B0A2DF352FA8CC26`.

До публикации прошли Flutter analyze, focused tests (`12` passed), полный
production/Fusion набор (`157` passed, `8` intentional skips), package audit и
release gate с `0` warnings / `0` errors. Владелец явно попросил опубликовать
этот кандидат без нового physical GUI smoke, чтобы самостоятельно проверить
встроенное обновление. Поэтому такой smoke не заявляется как пройденный.

## Production rollout

Использован только `install_windows_stable_release.sh` с `required=1` и
`min-supported-version=0.4.8`: dry-run, затем apply на каждом узле.

Rollback directories:

- fallback:
  `/root/greenvpn-windows-stable-release-backups/20260902T131317Z-ruvds-0.4.8-4641`;
- primary:
  `/root/greenvpn-windows-stable-release-backups/20260902T131520Z-timeweb-0.4.8-4641`.

Временные root-only staging directories удалены после проверки. Rollback
сохранён.

## Финальная проверка

- stable и public-product Windows manifests на обоих узлах содержат
  `0.4.8+4641`, exact SHA/size, `required=true`, rollout `100%`, minimum
  `0.4.8` и `fileReady=true`;
- Windows `0.4.7` получает HTTP `426`, `0.4.8` получает `200`, update manifest
  получает `200` на обоих доменах;
- оба публичных Windows installer совпадают с кандидатом;
- Android stable остаётся `0.4.12+2026083003`, SHA-256
  `1B476663062586B3BF1F90BC5A32FB617F99A3CF25455BBF8D9CAC9D250782C0`,
  size `56404945`;
- paid-beta Android/Windows и оба backend остаются точными прежними версиями
  и bytes;
- stable backend остаётся `0.9.165-subscription-lifecycle.2`;
- strict public verification после sync: `12/12`;
- обе production DB: `PRAGMA quick_check=ok`;
- явный DB sync на primary, затем fallback: `Result=success`,
  `ExecMainStatus=0`;
- backend и DB-sync timers active, failed units: `0` на обоих узлах.

Evidence root:
`C:\BlueVPN_Builds\windows_selective_ui_rollout_20260902_v048_b4641_v1`.

Post-sync report: `fusion-public-invariants-post-sync.json`, `5044` bytes,
SHA-256
`44205F64A05324771507788D599A6DAE6912A7815AC86553F25E12C96FE865C0`.

Финальный release gate после обновления publication contract: `0` warnings,
`0` errors. Log: `108859` bytes, SHA-256
`AF0AFA7A8D75A7D64C8E2D239B6D67B366A7DA5180F368B20C0A77D31423D947`.

## Оставшаяся граница

Windows installer не подписан, поэтому Windows может показать предупреждение.
Результат реальной установки через встроенный updater должен быть добавлен
после проверки владельцем; серверная публикация и download-контракт уже
подтверждены.
