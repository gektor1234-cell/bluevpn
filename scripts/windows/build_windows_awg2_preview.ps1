param(
    [string]$ThirdPartyRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\amneziawg-windows-client-2.0.0\extracted\AmneziaWG',
    [string]$HysteriaRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\hysteria-app-v2.9.3',
    [string]$HevRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\hev-socks5-tunnel-2.14.4-release\extracted\hev-socks5-tunnel',
    [string]$XrayRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\xray-core-v26.7.11\windows-64',
    [string]$NaiveRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\naiveproxy_v150.0.7871.63-1\win-extract\naiveproxy-v150.0.7871.63-1-win-x64',
    [string]$DnsttRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_dnstt_20260712',
    [string]$ProcessRouterRoot = '',
    [string]$OutDir = 'C:\BlueVPN_Builds\windows_transport_preview_20260712_naive',
    [string]$AppVersion = '0.3.0-transport-preview.3',
    [string]$WindowsBuildName = '0.3.0',
    [ValidateRange(0, 65535)]
    [int]$WindowsBuildNumber = 1511,
    [string]$ApiBaseUrl = 'https://api.greenvpn.pro/paid-beta-api',
    [string]$ApiFallbackBaseUrls = 'https://176-113-81-35.sslip.io/paid-beta-api',
    [switch]$PublicProductCandidate,
    [switch]$SkipChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($ProcessRouterRoot)) {
    $ProcessRouterRoot = Join-Path $repo 'third_party\windows\process_router'
}
if ($WindowsBuildName -notmatch '^\d+\.\d+\.\d+$') {
    throw "WindowsBuildName must be a numeric x.y.z version: $WindowsBuildName"
}
if ($PublicProductCandidate) {
    if ($ApiBaseUrl.Contains('/paid-beta-api') -or $ApiFallbackBaseUrls.Contains('/paid-beta-api')) {
        throw 'Public-product candidate must use production API roots.'
    }
} elseif (-not $ApiBaseUrl.Contains('/paid-beta-api') -or -not $ApiFallbackBaseUrls.Contains('/paid-beta-api')) {
    throw 'Transport preview must use the isolated paid-beta API roots.'
}
$licensePath = Join-Path $repo 'docs\licenses\AMNEZIAWG_WINDOWS_CLIENT_MIT.txt'
$hysteriaLicensePath = Join-Path $repo 'docs\licenses\HYSTERIA_APP_MIT.txt'
$hevLicensePath = Join-Path $repo 'docs\licenses\HEV_SOCKS5_TUNNEL_MIT.txt'
$hevLwipLicensePath = Join-Path $repo 'docs\licenses\HEV_LWIP_BSD.txt'
$hevWintunLicensePath = Join-Path $repo 'docs\licenses\HEV_WINTUN_PREBUILT_BINARY_LICENSE.txt'
$xraySourceNoticePath = Join-Path $repo 'docs\licenses\XRAY_CORE_MPL_SOURCE_NOTICE.txt'
$xrayLicensePath = Join-Path $XrayRoot 'LICENSE'
$naiveLicensePath = Join-Path $repo 'docs\licenses\NAIVEPROXY_BSD_3_CLAUSE.txt'
$dnsttLicensePath = Join-Path $repo 'docs\licenses\DNSTT_PUBLIC_DOMAIN_COPYING.txt'
$expectedHashes = @{
    'amneziawg.exe' = '5B00905ED02619FE149CEAFC898E79993D4455A0CDFA92072B3BB9AEE7B2D537'
    'awg.exe' = '26AC0BE14A8353EACF2F933736F6F7912F89EC7C59C4190CC990492934C74537'
    'wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
}
$expectedHysteriaHashes = @{
    'hysteria-windows-amd64.exe' = 'BCD3865B09BE2E5CC18D117DCF3AD687D1E6E27B0B050376B9CF4EA251B64D6F'
    'hev-socks5-tunnel.exe' = '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E'
    'msys-2.0.dll' = '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18'
    'wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
}
$expectedVlessHashes = @{
    'xray.exe' = '4B43C5EF596F326B233717B585D31A85DD5CD5F77D8DA872E75F7EBC00E99ACB'
    'hev-socks5-tunnel.exe' = '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E'
    'msys-2.0.dll' = '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18'
    'wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
}
$expectedNaiveHashes = @{
    'naive.exe' = '94F99801C665D29FC071624663C6F7BFA59E8D5EFAA84CD08EF5EBB18B46CB62'
    'hev-socks5-tunnel.exe' = '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E'
    'msys-2.0.dll' = '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18'
    'wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
}
$expectedDnsttHashes = @{
    'dnstt-client-windows-amd64.exe' = '282995EA68FD13514AC033BC953193AD11CF01F83BB6E3F97929089E5BD85A99'
    'hev-socks5-tunnel.exe' = '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E'
    'msys-2.0.dll' = '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18'
    'wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
}
$expectedProcessRouterHashes = @{
    'ProxyBridge_CLI.exe' = '6C215C7975E3CBEE086DE0EE2F3226FAE84F35A7B0A2FFD432FC346EF56A0569'
    'ProxyBridgeCore.dll' = 'AFBD2296022A9CE96884069BBB32FCB1B1E9EC7203C4A219E50E21D7E791ECD2'
    'WinDivert.dll' = 'C1E060EE19444A259B2162F8AF0F3FE8C4428A1C6F694DCE20DE194AC8D7D9A2'
    'WinDivert64.sys' = '8DA085332782708D8767BCACE5327A6EC7283C17CFB85E40B03CD2323A90DDC2'
}

