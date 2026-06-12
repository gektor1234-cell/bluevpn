# Windows public audit TODO, 2026-05-25

Короткий список рисков, найденных при read-only аудите основной Windows-версии Green VPN на `https://greenvpn.pro/downloads/GreenVPN_Setup.exe`.

## Что потом исправить

1. Подпись Windows installer и EXE.
   - `GreenVPN_Setup.exe`, `greenvpn.exe` и `greenvpn_service.exe` сейчас не подписаны.
   - Это главный риск SmartScreen/Defender/доверия пользователя, не runtime-баг VPN.
   - Исправление: Code Signing / Trusted Signing после решения по бюджету.

2. Smoke connect требует чистого состояния.
   - На проверочном ПК не было `C:\ProgramData\BlueVPN\BlueVPNDev1.conf`, `prefs.json`, `session.json`.
   - Это нормально без активной сессии/полученного конфига, но значит read-only аудит не проверил реальный connect.
   - Для реального smoke: войти в аккаунт, получить Trial/config, подключить VPN, проверить интернет, отключить.

3. Конфликт с другими VPN.
   - На ПК был активен `AmneziaWGTunnel$device20_full`.
   - Green VPN должен отказываться подключаться поверх другого VPN, это ожидаемое защитное поведение.
   - Для ручного теста Green VPN сначала выключать Amnezia/WARP/WireGuard-like туннели.

4. Устаревший README внутри installer.
   - Внутри payload `docs/README_RELEASE.txt` указано `Version: 0.1.0-working-freeze`.
   - Там же остался текст про scheduled tasks, хотя фактически текущая сборка `0.2.8+2026052401` использует `GreenVPNService`.
   - Это документационный мусор в пакете, не runtime-баг.

5. Mojibake в части backend JSON.
   - В `bootstrap` / `catalog` некоторые русские описания приходят битой кодировкой.
   - Подключение, вероятно, не ломает, но если строки попадут в UI, будет некрасиво.
   - Исправить кодировку/источник текстов в backend catalog/bootstrap.

## Что уже было зелёным

- Live installer доступен и совпадает с update manifest по SHA256.
- Установленный `greenvpn.exe` на проверочном ПК byte-for-byte совпал с `greenvpn.exe` внутри live installer.
- Backend `/healthz`, bootstrap, update manifest и public catalog отвечали.
- Public catalog отдавал два healthy WireGuard UDP сервера: `nl1.vpn.greenvpn.pro` и `nl2.vpn.greenvpn.pro`.
- Локальный `GreenVPNService` был запущен и отвечал на `127.0.0.1:48737/ping`.
