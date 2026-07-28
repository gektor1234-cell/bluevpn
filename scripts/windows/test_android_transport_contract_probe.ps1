param(
    [string]$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    [Parameter(Mandatory = $true)][string]$Serial,
    [string]$Package = 'pro.greenvpn.app.transportpreview',
    [ValidateRange(1, 100)][int]$ExpectedCheckCount = 10,
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\android_transport_contract_probe_20260712.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$resultFile = 'files/greenvpn-transport-contract-debug-result.json'

if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) { throw "adb is missing: $Adb" }
& $Adb -s $Serial shell am set-inactive $Package false | Out-Null
& $Adb -s $Serial shell am set-standby-bucket $Package active | Out-Null
& $Adb -s $Serial shell cmd deviceidle whitelist "+$Package" | Out-Null
& $Adb -s $Serial shell am start -n "$Package/pro.greenvpn.app.MainActivity" | Out-Null
Start-Sleep -Seconds 2
& $Adb -s $Serial shell run-as $Package rm -f $resultFile | Out-Null
& $Adb -s $Serial shell am startservice `
    -n "$Package/pro.greenvpn.app.TransportContractDebugService" `
    --es command probe | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to start the Android transport contract probe.' }

$deadline = (Get-Date).AddMinutes(3)
$raw = ''
do {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $raw = (@(& $Adb -s $Serial shell run-as $Package cat $resultFile 2>$null) -join '').Trim()
        $readExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($readExitCode -eq 0 -and $raw.StartsWith('{')) { break }
    Start-Sleep -Milliseconds 300
} while ((Get-Date) -lt $deadline)
if (-not $raw.StartsWith('{')) { throw 'Timed out waiting for the Android transport contract probe.' }

$report = $raw | ConvertFrom-Json
$safeReport = [ordered]@{
    capturedAt = (Get-Date).ToUniversalTime().ToString('o')
    serial = $Serial
    package = $Package
    versionCode = [int64]$report.versionCode
    success = [bool]$report.success
    checks = @($report.checks)
    error = if ($report.PSObject.Properties.Name -contains 'error') {
        [string]$report.error
    } else {
        ''
    }
}
$directory = Split-Path -Parent $ReportPath
if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
$safeReport | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
& $Adb -s $Serial shell run-as $Package rm -f $resultFile | Out-Null

if (-not $safeReport.success -or $safeReport.checks.Count -ne $ExpectedCheckCount) {
    throw "Android transport contract probe failed: $($safeReport.error)"
}
if (@($safeReport.checks | Where-Object { -not $_.valid -or $_.httpStatus -ne 200 }).Count -ne 0) {
    throw 'One or more Android transport config contracts failed.'
}

Write-Host "Android transport contract probe passed: $ReportPath"
Write-Host "VersionCode: $($safeReport.versionCode)"
Write-Host "Checks: $($safeReport.checks.Count)"
