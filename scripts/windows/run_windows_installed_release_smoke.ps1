[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\Program Files\Green VPN',
    [string]$AppPath = '',
    [string]$ExpectedFileVersion = '',
    [string]$ExpectedAppSha256 = '',
    [string]$ArtifactRoot = 'C:\BlueVPN_Builds\windows-installed-release-smoke',
    [string]$ExternalVpnServiceName = 'AmneziaWGTunnel$device20_full',
    [ValidateRange(60, 600)]
    [int]$InitialDelaySeconds = 90,
    [ValidateRange(180, 1800)]
    [int]$DeadmanDelaySeconds = 300,
    [ValidateRange(10, 120)]
    [int]$MaxConnectSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$physicalTestScript = Join-Path $repoRoot 'scripts\windows\test_windows_connect_latency_physical.ps1'
$restoreScript = Join-Path $repoRoot 'scripts\windows\restore_windows_smoke_network.ps1'
$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$resolvedAppPath = if ([string]::IsNullOrWhiteSpace($AppPath)) {
    Join-Path $resolvedInstallRoot 'greenvpn.exe'
} else {
    [IO.Path]::GetFullPath($AppPath)
}
$summaryPath = Join-Path $ArtifactRoot 'windows-installed-release-autonomous-summary.json'
$physicalReportPath = Join-Path $ArtifactRoot 'windows-installed-release-physical.json'
$recoveryReportPath = Join-Path $ArtifactRoot 'windows-installed-release-final-recovery.json'
$deadmanReportPath = Join-Path $ArtifactRoot 'windows-installed-release-deadman-recovery.json'
$logPath = Join-Path $ArtifactRoot 'windows-installed-release-autonomous.log'
$failsafeTaskName = 'GreenVPNConnectLatencySmokeFailsafe'
$mutex = [Threading.Mutex]::new($false, 'Local\GreenVPNInstalledReleaseSmoke')
$mutexAcquired = $false
$deadman = $null

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

function Write-RunnerLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
        "[$((Get-Date).ToUniversalTime().ToString('o'))] $Message"
    )
}

function Get-ServiceState {
    param([Parameter(Mandatory = $true)][string]$Name)

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        return 'Missing'
    }
    return [string]$service.Status
}

function Test-PublicHealth {
    try {
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri 'https://api.greenvpn.pro/healthz' `
            -TimeoutSec 12
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Test-YouTube {
    try {
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri 'https://www.youtube.com/generate_204' `
            -TimeoutSec 12
        return $response.StatusCode -eq 204
    } catch {
        return $false
    }
}

function Test-GreenComponentsStopped {
    $tokenPath = 'C:\ProgramData\BlueVPN\service_token'
    if (-not (Test-Path -LiteralPath $tokenPath -PathType Leaf)) {
        return $false
    }
    try {
        $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
        if ($token.Length -lt 24) {
            return $false
        }
        $status = Invoke-RestMethod `
            -Method Get `
            -Uri 'http://127.0.0.1:48737/status' `
            -Headers @{ 'X-GreenVPN-Local-Token' = $token } `
            -TimeoutSec 8
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
    } catch {
        return $false
    }
}

function Test-GreenUiStopped {
    foreach ($process in @(Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue)) {
        try {
            if ([IO.Path]::GetFullPath([string]$process.Path) -ieq $resolvedAppPath) {
                return $false
            }
        } catch {}
    }
    return $true
}

function Get-AppEvidence {
    if (-not (Test-Path -LiteralPath $resolvedAppPath -PathType Leaf)) {
        throw "Installed Green VPN application is missing: $resolvedAppPath"
    }
    $app = Get-Item -LiteralPath $resolvedAppPath
    $sha256 = (Get-FileHash -LiteralPath $resolvedAppPath -Algorithm SHA256).Hash
    $fileVersion = [string]$app.VersionInfo.FileVersion
    if (
        -not [string]::IsNullOrWhiteSpace($ExpectedFileVersion) -and
        $fileVersion -ne $ExpectedFileVersion
    ) {
        throw "Installed file version mismatch: expected $ExpectedFileVersion, got $fileVersion."
    }
    if (
        -not [string]::IsNullOrWhiteSpace($ExpectedAppSha256) -and
        $sha256 -ne $ExpectedAppSha256
    ) {
        throw "Installed application SHA-256 mismatch: expected $ExpectedAppSha256, got $sha256."
    }
    return [ordered]@{
        path = $resolvedAppPath
        size = [long]$app.Length
        sha256 = $sha256
        fileVersion = $fileVersion
        productVersion = [string]$app.VersionInfo.ProductVersion
    }
}

