param(
    [string]$AmneziaServiceName = 'AmneziaWGTunnel$device20_full',
    [string]$GreenServiceName = 'GreenVPNBetaService',
    [string]$GreenTunnelName = 'GreenVPNBeta',
    [int]$GreenLocalPort = 48738,
    [int]$HoldSeconds = 20,
    [string]$ReportPath = 'C:\BlueVPN_Builds\paid_beta_20260710_v6\windows-network-transition-report.json',
    [string]$LogPath = 'C:\BlueVPN_Builds\paid_beta_20260710_v6\windows-network-transition.log'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$programDataRoot = Join-Path $env:ProgramData 'BlueVPNBeta'
$tokenPath = Join-Path $programDataRoot 'service_token'
$configPath = Join-Path $programDataRoot "$GreenTunnelName.conf"
$greenTunnelServiceName = "WireGuardTunnel`$$GreenTunnelName"
$wireGuardWg = Join-Path $env:ProgramFiles 'WireGuard\wg.exe'
$sourceNetworkCheck = Join-Path $PSScriptRoot 'check_windows_network_protection.ps1'
$installedNetworkCheck = Join-Path $env:LOCALAPPDATA 'Programs\Green VPN Beta\tools\check_windows_network_protection.ps1'
$networkCheck = if (Test-Path -LiteralPath $sourceNetworkCheck) { $sourceNetworkCheck } else { $installedNetworkCheck }
$failSafeTaskName = 'GreenVPNBetaNetworkSmokeFailsafe'
$reportDirectory = Split-Path -Parent $ReportPath
$logDirectory = Split-Path -Parent $LogPath

foreach ($directory in @($reportDirectory, $logDirectory)) {
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
}

function Write-SmokeLog {
    param([string]$Message)
    $line = "[$((Get-Date).ToUniversalTime().ToString('o'))] $Message"
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value $line
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $arguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'RemoteSigned',
        '-File',
        ('"' + $PSCommandPath + '"'),
        '-AmneziaServiceName',
        ('"' + $AmneziaServiceName + '"'),
        '-GreenServiceName',
        ('"' + $GreenServiceName + '"'),
        '-GreenTunnelName',
        ('"' + $GreenTunnelName + '"'),
        '-GreenLocalPort',
        $GreenLocalPort.ToString([Globalization.CultureInfo]::InvariantCulture),
        '-HoldSeconds',
        $HoldSeconds.ToString([Globalization.CultureInfo]::InvariantCulture),
        '-ReportPath',
        ('"' + $ReportPath + '"'),
        '-LogPath',
        ('"' + $LogPath + '"')
    )
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList $arguments
    Write-Output "Elevated smoke started with PID $($process.Id)."
    exit 0
}

function Get-ServiceSnapshot {
    param([string]$Name)
    $service = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    return [ordered]@{
        name = $Name
        present = $null -ne $service
        state = if ($null -ne $service) { $service.State } else { $null }
    }
}

function Wait-ServiceState {
    param(
        [string]$Name,
        [ValidateSet('Running', 'Stopped', 'Missing')][string]$State,
        [int]$Loops = 60
    )
    for ($i = 0; $i -lt $Loops; $i++) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
        if ($State -eq 'Missing' -and $null -eq $service) { return $true }
        if ($null -ne $service -and $service.State -eq $State) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Invoke-GreenLocal {
    param(
        [ValidateSet('GET', 'POST')][string]$Method,
        [string]$Path,
        [string]$Token = ''
    )
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers['X-GreenVPN-Local-Token'] = $Token
    }
    return Invoke-RestMethod -Method $Method -Uri "http://127.0.0.1:$GreenLocalPort$Path" -Headers $headers -TimeoutSec 135
}

