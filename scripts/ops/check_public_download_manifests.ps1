param(
    [Parameter(Mandatory = $false)]
    [string]$ApiBaseUrl = "https://api.greenvpn.pro",

    [Parameter(Mandatory = $false)]
    [string]$SiteBaseUrl = "https://greenvpn.pro",

    [Parameter(Mandatory = $false)]
    [string]$FallbackApiBaseUrl = "https://176-113-81-35.sslip.io",

    [Parameter(Mandatory = $false)]
    [string]$FallbackSiteBaseUrl = "https://176-113-81-35.sslip.io",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedAndroidVersion = "0.3.19",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedAndroidSha256 = "BCA7CF6A4AB2381A6EB44836726AFC07B460B87F0789BA88DC81CF84CD37F4FB",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestAndroidSha256 = "99EB6C2D44C955F43441039B5375CEC5AF925D19EDAFEE1D17042FAE6E2ED8A7",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedAndroidBuildNumber = "2026072914",

    [Parameter(Mandatory = $false)]
    [bool]$ExpectedAndroidRequired = $false,

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestAndroidVersion = "0.3.19",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestAndroidBuildNumber = "2026072914",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestAndroidApplicationId = "pro.greenvpn.app.beta",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestAndroidAppLabel = "Green VPN Beta",

    [Parameter(Mandatory = $false)]
    [bool]$ExpectedTestAndroidRequired = $false,

    [Parameter(Mandatory = $false)]
    [string]$ExpectedWindowsVersion = "0.3.21",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedWindowsSha256 = "0D98EDBDBA4FFFA6B94F5C0D04CF3461C0C8E5F57AEC57FB201D678ED45A5E85",

    [Parameter(Mandatory = $false)]
    [bool]$ExpectedWindowsRequired = $false,

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestWindowsVersion = "0.3.21-paid-beta.1",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestWindowsSha256 = "34D838226281190EB6B867D87884B4C9AF066FD69C7D49D05D045713530338CA",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestWindowsBuildNumber = "3001",

    [Parameter(Mandatory = $false)]
    [bool]$ExpectedTestWindowsRequired = $false,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSec = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\infra\provider_api_common.ps1"

function Get-UpdateManifestCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedPlatform,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedExtension,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedChannel,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedVersion,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedSha256,

        [Parameter(Mandatory = $true)]
        [bool]$ExpectedRequired
    )

    try {
        $response = Invoke-RestMethod -Uri $Uri -TimeoutSec $TimeoutSec -ErrorAction Stop
        $manifest = $response.manifest
        $downloadUrl = [string]$manifest.downloadUrl
        $extensionOk = $downloadUrl.ToLowerInvariant().EndsWith($ExpectedExtension.ToLowerInvariant())
        $platformOk = ([string]$manifest.platform) -eq $ExpectedPlatform
        $channelOk = ([string]$manifest.channel) -eq $ExpectedChannel
        $versionOk = ([string]$manifest.latestVersion) -eq $ExpectedVersion
        $sha256Ok = ([string]$manifest.sha256).ToUpperInvariant() -eq $ExpectedSha256.ToUpperInvariant()
        $requiredOk = [bool]$manifest.required -eq $ExpectedRequired
        return [pscustomobject]@{
            name = $Name
            ok = [bool](
                $response.ok -and
                $platformOk -and
                $channelOk -and
                $versionOk -and
                $sha256Ok -and
                $requiredOk -and
                $extensionOk -and
                $manifest.fileReady
            )
            platform = $manifest.platform
            expectedPlatform = $ExpectedPlatform
            platformOk = $platformOk
            channel = $manifest.channel
            expectedChannel = $ExpectedChannel
            channelOk = $channelOk
            latestVersion = $manifest.latestVersion
            expectedVersion = $ExpectedVersion
            versionOk = $versionOk
            updateAvailable = $manifest.updateAvailable
            required = $manifest.required
            expectedRequired = $ExpectedRequired
            requiredOk = $requiredOk
            sha256 = $manifest.sha256
            expectedSha256 = $ExpectedSha256
            sha256Ok = $sha256Ok
            downloadUrl = $downloadUrl
            expectedExtension = $ExpectedExtension
            extensionOk = $extensionOk
            fileReady = $manifest.fileReady
        }
    } catch {
        return [pscustomobject]@{
            name = $Name
            ok = $false
            error = (Protect-GreenVpnString -Value $_.Exception.Message)
        }
    }
}

