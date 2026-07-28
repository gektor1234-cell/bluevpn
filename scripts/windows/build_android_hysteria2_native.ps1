param(
    [string]$SourceRoot,
    [string]$GoExe,
    [string]$NdkRoot,
    [string]$OutputRoot,
    [ValidateRange(1, 3)]
    [int]$ReproducibilityPasses = 2,
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$PinnedCommit = "2d973f9513ef661d1922d6d14acb37945caef47d"
$PinnedVersion = "app/v2.9.3"
$PinnedGoVersion = "go1.25.1"
$PinnedNdkVersion = "28.2.13676358"
$AndroidApi = 26
$BuildDate = "2026-06-18T18:48:37Z"
$CommandPackage = "github.com/apernet/hysteria/app/v2/cmd"
$RunningOnWindows = $env:OS -eq "Windows_NT"
$PrebuiltHost = if ($RunningOnWindows) { "windows-x86_64" } else { "linux-x86_64" }
$ExecutableSuffix = if ($RunningOnWindows) { ".exe" } else { "" }
$CompilerSuffix = if ($RunningOnWindows) { ".cmd" } else { "" }
$ManifestPath = Join-Path $RepoRoot (
    "android\transport_preview\hysteria_tunnel\HYSTERIA-NATIVE-MANIFEST.json"
)

$Targets = @(
    [ordered]@{
        asset = "arm64"
        abi = "arm64-v8a"
        goArch = "arm64"
        goArm = ""
        compiler = "aarch64-linux-android${AndroidApi}-clang"
    },
    [ordered]@{
        asset = "armv7"
        abi = "armeabi-v7a"
        goArch = "arm"
        goArm = "7"
        compiler = "armv7a-linux-androideabi${AndroidApi}-clang"
    },
    [ordered]@{
        asset = "x86"
        abi = "x86"
        goArch = "386"
        goArm = ""
        compiler = "i686-linux-android${AndroidApi}-clang"
    },
    [ordered]@{
        asset = "amd64"
        abi = "x86_64"
        goArch = "amd64"
        goArm = ""
        compiler = "x86_64-linux-android${AndroidApi}-clang"
    }
)

function Resolve-Ndk {
    if (-not [string]::IsNullOrWhiteSpace($NdkRoot)) {
        return [IO.Path]::GetFullPath($NdkRoot)
    }
    $sdkRoot = $env:ANDROID_SDK_ROOT
    if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
        $sdkRoot = $env:ANDROID_HOME
    }
    if ([string]::IsNullOrWhiteSpace($sdkRoot) -and $RunningOnWindows) {
        $sdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    }
    if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
        throw "ANDROID_SDK_ROOT or ANDROID_HOME must point to an Android SDK."
    }
    return [IO.Path]::GetFullPath(
        (Join-Path $sdkRoot "ndk\$PinnedNdkVersion")
    )
}

function Resolve-Go {
    if (-not [string]::IsNullOrWhiteSpace($GoExe)) {
        return [IO.Path]::GetFullPath($GoExe)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GREENVPN_GO_EXE)) {
        return [IO.Path]::GetFullPath($env:GREENVPN_GO_EXE)
    }
    if ($RunningOnWindows) {
        $checkpointGo = Join-Path $env:USERPROFILE (
            "GreenVPN_Checkpoints\toolchains\go1.25.1-complete\go\bin\go.exe"
        )
        if (Test-Path -LiteralPath $checkpointGo -PathType Leaf) {
            return [IO.Path]::GetFullPath($checkpointGo)
        }
    }
    $command = Get-Command "go$ExecutableSuffix" -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "Go $PinnedGoVersion is required. Pass -GoExe or set GREENVPN_GO_EXE."
    }
    return $command.Source
}

function Resolve-Source {
    if (-not [string]::IsNullOrWhiteSpace($SourceRoot)) {
        return [IO.Path]::GetFullPath($SourceRoot)
    }
    if ($RunningOnWindows) {
        $checkpointSource = Join-Path $env:USERPROFILE (
            "GreenVPN_Checkpoints\third_party\hysteria-app-v2.9.3"
        )
        if (Test-Path -LiteralPath $checkpointSource -PathType Container) {
            return [IO.Path]::GetFullPath($checkpointSource)
        }
    }

    $checkout = Join-Path $RepoRoot "build\third_party\hysteria-$PinnedCommit"
    if (-not (Test-Path -LiteralPath $checkout -PathType Container)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $checkout) |
            Out-Null
        & git clone --filter=blob:none --no-checkout `
            https://github.com/apernet/hysteria.git `
            $checkout
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone pinned Hysteria source."
        }
        & git -C $checkout checkout --detach $PinnedCommit
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to checkout pinned Hysteria commit."
        }
    }
    return [IO.Path]::GetFullPath($checkout)
}

