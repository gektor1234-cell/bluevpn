param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$Serial = "",
    [Parameter(Mandatory = $true)][string]$ApkPath,
    [string]$Package = 'pro.greenvpn.app',
    [string]$ProbePackage = 'pro.greenvpn.transportprobe',
    [string]$ExpectedVersionName = '0.3.20',
    [string]$ExpectedVersionCode = '2026080301',
    [ValidateRange(30, 180)][int]$ConnectTimeoutSeconds = 90,
    [string]$ReportPath = 'C:\BlueVPN_Builds\android-store-release-physical.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$connectDescriptionPattern =
    '\u041F\u043E\u0434\u043A\u043B\u044E\u0447\u0438\u0442\u044C VPN'
$disconnectDescriptionPattern =
    '\u041E\u0442\u043A\u043B\u044E\u0447\u0438\u0442\u044C VPN'
$subscriptionPattern = '\u043F\u043E\u0434\u043F\u0438\u0441\u043A'
$paymentPattern = '\u043E\u043F\u043B\u0430\u0442\u0438\u0442\u044C'
$emailLoginPattern =
    '\u0432\u043E\u0439\u0442\u0438\s+\u043F\u043E\s+email'
$freeAccessPattern =
    '\u0411\u0435\u0441\u043F\u043B\u0430\u0442\u043D\u044B\u0439\s+' +
    '\u0434\u043E\u0441\u0442\u0443\u043F'
$freeProfilePattern =
    '\u0411\u0435\u0441\u043F\u043B\u0430\u0442\u043D\u044B\u0439\s+' +
    '\u043F\u0440\u043E\u0444\u0438\u043B\u044C'
$versionForAndroidPattern =
    '\u0412\u0435\u0440\u0441\u0438\u044F\s+' +
    [regex]::Escape($ExpectedVersionName) +
    '\s+\u0434\u043B\u044F\s+Android'
$updatesPattern =
    '\u043E\u0431\u043D\u043E\u0432\u043B\u0435\u043D\u0438\u044F'
$restoreSubscriptionPattern =
    '\u0432\u043E\u0441\u0441\u0442\u0430\u043D\u043E\u0432\u0438\u0442\u044C' +
    '\s+' + $subscriptionPattern

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

function Get-UiXml {
    $remotePath = '/sdcard/greenvpn-store-release-ui.xml'
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
        $_.GetAttribute('content-desc') -match
            "(?:$connectDescriptionPattern|$disconnectDescriptionPattern)"
    } | Where-Object {
        $bounds = Get-Bounds -Value $_.GetAttribute('bounds')
        ($bounds.bottom - $bounds.top) -gt 100
    } | Select-Object -First 1
}

