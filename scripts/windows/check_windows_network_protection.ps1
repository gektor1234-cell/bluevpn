param(
    [string]$TunnelName = 'BlueVPNDev1',
    [string]$ConfigPath = '',
    [switch]$Json
)

# check_windows_network_protection: read-only Green VPN DNS/IPv6/route guard.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $env:ProgramData 'BlueVPN\BlueVPNDev1.conf'
}

$ServiceName = "WireGuardTunnel`$$TunnelName"

function New-Check {
    param(
        [string]$Code,
        [string]$Name,
        [ValidateSet('green', 'yellow', 'red')][string]$Status,
        [string]$Message,
        [object]$Details = $null
    )

    [pscustomobject]@{
        code = $Code
        name = $Name
        status = $Status
        message = $Message
        details = $Details
    }
}

function Read-GreenVpnConfigSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $safeLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -match '^\s*PrivateKey\s*=') {
            $safeLines.Add('PrivateKey = <hidden>') | Out-Null
        } else {
            $safeLines.Add($line) | Out-Null
        }
    }
    return ($safeLines -join "`n")
}

function Get-ConfigField {
    param(
        [string]$ConfigText,
        [string]$Field
    )

    $match = [regex]::Match($ConfigText, "(?im)^\s*$([regex]::Escape($Field))\s*=\s*(.+?)\s*$")
    if (-not $match.Success) {
        return ''
    }
    return $match.Groups[1].Value.Trim()
}

function Split-ConfigList {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }
    return @(
        $Value -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-ServiceStateSafe {
    param([string]$Name)
    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$($Name.Replace("'", "''"))'" -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            return 'not_installed'
        }
        return [string]$svc.State
    } catch {
        return 'unknown'
    }
}

function Get-AdapterStateSafe {
    param([string]$Name)
    try {
        $adapter = Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $adapter) {
            return 'missing'
        }
        return [string]$adapter.Status
    } catch {
        return 'unknown'
    }
}

function Get-DefaultRouteAliasSafe {
    param(
        [ValidateSet('IPv4', 'IPv6')][string]$AddressFamily
    )

    try {
        $prefix = if ($AddressFamily -eq 'IPv4') { '0.0.0.0/0' } else { '::/0' }
        $route = Get-NetRoute -AddressFamily $AddressFamily -DestinationPrefix $prefix -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric, InterfaceMetric |
            Select-Object -First 1
        if ($null -eq $route) {
            return ''
        }
        return [string]$route.InterfaceAlias
    } catch {
        return ''
    }
}

function Get-Ipv4FullTunnelRouteEvidenceSafe {
    param([string]$TunnelName)

    try {
        $routes = @(
            Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0', '0.0.0.0/1', '128.0.0.0/1') }
        )

        function Get-BestRouteForPrefix {
            param([string]$Prefix)
            return $routes |
                Where-Object { $_.DestinationPrefix -eq $Prefix -and $_.State -ne 'Dead' } |
                Sort-Object RouteMetric, InterfaceMetric |
                Select-Object -First 1
        }

        $defaultRoute = Get-BestRouteForPrefix -Prefix '0.0.0.0/0'
        $lowerHalfRoute = Get-BestRouteForPrefix -Prefix '0.0.0.0/1'
        $upperHalfRoute = Get-BestRouteForPrefix -Prefix '128.0.0.0/1'
        $defaultAlias = if ($null -ne $defaultRoute) { [string]$defaultRoute.InterfaceAlias } else { '' }
        $lowerHalfAlias = if ($null -ne $lowerHalfRoute) { [string]$lowerHalfRoute.InterfaceAlias } else { '' }
        $upperHalfAlias = if ($null -ne $upperHalfRoute) { [string]$upperHalfRoute.InterfaceAlias } else { '' }
        $ownsDefault = $defaultAlias -eq $TunnelName
        $ownsSplitDefault = $lowerHalfAlias -eq $TunnelName -and $upperHalfAlias -eq $TunnelName

        return [pscustomobject]@{
            ownsFullTunnel = ($ownsDefault -or $ownsSplitDefault)
            mode = if ($ownsDefault) { 'default' } elseif ($ownsSplitDefault) { 'split_default' } else { 'missing' }
            defaultRouteAlias = $defaultAlias
            lowerHalfRouteAlias = $lowerHalfAlias
            upperHalfRouteAlias = $upperHalfAlias
        }
    } catch {
        return [pscustomobject]@{
            ownsFullTunnel = $false
            mode = 'unknown'
            defaultRouteAlias = ''
            lowerHalfRouteAlias = ''
            upperHalfRouteAlias = ''
        }
    }
}

