param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$DestinationToolsDir,
    [ValidateSet('stable', 'paid-beta')]
    [string]$RuntimeScope = 'stable',
    [string]$AmneziaRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\amneziawg-windows-client-2.0.0\extracted\AmneziaWG',
    [string]$HysteriaRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\hysteria-app-v2.9.3',
    [string]$HevRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\hev-socks5-tunnel-2.14.4-release\extracted\hev-socks5-tunnel',
    [string]$XrayRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\xray-core-v26.7.11\windows-64',
    [string]$NaiveRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\naiveproxy_v150.0.7871.63-1\win-extract\naiveproxy-v150.0.7871.63-1-win-x64',
    [string]$DnsttRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_dnstt_20260712'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Copy-VerifiedRuntime {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$ExpectedSha256
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Transport runtime is missing: $Source"
    }
    $actual = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedSha256) {
        throw "Transport runtime hash mismatch: $Source"
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Copy-TransformedScript {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][hashtable]$Replacements
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Transport script is missing: $Source"
    }
    $content = [IO.File]::ReadAllText($Source, [Text.UTF8Encoding]::new($true))
    foreach ($entry in $Replacements.GetEnumerator()) {
        $content = $content.Replace([string]$entry.Key, [string]$entry.Value)
    }
    [IO.File]::WriteAllText($Destination, $content, [Text.UTF8Encoding]::new($true))
}

$project = [IO.Path]::GetFullPath($ProjectRoot)
$destination = [IO.Path]::GetFullPath($DestinationToolsDir)
New-Item -ItemType Directory -Force -Path $destination | Out-Null

$identity = if ($RuntimeScope -eq 'paid-beta') {
    [ordered]@{
        Tunnel = 'GreenVPNBeta'
        ProgramData = 'BlueVPNBeta'
        InstallName = 'Green VPN Beta'
    }
} else {
    [ordered]@{
        Tunnel = 'BlueVPNDev1'
        ProgramData = 'BlueVPN'
        InstallName = 'Green VPN'
    }
}
$replacements = @{
    'GreenVPNTransportPreview' = $identity.Tunnel
    'BlueVPNTransportPreview' = $identity.ProgramData
    'Green VPN Transport Preview' = $identity.InstallName
    'GreenVPNHysteriaPreview' = 'GreenVPNHysteria'
    'GreenVPNVlessPreview' = 'GreenVPNVless'
    'GreenVPNNaivePreview' = 'GreenVPNNaive'
    'GreenVPNDnsttPreview' = 'GreenVPNDnstt'
}

Copy-TransformedScript `
    -Source (Join-Path $project 'scripts\windows\greenvpn_transport_preview_vpn_task.ps1') `
    -Destination (Join-Path $destination 'greenvpn_vpn_task.ps1') `
    -Replacements $replacements
Copy-TransformedScript `
    -Source (Join-Path $project 'scripts\windows\greenvpn_selective_routing.ps1') `
    -Destination (Join-Path $destination 'greenvpn_selective_routing.ps1') `
    -Replacements $replacements
