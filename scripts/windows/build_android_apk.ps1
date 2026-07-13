param(
    [ValidateSet("debug", "release", "both")]
    [string]$Mode = "both",

    [switch]$EnableYandexRewardedAds,
    [switch]$EnableAwg2Preview,
    [switch]$EnableHysteria2Preview,
    [switch]$EnableVlessRealityPreview,
    [switch]$EnableNaiveHttpsPreview,
    [switch]$EnableDnsttPreview,
    [string]$Awg2PreviewApplicationId = "pro.greenvpn.app.transportpreview",
    [string]$Awg2PreviewAppLabel = "Green VPN Transport Preview",
    [string]$Awg2PreviewAppVersion = "0.2.45-vless-transport-preview.1",
    [string]$Awg2PreviewBuildName = "0.2.45",
    [string]$Awg2PreviewBuildNumber = "2026071201",
    [string]$Awg2PreviewApiBaseUrl = "https://api.greenvpn.pro/paid-beta-api",
    [string]$Awg2PreviewApiFallbackBaseUrls = "https://176-113-81-35.sslip.io/paid-beta-api",
    [switch]$DeployPreview,
    [string]$PreviewApkName = ""
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $repo

$androidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$jdkDir = "C:\Program Files\Android\openjdk\jdk-21.0.8"

if (-not (Test-Path $androidSdk)) {
    throw "Android SDK not found: $androidSdk"
}
if (-not (Test-Path $jdkDir)) {
    throw "JDK not found: $jdkDir"
}

$env:ANDROID_HOME = $androidSdk
$env:ANDROID_SDK_ROOT = $androidSdk
$env:JAVA_HOME = $jdkDir
$env:Path = "$jdkDir\bin;$androidSdk\platform-tools;$androidSdk\cmdline-tools\latest\bin;$env:Path"
$env:GREENVPN_ANDROID_AWG2_PREVIEW_ENABLED = if ($EnableAwg2Preview) { 'true' } else { 'false' }
$env:GREENVPN_ANDROID_HYSTERIA2_PREVIEW_ENABLED = if ($EnableHysteria2Preview) { 'true' } else { 'false' }
$env:GREENVPN_ANDROID_VLESS_REALITY_PREVIEW_ENABLED = if ($EnableVlessRealityPreview) { 'true' } else { 'false' }
$env:GREENVPN_ANDROID_NAIVE_HTTPS_PREVIEW_ENABLED = if ($EnableNaiveHttpsPreview) { 'true' } else { 'false' }
$env:GREENVPN_ANDROID_DNSTT_PREVIEW_ENABLED = if ($EnableDnsttPreview) { 'true' } else { 'false' }
if ($EnableAwg2Preview -or $EnableHysteria2Preview -or $EnableVlessRealityPreview -or $EnableNaiveHttpsPreview -or $EnableDnsttPreview) {
    if (-not $Awg2PreviewApiBaseUrl.Contains('/paid-beta-api')) {
        throw 'AWG2 preview primary API must use /paid-beta-api.'
    }
    if (-not $Awg2PreviewApiFallbackBaseUrls.Contains('/paid-beta-api')) {
        throw 'AWG2 preview fallback API must use /paid-beta-api.'
    }
    if ($Awg2PreviewApplicationId -eq 'pro.greenvpn.app') {
        throw 'AWG2 preview must not replace the production Android package.'
    }
    $env:GREENVPN_ANDROID_APPLICATION_ID = $Awg2PreviewApplicationId
    $env:GREENVPN_ANDROID_APP_LABEL = $Awg2PreviewAppLabel
    $env:GREENVPN_ANDROID_API_BASE_URL = $Awg2PreviewApiBaseUrl
    $env:GREENVPN_ANDROID_API_FALLBACK_BASE_URLS = $Awg2PreviewApiFallbackBaseUrls
    $env:GREENVPN_ANDROID_RELEASE_CHANNEL = 'paid-beta'
    $env:GREENVPN_ANDROID_CLIENT_MARKER = 'green-vpn-paid-beta-v1'
    $env:GREENVPN_APP_VERSION = $Awg2PreviewAppVersion
}
if ($EnableAwg2Preview) {
    & (Join-Path $PSScriptRoot 'prepare_android_awg2_preview.ps1')
}
if ($EnableHysteria2Preview) {
    & (Join-Path $PSScriptRoot 'prepare_android_hysteria2_preview.ps1')
}
if ($EnableVlessRealityPreview) {
    if (-not $EnableHysteria2Preview) {
        & (Join-Path $PSScriptRoot 'prepare_android_hysteria2_preview.ps1')
    }
    & (Join-Path $PSScriptRoot 'prepare_android_vless_reality_preview.ps1')
}
if ($EnableNaiveHttpsPreview) {
    if (-not $EnableHysteria2Preview -and -not $EnableVlessRealityPreview) {
        & (Join-Path $PSScriptRoot 'prepare_android_hysteria2_preview.ps1')
    }
    & (Join-Path $PSScriptRoot 'prepare_android_naive_https_preview.ps1')
}
if ($EnableDnsttPreview) {
    if (-not $EnableHysteria2Preview -and -not $EnableVlessRealityPreview -and -not $EnableNaiveHttpsPreview) {
        & (Join-Path $PSScriptRoot 'prepare_android_hysteria2_preview.ps1')
    }
    & (Join-Path $PSScriptRoot 'prepare_android_dnstt_preview.ps1')
}

flutter config --android-sdk $androidSdk | Out-Host
flutter config --jdk-dir $jdkDir | Out-Host

try {
    flutter config --no-enable-windows-desktop --no-enable-linux-desktop --no-enable-macos-desktop | Out-Host
    flutter pub get | Out-Host
}
finally {
    flutter config --enable-windows-desktop --enable-linux-desktop --enable-macos-desktop | Out-Host
}

flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings | Out-Host
flutter test --no-pub | Out-Host

$builds = @()
$releaseAppVersion = "0.2.44"
$releaseBuildName = "0.2.44"
$releaseBuildNumber = "2026070504"
if ($Mode -eq "debug" -or $Mode -eq "both") {
    $debugArgs = @('build', 'apk', '--debug', '--no-pub')
    if ($EnableAwg2Preview) {
        $debugArgs += '--dart-define=GREENVPN_AWG2_PREVIEW_ENABLED=true'
        $debugArgs += "--dart-define=GREENVPN_APP_VERSION=$Awg2PreviewAppVersion"
        $debugArgs += '--dart-define=GREENVPN_PAID_BETA_BUILD=true'
        $debugArgs += '--dart-define=GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1'
        $debugArgs += '--dart-define=GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false'
        $debugArgs += '--dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=false'
        $debugArgs += "--dart-define=BLUEVPN_API_BASE_URL=$Awg2PreviewApiBaseUrl"
        $debugArgs += "--dart-define=BLUEVPN_API_BASE_URLS=$Awg2PreviewApiFallbackBaseUrls"
        $debugArgs += "--build-name=$Awg2PreviewBuildName"
        $debugArgs += "--build-number=$Awg2PreviewBuildNumber"
    }
    if ($EnableHysteria2Preview) {
        $debugArgs += '--dart-define=GREENVPN_HYSTERIA2_PREVIEW_ENABLED=true'
        if (-not $EnableAwg2Preview) {
            $debugArgs += "--dart-define=GREENVPN_APP_VERSION=$Awg2PreviewAppVersion"
            $debugArgs += '--dart-define=GREENVPN_PAID_BETA_BUILD=true'
            $debugArgs += '--dart-define=GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1'
            $debugArgs += '--dart-define=GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false'
            $debugArgs += '--dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=false'
            $debugArgs += "--dart-define=BLUEVPN_API_BASE_URL=$Awg2PreviewApiBaseUrl"
            $debugArgs += "--dart-define=BLUEVPN_API_BASE_URLS=$Awg2PreviewApiFallbackBaseUrls"
            $debugArgs += "--build-name=$Awg2PreviewBuildName"
            $debugArgs += "--build-number=$Awg2PreviewBuildNumber"
        }
    }
    if ($EnableVlessRealityPreview) {
        $debugArgs += '--dart-define=GREENVPN_VLESS_REALITY_PREVIEW_ENABLED=true'
        if (-not $EnableAwg2Preview -and -not $EnableHysteria2Preview) {
            $debugArgs += "--dart-define=GREENVPN_APP_VERSION=$Awg2PreviewAppVersion"
            $debugArgs += '--dart-define=GREENVPN_PAID_BETA_BUILD=true'
            $debugArgs += '--dart-define=GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1'
            $debugArgs += '--dart-define=GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false'
            $debugArgs += '--dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=false'
            $debugArgs += "--dart-define=BLUEVPN_API_BASE_URL=$Awg2PreviewApiBaseUrl"
            $debugArgs += "--dart-define=BLUEVPN_API_BASE_URLS=$Awg2PreviewApiFallbackBaseUrls"
            $debugArgs += "--build-name=$Awg2PreviewBuildName"
            $debugArgs += "--build-number=$Awg2PreviewBuildNumber"
        }
    }
    if ($EnableNaiveHttpsPreview) {
        $debugArgs += '--dart-define=GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED=true'
        if (-not $EnableAwg2Preview -and -not $EnableHysteria2Preview -and -not $EnableVlessRealityPreview) {
            $debugArgs += "--dart-define=GREENVPN_APP_VERSION=$Awg2PreviewAppVersion"
            $debugArgs += '--dart-define=GREENVPN_PAID_BETA_BUILD=true'
            $debugArgs += '--dart-define=GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1'
            $debugArgs += '--dart-define=GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false'
            $debugArgs += '--dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=false'
            $debugArgs += "--dart-define=BLUEVPN_API_BASE_URL=$Awg2PreviewApiBaseUrl"
            $debugArgs += "--dart-define=BLUEVPN_API_BASE_URLS=$Awg2PreviewApiFallbackBaseUrls"
            $debugArgs += "--build-name=$Awg2PreviewBuildName"
            $debugArgs += "--build-number=$Awg2PreviewBuildNumber"
        }
    }
    if ($EnableDnsttPreview) {
        $debugArgs += '--dart-define=GREENVPN_DNSTT_PREVIEW_ENABLED=true'
        if (-not $EnableAwg2Preview -and -not $EnableHysteria2Preview -and -not $EnableVlessRealityPreview -and -not $EnableNaiveHttpsPreview) {
            $debugArgs += "--dart-define=GREENVPN_APP_VERSION=$Awg2PreviewAppVersion"
            $debugArgs += '--dart-define=GREENVPN_PAID_BETA_BUILD=true'
            $debugArgs += '--dart-define=GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1'
            $debugArgs += '--dart-define=GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false'
            $debugArgs += '--dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=false'
            $debugArgs += "--dart-define=BLUEVPN_API_BASE_URL=$Awg2PreviewApiBaseUrl"
            $debugArgs += "--dart-define=BLUEVPN_API_BASE_URLS=$Awg2PreviewApiFallbackBaseUrls"
            $debugArgs += "--build-name=$Awg2PreviewBuildName"
            $debugArgs += "--build-number=$Awg2PreviewBuildNumber"
        }
    }
    flutter @debugArgs | Out-Host
    $builds += "build\app\outputs\flutter-apk\app-debug.apk"
}
if ($Mode -eq "release" -or $Mode -eq "both") {
    $releaseArgs = @("build", "apk", "--release", "--no-pub")
    $releaseArgs += "--dart-define=GREENVPN_APP_VERSION=$releaseAppVersion"
    $releaseArgs += "--build-name=$releaseBuildName"
    $releaseArgs += "--build-number=$releaseBuildNumber"
    if ($EnableYandexRewardedAds -or $EnableAwg2Preview -or $EnableHysteria2Preview -or $EnableVlessRealityPreview -or $EnableNaiveHttpsPreview -or $EnableDnsttPreview -or $DeployPreview) {
        $releaseAppVersion = $Awg2PreviewAppVersion
        $releaseBuildName = $Awg2PreviewBuildName
        $releaseBuildNumber = $Awg2PreviewBuildNumber
        $releaseArgs[4] = "--dart-define=GREENVPN_APP_VERSION=$releaseAppVersion"
        $releaseArgs[5] = "--build-name=$releaseBuildName"
        $releaseArgs[6] = "--build-number=$releaseBuildNumber"
        $releaseArgs += "--dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=$($EnableYandexRewardedAds.ToString().ToLowerInvariant())"
        $releaseArgs += "--dart-define=GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false"
        $releaseArgs += "--dart-define=BLUEVPN_API_BASE_URLS=https://176-113-81-35.sslip.io"
    }
    if ($EnableAwg2Preview) {
        $releaseArgs += '--dart-define=GREENVPN_AWG2_PREVIEW_ENABLED=true'
        $releaseArgs += '--dart-define=GREENVPN_PAID_BETA_BUILD=true'
        $releaseArgs += '--dart-define=GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1'
        $releaseArgs += "--dart-define=BLUEVPN_API_BASE_URL=$Awg2PreviewApiBaseUrl"
        $releaseArgs += "--dart-define=BLUEVPN_API_BASE_URLS=$Awg2PreviewApiFallbackBaseUrls"
    }
    if ($EnableHysteria2Preview) {
        $releaseArgs += '--dart-define=GREENVPN_HYSTERIA2_PREVIEW_ENABLED=true'
        if (-not $EnableAwg2Preview) {
            $releaseArgs += '--dart-define=GREENVPN_PAID_BETA_BUILD=true'
            $releaseArgs += '--dart-define=GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1'
            $releaseArgs += "--dart-define=BLUEVPN_API_BASE_URL=$Awg2PreviewApiBaseUrl"
            $releaseArgs += "--dart-define=BLUEVPN_API_BASE_URLS=$Awg2PreviewApiFallbackBaseUrls"
        }
    }
    if ($EnableVlessRealityPreview) {
        $releaseArgs += '--dart-define=GREENVPN_VLESS_REALITY_PREVIEW_ENABLED=true'
        if (-not $EnableAwg2Preview -and -not $EnableHysteria2Preview) {
            $releaseArgs += '--dart-define=GREENVPN_PAID_BETA_BUILD=true'
            $releaseArgs += '--dart-define=GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1'
            $releaseArgs += "--dart-define=BLUEVPN_API_BASE_URL=$Awg2PreviewApiBaseUrl"
            $releaseArgs += "--dart-define=BLUEVPN_API_BASE_URLS=$Awg2PreviewApiFallbackBaseUrls"
        }
    }
    if ($EnableNaiveHttpsPreview) {
        $releaseArgs += '--dart-define=GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED=true'
        if (-not $EnableAwg2Preview -and -not $EnableHysteria2Preview -and -not $EnableVlessRealityPreview) {
            $releaseArgs += '--dart-define=GREENVPN_PAID_BETA_BUILD=true'
            $releaseArgs += '--dart-define=GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1'
            $releaseArgs += "--dart-define=BLUEVPN_API_BASE_URL=$Awg2PreviewApiBaseUrl"
            $releaseArgs += "--dart-define=BLUEVPN_API_BASE_URLS=$Awg2PreviewApiFallbackBaseUrls"
        }
    }
    if ($EnableDnsttPreview) {
        $releaseArgs += '--dart-define=GREENVPN_DNSTT_PREVIEW_ENABLED=true'
        if (-not $EnableAwg2Preview -and -not $EnableHysteria2Preview -and -not $EnableVlessRealityPreview -and -not $EnableNaiveHttpsPreview) {
            $releaseArgs += '--dart-define=GREENVPN_PAID_BETA_BUILD=true'
            $releaseArgs += '--dart-define=GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1'
            $releaseArgs += "--dart-define=BLUEVPN_API_BASE_URL=$Awg2PreviewApiBaseUrl"
            $releaseArgs += "--dart-define=BLUEVPN_API_BASE_URLS=$Awg2PreviewApiFallbackBaseUrls"
        }
    }
    $previousGreenVpnAppVersion = $env:GREENVPN_APP_VERSION
    try {
        $env:GREENVPN_APP_VERSION = $releaseAppVersion
        flutter @releaseArgs | Out-Host
    }
    finally {
        if ($null -eq $previousGreenVpnAppVersion) {
            Remove-Item Env:\GREENVPN_APP_VERSION -ErrorAction SilentlyContinue
        } else {
            $env:GREENVPN_APP_VERSION = $previousGreenVpnAppVersion
        }
    }
    $builds += "build\app\outputs\flutter-apk\app-release.apk"
}

$apksigner = Join-Path $androidSdk "build-tools\36.0.0\apksigner.bat"
$expectedSignerPath = Join-Path $repo "android\release_signer_sha256.txt"
$expectedReleaseSigner = if ($env:GREENVPN_EXPECTED_ANDROID_SIGNER_SHA256) {
    $env:GREENVPN_EXPECTED_ANDROID_SIGNER_SHA256.Trim().ToLowerInvariant()
} elseif (Test-Path -LiteralPath $expectedSignerPath -PathType Leaf) {
    (Get-Content -LiteralPath $expectedSignerPath -Raw).Trim().ToLowerInvariant()
} else {
    ''
}
if (-not (Test-Path -LiteralPath $apksigner -PathType Leaf)) {
    throw "apksigner is required but was not found: $apksigner"
}
if (($Mode -eq 'release' -or $Mode -eq 'both') -and $expectedReleaseSigner -notmatch '^[0-9a-f]{64}$') {
    throw 'Expected Android release signer SHA-256 is missing or invalid.'
}
foreach ($apk in $builds) {
    $item = Get-Item $apk
    $hash = Get-FileHash -Algorithm SHA256 $item.FullName
    Write-Host ""
    Write-Host "APK: $($item.FullName)"
    Write-Host "Size: $($item.Length) bytes"
    Write-Host "SHA256: $($hash.Hash)"
    & $apksigner verify --verbose $item.FullName | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "APK signature verification failed: $($item.FullName)"
    }
    if ($item.Name -eq 'app-release.apk') {
        $certificateOutput = & $apksigner verify --print-certs $item.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to inspect APK signer: $($item.FullName)"
        }
        $certificateLine = $certificateOutput |
            Select-String -Pattern 'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})' |
            Select-Object -First 1
        if (-not $certificateLine) {
            throw "APK signer SHA-256 was not reported: $($item.FullName)"
        }
        $actualSigner = $certificateLine.Matches[0].Groups[1].Value.ToLowerInvariant()
        if ($actualSigner -ne $expectedReleaseSigner) {
            throw "Unexpected Android release signer for $($item.FullName)."
        }
        Write-Host "Signer SHA256: $actualSigner"
    }
}

