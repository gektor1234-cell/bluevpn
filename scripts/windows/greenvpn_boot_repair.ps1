param(
    [switch]$NoSelfElevate,
    [switch]$FlushDns,
    [switch]$ResetWinsock
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tunnelName = 'BlueVPNDev1'
$serviceName = 'WireGuardTunnel$BlueVPNDev1'

function Write-Step {
    param([string]$Text)
    Write-Host "[Green VPN boot repair] $Text"
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WireGuardExe {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe')
    )
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function Remove-GreenVpnRunKeys {
    $runPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )

    foreach ($runPath in $runPaths) {
        if (-not (Test-Path -LiteralPath $runPath)) { continue }
        $props = Get-ItemProperty -LiteralPath $runPath
        foreach ($property in $props.PSObject.Properties) {
            $name = $property.Name
            if ($name -like 'PS*') { continue }
            $value = [string]$property.Value
            $isGreenVpn =
                $name -match 'GreenVPN|Green VPN|BlueVPN|Blue VPN' -or
                $value -match 'Green VPN|GreenVPN|greenvpn\.exe|bluevpn\.exe'
            if (-not $isGreenVpn) { continue }
            try {
                Remove-ItemProperty -LiteralPath $runPath -Name $name -Force
                Write-Step "Removed startup entry: $runPath :: $name"
            } catch {
                Write-Step "Could not remove startup entry $runPath :: $name : $($_.Exception.Message)"
            }
        }
    }
}

function Remove-GreenVpnScheduledTasks {
    try {
        $tasks = Get-ScheduledTask |
            Where-Object {
                $_.TaskName -match 'GreenVPN|Green VPN|BlueVPN|Blue VPN' -or
                $_.TaskPath -match 'GreenVPN|Green VPN|BlueVPN|Blue VPN'
            }
        foreach ($task in $tasks) {
            try {
                Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false
                Write-Step "Removed scheduled task: $($task.TaskPath)$($task.TaskName)"
            } catch {
                Write-Step "Could not remove scheduled task $($task.TaskName): $($_.Exception.Message)"
            }
        }
    } catch {
        Write-Step "Scheduled task cleanup skipped: $($_.Exception.Message)"
    }
}

if (-not (Test-IsAdmin)) {
    if ($NoSelfElevate) {
        throw 'Run this script from PowerShell as Administrator.'
    }

    Write-Step 'Requesting administrator rights...'
    $argsList = @(
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'RemoteSigned',
        '-File',
        "`"$PSCommandPath`"",
        '-NoSelfElevate'
    )
    if ($FlushDns) { $argsList += '-FlushDns' }
    if ($ResetWinsock) { $argsList += '-ResetWinsock' }
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList $argsList
    exit $p.ExitCode
}

Write-Step 'This repair only touches the Green VPN WireGuard tunnel BlueVPNDev1.'
Write-Step 'Amnezia, WARP and other VPN services are intentionally left alone.'

$wg = Get-WireGuardExe
$svc = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if ($svc) {
    Write-Step "Found $serviceName state=$($svc.State) startMode=$($svc.StartMode)"
    try {
        sc.exe stop $serviceName | Out-Host
    } catch {
        Write-Step "Stop returned: $($_.Exception.Message)"
    }
    Start-Sleep -Milliseconds 700

    if ($wg) {
        Write-Step "Uninstalling WireGuard tunnel $tunnelName via WireGuard..."
        & $wg /uninstalltunnelservice $tunnelName | Out-Host
    } else {
        Write-Step 'WireGuard.exe not found; deleting only the Green VPN tunnel service entry.'
        sc.exe delete $serviceName | Out-Host
    }
} else {
    Write-Step "$serviceName is not installed."
}

Remove-GreenVpnRunKeys
Remove-GreenVpnScheduledTasks

if ($FlushDns) {
    Write-Step 'Flushing DNS cache...'
    ipconfig /flushdns | Out-Host
}

if ($ResetWinsock) {
    Write-Step 'Resetting Winsock. Reboot Windows afterwards.'
    netsh winsock reset | Out-Host
}

Write-Step 'Current relevant VPN services:'
Get-CimInstance Win32_Service |
    Where-Object {
        $_.Name -match 'WireGuard|Amnezia|WARP|Cloudflare|BlueVPN|GreenVPN' -or
        $_.DisplayName -match 'WireGuard|Amnezia|WARP|Cloudflare|BlueVPN|GreenVPN'
    } |
    Select-Object Name, DisplayName, State, StartMode |
    Format-Table -AutoSize

Write-Step 'Done. Reboot Windows, then start only the VPN client you actually want to use.'
