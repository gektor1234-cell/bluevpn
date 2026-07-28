param(
    [Parameter(Mandatory=$true)][int]$DnsttPid,
    [Parameter(Mandatory=$true)][int]$HevPid
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'
$InstallRoot = Join-Path $env:ProgramFiles 'Green VPN Transport Preview'
$DnsttExe = Join-Path $InstallRoot 'tools\dnstt\dnstt-client-windows-amd64.exe'
$HevExe = Join-Path $InstallRoot 'tools\dnstt\hev-socks5-tunnel.exe'
$RouteStatePath = Join-Path $ProgramDataRoot 'dnstt-routes.json'
$EndpointRouteStatePath = Join-Path $ProgramDataRoot 'GreenVPNTransportPreview.conf.endpoint-route.json'
$LogPath = Join-Path $ProgramDataRoot 'dnstt-watchdog.log'
$RouteMetric = 42735
$EndpointRouteMetric = 42731
$ResolverIp = '1.1.1.1'

function Write-WatchdogLog {
    param([string]$Message)
    try { Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "[$((Get-Date).ToString('o'))] $Message" } catch {}
}

function Test-ExactProcess {
    param([int]$ProcessId, [string]$ExpectedPath)
    try {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
        if ($null -eq $process -or [string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) { return $false }
        return [IO.Path]::GetFullPath([string]$process.ExecutablePath).Equals(
            [IO.Path]::GetFullPath($ExpectedPath), [StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

function Stop-ExactProcess {
    param([int]$ProcessId, [string]$ExpectedPath)
    if (Test-ExactProcess -ProcessId $ProcessId -ExpectedPath $ExpectedPath) {
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Remove-ManagedRoutes {
    if (-not (Test-Path -LiteralPath $RouteStatePath)) { return }
    try {
        $state = Get-Content -LiteralPath $RouteStatePath -Raw | ConvertFrom-Json
        if ([int]$state.metric -ne $RouteMetric) { return }
        foreach ($prefix in @($state.prefixes)) {
            if ($prefix -notin @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')) { continue }
            Get-NetRoute -DestinationPrefix $prefix -InterfaceIndex ([int]$state.interfaceIndex) -ErrorAction SilentlyContinue |
                Where-Object { $_.RouteMetric -eq $RouteMetric } |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        }
    } catch {
        Write-WatchdogLog 'route cleanup warning'
    } finally {
        Remove-Item -LiteralPath $RouteStatePath -Force -ErrorAction SilentlyContinue
    }
}

function Remove-ManagedEndpointRoute {
    if (-not (Test-Path -LiteralPath $EndpointRouteStatePath)) { return }
    try {
        $state = Get-Content -LiteralPath $EndpointRouteStatePath -Raw | ConvertFrom-Json
        if ($state.created -eq $true -and [int]$state.metric -eq $EndpointRouteMetric -and
            [string]$state.endpoint -eq $ResolverIp) {
            Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "$ResolverIp/32" `
                -InterfaceIndex ([int]$state.interfaceIndex) -ErrorAction SilentlyContinue |
                Where-Object { $_.NextHop -eq [string]$state.nextHop -and $_.RouteMetric -eq $EndpointRouteMetric } |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        }
    } catch {
        Write-WatchdogLog 'endpoint route cleanup warning'
    } finally {
        Remove-Item -LiteralPath $EndpointRouteStatePath -Force -ErrorAction SilentlyContinue
    }
}

try {
    Write-WatchdogLog "started dnsttPid=$DnsttPid hevPid=$HevPid"
    while ($true) {
        $dnsttRunning = Test-ExactProcess -ProcessId $DnsttPid -ExpectedPath $DnsttExe
        $hevRunning = Test-ExactProcess -ProcessId $HevPid -ExpectedPath $HevExe
        if (-not $dnsttRunning -or -not $hevRunning) {
            Write-WatchdogLog "engine exit detected dnstt=$dnsttRunning hev=$hevRunning"
            break
        }
        Start-Sleep -Seconds 2
    }
} finally {
    Stop-ExactProcess -ProcessId $HevPid -ExpectedPath $HevExe
    Stop-ExactProcess -ProcessId $DnsttPid -ExpectedPath $DnsttExe
    Remove-ManagedRoutes
    Remove-ManagedEndpointRoute
    foreach ($name in @(
        'dnstt-client.pid',
        'dnstt-hev.pid',
        'dnstt-watchdog.pid',
        'dnstt-client.runtime.json',
        'dnstt-hev.runtime.yaml',
        'dnstt-client.stdout.log',
        'dnstt-client.stderr.log',
        'dnstt-hev.stdout.log',
        'dnstt-hev.stderr.log'
    )) {
        Remove-Item -LiteralPath (Join-Path $ProgramDataRoot $name) -Force -ErrorAction SilentlyContinue
    }
    Write-WatchdogLog 'cleanup complete'
}
