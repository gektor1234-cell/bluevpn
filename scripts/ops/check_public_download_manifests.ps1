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
    [string]$ExpectedAndroidVersion = "0.3.2",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedAndroidSha256 = "6C881410C2B8001BD3BCDA954526B86F8BE77400EE452B11D38A77362E9E936A",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestAndroidSha256 = "7313A781EC7B1CF834E0C5150FDF055FE5E7DE4B97891ACE419F5056109A0042",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedWindowsVersion = "0.2.39-windows-clean-server-ui",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedWindowsSha256 = "0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestWindowsVersion = "0.3.0-paid-beta.11",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedTestWindowsSha256 = "ECA801FBCFED9A08CD5470E6BDC9F2FC327019D6C3DE61D50F7AECC69668FE32",

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

$allChecks = @($manifestChecks + $downloadChecks)

Write-GreenVpnJson -InputObject ([pscustomobject]@{
    ok = -not [bool](@($allChecks | Where-Object { -not $_.ok }).Count)
    apiBaseUrl = $api
    siteBaseUrl = $site
    fallbackApiBaseUrl = $fallbackApi
    fallbackSiteBaseUrl = $fallbackSite
    manifests = $manifestChecks
    downloads = $downloadChecks
})
