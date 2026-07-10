# Green VPN: paid beta 0.3.0, release 2

Дата сборки: 2026-07-10. Статус: локальная тестовая сборка, не опубликована на основном сайте и не включена в production update manifests.

## Контур

- Channel: `paid-beta`.
- App marker: `0.3.0-paid-beta.2`.
- Client marker: `green-vpn-paid-beta-v1`.
- Primary API: `https://api.greenvpn.pro/paid-beta-api`.
- Fallback API: `https://176-113-81-35.sslip.io/paid-beta-api`.
- Production stable URL и production DB не используются beta-клиентом.
- Rewarded ads: compile-time `false`.
- Ad session timer: принудительно отключён для beta-scope.
- Trial-only build: `false`.
- Paid-beta build: `true`.

## Артефакты

| Платформа | Файл | Размер | SHA-256 | Подпись |
| --- | --- | ---: | --- | --- |
| Android | `GreenVPN_Android_0.3.0-paid-beta.2_2026071002.apk` | 65 707 339 | `29252A8AE44BA4487363E669A0ED31DDAC159289A49254EBBED34F123D20AB50` | APK Signature Scheme v2, сертификат Green VPN |
| Windows | `GreenVPN_Setup_0.3.0-paid-beta.2.exe` | 12 827 136 | `41F96CB95118507AACA861721F83B2972CF419E2F10BA2FCF38CB73800988332` | `NotSigned` |

Локальный каталог: `C:\BlueVPN_Builds\paid_beta_20260710_v2`.

Machine-readable manifest: `C:\BlueVPN_Builds\paid_beta_20260710_v2\paid-beta-artifacts.json`.

Изолированный deploy-bundle: `C:\BlueVPN_Builds\paid_beta_20260710_v2\paid-beta-0.3.0-paid-beta.2-2026071002.tar.gz`.

SHA-256 deploy-bundle: `F5AE97EC8760FAA077746CE942FC0B1E7F4DCD40185167A127AC4115DE60DE5B`.

## Проверки

- Android package: `pro.greenvpn.app`.
- Android `versionName`: `0.3.0`.
- Android `versionCode`: `2026071002`.
- Android signer certificate SHA-256: `1ea2c985890e9010aa3b76aee676624ec45398fd86a5e40dd95c76cdfc6a0fbc`.
- Android `classes.dex` содержит нативный marker `0.3.0-paid-beta.1`.
- Android и Windows AOT runtime содержат beta client marker и оба изолированных API URL.
- JSON manifest hashes совпадают с файлами.
- Stable Android SHA-256 остался `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F`.
- Stable Windows SHA-256 остался `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15`.
- Двадцать backend/DB-sync тестов проходят.
- Release gate: 0 предупреждений, 0 ошибок.
- В deploy-bundle входят только beta backend, отдельные ops-скрипты, закрытая страница и два beta-артефакта; секретов и production DB в нём нет.

## Сборка

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\windows\build_paid_beta.ps1 `
  -Mode both `
  -OutDir C:\BlueVPN_Builds\paid_beta_20260710_v2
```

Builder блокирует beta-сборку, если primary или fallback не содержат `/paid-beta-api`. Он не содержит шага публикации.

## Ограничения

- До развёртывания изолированного backend path beta-клиенты не смогут войти или получить конфиг.
- Windows installer нельзя считать доверенной массовой сборкой до Authenticode-подписи.
- Нельзя заменять этими файлами production `GreenVPN_Android.apk` или `GreenVPN_Setup.exe`.
