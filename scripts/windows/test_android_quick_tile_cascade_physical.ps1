param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$Serial = '',
    [string]$Package = 'pro.greenvpn.app.transportpreview',
    [string]$ProbePackage = 'pro.greenvpn.transportprobe',
    [ValidateRange(1, 6)][int]$StartStage = 1,
    [ValidateRange(1, 6)][int]$EndStage = 6,
    [ValidateRange(1, 5)][int]$ProbeAttempts = 3,
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\android_quick_tile_cascade_physical_20260714.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$service = "$Package/pro.greenvpn.app.TransportContractDebugService"
$tileComponent = "$Package/pro.greenvpn.app.GreenVpnQuickTileService"
$tileSetting = "custom($tileComponent)"
$resultFile = 'files/greenvpn-transport-contract-debug-result.json'

$transportCandidates = @(
    [pscustomobject]@{ serverId = 'current_wg0'; protocol = 'wireguard_udp'; egress = '37.220.85.211' },
    [pscustomobject]@{ serverId = 'ruvds-2584554-ld8'; protocol = 'wireguard_udp'; egress = '88.218.250.86' },
    [pscustomobject]@{ serverId = 'tw-7879598-nl1'; protocol = 'wireguard_udp'; egress = '5.129.216.42' },
    [pscustomobject]@{ serverId = 'gb1-awg2-canary'; protocol = 'amneziawg'; egress = '88.218.250.86' },
    [pscustomobject]@{ serverId = 'nl1-awg2-canary'; protocol = 'amneziawg'; egress = '37.220.85.211' },
    [pscustomobject]@{ serverId = 'nl2-awg2-canary'; protocol = 'amneziawg'; egress = '5.129.216.42' },
    [pscustomobject]@{ serverId = 'gb1-hysteria2-canary'; protocol = 'hysteria2'; egress = '88.218.250.86' },
    [pscustomobject]@{ serverId = 'nl1-hysteria2-canary'; protocol = 'hysteria2'; egress = '37.220.85.211' },
    [pscustomobject]@{ serverId = 'nl2-hysteria2-canary'; protocol = 'hysteria2'; egress = '5.129.216.42' },
    [pscustomobject]@{ serverId = 'gb1-vless-reality-xhttp-canary'; protocol = 'vless_reality'; egress = '88.218.250.86' },
    [pscustomobject]@{ serverId = 'nl1-vless-reality-xhttp-canary'; protocol = 'vless_reality'; egress = '37.220.85.211' },
    [pscustomobject]@{ serverId = 'nl2-vless-reality-xhttp-canary'; protocol = 'vless_reality'; egress = '5.129.216.42' },
    [pscustomobject]@{ serverId = 'gb1-naive-https-canary'; protocol = 'naive_https'; egress = '88.218.250.86' },
    [pscustomobject]@{ serverId = 'nl1-naive-https-canary'; protocol = 'naive_https'; egress = '37.220.85.211' },
    [pscustomobject]@{ serverId = 'nl2-naive-https-canary'; protocol = 'naive_https'; egress = '5.129.216.42' },
    [pscustomobject]@{ serverId = 'nl2-dnstt-canary'; protocol = 'dnstt'; egress = '5.129.216.42' }
)
$protocolOrder = @('wireguard_udp', 'amneziawg', 'hysteria2', 'vless_reality', 'naive_https', 'dnstt')

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $Adb -s $Serial @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) { throw "adb failed: $($Arguments -join ' ') :: $($output -join ' ')" }
    return $output
}

function Invoke-DebugCommand {
    param([string]$Command, [string[]]$Extras = @(), [int]$TimeoutSeconds = 45)
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', $resultFile) | Out-Null
    $arguments = @('shell', 'am', 'startservice', '-n', $service, '--es', 'command', $Command) + $Extras
    Invoke-Adb -Arguments $arguments | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
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

function Invoke-ExternalProbe {
    param([int]$TimeoutSeconds = 45)
    $result = [ordered]@{}
    foreach ($target in @('egressAlternate', 'productionApi', 'paidBetaPrimary', 'paidBetaFallback', 'youtube')) {
        $probe = $null
        $attemptUsed = 0
        for ($attempt = 1; $attempt -le $ProbeAttempts; $attempt++) {
            $attemptUsed = $attempt
            Invoke-Adb -Arguments @('shell', 'run-as', $ProbePackage, 'rm', '-f', 'files/transport-probe-result.json') | Out-Null
            Invoke-Adb -Arguments @(
                'shell', 'am', 'broadcast', '--include-stopped-packages',
                '-a', 'pro.greenvpn.transportprobe.RUN',
                '-n', "$ProbePackage/pro.greenvpn.transportprobe.TransportProbeReceiver",
                '--es', 'target', $target
            ) | Out-Null
            $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
            do {
                $previous = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    $raw = (@(& $Adb -s $Serial shell run-as $ProbePackage cat files/transport-probe-result.json 2>$null) -join '').Trim()
                    $readExit = $LASTEXITCODE
                } finally { $ErrorActionPreference = $previous }
                if ($readExit -eq 0 -and $raw.StartsWith('{')) {
                    $probe = $raw | ConvertFrom-Json
                    break
                }
                Start-Sleep -Milliseconds 200
            } while ((Get-Date) -lt $deadline)
            if ($null -ne $probe -and [int]$probe.status -ne 0) { break }
            if ($attempt -lt $ProbeAttempts) { Start-Sleep -Milliseconds 750 }
        }
        if ($null -eq $probe) { throw "Timed out waiting for Android transport probe: $target" }
        $resultKey = if ($target -eq 'egressAlternate') { 'egress' } else { $target }
        $result[$resultKey + 'Status'] = [int]$probe.status
        $result[$resultKey + 'Error'] = [string]$probe.error
        $result[$resultKey + 'Attempts'] = $attemptUsed
        if ($target -eq 'egressAlternate') {
            $result.egress = ([string]$probe.body).Trim()
        }
    }
    return [pscustomobject]$result
}

