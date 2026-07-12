param(
    [string]$ThirdPartyRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\amneziawg-windows-client-2.0.0\extracted\AmneziaWG',
    [string]$OutDir = 'C:\BlueVPN_Builds\windows_transport_preview_20260711',
    [string]$AppVersion = '0.3.0-transport-preview.1',
    [switch]$SkipChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$licensePath = Join-Path $repo 'docs\licenses\AMNEZIAWG_WINDOWS_CLIENT_MIT.txt'
$expectedHashes = @{
    'amneziawg.exe' = '5B00905ED02619FE149CEAFC898E79993D4455A0CDFA92072B3BB9AEE7B2D537'
    'awg.exe' = '26AC0BE14A8353EACF2F933736F6F7912F89EC7C59C4190CC990492934C74537'
    'wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
}

if (-not (Test-Path -LiteralPath $licensePath)) {
    throw "Missing AmneziaWG Windows license notice: $licensePath"
}

foreach ($name in $expectedHashes.Keys) {
    $path = Join-Path $ThirdPartyRoot $name
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing official AWG2 runtime: $path" }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    if ($hash -ne $expectedHashes[$name]) { throw "AWG2 runtime hash mismatch: $name" }
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) { throw "AWG2 runtime signature invalid: $name" }
}
if ((Get-Item -LiteralPath (Join-Path $ThirdPartyRoot 'amneziawg.exe')).VersionInfo.FileVersion -notlike '2.*') {
    throw 'AWG2 preview requires AmneziaWG Windows 2.x.'
}

Set-Location $repo
if (-not $SkipChecks) {
    flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
    flutter test --no-pub | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
}

$runtime = [ordered]@{
    GREENVPN_WINDOWS_RUNTIME_SCOPE = 'transport-preview'
    GREENVPN_WINDOWS_TUNNEL_NAME = 'GreenVPNTransportPreview'
    GREENVPN_WINDOWS_SERVICE_NAME = 'GreenVPNTransportPreviewService'
    GREENVPN_WINDOWS_PROGRAM_DATA_SUBDIR = 'BlueVPNTransportPreview'
    GREENVPN_WINDOWS_USER_DATA_SUBDIR = 'GreenVPNTransportPreview'
    GREENVPN_WINDOWS_LOCAL_SERVICE_PORT = '48739'
    GREENVPN_WINDOWS_INSTANCE_ID = 'GreenVPNTransportPreview'
    GREENVPN_WINDOWS_EXECUTABLE_NAME = 'greenvpn_transport_preview.exe'
    GREENVPN_PRODUCT_NAME = 'Green VPN Transport Preview'
}
$previous = @{}
foreach ($name in $runtime.Keys) {
    $previous[$name] = [pscustomobject]@{ Exists = Test-Path "Env:$name"; Value = [Environment]::GetEnvironmentVariable($name, 'Process') }
    Set-Item -LiteralPath "Env:$name" -Value $runtime[$name]
}

