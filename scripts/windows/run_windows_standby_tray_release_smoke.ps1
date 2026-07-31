[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedInstallerSha256,
    [Parameter(Mandatory = $true)]
    [long]$ExpectedInstallerSize,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,
    [Parameter(Mandatory = $true)]
    [string]$ArtifactRoot,
    [string]$InstallRoot = 'C:\Program Files\Green VPN',
    [string]$ExternalVpnServiceName = 'AmneziaWGTunnel$device20_full',
    [ValidateRange(90, 600)]
    [int]$InitialDelaySeconds = 90,
    [ValidateRange(900, 3600)]
    [int]$DeadmanDelaySeconds = 2400,
    [ValidateRange(10, 120)]
    [int]$MaxConnectSeconds = 30,
    [ValidateRange(60, 1200)]
    [int]$StandbyCycleTimeoutSeconds = 600,
    [ValidateRange(15, 180)]
    [int]$MaxPrevalidatedFailoverSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$latencyScript = Join-Path $repoRoot 'scripts\windows\test_windows_connect_latency_physical.ps1'
$failoverScript = Join-Path $repoRoot 'scripts\windows\test_windows_public_runtime_failover_physical.ps1'
$restoreScript = Join-Path $repoRoot 'scripts\windows\restore_windows_smoke_network.ps1'
$resolvedInstaller = [IO.Path]::GetFullPath($InstallerPath)
$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$appPath = Join-Path $resolvedInstallRoot 'greenvpn.exe'
$summaryPath = Join-Path $ArtifactRoot 'windows-standby-tray-autonomous-summary.json'
$logPath = Join-Path $ArtifactRoot 'windows-standby-tray-autonomous.log'
$latencyReportPath = Join-Path $ArtifactRoot 'windows-fast-foreground-physical.json'
$failoverReportPath = Join-Path $ArtifactRoot 'windows-prevalidated-failover-physical.json'
$failoverLogPath = Join-Path $ArtifactRoot 'windows-prevalidated-failover-physical.log'
$recoveryReportPath = Join-Path $ArtifactRoot 'windows-standby-tray-final-recovery.json'
$deadmanReportPath = Join-Path $ArtifactRoot 'windows-standby-tray-deadman-recovery.json'
$trayDiagnosticsPath = Join-Path $ArtifactRoot 'windows-tray-lifecycle.jsonl'
$isolatedAppDataRoot = Join-Path $ArtifactRoot 'isolated-appdata'
$isolatedUserStateRoot = Join-Path $isolatedAppDataRoot 'GreenVPN\state'
$mutex = [Threading.Mutex]::new($false, 'Local\GreenVPNStandbyTrayReleaseSmoke')
$mutexAcquired = $false
$deadman = $null
$expectedHash = $ExpectedInstallerSha256.ToUpperInvariant()

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

function Write-RunnerLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
        "[$((Get-Date).ToUniversalTime().ToString('o'))] $Message"
    )
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Get-ServiceState {
    param([Parameter(Mandatory = $true)][string]$Name)
    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $service) { return 'Missing' }
    return [string]$service.Status
}

function Get-LocalToken {
    $path = 'C:\ProgramData\BlueVPN\service_token'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    try {
        $token = (Get-Content -LiteralPath $path -Raw).Trim()
        return $(if ($token.Length -ge 24) { $token } else { '' })
    } catch {
        return ''
    }
}

function Invoke-GreenLocal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$TimeoutSeconds = 30
    )
    $token = Get-LocalToken
    if (-not $token) { throw 'Green VPN local service token is unavailable.' }
    return Invoke-RestMethod -Method $Method `
        -Uri "http://127.0.0.1:48737$Path" `
        -Headers @{ 'X-GreenVPN-Local-Token' = $token } `
        -ContentType 'application/json' `
        -Body $(if ($Method -eq 'POST') { '{}' } else { $null }) `
        -TimeoutSec $TimeoutSeconds
}

function Test-PublicHealth {
    try {
        return (Invoke-WebRequest -UseBasicParsing `
            -Uri 'https://api.greenvpn.pro/healthz' -TimeoutSec 15).StatusCode -eq 200
    } catch { return $false }
}

