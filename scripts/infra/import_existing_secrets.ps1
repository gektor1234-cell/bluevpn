param(
    [Parameter(Mandatory = $false)]
    [string]$SourceDir = "D:\GreenVPN_Secrets",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "",

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\provider_api_common.ps1"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = "D:\GreenVPN_Secrets\provider_api.local.ps1"
}

function Read-KeyValueFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $values
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $match = [regex]::Match($trimmed, '^([A-Za-z0-9_.-]+)\s*=\s*(.*)$')
        if (-not $match.Success) {
            continue
        }

        $key = $match.Groups[1].Value.Trim()
        $value = $match.Groups[2].Value.Trim()
        $value = $value.Trim('"').Trim("'")
        $values[$key] = $value
    }

    return $values
}

function Add-EnvLine {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Output,

        [Parameter(Mandatory = $true)]
        [string]$EnvName,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Value
    )

    if (Test-GreenVpnPlaceholderSecret -Value $Value) {
        return
    }

    $Output[$EnvName] = $Value
}

function Escape-PowerShellDoubleQuotedValue {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return ($Value -replace '`', '``' -replace '"', '`"')
}

if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
    throw "Source secrets directory not found: $SourceDir"
}

if ((Test-Path -LiteralPath $OutputPath -PathType Leaf) -and -not $Force) {
    throw "Output file already exists: $OutputPath. Pass -Force to overwrite it."
}

$resolvedSource = Resolve-Path -LiteralPath $SourceDir
$source = $resolvedSource.Path

$ruvds = Read-KeyValueFile -Path (Join-Path $source "ruvds_access.txt")
$serverspace = Read-KeyValueFile -Path (Join-Path $source "serverspace_access.txt")
$timeweb = Read-KeyValueFile -Path (Join-Path $source "timeweb_access.txt")
$sms = Read-KeyValueFile -Path (Join-Path $source "sms_ru_access.txt")
$smtp = Read-KeyValueFile -Path (Join-Path $source "smtp_access.txt")
$yookassa = Read-KeyValueFile -Path (Join-Path $source "yookassa_access.txt")

$envValues = [ordered]@{}

Add-EnvLine -Output $envValues -EnvName "GREENVPN_SERVERSPACE_API_KEY" -Value $serverspace["serverspace_api_token"]
Add-EnvLine -Output $envValues -EnvName "GREENVPN_TIMEWEB_TOKEN" -Value $timeweb["timeweb_api_token"]
Add-EnvLine -Output $envValues -EnvName "GREENVPN_RUVDS_API_KEY" -Value $ruvds["ruvds_api_v2_token"]
Add-EnvLine -Output $envValues -EnvName "GREENVPN_RUVDS_API_LOGIN" -Value $ruvds["ruvds_login"]
Add-EnvLine -Output $envValues -EnvName "GREENVPN_RUVDS_API_PASSWORD" -Value $ruvds["ruvds_password"]

Add-EnvLine -Output $envValues -EnvName "GREENVPN_SMS_RU_API_ID" -Value $sms["sms_ru_api_id"]

Add-EnvLine -Output $envValues -EnvName "GREENVPN_SMTP_HOST" -Value $smtp["smtp_host"]
Add-EnvLine -Output $envValues -EnvName "GREENVPN_SMTP_PORT" -Value $smtp["smtp_port"]
Add-EnvLine -Output $envValues -EnvName "GREENVPN_SMTP_USERNAME" -Value $smtp["smtp_username"]
Add-EnvLine -Output $envValues -EnvName "GREENVPN_SMTP_PASSWORD" -Value $smtp["smtp_password"]
Add-EnvLine -Output $envValues -EnvName "GREENVPN_SMTP_FROM" -Value $smtp["smtp_from"]
Add-EnvLine -Output $envValues -EnvName "GREENVPN_SMTP_USE_TLS" -Value "1"

Add-EnvLine -Output $envValues -EnvName "YOOKASSA_SHOP_ID" -Value $yookassa["yookassa_shop_id"]
Add-EnvLine -Output $envValues -EnvName "YOOKASSA_SECRET_KEY" -Value $yookassa["yookassa_secret_key"]
Add-EnvLine -Output $envValues -EnvName "YOOKASSA_API_BASE" -Value "https://api.yookassa.ru/v3"
Add-EnvLine -Output $envValues -EnvName "YOOKASSA_RETURN_URL" -Value "https://api.greenvpn.pro/payment/return"
Add-EnvLine -Output $envValues -EnvName "YOOKASSA_WEBHOOK_URL" -Value "https://api.greenvpn.pro/api/v1/billing/yookassa/webhook"

$outputDir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$lines = @(
    "# Local Green VPN secrets generated from $SourceDir.",
    "# This file is ignored by git. Do not commit. Do not paste values into chat.",
    ""
)

foreach ($name in $envValues.Keys) {
    $escaped = Escape-PowerShellDoubleQuotedValue -Value $envValues[$name]
    $lines += "`$env:$name = `"$escaped`""
}

$lines += ""
Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8

$configured = @()
foreach ($name in $envValues.Keys) {
    $value = [string]$envValues[$name]
    $configured += [pscustomobject]@{
        name = $name
        configured = $true
        length = $value.Length
    }
}

[pscustomobject]@{
    sourceDir = $source
    outputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    configuredCount = $configured.Count
    configured = $configured
} | ConvertTo-Json -Depth 5
