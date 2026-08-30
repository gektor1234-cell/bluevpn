[CmdletBinding()]
param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [Parameter(Mandatory = $true)][string]$Serial,
    [Parameter(Mandatory = $true)][string]$ExpectedApkPath,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedApkSha256,
    [Parameter(Mandatory = $true)][long]$ExpectedApkSize,
    [Parameter(Mandatory = $true)][string]$ExpectedVersionName,
    [Parameter(Mandatory = $true)][string]$ExpectedVersionCode,
    [string]$Package = 'pro.greenvpn.app',
    [string]$ProbePackage = 'pro.greenvpn.transportprobe',
    [Parameter(Mandatory = $true)][string]$ArtifactRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$connectPattern = '\u041F\u043E\u0434\u043A\u043B\u044E\u0447\u0438\u0442\u044C VPN'
$disconnectPattern = '\u041E\u0442\u043A\u043B\u044E\u0447\u0438\u0442\u044C VPN'
$waitingNetworkPattern = '\u041E\u0436\u0438\u0434\u0430\u0435\u043C \u0434\u043E\u0441\u0442\u0443\u043F\u043D\u0443\u044E \u0441\u0435\u0442\u044C'
$preservedNetworkPattern = 'VPN \u0441\u043E\u0445\u0440\u0430\u043D\u0451\u043D, \u043E\u0436\u0438\u0434\u0430\u0435\u043C \u0441\u0435\u0442\u044C'
$resolvedApk = [IO.Path]::GetFullPath($ExpectedApkPath)
$resolvedRoot = [IO.Path]::GetFullPath($ArtifactRoot).TrimEnd('\')
$reportPath = Join-Path $resolvedRoot 'android-network-lifecycle-physical.json'
$installedApkPath = Join-Path $resolvedRoot 'installed-base.apk'

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $Adb -s $Serial @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($exitCode -ne 0) {
        throw "adb failed: $($Arguments -join ' ') :: $($output -join ' ')"
    }
    return $output
}

function Get-UiXml {
    $remotePath = '/sdcard/greenvpn-network-lifecycle-ui.xml'
    Invoke-Adb -Arguments @('shell', 'uiautomator', 'dump', $remotePath) |
        Out-Null
    $raw = ((Invoke-Adb -Arguments @('shell', 'cat', $remotePath)) -join '').Trim()
    if (-not $raw.StartsWith('<?xml')) {
        throw 'Android UI dump is not XML.'
    }
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
    Invoke-Adb -Arguments @('shell', 'input', 'tap', [string]$x, [string]$y) |
        Out-Null
}

function Get-MainVpnButton {
    param([Parameter(Mandatory = $true)][xml]$Xml)

    return @($Xml.SelectNodes('//node[@clickable="true"]')) | Where-Object {
        $_.GetAttribute('content-desc') -match "(?:$connectPattern|$disconnectPattern)"
    } | Where-Object {
        $bounds = Get-Bounds -Value $_.GetAttribute('bounds')
        ($bounds.bottom - $bounds.top) -gt 100
    } | Select-Object -First 1
}

