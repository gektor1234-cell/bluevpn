param(
    [string]$XrayPath = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\xray-core-v26.7.11\windows-64\xray.exe',
    [string]$SourceConfig = 'C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_vless_20260712\nl2-vless-reality-xhttp.client.json',
    [string]$ExpectedCanaryEgress = '5.129.216.42',
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\windows_vless_reality_socks_physical_20260712.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedXraySha256 = '4B43C5EF596F326B233717B585D31A85DD5CD5F77D8DA872E75F7EBC00E99ACB'
$SocksPort = 1981

function Assert-ClientProfile {
    param([Parameter(Mandatory=$true)]$Root)

    if (@($Root.inbounds).Count -ne 1 -or [string]$Root.inbounds[0].protocol -ne 'socks' -or
        [string]$Root.inbounds[0].listen -ne '127.0.0.1' -or [int]$Root.inbounds[0].port -ne $SocksPort) {
        throw 'VLESS preview profile must expose exactly one loopback SOCKS listener.'
    }
    $outbound = $Root.outbounds[0]
    $server = $outbound.settings.vnext[0]
    $user = $server.users[0]
    $stream = $outbound.streamSettings
    if ([string]$outbound.protocol -ne 'vless' -or [string]$server.address -ne $ExpectedCanaryEgress -or
        [int]$server.port -ne 443 -or [string]$user.encryption -ne 'none' -or
        [string]::IsNullOrWhiteSpace([string]$user.id) -or [string]$stream.network -ne 'xhttp' -or
        [string]$stream.security -ne 'reality' -or
        [string]::IsNullOrWhiteSpace([string]$stream.realitySettings.serverName) -or
        [string]::IsNullOrWhiteSpace([string]$stream.realitySettings.password) -or
        [string]::IsNullOrWhiteSpace([string]$stream.realitySettings.shortId) -or
        [string]::IsNullOrWhiteSpace([string]$stream.xhttpSettings.path)) {
        throw 'VLESS preview profile failed the guarded REALITY/XHTTP contract.'
    }
}

function Wait-LocalPort {
    param([int]$Port, [int]$Seconds = 15)

    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $client = [Net.Sockets.TcpClient]::new()
        try {
            $pending = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
            if ($pending.AsyncWaitHandle.WaitOne(250) -and $client.Connected) {
                $client.EndConnect($pending)
                return
            }
        } catch {
        } finally {
            $client.Dispose()
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "SOCKS listener did not become ready on port $Port."
}

function Invoke-SocksCurl {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)

    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = (& curl.exe --silent --show-error --max-time 25 --socks5-hostname "127.0.0.1:$SocksPort" @Arguments 2>&1 | Out-String).Trim()
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($exitCode -ne 0) { throw "SOCKS HTTP probe failed with curl exit code $exitCode." }
    return $output
}

function Get-HttpStatus {
    param([Parameter(Mandatory=$true)][string]$Url)
    return [int](Invoke-SocksCurl -Arguments @('--output', 'NUL', '--write-out', '%{http_code}', $Url))
}

foreach ($path in @($XrayPath, $SourceConfig)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required VLESS preview file is missing: $path" }
}
if ((Get-FileHash -LiteralPath $XrayPath -Algorithm SHA256).Hash -ne $ExpectedXraySha256) {
    throw 'Official Xray Windows binary hash mismatch.'
}
$profile = Get-Content -LiteralPath $SourceConfig -Raw | ConvertFrom-Json
Assert-ClientProfile -Root $profile

$stdout = Join-Path $env:TEMP ('greenvpn-vless-' + [guid]::NewGuid().ToString('N') + '.stdout.log')
$stderr = Join-Path $env:TEMP ('greenvpn-vless-' + [guid]::NewGuid().ToString('N') + '.stderr.log')
$process = $null
$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    xraySha256 = $ExpectedXraySha256
    sourceConfigSha256 = (Get-FileHash -LiteralPath $SourceConfig -Algorithm SHA256).Hash
    socksReady = $false
    processPathValid = $false
    canaryEgressMatches = $false
    productionApiStatus = 0
    paidBetaPrimaryStatus = 0
    paidBetaFallbackStatus = 0
    youtubeStatus = 0
    processStopped = $false
    success = $false
    error = ''
}

try {
    $validation = Start-Process -FilePath $XrayPath -ArgumentList @('run', '-test', '-config', ('"' + $SourceConfig + '"')) `
        -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($validation.ExitCode -ne 0) { throw 'Official Xray rejected the VLESS preview profile.' }
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue

    $process = Start-Process -FilePath $XrayPath -ArgumentList @('run', '-config', ('"' + $SourceConfig + '"')) `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Wait-LocalPort -Port $SocksPort
    $report.socksReady = $true
    $actualProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)" -ErrorAction Stop
    $report.processPathValid = [IO.Path]::GetFullPath([string]$actualProcess.ExecutablePath).Equals(
        [IO.Path]::GetFullPath($XrayPath), [StringComparison]::OrdinalIgnoreCase)
    if (-not $report.processPathValid) { throw 'Xray process path validation failed.' }

    $egress = Invoke-SocksCurl -Arguments @('https://api.ipify.org')
    $report.canaryEgressMatches = $egress -eq $ExpectedCanaryEgress
    if (-not $report.canaryEgressMatches) { throw 'VLESS preview returned an unexpected egress address.' }
    $report.productionApiStatus = Get-HttpStatus 'https://api.greenvpn.pro/healthz'
    $report.paidBetaPrimaryStatus = Get-HttpStatus 'https://api.greenvpn.pro/paid-beta-api/healthz'
    $report.paidBetaFallbackStatus = Get-HttpStatus 'https://176-113-81-35.sslip.io/paid-beta-api/healthz'
    $report.youtubeStatus = Get-HttpStatus 'https://www.youtube.com/'
    foreach ($name in @('productionApiStatus', 'paidBetaPrimaryStatus', 'paidBetaFallbackStatus', 'youtubeStatus')) {
        if ([int]$report[$name] -lt 200 -or [int]$report[$name] -ge 400) { throw "HTTP probe failed: $name=$($report[$name])" }
    }
    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(5000) | Out-Null
    }
    $report.processStopped = $null -eq $process -or $process.HasExited
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($ReportPath))) | Out-Null
    [IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 4) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
}

if (-not $report.success -or -not $report.processStopped) { exit 1 }
Write-Output "Windows VLESS REALITY SOCKS smoke passed. Report: $ReportPath"
