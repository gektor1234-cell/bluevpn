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

# --- NEW DISCONNECT INNER (robust stop + kill PID + optional uninstall) ---
$newDisconnect = @'
$ErrorActionPreference="SilentlyContinue"
$exe="__EXE__"
$tn="__TN__"
$cfg="__CFG__"

# IMPORTANT: literal '$' in service name
$svc = "WireGuardTunnel`$$tn"

function Q {
  return (sc.exe queryex $svc 2>$null | Out-String)
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
  $n = [math]::Max(1, [int]($msTotal / 200))
  for ($i=0; $i -lt $n; $i++) {
    $q = Q
    if (-not $q) { return $true }          # service gone
    if (IsStopped $q) { return $true }
    Start-Sleep -Milliseconds 200
  }
  return $false
}

# 1) stop
sc.exe stop $svc | Out-Null
[void](WaitStopped 6000)

$q1 = Q

# 2) if still RUNNING -> kill exact service PID
if ($q1 -and (IsRunning $q1)) {
  $pid = GetSvcPid $q1
  if ($pid -gt 0) {
    try { Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue } catch {}
  }
  sc.exe stop $svc | Out-Null
  [void](WaitStopped 4000)
}

$q2 = Q

# 3) if STILL RUNNING -> uninstall tunnel service (last resort)
if ($q2 -and (IsRunning $q2)) {
  try { & $exe /uninstalltunnelservice $tn | Out-Null } catch {}
  Start-Sleep -Milliseconds 500
  [void](WaitStopped 6000)
}

# NOTE: bypass-route intentionally NOT removed (AllowedIPs=0.0.0.0/0 needs it)
exit 0
'@

# apply disconnect inner replacement
$content2 = Replace-Disconnect-Inner -text $content -newInner $newDisconnect
Write-Host "OK: disconnect() inner replaced" -ForegroundColor Green

# patch Dart verify block inside disconnect(): wait up to ~10s instead of single check
$idxDisc = $content2.IndexOf("Future<VpnBackendResult> disconnect() async")
if ($idxDisc -lt 0) { throw "disconnect() block not found for verify patch" }

$before = $content2.Substring(0, $idxDisc)
$after  = $content2.Substring($idxDisc)

$rxVerify = [regex]::new("(?s)//\s*verify\s*.*?return\s+const\s+VpnBackendResult\(\s*ok:\s*true\s*\);\s*", "Singleline")
if (-not $rxVerify.IsMatch($after)) {
  Write-Host "WARN: verify block not found (skip Dart verify patch)" -ForegroundColor Yellow
} else {
  $newVerify = @"
// verify (wait a bit: service can be stopping)
for (var i = 0; i < 40; i++) {
  final on = await isConnected();
  if (!on) return const VpnBackendResult(ok: true);
  await Future.delayed(const Duration(milliseconds: 250));
}
return const VpnBackendResult(ok: false, message: 'Service still RUNNING after stop/uninstall.');
"@
  $after = $rxVerify.Replace($after, $newVerify, 1)
  Write-Host "OK: Dart disconnect verify patched (wait loop)" -ForegroundColor Green
}

$content3 = $before + $after

Set-Content -LiteralPath $main -Value $content3 -Encoding UTF8
Write-Host "Patched: lib\main.dart (disconnect robustness + verify wait)" -ForegroundColor Green

if (-not $SkipBuild) {
  $build = Join-Path $project "bluevpn_build_release.ps1"
  if (Test-Path -LiteralPath $build) {
    Write-Host "Running build: $build" -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File $build
  } else {
    Write-Host "Build script not found: bluevpn_build_release.ps1 (skipped)" -ForegroundColor Yellow
  }
}