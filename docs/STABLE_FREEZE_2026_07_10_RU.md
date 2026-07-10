# Green VPN: stable freeze перед paid beta

Дата проверки: 2026-07-10. Этот freeze фиксирует существующий production stable Trial. Он не включает платный beta-функционал и не разрешает его публикацию в production.

## Точка восстановления

- Git tag: `greenvpn-stable-pre-paid-beta-20260710`.
- Ветка разработки beta: `green-vpn-paid-beta-20260710`.
- Локальный checkpoint: `C:\Users\gekto\GreenVPN_Checkpoints\pre_paid_beta_20260710_103722`.
- Полный Git bundle внутри checkpoint: `git-history.bundle`.
- Патч исходного dirty tree внутри checkpoint: `working-tree.patch`.
- Серверный root-only snapshot на каждом доступном узле: `/root/greenvpn-pre-paid-beta-20260710T103821`.

Серверный snapshot создан на `72.56.32.197`, `176.113.81.35`, `88.218.250.86`, `37.220.85.211` и `5.129.216.42`. Секреты не переносились в Git и не перечисляются в этом документе.

## Production-артефакты

| Платформа | Версия | Размер | SHA-256 |
| --- | --- | ---: | --- |
| Android | `0.2.44+2026070504` | 65 543 311 | `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F` |
| Windows | `0.2.39-windows-clean-server-ui` | 12 814 336 | `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15` |

Локальные эталоны:

- `C:\BlueVPN_Builds\GreenVPN_Android_0.2.44_2026070504_stable.apk`
- `C:\BlueVPN_Builds\GreenVPN_Setup.exe`
- `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`

Public downloads:

- `https://greenvpn.pro/downloads/GreenVPN_Android.apk`
- `https://greenvpn.pro/downloads/GreenVPN_Setup.exe`

## Проверка воспроизводимости

Android собран с Flutter 3.41.1 / Dart 3.11.0 и совпал с production APK байт-в-байт. Команда воспроизведения выполняется без переменной окружения `GREENVPN_APP_VERSION`, потому что production APK сохранил старое нативное значение `BuildConfig`, несмотря на корректные `versionName=0.2.44` и `versionCode=2026070504`:

```powershell
Remove-Item Env:\GREENVPN_APP_VERSION -ErrorAction SilentlyContinue
flutter build apk --release --no-pub `
  --build-name 0.2.44 `
  --build-number 2026070504 `
  --dart-define=GREENVPN_APP_VERSION=0.2.44 `
  --dart-define=GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=true `
  --dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=false `
  --dart-define=BLUEVPN_API_BASE_URL=https://api.greenvpn.pro `
  --dart-define=BLUEVPN_API_BASE_URLS=https://176-113-81-35.sslip.io
```

APK проверен `aapt` и `apksigner`: package `pro.greenvpn.app`, одна подпись, APK Signature Scheme v2, сертификат SHA-256 `1ea2c985890e9010aa3b76aee676624ec45398fd86a5e40dd95c76cdfc6a0fbc`.

Windows installer пересобран отдельно. IExpress-оболочка имеет другой SHA из-за времени сборки в `docs/BUILD_INFO.txt`; после распаковки 20 из 20 программных файлов совпали с production payload. Отличался только `docs/BUILD_INFO.txt`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\windows\build_installer.ps1 `
  -OutBase C:\BlueVPN_Builds\repro_20260710 `
  -InstallerName GreenVPN_Setup_repro_20260710.exe `
  -AppVersion 0.2.39-windows-clean-server-ui `
  -ApiBaseUrl https://api.greenvpn.pro `
  -ApiFallbackBaseUrls https://176-113-81-35.sslip.io
```

## Release gates

- `flutter test --no-pub`: проходит; текущий Flutter test остается placeholder и не считается достаточным покрытием.
- Python compile для backend/ops: проходит.
- Bash syntax для ops scripts: проходит.
- PowerShell parser checks: проходят.
- `scripts/windows/bluevpn_release_gate.ps1`: 0 ошибок, 0 предупреждений.
- `scripts/ops/check_public_download_manifests.ps1`: все manifests и downloads доступны, версии и расширения корректны.
- Рабочее дерево перед тегом проверяется через `git diff --check` и secret scan.

## Известные ограничения stable

- Production APK содержит старое нативное значение `BuildConfig.GREENVPN_APP_VERSION`; пользовательская и Dart-версия корректны. Исправление разрешено только в отдельной beta-сборке.
- Windows installer не имеет Authenticode-подписи. Это не скрывается и остается блокером доверенной массовой дистрибуции Windows.
- Реклама и трехминутный timer отключены и не должны включаться в paid beta.
- Subscription enforcement для старого stable отключен. Платные ограничения разрешены только для явного beta-marker и beta-cohort.
- Production stable, основной сайт и production-флаги не изменены в ходе freeze.

## Порядок восстановления

1. Остановить публикацию новых beta-артефактов и сохранить диагностические данные инцидента.
2. Восстановить исходники по Git tag. Если Git недоступен, использовать checkpoint и `git-history.bundle`.
3. Восстановить нужный control-plane/VPN-node из соответствующего root-only snapshot; не разворачивать все snapshots вслепую.
4. Вернуть эталонные Android/Windows файлы из checkpoint и сверить SHA-256 с таблицей выше.
5. Проверить auth, bootstrap, config, подключение, API failover и public manifests до снятия инцидента.

Rollback выполняется осознанно по затронутому компоненту. Автоматический массовый откат всех баз и серверов запрещен, поскольку он может уничтожить новые аккаунты и платежные данные, появившиеся после freeze.
