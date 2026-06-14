param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("all", "serverspace", "timeweb", "ruvds", "hostkey")]
    [string]$Provider = "all",

    [Parameter(Mandatory = $false)]
    [string]$SecretsPath = "",

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

function Get-ProviderField {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    if ($null -eq $Object) {
        return $null
    }

    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties[$name]
        if ($null -ne $prop) {
            return $prop.Value
        }
    }

    return $null
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
            $propNames = @($_.PSObject.Properties.Name)
            if ($propNames -contains "main_ipv4" -and $_.main_ipv4) {
                $mainIp = $_.main_ipv4
            } elseif ($propNames -contains "ips" -and $_.ips -and @($_.ips).Count -gt 0) {
                $ipItems = @($_.ips)
                $firstIp = @($ipItems | Where-Object {
                    ($_.PSObject.Properties.Name -contains "type") -and $_.type -eq "ipv4"
                } | Select-Object -First 1)
                if ($firstIp.Count -eq 0) {
                    $firstIp = @($ipItems | Select-Object -First 1)
                }
                if ($firstIp.Count -gt 0) {
                    if ($firstIp[0].PSObject.Properties.Name -contains "ip") {
                        $mainIp = $firstIp[0].ip
                    } else {
                        $mainIp = [string]$firstIp[0]
                    }
                }
            } elseif ($propNames -contains "networks" -and $_.networks) {
                $allNetworkIps = @($_.networks | ForEach-Object {
                    if ($_.PSObject.Properties.Name -contains "ips") {
                        @($_.ips)
                    }
                })
                $candidate = @($allNetworkIps | Where-Object {
                    ($_.PSObject.Properties.Name -contains "type") -and $_.type -eq "ipv4"
                } | Select-Object -First 1)
                if ($candidate.Count -eq 0) {
                    $candidate = @($allNetworkIps | Select-Object -First 1)
                }
                if ($candidate.Count -gt 0) {
                    $candidateValue = $candidate[0]
                    if ($candidateValue.PSObject.Properties.Name -contains "ip") {
                        $mainIp = $candidateValue.ip
                    } else {
                        $mainIp = [string]$candidateValue
                    }
                }
            }

            $osName = $null
            if ($propNames -contains "os" -and $_.os) {
                if ($_.os.PSObject.Properties.Name -contains "name") {
                    $osName = $_.os.name
                } else {
                    $osName = [string]$_.os
                }
            }

            [pscustomobject]@{
                id = $_.id
                name = $_.name
                status = $_.status
                os = $osName
                mainIp = $mainIp
            }
        })
    }

    return New-ProviderResult -Name "timeweb" -Status "ok" -Details $details
}

function Get-JsonArrayProperty {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) {
        return @()
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) {
        return @()
    }

    return @($prop.Value)
}

