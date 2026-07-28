param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [string]$Serial = '',
    [string]$Package = 'pro.greenvpn.app.transportpreview',
    [string]$ProbePackage = 'pro.greenvpn.transportprobe',
    [ValidateRange(10, 180)][int]$RouteTimeoutSeconds = 120,
    [string]$ReportPath = 'C:\BlueVPN_Builds\android_public_product_transport_matrix.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resultFile = 'files/greenvpn-transport-contract-debug-result.json'
$probeResultFile = 'files/transport-probe-result.json'
$debugService = "$Package/pro.greenvpn.app.TransportContractDebugService"
$candidates = @(
    [pscustomobject]@{ serverId = 'current_wg0'; protocol = 'wireguard_udp'; egress = '37.220.85.211' }
    [pscustomobject]@{ serverId = 'ruvds-2584554-ld8'; protocol = 'wireguard_udp'; egress = '88.218.250.86' }
    [pscustomobject]@{ serverId = 'tw-7879598-nl1'; protocol = 'wireguard_udp'; egress = '5.129.216.42' }
    [pscustomobject]@{ serverId = 'gb1-awg2-canary'; protocol = 'amneziawg'; egress = '88.218.250.86' }
    [pscustomobject]@{ serverId = 'nl1-awg2-canary'; protocol = 'amneziawg'; egress = '37.220.85.211' }
    [pscustomobject]@{ serverId = 'nl2-awg2-canary'; protocol = 'amneziawg'; egress = '5.129.216.42' }
    [pscustomobject]@{ serverId = 'gb1-hysteria2-canary'; protocol = 'hysteria2'; egress = '88.218.250.86' }
    [pscustomobject]@{ serverId = 'nl1-hysteria2-canary'; protocol = 'hysteria2'; egress = '37.220.85.211' }
    [pscustomobject]@{ serverId = 'nl2-hysteria2-canary'; protocol = 'hysteria2'; egress = '5.129.216.42' }
    [pscustomobject]@{ serverId = 'gb1-vless-reality-xhttp-canary'; protocol = 'vless_reality'; egress = '88.218.250.86' }
    [pscustomobject]@{ serverId = 'nl1-vless-reality-xhttp-canary'; protocol = 'vless_reality'; egress = '37.220.85.211' }
    [pscustomobject]@{ serverId = 'nl2-vless-reality-xhttp-canary'; protocol = 'vless_reality'; egress = '5.129.216.42' }
    [pscustomobject]@{ serverId = 'gb1-naive-https-canary'; protocol = 'naive_https'; egress = '88.218.250.86' }
    [pscustomobject]@{ serverId = 'nl1-naive-https-canary'; protocol = 'naive_https'; egress = '37.220.85.211' }
    [pscustomobject]@{ serverId = 'nl2-naive-https-canary'; protocol = 'naive_https'; egress = '5.129.216.42' }
    [pscustomobject]@{ serverId = 'nl2-dnstt-canary'; protocol = 'dnstt'; egress = '5.129.216.42' }
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
        [int]$TimeoutSeconds = 180
    )
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', $resultFile) | Out-Null
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
                & $Adb -s $Serial shell run-as $Package cat $resultFile 2>$null
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

