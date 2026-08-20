[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\Program Files\Green VPN',
    [string]$AppPath = '',
    [string]$ProcessName = '',
    [string]$ProgramDataRoot = 'C:\ProgramData\BlueVPN',
    [int]$LocalServicePort = 48737,
    [string]$ManagedTunnelName = 'BlueVPNDev1',
    [string]$StandbyProbeTunnelName = 'GreenVPNTransportPreviewStandbyProbe',
    [string]$ExternalVpnServiceName = 'AmneziaWGTunnel$device20_full',
    [string]$ExternalVpnConfigPath = '',
    [switch]$StopGreenUi,
    [ValidateRange(0, 900)]
    [int]$DelaySeconds = 0,
    [string]$ReportPath = 'C:\BlueVPN_Builds\windows-smoke-network-restore.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$resolvedProgramDataRoot = [IO.Path]::GetFullPath($ProgramDataRoot).TrimEnd('\')
$resolvedAppPath = if ([string]::IsNullOrWhiteSpace($AppPath)) {
    Join-Path $resolvedInstallRoot 'greenvpn.exe'
} else {
    [IO.Path]::GetFullPath($AppPath)
}
$resolvedProcessName = if ([string]::IsNullOrWhiteSpace($ProcessName)) {
    [IO.Path]::GetFileNameWithoutExtension($resolvedAppPath)
} else {
    [IO.Path]::GetFileNameWithoutExtension($ProcessName.Trim())
}
$resolvedExternalVpnConfigPath = if (
    [string]::IsNullOrWhiteSpace($ExternalVpnConfigPath)
) { '' } else { [IO.Path]::GetFullPath($ExternalVpnConfigPath) }
if ($resolvedProcessName -notmatch '^[A-Za-z0-9_.-]+$') {
    throw 'ProcessName contains unsupported characters.'
}
foreach ($name in @($ManagedTunnelName, $StandbyProbeTunnelName)) {
    if ($name -notmatch '^[A-Za-z0-9_.-]+$') {
        throw 'Tunnel names contain unsupported characters.'
    }
}
$taskScriptPath = Join-Path $resolvedInstallRoot 'tools\greenvpn_vpn_task.ps1'
$tokenPath = Join-Path $resolvedProgramDataRoot 'service_token'
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
    externalVpnServiceInstalledForRecovery = $false
    publicHealth = $false
    youtube = $false
    stopGreenUiRequested = [bool]$StopGreenUi
    greenUiStopped = -not [bool]$StopGreenUi
    runtime = [ordered]@{
        installRoot = $resolvedInstallRoot
        appPath = $resolvedAppPath
        processName = $resolvedProcessName
        programDataRoot = $resolvedProgramDataRoot
        localServicePort = $LocalServicePort
        managedTunnelName = $ManagedTunnelName
        standbyProbeTunnelName = $StandbyProbeTunnelName
        externalVpnConfigProvided = -not [string]::IsNullOrWhiteSpace(
            $resolvedExternalVpnConfigPath
        )
    }
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
    try {
        $status = Get-GreenStatus
    } catch {
        foreach ($prefix in @('WireGuardTunnel$', 'AmneziaWGTunnel$')) {
            $service = Get-Service -Name ($prefix + $ManagedTunnelName) `
                -ErrorAction SilentlyContinue
            if ($null -ne $service -and [string]$service.Status -ne 'Stopped') {
                return $false
            }
        }
        return $true
    }
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

function Resolve-ExternalVpnServiceName {
    param([Parameter(Mandatory = $true)][string]$PreferredName)
    $candidate = Get-Service -Name $PreferredName -ErrorAction SilentlyContinue
    if ($null -ne $candidate -and [string]$candidate.Status -eq 'Running') {
        return $candidate.Name
    }

    $prefixes = @('AmneziaWGTunnel$', 'WireGuardTunnel$')
    $services = @()
    foreach ($prefix in $prefixes) {
        $services += @(
            Get-Service -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -like "$prefix*" -or $_.DisplayName -like "$prefix*"
                }
        )
    }
    $services = @($services | Sort-Object Name -Unique)
    $managedServiceNames = @(
        ('WireGuardTunnel$' + $ManagedTunnelName),
        ('AmneziaWGTunnel$' + $ManagedTunnelName),
        ('WireGuardTunnel$' + $StandbyProbeTunnelName),
        ('AmneziaWGTunnel$' + $StandbyProbeTunnelName)
    )
    $services = @($services | Where-Object { $_.Name -notin $managedServiceNames })
    $running = @(
        $services | Where-Object { [string]$_.Status -eq 'Running' }
    )
    if ($running.Count -eq 1) { return [string]$running[0].Name }
    if ($running.Count -gt 1) { return $null }
    if ($null -ne $candidate) { return [string]$candidate.Name }
    if ($services.Count -eq 1) { return [string]$services[0].Name }
    return $null
}

function Install-ExternalVpnServiceForRecovery {
    param([Parameter(Mandatory = $true)][string]$ServiceName)

    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -ne $existing) { return $existing }
    if ([string]::IsNullOrWhiteSpace($resolvedExternalVpnConfigPath)) {
        throw 'External VPN service is missing and no protected recovery config was supplied.'
    }
    $allowedRoot = [IO.Path]::GetFullPath(
        'C:\Program Files\AmneziaWG\Data\Configurations'
    ).TrimEnd('\') + '\'
    if (-not ($resolvedExternalVpnConfigPath + '\').StartsWith(
            $allowedRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -or
            -not $resolvedExternalVpnConfigPath.EndsWith(
                '.conf.dpapi',
                [StringComparison]::OrdinalIgnoreCase
            )) {
        throw 'External VPN recovery config is outside the protected AmneziaWG configuration root.'
    }
    if (-not (Test-Path -LiteralPath $resolvedExternalVpnConfigPath -PathType Leaf)) {
        throw 'Protected external VPN recovery config is missing.'
    }
    $amneziaExe = 'C:\Program Files\AmneziaWG\amneziawg.exe'
    if (-not (Test-Path -LiteralPath $amneziaExe -PathType Leaf)) {
        throw 'AmneziaWG service executable is missing.'
    }
    $install = Start-Process -FilePath $amneziaExe -ArgumentList @(
        '/installtunnelservice',
        ('"' + $resolvedExternalVpnConfigPath + '"')
    ) -WindowStyle Hidden -Wait -PassThru
    if ($install.ExitCode -ne 0) {
        throw "AmneziaWG recovery service install failed with exit code $($install.ExitCode)."
    }
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($null -ne $service) {
            $report.externalVpnServiceInstalledForRecovery = $true
            return $service
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw 'AmneziaWG recovery service did not appear after installation.'
}

function Stop-GreenVpnUi {
    if (-not $StopGreenUi) {
        return
    }

    $expectedPath = $resolvedAppPath
    if (Test-Path -LiteralPath $expectedPath -PathType Leaf) {
        try {
            $shutdown = Start-Process -FilePath $expectedPath `
                -ArgumentList @('--shutdown-existing', '--background') `
                -WorkingDirectory $resolvedInstallRoot `
                -WindowStyle Hidden `
                -PassThru
            $shutdown.WaitForExit(15000) | Out-Null
        } catch {}
    }
    $deadline = (Get-Date).AddSeconds(12)
    do {
        $stillRunning = @(
            Get-Process -Name $resolvedProcessName -ErrorAction SilentlyContinue |
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
    foreach ($process in @(
        Get-Process -Name $resolvedProcessName -ErrorAction SilentlyContinue
    )) {
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
            Get-Process -Name $resolvedProcessName -ErrorAction SilentlyContinue |
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
        ('WireGuardTunnel$' + $StandbyProbeTunnelName),
        ('AmneziaWGTunnel$' + $StandbyProbeTunnelName)
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
        (Join-Path $resolvedProgramDataRoot 'standby-probe-runtime'),
        (Join-Path $resolvedProgramDataRoot 'standby-probe-request.json'),
        (Join-Path $resolvedProgramDataRoot 'standby-probe-result.json'),
        (Join-Path $resolvedProgramDataRoot 'standby-probe.cancel')
    )) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
    $report.standbyRuntimeAbsent =
        -not (Test-Path -LiteralPath (
            Join-Path $resolvedProgramDataRoot 'standby-probe-runtime'
        ))

    $resolvedExternalVpnServiceName = Resolve-ExternalVpnServiceName -PreferredName $ExternalVpnServiceName
    if ([string]::IsNullOrWhiteSpace($resolvedExternalVpnServiceName)) {
        if (-not [string]::IsNullOrWhiteSpace($resolvedExternalVpnConfigPath)) {
            $resolvedExternalVpnServiceName = $ExternalVpnServiceName
        } else {
            throw 'Unable to resolve external VPN service name for recovery.'
        }
    }
    $report.runtime.externalVpnServiceName = $resolvedExternalVpnServiceName
    $service = Install-ExternalVpnServiceForRecovery `
        -ServiceName $resolvedExternalVpnServiceName
    if ([string]$service.Status -ne 'Running') {
        Start-Service -Name $resolvedExternalVpnServiceName -ErrorAction Stop
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
