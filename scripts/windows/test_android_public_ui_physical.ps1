param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [Parameter(Mandatory = $true)][string]$Serial,
    [string]$Package = 'pro.greenvpn.app.candidate',
    [string]$ProbePackage = 'pro.greenvpn.transportprobe',
    [ValidateRange(30, 180)][int]$RouteTimeoutSeconds = 120,
    [string]$ReportPath = 'C:\BlueVPN_Builds\android_public_ui_physical.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$debugResultFile = 'files/greenvpn-transport-contract-debug-result.json'
$probeResultFile = 'files/transport-probe-result.json'
$debugService = "$Package/pro.greenvpn.app.TransportContractDebugService"
$uiDumpPath = '/sdcard/greenvpn-public-ui.xml'
$connectDescriptionPattern =
    '^\u041F\u043E\u0434\u043A\u043B\u044E\u0447\u0438\u0442\u044C VPN(?:\s|$)'
$disconnectDescriptionPattern =
    '^\u041E\u0442\u043A\u043B\u044E\u0447\u0438\u0442\u044C VPN(?:\s|$)'
$expectedLocations = @(
    [pscustomobject]@{
        index = 0
        name = 'auto'
        serverIds = @('current_wg0', 'ruvds-2584554-ld8', 'tw-7879598-nl1')
        egresses = @('37.220.85.211', '88.218.250.86', '5.129.216.42')
    },
    [pscustomobject]@{
        index = 1
        name = 'netherlands'
        serverIds = @('current_wg0', 'tw-7879598-nl1')
        egresses = @('37.220.85.211', '5.129.216.42')
    },
    [pscustomobject]@{
        index = 2
        name = 'london'
        serverIds = @('ruvds-2584554-ld8')
        egresses = @('88.218.250.86')
    }
)

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
    if ($exitCode -ne 0) {
        throw "adb failed: $($Arguments -join ' ') :: $($output -join ' ')"
    }
    return $output
}

function Invoke-DebugCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Extras = @(),
        [int]$TimeoutSeconds = 45
    )
    Invoke-Adb -Arguments @(
        'shell', 'run-as', $Package, 'rm', '-f', $debugResultFile
    ) | Out-Null
    $arguments = @(
        'shell', 'am', 'startservice', '-n', $debugService,
        '--es', 'command', $Command
    ) + $Extras
    Invoke-Adb -Arguments $arguments | Out-Null

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = (@(
                & $Adb -s $Serial shell run-as $Package cat $debugResultFile 2>$null
            ) -join '').Trim()
            $readExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($readExitCode -eq 0 -and $raw.StartsWith('{')) {
            $result = $raw | ConvertFrom-Json
            if (-not [bool]$result.success) {
                throw "debug command failed: $Command :: $($result.error)"
            }
            return $result
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for debug command: $Command"
}