function Assert-HysteriaLibraries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReadElf
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Pinned Hysteria native manifest is missing: $ManifestPath"
    }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if (
        [int]$manifest.schemaVersion -ne 1 -or
        $manifest.hysteriaVersion -ne $PinnedVersion -or
        $manifest.sourceCommit -ne $PinnedCommit -or
        $manifest.goVersion -ne $PinnedGoVersion -or
        $manifest.ndkRevision -ne $PinnedNdkVersion -or
        [int]$manifest.androidApi -ne $AndroidApi -or
        [int]$manifest.pageSizeBytes -ne 16384
    ) {
        throw "Pinned Hysteria native manifest provenance mismatch."
    }

    $results = @()
    foreach ($target in $Targets) {
        $expected = @($manifest.files | Where-Object abi -eq $target.abi)
        if ($expected.Count -ne 1 -or $expected[0].sha256 -notmatch "^[0-9A-Fa-f]{64}$") {
            throw "Pinned Hysteria manifest does not contain ABI $($target.abi)."
        }
        $library = Join-Path (
            Join-Path $OutputRoot ([string]$target.abi)
        ) "libhysteria.so"
        if (-not (Test-Path -LiteralPath $library -PathType Leaf)) {
            throw "Pinned Hysteria native library is missing: $library"
        }
        $actualHash = (
            Get-FileHash -LiteralPath $library -Algorithm SHA256
        ).Hash.ToUpperInvariant()
        if ($actualHash -ne $expected[0].sha256.ToUpperInvariant()) {
            throw "Pinned Hysteria hash mismatch for ABI $($target.abi)."
        }
        $loadLines = @(
            & $ReadElf -lW $library |
                Where-Object { $_ -match "^\s*LOAD\s" }
        )
        if ($LASTEXITCODE -ne 0 -or $loadLines.Count -eq 0) {
            throw "Unable to inspect Hysteria ELF headers: $library"
        }
        $bad = @(
            $loadLines | Where-Object {
                if ($_ -notmatch "(0x[0-9A-Fa-f]+)\s*$") {
                    return $true
                }
                $alignment = [Convert]::ToInt64($Matches[1].Substring(2), 16)
                return $alignment -lt 16384 -or ($alignment % 16384) -ne 0
            }
        )
        if ($bad.Count -ne 0) {
            throw "Hysteria library is not 16 KB compatible: $library"
        }
        $results += [pscustomobject]@{
            abi = $target.abi
            sha256 = $actualHash
            loadAlignment = "0x4000-or-greater"
            path = $library
        }
    }
    return $results
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepoRoot (
        "android\transport_preview\hysteria_tunnel\src\main\jniLibs"
    )
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

$resolvedNdk = Resolve-Ndk
$sourceProperties = Join-Path $resolvedNdk "source.properties"
if (-not (Test-Path -LiteralPath $sourceProperties -PathType Leaf)) {
    throw "Android NDK not found: $resolvedNdk"
}
if ((Get-Content -LiteralPath $sourceProperties -Raw) -notmatch [regex]::Escape($PinnedNdkVersion)) {
    throw "Android NDK $PinnedNdkVersion is required: $resolvedNdk"
}
$toolBin = Join-Path $resolvedNdk "toolchains\llvm\prebuilt\$PrebuiltHost\bin"
$readElf = Join-Path $toolBin "llvm-readelf$ExecutableSuffix"
if (-not (Test-Path -LiteralPath $readElf -PathType Leaf)) {
    throw "llvm-readelf is missing from the pinned NDK: $readElf"
}

if ($VerifyOnly) {
    Assert-HysteriaLibraries -ReadElf $readElf |
        ConvertTo-Json -Depth 5
    exit 0
}

$resolvedGo = Resolve-Go
$actualGoVersion = (& $resolvedGo version)
if ($LASTEXITCODE -ne 0 -or $actualGoVersion -notmatch "\b$PinnedGoVersion\b") {
    throw "Go $PinnedGoVersion is required. Found: $actualGoVersion"
}
$resolvedSource = Resolve-Source
$actualCommit = (& git -C $resolvedSource rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $PinnedCommit) {
    throw "Hysteria source must be exactly $PinnedCommit. Found: $actualCommit"
}
if (-not (Test-Path -LiteralPath (Join-Path $resolvedSource "app\go.mod") -PathType Leaf)) {
    throw "Pinned Hysteria source is incomplete: $resolvedSource"
}

