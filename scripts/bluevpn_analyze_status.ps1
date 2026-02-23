<#
BlueVPN статус-репорт (WireGuard Windows) v2
- Ничего не чинит, только собирает отчёт.
- Важно: WireGuard использует UDP. TCP-тест порта не является доказательством “сервер не работает”.
#>

[CmdletBinding()]
param(
  [string]$TunnelName = "BlueVPN",
  [string]$ExpectedConfigPath = "C:\ProgramData\BlueVPN\BlueVPN.conf",
  [switch]$CopyToClipboard,
  [switch]$OpenReport
)

$ErrorActionPreference = "Stop"

function NowStr { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }

function Sanitize-Config([string]$text) {
  $lines = $text -split "`r?`n"
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($l in $lines) {
    if ($l -match '^\s*(PrivateKey|PresharedKey)\s*=') {
      $out.Add( ($l -replace '=\s*.*$', '= [REDACTED]') )
      continue
    }
    $out.Add($l)
  }
  return ($out -join "`r`n")
}

function Try-ReadFile([string]$path) {
  try {
    if (Test-Path -LiteralPath $path) { return Get-Content -LiteralPath $path -Raw -ErrorAction Stop }
    return $null
  } catch { return $null }
}

function Parse-PathName([string]$pathName) {
  $exe = $null; $cfg = $null
  if ([string]::IsNullOrWhiteSpace($pathName)) {
    return [pscustomobject]@{ ExePath=$null; ConfigPath=$null; Raw=$pathName }
  }
  $m = [regex]::Match($pathName, '^"([^"]+)"\s+\/tunnelservice\s+(.+)$')
  if ($m.Success) {
    $exe = $m.Groups[1].Value.Trim()
    $cfg = $m.Groups[2].Value.Trim().Trim('"')
    return [pscustomobject]@{ ExePath=$exe; ConfigPath=$cfg; Raw=$pathName }
  }
  $m2 = [regex]::Match($pathName, '^(.*?)\s+\/tunnelservice\s+(.+)$')
  if ($m2.Success) {
    $exe = $m2.Groups[1].Value.Trim().Trim('"')
    $cfg = $m2.Groups[2].Value.Trim().Trim('"')
  }
  return [pscustomobject]@{ ExePath=$exe; ConfigPath=$cfg; Raw=$pathName }
}

function Parse-Endpoint([string]$configText) {
  if ([string]::IsNullOrWhiteSpace($configText)) { return $null }
  $m = [regex]::Match($configText, '(?im)^\s*Endpoint\s*=\s*([^\s#]+)\s*$')
  if (-not $m.Success) { return $null }
  $ep = $m.Groups[1].Value.Trim()
  $m4 = [regex]::Match($ep, '^(.+):(\d+)$')
  if ($m4.Success) {
    return [pscustomobject]@{ Endpoint=$ep; Host=$m4.Groups[1].Value; Port=[int]$m4.Groups[2].Value }
  }
  return [pscustomobject]@{ Endpoint=$ep; Host=$ep; Port=$null }
}

function Is-IPv4([string]$s) { return [bool]([regex]::IsMatch($s, '^\d{1,3}(\.\d{1,3}){3}$')) }

function Safe-Section([string]$title, [string]$body) {
  $sep = ("=" * 78)
  return @($sep,$title,$sep,$body,"") -join "`r`n"
}

$serviceName = "WireGuardTunnel`$$TunnelName"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("BlueVPN Status Report (v2)")
$lines.Add("Generated: $(NowStr)")
$lines.Add("TunnelName: $TunnelName")
$lines.Add("Expected service: $serviceName")
$lines.Add("ExpectedConfigPath: $ExpectedConfigPath")
$lines.Add("")

# ALL tunnel services
$allSvc = @()
try {
  $allSvc = Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object { $_.Name -like 'WireGuardTunnel$*' }
} catch { $allSvc = @() }

