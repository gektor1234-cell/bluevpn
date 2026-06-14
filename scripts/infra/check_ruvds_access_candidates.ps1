param(
    [Parameter(Mandatory = $false)]
    [string]$SecretsPath = "",

    [Parameter(Mandatory = $false)]
    [string]$LegacyAccessPath = "D:\GreenVPN_Secrets\ruvds_access.txt",

    [Parameter(Mandatory = $false)]
    [decimal]$RequiredBalanceRub = 933,

    [Parameter(Mandatory = $false)]
    [string]$RequiredSshKeyName = "greenvpn-codex-local"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\provider_api_common.ps1"

$secretState = Import-GreenVpnProviderSecrets -SecretsPath $SecretsPath

function Read-KeyValueFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $values
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $match = [regex]::Match($trimmed, '^([A-Za-z0-9_.-]+)\s*=\s*(.*)$')
        if (-not $match.Success) {
            continue
        }

        $key = $match.Groups[1].Value.Trim()
        $value = $match.Groups[2].Value.Trim().Trim('"').Trim("'")
        $values[$key] = $value
    }

    return $values
}

function Add-RuvdsTokenCandidate {
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

function Add-RuvdsTokenListCandidate {
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
        Add-RuvdsTokenCandidate -Candidates $Candidates -Source "${Source}[$index]" -Token $trimmed
    }
}

function Get-EnvironmentValue {
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

function Get-EnvironmentValuesByPattern {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $values = @()
    $seenNames = @{}

    foreach ($scope in @("Process", "User", "Machine")) {
        $environment = [Environment]::GetEnvironmentVariables($scope)
        foreach ($name in @($environment.Keys | Sort-Object)) {
            $nameText = [string]$name
            if ($nameText -notmatch $Pattern) {
                continue
            }

            $value = [string]$environment[$name]
            if (Test-GreenVpnPlaceholderSecret -Value $value) {
                continue
            }

            $source = "${scope}:${nameText}"
            if ($seenNames.ContainsKey($source)) {
                continue
            }
            $seenNames[$source] = $true

            $values += [pscustomobject]@{
                source = $source
                value = $value
            }
        }
    }

    return @($values)
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

$rawCandidates = [System.Collections.ArrayList]::new()

Add-RuvdsTokenCandidate `
    -Candidates $rawCandidates `
    -Source "GREENVPN_RUVDS_API_KEY" `
    -Token (Get-EnvironmentValue -Name "GREENVPN_RUVDS_API_KEY")

Add-RuvdsTokenListCandidate `
    -Candidates $rawCandidates `
    -Source "GREENVPN_RUVDS_API_KEYS" `
    -Value (Get-EnvironmentValue -Name "GREENVPN_RUVDS_API_KEYS")

foreach ($candidate in Get-EnvironmentValuesByPattern -Pattern '^GREENVPN_RUVDS_API_KEY_[A-Z0-9_]+$') {
    Add-RuvdsTokenCandidate -Candidates $rawCandidates -Source $candidate.source -Token $candidate.value
}

$legacyValues = Read-KeyValueFile -Path $LegacyAccessPath
if ($legacyValues.ContainsKey("ruvds_api_v2_token")) {
    Add-RuvdsTokenCandidate `
        -Candidates $rawCandidates `
        -Source "ruvds_access.txt:ruvds_api_v2_token" `
        -Token $legacyValues["ruvds_api_v2_token"]
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

$results = @()
foreach ($item in $unique.Values) {
    $sources = @($item.sources)
    try {
        $balance = Invoke-RuvdsApiV2 -Path "/v2/balance" -Token $item.token
        $servers = Invoke-RuvdsApiV2 -Path "/v2/servers?page=1&per_page=50" -Token $item.token
        $sshKeys = Invoke-RuvdsApiV2 -Path "/v2/ssh_keys" -Token $item.token

        $sshItems = @($sshKeys.ssh_keys)
        $matchingSshKeys = @($sshItems | Where-Object { $_.name -eq $RequiredSshKeyName })
        $balanceAmount = [decimal]$balance.amount

        $results += [pscustomobject]@{
            sources = $sources
            status = "ok"
            balanceRub = $balanceAmount
            currency = $balance.currency
            serverCount = @($servers.servers).Count
            sshKeyCount = $sshItems.Count
            requiredSshKeyPresent = ($matchingSshKeys.Count -gt 0)
            readyForZurich = ($balanceAmount -ge $RequiredBalanceRub -and $matchingSshKeys.Count -gt 0)
            missing = @(
                if ($balanceAmount -lt $RequiredBalanceRub) { "balance" }
                if ($matchingSshKeys.Count -eq 0) { "ssh_key:$RequiredSshKeyName" }
            )
        }
    } catch {
        $results += [pscustomobject]@{
            sources = $sources
            status = "error"
            error = (Protect-GreenVpnString -Value $_.Exception.Message)
            readyForZurich = $false
        }
    }
}

$ready = @($results | Where-Object { $_.readyForZurich } | Select-Object -First 1)

Write-GreenVpnJson -InputObject ([pscustomobject]@{
    ok = $true
    localConfigFile = $secretState
    legacyAccessFile = [pscustomobject]@{
        path = $LegacyAccessPath
        exists = (Test-Path -LiteralPath $LegacyAccessPath -PathType Leaf)
    }
    requiredBalanceRub = $RequiredBalanceRub
    requiredSshKeyName = $RequiredSshKeyName
    candidateCount = $results.Count
    readyCandidateFound = ($ready.Count -gt 0)
    candidates = $results
    nextAction = if ($ready.Count -gt 0) {
        "Run scripts\infra\rollout_ruvds_zurich_preview.ps1 -CreatePaidServer -ConfirmPaidCreate -ApplyBootstrap -ConfirmRemoteProvision -AddToPreview."
    } else {
        "Put an API v2 token from the funded RUVDS account into GREENVPN_RUVDS_API_KEY, GREENVPN_RUVDS_API_KEY_*, or GREENVPN_RUVDS_API_KEYS, and ensure that account has the required SSH key."
    }
})