function Assert-ExternalProbe {
    param([Parameter(Mandatory = $true)]$Probe, [string[]]$ExpectedEgresses = @())
    if ($Probe.egressStatus -ne 200 -or [string]::IsNullOrWhiteSpace([string]$Probe.egress)) {
        throw "Route egress probe failed: status=$($Probe.egressStatus) error=$($Probe.egressError)"
    }
    if ($ExpectedEgresses.Count -gt 0 -and $Probe.egress -notin $ExpectedEgresses) {
        throw "Unexpected canary egress: $($Probe.egress)"
    }
    foreach ($property in @('productionApiStatus', 'paidBetaPrimaryStatus', 'paidBetaFallbackStatus')) {
        if ([int]$Probe.$property -ne 200) { throw "Route API probe failed: $property=$($Probe.$property)" }
    }
    if ([int]$Probe.youtubeStatus -notin @(200, 204)) {
        throw "Route YouTube probe failed: status=$($Probe.youtubeStatus) error=$($Probe.youtubeError)"
    }
}

function Get-VpnRecordCount {
    return @(
        Invoke-Adb -Arguments @('shell', 'dumpsys', 'connectivity') |
            Select-String -Pattern 'type: VPN\[\], state: CONNECTED/CONNECTED'
    ).Count
}

function Get-TransportEngineProcessCount {
    return @(
        Invoke-Adb -Arguments @('shell', 'ps', '-A', '-o', 'PID,PPID,NAME,ARGS') |
            Select-String -Pattern 'libhysteria\.so|libxray\.so|libnaive\.so|libdnstt_client\.so'
    ).Count
}

function Set-TileList {
    param([string]$Value)
    if ($Value.Contains("'")) { throw 'Unexpected quote in Android quick tile list.' }
    Invoke-Adb -Arguments @('shell', "settings put secure sysui_qs_tiles '$Value'") | Out-Null
}

function Click-Tile {
    # Samsung Android 9 unbinds third-party tiles shortly after the shade closes.
    # Expanding Quick Settings first makes SystemUI bind the TileService again,
    # which matches a real user tap instead of invoking a stale binder.
    Invoke-Adb -Arguments @('shell', 'cmd', 'statusbar', 'expand-settings') | Out-Null
    Start-Sleep -Milliseconds 900
    Invoke-Adb -Arguments @('shell', 'cmd', 'statusbar', 'click-tile', $tileComponent) | Out-Null
    Start-Sleep -Milliseconds 250
    Invoke-Adb -Arguments @('shell', 'cmd', 'statusbar', 'collapse') | Out-Null
}

