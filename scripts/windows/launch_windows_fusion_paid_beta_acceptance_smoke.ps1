[CmdletBinding()]
param(
    [string]$RunnerPath = '',
    [string]$InstallerPath = 'C:\BlueVPN_Builds\paid_beta_20260813_fusion_acl_fix_v1_0.4.6\GreenVPN_Beta_Setup_0.4.6-paid-beta.2.exe',
    [string]$ArtifactRoot = 'C:\BlueVPN_Builds\fusion_windows_acceptance_20260813_physical_v4_b4602',
    [string]$LauncherStatusPath = 'C:\BlueVPN_Builds\fusion_windows_acceptance_20260813_physical_v4_b4602\windows-fusion-paid-beta-launcher-status.json',
    [ValidateRange(90, 600)]
    [int]$InitialDelaySeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$resolvedRunner = if ([string]::IsNullOrWhiteSpace($RunnerPath)) {
    Join-Path $repoRoot 'scripts\windows\run_windows_fusion_paid_beta_acceptance_smoke.ps1'
} else {
    [IO.Path]::GetFullPath($RunnerPath)
}
$resolvedInstaller = [IO.Path]::GetFullPath($InstallerPath)
$resolvedArtifactRoot = [IO.Path]::GetFullPath($ArtifactRoot)
$resolvedStatusPath = [IO.Path]::GetFullPath($LauncherStatusPath)

New-Item -ItemType Directory -Force -Path $resolvedArtifactRoot | Out-Null

function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Phase,
        [int]$ElevatedProcessId = 0,
        [string]$Failure = ''
    )
    [ordered]@{
        schemaVersion = 1
        updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        phase = $Phase
        runnerPath = $resolvedRunner
        installerPath = $resolvedInstaller
        artifactRoot = $resolvedArtifactRoot
        initialDelaySeconds = $InitialDelaySeconds
        elevatedProcessId = $ElevatedProcessId
        failure = $Failure
    } | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $resolvedStatusPath -Encoding UTF8
}

try {
    foreach ($required in @($resolvedRunner, $resolvedInstaller)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required file is missing: $required"
        }
    }
    $existing = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                [string]$_.CommandLine -match
                    'run_windows_fusion_paid_beta_acceptance_smoke\.ps1'
            }
    )
    if ($existing.Count -gt 0) {
        throw 'A Fusion paid-beta acceptance runner is already active.'
    }
    Write-Status -Phase 'uac_requested'
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', "`"$resolvedRunner`"",
        '-InstallerPath', "`"$resolvedInstaller`"",
        '-ArtifactRoot', "`"$resolvedArtifactRoot`"",
        '-InitialDelaySeconds', [string]$InitialDelaySeconds
    )
    $runner = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
        -WindowStyle Hidden -ArgumentList $arguments -PassThru
    Write-Status -Phase 'runner_started' -ElevatedProcessId $runner.Id
} catch {
    Write-Status -Phase 'launch_failed' -Failure $_.Exception.Message
    throw
}
