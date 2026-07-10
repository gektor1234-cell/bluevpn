param(
    [Parameter(Mandatory = $false)]
    [switch]$SkipPreviewSmoke,

    [Parameter(Mandatory = $false)]
    [int]$TimewebNlPresetId = 3344,

    [Parameter(Mandatory = $false)]
    [int]$TimewebKzPresetId = 2937
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

    return (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Get-ProviderStatus {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Providers,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $match = @($Providers | Where-Object { $_.provider -eq $Name } | Select-Object -First 1)
    if ($match.Count -eq 0) {
        return [pscustomobject]@{
            status = "missing"
        }
    }
    return $match[0]
}

function Get-TimewebQuote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$PresetId
    )

    return Invoke-InfraJsonScript -ScriptName "new_test_vps_plan.ps1" -Parameters @{
        Provider = "timeweb"
        Name = $Name
        TimewebPresetId = $PresetId
        TimewebOsId = 95
        QuotePrice = $true
    }
}

$providerInventory = Invoke-InfraJsonScript -ScriptName "test_provider_api.ps1" -Parameters @{
    Provider = "all"
    IncludeInventory = $true
}

$ruvdsAccessCandidates = Invoke-InfraJsonScript -ScriptName "check_ruvds_access_candidates.ps1"
$ruvdsGate = Invoke-InfraJsonScript -ScriptName "ruvds_zurich_gate.ps1"
$timewebNlQuote = Get-TimewebQuote -Name "greenvpn-timeweb-nl-test-next" -PresetId $TimewebNlPresetId
$timewebKzQuote = Get-TimewebQuote -Name "greenvpn-timeweb-kz-test-next" -PresetId $TimewebKzPresetId

$previewSmoke = $null
if (-not $SkipPreviewSmoke) {
    $previewSmoke = Invoke-InfraJsonScript -ScriptName "check_preview_vpn_nodes.ps1"
}

$timeweb = Get-ProviderStatus -Providers $providerInventory.providers -Name "timeweb"
$ruvds = Get-ProviderStatus -Providers $providerInventory.providers -Name "ruvds"
$serverspace = Get-ProviderStatus -Providers $providerInventory.providers -Name "serverspace"

$timewebNlReadyByBalance = [decimal]$timewebNlQuote.plan.currentBalanceRub -ge [decimal]$timewebNlQuote.plan.quotedPreset.price
$timewebKzReadyByBalance = [decimal]$timewebKzQuote.plan.currentBalanceRub -ge [decimal]$timewebKzQuote.plan.quotedPreset.price

