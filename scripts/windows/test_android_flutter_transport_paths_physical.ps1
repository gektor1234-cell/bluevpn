param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$Serial = 'R9WT10CDC2J',
    [string]$Package = 'pro.greenvpn.app.transportpreview',
    [string]$ProbePackage = 'pro.greenvpn.transportprobe',
    [string]$ExpectedCanaryEgress = '5.129.216.42',
    [string]$ExpectedWireGuardEgress = '37.220.85.211',
    [ValidateRange(1, 3)][int]$ProbeAttempts = 3,
    [ValidateRange(1, 6)][int]$StartStage = 1,
    [ValidateRange(1, 6)][int]$EndStage = 6,
    [switch]$InjectVlessEngineFailure,
    [switch]$InjectActiveEngineFailure,
    [switch]$InjectVlessTunFailure,
    [switch]$RequireAutomaticFailover,
    [switch]$RemoveAppTaskBeforeFailure,
    [ValidateRange(10, 120)][int]$FailureObservationSeconds = 45,
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\android_flutter_transport_paths_physical_20260714.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$debugService = "$Package/pro.greenvpn.app.TransportContractDebugService"
$resultFile = 'files/greenvpn-transport-contract-debug-result.json'
$uiDumpPath = '/sdcard/greenvpn-flutter-transport-test.xml'
$mainConnectX = 540
$mainConnectY = 504

$stages = @(
    [pscustomobject]@{ name = 'awg'; expectedProtocol = 'amneziawg'; selector = 'awg'; expectedEgress = $ExpectedCanaryEgress },
    [pscustomobject]@{ name = 'hysteria'; expectedProtocol = 'hysteria2'; selector = 'same-title:1'; expectedEgress = $ExpectedCanaryEgress },
    [pscustomobject]@{ name = 'vless'; expectedProtocol = 'vless_reality'; selector = 'same-title:4'; expectedEgress = $ExpectedCanaryEgress },
    [pscustomobject]@{ name = 'naive'; expectedProtocol = 'naive_https'; selector = 'same-title:2'; expectedEgress = $ExpectedCanaryEgress },
    [pscustomobject]@{ name = 'dnstt'; expectedProtocol = 'dnstt'; selector = 'same-title:3'; expectedEgress = $ExpectedCanaryEgress },
    [pscustomobject]@{ name = 'wireguard'; expectedProtocol = 'wireguard_udp'; selector = 'wireguard'; expectedEgress = $ExpectedWireGuardEgress }
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
    if ($exitCode -ne 0) { throw "adb failed: $($Arguments -join ' ') :: $($output -join ' ')" }
    return $output
}

function Invoke-DebugCommand {
    param(
        [string]$Command,
        [string[]]$Extras = @(),
        [int]$TimeoutSeconds = 45
    )
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', $resultFile) | Out-Null
    $arguments = @(
        'shell', 'am', 'startservice', '-n', $debugService, '--es', 'command', $Command
    ) + $Extras
    Invoke-Adb -Arguments $arguments | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $previous = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = (@(& $Adb -s $Serial shell run-as $Package cat $resultFile 2>$null) -join '').Trim()
            $readExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previous
        }
        if ($readExit -eq 0 -and $raw.StartsWith('{')) {
            $result = $raw | ConvertFrom-Json
            if (-not [bool]$result.success) { throw "debug command failed: $($result.error)" }
            return $result
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for debug command: $Command"
}

function Get-UiXml {
    Invoke-Adb -Arguments @('shell', 'uiautomator', 'dump', $uiDumpPath) | Out-Null
    $raw = ((Invoke-Adb -Arguments @('shell', 'cat', $uiDumpPath)) -join '').Trim()
    if (-not $raw.StartsWith('<?xml')) { throw 'Android UI dump is not XML.' }
    return [xml]$raw
}

