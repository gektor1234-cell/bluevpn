param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.." )).Path,
    [string]$ServerHost = "37.220.85.211"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl.exe not found. Deploy backend from WSL or install WSL."
}

$deployScript = Join-Path $ProjectRoot 'scripts\deploy_backend_wsl.sh'
if (-not (Test-Path -LiteralPath $deployScript)) {
    throw "Deploy script not found: $deployScript"
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

$wslDeployScript = ConvertTo-WslPath -WindowsPath $deployScript
if ([string]::IsNullOrWhiteSpace($wslDeployScript)) {
    throw "Could not resolve WSL path for: $deployScript"
}

Write-Host "[BlueVPN deploy] This will ask SSH for the server password if no SSH key is installed."
Write-Host "[BlueVPN deploy] Server: $ServerHost"
& wsl.exe bash "$wslDeployScript" "$ServerHost"
