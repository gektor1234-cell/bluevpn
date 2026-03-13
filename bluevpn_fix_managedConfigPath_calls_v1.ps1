# bluevpn_fix_managedConfigPath_calls_v1.ps1
# Fix: ConfigStore.managedConfigPath is a property (getter) but some code calls it like a method: managedConfigPath()
# This script replaces ".managedConfigPath()" -> ".managedConfigPath" in lib\main.dart, then rebuilds via bluevpn_build_release.ps1 (if present).

$ErrorActionPreference = "Stop"

function Info([string]$s) { Write-Host $s -ForegroundColor Cyan }
function Ok([string]$s)   { Write-Host $s -ForegroundColor Green }
function Warn([string]$s) { Write-Host $s -ForegroundColor Yellow }

$proj = Join-Path $env:USERPROFILE "projects\bluevpn"
Set-Location $proj

Info "== BlueVPN FIX managedConfigPath() calls =="
Info "Project: $proj"

# Stop running app to avoid locks
Get-Process bluevpn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $proj ("_patch_backup\" + $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$main = Join-Path $proj "lib\main.dart"
if (!(Test-Path $main)) { throw "main.dart not found: $main" }

Copy-Item $main (Join-Path $backupDir "main.dart") -Force
Ok "Backup created: $backupDir"

# Read / patch
$text = Get-Content -Raw -Encoding UTF8 $main

# Replace only the invocation form with a dot-prefix (most common + safe)
$before = ([regex]::Matches($text, '\.managedConfigPath\s*\(\s*\)')).Count
$text2  = [regex]::Replace($text, '\.managedConfigPath\s*\(\s*\)', '.managedConfigPath')
$after  = ([regex]::Matches($text2, '\.managedConfigPath\s*\(\s*\)')).Count

if ($before -eq 0) {
  Warn "No occurrences of '.managedConfigPath()' were found. Nothing to change."
} else {
  Ok ("Replaced occurrences: " + $before + " -> remaining: " + $after)
  Set-Content -Encoding UTF8 -Path $main -Value $text2
  Ok "Patched: lib\main.dart"
}

# Rebuild / deploy (uses existing build script if available)
$buildScript = Join-Path $proj "bluevpn_build_release.ps1"
if (Test-Path $buildScript) {
  Info "Running build script: $buildScript"
  powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript
  Ok "DONE."
} else {
  Warn "bluevpn_build_release.ps1 not found. Doing a minimal build only..."
  flutter pub get | Out-Host
  flutter clean   | Out-Host
  flutter build windows --release -t .\lib\main.dart | Out-Host
  Ok "Build finished. Release folder should be: build\windows\x64\runner\Release"
}
