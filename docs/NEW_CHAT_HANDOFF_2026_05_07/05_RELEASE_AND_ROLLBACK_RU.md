# Release, rollback и installer

## Latest known installer

- `C:\BlueVPN_Builds\GreenVPN_Setup.exe`
- `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`

Старые записи указывают на candidate copy:

- `C:\BlueVPN_Builds\GreenVPN_Setup_SupportReportFallback_20260505.exe`

## Stable rollback

Главный rollback anchor:

- `C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`
- SHA256: `71B455D04EB5C637C8A6E250DE7E6D4EFC90A76B470A87056F7946D61F6C5B87`

Это стабильная база с auth, tray/background, native service, payment return/pending polling.

## Installer hygiene

Пользователь хочет проверять fresh-user install flow, но не после каждого backend/admin изменения.

Перед финальной выдачей нового installer:

1. Остановить Green VPN.
2. Удалить только Green VPN tasks/service/tunnel artifacts.
3. Удалить Green VPN install/state folders.
4. Не удалять WireGuard itself, Amnezia, WARP, Friendly Linnet.
5. Собрать installer.
6. Дать пользователю один финальный `GreenVPN_Setup.exe` для теста.

Safe cleanup script:

`C:\Users\gekto\projects\bluevpn\scripts\windows\greenvpn_clean_previous_install.ps1`

Installer/build scripts:

- `C:\Users\gekto\projects\bluevpn\scripts\windows\build_installer.ps1`
- `C:\Users\gekto\projects\bluevpn\scripts\windows\build_release.ps1`
- `C:\Users\gekto\projects\bluevpn\scripts\windows\bluevpn_release_gate.ps1`

## Не делать сейчас

Не собирать installer только из-за подключения ЮKassa/backend/admin readiness.

ЮKassa подключается через backend env, без пересборки пользовательского Windows installer.
