[CmdletBinding()]
param([switch]$SkipBuild)

$ErrorActionPreference = "Stop"

$project = (Resolve-Path ".").Path
$main = Join-Path $project "lib\main.dart"
if (-not (Test-Path -LiteralPath $main)) { throw "Not found: $main" }

# backup
$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$backupDir = Join-Path $project ("_patch_backup\" + $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item -LiteralPath $main -Destination (Join-Path $backupDir "main.dart") -Force
Write-Host "Backup: $backupDir" -ForegroundColor Cyan

$content = Get-Content -LiteralPath $main -Raw -Encoding UTF8

$needleConnect = "final res = await _vpnBackend.connect"
$needleDisconnect = "final res = await _vpnBackend.disconnect"
$needleSync = "await _syncVpnStatus();"
$needleMarker = "final onNow = await _vpnBackend.isConnected();"

# detect vpn state var (you already saw it's vpnEnabled, but keep auto-detect)
$idxC = $content.IndexOf($needleConnect)
if ($idxC -lt 0) { throw "Cannot find: $needleConnect" }

$segStart = [Math]::Max(0, $idxC - 4000)
$seg = $content.Substring($segStart, $idxC - $segStart)

$m = [regex]::Match($seg, "if\s*\(\s*!\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\{", "Singleline")
if (-not $m.Success) { throw "Cannot detect vpn state variable (pattern if (!var) { )." }
$vpnVar = $m.Groups[1].Value
Write-Host "Detected VPN state var: $vpnVar" -ForegroundColor Green

function Get-IndentAt {
  param([string]$text, [int]$pos)
  $ls = $text.LastIndexOf("`n", $pos)
  if ($ls -lt 0) { $ls = 0 } else { $ls = $ls + 1 }
  $ind = ""
  for ($i = $ls; $i -lt $pos; $i++) {
    $ch = $text[$i]
    if ($ch -eq ' ' -or $ch -eq "`t") { $ind += $ch } else { break }
  }
  return $ind
}

function Insert-AfterSyncAfterIndex {
  param(
    [string]$text,
    [int]$startIndex,
    [string]$vpnVar
  )

  $syncIdx = $text.IndexOf($needleSync, $startIndex)
  if ($syncIdx -lt 0) { throw "Cannot find sync after index=$startIndex" }

  $after = $syncIdx + $needleSync.Length

  # already inserted?
  $winLen = [Math]::Min(300, $text.Length - $after)
  if ($winLen -gt 0) {
    $win = $text.Substring($after, $winLen)
    if ($win -match [regex]::Escape($needleMarker)) { return $text }
  }

  $indent = Get-IndentAt $text $syncIdx
  $ins =
    "`r`n" + $indent + "final onNow = await _vpnBackend.isConnected();" +
    "`r`n" + $indent + "if (mounted) setState(() => $vpnVar = onNow);" + "`r`n"

  return $text.Insert($after, $ins)
}

# patch connect branch
$content2 = Insert-AfterSyncAfterIndex -text $content -startIndex $idxC -vpnVar $vpnVar
Write-Host "OK: inserted after sync (connect branch)" -ForegroundColor Green

# patch disconnect branch
$idxD = $content2.IndexOf($needleDisconnect)
if ($idxD -lt 0) { throw "Cannot find: $needleDisconnect" }
$content3 = Insert-AfterSyncAfterIndex -text $content2 -startIndex $idxD -vpnVar $vpnVar
Write-Host "OK: inserted after sync (disconnect branch)" -ForegroundColor Green

Set-Content -LiteralPath $main -Value $content3 -Encoding UTF8
Write-Host "Patched: lib\main.dart (vpnEnabled synced via isConnected)" -ForegroundColor Green

if (-not $SkipBuild) {
  $build = Join-Path $project "bluevpn_build_release.ps1"
  if (Test-Path -LiteralPath $build) {
    Write-Host "Running build: $build" -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File $build
  } else {
    Write-Host "Build script not found: bluevpn_build_release.ps1 (skipped)" -ForegroundColor Yellow
  }
}