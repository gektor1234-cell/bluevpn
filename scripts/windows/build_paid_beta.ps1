param(
    [ValidateSet("android", "windows", "both")]
    [string]$Mode = "both",
    [string]$AppVersion = "0.4.6-paid-beta.1",
    [string]$WindowsAppVersion = "0.4.6-paid-beta.1",
    [ValidateRange(0, 65535)]
    [int]$WindowsBuildNumber = 4601,
    [string]$AndroidBuildName = "0.4.6",
    [string]$AndroidBuildNumber = "2026081106",
    [string]$AndroidApplicationId = "pro.greenvpn.app.beta",
    [string]$AndroidAppLabel = "Green VPN Beta",
    [string]$ApiBaseUrl = "https://api.greenvpn.pro/paid-beta-api",
    [string]$ApiFallbackBaseUrls = "https://176-113-81-35.sslip.io/paid-beta-api",
    [string]$ClientMarker = "green-vpn-paid-beta-v1",
    [string]$OutDir = "C:\BlueVPN_Builds\paid_beta_20260811_fusion_actions_v7_0.4.6",
    [bool]$EnableTransportCascade = $true,
    [bool]$EnableFusionUi = $true,
    [string]$WindowsCodeSigningCertificateThumbprint = $env:GREENVPN_WINDOWS_CODE_SIGNING_CERT_THUMBPRINT,
    [string]$WindowsCodeSigningPublisher = $env:GREENVPN_WINDOWS_CODE_SIGNING_PUBLISHER,
    [string]$WindowsCodeSigningTimestampUrl = 'http://timestamp.digicert.com',
    [switch]$RequireWindowsCodeSigning,
    [switch]$PublicProductCandidate,
    [switch]$EnableAndroidRewardedAds,
    [switch]$SkipChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo

if (-not $ApiBaseUrl.Contains("/paid-beta-api")) {
    throw "Primary API must use the isolated /paid-beta-api contour."
}
if (-not $ApiFallbackBaseUrls.Contains("/paid-beta-api")) {
    throw "Fallback API must use the isolated /paid-beta-api contour."
}
if ($EnableFusionUi -and $PublicProductCandidate) {
    throw "Fusion UI is allowed only in the isolated paid-beta product."
}
$expectedClientMarker = if ($PublicProductCandidate) {
    "green-vpn-public-product-v1"
} else {
    "green-vpn-paid-beta-v1"
}
if ($ClientMarker -ne $expectedClientMarker) {
    throw "Unexpected client marker for this build mode."
}
if ($AndroidApplicationId -eq "pro.greenvpn.app") {
    throw "Paid beta Android must not replace the production application ID."
}
if ($AndroidApplicationId -notmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$') {
    throw "Invalid paid beta Android application ID: $AndroidApplicationId"
}
if ($Mode -in @("android", "both")) {
    if ($PublicProductCandidate) {
        if ($AndroidAppLabel -ne "Green VPN") {
            throw "Public-product candidate must use the Green VPN launcher label."
        }
        if ($AppVersion -match "(?i)(preview|beta)") {
            throw "Public-product candidate version must not expose preview or beta markers."
        }
    } elseif ([string]::IsNullOrWhiteSpace($AndroidAppLabel) -or $AndroidAppLabel -eq "Green VPN") {
        throw "Paid beta Android must use a distinct launcher label."
    }
}
if (
    $PublicProductCandidate -and
    $Mode -in @("windows", "both") -and
    $WindowsAppVersion -match "(?i)(preview|beta)"
) {
    throw "Public-product Windows candidate version must not expose preview or beta markers."
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
            --dart-define="GREENVPN_PAID_BETA_BUILD=true" `
            --dart-define="GREENVPN_PUBLIC_PRODUCT_BUILD=false" `
            --dart-define="GREENVPN_FUSION_UI_ENABLED=true" `
            "test\fusion_ui_test.dart" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Fusion UI test failed" }
    }
}

$artifacts = New-Object System.Collections.Generic.List[object]
$safeVersion = $AppVersion -replace "[^A-Za-z0-9._-]", "_"
$safeWindowsVersion = $WindowsAppVersion -replace "[^A-Za-z0-9._-]", "_"

if ($Mode -in @("android", "both")) {
    $androidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    $jdkDir = "C:\Program Files\Android\openjdk\jdk-21.0.8"
    if (-not (Test-Path -LiteralPath $androidSdk)) {
        throw "Android SDK not found: $androidSdk"
    }
    if (-not (Test-Path -LiteralPath $jdkDir)) {
        throw "Android JDK not found: $jdkDir"
    }

    $oldAndroidHome = $env:ANDROID_HOME
    $oldAndroidSdkRoot = $env:ANDROID_SDK_ROOT
    $oldJavaHome = $env:JAVA_HOME
    $oldPath = $env:Path
    $androidBuildEnvironment = [ordered]@{
        GREENVPN_APP_VERSION = $AppVersion
        GREENVPN_ANDROID_APPLICATION_ID = $AndroidApplicationId
        GREENVPN_ANDROID_APP_LABEL = $AndroidAppLabel
        GREENVPN_ANDROID_API_BASE_URL = $ApiBaseUrl
        GREENVPN_ANDROID_API_FALLBACK_BASE_URLS = $ApiFallbackBaseUrls
        GREENVPN_ANDROID_RELEASE_CHANNEL = if ($PublicProductCandidate) { "public-product" } else { "paid-beta" }
        GREENVPN_ANDROID_CLIENT_MARKER = $ClientMarker
        GREENVPN_ANDROID_AWG2_PREVIEW_ENABLED = $EnableTransportCascade.ToString().ToLowerInvariant()
        GREENVPN_ANDROID_HYSTERIA2_PREVIEW_ENABLED = $EnableTransportCascade.ToString().ToLowerInvariant()
        GREENVPN_ANDROID_VLESS_REALITY_PREVIEW_ENABLED = $EnableTransportCascade.ToString().ToLowerInvariant()
        GREENVPN_ANDROID_NAIVE_HTTPS_PREVIEW_ENABLED = $EnableTransportCascade.ToString().ToLowerInvariant()
        GREENVPN_ANDROID_DNSTT_PREVIEW_ENABLED = $EnableTransportCascade.ToString().ToLowerInvariant()
    }
    $oldAndroidBuildEnvironment = @{}
    try {
        $env:ANDROID_HOME = $androidSdk
        $env:ANDROID_SDK_ROOT = $androidSdk
        $env:JAVA_HOME = $jdkDir
        $env:Path = "$jdkDir\bin;$androidSdk\platform-tools;$env:Path"
        foreach ($name in $androidBuildEnvironment.Keys) {
            $oldAndroidBuildEnvironment[$name] = [pscustomobject]@{
                existed = Test-Path -LiteralPath "Env:$name"
                value = [Environment]::GetEnvironmentVariable($name, "Process")
            }
            Set-Item -LiteralPath "Env:$name" -Value $androidBuildEnvironment[$name]
        }

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
                if ($LASTEXITCODE -ne 0) { throw "Android paid beta lint failed" }
            }
            finally {
                Pop-Location
            }
        }

        flutter build apk --release --no-pub `
            --target-platform android-arm64,android-x64 `
            --build-name $AndroidBuildName `
            --build-number $AndroidBuildNumber `
            --dart-define="GREENVPN_APP_VERSION=$AppVersion" `
            --dart-define="GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false" `
            --dart-define="GREENVPN_PAID_BETA_BUILD=$(((-not $PublicProductCandidate)).ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_PUBLIC_PRODUCT_BUILD=$($PublicProductCandidate.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_FUSION_UI_ENABLED=$($EnableFusionUi.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_UPDATE_CHANNEL=paid-beta" `
            --dart-define="GREENVPN_PUBLIC_PRODUCT_CLIENT_MARKER=green-vpn-public-product-v1" `
            --dart-define="GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1" `
            --dart-define="GREENVPN_YANDEX_REWARDED_ADS_ENABLED=$($EnableAndroidRewardedAds.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_AWG2_PREVIEW_ENABLED=$($EnableTransportCascade.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_HYSTERIA2_PREVIEW_ENABLED=$($EnableTransportCascade.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_VLESS_REALITY_PREVIEW_ENABLED=$($EnableTransportCascade.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED=$($EnableTransportCascade.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_DNSTT_PREVIEW_ENABLED=$($EnableTransportCascade.ToString().ToLowerInvariant())" `
            --dart-define="BLUEVPN_API_BASE_URL=$ApiBaseUrl" `
            --dart-define="BLUEVPN_API_BASE_URLS=$ApiFallbackBaseUrls" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Android paid beta build failed" }
    }
    finally {
        $env:ANDROID_HOME = $oldAndroidHome
        $env:ANDROID_SDK_ROOT = $oldAndroidSdkRoot
        $env:JAVA_HOME = $oldJavaHome
        $env:Path = $oldPath
        foreach ($name in $androidBuildEnvironment.Keys) {
            $previous = $oldAndroidBuildEnvironment[$name]
            if ($previous.existed) {
                Set-Item -LiteralPath "Env:$name" -Value $previous.value
            } else {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            }
        }
    }

    $sourceApk = (Resolve-Path "build\app\outputs\flutter-apk\app-release.apk").Path
    $androidName = "GreenVPN_Android_${safeVersion}_${AndroidBuildNumber}.apk"
    $androidPath = Join-Path $OutDir $androidName
    Copy-Item -LiteralPath $sourceApk -Destination $androidPath -Force

    $apksigner = Get-ChildItem -LiteralPath (Join-Path $androidSdk "build-tools") `
        -Filter "apksigner.bat" -Recurse | Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -eq $apksigner) { throw "apksigner.bat not found" }
    & $apksigner.FullName verify --verbose --print-certs $androidPath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Android paid beta signature verification failed" }
    $certificateOutput = & $apksigner.FullName verify --print-certs $androidPath
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect Android paid beta signer" }
    $expectedSignerPath = Join-Path $repo "android\release_signer_sha256.txt"
    if (-not (Test-Path -LiteralPath $expectedSignerPath -PathType Leaf)) {
        throw "Expected Android release signer file is missing."
    }
    $expectedSigner = (Get-Content -LiteralPath $expectedSignerPath -Raw).Trim().ToLowerInvariant()
    if ($expectedSigner -notmatch '^[0-9a-f]{64}$') {
        throw "Expected Android release signer SHA-256 is invalid."
    }
    $certificateLine = $certificateOutput |
        Select-String -Pattern 'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})' |
        Select-Object -First 1
    if (-not $certificateLine) { throw "Android paid beta signer fingerprint was not reported" }
    $actualSigner = $certificateLine.Matches[0].Groups[1].Value.ToLowerInvariant()
    if ($actualSigner -ne $expectedSigner) { throw "Unexpected Android paid beta release signer" }

    $aapt = Get-ChildItem -LiteralPath (Join-Path $androidSdk "build-tools") `
        -Filter "aapt.exe" -Recurse | Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -eq $aapt) { throw "aapt.exe not found" }
    $badging = (& $aapt.FullName dump badging $androidPath) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Android paid beta badging inspection failed" }
    if ($badging -notmatch "package: name='$([regex]::Escape($AndroidApplicationId))'") {
        throw "Android paid beta package ID does not match $AndroidApplicationId."
    }
    if ($badging -notmatch "application-label:'$([regex]::Escape($AndroidAppLabel))'") {
        throw "Android paid beta launcher label does not match $AndroidAppLabel."
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
        platform = "android"
        version = $AppVersion
        buildNumber = $AndroidBuildNumber
        applicationId = $AndroidApplicationId
        appLabel = $AndroidAppLabel
        path = $item.FullName
        fileName = $item.Name
        sizeBytes = $item.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash
        signed = $true
    })
}