if (-not $allSvc -or $allSvc.Count -eq 0) {
  $lines.Add( (Safe-Section "ALL WIREGUARD TUNNEL SERVICES" "None found (no WireGuardTunnel$* services).") )
} else {
  $b = @()
  foreach ($s in $allSvc) {
    $b += "Name: $($s.Name)"
    $b += "  State: $($s.State)  PID: $($s.ProcessId)  StartMode: $($s.StartMode)"
    $b += "  PathName: $($s.PathName)"
    $b += ""
  }
  $lines.Add( (Safe-Section "ALL WIREGUARD TUNNEL SERVICES" ($b -join "`r`n")) )
}

# Expected service details
$svc = $null
try { $svc = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop } catch { $svc = $null }

$exePath = $null
$configPathFromService = $null

if ($null -eq $svc) {
  $lines.Add( (Safe-Section "EXPECTED SERVICE" "NOT FOUND: $serviceName") )
} else {
  $body = @()
  $body += "State: $($svc.State)"
  $body += "Status: $($svc.Status)"
  $body += "StartMode: $($svc.StartMode)"
  $body += "ProcessId: $($svc.ProcessId)"
  $body += "PathName: $($svc.PathName)"
  $lines.Add( (Safe-Section "EXPECTED SERVICE" ($body -join "`r`n")) )

  $pp = Parse-PathName $svc.PathName
  $exePath = $pp.ExePath
  $configPathFromService = $pp.ConfigPath
  $b2 = @("ExePath: $exePath","ConfigPathFromService: $configPathFromService")
  if ($configPathFromService -and ($configPathFromService -ne $ExpectedConfigPath)) {
    $b2 += "WARNING: service uses different config path than ExpectedConfigPath."
  }
  $lines.Add( (Safe-Section "SERVICE PATH PARSE" ($b2 -join "`r`n")) )
}

# Read config (prefer service path)
$configPathToRead = $configPathFromService
if (-not $configPathToRead) { $configPathToRead = $ExpectedConfigPath }

$configText = $null
if ($configPathToRead) {
  $configText = Try-ReadFile $configPathToRead
  if ($configText -eq $null) {
    $lines.Add( (Safe-Section "CONFIG" "FAILED TO READ OR NOT FOUND: $configPathToRead") )
  } else {
    $lines.Add( (Safe-Section "CONFIG (SANITIZED)" (Sanitize-Config $configText)) )
  }
}

# Endpoint + notes
$epInfo = $null
if ($configText) { $epInfo = Parse-Endpoint $configText }

if ($epInfo -eq $null) {
  $lines.Add( (Safe-Section "ENDPOINT" "Endpoint not found in config.") )
} else {
  $b = @()
  $b += "Endpoint: $($epInfo.Endpoint)"
  $b += "Host: $($epInfo.Host)"
  $b += "Port: $($epInfo.Port)"
  $b += ""
  $b += "NOTE: WireGuard uses UDP. TCP test is not authoritative."
  try {
    $pingOk = Test-Connection -ComputerName $epInfo.Host -Count 1 -Quiet -ErrorAction Stop
    $b += "Ping(ICMP): $pingOk"
  } catch {
    $b += "Ping(ICMP): ERROR ($($_.Exception.Message))"
  }
  $lines.Add( (Safe-Section "ENDPOINT TESTS" ($b -join "`r`n")) )
}

# Default routes
try {
  $dr = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop |
    Sort-Object RouteMetric, InterfaceMetric
  $b = @()
  foreach ($r in $dr) {
    $b += ("{0,-18} via {1,-15} ifIndex={2,-4} if={3,-20} metric={4}" -f $r.DestinationPrefix, $r.NextHop, $r.ifIndex, $r.InterfaceAlias, $r.RouteMetric)
  }
  $lines.Add( (Safe-Section "DEFAULT ROUTES IPv4 (0.0.0.0/0)" ($b -join "`r`n")) )
} catch {
  $lines.Add( (Safe-Section "DEFAULT ROUTES IPv4 (0.0.0.0/0)" "Get-NetRoute ERROR: $($_.Exception.Message)") )
}

