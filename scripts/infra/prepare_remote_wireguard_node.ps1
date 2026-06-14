param(
    [Parameter(Mandatory = $true)]
    [string]$ServerId,

    [Parameter(Mandatory = $true)]
    [string]$NodeIPv4,

    [Parameter(Mandatory = $false)]
    [string]$Title = "",

    [Parameter(Mandatory = $false)]
    [string]$Country = "CH",

    [Parameter(Mandatory = $false)]
    [string]$City = "Zurich",

    [Parameter(Mandatory = $false)]
    [string]$Provider = "ruvds",

    [Parameter(Mandatory = $false)]
    [string]$ApiBaseUrl = "https://api.greenvpn.pro",

    [Parameter(Mandatory = $false)]
    [string]$OriginHost = "37.220.85.211",

    [Parameter(Mandatory = $false)]
    [int]$SshPort = 22,

    [Parameter(Mandatory = $false)]
    [int]$WireGuardPort = 443,

    [Parameter(Mandatory = $false)]
    [string]$WireGuardInterface = "wg0",

    [Parameter(Mandatory = $false)]
    [string]$WireGuardConfigPath = "/etc/wireguard/wg0.conf",

    [Parameter(Mandatory = $false)]
    [int]$PlannedBandwidthMbps = 100,

    [Parameter(Mandatory = $false)]
    [switch]$Apply,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmRemoteProvision,

    [Parameter(Mandatory = $false)]
    [switch]$AddToPreview
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\provider_api_common.ps1"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$BootstrapScript = Join-Path $RepoRoot "scripts\server\bootstrap_wireguard_node.sh"
$SshPath = Join-Path $env:WINDIR "System32\OpenSSH\ssh.exe"
$ScpPath = Join-Path $env:WINDIR "System32\OpenSSH\scp.exe"

function Assert-GreenVpnSafeToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    if ($Value -notmatch $Pattern) {
        throw "$Name contains unsupported characters."
    }
}

function ConvertTo-Base64Utf8 {
    param([Parameter(Mandatory = $true)][string]$Text)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Text -replace "`r", "")))
}

function Invoke-SshCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSec = 20
    )

    $args = @(
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "ConnectTimeout=$TimeoutSec",
        $HostName,
        $Command
    )
    $output = & $SshPath @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        $safe = Protect-GreenVpnString -Value (($output | Out-String).Trim())
        throw "SSH command failed on $HostName`: $safe"
    }
    return (($output | Out-String).Trim())
}

function Invoke-RemoteBash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$Script,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSec = 20
    )

    $b64 = ConvertTo-Base64Utf8 -Text $Script
    return Invoke-SshCommand -HostName $HostName -TimeoutSec $TimeoutSec -Command "echo $b64 | base64 -d | bash"
}

function Copy-ToRemote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LocalPath,

        [Parameter(Mandatory = $true)]
        [string]$RemoteSpec
    )

    $args = @(
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        $LocalPath,
        $RemoteSpec
    )
    $output = & $ScpPath @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        $safe = Protect-GreenVpnString -Value (($output | Out-String).Trim())
        throw "SCP failed: $safe"
    }
}

function Get-OriginAdminToken {
    $token = Invoke-RemoteBash -HostName "root@$OriginHost" -Script @'
set -euo pipefail
cat /opt/bluevpn/backend/data/admin_token.txt
'@ -TimeoutSec 10
    $token = $token.Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Origin admin token is empty."
    }
    return $token
}

function Invoke-AdminApi {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [object]$Body = $null
    )

    $headers = @{
        "X-Admin-Token" = $script:AdminToken
        "Accept" = "application/json"
    }
    if ($null -eq $Body) {
        return Invoke-GreenVpnJson -Method $Method -Uri "$($ApiBaseUrl.TrimEnd('/'))$Path" -Headers $headers -TimeoutSec 30
    }

    return Invoke-GreenVpnJson -Method $Method -Uri "$($ApiBaseUrl.TrimEnd('/'))$Path" -Headers $headers -Body $Body -TimeoutSec 30
}

function Get-ManagedCatalogEntry {
    $catalog = Invoke-AdminApi -Method "GET" -Path "/api/v1/admin/server-catalog?status=all&active=all&public=all&limit=500"
    $entries = @($catalog.managedEntries)
    return @($entries | Where-Object { $_.serverId -eq $ServerId } | Select-Object -First 1)
}