foreach ($watchdog in @(
    'greenvpn_hysteria2_watchdog.ps1',
    'greenvpn_vless_reality_watchdog.ps1',
    'greenvpn_naive_https_watchdog.ps1',
    'greenvpn_dnstt_watchdog.ps1'
)) {
    Copy-TransformedScript `
        -Source (Join-Path $project "scripts\windows\$watchdog") `
        -Destination (Join-Path $destination $watchdog) `
        -Replacements $replacements
}

$runtimeSets = [ordered]@{
    'amneziawg2' = [ordered]@{
        'amneziawg.exe' = @((Join-Path $AmneziaRoot 'amneziawg.exe'), '5B00905ED02619FE149CEAFC898E79993D4455A0CDFA92072B3BB9AEE7B2D537')
        'awg.exe' = @((Join-Path $AmneziaRoot 'awg.exe'), '26AC0BE14A8353EACF2F933736F6F7912F89EC7C59C4190CC990492934C74537')
        'wintun.dll' = @((Join-Path $AmneziaRoot 'wintun.dll'), 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE')
    }
    'hysteria2' = [ordered]@{
        'hysteria-windows-amd64.exe' = @((Join-Path $HysteriaRoot 'hysteria-windows-amd64.exe'), 'BCD3865B09BE2E5CC18D117DCF3AD687D1E6E27B0B050376B9CF4EA251B64D6F')
        'hev-socks5-tunnel.exe' = @((Join-Path $HevRoot 'hev-socks5-tunnel.exe'), '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E')
        'msys-2.0.dll' = @((Join-Path $HevRoot 'msys-2.0.dll'), '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18')
        'wintun.dll' = @((Join-Path $HevRoot 'wintun.dll'), 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE')
    }
    'vless-reality' = [ordered]@{
        'xray.exe' = @((Join-Path $XrayRoot 'xray.exe'), '4B43C5EF596F326B233717B585D31A85DD5CD5F77D8DA872E75F7EBC00E99ACB')
        'hev-socks5-tunnel.exe' = @((Join-Path $HevRoot 'hev-socks5-tunnel.exe'), '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E')
        'msys-2.0.dll' = @((Join-Path $HevRoot 'msys-2.0.dll'), '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18')
        'wintun.dll' = @((Join-Path $HevRoot 'wintun.dll'), 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE')
    }
    'naive-https' = [ordered]@{
        'naive.exe' = @((Join-Path $NaiveRoot 'naive.exe'), '94F99801C665D29FC071624663C6F7BFA59E8D5EFAA84CD08EF5EBB18B46CB62')
        'hev-socks5-tunnel.exe' = @((Join-Path $HevRoot 'hev-socks5-tunnel.exe'), '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E')
        'msys-2.0.dll' = @((Join-Path $HevRoot 'msys-2.0.dll'), '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18')
        'wintun.dll' = @((Join-Path $HevRoot 'wintun.dll'), 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE')
    }
    'dnstt' = [ordered]@{
        'dnstt-client-windows-amd64.exe' = @((Join-Path $DnsttRoot 'dnstt-client-windows-amd64.exe'), '282995EA68FD13514AC033BC953193AD11CF01F83BB6E3F97929089E5BD85A99')
        'hev-socks5-tunnel.exe' = @((Join-Path $HevRoot 'hev-socks5-tunnel.exe'), '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E')
        'msys-2.0.dll' = @((Join-Path $HevRoot 'msys-2.0.dll'), '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18')
        'wintun.dll' = @((Join-Path $HevRoot 'wintun.dll'), 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE')
    }
}

$manifestFiles = New-Object System.Collections.Generic.List[object]
foreach ($runtimeSet in $runtimeSets.GetEnumerator()) {
    $runtimeDir = Join-Path $destination $runtimeSet.Key
    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
    foreach ($file in $runtimeSet.Value.GetEnumerator()) {
        $target = Join-Path $runtimeDir $file.Key
        Copy-VerifiedRuntime -Source $file.Value[0] -Destination $target -ExpectedSha256 $file.Value[1]
        $manifestFiles.Add([pscustomobject]@{
            path = "$($runtimeSet.Key)/$($file.Key)"
            sha256 = $file.Value[1]
        })
    }
}

$amneziaSignature = Get-AuthenticodeSignature -LiteralPath (Join-Path $destination 'amneziawg2\amneziawg.exe')
if ($amneziaSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw 'AmneziaWG runtime signature is invalid.'
}

$licenseDir = Join-Path $destination 'licenses'
New-Item -ItemType Directory -Force -Path $licenseDir | Out-Null
foreach ($license in @(
    'AMNEZIAWG_WINDOWS_CLIENT_MIT.txt',
    'HYSTERIA_APP_MIT.txt',
    'HEV_SOCKS5_TUNNEL_MIT.txt',
    'HEV_LWIP_BSD.txt',
    'HEV_WINTUN_PREBUILT_BINARY_LICENSE.txt',
    'XRAY_CORE_MPL_SOURCE_NOTICE.txt',
    'NAIVEPROXY_BSD_3_CLAUSE.txt',
    'DNSTT_PUBLIC_DOMAIN_COPYING.txt'
)) {
    $source = Join-Path $project "docs\licenses\$license"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Transport license is missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $licenseDir $license) -Force
}
$xrayLicense = Join-Path $XrayRoot 'LICENSE'
if (-not (Test-Path -LiteralPath $xrayLicense -PathType Leaf)) {
    throw "Xray license is missing: $xrayLicense"
}
Copy-Item -LiteralPath $xrayLicense -Destination (Join-Path $licenseDir 'XRAY_CORE_MPL_2_0_LICENSE.txt') -Force

[ordered]@{
    schema = 'greenvpn-windows-transport-cascade-v1'
    runtimeScope = $RuntimeScope
    order = @('wireguard_udp', 'amneziawg', 'hysteria2', 'vless_reality', 'naive_https', 'dnstt')
    files = [object[]]$manifestFiles
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json -Depth 6 | Set-Content `
    -LiteralPath (Join-Path $destination 'transport-cascade-manifest.json') -Encoding UTF8
