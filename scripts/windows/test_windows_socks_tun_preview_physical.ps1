param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('naive_https', 'dnstt')]
    [string]$Protocol,
    [Parameter(Mandatory = $true)]
    [string]$SourceConfig,
    [string]$ExpectedCanaryEgress = '5.129.216.42',
    [string]$CompetingServiceName = 'AmneziaWGTunnel$device20_full',
    [ValidateRange(1, 30)]
    [int]$CompetingReleaseDelaySeconds = 8,
    [Parameter(Mandatory = $true)]
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PreviewServiceName = 'GreenVPNTransportPreviewService'
$InstallRoot = Join-Path $env:ProgramFiles 'Green VPN Transport Preview'
$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'
$ConfigPath = Join-Path $ProgramDataRoot 'GreenVPNTransportPreview.conf'
$ProtocolPath = $ConfigPath + '.protocol'
$TokenPath = Join-Path $ProgramDataRoot 'service_token'
$EndpointRouteStatePath = $ConfigPath + '.endpoint-route.json'
$ServiceBase = 'http://127.0.0.1:48739'

$contract = if ($Protocol -eq 'naive_https') {
    [ordered]@{
        label = 'Naive HTTPS'
        adapter = 'GreenVPNNaivePreview'
        routeMetric = 42734
        socksPort = 1982
        routeStatePath = Join-Path $ProgramDataRoot 'naive-https-routes.json'
        enginePidPath = Join-Path $ProgramDataRoot 'naive-https-client.pid'
        hevPidPath = Join-Path $ProgramDataRoot 'naive-https-hev.pid'
        engineExe = Join-Path $InstallRoot 'tools\naive-https\naive.exe'
        hevExe = Join-Path $InstallRoot 'tools\naive-https\hev-socks5-tunnel.exe'
    }
} else {
    [ordered]@{
        label = 'dnstt'
        adapter = 'GreenVPNDnsttPreview'
        routeMetric = 42735
        socksPort = 1983
        routeStatePath = Join-Path $ProgramDataRoot 'dnstt-routes.json'
        enginePidPath = Join-Path $ProgramDataRoot 'dnstt-client.pid'
        hevPidPath = Join-Path $ProgramDataRoot 'dnstt-hev.pid'
        engineExe = Join-Path $InstallRoot 'tools\dnstt\dnstt-client-windows-amd64.exe'
        hevExe = Join-Path $InstallRoot 'tools\dnstt\hev-socks5-tunnel.exe'
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-ServiceState {
    param([string]$Name, [string]$State, [int]$Seconds = 30)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        $current = if ($null -eq $service) { 'Missing' } else { $service.Status.ToString() }
        if ($current -eq $State) { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Service $Name did not reach $State."
}

function Invoke-PreviewApi {
    param([ValidateSet('GET', 'POST')][string]$Method, [string]$Path)
    $token = (Get-Content -LiteralPath $TokenPath -Raw).Trim()
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Method $Method -Uri ($ServiceBase + $Path) `
            -Headers @{ 'X-GreenVPN-Local-Token' = $token } -TimeoutSec 190
        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Body = $response.Content | ConvertFrom-Json
        }
    } catch {
        $statusCode = 0
        $body = $null
        if ($null -ne $_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            $reader = [IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            try { $body = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        }
        return [pscustomobject]@{ StatusCode = $statusCode; Body = $body }
    }
}

function Wait-ManagedState {
    param([bool]$Running, [int]$Seconds = 120)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $status = Invoke-PreviewApi -Method GET -Path '/status'
        $isRunning = $status.StatusCode -eq 200 -and
            $status.Body.protocol -eq $Protocol -and
            $status.Body.tunnelState -eq 'running'
        if ($isRunning -eq $Running) { return $status }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "$($contract.label) preview did not reach running=$Running."
}

function Get-PublicIp {
    param([int]$Seconds = 45)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        try {
            $value = (& curl.exe -4 --silent --show-error --max-time 20 https://api.ipify.org 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and $value -match '^\d{1,3}(?:\.\d{1,3}){3}$') { return $value }
        } catch {}
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    return ''
}

function Get-HttpStatus {
    param([string]$Uri)
    try {
        return [int](Invoke-WebRequest -UseBasicParsing -Uri $Uri -Method Get -TimeoutSec 45).StatusCode
    } catch {
        if ($null -ne $_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

function Get-ExactProcess {
    param([string]$PidPath, [string]$ExpectedPath)
    if (-not (Test-Path -LiteralPath $PidPath)) { return $null }
    $processId = 0
    if (-not [int]::TryParse((Get-Content -LiteralPath $PidPath -Raw).Trim(), [ref]$processId)) { return $null }
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
    if ($null -eq $process -or [string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) { return $null }
    if (-not [IO.Path]::GetFullPath([string]$process.ExecutablePath).Equals(
            [IO.Path]::GetFullPath($ExpectedPath),
            [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    return $process
}

function Get-LocalSocksIp {
    $curlConfig = ''
    try {
        $arguments = @(
            '-4', '--silent', '--show-error', '--max-time', '45',
            '--socks5-hostname', "127.0.0.1:$($contract.socksPort)"
        )
        if ($Protocol -eq 'dnstt') {
            $profile = Get-Content -LiteralPath $SourceConfig -Raw | ConvertFrom-Json
            $curlConfig = Join-Path $ProgramDataRoot ('dnstt-curl-' + [guid]::NewGuid().ToString('N') + '.conf')
            [IO.File]::WriteAllText(
                $curlConfig,
                "proxy-user = `"$([string]$profile.socks.username):$([string]$profile.socks.password)`"`r`n",
                [Text.UTF8Encoding]::new($false)
            )
            & attrib.exe +H $curlConfig 2>$null | Out-Null
            & icacls.exe $curlConfig /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Failed to protect the temporary dnstt curl config.' }
            $arguments += @('--config', $curlConfig)
        }
        $arguments += 'https://api.ipify.org'
        $value = (& curl.exe @arguments 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $value -match '^\d{1,3}(?:\.\d{1,3}){3}$') { return $value }
        return ''
    } finally {
        if ($curlConfig) { Remove-Item -LiteralPath $curlConfig -Force -ErrorAction SilentlyContinue }
    }
}