function Get-GreenRuntimeEvidence {
    $latestHandshake = 0L
    $receivedBytes = 0L
    $sentBytes = 0L

    if (Test-Path -LiteralPath $wireGuardWg) {
        try {
            $handshakeLines = @(& $wireGuardWg show $GreenTunnelName latest-handshakes 2>$null)
            foreach ($line in $handshakeLines) {
                $parts = $line -split "`t"
                if ($parts.Count -ge 2) {
                    $value = 0L
                    if ([long]::TryParse($parts[1], [ref]$value) -and $value -gt $latestHandshake) {
                        $latestHandshake = $value
                    }
                }
            }
        } catch {}

        try {
            $transferLines = @(& $wireGuardWg show $GreenTunnelName transfer 2>$null)
            foreach ($line in $transferLines) {
                $parts = $line -split "`t"
                if ($parts.Count -ge 3) {
                    $rx = 0L
                    $tx = 0L
                    [void][long]::TryParse($parts[1], [ref]$rx)
                    [void][long]::TryParse($parts[2], [ref]$tx)
                    $receivedBytes += $rx
                    $sentBytes += $tx
                }
            }
        } catch {}
    }

    $service = Get-CimInstance Win32_Service -Filter "Name='$greenTunnelServiceName'" -ErrorAction SilentlyContinue
    $adapter = Get-NetAdapter -Name $GreenTunnelName -ErrorAction SilentlyContinue
    $routes = @(
        Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0', '0.0.0.0/1', '128.0.0.0/1') } |
            Sort-Object RouteMetric, InterfaceMetric |
            ForEach-Object {
                [ordered]@{
                    destinationPrefix = $_.DestinationPrefix
                    interfaceAlias = $_.InterfaceAlias
                    routeMetric = $_.RouteMetric
                    interfaceMetric = $_.InterfaceMetric
                    state = $_.State.ToString()
                }
            }
    )

    return [ordered]@{
        tunnelServicePresent = $null -ne $service
        tunnelServiceState = if ($null -ne $service) { $service.State } else { $null }
        adapterPresent = $null -ne $adapter
        adapterStatus = if ($null -ne $adapter) { $adapter.Status.ToString() } else { $null }
        latestHandshakeEpoch = $latestHandshake
        handshakeFresh = $latestHandshake -gt ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 180)
        receivedBytes = $receivedBytes
        sentBytes = $sentBytes
        trafficPresent = ($receivedBytes -gt 0 -or $sentBytes -gt 0)
        defaultRoutes = $routes
    }
}

function Invoke-ExternalProbe {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 20
        return [ordered]@{
            url = $Url
            ok = ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
            statusCode = [int]$response.StatusCode
        }
    } catch {
        $statusCode = $null
        if ($null -ne $_.Exception.Response) {
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
        }
        return [ordered]@{
            url = $Url
            ok = $false
            statusCode = $statusCode
            errorType = $_.Exception.GetType().Name
        }
    }
}

function Invoke-DirectDnsLeakProbe {
    param([string]$TunnelName)

    $probeRows = New-Object System.Collections.Generic.List[object]
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Status -eq 'Up' -and
            $_.Name -ne $TunnelName -and
            $_.Name -notmatch '(?i)(loopback|isatap|teredo)' -and
            $_.InterfaceDescription -notmatch '(?i)(wireguard|wintun|amnezia|warp|cloudflare)'
        }

    foreach ($adapter in $adapters) {
        $dnsRows = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -ErrorAction SilentlyContinue
        foreach ($serverValue in @($dnsRows | ForEach-Object { $_.ServerAddresses } | ForEach-Object { $_ } | Where-Object { $_ })) {
            $serverForParse = ([string]$serverValue -split '%', 2)[0]
            $ipAddress = $null
            if (-not [System.Net.IPAddress]::TryParse($serverForParse, [ref]$ipAddress)) { continue }
            if ($ipAddress.ToString() -match '^(?i)fec0:0:0:ffff::[1-3]$') { continue }

            $routeAlias = ''
            try {
                $route = @(
                    Find-NetRoute -RemoteIPAddress $serverForParse -ErrorAction SilentlyContinue |
                        Where-Object { $_.CimClass.CimClassName -eq 'MSFT_NetRoute' }
                ) | Select-Object -First 1
                if ($null -ne $route) { $routeAlias = [string]$route.InterfaceAlias }
            } catch {}
            if ($routeAlias -eq $TunnelName) { continue }

            $reachable = $false
            $errorType = $null
            try {
                $answers = @(Resolve-DnsName 'www.youtube.com' -Server ([string]$serverValue) -DnsOnly -QuickTimeout -ErrorAction Stop)
                $reachable = $answers.Count -gt 0
            } catch {
                $errorType = $_.Exception.GetType().Name
            }

            $probeRows.Add([pscustomobject]@{
                adapter = $adapter.Name
                addressFamily = $ipAddress.AddressFamily.ToString()
                routeAlias = $routeAlias
                reachableOutsideTunnel = $reachable
                errorType = $errorType
            }) | Out-Null
        }
    }

    $reachableCount = @($probeRows | Where-Object { $_.reachableOutsideTunnel }).Count
    return [pscustomobject]@{
        attempted = $probeRows.Count
        reachableOutsideTunnel = $reachableCount
        blockedOrUnreachable = ($probeRows.Count - $reachableCount)
        leakDetected = $reachableCount -gt 0
        probes = @($probeRows.ToArray())
    }
}

if (-not (Test-Path -LiteralPath $tokenPath)) {
    throw "Green VPN local token is missing: $tokenPath"
}
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Green VPN managed config is missing: $configPath"
}