$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "greenvpn-hysteria-native-" + [Guid]::NewGuid().ToString("N")
)
$previousEnvironment = @{}
foreach ($name in @(
    "GOOS", "GOARCH", "GOARM", "CGO_ENABLED", "GOTOOLCHAIN", "CC",
    "CGO_CFLAGS", "CGO_LDFLAGS"
)) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    $passResults = @()
    for ($pass = 1; $pass -le $ReproducibilityPasses; $pass++) {
        foreach ($target in $Targets) {
            $compiler = Join-Path $toolBin (
                ([string]$target.compiler) + $CompilerSuffix
            )
            if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
                throw "Pinned NDK compiler is missing: $compiler"
            }

            $env:GOOS = "android"
            $env:GOARCH = [string]$target.goArch
            if ([string]::IsNullOrWhiteSpace([string]$target.goArm)) {
                Remove-Item Env:GOARM -ErrorAction SilentlyContinue
            } else {
                $env:GOARM = [string]$target.goArm
            }
            $env:CGO_ENABLED = "1"
            $env:GOTOOLCHAIN = "local"
            $env:CC = $compiler
            $env:CGO_CFLAGS = "-fPIC"
            $env:CGO_LDFLAGS = (
                "-Wl,-z,max-page-size=16384 " +
                "-Wl,-z,common-page-size=16384"
            )

            $passRoot = Join-Path $stagingRoot "pass-$pass"
            New-Item -ItemType Directory -Force -Path $passRoot | Out-Null
            $output = Join-Path $passRoot (
                "hysteria-android-" + [string]$target.asset
            )
            $ldflags = @(
                "-s", "-w", "-buildid=", "-checklinkname=0",
                "-X", "$CommandPackage.appVersion=v2.9.3",
                "-X", "$CommandPackage.appDate=$BuildDate",
                "-X", "$CommandPackage.appType=release-api26-16kb",
                "-X", "$CommandPackage.appToolchain=$PinnedGoVersion",
                "-X", "$CommandPackage.appCommit=$PinnedCommit",
                "-X", "$CommandPackage.libVersion=v0.60.1-0.20260618182935-599b15a1fa26",
                "-X", "$CommandPackage.appPlatform=android",
                "-X", "$CommandPackage.appArch=$($target.asset)"
            ) -join " "

            & $resolvedGo -C $resolvedSource build `
                -trimpath `
                -buildvcs=false `
                -o $output `
                -ldflags $ldflags `
                ./app
            if ($LASTEXITCODE -ne 0) {
                throw "Hysteria native build failed for $($target.abi), pass $pass."
            }
            $passResults += [pscustomobject]@{
                pass = $pass
                abi = [string]$target.abi
                path = $output
                sha256 = (
                    Get-FileHash -LiteralPath $output -Algorithm SHA256
                ).Hash.ToUpperInvariant()
            }
        }
    }

    $manifestFiles = @()
    foreach ($target in $Targets) {
        $abiResults = @($passResults | Where-Object abi -eq $target.abi)
        $uniqueHashes = @($abiResults.sha256 | Sort-Object -Unique)
        if ($uniqueHashes.Count -ne 1) {
            throw "Hysteria native build is not reproducible for ABI $($target.abi)."
        }
        $sourceOutput = @(
            $abiResults | Where-Object pass -eq $ReproducibilityPasses
        )[0].path
        $destinationRoot = Join-Path $OutputRoot ([string]$target.abi)
        New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
        $destination = Join-Path $destinationRoot "libhysteria.so"
        Copy-Item -LiteralPath $sourceOutput -Destination $destination -Force
        $manifestFiles += [ordered]@{
            asset = [string]$target.asset
            abi = [string]$target.abi
            file = "libhysteria.so"
            sha256 = $uniqueHashes[0]
            sizeBytes = (Get-Item -LiteralPath $destination).Length
        }
    }

    $manifest = [ordered]@{
        schemaVersion = 1
        hysteriaVersion = $PinnedVersion
        sourceCommit = $PinnedCommit
        goVersion = $PinnedGoVersion
        ndkRevision = $PinnedNdkVersion
        androidApi = $AndroidApi
        pageSizeBytes = 16384
        reproducibilityPasses = $ReproducibilityPasses
        linkerFlags = @(
            "-Wl,-z,max-page-size=16384",
            "-Wl,-z,common-page-size=16384"
        )
        files = $manifestFiles
    }
    [IO.File]::WriteAllText(
        $ManifestPath,
        ($manifest | ConvertTo-Json -Depth 8),
        [Text.UTF8Encoding]::new($false)
    )
} finally {
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $previousEnvironment[$name],
            "Process"
        )
    }
    if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}

Assert-HysteriaLibraries -ReadElf $readElf |
    ConvertTo-Json -Depth 5
