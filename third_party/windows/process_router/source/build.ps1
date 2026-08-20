[CmdletBinding()]
param(
    [string]$WinDivertRoot = $(
        if ($env:WINDIVERT_ROOT) { $env:WINDIVERT_ROOT }
        else { 'C:\WinDivert-2.2.2-A' }
    ),
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $PSScriptRoot 'output'
}

$vsWhere = Join-Path ${env:ProgramFiles(x86)} `
    'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vsWhere -PathType Leaf)) {
    throw 'Visual Studio locator was not found.'
}
$vsPath = & $vsWhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
if (-not $vsPath) { throw 'Visual Studio C++ x64 tools were not found.' }
$vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvarsall.bat'
if (-not (Test-Path -LiteralPath $vcvars -PathType Leaf)) {
    throw 'vcvarsall.bat was not found.'
}

$includeRoot = Join-Path $WinDivertRoot 'include'
$libraryRoot = Join-Path $WinDivertRoot 'x64'
foreach ($path in @(
    (Join-Path $includeRoot 'windivert.h'),
    (Join-Path $libraryRoot 'WinDivert.lib'),
    (Join-Path $libraryRoot 'WinDivert.dll'),
    (Join-Path $libraryRoot 'WinDivert64.sys')
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required WinDivert file is missing: $path"
    }
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
$coreOutput = Join-Path $resolvedOutput 'ProxyBridgeCore.dll'
$cliOutput = Join-Path $resolvedOutput 'ProxyBridge_CLI.exe'
$buildRoot = Join-Path $env:TEMP (
    'GreenVpnProxyBridgeBuild_' + [guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

$commonCompile = '/nologo /O2 /Ot /GL /Gy /W4 /wd4100 /wd4189 ' +
    '/wd4267 /wd4244 /wd4996 /D_CRT_SECURE_NO_WARNINGS ' +
    '/D_WINSOCK_DEPRECATED_NO_WARNINGS /D_WIN32_WINNT=0x0601 ' +
    '/DNDEBUG /arch:SSE2 /fp:fast /GS /guard:cf /Brepro'
$commonLink = '/LTCG /OPT:REF /OPT:ICF /RELEASE /DYNAMICBASE /NXCOMPAT /Brepro'

$coreCommand = 'cl.exe ' + $commonCompile +
    ' /DPROXYBRIDGE_EXPORTS ' +
    ('/I"{0}" "{1}" /LD /link {2} /LIBPATH:"{3}" ' -f `
        $includeRoot, (Join-Path $PSScriptRoot 'ProxyBridge.c'),
        $commonLink, $libraryRoot) +
    ('WinDivert.lib ws2_32.lib iphlpapi.lib /OUT:"{0}"' -f $coreOutput)
$cliCommand = 'cl.exe ' + $commonCompile + ' ' +
    ('"{0}" /link {1} /SUBSYSTEM:CONSOLE ' -f `
        (Join-Path $PSScriptRoot 'main.c'), $commonLink) +
    ('winhttp.lib shell32.lib advapi32.lib /OUT:"{0}"' -f $cliOutput)

try {
    Push-Location $buildRoot
    try {
        foreach ($command in @($coreCommand, $cliCommand)) {
            $output = & $env:ComSpec /d /c `
                ('call "{0}" x64 >nul && {1}' -f $vcvars, $command) 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "MSVC build failed:`n$($output -join [Environment]::NewLine)"
            }
        }
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Copy-Item -LiteralPath (Join-Path $libraryRoot 'WinDivert.dll') `
    -Destination $resolvedOutput -Force
Copy-Item -LiteralPath (Join-Path $libraryRoot 'WinDivert64.sys') `
    -Destination $resolvedOutput -Force

$driverSignature = Get-AuthenticodeSignature -LiteralPath (
    Join-Path $resolvedOutput 'WinDivert64.sys'
)
if ($driverSignature.Status -ne [Management.Automation.SignatureStatus]::Valid) {
    throw "WinDivert driver signature is invalid: $($driverSignature.Status)"
}

@('ProxyBridge_CLI.exe', 'ProxyBridgeCore.dll', 'WinDivert.dll', 'WinDivert64.sys') |
    ForEach-Object {
        $path = Join-Path $resolvedOutput $_
        [pscustomobject]@{
            name = $_
            size = (Get-Item -LiteralPath $path).Length
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }
    } | ConvertTo-Json | Write-Output
