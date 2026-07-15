param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$Serial = 'R9WT10CDC2J',
    [string]$Package = 'pro.greenvpn.app.transportpreview',
    [string]$ProbePackage = 'pro.greenvpn.transportprobe',
    [string]$SourceConfig = 'C:\Users\gekto\GreenVPN_Checkpoints\hysteria2_contract_deploy_20260711\nl2-hysteria2-canary.hysteria2.yaml',
    [string]$ExpectedEgress = '5.129.216.42',
    [ValidateRange(1, 5)][int]$ProbeAttempts = 3,
    [ValidateRange(5000, 60000)][int]$ProbeTimeoutMs = 15000,
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\android_hysteria2_preview_physical_20260712.json'
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
    param([string]$Command, [int]$TimeoutSeconds = 70)
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', 'files/greenvpn-h2-debug-result.json') | Out-Null
    Invoke-Adb -Arguments @('shell', 'am', 'broadcast', '--receiver-foreground', '-a', 'pro.greenvpn.hysteria.DEBUG_CONTROL', '-n', "$Package/pro.greenvpn.hysteria.Hysteria2DebugReceiver", '--es', 'command', $Command) | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = (@(& $Adb -s $Serial shell run-as $Package cat files/greenvpn-h2-debug-result.json 2>$null) -join '').Trim()
            $readExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($readExitCode -eq 0 -and $raw.StartsWith('{')) {
            return $raw | ConvertFrom-Json
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for Android debug command: $Command"
}

function Get-EngineProcessCount {
    return @(
        Invoke-Adb -Arguments @('shell', 'ps', '-A', '-o', 'PID,PPID,NAME,ARGS') |
            Select-String -Pattern '\blibhysteria\.so\b'
    ).Count
}

function Get-ServiceRecordCount {
    return @(
        Invoke-Adb -Arguments @('shell', 'dumpsys', 'activity', 'services', $Package) |
            Select-String -Pattern '^\s*\* ServiceRecord\{.*Hysteria2VpnService'
    ).Count
}

