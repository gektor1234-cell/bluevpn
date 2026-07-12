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
$expectedBinary = 'AAE616C0888DB31A61555CA4FE91B578E2A6734B7CEF7497B6FE30FFCDA1FDC5'
$binaryEntry = 'lib/arm64-v8a/libdnstt_client.so'
$licenseEntry = 'assets/DNSTT_PUBLIC_DOMAIN_COPYING.txt'
$zip = [IO.Compression.ZipFile]::OpenRead($apk)
try {
    $names = @($zip.Entries.FullName)
    $entry = $zip.GetEntry($binaryEntry)
    if ($null -eq $entry) { throw "dnstt binary is missing from APK: $binaryEntry" }
    $stream = $entry.Open()
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actualBinary = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
    if ($actualBinary -ne $expectedBinary) {
        throw "dnstt binary hash mismatch in APK: actual=$actualBinary"
    }
    if ($names -notcontains $licenseEntry) {
        throw "dnstt public-domain notice is missing from APK: $licenseEntry"
    }
    $unexpectedAbis = @($names | Where-Object {
        $_ -match '^lib/([^/]+)/libdnstt_client\.so$' -and $_ -ne $binaryEntry
    })
    if ($unexpectedAbis.Count -gt 0) {
        throw "Unexpected unverified dnstt ABI payload: $($unexpectedAbis -join ', ')"
    }
}
finally { $zip.Dispose() }

$badging = @(& $aapt2 dump badging $apk)
if ($LASTEXITCODE -ne 0) { throw 'aapt2 failed to read Android dnstt preview APK.' }
$packageLine = ($badging | Select-String -Pattern '^package:' | Select-Object -First 1).Line
if ($packageLine -notmatch "name='$([regex]::Escape($ExpectedPackage))'") {
    throw "Unexpected Android preview package: $packageLine"
}
if ($ExpectedVersionCode -and $packageLine -notmatch "versionCode='$([regex]::Escape($ExpectedVersionCode))'") {
    throw "Unexpected Android preview versionCode: $packageLine"
}

$manifest = @(& $aapt2 dump xmltree $apk --file AndroidManifest.xml) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not $manifest.Contains('pro.greenvpn.dnstt.DnsttVpnService')) {
    throw 'Android dnstt VPN service is missing from the merged manifest.'
}
$dex = @(& $apkanalyzer dex packages --defined-only $apk) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not $dex.Contains('pro.greenvpn.dnstt.DnsttVpnService')) {
    throw 'Android dnstt engine classes are missing from DEX.'
}
$buildConfig = @(& $apkanalyzer dex code --class pro.greenvpn.app.BuildConfig $apk) -join "`n"
if ($LASTEXITCODE -ne 0 -or $buildConfig -notmatch 'GREENVPN_DNSTT_PREVIEW_ENABLED:Z = true') {
    throw 'Android dnstt preview BuildConfig flag is not enabled.'
}

& $zipalign -c -p 4 $apk | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Android dnstt preview APK is not zip-aligned.' }
& $apksigner verify --verbose $apk | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Android dnstt preview APK signature verification failed.' }

$item = Get-Item -LiteralPath $apk
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apk).Hash
Write-Output "Android dnstt preview APK verified: $($item.FullName)"
Write-Output "Size: $($item.Length)"
Write-Output "SHA256: $hash"
