param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [Parameter(Mandatory = $true)][string]$Serial,
    [string]$Package = 'pro.greenvpn.app.transportpreview',
    [string]$ProbePackage = 'pro.greenvpn.transportprobe',
    [string]$SourceConfig = 'C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_vless_20260712\nl2-vless-reality-xhttp.client.json',
    [string]$ExpectedEgress = '5.129.216.42',
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\android_vless_route_probe_fail_closed_physical_20260715.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$vlessResultFile = 'files/greenvpn-vless-debug-result.json'
$appResultFile = 'files/greenvpn-transport-contract-debug-result.json'
$probeResultFile = 'files/transport-probe-result.json'
$vlessReceiver = "$Package/pro.greenvpn.vless.VlessRealityDebugReceiver"
$appDebugService = "$Package/pro.greenvpn.app.TransportContractDebugService"

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

function Read-AppJson {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPackage,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$TimeoutSeconds = 30
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = (@(& $Adb -s $Serial shell run-as $TargetPackage cat $Path 2>$null) -join '').Trim()
            $readExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($readExit -eq 0 -and $raw.StartsWith('{')) { return $raw | ConvertFrom-Json }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for $TargetPackage/$Path"
}

function Invoke-VlessDebugCommand {
    param([Parameter(Mandatory = $true)][string]$Command, [int]$TimeoutSeconds = 45)
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', $vlessResultFile) | Out-Null
    Invoke-Adb -Arguments @(
        'shell', 'am', 'broadcast', '--receiver-foreground', '--include-stopped-packages',
        '-a', 'pro.greenvpn.vless.DEBUG_CONTROL', '-n', $vlessReceiver, '--es', 'command', $Command
    ) | Out-Null
    $result = Read-AppJson -TargetPackage $Package -Path $vlessResultFile -TimeoutSeconds $TimeoutSeconds
    if ([string]$result.command -eq 'error') {
        throw "VLESS debug command failed: $Command :: $($result.commandError)"
    }
    return $result
}

function Invoke-AppRouteProbe {
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', $appResultFile) | Out-Null
    Invoke-Adb -Arguments @(
        'shell', 'am', 'startservice', '-n', $appDebugService,
        '--es', 'command', 'probe_route', '--es', 'protocol', 'vless_reality'
    ) | Out-Null
    $result = Read-AppJson -TargetPackage $Package -Path $appResultFile -TimeoutSeconds 30
    if (-not [bool]$result.success) { throw "App route probe command failed: $($result.error)" }
    return $result
}

function Invoke-ExternalProbe {
    param([Parameter(Mandatory = $true)][string]$Target, [int]$TimeoutMs = 5000)
    Invoke-Adb -Arguments @('shell', 'run-as', $ProbePackage, 'rm', '-f', $probeResultFile) | Out-Null
    Invoke-Adb -Arguments @(
        'shell', 'am', 'broadcast', '--include-stopped-packages',
        '-a', 'pro.greenvpn.transportprobe.RUN',
        '-n', "$ProbePackage/pro.greenvpn.transportprobe.TransportProbeReceiver",
        '--es', 'target', $Target, '--ei', 'timeoutMs', [string]$TimeoutMs
    ) | Out-Null
    return Read-AppJson -TargetPackage $ProbePackage -Path $probeResultFile -TimeoutSeconds 20
}

function Get-EngineProcessCount {
    return @(
        Invoke-Adb -Arguments @('shell', 'ps', '-A', '-o', 'PID,PPID,NAME,ARGS') |
            Select-String -Pattern '\blibxray\.so\b'
    ).Count
}

if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) { throw "adb is missing: $Adb" }
if (-not (Test-Path -LiteralPath $SourceConfig -PathType Leaf)) { throw "Config is missing: $SourceConfig" }
if (((Invoke-Adb -Arguments @('get-state')) -join '').Trim() -ne 'device') {
    throw "Android device is not ready: $Serial"
}

$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    finishedAt = ''
    serial = $Serial
    package = $Package
    versionCode = ''
    sourceConfigSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceConfig).Hash
    connectedState = ''
    routeBeforeOk = $false
    routeBeforeStatus = 0
    routeBeforeLatencyMs = 0
    egressBefore = ''
    stoppedTunState = ''
    engineCountAfterTunStop = -1
    routeAfterOk = $true
    routeAfterStatus = 0
    routeAfterLatencyMs = 0
    routeAfterErrorClass = ''
    externalAfterStatus = -1
    externalAfterErrorClass = ''
    recoveredState = ''
    recoveredRouteOk = $false
    finalState = ''
    success = $false
    error = ''
}

