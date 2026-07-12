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
                $_ -match '^lib/.*/(libhysteria|libhev-socks5-tunnel|libgreenvpn-hysteria-bridge|libxray|libnaive|libdnstt_client)\.so$' -or
                $_ -eq 'assets/transport_preview/SOURCE-MANIFEST.txt'
            }
    )
    if ($forbiddenEntries.Count -gt 0) {
        throw "Stable APK contains transport preview payload: $($forbiddenEntries -join ', ')"
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
$forbiddenComponents = @(
    'pro.greenvpn.hysteria.Hysteria2VpnService',
    'pro.greenvpn.hysteria.Hysteria2DebugReceiver',
    'pro.greenvpn.vless.VlessRealityVpnService',
    'pro.greenvpn.vless.VlessRealityDebugReceiver',
    'pro.greenvpn.naive.NaiveHttpsVpnService',
    'pro.greenvpn.naive.NaiveHttpsDebugReceiver',
    'pro.greenvpn.dnstt.DnsttVpnService',
    'pro.greenvpn.dnstt.DnsttDebugReceiver',
    'pro.greenvpn.app.TransportContractDebugService'
)
$leakedComponents = @($forbiddenComponents | Where-Object { $manifest.Contains($_) })
if ($leakedComponents.Count -gt 0) {
    throw "Stable Android manifest contains transport preview component(s): $($leakedComponents -join ', ')"
}
$dex = @(& $apkanalyzer dex packages --defined-only $apk) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'apkanalyzer failed to read stable Android DEX.' }
$forbiddenDexPackages = @('pro.greenvpn.hysteria', 'pro.greenvpn.vless', 'pro.greenvpn.naive', 'pro.greenvpn.dnstt')
$leakedDexPackages = @($forbiddenDexPackages | Where-Object { $dex.Contains($_) })
if ($leakedDexPackages.Count -gt 0) {
    throw "Stable Android DEX contains transport preview package(s): $($leakedDexPackages -join ', ')"
}
$previousErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $buildConfigOutput = @(& $apkanalyzer dex code --class pro.greenvpn.app.BuildConfig $apk 2>&1)
    $buildConfigExitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = $previousErrorActionPreference }
$buildConfig = $buildConfigOutput -join "`n"
$previewFlags = @(
    'GREENVPN_AWG2_PREVIEW_ENABLED',
    'GREENVPN_HYSTERIA2_PREVIEW_ENABLED',
    'GREENVPN_VLESS_REALITY_PREVIEW_ENABLED',
    'GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED',
    'GREENVPN_DNSTT_PREVIEW_ENABLED'
)
if ($buildConfigExitCode -eq 0) {
    $badFlags = @($previewFlags | Where-Object { $buildConfig -notmatch "$([regex]::Escape($_)):Z = false" })
    if ($badFlags.Count -gt 0) {
        throw "Stable Android BuildConfig does not prove preview disabled: $($badFlags -join ', ')"
    }
}
elseif ($buildConfig -match 'class .* not found') {
    Write-Output 'Stable BuildConfig was removed by release optimization; payload, manifest, and DEX isolation checks passed.'
}
else {
    throw "apkanalyzer failed to read stable Android BuildConfig: $buildConfig"
}

$item = Get-Item -LiteralPath $apk
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apk).Hash
Write-Output "Stable Android transport isolation verified: $($item.FullName)"
Write-Output "Size: $($item.Length)"
Write-Output "SHA256: $hash"
