param(
    [string]$AndroidSdk = $env:ANDROID_SDK_ROOT,
    [string]$JavaHome = $env:JAVA_HOME
)

$ErrorActionPreference = "Stop"

$version = "1.0.20260102"
$officialSha256 = "2B9C16DB026496123E4DB695D26D03D1958A201096C7C4C89B21077DC70F3119"
$officialUrl = "https://repo1.maven.org/maven2/com/wireguard/android/tunnel/$version/tunnel-$version.aar"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$sourcePath = Join-Path $repoRoot "android\vendor\wireguard\GoBackend.java"
$outputPath = Join-Path $repoRoot "android\app\libs\wireguard-tunnel-$version-greenvpn.aar"

if ([string]::IsNullOrWhiteSpace($AndroidSdk)) {
    throw "ANDROID_SDK_ROOT (or -AndroidSdk) is required."
}
if ([string]::IsNullOrWhiteSpace($JavaHome)) {
    throw "JAVA_HOME (or -JavaHome) is required."
}

$javac = Join-Path $JavaHome "bin\javac.exe"
$jar = Join-Path $JavaHome "bin\jar.exe"
if (-not (Test-Path -LiteralPath $javac -PathType Leaf)) {
    throw "javac.exe was not found under $JavaHome"
}
if (-not (Test-Path -LiteralPath $jar -PathType Leaf)) {
    throw "jar.exe was not found under $JavaHome"
}
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Patched GoBackend source is missing: $sourcePath"
}

$platform = Get-ChildItem (Join-Path $AndroidSdk "platforms") -Directory |
    Where-Object { $_.Name -match '^android-(\d+)$' } |
    Sort-Object { [int]($_.Name -replace '^android-', '') } -Descending |
    Select-Object -First 1
if ($null -eq $platform) {
    throw "No Android SDK platform is installed under $AndroidSdk"
}
$androidJar = Join-Path $platform.FullName "android.jar"

$work = Join-Path $env:TEMP ("greenvpn-wireguard-aar-" + [guid]::NewGuid().ToString("N"))
$officialAar = Join-Path $work "official.aar"
$aarDir = Join-Path $work "aar"
$classesDir = Join-Path $work "compiled"
$stubDir = Join-Path $work "stubs"

try {
    New-Item -ItemType Directory -Force -Path $work, $aarDir, $classesDir,
        (Join-Path $stubDir "androidx\annotation"),
        (Join-Path $stubDir "androidx\collection") | Out-Null

    Invoke-WebRequest -Uri $officialUrl -OutFile $officialAar
    $downloadedSha256 = (Get-FileHash -LiteralPath $officialAar -Algorithm SHA256).Hash
    if ($downloadedSha256 -ne $officialSha256) {
        throw "Official AAR checksum mismatch: $downloadedSha256"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($officialAar, $aarDir)
    $classesJar = Join-Path $aarDir "classes.jar"

    @'
package androidx.annotation;
public @interface Nullable {}
'@ | Set-Content -LiteralPath (Join-Path $stubDir "androidx\annotation\Nullable.java") -Encoding ascii

    @'
package androidx.collection;
public class ArraySet<E> extends java.util.HashSet<E> {}
'@ | Set-Content -LiteralPath (Join-Path $stubDir "androidx\collection\ArraySet.java") -Encoding ascii

    & $javac --release 17 -encoding UTF-8 `
        -classpath "$androidJar;$classesJar" `
        -d $classesDir `
        $sourcePath `
        (Join-Path $stubDir "androidx\annotation\Nullable.java") `
        (Join-Path $stubDir "androidx\collection\ArraySet.java")
    if ($LASTEXITCODE -ne 0) {
        throw "GoBackend compilation failed with exit code $LASTEXITCODE"
    }

    $backendClasses = Get-ChildItem (Join-Path $classesDir "com\wireguard\android\backend") `
        -Filter "GoBackend*.class"
    if ($backendClasses.Count -ne 3) {
        throw "Expected three GoBackend class files, found $($backendClasses.Count)."
    }

    Push-Location $classesDir
    try {
        & $jar --update --file $classesJar `
            "com/wireguard/android/backend/GoBackend.class" `
            'com/wireguard/android/backend/GoBackend$AlwaysOnCallback.class' `
            'com/wireguard/android/backend/GoBackend$VpnService.class'
        if ($LASTEXITCODE -ne 0) {
            throw "classes.jar update failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    $bytecode = & (Join-Path $JavaHome "bin\javap.exe") -classpath $classesJar -c -p `
        com.wireguard.android.backend.GoBackend
    if ($LASTEXITCODE -ne 0) {
        throw "Patched bytecode inspection failed."
    }
    if ($bytecode -match 'invokestatic.*wgVersion') {
        throw "Patched GoBackend still invokes wgVersion()."
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $outputPath -Parent) | Out-Null
    Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
    Push-Location $aarDir
    try {
        & $jar --create --file $outputPath .
        if ($LASTEXITCODE -ne 0) {
            throw "Patched AAR creation failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    $outputSha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
    Write-Output "Patched WireGuard AAR: $outputPath"
    Write-Output "SHA256: $outputSha256"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
