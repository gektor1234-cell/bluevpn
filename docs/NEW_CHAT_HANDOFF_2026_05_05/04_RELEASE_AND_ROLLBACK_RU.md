# Release, installer и rollback

## Текущий рабочий installer

Основной путь:

`C:\BlueVPN_Builds\GreenVPN_Setup.exe`

Alias:

`C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`

Кандидатная копия последней безопасной сборки:

`C:\BlueVPN_Builds\GreenVPN_Setup_SafeCatalogGate_20260505.exe`

Известный SHA256 последней candidate/public сборки:

`E0A861DE4B486E5FFC037C9D850B5E0F30C702F876DEAD536AB7BA43E53E7A54`

## Стабильный rollback

Rollback checkpoint:

`ROLLBACK_20260430_2028_payment_confirmation_ok`

Installer rollback:

`C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`

SHA256:

`71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`

Этот rollback считается “бетонной” стабильной версией, к которой можно возвращаться, если новый installer ломает пользовательский VPN.

## Когда нужен новый installer

Нужен, если меняется:

- `lib\main.dart`;
- Windows runner/service/helper;
- assets/icon/branding;
- installer logic;
- tray/autostart;
- user support report UI;
- updater UI;
- client API logic.

Не нужен, если меняется только:

- backend admin endpoints;
- monitoring scripts;
- admin_support_app static frontend;
- docs;
- server-side health scoring без client change.

## Правильная сборка

Из корня проекта:

```powershell
cd C:\Users\gekto\projects\bluevpn
flutter build windows --release -t .\lib\main.dart
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_release_gate.ps1 -StrictPaymentGate
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build_installer.ps1
```

Важно: installer должен паковать свежий `build\windows\x64\runner\Release`, а не старый freeze zip.

## Чистка перед тестовой установкой

Для тестов на локальном компьютере перед новым installer обычно надо убрать предыдущую тестовую установку Green VPN, но не трогать чужие VPN:

- не убивать Amnezia;
- не убивать WARP;
- не удалять чужие WireGuard tunnels;
- чистить только Green VPN app, Green VPN service/helper, Green VPN scheduled tasks/autostart, `WireGuardTunnel$BlueVPNDev1`, если это именно наш туннель.

Скрипт/логика для чистки находится в `scripts\windows\greenvpn_clean_previous_install.ps1`.

Перед любым destructive cleanup новый чат должен внимательно прочитать скрипт и убедиться, что он ограничен Green VPN.

## После стабильной сборки

После подтверждения пользователем “всё работает”:

- зафиксировать installer path;
- посчитать SHA256;
- обновить `RELEASE_STATE.md`;
- обновить `CURRENT_HANDOFF.md`;
- обновить rollback/candidate note;
- не удалять стабильный rollback.
