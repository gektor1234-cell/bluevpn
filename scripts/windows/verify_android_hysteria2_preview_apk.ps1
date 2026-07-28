param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,
    [string]$ExpectedPackage = 'pro.greenvpn.app.transportpreview',
    [string]$ExpectedVersionCode = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$androidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$buildTools = Join-Path $androidSdk 'build-tools\36.0.0'
$aapt2 = Join-Path $buildTools 'aapt2.exe'
$zipalign = Join-Path $buildTools 'zipalign.exe'
$apksigner = Join-Path $buildTools 'apksigner.bat'
$apkanalyzer = Join-Path $androidSdk 'cmdline-tools\latest\bin\apkanalyzer.bat'
foreach ($tool in @($aapt2, $zipalign, $apksigner, $apkanalyzer)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Android tool is missing: $tool" }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$nativeManifestPath = Join-Path $repo (
    'android\transport_preview\hysteria_tunnel\HYSTERIA-NATIVE-MANIFEST.json'
)
if (-not (Test-Path -LiteralPath $nativeManifestPath -PathType Leaf)) {
    throw "Tracked Hysteria2 native manifest is missing: $nativeManifestPath"
}
$nativeManifest = Get-Content -LiteralPath $nativeManifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if (
    [int]$nativeManifest.schemaVersion -ne 1 -or
    $nativeManifest.hysteriaVersion -ne 'app/v2.9.3' -or
    $nativeManifest.sourceCommit -ne '2d973f9513ef661d1922d6d14acb37945caef47d' -or
    $nativeManifest.goVersion -ne 'go1.25.1' -or
    $nativeManifest.ndkRevision -ne '28.2.13676358' -or
    [int]$nativeManifest.androidApi -ne 26 -or
    [int]$nativeManifest.pageSizeBytes -ne 16384 -or
    [int]$nativeManifest.reproducibilityPasses -lt 2
) {
    throw 'Tracked Hysteria2 native manifest does not satisfy the pinned 16 KB reproducibility contract.'
}

$packagedAbis = @('arm64-v8a', 'x86_64')
$expectedHysteria = [ordered]@{}
foreach ($abi in $packagedAbis) {
    $manifestRows = @($nativeManifest.files | Where-Object { $_.abi -eq $abi })
    if ($manifestRows.Count -ne 1) {
        throw "Tracked Hysteria2 native manifest must contain exactly one row for ABI $abi."
    }
    $row = $manifestRows[0]
    if ($row.file -ne 'libhysteria.so' -or [string]::IsNullOrWhiteSpace($row.sha256)) {
        throw "Tracked Hysteria2 native manifest row is incomplete for ABI $abi."
    }
    $expectedHysteria["lib/$abi/libhysteria.so"] = ([string]$row.sha256).ToUpperInvariant()
}
$requiredAssets = @(
    'assets/HYSTERIA_APP_MIT.txt',
    'assets/HEV_SOCKS5_TUNNEL_MIT.txt',
    'assets/HEV_LWIP_BSD.txt',
    'assets/transport_preview/SOURCE-MANIFEST.txt'
)

$zip = [IO.Compression.ZipFile]::OpenRead($apk)
try {
    $names = @($zip.Entries.FullName)
    foreach ($entry in $expectedHysteria.GetEnumerator()) {
        $zipEntry = $zip.GetEntry($entry.Key)
        if ($null -eq $zipEntry) { throw "Hysteria2 binary is missing from APK: $($entry.Key)" }
        $stream = $zipEntry.Open()
        try {
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
            }
            finally { $sha.Dispose() }
        }
        finally { $stream.Dispose() }
        if ($actual -ne $entry.Value) {
            throw "Hysteria2 binary hash mismatch in APK: $($entry.Key) actual=$actual"
        }
    }
    $actualHysteriaEntries = @($names | Where-Object { $_ -match '^lib/[^/]+/libhysteria\.so$' })
    $unexpectedHysteriaEntries = @(
        $actualHysteriaEntries |
            Where-Object { -not $expectedHysteria.Contains($_) }
    )
    if ($actualHysteriaEntries.Count -ne $expectedHysteria.Count -or $unexpectedHysteriaEntries.Count -ne 0) {
        throw "Flutter preview APK contains unexpected Hysteria2 ABI entries: $($actualHysteriaEntries -join ', ')"
    }
    foreach ($library in @('libhev-socks5-tunnel.so', 'libgreenvpn-hysteria-bridge.so')) {
        foreach ($abi in $packagedAbis) {
            $entryName = "lib/$abi/$library"
            if ($names -notcontains $entryName) {
                throw "Android Hysteria2 runtime ABI coverage is incomplete: $entryName"
            }
        }
        $actualEntries = @($names | Where-Object { $_ -match "^lib/[^/]+/$([regex]::Escape($library))$" })
        if ($actualEntries.Count -ne $packagedAbis.Count) {
            throw "Android Hysteria2 runtime contains unsupported ABI entries: $library count=$($actualEntries.Count)"
        }
    }
    foreach ($asset in $requiredAssets) {
        if ($names -notcontains $asset) { throw "Android Hysteria2 license/provenance asset is missing: $asset" }
    }
}
finally { $zip.Dispose() }

$badging = @(& $aapt2 dump badging $apk)
if ($LASTEXITCODE -ne 0) { throw 'aapt2 failed to read Android preview APK.' }
$packageLine = ($badging | Select-String -Pattern '^package:' | Select-Object -First 1).Line
if ($packageLine -notmatch "name='$([regex]::Escape($ExpectedPackage))'") {
    throw "Unexpected Android preview package: $packageLine"
}
if ($ExpectedVersionCode -and $packageLine -notmatch "versionCode='$([regex]::Escape($ExpectedVersionCode))'") {
    throw "Unexpected Android preview versionCode: $packageLine"
}

$manifest = @(& $aapt2 dump xmltree $apk --file AndroidManifest.xml) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not $manifest.Contains('pro.greenvpn.hysteria.Hysteria2VpnService')) {
    throw 'Android Hysteria2 VPN service is missing from the merged manifest.'
}
$dex = @(& $apkanalyzer dex packages --defined-only $apk) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not $dex.Contains('pro.greenvpn.hysteria.Hysteria2VpnService')) {
    throw 'Android Hysteria2 engine classes are missing from DEX.'
}
$buildConfig = @(& $apkanalyzer dex code --class pro.greenvpn.app.BuildConfig $apk) -join "`n"
if ($LASTEXITCODE -ne 0 -or $buildConfig -notmatch 'GREENVPN_HYSTERIA2_PREVIEW_ENABLED:Z = true') {
    throw 'Android Hysteria2 preview BuildConfig flag is not enabled.'
}

& $zipalign -c -p 4 $apk | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Android Hysteria2 preview APK is not zip-aligned.' }
& $apksigner verify --verbose $apk | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Android Hysteria2 preview APK signature verification failed.' }

$item = Get-Item -LiteralPath $apk
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apk).Hash
Write-Output "Android Hysteria2 preview APK verified: $($item.FullName)"
Write-Output "Size: $($item.Length)"
Write-Output "SHA256: $hash"
