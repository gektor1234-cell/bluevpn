param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$project = [IO.Path]::GetFullPath($ProjectRoot)
$taskPath = Join-Path $project 'scripts\windows\greenvpn_transport_preview_vpn_task.ps1'
$installerPath = Join-Path $project 'scripts\windows\build_installer.ps1'
$runnerPath = Join-Path $project 'scripts\windows\run_windows_mode_reconcile_release_smoke.ps1'
$restorePath = Join-Path $project 'scripts\windows\restore_windows_smoke_network.ps1'
foreach ($path in @($taskPath, $installerPath, $runnerPath, $restorePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required source is missing: $path"
    }
}

$task = [IO.File]::ReadAllText($taskPath, [Text.UTF8Encoding]::new($true))
$installer = [IO.File]::ReadAllText($installerPath, [Text.UTF8Encoding]::new($true))
$runner = [IO.File]::ReadAllText($runnerPath, [Text.UTF8Encoding]::new($true))
$restore = [IO.File]::ReadAllText($restorePath, [Text.UTF8Encoding]::new($true))

$startMarker = 'function Start-OwnTunnel {'
$cleanupCall = 'if (-not (Remove-StandbyProbeFallbackArtifacts)) {'
$takeoverCall = "Stop-CompetingVpnTunnels -Reason 'connect'"
$startIndex = $task.IndexOf($startMarker, [StringComparison]::Ordinal)
$cleanupIndex = $task.IndexOf($cleanupCall, $startIndex, [StringComparison]::Ordinal)
$takeoverIndex = $task.IndexOf($takeoverCall, $startIndex, [StringComparison]::Ordinal)
if ($startIndex -lt 0 -or $cleanupIndex -lt $startIndex -or
    $takeoverIndex -lt $cleanupIndex) {
    throw 'Connect must remove standby artifacts before evaluating competing VPNs.'
}

foreach ($fragment in @(
    "`$StandbyProbeTunnelName = 'GreenVPNTransportPreviewStandbyProbe'",
    '/uninstalltunnelservice $StandbyProbeTunnelName',
    'Get-NetAdapter -Name $StandbyProbeTunnelName',
    'connect phase=standby-cleanup-complete',
    'connect phase=standby-cleanup-failed'
)) {
    if (-not $task.Contains($fragment)) {
        throw "Standby connect cleanup marker is missing: $fragment"
    }
}

foreach ($fragment in @(
    "`$ConnectFailureDiagnosticsPath = Join-Path `$ProgramDataRoot 'state\connect-failure-diagnostics.json'",
    'function Write-GreenConnectFailureSnapshot {',
    'nativeTunnel = Get-GreenNativeTunnelTelemetry -Engine $engine',
    'rawConfigStored = $false',
    'rawKeysStored = $false',
    'rawEndpointStored = $false',
    "Write-GreenConnectFailureSnapshot -FailureRecord `$failure"
)) {
    if (-not $task.Contains($fragment)) {
        throw "Connect failure diagnostic marker is missing: $fragment"
    }
}

$failureCatchIndex = $task.IndexOf(
    'Write-GreenConnectFailureSnapshot -FailureRecord $failure',
    [StringComparison]::Ordinal
)
$failureRecoveryIndex = $task.IndexOf(
    'Complete-GreenDisconnectedRuntimeState',
    $failureCatchIndex,
    [StringComparison]::Ordinal
)
if ($failureCatchIndex -lt 0 -or $failureRecoveryIndex -lt $failureCatchIndex) {
    throw 'Connect failure diagnostics must be captured before failure recovery.'
}

foreach ($fragment in @(
    'function Remove-GreenVpnStandbyProbeArtifacts {',
    "`$tunnelName = 'BlueVPNDev1StandbyProbe'",
    '/uninstalltunnelservice $tunnelName',
    'Get-NetAdapter -Name $tunnelName',
    'if (-not (Remove-GreenVpnStandbyProbeArtifacts)) {'
)) {
    if (-not $installer.Contains($fragment)) {
        throw "Installer standby cleanup marker is missing: $fragment"
    }
}

foreach ($fragment in @(
    "'WireGuardTunnel`$BlueVPNDev1StandbyProbe'",
    "'AmneziaWGTunnel`$BlueVPNDev1StandbyProbe'"
)) {
    if (-not $runner.Contains($fragment)) {
        throw "Physical smoke managed-service marker is missing: $fragment"
    }
}

foreach ($fragment in @(
    "[string]`$LegacyStandbyProbeTunnelName = 'BlueVPNDev1StandbyProbe'",
    "('WireGuardTunnel`$' + `$LegacyStandbyProbeTunnelName)",
    "('AmneziaWGTunnel`$' + `$LegacyStandbyProbeTunnelName)"
)) {
    if (-not $restore.Contains($fragment)) {
        throw "Network recovery managed-service marker is missing: $fragment"
    }
}

Write-Output 'Windows standby connect cleanup contract test passed.'
