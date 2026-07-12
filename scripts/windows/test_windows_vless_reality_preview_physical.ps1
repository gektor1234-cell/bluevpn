param(
    [string]$SourceConfig = 'C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_vless_20260712\nl2-vless-reality-xhttp.client.json',
    [string]$ExpectedCanaryEgress = '5.129.216.42',
    [string]$CompetingServiceName = 'AmneziaWGTunnel$device20_full',
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\windows_vless_reality_preview_physical_20260712.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PreviewServiceName = 'GreenVPNTransportPreviewService'
$InstallRoot = Join-Path $env:ProgramFiles 'Green VPN Transport Preview'
$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'
$ConfigPath = Join-Path $ProgramDataRoot 'GreenVPNTransportPreview.conf'
$ProtocolPath = $ConfigPath + '.protocol'
$TokenPath = Join-Path $ProgramDataRoot 'service_token'
$RouteStatePath = Join-Path $ProgramDataRoot 'vless-reality-routes.json'
$EndpointRouteStatePath = $ConfigPath + '.endpoint-route.json'
$XrayPidPath = Join-Path $ProgramDataRoot 'vless-reality-client.pid'
$HevPidPath = Join-Path $ProgramDataRoot 'vless-reality-hev.pid'
$XrayExe = Join-Path $InstallRoot 'tools\vless-reality\xray.exe'
$HevExe = Join-Path $InstallRoot 'tools\vless-reality\hev-socks5-tunnel.exe'
$ServiceBase = 'http://127.0.0.1:48739'
$AdapterName = 'GreenVPNVlessPreview'
$RouteMetric = 42733

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
    param([ValidateSet('GET','POST')][string]$Method, [string]$Path)
    $token = (Get-Content -LiteralPath $TokenPath -Raw).Trim()
    $headers = @{ 'X-GreenVPN-Local-Token' = $token }
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Method $Method -Uri ($ServiceBase + $Path) -Headers $headers -TimeoutSec 130
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = ($response.Content | ConvertFrom-Json) }
    } catch {
        $statusCode = 0
        $body = $null
        if ($null -ne $_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            $reader = [IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            try { $body = ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose() }
        }
        return [pscustomobject]@{ StatusCode = $statusCode; Body = $body }
    }
}

function Wait-VlessState {
    param([bool]$Running, [int]$Seconds = 35)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $status = Invoke-PreviewApi -Method GET -Path '/status'
        $isRunning = $status.StatusCode -eq 200 -and
            $status.Body.protocol -eq 'vless_reality' -and
            $status.Body.tunnelState -eq 'running'
        if ($isRunning -eq $Running) { return $status }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "VLESS REALITY preview did not reach running=$Running."
}

