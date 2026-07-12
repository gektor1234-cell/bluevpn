param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,
    [string]$ExpectedPackage = 'pro.greenvpn.app'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$androidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$buildTools = Join-Path $androidSdk 'build-tools\36.0.0'
$aapt2 = Join-Path $buildTools 'aapt2.exe'
$apkanalyzer = Join-Path $androidSdk 'cmdline-tools\latest\bin\apkanalyzer.bat'
foreach ($tool in @($aapt2, $apkanalyzer)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Android tool is missing: $tool" }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($apk)
try {
    $forbiddenEntries = @(
        $zip.Entries.FullName |
            Where-Object {
                $_ -match '^lib/.*/(libhysteria|libhev-socks5-tunnel|libgreenvpn-hysteria-bridge)\.so$' -or
                $_ -eq 'assets/transport_preview/SOURCE-MANIFEST.txt'
            }
    )
    if ($forbiddenEntries.Count -gt 0) {
        throw "Stable APK contains Hysteria2 preview payload: $($forbiddenEntries -join ', ')"
    }
}
finally { $zip.Dispose() }

$badging = @(& $aapt2 dump badging $apk)
if ($LASTEXITCODE -ne 0) { throw 'aapt2 failed to read stable Android APK.' }
$packageLine = ($badging | Select-String -Pattern '^package:' | Select-Object -First 1).Line
if ($packageLine -notmatch "name='$([regex]::Escape($ExpectedPackage))'") {
    throw "Stable Android package changed unexpectedly: $packageLine"
}
$manifest = @(& $aapt2 dump xmltree $apk --file AndroidManifest.xml) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'aapt2 failed to read stable Android manifest.' }
if ($manifest.Contains('pro.greenvpn.hysteria.Hysteria2VpnService') -or
    $manifest.Contains('pro.greenvpn.hysteria.Hysteria2DebugReceiver')) {
    throw 'Stable Android manifest contains a Hysteria2 preview component.'
}
$dex = @(& $apkanalyzer dex packages --defined-only $apk) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'apkanalyzer failed to read stable Android DEX.' }
if ($dex -match '^P d .*pro\.greenvpn\.hysteria$' -or
    $dex.Contains('pro.greenvpn.hysteria.Hysteria2VpnService')) {
    throw 'Stable Android DEX contains the Hysteria2 preview engine.'
}
$buildConfig = @(& $apkanalyzer dex code --class pro.greenvpn.app.BuildConfig $apk) -join "`n"
if ($LASTEXITCODE -ne 0 -or $buildConfig -notmatch 'GREENVPN_HYSTERIA2_PREVIEW_ENABLED:Z = false') {
    throw 'Stable Android BuildConfig unexpectedly enables Hysteria2 preview.'
}

$item = Get-Item -LiteralPath $apk
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apk).Hash
Write-Output "Stable Android transport isolation verified: $($item.FullName)"
Write-Output "Size: $($item.Length)"
Write-Output "SHA256: $hash"
