param(
    [string]$SourceDir,
    [string]$OutputRoot,
    [string]$NdkRoot,
    [string]$GoExe,
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$PinnedCommit = "fb64e74ba5a0a54e9185b8776bcb8088afb772c9"
$PinnedGoVersion = "go1.25.1"
$PinnedNdkVersion = "28.2.13676358"
$AndroidApi = 26
$SocketDirectory = "/data/data/pro.greenvpn.app/cache/amneziawg"
$RunningOnWindows = $env:OS -eq "Windows_NT"
$PrebuiltHost = if ($RunningOnWindows) { "windows-x86_64" } else { "linux-x86_64" }
$ExecutableSuffix = if ($RunningOnWindows) { ".exe" } else { "" }
$CompilerSuffix = if ($RunningOnWindows) { ".cmd" } else { "" }

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepoRoot "android\transport_preview\awg_tunnel\src\main\jniLibs"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

$ExpectedHashes = @{
    "arm64-v8a"   = "C7EB9426709EA41939730F00040C310C0D4941808162127D2B25AF34728BF96A"
    "armeabi-v7a" = "0CBA97BA24E364D4418A141A7720D02DE3C1383B7301EC9488BF7513E6798264"
    "x86"         = "88670A68D0D40691955B6425FC6C90A156E4E8A89883792D8173CB31099BD549"
    "x86_64"      = "503DEC4AFC463B1D52EC0FD3A61EA0C892B48FB83A25797F2B9FF5DD9585B405"
}

$Targets = @(
    @{
        Abi = "arm64-v8a"
        GoArch = "arm64"
        Compiler = "aarch64-linux-android${AndroidApi}-clang"
        GoArm = $null
    },
    @{
        Abi = "armeabi-v7a"
        GoArch = "arm"
        Compiler = "armv7a-linux-androideabi${AndroidApi}-clang"
        GoArm = "7"
    },
    @{
        Abi = "x86"
        GoArch = "386"
        Compiler = "i686-linux-android${AndroidApi}-clang"
        GoArm = $null
    },
    @{
        Abi = "x86_64"
        GoArch = "amd64"
        Compiler = "x86_64-linux-android${AndroidApi}-clang"
        GoArm = $null
    }
)

function Resolve-NdkRoot {
    if (-not [string]::IsNullOrWhiteSpace($NdkRoot)) {
        return [IO.Path]::GetFullPath($NdkRoot)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_NDK_HOME)) {
        return [IO.Path]::GetFullPath($env:ANDROID_NDK_HOME)
    }
    $sdkRoot = $env:ANDROID_SDK_ROOT
    if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
        $sdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    }
    return [IO.Path]::GetFullPath(
        (Join-Path $sdkRoot "ndk\$PinnedNdkVersion")
    )
}

function Resolve-GoExe {
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

function Assert-NativeLibraries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReadElf
    )

    $result = @()
    foreach ($target in $Targets) {
        $abi = [string]$target.Abi
        $library = Join-Path (Join-Path $OutputRoot $abi) "libawg2-go.so"
        if (-not (Test-Path -LiteralPath $library -PathType Leaf)) {
            throw "Missing AWG2 native library: $library"
        }
        $loadLines = @(
            & $ReadElf -l $library |
                Where-Object { $_ -match "^\s*LOAD\s" }
        )
        if ($LASTEXITCODE -ne 0 -or $loadLines.Count -eq 0) {
            throw "Unable to inspect ELF program headers: $library"
        }
        $badAlignments = @(
            $loadLines | Where-Object { $_ -notmatch "0x4000\s*$" }
        )
        if ($badAlignments.Count -ne 0) {
            throw "AWG2 library is not 16 KB aligned: $library"
        }
        $actualHash = (
            Get-FileHash -LiteralPath $library -Algorithm SHA256
        ).Hash.ToUpperInvariant()
        if ($actualHash -ne $ExpectedHashes[$abi]) {
            throw "AWG2 hash mismatch for $abi. Expected $($ExpectedHashes[$abi]), got $actualHash."
        }
        $result += [pscustomobject]@{
            Abi = $abi
            Sha256 = $actualHash
            LoadAlignment = "0x4000"
            Path = $library
        }
    }
    return $result
}

