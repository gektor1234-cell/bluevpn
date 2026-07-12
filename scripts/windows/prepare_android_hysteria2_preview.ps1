param(
    [string]$HysteriaRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\hysteria-app-v2.9.3-android',
    [string]$HevRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\hev-socks5-tunnel-2.14.4'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$moduleRoot = [IO.Path]::GetFullPath((Join-Path $repo 'android\transport_preview\hysteria_tunnel'))
$allowedModuleRoot = [IO.Path]::GetFullPath((Join-Path $repo 'android\transport_preview'))
$generatedHevRoot = Join-Path $moduleRoot 'src\main\jni\hev-socks5-tunnel'
$jniLibsRoot = Join-Path $moduleRoot 'src\main\jniLibs'

if (-not $moduleRoot.StartsWith($allowedModuleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to prepare Hysteria2 outside $allowedModuleRoot"
}
foreach ($required in @('build.gradle.kts', 'src\main\jni\Android.mk', 'src\main\jni\greenvpn_hysteria_bridge.c')) {
    if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot $required))) {
        throw "Hysteria2 preview module is incomplete: $required"
    }
}

$expectedHysteriaHashes = [ordered]@{
    '386' = '1120809703BE02C5836EF4989CC445CD1CCBCEB6E7B67860FEBC290BF73FCA8F'
    'amd64' = '89D6C7CD9AAD1356196F8E7240A01368536091F1B1FA1E3EA5DE691F81B908D1'
    'arm64' = '623B12826D13F8BB67F581396CF22C6639ABCBB6B1F22A42BF80350FFDAF50A3'
    'armv7' = 'CD226A6EEBA011E809295082CA11C0B57560F070192372994E8DD968205595CC'
}
$abiMap = [ordered]@{
    '386' = 'x86'
    'amd64' = 'x86_64'
    'arm64' = 'arm64-v8a'
    'armv7' = 'armeabi-v7a'
}
$expectedHevCommits = [ordered]@{
    '.' = '4d6c334dbfb68a79d1970c2744e62d09f71df12f'
    'src/core' = '4be2e621813ba0315cfacd995bf501bde91d6996'
    'third-part/hev-task-system' = '8d83bbbf79557138726c8ee5a5fae99cbb978d61'
    'third-part/lwip' = '07dbf162c718cc78ddedb9e67c6ebd17065eaf13'
    'third-part/yaml' = 'efa36117a8646d26d12b58e05bac472d7854a70d'
}

if (-not (Test-Path -LiteralPath (Join-Path $HysteriaRoot 'hashes.txt'))) {
    New-Item -ItemType Directory -Force -Path $HysteriaRoot | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/apernet/hysteria/releases/download/app%2Fv2.9.3/hashes.txt' -OutFile (Join-Path $HysteriaRoot 'hashes.txt')
}
$officialHashes = Get-Content -LiteralPath (Join-Path $HysteriaRoot 'hashes.txt') -Raw
foreach ($asset in $expectedHysteriaHashes.Keys) {
    $name = "hysteria-android-$asset"
    $expected = $expectedHysteriaHashes[$asset]
    if (-not $officialHashes.Contains($expected.ToLowerInvariant() + '  build/' + $name)) {
        throw "Official Hysteria2 hashes.txt does not pin $name"
    }
    $path = Join-Path $HysteriaRoot $name
    if (-not (Test-Path -LiteralPath $path)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/apernet/hysteria/releases/download/app%2Fv2.9.3/$name" -OutFile $path
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    if ($actual -ne $expected) { throw "Hysteria2 Android hash mismatch: $name" }
}

if (-not (Test-Path -LiteralPath (Join-Path $HevRoot '.git'))) {
    throw "Audited HEV source checkout is missing: $HevRoot"
}
foreach ($entry in $expectedHevCommits.GetEnumerator()) {
    $path = if ($entry.Key -eq '.') { $HevRoot } else { Join-Path $HevRoot $entry.Key }
    $actual = (git -C $path rev-parse HEAD).Trim()
    if ($actual -ne $entry.Value) {
        throw "HEV source revision mismatch for $($entry.Key): $actual"
    }
}

if (Test-Path -LiteralPath $generatedHevRoot) {
    $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $generatedHevRoot).Path)
    $allowed = [IO.Path]::GetFullPath((Join-Path $moduleRoot 'src\main\jni')) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace unexpected HEV path: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $generatedHevRoot, $jniLibsRoot | Out-Null

& robocopy.exe $HevRoot $generatedHevRoot /E /XD .git /XF .git /NFL /NDL /NJH /NJS /NC /NS | Out-Null
if ($LASTEXITCODE -gt 7) { throw "Failed to copy audited HEV source: robocopy=$LASTEXITCODE" }

# The audited checkout may live on a Windows filesystem without symlink support.
# Materialize every git mode 120000 entry so NDK sees the intended header/source.
foreach ($entry in $expectedHevCommits.GetEnumerator()) {
    $sourceRepo = if ($entry.Key -eq '.') { $HevRoot } else { Join-Path $HevRoot $entry.Key }
    $generatedRepo = if ($entry.Key -eq '.') { $generatedHevRoot } else { Join-Path $generatedHevRoot $entry.Key }
    foreach ($indexLine in @(git -C $sourceRepo ls-files -s)) {
        if ($indexLine -notmatch '^120000\s+[0-9a-f]{40}\s+0\t(.+)$') { continue }
        $relativeLink = $matches[1]
        $sourceLink = Join-Path $sourceRepo $relativeLink
        $targetText = (Get-Content -LiteralPath $sourceLink -Raw).Trim()
        if ([string]::IsNullOrWhiteSpace($targetText) -or [IO.Path]::IsPathRooted($targetText)) {
            throw "Unsafe HEV symlink target: $relativeLink"
        }
        $sourceTarget = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $sourceLink) $targetText))
        $allowedSource = [IO.Path]::GetFullPath($HevRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $sourceTarget.StartsWith($allowedSource, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $sourceTarget -PathType Leaf)) {
            throw "HEV symlink escaped the audited source tree: $relativeLink"
        }
        $generatedLink = Join-Path $generatedRepo $relativeLink
        Copy-Item -LiteralPath $sourceTarget -Destination $generatedLink -Force
    }
}

foreach ($asset in $expectedHysteriaHashes.Keys) {
    $abi = $abiMap[$asset]
    $targetDir = Join-Path $jniLibsRoot $abi
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    $target = Join-Path $targetDir 'libhysteria.so'
    Copy-Item -LiteralPath (Join-Path $HysteriaRoot "hysteria-android-$asset") -Destination $target -Force
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
    if ($actual -ne $expectedHysteriaHashes[$asset]) {
        throw "Prepared Hysteria2 binary hash mismatch for ABI $abi"
    }
}

Write-Host "Prepared Android Hysteria2 preview module: $moduleRoot"
Write-Host 'Hysteria2 app/v2.9.3: four official Android ABIs verified'
Write-Host 'HEV 2.14.4: root and four submodule revisions verified'
Write-Host 'Hysteria built-in TUN: excluded'
