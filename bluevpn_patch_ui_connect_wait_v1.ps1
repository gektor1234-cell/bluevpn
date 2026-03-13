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

# already patched?
if ($content -match "VPN did not start \(service not RUNNING\)") {
  Write-Host "Already patched (connect wait-loop found). Skipping." -ForegroundColor Yellow
  exit 0
}

$needleConnect = "final res = await _vpnBackend.connect"
$idxC = $content.IndexOf($needleConnect)
if ($idxC -lt 0) { throw "Cannot find: $needleConnect" }

# detect vpn state var (your code uses vpnEnabled)
$segStart = [Math]::Max(0, $idxC - 4000)
$seg = $content.Substring($segStart, $idxC - $segStart)
$m = [regex]::Match($seg, "if\s*\(\s*!\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\{", "Singleline")
if (-not $m.Success) { throw "Cannot detect vpn state variable (pattern if (!var) { )." }
$vpnVar = $m.Groups[1].Value
Write-Host "Detected VPN state var: $vpnVar" -ForegroundColor Green

# find the sync call in CONNECT success path
$syncNeedle = "await _syncVpnStatus();"
$syncIdx = $content.IndexOf($syncNeedle, $idxC)
if ($syncIdx -lt 0) { throw "Cannot find sync after connect." }

# our earlier inserted quick check
$quickNeedle = "final onNow = await _vpnBackend.isConnected();"
$quickIdx = $content.IndexOf($quickNeedle, $syncIdx)
if ($quickIdx -lt 0) { throw "Cannot find inserted isConnected() after sync (expected from previous patch)." }

# also find the toast that follows (first _toast after quickIdx)
$toastNeedle = "_toast(context,"
$toastIdx = $content.IndexOf($toastNeedle, $quickIdx)
if ($toastIdx -lt 0) { throw "Cannot find _toast(context, after connect sync." }

# Replace ONLY the quick 2-line block with a wait-loop block
# We'll remove from quickIdx up to end of the setState line.
$endLineIdx = $content.IndexOf(");", $quickIdx)
if ($endLineIdx -lt 0) { throw "Cannot find end of setState line after quick isConnected." }
$endLineIdx = $content.IndexOf(");", $endLineIdx + 2)
if ($endLineIdx -lt 0) { throw "Cannot find end of second line (setState) after quick isConnected." }
$endLineIdx = $endLineIdx + 2

$before = $content.Substring(0, $quickIdx)
$after  = $content.Substring($endLineIdx)

$waitBlock = @"
var onNow = false;
for (var i = 0; i < 40; i++) {
  onNow = await _vpnBackend.isConnected();
  if (onNow) break;
  await Future.delayed(const Duration(milliseconds: 250));
}
if (mounted) setState(() => $vpnVar = onNow);
if (!onNow) {
  _toast(context, 'VPN did not start (service not RUNNING).');
  await _syncVpnStatus();
  return;
}
"@

$content2 = $before + $waitBlock + $after
Set-Content -LiteralPath $main -Value $content2 -Encoding UTF8
Write-Host "OK: connect wait-loop inserted (replaces quick isConnected)" -ForegroundColor Green

if (-not $SkipBuild) {
  $build = Join-Path $project "bluevpn_build_release.ps1"
  if (Test-Path -LiteralPath $build) {
    Write-Host "Running build: $build" -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File $build
  } else {
    Write-Host "Build script not found: bluevpn_build_release.ps1 (skipped)" -ForegroundColor Yellow
  }
}