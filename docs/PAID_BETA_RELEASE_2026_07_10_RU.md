# Green VPN: локальная paid beta 0.3.0

Дата сборки: 2026-07-10. Статус: локальная тестовая сборка, не опубликована на основном сайте и не включена в production update manifests.

## Контур

- Channel: `paid-beta`.
- App marker: `0.3.0-paid-beta.1`.
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
| Android | `GreenVPN_Android_0.3.0-paid-beta.1_2026071001.apk` | 65 576 143 | `A0594E2668DBBC4C037533550830F620A3F36C899478749B2E7544253FCE7483` | APK Signature Scheme v2, сертификат Green VPN |
| Windows | `GreenVPN_Setup_0.3.0-paid-beta.1.exe` | 12 818 432 | `C828110633A45F99945698839C013ED7581209C6492BA006C4C8B42AF36F167E` | `NotSigned` |

Локальный каталог: `C:\BlueVPN_Builds\paid_beta_20260710`.

Machine-readable manifest: `C:\BlueVPN_Builds\paid_beta_20260710\paid-beta-artifacts.json`.

## Проверки

- Android package: `pro.greenvpn.app`.
- Android `versionName`: `0.3.0`.
- Android `versionCode`: `2026071001`.
- Android signer certificate SHA-256: `1ea2c985890e9010aa3b76aee676624ec45398fd86a5e40dd95c76cdfc6a0fbc`.
- Android `classes.dex` содержит нативный marker `0.3.0-paid-beta.1`.
- Android и Windows AOT runtime содержат beta client marker и оба изолированных API URL.
- JSON manifest hashes совпадают с файлами.
- Stable Android SHA-256 остался `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F`.
- Stable Windows SHA-256 остался `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15`.
- Пятнадцать backend/DB-sync тестов проходят.

## Сборка

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\windows\build_paid_beta.ps1 `
  -Mode both
```

Builder блокирует beta-сборку, если primary или fallback не содержат `/paid-beta-api`. Он не содержит шага публикации.

## Ограничения

- До развёртывания изолированного backend path beta-клиенты не смогут войти или получить конфиг.
- Windows installer нельзя считать доверенной массовой сборкой до Authenticode-подписи.
- Нельзя заменять этими файлами production `GreenVPN_Android.apk` или `GreenVPN_Setup.exe`.
