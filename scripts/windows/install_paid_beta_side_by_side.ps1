param(
    [string]$PayloadZip = "",
    [string]$InstallDir = "$env:ProgramFiles\Green VPN Beta",
    [string]$OwnerSid = "",
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serviceName = 'GreenVPNBetaService'
$tunnelName = 'GreenVPNBeta'
$tunnelServiceName = 'WireGuardTunnel$GreenVPNBeta'
$programDataRoot = Join-Path $env:ProgramData 'BlueVPNBeta'
$processName = 'greenvpn_beta'
$productVersion = '__GREENVPN_APP_VERSION__'
$installErrorLog = Join-Path $env:TEMP 'GreenVPN_Beta_Setup_error.log'
Remove-Item -LiteralPath $installErrorLog -Force -ErrorAction SilentlyContinue

try {
    Start-Transcript -Path (Join-Path $env:TEMP 'GreenVPN_Beta_Setup.log') -Append -Force | Out-Null
} catch {}

function Write-Step {
    param([string]$Text)
    Write-Host "[Green VPN Beta] $Text"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-InstallingUserSid {
    param([string]$CandidateSid)

    $value = $CandidateSid.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    }
    try {
        $sid = [Security.Principal.SecurityIdentifier]::new($value)
    } catch {
        throw "Invalid Windows account SID supplied to the beta installer."
    }
    if (-not $sid.IsAccountSid() -or $sid.Value -in @(
        'S-1-1-0',
        'S-1-5-11',
        'S-1-5-18',
        'S-1-5-32-544',
        'S-1-5-32-545'
    )) {
        throw "The beta installer owner must be an individual Windows account."
    }
    return $sid.Value
}

function Remove-CallerLegacyInstall {
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'GreenVPNBeta' -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Green VPN Beta.lnk') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('Programs')) 'Green VPN Beta') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'Programs\Green VPN Beta') -Recurse -Force -ErrorAction SilentlyContinue
}

function Resolve-WireGuardExe {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe'),
        'C:\Program Files\WireGuard\wireguard.exe',
        'C:\Program Files (x86)\WireGuard\wireguard.exe'
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return ''
}

function Stop-BetaTunnel {
    try { & sc.exe stop $tunnelServiceName 2>$null | Out-Null } catch {}
    Start-Sleep -Milliseconds 500
    $wireGuard = Resolve-WireGuardExe
    if (-not [string]::IsNullOrWhiteSpace($wireGuard)) {
        try { & $wireGuard /uninstalltunnelservice $tunnelName | Out-Null } catch {}
    }
    try { & sc.exe delete $tunnelServiceName 2>$null | Out-Null } catch {}
}

function Remove-BetaService {
    try { & sc.exe stop $serviceName | Out-Null } catch {}
    for ($i = 0; $i -lt 20; $i++) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
        if ($null -eq $service -or $service.State -ne 'Running') { break }
        Start-Sleep -Milliseconds 250
    }
    try { & sc.exe delete $serviceName | Out-Null } catch {}
    for ($i = 0; $i -lt 20; $i++) {
        if ($null -eq (Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue)) {
            return
        }
        Start-Sleep -Milliseconds 250
    }
    throw "Could not remove existing beta service: $serviceName"
}