function Wait-Route {
    param([string]$ExpectedProtocol, [int]$TimeoutSeconds = 100)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $snapshot = $null
    do {
        $snapshot = Invoke-DebugCommand -Command 'snapshot'
        $active = @($snapshot.activeProtocols)
        $lastRouteProperty = $snapshot.lastRouteSuccess.PSObject.Properties['protocol']
        $lastProtocol = if ($null -ne $lastRouteProperty) { [string]$lastRouteProperty.Value } else { '' }
        $activeMatches = if ($ExpectedProtocol -eq 'wireguard_udp') {
            $active.Count -eq 0 -and (Get-VpnRecordCount) -eq 1
        } else {
            $active.Count -eq 1 -and
                $active[0] -eq $ExpectedProtocol -and
                (Get-VpnRecordCount) -eq 1
        }
        if ($lastProtocol -eq $ExpectedProtocol -and $activeMatches) { return $snapshot }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    $active = @($snapshot.activeProtocols) -join ','
    $lastRouteProperty = $snapshot.lastRouteSuccess.PSObject.Properties['protocol']
    $lastProtocol = if ($null -ne $lastRouteProperty) { [string]$lastRouteProperty.Value } else { '' }
    throw "Quick tile did not verify route: expected=$ExpectedProtocol active=[$active] lastRoute=$lastProtocol"
}

function Wait-Down {
    param([int]$TimeoutSeconds = 40)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $snapshot = $null
    do {
        $snapshot = Invoke-DebugCommand -Command 'snapshot'
        $lastRouteProperty = $snapshot.lastRouteSuccess.PSObject.Properties['protocol']
        $lastProtocol = if ($null -ne $lastRouteProperty) { [string]$lastRouteProperty.Value } else { '' }
        if (
            @($snapshot.activeProtocols).Count -eq 0 -and
            -not $lastProtocol -and
            (Get-VpnRecordCount) -eq 0 -and
            (Get-TransportEngineProcessCount) -eq 0
        ) {
            return $snapshot
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    $active = @($snapshot.activeProtocols) -join ','
    $lastRouteProperty = $snapshot.lastRouteSuccess.PSObject.Properties['protocol']
    $lastProtocol = if ($null -ne $lastRouteProperty) { [string]$lastRouteProperty.Value } else { '' }
    throw "VPN did not return to a clean down state: active=[$active] lastRoute=$lastProtocol"
}

function Clear-Cooldown {
    Invoke-DebugCommand -Command 'clear_tile_cooldown' | Out-Null
}

function Set-Cooldown {
    param([Parameter(Mandatory = $true)]$Candidate)
    Invoke-DebugCommand -Command 'set_tile_cooldown' -Extras @(
        '--es', 'serverId', [string]$Candidate.serverId,
        '--es', 'protocol', [string]$Candidate.protocol,
        '--ei', 'failureCount', '1'
    ) | Out-Null
}

function Disconnect-ThroughTile {
    Click-Tile
    Wait-Down | Out-Null
}

if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) { throw "adb is missing: $Adb" }
if ([string]::IsNullOrWhiteSpace($Serial)) {
    $connectedSerials = @(
        & $Adb devices |
            Select-String -Pattern '^\S+\s+device$' |
            ForEach-Object { ($_.Line -split '\s+')[0] }
    )
    if ($connectedSerials.Count -ne 1) {
        throw "Expected exactly one ready Android device, found $($connectedSerials.Count)."
    }
    $Serial = $connectedSerials[0]
}
if (((Invoke-Adb -Arguments @('get-state')) -join '').Trim() -ne 'device') { throw "Android device is not ready: $Serial" }
if ($StartStage -gt $EndStage) { throw 'StartStage must be less than or equal to EndStage.' }
if (-not ((Invoke-Adb -Arguments @('shell', 'pm', 'path', $ProbePackage)) -join '').Contains('package:')) {
    throw "Android transport probe is not installed: $ProbePackage"
}

$originalTiles = ((Invoke-Adb -Arguments @('shell', 'settings', 'get', 'secure', 'sysui_qs_tiles')) -join '').Trim()
$tileWasPresent = @($originalTiles.Split(',') | Where-Object { $_ -eq $tileSetting }).Count -gt 0
$stageReports = [System.Collections.Generic.List[object]]::new()
$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    finishedAt = ''
    device = 'selected-android-device'
    package = $Package
    versionCode = ''
    strictOrder = $protocolOrder
    tileWasPresent = $tileWasPresent
    selectionMethod = 'physical_quick_tile_with_persisted_cooldown'
    stages = @()
    restoredFirstRoute = $null
    youtubeProbeRequiredBeforeSuccessMarker = $true
    cleanupVerified = $false
    success = $false
    error = ''
}

try {
    $packageDump = Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $Package)
    $versionLine = $packageDump | Select-String -Pattern 'versionCode=' | Select-Object -First 1
    if ($null -eq $versionLine) { throw "Preview package is not installed: $Package" }
    $report.versionCode = [regex]::Match($versionLine.Line, 'versionCode=(\d+)').Groups[1].Value

    Invoke-Adb -Arguments @('shell', 'am', 'set-inactive', $Package, 'false') | Out-Null
    Invoke-Adb -Arguments @('shell', 'am', 'set-standby-bucket', $Package, 'active') | Out-Null
    Invoke-Adb -Arguments @('shell', 'cmd', 'deviceidle', 'whitelist', "+$Package") | Out-Null
    Invoke-Adb -Arguments @('shell', 'am', 'set-inactive', $ProbePackage, 'false') | Out-Null
    Invoke-Adb -Arguments @('shell', 'am', 'set-standby-bucket', $ProbePackage, 'active') | Out-Null
    Invoke-Adb -Arguments @('shell', 'cmd', 'deviceidle', 'whitelist', "+$ProbePackage") | Out-Null
    Invoke-Adb -Arguments @('shell', 'am', 'start', '-n', "$Package/pro.greenvpn.app.MainActivity") | Out-Null
    Start-Sleep -Seconds 2

    Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
    Clear-Cooldown
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

    for ($stageIndex = $StartStage - 1; $stageIndex -lt $EndStage; $stageIndex++) {
        Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
        Clear-Cooldown
        Wait-Down | Out-Null

        $cooledCandidates = @(
            $transportCandidates |
                Where-Object {
                    [array]::IndexOf($protocolOrder, [string]$_.protocol) -lt $stageIndex
                }
        )
        foreach ($candidate in $cooledCandidates) {
            Set-Cooldown -Candidate $candidate
        }

        $expectedProtocol = $protocolOrder[$stageIndex]
        Click-Tile
        $snapshot = Wait-Route -ExpectedProtocol $expectedProtocol
        $probe = Invoke-ExternalProbe
        $selectedCandidate = @(
            $transportCandidates |
                Where-Object { $_.serverId -eq [string]$snapshot.lastRouteSuccess.serverId }
        ) | Select-Object -First 1
        if ($null -eq $selectedCandidate -or $selectedCandidate.protocol -ne $expectedProtocol) {
            throw "Quick tile selected an unknown or misordered route: $($snapshot.lastRouteSuccess.serverId)"
        }
        Assert-ExternalProbe -Probe $probe -ExpectedEgresses @([string]$selectedCandidate.egress)

        $stageReports.Add([ordered]@{
            index = $stageIndex + 1
            expectedProtocol = $expectedProtocol
            selectedProtocol = [string]$snapshot.lastRouteSuccess.protocol
            selectedServerId = [string]$snapshot.lastRouteSuccess.serverId
            cooledProtocols = @($cooledCandidates | ForEach-Object { $_.protocol } | Select-Object -Unique)
            cooledRouteCount = $cooledCandidates.Count
            activeProtocols = @($snapshot.activeProtocols)
            egress = [string]$probe.egress
            egressStatus = [int]$probe.egressStatus
            productionApiStatus = [int]$probe.productionApiStatus
            paidBetaPrimaryStatus = [int]$probe.paidBetaPrimaryStatus
            paidBetaFallbackStatus = [int]$probe.paidBetaFallbackStatus
            youtubeStatus = [int]$probe.youtubeStatus
            probeAttempts = [ordered]@{
                egress = [int]$probe.egressAttempts
                productionApi = [int]$probe.productionApiAttempts
                paidBetaPrimary = [int]$probe.paidBetaPrimaryAttempts
                paidBetaFallback = [int]$probe.paidBetaFallbackAttempts
                youtube = [int]$probe.youtubeAttempts
            }
        })
        Disconnect-ThroughTile
    }

    Clear-Cooldown
    Click-Tile
    $restored = Wait-Route -ExpectedProtocol 'wireguard_udp'
    $restoredProbe = Invoke-ExternalProbe
    $restoredCandidate = @(
        $transportCandidates |
            Where-Object { $_.serverId -eq [string]$restored.lastRouteSuccess.serverId }
    ) | Select-Object -First 1
    if ($null -eq $restoredCandidate -or $restoredCandidate.protocol -ne 'wireguard_udp') {
        throw "Cooldown clear did not restore the first route: $($restored.lastRouteSuccess.serverId)"
    }
    Assert-ExternalProbe -Probe $restoredProbe -ExpectedEgresses @([string]$restoredCandidate.egress)
    $report.restoredFirstRoute = [ordered]@{
        protocol = [string]$restored.lastRouteSuccess.protocol
        serverId = [string]$restored.lastRouteSuccess.serverId
        activeProtocols = @($restored.activeProtocols)
        egress = [string]$restoredProbe.egress
        youtubeStatus = [int]$restoredProbe.youtubeStatus
    }
    Disconnect-ThroughTile
    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
} finally {
    try { Invoke-DebugCommand -Command 'disconnect_all' | Out-Null } catch {}
    try { Clear-Cooldown } catch {}
    if (-not $tileWasPresent) {
        try { Set-TileList -Value $originalTiles } catch {}
    }
    try {
        Wait-Down | Out-Null
        $report.cleanupVerified = $true
    } catch {
        if (-not $report.error) { $report.error = $_.Exception.Message }
        $report.success = $false
    }
    $report.stages = @($stageReports)
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    $directory = Split-Path -Parent $ReportPath
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) { throw "Android quick tile cascade failed: $($report.error)" }
Write-Host "Android six-stage quick tile cascade passed: $ReportPath"
Write-Host 'Order: wireguard_udp -> amneziawg -> hysteria2 -> vless_reality -> naive_https -> dnstt'
Write-Host 'Cooldown clear restored: wireguard_udp'