function Get-DnsServersSafe {
    param([string]$InterfaceAlias)
    try {
        $rows = Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ErrorAction SilentlyContinue
        return @(
            $rows |
                ForEach-Object { $_.ServerAddresses } |
                ForEach-Object { $_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
    } catch {
        return @()
    }
}

function Get-UpNonVpnDnsAdapters {
    param([string]$VpnAlias)
    $rows = New-Object System.Collections.Generic.List[object]
    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Status -eq 'Up' -and
                $_.Name -ne $VpnAlias -and
                $_.Name -notmatch '(?i)(loopback|isatap|teredo)' -and
                $_.InterfaceDescription -notmatch '(?i)(wireguard|wintun|amnezia|warp|cloudflare)'
            }
        foreach ($adapter in $adapters) {
            $dns = @(Get-DnsServersSafe -InterfaceAlias $adapter.Name)
            if ($dns.Count -gt 0) {
                $rows.Add([pscustomobject]@{
                    adapter = $adapter.Name
                    description = $adapter.InterfaceDescription
                    dnsServers = $dns
                }) | Out-Null
            }
        }
    } catch {
    }
    return @($rows.ToArray())
}

function Get-NonVpnDnsRouteEvidence {
    param(
        [object[]]$DnsAdapters,
        [string]$TunnelName
    )

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($adapter in $DnsAdapters) {
        foreach ($serverValue in @($adapter.dnsServers)) {
            $server = ([string]$serverValue -split '%', 2)[0]
            $ipAddress = $null
            $parsed = [System.Net.IPAddress]::TryParse($server, [ref]$ipAddress)
            $placeholder = $parsed -and $ipAddress.ToString() -match '^(?i)fec0:0:0:ffff::[1-3]$'
            $routeAlias = ''
            $addressFamily = if ($parsed) { $ipAddress.AddressFamily.ToString() } else { 'unknown' }

            if ($parsed) {
                try {
                    $route = @(
                        Find-NetRoute -RemoteIPAddress $server -ErrorAction SilentlyContinue |
                            Where-Object { $_.CimClass.CimClassName -eq 'MSFT_NetRoute' }
                    ) | Select-Object -First 1
                    if ($null -ne $route) {
                        $routeAlias = [string]$route.InterfaceAlias
                    }
                } catch {}
            }

            $rows.Add([pscustomobject]@{
                adapter = $adapter.adapter
                addressFamily = $addressFamily
                routeAlias = $routeAlias
                placeholder = $placeholder
                throughTunnel = ($placeholder -or $routeAlias -eq $TunnelName)
            }) | Out-Null
        }
    }

    $effectiveRows = @($rows | Where-Object { -not $_.placeholder })
    $unsafeCount = @($effectiveRows | Where-Object { -not $_.throughTunnel }).Count
    return [pscustomobject]@{
        checked = $effectiveRows.Count
        ignoredPlaceholders = ($rows.Count - $effectiveRows.Count)
        routedThroughTunnel = ($effectiveRows.Count - $unsafeCount)
        unsafe = $unsafeCount
        allThroughTunnel = ($effectiveRows.Count -eq 0 -or $unsafeCount -eq 0)
        routes = @($rows.ToArray())
    }
}