function Wait-MainVpnButton {
    param(
        [Parameter(Mandatory = $true)][bool]$Connected,
        [int]$TimeoutSeconds = 30
    )
    $expectedPattern = if ($Connected) {
        $disconnectDescriptionPattern
    } else {
        $connectDescriptionPattern
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $xml = Get-UiXml
        $button = Get-MainVpnButton -Xml $xml
        if ($null -ne $button -and
            $button.GetAttribute('content-desc') -match $expectedPattern) {
            return $button
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "VPN button did not reach connected=$Connected."
}

function Test-VpnConnected {
    $connectivity = (Invoke-Adb -Arguments @(
        'shell', 'dumpsys', 'connectivity'
    )) -join "`n"
    return (
        $connectivity -match 'type: VPN\[\], state: CONNECTED/CONNECTED' -or
        $connectivity -match "VPN CONNECTED extra: VPN:$([regex]::Escape($Package))"
    )
}

function Wait-VpnState {
    param(
        [Parameter(Mandatory = $true)][bool]$Connected,
        [int]$TimeoutSeconds = 45
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if ((Test-VpnConnected) -eq $Connected) {
            return
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Android VPN state did not reach connected=$Connected."
}

function Handle-SystemVpnConsent {
    $deadline = (Get-Date).AddSeconds(12)
    do {
        $xml = Get-UiXml
        $node = @($xml.SelectNodes('//node[@clickable="true"]')) |
            Where-Object {
                $_.GetAttribute('text') -match '^(?:OK|\u041E\u041A)$'
            } |
            Select-Object -First 1
        if ($null -ne $node) {
            Tap-Node -Node $node
            return $true
        }
        if ($null -ne (Get-MainVpnButton -Xml $xml)) {
            return $false
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Invoke-ExternalProbe {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [int]$TimeoutMs = 30000
    )
    $resultFile = 'files/transport-probe-result.json'
    Invoke-Adb -Arguments @(
        'shell', 'run-as', $ProbePackage, 'rm', '-f', $resultFile
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
                & $Adb -s $Serial shell run-as $ProbePackage cat $resultFile 2>$null
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
    throw "Timed out waiting for Android probe: $Target"
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
$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
if (-not $Serial) {
    $deviceLines = @(
        @(& $Adb devices) | Where-Object {
            $_ -match '^([^\s]+)\s+device$' -and $_ -notmatch '^emulator-'
        }
    )
    if ($deviceLines.Count -ne 1) {
        throw "Expected exactly one physical Android device, found $($deviceLines.Count)."
    }
    $Serial = ($deviceLines[0] -split '\s+')[0]
}
if (((Invoke-Adb -Arguments @('get-state')) -join '').Trim() -ne 'device') {
    throw "Android device is not ready: $Serial"
}
if (-not ((Invoke-Adb -Arguments @(
    'shell', 'pm', 'path', $ProbePackage
)) -join '').Contains('package:')) {
    throw "Required Android probe package is not installed: $ProbePackage"
}

$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    serial = $Serial
    package = $Package
    apk = $resolvedApk
    apkSha256 = (Get-FileHash -LiteralPath $resolvedApk -Algorithm SHA256).Hash
    versionName = ''
    versionCode = ''
    connectElapsedMs = $null
    foregroundProbe = $null
    backgroundProbe = $null
    backgroundStatePreserved = $false
    resumeStateReconciled = $false
    freeUiVerified = $false
    settingsVerified = $false
    crashBufferClean = $false
    screenshots = @()
    finalVpnDisconnected = $false
    success = $false
    error = ''
}
$screenshots = [System.Collections.Generic.List[string]]::new()

try {
    $installOutput = @(& $Adb -s $Serial install -r $resolvedApk 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "APK install failed: $($installOutput -join ' ')"
    }
    Invoke-Adb -Arguments @('logcat', '-b', 'crash', '-c') | Out-Null
    Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Wait-VpnState -Connected $false -TimeoutSeconds 20
    Invoke-Adb -Arguments @(
        'shell', 'am', 'start', '-n', "$Package/.MainActivity"
    ) | Out-Null

    $packageDump = (Invoke-Adb -Arguments @(
        'shell', 'dumpsys', 'package', $Package
    )) -join "`n"
    $versionNameMatch = [regex]::Match($packageDump, 'versionName=([^\s]+)')
    $versionCodeMatch = [regex]::Match($packageDump, 'versionCode=(\d+)')
    $report.versionName = $versionNameMatch.Groups[1].Value
    $report.versionCode = $versionCodeMatch.Groups[1].Value
    if ($report.versionName -ne $ExpectedVersionName -or
        $report.versionCode -ne $ExpectedVersionCode) {
        throw "Unexpected installed version: $($report.versionName)/$($report.versionCode)"
    }

    $button = Wait-MainVpnButton -Connected $false -TimeoutSeconds 30
    $homeUi = Get-UiXml
    $homeRaw = $homeUi.OuterXml
    $homeForbidden =
        "(?i)(beta|preview|trial|$subscriptionPattern|$paymentPattern|$emailLoginPattern)"
    if ($homeRaw -match $homeForbidden) {
        throw 'Store home exposes a beta, paid, or account marker.'
    }
    $screenshots.Add((Capture-Screenshot -Name 'rustore-01-home-disconnected'))

    $connectStarted = Get-Date
    Tap-Node -Node $button
    Handle-SystemVpnConsent | Out-Null
    Wait-VpnState -Connected $true -TimeoutSeconds $ConnectTimeoutSeconds
    Wait-MainVpnButton -Connected $true -TimeoutSeconds 30 | Out-Null
    $report.connectElapsedMs = [int]((Get-Date) - $connectStarted).TotalMilliseconds

    $egressProbe = Invoke-ExternalProbe -Target 'egressAlternate'
    $apiProbe = Invoke-ExternalProbe -Target 'productionApi'
    $youtubeProbe = Invoke-ExternalProbe -Target 'youtube'
    if ([int]$egressProbe.status -ne 200 -or
        ([string]$egressProbe.body).Trim() -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$') {
        throw 'Android VPN egress probe failed.'
    }
    if ([int]$apiProbe.status -ne 200) {
        throw 'Android production API probe failed.'
    }
    if ([int]$youtubeProbe.status -notin @(200, 204)) {
        throw 'Android YouTube probe failed.'
    }
    $report.foregroundProbe = [ordered]@{
        egress = ([string]$egressProbe.body).Trim()
        apiStatus = [int]$apiProbe.status
        youtubeStatus = [int]$youtubeProbe.status
    }
    $screenshots.Add((Capture-Screenshot -Name 'rustore-02-home-connected'))

    Invoke-Adb -Arguments @('shell', 'input', 'keyevent', 'KEYCODE_HOME') |
        Out-Null
    Start-Sleep -Seconds 10
    Wait-VpnState -Connected $true -TimeoutSeconds 10
    $backgroundYoutube = Invoke-ExternalProbe -Target 'youtube'
    if ([int]$backgroundYoutube.status -notin @(200, 204)) {
        throw 'Android background YouTube probe failed.'
    }
    $report.backgroundProbe = [ordered]@{
        youtubeStatus = [int]$backgroundYoutube.status
    }
    $report.backgroundStatePreserved = $true

    Invoke-Adb -Arguments @(
        'shell', 'am', 'start', '-n', "$Package/.MainActivity"
    ) | Out-Null
    $disconnectButton = Wait-MainVpnButton -Connected $true -TimeoutSeconds 30
    $report.resumeStateReconciled = $true
    Tap-Node -Node $disconnectButton
    Wait-VpnState -Connected $false -TimeoutSeconds 45
    Wait-MainVpnButton -Connected $false -TimeoutSeconds 30 | Out-Null

    $access = Open-Tab -Index 2
    $accessRaw = $access.OuterXml
    $advertisingOfferPattern =
        '\u0440\u0435\u043A\u043B\u0430\u043C\u0430\s+\u043E\u0442'
    $accessForbidden =
        "(?i)(249|649|1099|$subscriptionPattern|$paymentPattern|$advertisingOfferPattern)"
    if ($accessRaw -notmatch $freeAccessPattern -or
        $accessRaw -match $accessForbidden) {
        throw 'Store access screen is not a permanent-free screen.'
    }
    $report.freeUiVerified = $true
    $screenshots.Add((Capture-Screenshot -Name 'rustore-03-free-access'))

    $settings = Open-Tab -Index 3
    $settingsRaw = $settings.OuterXml
    $settingsForbidden =
        "(?i)($updatesPattern|$emailLoginPattern|$restoreSubscriptionPattern)"
    if ($settingsRaw -notmatch $freeProfilePattern -or
        $settingsRaw -notmatch $versionForAndroidPattern -or
        $settingsRaw -match $settingsForbidden) {
        throw 'Store settings screen exposes a direct-download or account action.'
    }
    $report.settingsVerified = $true
    $screenshots.Add((Capture-Screenshot -Name 'rustore-04-settings'))

    $crashText = (Invoke-Adb -Arguments @(
        'logcat', '-b', 'crash', '-d', '-v', 'brief'
    )) -join "`n"
    $report.crashBufferClean = -not $crashText.Contains($Package)
    if (-not $report.crashBufferClean) {
        throw 'Android crash buffer contains an entry for Green VPN.'
    }
    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
} finally {
    try {
        if (Test-VpnConnected) {
            Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $Package) |
                Out-Null
            Wait-VpnState -Connected $false -TimeoutSeconds 30
        }
        $report.finalVpnDisconnected = -not (Test-VpnConnected)
        if (-not $report.finalVpnDisconnected) {
            $report.success = $false
            if (-not $report.error) {
                $report.error = 'cleanup_failed: Green VPN remained connected.'
            }
        }
    } catch {
        $report.finalVpnDisconnected = $false
        $report.success = $false
        if (-not $report.error) {
            $report.error = "cleanup_failed: $($_.Exception.Message)"
        }
    }
    $report.screenshots = @($screenshots)
    $report.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $directory = Split-Path -Parent $ReportPath
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $report | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) {
    throw "Android store release physical test failed: $($report.error)"
}

Write-Host "Android store release physical test passed: $ReportPath"
Write-Host "Connect time: $($report.connectElapsedMs) ms"
Write-Host "Egress: $($report.foregroundProbe.egress)"
