param(
    [Parameter(Mandatory = $false)]
    [string]$SecretsPath = "",

    [Parameter(Mandatory = $false)]
    [string]$ServerId = "ruvds-zurich-test-01",

    [Parameter(Mandatory = $false)]
    [string]$Name = "greenvpn-ruvds-zurich-test-01",

    [Parameter(Mandatory = $false)]
    [string]$Title = "Green VPN RUVDS Zurich Test 01",

    [Parameter(Mandatory = $false)]
    [string]$NodeIPv4 = "",

    [Parameter(Mandatory = $false)]
    [switch]$CreatePaidServer,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmPaidCreate,

    [Parameter(Mandatory = $false)]
    [switch]$ApplyBootstrap,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmRemoteProvision,

    [Parameter(Mandatory = $false)]
    [switch]$AddToPreview
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\provider_api_common.ps1"

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

function Invoke-InfraJsonScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{}
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Infra script not found: $scriptPath"
    }

    $raw = & $scriptPath @Parameters
    return (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Find-PublicIPv4 {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Object
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [string]) {
        if ($Object -match '^(?!(?:10|127)\.)(?!(?:172\.(?:1[6-9]|2[0-9]|3[0-1]))\.)(?!(?:192\.168)\.)(?:[0-9]{1,3}\.){3}[0-9]{1,3}$') {
            return $Object
        }
        return $null
    }

    if ($Object -is [ValueType]) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in @("mainIp", "main_ipv4", "publicIp", "public_ip", "ip", "ipv4", "network_v4")) {
            if ($Object.Contains($key)) {
                $found = Find-PublicIPv4 -Object $Object[$key]
                if ($found) {
                    return $found
                }
            }
        }
        foreach ($key in $Object.Keys) {
            $found = Find-PublicIPv4 -Object $Object[$key]
            if ($found) {
                return $found
            }
        }
        return $null
    }

    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string])) {
        foreach ($item in $Object) {
            $found = Find-PublicIPv4 -Object $item
            if ($found) {
                return $found
            }
        }
        return $null
    }

    foreach ($prop in $Object.PSObject.Properties) {
        if ($prop.Name -match '^(mainIp|main_ipv4|publicIp|public_ip|ip|ipv4|network_v4)$') {
            $found = Find-PublicIPv4 -Object $prop.Value
            if ($found) {
                return $found
            }
        }
    }
    foreach ($prop in $Object.PSObject.Properties) {
        $found = Find-PublicIPv4 -Object $prop.Value
        if ($found) {
            return $found
        }
    }

    return $null
}

Assert-GreenVpnSafeToken -Name "ServerId" -Value $ServerId -Pattern "^[a-z0-9][a-z0-9_.-]{2,79}$"
Assert-GreenVpnSafeToken -Name "Name" -Value $Name -Pattern "^[a-zA-Z0-9][a-zA-Z0-9_.-]{2,79}$"
if (-not [string]::IsNullOrWhiteSpace($NodeIPv4)) {
    Assert-GreenVpnSafeToken -Name "NodeIPv4" -Value $NodeIPv4 -Pattern "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$"
}

$gateParams = @{
    SecretsPath = $SecretsPath
    Name = $Name
    ServerId = $ServerId
    Title = $Title
}
$gate = Invoke-InfraJsonScript -ScriptName "ruvds_zurich_gate.ps1" -Parameters $gateParams

$result = [ordered]@{
    ok = $true
    mode = if ($CreatePaidServer -or $ApplyBootstrap) { "apply-requested" } else { "dry-run" }
    serverId = $ServerId
    name = $Name
    title = $Title
    stableUntouched = $true
    target = $gate.target
    quote = $gate.quote
    createPaidServerRequested = [bool]$CreatePaidServer
    applyBootstrapRequested = [bool]$ApplyBootstrap
    addToPreviewRequested = [bool]$AddToPreview
    nodeIPv4 = if ([string]::IsNullOrWhiteSpace($NodeIPv4)) { $null } else { $NodeIPv4 }
    plannedSteps = @(
        "Verify RUVDS API-visible balance is enough.",
        "Create paid Zurich VPS only with -CreatePaidServer -ConfirmPaidCreate.",
        "Resolve the public IPv4 from API response or owner panel.",
        "Run prepare_remote_wireguard_node.ps1 dry-run or apply.",
        "Keep the node hidden unless -AddToPreview is explicitly passed.",
        "Verify stable catalog does not contain the new node."
    )
}

