[CmdletBinding()]
param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$Serial = '',
    [Parameter(Mandatory = $true)][string]$ApkPath,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedApkSha256,
    [Parameter(Mandatory = $true)][long]$ExpectedApkSize,
    [Parameter(Mandatory = $true)][string]$ExpectedVersionName,
    [Parameter(Mandatory = $true)][string]$ExpectedVersionCode,
    [string]$Package = 'pro.greenvpn.app',
    [string]$ProbePackage = 'pro.greenvpn.transportprobe',
    [ValidateRange(30, 180)][int]$ConnectTimeoutSeconds = 120,
    [Parameter(Mandatory = $true)][string]$ArtifactRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$connectPattern = '\u041F\u043E\u0434\u043A\u043B\u044E\u0447\u0438\u0442\u044C VPN'
$disconnectPattern = '\u041E\u0442\u043A\u043B\u044E\u0447\u0438\u0442\u044C VPN'
$resolvedApk = [IO.Path]::GetFullPath($ApkPath)
$resolvedRoot = [IO.Path]::GetFullPath($ArtifactRoot).TrimEnd('\')
$reportPath = Join-Path $resolvedRoot 'android-direct-release-physical.json'
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
    $remotePath = '/sdcard/greenvpn-direct-release-ui.xml'
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
            "(?:$connectPattern|$disconnectPattern)"
    } | Where-Object {
        $bounds = Get-Bounds -Value $_.GetAttribute('bounds')
        ($bounds.bottom - $bounds.top) -gt 100
    } | Select-Object -First 1
}

function Wait-MainVpnButton {
    param(
        [Parameter(Mandatory = $true)][bool]$Connected,
        [int]$TimeoutSeconds = 45
    )

    $expected = if ($Connected) { $disconnectPattern } else { $connectPattern }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $xml = Get-UiXml
        $button = Get-MainVpnButton -Xml $xml
        if ($null -ne $button -and
                $button.GetAttribute('content-desc') -match $expected) {
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
        $connectivity -match 'VPN CONNECTED extra: VPN:'
    )
}

