param(
    [switch]$RebuildNative,
    [string]$SourceRoot,
    [string]$GoExe,
    [string]$NdkRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$moduleRoot = Join-Path $repo "android\transport_preview\hysteria_tunnel"
$requiredTrackedPaths = @(
    "build.gradle.kts",
    "HYSTERIA-NATIVE-MANIFEST.json",
    "src\main\jni\Android.mk",
    "src\main\jni\Application.mk",
    "src\main\jni\greenvpn_hysteria_bridge.c",
    "src\main\jni\hev-socks5-tunnel\Android.mk",
    "src\main\jni\hev-socks5-tunnel\LICENSE"
)
foreach ($relativePath in $requiredTrackedPaths) {
    $required = Join-Path $moduleRoot $relativePath
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Tracked Hysteria2 source input is missing: $required"
    }
}

$builder = Join-Path $PSScriptRoot "build_android_hysteria2_native.ps1"
$arguments = @{}
if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
    $arguments.SourceRoot = $SourceRoot
}
if (-not [string]::IsNullOrWhiteSpace($GoExe)) {
    $arguments.GoExe = $GoExe
}
if (-not [string]::IsNullOrWhiteSpace($NdkRoot)) {
    $arguments.NdkRoot = $NdkRoot
}
if (-not $RebuildNative) {
    $arguments.VerifyOnly = $true
}

& $builder @arguments | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Pinned Hysteria2 native preparation failed with exit code $LASTEXITCODE."
}

Write-Host "Tracked Hysteria2 Android module is ready."