try {
    $packageDump = Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $Package)
    $versionLine = $packageDump | Select-String -Pattern 'versionCode=' | Select-Object -First 1
    if ($null -eq $versionLine) { throw "Preview package is not installed: $Package" }
    $report.versionCode = [regex]::Match($versionLine.Line, 'versionCode=(\d+)').Groups[1].Value

    Invoke-Adb -Arguments @('shell', 'am', 'start', '-n', "$Package/pro.greenvpn.vless.VlessRealityPermissionDebugActivity") | Out-Null
    Start-Sleep -Seconds 1
    Invoke-Adb -Arguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-VlessDebugCommand -Command 'disconnect' -TimeoutSeconds 20 | Out-Null

    Invoke-Adb -Arguments @('push', $SourceConfig, '/data/local/tmp/greenvpn-vless-debug.json') | Out-Null
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'cp', '/data/local/tmp/greenvpn-vless-debug.json', 'files/greenvpn-vless-debug.json') | Out-Null
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'chmod', '600', 'files/greenvpn-vless-debug.json') | Out-Null
    Invoke-Adb -Arguments @('shell', 'rm', '-f', '/data/local/tmp/greenvpn-vless-debug.json') | Out-Null

    $connected = Invoke-VlessDebugCommand -Command 'connect' -TimeoutSeconds 80
    $report.connectedState = [string]$connected.state
    if (-not [bool]$connected.connected -or $report.connectedState -ne 'up') {
        throw "VLESS did not reach up: $($connected.engineError)"
    }

    $routeBefore = Invoke-AppRouteProbe
    $report.routeBeforeOk = [bool]$routeBefore.ok
    $report.routeBeforeStatus = [int]$routeBefore.statusCode
    $report.routeBeforeLatencyMs = [int]$routeBefore.latencyMs
    if (-not $report.routeBeforeOk -or $report.routeBeforeStatus -notin @(200, 204)) {
        throw "Healthy app route probe failed: $($routeBefore.probeError)"
    }
    $egressBefore = Invoke-ExternalProbe -Target 'egressAlternate'
    $report.egressBefore = ([string]$egressBefore.body).Trim()
    if ([int]$egressBefore.status -ne 200 -or $report.egressBefore -ne $ExpectedEgress) {
        throw "Unexpected healthy egress: $($report.egressBefore)"
    }

    $stoppedTun = Invoke-VlessDebugCommand -Command 'stop_tun' -TimeoutSeconds 15
    $report.stoppedTunState = [string]$stoppedTun.state
    Start-Sleep -Milliseconds 750
    $report.engineCountAfterTunStop = Get-EngineProcessCount
    if ($report.stoppedTunState -ne 'up' -or $report.engineCountAfterTunStop -ne 1) {
        throw 'The negative probe did not preserve the engine while stopping only TUN.'
    }

    $routeAfter = Invoke-AppRouteProbe
    $report.routeAfterOk = [bool]$routeAfter.ok
    $report.routeAfterStatus = if ($routeAfter.PSObject.Properties.Name -contains 'statusCode') {
        [int]$routeAfter.statusCode
    } else {
        0
    }
    $report.routeAfterLatencyMs = [int]$routeAfter.latencyMs
    $routeAfterError = if ($routeAfter.PSObject.Properties.Name -contains 'probeError') {
        [string]$routeAfter.probeError
    } else {
        ''
    }
    $report.routeAfterErrorClass = ($routeAfterError -split ':', 2)[0]
    if ($report.routeAfterOk -or $report.routeAfterLatencyMs -gt 18500) {
        throw 'The app route probe did not fail closed within its hard deadline.'
    }

    $externalAfter = Invoke-ExternalProbe -Target 'youtube' -TimeoutMs 5000
    $report.externalAfterStatus = [int]$externalAfter.status
    $report.externalAfterErrorClass = ([string]$externalAfter.error -split ':', 2)[0]
    if ($report.externalAfterStatus -ne 0) {
        throw "External route unexpectedly remained usable after TUN stop: $($report.externalAfterStatus)"
    }

    Invoke-VlessDebugCommand -Command 'disconnect' -TimeoutSeconds 20 | Out-Null
    Invoke-Adb -Arguments @('push', $SourceConfig, '/data/local/tmp/greenvpn-vless-debug.json') | Out-Null
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'cp', '/data/local/tmp/greenvpn-vless-debug.json', 'files/greenvpn-vless-debug.json') | Out-Null
    Invoke-Adb -Arguments @('shell', 'rm', '-f', '/data/local/tmp/greenvpn-vless-debug.json') | Out-Null
    $recovered = Invoke-VlessDebugCommand -Command 'connect' -TimeoutSeconds 80
    $recoveredRoute = Invoke-AppRouteProbe
    $report.recoveredState = [string]$recovered.state
    $report.recoveredRouteOk = [bool]$recoveredRoute.ok
    if ($report.recoveredState -ne 'up' -or -not $report.recoveredRouteOk) {
        throw 'VLESS did not recover after the controlled TUN failure.'
    }

    $final = Invoke-VlessDebugCommand -Command 'disconnect' -TimeoutSeconds 20
    $report.finalState = [string]$final.state
    if ($report.finalState -ne 'down' -or (Get-EngineProcessCount) -ne 0) {
        throw 'Final VLESS cleanup did not reach a clean down state.'
    }
    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    try { Invoke-VlessDebugCommand -Command 'disconnect' -TimeoutSeconds 15 | Out-Null } catch {}
    try { Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', 'files/greenvpn-vless-debug.json') | Out-Null } catch {}
    try { Invoke-Adb -Arguments @('shell', 'rm', '-f', '/data/local/tmp/greenvpn-vless-debug.json') | Out-Null } catch {}
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($ReportPath))) | Out-Null
    $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) { exit 1 }
$report | ConvertTo-Json -Depth 4
