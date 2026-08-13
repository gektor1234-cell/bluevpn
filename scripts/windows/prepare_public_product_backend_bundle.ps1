[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{4,120}$')]
    [string]$ReleaseId = 'public-product-backend-fusion-production-20260813-r1',

    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$')]
    [string]$BackendVersion = '0.9.155-fusion-production-candidate.1',

    [string]$OutDir = 'C:\BlueVPN_Builds\fusion_production_backend_20260813'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outRoot = [IO.Path]::GetFullPath($OutDir)
$allowedRoot = [IO.Path]::GetFullPath('C:\BlueVPN_Builds').TrimEnd('\') + '\'
if (-not ($outRoot.TrimEnd('\') + '\').StartsWith(
        $allowedRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Unsafe backend bundle output path: $outRoot"
}

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
    'scripts\server\install_public_product_backend_release.sh'
)
foreach ($relative in $requiredSources) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $relative) -PathType Leaf)) {
        throw "Required source is missing: $relative"
    }
}

New-Item -ItemType Directory -Path `
    (Join-Path $stage 'backend\app'), (Join-Path $stage 'ops') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'backend_live\app\main.py') `
    -Destination (Join-Path $stage 'backend\app\main.py')
Copy-Item -LiteralPath (Join-Path $repo 'backend_live\requirements.txt') `
    -Destination (Join-Path $stage 'backend\requirements.txt')
foreach ($name in @(
    'greenvpn_db_sync_from_peer.sh',
    'greenvpn_sqlite_snapshot_stdout.py',
    'greenvpn_sqlite_state_sync.py',
    'greenvpn_prune_operational_history.py',
    'install_operational_retention_timer.sh'
)) {
    Copy-Item -LiteralPath (Join-Path $repo "scripts\ops\$name") `
        -Destination (Join-Path $stage "ops\$name")
}
Copy-Item -LiteralPath `
    (Join-Path $repo 'scripts\server\install_public_product_backend_release.sh') `
    -Destination (Join-Path $stage 'install.sh')

python -m py_compile `
    (Join-Path $stage 'backend\app\main.py') `
    (Join-Path $stage 'ops\greenvpn_sqlite_snapshot_stdout.py') `
    (Join-Path $stage 'ops\greenvpn_sqlite_state_sync.py') `
    (Join-Path $stage 'ops\greenvpn_prune_operational_history.py')
if ($LASTEXITCODE -ne 0) {
    throw 'Python validation failed for public-product backend bundle.'
}
Get-ChildItem -LiteralPath $stage -Directory -Filter '__pycache__' -Recurse |
    Remove-Item -Recurse -Force

$gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
$bash = if (Test-Path -LiteralPath $gitBash -PathType Leaf) {
    $gitBash
}
else {
    (Get-Command bash.exe -ErrorAction Stop).Source
}
foreach ($relative in @(
    'scripts/ops/greenvpn_db_sync_from_peer.sh',
    'scripts/ops/install_operational_retention_timer.sh',
    'scripts/server/install_public_product_backend_release.sh'
)) {
    & $bash -n (Join-Path $repo $relative)
    if ($LASTEXITCODE -ne 0) {
        throw "Shell validation failed: $relative"
    }
}

$head = (& git -C $repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or -not $head) {
    throw 'Unable to resolve source commit for backend bundle.'
}
$manifest = [ordered]@{
    schema = 1
    contour = 'public-product'
    releaseId = $ReleaseId
    backendVersion = $BackendVersion
    sourceCommit = $head
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    productionPublished = $false
    ownerApprovalRequired = $true
    changesClientArtifacts = $false
    changesSite = $false
    containsSecrets = $false
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
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText(
    (Join-Path $stage 'backend-release-manifest.json'),
    ($manifest | ConvertTo-Json -Depth 8) + "`n",
    $utf8
)

tar.exe -czf $archive -C $stage .
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to create public-product backend bundle archive.'
}

$archiveItem = Get-Item -LiteralPath $archive
[pscustomobject]@{
    success = $true
    contour = 'public-product'
    productionPublished = $false
    stage = $stage
    archive = $archive
    sizeBytes = $archiveItem.Length
    sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    backendVersion = $BackendVersion
    releaseId = $ReleaseId
    sourceCommit = $head
}
