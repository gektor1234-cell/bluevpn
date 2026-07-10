param(
    [Parameter(Mandatory = $true)]
    [string]$AndroidApk,

    [Parameter(Mandatory = $true)]
    [string]$WindowsInstaller,

    [string]$AppVersion = "0.3.0-paid-beta.5",
    [string]$AndroidBuildNumber = "2026071005",
    [string]$AndroidApplicationId = "pro.greenvpn.app.beta",
    [string]$AndroidAppLabel = "Green VPN Beta",
    [string]$WindowsAppVersion = "0.3.0-paid-beta.2",
    [string]$BackendVersion = "0.9.106-paid-beta.4",
    [ValidateRange(1, 99)]
    [int]$BundleRevision = 1,
    [string]$OutDir = "C:\BlueVPN_Builds\paid_beta_20260710"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$siteSource = Join-Path $repo "paid_beta_site"
$backendSource = Join-Path $repo "backend_live"
$android = Get-Item -LiteralPath $AndroidApk
$windows = Get-Item -LiteralPath $WindowsInstaller

if ($android.Extension.ToLowerInvariant() -ne ".apk") {
    throw "AndroidApk must point to an .apk file."
}
if ($windows.Extension.ToLowerInvariant() -ne ".exe") {
    throw "WindowsInstaller must point to an .exe file."
}
if (-not $AppVersion.Contains("paid-beta")) {
    throw "AppVersion must be a paid-beta version."
}
if (-not $WindowsAppVersion.Contains("paid-beta")) {
    throw "WindowsAppVersion must be a paid-beta version."
}
if ($AndroidApplicationId -eq "pro.greenvpn.app") {
    throw "Paid beta Android application ID must stay isolated from production."
}
if ([string]::IsNullOrWhiteSpace($AndroidAppLabel) -or $AndroidAppLabel -eq "Green VPN") {
    throw "Paid beta Android launcher label must stay distinct from production."
}
if (-not (Test-Path -LiteralPath (Join-Path $siteSource "index.html"))) {
    throw "Paid beta site source is incomplete: $siteSource"
}
if (-not (Test-Path -LiteralPath (Join-Path $backendSource "app\main.py"))) {
    throw "Backend source is incomplete: $backendSource"
}
if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
    throw "tar.exe was not found in PATH."
}

$androidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$aapt = Get-ChildItem -LiteralPath (Join-Path $androidSdk "build-tools") `
    -Filter "aapt.exe" -Recurse | Sort-Object FullName -Descending | Select-Object -First 1
if ($null -eq $aapt) {
    throw "aapt.exe was not found for paid beta APK verification."
}
$badging = (& $aapt.FullName dump badging $android.FullName) -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw "Paid beta APK badging inspection failed."
}
if ($badging -notmatch "package: name='$([regex]::Escape($AndroidApplicationId))'") {
    throw "Paid beta APK package ID does not match $AndroidApplicationId."
}
if ($badging -notmatch "application-label:'$([regex]::Escape($AndroidAppLabel))'") {
    throw "Paid beta APK launcher label does not match $AndroidAppLabel."
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$releaseId = "paid-beta-$($AppVersion -replace '[^A-Za-z0-9._-]', '_')-$AndroidBuildNumber"
if ($BundleRevision -gt 1) {
    $releaseId += "-r$BundleRevision"
}
$stage = Join-Path $OutDir $releaseId
if (Test-Path -LiteralPath $stage) {
    throw "Bundle staging directory already exists: $stage"
}

$backendTarget = Join-Path $stage "backend"
$opsTarget = Join-Path $stage "ops"
$monitoringTarget = Join-Path $stage "monitoring"
$siteTarget = Join-Path $stage "site"
$downloadsTarget = Join-Path $siteTarget "downloads"
New-Item -ItemType Directory -Force -Path `
    (Join-Path $backendTarget "app"), `
    $opsTarget, `
    $monitoringTarget, `
    (Join-Path $siteTarget "assets"), `
    (Join-Path $siteTarget "terms"), `
    (Join-Path $siteTarget "privacy"), `
    $downloadsTarget | Out-Null

Copy-Item `
    -LiteralPath (Join-Path $repo "scripts\server\install_paid_beta_contour.sh") `
    -Destination (Join-Path $stage "install_paid_beta_contour.sh")

Copy-Item -LiteralPath (Join-Path $backendSource "app\main.py") -Destination (Join-Path $backendTarget "app\main.py")
Copy-Item -LiteralPath (Join-Path $backendSource "requirements.txt") -Destination (Join-Path $backendTarget "requirements.txt")

$opsFiles = @(
    "greenvpn_db_sync_from_peer.sh",
    "greenvpn_sqlite_snapshot_stdout.py",
    "greenvpn_sqlite_state_sync.py",
    "create_paid_beta_first20_package.py",
    "smoke_paid_beta_contour.py"
)
foreach ($name in $opsFiles) {
    Copy-Item -LiteralPath (Join-Path $repo "scripts\ops\$name") -Destination (Join-Path $opsTarget $name)
}

