[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{4,120}$')]
    [string]$ReleaseId = 'paid-beta-backend-active-active-20260713-r22',

    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$')]
    [string]$BackendVersion = '0.9.116-active-active.3',

    [string]$OutDir = 'C:\BlueVPN_Builds\paid_beta_backend_20260713'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outRoot = [System.IO.Path]::GetFullPath($OutDir)
$stage = Join-Path $outRoot $ReleaseId
$archive = Join-Path $outRoot "$ReleaseId.tar.gz"

if (Test-Path -LiteralPath $stage) {
    throw "Bundle stage already exists: $stage"
}
if (Test-Path -LiteralPath $archive) {
    throw "Bundle archive already exists: $archive"
}

$requiredSources = @(
    'backend_live\app\main.py',
    'backend_live\requirements.txt',
    'scripts\ops\greenvpn_db_sync_from_peer.sh',
    'scripts\ops\greenvpn_sqlite_snapshot_stdout.py',
    'scripts\ops\greenvpn_sqlite_state_sync.py',
    'scripts\ops\greenvpn_prune_operational_history.py',
    'scripts\ops\install_operational_retention_timer.sh',
    'scripts\server\install_paid_beta_backend_release.sh'
)
foreach ($relative in $requiredSources) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $relative) -PathType Leaf)) {
        throw "Required source is missing: $relative"
    }
}

New-Item -ItemType Directory -Path (Join-Path $stage 'backend\app'), (Join-Path $stage 'ops') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'backend_live\app\main.py') -Destination (Join-Path $stage 'backend\app\main.py')
Copy-Item -LiteralPath (Join-Path $repo 'backend_live\requirements.txt') -Destination (Join-Path $stage 'backend\requirements.txt')
foreach ($name in @(
    'greenvpn_db_sync_from_peer.sh',
    'greenvpn_sqlite_snapshot_stdout.py',
    'greenvpn_sqlite_state_sync.py',
    'greenvpn_prune_operational_history.py',
    'install_operational_retention_timer.sh'
)) {
    Copy-Item -LiteralPath (Join-Path $repo "scripts\ops\$name") -Destination (Join-Path $stage "ops\$name")
}
Copy-Item -LiteralPath (Join-Path $repo 'scripts\server\install_paid_beta_backend_release.sh') -Destination (Join-Path $stage 'install.sh')

python -m py_compile `
    (Join-Path $stage 'backend\app\main.py') `
    (Join-Path $stage 'ops\greenvpn_sqlite_snapshot_stdout.py') `
    (Join-Path $stage 'ops\greenvpn_sqlite_state_sync.py') `
    (Join-Path $stage 'ops\greenvpn_prune_operational_history.py')
if ($LASTEXITCODE -ne 0) {
    throw 'Python validation failed for backend-only bundle.'
}
Get-ChildItem -LiteralPath $stage -Directory -Filter '__pycache__' -Recurse |
    Remove-Item -Recurse -Force
Push-Location $repo
try {
    $gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
    $bash = if (Test-Path -LiteralPath $gitBash -PathType Leaf) {
        $gitBash
    }
    else {
        (Get-Command bash.exe -ErrorAction Stop).Source
    }
    & $bash -n scripts/ops/greenvpn_db_sync_from_peer.sh
    if ($LASTEXITCODE -ne 0) {
        throw 'DB sync shell validation failed for backend-only bundle.'
    }
    & $bash -n scripts/ops/install_operational_retention_timer.sh
    if ($LASTEXITCODE -ne 0) {
        throw 'Retention installer shell validation failed for backend-only bundle.'
    }
    & $bash -n scripts/server/install_paid_beta_backend_release.sh
    if ($LASTEXITCODE -ne 0) {
        throw 'Installer shell validation failed for backend-only bundle.'
    }
}
finally {
    Pop-Location
}

$manifest = [ordered]@{
    schema = 1
    contour = 'paid-beta'
    releaseId = $ReleaseId
    backendVersion = $BackendVersion
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    changesClientArtifacts = $false
    changesSite = $false
    files = @(
        Get-ChildItem -LiteralPath $stage -File -Recurse |
            Sort-Object FullName |
            ForEach-Object {
                [ordered]@{
                    path = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
                    size = $_.Length
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                }
            }
    )
}
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
    (Join-Path $stage 'backend-release-manifest.json'),
    ($manifest | ConvertTo-Json -Depth 8) + "`n",
    $utf8
)

tar.exe -czf $archive -C $stage .
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to create backend-only bundle archive.'
}

$archiveItem = Get-Item -LiteralPath $archive
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
Write-Output 'bundle_status=ok'
Write-Output "bundle_stage=$stage"
Write-Output "bundle_archive=$archive"
Write-Output "bundle_size=$($archiveItem.Length)"
Write-Output "bundle_sha256=$archiveHash"
Write-Output 'client_artifacts_changed=false'
Write-Output 'site_changed=false'
