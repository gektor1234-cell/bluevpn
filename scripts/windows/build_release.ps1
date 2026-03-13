param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.." )).Path,
    [string]$OutBase = "$env:USERPROFILE\Desktop",
    [string]$PackageName = "BlueVPN_Release",
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

function Ensure-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Copy-IfExists {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (Test-Path $Source) {
        $parent = Split-Path $Destination -Parent
        if ($parent) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        Copy-Item $Source $Destination -Force
        Write-Host "Copied: $Source"
        return $true
    }

    Write-Host "Missing: $Source" -ForegroundColor Yellow
    return $false
}

function Get-SafeVersionText {
    param([string]$VersionPath)

    if (Test-Path $VersionPath) {
        $raw = Get-Content $VersionPath -Raw
        $line = ($raw -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
        if ($line) {
            $clean = $line.Trim()
            $clean = [regex]::Replace($clean, '[^A-Za-z0-9._-]', '_')
            if ($clean) {
                return $clean
            }
        }
    }

    return (Get-Date -Format 'yyyyMMdd_HHmmss')
}

Write-Section 'BLUEVPN RELEASE BUILDER'
Write-Host "ProjectRoot: $ProjectRoot"
Write-Host "OutBase:     $OutBase"
Write-Host "SkipBuild:   $SkipBuild"

if (-not (Test-Path $ProjectRoot)) {
    throw "ProjectRoot does not exist: $ProjectRoot"
}

$versionPath = Join-Path $ProjectRoot 'VERSION.txt'
$version = Get-SafeVersionText -VersionPath $versionPath
$releaseDir = Join-Path $OutBase ("{0}_{1}" -f $PackageName, $version)
$zipPath = "$releaseDir.zip"

$releaseRuntimeDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
$releaseExe = Join-Path $releaseRuntimeDir 'bluevpn.exe'

if (-not $SkipBuild) {
    Write-Section 'BUILD WINDOWS RELEASE'
    Ensure-Command -Name 'flutter'

    Push-Location $ProjectRoot
    try {
        flutter clean
        flutter pub get
        flutter build windows --release
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path $releaseRuntimeDir)) {
    throw "Release runtime folder not found: $releaseRuntimeDir"
}

if (-not (Test-Path $releaseExe)) {
    throw "Release EXE not found: $releaseExe"
}

Write-Section 'PREPARE PACKAGE FOLDER'
if (Test-Path $releaseDir) {
    Remove-Item $releaseDir -Recurse -Force
}
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

$appDir = Join-Path $releaseDir 'app'
$docsDir = Join-Path $releaseDir 'docs'
$toolsDir = Join-Path $releaseDir 'tools'
$samplesDir = Join-Path $releaseDir 'samples'

New-Item -ItemType Directory -Force -Path $appDir | Out-Null
New-Item -ItemType Directory -Force -Path $docsDir | Out-Null
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
New-Item -ItemType Directory -Force -Path $samplesDir | Out-Null

Write-Section 'COPY RUNTIME FILES'
Copy-Item (Join-Path $releaseRuntimeDir '*') $appDir -Recurse -Force
Write-Host "Copied full Flutter Windows runtime folder."

Write-Section 'COPY OPTIONAL PROJECT FILES'
Copy-IfExists (Join-Path $ProjectRoot 'VERSION.txt') (Join-Path $releaseDir 'VERSION.txt') | Out-Null
Copy-IfExists (Join-Path $ProjectRoot 'docs\README_RELEASE.txt') (Join-Path $docsDir 'README_RELEASE.txt') | Out-Null
Copy-IfExists (Join-Path $ProjectRoot 'scripts\windows\doctor_bluevpn.ps1') (Join-Path $toolsDir 'doctor_bluevpn.ps1') | Out-Null

Write-Section 'COPY OPTIONAL SAMPLE CONFIGS'
Copy-IfExists "$env:ProgramData\BlueVPN\BlueVPN.conf" (Join-Path $samplesDir 'BlueVPN.conf.sample') | Out-Null
Copy-IfExists "$env:ProgramData\BlueVPN\BlueVPN.base.conf" (Join-Path $samplesDir 'BlueVPN.base.conf.sample') | Out-Null

if (-not (Test-Path (Join-Path $docsDir 'README_RELEASE.txt'))) {
    @"
BlueVPN Release Package

Run:
1. Start app\bluevpn.exe as Administrator.
2. Make sure WireGuard is installed.
3. If VPN does not start, check C:\ProgramData\BlueVPN\backend.log.
4. Run tools\doctor_bluevpn.ps1 for diagnostics.

Notes:
- This package contains the full Flutter Windows release runtime.
- Do not move bluevpn.exe out of the app folder.
"@ | Set-Content -Path (Join-Path $docsDir 'README_RELEASE.txt') -Encoding UTF8
}

@"
BlueVPN release build info

Build time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Project root: $ProjectRoot
Release runtime source: $releaseRuntimeDir
Release exe: $releaseExe
Package folder: $releaseDir
Zip file: $zipPath
"@ | Set-Content -Path (Join-Path $docsDir 'BUILD_INFO.txt') -Encoding UTF8

Write-Section 'CREATE ZIP'
Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath -Force

Write-Section 'DONE'
Write-Host "Package folder: $releaseDir" -ForegroundColor Green
Write-Host "Zip file:       $zipPath" -ForegroundColor Green

if ($OpenFolder) {
    explorer /select,"$zipPath"
}
