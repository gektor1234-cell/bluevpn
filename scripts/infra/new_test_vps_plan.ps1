param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("serverspace", "timeweb", "ruvds", "hostkey")]
    [string]$Provider = "serverspace",

    [Parameter(Mandatory = $false)]
    [string]$SecretsPath = "",

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
    [ValidateRange(0, 5)]
    [int]$PaymentPeriod = 2,

    [Parameter(Mandatory = $false)]
    [int]$RuvdsTariffId = 41,

    [Parameter(Mandatory = $false)]
    [int]$RuvdsDriveTariffId = 9,

    [Parameter(Mandatory = $false)]
    [string]$RuvdsSshKeyId = "",

    [Parameter(Mandatory = $false)]
    [int]$TimewebPresetId = 2937,

    [Parameter(Mandatory = $false)]
    [int]$TimewebOsId = 95,

    [Parameter(Mandatory = $false)]
    [int]$TimewebSshKeyId = 0,

    [Parameter(Mandatory = $false)]
    [switch]$TimewebDdosGuard,

    [Parameter(Mandatory = $false)]
    [switch]$TimewebLocalNetwork,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 16)]
    [int]$IpCount = 1,

    [Parameter(Mandatory = $false)]
    [switch]$QuotePrice,

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

if ($Provider -eq "ruvds" -and $Country -eq "Netherlands" -and $City -eq "Amsterdam") {
    switch ([string]$LocationId) {
        "2" {
            $Country = "Switzerland"
            $City = "Zurich"
        }
        "3" {
            $Country = "United Kingdom"
            $City = "London"
        }
        "21" {
            $Country = "Germany"
            $City = "Frankfurt"
        }
        "29" {
            $Country = "Netherlands"
            $City = "Amsterdam"
        }
        "34" {
            $Country = "Kazakhstan"
            $City = "Almaty"
        }
        "36" {
            $Country = "Kazakhstan"
            $City = "Astana"
        }
    }
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

function New-RuvdsPayload {
    $ramGb = [Math]::Round(($RamMb / 1024.0), 2)

    $payload = [ordered]@{
        datacenter = [int]$LocationId
        tariff_id = $RuvdsTariffId
        os_id = [int]$ImageId
        payment_period = $PaymentPeriod
        cpu = $Cpu
        ram = $ramGb
        drive = $DiskGb
        drive_tariff_id = $RuvdsDriveTariffId
        ip = $IpCount
        computer_name = $Name
        user_comment = "Green VPN hidden test node. Do not publish before WireGuard bootstrap and smoke tests."
    }

    if (-not [string]::IsNullOrWhiteSpace($RuvdsSshKeyId)) {
        $payload.ssh_key_id = $RuvdsSshKeyId
    }

    return $payload
}

function New-TimewebPayload {
    $payload = [ordered]@{
        name = $Name
        comment = "Green VPN hidden test node. Do not publish before WireGuard bootstrap and smoke tests."
        preset_id = $TimewebPresetId
        os_id = $TimewebOsId
        bandwidth = $BandwidthMbps
        is_ddos_guard = [bool]$TimewebDdosGuard
        is_local_network = [bool]$TimewebLocalNetwork
    }

    if ($TimewebSshKeyId -gt 0) {
        $payload.ssh_keys_ids = @($TimewebSshKeyId)
    }

    return $payload
}

function Get-TimewebDefaultSshKeyId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    $keys = Invoke-GreenVpnJson `
        -Method GET `
        -Uri "https://api.timeweb.cloud/api/v1/ssh-keys" `
        -Headers @{ Authorization = "Bearer $Token" }

    $items = @($keys.ssh_keys)
    $default = @($items | Where-Object { $_.is_default -eq $true } | Select-Object -First 1)
    if ($default.Count -gt 0) {
        return [int]$default[0].id
    }

    $named = @($items | Where-Object { $_.name -eq "GreenVPN Codex PC key" } | Select-Object -First 1)
    if ($named.Count -gt 0) {
        return [int]$named[0].id
    }

    return 0
}

function Get-TimewebPreset {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [int]$PresetId
    )

    $presets = Invoke-GreenVpnJson `
        -Method GET `
        -Uri "https://api.timeweb.cloud/api/v1/presets/servers" `
        -Headers @{ Authorization = "Bearer $Token" }

    $items = @($presets.server_presets)
    $match = @($items | Where-Object { [int]$_.id -eq $PresetId } | Select-Object -First 1)
    if ($match.Count -eq 0) {
        throw "Timeweb preset '$PresetId' was not found."
    }

    return $match[0]
}

