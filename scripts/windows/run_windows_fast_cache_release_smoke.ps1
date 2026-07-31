[CmdletBinding()]
param(
    [string]$InstallerPath = 'C:\BlueVPN_Builds\public_product_20260731_b3103_fast_cache_v3\GreenVPN_Setup_0.3.24.exe',
    [string]$ExpectedSha256 = 'A6938B0EBA54BF0CC4CE029F8A3365D28DB63FA280A2E897B63FEA079F02FA38',
    [long]$ExpectedSizeBytes = 55401472,
    [string]$ExpectedFileVersion = '0.3.24+3103',
    [string]$ArtifactRoot = 'C:\BlueVPN_Builds\public_product_20260731_b3103_fast_cache_v3',
    [string]$ExternalVpnServiceName = 'AmneziaWGTunnel$device20_full',
    [ValidateRange(30, 300)]
    [int]$InitialDelaySeconds = 90,
    [ValidateRange(10, 120)]
    [int]$MaxConnectSeconds = 30,
    [int]$DeadmanProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testScript = Join-Path $repoRoot 'scripts\windows\test_windows_connect_latency_physical.ps1'
$restoreScript = Join-Path $repoRoot 'scripts\windows\restore_windows_smoke_network.ps1'
$summaryPath = Join-Path $ArtifactRoot 'windows-fast-cache-autonomous-summary.json'
$logPath = Join-Path $ArtifactRoot 'windows-fast-cache-autonomous.log'
$firstReportPath = Join-Path $ArtifactRoot 'windows-fast-cache-first-takeover-physical.json'
$cachedReportPath = Join-Path $ArtifactRoot 'windows-fast-cache-repeat-takeover-physical.json'
$recoveryReportPath = Join-Path $ArtifactRoot 'windows-fast-cache-final-recovery.json'
$failsafeTaskName = 'GreenVPNConnectLatencySmokeFailsafe'
$runStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$extractRoot = Join-Path $ArtifactRoot "autonomous-installer-extract-$runStamp"
$runtimeRoot = Join-Path $ArtifactRoot "autonomous-runtime-$runStamp"
$isolatedAppDataRoot = Join-Path $ArtifactRoot "autonomous-appdata-$runStamp"
$isolatedUserStateRoot = Join-Path $isolatedAppDataRoot 'GreenVPN\state'

function Write-RunnerLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
        "[$((Get-Date).ToUniversalTime().ToString('o'))] $Message"
    )
}

function Get-ServiceState {
    param([Parameter(Mandatory = $true)][string]$Name)

    $service = Get-CimInstance Win32_Service `
        -Filter "Name='$Name'" `
        -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        return 'Missing'
    }
    return [string]$service.State
}

function Test-PublicHealth {
    try {
        return (Invoke-WebRequest `
            -UseBasicParsing `
            -Uri 'https://api.greenvpn.pro/healthz' `
            -TimeoutSec 15).StatusCode -eq 200
    } catch {
        return $false
    }
}

function Test-YouTube {
    try {
        $status = (Invoke-WebRequest `
            -UseBasicParsing `
            -Uri 'https://www.youtube.com/generate_204' `
            -TimeoutSec 20).StatusCode
        return $status -in @(200, 204)
    } catch {
        return $false
    }
}

