param(
    [switch]$RestartAdapters,
    [switch]$ForceReboot,
    [int]$RebootDelaySeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Text)
    Write-Host "[Green VPN network recover] $Text"
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    throw "Run this script from PowerShell as Administrator."
}

Write-Step "Flushing DNS cache..."
ipconfig /flushdns | Out-Host

Write-Step "Resetting Winsock..."
netsh winsock reset | Out-Host

Write-Step "Resetting IPv4/IPv6 stack..."
netsh int ip reset | Out-Host

if ($RestartAdapters) {
    Write-Step "Restarting active network adapters..."
    Get-NetAdapter |
        Where-Object { $_.Status -ne 'Disabled' } |
        Restart-NetAdapter -Confirm:$false
}
else {
    Write-Step "Adapter restart skipped. Use -RestartAdapters if DNS/Winsock reset is not enough."
}

Write-Step "Renewing DHCP leases where possible..."
ipconfig /renew | Out-Host

if ($ForceReboot) {
    Write-Step "Rebooting in $RebootDelaySeconds seconds..."
    shutdown /r /t $RebootDelaySeconds
}
else {
    Write-Step "Done. Reboot Windows before testing VPN again."
}
