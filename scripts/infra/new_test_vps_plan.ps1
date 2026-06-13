param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("serverspace", "timeweb", "ruvds", "hostkey")]
    [string]$Provider = "serverspace",

    [Parameter(Mandatory = $false)]
    [string]$SecretsPath = "D:\GreenVPNSecrets\provider_api.local.ps1",

    [Parameter(Mandatory = $false)]
    [string]$Name = "greenvpn-test-node-01",

    [Parameter(Mandatory = $false)]
    [string]$LocationId = "am2",

    [Parameter(Mandatory = $false)]
    [string]$ImageId = "Debian-12-X64",

    [Parameter(Mandatory = $false)]
    [int]$Cpu = 1,

    [Parameter(Mandatory = $false)]
    [int]$RamMb = 1024,

    [Parameter(Mandatory = $false)]
    [int]$DiskGb = 25,

    [Parameter(Mandatory = $false)]
    [int]$BandwidthMbps = 50,

    [Parameter(Mandatory = $false)]
    [switch]$Apply,

    [Parameter(Mandatory = $false)]
    [switch]$RegisterDraft,

    [Parameter(Mandatory = $false)]
    [string]$ServerId,

    [Parameter(Mandatory = $false)]
    [string]$Title,

    [Parameter(Mandatory = $false)]
    [string]$Country = "Netherlands",

    [Parameter(Mandatory = $false)]
    [string]$City = "Amsterdam",

    [Parameter(Mandatory = $false)]
    [string]$NodeIPv4,

    [Parameter(Mandatory = $false)]
    [string]$ApiBaseUrl = "https://api.greenvpn.pro",

    [Parameter(Mandatory = $false)]
    [string]$AdminToken = $env:BLUEVPN_ADMIN_TOKEN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\provider_api_common.ps1"

$secretState = Import-GreenVpnProviderSecrets -SecretsPath $SecretsPath

if ($Cpu -lt 1) { throw "-Cpu must be >= 1." }
if ($RamMb -lt 512) { throw "-RamMb must be >= 512." }
if ($DiskGb -lt 10) { throw "-DiskGb must be >= 10." }
if ($BandwidthMbps -lt 10) { throw "-BandwidthMbps must be >= 10." }

if ([string]::IsNullOrWhiteSpace($ServerId)) {
    $ServerId = ($Name.ToLowerInvariant() -replace '[^a-z0-9-]+', '-').Trim('-')
}
if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = $Name
}

function New-ServerspacePayload {
    return [ordered]@{
        location_id = $LocationId
        image_id = $ImageId
        cpu = $Cpu
        ram_mb = $RamMb
        volumes = @(
            @{
                name = "boot"
                size_mb = ($DiskGb * 1024)
            }
        )
        networks = @(
            @{
                bandwidth_mbps = $BandwidthMbps
            }
        )
        name = $Name
    }
}

function Register-GreenVpnBackendDraft {
    if ([string]::IsNullOrWhiteSpace($AdminToken)) {
        throw "RegisterDraft requires -AdminToken or BLUEVPN_ADMIN_TOKEN."
    }
    if ([string]::IsNullOrWhiteSpace($NodeIPv4)) {
        throw "RegisterDraft requires -NodeIPv4 after provider creates the server."
    }

    $body = [ordered]@{
        serverId = $ServerId
        title = $Title
        country = $Country
        city = $City
        provider = $Provider
        host = $NodeIPv4
        port = 443
        protocol = "wireguard"
        transport = "udp"
        clientConfigProfile = "none"
        status = "draft"
        isActive = $false
        isPublic = $false
        notes = "Hidden test node draft from provider automation. Promote only after WireGuard bootstrap, remote provisioning check, smoke test, and owner approval."
    }

    return Invoke-GreenVpnJson `
        -Method POST `
        -Uri "$($ApiBaseUrl.TrimEnd('/'))/api/v1/admin/server-catalog/draft-from-plan" `
        -Headers @{ "X-Admin-Token" = $AdminToken } `
        -Body $body
}

$plan = [ordered]@{
    dryRun = -not [bool]$Apply
    provider = $Provider
    action = "create_test_vps"
    serverId = $ServerId
    title = $Title
    country = $Country
    city = $City
    publicCatalogImpact = "none; draft/test node only"
    nextSteps = @(
        "Top up provider balance if needed.",
        "Run this script with -Apply only when the plan is approved.",
        "Bootstrap WireGuard on the new VPS with scripts/server/bootstrap_wireguard_node.sh --apply.",
        "Create backend-only /etc/bluevpn/vpn_nodes/<serverId>.env on the origin.",
        "Run remote-provisioning-check and client-config-smoke before any publication."
    )
}

switch ($Provider) {
    "serverspace" {
        $plan.endpoint = "POST https://api.serverspace.io/api/v1/servers"
        $plan.payload = New-ServerspacePayload

        if ($Apply) {
            $apiKey = Get-GreenVpnSecret -Name "GREENVPN_SERVERSPACE_API_KEY" -Required
            $created = Invoke-GreenVpnJson `
                -Method POST `
                -Uri "https://api.serverspace.io/api/v1/servers" `
                -Headers @{ "x-api-key" = $apiKey } `
                -Body $plan.payload
            $plan.providerResponse = $created
        }
    }
    "timeweb" {
        $plan.endpoint = "Timeweb Cloud API"
        $plan.payload = [ordered]@{
            name = $Name
            location = $LocationId
            image = $ImageId
            cpu = $Cpu
            ramMb = $RamMb
            diskGb = $DiskGb
            note = "Live creation is intentionally disabled until exact Timeweb configuration IDs are pinned."
        }
        if ($Apply) {
            throw "Timeweb live creation is not enabled in this script yet. Use the existing Timeweb panel/API flow or pin exact IDs first."
        }
    }
    "ruvds" {
        $plan.endpoint = "RUVDS API v2"
        $plan.payload = [ordered]@{
            name = $Name
            datacenter = $LocationId
            os = $ImageId
            cpu = $Cpu
            ramMb = $RamMb
            diskGb = $DiskGb
            note = "Live creation is intentionally disabled until RUVDS tariff/datacenter/os IDs are pinned."
        }
        if ($Apply) {
            throw "RUVDS live creation is not enabled in this script yet. Pin tariff/datacenter/os IDs first."
        }
    }
    "hostkey" {
        $plan.endpoint = "HOSTKEY Invapi"
        $plan.payload = [ordered]@{
            name = $Name
            location = $LocationId
            image = $ImageId
            cpu = $Cpu
            ramMb = $RamMb
            diskGb = $DiskGb
            note = "Live creation is intentionally disabled until HOSTKEY account scope and order template are pinned."
        }
        if ($Apply) {
            throw "HOSTKEY live creation is not enabled in this script yet. Pin Invapi order template first."
        }
    }
}

if ($RegisterDraft) {
    $plan.backendDraft = Register-GreenVpnBackendDraft
}

Write-GreenVpnJson -InputObject ([pscustomobject]@{
    localConfigFile = $secretState
    plan = [pscustomobject]$plan
})