function Assert-Cleanup {
    param(
        [Parameter(Mandatory = $true)]$Report,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (
        -not [bool]$Report.cleanup.allManagedComponentsStopped -or
        -not [bool]$Report.cleanup.externalVpnRestored -or
        -not [bool]$Report.cleanup.originalEgressRestored -or
        -not [bool]$Report.cleanup.restoreFailsafeRemoved -or
        -not [bool]$Report.cleanup.publicHealth
    ) {
        throw "$Label did not restore the full network baseline."
    }
}

function Prepare-ExactCandidate {
    $installer = (Resolve-Path -LiteralPath $InstallerPath).Path
    $actualSize = (Get-Item -LiteralPath $installer).Length
    $actualSha = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
    if ($actualSize -ne $ExpectedSizeBytes) {
        throw "Installer size mismatch: expected $ExpectedSizeBytes, got $actualSize."
    }
    if ($actualSha -ne $ExpectedSha256) {
        throw "Installer SHA-256 mismatch: expected $ExpectedSha256, got $actualSha."
    }

    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    $extract = Start-Process `
        -FilePath $installer `
        -ArgumentList @('/Q', "/T:$extractRoot", '/C') `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if ($extract.ExitCode -ne 0) {
        throw "Exact installer extraction failed with exit code $($extract.ExitCode)."
    }

    $payloadZip = Join-Path $extractRoot 'GreenVPN_payload.zip'
    if (-not (Test-Path -LiteralPath $payloadZip -PathType Leaf)) {
        throw "Exact installer payload entry is missing: $payloadZip"
    }

    New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
    Expand-Archive -LiteralPath $payloadZip -DestinationPath $runtimeRoot -Force

    $portableExe = Join-Path $runtimeRoot 'app\greenvpn.exe'
    if (-not (Test-Path -LiteralPath $portableExe -PathType Leaf)) {
        throw 'Exact installer runtime does not contain Green VPN.'
    }
    $portableVersion = (Get-Item -LiteralPath $portableExe).VersionInfo.FileVersion
    if ($portableVersion -ne $ExpectedFileVersion) {
        throw "Exact runtime version mismatch: expected $ExpectedFileVersion, got $portableVersion."
    }
    $candidateTask = Join-Path $runtimeRoot 'tools\greenvpn_vpn_task.ps1'
    $installedTask = 'C:\Program Files\Green VPN\tools\greenvpn_vpn_task.ps1'
    foreach ($taskPath in @($candidateTask, $installedTask)) {
        if (-not (Test-Path -LiteralPath $taskPath -PathType Leaf)) {
            throw "Privileged VPN task is missing: $taskPath"
        }
        $taskText = Get-Content -LiteralPath $taskPath -Raw -Encoding UTF8
        foreach ($marker in @(
            'Save-CompetingVpnState',
            'Restore-CompetingVpnTunnels',
            '$activeAdapters = @(if ('
        )) {
            if (-not $taskText.Contains($marker)) {
                throw "Privileged VPN task lacks required marker '$marker': $taskPath"
            }
        }
    }
    return [ordered]@{
        installerPath = $installer
        sha256 = $actualSha
        sizeBytes = $actualSize
        runtimePath = $portableExe
        runtimeFileVersion = $portableVersion
        exactPayloadExtracted = $true
        candidateTaskContractConfirmed = $true
        installedTaskContractConfirmed = $true
    }
}

$summary = [ordered]@{
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    completedAtUtc = $null
    success = $false
    failure = $null
    initialDelaySeconds = $InitialDelaySeconds
    maxConnectSeconds = $MaxConnectSeconds
    installer = $null
    isolatedAppDataRoot = $isolatedAppDataRoot
    firstReport = $firstReportPath
    cachedReport = $cachedReportPath
    firstConnect = $null
    cachedConnect = $null
    cleanup = [ordered]@{
        recoveryReport = $recoveryReportPath
        recoverySuccess = $false
        externalVpnRunning = $false
        greenUiStopped = $false
        publicHealth = $false
        youtube = $false
        failsafeRemoved = $false
        deadmanStopped = $DeadmanProcessId -le 0
    }
}

try {
    if (-not (Test-Path -LiteralPath $testScript -PathType Leaf)) {
        throw "Physical latency test is missing: $testScript"
    }
    if (-not (Test-Path -LiteralPath $restoreScript -PathType Leaf)) {
        throw "Network recovery script is missing: $restoreScript"
    }
    if ((Get-ServiceState -Name $ExternalVpnServiceName) -ne 'Running') {
        throw "$ExternalVpnServiceName must be running before the autonomous smoke."
    }
    if (-not (Test-PublicHealth)) {
        throw 'Public connectivity baseline failed before the autonomous smoke.'
    }

    Write-RunnerLog "waiting $InitialDelaySeconds seconds before exact-runtime network transitions"
    Start-Sleep -Seconds $InitialDelaySeconds

    Write-RunnerLog 'extracting the exact candidate runtime without installing it'
    $summary.installer = Prepare-ExactCandidate
    $exactRuntimePath = [string]$summary.installer.runtimePath
    if ((Get-ServiceState -Name $ExternalVpnServiceName) -ne 'Running') {
        throw 'Exact candidate extraction changed the active external VPN.'
    }

    New-Item -ItemType Directory -Force -Path $isolatedUserStateRoot | Out-Null
    $env:APPDATA = $isolatedAppDataRoot

    Write-RunnerLog 'starting clean-profile competing-VPN takeover smoke'
    & powershell.exe `
        -NoProfile `
        -NonInteractive `
        -ExecutionPolicy Bypass `
        -File $testScript `
        -AppPath $exactRuntimePath `
        -UserStateRoot $isolatedUserStateRoot `
        -UseUiAutomationAction `
        -ExpectCompetingVpn `
        -FirstConnectTimeoutSeconds 90 `
        -MaxFirstConnectSeconds $MaxConnectSeconds `
        -MaxCachedConnectSeconds $MaxConnectSeconds `
        -ReportPath $firstReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "First takeover smoke returned exit code $LASTEXITCODE."
    }
    $first = Get-Content -LiteralPath $firstReportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if (-not [bool]$first.success) {
        throw "First takeover smoke failed: $($first.failure)"
    }
    Assert-Cleanup -Report $first -Label 'First takeover smoke'
    $firstCandidates = @($first.competingVpnTakeover.candidates)
    if (
        $firstCandidates.Count -ne 1 -or
        -not [bool]$first.competingVpnTakeover.probeConfirmed -or
        -not [bool]$first.competingVpnTakeover.privilegedTakeoverConfirmed -or
        [double]$first.competingVpnTakeover.logSeconds -gt $MaxConnectSeconds
    ) {
        throw 'First competing-VPN takeover did not satisfy the foreground timing contract.'
    }
    $summary.firstConnect = [ordered]@{
        logSeconds = [double]$first.competingVpnTakeover.logSeconds
        wallSeconds = [double]$first.competingVpnTakeover.wallSeconds
        candidate = $firstCandidates[0]
        storedPreference = $first.storedPreference
        probeConfirmed = [bool]$first.competingVpnTakeover.probeConfirmed
        privilegedTakeoverConfirmed = [bool]$first.competingVpnTakeover.privilegedTakeoverConfirmed
        cleanupConfirmed = $true
    }

    Write-RunnerLog 'starting exact cached-route competing-VPN takeover smoke'
    & powershell.exe `
        -NoProfile `
        -NonInteractive `
        -ExecutionPolicy Bypass `
        -File $testScript `
        -AppPath $exactRuntimePath `
        -UserStateRoot $isolatedUserStateRoot `
        -UseUiAutomationAction `
        -ExpectCompetingVpn `
        -AllowExistingPreferredRoute `
        -FirstConnectTimeoutSeconds 90 `
        -MaxFirstConnectSeconds $MaxConnectSeconds `
        -MaxCachedConnectSeconds $MaxConnectSeconds `
        -ReportPath $cachedReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "Cached takeover smoke returned exit code $LASTEXITCODE."
    }
    $cached = Get-Content -LiteralPath $cachedReportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if (-not [bool]$cached.success) {
        throw "Cached takeover smoke failed: $($cached.failure)"
    }
    Assert-Cleanup -Report $cached -Label 'Cached takeover smoke'
    $cachedCandidates = @($cached.competingVpnTakeover.candidates)
    if (
        $cachedCandidates.Count -ne 1 -or
        [string]$cachedCandidates[0].id -ne [string]$first.storedPreference.routeId -or
        [string]$cachedCandidates[0].protocol -ne [string]$first.storedPreference.protocol -or
        -not [bool]$cached.competingVpnTakeover.cachedRouteConfirmed -or
        -not [bool]$cached.competingVpnTakeover.probeConfirmed -or
        -not [bool]$cached.competingVpnTakeover.privilegedTakeoverConfirmed -or
        [double]$cached.competingVpnTakeover.logSeconds -gt $MaxConnectSeconds
    ) {
        throw 'Cached competing-VPN takeover did not satisfy the exact-route timing contract.'
    }
    $summary.cachedConnect = [ordered]@{
        logSeconds = [double]$cached.competingVpnTakeover.logSeconds
        wallSeconds = [double]$cached.competingVpnTakeover.wallSeconds
        candidate = $cachedCandidates[0]
        probeConfirmed = [bool]$cached.competingVpnTakeover.probeConfirmed
        privilegedTakeoverConfirmed = [bool]$cached.competingVpnTakeover.privilegedTakeoverConfirmed
        cachedRouteConfirmed = [bool]$cached.competingVpnTakeover.cachedRouteConfirmed
        cleanupConfirmed = $true
    }

    $summary.success = $true
} catch {
    $summary.failure = $_.Exception.Message
    Write-RunnerLog "failed: $($summary.failure)"
} finally {
    try {
        & powershell.exe `
            -NoProfile `
            -NonInteractive `
            -ExecutionPolicy Bypass `
            -File $restoreScript `
            -StopGreenUi `
            -ExternalVpnServiceName $ExternalVpnServiceName `
            -ReportPath $recoveryReportPath |
            Out-Null
        if (Test-Path -LiteralPath $recoveryReportPath -PathType Leaf) {
            $recovery = Get-Content -LiteralPath $recoveryReportPath -Raw -Encoding UTF8 |
                ConvertFrom-Json
            $summary.cleanup.recoverySuccess = [bool]$recovery.success
            $summary.cleanup.greenUiStopped = [bool]$recovery.greenUiStopped
        }
    } catch {}

    try {
        Unregister-ScheduledTask `
            -TaskName $failsafeTaskName `
            -Confirm:$false `
            -ErrorAction SilentlyContinue
    } catch {}
    $summary.cleanup.failsafeRemoved = -not [bool](
        Get-ScheduledTask -TaskName $failsafeTaskName -ErrorAction SilentlyContinue
    )
    if ($DeadmanProcessId -gt 0) {
        try {
            Stop-Process -Id $DeadmanProcessId -Force -ErrorAction Stop
        } catch {}
        for ($attempt = 0; $attempt -lt 30; $attempt += 1) {
            if (-not (Get-Process -Id $DeadmanProcessId -ErrorAction SilentlyContinue)) {
                break
            }
            Start-Sleep -Milliseconds 100
        }
        $summary.cleanup.deadmanStopped =
            -not [bool](Get-Process -Id $DeadmanProcessId -ErrorAction SilentlyContinue)
    }
    $summary.cleanup.externalVpnRunning =
        (Get-ServiceState -Name $ExternalVpnServiceName) -eq 'Running'
    $summary.cleanup.publicHealth = Test-PublicHealth
    $summary.cleanup.youtube = Test-YouTube

    if (
        -not $summary.cleanup.recoverySuccess -or
        -not $summary.cleanup.greenUiStopped -or
        -not $summary.cleanup.externalVpnRunning -or
        -not $summary.cleanup.publicHealth -or
        -not $summary.cleanup.youtube -or
        -not $summary.cleanup.failsafeRemoved -or
        -not $summary.cleanup.deadmanStopped
    ) {
        $summary.success = $false
        if (-not $summary.failure) {
            $summary.failure = 'Final network recovery was not fully confirmed.'
        }
    }

    $summary.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-RunnerLog "finished success=$($summary.success)"
}

if (-not $summary.success) {
    exit 1
}

$summary | ConvertTo-Json -Depth 10