function Get-CompetingVpnLabels {
    param([string]$OwnTunnelName, [string]$OwnServiceName)
    $labels = New-Object System.Collections.Generic.List[string]

    try {
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Status -eq 'Up' -and
                $_.Name -ne $OwnTunnelName -and
                (
                    $_.Name -match '(?i)(wireguard|wintun|amnezia|warp|cloudflare|device[0-9_]+)' -or
                    $_.InterfaceDescription -match '(?i)(wireguard|wintun|amnezia|warp|cloudflare)'
                )
            } |
            ForEach-Object { $labels.Add("adapter:$($_.Name)") | Out-Null }
    } catch {
    }

    try {
        Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -eq 'Running' -and
                (
                    ($_.Name -like 'WireGuardTunnel$*' -and $_.Name -ne $OwnServiceName) -or
                    ($_.Name -like 'AmneziaWGTunnel$*') -or
                    ($_.Name -match '(?i)(CloudflareWARP|Cloudflare WARP|WARP)')
                )
            } |
            ForEach-Object { $labels.Add("service:$($_.Name)") | Out-Null }
    } catch {
    }

    return @($labels | Sort-Object -Unique)
}

$checks = New-Object System.Collections.Generic.List[object]
$configSafe = Read-GreenVpnConfigSafe -Path $ConfigPath
$allowedIps = @(Split-ConfigList (Get-ConfigField -ConfigText $configSafe -Field 'AllowedIPs'))
$dnsFromConfig = @(Split-ConfigList (Get-ConfigField -ConfigText $configSafe -Field 'DNS'))
$endpoint = Get-ConfigField -ConfigText $configSafe -Field 'Endpoint'

$hasConfig = -not [string]::IsNullOrWhiteSpace($configSafe)
$hasFullIpv4 = $allowedIps -contains '0.0.0.0/0' -or (($allowedIps -contains '0.0.0.0/1') -and ($allowedIps -contains '128.0.0.0/1'))
$hasFullIpv6 = $allowedIps -contains '::/0'
$peerCount = @([regex]::Matches($configSafe, '(?im)^\s*\[Peer\]\s*$')).Count
$nativeKillSwitchConfigured = $peerCount -eq 1 -and (
    $allowedIps -contains '0.0.0.0/0' -or $allowedIps -contains '::/0'
)
$serviceState = Get-ServiceStateSafe -Name $ServiceName
$adapterState = Get-AdapterStateSafe -Name $TunnelName
$ipv4RouteEvidence = Get-Ipv4FullTunnelRouteEvidenceSafe -TunnelName $TunnelName
$ipv4RouteAlias = $ipv4RouteEvidence.defaultRouteAlias
$ipv6RouteAlias = Get-DefaultRouteAliasSafe -AddressFamily IPv6
$tunnelDns = @(Get-DnsServersSafe -InterfaceAlias $TunnelName)
$nonVpnDns = @(Get-UpNonVpnDnsAdapters -VpnAlias $TunnelName)
$nonVpnDnsRouteEvidence = Get-NonVpnDnsRouteEvidence -DnsAdapters $nonVpnDns -TunnelName $TunnelName
$competitors = @(Get-CompetingVpnLabels -OwnTunnelName $TunnelName -OwnServiceName $ServiceName)

if ($hasConfig) {
    $checks.Add((New-Check 'config_present' 'Green VPN config' 'green' 'Config found.' ([pscustomobject]@{ path = $ConfigPath; endpoint = $endpoint }))) | Out-Null
} else {
    $checks.Add((New-Check 'config_present' 'Green VPN config' 'red' 'Config not found. The user has not received a VPN config yet, or the install is damaged.' ([pscustomobject]@{ path = $ConfigPath }))) | Out-Null
}

if ($hasFullIpv4) {
    $checks.Add((New-Check 'full_tunnel_ipv4' 'Full IPv4 tunnel' 'green' 'IPv4 traffic should go through Green VPN.' $allowedIps)) | Out-Null
} else {
    $checks.Add((New-Check 'full_tunnel_ipv4' 'Full IPv4 tunnel' 'yellow' 'Config does not look like a full IPv4 tunnel. This can be okay for a special mode, but not for the normal user protection mode.' $allowedIps)) | Out-Null
}

