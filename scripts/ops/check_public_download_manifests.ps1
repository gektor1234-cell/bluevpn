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
    [string]$ExpectedAndroidVersion = "0.3.7",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedAndroidSha256 = "CAE9680C1BC0E59AD2046BEAC46779D782AD5F2D542EA6BB5847DBDBDDD96431",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestAndroidSha256 = "910D7C8D03E224484050EFB4AE845C0B2DD6FC592B85B7A3FF8B1475DE21E5C5",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedAndroidBuildNumber = "2026071902",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedWindowsVersion = "0.3.6",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedWindowsSha256 = "0A9297141199C3F9C2F971FF2B98B3C48B9CB3C4D939249C4B1DF6AA52F063FA",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestWindowsVersion = "0.3.6-paid-beta.1808",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestWindowsSha256 = "19BCCFB0866CAC69F78B9F6A3BFBC8C9A0AFE293876D95E3091179FEEBAB2AF4",

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
        $versionOk = ([string]$value.appVersion) -eq $ExpectedAndroidVersion -and
            ([string]$android.version) -eq $ExpectedAndroidVersion
        $buildOk = ([string]$android.buildNumber) -eq $ExpectedAndroidBuildNumber
        $sha256Ok = ([string]$android.sha256).ToUpperInvariant() -eq $ExpectedTestAndroidSha256.ToUpperInvariant()
        $sizeOk = [int64]$android.sizeBytes -gt 0
        return [pscustomobject]@{
            name = $Name
            ok = [bool]($versionOk -and $buildOk -and $sha256Ok -and $sizeOk)
            url = $Uri
            appVersion = $value.appVersion
            expectedVersion = $ExpectedAndroidVersion
            versionOk = $versionOk
            buildNumber = $android.buildNumber
            expectedBuildNumber = $ExpectedAndroidBuildNumber
            buildOk = $buildOk
            sha256 = $android.sha256
            expectedSha256 = $ExpectedTestAndroidSha256
            sha256Ok = $sha256Ok
            sizeBytes = $android.sizeBytes
            sizeOk = $sizeOk
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
        -ExpectedRequired $true
    Get-UpdateManifestCheck `
        -Name "android-production-fallback-manifest" `
        -Uri "$fallbackApi/api/v1/updates/manifest?platform=android&channel=stable&currentVersion=0.0.0&clientId=ops-check-android-production-fallback" `
        -ExpectedPlatform "android" `
        -ExpectedExtension ".apk" `
        -ExpectedChannel "stable" `
        -ExpectedVersion $ExpectedAndroidVersion `
        -ExpectedSha256 $ExpectedAndroidSha256 `
        -ExpectedRequired $true
    Get-UpdateManifestCheck `
        -Name "android-test-primary-manifest" `
        -Uri "$api/paid-beta-api/api/v1/updates/manifest?platform=android&channel=paid-beta&currentVersion=0.0.0&clientId=ops-check-android-test-primary" `
        -ExpectedPlatform "android" `
        -ExpectedExtension ".apk" `
        -ExpectedChannel "paid-beta" `
        -ExpectedVersion $ExpectedAndroidVersion `
        -ExpectedSha256 $ExpectedTestAndroidSha256 `
        -ExpectedRequired $true
    Get-UpdateManifestCheck `
        -Name "android-test-fallback-manifest" `
        -Uri "$fallbackApi/paid-beta-api/api/v1/updates/manifest?platform=android&channel=paid-beta&currentVersion=0.0.0&clientId=ops-check-android-test-fallback" `
        -ExpectedPlatform "android" `
        -ExpectedExtension ".apk" `
        -ExpectedChannel "paid-beta" `
        -ExpectedVersion $ExpectedAndroidVersion `
        -ExpectedSha256 $ExpectedTestAndroidSha256 `
        -ExpectedRequired $true
    Get-UpdateManifestCheck `
        -Name "windows-production-primary-manifest" `
        -Uri "$api/api/v1/updates/manifest?platform=windows&channel=stable&currentVersion=0.0.0&clientId=ops-check-windows-production-primary" `
        -ExpectedPlatform "windows" `
        -ExpectedExtension ".exe" `
        -ExpectedChannel "stable" `
        -ExpectedVersion $ExpectedWindowsVersion `
        -ExpectedSha256 $ExpectedWindowsSha256 `
        -ExpectedRequired $true
    Get-UpdateManifestCheck `
        -Name "windows-production-fallback-manifest" `
        -Uri "$fallbackApi/api/v1/updates/manifest?platform=windows&channel=stable&currentVersion=0.0.0&clientId=ops-check-windows-production-fallback" `
        -ExpectedPlatform "windows" `
        -ExpectedExtension ".exe" `
        -ExpectedChannel "stable" `
        -ExpectedVersion $ExpectedWindowsVersion `
        -ExpectedSha256 $ExpectedWindowsSha256 `
        -ExpectedRequired $true
    Get-UpdateManifestCheck `
        -Name "windows-test-primary-manifest" `
        -Uri "$api/paid-beta-api/api/v1/updates/manifest?platform=windows&channel=paid-beta&currentVersion=0.0.0&clientId=ops-check-windows-test-primary" `
        -ExpectedPlatform "windows" `
        -ExpectedExtension ".exe" `
        -ExpectedChannel "paid-beta" `
        -ExpectedVersion $ExpectedTestWindowsVersion `
        -ExpectedSha256 $ExpectedTestWindowsSha256 `
        -ExpectedRequired $false
    Get-UpdateManifestCheck `
        -Name "windows-test-fallback-manifest" `
        -Uri "$fallbackApi/paid-beta-api/api/v1/updates/manifest?platform=windows&channel=paid-beta&currentVersion=0.0.0&clientId=ops-check-windows-test-fallback" `
        -ExpectedPlatform "windows" `
        -ExpectedExtension ".exe" `
        -ExpectedChannel "paid-beta" `
        -ExpectedVersion $ExpectedTestWindowsVersion `
        -ExpectedSha256 $ExpectedTestWindowsSha256 `
        -ExpectedRequired $false
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

Write-GreenVpnJson -InputObject ([pscustomobject]@{
    ok = -not [bool](@($allChecks | Where-Object { -not $_.ok }).Count)
    apiBaseUrl = $api
    siteBaseUrl = $site
    fallbackApiBaseUrl = $fallbackApi
    fallbackSiteBaseUrl = $fallbackSite
    manifests = $manifestChecks
    staticManifests = $staticManifestChecks
    downloads = $downloadChecks
})
