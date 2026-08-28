param(
    [Parameter(Mandatory = $false)]
    [string]$ApiBaseUrl = "https://api.greenvpn.pro",

    [Parameter(Mandatory = $false)]
    [string]$AdminToken = $env:BLUEVPN_ADMIN_TOKEN,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Overview", "ListUsers", "ListUserDevices", "DisableDevice", "EnableDevice", "SetSubscription", "GrantSubscription", "RevokeSubscription", "SubscriptionHistory", "ApplyTariff")]
    [string]$Action = "Overview",

    [Parameter(Mandatory = $false)]
    [int]$UserId,

    [Parameter(Mandatory = $false)]
    [string]$DeviceUid,

    [Parameter(Mandatory = $false)]
    [string]$Reason = "",

    [Parameter(Mandatory = $false)]
    [string]$PlanCode = "base",

    [Parameter(Mandatory = $false)]
    [string]$PlanName = "Base",

    [Parameter(Mandatory = $false)]
    [int]$MaxDevices = 1,

    [Parameter(Mandatory = $false)]
    [int]$DurationDays = 30,

    [Parameter(Mandatory = $false)]
    [int]$MonthlyPriceRub = 249,

    [Parameter(Mandatory = $false)]
    [bool]$IsActive = $true,

    [Parameter(Mandatory = $false)]
    [string]$ExpiresAt
,
    [Parameter(Mandatory = $false)]
    [ValidateSet("gb5", "gb20", "gb50", "gb100", "unlimited")]
    [string]$TrafficPack = "gb20",

    [Parameter(Mandatory = $false)]
    [int]$TrafficGb = 20,

    [Parameter(Mandatory = $false)]
    [string[]]$UnlimitedApps = @(),

    [Parameter(Mandatory = $false)]
    [bool]$DedicatedIp = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-AdminToken {
    if ([string]::IsNullOrWhiteSpace($AdminToken)) {
        throw "Admin token is required. Pass -AdminToken or set BLUEVPN_ADMIN_TOKEN."
    }
}

function Invoke-BlueVpnAdminJson {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [object]$Body
    )

    Ensure-AdminToken

    $base = $ApiBaseUrl.TrimEnd("/")
    $uri = "$base$Path"

    $headers = @{
        "X-Admin-Token" = $AdminToken
    }

    $params = @{
        Method = $Method
        Uri = $uri
        Headers = $headers
        ContentType = "application/json"
    }

    if ($null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 8)
    }

    return Invoke-RestMethod @params
}

