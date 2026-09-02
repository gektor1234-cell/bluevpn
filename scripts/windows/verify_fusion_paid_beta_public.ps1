[CmdletBinding()]
param(
    [string]$BetaVersion = '',
    [string]$BetaAndroidVersion = '0.4.6-paid-beta.1',
    [string]$BetaWindowsVersion = '0.4.6-paid-beta.2',
    [string]$BetaAndroidBuild = '2026081106',
    [int]$BetaWindowsBuild = 4602,
    [string]$BetaAndroidSha256 = 'F2FF98B569C574910CEB4ED7BA18EBC33FD54013A1DD15DE808DEC69986F883D',
    [long]$BetaAndroidSize = 56340949,
    [string]$BetaWindowsSha256 = 'B882DB6EEF672C21786608888431126FAFC997EC6D7C5CEADB6CA16DD0AEC4B3',
    [long]$BetaWindowsSize = 55497728,
    [string]$StableWindowsVersion = '0.4.8',
    [string]$StableWindowsBuild = '4641',
    [string]$StableWindowsSha256 = '357EDA90DB1E58793385DABFACBB0C110FC6ECECF41B895F5EE343400CBF5A21',
    [long]$StableWindowsSize = 52839424,
    [string]$StableAndroidVersion = '0.4.12',
    [string]$StableAndroidBuild = '2026083003',
    [string]$StableAndroidSha256 = '1B476663062586B3BF1F90BC5A32FB617F99A3CF25455BBF8D9CAC9D250782C0',
    [long]$StableAndroidSize = 56404945,
    [string]$StableBackendVersion = '0.9.165-subscription-lifecycle.2',
    [string]$BetaBackendVersion = '0.9.154-fusion-actions.1',
    [bool]$StableRequired = $true,
    [string]$StableMinSupportedVersion = '',
    [string]$StableAndroidMinSupportedVersion = '0.4.12',
    [string]$StableWindowsMinSupportedVersion = '0.4.8',
    [bool]$BetaRequired = $false,
    [string]$BetaMinSupportedVersion = '',
    [string]$ReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

if (
    $PSBoundParameters.ContainsKey('BetaVersion') -and
    -not [string]::IsNullOrWhiteSpace($BetaVersion) -and
    -not $PSBoundParameters.ContainsKey('BetaAndroidVersion')
) {
    $BetaAndroidVersion = $BetaVersion
}
if (
    $PSBoundParameters.ContainsKey('BetaVersion') -and
    -not [string]::IsNullOrWhiteSpace($BetaVersion) -and
    -not $PSBoundParameters.ContainsKey('BetaWindowsVersion')
) {
    $BetaWindowsVersion = $BetaVersion
}
if (
    $PSBoundParameters.ContainsKey('StableMinSupportedVersion') -and
    -not [string]::IsNullOrWhiteSpace($StableMinSupportedVersion)
) {
    if (-not $PSBoundParameters.ContainsKey('StableAndroidMinSupportedVersion')) {
        $StableAndroidMinSupportedVersion = $StableMinSupportedVersion
    }
    if (-not $PSBoundParameters.ContainsKey('StableWindowsMinSupportedVersion')) {
        $StableWindowsMinSupportedVersion = $StableMinSupportedVersion
    }
}

$hosts = @(
    [pscustomobject]@{
        name = 'primary'
        api = 'https://api.greenvpn.pro'
        downloadHost = 'greenvpn.pro'
        stablePaidSalesEnabled = $true
    },
    [pscustomobject]@{
        name = 'fallback'
        api = 'https://176-113-81-35.sslip.io'
        downloadHost = '176-113-81-35.sslip.io'
        stablePaidSalesEnabled = $false
    }
)
$betaExpected = @{
    android = [pscustomobject]@{
        version = $BetaAndroidVersion
        build = $BetaAndroidBuild
        sha256 = $BetaAndroidSha256.ToUpperInvariant()
        size = $BetaAndroidSize
        required = $BetaRequired
        minSupportedVersion = $BetaMinSupportedVersion
    }
    windows = [pscustomobject]@{
        version = $BetaWindowsVersion
        build = [string]$BetaWindowsBuild
        sha256 = $BetaWindowsSha256.ToUpperInvariant()
        size = $BetaWindowsSize
        required = $BetaRequired
        minSupportedVersion = $BetaMinSupportedVersion
    }
}
$stableWindowsExpected = [pscustomobject]@{
    version = $StableWindowsVersion
    build = $StableWindowsBuild
    sha256 = $StableWindowsSha256.ToUpperInvariant()
    size = $StableWindowsSize
    required = $StableRequired
    minSupportedVersion = $StableWindowsMinSupportedVersion
}
$stableAndroidExpected = [pscustomobject]@{
    version = $StableAndroidVersion
    build = $StableAndroidBuild
    sha256 = $StableAndroidSha256.ToUpperInvariant()
    size = $StableAndroidSize
    required = $StableRequired
    minSupportedVersion = $StableAndroidMinSupportedVersion
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
        [bool]$Manifest.required -ne [bool]$Expected.required -or
        [string]$Manifest.minSupportedVersion -ne [string]$Expected.minSupportedVersion
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
            $expectedPaidSalesEnabled = if ($channel -eq 'paid-beta') {
                $false
            }
            else {
                [bool]$hostEntry.stablePaidSalesEnabled
            }
            $healthUrl = $hostEntry.api + $prefix + '/healthz'
            $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 30
            if (
                $health.ok -ne $true -or
                [string]$health.version -ne $expectedBackendVersion -or
                $null -eq $health.PSObject.Properties['paidSalesEnabled'] -or
                [bool]$health.paidSalesEnabled -ne $expectedPaidSalesEnabled
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
    paidBetaVersion = if ($BetaAndroidVersion -eq $BetaWindowsVersion) {
        $BetaAndroidVersion
    }
    else {
        $null
    }
    paidBetaAndroidVersion = $BetaAndroidVersion
    paidBetaWindowsVersion = $BetaWindowsVersion
    paidBetaBackendVersion = $BetaBackendVersion
    stableBackendVersion = $StableBackendVersion
    stablePaidSalesPolicy = [ordered]@{
        primary = $true
        fallback = $false
    }
    paidBetaSalesDisabled = $true
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
