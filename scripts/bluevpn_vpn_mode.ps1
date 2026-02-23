[CmdletBinding()]
param(
  [ValidateSet("warp","bluevpn")]
  [string]$Mode,

  [string]$TunnelName = "BlueVPN",
  [string]$WarpAlias  = "warp1234",

  [string]$ConfigPath = "C:\ProgramData\BlueVPN\BlueVPN.conf",
  [string]$WireGuardExe = "C:\Program Files\WireGuard\wireguard.exe",

  [string]$EndpointIP = "5.129.237.163",

  [int]$MetricPrimary = 5,
  [int]$MetricSecondary = 50,
  [int]$MetricPhysical = 100,

  [int]$TimeoutSec = 15
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run as Administrator."
  }
}

function SvcName([string]$name) { "WireGuardTunnel`$$name" }

function Get-Svc([string]$name) {
  try { Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction Stop } catch { $null }
}

function Wait-Until([scriptblock]$cond, [int]$timeoutSec) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  do {
    if (& $cond) { return $true }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Adapter-Exists([string]$alias) {
  try { return [bool](Get-NetAdapter -Name $alias -ErrorAction Stop) } catch { return $false }
}

function IPIf-Exists([string]$alias) {
  try { return [bool](Get-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction Stop) } catch { return $false }
}

function Ensure-EndpointBypassActiveAndPersistent([string]$ip, [int]$ifIndex, [string]$gw) {
  route delete $ip 2>$null | Out-Null
  route add  $ip mask 255.255.255.255 $gw metric 1 if $ifIndex
  route -p add $ip mask 255.255.255.255 $gw metric 1 if $ifIndex
}

function Get-PhysicalDefault {
  $r = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" |
    Where-Object { $_.NextHop -ne "0.0.0.0" -and $_.InterfaceAlias -notmatch "WireGuard" } |
    Sort-Object RouteMetric, InterfaceMetric |
    Select-Object -First 1
  if (-not $r) { throw "Cannot detect physical default route (Ethernet/Wi-Fi)." }
  return $r
}

function Try-SetMetric([string]$alias, [int]$metric) {
  if (-not (IPIf-Exists $alias)) {
    Write-Host "WARN: IP interface not found: $alias (skip metric)" -ForegroundColor Yellow
    return $false
  }
  try {
    Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -AutomaticMetric Disabled -InterfaceMetric $metric -ErrorAction Stop | Out-Null
    return $true
  } catch {
    Write-Host "WARN: Set-NetIPInterface failed for $alias : $($_.Exception.Message)" -ForegroundColor Yellow
    return $false
  }
}

function Start-BlueVPN {
  if (-not (Test-Path -LiteralPath $WireGuardExe)) { throw "wireguard.exe not found: $WireGuardExe" }
  if (-not (Test-Path -LiteralPath $ConfigPath))  { throw "Config not found: $ConfigPath" }

  $svc = SvcName $TunnelName
  $s = Get-Svc $svc

  if (-not $s) {
    & $WireGuardExe /installtunnelservice $ConfigPath | Out-Null
  } else {
    # если есть, просто стартуем
    sc.exe start $svc | Out-Null
  }

  # ждём RUNNING
  $ok = Wait-Until { 
    $x = Get-Svc $svc
    $x -and $x.State -eq "Running"
  } $TimeoutSec

  if (-not $ok) {
    $x = Get-Svc $svc
    Write-Host "WARN: service not Running yet. Current: $($x.State)" -ForegroundColor Yellow
  }

  # ждём появления адаптера BlueVPN (может появляться чуть позже)
  [void](Wait-Until { Adapter-Exists $TunnelName } $TimeoutSec)
}

function Stop-BlueVPN {
  $svc = SvcName $TunnelName
  $s = Get-Svc $svc
  if (-not $s) { return }

  sc.exe stop $svc | Out-Null

  # ждём STOPPED
  $ok = Wait-Until {
    $x = Get-Svc $svc
    $x -and $x.State -eq "Stopped"
  } $TimeoutSec

  if (-not $ok) {
    $x = Get-Svc $svc
    Write-Host "WARN: service did not reach STOPPED. Current: $($x.State)" -ForegroundColor Yellow
  }
}

function Show-Summary([string]$title, $phys) {
  Write-Host ""
  Write-Host "==== $title ====" -ForegroundColor Cyan

  Get-NetAdapter -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceDescription -match "WireGuard" -or $_.Name -in @($TunnelName,$WarpAlias) } |
    Select-Object Name, Status, ifIndex, InterfaceDescription |
    Format-Table -AutoSize

  Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -in @($TunnelName,$WarpAlias,$phys.InterfaceAlias) } |
    Select-Object InterfaceAlias, AutomaticMetric, InterfaceMetric |
    Format-Table -AutoSize

  Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    Sort-Object RouteMetric, InterfaceMetric |
    Select-Object DestinationPrefix, NextHop, InterfaceAlias, ifIndex, RouteMetric, InterfaceMetric |
    Format-Table -AutoSize

  route print -4 | findstr $EndpointIP
}

# ---- MAIN ----
Assert-Admin

$phys = Get-PhysicalDefault
Ensure-EndpointBypassActiveAndPersistent -ip $EndpointIP -ifIndex $phys.ifIndex -gw $phys.NextHop

if ($Mode -eq "warp") {
  Stop-BlueVPN

  $okW = Try-SetMetric $WarpAlias $MetricPrimary
  $okP = Try-SetMetric $phys.InterfaceAlias $MetricPhysical
  $okB = Try-SetMetric $TunnelName 5000

  Write-Host "Metrics set: WARP=$okW, Physical=$okP, BlueVPN(deprioritize)=$okB" -ForegroundColor Green
  Show-Summary "MODE = WARP (fallback)" $phys
  exit 0
}

if ($Mode -eq "bluevpn") {
  Start-BlueVPN

  $okB = Try-SetMetric $TunnelName $MetricPrimary
  $okW = Try-SetMetric $WarpAlias  $MetricSecondary
  $okP = Try-SetMetric $phys.InterfaceAlias $MetricPhysical

  Write-Host "Metrics set: BlueVPN=$okB, WARP=$okW, Physical=$okP" -ForegroundColor Green
  Show-Summary "MODE = BLUEVPN (primary)" $phys
  exit 0
}