function Get-TimewebFinances {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    return Invoke-GreenVpnJson `
        -Method GET `
        -Uri "https://api.timeweb.cloud/api/v1/account/finances" `
        -Headers @{ Authorization = "Bearer $Token" }
}

function Get-RuvdsDefaultSshKeyId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    $keys = Invoke-GreenVpnJson `
        -Method GET `
        -Uri "https://api.ruvds.com/v2/ssh_keys" `
        -Headers @{ Authorization = "Bearer $Token" }

    $items = @($keys.ssh_keys)
    $match = @($items | Where-Object { $_.name -eq "greenvpn-codex-local" } | Select-Object -First 1)
    if ($match.Count -eq 0) {
        return $null
    }

    return $match[0].ssh_key_id
}

function Get-GreenVpnEnvironmentSecretValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    foreach ($scope in @("Process", "User", "Machine")) {
        $value = [Environment]::GetEnvironmentVariable($Name, $scope)
        if (-not (Test-GreenVpnPlaceholderSecret -Value $value)) {
            return $value
        }
    }

    return $null
}

function Add-RuvdsCredentialCandidate {
    param(
        [Parameter(Mandatory = $false)]
        [System.Collections.ArrayList]$Candidates,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Token
    )

    if (Test-GreenVpnPlaceholderSecret -Value $Token) {
        return
    }

    [void]$Candidates.Add([pscustomobject]@{
        source = $Source
        token = $Token.Trim()
    })
}

function Add-RuvdsCredentialListCandidate {
    param(
        [Parameter(Mandatory = $false)]
        [System.Collections.ArrayList]$Candidates,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Value
    )

    if (Test-GreenVpnPlaceholderSecret -Value $Value) {
        return
    }

    $index = 0
    foreach ($part in ($Value -split '[,;\r\n]+')) {
        $trimmed = $part.Trim()
        if (Test-GreenVpnPlaceholderSecret -Value $trimmed) {
            continue
        }
        $index += 1
        Add-RuvdsCredentialCandidate -Candidates $Candidates -Source "${Source}[$index]" -Token $trimmed
    }
}

function Get-RuvdsApiCredentialCandidates {
    $rawCandidates = [System.Collections.ArrayList]::new()

    Add-RuvdsCredentialCandidate `
        -Candidates $rawCandidates `
        -Source "GREENVPN_RUVDS_API_KEY" `
        -Token (Get-GreenVpnEnvironmentSecretValue -Name "GREENVPN_RUVDS_API_KEY")

    Add-RuvdsCredentialListCandidate `
        -Candidates $rawCandidates `
        -Source "GREENVPN_RUVDS_API_KEYS" `
        -Value (Get-GreenVpnEnvironmentSecretValue -Name "GREENVPN_RUVDS_API_KEYS")

    $processEnv = [Environment]::GetEnvironmentVariables("Process")
    foreach ($name in @($processEnv.Keys | Sort-Object)) {
        $nameText = [string]$name
        if ($nameText -eq "GREENVPN_RUVDS_API_KEY" -or $nameText -eq "GREENVPN_RUVDS_API_KEYS") {
            continue
        }
        if ($nameText -match '^GREENVPN_RUVDS_API_KEY_[A-Z0-9_]+$') {
            Add-RuvdsCredentialCandidate -Candidates $rawCandidates -Source $nameText -Token ([string]$processEnv[$name])
        }
    }

    $unique = [ordered]@{}
    foreach ($candidate in $rawCandidates) {
        if (Test-GreenVpnPlaceholderSecret -Value $candidate.token) {
            continue
        }

        if (-not $unique.Contains($candidate.token)) {
            $unique[$candidate.token] = [ordered]@{
                sources = @()
                token = $candidate.token
            }
        }
        $unique[$candidate.token].sources += $candidate.source
    }

    return @($unique.Values | ForEach-Object {
        [pscustomobject]@{
            sources = @($_.sources)
            token = $_.token
        }
    })
}