function Ensure-BetaProgramData {
    param([Parameter(Mandatory=$true)][string]$UserSid)

    New-Item -ItemType Directory -Force -Path $programDataRoot | Out-Null
    attrib -H -S -R $programDataRoot 2>$null | Out-Null
    & takeown.exe /F $programDataRoot /A /R /D Y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to take ownership of existing Green VPN Beta state.' }
    & icacls.exe $programDataRoot /grant:r `
        ('*' + $UserSid + ':(OI)(CI)M') `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to seed protected Green VPN Beta state ACLs.' }
    & icacls.exe $programDataRoot /inheritance:r | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to disable inherited Green VPN Beta state ACLs.' }
    & icacls.exe $programDataRoot /remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to remove broad Green VPN Beta state access.' }
    & icacls.exe $programDataRoot /grant:r `
        ('*' + $UserSid + ':(OI)(CI)M') `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to apply protected Green VPN Beta state ACLs.' }
    if (Get-ChildItem -LiteralPath $programDataRoot -Force -ErrorAction SilentlyContinue) {
        & icacls.exe (Join-Path $programDataRoot '*') /reset /T /C | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Failed to restore inherited Green VPN Beta child state ACLs.' }
    }
    & icacls.exe $programDataRoot /setowner ('*' + $UserSid) /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to bind Green VPN Beta state to the installing Windows account.' }

    $tokenPath = Join-Path $programDataRoot 'service_token'
    $token = ''
    if (Test-Path -LiteralPath $tokenPath) {
        try { $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim() } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($token) -or $token.Length -lt 24) {
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $bytes = New-Object byte[] 32
            $rng.GetBytes($bytes)
            [Convert]::ToBase64String($bytes) | Set-Content -LiteralPath $tokenPath -NoNewline -Encoding ASCII
        } finally {
            $rng.Dispose()
        }
    }
    attrib +H $tokenPath 2>$null | Out-Null
    & icacls.exe $tokenPath /inheritance:r /remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to remove broad Green VPN Beta service token access.' }
    & icacls.exe $tokenPath /grant:r `
        '*S-1-5-18:F' `
        '*S-1-5-32-544:F' `
        ('*' + $UserSid + ':R') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to protect the Green VPN Beta service token.' }
}

function Install-BetaService {
    param(
        [Parameter(Mandatory=$true)][string]$ServiceExe,
        [Parameter(Mandatory=$true)][string]$TaskScript
    )

    if (-not (Test-Path -LiteralPath $ServiceExe)) {
        throw "Beta service executable not found: $ServiceExe"
    }
    if (-not (Test-Path -LiteralPath $TaskScript)) {
        throw "Beta VPN task script not found: $TaskScript"
    }

    Remove-BetaService
    $binaryPath = '"' + $ServiceExe + '" --task-script "' + $TaskScript + '"'
    New-Service -Name $serviceName -BinaryPathName $binaryPath -DisplayName 'Green VPN Beta Service' -StartupType Automatic | Out-Null
    & sc.exe description $serviceName 'Green VPN isolated paid beta local service.' | Out-Null
    & sc.exe start $serviceName | Out-Null

    for ($i = 0; $i -lt 30; $i++) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
        if ($null -ne $service -and $service.State -eq 'Running') { return }
        Start-Sleep -Milliseconds 300
    }
    throw 'Green VPN Beta service did not reach Running state.'
}

function Test-BetaInstalledRoot {
    param([Parameter(Mandatory=$true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $false
    }
    foreach ($requiredPath in @(
        (Join-Path $Root 'greenvpn_beta.exe'),
        (Join-Path $Root 'greenvpn_beta_service.exe'),
        (Join-Path $Root 'tools\greenvpn_vpn_task.ps1'),
        (Join-Path $Root 'uninstall_greenvpn_beta.cmd')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            return $false
        }
    }
    return Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN Beta'
}

function Remove-CorruptInstallRoot {
    param([Parameter(Mandatory=$true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) { return }

    & takeown.exe /F $Root /A /R /D Y | Out-Null
    & icacls.exe $Root /inheritance:e /grant:r `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' /T /C /Q | Out-Null
    & icacls.exe $Root /reset /T /C /Q | Out-Null
    Remove-Item -LiteralPath $Root -Recurse -Force
    if (Test-Path -LiteralPath $Root) {
        throw "Failed to remove an incomplete Green VPN Beta installation: $Root"
    }
}

function Move-DirectoryWithRetry {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [int]$Attempts = 30
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            Move-Item -LiteralPath $Source -Destination $Destination -Force
            return
        } catch {
            $lastError = $_
            if ($attempt -lt $Attempts) {
                Get-Process -Name 'greenvpn_beta' -ErrorAction SilentlyContinue |
                    Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
            }
        }
    }
    throw $lastError
}

