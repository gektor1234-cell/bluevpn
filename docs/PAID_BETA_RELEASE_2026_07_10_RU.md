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
| Windows beta | `GreenVPN_Beta_Setup_0.3.0-paid-beta.10.exe` | 12 822 016 | `A87F527D910CF50C075518270C221F7890963A5893D7FAB2637EC60FB3A2B170` | `NotSigned` |

- Android directory: `C:\BlueVPN_Builds\paid_beta_20260710_v5`.
- Windows candidate directory: `C:\BlueVPN_Builds\paid_beta_20260711_v13`.
- Серверный bundle и оба update manifest содержат проверенную Windows `.10`; production aliases не изменены.
- Final deploy bundle: `C:\BlueVPN_Builds\paid_beta_20260711_v16\paid-beta-0.3.0-paid-beta.5-2026071005-r8.tar.gz`.
- Bundle size/SHA-256: 44 363 292 / `FDFB9EDE9573C16748FA1AEF65A6979135D5C7394B48566F3D94091BDF610E98`.
- Backend in bundle: `0.9.106-paid-beta.5`.

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
- 31 backend/DB-sync/first20 tests: OK.
- Release gate: 0 warnings, 0 errors.
- Real Samsung Android 13: login, VPN, YouTube, failover, recents lifecycle, disconnect: OK.
- Chrome active add/remove: network UID set менялся с `{Chrome, Telegram}` на `{Telegram}` без потери `tun0`.
- Public manifests/downloads на Timeweb и RUVDS совпадают с SHA.
- Stateful primary/fallback/invite/config smoke: OK; cleanup выполнен на обоих узлах.
- Windows `.3`: real EXE extraction, side-by-side identity, payload, parser, PE metadata and Defender static gates: OK.

## Сборка

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\windows\build_paid_beta.ps1 `
  -Mode android `
  -OutDir C:\BlueVPN_Builds\paid_beta_20260710_v5
```

Bundle создаётся `prepare_paid_beta_bundle.ps1 -BundleRevision 8`. Упаковщик включает installer, backend, site, monitoring, stateful smoke и first20 generator; секретов и DB в архиве нет.

## Superseded

- Android `.2`: отклонён как same-package candidate.
- Android `.3`: отклонён из-за lifecycle/disconnect ownership bug.
- Android `.4`: lifecycle исправлен, но версия заменена `.5` после добавления custom app picker.
- Server `r1-r4`: forensic only; `r5-r7` are previous rollback points, current technical release is `r8`.

## Ограничения

- Windows `.10` side-by-side isolated, не подписан, но полный real-PC installation/reboot/VPN/DNS/uninstall/network-recovery/reinstall gate пройден; серверы beta отдают `.10`.
- YooKassa key перевыпущен и проверен на обоих control-plane. Реальный платёж 149 RUB успешно активировал подписку; actual refund намеренно не выполнялся. Перед first20 остаётся owner/legal acceptance условий и privacy.
- Эти beta-файлы нельзя публиковать как production aliases.
