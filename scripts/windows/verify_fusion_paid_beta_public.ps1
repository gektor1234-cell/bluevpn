[CmdletBinding()]
param(
    [string]$BetaVersion = '0.4.6-paid-beta.1',
    [string]$BetaAndroidBuild = '2026081106',
    [int]$BetaWindowsBuild = 4601,
    [string]$BetaAndroidSha256 = 'F2FF98B569C574910CEB4ED7BA18EBC33FD54013A1DD15DE808DEC69986F883D',
    [long]$BetaAndroidSize = 56340949,
    [string]$BetaWindowsSha256 = '1D752ADFFFB33D60B2693E6AE888EA62AA82EFA1EF0A7462513C35CF2FBCCC89',
    [long]$BetaWindowsSize = 55497216,
    [string]$StableWindowsVersion = '0.3.26',
    [string]$StableWindowsBuild = '3105',
    [string]$StableWindowsSha256 = '1E5505E73B735A00E1C7C44BD1919F96F98EA8DC5F03497205EA39E89AAE00F6',
    [long]$StableWindowsSize = 55441408,
    [string]$StableAndroidVersion = '0.3.19',
    [string]$StableAndroidBuild = '2026072914',
    [string]$StableAndroidSha256 = 'BCA7CF6A4AB2381A6EB44836726AFC07B460B87F0789BA88DC81CF84CD37F4FB',
    [long]$StableAndroidSize = 59988328,
    [string]$StableBackendVersion = '0.9.153-update-channel-alias.4',
    [string]$BetaBackendVersion = '0.9.154-fusion-actions.1',
    [string]$ReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$hosts = @(
    [pscustomobject]@{
        name = 'primary'
        api = 'https://api.greenvpn.pro'
        downloadHost = 'greenvpn.pro'
    },
    [pscustomobject]@{
        name = 'fallback'
        api = 'https://176-113-81-35.sslip.io'
        downloadHost = '176-113-81-35.sslip.io'
    }
)
$betaExpected = @{
    android = [pscustomobject]@{
        version = $BetaVersion
        build = $BetaAndroidBuild
        sha256 = $BetaAndroidSha256.ToUpperInvariant()
        size = $BetaAndroidSize
    }
    windows = [pscustomobject]@{
        version = $BetaVersion
        build = [string]$BetaWindowsBuild
        sha256 = $BetaWindowsSha256.ToUpperInvariant()
        size = $BetaWindowsSize
    }
}
$stableWindowsExpected = [pscustomobject]@{
    version = $StableWindowsVersion
    build = $StableWindowsBuild
    sha256 = $StableWindowsSha256.ToUpperInvariant()
    size = $StableWindowsSize
}
$stableAndroidExpected = [pscustomobject]@{
    version = $StableAndroidVersion
    build = $StableAndroidBuild
    sha256 = $StableAndroidSha256.ToUpperInvariant()
    size = $StableAndroidSize
}

function Assert-Manifest {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$ExpectedDownloadHost,
        [Parameter(Mandatory = $true)][string]$ExpectedDownloadPath
    )

    if (
        [string]$Manifest.latestVersion -ne [string]$Expected.version -or
        [string]$Manifest.buildNumber -ne [string]$Expected.build -or
        [string]$Manifest.sha256 -ne [string]$Expected.sha256 -or
        [long]$Manifest.sizeBytes -ne [long]$Expected.size -or
        $Manifest.fileReady -ne $true -or
        $Manifest.required -ne $false
    ) {
        throw "Manifest mismatch: $Label"
    }

    $downloadUri = [Uri]::new([string]$Manifest.downloadUrl)
    if (
        $downloadUri.Scheme -ne 'https' -or
        $downloadUri.Host -ne $ExpectedDownloadHost -or
        $downloadUri.AbsolutePath -ne $ExpectedDownloadPath -or
        -not [string]::IsNullOrEmpty($downloadUri.Query) -or
        -not [string]::IsNullOrEmpty($downloadUri.Fragment)
    ) {
        throw "Unsafe download URL: $Label"
    }
}

$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromMinutes(5)
$rows = New-Object System.Collections.Generic.List[object]
$backendRows = New-Object System.Collections.Generic.List[object]
$stableAndroid = New-Object System.Collections.Generic.List[object]

