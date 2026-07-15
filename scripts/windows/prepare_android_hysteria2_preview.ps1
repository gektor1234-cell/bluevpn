param(
    [string]$HysteriaRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\hysteria-app-v2.9.3-android-api24',
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
    'amd64' = '0CB45CBBF3E1D5CC0B2B9F54750D8D491CEDB4B11C203A944C3BE587C554A353'
    'arm64' = '0A019366C970C5298835E155A2923E35A42E7C72505EFC93F9D3F21D2D8C9454'
    'armv7' = 'F900A64CAF83916228E17D61CFB8937A3E2D49228B955DDBB9D508AEC44D761A'
}
$abiMap = [ordered]@{
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

$manifestPath = Join-Path $HysteriaRoot 'build-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Pinned API24 build manifest is missing. Run build_android_hysteria2_api24.ps1 first: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.hysteriaVersion -ne 'app/v2.9.3' -or
    $manifest.sourceCommit -ne '2d973f9513ef661d1922d6d14acb37945caef47d' -or
    [int]$manifest.minAndroidApi -ne 24 -or
    $manifest.goArchiveSha256 -ne '4A974DE310E7EE1D523D2FCEDB114BA5FA75408C98EB3652023E55CCF3FA7CAB' -or
    $manifest.ndkRevision -ne '28.2.13676358') {
    throw 'Pinned Hysteria2 API24 build provenance mismatch.'
}
foreach ($asset in $expectedHysteriaHashes.Keys) {
    $name = "hysteria-android-$asset"
    $expected = $expectedHysteriaHashes[$asset]
    $path = Join-Path $HysteriaRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Hysteria2 API24 binary is missing: $path" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    if ($actual -ne $expected) { throw "Hysteria2 Android API24 hash mismatch: $name" }
    $manifestFile = @($manifest.files | Where-Object file -eq $name)
    if ($manifestFile.Count -ne 1 -or $manifestFile[0].sha256 -ne $expected) {
        throw "Hysteria2 API24 manifest does not pin $name"
    }
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
Write-Host 'Hysteria2 app/v2.9.3: three reproducible Android API24 ABIs verified'
Write-Host 'HEV 2.14.4: root and four submodule revisions verified'
Write-Host 'Hysteria built-in TUN: excluded'