function New-HiddenRemotePayload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$ClientConfigProfile
    )

    return [ordered]@{
        serverId = $ServerId
        title = if ([string]::IsNullOrWhiteSpace($Title)) { "Green VPN $Provider $City" } else { $Title }
        subtitle = "Preview-only remote WireGuard node"
        country = $Country
        city = $City
        provider = $Provider
        host = $NodeIPv4
        port = $WireGuardPort
        protocol = "wireguard_udp"
        transport = "udp"
        clientConfigProfile = $ClientConfigProfile
        status = $Status
        healthScore = if ($Status -eq "healthy") { 100 } else { 0 }
        latencyMs = $null
        priority = 100
        isActive = $false
        isPublic = $false
        plannedBandwidthMbps = $PlannedBandwidthMbps
        reservedBandwidthMbps = $null
        currentLoadMbps = 0
        activeClients = 0
        assignedUsers = 0
        loadUpdatedAt = $null
        notes = "Prepared by scripts/infra/prepare_remote_wireguard_node.ps1. Hidden from stable; preview publication is controlled by GREENVPN_PREVIEW_SERVER_IDS."
    }
}

function Upsert-HiddenRemoteEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$ClientConfigProfile
    )

    $entry = @(Get-ManagedCatalogEntry)
    $payload = New-HiddenRemotePayload -Status $Status -ClientConfigProfile $ClientConfigProfile
    if ($entry.Count -gt 0) {
        return Invoke-AdminApi -Method "POST" -Path "/api/v1/admin/server-catalog/$($entry[0].id)" -Body $payload
    }
    return Invoke-AdminApi -Method "POST" -Path "/api/v1/admin/server-catalog" -Body $payload
}

function Wait-NodeSsh {
    $deadline = (Get-Date).AddMinutes(6)
    $lastError = ""
    while ((Get-Date) -lt $deadline) {
        try {
            $probe = Invoke-RemoteBash -HostName "root@$NodeIPv4" -Script "set -e; uname -s; id -u" -TimeoutSec 10
            if ($probe -match "Linux" -and $probe -match "0") {
                return $true
            }
        } catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Seconds 10
        }
    }
    throw "Node SSH did not become ready: $(Protect-GreenVpnString -Value $lastError)"
}

function Ensure-OriginNodeSshKey {
    $script = @"
set -euo pipefail
install -d -m 0700 /etc/bluevpn/vpn_nodes
key_path="/etc/bluevpn/vpn_nodes/$ServerId`_ed25519"
if [ ! -s "`$key_path" ]; then
  ssh-keygen -t ed25519 -N "" -f "`$key_path" -C "greenvpn-$ServerId" >/dev/null
fi
chmod 0600 "`$key_path"
chmod 0644 "`$key_path.pub"
cat "`$key_path.pub"
"@
    $publicKey = Invoke-RemoteBash -HostName "root@$OriginHost" -Script $script -TimeoutSec 20
    $publicKey = $publicKey.Trim()
    if ([string]::IsNullOrWhiteSpace($publicKey) -or $publicKey -notmatch "^ssh-ed25519 ") {
        throw "Origin SSH public key was not generated."
    }
    return [pscustomobject]@{
        privateKeyPath = "/etc/bluevpn/vpn_nodes/$ServerId`_ed25519"
        publicKey = $publicKey
    }
}

function Add-OriginKeyToNode {
    param([Parameter(Mandatory = $true)][string]$PublicKey)

    $keyB64 = ConvertTo-Base64Utf8 -Text $PublicKey
    $script = @"
set -euo pipefail
install -d -m 0700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
key="`$(echo $keyB64 | base64 -d)"
grep -qxF "`$key" /root/.ssh/authorized_keys || printf '%s\n' "`$key" >> /root/.ssh/authorized_keys
"@
    Invoke-RemoteBash -HostName "root@$NodeIPv4" -Script $script -TimeoutSec 20 | Out-Null
}

function Bootstrap-NodeWireGuard {
    Copy-ToRemote -LocalPath $BootstrapScript -RemoteSpec "root@$NodeIPv4`:/tmp/greenvpn-bootstrap-wireguard-node.sh"
    $output = Invoke-RemoteBash -HostName "root@$NodeIPv4" -Script @"
set -euo pipefail
chmod 0700 /tmp/greenvpn-bootstrap-wireguard-node.sh
/tmp/greenvpn-bootstrap-wireguard-node.sh --apply --iface $WireGuardInterface --port $WireGuardPort
"@ -TimeoutSec 240
    $match = [regex]::Match($output, "(?m)^server_public_key=([A-Za-z0-9+/=]+)$")
    if (-not $match.Success) {
        $safe = Protect-GreenVpnString -Value $output
        throw "WireGuard bootstrap did not return a server public key. Output: $safe"
    }
    return $match.Groups[1].Value
}

