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

if ($content -match "final\s+onNow\s*=\s*await\s+_vpnBackend\.isConnected\(\);") {
  Write-Host "Already patched (onNow/isConnected exists). Skipping." -ForegroundColor Yellow
  exit 0
}

# detect vpn state var name from the toggle handler area (usually: if (!vpnOn) { ... connect ... } else { ... disconnect ... })
$needle = "final res = await _vpnBackend.connect"
$idx = $content.IndexOf($needle)
if ($idx -lt 0) { throw "Cannot find connect() call: $needle" }

$segStart = [Math]::Max(0, $idx - 4000)
$seg = $content.Substring($segStart, $idx - $segStart)

$m = [regex]::Match($seg, "if\s*\(\s*!\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\{", "Singleline")
if (-not $m.Success) { throw "Cannot detect vpn state variable (pattern: if (!<var>) { )." }

$vpnVar = $m.Groups[1].Value
Write-Host "Detected VPN state var: $vpnVar" -ForegroundColor Green

function Patch-ToastBlock([string]$text, [string]$toastText, [string]$toastWhenTrue, [string]$toastWhenFalse) {
  # patch: await _syncVpnStatus(); _toast(context, '...');  =>  await _sync; final onNow=...; setState(...); toast based on onNow
  $pattern = "(?s)(await\s+_syncVpnStatus\(\);\s*\r?\n)(\s*)_toast\(context,\s*'$([regex]::Escape($toastText))'\s*\);\s*"
  $rx = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  if (-not $rx.IsMatch($text)) {
    throw "Toast block not found for: $toastText"
  }

  return $rx.Replace($text, {
    param($mm)
    $p1 = $mm.Groups[1].Value
    $indent = $mm.Groups[2].Value
    return (
      $p1 +
      $indent + "final onNow = await _vpnBackend.isConnected();" + "`r`n" +
      $indent + "if (mounted) setState(() => $vpnVar = onNow);" + "`r`n" +
      $indent + "_toast(context, onNow ? '$toastWhenTrue' : '$toastWhenFalse');" + "`r`n"
    )
  }, 1)
}

# connect toast patch
$content2 = $content
$content2 = Patch-ToastBlock $content2 "VPN включён." "VPN включён." "VPN не включился (сервис не RUNNING)."

# disconnect toast patch
$content2 = Patch-ToastBlock $content2 "VPN выключен." "VPN выключен." "VPN не выключился (сервис RUNNING)."

Set-Content -LiteralPath $main -Value $content2 -Encoding UTF8
Write-Host "Patched: lib\main.dart (UI vpnOn synced with isConnected)" -ForegroundColor Green

if (-not $SkipBuild) {
  $build = Join-Path $project "bluevpn_build_release.ps1"
  if (Test-Path -LiteralPath $build) {
    Write-Host "Running build: $build" -ForegroundColor Cyan
    powershell -NoProfile -ExecutionPolicy Bypass -File $build
  } else {
    Write-Host "Build script not found: bluevpn_build_release.ps1 (skipped)" -ForegroundColor Yellow
  }
}