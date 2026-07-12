param(
    [string]$XrayRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\xray-core-v26.7.11\android-arm64-v8a'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$moduleRoot = [IO.Path]::GetFullPath((Join-Path $repo 'android\transport_preview\hysteria_tunnel'))
$allowedModuleRoot = [IO.Path]::GetFullPath((Join-Path $repo 'android\transport_preview'))
$jniLibsRoot = Join-Path $moduleRoot 'src\main\jniLibs'
$xrayZip = Join-Path $XrayRoot 'Xray-android-arm64-v8a.zip'
$xrayBinary = Join-Path $XrayRoot 'extracted\xray'
$xrayLicense = Join-Path $XrayRoot 'extracted\LICENSE'

if (-not $moduleRoot.StartsWith($allowedModuleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to prepare VLESS REALITY outside $allowedModuleRoot"
}
foreach ($required in @(
    'build.gradle.kts',
    'src\main\kotlin\pro\greenvpn\vless\VlessRealityConfig.kt',
    'src\main\kotlin\pro\greenvpn\vless\VlessRealityVpnService.kt'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot $required))) {
        throw "VLESS REALITY preview module is incomplete: $required"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot 'src\main\jni\hev-socks5-tunnel'))) {
    throw 'Audited HEV source is not prepared. Run prepare_android_hysteria2_preview.ps1 first.'
}

$expectedZipHash = '4B9CD6A4D6CBB2ABCB4CC410A03EBBEBC17B7B405DF0467A5F615617744B681E'
$expectedBinaryHash = 'EA227CFB125FA093257F1A8227B5C6E30D93301D05F2E6AB8B79152F7AFF8CDB'
$expectedLicenseHash = '1F256ECAD192880510E84AD60474EAB7589218784B9A50BC7CEEE34C2B91F1D5'
if (-not (Test-Path -LiteralPath $xrayZip)) {
    New-Item -ItemType Directory -Force -Path $XrayRoot | Out-Null
    Invoke-WebRequest -UseBasicParsing `
        -Uri 'https://github.com/XTLS/Xray-core/releases/download/v26.7.11/Xray-android-arm64-v8a.zip' `
        -OutFile $xrayZip
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $xrayZip).Hash -ne $expectedZipHash) {
    throw 'Official Xray Android archive hash mismatch.'
}
if (-not (Test-Path -LiteralPath $xrayBinary) -or -not (Test-Path -LiteralPath $xrayLicense)) {
    $extractRoot = Join-Path $XrayRoot 'extracted'
    if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Recurse -Force }
    Expand-Archive -LiteralPath $xrayZip -DestinationPath $extractRoot
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $xrayBinary).Hash -ne $expectedBinaryHash) {
    throw 'Official Xray Android binary hash mismatch.'
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $xrayLicense).Hash -ne $expectedLicenseHash) {
    throw 'Xray MPL-2.0 license hash mismatch.'
}

$targetDir = Join-Path $jniLibsRoot 'arm64-v8a'
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
$target = Join-Path $targetDir 'libxray.so'
Copy-Item -LiteralPath $xrayBinary -Destination $target -Force
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash -ne $expectedBinaryHash) {
    throw 'Prepared Xray Android binary hash mismatch.'
}

Write-Host "Prepared Android VLESS REALITY preview module: $moduleRoot"
Write-Host "Xray-core v26.7.11 Android arm64-v8a verified: $expectedBinaryHash"
Write-Host 'Xray-core license: MPL-2.0; source notice is bundled from docs/licenses.'
