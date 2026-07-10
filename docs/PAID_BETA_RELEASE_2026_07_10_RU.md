# Green VPN: paid beta 0.3.0, Android release 5

Дата: 2026-07-10. Статус: развёрнуто только в изолированном beta-контуре. Production API/DB/site/downloads/update manifests не заменены.

## Контур

- Channel/client marker: `paid-beta` / `green-vpn-paid-beta-v1`.
- Android app marker: `0.3.0-paid-beta.5`.
- Primary/fallback API: `https://api.greenvpn.pro/paid-beta-api`, `https://176-113-81-35.sslip.io/paid-beta-api`.
- Rewarded ads/session timer/auto-renew: disabled.
- Paid-beta build: `true`; trial-only build: `false`.

## Артефакты

| Платформа | Файл | Размер | SHA-256 | Подпись |
| --- | --- | ---: | --- | --- |
| Android | `GreenVPN_Android_0.3.0-paid-beta.5_2026071005.apk` | 65 756 723 | `90E42FB6CE5A06247E620E5DC3302B7C7C86A0F9A8FEBDC523876A622B9C6580` | APK v2, Green VPN |
| Windows | `GreenVPN_Setup_0.3.0-paid-beta.2.exe` | 12 827 136 | `41F96CB95118507AACA861721F83B2972CF419E2F10BA2FCF38CB73800988332` | `NotSigned` |

- Android directory: `C:\BlueVPN_Builds\paid_beta_20260710_v5`.
- Windows source directory: `C:\BlueVPN_Builds\paid_beta_20260710_v2`.
- Final deploy bundle: `C:\BlueVPN_Builds\paid_beta_20260710_v5\paid-beta-0.3.0-paid-beta.5-2026071005-r5.tar.gz`.
- Bundle size/SHA-256: 44 367 657 / `5955F5A884A7E847A09F9DA43A226F6A78603107EDEDFA0E17C5D1EA2337AF07`.
- Backend in bundle: `0.9.106-paid-beta.4`.

## Android identity

- Package: `pro.greenvpn.app.beta`.
- Label: `Green VPN Beta`.
- `versionName`: `0.3.0`; `versionCode`: `2026071005`.
- Signer SHA-256: `1ea2c985890e9010aa3b76aee676624ec45398fd86a5e40dd95c76cdfc6a0fbc`.
- Stable package `pro.greenvpn.app` remains independently installed.

## Изменения Android `.5`

- Системный список launchable Android apps через MethodChannel.
- Поиск и отдельная кнопка добавления произвольного приложения.
- Persisted custom package allowlist для режима «Только для соц. сетей».
- Не выбранные Chrome, Avito, MAX, банки и другие приложения идут напрямую.
- Исправлено active reconfigure: нативный цикл ждёт исчезновения старой VPN-сети перед поднятием нового `tun0`.
- Сохранены process-scoped backend/tunnel и корректное состояние после swipe из recents.

## Проверки

- Flutter test и Android release build: OK.
- APK signature/badging: OK.
- 28 backend tests: OK.
- Release gate: 0 warnings, 0 errors.
- Real Samsung Android 13: login, VPN, YouTube, failover, recents lifecycle, disconnect: OK.
- Chrome active add/remove: network UID set менялся с `{Chrome, Telegram}` на `{Telegram}` без потери `tun0`.
- Public manifests/downloads на Timeweb и RUVDS совпадают с SHA.
- Stateful primary/fallback/invite/config smoke: OK; cleanup выполнен на обоих узлах.

## Сборка

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\windows\build_paid_beta.ps1 `
  -Mode android `
  -OutDir C:\BlueVPN_Builds\paid_beta_20260710_v5
```

Bundle создаётся `prepare_paid_beta_bundle.ps1 -BundleRevision 5`. Упаковщик включает installer, backend, site, monitoring, stateful smoke и first20 generator; секретов и DB в архиве нет.

## Superseded

- Android `.2`: отклонён как same-package candidate.
- Android `.3`: отклонён из-за lifecycle/disconnect ownership bug.
- Android `.4`: lifecycle исправлен, но версия заменена `.5` после добавления custom app picker.
- Server `r1-r4`: forensic only; current/approved is `r5`.

## Ограничения

- Windows `.2` не side-by-side isolated, не подписан и ждёт owner installation smoke.
- Реальный платёж и legal acceptance остаются owner gate.
- Эти beta-файлы нельзя публиковать как production aliases.
