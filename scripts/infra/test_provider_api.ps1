param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("all", "serverspace", "timeweb", "ruvds", "hostkey")]
    [string]$Provider = "all",

    [Parameter(Mandatory = $false)]
    [string]$SecretsPath = "D:\GreenVPNSecrets\provider_api.local.ps1",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeInventory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\provider_api_common.ps1"

$secretState = Import-GreenVpnProviderSecrets -SecretsPath $SecretsPath

function New-ProviderResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [hashtable]$Details = @{}
    )

    return [pscustomobject]@{
        provider = $Name
        status = $Status
        details = [pscustomobject]$Details
    }
}

function Test-Serverspace {
    $apiKey = Get-GreenVpnSecret -Name "GREENVPN_SERVERSPACE_API_KEY"
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        return New-ProviderResult -Name "serverspace" -Status "missing_secret" -Details @{
            requiredEnv = "GREENVPN_SERVERSPACE_API_KEY"
        }
    }

    $headers = @{
        "x-api-key" = $apiKey
    }

    $project = Invoke-GreenVpnJson `
        -Method GET `
        -Uri "https://api.serverspace.io/api/v1/project" `
        -Headers $headers

    $details = @{
        projectState = $project.project.state
        currency = $project.project.currency
        balance = $project.project.balance
    }

    if ($IncludeInventory) {
        try {
            $servers = Invoke-GreenVpnJson `
                -Method GET `
                -Uri "https://api.serverspace.io/api/v1/servers" `
                -Headers $headers
            $details.serverCount = @($servers.servers).Count
            $details.servers = @($servers.servers | ForEach-Object {
                [pscustomobject]@{
                    id = $_.id
                    name = $_.name
                    state = $_.state
                    location = $_.location_id
                    publicIp = $_.public_ip
                }
            })
        } catch {
            $details.inventoryError = $_.Exception.Message
        }
    }

    return New-ProviderResult -Name "serverspace" -Status "ok" -Details $details
}

function Test-Timeweb {
    $token = Get-GreenVpnSecret -Name "GREENVPN_TIMEWEB_TOKEN"
    if ([string]::IsNullOrWhiteSpace($token)) {
        return New-ProviderResult -Name "timeweb" -Status "missing_secret" -Details @{
            requiredEnv = "GREENVPN_TIMEWEB_TOKEN"
        }
    }

    $headers = @{
        Authorization = "Bearer $token"
    }

    $servers = Invoke-GreenVpnJson `
        -Method GET `
        -Uri "https://api.timeweb.cloud/api/v1/servers" `
        -Headers $headers

    $details = @{
        serverCount = @($servers.servers).Count
    }

    if ($IncludeInventory) {
        $details.servers = @($servers.servers | ForEach-Object {
            $mainIp = $null
            if ($_.main_ipv4) {
                $mainIp = $_.main_ipv4
            } elseif ($_.ips -and $_.ips.Count -gt 0) {
                $mainIp = $_.ips[0].ip
            }

            [pscustomobject]@{
                id = $_.id
                name = $_.name
                status = $_.status
                os = $_.os.name
                mainIp = $mainIp
            }
        })
    }

    return New-ProviderResult -Name "timeweb" -Status "ok" -Details $details
}

function Test-Ruvds {
    $apiKey = Get-GreenVpnSecret -Name "GREENVPN_RUVDS_API_KEY"
    $login = Get-GreenVpnSecret -Name "GREENVPN_RUVDS_API_LOGIN"
    $password = Get-GreenVpnSecret -Name "GREENVPN_RUVDS_API_PASSWORD"

    if ([string]::IsNullOrWhiteSpace($apiKey) -and
        ([string]::IsNullOrWhiteSpace($login) -or [string]::IsNullOrWhiteSpace($password))) {
        return New-ProviderResult -Name "ruvds" -Status "missing_secret" -Details @{
            requiredEnv = "GREENVPN_RUVDS_API_KEY or GREENVPN_RUVDS_API_LOGIN + GREENVPN_RUVDS_API_PASSWORD"
            note = "RUVDS API is provider-specific; creation script is kept in dry-run mode until tariff/datacenter IDs are pinned."
        }
    }

    return New-ProviderResult -Name "ruvds" -Status "configured_not_called" -Details @{
        reason = "RUVDS credentials are present, but this script does not call ambiguous endpoints yet."
        next = "Pin API v2 auth flow, datacenter id, os id, tariff id, then enable live calls."
    }
}

function Test-Hostkey {
    $apiKey = Get-GreenVpnSecret -Name "GREENVPN_HOSTKEY_API_KEY"
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        return New-ProviderResult -Name "hostkey" -Status "missing_secret" -Details @{
            requiredEnv = "GREENVPN_HOSTKEY_API_KEY"
            note = "HOSTKEY Invapi keys can be account-wide or server-specific; do not assume destructive rights."
        }
    }

    return New-ProviderResult -Name "hostkey" -Status "configured_not_called" -Details @{
        reason = "HOSTKEY key is present, but account/server scope must be confirmed before live calls."
        next = "Use HOSTKEY Invapi docs and pin the exact VM endpoint/order template before enabling creation."
    }
}

$providers = @()
if ($Provider -eq "all") {
    $providers = @("serverspace", "timeweb", "ruvds", "hostkey")
} else {
    $providers = @($Provider)
}

$results = @()
foreach ($item in $providers) {
    try {
        switch ($item) {
            "serverspace" { $results += Test-Serverspace }
            "timeweb" { $results += Test-Timeweb }
            "ruvds" { $results += Test-Ruvds }
            "hostkey" { $results += Test-Hostkey }
        }
    } catch {
        $results += New-ProviderResult -Name $item -Status "error" -Details @{
            error = $_.Exception.Message
        }
    }
}

Write-GreenVpnJson -InputObject ([pscustomobject]@{
    localConfigFile = $secretState
    includeInventory = [bool]$IncludeInventory
    providers = $results
})
