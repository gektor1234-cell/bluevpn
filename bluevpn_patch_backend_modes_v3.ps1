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

function Replace-InnerInMethod {
  param(
    [string]$text,
    [string]$methodName,
    [string]$newInner
  )

  $sig = "Future<VpnBackendResult> $methodName"
  $i0 = $text.IndexOf($sig)
  if ($i0 -lt 0) { throw "Method signature not found: $sig" }

  $marker = "final inner = r'''"
  $i1 = $text.IndexOf($marker, $i0)
  if ($i1 -lt 0) { throw "inner marker not found in $methodName(): $marker" }

  $contentStart = $i1 + $marker.Length

  $endMarker = "'''"
  $i2 = $text.IndexOf($endMarker, $contentStart)
  if ($i2 -lt 0) { throw "inner closing ''' not found in $methodName()" }

  $tail = $text.Substring($i2, [Math]::Min(500, $text.Length - $i2))
  if ($tail -notmatch "replaceAll\('__EXE__'") {
    throw "Sanity check failed: after inner in $methodName() no .replaceAll('__EXE__' found."
  }

  return $text.Substring(0, $contentStart) + "`r`n" + $newInner + "`r`n" + $text.Substring($i2)
}

# ===== NEW CONNECT INNER =====
$newConnect = @'
$ErrorActionPreference="Stop"
$exe="__EXE__"
$cfg="__CFG__"
$tn="__TN__"
$svc="__SVC__"
$warpPreferred="warp1234"

function Get-PhysDefault {
  try {
    return Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" |
      Where-Object { $_.NextHop -ne "0.0.0.0" -and $_.InterfaceAlias -notmatch "WireGuard" } |
      Sort-Object RouteMetric, InterfaceMetric |
      Select-Object -First 1
  } catch { return $null }
}

function Pick-WarpAlias {
  param([string]$preferred,[string]$tn)
  try {
    Get-NetIPInterface -AddressFamily IPv4 -InterfaceAlias $preferred -ErrorAction Stop | Out-Null
    return $preferred
  } catch {}
  try {
    $a = Get-NetAdapter -ErrorAction Stop |
      Where-Object { $_.InterfaceDescription -match "WireGuard" -and $_.Name -ne $tn } |
      Select-Object -First 1
    if ($a) { return $a.Name }
  } catch {}
  return $preferred
}

function Try-SetMetric {
  param([string]$alias,[int]$m)
  try {
    Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -AutomaticMetric Disabled -InterfaceMetric $m -ErrorAction Stop | Out-Null
    return $true
  } catch { return $false }
}

# parse endpoint IPv4 from config
$ep = $null
if ($cfg -and (Test-Path $cfg)) {
  $txt = Get-Content -Raw -Encoding UTF8 $cfg
  if ($txt -match '(?m)^\s*Endpoint\s*=\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})\s*:\s*\d+\s*$') { $ep = $matches[1] }
}

$phys = Get-PhysDefault
if (-not $phys) { Write-Host "No physical default route found"; exit 3 }

# endpoint bypass (ACTIVE + PERSISTENT) — держим всегда
if ($ep) {
  route.exe delete $ep | Out-Null
  route.exe add  $ep mask 255.255.255.255 $($phys.NextHop) metric 1 if $($phys.ifIndex) | Out-Null
  route.exe -p add $ep mask 255.255.255.255 $($phys.NextHop) metric 1 if $($phys.ifIndex) | Out-Null
}

$warp = Pick-WarpAlias $warpPreferred $tn

# baseline metrics: warp secondary, physical third
Try-SetMetric $warp 50 | Out-Null
Try-SetMetric $($phys.InterfaceAlias) 100 | Out-Null

# ensure service exists (без uninstall/install цикла)
$q0 = sc.exe query $svc 2>$null
if (-not $q0) { & $exe /installtunnelservice $cfg | Out-Null }

sc.exe start $svc | Out-Null