$greenService = Get-CimInstance Win32_Service -Filter "Name='$GreenServiceName'" -ErrorAction SilentlyContinue
if ($null -eq $greenService -or $greenService.State -ne 'Running') {
    throw "$GreenServiceName must be installed and running."
}

$token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
if ($token.Length -lt 24) {
    throw 'Green VPN local token is invalid.'
}

$amneziaBefore = Get-CimInstance Win32_Service -Filter "Name='$AmneziaServiceName'" -ErrorAction SilentlyContinue
$amneziaWasRunning = $null -ne $amneziaBefore -and $amneziaBefore.State -eq 'Running'
$greenConnected = $false
$failure = $null
$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    completedAt = $null
    success = $false
    failure = $null
    amneziaBefore = Get-ServiceSnapshot -Name $AmneziaServiceName
    greenBefore = Get-GreenRuntimeEvidence
    connectResponse = $null
    greenConnected = $null
    externalProbes = @()
    dnsResolution = $null
    dnsLeakProbe = $null
    networkProtection = $null
    greenAfterHold = $null
    greenAfterCleanup = $null
    amneziaAfter = $null
    restoredConnectivity = @()
    failSafeTask = [ordered]@{
        name = $failSafeTaskName
        registered = $false
        removed = $false
    }
}

Write-SmokeLog "start amneziaWasRunning=$amneziaWasRunning"

