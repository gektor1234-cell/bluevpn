param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$Serial = 'R9WT10CDC2J',
    [string]$Package = 'pro.greenvpn.app.transportpreview',
    [string]$ProbePackage = 'pro.greenvpn.transportprobe',
    [string]$SourceConfig = 'C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_naive_20260712\nl2-naive-https.client.json',
    [string]$ExpectedEgress = '5.129.216.42',
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\android_naive_https_preview_physical_20260712.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Adb {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
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
    param([string]$Command, [int]$TimeoutSeconds = 80)
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', 'files/greenvpn-naive-debug-result.json') | Out-Null
    Invoke-Adb -Arguments @(
        'shell', 'am', 'broadcast', '--receiver-foreground', '--include-stopped-packages',
        '-a', 'pro.greenvpn.naive.DEBUG_CONTROL',
        '-n', "$Package/pro.greenvpn.naive.NaiveHttpsDebugReceiver",
        '--es', 'command', $Command
    ) | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = (@(& $Adb -s $Serial shell run-as $Package cat files/greenvpn-naive-debug-result.json 2>$null) -join '').Trim()
            $readExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($readExitCode -eq 0 -and $raw.StartsWith('{')) { return $raw | ConvertFrom-Json }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for Android debug command: $Command"
}

function Get-EngineProcessCount {
    return @(
        Invoke-Adb -Arguments @('shell', 'ps', '-A', '-o', 'PID,PPID,NAME,ARGS') |
            Select-String -Pattern '\blibnaive\.so\b'
    ).Count
}

function Invoke-ExternalProbe {
    param([int]$TimeoutSeconds = 45)
    $result = [ordered]@{}
    foreach ($target in @('egress','productionApi','paidBetaPrimary','paidBetaFallback','youtube')) {
        Invoke-Adb -Arguments @('shell', 'run-as', $ProbePackage, 'rm', '-f', 'files/transport-probe-result.json') | Out-Null
        Invoke-Adb -Arguments @(
            'shell', 'am', 'broadcast', '--receiver-foreground', '--include-stopped-packages',
            '-a', 'pro.greenvpn.transportprobe.RUN',
            '-n', "$ProbePackage/pro.greenvpn.transportprobe.TransportProbeReceiver",
            '--es', 'target', $target
        ) | Out-Null
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $probe = $null
        do {
            $previousPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $raw = (@(& $Adb -s $Serial shell run-as $ProbePackage cat files/transport-probe-result.json 2>$null) -join '').Trim()
                $readExitCode = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $previousPreference
            }
            if ($readExitCode -eq 0 -and $raw.StartsWith('{')) { $probe = $raw | ConvertFrom-Json; break }
            Start-Sleep -Milliseconds 200
        } while ((Get-Date) -lt $deadline)
        if ($null -eq $probe) { throw "Timed out waiting for Android transport probe: $target" }
        $result[$target + 'Status'] = [int]$probe.status
        $result[$target + 'Error'] = [string]$probe.error
        if ($target -eq 'egress') {
            $ipMatch = [regex]::Match([string]$probe.body, '(?m)^ip=([^\r\n]+)')
            $result.egress = if ($ipMatch.Success) { $ipMatch.Groups[1].Value.Trim() } else { '' }
        }
    }
    return [pscustomobject]$result
}

function Get-ServiceRecordCount {
    return @(
        Invoke-Adb -Arguments @('shell', 'dumpsys', 'activity', 'services', $Package) |
            Select-String -Pattern '^\s*\* ServiceRecord\{.*NaiveHttpsVpnService'
    ).Count
}

