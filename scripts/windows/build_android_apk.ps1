param(
    [ValidateSet("debug", "release", "both")]
    [string]$Mode = "both",

    [switch]$EnableYandexRewardedAds,
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
$releaseAppVersion = "0.2.23-trial-only-android-vpn-takeover"
$releaseBuildName = "0.2.23"
$releaseBuildNumber = "2026060801"
if ($Mode -eq "debug" -or $Mode -eq "both") {
    flutter build apk --debug --no-pub | Out-Host
    $builds += "build\app\outputs\flutter-apk\app-debug.apk"
}
if ($Mode -eq "release" -or $Mode -eq "both") {
    $releaseArgs = @("build", "apk", "--release", "--no-pub")
    $releaseArgs += "--dart-define=GREENVPN_APP_VERSION=$releaseAppVersion"
    $releaseArgs += "--build-name=$releaseBuildName"
    $releaseArgs += "--build-number=$releaseBuildNumber"
    if ($EnableYandexRewardedAds -or $DeployPreview) {
        $releaseAppVersion = "0.2.25-adgate-preview-update-demo"
        $releaseBuildName = "0.2.25"
        $releaseBuildNumber = "2026061302"
        $releaseArgs[4] = "--dart-define=GREENVPN_APP_VERSION=$releaseAppVersion"
        $releaseArgs[5] = "--build-name=$releaseBuildName"
        $releaseArgs[6] = "--build-number=$releaseBuildNumber"
        $releaseArgs += "--dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=true"
        $releaseArgs += "--dart-define=GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false"
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
foreach ($apk in $builds) {
    $item = Get-Item $apk
    $hash = Get-FileHash -Algorithm SHA256 $item.FullName
    Write-Host ""
    Write-Host "APK: $($item.FullName)"
    Write-Host "Size: $($item.Length) bytes"
    Write-Host "SHA256: $($hash.Hash)"
    if (Test-Path $apksigner) {
        & $apksigner verify --verbose $item.FullName | Out-Host
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