function Get-DownloadHeadCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedExtension
    )

    try {
        $response = Invoke-WebRequest -Uri $Uri -Method Head -TimeoutSec $TimeoutSec -ErrorAction Stop
        $lengthText = ($response.Headers["Content-Length"] -join "")
        $length = if ([string]::IsNullOrWhiteSpace($lengthText)) { 0 } else { [int64]$lengthText }
        $extensionOk = $Uri.ToLowerInvariant().EndsWith($ExpectedExtension.ToLowerInvariant())
        return [pscustomobject]@{
            name = $Name
            ok = ([int]$response.StatusCode -eq 200 -and $extensionOk -and $length -gt 0)
            status = [int]$response.StatusCode
            url = $Uri
            expectedExtension = $ExpectedExtension
            extensionOk = $extensionOk
            contentType = ($response.Headers["Content-Type"] -join ",")
            contentLength = $length
        }
    } catch {
        return [pscustomobject]@{
            name = $Name
            ok = $false
            url = $Uri
            error = (Protect-GreenVpnString -Value $_.Exception.Message)
        }
    }
}

function Get-PaidBetaStaticManifestCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    try {
        $value = Invoke-RestMethod -Uri $Uri -TimeoutSec $TimeoutSec -ErrorAction Stop
        $android = @($value.artifacts | Where-Object { ([string]$_.platform) -eq "android" }) | Select-Object -First 1
        $windows = @($value.artifacts | Where-Object { ([string]$_.platform) -eq "windows" }) | Select-Object -First 1
        $androidVersionOk = ([string]$value.appVersion) -eq $ExpectedTestAndroidVersion -and
            ([string]$android.version) -eq $ExpectedTestAndroidVersion
        $androidBuildOk = ([string]$android.buildNumber) -eq $ExpectedTestAndroidBuildNumber
        $androidSha256Ok = ([string]$android.sha256).ToUpperInvariant() -eq $ExpectedTestAndroidSha256.ToUpperInvariant()
        $androidSizeOk = [int64]$android.sizeBytes -gt 0
        $androidApplicationIdOk = ([string]$value.androidApplicationId) -eq $ExpectedTestAndroidApplicationId
        $androidAppLabelOk = ([string]$value.androidAppLabel) -eq $ExpectedTestAndroidAppLabel
        $isolationOk = ([string]$value.channel) -eq "paid-beta" -and
            $value.isolated -eq $true -and
            $value.productionPublished -eq $false
        $windowsVersionOk = ([string]$value.windowsAppVersion) -eq $ExpectedTestWindowsVersion -and
            ([string]$windows.version) -eq $ExpectedTestWindowsVersion
        $windowsBuildOk = ([string]$windows.buildNumber) -eq $ExpectedTestWindowsBuildNumber
        $windowsSha256Ok = ([string]$windows.sha256).ToUpperInvariant() -eq $ExpectedTestWindowsSha256.ToUpperInvariant()
        $windowsSizeOk = [int64]$windows.sizeBytes -gt 0
        return [pscustomobject]@{
            name = $Name
            ok = [bool](
                $androidVersionOk -and
                $androidBuildOk -and
                $androidSha256Ok -and
                $androidSizeOk -and
                $androidApplicationIdOk -and
                $androidAppLabelOk -and
                $isolationOk -and
                $windowsVersionOk -and
                $windowsBuildOk -and
                $windowsSha256Ok -and
                $windowsSizeOk
            )
            url = $Uri
            androidVersion = $value.appVersion
            expectedAndroidVersion = $ExpectedTestAndroidVersion
            androidVersionOk = $androidVersionOk
            androidBuildNumber = $android.buildNumber
            expectedAndroidBuildNumber = $ExpectedTestAndroidBuildNumber
            androidBuildOk = $androidBuildOk
            androidSha256 = $android.sha256
            expectedAndroidSha256 = $ExpectedTestAndroidSha256
            androidSha256Ok = $androidSha256Ok
            androidSizeBytes = $android.sizeBytes
            androidSizeOk = $androidSizeOk
            androidApplicationId = $value.androidApplicationId
            expectedAndroidApplicationId = $ExpectedTestAndroidApplicationId
            androidApplicationIdOk = $androidApplicationIdOk
            androidAppLabel = $value.androidAppLabel
            expectedAndroidAppLabel = $ExpectedTestAndroidAppLabel
            androidAppLabelOk = $androidAppLabelOk
            channel = $value.channel
            isolated = $value.isolated
            productionPublished = $value.productionPublished
            isolationOk = $isolationOk
            windowsVersion = $value.windowsAppVersion
            expectedWindowsVersion = $ExpectedTestWindowsVersion
            windowsVersionOk = $windowsVersionOk
            windowsBuildNumber = $windows.buildNumber
            expectedWindowsBuildNumber = $ExpectedTestWindowsBuildNumber
            windowsBuildOk = $windowsBuildOk
            windowsSha256 = $windows.sha256
            expectedWindowsSha256 = $ExpectedTestWindowsSha256
            windowsSha256Ok = $windowsSha256Ok
            windowsSizeBytes = $windows.sizeBytes
            windowsSizeOk = $windowsSizeOk
        }
    } catch {
        return [pscustomobject]@{
            name = $Name
            ok = $false
            url = $Uri
            error = (Protect-GreenVpnString -Value $_.Exception.Message)
        }
    }
}

