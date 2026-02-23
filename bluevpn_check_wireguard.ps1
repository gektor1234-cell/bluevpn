# BlueVPN - quick WireGuard service checks
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_check_wireguard.ps1

$ErrorActionPreference = 'Stop'

$tn = 'BlueVPN'
$svc = "WireGuardTunnel`$$tn"  # escape $ in PowerShell string

Write-Host "Service: $svc" -ForegroundColor Cyan

Write-Host '--- sc query STATE ---' -ForegroundColor Cyan
sc.exe query $svc | findstr /i "STATE" | Out-Host

Write-Host '--- sc qc (binpath / conf) ---' -ForegroundColor Cyan
sc.exe qc $svc | Out-Host

Write-Host '--- routes that match Endpoint candidates (edit if needed) ---' -ForegroundColor Cyan
route print | findstr /i "255.255.255.255" | Out-Host
