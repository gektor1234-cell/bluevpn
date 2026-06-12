[CmdletBinding()]
param(
    [string]$ServerId = "tw-7879598-nl1",
    [string]$DnsHost = "nl2.vpn.greenvpn.pro",
    [string]$ExpectedIPv4 = "5.129.216.42",
    [string]$ApiBase = "https://api.greenvpn.pro",
    [string]$OriginHost = "37.220.85.211",
    [string]$OriginJumpHost = "72.56.32.197",
    [string]$ProbeHost = "72.56.32.197",
    [switch]$Apply,
    [switch]$SkipCanary
)

$ErrorActionPreference = "Stop"

function Assert-SafeId {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Pattern
    )
    if ($Value -notmatch $Pattern) {
        throw "$Name contains unsupported characters."
    }
}

function Resolve-IPv4Addresses {
    param([Parameter(Mandatory = $true)][string]$HostName)

    try {
        return @(Resolve-DnsName -Name $HostName -Type A -ErrorAction Stop |
            Where-Object { $_.IPAddress } |
            ForEach-Object { $_.IPAddress } |
            Sort-Object -Unique)
    } catch {
        return @([System.Net.Dns]::GetHostAddresses($HostName) |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
            ForEach-Object { $_.IPAddressToString } |
            Sort-Object -Unique)
    }
}

function Get-RemoteAdminToken {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [string]$JumpHost = ""
    )

    if ($JumpHost) {
        $token = (& ssh "-J" "root@$JumpHost" "root@$HostName" "cat /opt/bluevpn/backend/data/admin_token.txt") -join ""
    } else {
        $token = (& ssh "root@$HostName" "cat /opt/bluevpn/backend/data/admin_token.txt") -join ""
    }
    $token = $token.Trim()
    if (-not $token) {
        throw "Could not read admin token from origin host."
    }
    return $token
}

function Invoke-OriginSsh {
    param([Parameter(Mandatory = $true)][string]$Command)

    if ($OriginJumpHost) {
        return & ssh "-J" "root@$OriginJumpHost" "root@$OriginHost" $Command
    }
    return & ssh "root@$OriginHost" $Command
}

function Invoke-AdminApi {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body = $null
    )

    $headers = @{
        "X-Admin-Token" = $script:AdminToken
        "Accept" = "application/json"
    }
    $uri = $ApiBase.TrimEnd("/") + $Path
    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -TimeoutSec 30
    }
    $headers["Content-Type"] = "application/json"
    $json = $Body | ConvertTo-Json -Depth 8
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $json -TimeoutSec 30
}

function Copy-EntryValue {
    param(
        [object]$Entry,
        [string]$Name
    )
    if ($Entry.PSObject.Properties.Name -contains $Name) {
        return $Entry.$Name
    }
    return $null
}

Assert-SafeId -Name "ServerId" -Value $ServerId -Pattern "^[A-Za-z0-9_.-]+$"
Assert-SafeId -Name "DnsHost" -Value $DnsHost -Pattern "^[A-Za-z0-9.-]+$"
Assert-SafeId -Name "ExpectedIPv4" -Value $ExpectedIPv4 -Pattern "^[0-9.]+$"

$resolved = @(Resolve-IPv4Addresses -HostName $DnsHost)
$dnsReady = $resolved -contains $ExpectedIPv4
if (-not $dnsReady) {
    $actual = if ($resolved.Count -gt 0) { $resolved -join ", " } else { "(no A records)" }
    throw "DNS is not ready: $DnsHost must resolve to $ExpectedIPv4, actual: $actual"
}

$script:AdminToken = Get-RemoteAdminToken -HostName $OriginHost -JumpHost $OriginJumpHost
$catalog = Invoke-AdminApi -Method "GET" -Path "/api/v1/admin/server-catalog?status=all&active=all&public=all&limit=500"
$entry = @($catalog.managedEntries | Where-Object { $_.serverId -eq $ServerId } | Select-Object -First 1)
if (-not $entry) {
    throw "Managed server catalog entry was not found: $ServerId"
}
if ($entry.clientConfigProfile -ne "remote_ssh_wg0") {
    throw "Refusing to update non-remote profile: $($entry.clientConfigProfile)"
}
if (-not $entry.clientConfigReady) {
    throw "Refusing to update server without clientConfigReady=true."
}

