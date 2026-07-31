param(
    [ValidateSet("android", "windows", "both")]
    [string]$Mode = "both",
    [string]$AppVersion = "0.3.22",
    [string]$WindowsAppVersion = "0.3.22",
    [ValidateRange(0, 65535)]
    [int]$WindowsBuildNumber = 3101,
    [string]$AndroidBuildNumber = "2026073101",
    [string]$AndroidApplicationId = "pro.greenvpn.app",
    [string]$AndroidAppLabel = "Green VPN",
    [string]$ApiBaseUrl = "https://api.greenvpn.pro",
    [string]$ApiFallbackBaseUrls = "https://176-113-81-35.sslip.io",
    [string]$OutDir = "C:\BlueVPN_Builds\public_product_20260731_b3101",
    [bool]$EnableTransportCascade = $true,
    [string]$WindowsCodeSigningCertificateThumbprint = $env:GREENVPN_WINDOWS_CODE_SIGNING_CERT_THUMBPRINT,
    [string]$WindowsCodeSigningPublisher = $env:GREENVPN_WINDOWS_CODE_SIGNING_PUBLISHER,
    [string]$WindowsCodeSigningTimestampUrl = 'http://timestamp.digicert.com',
    [switch]$RequireWindowsCodeSigning,
    [switch]$EnableAndroidRewardedAds,
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
}

$artifacts = New-Object System.Collections.Generic.List[object]
$safeVersion = $AppVersion -replace "[^A-Za-z0-9._-]", "_"
$safeWindowsVersion = $WindowsAppVersion -replace "[^A-Za-z0-9._-]", "_"

if ($Mode -in @("android", "both")) {
    $androidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    $jdkDir = "C:\Program Files\Android\openjdk\jdk-21.0.8"
    if (-not (Test-Path -LiteralPath $androidSdk)) { throw "Android SDK not found: $androidSdk" }
    if (-not (Test-Path -LiteralPath $jdkDir)) { throw "Android JDK not found: $jdkDir" }

    $oldEnvironment = @{}
    $buildEnvironment = [ordered]@{
        ANDROID_HOME = $androidSdk
        ANDROID_SDK_ROOT = $androidSdk
        JAVA_HOME = $jdkDir
        GREENVPN_ANDROID_APPLICATION_ID = $AndroidApplicationId
        GREENVPN_ANDROID_APP_LABEL = $AndroidAppLabel
        GREENVPN_ANDROID_API_BASE_URL = $ApiBaseUrl
        GREENVPN_ANDROID_API_FALLBACK_BASE_URLS = $ApiFallbackBaseUrls
        GREENVPN_ANDROID_RELEASE_CHANNEL = "public-product"
        GREENVPN_ANDROID_CLIENT_MARKER = "green-vpn-public-product-v1"
        GREENVPN_ANDROID_AWG2_PREVIEW_ENABLED = $EnableTransportCascade.ToString().ToLowerInvariant()
        GREENVPN_ANDROID_HYSTERIA2_PREVIEW_ENABLED = $EnableTransportCascade.ToString().ToLowerInvariant()
        GREENVPN_ANDROID_VLESS_REALITY_PREVIEW_ENABLED = $EnableTransportCascade.ToString().ToLowerInvariant()
        GREENVPN_ANDROID_NAIVE_HTTPS_PREVIEW_ENABLED = $EnableTransportCascade.ToString().ToLowerInvariant()
        GREENVPN_ANDROID_DNSTT_PREVIEW_ENABLED = $EnableTransportCascade.ToString().ToLowerInvariant()
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

        flutter build apk --release --no-pub `
            --target-platform android-arm64,android-x64 `
            --build-name $AppVersion `
            --build-number $AndroidBuildNumber `
            --dart-define="GREENVPN_APP_VERSION=$AppVersion" `
            --dart-define="GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false" `
            --dart-define="GREENVPN_PAID_BETA_BUILD=false" `
            --dart-define="GREENVPN_PUBLIC_PRODUCT_BUILD=true" `
            --dart-define="GREENVPN_PUBLIC_PRODUCT_CLIENT_MARKER=green-vpn-public-product-v1" `
            --dart-define="GREENVPN_YANDEX_REWARDED_ADS_ENABLED=$($EnableAndroidRewardedAds.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_AWG2_PREVIEW_ENABLED=$($EnableTransportCascade.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_HYSTERIA2_PREVIEW_ENABLED=$($EnableTransportCascade.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_VLESS_REALITY_PREVIEW_ENABLED=$($EnableTransportCascade.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED=$($EnableTransportCascade.ToString().ToLowerInvariant())" `
            --dart-define="GREENVPN_DNSTT_PREVIEW_ENABLED=$($EnableTransportCascade.ToString().ToLowerInvariant())" `
            --dart-define="BLUEVPN_API_BASE_URL=$ApiBaseUrl" `
            --dart-define="BLUEVPN_API_BASE_URLS=$ApiFallbackBaseUrls" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Android public product build failed" }
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
        applicationId = $AndroidApplicationId; path = $item.FullName
        sizeBytes = $item.Length; sha256 = (Get-FileHash $item.FullName -Algorithm SHA256).Hash
        signed = $true
    })
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
$manifest = [ordered]@{
    channel = "stable"
    publicProduct = $true
    productionPublished = $false
    appVersion = $AppVersion
    windowsAppVersion = $WindowsAppVersion
    freeAccessPolicy = "server-configured"
    trialDays = $null
    plans = [object[]]@(
        [pscustomobject]@{ code = 'green_30d'; periodDays = 30; priceRub = 249 }
        [pscustomobject]@{ code = 'green_90d'; periodDays = 90; priceRub = 649 }
        [pscustomobject]@{ code = 'green_180d'; periodDays = 180; priceRub = 1099 }
    )
    autoRenew = $false
    autoRenewRequiresExplicitConsent = $true
    adsEnabled = [bool]$EnableAndroidRewardedAds
    transportCascade = $effectiveTransportCascade
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    artifacts = [object[]]$artifacts
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content `
    -LiteralPath (Join-Path $OutDir "public-product-artifacts.json") -Encoding utf8

$artifacts | Format-Table platform, version, sizeBytes, sha256, path -AutoSize | Out-Host
