param(
    [switch]$KeepProgramData,
    [switch]$RemoveOldInstallers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-Step {
    param([string]$Text)
    Write-Host "[Green VPN clean] $Text"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath) -or -not (Test-Path -LiteralPath $PSCommandPath)) {
        throw "Cannot locate cleanup script for elevation."
    }

    Write-Step "Administrator rights are required to remove Green VPN service/tasks. Asking Windows once..."
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        ('"{0}"' -f $PSCommandPath)
    )
    if ($KeepProgramData) { $argList += '-KeepProgramData' }
    if ($RemoveOldInstallers) { $argList += '-RemoveOldInstallers' }

    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList ($argList -join ' ') -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $proc.ExitCode
}

function Remove-SafePath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$AllowedRoots
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }

    $full = [System.IO.Path]::GetFullPath($Path)
    $allowed = $false
    foreach ($root in $AllowedRoots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
        if (
            ($full + '\').StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
            $full.Equals($rootFull.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
        ) {
            $allowed = $true
            break
        }
    }

    if (-not $allowed) {
        Write-Step "Skip unsafe path: $full"
        return
    }

    Write-Step "Removing $full"
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
}

function Remove-GreenVpnTunnel {
    $serviceName = 'WireGuardTunnel$BlueVPNDev1'
    Write-Step "Removing only Green VPN tunnel $serviceName"

    sc.exe qc $serviceName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Step "Tunnel service is not installed"
        return
    }

    sc.exe stop $serviceName 2>$null | Out-Null
    Start-Sleep -Milliseconds 500

    $wgCandidates = @(
        (Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe'),
        'C:\Program Files\WireGuard\wireguard.exe',
        'C:\Program Files (x86)\WireGuard\wireguard.exe'
    )

    foreach ($wg in $wgCandidates) {
        if ([string]::IsNullOrWhiteSpace($wg)) { continue }
        if (Test-Path -LiteralPath $wg) {
            try { & $wg /uninstalltunnelservice BlueVPNDev1 *> $null } catch {}
            break
        }
    }

    sc.exe delete $serviceName 2>$null | Out-Null
}

Write-Step "Stopping Green VPN processes"
Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name 'bluevpn' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name 'greenvpn_service' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Step "Removing Green VPN native service"
sc.exe stop GreenVPNService 2>$null | Out-Null
Start-Sleep -Milliseconds 500
sc.exe delete GreenVPNService 2>$null | Out-Null
for ($i = 0; $i -lt 20; $i++) {
    $svc = Get-CimInstance Win32_Service -Filter "Name='GreenVPNService'" -ErrorAction SilentlyContinue
    if ($null -eq $svc) { break }
    Start-Sleep -Milliseconds 250
}

Write-Step "Removing Green VPN scheduled tasks"
foreach ($taskName in @('GreenVPNConnect', 'GreenVPNDisconnect', 'GreenVPNGuard', 'BlueVPNConnect', 'BlueVPNDisconnect', 'BlueVPNGuard')) {
    schtasks.exe /End /TN $taskName 2>$null | Out-Null
    try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
    schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
}

Write-Step "Removing Green VPN startup entries"
foreach ($runKey in @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)) {
    if (Test-Path $runKey) {
        foreach ($valueName in @('GreenVPN', 'Green VPN', 'BlueVPN', 'Blue VPN')) {
            Remove-ItemProperty -Path $runKey -Name $valueName -Force -ErrorAction SilentlyContinue
        }
    }
}

Remove-GreenVpnTunnel

$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$commonDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
$programs = [Environment]::GetFolderPath('Programs')
$commonPrograms = [Environment]::GetFolderPath('CommonPrograms')
$localPrograms = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs'))
$localAppData = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA)
$appData = [System.IO.Path]::GetFullPath($env:APPDATA)
$programData = [System.IO.Path]::GetFullPath($env:ProgramData)

