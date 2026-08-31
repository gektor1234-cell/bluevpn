param(
    [Parameter(Mandatory = $true)]
    [string]$StatusPath,

    [Parameter(Mandatory = $true)]
    [string]$ConfigBackupPath,

    [Parameter(Mandatory = $true)]
    [string]$ConfigDestinationPath,

    [Parameter(Mandatory = $true)]
    [string]$RoutingModeBackupPath,

    [Parameter(Mandatory = $true)]
    [string]$RoutingModeDestinationPath,

    [ValidateRange(30, 600)]
    [int]$DelaySeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$result = [ordered]@{
    schema = 1
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    delaySeconds = $DelaySeconds
    disconnectAttempted = $false
    disconnectOk = $false
    configRestored = $false
    routingModeRestored = $false
    failure = ''
}

try {
    Start-Sleep -Seconds $DelaySeconds
    $tokenPath = Join-Path $env:ProgramData 'BlueVPN\service_token'
    $token = (Get-Content -LiteralPath $tokenPath -Raw -Encoding ASCII).Trim()
    $result.disconnectAttempted = $true
    $response = Invoke-RestMethod `
        -Method Post `
        -Uri 'http://127.0.0.1:48737/disconnect' `
        -Headers @{ 'X-GreenVPN-Local-Token' = $token } `
        -TimeoutSec 120
    $result.disconnectOk = $response.ok -eq $true
} catch {
    $result.failure = $_.Exception.Message
} finally {
    try {
        Copy-Item -LiteralPath $ConfigBackupPath `
            -Destination $ConfigDestinationPath -Force
        $result.configRestored = $true
    } catch {
        if (-not $result.failure) { $result.failure = $_.Exception.Message }
    }
    try {
        Copy-Item -LiteralPath $RoutingModeBackupPath `
            -Destination $RoutingModeDestinationPath -Force
        $result.routingModeRestored = $true
    } catch {
        if (-not $result.failure) { $result.failure = $_.Exception.Message }
    }
    $result.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $result | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $StatusPath -Encoding UTF8
}
