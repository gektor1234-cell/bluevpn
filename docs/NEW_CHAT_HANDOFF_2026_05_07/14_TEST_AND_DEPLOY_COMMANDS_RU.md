# Команды проверки и деплоя

## База

```powershell
cd C:\Users\gekto\projects\bluevpn
git status --short
```

## Backend syntax

```powershell
python -m py_compile backend_live\app\main.py
```

## Admin app syntax

```powershell
python -c "from pathlib import Path; import quickjs, json; code=Path('admin_support_app/app.js').read_text(encoding='utf-8'); quickjs.Context().eval('new Function(' + json.dumps(code) + ')'); print('admin_support_app/app.js syntax OK via quickjs')"
```

## PowerShell parse checks

```powershell
$errors = $null
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -Encoding UTF8 scripts\windows\check_external_services_readiness.ps1), [ref]$errors)
if ($errors) { $errors; exit 1 }
Write-Output 'check_external_services_readiness.ps1 parse OK'
```

```powershell
$errors = $null
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -Encoding UTF8 scripts\windows\check_api_vpn_split_preflight.ps1), [ref]$errors)
if ($errors) { $errors; exit 1 }
Write-Output 'check_api_vpn_split_preflight.ps1 parse OK'
```

```powershell
$errors = $null
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -Encoding UTF8 scripts\windows\get_owner_launch_packet.ps1), [ref]$errors)
if ($errors) { $errors; exit 1 }
Write-Output 'get_owner_launch_packet.ps1 parse OK'
```

```powershell
$errors = $null
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -Encoding UTF8 scripts\windows\check_payment_launch_safety.ps1), [ref]$errors)
if ($errors) { $errors; exit 1 }
Write-Output 'check_payment_launch_safety.ps1 parse OK'
```

```powershell
$errors = $null
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -Encoding UTF8 scripts\windows\get_monitoring_probe_plan.ps1), [ref]$errors)
if ($errors) { $errors; exit 1 }
Write-Output 'get_monitoring_probe_plan.ps1 parse OK'
```

```powershell
$errors = $null
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -Encoding UTF8 scripts\windows\bluevpn_release_gate.ps1), [ref]$errors)
if ($errors) { $errors; exit 1 }
Write-Output 'bluevpn_release_gate.ps1 parse OK'
```

## Backend deploy

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\deploy_backend_wsl.ps1
```

## External readiness

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck -Json
```

Server-admin self-check now includes `GET /api/v1/admin/launch/owner-packet` and validates that the packet has no secret values.
It also validates that renewal/expiry safe-enable flags cannot become true while payment smoke is not clean.

## Owner launch packet

Sanitized summary через server-side admin token file, без вывода token:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\get_owner_launch_packet.ps1
```

JSON:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\get_owner_launch_packet.ps1 -Json
```

## Payment launch safety

Sanitized payment safety summary через server-side admin token file:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_payment_launch_safety.ps1
```

JSON:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_payment_launch_safety.ps1 -Json
```

## Monitoring probe plan

Sanitized monitoring probe plan через server-side admin token file:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\get_monitoring_probe_plan.ps1
```

JSON:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\get_monitoring_probe_plan.ps1 -Json
```

## API/VPN split preflight

После появления отдельного API/site IP или reverse proxy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_api_vpn_split_preflight.ps1 -ApiBase https://api.greenvpn.pro -VpnEndpointHost nl1.vpn.greenvpn.pro -ExpectedVpnIp 37.220.85.211 -ExpectedApiIp <new-api-site-ip> -Json
```

Команда не меняет инфраструктуру и не требует секретов.

## Safe env configure

Для SMTP/SMS/ЮKassa/Telegram secrets:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\configure_backend_env_wsl.ps1
```

Секреты вводить только туда, не в чат и не в docs.

## Health checks

Если локальный Windows не открывает `https://api.greenvpn.pro` при включенном VPN, это может быть известный API/VPN same-IP blocker. Для backend health использовать server-side readiness.

Проверка с сервера/WSL может быть надежнее, чем локальный браузер с включенным full-tunnel VPN.

## Installer build

Не запускать без явной причины.

```powershell
flutter build windows --release -t .\lib\main.dart
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_release_gate.ps1 -StrictPaymentGate
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build_installer.ps1
```