function Select-RuvdsApiCredential {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Candidates
    )

    if (@($Candidates).Count -eq 0) {
        throw "Required secret 'GREENVPN_RUVDS_API_KEY' is not configured."
    }

    $results = @()
    foreach ($candidate in $Candidates) {
        try {
            $candidateBalance = Invoke-GreenVpnJson `
                -Method GET `
                -Uri "https://api.ruvds.com/v2/balance" `
                -Headers @{ Authorization = "Bearer $($candidate.token)" }

            $candidateSshKeyId = Get-RuvdsDefaultSshKeyId -Token $candidate.token

            $results += [pscustomobject]@{
                ok = $true
                sources = @($candidate.sources)
                token = $candidate.token
                balance = $candidateBalance
                balanceAmount = [decimal]$candidateBalance.amount
                sshKeyId = $candidateSshKeyId
                sshKeyPresent = (-not [string]::IsNullOrWhiteSpace($candidateSshKeyId))
            }
        } catch {
            $results += [pscustomobject]@{
                ok = $false
                sources = @($candidate.sources)
                token = $candidate.token
                error = (Protect-GreenVpnString -Value $_.Exception.Message)
                balanceAmount = [decimal]0
                sshKeyId = $null
                sshKeyPresent = $false
            }
        }
    }

    $valid = @($results | Where-Object { $_.ok })
    if ($valid.Count -eq 0) {
        $errors = @($results | ForEach-Object { "$($_.sources -join '+'): $($_.error)" })
        throw "No configured RUVDS API credential passed balance/SSH checks. $($errors -join '; ')"
    }

    return @($valid |
        Sort-Object `
            @{ Expression = { if ($_.sshKeyPresent) { 1 } else { 0 } }; Descending = $true },
            @{ Expression = { $_.balanceAmount }; Descending = $true } |
        Select-Object -First 1)[0]
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
        protocol = "wireguard_udp"
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
        $plan.endpoint = "POST https://api.timeweb.cloud/api/v1/servers"
        $apiKey = $null
        $timewebPreset = $null
        $timewebFinances = $null
        if ($QuotePrice -or $Apply) {
            $apiKey = Get-GreenVpnSecret -Name "GREENVPN_TIMEWEB_TOKEN" -Required
            if ($TimewebSshKeyId -le 0) {
                $TimewebSshKeyId = Get-TimewebDefaultSshKeyId -Token $apiKey
            }
            $timewebPreset = Get-TimewebPreset -Token $apiKey -PresetId $TimewebPresetId
            $timewebFinances = Get-TimewebFinances -Token $apiKey
        }

        $plan.payload = New-TimewebPayload
        $plan.defaults = [ordered]@{
            recommendedFirstPreset = "2937 / Cloud KZ-40 2023 / kz-1 / 611 RUB per month"
            stableLikeNetherlandsPreset = "3344 / Cloud NL-40 / nl-1 / 1600 RUB per month"
            os = "$TimewebOsId / Debian 12 when value is 95"
            sshKey = if ($TimewebSshKeyId -gt 0) { "GreenVPN Codex PC key" } else { "not set" }
        }

        if ($QuotePrice -and -not $Apply) {
            $plan.dryRun = $true
            $plan.action = "quote_test_vps_price"
            $plan.currentBalanceRub = $timewebFinances.finances.balance
            $plan.currentCurrency = $timewebFinances.finances.currency
            $plan.quotedPreset = [ordered]@{
                id = $timewebPreset.id
                name = $timewebPreset.description
                location = $timewebPreset.location
                price = $timewebPreset.price
                cpu = $timewebPreset.cpu
                ram = $timewebPreset.ram
                disk = $timewebPreset.disk
                bandwidth = $timewebPreset.bandwidth
            }
            $plan.minimumTopUpRub = [Math]::Max(0, [Math]::Ceiling(([decimal]$timewebPreset.price) - ([decimal]$timewebFinances.finances.balance)))
        }

        if ($Apply) {
            $plan.dryRun = $false
            $created = Invoke-GreenVpnJson `
                -Method POST `
                -Uri "https://api.timeweb.cloud/api/v1/servers" `
                -Headers @{ Authorization = "Bearer $apiKey" } `
                -Body $plan.payload
            $plan.providerResponse = $created
        }
    }
    "ruvds" {
        $plan.endpoint = "POST https://api.ruvds.com/v2/servers"
        $apiKey = $null
        $balance = $null
        $selectedCredential = $null
        if ($QuotePrice -or $Apply) {
            $selectedCredential = Select-RuvdsApiCredential -Candidates (Get-RuvdsApiCredentialCandidates)
            $apiKey = $selectedCredential.token
            $balance = $selectedCredential.balance
            if ([string]::IsNullOrWhiteSpace($RuvdsSshKeyId)) {
                $RuvdsSshKeyId = $selectedCredential.sshKeyId
            }
            if ($Apply -and [string]::IsNullOrWhiteSpace($RuvdsSshKeyId)) {
                throw "Selected RUVDS account does not have SSH key 'greenvpn-codex-local'. Add the SSH key before paid create."
            }
        }

        $plan.payload = New-RuvdsPayload
        if ($null -ne $selectedCredential) {
            $plan.credential = [ordered]@{
                sources = @($selectedCredential.sources)
                balanceRub = $selectedCredential.balanceAmount
                requiredSshKeyPresent = $selectedCredential.sshKeyPresent
            }
        }
        $plan.defaults = [ordered]@{
            recommendedFirstDatacenter = "3 / LD8 London"
            fallbackDatacenter = "2 / ZUR1 Zurich"
            os = "52 / Debian 12"
            tariff = "$RuvdsTariffId / PremiumEurope"
            driveTariff = "$RuvdsDriveTariffId"
            paymentPeriod = "$PaymentPeriod / one month when value is 2"
            sshKey = if ([string]::IsNullOrWhiteSpace($RuvdsSshKeyId)) { "not set" } else { "greenvpn-codex-local" }
        }

        if ($QuotePrice -and -not $Apply) {
            $plan.dryRun = $true
            $plan.action = "quote_test_vps_price"
            $plan.providerResponse = Invoke-GreenVpnJson `
                -Method POST `
                -Uri "https://api.ruvds.com/v2/servers?get_price_only=true" `
                -Headers @{ Authorization = "Bearer $apiKey" } `
                -Body $plan.payload
            $plan.currentBalanceRub = $balance.amount
            $plan.quotedCostRub = $plan.providerResponse.cost_rub
            $plan.minimumTopUpRub = [Math]::Max(0, [Math]::Ceiling(([decimal]$plan.quotedCostRub) - ([decimal]$plan.currentBalanceRub)))
        }

        if ($Apply) {
            $plan.dryRun = $false
            $plan.providerResponse = Invoke-GreenVpnJson `
                -Method POST `
                -Uri "https://api.ruvds.com/v2/servers" `
                -Headers @{ Authorization = "Bearer $apiKey" } `
                -Body $plan.payload
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
