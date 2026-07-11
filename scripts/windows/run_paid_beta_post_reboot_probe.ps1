param(
    [Parameter(Mandatory = $true)]
    [datetime]$ExpectedPreviousBootTime,
    [string]$ReportPath = 'C:\BlueVPN_Builds\paid_beta_20260711_v13\windows-post-reboot-report.json',
    [string]$ExpectedVersion = '0.3.0-paid-beta.10'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\Green VPN Beta'
$appPath = Join-Path $installRoot 'greenvpn_beta.exe'
$appSoPath = Join-Path $installRoot 'data\app.so'
$configPath = Join-Path $env:ProgramData 'BlueVPNBeta\GreenVPNBeta.conf'
$baseConfigPath = Join-Path $env:ProgramData 'BlueVPNBeta\GreenVPNBeta.base.conf'
$authLogPath = Join-Path $env:ProgramData 'BlueVPNBeta\auth.log'
$sessionPaths = @(
    (Join-Path $env:APPDATA 'GreenVPNBeta\state\session.dat'),
    (Join-Path $env:APPDATA 'GreenVPNBeta\state\session.json')
)

function Read-ConfigField {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $line = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -First 1
    if ($null -eq $line) { return '' }
    return (($line -split '=', 2)[1]).Trim()
}

function Test-BinaryMarker {
    param([string]$Path, [string]$Marker)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path))
        return $text.Contains($Marker)
    } catch {
        return $false
    }
}

function Invoke-WebProbe {
    param([string]$Url, [int]$ExpectedStatus)
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 15
        return [ordered]@{
            url = $Url
            ok = [int]$response.StatusCode -eq $ExpectedStatus
            statusCode = [int]$response.StatusCode
        }
    } catch {
        return [ordered]@{
            url = $Url
            ok = $false
            statusCode = 0
            errorType = $_.Exception.GetType().Name
        }
    }
}

$reportDir = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$deadline = (Get-Date).AddSeconds(90)
do {
    $service = Get-Service -Name 'GreenVPNBetaService' -ErrorAction SilentlyContinue
    $process = Get-Process -Name 'greenvpn_beta' -ErrorAction SilentlyContinue
    $managedAllowedIps = Read-ConfigField -Path $configPath -Name 'AllowedIPs'
    $ready = $null -ne $service -and
        $service.Status -eq 'Running' -and
        $null -ne $process -and
        $managedAllowedIps -match '0\.0\.0\.0/0' -and
        $managedAllowedIps -match '::/0'
    if (-not $ready) { Start-Sleep -Seconds 2 }
} while (-not $ready -and (Get-Date) -lt $deadline)

$bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$service = Get-CimInstance Win32_Service -Filter "Name='GreenVPNBetaService'" -ErrorAction SilentlyContinue
$process = Get-Process -Name 'greenvpn_beta' -ErrorAction SilentlyContinue | Select-Object -First 1
$amnezia = Get-Service -Name 'AmneziaWGTunnel$device20_full' -ErrorAction SilentlyContinue
$managedAllowedIps = Read-ConfigField -Path $configPath -Name 'AllowedIPs'
$baseAllowedIps = Read-ConfigField -Path $baseConfigPath -Name 'AllowedIPs'
$sessionReadAfterBoot = $false
$sessionMigrationFailureAfterBoot = $false
if (Test-Path -LiteralPath $authLogPath) {
    foreach ($line in @(Get-Content -LiteralPath $authLogPath -Tail 200 -ErrorAction SilentlyContinue)) {
        if ($line -notmatch '^\[(.+?)\]\s+UI (.+?)\s*$') { continue }
        $loggedAt = [datetime]::MinValue
        if (-not [datetime]::TryParse($Matches[1], [ref]$loggedAt)) { continue }
        if ($loggedAt -lt $bootTime.AddSeconds(-5)) { continue }
        $message = $Matches[2]
        if ($message -eq 'bootstrap session=present') { $sessionReadAfterBoot = $true }
        if ($message -like 'session storage migration skipped type=*') {
            $sessionMigrationFailureAfterBoot = $true
        }
    }
}
$sessionEncryptedAtRest = $false
$sessionDatPath = $sessionPaths[0]
if (Test-Path -LiteralPath $sessionDatPath) {
    try {
        $storedSession = [IO.File]::ReadAllText($sessionDatPath).Trim()
        [void][Convert]::FromBase64String($storedSession)
        $sessionEncryptedAtRest = -not $storedSession.StartsWith('{')
    } catch {
        $sessionEncryptedAtRest = $false
    }
}
$probes = @(
    (Invoke-WebProbe -Url 'https://api.greenvpn.pro/paid-beta-api/healthz' -ExpectedStatus 200),
    (Invoke-WebProbe -Url 'https://176-113-81-35.sslip.io/paid-beta-api/healthz' -ExpectedStatus 200),
    (Invoke-WebProbe -Url 'https://www.youtube.com/generate_204' -ExpectedStatus 204)
)

