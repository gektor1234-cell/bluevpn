param(
    [switch]$RebuildNative,
    [string]$SourceDir,
    [string]$GoExe,
    [string]$NdkRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$moduleRoot = Join-Path $repo "android\transport_preview\awg_tunnel"
$requiredTrackedPaths = @(
    "build.gradle.kts",
    "COPYING",
    "SOURCE-MANIFEST.txt",
    "src\main\AndroidManifest.xml",
    "src\main\java\org\amnezia\awg\backend\GoBackend.java",
    "src\main\java\pro\greenvpn\awg2\GreenVpnAwg2VpnService.java"
)
foreach ($relativePath in $requiredTrackedPaths) {
    $required = Join-Path $moduleRoot $relativePath
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Tracked AWG2 source input is missing: $required"
    }
}

$builder = Join-Path $PSScriptRoot "build_android_awg2_native.ps1"
$arguments = @{}
if (-not [string]::IsNullOrWhiteSpace($SourceDir)) {
    $arguments.SourceDir = $SourceDir
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
    throw "Pinned AWG2 native preparation failed with exit code $LASTEXITCODE."
}

Write-Host "Tracked AWG2 Android module is ready."
