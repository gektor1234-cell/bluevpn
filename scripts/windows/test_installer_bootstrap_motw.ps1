param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$LauncherPath = '',
    [string]$ReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CSharpCompiler {
    foreach ($candidate in @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw 'The .NET Framework C# compiler was not found.'
}

$root = Join-Path $env:TEMP ("GreenVpnBootstrapSmoke_" + [Guid]::NewGuid().ToString('N'))
$marker = Join-Path $root 'ui-started.txt'
$launcher = Join-Path $root 'install_bootstrap.exe'
$source = Join-Path $ProjectRoot 'scripts\windows\installer_bootstrap.cs'

try {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    if ([string]::IsNullOrWhiteSpace($LauncherPath)) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $root 'installer_bootstrap.cs') -Force
        $compiler = Get-CSharpCompiler
        & $compiler /nologo /target:winexe /optimize+ /platform:anycpu /reference:System.Windows.Forms.dll "/out:$launcher" (Join-Path $root 'installer_bootstrap.cs')
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $launcher)) {
            throw "Bootstrap compilation failed with exit code $LASTEXITCODE."
        }
    } else {
        $resolvedLauncher = (Resolve-Path -LiteralPath $LauncherPath).Path
        Copy-Item -LiteralPath $resolvedLauncher -Destination $launcher -Force
    }

    "Set-Content -LiteralPath '$($marker.Replace("'", "''"))' -Value 'started' -Encoding ASCII; exit 0" |
        Set-Content -LiteralPath (Join-Path $root 'install_ui.ps1') -Encoding UTF8
    '# smoke payload' | Set-Content -LiteralPath (Join-Path $root 'install_greenvpn.ps1') -Encoding UTF8
    'smoke' | Set-Content -LiteralPath (Join-Path $root 'GreenVPN_payload.zip') -Encoding ASCII
    'smoke' | Set-Content -LiteralPath (Join-Path $root 'app_icon.ico') -Encoding ASCII

    foreach ($path in @(
        (Join-Path $root 'install_ui.ps1'),
        (Join-Path $root 'install_greenvpn.ps1'),
        (Join-Path $root 'GreenVPN_payload.zip'),
        (Join-Path $root 'app_icon.ico')
    )) {
        Set-Content -LiteralPath ($path + ':Zone.Identifier') -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
    }

    $process = Start-Process -FilePath $launcher -Wait -PassThru
    $zoneStreams = @(Get-ChildItem -LiteralPath $root -File | ForEach-Object {
        Get-Item -LiteralPath $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue
    })
    $success = $process.ExitCode -eq 0 -and (Test-Path -LiteralPath $marker) -and $zoneStreams.Count -eq 0
    $report = [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        success = $success
        exitCode = $process.ExitCode
        uiStarted = Test-Path -LiteralPath $marker
        remainingZoneStreams = $zoneStreams.Count
    }

    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        $parent = Split-Path -Parent $ReportPath
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        $report | ConvertTo-Json | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    }
    $report | ConvertTo-Json
    if (-not $success) {
        throw 'Installer bootstrap MOTW smoke failed.'
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
