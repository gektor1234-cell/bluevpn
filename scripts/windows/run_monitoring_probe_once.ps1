param(
    [string]$ApiBase = "https://api.greenvpn.pro",
    [string]$ProbeId = "",
    [string]$ProbeRegion = "local-windows",
    [string]$AdminTokenFile = "",
    [switch]$AdminTokenFromStdin,
    [string[]]$TargetId = @(),
    [ValidateSet("active", "paused", "disabled", "all")]
    [string]$Status = "active",
    [int]$Limit = 200,
    [switch]$ServerHealth,
    [switch]$RouteHealth,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")
$probeScript = Join-Path $repoRoot "scripts\monitoring\service_probe.py"

if (-not (Test-Path -LiteralPath $probeScript)) {
    throw "Monitoring probe script not found: $probeScript"
}

if ([string]::IsNullOrWhiteSpace($ProbeId)) {
    $machine = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($machine)) {
        $machine = "windows"
    }
    $ProbeId = "windows-$($machine.ToLowerInvariant())"
}

$argsList = @(
    $probeScript,
    "--api-base", $ApiBase,
    "--probe-id", $ProbeId,
    "--probe-region", $ProbeRegion,
    "--status", $Status,
    "--limit", $Limit
)

if (-not [string]::IsNullOrWhiteSpace($AdminTokenFile)) {
    $resolvedTokenFile = Resolve-Path -LiteralPath $AdminTokenFile
    $argsList += @("--admin-token-file", $resolvedTokenFile.Path)
}

if ($AdminTokenFromStdin) {
    $argsList += "--admin-token-stdin"
}

foreach ($target in $TargetId) {
    if (-not [string]::IsNullOrWhiteSpace($target)) {
        $argsList += @("--target-id", $target)
    }
}

if ($DryRun) {
    $argsList += "--dry-run"
}

if ($ServerHealth) {
    $argsList += "--server-health"
}

if ($RouteHealth) {
    $argsList += "--route-health"
}

Write-Host "[Green VPN monitoring probe] api=$ApiBase probe=$ProbeId region=$ProbeRegion serverHealth=$($ServerHealth.IsPresent) routeHealth=$($RouteHealth.IsPresent) dryRun=$($DryRun.IsPresent)"
Write-Host "[Green VPN monitoring probe] Secrets are read only from stdin, env GREENVPN_ADMIN_TOKEN, or token file."

& python @argsList
exit $LASTEXITCODE