$report = [ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    expectedPreviousBootTime = $ExpectedPreviousBootTime.ToUniversalTime().ToString('o')
    currentBootTime = $bootTime.ToUniversalTime().ToString('o')
    rebootObserved = $bootTime -gt $ExpectedPreviousBootTime
    version = [ordered]@{
        expected = $ExpectedVersion
        markerPresent = Test-BinaryMarker -Path $appSoPath -Marker $ExpectedVersion
        appPath = $appPath
    }
    runtime = [ordered]@{
        processRunning = $null -ne $process
        processStartTime = if ($null -ne $process) { $process.StartTime.ToUniversalTime().ToString('o') } else { $null }
        serviceRunning = $null -ne $service -and $service.State -eq 'Running'
        serviceStartMode = if ($null -ne $service) { $service.StartMode } else { $null }
        port48738Listening = $null -ne (Get-NetTCPConnection -LocalPort 48738 -State Listen -ErrorAction SilentlyContinue)
    }
    config = [ordered]@{
        managedUsesNativeKillSwitch = $managedAllowedIps -match '0\.0\.0\.0/0' -and $managedAllowedIps -match '::/0'
        baseSplitDefaultPreserved = $baseAllowedIps -match '0\.0\.0\.0/1' -and $baseAllowedIps -match '128\.0\.0\.0/1'
        managedAllowedIps = $managedAllowedIps
        baseAllowedIps = $baseAllowedIps
    }
    session = [ordered]@{
        preserved = @($sessionPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0
        fileCount = @($sessionPaths | Where-Object { Test-Path -LiteralPath $_ }).Count
        appReadValidSessionAfterBoot = $sessionReadAfterBoot
        migrationWriteSucceeded = -not $sessionMigrationFailureAfterBoot
        encryptedAtRest = $sessionEncryptedAtRest
    }
    competingVpn = [ordered]@{
        amneziaServicePresent = $null -ne $amnezia
        amneziaRunning = $null -ne $amnezia -and $amnezia.Status -eq 'Running'
    }
    stableInstallAbsent = -not (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\Green VPN\greenvpn.exe'))
    probes = $probes
}

$report.success = $report.rebootObserved -and
    $report.version.markerPresent -and
    $report.runtime.processRunning -and
    $report.runtime.serviceRunning -and
    $report.runtime.port48738Listening -and
    $report.config.managedUsesNativeKillSwitch -and
    $report.config.baseSplitDefaultPreserved -and
    $report.session.preserved -and
    $report.session.appReadValidSessionAfterBoot -and
    $report.session.migrationWriteSucceeded -and
    $report.session.encryptedAtRest -and
    $report.competingVpn.amneziaRunning -and
    @($probes | Where-Object { -not $_.ok }).Count -eq 0

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
if (-not $report.success) { exit 1 }
