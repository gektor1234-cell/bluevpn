param(
    [Parameter(Mandatory=$true)][int]$HysteriaPid,
    [Parameter(Mandatory=$true)][int]$HevPid
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'
$InstallRoot = Join-Path $env:ProgramFiles 'Green VPN Transport Preview'
$HysteriaExe = Join-Path $InstallRoot 'tools\hysteria2\hysteria-windows-amd64.exe'
$HevExe = Join-Path $InstallRoot 'tools\hysteria2\hev-socks5-tunnel.exe'
$RouteStatePath = Join-Path $ProgramDataRoot 'hysteria2-routes.json'
$EndpointRouteStatePath = Join-Path $ProgramDataRoot 'GreenVPNTransportPreview.conf.endpoint-route.json'
$LogPath = Join-Path $ProgramDataRoot 'hysteria2-watchdog.log'
$RouteMetric = 42732
$EndpointRouteMetric = 42731

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
            [IO.Path]::GetFullPath($ExpectedPath),
            [StringComparison]::OrdinalIgnoreCase
        )
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
        if ($state.created -eq $true -and
            [int]$state.metric -eq $EndpointRouteMetric -and
            [string]$state.endpoint -match '^\d{1,3}(?:\.\d{1,3}){3}$') {
            Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "$($state.endpoint)/32" `
                -InterfaceIndex ([int]$state.interfaceIndex) -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.NextHop -eq [string]$state.nextHop -and
                    $_.RouteMetric -eq $EndpointRouteMetric
                } |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        }
    } catch {
        Write-WatchdogLog 'endpoint route cleanup warning'
    } finally {
        Remove-Item -LiteralPath $EndpointRouteStatePath -Force -ErrorAction SilentlyContinue
    }
}

try {
    Write-WatchdogLog "started hysteriaPid=$HysteriaPid hevPid=$HevPid"
    while ($true) {
        $hysteriaRunning = Test-ExactProcess -ProcessId $HysteriaPid -ExpectedPath $HysteriaExe
        $hevRunning = Test-ExactProcess -ProcessId $HevPid -ExpectedPath $HevExe
        if (-not $hysteriaRunning -or -not $hevRunning) {
            Write-WatchdogLog "engine exit detected hysteria=$hysteriaRunning hev=$hevRunning"
            break
        }
        Start-Sleep -Seconds 2
    }
} finally {
    Stop-ExactProcess -ProcessId $HevPid -ExpectedPath $HevExe
    Stop-ExactProcess -ProcessId $HysteriaPid -ExpectedPath $HysteriaExe
    Remove-ManagedRoutes
    Remove-ManagedEndpointRoute
    foreach ($name in @(
        'hysteria2-client.pid',
        'hysteria2-hev.pid',
        'hysteria2-watchdog.pid',
        'hysteria2-client.runtime.yaml',
        'hysteria2-hev.runtime.yaml'
    )) {
        Remove-Item -LiteralPath (Join-Path $ProgramDataRoot $name) -Force -ErrorAction SilentlyContinue
    }
    Write-WatchdogLog 'cleanup complete'
}