function Test-FileAclAllows {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Sid,
        [Parameter(Mandatory=$true)][Security.AccessControl.FileSystemRights]$RequiredRights
    )

    $securityIdentifier = [Security.Principal.SecurityIdentifier]::new($Sid)
    $rules = (Get-Acl -LiteralPath $Path).GetAccessRules(
        $true,
        $true,
        [Security.Principal.SecurityIdentifier]
    )
    $allowed = [Security.AccessControl.FileSystemRights]0
    foreach ($rule in $rules) {
        if ($rule.IdentityReference.Value -ne $securityIdentifier.Value) { continue }
        if (
            $rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Deny -and
            (($rule.FileSystemRights -band $RequiredRights) -ne 0)
        ) {
            return $false
        }
        if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow) {
            $allowed = $allowed -bor $rule.FileSystemRights
        }
    }
    return (($allowed -band $RequiredRights) -eq $RequiredRights)
}

if ([string]::IsNullOrWhiteSpace($PayloadZip)) {
    $PayloadZip = Join-Path $PSScriptRoot 'GreenVPN_payload.zip'
}
if (-not (Test-Path -LiteralPath $PayloadZip)) {
    throw "Payload zip not found: $PayloadZip"
}

if (-not (Test-IsAdministrator)) {
    $launchAfterInstall = -not $NoLaunch -and
        $env:GREENVPN_INSTALLER_SKIP_APP_LAUNCH -ne '1'
    $callerSid = Resolve-InstallingUserSid -CandidateSid $OwnerSid
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $PSCommandPath + '"'),
        '-PayloadZip', ('"' + $PayloadZip + '"'),
        '-InstallDir', ('"' + $InstallDir + '"'),
        '-OwnerSid', ('"' + $callerSid + '"'),
        '-NoLaunch'
    )
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList $arguments
    if ($process.ExitCode -eq 0) {
        Remove-CallerLegacyInstall
        if ($launchAfterInstall) {
            $installedExe = Join-Path ([System.IO.Path]::GetFullPath($InstallDir)) 'greenvpn_beta.exe'
            if (-not (Test-Path -LiteralPath $installedExe)) {
                throw "Green VPN Beta installation succeeded but the application is missing: $installedExe"
            }
            Start-Process -FilePath $installedExe -WorkingDirectory (Split-Path -Parent $installedExe)
        }
    }
    exit $process.ExitCode
}

