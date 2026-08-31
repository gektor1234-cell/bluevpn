param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$project = [IO.Path]::GetFullPath($ProjectRoot)
$taskPath = Join-Path $project 'scripts\windows\greenvpn_transport_preview_vpn_task.ps1'
$installerPath = Join-Path $project 'scripts\windows\build_installer.ps1'
foreach ($path in @($taskPath, $installerPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required source is missing: $path"
    }
}

$task = [IO.File]::ReadAllText($taskPath, [Text.UTF8Encoding]::new($true))
$installer = [IO.File]::ReadAllText($installerPath, [Text.UTF8Encoding]::new($true))

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

Write-Output 'Windows standby connect cleanup contract test passed.'
