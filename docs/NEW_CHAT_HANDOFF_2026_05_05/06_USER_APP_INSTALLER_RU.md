# Пользовательское приложение и installer

## Product

Visible brand:

`Green VPN`

Repo remains:

`C:\Users\gekto\projects\bluevpn`

Internal tunnel/config names remain:

- `BlueVPNDev1`
- `WireGuardTunnel$BlueVPNDev1`
- `C:\ProgramData\BlueVPN`

## UX expectations

Пользовательский сценарий:

1. Пользователь скачивает `GreenVPN_Setup.exe`.
2. Установщик один раз просит права администратора.
3. Установщик ставит приложение, service/helper, tray/autostart.
4. После установки приложение открывается обычным пользователем.
5. Дальше не должно быть постоянных UAC prompts.
6. Подключение VPN идёт через системный компонент.
7. Если другой VPN активен, Green VPN должен действовать осторожно: детектить, предупреждать или не подключаться поверх него, но не ломать чужие VPN.

## Что уже важно сохранить

- VPN connect/disconnect.
- Social Only.
- Trial/tariff UI.
- Green visual style.
- Tray/background/autostart.
- Installer branding.
- Clean uninstall/cleanup helper.
- Support/report groundwork.
- Update groundwork.

## Что пользователь не должен видеть

- Backend Admin.
- Admin token.
- Internal health endpoints.
- Raw backend state.
- Raw WireGuard config.
- Private keys.
- Service debug панели.
- “История заказов” в пользовательском UI, если она не нужна для реального пользовательского сценария.

## Account/settings UI

Нужно двигаться к простому виду:

- Аккаунт.
- Почта.
- Телефон.
- Поддержка.
- О приложении.
- Обновление.
- Тема.
- Язык.

Не нужно дублировать кнопки “Телефон” и “Привязать телефон”, если они делают одно и то же. Должна быть понятная строка `Телефон`.

Email/SMS должны быть через код, а не через сложную подтверждающую модель в пользовательском UI.

## Support UI

Цель:

- кнопка `Отправить отчет`;
- отчёт уходит на backend;
- пользователь не видит технический JSON;
- отчёт не содержит секретов;
- support/admin app может открыть report и понять проблему.

Содержимое report:

- app version;
- OS;
- service status;
- tunnel status;
- safe endpoint info;
- handshake age;
- traffic counters;
- competing VPN detection;
- auth/device/subscription status;
- network checks;
- support code;
- no tokens, no keys.

## Installer behavior

Установщик должен:

- показывать Green VPN Installer;
- иметь нормальный логотип/иконку;
- не показывать лишние PowerShell-окна;
- ставить service/helper;
- ставить desktop/start shortcut;
- ставить autostart/tray logic;
- удалять старые BlueVPN shortcuts;
- корректно чистить старую тестовую Green VPN установку при reinstall;
- выдавать понятный log path при ошибке;
- не ломать Amnezia/WARP.

## Если меняется клиент

Обязательные проверки:

```powershell
cd C:\Users\gekto\projects\bluevpn
flutter build windows --release -t .\lib\main.dart
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_release_gate.ps1 -StrictPaymentGate
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build_installer.ps1
```

После сборки:

- дать ссылку на `C:\BlueVPN_Builds\GreenVPN_Setup.exe`;
- посчитать SHA256;
- обновить release docs;
- не удалить rollback.