function Invoke-ExternalProbe {
    param([int]$TimeoutSeconds = 60)
    $result = [ordered]@{}
    foreach ($target in @('egressAlternate','productionApi','paidBetaPrimary','paidBetaFallback','youtube')) {
        $probe = $null
        $attemptUsed = 0
        for ($attempt = 1; $attempt -le $ProbeAttempts; $attempt++) {
            $attemptUsed = $attempt
            Invoke-Adb -Arguments @('shell', 'run-as', $ProbePackage, 'rm', '-f', 'files/transport-probe-result.json') | Out-Null
            Invoke-Adb -Arguments @(
                'shell', 'am', 'broadcast', '--include-stopped-packages',
                '-a', 'pro.greenvpn.transportprobe.RUN',
                '-n', "$ProbePackage/pro.greenvpn.transportprobe.TransportProbeReceiver",
                '--es', 'target', $target,
                '--ei', 'timeoutMs', ([string]$ProbeTimeoutMs)
            ) | Out-Null
            $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
            do {
                $previousPreference = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    $raw = (@(& $Adb -s $Serial shell run-as $ProbePackage cat files/transport-probe-result.json 2>$null) -join '').Trim()
                    $readExitCode = $LASTEXITCODE
                } finally { $ErrorActionPreference = $previousPreference }
                if ($readExitCode -eq 0 -and $raw.StartsWith('{')) { $probe = $raw | ConvertFrom-Json; break }
                Start-Sleep -Milliseconds 250
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

if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) { throw "adb is missing: $Adb" }
if (-not (Test-Path -LiteralPath $SourceConfig -PathType Leaf)) { throw "Config is missing: $SourceConfig" }
$device = Invoke-Adb -Arguments @('get-state')
if (($device -join '').Trim() -ne 'device') { throw "Android device is not ready: $Serial" }

$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    serial = $Serial
    package = $Package
    probePackage = $ProbePackage
    versionCode = ''
    probeTimeoutMs = $ProbeTimeoutMs
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
    egressAttempts = 0
    productionApiAttempts = 0
    paidBetaPrimaryAttempts = 0
    paidBetaFallbackAttempts = 0
    youtubeAttempts = 0
    rxBytes = 0
    txBytes = 0
    processCountWhileUp = 0
    watchdogState = ''
    watchdogProcessCount = -1
    watchdogServiceCount = -1
    reconnectState = ''
    reconnectEgress = ''
    reconnectProcessCount = -1
    finalState = ''
    finalProcessCount = -1
    finalServiceCount = -1
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
    Invoke-Adb -Arguments @('shell', 'am', 'set-inactive', $ProbePackage, 'false') | Out-Null
    Invoke-Adb -Arguments @('shell', 'am', 'set-standby-bucket', $ProbePackage, 'active') | Out-Null
    Invoke-Adb -Arguments @('shell', 'cmd', 'deviceidle', 'whitelist', "+$ProbePackage") | Out-Null

    $preflight = Invoke-DebugCommand -Command disconnect -TimeoutSeconds 20
    Start-Sleep -Milliseconds 500
    if ($preflight.state -ne 'down' -or (Get-EngineProcessCount) -ne 0 -or (Get-ServiceRecordCount) -ne 0) {
        throw 'Android Hysteria2 preflight cleanup did not reach a clean down state.'
    }

    Invoke-Adb -Arguments @('push', $SourceConfig, '/data/local/tmp/greenvpn-h2-debug.yaml') | Out-Null
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'cp', '/data/local/tmp/greenvpn-h2-debug.yaml', 'files/greenvpn-h2-debug.yaml') | Out-Null
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'chmod', '600', 'files/greenvpn-h2-debug.yaml') | Out-Null
    Invoke-Adb -Arguments @('shell', 'rm', '-f', '/data/local/tmp/greenvpn-h2-debug.yaml') | Out-Null

    $connected = Invoke-DebugCommand -Command connect
    Start-Sleep -Seconds 2
    $external = Invoke-ExternalProbe
    $connectedStatus = Invoke-DebugCommand -Command status -TimeoutSeconds 15
    $report.connected = [bool]$connected.connected
    $report.canaryEgress = [string]$external.egress
    foreach ($name in @('egressStatus','egressError','productionApiStatus','productionApiError','paidBetaPrimaryStatus','paidBetaPrimaryError','paidBetaFallbackStatus','paidBetaFallbackError','youtubeStatus','youtubeError','egressAttempts','productionApiAttempts','paidBetaPrimaryAttempts','paidBetaFallbackAttempts','youtubeAttempts')) {
        $report[$name] = $external.$name
    }
    $report.rxBytes = [int64]$connectedStatus.rxBytes
    $report.txBytes = [int64]$connectedStatus.txBytes
    $report.processCountWhileUp = Get-EngineProcessCount
    if (-not $report.connected -or $connected.state -ne 'up') { throw "Hysteria2 did not reach up: $($connected.engineError)" }
    if ($report.canaryEgress -ne $ExpectedEgress) { throw "Unexpected Android Hysteria2 egress: $($report.canaryEgress); $($report.egressError)" }
    foreach ($key in @('egressStatus','productionApiStatus','paidBetaPrimaryStatus','paidBetaFallbackStatus')) {
        if ([int]$report[$key] -ne 200) { throw "Android Hysteria2 probe failed: $key=$($report[$key])" }
    }
    if ([int]$report.youtubeStatus -notin @(200, 204)) { throw "Android Hysteria2 YouTube probe failed: $($report.youtubeStatus)" }
    if ($report.rxBytes -le 0 -or $report.txBytes -le 0 -or $report.processCountWhileUp -ne 1) {
        throw 'Android Hysteria2 did not prove bidirectional traffic and one exact child process.'
    }

    Invoke-DebugCommand -Command kill_engine -TimeoutSeconds 15 | Out-Null
    Start-Sleep -Seconds 8
    $watchdog = Invoke-DebugCommand -Command status -TimeoutSeconds 15
    $report.watchdogState = [string]$watchdog.state
    $report.watchdogProcessCount = Get-EngineProcessCount
    $report.watchdogServiceCount = Get-ServiceRecordCount
    if ($report.watchdogState -ne 'error' -or $report.watchdogProcessCount -ne 0 -or $report.watchdogServiceCount -ne 0) {
        throw "Android Hysteria2 watchdog cleanup failed: state=$($report.watchdogState) process=$($report.watchdogProcessCount) service=$($report.watchdogServiceCount)"
    }

    $reconnected = Invoke-DebugCommand -Command connect
    Start-Sleep -Seconds 2
    $reconnectedExternal = Invoke-ExternalProbe
    $report.reconnectState = [string]$reconnected.state
    $report.reconnectEgress = [string]$reconnectedExternal.egress
    $report.reconnectProcessCount = Get-EngineProcessCount
    if (-not $reconnected.connected -or $report.reconnectState -ne 'up' -or
        $report.reconnectEgress -ne $ExpectedEgress -or $report.reconnectProcessCount -ne 1) {
        throw 'Android Hysteria2 did not recover after fail-closed cleanup.'
    }

    $disconnected = Invoke-DebugCommand -Command disconnect -TimeoutSeconds 20
    $report.finalState = [string]$disconnected.state
    $report.finalProcessCount = Get-EngineProcessCount
    $report.finalServiceCount = Get-ServiceRecordCount
    if ($report.finalState -ne 'down' -or $report.finalProcessCount -ne 0 -or $report.finalServiceCount -ne 0) {
        throw 'Android Hysteria2 final disconnect did not reach a clean down state.'
    }
    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    try { Invoke-DebugCommand -Command disconnect -TimeoutSeconds 15 | Out-Null } catch {}
    try { Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', 'files/greenvpn-h2-debug.yaml') | Out-Null } catch {}
    try { Invoke-Adb -Arguments @('shell', 'rm', '-f', '/data/local/tmp/greenvpn-h2-debug.yaml') | Out-Null } catch {}
    try { Invoke-Adb -Arguments @('shell', 'cmd', 'deviceidle', 'whitelist', "-$ProbePackage") | Out-Null } catch {}
    try {
        $remaining = @(& $Adb -s $Serial shell run-as $Package ls files/greenvpn-h2-debug.yaml 2>$null)
        $report.plaintextConfigRemoved = ($LASTEXITCODE -ne 0 -or @($remaining).Count -eq 0)
    } catch {
        $report.plaintextConfigRemoved = $true
    }
    if (-not $report.plaintextConfigRemoved) {
        $report.success = $false
        if (-not $report.error) { $report.error = 'Debug plaintext config was not removed.' }
    }
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($ReportPath))) | Out-Null
    $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) { exit 1 }
Write-Output "Android Hysteria2 preview physical smoke passed. Report: $ReportPath"