function Invoke-ExternalProbe {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [int]$TimeoutMs = 30000
    )
    Invoke-Adb -Arguments @(
        'shell', 'run-as', $ProbePackage, 'rm', '-f', $probeResultFile
    ) | Out-Null
    Invoke-Adb -Arguments @(
        'shell', 'am', 'broadcast', '--include-stopped-packages',
        '-a', 'pro.greenvpn.transportprobe.RUN',
        '-n', "$ProbePackage/pro.greenvpn.transportprobe.TransportProbeReceiver",
        '--es', 'target', $Target,
        '--ei', 'timeoutMs', [string]$TimeoutMs
    ) | Out-Null

    $deadline = (Get-Date).AddSeconds([math]::Ceiling($TimeoutMs / 1000) + 20)
    do {
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = (@(
                & $Adb -s $Serial shell run-as $ProbePackage cat $probeResultFile 2>$null
            ) -join '').Trim()
            $readExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($readExitCode -eq 0 -and $raw.StartsWith('{')) {
            return $raw | ConvertFrom-Json
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for external probe: $Target"
}

function Get-Bounds {
    param([Parameter(Mandatory = $true)][string]$Value)
    $match = [regex]::Match($Value, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) {
        throw "Unexpected Android bounds: $Value"
    }
    return [pscustomobject]@{
        left = [int]$match.Groups[1].Value
        top = [int]$match.Groups[2].Value
        right = [int]$match.Groups[3].Value
        bottom = [int]$match.Groups[4].Value
    }
}

function Get-UiXml {
    Invoke-Adb -Arguments @('shell', 'uiautomator', 'dump', $uiDumpPath) |
        Out-Null
    $raw = ((Invoke-Adb -Arguments @('shell', 'cat', $uiDumpPath)) -join '').Trim()
    if (-not $raw.StartsWith('<?xml')) {
        throw 'Android UI dump is not XML.'
    }
    return [xml]$raw
}

function Tap-Node {
    param([Parameter(Mandatory = $true)]$Node)
    $bounds = Get-Bounds -Value $Node.GetAttribute('bounds')
    $x = [int](($bounds.left + $bounds.right) / 2)
    $y = [int](($bounds.top + $bounds.bottom) / 2)
    Invoke-Adb -Arguments @(
        'shell', 'input', 'tap', [string]$x, [string]$y
    ) | Out-Null
}

function Get-MainVpnButton {
    param([Parameter(Mandatory = $true)][xml]$Xml)
    return @($Xml.SelectNodes('//node[@clickable="true"]')) | Where-Object {
        $_.GetAttribute('content-desc') -match 'VPN(?:\s|$)'
    } | Where-Object {
        $bounds = Get-Bounds -Value $_.GetAttribute('bounds')
        $bounds.left -gt 0 -and $bounds.right -lt 1080 -and
        ($bounds.bottom - $bounds.top) -gt 100
    } | Select-Object -First 1
}

function Wait-MainScreen {
    param([int]$TimeoutSeconds = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $xml = Get-UiXml
        if ($null -ne (Get-MainVpnButton -Xml $xml)) {
            return $xml
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw 'Public VPN screen did not become ready.'
}

function Wait-MainVpnButtonState {
    param(
        [Parameter(Mandatory = $true)][bool]$Connected,
        [int]$TimeoutSeconds = 30
    )
    $pattern = if ($Connected) {
        $disconnectDescriptionPattern
    } else {
        $connectDescriptionPattern
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $xml = Get-UiXml
        $button = @($xml.SelectNodes('//node[@clickable="true"]')) |
            Where-Object {
                $_.GetAttribute('content-desc') -match $pattern
            } |
            Select-Object -First 1
        if ($null -ne $button) {
            return $button
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Public VPN button did not reach connected=$Connected."
}

function Get-ServerCard {
    param([Parameter(Mandatory = $true)][xml]$Xml)
    return @($Xml.SelectNodes('//node[@clickable="true"]')) | Where-Object {
        $bounds = Get-Bounds -Value $_.GetAttribute('bounds')
        $bounds.left -eq 48 -and $bounds.right -eq 1032 -and
        $bounds.top -ge 1400 -and $bounds.bottom -le 1902
    } | Sort-Object {
        (Get-Bounds -Value $_.GetAttribute('bounds')).top
    } | Select-Object -Last 1
}

function Select-PublicLocation {
    param([ValidateRange(0, 2)][int]$Index)
    Wait-MainVpnButtonState -Connected $false | Out-Null
    $rows = @()
    $deadline = (Get-Date).AddSeconds(15)
    do {
        $main = Wait-MainScreen
        $serverCard = Get-ServerCard -Xml $main
        if ($null -eq $serverCard) {
            throw 'Public server card is missing.'
        }
        Tap-Node -Node $serverCard
        Start-Sleep -Milliseconds 900
        $sheet = Get-UiXml
        $rows = @(
            @($sheet.SelectNodes('//node[@clickable="true"]')) |
                Where-Object {
                    $bounds = Get-Bounds -Value $_.GetAttribute('bounds')
                    $bounds.left -eq 192 -and $bounds.right -eq 888 -and
                    ($bounds.bottom - $bounds.top) -ge 180
                } |
                Sort-Object {
                    (Get-Bounds -Value $_.GetAttribute('bounds')).top
                }
        )
        if ($rows.Count -ge 2) {
            break
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    if ($rows.Count -ne 3) {
        throw "Expected exactly three public location rows, found $($rows.Count)."
    }
    $selectedDescription = $rows[$Index].GetAttribute('content-desc')
    Tap-Node -Node $rows[$Index]
    Wait-MainScreen | Out-Null
    return $selectedDescription
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

function Wait-WireGuardRoute {
    param(
        [Parameter(Mandatory = $true)][string[]]$ExpectedServerIds,
        [int]$TimeoutSeconds = 120
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $snapshot = Invoke-DebugCommand -Command 'snapshot'
        if (
            [string]$snapshot.runtimeFailover.protocol -eq 'wireguard_udp' -and
            [string]$snapshot.runtimeFailover.serverId -in $ExpectedServerIds -and
            [bool]$snapshot.runtimeFailover.desired -and
            [string]$snapshot.runtimeFailover.state -eq 'monitoring' -and
            @($snapshot.activeProtocols).Count -eq 0 -and
            (Get-VpnRecordCount) -eq 1
        ) {
            return $snapshot
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    throw "Public UI did not activate an expected WireGuard route."
}

function Wait-CleanDown {
    $deadline = (Get-Date).AddSeconds(45)
    do {
        $snapshot = Invoke-DebugCommand -Command 'snapshot'
        if (
            @($snapshot.activeProtocols).Count -eq 0 -and
            (Get-VpnRecordCount) -eq 0 -and
            (Get-TransportEngineProcessCount) -eq 0
        ) {
            return
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw 'Android did not return to a clean VPN-down state.'
}

function Open-Tab {
    param([ValidateRange(1, 3)][int]$Index)
    $xml = Get-UiXml
    $suffix = "Tab $Index of 3"
    $node = @($xml.SelectNodes('//node[@clickable="true"]')) | Where-Object {
        $_.GetAttribute('content-desc').EndsWith($suffix)
    } | Select-Object -First 1
    if ($null -eq $node) {
        throw "Bottom navigation tab is missing: $Index"
    }
    Tap-Node -Node $node
    Start-Sleep -Milliseconds 800
    return Get-UiXml
}

function Capture-Screenshot {
    param([Parameter(Mandatory = $true)][string]$Name)
    $directory = Split-Path -Parent $ReportPath
    if (-not $directory) {
        $directory = (Get-Location).Path
    }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $remote = "/sdcard/$Name.png"
    $local = Join-Path $directory "$Name.png"
    Invoke-Adb -Arguments @('shell', 'screencap', '-p', $remote) | Out-Null
    Invoke-Adb -Arguments @('pull', $remote, $local) | Out-Null
    Invoke-Adb -Arguments @('shell', 'rm', $remote) | Out-Null
    return $local
}

if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) {
    throw "adb is missing: $Adb"
}
if (((Invoke-Adb -Arguments @('get-state')) -join '').Trim() -ne 'device') {
    throw "Android device is not ready: $Serial"
}
foreach ($packageName in @($Package, $ProbePackage)) {
    if (-not ((Invoke-Adb -Arguments @(
        'shell', 'pm', 'path', $packageName
    )) -join '').Contains('package:')) {
        throw "Required Android package is not installed: $packageName"
    }
}

$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    package = $Package
    locations = @()
    tariffPricesPresent = $false
    settingsOpened = $false
    releaseMarkersAbsent = $false
    screenshots = @()
    crashBufferClean = $false
    finalCleanDown = $false
    success = $false
    error = ''
}
$locationReports = [System.Collections.Generic.List[object]]::new()
$screenshots = [System.Collections.Generic.List[string]]::new()

try {
    Invoke-Adb -Arguments @('logcat', '-b', 'crash', '-c') | Out-Null
    Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb -Arguments @(
        'shell', 'am', 'start', '-n', "$Package/pro.greenvpn.app.MainActivity"
    ) | Out-Null
    Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
    Invoke-DebugCommand -Command 'clear_tile_cooldown' | Out-Null
    Wait-CleanDown
    $main = Wait-MainScreen
    $mainRaw = $main.OuterXml
    if ($mainRaw -match '(?i)(beta|preview|trial|\u0431\u0435\u0442\u0430)') {
        throw 'Public main screen exposes a beta, preview, or trial marker.'
    }
    $screenshots.Add((Capture-Screenshot -Name 'android-public-main'))

    foreach ($location in $expectedLocations) {
        Invoke-DebugCommand -Command 'clear_tile_cooldown' | Out-Null
        $description = Select-PublicLocation -Index $location.index
        $main = Wait-MainScreen
        $button = Get-MainVpnButton -Xml $main
        if ($null -eq $button) {
            throw 'Public connect button is missing.'
        }
        Tap-Node -Node $button
        $snapshot = Wait-WireGuardRoute `
            -ExpectedServerIds $location.serverIds `
            -TimeoutSeconds $RouteTimeoutSeconds

        $egressProbe = Invoke-ExternalProbe -Target 'egressAlternate'
        $apiProbe = Invoke-ExternalProbe -Target 'productionApi'
        $youtubeProbe = Invoke-ExternalProbe -Target 'youtube'
        $egress = ([string]$egressProbe.body).Trim()
        if ([int]$egressProbe.status -ne 200 -or $egress -notin $location.egresses) {
            throw "Unexpected egress for $($location.name): $egress"
        }
        if ([int]$apiProbe.status -ne 200) {
            throw "Production API failed for $($location.name)."
        }
        if ([int]$youtubeProbe.status -notin @(200, 204)) {
            throw "YouTube failed for $($location.name)."
        }

        $screenshots.Add((Capture-Screenshot -Name "android-public-$($location.name)-connected"))
        $button = Wait-MainVpnButtonState -Connected $true -TimeoutSeconds 30
        Tap-Node -Node $button
        Wait-CleanDown
        Wait-MainVpnButtonState -Connected $false -TimeoutSeconds 30 | Out-Null

        $locationReports.Add([pscustomobject][ordered]@{
            name = $location.name
            selectedDescription = $description
            serverId = [string]$snapshot.runtimeFailover.serverId
            protocol = [string]$snapshot.runtimeFailover.protocol
            egress = $egress
            productionApiStatus = [int]$apiProbe.status
            youtubeStatus = [int]$youtubeProbe.status
            disconnected = $true
        })
    }

    $tariff = Open-Tab -Index 2
    $tariffRaw = $tariff.OuterXml
    $report.tariffPricesPresent = @('249', '649', '1099') |
        ForEach-Object { $tariffRaw.Contains($_) } |
        Where-Object { -not $_ } |
        Measure-Object |
        Select-Object -ExpandProperty Count
    $report.tariffPricesPresent = $report.tariffPricesPresent -eq 0
    if (-not $report.tariffPricesPresent) {
        throw 'The public tariff screen does not expose all three expected prices.'
    }
    if ($tariffRaw -match '(?i)(beta|preview|trial|\u0431\u0435\u0442\u0430)') {
        throw 'Public tariff screen exposes a beta, preview, or trial marker.'
    }
    $screenshots.Add((Capture-Screenshot -Name 'android-public-tariff'))

    $settings = Open-Tab -Index 3
    $report.settingsOpened = $settings.OuterXml.Contains('Tab 3 of 3')
    if (-not $report.settingsOpened) {
        throw 'Public settings screen did not open.'
    }
    if ($settings.OuterXml -match '(?i)(beta|preview|trial|\u0431\u0435\u0442\u0430)') {
        throw 'Public settings screen exposes a beta, preview, or trial marker.'
    }
    $screenshots.Add((Capture-Screenshot -Name 'android-public-settings'))

    Open-Tab -Index 1 | Out-Null
    Wait-MainScreen | Out-Null
    $report.releaseMarkersAbsent = $true

    $crashText = (
        Invoke-Adb -Arguments @('logcat', '-b', 'crash', '-d', '-v', 'brief')
    ) -join "`n"
    $report.crashBufferClean = -not $crashText.Contains($Package)
    if (-not $report.crashBufferClean) {
        throw 'Android crash buffer contains an entry for the candidate package.'
    }

    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
} finally {
    try { Invoke-DebugCommand -Command 'clear_tile_cooldown' | Out-Null } catch {}
    try { Invoke-DebugCommand -Command 'disconnect_all' | Out-Null } catch {}
    try {
        Wait-CleanDown
        $report.finalCleanDown = $true
    } catch {
        if (-not $report.error) {
            $report.error = "cleanup_failed: $($_.Exception.Message)"
        }
        $report.success = $false
    }
    $report.locations = @($locationReports)
    $report.screenshots = @($screenshots)
    $report.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $directory = Split-Path -Parent $ReportPath
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $report | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) {
    throw "Android public UI physical test failed: $($report.error)"
}

Write-Host "Android public UI physical test passed: $ReportPath"
Write-Host "Locations: $($report.locations.Count)"
Write-Host 'Tariffs: 249 / 649 / 1099'
