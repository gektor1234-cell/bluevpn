param(
    [ValidateSet('Connect', 'Disconnect', 'Guard')]
    [string]$Action = 'Guard'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TunnelName = 'GreenVPNTransportPreview'
$WireGuardServiceName = 'WireGuardTunnel$GreenVPNTransportPreview'
$AmneziaWgServiceName = 'AmneziaWGTunnel$GreenVPNTransportPreview'
$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'
$ConfigPath = Join-Path $ProgramDataRoot 'GreenVPNTransportPreview.conf'
$ProtocolPath = $ConfigPath + '.protocol'
$EndpointRouteStatePath = $ConfigPath + '.endpoint-route.json'
$EndpointBypassRouteMetric = 42731
$LogPath = Join-Path $ProgramDataRoot 'backend.log'

function Write-GreenLog {
    param([string]$Message)
    try {
        New-Item -ItemType Directory -Force -Path $ProgramDataRoot | Out-Null
        Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "[$((Get-Date).ToString('o'))] transport-task($Action) $Message"
    } catch {
    }
}

function Invoke-External {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )

    $stdout = Join-Path $env:TEMP ("greenvpn_transport_stdout_" + [guid]::NewGuid().ToString('N') + '.txt')
    $stderr = Join-Path $env:TEMP ("greenvpn_transport_stderr_" + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $output = ''
        if (Test-Path -LiteralPath $stdout) { $output += Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stderr) { $output += "`n" + (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) }
        $flat = ($output -replace "`r", ' ' -replace "`n", ' | ').Trim()
        Write-GreenLog "$([IO.Path]::GetFileName($FilePath)) action=$($Arguments[0]) exit=$($process.ExitCode) $flat"
        if ($AllowedExitCodes -notcontains $process.ExitCode) {
            throw "$([IO.Path]::GetFileName($FilePath)) exited with $($process.ExitCode)"
        }
        return $process.ExitCode
    } finally {
        Remove-Item -LiteralPath $stdout -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-WireGuardExe {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe'),
        'C:\Program Files\WireGuard\wireguard.exe',
        'C:\Program Files (x86)\WireGuard\wireguard.exe'
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return ''
}

function Resolve-AmneziaWgExe {
    $candidate = Join-Path $PSScriptRoot 'amneziawg2\amneziawg.exe'
    if (-not (Test-Path -LiteralPath $candidate)) { return '' }
    try {
        $item = Get-Item -LiteralPath $candidate
        $signature = Get-AuthenticodeSignature -LiteralPath $candidate
        if ($item.VersionInfo.FileVersion -notlike '2.*') { return '' }
        if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) { return '' }
        return $candidate
    } catch {
        return ''
    }
}

function Get-ManagedProtocol {
    if (-not (Test-Path -LiteralPath $ProtocolPath)) { return 'wireguard_udp' }
    $value = (Get-Content -LiteralPath $ProtocolPath -Raw -ErrorAction Stop).Trim().ToLowerInvariant()
    if ($value -notin @('wireguard_udp', 'amneziawg')) {
        throw "Unsupported managed protocol: $value"
    }
    return $value
}

function Get-SelectedServiceName {
    param([string]$Protocol)
    if ($Protocol -eq 'amneziawg') { return $AmneziaWgServiceName }
    return $WireGuardServiceName
}

function Ensure-GreenProgramDataAcl {
    New-Item -ItemType Directory -Force -Path $ProgramDataRoot | Out-Null
    foreach ($path in @($ProgramDataRoot, $ConfigPath, $ProtocolPath)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            Invoke-External -FilePath 'attrib.exe' -Arguments @('-H', '-S', '-R', $path) -AllowedExitCodes @(0, 1) | Out-Null
            if ((Get-Item -LiteralPath $path).PSIsContainer) {
                Invoke-External -FilePath 'icacls.exe' -Arguments @($path, '/inheritance:e', '/grant', '*S-1-5-11:(OI)(CI)M', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F') | Out-Null
            } else {
                Invoke-External -FilePath 'icacls.exe' -Arguments @($path, '/inheritance:e', '/grant', '*S-1-5-11:M', '*S-1-5-18:F', '*S-1-5-32-544:F') | Out-Null
            }
        } catch {
            Write-GreenLog "ACL warning for $path"
        }
    }
}

function Get-ManagedIpv4Endpoint {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config missing: $ConfigPath" }
    $configText = [IO.File]::ReadAllText($ConfigPath)
    $match = [regex]::Match($configText, '(?im)^\s*Endpoint\s*=\s*(\d{1,3}(?:\.\d{1,3}){3}):\d+\s*$')
    if (-not $match.Success) { throw 'Windows transport preview requires an IPv4-literal endpoint.' }
    $address = $null
    if (-not [Net.IPAddress]::TryParse($match.Groups[1].Value, [ref]$address) -or
        $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'Windows transport preview endpoint is not valid IPv4.'
    }
    return $address.IPAddressToString
}

function Remove-EndpointBypassRoute {
    if (-not (Test-Path -LiteralPath $EndpointRouteStatePath)) { return }
    try {
        $state = Get-Content -LiteralPath $EndpointRouteStatePath -Raw | ConvertFrom-Json
        $managedEndpoint = Get-ManagedIpv4Endpoint
        if ($state.created -eq $true -and $state.endpoint -eq $managedEndpoint) {
            $prefix = "$($state.endpoint)/32"
            Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $prefix -InterfaceIndex ([int]$state.interfaceIndex) -ErrorAction SilentlyContinue |
                Where-Object { $_.NextHop -eq [string]$state.nextHop -and $_.RouteMetric -eq $EndpointBypassRouteMetric } |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            Write-GreenLog "removed endpoint bypass route endpoint=$($state.endpoint) ifIndex=$($state.interfaceIndex)"
        }
    } catch {
        Write-GreenLog 'endpoint bypass route cleanup warning'
    } finally {
        Remove-Item -LiteralPath $EndpointRouteStatePath -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-EndpointBypassRoute {
    Remove-EndpointBypassRoute
    $endpoint = Get-ManagedIpv4Endpoint
    $selection = @(Find-NetRoute -RemoteIPAddress $endpoint -ErrorAction Stop)
    $route = $selection |
        Where-Object { $_.CimClass.CimClassName -eq 'MSFT_NetRoute' -and $_.InterfaceAlias -ne $TunnelName } |
        Select-Object -First 1
    if ($null -eq $route -or [string]::IsNullOrWhiteSpace([string]$route.NextHop) -or $route.NextHop -eq '0.0.0.0') {
        throw "No physical gateway route is available for endpoint $endpoint."
    }

    $prefix = "$endpoint/32"
    $existing = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $prefix -InterfaceIndex ([int]$route.InterfaceIndex) -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -eq [string]$route.NextHop } |
        Select-Object -First 1
    $created = $false
    if ($null -eq $existing) {
        New-NetRoute -AddressFamily IPv4 -DestinationPrefix $prefix -InterfaceIndex ([int]$route.InterfaceIndex) `
            -NextHop ([string]$route.NextHop) -RouteMetric $EndpointBypassRouteMetric -PolicyStore ActiveStore -ErrorAction Stop | Out-Null
        $created = $true
    }
    [ordered]@{
        endpoint = $endpoint
        interfaceIndex = [int]$route.InterfaceIndex
        nextHop = [string]$route.NextHop
        created = $created
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $EndpointRouteStatePath -Encoding ASCII
    & attrib.exe +H $EndpointRouteStatePath 2>$null | Out-Null
    & icacls.exe $EndpointRouteStatePath /inheritance:r /grant '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
    Write-GreenLog "endpoint bypass route ready endpoint=$endpoint ifIndex=$($route.InterfaceIndex) created=$created"
}

function Ensure-NativeFullTunnelKillSwitch {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return }
    $configText = [IO.File]::ReadAllText($ConfigPath)
    $match = [regex]::Match($configText, '(?im)^\s*AllowedIPs\s*=\s*(.+?)\s*$')
    if (-not $match.Success) { return }
    $allowedIps = @($match.Groups[1].Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $hasSplitIpv4 = $allowedIps -contains '0.0.0.0/1' -and $allowedIps -contains '128.0.0.0/1'
    $hasNativeDefault = $allowedIps -contains '0.0.0.0/0' -or $allowedIps -contains '::/0'
    if (-not $hasSplitIpv4 -or $hasNativeDefault) { return }
    $preserved = @($allowedIps | Where-Object { $_ -notin @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1') })
    $normalized = @($preserved + @('0.0.0.0/0', '::/0') | Select-Object -Unique)
    $updated = [regex]::Replace($configText, '(?im)^\s*AllowedIPs\s*=.*$', ('AllowedIPs = ' + ($normalized -join ', ')), 1)
    if ($updated -eq $configText) { return }
    $temp = $ConfigPath + '.killswitch.tmp'
    try {
        [IO.File]::WriteAllText($temp, $updated, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $ConfigPath -Force
        Write-GreenLog 'normalized full-tunnel routes for native kill switch'
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Get-CompetingVpnLabels {
    $labels = New-Object System.Collections.Generic.List[string]
    try {
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Status -eq 'Up' -and $_.Name -ne $TunnelName -and
                ($_.Name -match '(?i)(wireguard|wintun|amnezia|warp|cloudflare|device[0-9_]+)' -or $_.InterfaceDescription -match '(?i)(wireguard|wintun|amnezia|warp|cloudflare)')
            } | ForEach-Object { $labels.Add("adapter:$($_.Name)") | Out-Null }
    } catch {
        Write-GreenLog 'adapter competition check failed'
    }
    try {
        Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -eq 'Running' -and
                $_.Name -notin @($WireGuardServiceName, $AmneziaWgServiceName) -and
                ($_.Name -like 'WireGuardTunnel$*' -or $_.Name -like 'AmneziaWGTunnel$*' -or $_.Name -match '(?i)CloudflareWARP')
            } | ForEach-Object { $labels.Add("service:$($_.Name)") | Out-Null }
    } catch {
        Write-GreenLog 'service competition check failed'
    }
    return @($labels | Sort-Object -Unique)
}

function Stop-OwnTunnel {
    foreach ($serviceName in @($WireGuardServiceName, $AmneziaWgServiceName)) {
        try {
            Invoke-External -FilePath 'sc.exe' -Arguments @('stop', $serviceName) -AllowedExitCodes @(0, 1056, 1060, 1062) | Out-Null
        } catch {
            Write-GreenLog "service stop warning: $serviceName"
        }
    }
    Start-Sleep -Milliseconds 500

    $wireGuard = Resolve-WireGuardExe
    if ($wireGuard) {
        try { Invoke-External -FilePath $wireGuard -Arguments @('/uninstalltunnelservice', $TunnelName) -AllowedExitCodes @(0, 1) | Out-Null } catch { Write-GreenLog 'WireGuard uninstall warning' }
    }
    $amneziaWg = Resolve-AmneziaWgExe
    if ($amneziaWg) {
        try { Invoke-External -FilePath $amneziaWg -Arguments @('/uninstalltunnelservice', $TunnelName) -AllowedExitCodes @(0, 1) | Out-Null } catch { Write-GreenLog 'AmneziaWG uninstall warning' }
    }
    Remove-EndpointBypassRoute
}

function Start-OwnTunnel {
    Ensure-GreenProgramDataAcl
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config missing: $ConfigPath" }
    $protocol = Get-ManagedProtocol
    $competitors = @(Get-CompetingVpnLabels)
    if ($competitors.Count -gt 0) {
        Write-GreenLog "connect blocked by competitor count=$($competitors.Count)"
        Stop-OwnTunnel
        exit 2
    }

    $engine = if ($protocol -eq 'amneziawg') { Resolve-AmneziaWgExe } else { Resolve-WireGuardExe }
    if ([string]::IsNullOrWhiteSpace($engine)) { throw "Engine unavailable for $protocol" }
    Stop-OwnTunnel
    Ensure-NativeFullTunnelKillSwitch
    Ensure-GreenProgramDataAcl
    Ensure-EndpointBypassRoute
    Invoke-External -FilePath $engine -Arguments @('/installtunnelservice', $ConfigPath) | Out-Null
    $serviceName = Get-SelectedServiceName -Protocol $protocol
    Invoke-External -FilePath 'sc.exe' -Arguments @('config', $serviceName, 'start=', 'demand') | Out-Null
    Invoke-External -FilePath 'sc.exe' -Arguments @('start', $serviceName) -AllowedExitCodes @(0, 1056) | Out-Null
}

function Invoke-GreenGuard {
    $ownRunning = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @($WireGuardServiceName, $AmneziaWgServiceName) -and $_.State -eq 'Running' })
    if ($ownRunning.Count -eq 0) { return }
    if (@(Get-CompetingVpnLabels).Count -gt 0) {
        Write-GreenLog 'guard disconnecting preview because a competing VPN is active'
        Stop-OwnTunnel
    }
}

try {
    Write-GreenLog 'started'
    switch ($Action) {
        'Connect' { Start-OwnTunnel }
        'Disconnect' { Ensure-GreenProgramDataAcl; Stop-OwnTunnel }
        'Guard' { Invoke-GreenGuard }
    }
    Write-GreenLog 'finished'
    exit 0
} catch {
    Write-GreenLog "failed: $($_.Exception.Message)"
    if ($Action -eq 'Connect') { Remove-EndpointBypassRoute }
    exit 10
}