function Get-PublicIp {
    try {
        $value = (& curl.exe -4 --silent --show-error --max-time 15 https://api.ipify.org 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $value -match '^\d{1,3}(?:\.\d{1,3}){3}$') { return $value }
    } catch {}
    foreach ($uri in @('https://api.ipify.org', 'https://ifconfig.me/ip')) {
        try {
            $value = (Invoke-RestMethod -Uri $uri -TimeoutSec 15).ToString().Trim()
            if ($value -match '^\d{1,3}(?:\.\d{1,3}){3}$') { return $value }
        } catch {}
    }
    return ''
}

function Get-LocalSocksIp {
    try {
        $value = (& curl.exe -4 --silent --show-error --max-time 20 --socks5-hostname 127.0.0.1:1981 https://api.ipify.org 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $value -match '^\d{1,3}(?:\.\d{1,3}){3}$') { return $value }
    } catch {}
    return ''
}

function Get-HttpStatus {
    param([string]$Uri)
    try { return [int](Invoke-WebRequest -UseBasicParsing -Uri $Uri -Method Get -TimeoutSec 20).StatusCode } catch {
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
    if (-not [IO.Path]::GetFullPath([string]$process.ExecutablePath).Equals([IO.Path]::GetFullPath($ExpectedPath), [StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $process
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
        $restore = Start-Process -FilePath $engine -ArgumentList @('/installtunnelservice', ('"' + $config + '"')) `
            -WindowStyle Hidden -Wait -PassThru
        if ($restore.ExitCode -ne 0) { throw "AmneziaWG service reinstall failed with $($restore.ExitCode)." }
    }
    & sc.exe config $ServiceName start= auto | Out-Null
    & sc.exe start $ServiceName 2>$null | Out-Null
    Wait-ServiceState -Name $ServiceName -State 'Running'
}

if (-not (Test-Path -LiteralPath $SourceConfig)) { throw "Source config is missing: $SourceConfig" }
if (-not (Test-IsAdministrator)) {
    $args = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $PSCommandPath + '"'),
        '-SourceConfig', ('"' + [IO.Path]::GetFullPath($SourceConfig) + '"'),
        '-ExpectedCanaryEgress', $ExpectedCanaryEgress,
        '-CompetingServiceName', ('"' + $CompetingServiceName + '"'),
        '-ReportPath', ('"' + [IO.Path]::GetFullPath($ReportPath) + '"')
    )
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $process.ExitCode
}

foreach ($path in @($XrayExe, $HevExe, $TokenPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Installed preview component is missing: $path" }
}
$service = Get-CimInstance Win32_Service -Filter "Name='$PreviewServiceName'"
if ($null -eq $service -or $service.State -ne 'Running' -or
    -not ([string]$service.PathName).StartsWith(('"' + $InstallRoot), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Protected transport preview service is not installed under Program Files.'
}
$competing = Get-CimInstance Win32_Service -Filter "Name='$CompetingServiceName'" -ErrorAction SilentlyContinue
if ($null -eq $competing -or $competing.State -ne 'Running') { throw "Expected competing VPN is not running: $CompetingServiceName" }
$competingPathName = [string]$competing.PathName
$runningAmneziaBefore = @(Get-Service -Name 'AmneziaWGTunnel$*' -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -eq 'Running' } | ForEach-Object { $_.Name })

$beforeEgress = Get-PublicIp
$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    sourceConfigSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceConfig).Hash
    beforeEgress = $beforeEgress
    competitorGuardStatus = 0
    serviceStatus = ''
    adapterPresent = $false
    endpointRouteInterface = ''
    splitRoutes = @()
    xrayProcessPathValid = $false
    hevProcessPathValid = $false
    localSocksEgress = ''
    directFallbackStatus = 0
    directSocksEgress = ''
    xrayEndpointTcpStates = @()
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
    Copy-Item -LiteralPath $SourceConfig -Destination $ConfigPath -Force
    [IO.File]::WriteAllText($ProtocolPath, 'vless_reality', [Text.UTF8Encoding]::new($false))
    & icacls.exe $ConfigPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' ('*' + $currentUserSid + ':R') | Out-Null
    & icacls.exe $ProtocolPath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' ('*' + $currentUserSid + ':R') | Out-Null

    $blocked = Invoke-PreviewApi -Method POST -Path '/connect'
    $report.competitorGuardStatus = $blocked.StatusCode
    if ($blocked.StatusCode -ne 409) { throw 'Competing VPN guard did not fail closed with HTTP 409.' }

    Stop-Service -Name $CompetingServiceName -Force
    Wait-ServiceState -Name $CompetingServiceName -State 'Stopped'
    Start-Sleep -Seconds 1
    foreach ($other in @(Get-Service -Name 'AmneziaWGTunnel$*' -ErrorAction SilentlyContinue)) {
        if ($other.Status -eq 'Running' -and $other.Name -notin $runningAmneziaBefore) {
            Stop-Service -Name $other.Name -Force -ErrorAction SilentlyContinue
        }
    }
    $directStdout = Join-Path $env:TEMP ('greenvpn-vless-direct-' + [guid]::NewGuid().ToString('N') + '.stdout.log')
    $directStderr = Join-Path $env:TEMP ('greenvpn-vless-direct-' + [guid]::NewGuid().ToString('N') + '.stderr.log')
    $directProcess = $null
    try {
        $profile = Get-Content -LiteralPath $SourceConfig -Raw | ConvertFrom-Json
        $serverName = [string]$profile.outbounds[0].streamSettings.realitySettings.serverName
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $fallbackStatus = (& curl.exe -4 --silent --show-error --max-time 20 --noproxy '*' `
            --resolve "${serverName}:443:${ExpectedCanaryEgress}" --output NUL --write-out '%{http_code}' `
            "https://${serverName}/" 2>&1 | Out-String).Trim()
        $fallbackExit = $LASTEXITCODE
        $ErrorActionPreference = $oldPreference
        if ($fallbackExit -eq 0 -and $fallbackStatus -match '^\d{3}$') {
            $report.directFallbackStatus = [int]$fallbackStatus
        }
        $directProcess = Start-Process -FilePath $XrayExe -ArgumentList @('run', '-config', ('"' + $SourceConfig + '"')) `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput $directStdout -RedirectStandardError $directStderr
        Start-Sleep -Seconds 2
        $report.directSocksEgress = Get-LocalSocksIp
    } finally {
        if ($null -ne $directProcess -and -not $directProcess.HasExited) {
            Stop-Process -Id $directProcess.Id -Force -ErrorAction SilentlyContinue
            $directProcess.WaitForExit(5000) | Out-Null
        }
        Remove-Item -LiteralPath $directStdout, $directStderr -Force -ErrorAction SilentlyContinue
    }
    if ($report.directFallbackStatus -lt 100 -or $report.directFallbackStatus -ge 600) {
        throw 'Direct HTTPS fallback to the VLESS canary failed.'
    }
    if ($report.directSocksEgress -ne $ExpectedCanaryEgress) {
        throw 'Direct VLESS REALITY path failed before TUN startup.'
    }
    $connected = Invoke-PreviewApi -Method POST -Path '/connect'
    if ($connected.StatusCode -ne 200 -or $connected.Body.ok -ne $true) { throw "VLESS REALITY connect failed with HTTP $($connected.StatusCode)." }
    $status = Wait-VlessState -Running $true
    $report.serviceStatus = [string]$status.Body.tunnelState
    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
    $report.adapterPresent = $null -ne $adapter -and $adapter.Status -eq 'Up'
    if (-not $report.adapterPresent) { throw 'VLESS REALITY preview adapter is not up.' }

    $endpointRoute = Find-NetRoute -RemoteIPAddress '5.129.216.42' -ErrorAction Stop
    $report.endpointRouteInterface = [string]$endpointRoute.InterfaceAlias
    if ($report.endpointRouteInterface -eq $AdapterName) { throw 'VLESS REALITY endpoint route recursed into the preview adapter.' }
    $routeState = Get-Content -LiteralPath $RouteStatePath -Raw | ConvertFrom-Json
    $report.splitRoutes = @($routeState.prefixes)
    if ([int]$routeState.metric -ne $RouteMetric -or @($routeState.prefixes).Count -ne 4) { throw 'VLESS REALITY split-default route state is incomplete.' }

    $xrayProcess = Get-ExactProcess -PidPath $XrayPidPath -ExpectedPath $XrayExe
    $hevProcess = Get-ExactProcess -PidPath $HevPidPath -ExpectedPath $HevExe
    $report.xrayProcessPathValid = $null -ne $xrayProcess
    $report.hevProcessPathValid = $null -ne $hevProcess
    if (-not $report.xrayProcessPathValid -or -not $report.hevProcessPathValid) { throw 'VLESS REALITY engine process path validation failed.' }

    $report.localSocksEgress = Get-LocalSocksIp
    $report.xrayEndpointTcpStates = @(Get-NetTCPConnection -OwningProcess ([int]$xrayProcess.ProcessId) -ErrorAction SilentlyContinue |
        Where-Object { $_.RemoteAddress -eq $ExpectedCanaryEgress -and $_.RemotePort -eq 443 } |
        Group-Object -Property State | ForEach-Object {
            [pscustomobject]@{ state = $_.Name; count = $_.Count }
        })
    if ($report.localSocksEgress -ne $ExpectedCanaryEgress) { throw 'VLESS REALITY local SOCKS data plane failed.' }
    try {
        $report.dnsProbeOk = @((Resolve-DnsName api.ipify.org -DnsOnly -QuickTimeout -ErrorAction Stop)).Count -gt 0
    } catch {}
    try {
        $report.ipv4TcpProbeOk = Test-NetConnection 1.1.1.1 -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
    } catch {}

    $report.canaryEgress = Get-PublicIp
    if ($report.canaryEgress -ne $ExpectedCanaryEgress) { throw "Unexpected canary egress: $($report.canaryEgress)" }
    $report.productionApiStatus = Get-HttpStatus 'https://api.greenvpn.pro/healthz'
    $report.paidBetaPrimaryStatus = Get-HttpStatus 'https://api.greenvpn.pro/paid-beta-api/healthz'
    $report.paidBetaFallbackStatus = Get-HttpStatus 'https://176-113-81-35.sslip.io/paid-beta-api/healthz'
    $report.youtubeStatus = Get-HttpStatus 'https://www.youtube.com/'
    foreach ($key in @('productionApiStatus','paidBetaPrimaryStatus','paidBetaFallbackStatus','youtubeStatus')) {
        if ([int]$report[$key] -lt 200 -or [int]$report[$key] -ge 400) { throw "HTTP probe failed: $key=$($report[$key])" }
    }

    Stop-Process -Id ([int]$hevProcess.ProcessId) -Force
    $deadline = (Get-Date).AddSeconds(15)
    do {
        $enginesGone = $null -eq (Get-ExactProcess -PidPath $XrayPidPath -ExpectedPath $XrayExe) -and
            $null -eq (Get-ExactProcess -PidPath $HevPidPath -ExpectedPath $HevExe)
        $stateGone = -not (Test-Path -LiteralPath $RouteStatePath) -and -not (Test-Path -LiteralPath $EndpointRouteStatePath)
        if ($enginesGone -and $stateGone) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    $report.watchdogCleanupPassed = $enginesGone -and $stateGone
    if (-not $report.watchdogCleanupPassed) { throw 'VLESS REALITY watchdog did not complete fail-safe cleanup.' }
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
        Start-Sleep -Seconds 3
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

if (-not $report.success -or $report.restoredServiceState -ne 'Running' -or -not $report.restoredOriginalEgress) { exit 1 }
Write-Output "Windows VLESS REALITY preview physical smoke passed. Report: $ReportPath"
