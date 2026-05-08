# Команды проверки, сборки и деплоя

Все команды запускать из:

`C:\Users\gekto\projects\bluevpn`

## Инвентаризация

```powershell
cd C:\Users\gekto\projects\bluevpn
git status --short
```

## Backend syntax

```powershell
cd C:\Users\gekto\projects\bluevpn
python -m py_compile backend_live\app\main.py
```

## Admin support app syntax

```powershell
cd C:\Users\gekto\projects\bluevpn
@'
import json, pathlib, quickjs
code = pathlib.Path('admin_support_app/app.js').read_text(encoding='utf-8')
ctx = quickjs.Context()
ctx.eval('new Function(' + json.dumps(code) + ')')
print('quickjs app.js syntax ok')
'@ | python -
```

Если `quickjs` не установлен, можно использовать доступный JS parser/checker, но не надо ради этого ломать окружение.

## Backend deploy

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\deploy_backend_wsl.ps1
```

Скрипт может спросить SSH password. Пароль не писать в repo и не выводить в чат.

## Backend health

```powershell
wsl.exe curl -fsS http://37.220.85.211:8000/healthz
```

Ожидаемо:

`"version":"0.9.11"`

## Public catalog

```powershell
wsl.exe curl -fsS http://37.220.85.211:8000/api/v1/catalog/servers
```

или через домен:

```powershell
wsl.exe curl -fsS https://api.greenvpn.pro/api/v1/catalog/servers
```

Ожидаемо:

- `ok: true`;
- нет private keys;
- нет admin-only managed endpoint leakage.

## Admin endpoints

Проверять только с admin token из безопасного env или ручного ввода.

Принцип:

- не печатать token;
- не сохранять token в файл;
- не коммитить token.

Примерный паттерн:

```powershell
$adminToken = Read-Host -AsSecureString "Admin token"
```

Дальше аккуратно использовать в header без вывода.

Endpoints:

- `GET /api/v1/admin/server-catalog`
- `GET /api/v1/admin/server-health`
- `POST /api/v1/admin/server-health/probe-current`

## Flutter build

Нужен только если менялся пользовательский клиент.

```powershell
cd C:\Users\gekto\projects\bluevpn
flutter build windows --release -t .\lib\main.dart
```

## Release gate

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_release_gate.ps1 -StrictPaymentGate
```

## Installer build

```powershell
cd C:\Users\gekto\projects\bluevpn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build_installer.ps1
```

Output:

- `C:\BlueVPN_Builds\GreenVPN_Setup.exe`
- `C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`

## SHA256

```powershell
Get-FileHash C:\BlueVPN_Builds\GreenVPN_Setup.exe -Algorithm SHA256
```

## Admin app local serving

Если нужен локальный сервер на `127.0.0.1:8090`, использовать существующий способ проекта. Перед запуском проверить, не занят ли порт.

Пример:

```powershell
cd C:\Users\gekto\projects\bluevpn\admin_support_app
python -m http.server 8090 --bind 127.0.0.1
```

Если сервер уже запущен, не плодить лишние процессы.

## DNS checks

```powershell
Resolve-DnsName api.greenvpn.pro
Resolve-DnsName greenvpn.pro
Resolve-DnsName greenvpn.pro -Type MX
Resolve-DnsName greenvpn.pro -Type TXT
Resolve-DnsName mail._domainkey.greenvpn.pro -Type TXT
```

## Важная проверка перед финальным ответом

Перед отчётом пользователю написать:

- backend version;
- какие tests passed;
- нужен ли installer;
- где новый installer, если он нужен;
- что требуется от владельца;
- процент прогресса по плану.
