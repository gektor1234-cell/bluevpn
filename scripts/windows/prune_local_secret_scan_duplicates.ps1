[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$SecretRoot = 'D:\GreenVPN_Secrets'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedRoot = [System.IO.Path]::GetFullPath('D:\GreenVPN_Secrets')
$ActualRoot = [System.IO.Path]::GetFullPath($SecretRoot)
if ($ActualRoot -ne $ExpectedRoot) {
    throw "Secret-root guard failed: $ActualRoot"
}
if (-not (Test-Path -LiteralPath $ActualRoot -PathType Container)) {
    throw 'Secret root is missing.'
}
$rootItem = Get-Item -LiteralPath $ActualRoot -Force
if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'Secret root must not be a reparse point.'
}

$RequiredInventories = @(
    'secret_inventory_redacted_20260612_192213.csv',
    'timeweb_inventory_redacted_20260612_192305.csv',
    'named_secret_inventory_REDACTED_20260612_current.csv',
    'secret_file_inventory_REDACTED_20260612_current.csv',
    'ACCESS_STATUS_REDACTED.md'
)
$DeleteNames = @(
    'raw_secret_marker_hits_FULL_20260612_193337.txt',
    'codex_session_secret_hits_FULL_20260612_193609.txt',
    'timeweb_codex_hits_FULL_20260612_193848.txt',
    'provider_secret_candidates_FULL_20260612_194728.json'
)

foreach ($name in $RequiredInventories) {
    $path = Join-Path $ActualRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required redacted inventory is missing: $name"
    }
}

$deleteItems = foreach ($name in $DeleteNames) {
    $path = [System.IO.Path]::GetFullPath((Join-Path $ActualRoot $name))
    if ((Split-Path -Parent $path) -ne $ActualRoot) {
        throw "Cleanup path guard failed: $path"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Expected generated duplicate is missing: $name"
    }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Cleanup reparse point refused: $name"
    }
    $item
}

$beforeBytes = ($deleteItems | Measure-Object -Property Length -Sum).Sum
Write-Output "secret_duplicate_prune_apply=$($Apply.IsPresent.ToString().ToLowerInvariant())"
Write-Output "secret_duplicate_prune_files=$($deleteItems.Count)"
Write-Output "secret_duplicate_prune_bytes=$beforeBytes"
if (-not $Apply) {
    return
}

foreach ($item in $deleteItems) {
    Remove-Item -LiteralPath $item.FullName -Force
}
foreach ($name in $DeleteNames) {
    if (Test-Path -LiteralPath (Join-Path $ActualRoot $name)) {
        throw "Generated duplicate still exists after cleanup: $name"
    }
}

Write-Output 'secret_duplicate_prune_status=applied'
Write-Output "secret_duplicate_prune_freed_bytes=$beforeBytes"
