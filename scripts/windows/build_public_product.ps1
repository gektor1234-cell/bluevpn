param(
    [ValidateSet("android", "windows", "both")]
    [string]$Mode = "both",
    [string]$AppVersion = "0.4.12",
    [string]$WindowsAppVersion = "0.4.7",
    [ValidateRange(0, 65535)]
    [int]$WindowsBuildNumber = 4640,
    [string]$AndroidBuildNumber = "2026083003",
    [string]$AndroidApplicationId = "pro.greenvpn.app",
    [string]$AndroidAppLabel = "Green VPN",
    [string]$ApiBaseUrl = "https://api.greenvpn.pro",
    [string]$ApiFallbackBaseUrls = "https://176-113-81-35.sslip.io",
    [string]$OutDir = "C:\BlueVPN_Builds\public_product_20260901_android_2026083003_windows_4640",
    [bool]$EnableTransportCascade = $true,
    [bool]$EnableFusionUi = $true,
    [switch]$PrepareFusionProductionPromotionCandidate,
    [string]$WindowsCodeSigningCertificateThumbprint = $env:GREENVPN_WINDOWS_CODE_SIGNING_CERT_THUMBPRINT,
    [string]$WindowsCodeSigningPublisher = $env:GREENVPN_WINDOWS_CODE_SIGNING_PUBLISHER,
    [string]$WindowsCodeSigningTimestampUrl = 'http://timestamp.digicert.com',
    [switch]$RequireWindowsCodeSigning,
    [switch]$EnableAndroidRewardedAds,
    [switch]$AndroidStoreDistribution,
    [switch]$BuildAndroidAppBundle,
    [switch]$SkipChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo

if ($ApiBaseUrl.Contains("/paid-beta-api") -or $ApiFallbackBaseUrls.Contains("/paid-beta-api")) {
    throw "Public product build must use production API roots."
}
if ($AndroidApplicationId -ne "pro.greenvpn.app") {
    throw "Public product Android build must keep the production package ID."
}
if ($AndroidAppLabel -ne "Green VPN") {
    throw "Public product Android build must keep the production label."
}
if ($AndroidStoreDistribution -and $EnableAndroidRewardedAds) {
    throw "Android store distribution builds must not include rewarded ads."
}
if ($BuildAndroidAppBundle -and $Mode -notin @("android", "both")) {
    throw "BuildAndroidAppBundle requires an Android build mode."
}
if ($EnableFusionUi -and -not $PrepareFusionProductionPromotionCandidate) {
    throw "Fusion production build requires PrepareFusionProductionPromotionCandidate."
}
if ($PrepareFusionProductionPromotionCandidate -and -not $EnableFusionUi) {
    throw "Fusion production promotion gate requires EnableFusionUi=true."
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "flutter was not found in PATH."
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not $SkipChecks) {
    flutter pub get | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
    flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed" }
    flutter test --no-pub | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "flutter test failed" }
    if ($EnableFusionUi) {
        flutter test --no-pub `
            --dart-define="GREENVPN_PUBLIC_PRODUCT_BUILD=true" `
            --dart-define="GREENVPN_FUSION_UI_ENABLED=true" `
            --dart-define="GREENVPN_FUSION_PRODUCTION_PROMOTION_CANDIDATE=true" `
            "test\fusion_ui_test.dart" "test\free_tier_ui_test.dart" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Fusion production UI test failed" }
    }
}

$artifacts = New-Object System.Collections.Generic.List[object]
$safeVersion = $AppVersion -replace "[^A-Za-z0-9._-]", "_"
$safeWindowsVersion = $WindowsAppVersion -replace "[^A-Za-z0-9._-]", "_"