function Test-RuntimeConfigRemoved {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $found = @(& $Adb -s $Serial shell run-as $Package find no_backup/naive-preview -maxdepth 1 -type f `
            '(' -name base.json -o -name runtime.json -o -name hev.yaml ')' 2>$null)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return $exitCode -ne 0 -or @($found).Count -eq 0
}

if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) { throw "adb is missing: $Adb" }
if (-not (Test-Path -LiteralPath $SourceConfig -PathType Leaf)) { throw "Config is missing: $SourceConfig" }
if (((Invoke-Adb -Arguments @('get-state')) -join '').Trim() -ne 'device') {
    throw "Android device is not ready: $Serial"
}

$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    serial = $Serial
    package = $Package
    probePackage = $ProbePackage
    versionCode = ''
    sourceConfigSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceConfig).Hash
    connected = $false
    canaryEgress = ''
    egressStatus = 0
    egressError = ''
    productionApiStatus = 0
    productionApiError = ''
    paidBetaPrimaryStatus = 0
    paidBetaPrimaryError = ''
    paidBetaFallbackStatus = 0
    paidBetaFallbackError = ''
    youtubeStatus = 0
    youtubeError = ''
    rxBytes = 0
    txBytes = 0
    processCountWhileUp = 0
    watchdogState = ''
    watchdogProcessCount = -1
    watchdogServiceCount = -1
    reconnectState = ''
    reconnectEgress = ''
    finalState = ''
    finalProcessCount = -1
    finalServiceCount = -1
    runtimeConfigRemoved = $false
    plaintextConfigRemoved = $false
    success = $false
    error = ''
}

try {
    $packageDump = Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $Package)
    $versionLine = $packageDump | Select-String -Pattern 'versionCode=' | Select-Object -First 1
    if ($null -eq $versionLine) { throw "Preview package is not installed: $Package" }
    $report.versionCode = [regex]::Match($versionLine.Line, 'versionCode=(\d+)').Groups[1].Value
    $probeDump = Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $ProbePackage)
    if ($null -eq ($probeDump | Select-String -Pattern 'userId=' | Select-Object -First 1)) {
        throw "Separate-UID transport probe is not installed: $ProbePackage"
    }
    Invoke-Adb -Arguments @(
        'shell', 'am', 'start', '-W',
        '-n', "$Package/pro.greenvpn.naive.NaiveHttpsPermissionDebugActivity"
    ) | Out-Null
    $permissionResult = ((Invoke-Adb -Arguments @(
        'shell', 'run-as', $Package, 'cat', 'files/greenvpn-naive-permission-result.txt'
    )) -join '').Trim()
    $preparedVpn = (Invoke-Adb -Arguments @('shell', 'dumpsys', 'vpn_management')) -join "`n"
    if ($permissionResult -ne 'granted' -or $preparedVpn -notmatch [regex]::Escape($Package)) {
        throw "Android VPN permission is not prepared for the Naive preview package."
    }
    Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb -Arguments @('shell', 'am', 'set-inactive', $ProbePackage, 'false') | Out-Null
    Invoke-Adb -Arguments @('shell', 'am', 'set-standby-bucket', $ProbePackage, 'active') | Out-Null
    Invoke-Adb -Arguments @('shell', 'cmd', 'deviceidle', 'whitelist', "+$ProbePackage") | Out-Null

    $preflight = Invoke-DebugCommand -Command disconnect -TimeoutSeconds 20
    Start-Sleep -Milliseconds 500
    if ($preflight.state -ne 'down' -or (Get-EngineProcessCount) -ne 0 -or (Get-ServiceRecordCount) -ne 0) {
        throw 'Android Naive HTTPS preflight cleanup did not reach a clean down state.'
    }

    Invoke-Adb -Arguments @('push', $SourceConfig, '/data/local/tmp/greenvpn-naive-debug.json') | Out-Null
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'cp', '/data/local/tmp/greenvpn-naive-debug.json', 'files/greenvpn-naive-debug.json') | Out-Null
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'chmod', '600', 'files/greenvpn-naive-debug.json') | Out-Null
    Invoke-Adb -Arguments @('shell', 'rm', '-f', '/data/local/tmp/greenvpn-naive-debug.json') | Out-Null

    $connected = Invoke-DebugCommand -Command connect
    $external = Invoke-ExternalProbe
    $report.connected = [bool]$connected.connected
    $report.canaryEgress = [string]$external.egress
    $report.egressStatus = [int]$external.egressStatus
    $report.egressError = [string]$external.egressError
    $report.productionApiStatus = [int]$external.productionApiStatus
    $report.productionApiError = [string]$external.productionApiError
    $report.paidBetaPrimaryStatus = [int]$external.paidBetaPrimaryStatus
    $report.paidBetaPrimaryError = [string]$external.paidBetaPrimaryError
    $report.paidBetaFallbackStatus = [int]$external.paidBetaFallbackStatus
    $report.paidBetaFallbackError = [string]$external.paidBetaFallbackError
    $report.youtubeStatus = [int]$external.youtubeStatus
    $report.youtubeError = [string]$external.youtubeError
    $report.rxBytes = [int64]$connected.rxBytes
    $report.txBytes = [int64]$connected.txBytes
    $report.processCountWhileUp = Get-EngineProcessCount
    if (-not $report.connected -or $connected.state -ne 'up') {
        throw "Naive HTTPS did not reach up: $($connected.engineError) $($connected.commandError)"
    }
    if ($report.canaryEgress -ne $ExpectedEgress) {
        throw "Unexpected Android Naive HTTPS egress: $($report.canaryEgress); $($report.egressError)"
    }
    foreach ($key in @('egressStatus','productionApiStatus','paidBetaPrimaryStatus','paidBetaFallbackStatus')) {
        if ([int]$report[$key] -ne 200) {
            $errorKey = $key -replace 'Status$', 'Error'
            throw "Android Naive HTTPS probe failed: $key=$($report[$key]); $($report[$errorKey])"
        }
    }
    if ([int]$report.youtubeStatus -notin @(200, 204)) {
        throw "Android Naive HTTPS probe failed: youtubeStatus=$($report.youtubeStatus); $($report.youtubeError)"
    }
    if ($report.rxBytes -le 0 -or $report.txBytes -le 0 -or $report.processCountWhileUp -ne 1) {
        throw 'Android Naive HTTPS did not prove bidirectional traffic and one exact child process.'
    }

    Invoke-DebugCommand -Command kill_engine -TimeoutSeconds 15 | Out-Null
    Start-Sleep -Seconds 8
    $watchdog = Invoke-DebugCommand -Command status -TimeoutSeconds 15
    $report.watchdogState = [string]$watchdog.state
    $report.watchdogProcessCount = Get-EngineProcessCount
    $report.watchdogServiceCount = Get-ServiceRecordCount
    if ($report.watchdogState -ne 'error' -or $report.watchdogProcessCount -ne 0 -or $report.watchdogServiceCount -ne 0) {
        throw "Android Naive HTTPS watchdog cleanup failed: state=$($report.watchdogState) process=$($report.watchdogProcessCount) service=$($report.watchdogServiceCount)"
    }

    $reconnected = Invoke-DebugCommand -Command connect
    $reconnectedExternal = Invoke-ExternalProbe
    $report.reconnectState = [string]$reconnected.state
    $report.reconnectEgress = [string]$reconnectedExternal.egress
    if (-not $reconnected.connected -or $report.reconnectState -ne 'up' -or $report.reconnectEgress -ne $ExpectedEgress) {
        throw 'Android Naive HTTPS did not recover after fail-closed cleanup.'
    }

    $disconnected = Invoke-DebugCommand -Command disconnect -TimeoutSeconds 20
    $report.finalState = [string]$disconnected.state
    $report.finalProcessCount = Get-EngineProcessCount
    $report.finalServiceCount = Get-ServiceRecordCount
    $report.runtimeConfigRemoved = Test-RuntimeConfigRemoved
    if ($report.finalState -ne 'down' -or $report.finalProcessCount -ne 0 -or
        $report.finalServiceCount -ne 0 -or -not $report.runtimeConfigRemoved) {
        throw 'Android Naive HTTPS final cleanup did not reach a clean down state.'
    }
    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    try { Invoke-DebugCommand -Command disconnect -TimeoutSeconds 15 | Out-Null } catch {}
    try { Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', 'files/greenvpn-naive-debug.json') | Out-Null } catch {}
    try { Invoke-Adb -Arguments @('shell', 'rm', '-f', '/data/local/tmp/greenvpn-naive-debug.json') | Out-Null } catch {}
    try { Invoke-Adb -Arguments @('shell', 'cmd', 'deviceidle', 'whitelist', "-$ProbePackage") | Out-Null } catch {}
    try {
        $remaining = @(& $Adb -s $Serial shell run-as $Package ls files/greenvpn-naive-debug.json 2>$null)
        $report.plaintextConfigRemoved = ($LASTEXITCODE -ne 0 -or @($remaining).Count -eq 0)
    } catch {
        $report.plaintextConfigRemoved = $true
    }
    $report.runtimeConfigRemoved = Test-RuntimeConfigRemoved
    if (-not $report.plaintextConfigRemoved -or -not $report.runtimeConfigRemoved) {
        $report.success = $false
        if (-not $report.error) { $report.error = 'Plaintext transport config was not removed.' }
    }
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($ReportPath))) | Out-Null
    $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) { exit 1 }
Write-Output "Android Naive HTTPS preview physical smoke passed. Report: $ReportPath"
