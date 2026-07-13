[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9._-]{1,80}$')]
    [string]$Label,

    [Parameter(Mandatory = $true)]
    [string]$CheckpointRoot,

    [string[]]$Hosts = @(
        '72.56.32.197',
        '176.113.81.35',
        '88.218.250.86',
        '37.220.85.211',
        '5.129.216.42'
    ),

    [string]$SecretRoot = 'D:\GreenVPN_Secrets'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

function Set-RestrictedCheckpointAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Invoke-Checked -FilePath 'icacls.exe' -ArgumentList @(
        $Path, '/reset', '/T', '/C', '/Q'
    )
    Invoke-Checked -FilePath 'icacls.exe' -ArgumentList @(
        $Path,
        '/inheritance:r',
        '/grant:r',
        "*$currentSid`:(OI)(CI)F",
        '*S-1-5-18:(OI)(CI)F',
        '*S-1-5-32-544:(OI)(CI)F',
        '/Q'
    )
}

$checkpointParent = [System.IO.Path]::GetFullPath('C:\Users\gekto\GreenVPN_Checkpoints')
$checkpoint = Resolve-ContainedPath -Path $CheckpointRoot -Parent $checkpointParent
$serverPlainRoot = Resolve-ContainedPath -Path (Join-Path $checkpoint 'server_archives\plaintext') -Parent $checkpoint
$encryptedArchive = Resolve-ContainedPath -Path (Join-Path $checkpoint 'server_archives\server_state.7z') -Parent $checkpoint
$scriptPath = Resolve-Path (Join-Path $PSScriptRoot '..\server\create_full_restore_snapshot.sh')
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$passwordPath = Join-Path $SecretRoot 'full_checkpoint_archive_password.txt'
$dpapiPath = Resolve-ContainedPath -Path (Join-Path $checkpoint 'server_archives\server_state_password.dpapi') -Parent $checkpoint

if (-not (Test-Path -LiteralPath $checkpoint -PathType Container)) {
    throw "Checkpoint directory does not exist: $checkpoint"
}
if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
    throw "7-Zip is not installed at $sevenZip"
}
if (-not (Test-Path -LiteralPath $SecretRoot -PathType Container)) {
    throw "Secret root does not exist: $SecretRoot"
}

Set-RestrictedCheckpointAcl -Path $checkpoint
New-Item -ItemType Directory -Path $serverPlainRoot -Force | Out-Null

if (-not (Test-Path -LiteralPath $passwordPath -PathType Leaf)) {
    $randomBytes = [byte[]]::new(48)
    $randomGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $randomGenerator.GetBytes($randomBytes)
    }
    finally {
        $randomGenerator.Dispose()
    }
    $password = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    [System.IO.File]::WriteAllText($passwordPath, $password, [System.Text.UTF8Encoding]::new($false))
}
$password = [System.IO.File]::ReadAllText($passwordPath, [System.Text.Encoding]::UTF8).Trim()
if ($password.Length -lt 40) {
    throw 'Checkpoint password is unexpectedly short.'
}

Add-Type -AssemblyName System.Security
$protectedPassword = [System.Security.Cryptography.ProtectedData]::Protect(
    [System.Text.Encoding]::UTF8.GetBytes($password),
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)
[System.IO.File]::WriteAllBytes($dpapiPath, $protectedPassword)

$manifest = [ordered]@{
    schema = 1
    label = $Label
    createdUtc = [DateTime]::UtcNow.ToString('o')
    repositoryHead = (git rev-parse HEAD).Trim()
    hosts = @()
}

foreach ($ip in $Hosts) {
    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        throw "Invalid host address: $ip"
    }

    $remoteScript = "/root/create_full_restore_snapshot-$Label.sh"
    $remoteArchive = "/root/greenvpn-full-restore-$Label.tar.gz"
    $localArchive = Join-Path $serverPlainRoot ("{0}.tar.gz" -f $ip.Replace('.', '_'))

    Invoke-Checked -FilePath 'scp.exe' -ArgumentList @(
        '-O', '-q', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10',
        $scriptPath.Path, "root@${ip}:$remoteScript"
    )
    Invoke-Checked -FilePath 'ssh.exe' -ArgumentList @(
        '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', "root@$ip",
        "chmod 700 '$remoteScript' && '$remoteScript' --label '$Label' --output '$remoteArchive'"
    )
    Invoke-Checked -FilePath 'scp.exe' -ArgumentList @(
        '-O', '-q', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10',
        "root@${ip}:$remoteArchive", $localArchive
    )
    Invoke-Checked -FilePath 'ssh.exe' -ArgumentList @(
        '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', "root@$ip",
        "rm -f -- '$remoteArchive' '$remoteScript'"
    )

    $manifest.hosts += [ordered]@{
        ip = $ip
        archive = [System.IO.Path]::GetFileName($localArchive)
        size = (Get-Item -LiteralPath $localArchive).Length
        sha256 = (Get-FileHash -LiteralPath $localArchive -Algorithm SHA256).Hash
    }
}

$manifestPath = Join-Path $serverPlainRoot 'manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

if (Test-Path -LiteralPath $encryptedArchive) {
    throw "Encrypted archive already exists: $encryptedArchive"
}
Invoke-Checked -FilePath $sevenZip -ArgumentList @(
    'a', '-t7z', '-mx=7', '-mhe=on', "-p$password", $encryptedArchive,
    (Join-Path $serverPlainRoot '*')
)
Invoke-Checked -FilePath $sevenZip -ArgumentList @('t', "-p$password", $encryptedArchive)

$encryptedHash = (Get-FileHash -LiteralPath $encryptedArchive -Algorithm SHA256).Hash
$encryptedSize = (Get-Item -LiteralPath $encryptedArchive).Length
@{
    archive = [System.IO.Path]::GetFileName($encryptedArchive)
    sha256 = $encryptedHash
    size = $encryptedSize
    passwordFile = $passwordPath
    dpapiRecoveryFile = [System.IO.Path]::GetFileName($dpapiPath)
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $checkpoint 'server_archives\encrypted_manifest.json') -Encoding utf8

$verifiedPlainRoot = Resolve-ContainedPath -Path $serverPlainRoot -Parent $checkpoint
if (Test-Path -LiteralPath $verifiedPlainRoot -PathType Container) {
    Remove-Item -LiteralPath $verifiedPlainRoot -Recurse -Force
}

$localSnapshotScript = Resolve-Path (Join-Path $PSScriptRoot 'create_local_restore_snapshot.ps1')
Invoke-Checked -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $localSnapshotScript.Path,
    '-Label', $Label,
    '-CheckpointRoot', $checkpoint,
    '-ProjectRoot', (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    '-SecretRoot', $SecretRoot
)

Write-Output "checkpoint_status=ok"
Write-Output "encrypted_archive=$encryptedArchive"
Write-Output "encrypted_sha256=$encryptedHash"
Write-Output "encrypted_size=$encryptedSize"
