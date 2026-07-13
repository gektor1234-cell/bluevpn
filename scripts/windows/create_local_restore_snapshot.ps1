[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9._-]{1,80}$')]
    [string]$Label,

    [Parameter(Mandatory = $true)]
    [string]$CheckpointRoot,

    [string]$ProjectRoot = 'C:\Users\gekto\projects\bluevpn',
    [string]$SecretRoot = 'D:\GreenVPN_Secrets',
    [string]$SshRoot = 'C:\Users\gekto\.ssh'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExcludedGeneratedSecretDuplicates = @(
    'raw_secret_marker_hits_FULL_20260612_193337.txt',
    'codex_session_secret_hits_FULL_20260612_193609.txt',
    'timeweb_codex_hits_FULL_20260612_193848.txt',
    'provider_secret_candidates_FULL_20260612_194728.json'
)

function Resolve-ContainedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    if (-not $resolvedPath.StartsWith($resolvedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe path outside expected parent: $resolvedPath"
    }
    return $resolvedPath
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $FilePath"
    }
}

function Copy-SafeTree {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [string[]]$ExcludedRelativePaths = @()
    )

    $source = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Required source directory is missing: $source"
    }
    $excluded = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($entry in $ExcludedRelativePaths) {
        [void]$excluded.Add($entry.Replace('/', '\').TrimStart('\'))
    }

    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    $copiedFiles = 0
    foreach ($item in Get-ChildItem -LiteralPath $source -Force -Recurse | Sort-Object FullName) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse point refused while building checkpoint: $($item.FullName)"
        }
        $relative = $item.FullName.Substring($source.Length).TrimStart('\')
        if ($excluded.Contains($relative)) {
            continue
        }
        $destination = Resolve-ContainedPath -Path (Join-Path $DestinationRoot $relative) -Parent $DestinationRoot
        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
        }
        else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
            $copiedFiles++
        }
    }
    return $copiedFiles
}

$checkpointParent = [System.IO.Path]::GetFullPath('C:\Users\gekto\GreenVPN_Checkpoints')
$checkpoint = Resolve-ContainedPath -Path $CheckpointRoot -Parent $checkpointParent
$project = [System.IO.Path]::GetFullPath($ProjectRoot)
$secretStore = [System.IO.Path]::GetFullPath($SecretRoot)
$localRoot = Resolve-ContainedPath -Path (Join-Path $checkpoint 'local_state') -Parent $checkpoint
$plainRoot = Resolve-ContainedPath -Path (Join-Path $localRoot 'plaintext') -Parent $localRoot
$encryptedArchive = Resolve-ContainedPath -Path (Join-Path $localRoot 'local_state.7z') -Parent $localRoot
$manifestPath = Resolve-ContainedPath -Path (Join-Path $localRoot 'encrypted_manifest.json') -Parent $localRoot
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$passwordPath = Join-Path $secretStore 'full_checkpoint_archive_password.txt'

foreach ($requiredDirectory in @($checkpoint, $project, $secretStore, $SshRoot)) {
    if (-not (Test-Path -LiteralPath $requiredDirectory -PathType Container)) {
        throw "Required directory is missing: $requiredDirectory"
    }
}
foreach ($requiredFile in @($sevenZip, $passwordPath)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file is missing: $requiredFile"
    }
}
if (Test-Path -LiteralPath $localRoot) {
    throw "Local-state checkpoint already exists: $localRoot"
}

New-Item -ItemType Directory -Path $plainRoot -Force | Out-Null
$snapshotSucceeded = $false
try {
$repositoryRoot = Join-Path $plainRoot 'repository'
$untrackedRoot = Join-Path $repositoryRoot 'untracked'
$secretsRoot = Join-Path $plainRoot 'secrets'
$sshDestination = Join-Path $plainRoot 'ssh'
$signingRoot = Join-Path $plainRoot 'android_signing'
New-Item -ItemType Directory -Path $repositoryRoot, $untrackedRoot, $secretsRoot, $sshDestination, $signingRoot -Force | Out-Null

Push-Location $project
try {
    $actualRepositoryRoot = (& git rev-parse --show-toplevel).Trim()
    if ($LASTEXITCODE -ne 0 -or [System.IO.Path]::GetFullPath($actualRepositoryRoot) -ne $project) {
        throw 'ProjectRoot is not the expected Git repository root.'
    }

    $patchPath = Join-Path $repositoryRoot 'working_tree.patch'
    Invoke-Checked -FilePath 'git.exe' -ArgumentList @(
        'diff', '--binary', '--full-index', "--output=$patchPath", 'HEAD', '--'
    )
    (& git status --short --branch) | Set-Content -LiteralPath (Join-Path $repositoryRoot 'git_status.txt') -Encoding utf8
    (& git rev-parse HEAD) | Set-Content -LiteralPath (Join-Path $repositoryRoot 'git_head.txt') -Encoding ascii
    (& git remote -v) | Set-Content -LiteralPath (Join-Path $repositoryRoot 'git_remotes.txt') -Encoding utf8

    $untrackedPaths = @(& git ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate untracked files.'
    }
    foreach ($relative in $untrackedPaths) {
        if ([string]::IsNullOrWhiteSpace($relative)) {
            continue
        }
        $source = Resolve-ContainedPath -Path (Join-Path $project $relative) -Parent $project
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Untracked path is not a regular file: $relative"
        }
        $item = Get-Item -LiteralPath $source -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Untracked reparse point refused: $relative"
        }
        $destination = Resolve-ContainedPath -Path (Join-Path $untrackedRoot $relative) -Parent $untrackedRoot
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    $untrackedPaths | Set-Content -LiteralPath (Join-Path $repositoryRoot 'untracked_files.txt') -Encoding utf8
}
finally {
    Pop-Location
}

