param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.." )).Path,
    [string]$ServerHost = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$allowedControlPlaneHosts = @('72.56.32.197', '176.113.81.35')
if ([string]::IsNullOrWhiteSpace($ServerHost)) {
    throw "-ServerHost is required. Use an explicit current control plane: $($allowedControlPlaneHosts -join ', ')."
}
if ($ServerHost -notin $allowedControlPlaneHosts) {
    throw "Refusing to configure backend env on non-control-plane host: $ServerHost"
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl.exe not found. Configure backend env from WSL or install WSL."
}

$configureScript = Join-Path $ProjectRoot 'scripts\configure_backend_env_wsl.sh'
if (-not (Test-Path -LiteralPath $configureScript)) {
    throw "Configure script not found: $configureScript"
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory = $true)][string]$WindowsPath)

    $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
    $normalized = $fullPath -replace '\\', '/'

    if ($normalized -match '^([A-Za-z]):/(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        return "/mnt/$drive/$($Matches[2])"
    }

    throw "Could not convert Windows path to WSL path: $WindowsPath"
}

$wslConfigureScript = ConvertTo-WslPath -WindowsPath $configureScript
Write-Host "[Green VPN env] This script prompts for secrets and sends them to the server over SSH only."
Write-Host "[Green VPN env] Secrets are not written into the repository."
Write-Host "[Green VPN env] Server: $ServerHost"
& wsl.exe bash "$wslConfigureScript" "$ServerHost"