$resolvedNdk = Resolve-NdkRoot
$ndkVersionFile = Join-Path $resolvedNdk "source.properties"
if (-not (Test-Path -LiteralPath $ndkVersionFile -PathType Leaf)) {
    throw "Android NDK not found: $resolvedNdk"
}
$ndkProperties = Get-Content -LiteralPath $ndkVersionFile -Raw
if ($ndkProperties -notmatch [regex]::Escape($PinnedNdkVersion)) {
    throw "Android NDK $PinnedNdkVersion is required: $resolvedNdk"
}
$toolBin = Join-Path $resolvedNdk "toolchains\llvm\prebuilt\$PrebuiltHost\bin"
$readElf = Join-Path $toolBin "llvm-readelf$ExecutableSuffix"
if (-not (Test-Path -LiteralPath $readElf -PathType Leaf)) {
    throw "llvm-readelf.exe is missing from NDK: $readElf"
}

if ($VerifyOnly) {
    Assert-NativeLibraries -ReadElf $readElf |
        ConvertTo-Json -Depth 4
    exit 0
}

$resolvedGo = Resolve-GoExe
$actualGoVersion = (& $resolvedGo version)
if ($LASTEXITCODE -ne 0 -or $actualGoVersion -notmatch "\b$PinnedGoVersion\b") {
    throw "Go $PinnedGoVersion is required. Found: $actualGoVersion"
}

if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    $SourceDir = Join-Path $RepoRoot (
        "build\third_party\amneziawg-android-$PinnedCommit"
    )
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $SourceDir) |
            Out-Null
        & git clone --filter=blob:none --no-checkout `
            https://github.com/amnezia-vpn/amneziawg-android.git `
            $SourceDir
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone AmneziaWG Android source."
        }
        & git -C $SourceDir checkout --detach $PinnedCommit
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to checkout pinned AmneziaWG commit."
        }
    }
}
$SourceDir = [IO.Path]::GetFullPath($SourceDir)
$actualCommit = (& git -C $SourceDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $PinnedCommit) {
    throw "AmneziaWG source must be exactly $PinnedCommit. Found: $actualCommit"
}
$goSource = Join-Path $SourceDir "tunnel\tools\libwg-go"
if (-not (Test-Path -LiteralPath (Join-Path $goSource "go.sum") -PathType Leaf)) {
    throw "Pinned libwg-go source is incomplete: $goSource"
}

$temporaryRoot = Join-Path $RepoRoot "build\awg2-native-staging"
if (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null

Push-Location $goSource
try {
    foreach ($target in $Targets) {
        $abi = [string]$target.Abi
        $compiler = Join-Path $toolBin (([string]$target.Compiler) + $CompilerSuffix)
        if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
            throw "NDK compiler is missing: $compiler"
        }
        $stageDir = Join-Path $temporaryRoot $abi
        New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
        $stageLibrary = Join-Path $stageDir "libawg2-go.so"

        $env:CGO_ENABLED = "1"
        $env:GOOS = "android"
        $env:GOARCH = [string]$target.GoArch
        $env:CC = $compiler
        $env:CGO_CFLAGS = "-fPIC"
        $env:CGO_LDFLAGS = (
            "-Wl,-z,max-page-size=16384 " +
            "-Wl,-z,common-page-size=16384 " +
            "-Wl,-soname=libawg2-go.so"
        )
        if ($null -eq $target.GoArm) {
            Remove-Item Env:GOARM -ErrorAction SilentlyContinue
        } else {
            $env:GOARM = [string]$target.GoArm
        }

        $linkerFlags = (
            "-X github.com/amnezia-vpn/amneziawg-go/ipc.socketDirectory=" +
            "$SocketDirectory -buildid="
        )
        & $resolvedGo build `
            -tags linux `
            "-ldflags=$linkerFlags" `
            -trimpath `
            -buildvcs=false `
            -o $stageLibrary `
            -buildmode c-shared `
            .
        if ($LASTEXITCODE -ne 0) {
            throw "AWG2 native build failed for $abi."
        }
        $destinationDir = Join-Path $OutputRoot $abi
        New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
        Copy-Item -LiteralPath $stageLibrary `
            -Destination (Join-Path $destinationDir "libawg2-go.so") `
            -Force
    }
} finally {
    Pop-Location
}

Assert-NativeLibraries -ReadElf $readElf |
    ConvertTo-Json -Depth 4