function Wait-ExactRoute {
    param(
        [Parameter(Mandatory = $true)][string]$ServerId,
        [Parameter(Mandatory = $true)][string]$Protocol
    )
    $deadline = (Get-Date).AddSeconds($RouteTimeoutSeconds)
    do {
        $snapshot = Invoke-DebugCommand -Command 'snapshot' -TimeoutSeconds 20
        $lastServer = [string]$snapshot.lastRouteSuccess.serverId
        $lastProtocol = [string]$snapshot.lastRouteSuccess.protocol
        $active = @($snapshot.activeProtocols)
        $activeMatches = if ($Protocol -eq 'wireguard_udp') {
            $active.Count -eq 0 -and (Get-VpnRecordCount) -eq 1
        } else {
            $active.Count -eq 1 -and [string]$active[0] -eq $Protocol
        }
        if ($lastServer -eq $ServerId -and $lastProtocol -eq $Protocol -and $activeMatches) {
            return $snapshot
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Route did not become active: $ServerId/$Protocol"
}

function Wait-CleanDown {
    $deadline = (Get-Date).AddSeconds(45)
    do {
        $snapshot = Invoke-DebugCommand -Command 'snapshot' -TimeoutSeconds 20
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

function Get-EgressIp {
    # 1.1.1.1 is intentionally excluded from VLESS and dnstt full-tunnel
    # routes because those engines use it as their protected DNS transport.
    $probe = Invoke-ExternalProbe -Target 'egressAlternate'
    if ([int]$probe.status -ne 200) {
        throw "Egress probe failed: status=$($probe.status) error=$($probe.error)"
    }
    $match = [regex]::Match(([string]$probe.body).Trim(), '^(?:\d{1,3}\.){3}\d{1,3}$')
    if (-not $match.Success) {
        throw 'Egress probe did not return a canonical IPv4 address.'
    }
    return $match.Value
}

if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) {
    throw "adb is missing: $Adb"
}
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
if (((Invoke-Adb -Arguments @('get-state')) -join '').Trim() -ne 'device') {
    throw "Android device is not ready: $Serial"
}
foreach ($packageName in @($Package, $ProbePackage)) {
    $dump = Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $packageName)
    if ($null -eq ($dump | Select-String -Pattern 'userId=' | Select-Object -First 1)) {
        throw "Required Android package is not installed: $packageName"
    }
}

Invoke-Adb -Arguments @('shell', 'am', 'set-inactive', $Package, 'false') | Out-Null
Invoke-Adb -Arguments @('shell', 'am', 'set-standby-bucket', $Package, 'active') | Out-Null
Invoke-Adb -Arguments @('shell', 'cmd', 'deviceidle', 'whitelist', "+$Package") | Out-Null
Invoke-Adb -Arguments @('shell', 'am', 'set-inactive', $ProbePackage, 'false') | Out-Null
Invoke-Adb -Arguments @('shell', 'am', 'set-standby-bucket', $ProbePackage, 'active') | Out-Null
Invoke-Adb -Arguments @('shell', 'cmd', 'deviceidle', 'whitelist', "+$ProbePackage") | Out-Null

$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    device = 'selected-android-device'
    package = $Package
    strictOrder = @('wireguard_udp', 'amneziawg', 'hysteria2', 'vless_reality', 'naive_https', 'dnstt')
    routes = @()
    fallback = $null
    finalCleanDown = $false
    success = $false
}

try {
    Invoke-DebugCommand -Command 'clear_tile_cooldown' | Out-Null
    Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
    Wait-CleanDown

    foreach ($candidate in $candidates) {
        $routeResult = [ordered]@{
            serverId = $candidate.serverId
            protocol = $candidate.protocol
            expectedEgress = $candidate.egress
            connectMs = 0
            routeProbeOk = $false
            routeProbeStatus = 0
            routeProbeLatencyMs = 0
            egress = ''
            productionApiStatus = 0
            youtubeStatus = 0
            cleanupOk = $false
            success = $false
            error = ''
        }
        try {
            Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
            Wait-CleanDown
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-DebugCommand -Command 'connect_candidate' -Extras @(
                '--es', 'serverId', $candidate.serverId
            ) -TimeoutSeconds $RouteTimeoutSeconds | Out-Null
            Wait-ExactRoute -ServerId $candidate.serverId -Protocol $candidate.protocol | Out-Null
            $stopwatch.Stop()
            $routeResult.connectMs = $stopwatch.ElapsedMilliseconds

            $routeProbe = Invoke-DebugCommand -Command 'probe_route' -Extras @(
                '--es', 'protocol', $candidate.protocol
            ) -TimeoutSeconds $RouteTimeoutSeconds
            $routeResult.routeProbeOk = [bool]$routeProbe.ok
            $routeResult.routeProbeStatus = [int]$routeProbe.statusCode
            $routeResult.routeProbeLatencyMs = [int64]$routeProbe.latencyMs
            if (-not $routeResult.routeProbeOk) {
                throw "Route probe failed: $($routeProbe.probeError)"
            }

            $routeResult.egress = Get-EgressIp
            if ($routeResult.egress -ne $candidate.egress) {
                throw "Unexpected egress: $($routeResult.egress)"
            }
            $apiProbe = Invoke-ExternalProbe -Target 'productionApi'
            $routeResult.productionApiStatus = [int]$apiProbe.status
            if ($routeResult.productionApiStatus -ne 200) {
                throw "Production API failed: $($apiProbe.error)"
            }
            $youtubeProbe = Invoke-ExternalProbe -Target 'youtube'
            $routeResult.youtubeStatus = [int]$youtubeProbe.status
            if ($routeResult.youtubeStatus -notin @(200, 204)) {
                throw "YouTube probe failed: $($youtubeProbe.error)"
            }

            Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
            Wait-CleanDown
            $routeResult.cleanupOk = $true
            $routeResult.success = $true
        } catch {
            $routeResult.error = $_.Exception.Message
            try {
                Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
                Wait-CleanDown
                $routeResult.cleanupOk = $true
            } catch {
                $routeResult.error += "; cleanup: $($_.Exception.Message)"
            }
        }
        $report.routes += [pscustomobject]$routeResult
        Write-Host (
            "route={0}/{1} success={2} egress={3} connectMs={4}" -f
            $candidate.serverId,
            $candidate.protocol,
            $routeResult.success,
            $routeResult.egress,
            $routeResult.connectMs
        )
    }

    $fallbackResult = [ordered]@{
        fromProtocol = 'amneziawg'
        toProtocol = 'hysteria2'
        overlapDetected = $false
        recoveredServerId = ''
        recoveredEgress = ''
        routeProbeOk = $false
        success = $false
        error = ''
    }
    try {
        Invoke-DebugCommand -Command 'clear_tile_cooldown' | Out-Null
        $routesToCool = @(
            $candidates |
                Where-Object {
                    $_.protocol -eq 'wireguard_udp' -or
                    ($_.protocol -eq 'amneziawg' -and $_.serverId -ne 'nl1-awg2-canary')
                }
        )
        foreach ($route in $routesToCool) {
            Invoke-DebugCommand -Command 'set_tile_cooldown' -Extras @(
                '--es', 'serverId', $route.serverId,
                '--es', 'protocol', $route.protocol,
                '--ei', 'failureCount', '4'
            ) | Out-Null
        }
        Invoke-DebugCommand -Command 'connect_candidate' -Extras @(
            '--es', 'serverId', 'nl1-awg2-canary'
        ) -TimeoutSeconds $RouteTimeoutSeconds | Out-Null
        Wait-ExactRoute -ServerId 'nl1-awg2-canary' -Protocol 'amneziawg' | Out-Null
        Invoke-DebugCommand -Command 'fail_active_engine' -Extras @(
            '--es', 'protocol', 'amneziawg'
        ) | Out-Null

        $deadline = (Get-Date).AddSeconds($RouteTimeoutSeconds)
        do {
            $snapshot = Invoke-DebugCommand -Command 'snapshot' -TimeoutSeconds 20
            $active = @($snapshot.activeProtocols)
            if ($active.Count -gt 1) {
                $fallbackResult.overlapDetected = $true
                throw "Multiple transport engines became active: $($active -join ',')"
            }
            if (
                [string]$snapshot.lastRouteSuccess.protocol -eq 'hysteria2' -and
                $active.Count -eq 1 -and
                [string]$active[0] -eq 'hysteria2'
            ) {
                $fallbackResult.recoveredServerId = [string]$snapshot.lastRouteSuccess.serverId
                break
            }
            Start-Sleep -Milliseconds 750
        } while ((Get-Date) -lt $deadline)
        if (-not $fallbackResult.recoveredServerId) {
            throw 'Runtime failover did not recover from AWG to Hysteria2.'
        }
        $routeProbe = Invoke-DebugCommand -Command 'probe_route' -Extras @(
            '--es', 'protocol', 'hysteria2'
        ) -TimeoutSeconds $RouteTimeoutSeconds
        $fallbackResult.routeProbeOk = [bool]$routeProbe.ok
        if (-not $fallbackResult.routeProbeOk) {
            throw "Recovered route probe failed: $($routeProbe.probeError)"
        }
        $fallbackResult.recoveredEgress = Get-EgressIp
        if ($fallbackResult.recoveredEgress -notin @('37.220.85.211', '5.129.216.42', '88.218.250.86')) {
            throw "Unexpected recovered egress: $($fallbackResult.recoveredEgress)"
        }
        $fallbackResult.success = -not $fallbackResult.overlapDetected
    } catch {
        $fallbackResult.error = $_.Exception.Message
    } finally {
        try { Invoke-DebugCommand -Command 'clear_tile_cooldown' | Out-Null } catch {}
        try {
            Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
            Wait-CleanDown
        } catch {
            if (-not $fallbackResult.error) {
                $fallbackResult.error = "final cleanup: $($_.Exception.Message)"
            }
        }
    }
    $report.fallback = [pscustomobject]$fallbackResult
    $report.finalCleanDown = (Get-VpnRecordCount) -eq 0 -and (Get-TransportEngineProcessCount) -eq 0
    $report.success = (
        @($report.routes | Where-Object { -not $_.success }).Count -eq 0 -and
        $fallbackResult.success -and
        $report.finalCleanDown
    )
} finally {
    $report.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $directory = Split-Path -Parent $ReportPath
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) {
    $failed = @($report.routes | Where-Object { -not $_.success })
    throw "Android public-product transport matrix failed: routes=$($failed.Count), fallback=$($report.fallback.success)"
}

Write-Host "Android public-product transport matrix passed: $ReportPath"
Write-Host "Routes: $($report.routes.Count)"
Write-Host "Fallback: $($report.fallback.fromProtocol) -> $($report.fallback.toProtocol)"