function Test-YouTube {
    try {
        return (Invoke-WebRequest -UseBasicParsing `
            -Uri 'https://www.youtube.com/generate_204' -TimeoutSec 15).StatusCode -eq 204
    } catch { return $false }
}

function Get-ExactAppProcesses {
    return @(
        Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    [IO.Path]::GetFullPath([string]$_.Path) -ieq $appPath
                } catch {
                    $false
                }
            }
    )
}

function Stop-GreenUiGracefully {
    if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) { return $true }
    if (@(Get-ExactAppProcesses).Count -eq 0) { return $true }
    try {
        $shutdown = Start-Process -FilePath $appPath `
            -ArgumentList @('--shutdown-existing', '--background') `
            -WorkingDirectory $resolvedInstallRoot -PassThru
        [void]$shutdown.WaitForExit(15000)
    } catch {}
    $deadline = (Get-Date).AddSeconds(15)
    do {
        if (@(Get-ExactAppProcesses).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    foreach ($process in @(Get-ExactAppProcesses)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 700
    return @(Get-ExactAppProcesses).Count -eq 0
}

function Test-GreenComponentsStopped {
    try {
        $status = Invoke-GreenLocal -Method GET -Path '/status' -TimeoutSeconds 8
        foreach ($key in @(
            'wireGuardState', 'amneziaWgState', 'hysteriaClientState',
            'hysteriaTunState', 'vlessClientState', 'vlessTunState',
            'naiveClientState', 'naiveTunState', 'dnsttClientState',
            'dnsttTunState', 'processRouterState'
        )) {
            if (([string]$status.$key).Trim().ToLowerInvariant() -notin @('missing', 'stopped')) {
                return $false
            }
        }
        return $true
    } catch { return $false }
}

function Assert-SafeBaseline {
    param([Parameter(Mandatory = $true)][string]$Label)
    if (-not (Stop-GreenUiGracefully)) {
        throw "${Label}: Green VPN UI did not stop."
    }
    try { [void](Invoke-GreenLocal -Method POST -Path '/disconnect' -TimeoutSeconds 45) } catch {}
    if (-not (Test-GreenComponentsStopped)) {
        throw "${Label}: Green VPN transports are not fully stopped."
    }
    if ((Get-ServiceState -Name $ExternalVpnServiceName) -ne 'Running') {
        throw "${Label}: $ExternalVpnServiceName is not running."
    }
    if (-not (Test-PublicHealth)) {
        throw "${Label}: public API health probe failed."
    }
    if (-not (Test-YouTube)) {
        throw "${Label}: YouTube generate_204 probe failed."
    }
}

function Assert-ReadOnlySafeBaseline {
    param([Parameter(Mandatory = $true)][string]$Label)
    if (-not (Test-GreenComponentsStopped)) {
        throw "${Label}: Green VPN transports are not fully stopped."
    }
    if ((Get-ServiceState -Name $ExternalVpnServiceName) -ne 'Running') {
        throw "${Label}: $ExternalVpnServiceName is not running."
    }
    if (-not (Test-PublicHealth)) {
        throw "${Label}: public API health probe failed."
    }
    if (-not (Test-YouTube)) {
        throw "${Label}: YouTube generate_204 probe failed."
    }
}

function Start-DeadmanRecovery {
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$restoreScript`"",
        '-InstallRoot', "`"$resolvedInstallRoot`"",
        '-ExternalVpnServiceName', "`"$ExternalVpnServiceName`"",
        '-StopGreenUi',
        '-DelaySeconds', [string]$DeadmanDelaySeconds,
        '-ReportPath', "`"$deadmanReportPath`""
    )
    return Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments `
        -WindowStyle Hidden -PassThru
}

function Invoke-FinalRecovery {
    try {
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
            -File $restoreScript `
            -InstallRoot $resolvedInstallRoot `
            -ExternalVpnServiceName $ExternalVpnServiceName `
            -StopGreenUi `
            -ReportPath $recoveryReportPath | Out-Null
    } catch {}
    if (-not (Test-Path -LiteralPath $recoveryReportPath -PathType Leaf)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $recoveryReportPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    } catch { return $null }
}

function Install-ExactCandidate {
    if (-not (Test-Path -LiteralPath $resolvedInstaller -PathType Leaf)) {
        throw 'Exact installer is missing.'
    }
    $item = Get-Item -LiteralPath $resolvedInstaller
    $hash = (Get-FileHash -LiteralPath $resolvedInstaller -Algorithm SHA256).Hash
    if ($hash -ne $expectedHash -or [long]$item.Length -ne $ExpectedInstallerSize) {
        throw 'Exact installer SHA-256 or size mismatch.'
    }
    if (-not (Stop-GreenUiGracefully)) {
        throw 'Existing Green VPN UI did not stop before installation.'
    }
    $oldAutoClose = $env:GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS
    $oldSkipLaunch = $env:GREENVPN_INSTALLER_SKIP_APP_LAUNCH
    try {
        $env:GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS = '1'
        $env:GREENVPN_INSTALLER_SKIP_APP_LAUNCH = '1'
        $installer = Start-Process -FilePath $resolvedInstaller -PassThru -Wait
    } finally {
        $env:GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS = $oldAutoClose
        $env:GREENVPN_INSTALLER_SKIP_APP_LAUNCH = $oldSkipLaunch
    }
    if ($installer.ExitCode -ne 0) {
        throw "Installer returned exit code $($installer.ExitCode)."
    }
    if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) {
        throw 'Installed application is missing.'
    }
    $app = Get-Item -LiteralPath $appPath
    if ([string]$app.VersionInfo.FileVersion -ne $ExpectedVersion) {
        throw "Installed file version mismatch: $($app.VersionInfo.FileVersion)."
    }
    return [ordered]@{
        path = $resolvedInstaller
        size = [long]$item.Length
        sha256 = $hash
        signatureStatus = (Get-AuthenticodeSignature -LiteralPath $resolvedInstaller).Status.ToString()
        installedAppPath = $appPath
        installedAppSize = [long]$app.Length
        installedAppSha256 = (Get-FileHash -LiteralPath $appPath -Algorithm SHA256).Hash
        installedFileVersion = [string]$app.VersionInfo.FileVersion
    }
}

function Get-TrayDiagnostics {
    if (-not (Test-Path -LiteralPath $trayDiagnosticsPath -PathType Leaf)) {
        return @()
    }
    $events = @()
    foreach ($line in @(Get-Content -LiteralPath $trayDiagnosticsPath -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $events += ($line | ConvertFrom-Json)
        } catch {
            # A poll can race the single append-only WriteFile call. The final
            # stopped-process read below still validates the complete events.
        }
    }
    return @($events)
}

function Get-TrayDiagnosticsAfter {
    param([Parameter(Mandatory = $true)][int]$AfterIndex)
    $events = @(Get-TrayDiagnostics)
    if ($events.Count -le $AfterIndex) { return @() }
    return @($events[$AfterIndex..($events.Count - 1)])
}

function Wait-TrayDiagnostic {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][string]$Event,
        [Parameter(Mandatory = $true)][bool]$Success,
        [Parameter(Mandatory = $true)][int]$AfterIndex,
        [int]$TimeoutSeconds = 20
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $matches = @(
            Get-TrayDiagnosticsAfter -AfterIndex $AfterIndex |
                Where-Object {
                    [int]$_.pid -eq $ProcessId -and
                    [string]$_.event -eq $Event -and
                    [bool]$_.success -eq $Success
                }
        )
        if ($matches.Count -gt 0) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Assert-TrayProcessLifecycle {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][int]$AfterIndex,
        [Parameter(Mandatory = $true)][bool]$RequireGracefulDelete
    )
    $events = @(
        Get-TrayDiagnosticsAfter -AfterIndex $AfterIndex |
            Where-Object { [int]$_.pid -eq $ProcessId }
    )
    $successfulAdds = @(
        $events | Where-Object { $_.event -eq 'add' -and [bool]$_.success }
    )
    $versionEvents = @(
        $events | Where-Object { $_.event -eq 'set_version' -and [bool]$_.success }
    )
    $staleCleanupEvents = @(
        $events | Where-Object { $_.event -eq 'delete_stale' }
    )
    $retryExhausted = @(
        $events | Where-Object { $_.event -eq 'retry_exhausted' }
    )
    $shutdownDeletes = @(
        $events | Where-Object {
            $_.event -eq 'delete_shutdown' -and [bool]$_.success
        }
    )
    if ($successfulAdds.Count -ne 1) {
        throw "Tray process $ProcessId reported $($successfulAdds.Count) successful NIM_ADD events; expected exactly one."
    }
    if ($versionEvents.Count -ne 1) {
        throw "Tray process $ProcessId did not confirm one successful NIM_SETVERSION."
    }
    if ($staleCleanupEvents.Count -ne 1) {
        throw "Tray process $ProcessId did not perform exactly one initial stale cleanup."
    }
    if ($retryExhausted.Count -ne 0) {
        throw "Tray process $ProcessId exhausted its bounded NIM_ADD retries."
    }
    if ($RequireGracefulDelete -and $shutdownDeletes.Count -ne 1) {
        throw "Tray process $ProcessId did not confirm one successful graceful NIM_DELETE."
    }
    return [ordered]@{
        pid = $ProcessId
        successfulAddCount = $successfulAdds.Count
        successfulSetVersionCount = $versionEvents.Count
        staleCleanupCount = $staleCleanupEvents.Count
        successfulGracefulDeleteCount = $shutdownDeletes.Count
        events = @($events)
    }
}