# wait RUNNING
for ($i=0; $i -lt 80; $i++) {
  $q = sc.exe query $svc 2>$null
  if ($q -match 'STATE\s*:\s*\d+\s+RUNNING') { break }
  Start-Sleep -Milliseconds 200
}
$qf = sc.exe query $svc 2>$null
if (-not ($qf -match 'STATE\s*:\s*\d+\s+RUNNING')) { Write-Host $qf; exit 2 }

# BlueVPN primary
Try-SetMetric $tn 5 | Out-Null
exit 0
'@

# ===== NEW DISCONNECT INNER =====
$newDisconnect = @'
$ErrorActionPreference="SilentlyContinue"
$tn="__TN__"
$svc="__SVC__"
$cfg="__CFG__"
$warpPreferred="warp1234"

function Get-PhysDefault {
  try {
    return Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" |
      Where-Object { $_.NextHop -ne "0.0.0.0" -and $_.InterfaceAlias -notmatch "WireGuard" } |
      Sort-Object RouteMetric, InterfaceMetric |
      Select-Object -First 1
  } catch { return $null }
}

function Pick-WarpAlias {
  param([string]$preferred,[string]$tn)
  try {
    Get-NetIPInterface -AddressFamily IPv4 -InterfaceAlias $preferred -ErrorAction Stop | Out-Null
    return $preferred
  } catch {}
  try {
    $a = Get-NetAdapter -ErrorAction Stop |
      Where-Object { $_.InterfaceDescription -match "WireGuard" -and $_.Name -ne $tn } |
      Select-Object -First 1
    if ($a) { return $a.Name }
  } catch {}
  return $preferred
}

function Try-SetMetric {
  param([string]$alias,[int]$m)
  try {
    Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -AutomaticMetric Disabled -InterfaceMetric $m -ErrorAction Stop | Out-Null
    return $true
  } catch { return $false }
}

# stop + wait STOPPED
sc.exe stop $svc | Out-Null
for ($i=0; $i -lt 80; $i++) {
  $q = sc.exe query $svc 2>$null
  if (!$q) { break }
  if ($q -match 'STATE\s*:\s*\d+\s+STOPPED') { break }
  Start-Sleep -Milliseconds 200
}

# если завис в RUNNING — прибить tunnelservice по cfg
$q2 = sc.exe query $svc 2>$null
if ($q2 -and ($q2 -match 'STATE\s*:\s*\d+\s+RUNNING')) {
  try {
    Get-CimInstance Win32_Process -Filter "Name='wireguard.exe'" | ForEach-Object {
      if ($_.CommandLine -match '/tunnelservice' -and $cfg -and $_.CommandLine -match [regex]::Escape($cfg)) {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
      }
    }
  } catch {}
  sc.exe stop $svc | Out-Null
  Start-Sleep -Milliseconds 300
}

# OFF = WARP primary, physical third, BlueVPN deprioritize (если интерфейс есть)
$phys = Get-PhysDefault
if ($phys) {
  $warp = Pick-WarpAlias $warpPreferred $tn
  Try-SetMetric $warp 5 | Out-Null
  Try-SetMetric $($phys.InterfaceAlias) 100 | Out-Null
  Try-SetMetric $tn 5000 | Out-Null
}

# ВАЖНО: bypass-route НЕ удаляем
exit 0
'@

$content2 = $content
$content2 = Replace-InnerInMethod $content2 "connect" $newConnect
Write-Host "OK: connect() inner patched" -ForegroundColor Green
$content2 = Replace-InnerInMethod $content2 "disconnect" $newDisconnect
Write-Host "OK: disconnect() inner patched" -ForegroundColor Green

Set-Content -LiteralPath $main -Value $content2 -Encoding UTF8
Write-Host "Patched: lib\main.dart" -ForegroundColor Green

if (-not $SkipBuild) {
  $build = Join-Path $project "bluevpn_build_release.ps1"
  if (Test-Path -LiteralPath $build) {
    Write-Host "Running build: $build" -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File $build
  } else {
    Write-Host "Build script not found: bluevpn_build_release.ps1 (skipped)" -ForegroundColor Yellow
  }
}