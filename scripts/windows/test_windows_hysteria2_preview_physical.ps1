param(
    [string]$SourceConfig = 'C:\Users\gekto\GreenVPN_Checkpoints\hysteria2_contract_deploy_20260711\nl2-hysteria2-canary.hysteria2.yaml',
    [string]$ExpectedCanaryEgress = '5.129.216.42',
    [string]$CompetingServiceName = 'AmneziaWGTunnel$device20_full',
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\windows_hysteria2_preview_physical_20260712.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PreviewServiceName = 'GreenVPNTransportPreviewService'
$InstallRoot = Join-Path $env:ProgramFiles 'Green VPN Transport Preview'
$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'
$ConfigPath = Join-Path $ProgramDataRoot 'GreenVPNTransportPreview.conf'
$ProtocolPath = $ConfigPath + '.protocol'
$TokenPath = Join-Path $ProgramDataRoot 'service_token'
$RouteStatePath = Join-Path $ProgramDataRoot 'hysteria2-routes.json'
$EndpointRouteStatePath = $ConfigPath + '.endpoint-route.json'
$HysteriaPidPath = Join-Path $ProgramDataRoot 'hysteria2-client.pid'
$HevPidPath = Join-Path $ProgramDataRoot 'hysteria2-hev.pid'
$HysteriaExe = Join-Path $InstallRoot 'tools\hysteria2\hysteria-windows-amd64.exe'
$HevExe = Join-Path $InstallRoot 'tools\hysteria2\hev-socks5-tunnel.exe'
$ServiceBase = 'http://127.0.0.1:48739'
$AdapterName = 'GreenVPNHysteriaPreview'
$RouteMetric = 42732

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-ServiceState {
    param([string]$Name, [string]$State, [int]$Seconds = 30)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        $current = if ($null -eq $service) { 'Missing' } else { $service.Status.ToString() }
        if ($current -eq $State) { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Service $Name did not reach $State."
}

function Invoke-PreviewApi {
    param([ValidateSet('GET','POST')][string]$Method, [string]$Path)
    $token = (Get-Content -LiteralPath $TokenPath -Raw).Trim()
    $headers = @{ 'X-GreenVPN-Local-Token' = $token }
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Method $Method -Uri ($ServiceBase + $Path) -Headers $headers -TimeoutSec 130
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = ($response.Content | ConvertFrom-Json) }
    } catch {
        $statusCode = 0
        $body = $null
        if ($null -ne $_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            $reader = [IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            try { $body = ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose() }
        }
        return [pscustomobject]@{ StatusCode = $statusCode; Body = $body }
    }
}

function Wait-HysteriaState {
    param([bool]$Running, [int]$Seconds = 35)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $status = Invoke-PreviewApi -Method GET -Path '/status'
        $isRunning = $status.StatusCode -eq 200 -and
            $status.Body.protocol -eq 'hysteria2' -and
            $status.Body.tunnelState -eq 'running'
        if ($isRunning -eq $Running) { return $status }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Hysteria2 preview did not reach running=$Running."
}

function Get-PublicIp {
    foreach ($uri in @('https://api.ipify.org', 'https://ifconfig.me/ip')) {
        try {
            $value = (Invoke-RestMethod -Uri $uri -TimeoutSec 15).ToString().Trim()
            if ($value -match '^\d{1,3}(?:\.\d{1,3}){3}$') { return $value }
        } catch {}
    }
    return ''
}

function Get-HttpStatus {
    param([string]$Uri)
    try { return [int](Invoke-WebRequest -UseBasicParsing -Uri $Uri -Method Head -TimeoutSec 20).StatusCode } catch {
        if ($null -ne $_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

function Get-ExactProcess {
    param([string]$PidPath, [string]$ExpectedPath)
    if (-not (Test-Path -LiteralPath $PidPath)) { return $null }
    $processId = 0
    if (-not [int]::TryParse((Get-Content -LiteralPath $PidPath -Raw).Trim(), [ref]$processId)) { return $null }
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
    if ($null -eq $process -or [string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) { return $null }
    if (-not [IO.Path]::GetFullPath([string]$process.ExecutablePath).Equals([IO.Path]::GetFullPath($ExpectedPath), [StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $process
}

if (-not (Test-Path -LiteralPath $SourceConfig)) { throw "Source config is missing: $SourceConfig" }
if (-not (Test-IsAdministrator)) {
    $args = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $PSCommandPath + '"'),
        '-SourceConfig', ('"' + [IO.Path]::GetFullPath($SourceConfig) + '"'),
        '-ExpectedCanaryEgress', $ExpectedCanaryEgress,
        '-CompetingServiceName', ('"' + $CompetingServiceName + '"'),
        '-ReportPath', ('"' + [IO.Path]::GetFullPath($ReportPath) + '"')
    )
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $process.ExitCode
}

foreach ($path in @($HysteriaExe, $HevExe, $TokenPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Installed preview component is missing: $path" }
}
$service = Get-CimInstance Win32_Service -Filter "Name='$PreviewServiceName'"
if ($null -eq $service -or $service.State -ne 'Running' -or
    -not ([string]$service.PathName).StartsWith(('"' + $InstallRoot), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Protected transport preview service is not installed under Program Files.'
}
$competing = Get-Service -Name $CompetingServiceName -ErrorAction SilentlyContinue
if ($null -eq $competing -or $competing.Status -ne 'Running') { throw "Expected competing VPN is not running: $CompetingServiceName" }

$beforeEgress = Get-PublicIp
$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    sourceConfigSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceConfig).Hash
    beforeEgress = $beforeEgress
    competitorGuardStatus = 0
    serviceStatus = ''
    adapterPresent = $false
    endpointRouteInterface = ''
    splitRoutes = @()
    hysteriaProcessPathValid = $false
    hevProcessPathValid = $false
    canaryEgress = ''
    productionApiStatus = 0
    paidBetaPrimaryStatus = 0
    paidBetaFallbackStatus = 0
    youtubeStatus = 0
    watchdogCleanupPassed = $false
    restoredServiceState = ''
    restoredEgress = ''
    success = $false
    error = ''
}

try {
    $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Copy-Item -LiteralPath $SourceConfig -Destination $ConfigPath -Force
    [IO.File]::WriteAllText($ProtocolPath, 'hysteria2', [Text.UTF8Encoding]::new($false))
    & icacls.exe $ConfigPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' ('*' + $currentUserSid + ':R') | Out-Null
    & icacls.exe $ProtocolPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' ('*' + $currentUserSid + ':R') | Out-Null

    $blocked = Invoke-PreviewApi -Method POST -Path '/connect'
    $report.competitorGuardStatus = $blocked.StatusCode
    if ($blocked.StatusCode -ne 409) { throw 'Competing VPN guard did not fail closed with HTTP 409.' }

    Stop-Service -Name $CompetingServiceName -Force
    Wait-ServiceState -Name $CompetingServiceName -State 'Stopped'
    $connected = Invoke-PreviewApi -Method POST -Path '/connect'
    if ($connected.StatusCode -ne 200 -or $connected.Body.ok -ne $true) { throw "Hysteria2 connect failed with HTTP $($connected.StatusCode)." }
    $status = Wait-HysteriaState -Running $true
    $report.serviceStatus = [string]$status.Body.tunnelState
    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
    $report.adapterPresent = $null -ne $adapter -and $adapter.Status -eq 'Up'
    if (-not $report.adapterPresent) { throw 'Hysteria2 preview adapter is not up.' }

    $endpointRoute = Find-NetRoute -RemoteIPAddress '5.129.216.42' -ErrorAction Stop
    $report.endpointRouteInterface = [string]$endpointRoute.InterfaceAlias
    if ($report.endpointRouteInterface -eq $AdapterName) { throw 'Hysteria2 endpoint route recursed into the preview adapter.' }
    $routeState = Get-Content -LiteralPath $RouteStatePath -Raw | ConvertFrom-Json
    $report.splitRoutes = @($routeState.prefixes)
    if ([int]$routeState.metric -ne $RouteMetric -or @($routeState.prefixes).Count -ne 4) { throw 'Hysteria2 split-default route state is incomplete.' }

    $hysteriaProcess = Get-ExactProcess -PidPath $HysteriaPidPath -ExpectedPath $HysteriaExe
    $hevProcess = Get-ExactProcess -PidPath $HevPidPath -ExpectedPath $HevExe
    $report.hysteriaProcessPathValid = $null -ne $hysteriaProcess
    $report.hevProcessPathValid = $null -ne $hevProcess
    if (-not $report.hysteriaProcessPathValid -or -not $report.hevProcessPathValid) { throw 'Hysteria2 engine process path validation failed.' }

    $report.canaryEgress = Get-PublicIp
    if ($report.canaryEgress -ne $ExpectedCanaryEgress) { throw "Unexpected canary egress: $($report.canaryEgress)" }
    $report.productionApiStatus = Get-HttpStatus 'https://api.greenvpn.pro/healthz'
    $report.paidBetaPrimaryStatus = Get-HttpStatus 'https://api.greenvpn.pro/paid-beta-api/healthz'
    $report.paidBetaFallbackStatus = Get-HttpStatus 'https://176-113-81-35.sslip.io/paid-beta-api/healthz'
    $report.youtubeStatus = Get-HttpStatus 'https://www.youtube.com/'
    foreach ($key in @('productionApiStatus','paidBetaPrimaryStatus','paidBetaFallbackStatus','youtubeStatus')) {
        if ([int]$report[$key] -lt 200 -or [int]$report[$key] -ge 400) { throw "HTTP probe failed: $key=$($report[$key])" }
    }

    Stop-Process -Id ([int]$hevProcess.ProcessId) -Force
    $deadline = (Get-Date).AddSeconds(15)
    do {
        $enginesGone = $null -eq (Get-ExactProcess -PidPath $HysteriaPidPath -ExpectedPath $HysteriaExe) -and
            $null -eq (Get-ExactProcess -PidPath $HevPidPath -ExpectedPath $HevExe)
        $stateGone = -not (Test-Path -LiteralPath $RouteStatePath) -and -not (Test-Path -LiteralPath $EndpointRouteStatePath)
        if ($enginesGone -and $stateGone) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    $report.watchdogCleanupPassed = $enginesGone -and $stateGone
    if (-not $report.watchdogCleanupPassed) { throw 'Hysteria2 watchdog did not complete fail-safe cleanup.' }
    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    try { Invoke-PreviewApi -Method POST -Path '/disconnect' | Out-Null } catch {}
    try {
        if ((Get-Service -Name $CompetingServiceName -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service -Name $CompetingServiceName }
        Wait-ServiceState -Name $CompetingServiceName -State 'Running'
        $report.restoredServiceState = 'Running'
        Start-Sleep -Seconds 3
        $report.restoredEgress = Get-PublicIp
    } catch {
        $report.restoredServiceState = 'restore_failed'
        if (-not $report.error) { $report.error = $_.Exception.Message }
    }
    $report.restoredOriginalEgress = $beforeEgress -ne '' -and $report.restoredEgress -eq $beforeEgress
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($ReportPath))) | Out-Null
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success -or $report.restoredServiceState -ne 'Running' -or -not $report.restoredOriginalEgress) { exit 1 }
Write-Output "Windows Hysteria2 preview physical smoke passed. Report: $ReportPath"
