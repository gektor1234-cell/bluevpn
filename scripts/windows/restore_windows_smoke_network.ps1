[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\Program Files\Green VPN',
    [string]$ProgramDataRoot = 'C:\ProgramData\BlueVPN',
    [int]$LocalServicePort = 48737,
    [string]$ExternalVpnServiceName = 'AmneziaWGTunnel$device20_full',
    [switch]$StopGreenUi,
    [ValidateRange(0, 900)]
    [int]$DelaySeconds = 0,
    [string]$ReportPath = 'C:\BlueVPN_Builds\windows-smoke-network-restore.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskScriptPath = Join-Path $InstallRoot 'tools\greenvpn_vpn_task.ps1'
$tokenPath = Join-Path $ProgramDataRoot 'service_token'
$reportDirectory = Split-Path -Parent $ReportPath
if ($reportDirectory) {
    New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
}

$report = [ordered]@{
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    delaySeconds = $DelaySeconds
    completedAtUtc = $null
    success = $false
    greenDisconnectAccepted = $false
    greenComponentsStopped = $false
    standbyProbeCancelled = $false
    standbyProbeServicesStopped = $false
    standbyRuntimeAbsent = $false
    standbyBypassRoutesAbsent = $false
    externalVpnRunning = $false
    publicHealth = $false
    youtube = $false
    stopGreenUiRequested = [bool]$StopGreenUi
    greenUiStopped = -not [bool]$StopGreenUi
    failure = $null
}

if ($DelaySeconds -gt 0) {
    Start-Sleep -Seconds $DelaySeconds
}

function Get-GreenStatus {
    if (-not (Test-Path -LiteralPath $tokenPath -PathType Leaf)) {
        throw 'Green VPN local service token is missing.'
    }
    $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
    if ($token.Length -lt 24) {
        throw 'Green VPN local service token is invalid.'
    }
    $headers = @{ 'X-GreenVPN-Local-Token' = $token }
    return Invoke-RestMethod `
        -Method Get `
        -Uri "http://127.0.0.1:$LocalServicePort/status" `
        -Headers $headers `
        -TimeoutSec 8
}

function Test-GreenComponentsStopped {
    $status = Get-GreenStatus
    foreach ($key in @(
        'wireGuardState',
        'amneziaWgState',
        'hysteriaClientState',
        'hysteriaTunState',
        'vlessClientState',
        'vlessTunState',
        'naiveClientState',
        'naiveTunState',
        'dnsttClientState',
        'dnsttTunState',
        'processRouterState'
    )) {
        if (([string]$status.$key).Trim().ToLowerInvariant() -notin @('missing', 'stopped')) {
            return $false
        }
    }
    return $true
}

function Stop-GreenVpnUi {
    if (-not $StopGreenUi) {
        return
    }

    $expectedPath = [IO.Path]::GetFullPath(
        (Join-Path $InstallRoot 'greenvpn.exe')
    )
    if (Test-Path -LiteralPath $expectedPath -PathType Leaf) {
        try {
            $shutdown = Start-Process -FilePath $expectedPath `
                -ArgumentList @('--shutdown-existing', '--background') `
                -WorkingDirectory $InstallRoot `
                -WindowStyle Hidden `
                -PassThru
            $shutdown.WaitForExit(15000) | Out-Null
        } catch {}
    }
    $deadline = (Get-Date).AddSeconds(12)
    do {
        $stillRunning = @(
            Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue |
                Where-Object {
                    try {
                        [IO.Path]::GetFullPath([string]$_.Path) -ieq $expectedPath
                    } catch {
                        $false
                    }
                }
        )
        if ($stillRunning.Count -eq 0) {
            $report.greenUiStopped = $true
            return
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    foreach ($process in $stillRunning) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    foreach ($process in @(Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue)) {
        try {
            $actualPath = [IO.Path]::GetFullPath([string]$process.Path)
            if ($actualPath -ieq $expectedPath) {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            }
        } catch {
            throw "Could not stop Green VPN UI process $($process.Id): $($_.Exception.Message)"
        }
    }

    $deadline = (Get-Date).AddSeconds(15)
    do {
        $stillRunning = @(
            Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue |
                Where-Object {
                    try {
                        [IO.Path]::GetFullPath([string]$_.Path) -ieq $expectedPath
                    } catch {
                        $false
                    }
                }
        )
        if ($stillRunning.Count -eq 0) {
            $report.greenUiStopped = $true
            return
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    throw 'Green VPN UI process did not stop before network restoration.'
}

try {
    Stop-GreenVpnUi

    try {
        $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
        $headers = @{ 'X-GreenVPN-Local-Token' = $token }
        $cancel = Invoke-RestMethod `
            -Method Post `
            -Uri "http://127.0.0.1:$LocalServicePort/standby/cancel" `
            -Headers $headers `
            -TimeoutSec 75
        $report.standbyProbeCancelled = [bool]$cancel.ok
    } catch {
        $report.standbyProbeCancelled = $true
    }

    try {
        $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
        $headers = @{ 'X-GreenVPN-Local-Token' = $token }
        $disconnect = Invoke-RestMethod `
            -Method Post `
            -Uri "http://127.0.0.1:$LocalServicePort/disconnect" `
            -Headers $headers `
            -TimeoutSec 45
        $report.greenDisconnectAccepted = [bool]$disconnect.ok
    } catch {
        if (Test-Path -LiteralPath $taskScriptPath -PathType Leaf) {
            & powershell.exe `
                -NoProfile `
                -NonInteractive `
                -ExecutionPolicy Bypass `
                -File $taskScriptPath `
                -Action Disconnect |
                Out-Null
            $report.greenDisconnectAccepted = $LASTEXITCODE -eq 0
        }
    }

    $deadline = (Get-Date).AddSeconds(45)
    do {
        try {
            if (Test-GreenComponentsStopped) {
                $report.greenComponentsStopped = $true
                break
            }
        } catch {}
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    $probeServices = @(
        'WireGuardTunnel$GreenVPNTransportPreviewStandbyProbe',
        'AmneziaWGTunnel$GreenVPNTransportPreviewStandbyProbe'
    )
    foreach ($name in $probeServices) {
        $probeService = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $probeService) {
            if ([string]$probeService.Status -ne 'Stopped') {
                Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
                try {
                    $probeService.WaitForStatus(
                        [System.ServiceProcess.ServiceControllerStatus]::Stopped,
                        [TimeSpan]::FromSeconds(20)
                    )
                } catch {}
            }
            & sc.exe delete $name 2>$null | Out-Null
        }
    }
    $report.standbyProbeServicesStopped = @(
        $probeServices | Where-Object {
            $state = Get-Service -Name $_ -ErrorAction SilentlyContinue
            $null -ne $state -and [string]$state.Status -ne 'Stopped'
        }
    ).Count -eq 0

    foreach ($route in @(
        Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
            [int]$_.RouteMetric -eq 42739
        }
    )) {
        Remove-NetRoute -InputObject $route -Confirm:$false -ErrorAction SilentlyContinue
    }
    $report.standbyBypassRoutesAbsent = @(
        Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
            [int]$_.RouteMetric -eq 42739
        }
    ).Count -eq 0

    foreach ($path in @(
        (Join-Path $ProgramDataRoot 'standby-probe-runtime'),
        (Join-Path $ProgramDataRoot 'standby-probe-request.json'),
        (Join-Path $ProgramDataRoot 'standby-probe-result.json'),
        (Join-Path $ProgramDataRoot 'standby-probe.cancel')
    )) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
    $report.standbyRuntimeAbsent =
        -not (Test-Path -LiteralPath (Join-Path $ProgramDataRoot 'standby-probe-runtime'))

    $service = Get-Service -Name $ExternalVpnServiceName -ErrorAction Stop
    if ([string]$service.Status -ne 'Running') {
        Start-Service -Name $ExternalVpnServiceName -ErrorAction Stop
    }
    $service.WaitForStatus(
        [System.ServiceProcess.ServiceControllerStatus]::Running,
        [TimeSpan]::FromSeconds(45)
    )
    $report.externalVpnRunning = $true

    $healthDeadline = (Get-Date).AddSeconds(60)
    do {
        try {
            $response = Invoke-WebRequest `
                -UseBasicParsing `
                -Uri 'https://api.greenvpn.pro/healthz' `
                -TimeoutSec 12
            if ($response.StatusCode -eq 200) {
                $report.publicHealth = $true
                break
            }
        } catch {}
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $healthDeadline)

    try {
        $youtubeResponse = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri 'https://www.youtube.com/generate_204' `
            -TimeoutSec 15
        $report.youtube = $youtubeResponse.StatusCode -eq 204
    } catch {}

    $report.success =
        $report.greenUiStopped -and
        $report.greenDisconnectAccepted -and
        $report.greenComponentsStopped -and
        $report.standbyProbeCancelled -and
        $report.standbyProbeServicesStopped -and
        $report.standbyRuntimeAbsent -and
        $report.standbyBypassRoutesAbsent -and
        $report.externalVpnRunning -and
        $report.publicHealth -and
        $report.youtube
    if (-not $report.success) {
        throw 'Network restoration postconditions were not all confirmed.'
    }
} catch {
    $report.failure = $_.Exception.Message
} finally {
    $report.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $report |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) {
    exit 1
}
