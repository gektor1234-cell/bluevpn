param(
    [Parameter(Mandatory=$true)]
    [string]$SourceConfig,
    [string]$ExpectedCanaryEgress = '5.129.216.42',
    [string]$CompetingServiceName = 'AmneziaWGTunnel$device20_full',
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\windows_awg2_preview_physical_20260711.json',
    [string]$TaskScriptSource = (Join-Path $PSScriptRoot 'greenvpn_transport_preview_vpn_task.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PreviewServiceName = 'GreenVPNTransportPreviewService'
$PreviewTunnelService = 'AmneziaWGTunnel$GreenVPNTransportPreview'
$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'
$ConfigPath = Join-Path $ProgramDataRoot 'GreenVPNTransportPreview.conf'
$ProtocolPath = $ConfigPath + '.protocol'
$TokenPath = Join-Path $ProgramDataRoot 'service_token'
$ServiceBase = 'http://127.0.0.1:48739'
$InstallRoot = Join-Path $env:ProgramFiles 'Green VPN Transport Preview'
$AwgExe = Join-Path $InstallRoot 'tools\amneziawg2\awg.exe'
$InstalledTaskScript = Join-Path $InstallRoot 'tools\greenvpn_transport_preview_vpn_task.ps1'

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
    if ($token.Length -lt 24) { throw 'Preview service token is unavailable.' }
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
    try {
        return [int](Invoke-WebRequest -UseBasicParsing -Uri $Uri -Method Head -TimeoutSec 20).StatusCode
    } catch {
        if ($null -ne $_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

if (-not (Test-Path -LiteralPath $SourceConfig)) { throw "Source config is missing: $SourceConfig" }
if (-not (Test-Path -LiteralPath $AwgExe)) { throw 'Pinned AmneziaWG CLI is missing.' }
if (-not (Test-Path -LiteralPath $TokenPath)) { throw 'Preview service token is missing.' }
if ((Get-Service -Name $PreviewServiceName -ErrorAction SilentlyContinue).Status -ne 'Running') {
    throw 'Preview system service is not running.'
}

if (-not (Test-IsAdministrator)) {
    $args = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $PSCommandPath + '"'),
        '-SourceConfig', ('"' + [IO.Path]::GetFullPath($SourceConfig) + '"'),
        '-ExpectedCanaryEgress', $ExpectedCanaryEgress,
        '-CompetingServiceName', ('"' + $CompetingServiceName + '"'),
        '-ReportPath', ('"' + [IO.Path]::GetFullPath($ReportPath) + '"')
    )
    if ($TaskScriptSource) { $args += @('-TaskScriptSource', ('"' + [IO.Path]::GetFullPath($TaskScriptSource) + '"')) }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $process.ExitCode
}

$CurrentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

$competing = Get-Service -Name $CompetingServiceName -ErrorAction SilentlyContinue
if ($null -eq $competing -or $competing.Status -ne 'Running') {
    throw "Expected competing VPN service is not running: $CompetingServiceName"
}

if ($TaskScriptSource) {
    if (-not (Test-Path -LiteralPath $TaskScriptSource)) { throw 'Updated preview task script is missing.' }
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile([IO.Path]::GetFullPath($TaskScriptSource), [ref]$null, [ref]$parseErrors) | Out-Null
    if (@($parseErrors).Count -gt 0) { throw 'Updated preview task script failed PowerShell parsing.' }
    Copy-Item -LiteralPath $TaskScriptSource -Destination $InstalledTaskScript -Force
}

$beforeEgress = Get-PublicIp
$startedAt = (Get-Date).ToUniversalTime()
$report = [ordered]@{
    startedAt = $startedAt.ToString('o')
    sourceConfigSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceConfig).Hash
    beforeEgress = $beforeEgress
    competitorGuardStatus = 0
    canaryEgress = ''
    canaryServiceState = ''
    tunnelGatewayReachable = $false
    interfacePresent = $false
    latestHandshakeEpoch = 0
    handshakeFresh = $false
    receivedBytes = 0
    sentBytes = 0
    endpointRouteInterface = ''
    productionApiStatus = 0
    paidBetaPrimaryStatus = 0
    paidBetaFallbackStatus = 0
    youtubeStatus = 0
    restoredServiceState = ''
    restoredEgress = ''
    success = $false
    error = ''
}

try {
    New-Item -ItemType Directory -Force -Path $ProgramDataRoot | Out-Null
    Copy-Item -LiteralPath $SourceConfig -Destination $ConfigPath -Force
    [IO.File]::WriteAllText($ProtocolPath, 'amneziawg', [Text.UTF8Encoding]::new($false))
    & attrib.exe +H $ConfigPath $ProtocolPath 2>$null | Out-Null
    & icacls.exe $ConfigPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' ('*' + $CurrentUserSid + ':R') | Out-Null
    & icacls.exe $ProtocolPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' ('*' + $CurrentUserSid + ':R') | Out-Null

    $blocked = Invoke-PreviewApi -Method POST -Path '/connect'
    $report.competitorGuardStatus = $blocked.StatusCode
    if ($blocked.StatusCode -ne 409) { throw 'Competing VPN guard did not fail closed with HTTP 409.' }
    if (Get-Service -Name $PreviewTunnelService -ErrorAction SilentlyContinue) {
        throw 'Preview tunnel service exists after the competitor guard rejection.'
    }

    Stop-Service -Name $CompetingServiceName -Force
    Wait-ServiceState -Name $CompetingServiceName -State 'Stopped' -Seconds 30

    $connected = Invoke-PreviewApi -Method POST -Path '/connect'
    if ($connected.StatusCode -ne 200 -or $connected.Body.ok -ne $true) {
        throw "Preview connect failed with HTTP $($connected.StatusCode)."
    }
    Wait-ServiceState -Name $PreviewTunnelService -State 'Running' -Seconds 30
    Start-Sleep -Seconds 3

    $status = Invoke-PreviewApi -Method GET -Path '/status'
    $report.canaryServiceState = [string]$status.Body.tunnelState
    if ($status.StatusCode -ne 200 -or $status.Body.protocol -ne 'amneziawg' -or $status.Body.tunnelState -ne 'running') {
        throw 'Preview status does not report a running AmneziaWG tunnel.'
    }

    $report.interfacePresent = $null -ne (Get-NetAdapter -Name 'GreenVPNTransportPreview' -ErrorAction SilentlyContinue)
    try {
        $endpointRoute = Find-NetRoute -RemoteIPAddress '5.129.216.42' -ErrorAction Stop
        $report.endpointRouteInterface = [string]$endpointRoute.InterfaceAlias
    } catch {}
    $report.tunnelGatewayReachable = [bool](Test-Connection -ComputerName '10.202.0.1' -Count 2 -Quiet -ErrorAction SilentlyContinue)
    & ping.exe -n 2 -w 3000 1.1.1.1 2>$null | Out-Null
    Start-Sleep -Seconds 2

    $dump = @(& $AwgExe show GreenVPNTransportPreview dump 2>$null)
    $peerRows = @($dump | Select-Object -Skip 1)
    foreach ($row in $peerRows) {
        $parts = @($row -split "`t")
        if ($parts.Count -lt 8) { continue }
        $epoch = [int64]$parts[4]
        if ($epoch -gt [int64]$report.latestHandshakeEpoch) { $report.latestHandshakeEpoch = $epoch }
        $report.receivedBytes = [int64]$report.receivedBytes + [int64]$parts[5]
        $report.sentBytes = [int64]$report.sentBytes + [int64]$parts[6]
    }
    if ([int64]$report.latestHandshakeEpoch -gt 0) {
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int64]$report.latestHandshakeEpoch
        $report.handshakeFresh = ($age -ge 0 -and $age -le 180)
    }
    if (-not $report.handshakeFresh) { throw 'No fresh AmneziaWG handshake was observed.' }

    $report.canaryEgress = Get-PublicIp
    if ($ExpectedCanaryEgress -ne 'SKIP' -and $report.canaryEgress -ne $ExpectedCanaryEgress) {
        throw "Unexpected canary egress: $($report.canaryEgress)"
    }

    if ($ExpectedCanaryEgress -ne 'SKIP') {
        $report.productionApiStatus = Get-HttpStatus 'https://api.greenvpn.pro/healthz'
        $report.paidBetaPrimaryStatus = Get-HttpStatus 'https://api.greenvpn.pro/paid-beta-api/healthz'
        $report.paidBetaFallbackStatus = Get-HttpStatus 'https://176-113-81-35.sslip.io/paid-beta-api/healthz'
        $report.youtubeStatus = Get-HttpStatus 'https://www.youtube.com/'
        foreach ($key in @('productionApiStatus','paidBetaPrimaryStatus','paidBetaFallbackStatus','youtubeStatus')) {
            if ([int]$report[$key] -lt 200 -or [int]$report[$key] -ge 400) { throw "HTTP probe failed: $key=$($report[$key])" }
        }
    }
    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    try { Invoke-PreviewApi -Method POST -Path '/disconnect' | Out-Null } catch {}
    try {
        if ((Get-Service -Name $CompetingServiceName -ErrorAction SilentlyContinue).Status -ne 'Running') {
            Start-Service -Name $CompetingServiceName
        }
        Wait-ServiceState -Name $CompetingServiceName -State 'Running' -Seconds 30
        $report.restoredServiceState = 'Running'
        Start-Sleep -Seconds 3
        $report.restoredEgress = Get-PublicIp
    } catch {
        $report.restoredServiceState = 'restore_failed'
        if (-not $report.error) { $report.error = $_.Exception.Message }
    }
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    $report.restoredOriginalEgress = ($beforeEgress -ne '' -and $report.restoredEgress -eq $beforeEgress)
    $reportDir = Split-Path -Parent ([IO.Path]::GetFullPath($ReportPath))
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success -or $report.restoredServiceState -ne 'Running') { exit 1 }
Write-Output "Windows AWG2 preview physical smoke passed. Report: $ReportPath"
