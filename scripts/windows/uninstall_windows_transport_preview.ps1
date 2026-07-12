param(
    [switch]$KeepProgramData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ServiceName = 'GreenVPNTransportPreviewService'
$TunnelName = 'GreenVPNTransportPreview'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'Programs\Green VPN Transport Preview'
$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned', '-File', ('"' + $PSCommandPath + '"'))
    if ($KeepProgramData) { $arguments += '-KeepProgramData' }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $process.ExitCode
}

Get-Process -Name 'greenvpn_transport_preview' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
foreach ($service in @('WireGuardTunnel$GreenVPNTransportPreview', 'AmneziaWGTunnel$GreenVPNTransportPreview')) {
    & sc.exe stop $service 2>$null | Out-Null
}
Start-Sleep -Milliseconds 500

$awg = Join-Path $InstallRoot 'tools\amneziawg2\amneziawg.exe'
if (Test-Path -LiteralPath $awg) {
    try { & $awg /uninstalltunnelservice $TunnelName | Out-Null } catch {}
}
foreach ($wg in @((Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'), (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe'))) {
    if (Test-Path -LiteralPath $wg) {
        try { & $wg /uninstalltunnelservice $TunnelName | Out-Null } catch {}
        break
    }
}

& sc.exe stop $ServiceName 2>$null | Out-Null
Start-Sleep -Milliseconds 500
& sc.exe delete $ServiceName 2>$null | Out-Null

$allowedInstallRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs')).TrimEnd('\') + '\'
$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\') + '\'
if ($resolvedInstallRoot.StartsWith($allowedInstallRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $InstallRoot)) {
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force
}

if (-not $KeepProgramData) {
    $allowedProgramData = [IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\') + '\'
    $resolvedProgramData = [IO.Path]::GetFullPath($ProgramDataRoot).TrimEnd('\') + '\'
    if ($resolvedProgramData.StartsWith($allowedProgramData, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $ProgramDataRoot)) {
        Remove-Item -LiteralPath $ProgramDataRoot -Recurse -Force
    }
}

Write-Output 'Green VPN Transport Preview removed.'