if ($Mode -in @("windows", "both")) {
    $windowsName = if ($PublicProductCandidate) {
        "GreenVPN_Setup_${safeWindowsVersion}.exe"
    } else {
        "GreenVPN_Beta_Setup_${safeWindowsVersion}.exe"
    }
    & (Join-Path $PSScriptRoot "build_installer.ps1") `
        -ProjectRoot $repo `
        -OutBase $OutDir `
        -InstallerName $windowsName `
        -AppVersion $WindowsAppVersion `
        -WindowsBuildNumber $WindowsBuildNumber `
        -ApiBaseUrl $ApiBaseUrl `
        -ApiFallbackBaseUrls $ApiFallbackBaseUrls `
        -TrialOnlyNoAdsBuild $false `
        -PaidBetaBuild (-not $PublicProductCandidate) `
        -PublicProductBuild ([bool]$PublicProductCandidate) `
        -EnableFusionUi $EnableFusionUi `
        -EnableTransportCascade $EnableTransportCascade `
        -WindowsRuntimeScope $(if ($PublicProductCandidate) { 'stable' } else { 'paid-beta' }) `
        -UpdateChannelOverride 'paid-beta' `
        -CertificateThumbprint $WindowsCodeSigningCertificateThumbprint `
        -CodeSigningExpectedPublisher $WindowsCodeSigningPublisher `
        -CodeSigningTimestampUrl $WindowsCodeSigningTimestampUrl `
        -RequireCodeSigning:$RequireWindowsCodeSigning
    if (-not $?) { throw "Windows paid beta installer build failed" }

    $windowsPath = Join-Path $OutDir $windowsName
    $item = Get-Item -LiteralPath $windowsPath
    $signature = Get-AuthenticodeSignature -LiteralPath $item.FullName
    $artifacts.Add([pscustomobject]@{
        platform = "windows"
        version = $WindowsAppVersion
        buildNumber = $WindowsBuildNumber
        path = $item.FullName
        fileName = $item.Name
        sizeBytes = $item.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash
        signed = $signature.Status -eq "Valid"
        signatureStatus = $signature.Status.ToString()
        signerSubject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { "" }
        signerThumbprint = if ($signature.SignerCertificate) { $signature.SignerCertificate.Thumbprint } else { "" }
    })
}

$manifest = [pscustomobject]@{
    channel = "paid-beta"
    isolated = $true
    productionPublished = $false
    appVersion = $AppVersion
    windowsAppVersion = $WindowsAppVersion
    androidApplicationId = $AndroidApplicationId
    androidAppLabel = $AndroidAppLabel
    clientMarker = $ClientMarker
    apiBaseUrl = $ApiBaseUrl
    apiFallbackBaseUrls = $ApiFallbackBaseUrls
    trialOnlyNoAdsBuild = $false
    paidBetaBuild = -not $PublicProductCandidate
    publicProductBuild = [bool]$PublicProductCandidate
    fusionUiEnabled = [bool]$EnableFusionUi
    rewardedAdsEnabled = [bool]$EnableAndroidRewardedAds
    transportCascade = $EnableTransportCascade
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    artifacts = @($artifacts | ForEach-Object { $_ })
}
$manifestPath = Join-Path $OutDir "paid-beta-artifacts.json"
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Paid beta artifacts:" -ForegroundColor Green
$artifacts | Format-Table platform, version, sizeBytes, sha256, path -AutoSize | Out-Host
Write-Host "Manifest: $manifestPath" -ForegroundColor Green
