Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:GreenVpnSensitiveNamePattern = '(?i)(token|secret|password|passwd|(^|_)pass($|_)|authorization|auth|api[_-]?key|apikey|access[_-]?key|private[_-]?key|client[_-]?secret|session|card)'

function Import-GreenVpnProviderSecrets {
    param(
        [Parameter(Mandatory = $false)]
        [string]$SecretsPath = ""
    )

    $candidatePaths = @()
    if (-not [string]::IsNullOrWhiteSpace($SecretsPath)) {
        $candidatePaths += $SecretsPath
    } else {
        $candidatePaths += "D:\GreenVPN_Secrets\provider_api.local.ps1"
        $candidatePaths += (Join-Path $PSScriptRoot "..\..\secrets\provider_api.local.ps1")
    }

    foreach ($candidate in $candidatePaths) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }

        $resolved = Resolve-Path -LiteralPath $candidate
        . $resolved.Path

        return [pscustomobject]@{
            loaded = $true
            path = $resolved.Path
            reason = "loaded"
            searched = @($candidatePaths)
        }
    }

    return [pscustomobject]@{
        loaded = $false
        path = $null
        reason = "not_found"
        searched = @($candidatePaths)
    }
}

function Test-GreenVpnPlaceholderSecret {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    $trimmed = $Value.Trim()
    return ($trimmed -match '^(CHANGE_ME|TODO|PASTE_|YOUR_|EXAMPLE_|xxx|<.+>)')
}

function Get-GreenVpnSecret {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [switch]$Required
    )

    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [Environment]::GetEnvironmentVariable($Name, "User")
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [Environment]::GetEnvironmentVariable($Name, "Machine")
    }

    if (Test-GreenVpnPlaceholderSecret -Value $value) {
        if ($Required) {
            throw "Required secret '$Name' is not configured."
        }
        return $null
    }

    return $value
}

function Protect-GreenVpnString {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $safe = $Value
    $safe = $safe -replace '(?i)(Bearer\s+)[A-Za-z0-9._~+/\-=]+', '$1***'
    $safe = $safe -replace '(?i)(X-API-KEY:\s*)[A-Za-z0-9._~+/\-=]+', '$1***'
    $safe = $safe -replace '(?i)(api[_-]?key=)[^&\s]+', '$1***'
    $safe = $safe -replace '(?i)(token=)[^&\s]+', '$1***'

    if ($safe.Length -gt 120 -and $safe -match '[A-Za-z0-9._~+/\-=]{48,}') {
        return "<redacted-string>"
    }

    return $safe
}

function ConvertTo-GreenVpnSafeObject {
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $false)]
        [int]$Depth = 0
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        if ($Depth -gt 12) {
            return "<depth-limit>"
        }

        if ($InputObject -is [string]) {
            return (Protect-GreenVpnString -Value $InputObject)
        }

        if ($InputObject -is [ValueType]) {
            return $InputObject
        }

        if ($InputObject -is [System.Collections.IDictionary]) {
            $safe = [ordered]@{}
            foreach ($key in $InputObject.Keys) {
                $keyText = [string]$key
                if ($keyText -match $script:GreenVpnSensitiveNamePattern) {
                    $safe[$keyText] = "<redacted>"
                } else {
                    $safe[$keyText] = ConvertTo-GreenVpnSafeObject -InputObject $InputObject[$key] -Depth ($Depth + 1)
                }
            }
            return [pscustomobject]$safe
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
            $items = @()
            foreach ($item in $InputObject) {
                $items += ConvertTo-GreenVpnSafeObject -InputObject $item -Depth ($Depth + 1)
            }
            return ,$items
        }

        $props = $InputObject.PSObject.Properties |
            Where-Object { $_.MemberType -in @("NoteProperty", "Property", "AliasProperty", "ScriptProperty") }

        if (@($props).Count -eq 0) {
            return (Protect-GreenVpnString -Value ([string]$InputObject))
        }

        $result = [ordered]@{}
        foreach ($prop in $props) {
            if ($prop.Name -match $script:GreenVpnSensitiveNamePattern) {
                $result[$prop.Name] = "<redacted>"
            } else {
                $result[$prop.Name] = ConvertTo-GreenVpnSafeObject -InputObject $prop.Value -Depth ($Depth + 1)
            }
        }

        return [pscustomobject]$result
    }
}

function Write-GreenVpnJson {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $false)]
        [int]$Depth = 12
    )

    ConvertTo-GreenVpnSafeObject -InputObject $InputObject |
        ConvertTo-Json -Depth $Depth
}

function Invoke-GreenVpnJson {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [hashtable]$Headers = @{},

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSec = 30
    )

    $params = @{
        Method = $Method
        Uri = $Uri
        Headers = $Headers
        ContentType = "application/json"
        TimeoutSec = $TimeoutSec
        ErrorAction = "Stop"
    }

    if ($null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 20)
    }

    try {
        return Invoke-RestMethod @params
    } catch {
        $message = Protect-GreenVpnString -Value $_.Exception.Message
        throw "HTTP $Method failed for $Uri`: $message"
    }
}
