param(
    [Parameter(Mandatory=$true)][int]$NaivePid,
    [Parameter(Mandatory=$true)][int]$HevPid
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'
$InstallRoot = Join-Path $env:ProgramFiles 'Green VPN Transport Preview'
$NaiveExe = Join-Path $InstallRoot 'tools\naive-https\naive.exe'
$HevExe = Join-Path $InstallRoot 'tools\naive-https\hev-socks5-tunnel.exe'
$RouteStatePath = Join-Path $ProgramDataRoot 'naive-https-routes.json'
$EndpointRouteStatePath = Join-Path $ProgramDataRoot 'GreenVPNTransportPreview.conf.endpoint-route.json'
$LogPath = Join-Path $ProgramDataRoot 'naive-https-watchdog.log'
$RouteMetric = 42734
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
            [string]$state.endpoint -match '^\d{1,3}(?:\.\d{1,3}){3}$') {
            Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "$($state.endpoint)/32" `
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
    Write-WatchdogLog "started naivePid=$NaivePid hevPid=$HevPid"
    while ($true) {
        $naiveRunning = Test-ExactProcess -ProcessId $NaivePid -ExpectedPath $NaiveExe
        $hevRunning = Test-ExactProcess -ProcessId $HevPid -ExpectedPath $HevExe
        if (-not $naiveRunning -or -not $hevRunning) {
            Write-WatchdogLog "engine exit detected naive=$naiveRunning hev=$hevRunning"
            break
        }
        Start-Sleep -Seconds 2
    }
} finally {
    Stop-ExactProcess -ProcessId $HevPid -ExpectedPath $HevExe
    Stop-ExactProcess -ProcessId $NaivePid -ExpectedPath $NaiveExe
    Remove-ManagedRoutes
    Remove-ManagedEndpointRoute
    foreach ($name in @(
        'naive-https-client.pid',
        'naive-https-hev.pid',
        'naive-https-watchdog.pid',
        'naive-https-client.runtime.json',
        'naive-https-hev.runtime.yaml',
        'naive-https-client.stdout.log',
        'naive-https-client.stderr.log',
        'naive-https-hev.stdout.log',
        'naive-https-hev.stderr.log'
    )) {
        Remove-Item -LiteralPath (Join-Path $ProgramDataRoot $name) -Force -ErrorAction SilentlyContinue
    }
    Write-WatchdogLog 'cleanup complete'
}