$windowsBuildRoot = Join-Path $repo 'build\windows\x64'
if (Test-Path -LiteralPath $windowsBuildRoot) {
    $resolved = [IO.Path]::GetFullPath($windowsBuildRoot)
    if (-not $resolved.StartsWith(([IO.Path]::GetFullPath($repo).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe Windows build cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

try {
    flutter build windows --release -t .\lib\main.dart `
        --dart-define="GREENVPN_APP_VERSION=$AppVersion" `
        --dart-define="GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false" `
        --dart-define="GREENVPN_PAID_BETA_BUILD=true" `
        --dart-define="GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1" `
        --dart-define="GREENVPN_AWG2_PREVIEW_ENABLED=true" `
        --dart-define="GREENVPN_WINDOWS_RUNTIME_SCOPE=$($runtime.GREENVPN_WINDOWS_RUNTIME_SCOPE)" `
        --dart-define="GREENVPN_WINDOWS_TUNNEL_NAME=$($runtime.GREENVPN_WINDOWS_TUNNEL_NAME)" `
        --dart-define="GREENVPN_WINDOWS_SERVICE_NAME=$($runtime.GREENVPN_WINDOWS_SERVICE_NAME)" `
        --dart-define="GREENVPN_WINDOWS_PROGRAM_DATA_SUBDIR=$($runtime.GREENVPN_WINDOWS_PROGRAM_DATA_SUBDIR)" `
        --dart-define="GREENVPN_WINDOWS_USER_DATA_SUBDIR=$($runtime.GREENVPN_WINDOWS_USER_DATA_SUBDIR)" `
        --dart-define="GREENVPN_WINDOWS_LOCAL_SERVICE_PORT=$($runtime.GREENVPN_WINDOWS_LOCAL_SERVICE_PORT)" `
        --dart-define="GREENVPN_PRODUCT_NAME=$($runtime.GREENVPN_PRODUCT_NAME)" `
        --dart-define="GREENVPN_YANDEX_REWARDED_ADS_ENABLED=false" `
        --dart-define="BLUEVPN_API_BASE_URL=https://api.greenvpn.pro/paid-beta-api" `
        --dart-define="BLUEVPN_API_BASE_URLS=https://176-113-81-35.sslip.io/paid-beta-api"
    if ($LASTEXITCODE -ne 0) { throw 'Windows transport preview build failed' }
} finally {
    foreach ($name in $runtime.Keys) {
        if ($previous[$name].Exists) {
            Set-Item -LiteralPath "Env:$name" -Value $previous[$name].Value
        } else {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
    }
}

$releaseDir = Join-Path $windowsBuildRoot 'runner\Release'
$appDir = Join-Path $OutDir 'app'
$allowedOutRoot = [IO.Path]::GetFullPath('C:\BlueVPN_Builds').TrimEnd('\') + '\'
$resolvedOutDir = [IO.Path]::GetFullPath($OutDir).TrimEnd('\') + '\'
if (-not $resolvedOutDir.StartsWith($allowedOutRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe transport preview output path: $resolvedOutDir"
}
if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item -LiteralPath $releaseDir -Destination $appDir -Recurse -Force
Move-Item -LiteralPath (Join-Path $appDir 'bluevpn.exe') -Destination (Join-Path $appDir 'greenvpn_transport_preview.exe') -Force
Move-Item -LiteralPath (Join-Path $appDir 'greenvpn_service.exe') -Destination (Join-Path $appDir 'greenvpn_transport_preview_service.exe') -Force

$toolsDir = Join-Path $appDir 'tools'
$awgDir = Join-Path $toolsDir 'amneziawg2'
New-Item -ItemType Directory -Force -Path $awgDir | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'scripts\windows\greenvpn_transport_preview_vpn_task.ps1') -Destination $toolsDir -Force
foreach ($name in $expectedHashes.Keys) { Copy-Item -LiteralPath (Join-Path $ThirdPartyRoot $name) -Destination $awgDir -Force }
Copy-Item -LiteralPath (Join-Path $repo 'scripts\windows\install_windows_transport_preview.ps1') -Destination $OutDir -Force
Copy-Item -LiteralPath (Join-Path $repo 'scripts\windows\uninstall_windows_transport_preview.ps1') -Destination $OutDir -Force
Copy-Item -LiteralPath (Join-Path $repo 'docs\THIRD_PARTY_AWG2_WINDOWS_PREVIEW.md') -Destination $OutDir -Force
Copy-Item -LiteralPath $licensePath -Destination (Join-Path $OutDir 'AMNEZIAWG_WINDOWS_CLIENT_MIT.txt') -Force

$artifactRows = Get-ChildItem -LiteralPath $OutDir -Recurse -File | ForEach-Object {
    [pscustomobject]@{ path = $_.FullName.Substring($OutDir.Length).TrimStart('\'); size = $_.Length; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash }
}
$manifest = [ordered]@{
    appVersion = $AppVersion
    runtimeScope = 'transport-preview'
    tunnelName = 'GreenVPNTransportPreview'
    serviceName = 'GreenVPNTransportPreviewService'
    localPort = 48739
    awgSource = 'https://github.com/amnezia-vpn/amneziawg-windows-client/releases/tag/2.0.0'
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    files = @($artifactRows)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'manifest.json') -Encoding UTF8

$zip = Join-Path $OutDir 'GreenVPN_Windows_Transport_Preview_0.3.0-preview1.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $OutDir 'app'), (Join-Path $OutDir 'install_windows_transport_preview.ps1'), (Join-Path $OutDir 'uninstall_windows_transport_preview.ps1'), (Join-Path $OutDir 'THIRD_PARTY_AWG2_WINDOWS_PREVIEW.md'), (Join-Path $OutDir 'AMNEZIAWG_WINDOWS_CLIENT_MIT.txt'), (Join-Path $OutDir 'manifest.json') -DestinationPath $zip -Force
Get-Item -LiteralPath $zip | Select-Object FullName,Length
Get-FileHash -Algorithm SHA256 -LiteralPath $zip