function Get-Bounds {
    param([Parameter(Mandatory = $true)][string]$Value)
    $match = [regex]::Match($Value, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Unexpected Android bounds: $Value" }
    return [pscustomobject]@{
        left = [int]$match.Groups[1].Value
        top = [int]$match.Groups[2].Value
        right = [int]$match.Groups[3].Value
        bottom = [int]$match.Groups[4].Value
    }
}

function Tap-Node {
    param([Parameter(Mandatory = $true)]$Node)
    $bounds = Get-Bounds -Value $Node.GetAttribute('bounds')
    $x = [int](($bounds.left + $bounds.right) / 2)
    $y = [int](($bounds.top + $bounds.bottom) / 2)
    Invoke-Adb -Arguments @('shell', 'input', 'tap', [string]$x, [string]$y) | Out-Null
}

function Wait-MainScreen {
    param([int]$TimeoutSeconds = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $xml = Get-UiXml
        $button = @($xml.SelectNodes('//node[@clickable="true"]')) | Where-Object {
            $bounds = Get-Bounds -Value $_.GetAttribute('bounds')
            $bounds.left -le $mainConnectX -and $bounds.right -ge $mainConnectX -and
            $bounds.top -le $mainConnectY -and $bounds.bottom -ge $mainConnectY
        } | Select-Object -First 1
        if ($null -ne $button) { return $xml }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw 'Flutter main VPN screen did not become ready.'
}

function Open-ServerSheet {
    $mainXml = Wait-MainScreen
    $serverCard = @($mainXml.SelectNodes('//node[@clickable="true"]')) | Where-Object {
        $bounds = Get-Bounds -Value $_.GetAttribute('bounds')
        $bounds.left -eq 48 -and $bounds.right -eq 1032 -and
        $bounds.top -ge 1400 -and $bounds.bottom -le 1902
    } | Sort-Object {
        (Get-Bounds -Value $_.GetAttribute('bounds')).top
    } | Select-Object -Last 1
    if ($null -eq $serverCard) { throw 'Main server card is missing.' }
    Tap-Node -Node $serverCard
    Start-Sleep -Milliseconds 900
    $xml = Get-UiXml
    $hasServerRows = @($xml.SelectNodes('//node[@clickable="true"]')) | Where-Object {
        $_.GetAttribute('content-desc').StartsWith('NL2 Protected Preview')
    }
    if (@($hasServerRows).Count -eq 0) { throw 'Server selection sheet did not open.' }
}

function Reset-ServerSheetScroll {
    for ($i = 0; $i -lt 2; $i++) {
        Invoke-Adb -Arguments @('shell', 'input', 'swipe', '540', '800', '540', '1600', '350') | Out-Null
        Start-Sleep -Milliseconds 350
    }
}

function Select-ServerThroughUi {
    param([Parameter(Mandatory = $true)][string]$Selector)
    Open-ServerSheet
    Reset-ServerSheetScroll

    if ($Selector.StartsWith('same-title:')) {
        Invoke-Adb -Arguments @('shell', 'input', 'swipe', '540', '1600', '540', '800', '500') | Out-Null
        Start-Sleep -Milliseconds 800
    }

    $xml = Get-UiXml
    $buttons = @($xml.SelectNodes('//node[@clickable="true"]'))
    $node = $null
    switch -Regex ($Selector) {
        '^awg$' {
            $node = $buttons | Where-Object {
                $_.GetAttribute('content-desc').StartsWith('NL2 Protected Preview')
            } | Select-Object -First 1
        }
        '^wireguard$' {
            $node = $buttons | Where-Object {
                $_.GetAttribute('content-desc').StartsWith('Netherlands #1')
            } | Select-Object -First 1
        }
        '^auto$' {
            $node = $buttons | Where-Object {
                $bounds = Get-Bounds -Value $_.GetAttribute('bounds')
                $bounds.left -eq 192 -and $bounds.right -eq 888 -and
                $bounds.top -ge 350 -and $bounds.bottom -le 600
            } | Sort-Object {
                (Get-Bounds -Value $_.GetAttribute('bounds')).top
            } | Select-Object -First 1
        }
        '^same-title:(\d+)$' {
            $index = [int]$Matches[1]
            $sameTitleNodes = @($buttons | Where-Object {
                $_.GetAttribute('content-desc').StartsWith('Netherlands #2')
            } | Sort-Object {
                (Get-Bounds -Value $_.GetAttribute('bounds')).top
            })
            if ($sameTitleNodes.Count -ne 5) {
                throw "Expected five Netherlands #2 rows after one scroll, found $($sameTitleNodes.Count)."
            }
            if ($index -lt 0 -or $index -ge $sameTitleNodes.Count) {
                throw "Invalid same-title selector index: $index"
            }
            $node = $sameTitleNodes[$index]
        }
    }
    if ($null -eq $node) { throw "Could not resolve server selector: $Selector" }
    $description = $node.GetAttribute('content-desc').Replace("`n", ' | ')
    Tap-Node -Node $node
    Wait-MainScreen | Out-Null
    return $description
}

function Tap-MainVpnButton {
    $xml = Wait-MainScreen
    $button = @($xml.SelectNodes('//node[@clickable="true"]')) | Where-Object {
        $bounds = Get-Bounds -Value $_.GetAttribute('bounds')
        $bounds.left -le $mainConnectX -and $bounds.right -ge $mainConnectX -and
        $bounds.top -le $mainConnectY -and $bounds.bottom -ge $mainConnectY
    } | Select-Object -First 1
    if ($null -eq $button) { throw 'Main VPN button is missing.' }
    Tap-Node -Node $button
}

function Wait-ProtocolActive {
    param([string]$ExpectedProtocol, [int]$TimeoutSeconds = 110)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $snapshot = $null
    do {
        $snapshot = Invoke-DebugCommand -Command 'snapshot'
        $active = @($snapshot.activeProtocols)
        $matches = if ($ExpectedProtocol -eq 'wireguard_udp') {
            $active.Count -eq 1 -and $active[0] -eq 'amneziawg'
        } else {
            $active.Count -eq 1 -and $active[0] -eq $ExpectedProtocol
        }
        if ($matches) {
            Start-Sleep -Seconds 2
            return $snapshot
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    $activeText = if ($null -eq $snapshot) { '' } else { @($snapshot.activeProtocols) -join ',' }
    throw "Flutter connection did not activate expected protocol: expected=$ExpectedProtocol active=[$activeText]"
}

function Wait-AllDown {
    param([int]$TimeoutSeconds = 45)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $snapshot = $null
    do {
        $snapshot = Invoke-DebugCommand -Command 'snapshot'
        if (@($snapshot.activeProtocols).Count -eq 0) { return $snapshot }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    $activeText = if ($null -eq $snapshot) { '' } else { @($snapshot.activeProtocols) -join ',' }
    throw "Flutter disconnect did not stop all transports: active=[$activeText]"
}

function Invoke-ExternalProbe {
    param([int]$TimeoutSeconds = 45)
    $result = [ordered]@{}
    foreach ($target in @('egressAlternate', 'productionApi', 'paidBetaPrimary', 'paidBetaFallback', 'youtube')) {
        $probe = $null
        $attemptUsed = 0
        for ($attempt = 1; $attempt -le $ProbeAttempts; $attempt++) {
            $attemptUsed = $attempt
            Invoke-Adb -Arguments @(
                'shell', 'run-as', $ProbePackage, 'rm', '-f', 'files/transport-probe-result.json'
            ) | Out-Null
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
                } finally {
                    $ErrorActionPreference = $previous
                }
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
    param([Parameter(Mandatory = $true)]$Probe, [string]$ExpectedEgress)
    if ($Probe.egressStatus -ne 200 -or $Probe.egress -ne $ExpectedEgress) {
        throw "Unexpected route egress: expected=$ExpectedEgress actual=$($Probe.egress) status=$($Probe.egressStatus)"
    }
    foreach ($property in @('productionApiStatus', 'paidBetaPrimaryStatus', 'paidBetaFallbackStatus')) {
        if ([int]$Probe.$property -ne 200) { throw "Route API probe failed: $property=$($Probe.$property)" }
    }
    if ([int]$Probe.youtubeStatus -notin @(200, 204)) {
        throw "Route YouTube probe failed: status=$($Probe.youtubeStatus) error=$($Probe.youtubeError)"
    }
}

function Remove-AppTaskKeepingService {
    $lines = @(Invoke-Adb -Arguments @('shell', 'am', 'stack', 'list'))
    $currentStackId = $null
    $appStackIds = [System.Collections.Generic.List[int]]::new()
    foreach ($line in $lines) {
        $stackMatch = [regex]::Match([string]$line, '^Stack id=(\d+)')
        if ($stackMatch.Success) {
            $currentStackId = [int]$stackMatch.Groups[1].Value
            continue
        }
        if ($null -ne $currentStackId -and [string]$line -like "*$Package/*") {
            if (-not $appStackIds.Contains($currentStackId)) {
                $appStackIds.Add($currentStackId)
            }
        }
    }
    if ($appStackIds.Count -eq 0) { throw 'Preview application task stack was not found.' }
    foreach ($appStackId in $appStackIds) {
        Invoke-Adb -Arguments @('shell', 'am', 'stack', 'remove', [string]$appStackId) | Out-Null
    }
    Start-Sleep -Seconds 1
    $remainingStacks = ((Invoke-Adb -Arguments @('shell', 'am', 'stack', 'list')) -join "`n")
    if ($remainingStacks.Contains("$Package/")) {
        throw 'Preview application task remained after stack removal.'
    }
    $services = ((Invoke-Adb -Arguments @('shell', 'dumpsys', 'activity', 'services', $Package)) -join "`n")
    if (-not $services.Contains('GreenVpnRuntimeFailoverService')) {
        throw 'Runtime failover service stopped when the application task was removed.'
    }
    return $appStackIds[0]
}

function Stop-ActiveTransportEngine {
    param([Parameter(Mandatory = $true)][string]$Protocol)
    Invoke-DebugCommand -Command 'fail_active_engine' -Extras @(
        '--es', 'protocol', $Protocol
    ) | Out-Null
}

if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) { throw "adb is missing: $Adb" }
if (((Invoke-Adb -Arguments @('get-state')) -join '').Trim() -ne 'device') { throw "Android device is not ready: $Serial" }
if (-not ((Invoke-Adb -Arguments @('shell', 'pm', 'path', $ProbePackage)) -join '').Contains('package:')) {
    throw "Android transport probe is not installed: $ProbePackage"
}
if ($StartStage -gt $EndStage) { throw 'StartStage must be less than or equal to EndStage.' }
if (@(@(
        $InjectVlessEngineFailure,
        $InjectActiveEngineFailure,
        $InjectVlessTunFailure
    ) | Where-Object { [bool]$_ }).Count -gt 1) {
    throw 'Choose only one transport failure injection mode.'
}
$selectedStages = @($stages[($StartStage - 1)..($EndStage - 1)])

$displaySize = ((Invoke-Adb -Arguments @('shell', 'wm', 'size')) -join ' ')
if (-not $displaySize.Contains('1080x2220')) { throw "This physical UI test expects 1080x2220, found: $displaySize" }

$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    finishedAt = ''
    serial = $Serial
    package = $Package
    selectionMethod = 'physical_flutter_ui'
    displaySize = $displaySize.Trim()
    startStage = $StartStage
    endStage = $EndStage
    injectVlessEngineFailure = [bool]$InjectVlessEngineFailure
    injectActiveEngineFailure = [bool]$InjectActiveEngineFailure
    injectVlessTunFailure = [bool]$InjectVlessTunFailure
    requireAutomaticFailover = [bool]$RequireAutomaticFailover
    removeAppTaskBeforeFailure = [bool]$RemoveAppTaskBeforeFailure
    appTaskRemoved = $false
    failureInjection = $null
    stages = @()
    restoredAuto = $false
    cleanupVerified = $false
    success = $false
    error = ''
}
$stageReports = [System.Collections.Generic.List[object]]::new()

try {
    Invoke-Adb -Arguments @('shell', 'svc', 'power', 'stayon', 'usb') | Out-Null
    Invoke-Adb -Arguments @('shell', 'input', 'keyevent', '4') | Out-Null
    Invoke-Adb -Arguments @(
        'shell', 'am', 'start', '-W', '-n', "$Package/pro.greenvpn.app.MainActivity"
    ) | Out-Null
    Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
    Invoke-DebugCommand -Command 'clear_tile_cooldown' | Out-Null
    Wait-AllDown | Out-Null
    Wait-MainScreen | Out-Null

    foreach ($stage in $selectedStages) {
        Write-Output "START $($stage.name)"
        $selected = Select-ServerThroughUi -Selector $stage.selector
        Tap-MainVpnButton
        $snapshot = Wait-ProtocolActive -ExpectedProtocol $stage.expectedProtocol
        Wait-MainScreen -TimeoutSeconds 120 | Out-Null
        $snapshot = Wait-ProtocolActive -ExpectedProtocol $stage.expectedProtocol -TimeoutSeconds 15
        $probe = Invoke-ExternalProbe
        Assert-ExternalProbe -Probe $probe -ExpectedEgress $stage.expectedEgress
        $failureInjection = $null
        if ($InjectVlessEngineFailure -or $InjectActiveEngineFailure -or $InjectVlessTunFailure) {
            if ($selectedStages.Count -ne 1) {
                throw 'Runtime failure injection requires a single transport stage.'
            }
            if (($InjectVlessEngineFailure -or $InjectVlessTunFailure) -and
                $stage.expectedProtocol -ne 'vless_reality') {
                throw 'VLESS-specific failure injection requires the VLESS stage.'
            }
            $injectedProtocol = [string]$stage.expectedProtocol
            $armedSnapshot = Invoke-DebugCommand -Command 'snapshot'
            if (-not [bool]$armedSnapshot.runtimeFailover.desired -or
                [string]$armedSnapshot.runtimeFailover.state -ne 'monitoring') {
                throw 'Runtime failover service was not armed before failure injection.'
            }
            $baselineRecoveryCount = [int]$armedSnapshot.runtimeFailover.recoveryCount
            $baselineServerId = [string]$armedSnapshot.runtimeFailover.serverId
            $removedStackId = $null
            if ($RemoveAppTaskBeforeFailure) {
                $removedStackId = Remove-AppTaskKeepingService
                $report.appTaskRemoved = $true
            }
            if ($InjectVlessTunFailure) {
                Invoke-Adb -Arguments @(
                    'shell', 'am', 'broadcast', '--receiver-foreground', '--include-stopped-packages',
                    '-a', 'pro.greenvpn.vless.DEBUG_CONTROL',
                    '-n', "$Package/pro.greenvpn.vless.VlessRealityDebugReceiver",
                    '--es', 'command', 'stop_tun'
                ) | Out-Null
            } else {
                Stop-ActiveTransportEngine -Protocol $injectedProtocol
            }
            $tunFailurePrecondition = $true
            if ($InjectVlessTunFailure) {
                Start-Sleep -Milliseconds 500
                $tunFailureSnapshot = Invoke-DebugCommand -Command 'snapshot'
                $tunFailurePrecondition = @($tunFailureSnapshot.activeProtocols) -contains 'vless_reality'
                if (-not $tunFailurePrecondition) {
                    throw 'TUN-only failure did not preserve the active VLESS engine.'
                }
            }
            $failureStarted = Get-Date
            $deadline = $failureStarted.AddSeconds($FailureObservationSeconds)
            $observedProtocols = [System.Collections.Generic.List[string]]::new()
            $observedRuntimeStates = [System.Collections.Generic.List[string]]::new()
            $maxRouteFailures = 0
            $lastFailureSnapshot = $null
            do {
                $lastFailureSnapshot = Invoke-DebugCommand -Command 'snapshot'
                foreach ($protocol in @($lastFailureSnapshot.activeProtocols)) {
                    if (-not $observedProtocols.Contains([string]$protocol)) {
                        $observedProtocols.Add([string]$protocol)
                    }
                }
                $runtimeState = [string]$lastFailureSnapshot.runtimeFailover.state
                if (-not $observedRuntimeStates.Contains($runtimeState)) {
                    $observedRuntimeStates.Add($runtimeState)
                }
                $maxRouteFailures = [Math]::Max(
                    $maxRouteFailures,
                    [int]$lastFailureSnapshot.runtimeFailover.routeFailures
                )
                $replacementActive = @($lastFailureSnapshot.activeProtocols).Count -eq 1
                $routeChanged =
                    [string]$lastFailureSnapshot.runtimeFailover.serverId -ne $baselineServerId -or
                    [string]$lastFailureSnapshot.runtimeFailover.protocol -ne $injectedProtocol
                $runtimeSettled =
                    [bool]$lastFailureSnapshot.runtimeFailover.desired -and
                    [string]$lastFailureSnapshot.runtimeFailover.state -eq 'monitoring' -and
                    $routeChanged -and
                    [int]$lastFailureSnapshot.runtimeFailover.recoveryCount -gt $baselineRecoveryCount
                if ($replacementActive -and $runtimeSettled) {
                    break
                }
                Start-Sleep -Seconds 1
            } while ((Get-Date) -lt $deadline)
            $replacementActive = @($lastFailureSnapshot.activeProtocols).Count -eq 1
            $routeChanged =
                [string]$lastFailureSnapshot.runtimeFailover.serverId -ne $baselineServerId -or
                [string]$lastFailureSnapshot.runtimeFailover.protocol -ne $injectedProtocol
            $runtimeSettled =
                [bool]$lastFailureSnapshot.runtimeFailover.desired -and
                [string]$lastFailureSnapshot.runtimeFailover.state -eq 'monitoring' -and
                $routeChanged -and
                [int]$lastFailureSnapshot.runtimeFailover.recoveryCount -gt $baselineRecoveryCount
            $replacementProtocol = if ($runtimeSettled) {
                [string]$lastFailureSnapshot.runtimeFailover.protocol
            } else {
                ''
            }
            $failureMechanismConfirmed = -not $InjectVlessTunFailure -or
                ($tunFailurePrecondition -and $maxRouteFailures -ge 2)
            $replacementProbe = $null
            if ($replacementActive -and $runtimeSettled) {
                $replacementProbe = Invoke-ExternalProbe
                $replacementEgress = if ($replacementProtocol -eq 'wireguard_udp') {
                    $ExpectedWireGuardEgress
                } else {
                    $ExpectedCanaryEgress
                }
                Assert-ExternalProbe -Probe $replacementProbe -ExpectedEgress $replacementEgress
            }
            $failureInjection = [ordered]@{
                injectedProtocol = $injectedProtocol
                injectedFailure = if ($InjectVlessTunFailure) { 'tun_only' } else { 'engine_process' }
                observationSeconds = $FailureObservationSeconds
                elapsedMs = [int]((Get-Date) - $failureStarted).TotalMilliseconds
                observedProtocols = @($observedProtocols)
                observedRuntimeStates = @($observedRuntimeStates)
                maxRouteFailures = $maxRouteFailures
                finalActiveProtocols = @($lastFailureSnapshot.activeProtocols)
                automaticFailoverObserved =
                    $replacementActive -and $runtimeSettled -and $failureMechanismConfirmed
                replacementProtocol = $replacementProtocol
                baselineRecoveryCount = $baselineRecoveryCount
                runtimeFailover = $lastFailureSnapshot.runtimeFailover
                removedAppTaskStackId = if ($null -ne $removedStackId) { [int]$removedStackId } else { -1 }
                replacementEgress = if ($null -ne $replacementProbe) { $replacementProbe.egress } else { '' }
                replacementEgressStatus = if ($null -ne $replacementProbe) { $replacementProbe.egressStatus } else { 0 }
                replacementProductionApiStatus = if ($null -ne $replacementProbe) { $replacementProbe.productionApiStatus } else { 0 }
                replacementPaidBetaPrimaryStatus = if ($null -ne $replacementProbe) { $replacementProbe.paidBetaPrimaryStatus } else { 0 }
                replacementPaidBetaFallbackStatus = if ($null -ne $replacementProbe) { $replacementProbe.paidBetaFallbackStatus } else { 0 }
                replacementYoutubeStatus = if ($null -ne $replacementProbe) { $replacementProbe.youtubeStatus } else { 0 }
            }
            $report.failureInjection = $failureInjection
            if ($RequireAutomaticFailover -and -not $failureInjection.automaticFailoverObserved) {
                throw "Automatic runtime failover was not observed for $injectedProtocol."
            }
            Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
            $down = Wait-AllDown
            if ($RemoveAppTaskBeforeFailure) {
                Invoke-Adb -Arguments @(
                    'shell', 'am', 'start', '-W', '-n', "$Package/pro.greenvpn.app.MainActivity"
                ) | Out-Null
            }
            Wait-MainScreen | Out-Null
        } else {
            Tap-MainVpnButton
            $down = Wait-AllDown
            Wait-MainScreen | Out-Null
        }

        $stageReports.Add([pscustomobject][ordered]@{
            name = $stage.name
            expectedProtocol = $stage.expectedProtocol
            selectedUiRow = $selected
            activeProtocols = @($snapshot.activeProtocols)
            egress = $probe.egress
            egressStatus = $probe.egressStatus
            productionApiStatus = $probe.productionApiStatus
            paidBetaPrimaryStatus = $probe.paidBetaPrimaryStatus
            paidBetaFallbackStatus = $probe.paidBetaFallbackStatus
            youtubeStatus = $probe.youtubeStatus
            egressAttempts = $probe.egressAttempts
            productionApiAttempts = $probe.productionApiAttempts
            paidBetaPrimaryAttempts = $probe.paidBetaPrimaryAttempts
            paidBetaFallbackAttempts = $probe.paidBetaFallbackAttempts
            youtubeAttempts = $probe.youtubeAttempts
            disconnectedActiveProtocols = @($down.activeProtocols)
            failureInjection = $failureInjection
            success = $true
        })
        Write-Output "PASS $($stage.name) egress=$($probe.egress)"
    }

    Select-ServerThroughUi -Selector 'auto' | Out-Null
    $report.restoredAuto = $true
    Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
    $clean = Wait-AllDown
    $report.cleanupVerified = @($clean.activeProtocols).Count -eq 0
    $report.success = $report.cleanupVerified -and $stageReports.Count -eq $selectedStages.Count
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    $report.stages = @($stageReports)
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    try {
        Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
        Wait-AllDown | Out-Null
        $report.cleanupVerified = $true
    } catch {
        if (-not $report.error) { $report.error = "cleanup_failed: $($_.Exception.Message)" }
        $report.success = $false
    }
    $directory = Split-Path -Parent $ReportPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) { throw "Flutter physical transport test failed: $($report.error)" }
$report | ConvertTo-Json -Depth 8
