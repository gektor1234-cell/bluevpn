param(
  [string]$ApiBase = "https://api.greenvpn.pro",
  [string]$VpnEndpointHost = "nl1.vpn.greenvpn.pro",
  [string]$ExpectedApiIp = "",
  [string]$ExpectedVpnIp = "37.220.85.211",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Test-IpLiteral {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $false
  }
  $parsed = [System.Net.IPAddress]::None
  return [System.Net.IPAddress]::TryParse($Value.Trim(), [ref]$parsed)
}

function Resolve-HostIps {
  param([string]$HostName)
  if ([string]::IsNullOrWhiteSpace($HostName)) {
    return @()
  }
  $value = $HostName.Trim()
  if (Test-IpLiteral -Value $value) {
    return @($value)
  }
  try {
    return @(
      Resolve-DnsName -Name $value -Type A -ErrorAction Stop |
        Where-Object { $_.IPAddress } |
        Select-Object -ExpandProperty IPAddress -Unique
    )
  } catch {
    return @()
  }
}

function New-Check {
  param(
    [string]$Name,
    [string]$Status,
    [string]$Message,
    [object]$Details = $null
  )
  [pscustomobject]@{
    name = $Name
    status = $Status
    message = $Message
    details = $Details
  }
}

function Add-ExpectedIpCheck {
  param(
    [System.Collections.Generic.List[object]]$Checks,
    [string]$Name,
    [string[]]$ActualIps,
    [string]$ExpectedIp
  )
  if ([string]::IsNullOrWhiteSpace($ExpectedIp)) {
    $Checks.Add((New-Check $Name "yellow" "Expected IP was not provided; resolved IPs are informational only." @{
      actualIps = $ActualIps
    }))
    return
  }
  if ($ActualIps -contains $ExpectedIp.Trim()) {
    $Checks.Add((New-Check $Name "green" "Resolved IP matches expected value." @{
      expectedIp = $ExpectedIp.Trim()
      actualIps = $ActualIps
    }))
    return
  }
  $Checks.Add((New-Check $Name "red" "Resolved IP does not match expected value." @{
    expectedIp = $ExpectedIp.Trim()
    actualIps = $ActualIps
  }))
}

$checks = [System.Collections.Generic.List[object]]::new()

try {
  $apiUri = [Uri]$ApiBase
  $apiHost = $apiUri.Host
  if ($apiUri.Scheme -eq "https" -and $apiHost) {
    $checks.Add((New-Check "API HTTPS URL" "green" "API base uses HTTPS." @{
      apiBase = $ApiBase
      apiHost = $apiHost
    }))
  } else {
    $checks.Add((New-Check "API HTTPS URL" "red" "API base must be a real HTTPS URL." @{
      apiBase = $ApiBase
    }))
  }
} catch {
  $apiHost = ""
  $checks.Add((New-Check "API HTTPS URL" "red" $_.Exception.Message @{
    apiBase = $ApiBase
  }))
}

$apiIps = @(Resolve-HostIps -HostName $apiHost)
$vpnIps = @(Resolve-HostIps -HostName $VpnEndpointHost)
$overlap = @($apiIps | Where-Object { $vpnIps -contains $_ })

if ($apiIps.Count -gt 0) {
  $checks.Add((New-Check "API DNS" "green" "API host resolves." @{
    host = $apiHost
    ips = $apiIps
  }))
} else {
  $checks.Add((New-Check "API DNS" "red" "API host does not resolve." @{
    host = $apiHost
  }))
}

if ($vpnIps.Count -gt 0) {
  $checks.Add((New-Check "VPN endpoint DNS" "green" "VPN endpoint host resolves." @{
    host = $VpnEndpointHost
    ips = $vpnIps
  }))
} else {
  $checks.Add((New-Check "VPN endpoint DNS" "red" "VPN endpoint host does not resolve." @{
    host = $VpnEndpointHost
  }))
}

Add-ExpectedIpCheck -Checks $checks -Name "Expected API IP" -ActualIps $apiIps -ExpectedIp $ExpectedApiIp
Add-ExpectedIpCheck -Checks $checks -Name "Expected VPN IP" -ActualIps $vpnIps -ExpectedIp $ExpectedVpnIp

if ($apiIps.Count -gt 0 -and $vpnIps.Count -gt 0 -and $overlap.Count -eq 0) {
  $checks.Add((New-Check "API/VPN IP split" "green" "API/site and VPN endpoint resolve to separate IPs." @{
    apiHost = $apiHost
    apiIps = $apiIps
    vpnEndpointHost = $VpnEndpointHost
    vpnEndpointIps = $vpnIps
  }))
} else {
  $checks.Add((New-Check "API/VPN IP split" "red" "API/site and VPN endpoint still share an IP or cannot both be resolved." @{
    apiHost = $apiHost
    apiIps = $apiIps
    vpnEndpointHost = $VpnEndpointHost
    vpnEndpointIps = $vpnIps
    overlap = $overlap
  }))
}

try {
  $health = Invoke-RestMethod -Uri "$($ApiBase.TrimEnd('/'))/healthz" -TimeoutSec 15
  $checks.Add((New-Check "API healthz" "green" "Backend /healthz responded." $health))
} catch {
  $checks.Add((New-Check "API healthz" "yellow" $_.Exception.Message $null))
}

$summary = [pscustomobject]@{
  ok = -not ($checks | Where-Object { $_.status -eq "red" })
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  apiBase = $ApiBase
  apiHost = $apiHost
  vpnEndpointHost = $VpnEndpointHost
  expectedApiIp = $ExpectedApiIp
  expectedVpnIp = $ExpectedVpnIp
  green = @($checks | Where-Object { $_.status -eq "green" }).Count
  yellow = @($checks | Where-Object { $_.status -eq "yellow" }).Count
  red = @($checks | Where-Object { $_.status -eq "red" }).Count
  checks = $checks
  policy = @{
    secretFree = $true
    mutationFree = $true
    purpose = "Run after DNS/proxy changes to verify api.greenvpn.pro is separated from the VPN endpoint."
  }
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8
} else {
  Write-Host "[Green VPN API/VPN split preflight] $($summary.green) green, $($summary.yellow) yellow, $($summary.red) red"
  $checks | Select-Object name, status, message | Format-Table -AutoSize
}
