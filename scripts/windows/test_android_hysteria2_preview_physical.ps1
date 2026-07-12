param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$Serial = 'R9WT10CDC2J',
    [string]$Package = 'pro.greenvpn.app.transportpreview',
    [string]$SourceConfig = 'C:\Users\gekto\GreenVPN_Checkpoints\hysteria2_contract_deploy_20260711\nl2-hysteria2-canary.hysteria2.yaml',
    [string]$ExpectedEgress = '5.129.216.42',
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

if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) { throw "adb is missing: $Adb" }
if (-not (Test-Path -LiteralPath $SourceConfig -PathType Leaf)) { throw "Config is missing: $SourceConfig" }
$device = Invoke-Adb -Arguments @('get-state')
if (($device -join '').Trim() -ne 'device') { throw "Android device is not ready: $Serial" }

$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    serial = $Serial
    package = $Package
    versionCode = ''
    sourceConfigSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceConfig).Hash
    connected = $false
    canaryEgress = ''
    egressStatus = 0
    productionApiStatus = 0
    paidBetaPrimaryStatus = 0
    paidBetaFallbackStatus = 0
    youtubeStatus = 0
    rxBytes = 0
    txBytes = 0
    processCountWhileUp = 0
    watchdogState = ''
    watchdogProcessCount = -1
    watchdogServiceCount = -1
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
    $report.connected = [bool]$connected.connected
    $report.canaryEgress = [string]$connected.canaryEgress
    $report.egressStatus = [int]$connected.egressStatus
    $report.productionApiStatus = [int]$connected.productionApiStatus
    $report.paidBetaPrimaryStatus = [int]$connected.paidBetaPrimaryStatus
    $report.paidBetaFallbackStatus = [int]$connected.paidBetaFallbackStatus
    $report.youtubeStatus = [int]$connected.youtubeStatus
    $report.rxBytes = [int64]$connected.rxBytes
    $report.txBytes = [int64]$connected.txBytes
    $report.processCountWhileUp = Get-EngineProcessCount
    if (-not $report.connected -or $connected.state -ne 'up') { throw "Hysteria2 did not reach up: $($connected.engineError)" }
    if ($report.canaryEgress -ne $ExpectedEgress) { throw "Unexpected Android Hysteria2 egress: $($report.canaryEgress)" }
    foreach ($key in @('egressStatus','productionApiStatus','paidBetaPrimaryStatus','paidBetaFallbackStatus','youtubeStatus')) {
        if ([int]$report[$key] -ne 200) { throw "Android Hysteria2 probe failed: $key=$($report[$key])" }
    }
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