if (-not $CreatePaidServer -and -not $ApplyBootstrap -and [string]::IsNullOrWhiteSpace($NodeIPv4)) {
    $result.nextCommandWhenRuvdsReady = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1 -CreatePaidServer -ConfirmPaidCreate -ApplyBootstrap -ConfirmRemoteProvision -AddToPreview"
    $result.nextCommandWithKnownIp = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1 -NodeIPv4 <public-ip> -ApplyBootstrap -ConfirmRemoteProvision -AddToPreview"
    Write-GreenVpnJson -InputObject ([pscustomobject]$result)
    return
}

if ($CreatePaidServer) {
    if (-not $ConfirmPaidCreate) {
        throw "Refusing paid create: pass both -CreatePaidServer and -ConfirmPaidCreate."
    }
    if (-not [bool]$gate.quote.readyToCreate) {
        throw "Refusing paid create: RUVDS API-visible balance is $($gate.quote.currentBalanceRub) RUB, quoted cost is $($gate.quote.quotedCostRub) RUB."
    }

    $createParams = $gateParams.Clone()
    $createParams.ApplyWhenReady = $true
    $createParams.ConfirmPaidCreate = $true
    $created = Invoke-InfraJsonScript -ScriptName "ruvds_zurich_gate.ps1" -Parameters $createParams
    $result.created = $created.created
    if ([string]::IsNullOrWhiteSpace($NodeIPv4)) {
        $candidateIp = Find-PublicIPv4 -Object $created.created
        if ($candidateIp) {
            $NodeIPv4 = $candidateIp
            $result.nodeIPv4 = $NodeIPv4
            $result.nodeIPv4Source = "ruvds_create_response"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($NodeIPv4)) {
    $result.ok = $false
    $result.needsOwnerAction = [ordered]@{
        reason = "RUVDS API response did not expose the new public IPv4."
        action = "Open the new RUVDS server in the panel and copy its public IPv4."
        resumeCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_ruvds_zurich_preview.ps1 -NodeIPv4 <public-ip> -ApplyBootstrap -ConfirmRemoteProvision -AddToPreview"
    }
    Write-GreenVpnJson -InputObject ([pscustomobject]$result)
    return
}

$prepareParams = @{
    ServerId = $ServerId
    NodeIPv4 = $NodeIPv4
    Title = $Title
    Country = "CH"
    City = "Zurich"
    Provider = "ruvds"
}
if ($ApplyBootstrap) {
    if (-not $ConfirmRemoteProvision) {
        throw "Refusing remote provisioning: pass both -ApplyBootstrap and -ConfirmRemoteProvision."
    }
    $prepareParams.Apply = $true
    $prepareParams.ConfirmRemoteProvision = $true
    if ($AddToPreview) {
        $prepareParams.AddToPreview = $true
    }
}

$prepared = Invoke-InfraJsonScript -ScriptName "prepare_remote_wireguard_node.ps1" -Parameters $prepareParams
$result.nodeIPv4 = $NodeIPv4
$result.prepareRemoteWireGuardNode = $prepared

if ($ApplyBootstrap -and $AddToPreview) {
    $smoke = Invoke-InfraJsonScript -ScriptName "check_preview_vpn_nodes.ps1" -Parameters @{
        ServerId = @($ServerId)
    }
    $result.previewSmoke = $smoke
}

Write-GreenVpnJson -InputObject ([pscustomobject]$result)