try {
    if (-not $amneziaWasRunning) {
        throw "$AmneziaServiceName was not running before the smoke; refusing to change an unknown baseline."
    }

    $failSafeAction = New-ScheduledTaskAction -Execute 'sc.exe' -Argument "start `"$AmneziaServiceName`""
    $failSafeTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(8)
    $failSafePrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $failSafeTaskName -Action $failSafeAction -Trigger $failSafeTrigger -Principal $failSafePrincipal -Force | Out-Null
    $report.failSafeTask.registered = $true
    Write-SmokeLog "registered failsafe task $failSafeTaskName"

    Write-SmokeLog "stopping $AmneziaServiceName"
    & sc.exe stop $AmneziaServiceName 2>$null | Out-Null
    if (-not (Wait-ServiceState -Name $AmneziaServiceName -State Stopped)) {
        throw "$AmneziaServiceName did not stop."
    }

    Write-SmokeLog 'requesting Green VPN connect'
    $connect = Invoke-GreenLocal -Method POST -Path '/connect' -Token $token
    $report.connectResponse = [ordered]@{
        ok = $connect.ok
        exitCode = $connect.exitCode
        message = $connect.message
    }
    if (-not $connect.ok) {
        throw "Green VPN connect failed: $($connect.message)"
    }

    for ($i = 0; $i -lt 60; $i++) {
        $status = Invoke-GreenLocal -Method GET -Path '/status' -Token $token
        if ($status.ok -and $status.tunnelState -eq 'running') {
            $greenConnected = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $greenConnected) {
        throw 'Green VPN tunnel did not reach running state.'
    }

    Start-Sleep -Seconds 3
    $report.greenConnected = Get-GreenRuntimeEvidence

    try {
        $dnsAnswers = @(Resolve-DnsName 'www.youtube.com' -DnsOnly -ErrorAction Stop)
        $report.dnsResolution = [ordered]@{
            ok = $dnsAnswers.Count -gt 0
            answerCount = $dnsAnswers.Count
        }
    } catch {
        $report.dnsResolution = [ordered]@{
            ok = $false
            answerCount = 0
            errorType = $_.Exception.GetType().Name
        }
    }
    $report.dnsLeakProbe = Invoke-DirectDnsLeakProbe -TunnelName $GreenTunnelName

    $probeUrls = @(
        'https://api.greenvpn.pro/paid-beta-api/healthz',
        'https://176-113-81-35.sslip.io/paid-beta-api/healthz',
        'https://www.youtube.com/generate_204'
    )
    $report.externalProbes = @($probeUrls | ForEach-Object { Invoke-ExternalProbe -Url $_ })

    if (Test-Path -LiteralPath $networkCheck) {
        $networkRaw = & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File $networkCheck -TunnelName $GreenTunnelName -ConfigPath $configPath -Json 2>$null
        $network = $networkRaw | ConvertFrom-Json
        $report.networkProtection = [ordered]@{
            ok = $network.ok
            productionReady = $network.productionReady
            green = $network.summary.green
            yellow = $network.summary.yellow
            red = $network.summary.red
            checks = @(
                $network.checks |
                    ForEach-Object {
                        [ordered]@{
                            code = $_.code
                            status = $_.status
                            message = $_.message
                        }
                    }
            )
        }
    }

    Write-SmokeLog "holding Green VPN for $HoldSeconds seconds"
    Start-Sleep -Seconds $HoldSeconds
    $report.greenAfterHold = Get-GreenRuntimeEvidence

    $allProbesOk = @($report.externalProbes | Where-Object { $_.ok }).Count -eq $report.externalProbes.Count
    if (-not $allProbesOk) {
        throw 'One or more external probes failed through Green VPN.'
    }
    if (-not $report.dnsResolution.ok) {
        throw 'DNS resolution failed through Green VPN.'
    }
    if ($report.dnsLeakProbe.leakDetected) {
        throw 'A DNS server outside the Green VPN route answered a direct leak probe.'
    }
    if ($null -ne $report.networkProtection -and -not $report.networkProtection.productionReady) {
        throw 'The Windows network-protection checker did not reach production-ready state.'
    }
    if (-not $report.greenAfterHold.handshakeFresh) {
        throw 'No fresh Green VPN handshake was observed.'
    }
    if (-not $report.greenAfterHold.trafficPresent) {
        throw 'No Green VPN traffic counters were observed.'
    }

    $report.success = $true
    Write-SmokeLog 'Green VPN connected smoke passed'
} catch {
    $failure = $_.Exception.Message
    $report.failure = $failure
    Write-SmokeLog "failure type=$($_.Exception.GetType().Name)"
} finally {
    try {
        Write-SmokeLog 'disconnecting Green VPN'
        [void](Invoke-GreenLocal -Method POST -Path '/disconnect' -Token $token)
        [void](Wait-ServiceState -Name $greenTunnelServiceName -State Missing -Loops 80)
    } catch {
        Write-SmokeLog "Green VPN cleanup warning type=$($_.Exception.GetType().Name)"
    }
    $report.greenAfterCleanup = Get-GreenRuntimeEvidence
    if ($report.greenAfterCleanup.tunnelServicePresent -or $report.greenAfterCleanup.adapterPresent) {
        $cleanupFailure = 'Green VPN tunnel or adapter remained after cleanup.'
        $report.success = $false
        if ($null -eq $report.failure) { $report.failure = $cleanupFailure }
        Write-SmokeLog 'Green VPN cleanup did not fully remove runtime state'
    }

    if ($amneziaWasRunning) {
        try {
            Write-SmokeLog "restoring $AmneziaServiceName"
            & sc.exe start $AmneziaServiceName 2>$null | Out-Null
            if (-not (Wait-ServiceState -Name $AmneziaServiceName -State Running -Loops 80)) {
                throw "$AmneziaServiceName did not return to Running."
            }
        } catch {
            $restoreFailure = $_.Exception.Message
            Write-SmokeLog "Amnezia restore failure type=$($_.Exception.GetType().Name)"
            if ($null -eq $failure) {
                $failure = $restoreFailure
                $report.failure = $restoreFailure
                $report.success = $false
            }
        }
    }

    Start-Sleep -Seconds 3
    $report.amneziaAfter = Get-ServiceSnapshot -Name $AmneziaServiceName
    $report.restoredConnectivity = @(
        Invoke-ExternalProbe -Url 'https://api.greenvpn.pro/paid-beta-api/healthz'
        Invoke-ExternalProbe -Url 'https://176-113-81-35.sslip.io/paid-beta-api/healthz'
    )
    $restoreProbesOk = @($report.restoredConnectivity | Where-Object { $_.ok }).Count -eq $report.restoredConnectivity.Count
    if ($report.amneziaAfter.state -ne 'Running' -or -not $restoreProbesOk) {
        $restoreVerificationFailure = 'Amnezia or external connectivity was not restored to the pre-smoke baseline.'
        $report.success = $false
        if ($null -eq $report.failure) { $report.failure = $restoreVerificationFailure }
        Write-SmokeLog 'post-restore verification failed'
    } elseif ($report.failSafeTask.registered) {
        try {
            Unregister-ScheduledTask -TaskName $failSafeTaskName -Confirm:$false -ErrorAction Stop
            $report.failSafeTask.removed = $true
            Write-SmokeLog "removed failsafe task $failSafeTaskName"
        } catch {
            $report.success = $false
            if ($null -eq $report.failure) { $report.failure = 'Temporary failsafe task could not be removed.' }
            Write-SmokeLog 'failsafe task cleanup failed'
        }
    }
    $report.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $report | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-SmokeLog "finished success=$($report.success)"
    Remove-Variable token -ErrorAction SilentlyContinue
}

if (-not $report.success) {
    throw "Network transition smoke failed. See $ReportPath and $LogPath"
}
