param(
    [string]$PayloadDir = (Join-Path $PSScriptRoot 'app'),
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ServiceName = 'GreenVPNTransportPreviewService'
$TunnelName = 'GreenVPNTransportPreview'
$WireGuardTunnelService = 'WireGuardTunnel$GreenVPNTransportPreview'
$AmneziaWgTunnelService = 'AmneziaWGTunnel$GreenVPNTransportPreview'
$InstallRoot = Join-Path $env:ProgramFiles 'Green VPN Transport Preview'
$LegacyInstallRoot = Join-Path $env:LOCALAPPDATA 'Programs\Green VPN Transport Preview'
$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-SafeInstallPath {
    $allowed = [IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\') + '\'
    $candidate = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\') + '\'
    if (-not $candidate.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe transport preview install path: $candidate"
    }
}

function Set-PreviewAcl {
    param([string]$UserSid)

    & icacls.exe $InstallRoot /inheritance:r /grant:r `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' `
        '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to protect transport preview binaries.' }

    & icacls.exe $ProgramDataRoot /inheritance:r /grant:r `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' `
        ('*' + $UserSid + ':(OI)(CI)M') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to protect transport preview state.' }
    & icacls.exe $ProgramDataRoot /remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to remove broad transport preview state access.' }
    & icacls.exe $ProgramDataRoot /grant:r `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' `
        ('*' + $UserSid + ':(OI)(CI)M') /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to apply recursive transport preview state ACLs.' }
}

function Stop-PreviewTunnel {
    foreach ($service in @($WireGuardTunnelService, $AmneziaWgTunnelService)) {
        & sc.exe stop $service 2>$null | Out-Null
    }
    Start-Sleep -Milliseconds 500

    $awgCandidates = @(
        (Join-Path $InstallRoot 'tools\amneziawg2\amneziawg.exe'),
        (Join-Path $PayloadDir 'tools\amneziawg2\amneziawg.exe')
    )
    foreach ($awg in $awgCandidates) {
        if (Test-Path -LiteralPath $awg) {
            try { & $awg /uninstalltunnelservice $TunnelName | Out-Null } catch {}
            break
        }
    }
    foreach ($wg in @(
        (Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe')
    )) {
        if (Test-Path -LiteralPath $wg) {
            try { & $wg /uninstalltunnelservice $TunnelName | Out-Null } catch {}
            break
        }
    }
}

function Remove-PreviewService {
    & sc.exe stop $ServiceName 2>$null | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
        if ($null -eq $service -or $service.State -ne 'Running') { break }
        Start-Sleep -Milliseconds 200
    }
    & sc.exe delete $ServiceName 2>$null | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        if ($null -eq (Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 200
    }
}

function Ensure-ServiceToken {
    param([string]$UserSid)

    New-Item -ItemType Directory -Force -Path $ProgramDataRoot | Out-Null
    $tokenPath = Join-Path $ProgramDataRoot 'service_token'
    $current = if (Test-Path -LiteralPath $tokenPath) { (Get-Content -LiteralPath $tokenPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
    if ($current.Length -lt 24) {
        $bytes = New-Object byte[] 32
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        [Convert]::ToBase64String($bytes) | Set-Content -LiteralPath $tokenPath -NoNewline -Encoding ASCII
    }
    & attrib.exe +H $tokenPath 2>$null | Out-Null
    & icacls.exe $tokenPath /inheritance:r /grant:r `
        '*S-1-5-18:F' `
        '*S-1-5-32-544:F' `
        ('*' + $UserSid + ':R') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to protect transport preview service token.' }
}

$PayloadDir = [IO.Path]::GetFullPath($PayloadDir)
$required = @(
    'greenvpn_transport_preview.exe',
    'greenvpn_transport_preview_service.exe',
    'tools\greenvpn_transport_preview_vpn_task.ps1',
    'tools\amneziawg2\amneziawg.exe',
    'tools\amneziawg2\awg.exe',
    'tools\amneziawg2\wintun.dll'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $PayloadDir $relative))) {
        throw "Transport preview payload is incomplete: $relative"
    }
}

if (-not (Test-IsAdministrator)) {
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $PSCommandPath + '"'),
        '-PayloadDir', ('"' + $PayloadDir + '"')
    )
    if ($NoLaunch) { $arguments += '-NoLaunch' }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $process.ExitCode
}

Assert-SafeInstallPath
$installingUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Stop-PreviewTunnel
Remove-PreviewService
Get-Process -Name 'greenvpn_transport_preview' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $InstallRoot) {
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force
}
if (Test-Path -LiteralPath $LegacyInstallRoot) {
    $legacyAllowed = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs')).TrimEnd('\') + '\'
    $legacyCandidate = [IO.Path]::GetFullPath($LegacyInstallRoot).TrimEnd('\') + '\'
    if (-not $legacyCandidate.StartsWith($legacyAllowed, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe legacy transport preview path: $legacyCandidate"
    }
    Remove-Item -LiteralPath $LegacyInstallRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
Copy-Item -Path (Join-Path $PayloadDir '*') -Destination $InstallRoot -Recurse -Force
New-Item -ItemType Directory -Force -Path $ProgramDataRoot | Out-Null
Set-PreviewAcl -UserSid $installingUserSid
Ensure-ServiceToken -UserSid $installingUserSid

$serviceExe = Join-Path $InstallRoot 'greenvpn_transport_preview_service.exe'
$taskScript = Join-Path $InstallRoot 'tools\greenvpn_transport_preview_vpn_task.ps1'
$binaryPath = '"' + $serviceExe + '" --task-script "' + $taskScript + '"'
New-Service -Name $ServiceName -BinaryPathName $binaryPath -DisplayName 'Green VPN Transport Preview Service' -StartupType Automatic | Out-Null
& sc.exe description $ServiceName 'Green VPN isolated privileged service for preview VPN transports.' | Out-Null
& sc.exe start $ServiceName | Out-Null

for ($i = 0; $i -lt 40; $i++) {
    $service = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($null -ne $service -and $service.State -eq 'Running') { break }
    Start-Sleep -Milliseconds 250
}
$ready = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
if ($null -eq $ready -or $ready.State -ne 'Running') {
    throw 'Transport preview service did not reach Running state.'
}

if (-not $NoLaunch) {
    Start-Process -FilePath (Join-Path $InstallRoot 'greenvpn_transport_preview.exe') -WorkingDirectory $InstallRoot
}

Write-Output "Installed Green VPN Transport Preview to $InstallRoot"