function Assert-SafeBaseline {
    param([Parameter(Mandatory = $true)][string]$Label)

    if ((Get-ServiceState -Name $ExternalVpnServiceName) -ne 'Running') {
        throw "${Label}: $ExternalVpnServiceName must be running."
    }
    if (-not (Test-GreenComponentsStopped)) {
        throw "${Label}: Green VPN managed components must be stopped."
    }
    if (-not (Test-PublicHealth)) {
        throw "${Label}: Green VPN public health is unavailable."
    }
    if (-not (Test-YouTube)) {
        throw "${Label}: YouTube generate_204 is unavailable."
    }
}

function Start-DeadmanRecovery {
    $arguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        "`"$restoreScript`"",
        '-InstallRoot',
        "`"$resolvedInstallRoot`"",
        '-ExternalVpnServiceName',
        "`"$ExternalVpnServiceName`"",
        '-StopGreenUi',
        '-DelaySeconds',
        [string]$DeadmanDelaySeconds,
        '-ReportPath',
        "`"$deadmanReportPath`""
    )
    return Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList $arguments `
        -WindowStyle Hidden `
        -PassThru
}

function Invoke-FinalRecovery {
    try {
        & powershell.exe `
            -NoProfile `
            -NonInteractive `
            -ExecutionPolicy Bypass `
            -File $restoreScript `
            -InstallRoot $resolvedInstallRoot `
            -ExternalVpnServiceName $ExternalVpnServiceName `
            -StopGreenUi `
            -ReportPath $recoveryReportPath |
            Out-Null
    } catch {}
    if (-not (Test-Path -LiteralPath $recoveryReportPath -PathType Leaf)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $recoveryReportPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    } catch {
        return $null
    }
}

$summary = [ordered]@{
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    completedAtUtc = $null
    success = $false
    failure = $null
    initialDelaySeconds = $InitialDelaySeconds
    deadmanDelaySeconds = $DeadmanDelaySeconds
    maxConnectSeconds = $MaxConnectSeconds
    installedApp = $null
    physicalReport = $physicalReportPath
    takeover = $null
    cleanup = [ordered]@{
        recoveryReport = $recoveryReportPath
        deadmanReport = $deadmanReportPath
        recoverySuccess = $false
        greenUiStopped = $false
        greenComponentsStopped = $false
        externalVpnRunning = $false
        publicHealth = $false
        youtube = $false
        failsafeRemoved = $false
        deadmanStopped = $false
    }
}

$mutexAcquired = $mutex.WaitOne(0)
if (-not $mutexAcquired) {
    $mutex.Dispose()
    Write-Error 'Another installed-release network smoke is already running.'
    exit 2
}

