param(
    [string]$Version = '2.0.1',
    [string]$SourceCommit = 'fb64e74ba5a0a54e9185b8776bcb8088afb772c9'
)

$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$moduleRoot = [IO.Path]::GetFullPath((Join-Path $repo 'android\transport_preview\awg_tunnel'))
$allowedModuleRoot = [IO.Path]::GetFullPath((Join-Path $repo 'android\transport_preview'))
if (-not $moduleRoot.StartsWith($allowedModuleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to prepare AWG2 outside $allowedModuleRoot"
}

$workRoot = Join-Path $env:TEMP ("greenvpn-awg2-android-" + [Guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $workRoot 'source'
$apkPath = Join-Path $workRoot "amneziawg-$Version.apk"
$extractRoot = Join-Path $workRoot 'apk'
$apkSha256 = '313A42014BD54C487E4592CEB64F023C588817F8C4EAEB465163F25C1E70AD33'

try {
    New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
    git clone --depth 1 --branch $Version https://github.com/amnezia-vpn/amneziawg-android.git $sourceRoot | Out-Host
    $actualCommit = (git -C $sourceRoot rev-parse HEAD).Trim()
    if ($actualCommit -ne $SourceCommit) {
        throw "Unexpected AmneziaWG Android commit: $actualCommit"
    }

    $apkUrl = "https://github.com/amnezia-vpn/amneziawg-android/releases/download/$Version/amneziawg-$Version.apk"
    Invoke-WebRequest -UseBasicParsing -Uri $apkUrl -OutFile $apkPath
    $actualApkSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash.ToUpperInvariant()
    if ($actualApkSha256 -ne $apkSha256) {
        throw "Unexpected AmneziaWG Android APK SHA256: $actualApkSha256"
    }

    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    tar -xf $apkPath -C $extractRoot

    if (Test-Path -LiteralPath $moduleRoot) {
        $resolvedExisting = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $moduleRoot).Path)
        if (-not $resolvedExisting.StartsWith($allowedModuleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unexpected path: $resolvedExisting"
        }
        Remove-Item -LiteralPath $resolvedExisting -Recurse -Force
    }

    $javaTarget = Join-Path $moduleRoot 'src\main\java'
    $jniTarget = Join-Path $moduleRoot 'src\main\jniLibs'
    New-Item -ItemType Directory -Force -Path $javaTarget, $jniTarget | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tunnel\src\main\java\org') -Destination $javaTarget -Recurse
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tunnel\src\main\AndroidManifest.xml') -Destination (Join-Path $moduleRoot 'src\main\AndroidManifest.xml')
    $goBackendPath = Join-Path $javaTarget 'org\amnezia\awg\backend\GoBackend.java'
    $goBackendSource = Get-Content -Raw -LiteralPath $goBackendPath
    $goBackendSource = $goBackendSource.Replace('loadSharedLibrary(context, "wg-go")', 'loadSharedLibrary(context, "awg2-go")')
    if (-not $goBackendSource.Contains('loadSharedLibrary(context, "awg2-go")')) {
        throw 'Failed to isolate the AWG2 native library name.'
    }
    [IO.File]::WriteAllText(
        $goBackendPath,
        $goBackendSource,
        [Text.UTF8Encoding]::new($false)
    )

    foreach ($abiDir in Get-ChildItem -LiteralPath (Join-Path $extractRoot 'lib') -Directory) {
        $sourceLibrary = Join-Path $abiDir.FullName 'libwg-go.so'
        if (-not (Test-Path -LiteralPath $sourceLibrary)) {
            throw "Missing libwg-go.so for ABI $($abiDir.Name)"
        }
        $abiTarget = Join-Path $jniTarget $abiDir.Name
        New-Item -ItemType Directory -Force -Path $abiTarget | Out-Null
        Copy-Item -LiteralPath $sourceLibrary -Destination (Join-Path $abiTarget 'libawg2-go.so')
    }

    @'
plugins {
    id("com.android.library")
}

android {
    namespace = "org.amnezia.awg.tunnel"
    compileSdk = 35
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.annotation:annotation:1.8.2")
    implementation("androidx.collection:collection:1.4.5")
    compileOnly("com.google.code.findbugs:jsr305:3.0.2")
}
'@ | Set-Content -LiteralPath (Join-Path $moduleRoot 'build.gradle.kts') -Encoding UTF8

    Copy-Item -LiteralPath (Join-Path $sourceRoot 'COPYING') -Destination (Join-Path $moduleRoot 'COPYING')
    @"
version=$Version
sourceCommit=$SourceCommit
officialApkSha256=$apkSha256
packagedNativeLibrary=libawg2-go.so (renamed from the official libwg-go.so)
excludedNativeLibraries=libwg.so,libwg-quick.so
"@ | Set-Content -LiteralPath (Join-Path $moduleRoot 'SOURCE-MANIFEST.txt') -Encoding ASCII

    Write-Host "Prepared AWG2 Android preview module: $moduleRoot"
    Write-Host "Source commit: $SourceCommit"
    Write-Host "Official APK SHA256: $apkSha256"
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        $resolvedWork = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $workRoot).Path)
        $allowedTemp = [IO.Path]::GetFullPath($env:TEMP)
        if ($resolvedWork.StartsWith($allowedTemp + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedWork -Recurse -Force
        }
    }
}