$monitoringFiles = @(
    "service_probe.py",
    "install_paid_beta_probe_systemd.sh"
)
foreach ($name in $monitoringFiles) {
    Copy-Item -LiteralPath (Join-Path $repo "scripts\monitoring\$name") -Destination (Join-Path $monitoringTarget $name)
}

Copy-Item -LiteralPath (Join-Path $siteSource "index.html") -Destination (Join-Path $siteTarget "index.html")
Copy-Item -LiteralPath (Join-Path $siteSource "styles.css") -Destination (Join-Path $siteTarget "styles.css")
Copy-Item -LiteralPath (Join-Path $siteSource "robots.txt") -Destination (Join-Path $siteTarget "robots.txt")
Copy-Item -LiteralPath (Join-Path $siteSource "assets\app_icon.png") -Destination (Join-Path $siteTarget "assets\app_icon.png")
Copy-Item -LiteralPath (Join-Path $siteSource "terms\index.html") -Destination (Join-Path $siteTarget "terms\index.html")
Copy-Item -LiteralPath (Join-Path $siteSource "privacy\index.html") -Destination (Join-Path $siteTarget "privacy\index.html")

$androidTarget = Join-Path $downloadsTarget "GreenVPN_Android.apk"
$windowsTarget = Join-Path $downloadsTarget "GreenVPN_Setup.exe"
Copy-Item -LiteralPath $android.FullName -Destination $androidTarget
Copy-Item -LiteralPath $windows.FullName -Destination $windowsTarget

function Get-ArtifactRecord {
    param(
        [string]$Platform,
        [string]$Path,
        [string]$BuildNumber,
        [string]$Version
    )
    $item = Get-Item -LiteralPath $Path
    $signatureStatus = $null
    $signed = $true
    if ($Platform -eq "windows") {
        $signatureStatus = (Get-AuthenticodeSignature -LiteralPath $Path).Status.ToString()
        $signed = $signatureStatus -eq "Valid"
    }
    return [ordered]@{
        platform = $Platform
        fileName = $item.Name
        version = $Version
        buildNumber = $BuildNumber
        sizeBytes = $item.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
        signed = $signed
        signatureStatus = $signatureStatus
    }
}

$artifacts = @(
    Get-ArtifactRecord -Platform "android" -Path $androidTarget -BuildNumber $AndroidBuildNumber -Version $AppVersion
    Get-ArtifactRecord -Platform "windows" -Path $windowsTarget -BuildNumber "" -Version $WindowsAppVersion
)
$generatedAt = (Get-Date).ToUniversalTime().ToString("o")
$downloadManifest = [ordered]@{
    channel = "paid-beta"
    isolated = $true
    productionPublished = $false
    appVersion = $AppVersion
    androidApplicationId = $AndroidApplicationId
    androidAppLabel = $AndroidAppLabel
    windowsAppVersion = $WindowsAppVersion
    generatedAt = $generatedAt
    artifacts = $artifacts
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$downloadManifestPath = Join-Path $downloadsTarget "manifest.json"
[System.IO.File]::WriteAllText(
    $downloadManifestPath,
    ($downloadManifest | ConvertTo-Json -Depth 8) + "`n",
    $utf8
)

$bundleManifest = [ordered]@{
    releaseId = $releaseId
    channel = "paid-beta"
    isolated = $true
    productionPublished = $false
    appVersion = $AppVersion
    androidBuildNumber = $AndroidBuildNumber
    androidApplicationId = $AndroidApplicationId
    androidAppLabel = $AndroidAppLabel
    windowsAppVersion = $WindowsAppVersion
    backendVersion = $BackendVersion
    bundleRevision = $BundleRevision
    generatedAt = $generatedAt
    apiBaseUrl = "https://api.greenvpn.pro/paid-beta-api"
    apiFallbackBaseUrl = "https://176-113-81-35.sslip.io/paid-beta-api"
    siteUrl = "https://greenvpn.pro/paid-beta/"
    fallbackSiteUrl = "https://176-113-81-35.sslip.io/paid-beta/"
    clientIpRange = "10.10.0.180-10.10.0.229"
    files = @(
        Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName | ForEach-Object {
            [ordered]@{
                path = $_.FullName.Substring($stage.Length + 1).Replace("\", "/")
                sizeBytes = $_.Length
                sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToUpperInvariant()
            }
        }
    )
}
$bundleManifestPath = Join-Path $stage "bundle-manifest.json"
[System.IO.File]::WriteAllText(
    $bundleManifestPath,
    ($bundleManifest | ConvertTo-Json -Depth 10) + "`n",
    $utf8
)

$archive = Join-Path $OutDir "$releaseId.tar.gz"
& tar.exe -czf $archive -C $stage .
if ($LASTEXITCODE -ne 0) {
    throw "tar.exe failed to create the paid beta bundle."
}

$archiveItem = Get-Item -LiteralPath $archive
$archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToUpperInvariant()
Write-Host "Paid beta bundle prepared:" -ForegroundColor Green
Write-Host "Stage: $stage"
Write-Host "Archive: $archive"
Write-Host "Size: $($archiveItem.Length)"
Write-Host "SHA256: $archiveHash"
Write-Host "Production artifacts changed: false"