Write-Step "Removing shortcuts"
foreach ($shortcutPath in @(
    (Join-Path $desktop 'Green VPN.lnk'),
    (Join-Path $desktop 'BlueVPN.lnk'),
    (Join-Path $commonDesktop 'Green VPN.lnk'),
    (Join-Path $commonDesktop 'BlueVPN.lnk')
)) {
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
}

foreach ($shortcutDir in @(
    (Join-Path $programs 'Green VPN'),
    (Join-Path $programs 'BlueVPN'),
    (Join-Path $commonPrograms 'Green VPN'),
    (Join-Path $commonPrograms 'BlueVPN')
)) {
    Remove-Item -LiteralPath $shortcutDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step "Removing installed files"
$allowedUserRoots = @($localPrograms, $localAppData, $appData)
foreach ($path in @(
    (Join-Path $localPrograms 'Green VPN'),
    (Join-Path $localPrograms 'GreenVPN'),
    (Join-Path $localPrograms 'BlueVPN'),
    (Join-Path $localAppData 'Green VPN'),
    (Join-Path $localAppData 'GreenVPN'),
    (Join-Path $localAppData 'BlueVPN'),
    (Join-Path $appData 'Green VPN'),
    (Join-Path $appData 'GreenVPN'),
    (Join-Path $appData 'BlueVPN')
)) {
    Remove-SafePath -Path $path -AllowedRoots $allowedUserRoots
}

$greenInstallRoot = Join-Path $localPrograms 'Green VPN'
if (Test-Path -LiteralPath $greenInstallRoot) {
    Write-Step "Green VPN install folder is still locked; stopping stale WSL relay and retrying"
    try { wsl.exe --shutdown 2>$null } catch {}
    Start-Sleep -Seconds 3
    Remove-SafePath -Path $greenInstallRoot -AllowedRoots $allowedUserRoots
}

if (-not $KeepProgramData) {
    Write-Step "Removing Green VPN machine state"
    foreach ($path in @(
        (Join-Path $programData 'BlueVPN'),
        (Join-Path $programData 'GreenVPN'),
        (Join-Path $programData 'Green VPN')
    )) {
        Remove-SafePath -Path $path -AllowedRoots @($programData)
    }
}

if ($RemoveOldInstallers) {
    $buildDir = 'C:\BlueVPN_Builds'
    if (Test-Path -LiteralPath $buildDir) {
        Write-Step "Removing old setup exe files from $buildDir"
        Get-ChildItem -LiteralPath $buildDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^(GreenVPN|BlueVPN)_Setup.*\.exe$' } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

$remaining = @()
if (Get-CimInstance Win32_Service -Filter "Name='GreenVPNService'" -ErrorAction SilentlyContinue) {
    $remaining += 'GreenVPNService'
}
if (Get-CimInstance Win32_Service -Filter "Name='WireGuardTunnel`$BlueVPNDev1'" -ErrorAction SilentlyContinue) {
    $remaining += 'WireGuardTunnel$BlueVPNDev1'
}
foreach ($taskName in @('GreenVPNConnect', 'GreenVPNDisconnect', 'GreenVPNGuard', 'BlueVPNConnect', 'BlueVPNDisconnect', 'BlueVPNGuard')) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        $remaining += $taskName
    }
}
if (Test-Path -LiteralPath (Join-Path $localPrograms 'Green VPN')) {
    $remaining += (Join-Path $localPrograms 'Green VPN')
}
if (-not $KeepProgramData -and (Test-Path -LiteralPath (Join-Path $programData 'BlueVPN'))) {
    $remaining += (Join-Path $programData 'BlueVPN')
}

if ($remaining.Count -gt 0) {
    Write-Step "Cleanup incomplete. Remaining Green VPN artifacts:"
    foreach ($item in $remaining) {
        Write-Step " - $item"
    }
    exit 1
}

Write-Step "Done. WireGuard, Amnezia and WARP were not removed."