try {
    Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $physicalTestScript -PathType Leaf)) {
        throw "Physical smoke script is missing: $physicalTestScript"
    }
    if (-not (Test-Path -LiteralPath $restoreScript -PathType Leaf)) {
        throw "Network recovery script is missing: $restoreScript"
    }

    $summary.installedApp = Get-AppEvidence
    Assert-SafeBaseline -Label 'Initial baseline'
    Write-RunnerLog "waiting $InitialDelaySeconds seconds before any network transition"
    Start-Sleep -Seconds $InitialDelaySeconds

    $summary.installedApp = Get-AppEvidence
    Assert-SafeBaseline -Label 'Pre-transition baseline'
    $deadman = Start-DeadmanRecovery
    Write-RunnerLog "deadman recovery started pid=$($deadman.Id) delay=$DeadmanDelaySeconds"

    & powershell.exe `
        -NoProfile `
        -NonInteractive `
        -ExecutionPolicy Bypass `
        -File $physicalTestScript `
        -InstallRoot $resolvedInstallRoot `
        -AppPath $resolvedAppPath `
        -UseUiAutomationAction `
        -ExpectCompetingVpn `
        -AllowExistingPreferredRoute `
        -FirstConnectTimeoutSeconds 90 `
        -MaxFirstConnectSeconds $MaxConnectSeconds `
        -MaxCachedConnectSeconds $MaxConnectSeconds `
        -FailsafeProcessId $deadman.Id `
        -ReportPath $physicalReportPath |
        Out-Null
    $physicalExitCode = $LASTEXITCODE
    if (-not (Test-Path -LiteralPath $physicalReportPath -PathType Leaf)) {
        throw "Installed physical smoke produced no report; exit code $physicalExitCode."
    }
    $physical = Get-Content -LiteralPath $physicalReportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ($physicalExitCode -ne 0 -or -not [bool]$physical.success) {
        throw "Installed physical smoke failed: $($physical.failure)"
    }
    $candidates = @($physical.competingVpnTakeover.candidates)
    if (
        $candidates.Count -ne 1 -or
        -not [bool]$physical.competingVpnTakeover.cachedRouteConfirmed -or
        -not [bool]$physical.competingVpnTakeover.probeConfirmed -or
        -not [bool]$physical.competingVpnTakeover.privilegedTakeoverConfirmed -or
        [double]$physical.competingVpnTakeover.logSeconds -gt $MaxConnectSeconds -or
        -not [bool]$physical.cleanup.allManagedComponentsStopped -or
        -not [bool]$physical.cleanup.externalVpnRestored -or
        -not [bool]$physical.cleanup.originalEgressRestored -or
        -not [bool]$physical.cleanup.publicHealth -or
        -not [bool]$physical.cleanup.failsafeStopped -or
        -not [bool]$physical.cleanup.restoreFailsafeRemoved
    ) {
        throw 'Installed physical smoke did not satisfy timing, takeover, cache, or cleanup gates.'
    }
    $summary.takeover = [ordered]@{
        logSeconds = [double]$physical.competingVpnTakeover.logSeconds
        wallSeconds = [double]$physical.competingVpnTakeover.wallSeconds
        candidate = $candidates[0]
        cachedRouteConfirmed = [bool]$physical.competingVpnTakeover.cachedRouteConfirmed
        probeConfirmed = [bool]$physical.competingVpnTakeover.probeConfirmed
        privilegedTakeoverConfirmed = [bool]$physical.competingVpnTakeover.privilegedTakeoverConfirmed
        cleanupConfirmed = $true
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
    $summary.cleanup.failsafeRemoved = -not [bool](
        Get-ScheduledTask -TaskName $failsafeTaskName -ErrorAction SilentlyContinue
    )

    $recoveryConfirmed =
        $summary.cleanup.recoverySuccess -and
        $summary.cleanup.greenUiStopped -and
        $summary.cleanup.greenComponentsStopped -and
        $summary.cleanup.externalVpnRunning -and
        $summary.cleanup.publicHealth -and
        $summary.cleanup.youtube -and
        $summary.cleanup.failsafeRemoved
    if ($recoveryConfirmed -and $null -ne $deadman) {
        try {
            Stop-Process -Id $deadman.Id -Force -ErrorAction Stop
        } catch {}
    }
    if ($null -eq $deadman) {
        $summary.cleanup.deadmanStopped = $true
    } else {
        $summary.cleanup.deadmanStopped =
            -not [bool](Get-Process -Id $deadman.Id -ErrorAction SilentlyContinue)
    }

    if (-not $recoveryConfirmed -or -not $summary.cleanup.deadmanStopped) {
        $summary.success = $false
        if (-not $summary.failure) {
            $summary.failure = 'Final recovery or deadman cleanup was not fully confirmed.'
        }
    }

    $summary.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-RunnerLog "finished success=$($summary.success)"
    if ($mutexAcquired) {
        try { $mutex.ReleaseMutex() } catch {}
    }
    $mutex.Dispose()
}

if (-not $summary.success) {
    exit 1
}

$summary | ConvertTo-Json -Depth 10
