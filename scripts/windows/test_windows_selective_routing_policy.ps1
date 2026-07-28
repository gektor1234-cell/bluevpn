param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tempBoundary = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
$testRoot = Join-Path $env:TEMP ("GreenVpnSelectiveRoutingTest_" + [guid]::NewGuid().ToString('N'))
$resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
if (-not ($resolvedTestRoot + '\').StartsWith($tempBoundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe selective-routing test path: $resolvedTestRoot"
}

New-Item -ItemType Directory -Path $resolvedTestRoot | Out-Null
try {
    $ProgramDataRoot = $resolvedTestRoot
    $ConfigPath = Join-Path $resolvedTestRoot 'test.conf'

    function Ensure-GreenProgramDataAcl {}
    function Write-GreenLog {
        param([string]$Message)
    }

    . (Join-Path $PSScriptRoot 'greenvpn_selective_routing.ps1')

    [IO.File]::WriteAllText(
        $RoutingModePath,
        'applications',
        [Text.UTF8Encoding]::new($false)
    )
    [ordered]@{
        schemaVersion = 2
        proxy = [ordered]@{
            host = '10.10.0.1'
            port = 1080
        }
        applications = @()
        destinationCidrs = @('142.250.0.0/15')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $RoutingAppsPath -Encoding UTF8
    [IO.File]::WriteAllText(
        $ConfigPath,
        "[Peer]`r`nAllowedIPs = 0.0.0.0/0, ::/0`r`n",
        [Text.UTF8Encoding]::new($false)
    )

    $policy = Get-GreenRoutingPolicy
    Ensure-GreenApplicationTunnelRoutes -Policy $policy
    $updated = [IO.File]::ReadAllText($ConfigPath)
    if ($updated -notmatch '(?m)^AllowedIPs = 142\.250\.0\.0/15$') {
        throw 'Selective routing did not keep the requested public destination.'
    }
    if ($updated -match '0\.0\.0\.0/0|0\.0\.0\.0/1|128\.0\.0\.0/1|::/0') {
        throw 'Selective routing retained a default route.'
    }

    [ordered]@{
        schemaVersion = 2
        proxy = [ordered]@{
            host = '10.10.0.1'
            port = 1080
        }
        applications = @()
        destinationCidrs = @('127.0.0.0/8')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $RoutingAppsPath -Encoding UTF8

    $privateCidrRejected = $false
    try {
        $invalidPolicy = Get-GreenRoutingPolicy
        [void](Get-GreenDestinationCidrs -Policy $invalidPolicy)
    }
    catch {
        $privateCidrRejected = $true
    }
    if (-not $privateCidrRejected) {
        throw 'Selective routing accepted a private destination CIDR.'
    }

    [pscustomobject]@{
        success = $true
        routingMode = Get-GreenRoutingMode
        defaultRoutesRemoved = $true
        privateCidrRejected = $privateCidrRejected
    } | ConvertTo-Json
}
finally {
    $cleanupTarget = [IO.Path]::GetFullPath($resolvedTestRoot)
    if (($cleanupTarget + '\').StartsWith($tempBoundary, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $cleanupTarget -Recurse -Force -ErrorAction SilentlyContinue
    }
}