$result = [ordered]@{
    ok = $true
    generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    stablePolicy = [ordered]@{
        stableMustRemainUntouched = $true
        newNodesGoToPreviewFirst = $true
        friendlyLinnetNoTouch = $true
    }
    providers = [ordered]@{
        timeweb = [ordered]@{
            status = $timeweb.status
            serverCount = $timeweb.details.serverCount
            balanceRub = $timewebNlQuote.plan.currentBalanceRub
            currentServers = @($timeweb.details.servers | ForEach-Object {
                [ordered]@{
                    id = $_.id
                    name = $_.name
                    status = $_.status
                    mainIp = $_.mainIp
                }
            })
        }
        ruvds = [ordered]@{
            status = $ruvds.status
            serverCount = $ruvds.details.serverCount
            balanceRub = $ruvds.details.balanceAmount
            accessCandidates = [ordered]@{
                count = $ruvdsAccessCandidates.candidateCount
                readyCandidateFound = $ruvdsAccessCandidates.readyCandidateFound
                requiredBalanceRub = $ruvdsAccessCandidates.requiredBalanceRub
                requiredSshKeyName = $ruvdsAccessCandidates.requiredSshKeyName
                candidates = @($ruvdsAccessCandidates.candidates | ForEach-Object {
                    [ordered]@{
                        sources = @($_.sources)
                        status = $_.status
                        balanceRub = if ($_.PSObject.Properties.Name -contains "balanceRub") { $_.balanceRub } else { $null }
                        serverCount = if ($_.PSObject.Properties.Name -contains "serverCount") { $_.serverCount } else { $null }
                        requiredSshKeyPresent = if ($_.PSObject.Properties.Name -contains "requiredSshKeyPresent") { $_.requiredSshKeyPresent } else { $false }
                        readyForZurich = $_.readyForZurich
                        missing = if ($_.PSObject.Properties.Name -contains "missing") { @($_.missing) } else { @("api_error") }
                    }
                })
            }
            currentServers = @($ruvds.details.servers | ForEach-Object {
                [ordered]@{
                    id = $_.id
                    status = $_.status
                    datacenter = $_.datacenter
                }
            })
        }
        serverspace = [ordered]@{
            status = $serverspace.status
            serverCount = $serverspace.details.serverCount
            balance = $serverspace.details.balance
            currency = $serverspace.details.currency
        }
    }
    createOptions = [ordered]@{
        ruvdsZurich = [ordered]@{
            readyToCreate = [bool]$ruvdsGate.quote.readyToCreate
            currentBalanceRub = $ruvdsGate.quote.currentBalanceRub
            quotedCostRub = $ruvdsGate.quote.quotedCostRub
            minimumTopUpRub = $ruvdsGate.quote.minimumTopUpRub
            commandWhenReady = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\continue_ruvds_preview_rollout.ps1 -CreateWhenReady -ConfirmPaidCreate"
        }
        timewebNetherlands = [ordered]@{
            readyByBalance = $timewebNlReadyByBalance
            recommendedForEmergencyOnly = $true
            reason = "Creating this node would consume almost all current Timeweb production balance."
            currentBalanceRub = $timewebNlQuote.plan.currentBalanceRub
            quotedMonthlyRub = $timewebNlQuote.plan.quotedPreset.price
            presetId = $timewebNlQuote.plan.quotedPreset.id
            location = $timewebNlQuote.plan.quotedPreset.location
            dryRunCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_timeweb_nl_preview.ps1"
            commandIfOwnerAcceptsRisk = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\infra\rollout_timeweb_nl_preview.ps1 -CreatePaidServer -ConfirmPaidCreate -AcceptProductionBalanceRisk"
        }
        timewebKazakhstan = [ordered]@{
            readyByBalance = $timewebKzReadyByBalance
            recommended = $false
            reason = "Existing KZ node is already in preview. Do not create more KZ before real-device testing confirms value."
            currentBalanceRub = $timewebKzQuote.plan.currentBalanceRub
            quotedMonthlyRub = $timewebKzQuote.plan.quotedPreset.price
            presetId = $timewebKzQuote.plan.quotedPreset.id
            location = $timewebKzQuote.plan.quotedPreset.location
        }
    }
    previewSmoke = if ($null -eq $previewSmoke) {
        [ordered]@{
            skipped = $true
        }
    } else {
        [ordered]@{
            skipped = $false
            ok = $previewSmoke.ok
            serverCount = $previewSmoke.serverCount
            servers = @($previewSmoke.servers | ForEach-Object {
                [ordered]@{
                    serverId = $_.serverId
                    checksOk = $_.checksOk
                    inStable = $_.publicCatalog.inStable
                    inPreview = $_.publicCatalog.inPreview
                    status = $_.catalog.status
                    clientConfigReady = $_.catalog.clientConfigReady
                }
            })
        }
    }
    nextActions = @(
        "If RUVDS browser balance is funded but accessCandidates.readyCandidateFound is false, put a token from that same funded account into GREENVPN_RUVDS_API_KEY, GREENVPN_RUVDS_API_KEY_*, or GREENVPN_RUVDS_API_KEYS and rerun this script.",
        "When ruvdsZurich.readyToCreate is true, run continue_ruvds_preview_rollout.ps1 with -CreateWhenReady -ConfirmPaidCreate; if the API does not return IPv4, rerun rollout_ruvds_zurich_preview.ps1 with -NodeIPv4 <public-ip> -ApplyBootstrap -ConfirmRemoteProvision -AddToPreview.",
        "Do not spend Timeweb NL balance unless the owner explicitly accepts the production-balance risk; use rollout_timeweb_nl_preview.ps1 for the protected emergency path.",
        "Keep KZ in preview only until real-device testing confirms it is useful; do not publish KZ to stable yet."
    )
}

Write-GreenVpnJson -InputObject ([pscustomobject]$result)