$api = $ApiBaseUrl.TrimEnd("/")
$site = $SiteBaseUrl.TrimEnd("/")
$fallbackApi = $FallbackApiBaseUrl.TrimEnd("/")
$fallbackSite = $FallbackSiteBaseUrl.TrimEnd("/")

$manifestChecks = @(
    Get-UpdateManifestCheck `
        -Name "android-production-primary-manifest" `
        -Uri "$api/api/v1/updates/manifest?platform=android&channel=stable&currentVersion=0.0.0&clientId=ops-check-android-production-primary" `
        -ExpectedPlatform "android" `
        -ExpectedExtension ".apk" `
        -ExpectedChannel "stable" `
        -ExpectedVersion $ExpectedAndroidVersion `
        -ExpectedSha256 $ExpectedAndroidSha256 `
        -ExpectedRequired $ExpectedAndroidRequired
    Get-UpdateManifestCheck `
        -Name "android-production-fallback-manifest" `
        -Uri "$fallbackApi/api/v1/updates/manifest?platform=android&channel=stable&currentVersion=0.0.0&clientId=ops-check-android-production-fallback" `
        -ExpectedPlatform "android" `
        -ExpectedExtension ".apk" `
        -ExpectedChannel "stable" `
        -ExpectedVersion $ExpectedAndroidVersion `
        -ExpectedSha256 $ExpectedAndroidSha256 `
        -ExpectedRequired $ExpectedAndroidRequired
    Get-UpdateManifestCheck `
        -Name "android-test-primary-manifest" `
        -Uri "$api/paid-beta-api/api/v1/updates/manifest?platform=android&channel=paid-beta&currentVersion=0.0.0&clientId=ops-check-android-test-primary" `
        -ExpectedPlatform "android" `
        -ExpectedExtension ".apk" `
        -ExpectedChannel "paid-beta" `
        -ExpectedVersion $ExpectedTestAndroidVersion `
        -ExpectedSha256 $ExpectedTestAndroidSha256 `
        -ExpectedRequired $ExpectedTestAndroidRequired
    Get-UpdateManifestCheck `
        -Name "android-test-fallback-manifest" `
        -Uri "$fallbackApi/paid-beta-api/api/v1/updates/manifest?platform=android&channel=paid-beta&currentVersion=0.0.0&clientId=ops-check-android-test-fallback" `
        -ExpectedPlatform "android" `
        -ExpectedExtension ".apk" `
        -ExpectedChannel "paid-beta" `
        -ExpectedVersion $ExpectedTestAndroidVersion `
        -ExpectedSha256 $ExpectedTestAndroidSha256 `
        -ExpectedRequired $ExpectedTestAndroidRequired
    Get-UpdateManifestCheck `
        -Name "windows-production-primary-manifest" `
        -Uri "$api/api/v1/updates/manifest?platform=windows&channel=stable&currentVersion=0.0.0&clientId=ops-check-windows-production-primary" `
        -ExpectedPlatform "windows" `
        -ExpectedExtension ".exe" `
        -ExpectedChannel "stable" `
        -ExpectedVersion $ExpectedWindowsVersion `
        -ExpectedSha256 $ExpectedWindowsSha256 `
        -ExpectedRequired $ExpectedWindowsRequired
    Get-UpdateManifestCheck `
        -Name "windows-production-fallback-manifest" `
        -Uri "$fallbackApi/api/v1/updates/manifest?platform=windows&channel=stable&currentVersion=0.0.0&clientId=ops-check-windows-production-fallback" `
        -ExpectedPlatform "windows" `
        -ExpectedExtension ".exe" `
        -ExpectedChannel "stable" `
        -ExpectedVersion $ExpectedWindowsVersion `
        -ExpectedSha256 $ExpectedWindowsSha256 `
        -ExpectedRequired $ExpectedWindowsRequired
    Get-UpdateManifestCheck `
        -Name "windows-public-product-primary-alias-manifest" `
        -Uri "$api/api/v1/updates/manifest?platform=windows&channel=public-product&currentVersion=0.0.0&clientId=ops-check-windows-public-product-primary" `
        -ExpectedPlatform "windows" `
        -ExpectedExtension ".exe" `
        -ExpectedChannel "stable" `
        -ExpectedVersion $ExpectedWindowsVersion `
        -ExpectedSha256 $ExpectedWindowsSha256 `
        -ExpectedRequired $ExpectedWindowsRequired
    Get-UpdateManifestCheck `
        -Name "windows-public-product-fallback-alias-manifest" `
        -Uri "$fallbackApi/api/v1/updates/manifest?platform=windows&channel=public-product&currentVersion=0.0.0&clientId=ops-check-windows-public-product-fallback" `
        -ExpectedPlatform "windows" `
        -ExpectedExtension ".exe" `
        -ExpectedChannel "stable" `
        -ExpectedVersion $ExpectedWindowsVersion `
        -ExpectedSha256 $ExpectedWindowsSha256 `
        -ExpectedRequired $ExpectedWindowsRequired
    Get-UpdateManifestCheck `
        -Name "windows-test-primary-manifest" `
        -Uri "$api/paid-beta-api/api/v1/updates/manifest?platform=windows&channel=paid-beta&currentVersion=0.0.0&clientId=ops-check-windows-test-primary" `
        -ExpectedPlatform "windows" `
        -ExpectedExtension ".exe" `
        -ExpectedChannel "paid-beta" `
        -ExpectedVersion $ExpectedTestWindowsVersion `
        -ExpectedSha256 $ExpectedTestWindowsSha256 `
        -ExpectedRequired $ExpectedTestWindowsRequired
    Get-UpdateManifestCheck `
        -Name "windows-test-fallback-manifest" `
        -Uri "$fallbackApi/paid-beta-api/api/v1/updates/manifest?platform=windows&channel=paid-beta&currentVersion=0.0.0&clientId=ops-check-windows-test-fallback" `
        -ExpectedPlatform "windows" `
        -ExpectedExtension ".exe" `
        -ExpectedChannel "paid-beta" `
        -ExpectedVersion $ExpectedTestWindowsVersion `
        -ExpectedSha256 $ExpectedTestWindowsSha256 `
        -ExpectedRequired $ExpectedTestWindowsRequired
)

