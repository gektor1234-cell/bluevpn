param(
    [Parameter(Mandatory = $false)]
    [string]$ServerId = "tw-nl-emergency-01",

    [Parameter(Mandatory = $false)]
    [string]$Name = "greenvpn-timeweb-nl-emergency-01",

    [Parameter(Mandatory = $false)]
    [string]$Title = "Green VPN Timeweb NL Emergency 01",

    [Parameter(Mandatory = $false)]
    [string]$NodeIPv4 = "",

    [Parameter(Mandatory = $false)]
    [int]$TimewebPresetId = 3344,

    [Parameter(Mandatory = $false)]
    [int]$TimewebOsId = 95,

    [Parameter(Mandatory = $false)]
    [switch]$CreatePaidServer,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmPaidCreate,

    [Parameter(Mandatory = $false)]
    [switch]$AcceptProductionBalanceRisk,

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

$quoteParams = @{
    Provider = "timeweb"
    Name = $Name
    TimewebPresetId = $TimewebPresetId
    TimewebOsId = $TimewebOsId
    ServerId = $ServerId
    Title = $Title
    Country = "Netherlands"
    City = "Amsterdam"
    QuotePrice = $true
}
$quote = Invoke-InfraJsonScript -ScriptName "new_test_vps_plan.ps1" -Parameters $quoteParams
$currentBalanceRub = [decimal]$quote.plan.currentBalanceRub
$quotedMonthlyRub = [decimal]$quote.plan.quotedPreset.price
$readyByBalance = $currentBalanceRub -ge $quotedMonthlyRub

$result = [ordered]@{
    ok = $true
    mode = if ($CreatePaidServer -or $ApplyBootstrap) { "apply-requested" } else { "dry-run" }
    serverId = $ServerId
    name = $Name
    title = $Title
    stableUntouched = $true
    target = [ordered]@{
        provider = "timeweb"
        country = "Netherlands"
        city = "Amsterdam"
        presetId = $TimewebPresetId
        osId = $TimewebOsId
    }
    quote = [ordered]@{
        readyByBalance = $readyByBalance
        currentBalanceRub = $currentBalanceRub
        quotedMonthlyRub = $quotedMonthlyRub
        minimumTopUpRub = [Math]::Max(0, [Math]::Ceiling($quotedMonthlyRub - $currentBalanceRub))
        productionBalanceRisk = "This is the same Timeweb account that hosts production Green VPN infrastructure."
    }
    createPaidServerRequested = [bool]$CreatePaidServer
    acceptProductionBalanceRisk = [bool]$AcceptProductionBalanceRisk
    applyBootstrapRequested = [bool]$ApplyBootstrap
    addToPreviewRequested = [bool]$AddToPreview
    nodeIPv4 = if ([string]::IsNullOrWhiteSpace($NodeIPv4)) { $null } else { $NodeIPv4 }
    plannedSteps = @(
        "Verify Timeweb API-visible balance is enough.",
        "Create paid NL VPS only with -CreatePaidServer -ConfirmPaidCreate -AcceptProductionBalanceRisk.",
        "Resolve the public IPv4 from API response or owner panel.",
        "Run prepare_remote_wireguard_node.ps1 dry-run or apply.",
        "Keep the node hidden unless -AddToPreview is explicitly passed.",
        "Verify stable catalog does not contain the new node."
    )
}

if (-not $CreatePaidServer -and -not $ApplyBootstrap -and [string]::IsNullOrWhiteSpace($NodeIPv4)) {
    $result.nextCommandIfOwnerAcceptsRisk = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_timeweb_nl_preview.ps1 -CreatePaidServer -ConfirmPaidCreate -AcceptProductionBalanceRisk"
    $result.nextCommandWithKnownIp = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_timeweb_nl_preview.ps1 -NodeIPv4 <public-ip> -ApplyBootstrap -ConfirmRemoteProvision -AddToPreview"
    Write-GreenVpnJson -InputObject ([pscustomobject]$result)
    return
}

if ($CreatePaidServer) {
    if (-not $ConfirmPaidCreate) {
        throw "Refusing paid create: pass both -CreatePaidServer and -ConfirmPaidCreate."
    }
    if (-not $AcceptProductionBalanceRisk) {
        throw "Refusing paid Timeweb create: pass -AcceptProductionBalanceRisk because this account hosts production infrastructure."
    }
    if (-not $readyByBalance) {
        throw "Refusing paid create: Timeweb API-visible balance is $currentBalanceRub RUB, quoted monthly price is $quotedMonthlyRub RUB."
    }

    $createParams = $quoteParams.Clone()
    $createParams.Remove("QuotePrice")
    $createParams.Apply = $true
    $created = Invoke-InfraJsonScript -ScriptName "new_test_vps_plan.ps1" -Parameters $createParams
    $result.created = $created.plan.providerResponse
    if ([string]::IsNullOrWhiteSpace($NodeIPv4)) {
        $candidateIp = Find-PublicIPv4 -Object $created.plan.providerResponse
        if ($candidateIp) {
            $NodeIPv4 = $candidateIp
            $result.nodeIPv4 = $NodeIPv4
            $result.nodeIPv4Source = "timeweb_create_response"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($NodeIPv4)) {
    $result.ok = $false
    $result.needsOwnerAction = [ordered]@{
        reason = "Timeweb API response did not expose the new public IPv4."
        action = "Open the new Timeweb server in the panel and copy its public IPv4."
        resumeCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_timeweb_nl_preview.ps1 -NodeIPv4 <public-ip> -ApplyBootstrap -ConfirmRemoteProvision -AddToPreview"
    }
    Write-GreenVpnJson -InputObject ([pscustomobject]$result)
    return
}

$prepareParams = @{
    ServerId = $ServerId
    NodeIPv4 = $NodeIPv4
    Title = $Title
    Country = "NL"
    City = "Amsterdam"
    Provider = "timeweb"
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