function Invoke-TrayLifecycleSmoke {
    if (-not (Stop-GreenUiGracefully)) {
        throw 'Tray smoke could not establish a stopped UI baseline.'
    }
    Remove-Item -LiteralPath $trayDiagnosticsPath -Force -ErrorAction SilentlyContinue
    $env:GREENVPN_TRAY_DIAGNOSTIC_PATH = $trayDiagnosticsPath
    $cycles = @()
    for ($cycle = 1; $cycle -le 5; $cycle++) {
        $diagnosticStart = @(Get-TrayDiagnostics).Count
        $primary = Start-Process -FilePath $appPath -ArgumentList '--background' `
            -WorkingDirectory $resolvedInstallRoot -PassThru
        if (-not (Wait-TrayDiagnostic -ProcessId $primary.Id -Event 'add' `
                -Success $true -AfterIndex $diagnosticStart)) {
            $primary.Refresh()
            $exactProcesses = @(Get-ExactAppProcesses)
            $exactProcessIds = @($exactProcesses | ForEach-Object { [int]$_.Id })
            $exitCode = $(if ($primary.HasExited) { $primary.ExitCode } else { $null })
            throw (
                "Tray NIM_ADD was not confirmed in lifecycle cycle $cycle; " +
                "launchPid=$($primary.Id) launchExited=$($primary.HasExited) " +
                "exitCode=$exitCode exactPids=$($exactProcessIds -join ',')."
            )
        }
        $duplicateLaunches = @()
        for ($launch = 1; $launch -le 8; $launch++) {
            $duplicate = Start-Process -FilePath $appPath -ArgumentList '--background' `
                -WorkingDirectory $resolvedInstallRoot -PassThru
            [void]$duplicate.WaitForExit(10000)
            $duplicateLaunches += [ordered]@{
                pid = $duplicate.Id
                exited = $duplicate.HasExited
                exitCode = $(if ($duplicate.HasExited) { $duplicate.ExitCode } else { $null })
            }
        }
        $processCount = @(Get-ExactAppProcesses).Count
        if ($processCount -ne 1) {
            throw "Single-instance contract failed in cycle ${cycle}: $processCount processes."
        }
        if (-not (Stop-GreenUiGracefully) -or
                -not (Wait-TrayDiagnostic -ProcessId $primary.Id `
                    -Event 'delete_shutdown' -Success $true `
                    -AfterIndex $diagnosticStart)) {
            throw "Graceful tray cleanup failed in cycle $cycle."
        }
        $lifecycle = Assert-TrayProcessLifecycle -ProcessId $primary.Id `
            -AfterIndex $diagnosticStart -RequireGracefulDelete $true
        $cycles += [ordered]@{
            cycle = $cycle
            duplicateLaunches = @($duplicateLaunches)
            exactProcessCount = $processCount
            gracefulIconRemoved = $true
            lifecycle = $lifecycle
        }
    }

    $forcedStart = @(Get-TrayDiagnostics).Count
    $forcedPrimary = Start-Process -FilePath $appPath -ArgumentList '--background' `
        -WorkingDirectory $resolvedInstallRoot -PassThru
    if (-not (Wait-TrayDiagnostic -ProcessId $forcedPrimary.Id -Event 'add' `
            -Success $true -AfterIndex $forcedStart)) {
        throw 'Tray NIM_ADD was not confirmed before forced-exit recovery check.'
    }
    $forced = @(Get-ExactAppProcesses)
    if ($forced.Count -ne 1) { throw 'Forced-exit tray setup did not have one process.' }
    $forcedLifecycle = Assert-TrayProcessLifecycle -ProcessId $forcedPrimary.Id `
        -AfterIndex $forcedStart -RequireGracefulDelete $false
    Stop-Process -Id $forced[0].Id -Force -ErrorAction Stop
    [void]$forced[0].WaitForExit(10000)
    $replacementStart = @(Get-TrayDiagnostics).Count
    $replacement = Start-Process -FilePath $appPath -ArgumentList '--background' `
        -WorkingDirectory $resolvedInstallRoot -PassThru
    if (-not (Wait-TrayDiagnostic -ProcessId $replacement.Id -Event 'add' `
            -Success $true -AfterIndex $replacementStart)) {
        throw 'Stable tray GUID did not recover after a forced predecessor exit.'
    }
    if (@(Get-ExactAppProcesses).Count -ne 1) {
        throw 'Forced-exit recovery left more than one Green VPN process.'
    }
    if (-not (Stop-GreenUiGracefully) -or
            -not (Wait-TrayDiagnostic -ProcessId $replacement.Id `
                -Event 'delete_shutdown' -Success $true `
                -AfterIndex $replacementStart)) {
        throw 'Tray icon did not disappear after final graceful shutdown.'
    }
    $replacementLifecycle = Assert-TrayProcessLifecycle `
        -ProcessId $replacement.Id -AfterIndex $replacementStart `
        -RequireGracefulDelete $true
    return [ordered]@{
        stableGuid = '6a82be61-7d31-4f65-9a6d-32118c44e290'
        diagnosticPath = $trayDiagnosticsPath
        lifecycleCycles = @($cycles)
        singleInstanceConfirmed = $true
        gracefulShutdownConfirmed = $true
        forcedPredecessorRecoveryConfirmed = $true
        forcedPredecessorLifecycle = $forcedLifecycle
        replacementLifecycle = $replacementLifecycle
        finalIconAbsent = $true
        finalProcessCount = @(Get-ExactAppProcesses).Count
    }
}

$summary = [ordered]@{
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    completedAtUtc = $null
    success = $false
    failure = $null
    initialDelaySeconds = $InitialDelaySeconds
    deadmanDelaySeconds = $DeadmanDelaySeconds
    installer = $null
    tray = $null
    foreground = $null
    standbyFailover = $null
    reports = [ordered]@{
        latency = $latencyReportPath
        failover = $failoverReportPath
        recovery = $recoveryReportPath
        deadman = $deadmanReportPath
        trayDiagnostics = $trayDiagnosticsPath
    }
    cleanup = [ordered]@{
        recoverySuccess = $false
        greenUiStopped = $false
        greenComponentsStopped = $false
        externalVpnRunning = $false
        publicHealth = $false
        youtube = $false
        standbyRuntimeAbsent = $false
        standbyBypassRoutesAbsent = $false
        failsafesRemoved = $false
        deadmanStopped = $false
    }
}

$mutexAcquired = $mutex.WaitOne(0)
if (-not $mutexAcquired) {
    $mutex.Dispose()
    Write-Error 'Another standby/tray release smoke is already running.'
    exit 2
}

try {
    if (-not (Test-IsAdministrator)) {
        throw 'Autonomous standby/tray release smoke must run elevated.'
    }
    foreach ($required in @($latencyScript, $failoverScript, $restoreScript)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required smoke script is missing: $required"
        }
    }
    Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $isolatedAppDataRoot) {
        Remove-Item -LiteralPath $isolatedAppDataRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $isolatedUserStateRoot | Out-Null

    Assert-ReadOnlySafeBaseline -Label 'Initial read-only baseline'
    Write-RunnerLog "waiting $InitialDelaySeconds seconds before installation or network transitions"
    Start-Sleep -Seconds $InitialDelaySeconds

    $deadman = Start-DeadmanRecovery
    Write-RunnerLog "deadman started pid=$($deadman.Id) delay=$DeadmanDelaySeconds"
    Assert-SafeBaseline -Label 'Delayed baseline'

    $summary.installer = Install-ExactCandidate
    $env:APPDATA = $isolatedAppDataRoot
    $summary.tray = Invoke-TrayLifecycleSmoke
    Assert-SafeBaseline -Label 'Post-install tray baseline'

    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $latencyScript `
        -InstallRoot $resolvedInstallRoot `
        -AppPath $appPath `
        -UserStateRoot $isolatedUserStateRoot `
        -UseUiAutomationAction `
        -ExpectCompetingVpn `
        -FirstConnectTimeoutSeconds 120 `
        -MaxFirstConnectSeconds $MaxConnectSeconds `
        -MaxCachedConnectSeconds $MaxConnectSeconds `
        -ReportPath $latencyReportPath | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $latencyReportPath)) {
        throw 'Fast foreground physical smoke did not produce a successful report.'
    }
    $latency = Get-Content -LiteralPath $latencyReportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $foregroundCandidates = @($latency.competingVpnTakeover.candidates)
    if (
        -not [bool]$latency.success -or
        $foregroundCandidates.Count -ne 1 -or
        -not [bool]$latency.competingVpnTakeover.probeConfirmed -or
        -not [bool]$latency.competingVpnTakeover.privilegedTakeoverConfirmed -or
        [double]$latency.competingVpnTakeover.logSeconds -gt $MaxConnectSeconds
    ) {
        throw "Fast foreground contract failed: $($latency.failure)"
    }
    $summary.foreground = [ordered]@{
        logSeconds = [double]$latency.competingVpnTakeover.logSeconds
        wallSeconds = [double]$latency.competingVpnTakeover.wallSeconds
        candidate = $foregroundCandidates[0]
        oneCandidate = $true
        probeConfirmed = $true
        privilegedTakeoverConfirmed = $true
    }

    Assert-SafeBaseline -Label 'Between physical smokes'
    Remove-Item -LiteralPath (Join-Path $isolatedUserStateRoot 'standby_routes.json') `
        -Force -ErrorAction SilentlyContinue

    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $failoverScript `
        -InstallerPath $resolvedInstaller `
        -ExpectedInstallerSha256 $expectedHash `
        -ExpectedVersion $ExpectedVersion `
        -InstallRoot $resolvedInstallRoot `
        -UserStateRoot $isolatedUserStateRoot `
        -UseExistingExactInstall `
        -RequireStandbyProof `
        -StandbyCycleTimeoutSeconds $StandbyCycleTimeoutSeconds `
        -MaxPrevalidatedFailoverSeconds $MaxPrevalidatedFailoverSeconds `
        -FailsafeDelayMinutes 25 `
        -ReportPath $failoverReportPath `
        -LogPath $failoverLogPath | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $failoverReportPath)) {
        throw 'Prevalidated failover physical smoke did not produce a successful report.'
    }
    $failover = Get-Content -LiteralPath $failoverReportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if (
        -not [bool]$failover.success -or
        -not [bool]$failover.standby.cycleCompleted -or
        -not [bool]$failover.standby.allEligibleAccounted -or
        @($failover.standby.freshProofs).Count -lt 1 -or
        -not [bool]$failover.standby.cleanup.cleanupOk -or
        -not [bool]$failover.injection.prevalidatedStandbyUsed -or
        [double]$failover.injection.recoverySeconds -gt $MaxPrevalidatedFailoverSeconds -or
        [bool]$failover.injection.overlapObserved -or
        -not [bool]$failover.cleanup.standbyArtifactsClean
    ) {
        throw "Prevalidated failover contract failed: $($failover.failure)"
    }
    $summary.standbyFailover = [ordered]@{
        activeRoute = $failover.firstRoute
        eligibleRoutes = @($failover.standby.eligibleRoutes)
        outcomes = $failover.standby.outcomes
        freshProofs = @($failover.standby.freshProofs)
        cycleCompleted = $true
        allEligibleAccounted = $true
        temporaryArtifactsClean = $true
        recoverySeconds = [double]$failover.injection.recoverySeconds
        prevalidatedStandbyUsed = $true
        overlapObserved = $false
        recoveredRoute = $failover.recoveredRoute
    }
    $summary.success = $true
} catch {
    $summary.failure = $_.Exception.Message
    Write-RunnerLog "failed: $($summary.failure)"
} finally {
    $recovery = Invoke-FinalRecovery
    if ($null -ne $recovery) {
        $summary.cleanup.recoverySuccess = [bool]$recovery.success
        $summary.cleanup.greenUiStopped = [bool]$recovery.greenUiStopped
    }
    $summary.cleanup.greenComponentsStopped = Test-GreenComponentsStopped
    $summary.cleanup.externalVpnRunning =
        (Get-ServiceState -Name $ExternalVpnServiceName) -eq 'Running'
    $summary.cleanup.publicHealth = Test-PublicHealth
    $summary.cleanup.youtube = Test-YouTube
    $summary.cleanup.standbyRuntimeAbsent =
        -not (Test-Path -LiteralPath 'C:\ProgramData\BlueVPN\standby-probe-runtime')
    $summary.cleanup.standbyBypassRoutesAbsent =
        @(Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
            [int]$_.RouteMetric -eq 42739
        }).Count -eq 0
    $summary.cleanup.failsafesRemoved = @(
        'GreenVPNConnectLatencySmokeFailsafe',
        'GreenVPNPublicRuntimeFailoverSmokeFailsafe'
    ).Where({
        Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue
    }).Count -eq 0

    $recoveryConfirmed =
        $summary.cleanup.recoverySuccess -and
        $summary.cleanup.greenUiStopped -and
        $summary.cleanup.greenComponentsStopped -and
        $summary.cleanup.externalVpnRunning -and
        $summary.cleanup.publicHealth -and
        $summary.cleanup.youtube -and
        $summary.cleanup.standbyRuntimeAbsent -and
        $summary.cleanup.standbyBypassRoutesAbsent -and
        $summary.cleanup.failsafesRemoved
    if ($recoveryConfirmed -and $null -ne $deadman) {
        Stop-Process -Id $deadman.Id -Force -ErrorAction SilentlyContinue
    }
    $summary.cleanup.deadmanStopped =
        $null -eq $deadman -or
        -not [bool](Get-Process -Id $deadman.Id -ErrorAction SilentlyContinue)
    if (-not $recoveryConfirmed -or -not $summary.cleanup.deadmanStopped) {
        $summary.success = $false
        if (-not $summary.failure) {
            $summary.failure = 'Final recovery or independent deadman cleanup was not confirmed.'
        }
    }
    $summary.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-RunnerLog "finished success=$($summary.success)"
    if ($mutexAcquired) { try { $mutex.ReleaseMutex() } catch {} }
    $mutex.Dispose()
}

if (-not $summary.success) { exit 1 }
$summary | ConvertTo-Json -Depth 12