# Routes to endpoint (/32)
if ($epInfo -ne $null -and (Is-IPv4 $epInfo.Host)) {
  $ip = $epInfo.Host
  $rBody = @()
  try {
    $routes = Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.DestinationPrefix -eq "$ip/32" }
    if ($routes) {
      foreach ($r in $routes) {
        $rBody += ("{0}  via {1}  ifIndex={2}  if={3}  metric={4}" -f $r.DestinationPrefix, $r.NextHop, $r.ifIndex, $r.InterfaceAlias, $r.RouteMetric)
      }
    } else {
      $rBody += "No /32 route found for $ip via Get-NetRoute."
    }
  } catch { $rBody += "Get-NetRoute ERROR: $($_.Exception.Message)" }

  try {
    $routePrint = (route print -4) 2>&1 | Out-String
    $hit = ($routePrint -split "`r?`n") | Where-Object { $_ -match [regex]::Escape($ip) }
    $rBody += ""
    $rBody += "route print hits:"
    $rBody += ($(if ($hit) { $hit -join "`r`n" } else { "(none)" }))
  } catch { $rBody += "route print ERROR: $($_.Exception.Message)" }

  $lines.Add( (Safe-Section "ROUTES TO ENDPOINT (IPv4)" ($rBody -join "`r`n")) )
}

# Adapters (show all WireGuard tunnels)
try {
  $adapters = Get-NetAdapter -ErrorAction Stop
  $wg = $adapters | Where-Object { $_.InterfaceDescription -match 'WireGuard' }
  $b = @()
  if ($wg) {
    foreach ($a in $wg) {
      $b += ("Name={0}  Status={1}  ifIndex={2}  Desc={3}" -f $a.Name, $a.Status, $a.ifIndex, $a.InterfaceDescription)
    }
  } else {
    $b += "No WireGuard adapters found."
  }
  $lines.Add( (Safe-Section "WIREGUARD ADAPTERS" ($b -join "`r`n")) )
} catch {
  $lines.Add( (Safe-Section "WIREGUARD ADAPTERS" "Get-NetAdapter ERROR: $($_.Exception.Message)") )
}

# Processes with command line (critical)
try {
  $procs = Get-CimInstance Win32_Process -Filter "Name='wireguard.exe'" -ErrorAction Stop |
    Select-Object ProcessId, CommandLine
  $b = @()
  if ($procs) {
    foreach ($p in $procs) {
      $b += "PID: $($p.ProcessId)"
      $b += "  $($p.CommandLine)"
      $b += ""
    }
  } else {
    $b += "No wireguard.exe processes found."
  }
  $lines.Add( (Safe-Section "WIREGUARD PROCESSES (COMMAND LINE)" ($b -join "`r`n")) )
} catch {
  $lines.Add( (Safe-Section "WIREGUARD PROCESSES (COMMAND LINE)" "Win32_Process ERROR: $($_.Exception.Message)") )
}

# Hints
$hint = @()
if ($null -eq $svc) {
  $hint += "Expected service missing => tunnel is OFF (or named differently)."
  if ($allSvc -and $allSvc.Count -gt 0) { $hint += "Other tunnel services exist. See section ALL WIREGUARD TUNNEL SERVICES." }
} else {
  $hint += "Expected service exists => tunnel should be ON."
}
$hint += "If using AllowedIPs=0.0.0.0/0, endpoint MUST have bypass /32 route via physical gateway."
$lines.Add( (Safe-Section "DIAGNOSIS HINTS" ($hint -join "`r`n")) )

# Write report
$outDir = Join-Path $env:USERPROFILE "Desktop\BlueVPN_Reports"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$outFile = Join-Path $outDir "BlueVPN_Status_$stamp.txt"

$report = ($lines -join "`r`n")
Set-Content -LiteralPath $outFile -Value $report -Encoding UTF8

Write-Host ""
Write-Host "Report saved:" -ForegroundColor Cyan
Write-Host $outFile -ForegroundColor Cyan

if ($CopyToClipboard) {
  try { Set-Clipboard -Value $report; Write-Host "Copied to clipboard." -ForegroundColor Green }
  catch { Write-Host "Clipboard copy failed: $($_.Exception.Message)" -ForegroundColor Yellow }
}

if ($OpenReport) { try { notepad $outFile | Out-Null } catch {} }