$secretFileCount = Copy-SafeTree `
    -SourceRoot $secretStore `
    -DestinationRoot $secretsRoot `
    -ExcludedRelativePaths $ExcludedGeneratedSecretDuplicates
$sshFileCount = Copy-SafeTree -SourceRoot $SshRoot -DestinationRoot $sshDestination

$excludedInventory = foreach ($name in $ExcludedGeneratedSecretDuplicates) {
    $path = Resolve-ContainedPath -Path (Join-Path $secretStore $name) -Parent $secretStore
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [ordered]@{ name = $name; present = $false; size = 0 }
        continue
    }
    $item = Get-Item -LiteralPath $path
    [ordered]@{ name = $name; present = $true; size = $item.Length }
}
$excludedInventory | ConvertTo-Json -Depth 3 | Set-Content `
    -LiteralPath (Join-Path $plainRoot 'excluded_generated_sensitive_duplicates.json') `
    -Encoding utf8

$keyProperties = Join-Path $project 'android\key.properties'
if (-not (Test-Path -LiteralPath $keyProperties -PathType Leaf)) {
    throw 'Android release key.properties is missing.'
}
$properties = @{}
foreach ($line in Get-Content -LiteralPath $keyProperties) {
    if ($line -match '^([^#=]+)=(.*)$') {
        $properties[$matches[1].Trim()] = $matches[2].Trim()
    }
}
foreach ($requiredKey in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
    if (-not $properties.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace($properties[$requiredKey])) {
        throw "Android signing property is missing: $requiredKey"
    }
}
$storeFile = $properties['storeFile']
if (-not [System.IO.Path]::IsPathRooted($storeFile)) {
    $storeFile = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $keyProperties) $storeFile))
}
if (-not (Test-Path -LiteralPath $storeFile -PathType Leaf)) {
    throw 'Android release keystore is missing.'
}
Copy-Item -LiteralPath $keyProperties -Destination (Join-Path $signingRoot 'key.properties') -Force
Copy-Item -LiteralPath $storeFile -Destination (Join-Path $signingRoot (Split-Path -Leaf $storeFile)) -Force
@{
    originalKeyProperties = $keyProperties
    originalStoreFile = $storeFile
    signerPinFile = 'android/release_signer_sha256.txt'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $signingRoot 'restore_metadata.json') -Encoding utf8

$password = [System.IO.File]::ReadAllText($passwordPath, [System.Text.Encoding]::UTF8).Trim()
if ($password.Length -lt 40) {
    throw 'Checkpoint password is unexpectedly short.'
}

Invoke-Checked -FilePath $sevenZip -ArgumentList @(
    'a', '-t7z', '-mx=7', '-mhe=on', '-bb0', "-p$password", $encryptedArchive,
    (Join-Path $plainRoot '*')
)
Invoke-Checked -FilePath $sevenZip -ArgumentList @('t', '-bb0', "-p$password", $encryptedArchive)

$archiveHash = (Get-FileHash -LiteralPath $encryptedArchive -Algorithm SHA256).Hash
$archiveSize = (Get-Item -LiteralPath $encryptedArchive).Length
@{
    schema = 1
    label = $Label
    createdUtc = [DateTime]::UtcNow.ToString('o')
    archive = [System.IO.Path]::GetFileName($encryptedArchive)
    sha256 = $archiveHash
    size = $archiveSize
    repositoryHead = (& git -C $project rev-parse HEAD).Trim()
    untrackedFiles = @($untrackedPaths).Count
    secretFiles = $secretFileCount
    sshFiles = $sshFileCount
    excludedGeneratedSensitiveDuplicates = $ExcludedGeneratedSecretDuplicates
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8

$verifiedPlainRoot = Resolve-ContainedPath -Path $plainRoot -Parent $localRoot
Remove-Item -LiteralPath $verifiedPlainRoot -Recurse -Force
$snapshotSucceeded = $true
}
finally {
    if (Test-Path -LiteralPath $plainRoot -PathType Container) {
        Remove-Item -LiteralPath $plainRoot -Recurse -Force
    }
    if (-not $snapshotSucceeded) {
        if (Test-Path -LiteralPath $encryptedArchive -PathType Leaf) {
            Remove-Item -LiteralPath $encryptedArchive -Force
        }
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            Remove-Item -LiteralPath $manifestPath -Force
        }
    }
}

Write-Output 'local_checkpoint_status=ok'
Write-Output "local_checkpoint_archive=$encryptedArchive"
Write-Output "local_checkpoint_sha256=$archiveHash"
Write-Output "local_checkpoint_size=$archiveSize"
