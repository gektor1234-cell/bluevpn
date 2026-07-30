param(
    [string]$OutDir = 'C:\BlueVPN_Builds\public_product_final_candidate_20260730_b3001',
    [string]$AppVersion = '0.3.21',
    [string]$AndroidBuildNumber = '2026073001',
    [ValidateRange(0, 65535)]
    [int]$WindowsBuildNumber = 3001
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repo

$status = @(& git status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw 'Unable to read Git status.' }
if ($status.Count -ne 0) {
    throw 'Final candidate builds require a clean Git worktree. Commit the verified source first.'
}

$allowedRoot = [IO.Path]::GetFullPath('C:\BlueVPN_Builds').TrimEnd('\') + '\'
$resolvedOut = [IO.Path]::GetFullPath($OutDir).TrimEnd('\') + '\'
if (-not $resolvedOut.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe final candidate output path: $resolvedOut"
}
if (Test-Path -LiteralPath $OutDir) {
    throw "Final candidate output already exists. Use a new immutable OutDir: $OutDir"
}
New-Item -ItemType Directory -Path $OutDir | Out-Null

$androidPackage = 'pro.greenvpn.app.finalcandidate'
$apiBaseUrl = 'https://api.greenvpn.pro'
$apiFallbackBaseUrls = 'https://176-113-81-35.sslip.io'

& (Join-Path $PSScriptRoot 'build_android_apk.ps1') `
    -Mode release `
    -EnableAwg2Preview `
    -EnableHysteria2Preview `
    -EnableVlessRealityPreview `
    -EnableNaiveHttpsPreview `
    -EnableDnsttPreview `
    -PublicProductCandidate `
    -Awg2PreviewApplicationId $androidPackage `
    -Awg2PreviewAppLabel 'Green VPN' `
    -Awg2PreviewAppVersion $AppVersion `
    -Awg2PreviewBuildName $AppVersion `
    -Awg2PreviewBuildNumber $AndroidBuildNumber `
    -Awg2PreviewApiBaseUrl $apiBaseUrl `
    -Awg2PreviewApiFallbackBaseUrls $apiFallbackBaseUrls
if ($LASTEXITCODE -ne 0) { throw 'Android final candidate release build failed.' }

$sourceApk = (Resolve-Path 'build\app\outputs\flutter-apk\app-release.apk').Path
$androidArtifact = Join-Path $OutDir "GreenVPN_Android_${AppVersion}_final_candidate_${AndroidBuildNumber}.apk"
Copy-Item -LiteralPath $sourceApk -Destination $androidArtifact

& (Join-Path $PSScriptRoot 'verify_android_hysteria2_preview_apk.ps1') `
    -ApkPath $androidArtifact `
    -ExpectedPackage $androidPackage `
    -ExpectedVersionCode $AndroidBuildNumber
if ($LASTEXITCODE -ne 0) { throw 'Android Hysteria2 verifier failed.' }

& (Join-Path $PSScriptRoot 'verify_android_dnstt_preview_apk.ps1') `
    -ApkPath $androidArtifact `
    -ExpectedPackage $androidPackage `
    -ExpectedVersionCode $AndroidBuildNumber
if ($LASTEXITCODE -ne 0) { throw 'Android dnstt verifier failed.' }

$windowsOut = Join-Path $OutDir 'windows'
& (Join-Path $PSScriptRoot 'build_windows_awg2_preview.ps1') `
    -OutDir $windowsOut `
    -AppVersion $AppVersion `
    -WindowsBuildName $AppVersion `
    -WindowsBuildNumber $WindowsBuildNumber `
    -ApiBaseUrl $apiBaseUrl `
    -ApiFallbackBaseUrls $apiFallbackBaseUrls `
    -PublicProductCandidate `
    -SkipChecks
if ($LASTEXITCODE -ne 0) { throw 'Windows final candidate build failed.' }

$safeAppVersion = $AppVersion -replace '[^A-Za-z0-9._-]', '_'
$windowsArtifact = Join-Path $windowsOut "GreenVPN_Windows_${safeAppVersion}_final_candidate.zip"
if (-not (Test-Path -LiteralPath $windowsArtifact -PathType Leaf)) {
    throw "Windows final candidate ZIP is missing: $windowsArtifact"
}
$requiredWindowsPayloads = @(
    'app\tools\greenvpn_transport_preview_vpn_task.ps1',
    'app\tools\greenvpn_selective_routing.ps1',
    'app\tools\process-router\ProxyBridge_CLI.exe',
    'app\tools\process-router\ProxyBridgeCore.dll',
    'app\tools\process-router\WinDivert.dll',
    'app\tools\process-router\WinDivert64.sys',
    'app\tools\process-router\PROVENANCE.md',
    'app\tools\process-router\THIRD_PARTY_NOTICES.txt'
)
foreach ($relativePath in $requiredWindowsPayloads) {
    $payloadPath = Join-Path $windowsOut $relativePath
    if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
        throw "Windows final candidate dependency is missing: $relativePath"
    }
}

$head = (& git rev-parse HEAD).Trim()
$branch = (& git branch --show-current).Trim()
$artifactRows = @(
    foreach ($entry in @(
        [pscustomobject]@{ platform = 'android'; path = $androidArtifact; signedForProduction = $true },
        [pscustomobject]@{ platform = 'windows'; path = $windowsArtifact; signedForProduction = $false }
    )) {
        $item = Get-Item -LiteralPath $entry.path
        [pscustomobject]@{
            platform = $entry.platform
            path = $item.FullName.Substring($OutDir.Length).TrimStart('\')
            sizeBytes = $item.Length
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash
            signedForProduction = $entry.signedForProduction
        }
    }
)

$manifest = [ordered]@{
    schema = 1
    product = 'Green VPN'
    releaseClass = 'local-final-candidate'
    productionPublished = $false
    source = [ordered]@{
        repository = $repo
        branch = $branch
        commit = $head
        clean = $true
    }
    version = [ordered]@{
        app = $AppVersion
        androidBuildNumber = $AndroidBuildNumber
        windowsBuildNumber = $WindowsBuildNumber
    }
    customerLocations = @('auto', 'NL', 'GB-when-ready')
    transportCascade = [ordered]@{
        android = @('stable', 'protected-udp', 'quic', 'tls', 'https', 'dns')
        windows = @('stable', 'protected-udp', 'quic', 'tls', 'https', 'dns')
    }
    billing = [ordered]@{
        adsEnabled = $false
        forcedDisconnectTimerEnabled = $false
        plansRub = @(249, 649, 1099)
        historicalTechnicalPaymentSmokeCompleted = $true
        paidSalesEnabled = $false
        taxReceiptReady = $false
    }
    api = [ordered]@{
        primary = $apiBaseUrl
        fallbacks = @($apiFallbackBaseUrls)
    }
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    artifacts = $artifactRows
}
$manifestPath = Join-Path $OutDir 'final-candidate-manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8

$artifactRows | Format-Table platform, sizeBytes, sha256, path -AutoSize | Out-Host
Write-Host "Manifest: $manifestPath"
