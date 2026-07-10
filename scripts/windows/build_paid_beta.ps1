param(
    [ValidateSet("android", "windows", "both")]
    [string]$Mode = "both",
    [string]$AppVersion = "0.3.0-paid-beta.1",
    [string]$AndroidBuildName = "0.3.0",
    [string]$AndroidBuildNumber = "2026071001",
    [string]$ApiBaseUrl = "https://api.greenvpn.pro/paid-beta-api",
    [string]$ApiFallbackBaseUrls = "https://176-113-81-35.sslip.io/paid-beta-api",
    [string]$ClientMarker = "green-vpn-paid-beta-v1",
    [string]$OutDir = "C:\BlueVPN_Builds\paid_beta_20260710",
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
if ($ClientMarker -ne "green-vpn-paid-beta-v1") {
    throw "Unexpected paid beta client marker."
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
    $hadAppVersion = Test-Path Env:\GREENVPN_APP_VERSION
    $oldAppVersion = $env:GREENVPN_APP_VERSION
    try {
        $env:ANDROID_HOME = $androidSdk
        $env:ANDROID_SDK_ROOT = $androidSdk
        $env:JAVA_HOME = $jdkDir
        $env:Path = "$jdkDir\bin;$androidSdk\platform-tools;$env:Path"
        $env:GREENVPN_APP_VERSION = $AppVersion

        flutter build apk --release --no-pub `
            --build-name $AndroidBuildName `
            --build-number $AndroidBuildNumber `
            --dart-define="GREENVPN_APP_VERSION=$AppVersion" `
            --dart-define="GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false" `
            --dart-define="GREENVPN_PAID_BETA_BUILD=true" `
            --dart-define="GREENVPN_PAID_BETA_CLIENT_MARKER=$ClientMarker" `
            --dart-define="GREENVPN_YANDEX_REWARDED_ADS_ENABLED=false" `
            --dart-define="BLUEVPN_API_BASE_URL=$ApiBaseUrl" `
            --dart-define="BLUEVPN_API_BASE_URLS=$ApiFallbackBaseUrls" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Android paid beta build failed" }
    }
    finally {
        $env:ANDROID_HOME = $oldAndroidHome
        $env:ANDROID_SDK_ROOT = $oldAndroidSdkRoot
        $env:JAVA_HOME = $oldJavaHome
        $env:Path = $oldPath
        if ($hadAppVersion) {
            $env:GREENVPN_APP_VERSION = $oldAppVersion
        } else {
            Remove-Item Env:\GREENVPN_APP_VERSION -ErrorAction SilentlyContinue
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

    $item = Get-Item -LiteralPath $androidPath
    $artifacts.Add([pscustomobject]@{
        platform = "android"
        version = $AppVersion
        buildNumber = $AndroidBuildNumber
        path = $item.FullName
        fileName = $item.Name
        sizeBytes = $item.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash
        signed = $true
    })
}

if ($Mode -in @("windows", "both")) {
    $windowsName = "GreenVPN_Setup_${safeVersion}.exe"
    & (Join-Path $PSScriptRoot "build_installer.ps1") `
        -ProjectRoot $repo `
        -OutBase $OutDir `
        -InstallerName $windowsName `
        -AppVersion $AppVersion `
        -ApiBaseUrl $ApiBaseUrl `
        -ApiFallbackBaseUrls $ApiFallbackBaseUrls `
        -TrialOnlyNoAdsBuild $false `
        -PaidBetaBuild $true
    if ($LASTEXITCODE -ne 0) { throw "Windows paid beta installer build failed" }

    $windowsPath = Join-Path $OutDir $windowsName
    $item = Get-Item -LiteralPath $windowsPath
    $signature = Get-AuthenticodeSignature -LiteralPath $item.FullName
    $artifacts.Add([pscustomobject]@{
        platform = "windows"
        version = $AppVersion
        buildNumber = ""
        path = $item.FullName
        fileName = $item.Name
        sizeBytes = $item.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash
        signed = $signature.Status -eq "Valid"
        signatureStatus = $signature.Status.ToString()
    })
}

$manifest = [pscustomobject]@{
    channel = "paid-beta"
    isolated = $true
    productionPublished = $false
    appVersion = $AppVersion
    clientMarker = $ClientMarker
    apiBaseUrl = $ApiBaseUrl
    apiFallbackBaseUrls = $ApiFallbackBaseUrls
    trialOnlyNoAdsBuild = $false
    paidBetaBuild = $true
    rewardedAdsEnabled = $false
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    artifacts = @($artifacts | ForEach-Object { $_ })
}
$manifestPath = Join-Path $OutDir "paid-beta-artifacts.json"
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Paid beta artifacts:" -ForegroundColor Green
$artifacts | Format-Table platform, version, sizeBytes, sha256, path -AutoSize | Out-Host
Write-Host "Manifest: $manifestPath" -ForegroundColor Green
