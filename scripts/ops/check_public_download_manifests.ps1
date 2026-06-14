param(
    [Parameter(Mandatory = $false)]
    [string]$ApiBaseUrl = "https://api.greenvpn.pro",

    [Parameter(Mandatory = $false)]
    [string]$SiteBaseUrl = "https://greenvpn.pro",

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
        [string]$ExpectedExtension
    )

    try {
        $response = Invoke-RestMethod -Uri $Uri -TimeoutSec $TimeoutSec -ErrorAction Stop
        $manifest = $response.manifest
        $downloadUrl = [string]$manifest.downloadUrl
        $extensionOk = $downloadUrl.ToLowerInvariant().EndsWith($ExpectedExtension.ToLowerInvariant())
        $platformOk = ([string]$manifest.platform) -eq $ExpectedPlatform
        return [pscustomobject]@{
            name = $Name
            ok = [bool]($response.ok -and $platformOk -and $extensionOk -and $manifest.fileReady)
            platform = $manifest.platform
            expectedPlatform = $ExpectedPlatform
            platformOk = $platformOk
            channel = $manifest.channel
            latestVersion = $manifest.latestVersion
            updateAvailable = $manifest.updateAvailable
            required = $manifest.required
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

$manifestChecks = @(
    Get-UpdateManifestCheck `
        -Name "android-stable-manifest" `
        -Uri "$api/api/v1/updates/manifest?platform=android&channel=stable&currentVersion=0.2.14-trial-only-routeprobe-android-diagnostics&clientId=ops-check-android-stable" `
        -ExpectedPlatform "android" `
        -ExpectedExtension ".apk"
    Get-UpdateManifestCheck `
        -Name "android-preview-manifest" `
        -Uri "$api/api/v1/updates/manifest?platform=android&channel=preview&currentVersion=0.2.14-adgate-preview-routeprobe-android-diagnostics&clientId=ops-check-android-preview" `
        -ExpectedPlatform "android" `
        -ExpectedExtension ".apk"
    Get-UpdateManifestCheck `
        -Name "windows-stable-manifest" `
        -Uri "$api/api/v1/updates/manifest?platform=windows&channel=stable&currentVersion=0.2.10-trial-only-routeprobe&clientId=ops-check-windows-stable" `
        -ExpectedPlatform "windows" `
        -ExpectedExtension ".exe"
    Get-UpdateManifestCheck `
        -Name "legacy-android-windows-endpoint" `
        -Uri "$api/api/v1/updates/windows?currentVersion=0.2.14-adgate-preview-routeprobe-android-diagnostics&clientId=ops-check-legacy-android" `
        -ExpectedPlatform "android" `
        -ExpectedExtension ".apk"
)

$downloadChecks = @(
    Get-DownloadHeadCheck -Name "android-stable-apk" -Uri "$site/downloads/GreenVPN_Android.apk" -ExpectedExtension ".apk"
    Get-DownloadHeadCheck -Name "android-preview-apk" -Uri "$site/downloads/GreenVPN_Android_preview_latest.apk" -ExpectedExtension ".apk"
    Get-DownloadHeadCheck -Name "windows-stable-installer" -Uri "$site/downloads/GreenVPN_Setup.exe" -ExpectedExtension ".exe"
    Get-DownloadHeadCheck -Name "windows-preview-installer" -Uri "$site/downloads/GreenVPN_Setup_0.2.10_adgate_preview_routeprobe.exe" -ExpectedExtension ".exe"
)

$allChecks = @($manifestChecks + $downloadChecks)

Write-GreenVpnJson -InputObject ([pscustomobject]@{
    ok = -not [bool](@($allChecks | Where-Object { -not $_.ok }).Count)
    apiBaseUrl = $api
    siteBaseUrl = $site
    manifests = $manifestChecks
    downloads = $downloadChecks
})
