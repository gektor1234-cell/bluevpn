param(
    [Parameter(Mandatory = $false)]
    [string]$SecretsPath = "",

    [Parameter(Mandatory = $false)]
    [string]$Name = "greenvpn-ruvds-zurich-test-01",

    [Parameter(Mandatory = $false)]
    [string]$ServerId = "ruvds-zurich-test-01",

    [Parameter(Mandatory = $false)]
    [string]$Title = "Green VPN RUVDS Zurich Test 01",

    [Parameter(Mandatory = $false)]
    [switch]$ApplyWhenReady,

    [Parameter(Mandatory = $false)]
    [switch]$ConfirmPaidCreate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\provider_api_common.ps1"

function Invoke-RuvdsZurichPlan {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Apply
    )

    $planParams = @{
        Provider = "ruvds"
        SecretsPath = $SecretsPath
        Name = $Name
        LocationId = "2"
        ImageId = "52"
        Cpu = 1
        RamMb = 1024
        DiskGb = 20
        PaymentPeriod = 2
        RuvdsTariffId = 41
        RuvdsDriveTariffId = 9
        ServerId = $ServerId
        Title = $Title
        Country = "Switzerland"
        City = "Zurich"
    }

    if ($Apply) {
        $planParams.Apply = $true
    } else {
        $planParams.QuotePrice = $true
    }

    $jsonText = & "$PSScriptRoot\new_test_vps_plan.ps1" @planParams
    return ($jsonText | ConvertFrom-Json)
}

$quote = Invoke-RuvdsZurichPlan
$plan = $quote.plan

$currentBalance = [decimal]$plan.currentBalanceRub
$quotedCost = [decimal]$plan.quotedCostRub
$minimumTopUp = [decimal]$plan.minimumTopUpRub
$ready = $currentBalance -ge $quotedCost

$result = [ordered]@{
    localConfigFile = $quote.localConfigFile
    target = [ordered]@{
        provider = "ruvds"
        location = "ZUR1 Zurich"
        serverId = $ServerId
        title = $Title
    }
    quote = [ordered]@{
        currentBalanceRub = $currentBalance
        quotedCostRub = $quotedCost
        minimumTopUpRub = $minimumTopUp
        readyToCreate = $ready
    }
    safety = [ordered]@{
        stableUntouched = $true
        createsPaidServerOnlyWithApplyWhenReadyAndConfirmPaidCreate = $true
    }
}

if ($ApplyWhenReady) {
    if (-not $ConfirmPaidCreate) {
        throw "Refusing paid create: pass both -ApplyWhenReady and -ConfirmPaidCreate."
    }

    if (-not $ready) {
        throw "Refusing paid create: RUVDS API-visible balance is $currentBalance RUB, quoted cost is $quotedCost RUB."
    }

    $created = Invoke-RuvdsZurichPlan -Apply
    $result.created = $created.plan.providerResponse
}

Write-GreenVpnJson -InputObject ([pscustomobject]$result)
