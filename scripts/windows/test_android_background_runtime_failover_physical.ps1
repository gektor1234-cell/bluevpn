param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [Parameter(Mandatory = $true)][string]$Serial,
    [string]$Package = 'pro.greenvpn.app.candidate',
    [string]$ProbePackage = 'pro.greenvpn.transportprobe',
    [ValidateRange(30, 180)][int]$ObservationSeconds = 120,
    [string]$ReportPath = 'C:\BlueVPN_Builds\android_background_runtime_failover.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resultFile = 'files/greenvpn-transport-contract-debug-result.json'
$probeResultFile = 'files/transport-probe-result.json'
$debugService = "$Package/pro.greenvpn.app.TransportContractDebugService"
$sourceServer = 'nl1-awg2-canary'
$sourceProtocol = 'amneziawg'
$replacementProtocol = 'hysteria2'
$knownEgresses = @('37.220.85.211', '5.129.216.42', '88.218.250.86')
$routesToCool = @(
    @{ serverId = 'current_wg0'; protocol = 'wireguard_udp' },
    @{ serverId = 'ruvds-2584554-ld8'; protocol = 'wireguard_udp' },
    @{ serverId = 'tw-7879598-nl1'; protocol = 'wireguard_udp' },
    @{ serverId = 'gb1-awg2-canary'; protocol = 'amneziawg' },
    @{ serverId = 'nl2-awg2-canary'; protocol = 'amneziawg' }
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
    Invoke-Adb -Arguments @('shell', 'run-as', $Package, 'rm', '-f', $resultFile) |
        Out-Null
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
    if ($appStackIds.Count -eq 0) {
        throw 'Application task stack was not found.'
    }
    foreach ($stackId in $appStackIds) {
        Invoke-Adb -Arguments @(
            'shell', 'am', 'stack', 'remove', [string]$stackId
        ) | Out-Null
    }
    Start-Sleep -Seconds 1
    $services = (
        Invoke-Adb -Arguments @('shell', 'dumpsys', 'activity', 'services', $Package)
    ) -join "`n"
    if (-not $services.Contains('GreenVpnRuntimeFailoverService')) {
        throw 'Runtime failover service stopped when the application task was removed.'
    }
    return @($appStackIds)
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
    sourceServer = $sourceServer
    sourceProtocol = $sourceProtocol
    replacementProtocol = $replacementProtocol
    appTaskStackIds = @()
    overlapDetected = $false
    recoveryCountBefore = 0
    recoveryCountAfter = 0
    recoveredServerId = ''
    recoveredEgress = ''
    productionApiStatus = 0
    youtubeStatus = 0
    finalCleanDown = $false
    success = $false
    error = ''
}

try {
    Invoke-Adb -Arguments @(
        'shell', 'am', 'start', '-n', "$Package/pro.greenvpn.app.MainActivity"
    ) | Out-Null
    Invoke-DebugCommand -Command 'disconnect_all' | Out-Null
    Invoke-DebugCommand -Command 'clear_tile_cooldown' | Out-Null
    Wait-CleanDown

    foreach ($route in $routesToCool) {
        Invoke-DebugCommand -Command 'set_tile_cooldown' -Extras @(
            '--es', 'serverId', [string]$route.serverId,
            '--es', 'protocol', [string]$route.protocol,
            '--ei', 'failureCount', '4'
        ) | Out-Null
    }

    Invoke-DebugCommand -Command 'connect_candidate' -Extras @(
        '--es', 'serverId', $sourceServer
    ) -TimeoutSeconds 120 | Out-Null
    $sourceSnapshot = Invoke-DebugCommand -Command 'snapshot'
    if (
        @($sourceSnapshot.activeProtocols).Count -ne 1 -or
        [string]$sourceSnapshot.activeProtocols[0] -ne $sourceProtocol -or
        -not [bool]$sourceSnapshot.runtimeFailover.desired -or
        [string]$sourceSnapshot.runtimeFailover.state -ne 'monitoring'
    ) {
        throw 'Source route or runtime failover monitor did not become ready.'
    }
    $report.recoveryCountBefore = [int]$sourceSnapshot.runtimeFailover.recoveryCount
    $report.appTaskStackIds = @(Remove-AppTaskKeepingService)

    Invoke-DebugCommand -Command 'fail_active_engine' -Extras @(
        '--es', 'protocol', $sourceProtocol
    ) | Out-Null

    $deadline = (Get-Date).AddSeconds($ObservationSeconds)
    $recovered = $null
    do {
        $snapshot = Invoke-DebugCommand -Command 'snapshot'
        $active = @($snapshot.activeProtocols)
        if ($active.Count -gt 1) {
            $report.overlapDetected = $true
            throw "Multiple transport engines became active: $($active -join ',')"
        }
        if (
            $active.Count -eq 1 -and
            [string]$active[0] -eq $replacementProtocol -and
            [string]$snapshot.lastRouteSuccess.protocol -eq $replacementProtocol -and
            [int]$snapshot.runtimeFailover.recoveryCount -gt $report.recoveryCountBefore -and
            [string]$snapshot.runtimeFailover.state -eq 'monitoring'
        ) {
            $recovered = $snapshot
            break
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)
    if ($null -eq $recovered) {
        throw 'Background runtime failover did not recover to Hysteria2.'
    }

    $routeProbe = Invoke-DebugCommand -Command 'probe_route' -Extras @(
        '--es', 'protocol', $replacementProtocol
    )
    if (-not [bool]$routeProbe.ok) {
        throw "Recovered route probe failed: $($routeProbe.probeError)"
    }
    $egressProbe = Invoke-ExternalProbe -Target 'egressAlternate'
    $apiProbe = Invoke-ExternalProbe -Target 'productionApi'
    $youtubeProbe = Invoke-ExternalProbe -Target 'youtube'
    $egress = ([string]$egressProbe.body).Trim()
    if ([int]$egressProbe.status -ne 200 -or $egress -notin $knownEgresses) {
        throw "Unexpected recovered egress: $egress"
    }
    if ([int]$apiProbe.status -ne 200) {
        throw "Production API failed after recovery: $($apiProbe.error)"
    }
    if ([int]$youtubeProbe.status -notin @(200, 204)) {
        throw "YouTube failed after recovery: $($youtubeProbe.error)"
    }

    $report.recoveryCountAfter = [int]$recovered.runtimeFailover.recoveryCount
    $report.recoveredServerId = [string]$recovered.lastRouteSuccess.serverId
    $report.recoveredEgress = $egress
    $report.productionApiStatus = [int]$apiProbe.status
    $report.youtubeStatus = [int]$youtubeProbe.status
    $report.success = -not $report.overlapDetected
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
    try {
        Invoke-Adb -Arguments @(
            'shell', 'am', 'start', '-n', "$Package/pro.greenvpn.app.MainActivity"
        ) | Out-Null
    } catch {}
    $report.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $directory = Split-Path -Parent $ReportPath
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $report | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) {
    throw "Android background runtime failover failed: $($report.error)"
}

Write-Host "Android background runtime failover passed: $ReportPath"
Write-Host "$sourceProtocol -> $replacementProtocol"
Write-Host "Recovered server: $($report.recoveredServerId)"
