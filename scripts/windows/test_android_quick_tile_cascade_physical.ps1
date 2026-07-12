param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$Serial = 'R9WT10CDC2J',
    [string]$Package = 'pro.greenvpn.app.transportpreview',
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\android_quick_tile_cascade_physical_20260712.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$service = "$Package/pro.greenvpn.app.TransportContractDebugService"
$tileComponent = "$Package/pro.greenvpn.app.GreenVpnQuickTileService"
$tileSetting = "custom($tileComponent)"
$resultFile = 'files/greenvpn-transport-contract-debug-result.json'

function Invoke-Adb {
    param([string[]]$Arguments)
    $output = @(& $Adb -s $Serial @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "adb failed: $($output -join ' ')" }
    return $output
}

function Invoke-DebugCommand {
    param([string]$Command, [string[]]$Extras = @())
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', $resultFile) | Out-Null
    $arguments = @('shell', 'am', 'startservice', '-n', $service, '--es', 'command', $Command) + $Extras
    Invoke-Adb -Arguments $arguments | Out-Null
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $previous = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = (@(& $Adb -s $Serial shell run-as $Package cat $resultFile 2>$null) -join '').Trim()
            $readExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previous }
        if ($readExit -eq 0 -and $raw.StartsWith('{')) {
            $result = $raw | ConvertFrom-Json
            if (-not [bool]$result.success) { throw "debug command failed: $($result.error)" }
            return $result
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for debug command: $Command"
}

function Set-TileList {
    param([string]$Value)
    if ($Value.Contains("'")) { throw 'Unexpected quote in Android quick tile list.' }
    Invoke-Adb -Arguments @('shell', "settings put secure sysui_qs_tiles '$Value'") | Out-Null
}

function Wait-Route {
    param([string]$ExpectedProtocol, [int]$TimeoutSeconds = 75)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $snapshot = Invoke-DebugCommand -Command 'snapshot'
        $active = @($snapshot.activeProtocols)
        $lastRouteProperty = $snapshot.lastRouteSuccess.PSObject.Properties['protocol']
        $lastProtocol = if ($null -ne $lastRouteProperty) {
            [string]$lastRouteProperty.Value
        } else {
            ''
        }
        if ($active -contains $ExpectedProtocol -and $lastProtocol -eq $ExpectedProtocol) {
            return $snapshot
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    throw "Quick tile did not verify route: $ExpectedProtocol"
}

function Wait-Down {
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $snapshot = Invoke-DebugCommand -Command 'snapshot'
        if (@($snapshot.activeProtocols).Count -eq 0) { return $snapshot }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw 'Preview transport did not return to down state.'
}

if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) { throw "adb is missing: $Adb" }
$originalTiles = ((Invoke-Adb -Arguments @('shell', 'settings', 'get', 'secure', 'sysui_qs_tiles')) -join '').Trim()
$tileWasPresent = @($originalTiles.Split(',') | Where-Object { $_ -eq $tileSetting }).Count -gt 0
$firstRoute = $null
$cooldownRoute = $null

try {
    Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
    Invoke-DebugCommand -Command 'clear_tile_cooldown' | Out-Null
    Wait-Down | Out-Null

    if (-not $tileWasPresent) {
        $updatedTiles = if ($originalTiles -and $originalTiles -ne 'null') {
            "$originalTiles,$tileSetting"
        } else {
            $tileSetting
        }
        Set-TileList -Value $updatedTiles
        Start-Sleep -Seconds 2
    }

    Invoke-Adb -Arguments @('shell', 'cmd', 'statusbar', 'click-tile', $tileComponent) | Out-Null
    $firstRoute = Wait-Route -ExpectedProtocol 'amneziawg'
    Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
    Wait-Down | Out-Null

    Invoke-DebugCommand -Command 'set_tile_cooldown' -Extras @(
        '--es', 'serverId', 'nl2-awg2-canary',
        '--es', 'protocol', 'amneziawg',
        '--ei', 'failureCount', '1'
    ) | Out-Null
    Invoke-Adb -Arguments @('shell', 'cmd', 'statusbar', 'click-tile', $tileComponent) | Out-Null
    $cooldownRoute = Wait-Route -ExpectedProtocol 'hysteria2'

    $report = [ordered]@{
        capturedAt = (Get-Date).ToUniversalTime().ToString('o')
        serial = $Serial
        package = $Package
        tileWasPresent = $tileWasPresent
        strictFirstProtocol = [string]$firstRoute.lastRouteSuccess.protocol
        cooldownFallbackProtocol = [string]$cooldownRoute.lastRouteSuccess.protocol
        firstActiveProtocols = @($firstRoute.activeProtocols)
        cooldownActiveProtocols = @($cooldownRoute.activeProtocols)
        youtubeProbeRequiredBeforeSuccessMarker = $true
        success = $true
    }
    $directory = Split-Path -Parent $ReportPath
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
finally {
    try { Invoke-DebugCommand -Command 'disconnect_all' | Out-Null } catch {}
    try { Invoke-DebugCommand -Command 'clear_tile_cooldown' | Out-Null } catch {}
    if (-not $tileWasPresent) {
        try {
            Set-TileList -Value $originalTiles
        } catch {}
    }
    try { Wait-Down | Out-Null } catch {}
}

if ($null -eq $firstRoute -or $null -eq $cooldownRoute) {
    throw 'Quick tile cascade physical proof did not complete.'
}
Write-Host "Android quick tile cascade passed: $ReportPath"
Write-Host 'Strict first route: amneziawg'
Write-Host 'Cooldown fallback route: hysteria2'
