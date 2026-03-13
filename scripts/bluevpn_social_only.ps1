[CmdletBinding()]
param(
  [ValidateSet("enable","disable")]
  [string]$Mode = "enable",

  # Можно так:
  # -Apps telegram instagram youtube
  # или так:
  # -Apps "telegram,instagram,youtube"
  [string[]]$Apps = @("telegram","instagram","youtube"),

  [string]$TunnelName = "BlueVPN",
  [string]$ConfigPath = "C:\ProgramData\BlueVPN\BlueVPN.conf",

  # ограничение чтобы не раздувать AllowedIPs
  [int]$MaxIPsPerDomain = 40
)

$ErrorActionPreference = "Stop"

function Test-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Self-elevate (so you can run it from a normal PowerShell)
if (-not (Test-Admin)) {
  Write-Host "Requesting UAC (run as Administrator)..." -ForegroundColor Yellow
  $argList = @(
    "-NoProfile",
    "-ExecutionPolicy","Bypass",
    "-File","`"$PSCommandPath`""
  ) + $MyInvocation.UnboundArguments

  $p = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList -Wait -PassThru
  exit $p.ExitCode
}

# Normalize -Apps (support comma-separated single argument)
if ($Apps -and $Apps.Count -eq 1 -and ($Apps[0] -match ",")) {
  $Apps = $Apps[0].Split(",") | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }
} elseif ($Apps) {
  $Apps = $Apps | ForEach-Object { $_.ToString().Trim().ToLowerInvariant() } | Where-Object { $_ }
}

function Get-ServiceName([string]$tn) { "WireGuardTunnel`$$tn" }

function Read-Config([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Config not found: $path" }
  return Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

function Get-DnsFromConfig([string]$cfgText) {
  $m = [regex]::Match($cfgText, '(?im)^\s*DNS\s*=\s*(.+?)\s*$')
  if (-not $m.Success) { return @() }
  return ($m.Groups[1].Value -split '\s*,\s*' | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
}

function Replace-AllowedIPs([string]$cfgText, [string]$allowedValue) {
  if ($cfgText -notmatch '(?im)^\s*AllowedIPs\s*=') {
    throw "AllowedIPs line not found in config."
  }
  return [regex]::Replace(
    $cfgText,
    '(?im)^\s*AllowedIPs\s*=.*$',
    ("AllowedIPs = " + $allowedValue),
    1
  )
}

function Write-ConfigAtomic([string]$path, [string]$text) {
  $tmp = "$path.tmp"
  Set-Content -LiteralPath $tmp -Value $text -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $path -Force
}

$domainMap = @{
  telegram   = @("t.me","telegram.org","telegram.me","cdn-telegram.org","telesco.pe","telegram.dog")
  instagram  = @("instagram.com","i.instagram.com","cdninstagram.com","fbcdn.net")
  youtube    = @("youtube.com","www.youtube.com","m.youtube.com","googlevideo.com","ytimg.com","youtubei.googleapis.com")
  tiktok     = @("tiktok.com","www.tiktok.com","tiktokcdn.com","byteoversea.com")
  x          = @("x.com","twitter.com","t.co","twimg.com")
  discord    = @("discord.com","discord.gg","discordapp.com","discordapp.net")
  reddit     = @("reddit.com","www.reddit.com","redd.it","redditmedia.com","redditstatic.com")
  facebook   = @("facebook.com","fb.com","messenger.com","fbcdn.net")
}

function Resolve-DomainsToIPs([string[]]$domains, [int]$capPerDomain) {
  $set = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($d in $domains) {
    try {
      $res = Resolve-DnsName -Name $d -Type A -ErrorAction Stop |
        Select-Object -ExpandProperty IPAddress -ErrorAction SilentlyContinue
      if ($res) {
        $cnt = 0
        foreach ($ip in $res) {
          if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') {
            [void]$set.Add($ip)
            $cnt++
            if ($cnt -ge $capPerDomain) { break }
          }
        }
      }
    } catch {}
  }
  return ,$set   # IMPORTANT: return as single object (avoid HashSet unroll into string[])
}

function Restart-TunnelIfRunning([string]$svc) {
  $q = sc.exe query $svc 2>$null | Out-String
  if (-not $q) { return }
  if ($q -match 'STATE\s*:\s*\d+\s+RUNNING') {
    sc.exe stop $svc | Out-Null
    for ($i=0; $i -lt 80; $i++) {
      $qq = sc.exe query $svc 2>$null | Out-String
      if ($qq -match 'STATE\s*:\s*\d+\s+STOPPED') { break }
      Start-Sleep -Milliseconds 200
    }
    sc.exe start $svc | Out-Null
  }
}

$svc = Get-ServiceName $TunnelName
$cfg = Read-Config $ConfigPath

# backup (once)
$bak = "$ConfigPath.full.bak"
if (-not (Test-Path -LiteralPath $bak)) {
  Copy-Item -LiteralPath $ConfigPath -Destination $bak -Force
}

if ($Mode -eq "disable") {
  $newText = Replace-AllowedIPs $cfg "0.0.0.0/0, ::/0"
  Write-ConfigAtomic $ConfigPath $newText
  Restart-TunnelIfRunning $svc
  Write-Host "OK: Social-only DISABLED. Restored full tunnel AllowedIPs." -ForegroundColor Green
  exit 0
}

# enable
$domains = New-Object System.Collections.Generic.List[string]
foreach ($a in $Apps) {
  if ($domainMap.ContainsKey($a)) {
    foreach ($d in $domainMap[$a]) { [void]$domains.Add($d) }
  } else {
    Write-Host "WARN: unknown app '$a' (skip). Known: $($domainMap.Keys -join ', ')" -ForegroundColor Yellow
  }
}
if ($domains.Count -eq 0) { throw "No domains selected. Apps=$($Apps -join ',')" }

$dns = Get-DnsFromConfig $cfg
$ips = Resolve-DomainsToIPs $domains.ToArray() $MaxIPsPerDomain

# include DNS server IPs
foreach ($d in $dns) { [void]$ips.Add($d) }

if ($ips.Count -eq 0) { throw "DNS resolve returned 0 IPs. Try again later or change DNS." }

$allowed = ($ips | Sort-Object | ForEach-Object { "$_/32" }) -join ", "

$newText2 = Replace-AllowedIPs $cfg $allowed
Write-ConfigAtomic $ConfigPath $newText2
Restart-TunnelIfRunning $svc

Write-Host "OK: Social-only ENABLED for: $($Apps -join ', ')" -ForegroundColor Green
Write-Host "IPs in AllowedIPs: $($ips.Count)" -ForegroundColor Cyan