function Write-OriginNodeEnv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OriginKeyPath,

        [Parameter(Mandatory = $true)]
        [string]$WireGuardPublicKey
    )

    $publicKeyB64 = ConvertTo-Base64Utf8 -Text $WireGuardPublicKey
    $script = @"
set -euo pipefail
install -d -m 0700 /etc/bluevpn/vpn_nodes
env_file="/etc/bluevpn/vpn_nodes/$ServerId.env"
if [ -f "`$env_file" ]; then
  cp "`$env_file" "`$env_file.bak.`$(date -u +%Y%m%dT%H%M%SZ)"
fi
wg_public_key="`$(echo $publicKeyB64 | base64 -d)"
cat > "`$env_file" <<EOF
GREENVPN_NODE_HOST=$NodeIPv4
GREENVPN_NODE_PORT=$SshPort
GREENVPN_NODE_USER=root
GREENVPN_NODE_SSH_KEY=$OriginKeyPath
GREENVPN_NODE_PUBLIC_HOST=$NodeIPv4
GREENVPN_NODE_PUBLIC_PORT=$WireGuardPort
GREENVPN_NODE_WG_INTERFACE=$WireGuardInterface
GREENVPN_NODE_WG_CONFIG=$WireGuardConfigPath
GREENVPN_NODE_WG_PUBLIC_KEY=`$wg_public_key
EOF
chmod 0600 "`$env_file"
"@
    Invoke-RemoteBash -HostName "root@$OriginHost" -Script $script -TimeoutSec 20 | Out-Null
}

function Add-NodeToPreview {
    $script = @"
set -euo pipefail
env_file="/etc/bluevpn/backend.env"
install -d -m 0755 /etc/bluevpn
touch "`$env_file"
chmod 0600 "`$env_file"
cp "`$env_file" "`$env_file.bak.`$(date -u +%Y%m%dT%H%M%SZ)"
current="`$(grep -E '^GREENVPN_PREVIEW_SERVER_IDS=' "`$env_file" | tail -n 1 | cut -d= -f2- || true)"
current="`${current%\"}"
current="`${current#\"}"
current="`${current%\'}"
current="`${current#\'}"
next="`$current"
case ",`$current," in
  *",$ServerId,"*) ;;
  ",,") next="$ServerId" ;;
  *) next="`$current,$ServerId" ;;
esac
tmp="`$(mktemp)"
grep -v -E '^GREENVPN_PREVIEW_SERVER_IDS=' "`$env_file" > "`$tmp" || true
printf 'GREENVPN_PREVIEW_SERVER_IDS=%s\n' "`$next" >> "`$tmp"
cat "`$tmp" > "`$env_file"
rm -f "`$tmp"
systemctl restart bluevpn-backend
"@
    Invoke-RemoteBash -HostName "root@$OriginHost" -Script $script -TimeoutSec 30 | Out-Null
}

Assert-GreenVpnSafeToken -Name "ServerId" -Value $ServerId -Pattern "^[a-z0-9][a-z0-9_.-]{2,79}$"
Assert-GreenVpnSafeToken -Name "NodeIPv4" -Value $NodeIPv4 -Pattern "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$"
Assert-GreenVpnSafeToken -Name "OriginHost" -Value $OriginHost -Pattern "^[A-Za-z0-9.-]+$"
if (-not (Test-Path -LiteralPath $BootstrapScript -PathType Leaf)) {
    throw "Bootstrap script not found: $BootstrapScript"
}

$script:AdminToken = Get-OriginAdminToken
$existing = @(Get-ManagedCatalogEntry)
$dryRunActions = @(
    "wait for SSH on root@$NodeIPv4",
    "bootstrap WireGuard wg0 on UDP $WireGuardPort",
    "create origin-only SSH key and node env under /etc/bluevpn/vpn_nodes",
    "upsert hidden managed catalog entry as remote_ssh_wg0",
    "run remote-provisioning-check, remote-peer-smoke, and client-config-smoke",
    "keep isActive=false and isPublic=false",
    $(if ($AddToPreview) { "append $ServerId to GREENVPN_PREVIEW_SERVER_IDS and restart backend" } else { "do not add to preview automatically" })
)