switch ($Action) {
    "Overview" {
        Invoke-BlueVpnAdminJson -Method GET -Path "/api/v1/admin/overview" |
            ConvertTo-Json -Depth 8
        break
    }

    "ListUsers" {
        Invoke-BlueVpnAdminJson -Method GET -Path "/api/v1/admin/users" |
            ConvertTo-Json -Depth 8
        break
    }

    "ListUserDevices" {
        if ($UserId -le 0) {
            throw "ListUserDevices requires -UserId."
        }

        Invoke-BlueVpnAdminJson -Method GET -Path "/api/v1/admin/users/$UserId/devices" |
            ConvertTo-Json -Depth 8
        break
    }

    "DisableDevice" {
        if ([string]::IsNullOrWhiteSpace($DeviceUid)) {
            throw "DisableDevice requires -DeviceUid."
        }

        $deviceReason = if ([string]::IsNullOrWhiteSpace($Reason)) {
            "disabled_by_admin"
        } else {
            $Reason.Trim()
        }

        Invoke-BlueVpnAdminJson `
            -Method POST `
            -Path "/api/v1/admin/devices/$DeviceUid/disable" `
            -Body @{ reason = $deviceReason } |
            ConvertTo-Json -Depth 8
        break
    }

    "EnableDevice" {
        if ([string]::IsNullOrWhiteSpace($DeviceUid)) {
            throw "EnableDevice requires -DeviceUid."
        }

        Invoke-BlueVpnAdminJson `
            -Method POST `
            -Path "/api/v1/admin/devices/$DeviceUid/enable" `
            -Body @{} |
            ConvertTo-Json -Depth 8
        break
    }

    "SetSubscription" {
        if ($UserId -le 0) {
            throw "SetSubscription requires -UserId."
        }
        if ($MaxDevices -lt 1) {
            throw "SetSubscription requires -MaxDevices >= 1."
        }
        if ([string]::IsNullOrWhiteSpace($Reason) -or $Reason.Trim().Length -lt 8) {
            throw "SetSubscription requires a reason of at least 8 characters."
        }

        $body = @{
            planCode = $PlanCode
            planName = $PlanName
            maxDevices = $MaxDevices
            isActive = $IsActive
            reason = $Reason
        }

        if (-not [string]::IsNullOrWhiteSpace($ExpiresAt)) {
            $body.expiresAt = $ExpiresAt
        }

        Invoke-BlueVpnAdminJson `
            -Method POST `
            -Path "/api/v1/admin/users/$UserId/subscription" `
            -Body $body |
            ConvertTo-Json -Depth 8
        break
    }

    "GrantSubscription" {
        if ($UserId -le 0) {
            throw "GrantSubscription requires -UserId."
        }
        $grantPlanCode = if ($PSBoundParameters.ContainsKey('PlanCode')) {
            $PlanCode
        } else {
            'green_30d'
        }
        $grantPlanName = if ($PSBoundParameters.ContainsKey('PlanName')) {
            $PlanName
        } else {
            'Green VPN - 1 месяц'
        }
        $grantMaxDevices = if ($PSBoundParameters.ContainsKey('MaxDevices')) {
            $MaxDevices
        } else {
            5
        }
        if ($DurationDays -lt 1 -or $DurationDays -gt 3650) {
            throw "GrantSubscription requires -DurationDays between 1 and 3650."
        }
        if ($grantMaxDevices -lt 1 -or $grantMaxDevices -gt 100) {
            throw "GrantSubscription requires -MaxDevices between 1 and 100."
        }
        if ($MonthlyPriceRub -lt 1) {
            throw "GrantSubscription requires -MonthlyPriceRub >= 1."
        }
        if ([string]::IsNullOrWhiteSpace($Reason) -or $Reason.Trim().Length -lt 8) {
            throw "GrantSubscription requires a reason of at least 8 characters."
        }

        $body = @{
            durationDays = $DurationDays
            planCode = $grantPlanCode
            planName = $grantPlanName
            maxDevices = $grantMaxDevices
            monthlyPriceRub = $MonthlyPriceRub
            reason = $Reason
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpiresAt)) {
            $body.expiresAt = $ExpiresAt
        }

        Invoke-BlueVpnAdminJson `
            -Method POST `
            -Path "/api/v1/admin/users/$UserId/subscription/grant" `
            -Body $body |
            ConvertTo-Json -Depth 8
        break
    }

    "RevokeSubscription" {
        if ($UserId -le 0) {
            throw "RevokeSubscription requires -UserId."
        }
        if ([string]::IsNullOrWhiteSpace($Reason) -or $Reason.Trim().Length -lt 8) {
            throw "RevokeSubscription requires a reason of at least 8 characters."
        }

        Invoke-BlueVpnAdminJson `
            -Method POST `
            -Path "/api/v1/admin/users/$UserId/subscription/revoke" `
            -Body @{ reason = $Reason } |
            ConvertTo-Json -Depth 8
        break
    }

    "SubscriptionHistory" {
        if ($UserId -le 0) {
            throw "SubscriptionHistory requires -UserId."
        }

        Invoke-BlueVpnAdminJson `
            -Method GET `
            -Path "/api/v1/admin/users/$UserId/subscription-history" |
            ConvertTo-Json -Depth 12
        break
    }

    "ApplyTariff" {
        if ($UserId -le 0) {
            throw "ApplyTariff requires -UserId."
        }
        if ($TrafficGb -lt 1) {
            throw "ApplyTariff requires -TrafficGb >= 1."
        }
        if ($MaxDevices -lt 1) {
            throw "ApplyTariff requires -MaxDevices >= 1."
        }
        if ([string]::IsNullOrWhiteSpace($Reason) -or $Reason.Trim().Length -lt 8) {
            throw "ApplyTariff requires a reason of at least 8 characters."
        }

        $body = @{
            trafficPack = $TrafficPack
            trafficGb = $TrafficGb
            unlimitedApps = $UnlimitedApps
            devices = $MaxDevices
            dedicatedIp = $DedicatedIp
            autoRenew = $false
            adminReason = $Reason.Trim()
        }

        Invoke-BlueVpnAdminJson `
            -Method POST `
            -Path "/api/v1/admin/users/$UserId/tariff/apply" `
            -Body $body |
            ConvertTo-Json -Depth 8
        break
    }
}
