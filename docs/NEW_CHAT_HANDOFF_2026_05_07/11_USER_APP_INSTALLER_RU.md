# Пользовательское приложение и installer

## Приложение

Green VPN - Windows-first Flutter client.

Основные файлы:

- `C:\Users\gekto\projects\bluevpn\lib\main.dart`
- `C:\Users\gekto\projects\bluevpn\lib\bluevpn_desktop.dart`
- `C:\Users\gekto\projects\bluevpn\lib\screens\home_screen.dart`
- `C:\Users\gekto\projects\bluevpn\lib\services\vpn_backend_service.dart`
- `C:\Users\gekto\projects\bluevpn\lib\services\wireguard_service.dart`
- `C:\Users\gekto\projects\bluevpn\lib\services\managed_config_service.dart`
- `C:\Users\gekto\projects\bluevpn\windows\green_vpn_service`

## Что уже есть

- Видимый бренд Green VPN.
- Native `GreenVPNService`.
- Tray/background/autostart.
- Scheduled tasks as fallback.
- Login/register flow.
- Payment return/pending polling.
- Support report groundwork.
- Social Only mode.

## Installer

Installer scripts:

- `C:\Users\gekto\projects\bluevpn\scripts\windows\build_installer.ps1`
- `C:\Users\gekto\projects\bluevpn\scripts\windows\build_release.ps1`
- `C:\Users\gekto\projects\bluevpn\scripts\windows\bluevpn_release_gate.ps1`

Current installer:

- `C:\BlueVPN_Builds\GreenVPN_Setup.exe`
- `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`

Rollback:

- `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`

## Clean install testing

Пользователь любит fresh-user install test:

- полностью снести предыдущий Green VPN;
- скачать/запустить новый installer;
- проверить login;
- проверить VPN;
- проверить оплату/активацию, если релевантно.

Но новый installer нужен только в конце или по явной просьбе.

## Не трогать

- WireGuard itself;
- Amnezia;
- WARP;
- Friendly Linnet;
- чужие туннели.

Green VPN cleanup должен трогать только Green VPN artifacts.