try {
    foreach ($hostEntry in $hosts) {
        foreach ($channel in @('stable', 'paid-beta')) {
            $prefix = if ($channel -eq 'paid-beta') { '/paid-beta-api' } else { '' }
            $expectedBackendVersion = if ($channel -eq 'paid-beta') {
                $BetaBackendVersion
            }
            else {
                $StableBackendVersion
            }
            $healthUrl = $hostEntry.api + $prefix + '/healthz'
            $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 30
            if (
                $health.ok -ne $true -or
                [string]$health.version -ne $expectedBackendVersion -or
                $null -eq $health.PSObject.Properties['paidSalesEnabled'] -or
                $health.paidSalesEnabled -ne $false
            ) {
                throw "Backend health mismatch: $($hostEntry.name) $channel"
            }
            $backendRows.Add([pscustomobject]@{
                host = $hostEntry.name
                channel = $channel
                version = [string]$health.version
                ok = [bool]$health.ok
                paidSalesEnabled = [bool]$health.paidSalesEnabled
                healthUrl = $healthUrl
            })

            foreach ($platform in @('android', 'windows')) {
                $manifestUrl = (
                    $hostEntry.api + $prefix +
                    "/api/v1/updates/manifest?platform=$platform&channel=$channel&currentVersion=0.0.0"
                )
                $manifest = (Invoke-RestMethod -Uri $manifestUrl -TimeoutSec 30).manifest
                $fileName = if ($platform -eq 'android') {
                    'GreenVPN_Android.apk'
                }
                else {
                    'GreenVPN_Setup.exe'
                }
                $expectedDownloadPath = if ($channel -eq 'paid-beta') {
                    "/paid-beta/downloads/$fileName"
                }
                else {
                    "/downloads/$fileName"
                }

                if ($channel -eq 'paid-beta') {
                    Assert-Manifest -Manifest $manifest -Expected $betaExpected[$platform] `
                        -Label "$($hostEntry.name) paid-beta $platform" `
                        -ExpectedDownloadHost $hostEntry.downloadHost `
                        -ExpectedDownloadPath $expectedDownloadPath
                }
                else {
                    $stableExpected = if ($platform -eq 'windows') {
                        $stableWindowsExpected
                    }
                    else {
                        $stableAndroidExpected
                    }
                    Assert-Manifest -Manifest $manifest -Expected $stableExpected `
                        -Label "$($hostEntry.name) stable $platform" `
                        -ExpectedDownloadHost $hostEntry.downloadHost `
                        -ExpectedDownloadPath $expectedDownloadPath
                    if ($platform -eq 'android') {
                        $stableAndroid.Add($manifest)
                    }
                }

                $response = $client.GetAsync(
                    [string]$manifest.downloadUrl,
                    [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
                ).GetAwaiter().GetResult()
                try {
                    $response.EnsureSuccessStatusCode() | Out-Null
                    $length = $response.Content.Headers.ContentLength
                    if ($null -eq $length) {
                        throw "Content-Length is missing: $($manifest.downloadUrl)"
                    }
                    $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                    try {
                        $algorithm = [System.Security.Cryptography.SHA256]::Create()
                        try {
                            $sha256 = ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '')
                        }
                        finally {
                            $algorithm.Dispose()
                        }
                    }
                    finally {
                        $stream.Dispose()
                    }
                }
                finally {
                    $response.Dispose()
                }

                if (
                    $sha256 -ne ([string]$manifest.sha256).ToUpperInvariant() -or
                    [long]$length -ne [long]$manifest.sizeBytes
                ) {
                    throw "Public body mismatch: $($hostEntry.name) $channel $platform"
                }

                $rows.Add([pscustomobject]@{
                    host = $hostEntry.name
                    channel = $channel
                    platform = $platform
                    version = [string]$manifest.latestVersion
                    buildNumber = [string]$manifest.buildNumber
                    sizeBytes = [long]$length
                    sha256 = $sha256
                    fileReady = [bool]$manifest.fileReady
                    required = [bool]$manifest.required
                    downloadUrl = [string]$manifest.downloadUrl
                })
            }
        }
    }
}
finally {
    $client.Dispose()
}

if (
    $stableAndroid.Count -ne 2 -or
    [string]$stableAndroid[0].latestVersion -ne [string]$stableAndroid[1].latestVersion -or
    [string]$stableAndroid[0].buildNumber -ne [string]$stableAndroid[1].buildNumber -or
    [string]$stableAndroid[0].sha256 -ne [string]$stableAndroid[1].sha256 -or
    [long]$stableAndroid[0].sizeBytes -ne [long]$stableAndroid[1].sizeBytes
) {
    throw 'Stable Android manifests differ between primary and fallback.'
}

$report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    success = $true
    checksPassed = $rows.Count + $backendRows.Count
    artifactChecksPassed = $rows.Count
    backendChecksPassed = $backendRows.Count
    paidBetaVersion = $BetaVersion
    paidBetaBackendVersion = $BetaBackendVersion
    stableBackendVersion = $StableBackendVersion
    paidSalesDisabled = $true
    productionBackendUnchanged = $true
    stableWindowsUnchanged = $true
    stableAndroidUnchanged = $true
    stableAndroidNodesMatch = $true
    backendResults = @($backendRows | ForEach-Object { $_ })
    results = @($rows | ForEach-Object { $_ })
}
$json = $report | ConvertTo-Json -Depth 8
if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $fullReportPath = [System.IO.Path]::GetFullPath($ReportPath)
    $reportDirectory = Split-Path -Parent $fullReportPath
    if (-not [string]::IsNullOrWhiteSpace($reportDirectory)) {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $fullReportPath,
        $json + "`n",
        [System.Text.UTF8Encoding]::new($false)
    )
}
$json