if ($Mode -in @("android", "both")) {
    $androidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    $jdkDir = "C:\Program Files\Android\openjdk\jdk-21.0.8"
    if (-not (Test-Path -LiteralPath $androidSdk)) { throw "Android SDK not found: $androidSdk" }
    if (-not (Test-Path -LiteralPath $jdkDir)) { throw "Android JDK not found: $jdkDir" }

    $androidReleaseChannel = if ($AndroidStoreDistribution) { "store" } else { "public-product" }
    $androidClientMarker = if ($AndroidStoreDistribution) {
        "green-vpn-store-v1"
    } else {
        "green-vpn-public-product-v1"
    }
    $storeDistributionValue = $AndroidStoreDistribution.ToString().ToLowerInvariant()
    $trialOnlyNoAdsValue = $AndroidStoreDistribution.ToString().ToLowerInvariant()
    $rewardedAdsValue = $EnableAndroidRewardedAds.ToString().ToLowerInvariant()
    $transportCascadeValue = $EnableTransportCascade.ToString().ToLowerInvariant()
    $fusionUiValue = $EnableFusionUi.ToString().ToLowerInvariant()
    $fusionProductionPromotionCandidateValue = (
        $PrepareFusionProductionPromotionCandidate.IsPresent
    ).ToString().ToLowerInvariant()

    $oldEnvironment = @{}
    $buildEnvironment = [ordered]@{
        ANDROID_HOME = $androidSdk
        ANDROID_SDK_ROOT = $androidSdk
        JAVA_HOME = $jdkDir
        GREENVPN_ANDROID_APPLICATION_ID = $AndroidApplicationId
        GREENVPN_ANDROID_APP_LABEL = $AndroidAppLabel
        GREENVPN_ANDROID_API_BASE_URL = $ApiBaseUrl
        GREENVPN_ANDROID_API_FALLBACK_BASE_URLS = $ApiFallbackBaseUrls
        GREENVPN_ANDROID_RELEASE_CHANNEL = $androidReleaseChannel
        GREENVPN_ANDROID_CLIENT_MARKER = $androidClientMarker
        GREENVPN_ANDROID_STORE_DISTRIBUTION = $storeDistributionValue
        GREENVPN_ANDROID_AWG2_PREVIEW_ENABLED = $transportCascadeValue
        GREENVPN_ANDROID_HYSTERIA2_PREVIEW_ENABLED = $transportCascadeValue
        GREENVPN_ANDROID_VLESS_REALITY_PREVIEW_ENABLED = $transportCascadeValue
        GREENVPN_ANDROID_NAIVE_HTTPS_PREVIEW_ENABLED = $transportCascadeValue
        GREENVPN_ANDROID_DNSTT_PREVIEW_ENABLED = $transportCascadeValue
        GREENVPN_APP_VERSION = $AppVersion
    }
    $oldPath = $env:Path
    try {
        foreach ($name in $buildEnvironment.Keys) {
            $oldEnvironment[$name] = [pscustomobject]@{
                existed = Test-Path -LiteralPath "Env:$name"
                value = [Environment]::GetEnvironmentVariable($name, "Process")
            }
            Set-Item -LiteralPath "Env:$name" -Value $buildEnvironment[$name]
        }
        $env:Path = "$jdkDir\bin;$androidSdk\platform-tools;$env:Path"

        if ($EnableTransportCascade) {
            & (Join-Path $PSScriptRoot "build_android_awg2_native.ps1") -VerifyOnly
            if ($LASTEXITCODE -ne 0) { throw "Pinned Android AWG native verification failed" }
            & (Join-Path $PSScriptRoot "build_android_hysteria2_native.ps1") -VerifyOnly
            if ($LASTEXITCODE -ne 0) { throw "Pinned Android Hysteria native verification failed" }
            & (Join-Path $PSScriptRoot "prepare_android_awg2_preview.ps1")
            & (Join-Path $PSScriptRoot "prepare_android_hysteria2_preview.ps1")
            & (Join-Path $PSScriptRoot "prepare_android_vless_reality_preview.ps1")
            & (Join-Path $PSScriptRoot "prepare_android_naive_https_preview.ps1")
            & (Join-Path $PSScriptRoot "prepare_android_dnstt_preview.ps1")
        }

        if (-not $SkipChecks) {
            $lintTasks = @(':app:lintRelease')
            if ($EnableTransportCascade) {
                $lintTasks += ':awg_tunnel_preview:lint'
                $lintTasks += ':hysteria_tunnel_preview:lint'
            }
            Push-Location (Join-Path $repo 'android')
            try {
                & '.\gradlew.bat' @lintTasks '--rerun-tasks' '--stacktrace' | Out-Host
                if ($LASTEXITCODE -ne 0) { throw "Android public product lint failed" }
            }
            finally {
                Pop-Location
            }
        }

        $flutterAndroidArgs = @(
            '--release'
            '--no-pub'
            '--target-platform'
            'android-arm64,android-x64'
            '--build-name'
            $AppVersion
            '--build-number'
            $AndroidBuildNumber
            "--dart-define=GREENVPN_APP_VERSION=$AppVersion"
            "--dart-define=GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=$trialOnlyNoAdsValue"
            '--dart-define=GREENVPN_PAID_BETA_BUILD=false'
            '--dart-define=GREENVPN_PUBLIC_PRODUCT_BUILD=true'
            "--dart-define=GREENVPN_FUSION_UI_ENABLED=$fusionUiValue"
            "--dart-define=GREENVPN_FUSION_PRODUCTION_PROMOTION_CANDIDATE=$fusionProductionPromotionCandidateValue"
            "--dart-define=GREENVPN_STORE_DISTRIBUTION_BUILD=$storeDistributionValue"
            "--dart-define=GREENVPN_PUBLIC_PRODUCT_CLIENT_MARKER=$androidClientMarker"
            "--dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=$rewardedAdsValue"
            "--dart-define=GREENVPN_AWG2_PREVIEW_ENABLED=$transportCascadeValue"
            "--dart-define=GREENVPN_HYSTERIA2_PREVIEW_ENABLED=$transportCascadeValue"
            "--dart-define=GREENVPN_VLESS_REALITY_PREVIEW_ENABLED=$transportCascadeValue"
            "--dart-define=GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED=$transportCascadeValue"
            "--dart-define=GREENVPN_DNSTT_PREVIEW_ENABLED=$transportCascadeValue"
            "--dart-define=BLUEVPN_API_BASE_URL=$ApiBaseUrl"
            "--dart-define=BLUEVPN_API_BASE_URLS=$ApiFallbackBaseUrls"
        )

        flutter build apk @flutterAndroidArgs | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Android public product build failed" }

        if ($BuildAndroidAppBundle) {
            flutter build appbundle @flutterAndroidArgs | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "Android public product app bundle build failed" }
        }
    }
    finally {
        $env:Path = $oldPath
        foreach ($name in $buildEnvironment.Keys) {
            $previous = $oldEnvironment[$name]
            if ($previous.existed) {
                Set-Item -LiteralPath "Env:$name" -Value $previous.value
            } else {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            }
        }
    }

    $sourceApk = (Resolve-Path "build\app\outputs\flutter-apk\app-release.apk").Path
    $androidPath = Join-Path $OutDir "GreenVPN_Android_${safeVersion}_${AndroidBuildNumber}.apk"
    Copy-Item -LiteralPath $sourceApk -Destination $androidPath -Force
    $androidBundlePath = $null
    if ($BuildAndroidAppBundle) {
        $sourceBundle = (Resolve-Path "build\app\outputs\bundle\release\app-release.aab").Path
        $androidBundlePath = Join-Path $OutDir "GreenVPN_Android_${safeVersion}_${AndroidBuildNumber}.aab"
        Copy-Item -LiteralPath $sourceBundle -Destination $androidBundlePath -Force
    }

    $apksigner = Get-ChildItem -LiteralPath (Join-Path $androidSdk "build-tools") `
        -Filter "apksigner.bat" -Recurse | Sort-Object FullName -Descending | Select-Object -First 1
    $aapt = Get-ChildItem -LiteralPath (Join-Path $androidSdk "build-tools") `
        -Filter "aapt.exe" -Recurse | Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -eq $apksigner -or $null -eq $aapt) { throw "Android verification tools not found" }
    & $apksigner.FullName verify --verbose $androidPath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Android signature verification failed" }
    $certificateOutput = & $apksigner.FullName verify --print-certs $androidPath
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect Android signer" }
    $certificateOutput | Out-Host
    $expectedSignerPath = Join-Path $repo "android\release_signer_sha256.txt"
    $expectedSigner = (Get-Content -LiteralPath $expectedSignerPath -Raw).Trim().ToLowerInvariant()
    $certificateLine = $certificateOutput |
        Select-String -Pattern 'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})' |
        Select-Object -First 1
    if (-not $certificateLine) { throw "Android signer fingerprint was not reported" }
    $actualSigner = $certificateLine.Matches[0].Groups[1].Value.ToLowerInvariant()
    if ($actualSigner -ne $expectedSigner) { throw "Unexpected Android release signer" }
    $badging = (& $aapt.FullName dump badging $androidPath) -join "`n"
    if ($badging -notmatch "package: name='$([regex]::Escape($AndroidApplicationId))'") {
        throw "Android package ID mismatch."
    }
    if ($badging -notmatch "application-label:'$([regex]::Escape($AndroidAppLabel))'") {
        throw "Android app label mismatch."
    }
    if ($AndroidStoreDistribution) {
        $permissions = (& $aapt.FullName dump permissions $androidPath) -join "`n"
        if ($permissions -match 'android\.permission\.REQUEST_INSTALL_PACKAGES') {
            throw "Android store APK must not request REQUEST_INSTALL_PACKAGES."
        }
        if ($permissions -match 'com\.google\.android\.gms\.permission\.AD_ID') {
            throw "Android store APK must not request AD_ID."
        }
        $manifestTree = (& $aapt.FullName dump xmltree $androidPath AndroidManifest.xml) -join "`n"
        if ($manifestTree -match '(?i)yandex|appmetrica|mobileads') {
            throw "Android store APK still contains an advertising SDK manifest component."
        }
    }
    if ($EnableTransportCascade) {
        & (Join-Path $PSScriptRoot "verify_android_hysteria2_preview_apk.ps1") `
            -ApkPath $androidPath `
            -ExpectedPackage $AndroidApplicationId `
            -ExpectedVersionCode $AndroidBuildNumber
        if ($LASTEXITCODE -ne 0) { throw "Android Hysteria2 verifier failed" }
        & (Join-Path $PSScriptRoot "verify_android_dnstt_preview_apk.ps1") `
            -ApkPath $androidPath `
            -ExpectedPackage $AndroidApplicationId `
            -ExpectedVersionCode $AndroidBuildNumber
        if ($LASTEXITCODE -ne 0) { throw "Android dnstt verifier failed" }
    }
    & (Join-Path $PSScriptRoot "verify_android_16kb_compatibility.ps1") `
        -ApkPath $androidPath `
        -JsonOutput (Join-Path $OutDir "android-16kb-compatibility.json") | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Android 16 KB compatibility verification failed" }

    $item = Get-Item -LiteralPath $androidPath
    $artifacts.Add([pscustomobject]@{
        platform = "android"; version = $AppVersion; buildNumber = $AndroidBuildNumber
        artifactType = "apk"; storeDistribution = [bool]$AndroidStoreDistribution
        applicationId = $AndroidApplicationId; path = $item.FullName
        sizeBytes = $item.Length; sha256 = (Get-FileHash $item.FullName -Algorithm SHA256).Hash
        signed = $true
    })

    if ($BuildAndroidAppBundle) {
        $jarsigner = Join-Path $jdkDir 'bin\jarsigner.exe'
        $keytool = Join-Path $jdkDir 'bin\keytool.exe'
        foreach ($tool in @($jarsigner, $keytool)) {
            if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
                throw "Android app bundle verification tool not found: $tool"
            }
        }
        & $jarsigner -verify $androidBundlePath | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Android app bundle signature verification failed" }
        $bundleCertificate = (& $keytool -printcert -jarfile $androidBundlePath) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "Unable to inspect Android app bundle signer" }
        $bundleShaLine = $bundleCertificate |
            Select-String -Pattern 'SHA256:\s*([0-9A-Fa-f:]{95})' |
            Select-Object -First 1
        if (-not $bundleShaLine) { throw "Android app bundle signer fingerprint was not reported" }
        $bundleSigner = ($bundleShaLine.Matches[0].Groups[1].Value -replace ':', '').ToLowerInvariant()
        if ($bundleSigner -ne $expectedSigner) { throw "Unexpected Android app bundle release signer" }

        $bundleItem = Get-Item -LiteralPath $androidBundlePath
        $artifacts.Add([pscustomobject]@{
            platform = "android"; version = $AppVersion; buildNumber = $AndroidBuildNumber
            artifactType = "aab"; storeDistribution = [bool]$AndroidStoreDistribution
            applicationId = $AndroidApplicationId; path = $bundleItem.FullName
            sizeBytes = $bundleItem.Length
            sha256 = (Get-FileHash $bundleItem.FullName -Algorithm SHA256).Hash
            signed = $true
        })
    }
}

