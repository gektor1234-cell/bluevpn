[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedInstallerSha256,
    [Parameter(Mandatory = $true)]
    [long]$ExpectedInstallerSize,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,
    [Parameter(Mandatory = $true)]
    [string]$ArtifactRoot,
    [ValidateRange(90, 600)]
    [int]$InitialDelaySeconds = 90,
    [ValidateRange(900, 3600)]
    [int]$DeadmanDelaySeconds = 2400,
    [ValidateRange(10, 120)]
    [int]$MaxConnectSeconds = 30,
    [ValidateRange(60, 1200)]
    [int]$StandbyCycleTimeoutSeconds = 600,
    [ValidateRange(15, 180)]
    [int]$MaxPrevalidatedFailoverSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$runnerPath = Join-Path $repoRoot 'scripts\windows\run_windows_standby_tray_release_smoke.ps1'
$resolvedInstaller = [IO.Path]::GetFullPath($InstallerPath)
$resolvedArtifactRoot = [IO.Path]::GetFullPath($ArtifactRoot)
$statusPath = Join-Path $resolvedArtifactRoot 'windows-standby-tray-launcher-status.json'
$expectedHash = $ExpectedInstallerSha256.ToUpperInvariant()

New-Item -ItemType Directory -Force -Path $resolvedArtifactRoot | Out-Null

function Write-LauncherStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Phase,
        [int]$ElevatedProcessId = 0,
        [string]$Failure = ''
    )
    $status = [ordered]@{
        updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        phase = $Phase
        runnerPath = $runnerPath
        artifactRoot = $resolvedArtifactRoot
        expectedInstallerSha256 = $expectedHash
        expectedInstallerSize = $ExpectedInstallerSize
        expectedVersion = $ExpectedVersion
        elevatedProcessId = $(if ($ElevatedProcessId -gt 0) { $ElevatedProcessId } else { $null })
        failure = $(if ($Failure) { $Failure } else { $null })
    }
    $temporaryPath = "$statusPath.tmp"
    $status | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $statusPath -Force
}

function Quote-NativeArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

try {
    if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
        throw "Autonomous runner is missing: $runnerPath"
    }
    if (-not (Test-Path -LiteralPath $resolvedInstaller -PathType Leaf)) {
        throw "Exact installer is missing: $resolvedInstaller"
    }
    $installer = Get-Item -LiteralPath $resolvedInstaller
    $actualHash = (Get-FileHash -LiteralPath $resolvedInstaller -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash -or [long]$installer.Length -ne $ExpectedInstallerSize) {
        throw 'Exact installer SHA-256 or size mismatch.'
    }

    $existing = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -like "*$runnerPath*" -and
            $_.CommandLine -like "*$resolvedArtifactRoot*"
        })
    if ($existing.Count -gt 0) {
        throw "The exact autonomous runner is already active (PID $($existing[0].ProcessId))."
    }

    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', (Quote-NativeArgument -Value $runnerPath),
        '-InstallerPath', (Quote-NativeArgument -Value $resolvedInstaller),
        '-ExpectedInstallerSha256', $expectedHash,
        '-ExpectedInstallerSize', [string]$ExpectedInstallerSize,
        '-ExpectedVersion', (Quote-NativeArgument -Value $ExpectedVersion),
        '-ArtifactRoot', (Quote-NativeArgument -Value $resolvedArtifactRoot),
        '-InitialDelaySeconds', [string]$InitialDelaySeconds,
        '-DeadmanDelaySeconds', [string]$DeadmanDelaySeconds,
        '-MaxConnectSeconds', [string]$MaxConnectSeconds,
        '-StandbyCycleTimeoutSeconds', [string]$StandbyCycleTimeoutSeconds,
        '-MaxPrevalidatedFailoverSeconds', [string]$MaxPrevalidatedFailoverSeconds
    )

    Write-LauncherStatus -Phase 'uac_requested'
    $elevated = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
        -ArgumentList $arguments -WindowStyle Hidden -PassThru
    Write-LauncherStatus -Phase 'runner_started' -ElevatedProcessId $elevated.Id
} catch {
    Write-LauncherStatus -Phase 'launch_failed' -Failure $_.Exception.Message
    throw
}
