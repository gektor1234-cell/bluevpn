param(
    [string]$CacheRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_dnstt_20260712',
    [string]$SourceRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\dnstt-20260501'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$moduleRoot = [IO.Path]::GetFullPath((Join-Path $repo 'android\transport_preview\hysteria_tunnel'))
$allowedModuleRoot = [IO.Path]::GetFullPath((Join-Path $repo 'android\transport_preview'))
$sourceBinary = Join-Path $CacheRoot 'dnstt-client-android-arm64'
$sourceArchive = Join-Path $SourceRoot 'dnstt-20260501.zip'
$sourceSignature = Join-Path $SourceRoot 'dnstt-20260501.zip.asc'
$sourceKey = Join-Path $SourceRoot 'david.asc'
$license = Join-Path $repo 'docs\licenses\DNSTT_PUBLIC_DOMAIN_COPYING.txt'
$target = Join-Path $moduleRoot 'src\main\jniLibs\arm64-v8a\libdnstt_client.so'

if (-not $moduleRoot.StartsWith($allowedModuleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to prepare dnstt outside $allowedModuleRoot"
}
foreach ($required in @(
    'build.gradle.kts',
    'src\main\kotlin\pro\greenvpn\dnstt\DnsttConfig.kt',
    'src\main\kotlin\pro\greenvpn\dnstt\DnsttVpnService.kt'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot $required))) {
        throw "dnstt preview module is incomplete: $required"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot 'src\main\jni\hev-socks5-tunnel'))) {
    throw 'Audited HEV source is not prepared. Run prepare_android_hysteria2_preview.ps1 first.'
}

$expected = @{
    $sourceBinary = 'AAE616C0888DB31A61555CA4FE91B578E2A6734B7CEF7497B6FE30FFCDA1FDC5'
    $sourceArchive = 'A7B21D3D787570D9127643E360E150D2DA7B33AA8039D0546A04DCFE8EE1864F'
    $sourceSignature = '71AACF3EFCD21671D9F61BF084AF1833368B1543C7A61F5BCD54A5A602712F36'
    $sourceKey = '72783E9C98CD16A8048E38198CB13D673A3A320BA14AC9860F0379C0B4580FED'
    $license = 'A2010F343487D3F7618AFFE54F789F5487602331C0A8D03F49E9A7C547CF0499'
}
foreach ($entry in $expected.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) { throw "Pinned dnstt material is missing: $($entry.Key)" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Key).Hash -ne $entry.Value) {
        throw "Pinned dnstt material hash mismatch: $($entry.Key)"
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
Copy-Item -LiteralPath $sourceBinary -Destination $target -Force
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash -ne $expected[$sourceBinary]) {
    throw 'Prepared dnstt Android binary hash mismatch.'
}

Write-Host "Prepared Android dnstt preview module: $moduleRoot"
Write-Host "dnstt 20260501 Android arm64 verified: $($expected[$sourceBinary])"
Write-Host 'Upstream archive signature was verified on NL2 with signer fingerprint AD1AB35C674DF572FBCE8B0A6BC758CBC11F6276.'
Write-Host 'dnstt is public-domain software; upstream COPYING is bundled from docs/licenses.'