$installingUserSid = Resolve-InstallingUserSid -CandidateSid $OwnerSid
$installRoot = [System.IO.Path]::GetFullPath($InstallDir)
$allowedRoot = [System.IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\') + '\'
if (-not (($installRoot.TrimEnd('\') + '\').StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
    throw "InstallDir must stay under $allowedRoot"
}
$tempRoot = Join-Path $env:TEMP ("GreenVPNBetaInstall_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$swapId = [guid]::NewGuid().ToString('N')
$stagingRoot = "$installRoot.staging-$swapId"
$backupRoot = "$installRoot.backup-$swapId"
$installSwapped = $false
$installCompleted = $false
$runtimeStopped = $false
$existingRootBackedUp = $false
$existingInstallValid = Test-BetaInstalledRoot -Root $installRoot
$legacyInstallRoot = Join-Path $env:LOCALAPPDATA 'Programs\Green VPN Beta'
$legacyInstallValid = (
    (Test-Path -LiteralPath (Join-Path $legacyInstallRoot 'greenvpn_beta.exe') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $legacyInstallRoot 'greenvpn_beta_service.exe') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $legacyInstallRoot 'tools\greenvpn_vpn_task.ps1') -PathType Leaf)
)
$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$uninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN Beta'
$previousUninstallValues = @{}
$previousRunValue = $null
if ($existingInstallValid) {
    $existingUninstall = Get-ItemProperty -LiteralPath $uninstallKey -ErrorAction SilentlyContinue
    foreach ($name in @(
        'DisplayName', 'DisplayVersion', 'DisplayIcon', 'Publisher', 'InstallLocation',
        'UninstallString', 'QuietUninstallString', 'URLInfoAbout', 'InstallDate',
        'EstimatedSize', 'NoModify', 'NoRepair'
    )) {
        if ($null -ne $existingUninstall -and $null -ne $existingUninstall.$name) {
            $previousUninstallValues[$name] = $existingUninstall.$name
        }
    }
    $existingRun = Get-ItemProperty -LiteralPath $runKey -Name 'GreenVPNBeta' -ErrorAction SilentlyContinue
    if ($null -ne $existingRun -and $null -ne $existingRun.PSObject.Properties['GreenVPNBeta']) {
        $previousRunValue = [string]$existingRun.GreenVPNBeta
    }
}

try {
    Write-Step 'Extracting beta package...'
    Expand-Archive -LiteralPath $PayloadZip -DestinationPath $tempRoot -Force
    $appSource = Join-Path $tempRoot 'app'
    foreach ($requiredSource in @(
        (Join-Path $appSource 'greenvpn_beta.exe'),
        (Join-Path $appSource 'greenvpn_beta_service.exe'),
        (Join-Path $tempRoot 'tools\greenvpn_vpn_task.ps1'),
        (Join-Path $tempRoot 'tools\uninstall_greenvpn_beta.ps1')
    )) {
        if (-not (Test-Path -LiteralPath $requiredSource)) {
            throw "Invalid beta package: required file is missing: $requiredSource"
        }
    }

    Write-Step 'Preparing a verified Green VPN Beta copy...'
    New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null
    Get-ChildItem -LiteralPath $appSource -Force | Copy-Item -Destination $stagingRoot -Recurse -Force

    foreach ($folder in @('docs', 'tools')) {
        $source = Join-Path $tempRoot $folder
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $stagingRoot $folder) -Recurse -Force
        }
    }

    & icacls.exe $stagingRoot /inheritance:r /grant:r `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' `
        '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to protect the Green VPN Beta installation root.'
    }
    & icacls.exe (Join-Path $stagingRoot '*') /reset /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to inherit Green VPN Beta application and service file permissions.'
    }

    foreach ($requiredStaged in @(
        (Join-Path $stagingRoot 'greenvpn_beta.exe'),
        (Join-Path $stagingRoot 'greenvpn_beta_service.exe'),
        (Join-Path $stagingRoot 'tools\greenvpn_vpn_task.ps1'),
        (Join-Path $stagingRoot 'tools\uninstall_greenvpn_beta.ps1')
    )) {
        if (-not (Test-Path -LiteralPath $requiredStaged)) {
            throw "Green VPN Beta staging postcondition failed: $requiredStaged was not created."
        }
        if (-not (Test-FileAclAllows -Path $requiredStaged -Sid 'S-1-5-18' -RequiredRights ([Security.AccessControl.FileSystemRights]::FullControl))) {
            throw "Green VPN Beta staging ACL postcondition failed for SYSTEM: $requiredStaged"
        }
        if (-not (Test-FileAclAllows -Path $requiredStaged -Sid 'S-1-5-32-545' -RequiredRights ([Security.AccessControl.FileSystemRights]::ReadAndExecute))) {
            throw "Green VPN Beta staging ACL postcondition failed for Users: $requiredStaged"
        }
    }

    Write-Step 'Stopping only an existing beta instance...'
    Get-Process -Name $processName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-BetaTunnel
    Remove-BetaService
    $runtimeStopped = $true

    if (Test-Path -LiteralPath $installRoot) {
        if ($existingInstallValid) {
            Move-DirectoryWithRetry -Source $installRoot -Destination $backupRoot
            $existingRootBackedUp = $true
        } else {
            Write-Step 'Removing an incomplete previous beta installation...'
            Remove-CorruptInstallRoot -Root $installRoot
        }
    }
    Move-Item -LiteralPath $stagingRoot -Destination $installRoot -Force
    $installSwapped = $true

    $exe = Join-Path $installRoot 'greenvpn_beta.exe'
    $serviceExe = Join-Path $installRoot 'greenvpn_beta_service.exe'
    $taskScript = Join-Path $installRoot 'tools\greenvpn_vpn_task.ps1'
    $uninstallerSource = Join-Path $installRoot 'tools\uninstall_greenvpn_beta.ps1'
    if (-not (Test-Path -LiteralPath $uninstallerSource)) {
        throw 'Beta uninstaller is missing from the package.'
    }
    Copy-Item -LiteralPath $uninstallerSource -Destination (Join-Path $installRoot 'uninstall_greenvpn_beta.ps1') -Force

    @"
