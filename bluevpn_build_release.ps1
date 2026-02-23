# BlueVPN - build Windows Release and deploy to C:\BlueVPN_Builds (no OneDrive file locks)
# Usage:
#   cd "$env:USERPROFILE\projects\bluevpn"
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\bluevpn_build_release.ps1

$ErrorActionPreference = 'Stop'

$proj = Join-Path $env:USERPROFILE 'projects\bluevpn'
Set-Location $proj

# Stop running app (prevents locked .dll/.exe during copy)
Get-Process bluevpn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400

Write-Host '== BlueVPN build release ==' -ForegroundColor Cyan

Write-Host 'flutter pub get...' -ForegroundColor Cyan
flutter pub get | Out-Host

Write-Host 'flutter clean...' -ForegroundColor Cyan
flutter clean | Out-Host

Write-Host 'flutter build windows --release...' -ForegroundColor Cyan
flutter build windows --release -t .\lib\main.dart | Out-Host

$release = Join-Path (Get-Location) 'build\windows\x64\runner\Release'
if (!(Test-Path $release)) {
  throw "Release folder not found: $release"
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$rootOut = 'C:\BlueVPN_Builds'
$dst = Join-Path $rootOut ("BlueVPN_$stamp")

New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Path (Join-Path $release '*') -Destination $dst -Recurse -Force

$exe = Join-Path $dst 'bluevpn.exe'
if (!(Test-Path $exe)) {
  throw "bluevpn.exe not found after copy: $exe"
}

# Desktop shortcut (only .lnk goes to OneDrive Desktop)
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $desktop 'BlueVPN.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force }

$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($lnk)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $dst
$sc.IconLocation = "$exe,0"
$sc.Save()

Write-Host "OK: Release deployed to: $dst" -ForegroundColor Green
Write-Host "OK: Shortcut updated:   $lnk" -ForegroundColor Green
Write-Host "Note: If ON/OFF asks for UAC, accept it (WireGuard service needs admin)." -ForegroundColor Yellow
