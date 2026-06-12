param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,

    [string]$RemoteHost = "root@72.56.32.197",
    [string]$RemoteRoot = "/var/www/greenvpn",
    [string]$PreviewSubdir = "release-preview-20260517-private",
    [string]$LatestFileName = "GreenVPN_Android_preview_latest.apk",
    [string]$PublicBaseUrl = "https://greenvpn.pro",

    [switch]$SkipVersionedCopy,
    [switch]$SkipPreviewSiteUpload,
    [switch]$SkipNginxReload,
    [switch]$SkipHttpVerify
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$apkItem = Get-Item -LiteralPath $ApkPath
if ($apkItem.Extension.ToLowerInvariant() -ne ".apk") {
    throw "Expected an APK file, got: $($apkItem.FullName)"
}

$apkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkItem.FullName).Hash.ToUpperInvariant()
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$remoteDownloads = "$RemoteRoot/downloads"
$remotePreview = "$RemoteRoot/$PreviewSubdir"
$remoteBackups = "/root/greenvpn-site-backups"
$remoteLatest = "$remoteDownloads/$LatestFileName"
$remoteVersioned = "$remoteDownloads/$($apkItem.Name)"
$latestBaseName = [System.IO.Path]::GetFileNameWithoutExtension($LatestFileName)
$versionedBaseName = [System.IO.Path]::GetFileNameWithoutExtension($apkItem.Name)

$sshOptions = @("-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new")
$scpOptions = @("-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new")

Write-Host "Deploying Android preview APK"
Write-Host "APK: $($apkItem.FullName)"
Write-Host "Size: $($apkItem.Length) bytes"
Write-Host "SHA256: $apkHash"

$prepareCommand = "set -eu; mkdir -p '$remoteBackups' '$remoteDownloads' '$remotePreview'; " +
    "if [ -f '$remoteLatest' ]; then cp -a '$remoteLatest' '$remoteBackups/${latestBaseName}_pre_$timestamp.apk'; fi; " +
    "if [ -f '$remoteVersioned' ]; then cp -a '$remoteVersioned' '$remoteBackups/${versionedBaseName}_pre_$timestamp.apk'; fi; " +
    "if [ -f '$remotePreview/index.html' ]; then cp -a '$remotePreview/index.html' '$remoteBackups/${PreviewSubdir}_index_pre_$timestamp.html'; fi"

& ssh @sshOptions $RemoteHost $prepareCommand | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Remote backup/prepare failed"
}

& scp @scpOptions $apkItem.FullName "${RemoteHost}:$remoteLatest" | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Upload to latest preview APK failed"
}

if (-not $SkipVersionedCopy) {
    & scp @scpOptions $apkItem.FullName "${RemoteHost}:$remoteVersioned" | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Upload to versioned preview APK failed"
    }
}

if (-not $SkipPreviewSiteUpload) {
    $siteDir = Join-Path $repo "public_release_preview_site"
    $indexPath = Join-Path $siteDir "index.html"
    $stylesPath = Join-Path $siteDir "styles.css"
    if (-not (Test-Path -LiteralPath $indexPath)) {
        throw "Preview index not found: $indexPath"
    }
    if (-not (Test-Path -LiteralPath $stylesPath)) {
        throw "Preview styles not found: $stylesPath"
    }

    & scp @scpOptions $indexPath "${RemoteHost}:$remotePreview/index.html" | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Preview index upload failed"
    }

    & scp @scpOptions $stylesPath "${RemoteHost}:$remotePreview/styles.css" | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Preview styles upload failed"
    }
}

if (-not $SkipNginxReload) {
    & ssh @sshOptions $RemoteHost "nginx -t && systemctl reload nginx" | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "nginx validation/reload failed"
    }
}

$verifyCommand = "set -eu; stat -c '%s' '$remoteLatest'; sha256sum '$remoteLatest'"
$remoteVerify = & ssh @sshOptions $RemoteHost $verifyCommand
if ($LASTEXITCODE -ne 0) {
    throw "Remote APK verification failed"
}
$remoteVerify | Out-Host
$remoteSize = [int64]($remoteVerify | Select-Object -First 1)
$remoteHash = (($remoteVerify | Select-Object -Last 1) -split "\s+")[0].ToUpperInvariant()
if ($remoteSize -ne $apkItem.Length) {
    throw "Remote latest APK size mismatch. Expected $($apkItem.Length), got $remoteSize"
}
if ($remoteHash -ne $apkHash) {
    throw "Remote latest APK hash mismatch. Expected $apkHash, got $remoteHash"
}

if (-not $SkipHttpVerify) {
    $previewUrl = "$PublicBaseUrl/$PreviewSubdir/"
    $latestUrl = "$PublicBaseUrl/downloads/$LatestFileName"
    $previewHtml = (Invoke-WebRequest -Uri "${previewUrl}?t=${timestamp}" -UseBasicParsing).Content
    if ($previewHtml -notlike "*$LatestFileName*") {
        throw "Preview page does not reference $LatestFileName"
    }

    $downloadCheckPath = Join-Path $env:TEMP "$LatestFileName.$timestamp.check.apk"
    Invoke-WebRequest -Uri "${latestUrl}?t=${timestamp}" -OutFile $downloadCheckPath -UseBasicParsing
    $downloadItem = Get-Item -LiteralPath $downloadCheckPath
    $downloadHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $downloadCheckPath).Hash.ToUpperInvariant()
    if ($downloadItem.Length -ne $apkItem.Length) {
        throw "HTTPS APK size mismatch. Expected $($apkItem.Length), got $($downloadItem.Length)"
    }
    if ($downloadHash -ne $apkHash) {
        throw "HTTPS APK hash mismatch. Expected $apkHash, got $downloadHash"
    }

    Write-Host "Preview page: $previewUrl"
    Write-Host "Latest APK URL: $latestUrl"
}

Write-Host "Android preview APK deployed successfully."
