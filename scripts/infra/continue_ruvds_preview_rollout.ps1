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
    [switch]$CreateWhenReady,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmPaidCreate,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPostChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\provider_api_common.ps1"

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
    $text = ($raw | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Infra script returned empty output: $ScriptName"
    }

    return ($text | ConvertFrom-Json)
}

function New-TargetParams {
    $params = @{
        SecretsPath = $SecretsPath
        ServerId = $ServerId
        Name = $Name
        Title = $Title
    }

    if ([string]::IsNullOrWhiteSpace($SecretsPath)) {
        $params.Remove("SecretsPath")
    }

    return $params
}

$targetParams = New-TargetParams
$accessParams = @{}
if (-not [string]::IsNullOrWhiteSpace($SecretsPath)) {
    $accessParams.SecretsPath = $SecretsPath
}

$access = Invoke-InfraJsonScript -ScriptName "check_ruvds_access_candidates.ps1" -Parameters $accessParams
$gate = Invoke-InfraJsonScript -ScriptName "ruvds_zurich_gate.ps1" -Parameters $targetParams
$dryRun = Invoke-InfraJsonScript -ScriptName "rollout_ruvds_zurich_preview.ps1" -Parameters $targetParams

$ready = [bool]$access.readyCandidateFound -and [bool]$gate.quote.readyToCreate
$result = [ordered]@{
    ok = $true
    mode = if ($CreateWhenReady) { "create-when-ready" } else { "dry-run" }
    generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    stableUntouched = $true
    target = [ordered]@{
        provider = "ruvds"
        serverId = $ServerId
        name = $Name
        title = $Title
        rollout = "preview-only"
    }
    readiness = [ordered]@{
        ready = $ready
        readyCandidateFound = [bool]$access.readyCandidateFound
        candidateCount = $access.candidateCount
        currentBalanceRub = $gate.quote.currentBalanceRub
        quotedCostRub = $gate.quote.quotedCostRub
        minimumTopUpRub = $gate.quote.minimumTopUpRub
        readyToCreate = [bool]$gate.quote.readyToCreate
    }
    dryRun = $dryRun
    createWhenReadyRequested = [bool]$CreateWhenReady
}

if (-not $ready) {
    $result.status = "waiting_for_funded_ruvds_api_token"
    $result.ownerAction = [ordered]@{
        reason = "The configured RUVDS API credentials do not expose enough balance for the Zurich preview node."
        currentApiVisibleBalanceRub = $gate.quote.currentBalanceRub
        requiredRub = $gate.quote.quotedCostRub
        file = "D:\GreenVPN_Secrets\provider_api.local.ps1"
        addExample = '$env:GREENVPN_RUVDS_API_KEY_FUNDED = "PASTE_RUVDS_API_V2_TOKEN_HERE"'
        links = @(
            "https://ruvds.com/my/settings/api"
        )
    }
    $result.nextLocalCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\continue_ruvds_preview_rollout.ps1"

    Write-GreenVpnJson -InputObject ([pscustomobject]$result)
    return
}

if (-not $CreateWhenReady) {
    $result.status = "ready_for_paid_preview_rollout"
    $result.nextLocalCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\continue_ruvds_preview_rollout.ps1 -CreateWhenReady -ConfirmPaidCreate"

    Write-GreenVpnJson -InputObject ([pscustomobject]$result)
    return
}

if (-not $ConfirmPaidCreate) {
    throw "Refusing paid create: pass both -CreateWhenReady and -ConfirmPaidCreate."
}

$rolloutParams = New-TargetParams
$rolloutParams.CreatePaidServer = $true
$rolloutParams.ConfirmPaidCreate = $true
$rolloutParams.ApplyBootstrap = $true
$rolloutParams.ConfirmRemoteProvision = $true
$rolloutParams.AddToPreview = $true

$rollout = Invoke-InfraJsonScript -ScriptName "rollout_ruvds_zurich_preview.ps1" -Parameters $rolloutParams
$result.rollout = $rollout
$result.ok = [bool]$rollout.ok

if (-not [bool]$rollout.ok) {
    $result.status = "needs_owner_ip_from_provider_panel"
    if ($rollout.PSObject.Properties.Name -contains "needsOwnerAction") {
        $result.ownerAction = $rollout.needsOwnerAction
    }

    Write-GreenVpnJson -InputObject ([pscustomobject]$result)
    return
}

$result.status = "preview_rollout_complete"

if (-not $SkipPostChecks) {
    $result.postChecks = [ordered]@{
        previewSmoke = Invoke-InfraJsonScript -ScriptName "check_preview_vpn_nodes.ps1"
        downloads = Invoke-InfraJsonScript -ScriptName "..\ops\check_public_download_manifests.ps1"
    }
}

Write-GreenVpnJson -InputObject ([pscustomobject]$result)