if (-not (Test-Path -LiteralPath $licensePath)) {
    throw "Missing AmneziaWG Windows license notice: $licensePath"
}
foreach ($notice in @($hysteriaLicensePath, $hevLicensePath, $hevLwipLicensePath, $hevWintunLicensePath)) {
    if (-not (Test-Path -LiteralPath $notice)) { throw "Missing Hysteria2 preview license notice: $notice" }
}
foreach ($notice in @($xraySourceNoticePath, $xrayLicensePath)) {
    if (-not (Test-Path -LiteralPath $notice)) { throw "Missing Xray preview license material: $notice" }
}
if (-not (Test-Path -LiteralPath $naiveLicensePath)) {
    throw "Missing Naive HTTPS preview license notice: $naiveLicensePath"
}
if (-not (Test-Path -LiteralPath $dnsttLicensePath)) {
    throw "Missing dnstt license notice: $dnsttLicensePath"
}
foreach ($name in $expectedProcessRouterHashes.Keys) {
    $path = Join-Path $ProcessRouterRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing process-router payload: $path"
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expectedProcessRouterHashes[$name]) {
        throw "Process-router payload hash mismatch: $name"
    }
}
$processRouterDriverSignature = Get-AuthenticodeSignature -LiteralPath (
    Join-Path $ProcessRouterRoot 'WinDivert64.sys'
)
if ($processRouterDriverSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw "Process-router driver signature invalid: $($processRouterDriverSignature.Status)"
}
foreach ($name in @('PROXYBRIDGE_LICENSE.txt', 'WINDIVERT_LICENSE.txt', 'PROVENANCE.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProcessRouterRoot $name) -PathType Leaf)) {
        throw "Missing process-router license/provenance file: $name"
    }
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

$hysteriaRuntimeSources = @{
    'hysteria-windows-amd64.exe' = (Join-Path $HysteriaRoot 'hysteria-windows-amd64.exe')
    'hev-socks5-tunnel.exe' = (Join-Path $HevRoot 'hev-socks5-tunnel.exe')
    'msys-2.0.dll' = (Join-Path $HevRoot 'msys-2.0.dll')
    'wintun.dll' = (Join-Path $HevRoot 'wintun.dll')
}
foreach ($name in $expectedHysteriaHashes.Keys) {
    $path = $hysteriaRuntimeSources[$name]
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing official Hysteria2 preview runtime: $path" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $expectedHysteriaHashes[$name]) {
        throw "Hysteria2 preview runtime hash mismatch: $name"
    }
}
$vlessRuntimeSources = @{
    'xray.exe' = (Join-Path $XrayRoot 'xray.exe')
    'hev-socks5-tunnel.exe' = (Join-Path $HevRoot 'hev-socks5-tunnel.exe')
    'msys-2.0.dll' = (Join-Path $HevRoot 'msys-2.0.dll')
    'wintun.dll' = (Join-Path $HevRoot 'wintun.dll')
}
foreach ($name in $expectedVlessHashes.Keys) {
    $path = $vlessRuntimeSources[$name]
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing official VLESS preview runtime: $path" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $expectedVlessHashes[$name]) {
        throw "VLESS preview runtime hash mismatch: $name"
    }
}
$naiveRuntimeSources = @{
    'naive.exe' = (Join-Path $NaiveRoot 'naive.exe')
    'hev-socks5-tunnel.exe' = (Join-Path $HevRoot 'hev-socks5-tunnel.exe')
    'msys-2.0.dll' = (Join-Path $HevRoot 'msys-2.0.dll')
    'wintun.dll' = (Join-Path $HevRoot 'wintun.dll')
}
foreach ($name in $expectedNaiveHashes.Keys) {
    $path = $naiveRuntimeSources[$name]
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing official Naive HTTPS preview runtime: $path" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $expectedNaiveHashes[$name]) {
        throw "Naive HTTPS preview runtime hash mismatch: $name"
    }
}
$dnsttRuntimeSources = @{
    'dnstt-client-windows-amd64.exe' = (Join-Path $DnsttRoot 'dnstt-client-windows-amd64.exe')
    'hev-socks5-tunnel.exe' = (Join-Path $HevRoot 'hev-socks5-tunnel.exe')
    'msys-2.0.dll' = (Join-Path $HevRoot 'msys-2.0.dll')
    'wintun.dll' = (Join-Path $HevRoot 'wintun.dll')
}
foreach ($name in $expectedDnsttHashes.Keys) {
    $path = $dnsttRuntimeSources[$name]
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing official dnstt preview runtime: $path" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $expectedDnsttHashes[$name]) {
        throw "dnstt preview runtime hash mismatch: $name"
    }
}

