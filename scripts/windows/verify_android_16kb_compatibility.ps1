param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,

    [string]$NdkRoot,
    [string]$BuildToolsRoot,
    [string]$JsonOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$minimumPageSize = 16384L
$runningOnWindows = $env:OS -eq "Windows_NT"
$toolSuffix = if ($runningOnWindows) { ".exe" } else { "" }
$prebuiltHost = if ($runningOnWindows) { "windows-x86_64" } else { "linux-x86_64" }

function Resolve-LatestVersionDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "$Description root not found: $Root"
    }
    $candidate = Get-ChildItem -LiteralPath $Root -Directory |
        Sort-Object {
            try { [version]$_.Name } catch { [version]"0.0" }
        } -Descending |
        Select-Object -First 1
    if ($null -eq $candidate) {
        throw "No $Description installation found under: $Root"
    }
    return $candidate.FullName
}

$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
if (-not (Test-Path -LiteralPath $resolvedApk -PathType Leaf)) {
    throw "APK not found: $ApkPath"
}

$sdkRoot = $env:ANDROID_SDK_ROOT
if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
    $sdkRoot = $env:ANDROID_HOME
}
if ([string]::IsNullOrWhiteSpace($sdkRoot) -and $runningOnWindows) {
    $sdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk"
}
if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
    throw "ANDROID_SDK_ROOT or ANDROID_HOME must point to an Android SDK."
}

if ([string]::IsNullOrWhiteSpace($NdkRoot)) {
    $preferredNdk = Join-Path $sdkRoot "ndk\28.2.13676358"
    $NdkRoot = if (Test-Path -LiteralPath $preferredNdk -PathType Container) {
        $preferredNdk
    } else {
        Resolve-LatestVersionDirectory -Root (Join-Path $sdkRoot "ndk") -Description "Android NDK"
    }
}
if ([string]::IsNullOrWhiteSpace($BuildToolsRoot)) {
    $preferredBuildTools = Join-Path $sdkRoot "build-tools\36.0.0"
    $BuildToolsRoot = if (Test-Path -LiteralPath $preferredBuildTools -PathType Container) {
        $preferredBuildTools
    } else {
        Resolve-LatestVersionDirectory -Root (Join-Path $sdkRoot "build-tools") -Description "Android build-tools"
    }
}

$readElf = Join-Path $NdkRoot "toolchains\llvm\prebuilt\$prebuiltHost\bin\llvm-readelf$toolSuffix"
$zipAlign = Join-Path $BuildToolsRoot "zipalign$toolSuffix"
foreach ($requiredTool in @($readElf, $zipAlign)) {
    if (-not (Test-Path -LiteralPath $requiredTool -PathType Leaf)) {
        throw "Required Android verification tool is missing: $requiredTool"
    }
}

$zipAlignOutput = @(& $zipAlign -P 16 -c 4 $resolvedApk)
if ($LASTEXITCODE -ne 0) {
    throw "APK ZIP entries are not 16 KB page aligned: $resolvedApk`n$($zipAlignOutput -join [Environment]::NewLine)"
}
Write-Host "APK ZIP alignment: 16 KB compatible"

Add-Type -AssemblyName System.IO.Compression.FileSystem
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "greenvpn-apk-16kb-" + [Guid]::NewGuid().ToString("N")
)
$results = @()
$incompatibleLibraries = @()
$archive = $null

try {
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    $archive = [IO.Compression.ZipFile]::OpenRead($resolvedApk)
    $nativeEntries = @(
        $archive.Entries | Where-Object {
            $_.FullName -match "^lib/([^/]+)/([^/]+\.so)$"
        }
    )
    if ($nativeEntries.Count -eq 0) {
        throw "APK does not contain native libraries: $resolvedApk"
    }

    $seenEntries = @{}
    foreach ($entry in $nativeEntries) {
        $entryName = $entry.FullName.Replace("\", "/")
        if ($seenEntries.ContainsKey($entryName)) {
            throw "APK contains a duplicate native library entry: $entryName"
        }
        $seenEntries[$entryName] = $true

        if ($entryName -notmatch "^lib/([^/]+)/([^/]+\.so)$") {
            throw "Unsafe native library path in APK: $entryName"
        }
        $abi = $Matches[1]
        $fileName = $Matches[2]
        $abiRoot = Join-Path $temporaryRoot $abi
        New-Item -ItemType Directory -Force -Path $abiRoot | Out-Null
        $extractedPath = Join-Path $abiRoot $fileName

        $inputStream = $entry.Open()
        $outputStream = [IO.File]::Open(
            $extractedPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )
        try {
            $inputStream.CopyTo($outputStream)
        } finally {
            $outputStream.Dispose()
            $inputStream.Dispose()
        }

        $programHeaders = @(& $readElf -lW $extractedPath)
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to inspect ELF program headers: $entryName"
        }
        $loadLines = @($programHeaders | Where-Object { $_ -match "^\s*LOAD\s" })
        if ($loadLines.Count -eq 0) {
            throw "ELF has no LOAD segments: $entryName"
        }

        $alignments = @(
            foreach ($loadLine in $loadLines) {
                if ($loadLine -notmatch "(0x[0-9a-fA-F]+)\s*$") {
                    throw "Unable to parse ELF LOAD alignment for ${entryName}: $loadLine"
                }
                [Convert]::ToInt64($Matches[1].Substring(2), 16)
            }
        )
        $badAlignments = @(
            $alignments | Where-Object {
                $_ -lt $minimumPageSize -or ($_ % $minimumPageSize) -ne 0
            }
        )
        $compatible = $badAlignments.Count -eq 0
        $reportedAlignments = @(
            $alignments | ForEach-Object { "0x{0:x}" -f $_ }
        )
        if (-not $compatible) {
            $incompatibleLibraries += [pscustomobject]@{
                entry = $entryName
                loadAlignments = $reportedAlignments
            }
        }

        $results += [pscustomobject]@{
            entry = $entryName
            abi = $abi
            sizeBytes = $entry.Length
            sha256 = (Get-FileHash -LiteralPath $extractedPath -Algorithm SHA256).Hash
            loadAlignments = $reportedAlignments
            compatible = $compatible
        }
    }
} finally {
    if ($null -ne $archive) {
        $archive.Dispose()
    }
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

$report = [ordered]@{
    schemaVersion = 1
    apk = $resolvedApk
    apkSha256 = (Get-FileHash -LiteralPath $resolvedApk -Algorithm SHA256).Hash
    zipAlignmentBytes = $minimumPageSize
    nativeLibraryCount = $results.Count
    compatible = $incompatibleLibraries.Count -eq 0
    incompatibleLibraries = @($incompatibleLibraries | Sort-Object entry)
    libraries = @($results | Sort-Object abi, entry)
}

if (-not [string]::IsNullOrWhiteSpace($JsonOutput)) {
    $resolvedJsonOutput = [IO.Path]::GetFullPath($JsonOutput)
    $parent = Split-Path -Parent $resolvedJsonOutput
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [IO.File]::WriteAllText(
        $resolvedJsonOutput,
        ($report | ConvertTo-Json -Depth 8),
        [Text.UTF8Encoding]::new($false)
    )
}

$report | ConvertTo-Json -Depth 8
if ($incompatibleLibraries.Count -ne 0) {
    $names = @($incompatibleLibraries.entry | Sort-Object) -join ", "
    throw "APK contains $($incompatibleLibraries.Count) native libraries that are not 16 KB compatible: $names"
}
