param(
    [string]$PayloadZip = "",
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\Green VPN Beta",
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serviceName = 'GreenVPNBetaService'
$tunnelName = 'GreenVPNBeta'
$tunnelServiceName = 'WireGuardTunnel$GreenVPNBeta'
$programDataRoot = Join-Path $env:ProgramData 'BlueVPNBeta'
$processName = 'greenvpn_beta'

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
    New-Item -ItemType Directory -Force -Path $programDataRoot | Out-Null
    attrib -H -S -R $programDataRoot 2>$null | Out-Null
    icacls $programDataRoot /inheritance:e /grant '*S-1-5-11:(OI)(CI)M' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null

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
    icacls $tokenPath /inheritance:r /grant '*S-1-5-18:F' '*S-1-5-32-544:F' '*S-1-5-11:R' | Out-Null
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

if ([string]::IsNullOrWhiteSpace($PayloadZip)) {
    $PayloadZip = Join-Path $PSScriptRoot 'GreenVPN_payload.zip'
}
if (-not (Test-Path -LiteralPath $PayloadZip)) {
    throw "Payload zip not found: $PayloadZip"
}

if (-not (Test-IsAdministrator)) {
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $PSCommandPath + '"'),
        '-PayloadZip', ('"' + $PayloadZip + '"'),
        '-InstallDir', ('"' + $InstallDir + '"')
    )
    if ($NoLaunch) { $arguments += '-NoLaunch' }
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList $arguments
    exit $process.ExitCode
}

$installRoot = [System.IO.Path]::GetFullPath($InstallDir)
$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs')).TrimEnd('\') + '\'
if (-not (($installRoot.TrimEnd('\') + '\').StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
    throw "InstallDir must stay under $allowedRoot"
}

$tempRoot = Join-Path $env:TEMP ("GreenVPNBetaInstall_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    Write-Step 'Stopping only an existing beta instance...'
    Get-Process -Name $processName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-BetaTunnel
    Remove-BetaService

    Write-Step 'Extracting beta package...'
    Expand-Archive -LiteralPath $PayloadZip -DestinationPath $tempRoot -Force
    $appSource = Join-Path $tempRoot 'app'
    foreach ($required in @('greenvpn_beta.exe', 'greenvpn_beta_service.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $appSource $required))) {
            throw "Invalid beta package: app\$required not found."
        }
    }

    Write-Step "Installing beta to $installRoot..."
    New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
    Get-ChildItem -LiteralPath $installRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    Get-ChildItem -LiteralPath $appSource -Force | Copy-Item -Destination $installRoot -Recurse -Force

    foreach ($folder in @('docs', 'tools')) {
        $source = Join-Path $tempRoot $folder
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $installRoot $folder) -Recurse -Force
        }
    }

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
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    $desktopShortcut = Join-Path $desktop 'Green VPN Beta.lnk'
    Remove-Item -LiteralPath $desktopShortcut -Force -ErrorAction SilentlyContinue
    $shortcut = $shell.CreateShortcut($desktopShortcut)
    $shortcut.TargetPath = $exe
    $shortcut.WorkingDirectory = $installRoot
    $shortcut.IconLocation = "$exe,0"
    $shortcut.Save()

    $startMenuDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Green VPN Beta'
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

    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $runKey -Force | Out-Null
    New-ItemProperty -Path $runKey -Name 'GreenVPNBeta' -PropertyType String -Value ('"' + $exe + '" --background') -Force | Out-Null

    Ensure-BetaProgramData
    Install-BetaService -ServiceExe $serviceExe -TaskScript $taskScript

    Write-Step 'Beta installed successfully; stable installation was not modified.'
    if (-not $NoLaunch) {
        Start-Process -FilePath $exe -WorkingDirectory $installRoot
    }
} finally {
    try { Stop-Transcript | Out-Null } catch {}
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