function Wait-MainVpnButton {
    param(
        [Parameter(Mandatory = $true)][bool]$Connected,
        [int]$TimeoutSeconds = 90
    )

    $expected = if ($Connected) { $disconnectPattern } else { $connectPattern }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $xml = Get-UiXml
        $button = Get-MainVpnButton -Xml $xml
        if ($null -ne $button -and $button.GetAttribute('content-desc') -match $expected) {
            return $button
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "VPN button did not reach connected=$Connected."
}

function Open-GreenVpn {
    Invoke-Adb -Arguments @('shell', 'am', 'start', '-n', "$Package/.MainActivity") |
        Out-Null
}

function Test-VpnConnected {
    $connectivity = (Invoke-Adb -Arguments @('shell', 'dumpsys', 'connectivity')) -join "`n"
    return (
        $connectivity -match 'type: VPN\[\], state: CONNECTED/CONNECTED' -or
        $connectivity -match 'VPN CONNECTED extra: VPN:'
    )
}

function Wait-VpnState {
    param(
        [Parameter(Mandatory = $true)][bool]$Connected,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if ((Test-VpnConnected) -eq $Connected) { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Android VPN state did not reach connected=$Connected."
}

function Handle-SystemVpnConsent {
    param([int]$TimeoutSeconds = 20)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $xml = Get-UiXml
        $node = @($xml.SelectNodes('//node[@clickable="true"]')) | Where-Object {
            $_.GetAttribute('text') -match '^(?:OK|\u041E\u041A)$'
        } | Select-Object -First 1
        if ($null -ne $node) {
            Tap-Node -Node $node
            return $true
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Invoke-ExternalProbe {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [int]$TimeoutMs = 8000
    )

    $resultFile = 'files/transport-probe-result.json'
    Invoke-Adb -Arguments @('shell', 'run-as', $ProbePackage, 'rm', '-f', $resultFile) |
        Out-Null
    Invoke-Adb -Arguments @(
        'shell', 'am', 'broadcast', '--include-stopped-packages',
        '-a', 'pro.greenvpn.transportprobe.RUN',
        '-n', "$ProbePackage/pro.greenvpn.transportprobe.TransportProbeReceiver",
        '--es', 'target', $Target,
        '--ei', 'timeoutMs', [string]$TimeoutMs
    ) | Out-Null

    $deadline = (Get-Date).AddSeconds([math]::Ceiling(($TimeoutMs * 2) / 1000) + 12)
    do {
        $oldPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = (@(
                & $Adb -s $Serial shell run-as $ProbePackage cat $resultFile 2>$null
            ) -join '').Trim()
            $readExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldPreference
        }
        if ($readExitCode -eq 0 -and $raw.StartsWith('{')) {
            return $raw | ConvertFrom-Json
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for Android probe: $Target"
}

function Wait-ProtectedDataPlane {
    param(
        [Parameter(Mandatory = $true)][string]$DirectEgress,
        [int]$TimeoutSeconds = 180,
        [switch]$RequireContinuousVpn
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = 'probe_not_started'
    do {
        if ($RequireContinuousVpn -and -not (Test-VpnConnected)) {
            throw 'VPN tunnel disappeared while waiting for data-plane recovery.'
        }
        try {
            $egress = Invoke-ExternalProbe -Target 'egressAlternate'
            $egressValue = ([string]$egress.body).Trim()
            if ([int]$egress.status -eq 200 -and
                    $egressValue -match '^\d{1,3}(?:\.\d{1,3}){3}$' -and
                    $egressValue -ne $DirectEgress) {
                $api = Invoke-ExternalProbe -Target 'productionApi'
                $youtube = Invoke-ExternalProbe -Target 'youtube'
                if ([int]$api.status -eq 200 -and [int]$youtube.status -in @(200, 204)) {
                    if ($RequireContinuousVpn -and -not (Test-VpnConnected)) {
                        throw 'VPN tunnel disappeared after successful recovery probes.'
                    }
                    return [pscustomobject]@{
                        egress = $egressValue
                        apiStatus = [int]$api.status
                        youtubeStatus = [int]$youtube.status
                    }
                }
                $lastError = "api=$($api.status) youtube=$($youtube.status)"
            } else {
                $lastError = "egress_status=$($egress.status) egress=$egressValue error=$($egress.error)"
            }
        } catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "Protected Android data plane did not recover: $lastError"
}

function Wait-NotificationPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $notifications = (Invoke-Adb -Arguments @(
            'shell', 'dumpsys', 'notification', '--noredact'
        )) -join "`n"
        if ($notifications -match $Pattern) { return $true }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Capture-Screenshot {
    param([Parameter(Mandatory = $true)][string]$Name)

    $remote = "/sdcard/$Name.png"
    $local = Join-Path $resolvedRoot "$Name.png"
    Invoke-Adb -Arguments @('shell', 'screencap', '-p', $remote) | Out-Null
    Invoke-Adb -Arguments @('pull', $remote, $local) | Out-Null
    Invoke-Adb -Arguments @('shell', 'rm', $remote) | Out-Null
    return $local
}

function Save-ConnectivitySnapshot {
    param([Parameter(Mandatory = $true)][string]$Name)

    $path = Join-Path $resolvedRoot "$Name-connectivity.txt"
    (Invoke-Adb -Arguments @('shell', 'dumpsys', 'connectivity')) |
        Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Get-TelephonySummary {
    return @(
        Invoke-Adb -Arguments @('shell', 'dumpsys', 'telephony.registry') |
            Where-Object { $_ -match 'mCallState=|mServiceState=|mDataConnectionState=' }
    )
}

function Read-GlobalSetting {
    param([Parameter(Mandatory = $true)][string]$Name)
    return ((Invoke-Adb -Arguments @('shell', 'settings', 'get', 'global', $Name)) -join '').Trim()
}

function Set-NetworksOffline {
    Invoke-Adb -Arguments @('shell', 'svc', 'wifi', 'disable') | Out-Null
    Invoke-Adb -Arguments @('shell', 'svc', 'data', 'disable') | Out-Null
}

function Restore-Networks {
    param(
        [Parameter(Mandatory = $true)][string]$Wifi,
        [Parameter(Mandatory = $true)][string]$MobileData
    )

    Invoke-Adb -Arguments @(
        'shell', 'svc', 'wifi', $(if ($Wifi -eq '1') { 'enable' } else { 'disable' })
    ) | Out-Null
    Invoke-Adb -Arguments @(
        'shell', 'svc', 'data', $(if ($MobileData -eq '1') { 'enable' } else { 'disable' })
    ) | Out-Null
}

function Disconnect-GreenVpn {
    Open-GreenVpn
    $button = Wait-MainVpnButton -Connected $true -TimeoutSeconds 90
    Tap-Node -Node $button
    Wait-VpnState -Connected $false -TimeoutSeconds 90
    Wait-MainVpnButton -Connected $false -TimeoutSeconds 60 | Out-Null
}

function Start-GreenVpn {
    param(
        [Parameter(Mandatory = $true)][string]$DirectEgress,
        [switch]$BackgroundImmediately
    )

    Open-GreenVpn
    $button = Wait-MainVpnButton -Connected $false -TimeoutSeconds 60
    $started = Get-Date
    Tap-Node -Node $button
    if ($BackgroundImmediately) {
        Start-Sleep -Milliseconds 150
        Invoke-Adb -Arguments @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null
    } else {
        Handle-SystemVpnConsent -TimeoutSeconds 5 | Out-Null
    }
    Wait-VpnState -Connected $true -TimeoutSeconds 180
    $probe = Wait-ProtectedDataPlane -DirectEgress $DirectEgress -TimeoutSeconds 180
    Open-GreenVpn
    Wait-MainVpnButton -Connected $true -TimeoutSeconds 90 | Out-Null
    return [pscustomobject]@{
        connectElapsedMs = [int]((Get-Date) - $started).TotalMilliseconds
        egress = $probe.egress
        apiStatus = $probe.apiStatus
        youtubeStatus = $probe.youtubeStatus
    }
}

function Test-ProbeVpnService {
    $services = (Invoke-Adb -Arguments @(
        'shell', 'dumpsys', 'activity', 'services', $ProbePackage
    )) -join "`n"
    return $services -match 'CompetingVpnService'
}

function Start-CompetingVpn {
    Invoke-Adb -Arguments @(
        'shell', 'am', 'start', '-n', "$ProbePackage/.CompetingVpnActivity"
    ) | Out-Null
    $deadline = (Get-Date).AddSeconds(30)
    do {
        if (Test-ProbeVpnService) { return }
        Handle-SystemVpnConsent -TimeoutSeconds 2 | Out-Null
        if (Test-ProbeVpnService) { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw 'Competing VPN probe service did not start.'
}

function Stop-CompetingVpn {
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Adb -s $Serial shell am start -n "$ProbePackage/.CompetingVpnActivity" `
            --es action stop 2>&1 | Out-Null
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    Start-Sleep -Seconds 2
    Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $ProbePackage) | Out-Null
}

function Wait-RuntimeLogPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $logs = (Invoke-Adb -Arguments @('logcat', '-d', '-v', 'brief')) -join "`n"
        if ($logs -match $Pattern) { return $true }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return $false
}

foreach ($requiredPath in @($Adb, $resolvedApk)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required file is missing: $requiredPath"
    }
}
if (Test-Path -LiteralPath $resolvedRoot) {
    throw "Artifact root already exists: $resolvedRoot"
}
New-Item -ItemType Directory -Path $resolvedRoot | Out-Null

$apk = Get-Item -LiteralPath $resolvedApk
$actualHash = (Get-FileHash -LiteralPath $resolvedApk -Algorithm SHA256).Hash
if ($actualHash -ne $ExpectedApkSha256.ToUpperInvariant() -or
        [long]$apk.Length -ne $ExpectedApkSize) {
    throw 'Exact APK SHA-256 or size mismatch.'
}
if (((Invoke-Adb -Arguments @('get-state')) -join '').Trim() -ne 'device') {
    throw "Android device is not ready: $Serial"
}
if (-not ((Invoke-Adb -Arguments @('shell', 'pm', 'path', $ProbePackage)) -join '').Contains('package:')) {
    throw "Required Android probe package is not installed: $ProbePackage"
}
if (Test-VpnConnected) {
    throw 'A VPN is already active on the Android device.'
}

$packageDump = (Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $Package)) -join "`n"
$installedName = [regex]::Match($packageDump, 'versionName=([^\s]+)').Groups[1].Value
$installedCode = [regex]::Match($packageDump, 'versionCode=(\d+)').Groups[1].Value
if ($installedName -ne $ExpectedVersionName -or $installedCode -ne $ExpectedVersionCode) {
    throw "Unexpected installed version: $installedName/$installedCode"
}
$packagePathLine = Invoke-Adb -Arguments @('shell', 'pm', 'path', $Package) |
    Where-Object { $_ -like 'package:*base.apk' } | Select-Object -First 1
$packagePath = $packagePathLine.Substring(8).Trim()
Invoke-Adb -Arguments @('pull', $packagePath, $installedApkPath) | Out-Null
$installedHash = (Get-FileHash -LiteralPath $installedApkPath -Algorithm SHA256).Hash
if ($installedHash -ne $actualHash) {
    throw 'Installed Android base.apk differs from the exact candidate.'
}

$initialWifi = Read-GlobalSetting -Name 'wifi_on'
$initialMobileData = Read-GlobalSetting -Name 'mobile_data'
$screenshots = [Collections.Generic.List[string]]::new()
$snapshots = [Collections.Generic.List[string]]::new()
$report = [ordered]@{
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    serial = $Serial
    apk = [ordered]@{
        path = $resolvedApk
        sha256 = $actualHash
        size = [long]$apk.Length
        installedSha256 = $installedHash
        versionName = $installedName
        versionCode = $installedCode
    }
    initialNetwork = [ordered]@{ wifi = $initialWifi; mobileData = $initialMobileData }
    initialTelephony = @(Get-TelephonySummary)
    directEgress = ''
    backgroundConnect = $null
    offlineConnect = $null
    networkLoss = $null
    competingVpn = $null
    finalNetwork = $null
    finalTelephony = @()
    finalVpnDisconnected = $false
    screenshots = @()
    connectivitySnapshots = @()
    success = $false
    error = ''
}

try {
    Invoke-Adb -Arguments @('logcat', '-c') | Out-Null
    $direct = Invoke-ExternalProbe -Target 'egressAlternate'
    if ([int]$direct.status -ne 200) { throw 'Direct egress preflight failed.' }
    $report.directEgress = ([string]$direct.body).Trim()

    $background = Start-GreenVpn -DirectEgress $report.directEgress -BackgroundImmediately
    $screenshots.Add((Capture-Screenshot -Name 'android-lifecycle-01-background-connected'))
    $report.backgroundConnect = [ordered]@{
        completedWhileActivityBackgrounded = $true
        connectElapsedMs = $background.connectElapsedMs
        egress = $background.egress
        apiStatus = $background.apiStatus
        youtubeStatus = $background.youtubeStatus
    }
    Disconnect-GreenVpn

    Open-GreenVpn
    $offlineButton = Wait-MainVpnButton -Connected $false -TimeoutSeconds 60
    Set-NetworksOffline
    Start-Sleep -Seconds 4
    $offlineProbe = Invoke-ExternalProbe -Target 'productionApi' -TimeoutMs 3000
    if ([int]$offlineProbe.status -ne 0) {
        throw 'Network-off precondition still had a working data path.'
    }
    $offlineStarted = Get-Date
    Tap-Node -Node $offlineButton
    Start-Sleep -Milliseconds 150
    Invoke-Adb -Arguments @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null
    $waitingNotification = Wait-NotificationPattern -Pattern $waitingNetworkPattern -TimeoutSeconds 20
    Start-Sleep -Seconds 5
    $vpnBeforeRestore = Test-VpnConnected
    if (-not $waitingNotification -or $vpnBeforeRestore) {
        throw 'Offline connect did not remain in the durable waiting state.'
    }
    Restore-Networks -Wifi $initialWifi -MobileData $initialMobileData
    Wait-VpnState -Connected $true -TimeoutSeconds 180
    $offlineProtected = Wait-ProtectedDataPlane -DirectEgress $report.directEgress -TimeoutSeconds 180
    Open-GreenVpn
    Wait-MainVpnButton -Connected $true -TimeoutSeconds 90 | Out-Null
    $screenshots.Add((Capture-Screenshot -Name 'android-lifecycle-02-offline-restored'))
    $report.offlineConnect = [ordered]@{
        offlineProbeStatus = [int]$offlineProbe.status
        waitingNotification = $waitingNotification
        vpnBeforeNetworkRestore = $vpnBeforeRestore
        restoredWithoutSecondTap = $true
        restoreElapsedMs = [int]((Get-Date) - $offlineStarted).TotalMilliseconds
        egress = $offlineProtected.egress
        apiStatus = $offlineProtected.apiStatus
        youtubeStatus = $offlineProtected.youtubeStatus
    }
    Disconnect-GreenVpn

    $connectedBeforeLoss = Start-GreenVpn -DirectEgress $report.directEgress
    Invoke-Adb -Arguments @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null
    $lossStarted = Get-Date
    Set-NetworksOffline
    $vpnCheckpoints = [Collections.Generic.List[object]]::new()
    foreach ($seconds in @(5, 10, 15)) {
        $remaining = $seconds - [int]((Get-Date) - $lossStarted).TotalSeconds
        if ($remaining -gt 0) { Start-Sleep -Seconds $remaining }
        $stillConnected = Test-VpnConnected
        $vpnCheckpoints.Add([ordered]@{ seconds = $seconds; vpnConnected = $stillConnected })
        if (-not $stillConnected) {
            throw "VPN tunnel was torn down after underlying network loss at ${seconds}s."
        }
    }
    $preservedNotification = Wait-NotificationPattern -Pattern $preservedNetworkPattern -TimeoutSeconds 20
    if (-not $preservedNotification) {
        throw 'VPN did not expose the preserved-tunnel network-loss state.'
    }
    $snapshots.Add((Save-ConnectivitySnapshot -Name 'android-lifecycle-network-lost'))
    Restore-Networks -Wifi $initialWifi -MobileData $initialMobileData
    $restoredProtected = Wait-ProtectedDataPlane `
        -DirectEgress $report.directEgress `
        -TimeoutSeconds 180 `
        -RequireContinuousVpn
    Open-GreenVpn
    Wait-MainVpnButton -Connected $true -TimeoutSeconds 90 | Out-Null
    $screenshots.Add((Capture-Screenshot -Name 'android-lifecycle-03-network-restored'))
    $report.networkLoss = [ordered]@{
        initialEgress = $connectedBeforeLoss.egress
        checkpoints = @($vpnCheckpoints)
        preservedNotification = $preservedNotification
        restoredWithoutSecondTap = $true
        egress = $restoredProtected.egress
        apiStatus = $restoredProtected.apiStatus
        youtubeStatus = $restoredProtected.youtubeStatus
    }
    Disconnect-GreenVpn

    $competingBaseline = Start-GreenVpn -DirectEgress $report.directEgress
    Invoke-Adb -Arguments @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null
    Start-CompetingVpn
    Wait-VpnState -Connected $true -TimeoutSeconds 30
    $probeServiceActive = Test-ProbeVpnService
    $runtimeDisarmed = Wait-RuntimeLogPattern `
        -Pattern 'runtime_failover_disarmed reason=competing_vpn_active' `
        -TimeoutSeconds 30
    if (-not $probeServiceActive -or -not $runtimeDisarmed) {
        throw 'Green VPN did not terminally disarm after competing VPN takeover.'
    }
    Open-GreenVpn
    Start-Sleep -Seconds 2
    $screenshots.Add((Capture-Screenshot -Name 'android-lifecycle-04-competing-vpn'))
    Stop-CompetingVpn
    Wait-VpnState -Connected $false -TimeoutSeconds 45
    Start-Sleep -Seconds 20
    $autoRestored = Test-VpnConnected
    if ($autoRestored) {
        throw 'Green VPN restored itself after the competing VPN stopped.'
    }
    Open-GreenVpn
    Wait-MainVpnButton -Connected $false -TimeoutSeconds 60 | Out-Null
    $screenshots.Add((Capture-Screenshot -Name 'android-lifecycle-05-competing-stopped'))
    $report.competingVpn = [ordered]@{
        initialEgress = $competingBaseline.egress
        probeServiceActive = $probeServiceActive
        runtimeTerminallyDisarmed = $runtimeDisarmed
        greenAutoRestoredAfterProbeStopped = $autoRestored
    }

    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
} finally {
    try { Stop-CompetingVpn } catch {}
    try {
        Restore-Networks -Wifi $initialWifi -MobileData $initialMobileData
        Start-Sleep -Seconds 3
    } catch {}
    try {
        if (Test-VpnConnected) {
            Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $Package) | Out-Null
            Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $ProbePackage) | Out-Null
            Wait-VpnState -Connected $false -TimeoutSeconds 60
        }
    } catch {
        $report.success = $false
        if (-not $report.error) { $report.error = "cleanup_failed: $($_.Exception.Message)" }
    }
    try {
        $runtimeLogPath = Join-Path $resolvedRoot 'android-network-lifecycle-logcat.txt'
        (Invoke-Adb -Arguments @('logcat', '-d', '-v', 'threadtime')) |
            Set-Content -LiteralPath $runtimeLogPath -Encoding UTF8
    } catch {}
    $report.finalVpnDisconnected = -not (Test-VpnConnected)
    if (-not $report.finalVpnDisconnected) {
        $report.success = $false
        if (-not $report.error) { $report.error = 'cleanup_failed: VPN remained connected.' }
    }
    $report.finalNetwork = [ordered]@{
        wifi = Read-GlobalSetting -Name 'wifi_on'
        mobileData = Read-GlobalSetting -Name 'mobile_data'
    }
    if ($report.finalNetwork.wifi -ne $initialWifi -or
            $report.finalNetwork.mobileData -ne $initialMobileData) {
        $report.success = $false
        if (-not $report.error) { $report.error = 'cleanup_failed: network settings differ.' }
    }
    $report.finalTelephony = @(Get-TelephonySummary)
    $report.screenshots = @($screenshots)
    $report.connectivitySnapshots = @($snapshots)
    $report.completedAtUtc = [DateTime]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $reportPath -Encoding UTF8
}

if (-not $report.success) {
    throw "Android network lifecycle physical test failed: $($report.error)"
}

Write-Host "Android network lifecycle physical test passed: $reportPath"