function Restore-CompetingTunnel {
    param([string]$ServiceName, [string]$OriginalPathName, [string[]]$OriginallyRunningTunnelServices)
    foreach ($service in @(Get-Service -Name 'AmneziaWGTunnel$*' -ErrorAction SilentlyContinue)) {
        if ($service.Status -eq 'Running' -and $service.Name -notin $OriginallyRunningTunnelServices) {
            Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
        }
    }
    if ($null -eq (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
        $match = [regex]::Match($OriginalPathName, '^"([^"]+)"\s+/tunnelservice\s+"([^"]+)"$')
        if (-not $match.Success) { throw 'Original AmneziaWG service command line is not restorable.' }
        $engine = $match.Groups[1].Value
        $config = $match.Groups[2].Value
        if (-not (Test-Path -LiteralPath $engine) -or -not (Test-Path -LiteralPath $config)) {
            throw 'Original AmneziaWG engine or protected config is missing.'
        }
        $restore = Start-Process -FilePath $engine -ArgumentList @(
            '/installtunnelservice', ('"' + $config + '"')
        ) -WindowStyle Hidden -Wait -PassThru
        if ($restore.ExitCode -ne 0) { throw "AmneziaWG service reinstall failed with $($restore.ExitCode)." }
    }
    & sc.exe config $ServiceName start= auto | Out-Null
    & sc.exe start $ServiceName 2>$null | Out-Null
    Wait-ServiceState -Name $ServiceName -State 'Running'
}

if (-not (Test-Path -LiteralPath $SourceConfig -PathType Leaf)) {
    throw "Source config is missing: $SourceConfig"
}
if (-not (Test-IsAdministrator)) {
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $PSCommandPath + '"'),
        '-Protocol', $Protocol,
        '-SourceConfig', ('"' + [IO.Path]::GetFullPath($SourceConfig) + '"'),
        '-ExpectedCanaryEgress', $ExpectedCanaryEgress,
        '-CompetingServiceName', ('"' + $CompetingServiceName + '"'),
        '-CompetingReleaseDelaySeconds', $CompetingReleaseDelaySeconds,
        '-ReportPath', ('"' + [IO.Path]::GetFullPath($ReportPath) + '"')
    )
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments `
        -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $process.ExitCode
}

foreach ($path in @($contract.engineExe, $contract.hevExe, $TokenPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Installed preview component is missing: $path"
    }
}
$previewService = Get-CimInstance Win32_Service -Filter "Name='$PreviewServiceName'"
if ($null -eq $previewService -or $previewService.State -ne 'Running' -or
    -not ([string]$previewService.PathName).StartsWith(('"' + $InstallRoot), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Protected transport preview service is not installed under Program Files.'
}
$competing = Get-CimInstance Win32_Service -Filter "Name='$CompetingServiceName'" -ErrorAction SilentlyContinue
if ($null -eq $competing -or $competing.State -ne 'Running') {
    throw "Expected competing VPN is not running: $CompetingServiceName"
}
$competingPathName = [string]$competing.PathName
$runningAmneziaBefore = @(
    Get-Service -Name 'AmneziaWGTunnel$*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Running' } |
        ForEach-Object { $_.Name }
)

$beforeEgress = Get-PublicIp
$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    protocol = $Protocol
    sourceConfigSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceConfig).Hash
    legacyNaiveProfileAdapted = $false
    beforeEgress = $beforeEgress
    competitorGuardStatus = 0
    competingReleaseDelaySeconds = $CompetingReleaseDelaySeconds
    serviceStatus = ''
    adapterPresent = $false
    endpointRouteInterface = ''
    splitRoutes = @()
    engineProcessPathValid = $false
    hevProcessPathValid = $false
    localSocksEgress = ''
    dnsProbeOk = $false
    ipv4TcpProbeOk = $false
    canaryEgress = ''
    productionApiStatus = 0
    paidBetaPrimaryStatus = 0
    paidBetaFallbackStatus = 0
    youtubeStatus = 0
    watchdogCleanupPassed = $false
    restoredServiceState = ''
    restoredEgress = ''
    success = $false
    error = ''
}

try {
    $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($Protocol -eq 'naive_https') {
        $profile = Get-Content -LiteralPath $SourceConfig -Raw | ConvertFrom-Json
        if ($profile.PSObject.Properties.Name -notcontains 'endpointIp') {
            $proxy = [Uri][string]$profile.proxy
            $guardedEndpoints = @{
                'nl2.vpn.greenvpn.pro' = '5.129.216.42'
                'nl1.vpn.greenvpn.pro' = '37.220.85.211'
                '88-218-250-86.sslip.io' = '88.218.250.86'
            }
            $endpointIp = $guardedEndpoints[$proxy.Host.ToLowerInvariant()]
            if ([string]::IsNullOrWhiteSpace([string]$endpointIp)) {
                throw 'Legacy Naive HTTPS test profile host is not allowlisted.'
            }
            $profile | Add-Member -NotePropertyName endpointIp -NotePropertyValue $endpointIp -Force
            $report.legacyNaiveProfileAdapted = $true
        }
        [IO.File]::WriteAllText(
            $ConfigPath,
            ($profile | ConvertTo-Json -Depth 10),
            [Text.UTF8Encoding]::new($false)
        )
    }
    else {
        Copy-Item -LiteralPath $SourceConfig -Destination $ConfigPath -Force
    }
    [IO.File]::WriteAllText($ProtocolPath, $Protocol, [Text.UTF8Encoding]::new($false))
    & icacls.exe $ConfigPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' ('*' + $currentUserSid + ':R') | Out-Null
    & icacls.exe $ProtocolPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' ('*' + $currentUserSid + ':R') | Out-Null

    $blocked = Invoke-PreviewApi -Method POST -Path '/connect'
    $report.competitorGuardStatus = $blocked.StatusCode
    if ($blocked.StatusCode -ne 409) { throw 'Competing VPN guard did not fail closed with HTTP 409.' }

    Stop-Service -Name $CompetingServiceName -Force
    Wait-ServiceState -Name $CompetingServiceName -State 'Stopped'
    Start-Sleep -Seconds $CompetingReleaseDelaySeconds
    $connected = Invoke-PreviewApi -Method POST -Path '/connect'
    if ($connected.StatusCode -ne 200 -or $connected.Body.ok -ne $true) {
        throw "$($contract.label) connect failed with HTTP $($connected.StatusCode)."
    }
    $status = Wait-ManagedState -Running $true
    $report.serviceStatus = [string]$status.Body.tunnelState

    $adapter = Get-NetAdapter -Name $contract.adapter -ErrorAction SilentlyContinue
    $report.adapterPresent = $null -ne $adapter -and $adapter.Status -eq 'Up'
    if (-not $report.adapterPresent) { throw "$($contract.label) preview adapter is not up." }

    $bypassEndpoint = if ($Protocol -eq 'dnstt') { '1.1.1.1' } else { $ExpectedCanaryEgress }
    $endpointRoute = @(Find-NetRoute -RemoteIPAddress $bypassEndpoint -ErrorAction Stop |
        Where-Object { $_.CimClass.CimClassName -eq 'MSFT_NetRoute' }) |
        Select-Object -First 1
    $report.endpointRouteInterface = [string]$endpointRoute.InterfaceAlias
    if ($report.endpointRouteInterface -eq $contract.adapter) {
        throw "$($contract.label) endpoint route recursed into the preview adapter."
    }
    $routeState = Get-Content -LiteralPath $contract.routeStatePath -Raw | ConvertFrom-Json
    $report.splitRoutes = @($routeState.prefixes)
    if ([int]$routeState.metric -ne [int]$contract.routeMetric -or @($routeState.prefixes).Count -ne 4) {
        throw "$($contract.label) split-default route state is incomplete."
    }

    $engineProcess = Get-ExactProcess -PidPath $contract.enginePidPath -ExpectedPath $contract.engineExe
    $hevProcess = Get-ExactProcess -PidPath $contract.hevPidPath -ExpectedPath $contract.hevExe
    $report.engineProcessPathValid = $null -ne $engineProcess
    $report.hevProcessPathValid = $null -ne $hevProcess
    if (-not $report.engineProcessPathValid -or -not $report.hevProcessPathValid) {
        throw "$($contract.label) engine process path validation failed."
    }

    $report.localSocksEgress = Get-LocalSocksIp
    if ($report.localSocksEgress -ne $ExpectedCanaryEgress) {
        throw "$($contract.label) local SOCKS data plane failed."
    }
    try {
        $report.dnsProbeOk = @(
            Resolve-DnsName api.ipify.org -DnsOnly -QuickTimeout -ErrorAction Stop
        ).Count -gt 0
    } catch {}
    try {
        $report.ipv4TcpProbeOk = Test-NetConnection 1.1.1.1 -Port 443 `
            -InformationLevel Quiet -WarningAction SilentlyContinue
    } catch {}
    if (-not $report.dnsProbeOk -or -not $report.ipv4TcpProbeOk) {
        throw "$($contract.label) DNS or IPv4 TCP probe failed."
    }

    $report.canaryEgress = Get-PublicIp
    if ($report.canaryEgress -ne $ExpectedCanaryEgress) {
        throw "Unexpected $($contract.label) canary egress: $($report.canaryEgress)"
    }
    $report.productionApiStatus = Get-HttpStatus 'https://api.greenvpn.pro/healthz'
    $report.paidBetaPrimaryStatus = Get-HttpStatus 'https://api.greenvpn.pro/paid-beta-api/healthz'
    $report.paidBetaFallbackStatus = Get-HttpStatus 'https://176-113-81-35.sslip.io/paid-beta-api/healthz'
    $report.youtubeStatus = Get-HttpStatus 'https://www.youtube.com/'
    foreach ($key in @('productionApiStatus', 'paidBetaPrimaryStatus', 'paidBetaFallbackStatus', 'youtubeStatus')) {
        if ([int]$report[$key] -lt 200 -or [int]$report[$key] -ge 400) {
            throw "HTTP probe failed: $key=$($report[$key])"
        }
    }

    Stop-Process -Id ([int]$hevProcess.ProcessId) -Force
    $deadline = (Get-Date).AddSeconds(25)
    do {
        $enginesGone = $null -eq (Get-ExactProcess -PidPath $contract.enginePidPath -ExpectedPath $contract.engineExe) -and
            $null -eq (Get-ExactProcess -PidPath $contract.hevPidPath -ExpectedPath $contract.hevExe)
        $stateGone = -not (Test-Path -LiteralPath $contract.routeStatePath) -and
            -not (Test-Path -LiteralPath $EndpointRouteStatePath)
        if ($enginesGone -and $stateGone) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    $report.watchdogCleanupPassed = $enginesGone -and $stateGone
    if (-not $report.watchdogCleanupPassed) {
        throw "$($contract.label) watchdog did not complete fail-safe cleanup."
    }
    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    try { Invoke-PreviewApi -Method POST -Path '/disconnect' | Out-Null } catch {}
    try {
        Restore-CompetingTunnel -ServiceName $CompetingServiceName -OriginalPathName $competingPathName `
            -OriginallyRunningTunnelServices $runningAmneziaBefore
        $report.restoredServiceState = 'Running'
        $report.restoredEgress = Get-PublicIp
    } catch {
        $report.restoredServiceState = 'restore_failed'
        if (-not $report.error) { $report.error = $_.Exception.Message }
    }
    $report.restoredOriginalEgress = $beforeEgress -ne '' -and $report.restoredEgress -eq $beforeEgress
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($ReportPath))) | Out-Null
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success -or $report.restoredServiceState -ne 'Running' -or -not $report.restoredOriginalEgress) {
    exit 1
}
Write-Output "Windows $($contract.label) preview physical smoke passed. Report: $ReportPath"