$result = [ordered]@{
    ok = $true
    mode = if ($Apply) { "apply" } else { "dry-run" }
    serverId = $ServerId
    nodeIPv4 = $NodeIPv4
    title = if ([string]::IsNullOrWhiteSpace($Title)) { "Green VPN $Provider $City" } else { $Title }
    provider = $Provider
    country = $Country
    city = $City
    stableUntouched = $true
    addToPreviewRequested = [bool]$AddToPreview
    existingManagedEntry = if ($existing.Count -gt 0) {
        [ordered]@{
            found = $true
            status = $existing[0].status
            clientConfigProfile = $existing[0].clientConfigProfile
            isActive = $existing[0].isActive
            isPublic = $existing[0].isPublic
            clientConfigReady = $existing[0].clientConfigReady
        }
    } else {
        [ordered]@{ found = $false }
    }
    plannedActions = $dryRunActions
}

if (-not $Apply) {
    Write-GreenVpnJson -InputObject ([pscustomobject]$result)
    return
}

if (-not $ConfirmRemoteProvision) {
    throw "Refusing remote provisioning: pass both -Apply and -ConfirmRemoteProvision."
}

Wait-NodeSsh | Out-Null
$originKey = Ensure-OriginNodeSshKey
Add-OriginKeyToNode -PublicKey $originKey.publicKey
$wgPublicKey = Bootstrap-NodeWireGuard
Write-OriginNodeEnv -OriginKeyPath $originKey.privateKeyPath -WireGuardPublicKey $wgPublicKey
$catalogUpdate = Upsert-HiddenRemoteEntry -Status "healthy" -ClientConfigProfile "remote_ssh_wg0"

$provisioning = Invoke-AdminApi -Method "GET" -Path "/api/v1/admin/server-catalog/$ServerId/remote-provisioning-check"
if (-not [bool]$provisioning.ok) {
    throw "remote-provisioning-check failed for $ServerId."
}

$peerSmoke = Invoke-AdminApi -Method "POST" -Path "/api/v1/admin/server-catalog/$ServerId/remote-peer-smoke" -Body @{}
if (-not [bool]$peerSmoke.ok) {
    throw "remote-peer-smoke failed for $ServerId."
}

$clientSmoke = Invoke-AdminApi -Method "POST" -Path "/api/v1/admin/server-catalog/$ServerId/client-config-smoke" -Body @{}
if (-not [bool]$clientSmoke.ok) {
    throw "client-config-smoke failed for $ServerId."
}

if ($AddToPreview) {
    Add-NodeToPreview
    Start-Sleep -Seconds 5
}

$stableCatalog = Invoke-GreenVpnJson -Method GET -Uri "$($ApiBaseUrl.TrimEnd('/'))/api/v1/catalog/servers?channel=stable&appVersion=0.2.26" -TimeoutSec 30
$previewCatalog = Invoke-GreenVpnJson -Method GET -Uri "$($ApiBaseUrl.TrimEnd('/'))/api/v1/catalog/servers?channel=preview&appVersion=0.2.26-adgate-preview" -TimeoutSec 30
$stableIds = @($stableCatalog.catalog.servers | ForEach-Object { $_.id })
$previewIds = @($previewCatalog.catalog.servers | ForEach-Object { $_.id })

$result.applied = [ordered]@{
    catalogStatus = $catalogUpdate.entry.status
    clientConfigProfile = $catalogUpdate.entry.clientConfigProfile
    clientConfigReady = $catalogUpdate.entry.clientConfigReady
    isActive = $catalogUpdate.entry.isActive
    isPublic = $catalogUpdate.entry.isPublic
    remoteProvisioningOk = [bool]$provisioning.ok
    remotePeerSmokeOk = [bool]$peerSmoke.ok
    clientConfigSmokeOk = [bool]$clientSmoke.ok
    stableContainsNode = ($stableIds -contains $ServerId)
    previewContainsNode = ($previewIds -contains $ServerId)
}

if ($stableIds -contains $ServerId) {
    throw "Safety violation: stable catalog contains $ServerId."
}
if ($AddToPreview -and -not ($previewIds -contains $ServerId)) {
    throw "Preview allowlist was requested, but preview catalog does not contain $ServerId."
}

Write-GreenVpnJson -InputObject ([pscustomobject]$result)