@echo off
powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "%~dp0uninstall_greenvpn_beta.ps1"
exit /b %ERRORLEVEL%
"@ | Set-Content -LiteralPath (Join-Path $installRoot 'uninstall_greenvpn_beta.cmd') -Encoding ASCII

    $shell = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $desktopShortcut = Join-Path $desktop 'Green VPN Beta.lnk'
    Remove-Item -LiteralPath $desktopShortcut -Force -ErrorAction SilentlyContinue
    $shortcut = $shell.CreateShortcut($desktopShortcut)
    $shortcut.TargetPath = $exe
    $shortcut.WorkingDirectory = $installRoot
    $shortcut.IconLocation = "$exe,0"
    $shortcut.Save()

    $startMenuDir = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Green VPN Beta'
    New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null
    $appShortcut = $shell.CreateShortcut((Join-Path $startMenuDir 'Green VPN Beta.lnk'))
    $appShortcut.TargetPath = $exe
    $appShortcut.WorkingDirectory = $installRoot
    $appShortcut.IconLocation = "$exe,0"
    $appShortcut.Save()
    $uninstallShortcut = $shell.CreateShortcut((Join-Path $startMenuDir 'Uninstall Green VPN Beta.lnk'))
    $uninstallShortcut.TargetPath = Join-Path $installRoot 'uninstall_greenvpn_beta.cmd'
    $uninstallShortcut.WorkingDirectory = $installRoot
    $uninstallShortcut.Save()

    New-Item -Path $runKey -Force | Out-Null
    New-ItemProperty -Path $runKey -Name 'GreenVPNBeta' -PropertyType String -Value ('"' + $exe + '" --background') -Force | Out-Null

    New-Item -Path $uninstallKey -Force | Out-Null
    $uninstallCommand = '"' + (Join-Path $installRoot 'uninstall_greenvpn_beta.cmd') + '"'
    $estimatedSizeKb = [Math]::Max(1, [int]([Math]::Ceiling((
        (Get-ChildItem -LiteralPath $installRoot -File -Recurse | Measure-Object -Property Length -Sum).Sum
    ) / 1KB)))
    $uninstallValues = [ordered]@{
        DisplayName = 'Green VPN Beta'
        DisplayVersion = $productVersion
        DisplayIcon = $exe
        Publisher = 'Green VPN'
        InstallLocation = $installRoot
        UninstallString = $uninstallCommand
        QuietUninstallString = $uninstallCommand
        URLInfoAbout = 'https://greenvpn.pro/paid-beta/'
        InstallDate = (Get-Date -Format 'yyyyMMdd')
    }
    foreach ($entry in $uninstallValues.GetEnumerator()) {
        New-ItemProperty -Path $uninstallKey -Name $entry.Key -PropertyType String -Value $entry.Value -Force | Out-Null
    }
    New-ItemProperty -Path $uninstallKey -Name 'EstimatedSize' -PropertyType DWord -Value $estimatedSizeKb -Force | Out-Null
    New-ItemProperty -Path $uninstallKey -Name 'NoModify' -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $uninstallKey -Name 'NoRepair' -PropertyType DWord -Value 1 -Force | Out-Null

    Ensure-BetaProgramData -UserSid $installingUserSid
    Install-BetaService -ServiceExe $serviceExe -TaskScript $taskScript

    foreach ($requiredPath in @(
        $exe,
        $serviceExe,
        $desktopShortcut,
        (Join-Path $startMenuDir 'Green VPN Beta.lnk'),
        $uninstallKey
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Green VPN Beta installation postcondition failed: $requiredPath was not created."
        }
    }

    Write-Step 'Beta installed successfully; stable installation was not modified.'
    $installCompleted = $true
    Remove-Item -LiteralPath $installErrorLog -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-CallerLegacyInstall
    if (
        -not $NoLaunch -and
        $env:GREENVPN_INSTALLER_SKIP_APP_LAUNCH -ne '1'
    ) {
        Start-Process -FilePath $exe -WorkingDirectory $installRoot
    }
} catch {
    $installError = $_
    try {
        $installError.Exception.ToString() | Set-Content -LiteralPath $installErrorLog -Encoding UTF8 -Force
    } catch {
    }
    if (-not $installCompleted -and ($runtimeStopped -or $existingRootBackedUp -or $installSwapped)) {
        Write-Step 'Beta installation did not complete; restoring the previous beta version...'
        try { Remove-BetaService } catch {}
        Get-Process -Name $processName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if ($installSwapped -or $existingRootBackedUp) {
            try { Remove-CorruptInstallRoot -Root $installRoot } catch {}
        }
        if (Test-Path -LiteralPath $backupRoot) {
            Move-DirectoryWithRetry -Source $backupRoot -Destination $installRoot
        }
        if ($existingInstallValid -and (Test-Path -LiteralPath $installRoot)) {
            $oldServiceExe = Join-Path $installRoot 'greenvpn_beta_service.exe'
            $oldTaskScript = Join-Path $installRoot 'tools\greenvpn_vpn_task.ps1'
            if ((Test-Path -LiteralPath $oldServiceExe) -and (Test-Path -LiteralPath $oldTaskScript)) {
                try { Install-BetaService -ServiceExe $oldServiceExe -TaskScript $oldTaskScript } catch {}
            }
            Remove-Item -LiteralPath $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
            if ($previousUninstallValues.Count -gt 0) {
                New-Item -Path $uninstallKey -Force | Out-Null
                foreach ($entry in $previousUninstallValues.GetEnumerator()) {
                    $propertyType = if ($entry.Key -in @('EstimatedSize', 'NoModify', 'NoRepair')) { 'DWord' } else { 'String' }
                    New-ItemProperty -Path $uninstallKey -Name $entry.Key -PropertyType $propertyType -Value $entry.Value -Force | Out-Null
                }
            }
            Remove-ItemProperty -Path $runKey -Name 'GreenVPNBeta' -Force -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace([string]$previousRunValue)) {
                New-Item -Path $runKey -Force | Out-Null
                New-ItemProperty -Path $runKey -Name 'GreenVPNBeta' -PropertyType String -Value $previousRunValue -Force | Out-Null
            }
        } elseif ($legacyInstallValid -and (Test-Path -LiteralPath $legacyInstallRoot)) {
            $legacyServiceExe = Join-Path $legacyInstallRoot 'greenvpn_beta_service.exe'
            $legacyTaskScript = Join-Path $legacyInstallRoot 'tools\greenvpn_vpn_task.ps1'
            try { Install-BetaService -ServiceExe $legacyServiceExe -TaskScript $legacyTaskScript } catch {}
            Remove-Item -LiteralPath $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $runKey -Name 'GreenVPNBeta' -Force -ErrorAction SilentlyContinue
        } else {
            Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Green VPN Beta.lnk') -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Green VPN Beta') -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $runKey -Name 'GreenVPNBeta' -Force -ErrorAction SilentlyContinue
        }
    }
    throw $installError
} finally {
    try { Stop-Transcript | Out-Null } catch {}
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}