if ($hasFullIpv6) {
    $checks.Add((New-Check 'full_tunnel_ipv6' 'Full IPv6 tunnel' 'green' 'IPv6 traffic is covered by the VPN config.' $allowedIps)) | Out-Null
} elseif (-not [string]::IsNullOrWhiteSpace($ipv6RouteAlias)) {
    $checks.Add((New-Check 'full_tunnel_ipv6' 'Full IPv6 tunnel' 'yellow' 'Windows has an IPv6 default route, but the VPN config has no ::/0. Until a dedicated IPv6 mode exists, this is a potential leak.' ([pscustomobject]@{ ipv6DefaultRouteAlias = $ipv6RouteAlias; allowedIps = $allowedIps }))) | Out-Null
} else {
    $checks.Add((New-Check 'full_tunnel_ipv6' 'Full IPv6 tunnel' 'green' 'No active IPv6 default route was found; IPv6 leak risk is not visible now.' $allowedIps)) | Out-Null
}

if ($dnsFromConfig.Count -gt 0) {
    $checks.Add((New-Check 'config_dns_present' 'DNS in VPN config' 'green' 'VPN DNS is present in the config.' $dnsFromConfig)) | Out-Null
} else {
    $checks.Add((New-Check 'config_dns_present' 'DNS in VPN config' 'red' 'VPN DNS is missing from the config. This is a DNS leak risk for normal users.' $null)) | Out-Null
}

if ($serviceState -eq 'Running') {
    $checks.Add((New-Check 'tunnel_service_state' 'Tunnel service' 'green' 'Green VPN WireGuard service is running.' ([pscustomobject]@{ service = $ServiceName; state = $serviceState }))) | Out-Null
} elseif ($serviceState -eq 'not_installed') {
    $checks.Add((New-Check 'tunnel_service_state' 'Tunnel service' 'yellow' 'WireGuard service is not installed yet. This is normal before connecting.' ([pscustomobject]@{ service = $ServiceName; state = $serviceState }))) | Out-Null
} else {
    $checks.Add((New-Check 'tunnel_service_state' 'Tunnel service' 'yellow' 'Green VPN WireGuard service is not running.' ([pscustomobject]@{ service = $ServiceName; state = $serviceState }))) | Out-Null
}

if ($adapterState -eq 'Up') {
    $checks.Add((New-Check 'adapter_state' 'Tunnel adapter' 'green' 'Green VPN adapter is active.' ([pscustomobject]@{ tunnel = $TunnelName; state = $adapterState }))) | Out-Null
} elseif ($adapterState -eq 'missing') {
    $checks.Add((New-Check 'adapter_state' 'Tunnel adapter' 'yellow' 'Adapter is missing. This is normal before connecting.' ([pscustomobject]@{ tunnel = $TunnelName; state = $adapterState }))) | Out-Null
} else {
    $checks.Add((New-Check 'adapter_state' 'Tunnel adapter' 'yellow' 'Green VPN adapter is not active now.' ([pscustomobject]@{ tunnel = $TunnelName; state = $adapterState }))) | Out-Null
}

if ($serviceState -eq 'Running' -and $ipv4RouteEvidence.ownsFullTunnel) {
    $checks.Add((New-Check 'ipv4_default_route' 'Full IPv4 route' 'green' 'The effective full IPv4 route belongs to Green VPN.' $ipv4RouteEvidence)) | Out-Null
} elseif ($serviceState -eq 'Running') {
    $checks.Add((New-Check 'ipv4_default_route' 'Full IPv4 route' 'red' 'VPN is running, but neither the default route nor both split-default routes belong to Green VPN.' ([pscustomobject]@{ routeEvidence = $ipv4RouteEvidence; expected = $TunnelName }))) | Out-Null
} else {
    $checks.Add((New-Check 'ipv4_default_route' 'Full IPv4 route' 'yellow' 'VPN is not running now; route is informational only.' $ipv4RouteEvidence)) | Out-Null
}