function Wait-VpnState {
    param(
        [Parameter(Mandatory = $true)][bool]$Connected,
        [int]$TimeoutSeconds = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if ((Test-VpnConnected) -eq $Connected) { return }
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
            } | Select-Object -First 1
        if ($null -ne $node) {
            Tap-Node -Node $node
            return
        }
        if ($null -ne (Get-MainVpnButton -Xml $xml)) { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
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

function Capture-Screenshot {
    param([Parameter(Mandatory = $true)][string]$Name)

    $remote = "/sdcard/$Name.png"
    $local = Join-Path $resolvedRoot "$Name.png"
    Invoke-Adb -Arguments @('shell', 'screencap', '-p', $remote) | Out-Null
    Invoke-Adb -Arguments @('pull', $remote, $local) | Out-Null
    Invoke-Adb -Arguments @('shell', 'rm', $remote) | Out-Null
    return $local
}

function Read-PackageVersion {
    $dump = (Invoke-Adb -Arguments @(
        'shell', 'dumpsys', 'package', $Package
    )) -join "`n"
    $name = [regex]::Match($dump, 'versionName=([^\s]+)').Groups[1].Value
    $code = [regex]::Match($dump, 'versionCode=(\d+)').Groups[1].Value
    return [pscustomobject]@{ name = $name; code = $code }
}

foreach ($requiredPath in @($Adb, $resolvedApk)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required file is missing: $requiredPath"
    }
}
$apk = Get-Item -LiteralPath $resolvedApk
$actualHash = (Get-FileHash -LiteralPath $resolvedApk -Algorithm SHA256).Hash
if ($actualHash -ne $ExpectedApkSha256.ToUpperInvariant() -or
        [long]$apk.Length -ne $ExpectedApkSize) {
    throw 'Exact APK SHA-256 or size mismatch.'
}
if (-not $Serial) {
    $devices = @(
        @(& $Adb devices) | Where-Object {
            $_ -match '^([^\s]+)\s+device$' -and $_ -notmatch '^emulator-'
        }
    )
    if ($devices.Count -ne 1) {
        throw "Expected exactly one physical Android device, found $($devices.Count)."
    }
    $Serial = ($devices[0] -split '\s+')[0]
}
if (((Invoke-Adb -Arguments @('get-state')) -join '').Trim() -ne 'device') {
    throw "Android device is not ready: $Serial"
}
if (-not ((Invoke-Adb -Arguments @(
    'shell', 'pm', 'path', $ProbePackage
)) -join '').Contains('package:')) {
    throw "Required Android probe package is not installed: $ProbePackage"
}
if (Test-VpnConnected) {
    throw 'A VPN is already active on the Android device; refusing to replace it.'
}

New-Item -ItemType Directory -Force -Path $resolvedRoot | Out-Null
$initialVersion = Read-PackageVersion
$screenshots = [Collections.Generic.List[string]]::new()
$report = [ordered]@{
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    serial = $Serial
    package = $Package
    apk = [ordered]@{
        path = $resolvedApk
        sha256 = $actualHash
        size = [long]$apk.Length
    }
    initialVersion = $initialVersion
    installedVersion = $null
    installedApkSha256 = ''
    inPlaceUpgrade = $false
    directProbe = $null
    connectedProbe = $null
    backgroundYoutubeStatus = $null
    crashBufferClean = $false
    finalVpnDisconnected = $false
    screenshots = @()
    success = $false
    error = ''
}

try {
    $direct = Invoke-ExternalProbe -Target 'egressAlternate'
    if ([int]$direct.status -ne 200) {
        throw 'Direct Android egress preflight failed.'
    }
    $report.directProbe = [ordered]@{
        egress = ([string]$direct.body).Trim()
        status = [int]$direct.status
    }

    $installOutput = @(& $Adb -s $Serial install -r $resolvedApk 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($installOutput -join ' ') -notmatch 'Success') {
        throw "APK in-place install failed: $($installOutput -join ' ')"
    }
    $installedVersion = Read-PackageVersion
    $report.installedVersion = $installedVersion
    $report.inPlaceUpgrade = -not [string]::IsNullOrWhiteSpace($initialVersion.name)
    if ($installedVersion.name -ne $ExpectedVersionName -or
            $installedVersion.code -ne $ExpectedVersionCode) {
        throw "Unexpected installed version: $($installedVersion.name)/$($installedVersion.code)"
    }

    $packagePath = ((Invoke-Adb -Arguments @(
        'shell', 'pm', 'path', $Package
    )) | Where-Object { $_ -like 'package:*base.apk' } |
        Select-Object -First 1).Substring(8).Trim()
    Invoke-Adb -Arguments @('pull', $packagePath, $installedApkPath) | Out-Null
    $report.installedApkSha256 = (
        Get-FileHash -LiteralPath $installedApkPath -Algorithm SHA256
    ).Hash
    if ($report.installedApkSha256 -ne $actualHash) {
        throw 'Installed Android base.apk differs from the exact candidate.'
    }

    Invoke-Adb -Arguments @('logcat', '-b', 'crash', '-c') | Out-Null
    Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb -Arguments @(
        'shell', 'am', 'start', '-n', "$Package/.MainActivity"
    ) | Out-Null

    $button = Wait-MainVpnButton -Connected $false -TimeoutSeconds 45
    $homeXml = Get-UiXml
    if ($homeXml.OuterXml -match '(?i)(paid-beta|preview)') {
        throw 'Production Android UI exposes a beta or preview marker.'
    }
    $screenshots.Add((Capture-Screenshot -Name 'android-direct-01-disconnected'))

    $connectStarted = Get-Date
    Tap-Node -Node $button
    Handle-SystemVpnConsent
    Wait-VpnState -Connected $true -TimeoutSeconds $ConnectTimeoutSeconds
    Wait-MainVpnButton -Connected $true -TimeoutSeconds 45 | Out-Null

    $egress = Invoke-ExternalProbe -Target 'egressAlternate'
    $api = Invoke-ExternalProbe -Target 'productionApi'
    $youtube = Invoke-ExternalProbe -Target 'youtube'
    $connectedEgress = ([string]$egress.body).Trim()
    if ([int]$egress.status -ne 200 -or
            $connectedEgress -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$' -or
            $connectedEgress -eq ([string]$report.directProbe.egress)) {
        throw 'Android VPN egress fingerprint did not change from direct.'
    }
    if ([int]$api.status -ne 200 -or [int]$youtube.status -notin @(200, 204)) {
        throw 'Android API or YouTube probe failed while connected.'
    }
    $report.connectedProbe = [ordered]@{
        egress = $connectedEgress
        apiStatus = [int]$api.status
        youtubeStatus = [int]$youtube.status
        connectElapsedMs = [int]((Get-Date) - $connectStarted).TotalMilliseconds
    }
    $screenshots.Add((Capture-Screenshot -Name 'android-direct-02-connected'))

    Invoke-Adb -Arguments @('shell', 'input', 'keyevent', 'KEYCODE_HOME') |
        Out-Null
    Start-Sleep -Seconds 10
    Wait-VpnState -Connected $true -TimeoutSeconds 15
    $background = Invoke-ExternalProbe -Target 'youtube'
    $report.backgroundYoutubeStatus = [int]$background.status
    if ([int]$background.status -notin @(200, 204)) {
        throw 'Android background YouTube probe failed.'
    }

    Invoke-Adb -Arguments @(
        'shell', 'am', 'start', '-n', "$Package/.MainActivity"
    ) | Out-Null
    $disconnectButton = Wait-MainVpnButton -Connected $true -TimeoutSeconds 45
    Tap-Node -Node $disconnectButton
    Wait-VpnState -Connected $false -TimeoutSeconds 60
    Wait-MainVpnButton -Connected $false -TimeoutSeconds 45 | Out-Null

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
            Wait-VpnState -Connected $false -TimeoutSeconds 45
        }
        $report.finalVpnDisconnected = -not (Test-VpnConnected)
        if (-not $report.finalVpnDisconnected) {
            $report.success = $false
            if (-not $report.error) {
                $report.error = 'cleanup_failed: Android VPN remained connected.'
            }
        }
    } catch {
        $report.success = $false
        $report.finalVpnDisconnected = $false
        if (-not $report.error) {
            $report.error = "cleanup_failed: $($_.Exception.Message)"
        }
    }
    $report.screenshots = @($screenshots)
    $report.completedAtUtc = [DateTime]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $reportPath -Encoding UTF8
}

if (-not $report.success) {
    throw "Android direct-release physical test failed: $($report.error)"
}

Write-Host "Android direct-release physical test passed: $reportPath"
Write-Host "Connected egress: $($report.connectedProbe.egress)"