function Invoke-RuvdsApiV2 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    return Invoke-GreenVpnJson `
        -Method GET `
        -Uri "https://api.ruvds.com$Path" `
        -Headers @{ Authorization = "Bearer $Token" }
}

function Test-Ruvds {
    $apiKey = Get-GreenVpnSecret -Name "GREENVPN_RUVDS_API_KEY"

    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        return New-ProviderResult -Name "ruvds" -Status "missing_secret" -Details @{
            requiredEnv = "GREENVPN_RUVDS_API_KEY"
            note = "Use a RUVDS API v2 bearer token from https://ruvds.com/my/settings/api."
        }
    }

    $balance = Invoke-RuvdsApiV2 -Path "/v2/balance" -Token $apiKey
    $servers = Invoke-RuvdsApiV2 -Path "/v2/servers?page=1&per_page=50" -Token $apiKey
    $datacenters = Invoke-RuvdsApiV2 -Path "/v2/datacenters" -Token $apiKey
    $operatingSystems = Invoke-RuvdsApiV2 -Path "/v2/os" -Token $apiKey
    $tariffs = Invoke-RuvdsApiV2 -Path "/v2/tariffs" -Token $apiKey
    $sshKeys = Invoke-RuvdsApiV2 -Path "/v2/ssh_keys" -Token $apiKey

    $serverItems = Get-JsonArrayProperty -Object $servers -Name "servers"
    $datacenterItems = Get-JsonArrayProperty -Object $datacenters -Name "datacenters"
    $osItems = Get-JsonArrayProperty -Object $operatingSystems -Name "os"
    $vpsTariffs = Get-JsonArrayProperty -Object $tariffs -Name "vps"
    $driveTariffs = Get-JsonArrayProperty -Object $tariffs -Name "drive"
    $sshKeyItems = Get-JsonArrayProperty -Object $sshKeys -Name "ssh_keys"

    $details = @{
        balanceAmount = $balance.amount
        balanceCurrency = $balance.currency
        balanceType = $balance.type
        serverCount = @($serverItems).Count
        datacenterCount = @($datacenterItems).Count
        osCount = @($osItems).Count
        vpsTariffCount = @($vpsTariffs).Count
        driveTariffCount = @($driveTariffs).Count
        sshKeyCount = @($sshKeyItems).Count
    }

    if ($IncludeInventory) {
        $details.serverFieldNames = @($serverItems |
            Select-Object -First 1 |
            ForEach-Object { $_.PSObject.Properties.Name })
        $details.firstServerPreview = @($serverItems | Select-Object -First 1)

        $details.servers = @($serverItems | ForEach-Object {
            [pscustomobject]@{
                id = Get-ProviderField -Object $_ -Names @("id", "server_id", "virtual_server_id")
                name = Get-ProviderField -Object $_ -Names @("name", "title")
                status = Get-ProviderField -Object $_ -Names @("status", "state")
                datacenter = Get-ProviderField -Object $_ -Names @("datacenter", "datacenter_id", "dc")
                paidTill = Get-ProviderField -Object $_ -Names @("paid_till", "paidTill")
            }
        })

        $details.targetDatacenters = @($datacenterItems |
            Where-Object { $_.name -match 'LD|London|ZUR|Zurich|Amsterdam|Almaty|Astana' } |
            Select-Object -First 20 |
            ForEach-Object {
                [pscustomobject]@{
                    id = Get-ProviderField -Object $_ -Names @("id", "datacenter_id")
                    name = Get-ProviderField -Object $_ -Names @("name", "title")
                    vpsTariffs = Get-ProviderField -Object $_ -Names @("vps_tariffs", "vpsTariffs")
                    driveTariffs = Get-ProviderField -Object $_ -Names @("drive_tariffs", "driveTariffs")
                }
            })

        $details.linuxImages = @($osItems |
            Where-Object { $_.type -eq "linux" -and $_.is_active -and $_.name -match 'Debian 12|Ubuntu 22\.04|Ubuntu 24\.04' } |
            ForEach-Object {
                [pscustomobject]@{
                    id = Get-ProviderField -Object $_ -Names @("id", "os_id", "image_id")
                    name = Get-ProviderField -Object $_ -Names @("name", "title")
                    sshKeysSupported = Get-ProviderField -Object $_ -Names @("ssh_keys_supported", "sshKeysSupported")
                }
            })

        $details.vpsTariffs = @($vpsTariffs |
            Where-Object { $_.is_active } |
            Select-Object -First 20 |
            ForEach-Object {
                [pscustomobject]@{
                    id = Get-ProviderField -Object $_ -Names @("id", "tariff_id")
                    name = Get-ProviderField -Object $_ -Names @("name", "title")
                    cpuPrice = Get-ProviderField -Object $_ -Names @("cpu", "cpu_price")
                    ramPrice = Get-ProviderField -Object $_ -Names @("ram", "ram_price")
                    ipPrice = Get-ProviderField -Object $_ -Names @("ip", "ip_price")
                }
            })

        $details.sshKeys = @($sshKeyItems | ForEach-Object {
            [pscustomobject]@{
                id = $_.ssh_key_id
                name = $_.name
                fingerprint = $_.sha256_fingerprint
            }
        })
    }

    return New-ProviderResult -Name "ruvds" -Status "ok" -Details $details
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
    $providers = @("timeweb", "ruvds", "serverspace")
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
