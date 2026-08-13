param(
    [string]$InstallRoot = $PSScriptRoot,
    [switch]$FromTemp,
    [switch]$KeepProgramData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serviceName = 'GreenVPNBetaService'
$tunnelName = 'GreenVPNBeta'
$tunnelServiceName = 'WireGuardTunnel$GreenVPNBeta'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-PathSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$AllowedRoots
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }
    $full = [System.IO.Path]::GetFullPath($Path)
    foreach ($root in $AllowedRoots) {
        $allowed = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
        if (($full.TrimEnd('\') + '\').StartsWith($allowed, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
            return
        }
    }
    throw "Refusing to remove path outside beta roots: $full"
}

function Remove-ServiceAndWait {
    param([Parameter(Mandatory=$true)][string]$Name)

    try { & sc.exe stop $Name 2>$null | Out-Null } catch {}
    for ($i = 0; $i -lt 20; $i++) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
        if ($null -eq $service -or $service.State -ne 'Running') { break }
        Start-Sleep -Milliseconds 250
    }
    try { & sc.exe delete $Name 2>$null | Out-Null } catch {}
    for ($i = 0; $i -lt 20; $i++) {
        if ($null -eq (Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue)) {
            return
        }
        Start-Sleep -Milliseconds 250
    }
    throw "Could not remove beta service: $Name"
}

if (-not $FromTemp) {
    $tempDir = Join-Path $env:TEMP ("GreenVPNBetaUninstall_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $tempScript = Join-Path $tempDir 'uninstall_greenvpn_beta.ps1'
    Copy-Item -LiteralPath $PSCommandPath -Destination $tempScript -Force
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $tempScript + '"'),
        '-InstallRoot', ('"' + $InstallRoot + '"'),
        '-FromTemp'
    )
    if ($KeepProgramData) { $arguments += '-KeepProgramData' }
    $start = @{
        FilePath = 'powershell.exe'
        ArgumentList = $arguments
        WindowStyle = 'Hidden'
        Wait = $true
        PassThru = $true
    }
    if (-not (Test-IsAdministrator)) { $start['Verb'] = 'RunAs' }
    $process = Start-Process @start
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit $process.ExitCode
}

if (-not (Test-IsAdministrator)) {
    throw 'Green VPN Beta uninstaller must run as Administrator.'
}

Get-Process -Name 'greenvpn_beta' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Remove-ServiceAndWait -Name $serviceName

try { & sc.exe stop $tunnelServiceName 2>$null | Out-Null } catch {}
Start-Sleep -Milliseconds 500
foreach ($wireGuard in @(
    (Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe'),
    'C:\Program Files\WireGuard\wireguard.exe',
    'C:\Program Files (x86)\WireGuard\wireguard.exe'
)) {
    if (-not [string]::IsNullOrWhiteSpace($wireGuard) -and (Test-Path -LiteralPath $wireGuard)) {
        try { & $wireGuard /uninstalltunnelservice $tunnelName | Out-Null } catch {}
        break
    }
}
Remove-ServiceAndWait -Name $tunnelServiceName

foreach ($runKey in @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)) {
    Remove-ItemProperty -Path $runKey -Name 'GreenVPNBeta' -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN Beta' -Recurse -Force -ErrorAction SilentlyContinue

$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$commonDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
$programs = [Environment]::GetFolderPath('Programs')
$commonPrograms = [Environment]::GetFolderPath('CommonPrograms')
Remove-Item -LiteralPath (Join-Path $desktop 'Green VPN Beta.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $commonDesktop 'Green VPN Beta.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $programs 'Green VPN Beta') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $commonPrograms 'Green VPN Beta') -Recurse -Force -ErrorAction SilentlyContinue

$localPrograms = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs'))
$programFiles = [System.IO.Path]::GetFullPath($env:ProgramFiles)
$localAppData = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA)
$appData = [System.IO.Path]::GetFullPath($env:APPDATA)
$programData = [System.IO.Path]::GetFullPath($env:ProgramData)
Remove-PathSafe -Path $InstallRoot -AllowedRoots @($localPrograms, $programFiles)
Remove-PathSafe -Path (Join-Path $localPrograms 'Green VPN Beta') -AllowedRoots @($localPrograms)
Remove-PathSafe -Path (Join-Path $localAppData 'GreenVPNBeta') -AllowedRoots @($localAppData)
Remove-PathSafe -Path (Join-Path $appData 'GreenVPNBeta') -AllowedRoots @($appData)
if (-not $KeepProgramData) {
    Remove-PathSafe -Path (Join-Path $programData 'BlueVPNBeta') -AllowedRoots @($programData)
    Remove-Item -LiteralPath 'HKLM:\SOFTWARE\GreenVPN\Runtime\paid-beta' -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Green VPN Beta removed. Stable Green VPN was not modified.'