$updatedEntry = [ordered]@{
    serverId = $entry.serverId
    title = $entry.title
    subtitle = Copy-EntryValue -Entry $entry -Name "subtitle"
    country = $entry.country
    city = Copy-EntryValue -Entry $entry -Name "city"
    provider = Copy-EntryValue -Entry $entry -Name "provider"
    host = $DnsHost
    port = $entry.port
    protocol = $entry.protocol
    transport = $entry.transport
    clientConfigProfile = $entry.clientConfigProfile
    status = $entry.status
    healthScore = Copy-EntryValue -Entry $entry -Name "healthScore"
    latencyMs = Copy-EntryValue -Entry $entry -Name "latencyMs"
    priority = Copy-EntryValue -Entry $entry -Name "priority"
    isActive = [bool]$entry.isActive
    isPublic = [bool]$entry.isPublic
    plannedBandwidthMbps = Copy-EntryValue -Entry $entry -Name "plannedBandwidthMbps"
    reservedBandwidthMbps = Copy-EntryValue -Entry $entry -Name "reservedBandwidthMbps"
    currentLoadMbps = Copy-EntryValue -Entry $entry -Name "currentLoadMbps"
    activeClients = Copy-EntryValue -Entry $entry -Name "activeClients"
    assignedUsers = Copy-EntryValue -Entry $entry -Name "assignedUsers"
    loadUpdatedAt = Copy-EntryValue -Entry $entry -Name "loadUpdatedAt"
    notes = Copy-EntryValue -Entry $entry -Name "notes"
}

$summary = [ordered]@{
    ok = $true
    apply = [bool]$Apply
    serverId = $ServerId
    dnsHost = $DnsHost
    expectedIPv4 = $ExpectedIPv4
    resolvedIPv4 = $resolved
    currentCatalogHost = $entry.host
    plannedCatalogHost = $DnsHost
    currentStatus = $entry.status
    willRemainActive = [bool]$entry.isActive
    willRemainPublic = [bool]$entry.isPublic
    action = "DNS is ready. Use -Apply to update origin env, catalog host, and run draft canary."
}

if (-not $Apply) {
    $summary | ConvertTo-Json -Depth 6
    return
}

$envFile = "/etc/bluevpn/vpn_nodes/$ServerId.env"
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$remoteCommand = "set -e; test -f '$envFile'; cp '$envFile' '$envFile.bak.$stamp'; if grep -q '^GREENVPN_NODE_PUBLIC_HOST=' '$envFile'; then sed -i 's|^GREENVPN_NODE_PUBLIC_HOST=.*|GREENVPN_NODE_PUBLIC_HOST=$DnsHost|' '$envFile'; else printf '\nGREENVPN_NODE_PUBLIC_HOST=$DnsHost\n' >> '$envFile'; fi; chmod 600 '$envFile'"
Invoke-OriginSsh -Command $remoteCommand | Out-Null

$entryId = [int]$entry.id
$catalogUpdate = Invoke-AdminApi -Method "POST" -Path "/api/v1/admin/server-catalog/$entryId" -Body $updatedEntry
$remoteCheck = Invoke-AdminApi -Method "GET" -Path "/api/v1/admin/server-catalog/$ServerId/remote-provisioning-check"

$canaryOutput = $null
if (-not $SkipCanary) {
    $probeCommand = "python3 /opt/greenvpn-monitoring/service_probe.py --api-base https://api.greenvpn.pro --admin-token-file /etc/greenvpn-monitoring/admin_token --probe-id external-site-72 --probe-region timeweb-msk-site --server-health --server-health-server-id $ServerId"
    $canaryOutput = (& ssh "root@$ProbeHost" $probeCommand) -join "`n"
}

[ordered]@{
    ok = $true
    serverId = $ServerId
    dnsHost = $DnsHost
    expectedIPv4 = $ExpectedIPv4
    resolvedIPv4 = $resolved
    catalogHost = $catalogUpdate.entry.host
    status = $catalogUpdate.entry.status
    isActive = $catalogUpdate.entry.isActive
    isPublic = $catalogUpdate.entry.isPublic
    remoteProvisioningOk = [bool]$remoteCheck.ok
    canaryRan = -not $SkipCanary
    canaryOutputPreview = if ($canaryOutput) { $canaryOutput.Substring(0, [Math]::Min(2000, $canaryOutput.Length)) } else { $null }
    note = "Node host is updated for DNS, but publication is still controlled separately."
} | ConvertTo-Json -Depth 8
