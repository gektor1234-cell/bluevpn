param(
    [Parameter(Mandatory = $false)]
    [string]$ApiBaseUrl = "http://37.220.85.211:8000",

    [Parameter(Mandatory = $false)]
    [string]$AdminToken = $env:BLUEVPN_ADMIN_TOKEN,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Overview", "ListUsers", "ListUserDevices", "DisableDevice", "EnableDevice", "SetSubscription", "ApplyTariff")]
    [string]$Action = "Overview",

    [Parameter(Mandatory = $false)]
    [int]$UserId,

    [Parameter(Mandatory = $false)]
    [string]$DeviceUid,

    [Parameter(Mandatory = $false)]
    [string]$Reason = "disabled_by_admin",

    [Parameter(Mandatory = $false)]
    [string]$PlanCode = "base",

    [Parameter(Mandatory = $false)]
    [string]$PlanName = "Base",

    [Parameter(Mandatory = $false)]
    [int]$MaxDevices = 1,

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

        Invoke-BlueVpnAdminJson `
            -Method POST `
            -Path "/api/v1/admin/devices/$DeviceUid/disable" `
            -Body @{ reason = $Reason } |
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

        $body = @{
            planCode = $PlanCode
            planName = $PlanName
            maxDevices = $MaxDevices
            isActive = $IsActive
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

        $body = @{
            trafficPack = $TrafficPack
            trafficGb = $TrafficGb
            unlimitedApps = $UnlimitedApps
            devices = $MaxDevices
            dedicatedIp = $DedicatedIp
        }

        Invoke-BlueVpnAdminJson `
            -Method POST `
            -Path "/api/v1/admin/users/$UserId/tariff/apply" `
            -Body $body |
            ConvertTo-Json -Depth 8
        break
    }
}
