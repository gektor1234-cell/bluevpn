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
$expectedHysteria = [ordered]@{
    'lib/arm64-v8a/libhysteria.so' = '623B12826D13F8BB67F581396CF22C6639ABCBB6B1F22A42BF80350FFDAF50A3'
    'lib/armeabi-v7a/libhysteria.so' = 'CD226A6EEBA011E809295082CA11C0B57560F070192372994E8DD968205595CC'
    'lib/x86_64/libhysteria.so' = '89D6C7CD9AAD1356196F8E7240A01368536091F1B1FA1E3EA5DE691F81B908D1'
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
    if ($names -contains 'lib/x86/libhysteria.so') {
        throw 'Flutter preview APK unexpectedly contains an unsupported x86 Hysteria2 binary.'
    }
    foreach ($library in @('libhev-socks5-tunnel.so', 'libgreenvpn-hysteria-bridge.so')) {
        $count = @($names | Where-Object { $_ -match "^lib/(arm64-v8a|armeabi-v7a|x86_64)/$([regex]::Escape($library))$" }).Count
        if ($count -ne 3) { throw "Android Hysteria2 runtime ABI coverage is incomplete: $library count=$count" }
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
