param(
    [string]$SourceConfig = 'C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_naive_20260712\nl2-naive-https.client.json',
    [string]$NaiveExe = 'C:\BlueVPN_Builds\windows_transport_preview_20260712_naive\app\tools\naive-https\naive.exe',
    [string]$ExpectedEgress = '5.129.216.42',
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\windows_naive_https_client_smoke_20260712.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SocksPort = 1982

function Get-RouteSignature {
    $rows = Get-NetRoute -ErrorAction Stop |
        Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0', '0.0.0.0/1', '128.0.0.0/1', '::/0', '::/1', '8000::/1') } |
        Sort-Object DestinationPrefix, InterfaceIndex, NextHop, RouteMetric |
        ForEach-Object { "$($_.DestinationPrefix)|$($_.InterfaceIndex)|$($_.NextHop)|$($_.RouteMetric)" }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') } finally { $sha.Dispose() }
}

function Wait-LocalListener {
    param([int]$Seconds = 15)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        if (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $SocksPort -State Listen -ErrorAction SilentlyContinue) { return }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw 'Naive local SOCKS listener did not start.'
}

function Invoke-SocksCurl {
    param([string[]]$Arguments)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = (& curl.exe -4 --silent --show-error --max-time 25 --socks5-hostname "127.0.0.1:$SocksPort" @Arguments 2>&1 | Out-String).Trim()
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    } finally {
        $ErrorActionPreference = $oldPreference
    }
}

foreach ($path in @($SourceConfig, $NaiveExe)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file is missing: $path" }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $NaiveExe).Hash -ne '94F99801C665D29FC071624663C6F7BFA59E8D5EFAA84CD08EF5EBB18B46CB62') {
    throw 'Naive Windows runtime hash mismatch.'
}
if (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $SocksPort -State Listen -ErrorAction SilentlyContinue) {
    throw "Loopback port $SocksPort is already in use."
}

$routeBefore = Get-RouteSignature
$warpBefore = @(Get-Service -Name 'CloudflareWARP' -ErrorAction SilentlyContinue | ForEach-Object { $_.Status.ToString() }) -join ','
$stdout = Join-Path $env:TEMP ('greenvpn-naive-client-' + [guid]::NewGuid().ToString('N') + '.stdout.log')
$stderr = $stdout + '.stderr.log'
$process = $null
$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    sourceConfigSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceConfig).Hash
    naiveExeSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $NaiveExe).Hash
    expectedEgress = $ExpectedEgress
    egress = ''
    youtubeStatus = 0
    exactProcessPath = $false
    routeSignatureUnchanged = $false
    warpServiceStateUnchanged = $false
    listenerRemoved = $false
    success = $false
    error = ''
}

try {
    $process = Start-Process -FilePath $NaiveExe -ArgumentList @($SourceConfig) `
        -WorkingDirectory (Split-Path -Parent $NaiveExe) -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Wait-LocalListener
    $report.exactProcessPath = [IO.Path]::GetFullPath($process.Path).Equals(
        [IO.Path]::GetFullPath($NaiveExe), [StringComparison]::OrdinalIgnoreCase)
    $egress = Invoke-SocksCurl -Arguments @('https://api.ipify.org')
    $youtube = Invoke-SocksCurl -Arguments @('-o', 'NUL', '-w', '%{http_code}', 'https://www.youtube.com/generate_204')
    $report.egress = $egress.Output
    if ($youtube.Output -match '^\d{3}$') { $report.youtubeStatus = [int]$youtube.Output }
    if ($egress.ExitCode -ne 0 -or $report.egress -ne $ExpectedEgress) { throw 'Naive HTTPS egress probe failed.' }
    if ($youtube.ExitCode -ne 0 -or $report.youtubeStatus -lt 200 -or $report.youtubeStatus -ge 400) {
        throw 'Naive HTTPS YouTube probe failed.'
    }
    if (-not $report.exactProcessPath) { throw 'Naive HTTPS process path validation failed.' }
} catch {
    $report.error = $_.Exception.Message
} finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(5000) | Out-Null
    }
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    $report.listenerRemoved = $null -eq (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $SocksPort -State Listen -ErrorAction SilentlyContinue)
    $report.routeSignatureUnchanged = (Get-RouteSignature) -eq $routeBefore
    $warpAfter = @(Get-Service -Name 'CloudflareWARP' -ErrorAction SilentlyContinue | ForEach-Object { $_.Status.ToString() }) -join ','
    $report.warpServiceStateUnchanged = $warpAfter -eq $warpBefore
    $report.success = [string]::IsNullOrEmpty($report.error) -and $report.listenerRemoved -and
        $report.routeSignatureUnchanged -and $report.warpServiceStateUnchanged
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($ReportPath))) | Out-Null
    $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) { exit 1 }
Write-Output "Windows Naive HTTPS non-disruptive client smoke passed. Report: $ReportPath"