$downloadChecks = @(
    Get-DownloadHeadCheck -Name "android-production-primary-apk" -Uri "$site/downloads/GreenVPN_Android.apk" -ExpectedExtension ".apk"
    Get-DownloadHeadCheck -Name "android-production-fallback-apk" -Uri "$fallbackSite/downloads/GreenVPN_Android.apk" -ExpectedExtension ".apk"
    Get-DownloadHeadCheck -Name "android-test-primary-apk" -Uri "$site/paid-beta/downloads/GreenVPN_Android.apk" -ExpectedExtension ".apk"
    Get-DownloadHeadCheck -Name "android-test-fallback-apk" -Uri "$fallbackSite/paid-beta/downloads/GreenVPN_Android.apk" -ExpectedExtension ".apk"
    Get-DownloadHeadCheck -Name "windows-production-primary-installer" -Uri "$site/downloads/GreenVPN_Setup.exe" -ExpectedExtension ".exe"
    Get-DownloadHeadCheck -Name "windows-production-fallback-installer" -Uri "$fallbackSite/downloads/GreenVPN_Setup.exe" -ExpectedExtension ".exe"
    Get-DownloadHeadCheck -Name "windows-test-primary-installer" -Uri "$site/paid-beta/downloads/GreenVPN_Setup.exe" -ExpectedExtension ".exe"
    Get-DownloadHeadCheck -Name "windows-test-fallback-installer" -Uri "$fallbackSite/paid-beta/downloads/GreenVPN_Setup.exe" -ExpectedExtension ".exe"
)

$staticManifestChecks = @(
    Get-PaidBetaStaticManifestCheck -Name "android-test-primary-static-manifest" -Uri "$site/paid-beta/downloads/manifest.json"
    Get-PaidBetaStaticManifestCheck -Name "android-test-fallback-static-manifest" -Uri "$fallbackSite/paid-beta/downloads/manifest.json"
)

$allChecks = @($manifestChecks + $staticManifestChecks + $downloadChecks)
$result = [pscustomobject]@{
    ok = -not [bool](@($allChecks | Where-Object { -not $_.ok }).Count)
    apiBaseUrl = $api
    siteBaseUrl = $site
    fallbackApiBaseUrl = $fallbackApi
    fallbackSiteBaseUrl = $fallbackSite
    manifests = $manifestChecks
    staticManifests = $staticManifestChecks
    downloads = $downloadChecks
}

Write-GreenVpnJson -InputObject $result
if (-not $result.ok) {
    exit 1
}
