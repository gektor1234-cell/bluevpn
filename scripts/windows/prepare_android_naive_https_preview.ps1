param(
    [string]$CacheRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\naiveproxy_v150.0.7871.63-1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$moduleRoot = [IO.Path]::GetFullPath((Join-Path $repo 'android\transport_preview\hysteria_tunnel'))
$allowedModuleRoot = [IO.Path]::GetFullPath((Join-Path $repo 'android\transport_preview'))
$apk = Join-Path $CacheRoot 'naiveproxy-plugin-v150.0.7871.63-1-arm64-v8a.apk'
$extractRoot = Join-Path $CacheRoot 'apk-extract'
$extractedBinary = Join-Path $extractRoot 'lib\arm64-v8a\libnaive.so'
$license = Join-Path $repo 'docs\licenses\NAIVEPROXY_BSD_3_CLAUSE.txt'
$target = Join-Path $moduleRoot 'src\main\jniLibs\arm64-v8a\libnaive.so'

if (-not $moduleRoot.StartsWith($allowedModuleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to prepare Naive HTTPS outside $allowedModuleRoot"
}
foreach ($required in @(
    'build.gradle.kts',
    'src\main\kotlin\pro\greenvpn\naive\NaiveHttpsConfig.kt',
    'src\main\kotlin\pro\greenvpn\naive\NaiveHttpsVpnService.kt'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot $required))) {
        throw "Naive HTTPS preview module is incomplete: $required"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot 'src\main\jni\hev-socks5-tunnel'))) {
    throw 'Audited HEV source is not prepared. Run prepare_android_hysteria2_preview.ps1 first.'
}

$expectedApkHash = '733FBBBEBB383A91F42036992C21CFD19B99E089AC3D15D7C077DF79FC471A89'
$expectedBinaryHash = '55B64ADBDA9FC09F4137800D74AC6772B797F96E224C12F69A8E001886BB82EB'
$expectedLicenseHash = '2B5D44220CEE7D541EFDEF3126CE838B2E73EAEBAE2F441AF3573CB2C0AF4D70'
if (-not (Test-Path -LiteralPath $apk)) {
    New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
    Invoke-WebRequest -UseBasicParsing `
        -Uri 'https://github.com/klzgrad/naiveproxy/releases/download/v150.0.7871.63-1/naiveproxy-plugin-v150.0.7871.63-1-arm64-v8a.apk' `
        -OutFile $apk
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $apk).Hash -ne $expectedApkHash) {
    throw 'Official NaiveProxy Android plugin hash mismatch.'
}
if (-not (Test-Path -LiteralPath $extractedBinary)) {
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    & tar -xf $apk -C $extractRoot 'lib/arm64-v8a/libnaive.so'
    if ($LASTEXITCODE -ne 0) { throw 'NaiveProxy Android binary extraction failed.' }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $extractedBinary).Hash -ne $expectedBinaryHash) {
    throw 'Official NaiveProxy Android binary hash mismatch.'
}
if (-not (Test-Path -LiteralPath $license) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $license).Hash -ne $expectedLicenseHash) {
    throw 'NaiveProxy BSD-3-Clause license hash mismatch.'
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
Copy-Item -LiteralPath $extractedBinary -Destination $target -Force
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash -ne $expectedBinaryHash) {
    throw 'Prepared NaiveProxy Android binary hash mismatch.'
}

Write-Host "Prepared Android Naive HTTPS preview module: $moduleRoot"
Write-Host "NaiveProxy v150.0.7871.63-1 Android arm64-v8a verified: $expectedBinaryHash"
Write-Host 'NaiveProxy license: BSD-3-Clause; license text is bundled from docs/licenses.'