if ($DeployPreview) {
    if ($Mode -eq "debug") {
        throw "DeployPreview requires a release build. Use -Mode release or -Mode both."
    }

    $releaseApk = Get-Item "build\app\outputs\flutter-apk\app-release.apk"
    $deployApk = $releaseApk.FullName

    if ([string]::IsNullOrWhiteSpace($PreviewApkName)) {
        if (-not [string]::IsNullOrWhiteSpace($releaseBuildName) -and -not [string]::IsNullOrWhiteSpace($releaseBuildNumber)) {
            $version = "${releaseBuildName}_${releaseBuildNumber}"
        } else {
            $versionLine = Select-String -LiteralPath "pubspec.yaml" -Pattern "^version:\s*(.+)$" | Select-Object -First 1
            $version = "preview"
            if ($versionLine) {
                $version = $versionLine.Matches[0].Groups[1].Value.Trim() -replace "\+", "_" -replace "[^A-Za-z0-9_.-]", "_"
            }
        }
        $PreviewApkName = "GreenVPN_Android_${version}_preview.apk"
    }

    $buildsDir = "C:\BlueVPN_Builds"
    New-Item -ItemType Directory -Force -Path $buildsDir | Out-Null
    $deployApk = Join-Path $buildsDir $PreviewApkName
    Copy-Item -LiteralPath $releaseApk.FullName -Destination $deployApk -Force

    & (Join-Path $PSScriptRoot "deploy_android_preview_apk.ps1") -ApkPath $deployApk
}
