param(
    [string]$SourceRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\hysteria-app-v2.9.3',
    [string]$GoRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\toolchains\go1.25.1-complete\go',
    [string]$GoArchive = 'C:\Users\gekto\GreenVPN_Checkpoints\toolchains\go1.25.1.windows-amd64.zip',
    [string]$NdkRoot = "$env:LOCALAPPDATA\Android\Sdk\ndk\28.2.13676358",
    [string]$OutputRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\third_party\hysteria-app-v2.9.3-android-api24'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedCommit = '2d973f9513ef661d1922d6d14acb37945caef47d'
$expectedGoVersion = 'go version go1.25.1 windows/amd64'
$expectedGoArchiveSha256 = '4A974DE310E7EE1D523D2FCEDB114BA5FA75408C98EB3652023E55CCF3FA7CAB'
$expectedNdkRevision = '28.2.13676358'
$buildDate = '2026-06-18T18:48:37Z'
$apiLevel = 24
$commandPackage = 'github.com/apernet/hysteria/app/v2/cmd'
$expectedHashes = [ordered]@{
    'arm64' = '0A019366C970C5298835E155A2923E35A42E7C72505EFC93F9D3F21D2D8C9454'
    'armv7' = 'F900A64CAF83916228E17D61CFB8937A3E2D49228B955DDBB9D508AEC44D761A'
    'amd64' = '0CB45CBBF3E1D5CC0B2B9F54750D8D491CEDB4B11C203A944C3BE587C554A353'
}
$targets = @(
    [ordered]@{ asset = 'arm64'; goArch = 'arm64'; goArm = ''; compiler = 'aarch64-linux-android24-clang.cmd' },
    [ordered]@{ asset = 'armv7'; goArch = 'arm'; goArm = '7'; compiler = 'armv7a-linux-androideabi24-clang.cmd' },
    [ordered]@{ asset = 'amd64'; goArch = 'amd64'; goArm = ''; compiler = 'x86_64-linux-android24-clang.cmd' }
)

$go = Join-Path $GoRoot 'bin\go.exe'
$readElf = Join-Path $NdkRoot 'toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe'
foreach ($required in @($go, $GoArchive, $readElf, (Join-Path $SourceRoot 'app\go.mod'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required Hysteria2 API24 build input is missing: $required"
    }
}

$actualCommit = (git -C $SourceRoot rev-parse HEAD).Trim()
if ($actualCommit -ne $expectedCommit) { throw "Unexpected Hysteria2 source commit: $actualCommit" }
$actualGoVersion = (& $go version).Trim()
if ($actualGoVersion -ne $expectedGoVersion) { throw "Unexpected Go toolchain: $actualGoVersion" }
$actualArchiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $GoArchive).Hash
if ($actualArchiveHash -ne $expectedGoArchiveSha256) { throw 'Go archive hash mismatch.' }
$sourceProperties = Get-Content -LiteralPath (Join-Path $NdkRoot 'source.properties') -Raw
if ($sourceProperties -notmatch "(?m)^Pkg\.Revision\s*=\s*$([regex]::Escape($expectedNdkRevision))\s*$") {
    throw "Unexpected Android NDK revision in $NdkRoot"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$previousEnvironment = @{}
foreach ($name in @('GOOS','GOARCH','GOARM','CGO_ENABLED','GOTOOLCHAIN','CC')) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$results = @()
try {
    foreach ($target in $targets) {
        $compiler = Join-Path $NdkRoot "toolchains\llvm\prebuilt\windows-x86_64\bin\$($target.compiler)"
        if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw "NDK compiler is missing: $compiler" }
        $env:GOOS = 'android'
        $env:GOARCH = $target.goArch
        if ($target.goArm) { $env:GOARM = $target.goArm } else { Remove-Item Env:GOARM -ErrorAction SilentlyContinue }
        $env:CGO_ENABLED = '1'
        $env:GOTOOLCHAIN = 'local'
        $env:CC = $compiler

        $name = "hysteria-android-$($target.asset)"
        $output = Join-Path $OutputRoot $name
        $temporary = "$output.tmp-$PID"
        $ldflags = @(
            '-s', '-w', '-buildid=', '-checklinkname=0',
            '-X', "$commandPackage.appVersion=v2.9.3",
            '-X', "$commandPackage.appDate=$buildDate",
            '-X', "$commandPackage.appType=release-api24",
            '-X', "$commandPackage.appToolchain=go1.25.1-windows-amd64",
            '-X', "$commandPackage.appCommit=$expectedCommit",
            '-X', "$commandPackage.libVersion=v0.60.1-0.20260618182935-599b15a1fa26",
            '-X', "$commandPackage.appPlatform=android",
            '-X', "$commandPackage.appArch=$($target.asset)"
        ) -join ' '
        try {
            & $go -C $SourceRoot build -trimpath -o $temporary -ldflags $ldflags .\app
            if ($LASTEXITCODE -ne 0) { throw "Go build failed for $($target.asset): $LASTEXITCODE" }
            $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporary).Hash
            if ($hash -ne $expectedHashes[$target.asset]) {
                throw "Non-reproducible Hysteria2 API24 binary for $($target.asset): $hash"
            }
            if (@(& $readElf --dyn-syms $temporary | Select-String 'android_get_device_api_level').Count -ne 0) {
                throw "Hysteria2 $($target.asset) still imports the API29-only symbol."
            }
            Move-Item -LiteralPath $temporary -Destination $output -Force
            $item = Get-Item -LiteralPath $output
            $results += [ordered]@{ asset = $target.asset; file = $name; sha256 = $hash; size = $item.Length }
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        }
    }
} finally {
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    hysteriaVersion = 'app/v2.9.3'
    sourceCommit = $expectedCommit
    minAndroidApi = $apiLevel
    buildDate = $buildDate
    goVersion = $expectedGoVersion
    goArchiveSha256 = $expectedGoArchiveSha256
    ndkRevision = $expectedNdkRevision
    files = $results
}
$manifestPath = Join-Path $OutputRoot 'build-manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
Write-Output "Pinned Android Hysteria2 API24 binaries built: $manifestPath"
