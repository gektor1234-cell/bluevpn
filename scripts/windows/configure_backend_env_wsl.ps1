param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.." )).Path,
    [string]$ServerHost = "37.220.85.211"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