if ($serviceState -eq 'Running' -and $dnsFromConfig.Count -gt 0 -and $tunnelDns.Count -gt 0) {
    $checks.Add((New-Check 'active_tunnel_dns' 'Active tunnel DNS' 'green' 'DNS servers are visible on the VPN adapter.' ([pscustomobject]@{ tunnelDns = $tunnelDns; configDns = $dnsFromConfig }))) | Out-Null
} elseif ($serviceState -eq 'Running') {
    $checks.Add((New-Check 'active_tunnel_dns' 'Active tunnel DNS' 'yellow' 'VPN is running, but DNS on the VPN adapter is not confirmed.' ([pscustomobject]@{ tunnelDns = $tunnelDns; configDns = $dnsFromConfig }))) | Out-Null
} else {
    $checks.Add((New-Check 'active_tunnel_dns' 'Active tunnel DNS' 'yellow' 'VPN is not running now; active DNS can be checked after connecting.' ([pscustomobject]@{ configDns = $dnsFromConfig }))) | Out-Null
}

if ($serviceState -eq 'Running' -and $nativeKillSwitchConfigured) {
    $checks.Add((New-Check 'non_vpn_dns_visible' 'DNS route safety' 'green' 'The native Windows tunnel kill switch blocks DNS outside the configured VPN DNS servers.' ([pscustomobject]@{
        nativeKillSwitch = $true
        peerCount = $peerCount
        routeEvidence = $nonVpnDnsRouteEvidence
    }))) | Out-Null
} elseif ($serviceState -eq 'Running' -and $nonVpnDns.Count -gt 0 -and $nonVpnDnsRouteEvidence.allThroughTunnel) {
    $checks.Add((New-Check 'non_vpn_dns_visible' 'DNS route safety' 'green' 'Regular adapters retain DNS settings, but every effective DNS route goes through Green VPN.' $nonVpnDnsRouteEvidence)) | Out-Null
} elseif ($serviceState -eq 'Running' -and $nonVpnDns.Count -gt 0) {
    $checks.Add((New-Check 'non_vpn_dns_visible' 'DNS route safety' 'yellow' 'One or more DNS server routes are not confirmed through Green VPN.' $nonVpnDnsRouteEvidence)) | Out-Null
} else {
    $checks.Add((New-Check 'non_vpn_dns_visible' 'DNS route safety' 'green' 'No active regular-adapter DNS routing problem is visible.' $nonVpnDnsRouteEvidence)) | Out-Null
}

if ($competitors.Count -gt 0) {
    $checks.Add((New-Check 'competing_vpn' 'Other VPNs' 'yellow' 'Another active VPN or tunnel-like adapter was found. Green VPN should not connect on top of it.' $competitors)) | Out-Null
} else {
    $checks.Add((New-Check 'competing_vpn' 'Other VPNs' 'green' 'No active competing VPNs were found.' $competitors)) | Out-Null
}

$red = @($checks | Where-Object { $_.status -eq 'red' }).Count
$yellow = @($checks | Where-Object { $_.status -eq 'yellow' }).Count
$green = @($checks | Where-Object { $_.status -eq 'green' }).Count
$summaryMessage = if ($red -gt 0) {
    'Network protection has red issues.'
} elseif ($yellow -gt 0) {
    'No critical issues found, but there are items to verify before public release.'
} else {
    'Network protection looks ready.'
}
$checksArray = @($checks.ToArray())
$payload = New-Object psobject -Property ([ordered]@{
    ok = ($red -eq 0)
    productionReady = ($red -eq 0 -and $yellow -eq 0)
    tunnelName = $TunnelName
    serviceName = $ServiceName
    configPath = $ConfigPath
    summary = [pscustomobject]@{
        green = $green
        yellow = $yellow
        red = $red
        message = $summaryMessage
    }
    checks = $checksArray
})

if ($Json) {
    $payload | ConvertTo-Json -Depth 8
    exit $(if ($red -eq 0) { 0 } else { 1 })
}

Write-Host "Green VPN Windows network protection check"
Write-Host "Tunnel: $TunnelName"
Write-Host "Config: $ConfigPath"
Write-Host ""
foreach ($check in $checks) {
    $prefix = switch ($check.status) {
        'green' { '[ OK ]' }
        'yellow' { '[WARN]' }
        'red' { '[FAIL]' }
    }
    Write-Host "$prefix $($check.name): $($check.message)"
}
Write-Host ""
Write-Host "Summary: green=$green yellow=$yellow red=$red"

if ($red -gt 0) {
    exit 1
}
