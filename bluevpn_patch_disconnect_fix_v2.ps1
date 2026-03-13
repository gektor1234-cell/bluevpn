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

function Replace-Disconnect-Inner {
  param([string]$text, [string]$newInner)

  $sig = "Future<VpnBackendResult> disconnect() async"
  $i0 = $text.IndexOf($sig)
  if ($i0 -lt 0) { throw "disconnect() signature not found: $sig" }

  $marker = "final inner = r'''"
  $i1 = $text.IndexOf($marker, $i0)
  if ($i1 -lt 0) { throw "inner marker not found in disconnect(): $marker" }

  $contentStart = $i1 + $marker.Length
  $endMarker = "'''"
  $i2 = $text.IndexOf($endMarker, $contentStart)
  if ($i2 -lt 0) { throw "inner closing ''' not found in disconnect()" }

  $tail = $text.Substring($i2, [Math]::Min(600, $text.Length - $i2))
  if ($tail -notmatch "replaceAll\('__EXE__'") {
    throw "Sanity check failed: after disconnect inner no .replaceAll('__EXE__' found."
  }

  return $text.Substring(0, $contentStart) + "`r`n" + $newInner + "`r`n" + $text.Substring($i2)
}

$newDisconnect = @'
$ErrorActionPreference="Stop"
$exe="__EXE__"
$tn="__TN__"
$cfg="__CFG__"

function Is-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Is-Admin)) {
  Write-Host "ERROR: Not running as Administrator. Cannot stop/kill WireGuard service." -ForegroundColor Red
  exit 5
}

# IMPORTANT: literal '$' in service name
$svc = "WireGuardTunnel`$$tn"

function QueryText {
  return (sc.exe queryex $svc 2>&1 | Out-String)
}

function IsStopped([string]$q) { return ($q -match '\sSTOPPED\b') }
function IsRunning([string]$q) { return ($q -match '\sRUNNING\b') }

function GetSvcPid([string]$q) {
  $m = [regex]::Match($q, '(?m)PID\s*:\s*(\d+)')
  if ($m.Success) { return [int]$m.Groups[1].Value }
  $m2 = [regex]::Match($q, '(?m)ID_процесса\s*:\s*(\d+)')
  if ($m2.Success) { return [int]$m2.Groups[1].Value }
  return 0
}

function WaitStopped([int]$msTotal) {
  $n = [math]::Max(1, [int]($msTotal / 250))
  for ($i=0; $i -lt $n; $i++) {
    $q = QueryText
    if (-not $q) { return $true }     # service gone
    if (IsStopped $q) { return $true }
    Start-Sleep -Milliseconds 250
  }
  return $false
}

# 1) stop
$stopOut = (sc.exe stop $svc 2>&1 | Out-String)
Start-Sleep -Milliseconds 300
[void](WaitStopped 6000)

$q1 = QueryText

# 2) if still RUNNING -> kill exact service PID
if ($q1 -and (IsRunning $q1)) {
  $pid = GetSvcPid $q1
  if ($pid -gt 0) {
    try { taskkill.exe /PID $pid /F | Out-Null } catch {}
  }
  Start-Sleep -Milliseconds 300
  [void](WaitStopped 4000)
}

$q2 = QueryText

# 3) if STILL RUNNING -> last resort: delete + uninstall
if ($q2 -and (IsRunning $q2)) {
  try { sc.exe stop $svc | Out-Null } catch {}
  try { sc.exe delete $svc | Out-Null } catch {}
  try { & $exe /uninstalltunnelservice $tn | Out-Null } catch {}
  Start-Sleep -Milliseconds 500
  [void](WaitStopped 6000)
}

# FINAL CHECK (return non-zero if still running, so UI shows real reason)
$qf = QueryText
if ($qf -and (IsRunning $qf)) {
  Write-Host "ERROR: Service still RUNNING after stop/kill/delete/uninstall." -ForegroundColor Red
  Write-Host $qf
  exit 2
}

# NOTE: bypass-route intentionally NOT removed (AllowedIPs=0.0.0.0/0 needs it)
exit 0
'@

$content2 = Replace-Disconnect-Inner -text $content -newInner $newDisconnect
Write-Host "OK: disconnect() inner replaced (v2)" -ForegroundColor Green

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