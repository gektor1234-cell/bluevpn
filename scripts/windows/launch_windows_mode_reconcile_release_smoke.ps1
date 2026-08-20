[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedInstallerSha256,
    [Parameter(Mandatory = $true)][long]$ExpectedInstallerSize,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedAppSha256,
    [Parameter(Mandatory = $true)][long]$ExpectedAppSize,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedAppSoSha256,
    [Parameter(Mandatory = $true)][long]$ExpectedAppSoSize,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedServiceSha256,
    [Parameter(Mandatory = $true)][long]$ExpectedServiceSize,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{40}$')]
    [string]$CandidateSourceCommit,
    [Parameter(Mandatory = $true)][string]$ArtifactRoot,
    [ValidateRange(90, 600)][int]$InitialDelaySeconds = 90,
    [ValidateRange(600, 1800)][int]$DeadmanDelaySeconds = 900,
    [ValidateRange(10, 120)][int]$MaxConnectSeconds = 30,
    [ValidateRange(15, 120)][int]$MaxModeSwitchSeconds = 60,
    [switch]$RecoverInitialBaselineAfterDelay
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$runnerPath = Join-Path $repoRoot `
    'scripts\windows\run_windows_mode_reconcile_release_smoke.ps1'
$resolvedInstaller = [IO.Path]::GetFullPath($InstallerPath)
$resolvedArtifactRoot = [IO.Path]::GetFullPath($ArtifactRoot).TrimEnd('\')
$statusPath = Join-Path $resolvedArtifactRoot `
    'windows-mode-reconcile-launcher-status.json'
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
        candidateSourceCommit = $CandidateSourceCommit.ToLowerInvariant()
        recoverInitialBaselineAfterDelay = [bool]$RecoverInitialBaselineAfterDelay
        elevatedProcessId = if ($ElevatedProcessId -gt 0) {
            $ElevatedProcessId
        } else { $null }
        failure = if ($Failure) { $Failure } else { $null }
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

function Get-FileSha256Hex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Get-Command -Name 'Get-FileHash' -ErrorAction SilentlyContinue) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
        try {
            $hashBytes = $sha256.ComputeHash($stream)
        } finally {
            $stream.Dispose()
        }
    } finally {
        $sha256.Dispose()
    }

    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToUpperInvariant()
}

try {
    foreach ($required in @($runnerPath, $resolvedInstaller)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required exact runner file is missing: $required"
        }
    }
    $installer = Get-Item -LiteralPath $resolvedInstaller
    $actualHash = Get-FileSha256Hex -Path $resolvedInstaller
    if ($actualHash -ne $expectedHash -or
            [long]$installer.Length -ne $ExpectedInstallerSize) {
        throw 'Exact installer SHA-256 or size mismatch.'
    }
    $existing = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -like "*$runnerPath*" -and
            $_.CommandLine -like "*$resolvedArtifactRoot*"
        })
    if ($existing.Count -gt 0) {
        throw "The exact mode runner is already active (PID $($existing[0].ProcessId))."
    }
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', (Quote-NativeArgument -Value $runnerPath),
        '-InstallerPath', (Quote-NativeArgument -Value $resolvedInstaller),
        '-ExpectedInstallerSha256', $expectedHash,
        '-ExpectedInstallerSize', [string]$ExpectedInstallerSize,
        '-ExpectedVersion', (Quote-NativeArgument -Value $ExpectedVersion),
        '-ExpectedAppSha256', $ExpectedAppSha256.ToUpperInvariant(),
        '-ExpectedAppSize', [string]$ExpectedAppSize,
        '-ExpectedAppSoSha256', $ExpectedAppSoSha256.ToUpperInvariant(),
        '-ExpectedAppSoSize', [string]$ExpectedAppSoSize,
        '-ExpectedServiceSha256', $ExpectedServiceSha256.ToUpperInvariant(),
        '-ExpectedServiceSize', [string]$ExpectedServiceSize,
        '-CandidateSourceCommit', $CandidateSourceCommit.ToLowerInvariant(),
        '-ArtifactRoot', (Quote-NativeArgument -Value $resolvedArtifactRoot),
        '-InitialDelaySeconds', [string]$InitialDelaySeconds,
        '-DeadmanDelaySeconds', [string]$DeadmanDelaySeconds,
        '-MaxConnectSeconds', [string]$MaxConnectSeconds,
        '-MaxModeSwitchSeconds', [string]$MaxModeSwitchSeconds
    )
    if ($RecoverInitialBaselineAfterDelay) {
        $arguments += '-RecoverInitialBaselineAfterDelay'
    }
    Write-LauncherStatus -Phase 'uac_requested'
    $elevated = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
        -ArgumentList $arguments -WindowStyle Hidden -PassThru
    Write-LauncherStatus -Phase 'runner_started' `
        -ElevatedProcessId $elevated.Id
} catch {
    Write-LauncherStatus -Phase 'launch_failed' -Failure $_.Exception.Message
    throw
}
