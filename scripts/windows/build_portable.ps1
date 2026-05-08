param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.." )).Path,
    [string]$OutBase = "C:\BlueVPN_Builds",
    [string]$PackageName = "BlueVPN_Portable",
    [switch]$SkipBuild,
    [switch]$OpenFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
}

function Assert-SafeChildPath {
    param(
        [string]$BasePath,
        [string]$CandidatePath
    )

    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $candidate = [System.IO.Path]::GetFullPath($CandidatePath)
    if (-not $candidate.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe path outside base. Base=$base Candidate=$candidate"
    }
}

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    throw "ProjectRoot does not exist: $ProjectRoot"
}

if (-not $SkipBuild) {
    Write-Section 'BUILD WINDOWS RELEASE'
    Push-Location $ProjectRoot
    try {
        flutter build windows --release
    }
    finally {
        Pop-Location
    }
}

$releaseRuntimeDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
$releaseExe = Join-Path $releaseRuntimeDir 'bluevpn.exe'
if (-not (Test-Path -LiteralPath $releaseExe)) {
    throw "Release EXE not found: $releaseExe"
}

New-Item -ItemType Directory -Force -Path $OutBase | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$portableDir = Join-Path $OutBase ("{0}_{1}" -f $PackageName, $stamp)
$zipPath = "$portableDir.zip"

Assert-SafeChildPath -BasePath $OutBase -CandidatePath $portableDir
Assert-SafeChildPath -BasePath $OutBase -CandidatePath $zipPath

Write-Section 'PREPARE PORTABLE FOLDER'
if (Test-Path -LiteralPath $portableDir) {
    Remove-Item -LiteralPath $portableDir -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
New-Item -ItemType Directory -Force -Path $portableDir | Out-Null

Write-Section 'COPY RUNTIME TO ROOT'
Copy-Item -LiteralPath (Join-Path $releaseRuntimeDir 'bluevpn.exe') -Destination $portableDir -Force
Copy-Item -LiteralPath (Join-Path $releaseRuntimeDir 'flutter_windows.dll') -Destination $portableDir -Force
Copy-Item -LiteralPath (Join-Path $releaseRuntimeDir 'data') -Destination (Join-Path $portableDir 'data') -Recurse -Force

Write-Section 'CREATE ZIP'
Compress-Archive -Path (Join-Path $portableDir '*') -DestinationPath $zipPath -Force

Write-Section 'DONE'
Get-Item -LiteralPath $zipPath | Select-Object FullName,Length,LastWriteTime | Format-List

if ($OpenFolder) {
    explorer /select,"$zipPath"
}