if ($Mode -in @("windows", "both")) {
    $windowsPath = Join-Path $OutDir "GreenVPN_Setup_${safeWindowsVersion}.exe"
    & (Join-Path $PSScriptRoot "build_installer.ps1") `
        -ProjectRoot $repo -OutBase $OutDir `
        -InstallerName (Split-Path $windowsPath -Leaf) `
        -AppVersion $WindowsAppVersion `
        -WindowsBuildNumber $WindowsBuildNumber `
        -ApiBaseUrl $ApiBaseUrl `
        -ApiFallbackBaseUrls $ApiFallbackBaseUrls `
        -TrialOnlyNoAdsBuild $false `
        -PaidBetaBuild $false `
        -PublicProductBuild $true `
        -EnableFusionUi $EnableFusionUi `
        -AllowFusionProductionPromotionCandidate:$PrepareFusionProductionPromotionCandidate `
        -EnableTransportCascade $EnableTransportCascade `
        -WindowsRuntimeScope stable `
        -CertificateThumbprint $WindowsCodeSigningCertificateThumbprint `
        -CodeSigningExpectedPublisher $WindowsCodeSigningPublisher `
        -CodeSigningTimestampUrl $WindowsCodeSigningTimestampUrl `
        -RequireCodeSigning:$RequireWindowsCodeSigning
    if (-not $?) { throw "Windows public product build failed" }
    $item = Get-Item -LiteralPath $windowsPath
    $signature = Get-AuthenticodeSignature -LiteralPath $item.FullName
    $artifacts.Add([pscustomobject]@{
        platform = "windows"; version = $WindowsAppVersion; buildNumber = $WindowsBuildNumber
        path = $item.FullName; sizeBytes = $item.Length
        sha256 = (Get-FileHash $item.FullName -Algorithm SHA256).Hash
        signed = $signature.Status -eq "Valid"; signatureStatus = $signature.Status.ToString()
        signerSubject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { "" }
        signerThumbprint = if ($signature.SignerCertificate) { $signature.SignerCertificate.Thumbprint } else { "" }
    })
}

$effectiveTransportCascade = $EnableTransportCascade
$manifestChannel = if ($AndroidStoreDistribution) { "store" } else { "stable" }
[object[]]$releasePlans = @()
if (-not $AndroidStoreDistribution) {
    $releasePlans = @(
        [pscustomobject]@{ code = 'green_30d'; periodDays = 30; priceRub = 249 }
        [pscustomobject]@{ code = 'green_90d'; periodDays = 90; priceRub = 649 }
        [pscustomobject]@{ code = 'green_180d'; periodDays = 180; priceRub = 1099 }
    )
}
$manifest = [ordered]@{
    channel = $manifestChannel
    publicProduct = $true
    productionPublished = $false
    appVersion = $AppVersion
    windowsAppVersion = $WindowsAppVersion
    freeAccessPolicy = "server-configured"
    trialDays = $null
    plans = $releasePlans
    autoRenew = $false
    autoRenewRequiresExplicitConsent = $true
    adsEnabled = [bool]$EnableAndroidRewardedAds
    androidStoreDistribution = [bool]$AndroidStoreDistribution
    fusionUiEnabled = [bool]$EnableFusionUi
    fusionProductionPromotionCandidate = [bool]$PrepareFusionProductionPromotionCandidate
    ownerApprovalRequired = $true
    requiredOwnerGates = @(
        'fusion_ui_acceptance'
        'windows_signature_or_smartscreen_acceptance'
        'stable_production_promotion'
    )
    transportCascade = $effectiveTransportCascade
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    artifacts = [object[]]$artifacts
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content `
    -LiteralPath (Join-Path $OutDir "public-product-artifacts.json") -Encoding utf8

$artifacts | Format-Table platform, version, sizeBytes, sha256, path -AutoSize | Out-Host