Set-Location $repo
if (-not $SkipChecks) {
    flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
    flutter test --no-pub | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
}

$customerProductName = if ($PublicProductCandidate) { 'Green VPN' } else { 'Green VPN Transport Preview' }
$paidBetaBuild = if ($PublicProductCandidate) { 'false' } else { 'true' }
$publicProductBuild = if ($PublicProductCandidate) { 'true' } else { 'false' }

$runtime = [ordered]@{
    GREENVPN_WINDOWS_RUNTIME_SCOPE = 'transport-preview'
    GREENVPN_WINDOWS_TUNNEL_NAME = 'GreenVPNTransportPreview'
    GREENVPN_WINDOWS_SERVICE_NAME = 'GreenVPNTransportPreviewService'
    GREENVPN_WINDOWS_PROGRAM_DATA_SUBDIR = 'BlueVPNTransportPreview'
    GREENVPN_WINDOWS_USER_DATA_SUBDIR = 'GreenVPNTransportPreview'
    GREENVPN_WINDOWS_LOCAL_SERVICE_PORT = '48739'
    GREENVPN_WINDOWS_INSTANCE_ID = 'GreenVPNTransportPreview'
    GREENVPN_WINDOWS_EXECUTABLE_NAME = 'greenvpn_transport_preview.exe'
    GREENVPN_PRODUCT_NAME = $customerProductName
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
        --build-name="$WindowsBuildName" `
        --build-number="$WindowsBuildNumber" `
        --dart-define="GREENVPN_APP_VERSION=$AppVersion" `
        --dart-define="GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=false" `
        --dart-define="GREENVPN_PAID_BETA_BUILD=$paidBetaBuild" `
        --dart-define="GREENVPN_PUBLIC_PRODUCT_BUILD=$publicProductBuild" `
        --dart-define="GREENVPN_PAID_BETA_CLIENT_MARKER=green-vpn-paid-beta-v1" `
        --dart-define="GREENVPN_AWG2_PREVIEW_ENABLED=true" `
        --dart-define="GREENVPN_HYSTERIA2_PREVIEW_ENABLED=true" `
        --dart-define="GREENVPN_VLESS_REALITY_PREVIEW_ENABLED=true" `
        --dart-define="GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED=true" `
        --dart-define="GREENVPN_DNSTT_PREVIEW_ENABLED=true" `
        --dart-define="GREENVPN_WINDOWS_RUNTIME_SCOPE=$($runtime.GREENVPN_WINDOWS_RUNTIME_SCOPE)" `
        --dart-define="GREENVPN_WINDOWS_TUNNEL_NAME=$($runtime.GREENVPN_WINDOWS_TUNNEL_NAME)" `
        --dart-define="GREENVPN_WINDOWS_SERVICE_NAME=$($runtime.GREENVPN_WINDOWS_SERVICE_NAME)" `
        --dart-define="GREENVPN_WINDOWS_PROGRAM_DATA_SUBDIR=$($runtime.GREENVPN_WINDOWS_PROGRAM_DATA_SUBDIR)" `
        --dart-define="GREENVPN_WINDOWS_USER_DATA_SUBDIR=$($runtime.GREENVPN_WINDOWS_USER_DATA_SUBDIR)" `
        --dart-define="GREENVPN_WINDOWS_LOCAL_SERVICE_PORT=$($runtime.GREENVPN_WINDOWS_LOCAL_SERVICE_PORT)" `
        --dart-define="GREENVPN_PRODUCT_NAME=$($runtime.GREENVPN_PRODUCT_NAME)" `
        --dart-define="GREENVPN_YANDEX_REWARDED_ADS_ENABLED=false" `
        --dart-define="BLUEVPN_API_BASE_URL=$ApiBaseUrl" `
        --dart-define="BLUEVPN_API_BASE_URLS=$ApiFallbackBaseUrls"
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
$hysteriaDir = Join-Path $toolsDir 'hysteria2'
$vlessDir = Join-Path $toolsDir 'vless-reality'
$naiveDir = Join-Path $toolsDir 'naive-https'
$dnsttDir = Join-Path $toolsDir 'dnstt'
$processRouterDir = Join-Path $toolsDir 'process-router'
New-Item -ItemType Directory -Force -Path $awgDir | Out-Null
New-Item -ItemType Directory -Force -Path $hysteriaDir | Out-Null
New-Item -ItemType Directory -Force -Path $vlessDir | Out-Null
New-Item -ItemType Directory -Force -Path $naiveDir | Out-Null
New-Item -ItemType Directory -Force -Path $dnsttDir | Out-Null
New-Item -ItemType Directory -Force -Path $processRouterDir | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'scripts\windows\greenvpn_transport_preview_vpn_task.ps1') -Destination $toolsDir -Force
Copy-Item -LiteralPath (Join-Path $repo 'scripts\windows\greenvpn_selective_routing.ps1') -Destination $toolsDir -Force
Copy-Item -LiteralPath (Join-Path $repo 'scripts\windows\greenvpn_hysteria2_watchdog.ps1') -Destination $toolsDir -Force
Copy-Item -LiteralPath (Join-Path $repo 'scripts\windows\greenvpn_vless_reality_watchdog.ps1') -Destination $toolsDir -Force
Copy-Item -LiteralPath (Join-Path $repo 'scripts\windows\greenvpn_naive_https_watchdog.ps1') -Destination $toolsDir -Force
Copy-Item -LiteralPath (Join-Path $repo 'scripts\windows\greenvpn_dnstt_watchdog.ps1') -Destination $toolsDir -Force
foreach ($name in $expectedHashes.Keys) { Copy-Item -LiteralPath (Join-Path $ThirdPartyRoot $name) -Destination $awgDir -Force }
foreach ($name in $expectedHysteriaHashes.Keys) { Copy-Item -LiteralPath $hysteriaRuntimeSources[$name] -Destination $hysteriaDir -Force }
foreach ($name in $expectedVlessHashes.Keys) { Copy-Item -LiteralPath $vlessRuntimeSources[$name] -Destination $vlessDir -Force }
foreach ($name in $expectedNaiveHashes.Keys) { Copy-Item -LiteralPath $naiveRuntimeSources[$name] -Destination $naiveDir -Force }
foreach ($name in $expectedDnsttHashes.Keys) { Copy-Item -LiteralPath $dnsttRuntimeSources[$name] -Destination $dnsttDir -Force }
foreach ($name in $expectedProcessRouterHashes.Keys) {
    Copy-Item -LiteralPath (Join-Path $ProcessRouterRoot $name) -Destination $processRouterDir -Force
}
foreach ($name in @('PROXYBRIDGE_LICENSE.txt', 'WINDIVERT_LICENSE.txt', 'PROVENANCE.md')) {
    Copy-Item -LiteralPath (Join-Path $ProcessRouterRoot $name) -Destination $processRouterDir -Force
}
@'
Green VPN Windows application routing uses:

- Green VPN ProxyBridge fork based on v4.0.0 (MIT License)
- WinDivert v2.2.2-A (see WINDIVERT_LICENSE.txt)

The corresponding license texts are distributed in this directory.
'@ | Set-Content -LiteralPath (Join-Path $processRouterDir 'THIRD_PARTY_NOTICES.txt') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $repo 'scripts\windows\install_windows_transport_preview.ps1') -Destination $OutDir -Force
Copy-Item -LiteralPath (Join-Path $repo 'scripts\windows\uninstall_windows_transport_preview.ps1') -Destination $OutDir -Force
Copy-Item -LiteralPath (Join-Path $repo 'docs\THIRD_PARTY_AWG2_WINDOWS_PREVIEW.md') -Destination $OutDir -Force
Copy-Item -LiteralPath $licensePath -Destination (Join-Path $OutDir 'AMNEZIAWG_WINDOWS_CLIENT_MIT.txt') -Force
Copy-Item -LiteralPath (Join-Path $repo 'docs\HYSTERIA2_CLIENT_ENGINE_LICENSE_AND_DESIGN_2026_07_12.md') -Destination $OutDir -Force
Copy-Item -LiteralPath $hysteriaLicensePath -Destination (Join-Path $OutDir 'HYSTERIA_APP_MIT.txt') -Force
Copy-Item -LiteralPath $hevLicensePath -Destination (Join-Path $OutDir 'HEV_SOCKS5_TUNNEL_MIT.txt') -Force
Copy-Item -LiteralPath $hevLwipLicensePath -Destination (Join-Path $OutDir 'HEV_LWIP_BSD.txt') -Force
Copy-Item -LiteralPath $hevWintunLicensePath -Destination (Join-Path $OutDir 'HEV_WINTUN_PREBUILT_BINARY_LICENSE.txt') -Force
Copy-Item -LiteralPath $xrayLicensePath -Destination (Join-Path $OutDir 'XRAY_CORE_MPL_2_0_LICENSE.txt') -Force
Copy-Item -LiteralPath $xraySourceNoticePath -Destination (Join-Path $OutDir 'XRAY_CORE_MPL_SOURCE_NOTICE.txt') -Force
Copy-Item -LiteralPath $naiveLicensePath -Destination (Join-Path $OutDir 'NAIVEPROXY_BSD_3_CLAUSE.txt') -Force
Copy-Item -LiteralPath $dnsttLicensePath -Destination (Join-Path $OutDir 'DNSTT_PUBLIC_DOMAIN_COPYING.txt') -Force

$artifactRows = Get-ChildItem -LiteralPath $OutDir -Recurse -File | ForEach-Object {
    [pscustomobject]@{ path = $_.FullName.Substring($OutDir.Length).TrimStart('\'); size = $_.Length; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash }
}
$manifest = [ordered]@{
    appVersion = $AppVersion
    windowsBuildName = $WindowsBuildName
    windowsBuildNumber = $WindowsBuildNumber
    publicProductCandidate = [bool]$PublicProductCandidate
    customerProductName = $customerProductName
    runtimeScope = 'transport-preview'
    tunnelName = 'GreenVPNTransportPreview'
    serviceName = 'GreenVPNTransportPreviewService'
    localPort = 48739
    awgSource = 'https://github.com/amnezia-vpn/amneziawg-windows-client/releases/tag/2.0.0'
    hysteriaSource = 'https://github.com/apernet/hysteria/releases/tag/app/v2.9.3'
    hevSource = 'https://github.com/heiher/hev-socks5-tunnel/releases/tag/2.14.4'
    xraySource = 'https://github.com/XTLS/Xray-core/tree/v26.7.11'
    naiveSource = 'https://github.com/klzgrad/naiveproxy/releases/tag/v150.0.7871.63-1'
    dnsttSource = 'https://www.bamsoftware.com/software/dnstt/'
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    files = @($artifactRows)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'manifest.json') -Encoding UTF8

$safeAppVersion = $AppVersion -replace '[^A-Za-z0-9._-]', '_'
$zipName = if ($PublicProductCandidate) {
    "GreenVPN_Windows_${safeAppVersion}_final_candidate.zip"
} else {
    "GreenVPN_Windows_Transport_Preview_${safeAppVersion}.zip"
}
$zip = Join-Path $OutDir $zipName
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
$packagePaths = @(
    (Join-Path $OutDir 'app'),
    (Join-Path $OutDir 'install_windows_transport_preview.ps1'),
    (Join-Path $OutDir 'uninstall_windows_transport_preview.ps1'),
    (Join-Path $OutDir 'THIRD_PARTY_AWG2_WINDOWS_PREVIEW.md'),
    (Join-Path $OutDir 'AMNEZIAWG_WINDOWS_CLIENT_MIT.txt'),
    (Join-Path $OutDir 'HYSTERIA2_CLIENT_ENGINE_LICENSE_AND_DESIGN_2026_07_12.md'),
    (Join-Path $OutDir 'HYSTERIA_APP_MIT.txt'),
    (Join-Path $OutDir 'HEV_SOCKS5_TUNNEL_MIT.txt'),
    (Join-Path $OutDir 'HEV_LWIP_BSD.txt'),
    (Join-Path $OutDir 'HEV_WINTUN_PREBUILT_BINARY_LICENSE.txt'),
    (Join-Path $OutDir 'XRAY_CORE_MPL_2_0_LICENSE.txt'),
    (Join-Path $OutDir 'XRAY_CORE_MPL_SOURCE_NOTICE.txt'),
    (Join-Path $OutDir 'NAIVEPROXY_BSD_3_CLAUSE.txt'),
    (Join-Path $OutDir 'DNSTT_PUBLIC_DOMAIN_COPYING.txt'),
    (Join-Path $OutDir 'manifest.json')
)
Compress-Archive -Path $packagePaths -DestinationPath $zip -Force
Get-Item -LiteralPath $zip | Select-Object FullName,Length
Get-FileHash -Algorithm SHA256 -LiteralPath $zip
