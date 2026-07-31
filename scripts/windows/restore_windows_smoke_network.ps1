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
    externalVpnRunning = $false
    publicHealth = $false
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

    $report.success =
        $report.greenUiStopped -and
        $report.greenDisconnectAccepted -and
        $report.greenComponentsStopped -and
        $report.externalVpnRunning -and
        $report.publicHealth
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
