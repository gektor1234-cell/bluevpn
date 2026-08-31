param(
    [ValidateSet('Connect', 'Disconnect', 'Guard', 'ProbeStandby')]
    [string]$Action = 'Guard'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TunnelName = 'GreenVPNTransportPreview'
$WireGuardServiceName = 'WireGuardTunnel$GreenVPNTransportPreview'
$AmneziaWgServiceName = 'AmneziaWGTunnel$GreenVPNTransportPreview'
$HysteriaTunnelName = 'GreenVPNHysteriaPreview'
$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'
$ConfigPath = Join-Path $ProgramDataRoot 'GreenVPNTransportPreview.conf'
$ProtocolPath = $ConfigPath + '.protocol'
$EndpointRouteStatePath = $ConfigPath + '.endpoint-route.json'
$EndpointBypassRouteMetric = 42731
$HysteriaRouteMetric = 42732
$HysteriaSocksPort = 1980
$HysteriaToolRoot = Join-Path $PSScriptRoot 'hysteria2'
$HysteriaExe = Join-Path $HysteriaToolRoot 'hysteria-windows-amd64.exe'
$HevExe = Join-Path $HysteriaToolRoot 'hev-socks5-tunnel.exe'
$HevMsysDll = Join-Path $HysteriaToolRoot 'msys-2.0.dll'
$HevWintunDll = Join-Path $HysteriaToolRoot 'wintun.dll'
$HysteriaWatchdogScript = Join-Path $PSScriptRoot 'greenvpn_hysteria2_watchdog.ps1'
$HysteriaRuntimeConfigPath = Join-Path $ProgramDataRoot 'hysteria2-client.runtime.yaml'
$HevRuntimeConfigPath = Join-Path $ProgramDataRoot 'hysteria2-hev.runtime.yaml'
$HysteriaPidPath = Join-Path $ProgramDataRoot 'hysteria2-client.pid'
$HevPidPath = Join-Path $ProgramDataRoot 'hysteria2-hev.pid'
$HysteriaWatchdogPidPath = Join-Path $ProgramDataRoot 'hysteria2-watchdog.pid'
$HysteriaRouteStatePath = Join-Path $ProgramDataRoot 'hysteria2-routes.json'
$HysteriaStdoutPath = Join-Path $ProgramDataRoot 'hysteria2-client.stdout.log'
$HysteriaStderrPath = Join-Path $ProgramDataRoot 'hysteria2-client.stderr.log'
$HevStdoutPath = Join-Path $ProgramDataRoot 'hysteria2-hev.stdout.log'
$HevStderrPath = Join-Path $ProgramDataRoot 'hysteria2-hev.stderr.log'
$VlessTunnelName = 'GreenVPNVlessPreview'
$VlessRouteMetric = 42733
$VlessSocksPort = 1981
$VlessToolRoot = Join-Path $PSScriptRoot 'vless-reality'
$XrayExe = Join-Path $VlessToolRoot 'xray.exe'
$VlessHevExe = Join-Path $VlessToolRoot 'hev-socks5-tunnel.exe'
$VlessHevMsysDll = Join-Path $VlessToolRoot 'msys-2.0.dll'
$VlessHevWintunDll = Join-Path $VlessToolRoot 'wintun.dll'
$VlessWatchdogScript = Join-Path $PSScriptRoot 'greenvpn_vless_reality_watchdog.ps1'
$VlessRuntimeConfigPath = Join-Path $ProgramDataRoot 'vless-reality-client.runtime.json'
$VlessHevRuntimeConfigPath = Join-Path $ProgramDataRoot 'vless-reality-hev.runtime.yaml'
$XrayPidPath = Join-Path $ProgramDataRoot 'vless-reality-client.pid'
$VlessHevPidPath = Join-Path $ProgramDataRoot 'vless-reality-hev.pid'
$VlessWatchdogPidPath = Join-Path $ProgramDataRoot 'vless-reality-watchdog.pid'
$VlessRouteStatePath = Join-Path $ProgramDataRoot 'vless-reality-routes.json'
$XrayStdoutPath = Join-Path $ProgramDataRoot 'vless-reality-client.stdout.log'
$XrayStderrPath = Join-Path $ProgramDataRoot 'vless-reality-client.stderr.log'
$VlessHevStdoutPath = Join-Path $ProgramDataRoot 'vless-reality-hev.stdout.log'
$VlessHevStderrPath = Join-Path $ProgramDataRoot 'vless-reality-hev.stderr.log'
$NaiveTunnelName = 'GreenVPNNaivePreview'
$NaiveRouteMetric = 42734
$NaiveSocksPort = 1982
$NaiveCanaryPort = 8443
$NaiveToolRoot = Join-Path $PSScriptRoot 'naive-https'
$NaiveExe = Join-Path $NaiveToolRoot 'naive.exe'
$NaiveHevExe = Join-Path $NaiveToolRoot 'hev-socks5-tunnel.exe'
$NaiveHevMsysDll = Join-Path $NaiveToolRoot 'msys-2.0.dll'
$NaiveHevWintunDll = Join-Path $NaiveToolRoot 'wintun.dll'
$NaiveWatchdogScript = Join-Path $PSScriptRoot 'greenvpn_naive_https_watchdog.ps1'
$NaiveRuntimeConfigPath = Join-Path $ProgramDataRoot 'naive-https-client.runtime.json'
$NaiveHevRuntimeConfigPath = Join-Path $ProgramDataRoot 'naive-https-hev.runtime.yaml'
$NaivePidPath = Join-Path $ProgramDataRoot 'naive-https-client.pid'
$NaiveHevPidPath = Join-Path $ProgramDataRoot 'naive-https-hev.pid'
$NaiveWatchdogPidPath = Join-Path $ProgramDataRoot 'naive-https-watchdog.pid'
$NaiveRouteStatePath = Join-Path $ProgramDataRoot 'naive-https-routes.json'
$NaiveStdoutPath = Join-Path $ProgramDataRoot 'naive-https-client.stdout.log'
$NaiveStderrPath = Join-Path $ProgramDataRoot 'naive-https-client.stderr.log'
$NaiveHevStdoutPath = Join-Path $ProgramDataRoot 'naive-https-hev.stdout.log'
$NaiveHevStderrPath = Join-Path $ProgramDataRoot 'naive-https-hev.stderr.log'
$DnsttTunnelName = 'GreenVPNDnsttPreview'
$DnsttRouteMetric = 42735
$DnsttSocksPort = 1983
$DnsttZone = 't.greenvpn.pro'
$DnsttExpectedEgress = '5.129.216.42'
$StandbyProbeScript = Join-Path $PSScriptRoot 'greenvpn_standby_probe.ps1'
$StandbyProbeTunnelName = 'GreenVPNTransportPreviewStandbyProbe'
$StandbyProbeWireGuardServiceName = 'WireGuardTunnel$GreenVPNTransportPreviewStandbyProbe'
$StandbyProbeAmneziaServiceName = 'AmneziaWGTunnel$GreenVPNTransportPreviewStandbyProbe'
$StandbyProbeRequestPath = Join-Path $ProgramDataRoot 'standby-probe-request.json'
$StandbyProbeResultPath = Join-Path $ProgramDataRoot 'standby-probe-result.json'
$StandbyProbeRuntimeRoot = Join-Path $ProgramDataRoot 'standby-probe-runtime'
$StandbyProbeEndpointRouteMetric = 42739
$DnsttToolRoot = Join-Path $PSScriptRoot 'dnstt'
$DnsttExe = Join-Path $DnsttToolRoot 'dnstt-client-windows-amd64.exe'
$DnsttHevExe = Join-Path $DnsttToolRoot 'hev-socks5-tunnel.exe'
$DnsttHevMsysDll = Join-Path $DnsttToolRoot 'msys-2.0.dll'
$DnsttHevWintunDll = Join-Path $DnsttToolRoot 'wintun.dll'
$DnsttWatchdogScript = Join-Path $PSScriptRoot 'greenvpn_dnstt_watchdog.ps1'
$DnsttRuntimeConfigPath = Join-Path $ProgramDataRoot 'dnstt-client.runtime.json'
$DnsttHevRuntimeConfigPath = Join-Path $ProgramDataRoot 'dnstt-hev.runtime.yaml'
$DnsttPidPath = Join-Path $ProgramDataRoot 'dnstt-client.pid'
$DnsttHevPidPath = Join-Path $ProgramDataRoot 'dnstt-hev.pid'
$DnsttWatchdogPidPath = Join-Path $ProgramDataRoot 'dnstt-watchdog.pid'
$DnsttRouteStatePath = Join-Path $ProgramDataRoot 'dnstt-routes.json'
$DnsttStdoutPath = Join-Path $ProgramDataRoot 'dnstt-client.stdout.log'
$DnsttStderrPath = Join-Path $ProgramDataRoot 'dnstt-client.stderr.log'
$DnsttHevStdoutPath = Join-Path $ProgramDataRoot 'dnstt-hev.stdout.log'
$DnsttHevStderrPath = Join-Path $ProgramDataRoot 'dnstt-hev.stderr.log'
$LogPath = Join-Path $ProgramDataRoot 'backend.log'
$DiagnosticLogPath = Join-Path $ProgramDataRoot 'state\transport-task.log'
$CompetingVpnStatePath = Join-Path $ProgramDataRoot 'state\competing-vpn-services.json'
$DiagnosticLogAclReady = $false
$CompetingVpnTakeoverOccurred = $false
$ActiveRuntimeTransitionGeneration = $null
$SelectiveRoutingHelper = Join-Path $PSScriptRoot 'greenvpn_selective_routing.ps1'

$ExpectedHysteriaRuntimeHashes = @{
    'hysteria-windows-amd64.exe' = 'BCD3865B09BE2E5CC18D117DCF3AD687D1E6E27B0B050376B9CF4EA251B64D6F'
    'hev-socks5-tunnel.exe' = '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E'
    'msys-2.0.dll' = '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18'
    'wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
}
$ExpectedVlessRuntimeHashes = @{
    'xray.exe' = '4B43C5EF596F326B233717B585D31A85DD5CD5F77D8DA872E75F7EBC00E99ACB'
    'hev-socks5-tunnel.exe' = '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E'
    'msys-2.0.dll' = '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18'
    'wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
}
$ExpectedNaiveRuntimeHashes = @{
    'naive.exe' = '94F99801C665D29FC071624663C6F7BFA59E8D5EFAA84CD08EF5EBB18B46CB62'
    'hev-socks5-tunnel.exe' = '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E'
    'msys-2.0.dll' = '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18'
    'wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
}
$ExpectedDnsttRuntimeHashes = @{
    'dnstt-client-windows-amd64.exe' = '282995EA68FD13514AC033BC953193AD11CF01F83BB6E3F97929089E5BD85A99'
    'hev-socks5-tunnel.exe' = '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E'
    'msys-2.0.dll' = '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18'
    'wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
}

if (-not (Test-Path -LiteralPath $SelectiveRoutingHelper -PathType Leaf)) {
    throw "Selective routing helper is missing: $SelectiveRoutingHelper"
}
. $SelectiveRoutingHelper

function Ensure-DiagnosticLogAccess {
    if ($script:DiagnosticLogAclReady) { return }
    $directory = Split-Path -Parent $DiagnosticLogPath
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    if (-not (Test-Path -LiteralPath $DiagnosticLogPath -PathType Leaf)) {
        New-Item -ItemType File -Force -Path $DiagnosticLogPath | Out-Null
    }
    $acl = Get-Acl -LiteralPath $DiagnosticLogPath
    $acl.SetAccessRuleProtection($false, $true)
    Set-Acl -LiteralPath $DiagnosticLogPath -AclObject $acl
    $script:DiagnosticLogAclReady = $true
}

function Write-GreenLog {
    param([string]$Message)
    $line = "[$((Get-Date).ToString('o'))] transport-task($Action) $Message"
    try {
        New-Item -ItemType Directory -Force -Path $ProgramDataRoot | Out-Null
        Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value $line
    } catch {
    }
    try {
        Ensure-DiagnosticLogAccess
        Add-Content -LiteralPath $DiagnosticLogPath -Encoding UTF8 -Value $line
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

function Assert-HysteriaRuntime {
    foreach ($entry in $ExpectedHysteriaRuntimeHashes.GetEnumerator()) {
        $path = Join-Path $HysteriaToolRoot $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Hysteria2 preview runtime is missing: $($entry.Key)"
        }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $entry.Value) {
            throw "Hysteria2 preview runtime hash mismatch: $($entry.Key)"
        }
    }
    if (-not (Test-Path -LiteralPath $HysteriaWatchdogScript -PathType Leaf)) {
        throw 'Hysteria2 preview watchdog is missing.'
    }
}

function Assert-VlessRuntime {
    foreach ($entry in $ExpectedVlessRuntimeHashes.GetEnumerator()) {
        $path = Join-Path $VlessToolRoot $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "VLESS REALITY preview runtime is missing: $($entry.Key)"
        }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $entry.Value) {
            throw "VLESS REALITY preview runtime hash mismatch: $($entry.Key)"
        }
    }
    if (-not (Test-Path -LiteralPath $VlessWatchdogScript -PathType Leaf)) {
        throw 'VLESS REALITY preview watchdog is missing.'
    }
}

function Assert-NaiveRuntime {
    foreach ($entry in $ExpectedNaiveRuntimeHashes.GetEnumerator()) {
        $path = Join-Path $NaiveToolRoot $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Naive HTTPS preview runtime is missing: $($entry.Key)"
        }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $entry.Value) {
            throw "Naive HTTPS preview runtime hash mismatch: $($entry.Key)"
        }
    }
    if (-not (Test-Path -LiteralPath $NaiveWatchdogScript -PathType Leaf)) {
        throw 'Naive HTTPS preview watchdog is missing.'
    }
}

function Assert-DnsttRuntime {
    foreach ($entry in $ExpectedDnsttRuntimeHashes.GetEnumerator()) {
        $path = Join-Path $DnsttToolRoot $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "dnstt preview runtime is missing: $($entry.Key)"
        }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $entry.Value) {
            throw "dnstt preview runtime hash mismatch: $($entry.Key)"
        }
    }
    if (-not (Test-Path -LiteralPath $DnsttWatchdogScript -PathType Leaf)) {
        throw 'dnstt preview watchdog is missing.'
    }
}

function Get-ManagedProtocol {
    if (-not (Test-Path -LiteralPath $ProtocolPath)) { return 'wireguard_udp' }
    $value = (Get-Content -LiteralPath $ProtocolPath -Raw -ErrorAction Stop).Trim().ToLowerInvariant()
    if ($value -notin @('wireguard_udp', 'amneziawg', 'hysteria2', 'vless_reality', 'naive_https', 'dnstt')) {
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
    if (-not (Test-Path -LiteralPath $ProgramDataRoot -PathType Container)) {
        throw 'Protected transport preview state directory is missing.'
    }
    $broadSids = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545')
    $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor `
        [Security.AccessControl.FileSystemRights]::Modify -bor `
        [Security.AccessControl.FileSystemRights]::FullControl
    foreach ($path in @(
        $ProgramDataRoot,
        $ConfigPath,
        $ProtocolPath,
        $RoutingModePath,
        $RoutingAppsPath
    )) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Transport preview state must not be a reparse point: $path"
        }
        foreach ($ace in (Get-Acl -LiteralPath $path).Access) {
            if ($ace.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { continue }
            try {
                $sid = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            } catch {
                continue
            }
            if ($sid -in $broadSids -and (($ace.FileSystemRights -band $writeMask) -ne 0)) {
                throw "Broad write ACL is forbidden for transport preview state: $path sid=$sid"
            }
        }
    }
}

function Get-ManagedIpv4Endpoint {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config missing: $ConfigPath" }
    $protocol = Get-ManagedProtocol
    if ($protocol -eq 'dnstt') {
        $root = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        $resolvers = @($root.resolvers)
        if ($resolvers.Count -lt 1 -or [string]$resolvers[0].mode -ne 'doh' -or
            [string]$resolvers[0].endpoint -ne 'https://1.1.1.1/dns-query') {
            throw 'Windows dnstt preview resolver is not the guarded DoH endpoint.'
        }
        return '1.1.1.1'
    }
    if ($protocol -eq 'naive_https') {
        $root = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        $proxy = [Uri][string]$root.proxy
        $endpointIp = [string]$root.endpointIp
        $guardedEndpoints = @{
            'nl2.vpn.greenvpn.pro' = '5.129.216.42'
            'nl1.vpn.greenvpn.pro' = '37.220.85.211'
            '88-218-250-86.sslip.io' = '88.218.250.86'
        }
        $expectedIp = $guardedEndpoints[$proxy.Host.ToLowerInvariant()]
        if ($proxy.Scheme -ne 'https' -or $proxy.Port -ne $NaiveCanaryPort -or
            [string]::IsNullOrWhiteSpace([string]$expectedIp) -or $endpointIp -ne $expectedIp) {
            throw 'Windows Naive HTTPS preview endpoint is not the guarded canary.'
        }
        return $endpointIp
    }
    if ($protocol -eq 'vless_reality') {
        $root = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        $candidate = [string]$root.outbounds[0].settings.vnext[0].address
        $address = $null
        if (-not [Net.IPAddress]::TryParse($candidate, [ref]$address) -or
            $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
            throw 'Windows VLESS preview endpoint is not valid IPv4.'
        }
        $candidatePort = [int]$root.outbounds[0].settings.vnext[0].port
        if ("$($address.IPAddressToString):$candidatePort" -notin @(
            '5.129.216.42:443',
            '37.220.85.211:443',
            '88.218.250.86:9443'
        )) {
            throw 'Windows VLESS preview endpoint passport is not allowlisted.'
        }
        return $address.IPAddressToString
    }
    $configText = [IO.File]::ReadAllText($ConfigPath)
    $pattern = if ($protocol -eq 'hysteria2') {
        '(?im)^\s*server\s*:\s*(\d{1,3}(?:\.\d{1,3}){3}):\d+\s*$'
    } else {
        '(?im)^\s*Endpoint\s*=\s*(\d{1,3}(?:\.\d{1,3}){3}):\d+\s*$'
    }
    $match = [regex]::Match($configText, $pattern)
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
        $validState = $state.created -eq $true -and
            [int]$state.metric -eq $EndpointBypassRouteMetric -and
            [string]$state.endpoint -match '^\d{1,3}(?:\.\d{1,3}){3}$'
        if ($validState -and (Test-Path -LiteralPath $ConfigPath)) {
            $validState = [string]$state.endpoint -eq (Get-ManagedIpv4Endpoint)
        }
        if ($validState) {
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

function Get-SafePhysicalEndpointRoute {
    param(
        [Parameter(Mandatory=$true)][string]$Endpoint,
        [int]$MaxAttempts = 24
    )

    for ($attempt = 0; $attempt -lt $MaxAttempts; $attempt++) {
        $selection = @()
        try {
            $selection = @(Find-NetRoute -RemoteIPAddress $endpoint -ErrorAction Stop)
        } catch {
        }
        foreach ($candidate in @(
            $selection |
                Where-Object { $_.CimClass.CimClassName -eq 'MSFT_NetRoute' }
        )) {
            $nextHop = [string]$candidate.NextHop
            if ([string]::IsNullOrWhiteSpace($nextHop) -or $nextHop -eq '0.0.0.0') {
                continue
            }
            $adapter = Get-NetAdapter -InterfaceIndex ([int]$candidate.InterfaceIndex) `
                -ErrorAction SilentlyContinue
            if ($null -eq $adapter -or [string]$adapter.Status -ne 'Up') {
                continue
            }
            if (
                [string]$adapter.Name -in @(
                    $TunnelName,
                    $HysteriaTunnelName,
                    $VlessTunnelName,
                    $NaiveTunnelName,
                    $DnsttTunnelName
                ) -or
                [string]$adapter.Name -match '(?i)(wireguard|wintun|amnezia|warp|cloudflare|device[0-9_]+)' -or
                [string]$adapter.InterfaceDescription -match '(?i)(wireguard|wintun|amnezia|warp|cloudflare)'
            ) {
                continue
            }
            Write-GreenLog "physical gateway settled after takeover attempt=$attempt ifIndex=$($candidate.InterfaceIndex)"
            return $candidate
        }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

function Ensure-EndpointBypassRoute {
    Remove-EndpointBypassRoute
    $endpoint = Get-ManagedIpv4Endpoint
    $route = Get-SafePhysicalEndpointRoute -Endpoint $endpoint
    if ($null -eq $route) {
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
        metric = $EndpointBypassRouteMetric
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

function Write-PrivateRuntimeFile {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
    Protect-PrivateRuntimeFile -Path $Path
}

function Write-GreenActiveRoutingMode {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('full', 'applications')][string]$Mode,
        [Parameter(Mandatory=$true)][bool]$ProcessRouterRequired,
        [Parameter(Mandatory=$true)][uint32]$TransitionGeneration
    )
    Remove-GreenPrivilegedRuntimeValue -Name 'ActiveRoutingMode'
    Confirm-GreenProcessRouterRuntimeContract -Required $ProcessRouterRequired
    Write-GreenPrivilegedRuntimeValue `
        -Name 'ActiveRoutingMode' `
        -Value $Mode `
        -PropertyType String
    $committedMode = [string](
        Read-GreenPrivilegedRuntimeValue -Name 'ActiveRoutingMode'
    )
    try {
        if ($committedMode -ne $Mode) {
            throw 'Privileged active routing mode readback failed.'
        }
        Confirm-GreenProcessRouterRuntimeContract `
            -Required $ProcessRouterRequired
        Complete-GreenRuntimeStateTransition `
            -TransitionGeneration $TransitionGeneration
    } catch {
        Remove-GreenPrivilegedRuntimeValue -Name 'ActiveRoutingMode'
        throw
    }
    Write-GreenLog "active routing mode committed mode=$Mode routerRequired=$ProcessRouterRequired generation=$($TransitionGeneration + 1)"
}

function Protect-PrivateRuntimeFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Private runtime file is missing: $Path"
    }
    & attrib.exe +H $Path 2>$null | Out-Null
    & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to protect runtime file: $Path" }
}

function Read-ManagedPid {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $value = 0
    if (-not [int]::TryParse((Get-Content -LiteralPath $Path -Raw).Trim(), [ref]$value) -or $value -le 0) {
        return 0
    }
    return $value
}

function Test-ExactProcess {
    param([int]$ProcessId, [string]$ExpectedPath)
    if ($ProcessId -le 0) { return $false }
    try {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
        if ($null -eq $process -or [string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) { return $false }
        return [IO.Path]::GetFullPath([string]$process.ExecutablePath).Equals(
            [IO.Path]::GetFullPath($ExpectedPath),
            [StringComparison]::OrdinalIgnoreCase
        )
    } catch {
        return $false
    }
}

function Stop-ExactProcessFromState {
    param([string]$PidPath, [string]$ExpectedPath)
    $pidValue = Read-ManagedPid -Path $PidPath
    if (Test-ExactProcess -ProcessId $pidValue -ExpectedPath $ExpectedPath) {
        Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
}

function Stop-HysteriaWatchdog {
    $pidValue = Read-ManagedPid -Path $HysteriaWatchdogPidPath
    if ($pidValue -gt 0) {
        try {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId=$pidValue" -ErrorAction Stop
            $expectedPowerShell = [IO.Path]::GetFullPath((Join-Path $PSHOME 'powershell.exe'))
            $actual = [IO.Path]::GetFullPath([string]$process.ExecutablePath)
            $command = [string]$process.CommandLine
            if ($actual.Equals($expectedPowerShell, [StringComparison]::OrdinalIgnoreCase) -and
                $command.IndexOf($HysteriaWatchdogScript, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Remove-Item -LiteralPath $HysteriaWatchdogPidPath -Force -ErrorAction SilentlyContinue
}

function Remove-HysteriaRoutes {
    if (-not (Test-Path -LiteralPath $HysteriaRouteStatePath)) { return }
    try {
        $state = Get-Content -LiteralPath $HysteriaRouteStatePath -Raw | ConvertFrom-Json
        if ([int]$state.metric -ne $HysteriaRouteMetric) { return }
        foreach ($prefix in @($state.prefixes)) {
            if ($prefix -notin @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')) { continue }
            Get-NetRoute -DestinationPrefix $prefix -InterfaceIndex ([int]$state.interfaceIndex) -ErrorAction SilentlyContinue |
                Where-Object { $_.RouteMetric -eq $HysteriaRouteMetric } |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        }
    } catch {
        Write-GreenLog 'Hysteria2 route cleanup warning'
    } finally {
        Remove-Item -LiteralPath $HysteriaRouteStatePath -Force -ErrorAction SilentlyContinue
    }
}

function Stop-Hysteria2Tunnel {
    Stop-HysteriaWatchdog
    Stop-ExactProcessFromState -PidPath $HevPidPath -ExpectedPath $HevExe
    Stop-ExactProcessFromState -PidPath $HysteriaPidPath -ExpectedPath $HysteriaExe
    Remove-HysteriaRoutes
    foreach ($path in @($HysteriaRuntimeConfigPath, $HevRuntimeConfigPath)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Stop-VlessWatchdog {
    $pidValue = Read-ManagedPid -Path $VlessWatchdogPidPath
    if ($pidValue -gt 0) {
        try {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId=$pidValue" -ErrorAction Stop
            $expectedPowerShell = [IO.Path]::GetFullPath((Join-Path $PSHOME 'powershell.exe'))
            $actual = [IO.Path]::GetFullPath([string]$process.ExecutablePath)
            $command = [string]$process.CommandLine
            if ($actual.Equals($expectedPowerShell, [StringComparison]::OrdinalIgnoreCase) -and
                $command.IndexOf($VlessWatchdogScript, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Remove-Item -LiteralPath $VlessWatchdogPidPath -Force -ErrorAction SilentlyContinue
}

function Remove-VlessRoutes {
    if (-not (Test-Path -LiteralPath $VlessRouteStatePath)) { return }
    try {
        $state = Get-Content -LiteralPath $VlessRouteStatePath -Raw | ConvertFrom-Json
        if ([int]$state.metric -ne $VlessRouteMetric) { return }
        foreach ($prefix in @($state.prefixes)) {
            if ($prefix -notin @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')) { continue }
            Get-NetRoute -DestinationPrefix $prefix -InterfaceIndex ([int]$state.interfaceIndex) -ErrorAction SilentlyContinue |
                Where-Object { $_.RouteMetric -eq $VlessRouteMetric } |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        }
    } catch {
        Write-GreenLog 'VLESS REALITY route cleanup warning'
    } finally {
        Remove-Item -LiteralPath $VlessRouteStatePath -Force -ErrorAction SilentlyContinue
    }
}

function Stop-VlessRealityTunnel {
    Stop-VlessWatchdog
    Stop-ExactProcessFromState -PidPath $VlessHevPidPath -ExpectedPath $VlessHevExe
    Stop-ExactProcessFromState -PidPath $XrayPidPath -ExpectedPath $XrayExe
    Remove-VlessRoutes
    foreach ($path in @($VlessRuntimeConfigPath, $VlessHevRuntimeConfigPath)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Stop-NaiveWatchdog {
    $pidValue = Read-ManagedPid -Path $NaiveWatchdogPidPath
    if ($pidValue -gt 0) {
        try {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId=$pidValue" -ErrorAction Stop
            $expectedPowerShell = [IO.Path]::GetFullPath((Join-Path $PSHOME 'powershell.exe'))
            $actual = [IO.Path]::GetFullPath([string]$process.ExecutablePath)
            $command = [string]$process.CommandLine
            if ($actual.Equals($expectedPowerShell, [StringComparison]::OrdinalIgnoreCase) -and
                $command.IndexOf($NaiveWatchdogScript, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Remove-Item -LiteralPath $NaiveWatchdogPidPath -Force -ErrorAction SilentlyContinue
}

function Remove-NaiveRoutes {
    if (-not (Test-Path -LiteralPath $NaiveRouteStatePath)) { return }
    try {
        $state = Get-Content -LiteralPath $NaiveRouteStatePath -Raw | ConvertFrom-Json
        if ([int]$state.metric -ne $NaiveRouteMetric) { return }
        foreach ($prefix in @($state.prefixes)) {
            if ($prefix -notin @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')) { continue }
            Get-NetRoute -DestinationPrefix $prefix -InterfaceIndex ([int]$state.interfaceIndex) -ErrorAction SilentlyContinue |
                Where-Object { $_.RouteMetric -eq $NaiveRouteMetric } |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        }
    } catch {
        Write-GreenLog 'Naive HTTPS route cleanup warning'
    } finally {
        Remove-Item -LiteralPath $NaiveRouteStatePath -Force -ErrorAction SilentlyContinue
    }
}

function Stop-NaiveHttpsTunnel {
    Stop-NaiveWatchdog
    Stop-ExactProcessFromState -PidPath $NaiveHevPidPath -ExpectedPath $NaiveHevExe
    Stop-ExactProcessFromState -PidPath $NaivePidPath -ExpectedPath $NaiveExe
    Remove-NaiveRoutes
    foreach ($path in @(
        $NaiveRuntimeConfigPath,
        $NaiveHevRuntimeConfigPath,
        $NaiveStdoutPath,
        $NaiveStderrPath,
        $NaiveHevStdoutPath,
        $NaiveHevStderrPath
    )) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Stop-DnsttWatchdog {
    $pidValue = Read-ManagedPid -Path $DnsttWatchdogPidPath
    if ($pidValue -gt 0) {
        try {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId=$pidValue" -ErrorAction Stop
            $expectedPowerShell = [IO.Path]::GetFullPath((Join-Path $PSHOME 'powershell.exe'))
            $actual = [IO.Path]::GetFullPath([string]$process.ExecutablePath)
            $command = [string]$process.CommandLine
            if ($actual.Equals($expectedPowerShell, [StringComparison]::OrdinalIgnoreCase) -and
                $command.IndexOf($DnsttWatchdogScript, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Remove-Item -LiteralPath $DnsttWatchdogPidPath -Force -ErrorAction SilentlyContinue
}

function Remove-DnsttRoutes {
    if (-not (Test-Path -LiteralPath $DnsttRouteStatePath)) { return }
    try {
        $state = Get-Content -LiteralPath $DnsttRouteStatePath -Raw | ConvertFrom-Json
        if ([int]$state.metric -ne $DnsttRouteMetric) { return }
        foreach ($prefix in @($state.prefixes)) {
            if ($prefix -notin @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')) { continue }
            Get-NetRoute -DestinationPrefix $prefix -InterfaceIndex ([int]$state.interfaceIndex) -ErrorAction SilentlyContinue |
                Where-Object { $_.RouteMetric -eq $DnsttRouteMetric } |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        }
    } catch {
        Write-GreenLog 'dnstt route cleanup warning'
    } finally {
        Remove-Item -LiteralPath $DnsttRouteStatePath -Force -ErrorAction SilentlyContinue
    }
}

function Stop-DnsttTunnel {
    Stop-DnsttWatchdog
    Stop-ExactProcessFromState -PidPath $DnsttHevPidPath -ExpectedPath $DnsttHevExe
    Stop-ExactProcessFromState -PidPath $DnsttPidPath -ExpectedPath $DnsttExe
    Remove-DnsttRoutes
    foreach ($path in @(
        $DnsttRuntimeConfigPath,
        $DnsttHevRuntimeConfigPath,
        $DnsttStdoutPath,
        $DnsttStderrPath,
        $DnsttHevStdoutPath,
        $DnsttHevStderrPath
    )) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Wait-LocalTcpPort {
    param([int]$Port, [int]$Seconds = 15)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $client = [Net.Sockets.TcpClient]::new()
        try {
            $pending = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
            if ($pending.AsyncWaitHandle.WaitOne(250) -and $client.Connected) {
                $client.EndConnect($pending)
                return
            }
        } catch {
        } finally {
            $client.Dispose()
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Local TCP port did not become ready: $Port"
}

function Wait-HysteriaAdapter {
    param([int]$Seconds = 20)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $adapter = Get-NetAdapter -Name $HysteriaTunnelName -ErrorAction SilentlyContinue
        if ($null -ne $adapter -and $adapter.Status -eq 'Up') { return $adapter }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    throw 'Hysteria2 preview adapter did not become ready.'
}

function New-HysteriaRuntimeConfigs {
    $configText = [IO.File]::ReadAllText($ConfigPath)
    if ($configText -match '(?im)^\s*(socks5|http|tun|tcpForwarding|udpForwarding)\s*:') {
        throw 'Hysteria2 base config must not contain local listener or forwarding sections.'
    }
    foreach ($required in @(
        '(?im)^\s*server\s*:\s*\d{1,3}(?:\.\d{1,3}){3}:\d+\s*$',
        '(?im)^\s*auth\s*:\s*\S.+$',
        '(?im)^\s*sni\s*:\s*[a-z0-9.-]+\s*$',
        '(?im)^\s*insecure\s*:\s*false\s*$',
        '(?im)^\s*type\s*:\s*salamander\s*$',
        '(?im)^\s*password\s*:\s*\S.+$'
    )) {
        if ($configText -notmatch $required) { throw 'Hysteria2 base config failed the safe profile contract.' }
    }

    $hysteriaRuntime = $configText.TrimEnd() + "`r`n" + @"
socks5:
  listen: 127.0.0.1:$HysteriaSocksPort
"@
    $hevRuntime = @"
tunnel:
  name: $HysteriaTunnelName
  mtu: 1400
  ipv4: 198.18.0.1
  ipv6: 'fc00::1'
socks5:
  port: $HysteriaSocksPort
  address: 127.0.0.1
  udp: 'udp'
misc:
  log-file: stderr
  log-level: warn
  task-stack-size: 86016
  connect-timeout: 10000
  tcp-read-write-timeout: 300000
  udp-read-write-timeout: 60000
"@
    Write-PrivateRuntimeFile -Path $HysteriaRuntimeConfigPath -Content $hysteriaRuntime
    Write-PrivateRuntimeFile -Path $HevRuntimeConfigPath -Content $hevRuntime
}

function Add-HysteriaRoutes {
    param([int]$InterfaceIndex)
    $prefixes = @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')
    foreach ($prefix in $prefixes) {
        $family = if ($prefix.Contains(':')) { 'IPv6' } else { 'IPv4' }
        $nextHop = if ($family -eq 'IPv6') { '::' } else { '0.0.0.0' }
        Get-NetRoute -AddressFamily $family -DestinationPrefix $prefix -InterfaceIndex $InterfaceIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.RouteMetric -eq $HysteriaRouteMetric } |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        New-NetRoute -AddressFamily $family -DestinationPrefix $prefix -InterfaceIndex $InterfaceIndex `
            -NextHop $nextHop -RouteMetric $HysteriaRouteMetric -PolicyStore ActiveStore -ErrorAction Stop | Out-Null
    }
    Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses @('1.1.1.1', '1.0.0.1') -ErrorAction Stop
    [ordered]@{
        interfaceIndex = $InterfaceIndex
        metric = $HysteriaRouteMetric
        prefixes = $prefixes
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $HysteriaRouteStatePath -Encoding ASCII
    & attrib.exe +H $HysteriaRouteStatePath 2>$null | Out-Null
    & icacls.exe $HysteriaRouteStatePath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
}

function Start-Hysteria2Tunnel {
    Assert-HysteriaRuntime
    New-HysteriaRuntimeConfigs
    Ensure-EndpointBypassRoute

    foreach ($path in @($HysteriaStdoutPath, $HysteriaStderrPath, $HevStdoutPath, $HevStderrPath)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    $hysteria = Start-Process -FilePath $HysteriaExe -ArgumentList @(
        'client', '--disable-update-check', '--log-level', 'warn', '--config', $HysteriaRuntimeConfigPath
    ) -WorkingDirectory $HysteriaToolRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $HysteriaStdoutPath -RedirectStandardError $HysteriaStderrPath
    Write-PrivateRuntimeFile -Path $HysteriaPidPath -Content ([string]$hysteria.Id)
    Wait-LocalTcpPort -Port $HysteriaSocksPort

    $hev = Start-Process -FilePath $HevExe -ArgumentList @($HevRuntimeConfigPath) `
        -WorkingDirectory $HysteriaToolRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $HevStdoutPath -RedirectStandardError $HevStderrPath
    Write-PrivateRuntimeFile -Path $HevPidPath -Content ([string]$hev.Id)
    $adapter = Wait-HysteriaAdapter
    Add-HysteriaRoutes -InterfaceIndex ([int]$adapter.ifIndex)

    $watchdog = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $HysteriaWatchdogScript + '"'),
        '-HysteriaPid', $hysteria.Id,
        '-HevPid', $hev.Id
    ) -WindowStyle Hidden -PassThru
    Write-PrivateRuntimeFile -Path $HysteriaWatchdogPidPath -Content ([string]$watchdog.Id)

    if (-not (Test-ExactProcess -ProcessId $hysteria.Id -ExpectedPath $HysteriaExe) -or
        -not (Test-ExactProcess -ProcessId $hev.Id -ExpectedPath $HevExe)) {
        throw 'Hysteria2 preview engine exited during startup.'
    }
    Write-GreenLog "Hysteria2 preview started ifIndex=$($adapter.ifIndex)"
}

function Wait-VlessAdapter {
    param([int]$Seconds = 20)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $adapter = Get-NetAdapter -Name $VlessTunnelName -ErrorAction SilentlyContinue
        if ($null -ne $adapter -and $adapter.Status -eq 'Up') { return $adapter }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    throw 'VLESS REALITY preview adapter did not become ready.'
}

function New-VlessRuntimeConfigs {
    $configText = [IO.File]::ReadAllText($ConfigPath)
    $root = $configText | ConvertFrom-Json
    if (@($root.inbounds).Count -ne 1 -or [string]$root.inbounds[0].protocol -ne 'socks' -or
        [string]$root.inbounds[0].listen -ne '127.0.0.1' -or [int]$root.inbounds[0].port -ne $VlessSocksPort -or
        $root.inbounds[0].settings.udp -ne $true) {
        throw 'VLESS REALITY profile must expose exactly one guarded loopback SOCKS listener.'
    }
    $outbound = $root.outbounds[0]
    $server = $outbound.settings.vnext[0]
    $user = $server.users[0]
    $stream = $outbound.streamSettings
    if ([string]$outbound.protocol -ne 'vless' -or
        "$([string]$server.address):$([int]$server.port)" -notin @(
            '5.129.216.42:443',
            '37.220.85.211:443',
            '88.218.250.86:9443'
        ) -or
        [string]$user.encryption -ne 'none' -or [string]::IsNullOrWhiteSpace([string]$user.id) -or
        [string]$stream.network -ne 'xhttp' -or [string]$stream.security -ne 'reality' -or
        [string]::IsNullOrWhiteSpace([string]$stream.realitySettings.serverName) -or
        [string]::IsNullOrWhiteSpace([string]$stream.realitySettings.password) -or
        [string]::IsNullOrWhiteSpace([string]$stream.realitySettings.shortId) -or
        [string]::IsNullOrWhiteSpace([string]$stream.xhttpSettings.path)) {
        throw 'VLESS REALITY profile failed the safe XHTTP contract.'
    }
    $user | Add-Member -NotePropertyName packetEncoding -NotePropertyValue 'xudp' -Force
    $stream.xhttpSettings | Add-Member -NotePropertyName mode -NotePropertyValue 'stream-up' -Force
    $stream.xhttpSettings | Add-Member -NotePropertyName extra -NotePropertyValue ([pscustomobject]@{
        xmux = [pscustomobject]@{
            maxConnections = 1
            cMaxReuseTimes = '128-256'
            hMaxRequestTimes = '1000-2000'
            hMaxReusableSecs = '600-900'
            hKeepAlivePeriod = 30
        }
    }) -Force
    $endpoint = Get-ManagedIpv4Endpoint
    if ([string]$server.address -ne $endpoint) { throw 'VLESS REALITY profile endpoint is inconsistent.' }
    if (-not (Test-Path -LiteralPath $EndpointRouteStatePath)) {
        throw 'VLESS REALITY endpoint route state is missing.'
    }
    $endpointRoute = Get-Content -LiteralPath $EndpointRouteStatePath -Raw | ConvertFrom-Json
    $physicalAdapter = Get-NetAdapter -InterfaceIndex ([int]$endpointRoute.interfaceIndex) -ErrorAction Stop
    if ($null -eq $physicalAdapter -or $physicalAdapter.Name -in @($TunnelName, $HysteriaTunnelName, $VlessTunnelName, $NaiveTunnelName, $DnsttTunnelName)) {
        throw 'VLESS REALITY could not resolve a safe physical outbound interface.'
    }
    $physicalAddress = Get-NetIPAddress -InterfaceIndex ([int]$endpointRoute.interfaceIndex) -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.AddressState -eq 'Preferred' } |
        Select-Object -First 1
    if ($null -eq $physicalAddress) { throw 'VLESS REALITY physical IPv4 source address is unavailable.' }
    $sockopt = if ($null -ne $stream.PSObject.Properties['sockopt']) {
        $stream.sockopt
    } else {
        [pscustomobject]@{}
    }
    $sockopt | Add-Member -NotePropertyName interface -NotePropertyValue ([string]$physicalAdapter.Name) -Force
    $stream | Add-Member -NotePropertyName sockopt -NotePropertyValue $sockopt -Force
    $outbound | Add-Member -NotePropertyName sendThrough -NotePropertyValue ([string]$physicalAddress.IPAddress) -Force
    $blockOutbound = [pscustomobject]@{
        protocol = 'blackhole'
        tag = 'block'
    }
    $existingBlock = @($root.outbounds | Where-Object { [string]$_.tag -eq 'block' })
    if ($existingBlock.Count -eq 0) {
        $root.outbounds = @($root.outbounds) + @($blockOutbound)
    }
    $dnsOutbound = [pscustomobject]@{
        protocol = 'dns'
        tag = 'dns-out'
        settings = [pscustomobject]@{
            rules = @(
                [pscustomobject]@{
                    action = 'hijack'
                    qType = '1,28'
                }
            )
        }
    }
    $existingDns = @($root.outbounds | Where-Object { [string]$_.tag -eq 'dns-out' })
    if ($existingDns.Count -eq 0) {
        $root.outbounds = @($root.outbounds) + @($dnsOutbound)
    }
    $root | Add-Member -NotePropertyName dns -NotePropertyValue ([pscustomobject]@{
        queryStrategy = 'UseIPv4'
        servers = @(
            [pscustomobject]@{
                address = 'https://1.1.1.1/dns-query'
                queryStrategy = 'UseIPv4'
                skipFallback = $true
                finalQuery = $true
                tag = 'dns-upstream'
            }
        )
    }) -Force
    $root | Add-Member -NotePropertyName routing -NotePropertyValue ([pscustomobject]@{
        domainStrategy = 'AsIs'
        rules = @(
            [pscustomobject]@{
                type = 'field'
                port = '53'
                outboundTag = 'dns-out'
            },
            [pscustomobject]@{
                type = 'field'
                network = 'udp'
                port = '443'
                outboundTag = 'block'
            },
            [pscustomobject]@{
                type = 'field'
                ip = @(
                    '0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8',
                    '169.254.0.0/16', '172.16.0.0/12', '192.0.0.0/24', '192.168.0.0/16',
                    '198.18.0.0/15', '224.0.0.0/4', '240.0.0.0/4',
                    '::1/128', 'fc00::/7', 'fe80::/10', 'ff00::/8'
                )
                outboundTag = 'block'
            }
        )
    }) -Force

    $hevRuntime = @"
tunnel:
  name: $VlessTunnelName
  mtu: 1400
  ipv4: 198.18.1.1
  ipv6: 'fc00:1::1'
socks5:
  port: $VlessSocksPort
  address: 127.0.0.1
  udp: 'udp'
mapdns:
  address: 198.18.1.2
  port: 53
  network: 100.64.0.0
  netmask: 255.192.0.0
  cache-size: 10000
misc:
  log-file: stderr
  log-level: warn
  task-stack-size: 86016
  connect-timeout: 10000
  tcp-read-write-timeout: 300000
  udp-read-write-timeout: 60000
"@
    Write-PrivateRuntimeFile -Path $VlessRuntimeConfigPath -Content ($root | ConvertTo-Json -Depth 100)
    Write-PrivateRuntimeFile -Path $VlessHevRuntimeConfigPath -Content $hevRuntime
}

function Add-VlessRoutes {
    param([int]$InterfaceIndex)
    $prefixes = @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')
    foreach ($prefix in $prefixes) {
        $family = if ($prefix.Contains(':')) { 'IPv6' } else { 'IPv4' }
        $nextHop = if ($family -eq 'IPv6') { '::' } else { '0.0.0.0' }
        Get-NetRoute -AddressFamily $family -DestinationPrefix $prefix -InterfaceIndex $InterfaceIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.RouteMetric -eq $VlessRouteMetric } |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        New-NetRoute -AddressFamily $family -DestinationPrefix $prefix -InterfaceIndex $InterfaceIndex `
            -NextHop $nextHop -RouteMetric $VlessRouteMetric -PolicyStore ActiveStore -ErrorAction Stop | Out-Null
    }
    Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses @('198.18.1.2') -ErrorAction Stop
    [ordered]@{
        interfaceIndex = $InterfaceIndex
        metric = $VlessRouteMetric
        prefixes = $prefixes
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $VlessRouteStatePath -Encoding ASCII
    & attrib.exe +H $VlessRouteStatePath 2>$null | Out-Null
    & icacls.exe $VlessRouteStatePath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
}

function Start-VlessRealityTunnel {
    Assert-VlessRuntime
    Ensure-EndpointBypassRoute
    New-VlessRuntimeConfigs

    foreach ($path in @($XrayStdoutPath, $XrayStderrPath, $VlessHevStdoutPath, $VlessHevStderrPath)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    $xray = Start-Process -FilePath $XrayExe -ArgumentList @(
        'run', '-config', $VlessRuntimeConfigPath
    ) -WorkingDirectory $VlessToolRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $XrayStdoutPath -RedirectStandardError $XrayStderrPath
    Write-PrivateRuntimeFile -Path $XrayPidPath -Content ([string]$xray.Id)
    Wait-LocalTcpPort -Port $VlessSocksPort

    $hev = Start-Process -FilePath $VlessHevExe -ArgumentList @($VlessHevRuntimeConfigPath) `
        -WorkingDirectory $VlessToolRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $VlessHevStdoutPath -RedirectStandardError $VlessHevStderrPath
    Write-PrivateRuntimeFile -Path $VlessHevPidPath -Content ([string]$hev.Id)
    $adapter = Wait-VlessAdapter
    Add-VlessRoutes -InterfaceIndex ([int]$adapter.ifIndex)

    $watchdog = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $VlessWatchdogScript + '"'),
        '-XrayPid', $xray.Id,
        '-HevPid', $hev.Id
    ) -WindowStyle Hidden -PassThru
    Write-PrivateRuntimeFile -Path $VlessWatchdogPidPath -Content ([string]$watchdog.Id)

    if (-not (Test-ExactProcess -ProcessId $xray.Id -ExpectedPath $XrayExe) -or
        -not (Test-ExactProcess -ProcessId $hev.Id -ExpectedPath $VlessHevExe)) {
        throw 'VLESS REALITY preview engine exited during startup.'
    }
    Write-GreenLog "VLESS REALITY preview started ifIndex=$($adapter.ifIndex)"
}

function Get-SafeHevDiagnostic {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'no stderr' }
    $text = [IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($text)) { return 'empty stderr' }
    $flat = ($text -replace '[\x00-\x1f]+', ' ' -replace '\s+', ' ').Trim()
    $flat = $flat -replace '(?i)(https?://)[^/@\s]+@', '$1<redacted>@'
    $flat = $flat -replace '(?i)(username|password|token|secret)\s*[:=]\s*\S+', '$1=<redacted>'
    if ($flat.Length -gt 1000) { $flat = $flat.Substring(0, 1000) }
    return $flat
}

function Wait-NaiveAdapter {
    param(
        [System.Diagnostics.Process]$HevProcess,
        [int]$Seconds = 20
    )
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        if ($null -ne $HevProcess) {
            $HevProcess.Refresh()
            if ($HevProcess.HasExited) {
                $diagnostic = Get-SafeHevDiagnostic -Path $NaiveHevStderrPath
                throw "Naive HTTPS HEV exited with code $($HevProcess.ExitCode): $diagnostic"
            }
        }
        $adapter = Get-NetAdapter -Name $NaiveTunnelName -ErrorAction SilentlyContinue
        if ($null -ne $adapter -and $adapter.Status -eq 'Up') { return $adapter }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    $diagnostic = Get-SafeHevDiagnostic -Path $NaiveHevStderrPath
    throw "Naive HTTPS preview adapter did not become ready: $diagnostic"
}

function New-NaiveRuntimeConfigs {
    $configText = [IO.File]::ReadAllText($ConfigPath)
    if ([Text.Encoding]::UTF8.GetByteCount($configText) -lt 64 -or [Text.Encoding]::UTF8.GetByteCount($configText) -gt 16384) {
        throw 'Naive HTTPS config size is invalid.'
    }
    $root = $configText | ConvertFrom-Json
    $properties = @($root.PSObject.Properties.Name)
    if ($properties.Count -ne 3 -or @($properties | Where-Object { $_ -notin @('listen', 'proxy', 'endpointIp') }).Count -ne 0) {
        throw 'Naive HTTPS config contains unsupported fields.'
    }
    if ([string]$root.listen -ne "socks://127.0.0.1:$NaiveSocksPort") {
        throw 'Naive HTTPS listener must be loopback-only.'
    }
    $proxyText = [string]$root.proxy
    if ([string]::IsNullOrWhiteSpace($proxyText) -or $proxyText -match '\s|[\x00-\x1f]') {
        throw 'Naive HTTPS proxy URI is invalid.'
    }
    $proxy = [Uri]$proxyText
    $guardedEndpoints = @{
        'nl2.vpn.greenvpn.pro' = '5.129.216.42'
        'nl1.vpn.greenvpn.pro' = '37.220.85.211'
        '88-218-250-86.sslip.io' = '88.218.250.86'
    }
    $expectedIp = $guardedEndpoints[$proxy.Host.ToLowerInvariant()]
    if ($proxy.Scheme -ne 'https' -or $proxy.Port -ne $NaiveCanaryPort -or
        [string]::IsNullOrWhiteSpace([string]$expectedIp) -or [string]$root.endpointIp -ne $expectedIp -or
        $proxy.AbsolutePath -ne '/' -or -not [string]::IsNullOrEmpty($proxy.Query) -or
        -not [string]::IsNullOrEmpty($proxy.Fragment)) {
        throw 'Naive HTTPS profile is not the guarded TLS canary.'
    }
    $userInfo = [Uri]::UnescapeDataString($proxy.UserInfo)
    $credentialParts = $userInfo.Split(':', 2)
    if ($userInfo.Length -lt 3 -or $userInfo.Length -gt 512 -or $credentialParts.Count -ne 2 -or
        [string]::IsNullOrWhiteSpace($credentialParts[0]) -or [string]::IsNullOrWhiteSpace($credentialParts[1])) {
        throw 'Naive HTTPS credentials are incomplete.'
    }
    $endpoint = Get-ManagedIpv4Endpoint
    if ($endpoint -ne $expectedIp) { throw 'Naive HTTPS endpoint is inconsistent.' }
    $root.PSObject.Properties.Remove('endpointIp')
    $root | Add-Member -NotePropertyName 'host-resolver-rules' -NotePropertyValue "MAP $($proxy.Host) $endpoint" -Force

    $hevRuntime = @"
tunnel:
  name: $NaiveTunnelName
  mtu: 1400
  ipv4: 198.18.2.1
  ipv6: 'fc00:2::1'
socks5:
  port: $NaiveSocksPort
  address: 127.0.0.1
  udp: 'tcp'
mapdns:
  address: 198.18.2.2
  port: 53
  network: 100.64.0.0
  netmask: 255.192.0.0
  cache-size: 10000
misc:
  log-file: stderr
  log-level: warn
  task-stack-size: 86016
  connect-timeout: 10000
  tcp-read-write-timeout: 300000
  udp-read-write-timeout: 60000
"@
    Write-PrivateRuntimeFile -Path $NaiveRuntimeConfigPath -Content ($root | ConvertTo-Json -Depth 20)
    Write-PrivateRuntimeFile -Path $NaiveHevRuntimeConfigPath -Content $hevRuntime
}

function Add-NaiveRoutes {
    param([int]$InterfaceIndex)
    $prefixes = @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')
    foreach ($prefix in $prefixes) {
        $family = if ($prefix.Contains(':')) { 'IPv6' } else { 'IPv4' }
        $nextHop = if ($family -eq 'IPv6') { '::' } else { '0.0.0.0' }
        Get-NetRoute -AddressFamily $family -DestinationPrefix $prefix -InterfaceIndex $InterfaceIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.RouteMetric -eq $NaiveRouteMetric } |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        New-NetRoute -AddressFamily $family -DestinationPrefix $prefix -InterfaceIndex $InterfaceIndex `
            -NextHop $nextHop -RouteMetric $NaiveRouteMetric -PolicyStore ActiveStore -ErrorAction Stop | Out-Null
    }
    Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses @('198.18.2.2') -ErrorAction Stop
    [ordered]@{
        interfaceIndex = $InterfaceIndex
        metric = $NaiveRouteMetric
        prefixes = $prefixes
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $NaiveRouteStatePath -Encoding ASCII
    & attrib.exe +H $NaiveRouteStatePath 2>$null | Out-Null
    & icacls.exe $NaiveRouteStatePath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
}

function Start-NaiveHttpsTunnel {
    Assert-NaiveRuntime
    Ensure-EndpointBypassRoute
    New-NaiveRuntimeConfigs

    foreach ($path in @($NaiveStdoutPath, $NaiveStderrPath, $NaiveHevStdoutPath, $NaiveHevStderrPath)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    $naive = Start-Process -FilePath $NaiveExe -ArgumentList @($NaiveRuntimeConfigPath) `
        -WorkingDirectory $NaiveToolRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $NaiveStdoutPath -RedirectStandardError $NaiveStderrPath
    foreach ($path in @($NaiveStdoutPath, $NaiveStderrPath)) {
        Protect-PrivateRuntimeFile -Path $path
    }
    Write-PrivateRuntimeFile -Path $NaivePidPath -Content ([string]$naive.Id)
    Wait-LocalTcpPort -Port $NaiveSocksPort

    $hev = Start-Process -FilePath $NaiveHevExe -ArgumentList @($NaiveHevRuntimeConfigPath) `
        -WorkingDirectory $NaiveToolRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $NaiveHevStdoutPath -RedirectStandardError $NaiveHevStderrPath
    foreach ($path in @($NaiveHevStdoutPath, $NaiveHevStderrPath)) {
        Protect-PrivateRuntimeFile -Path $path
    }
    Write-PrivateRuntimeFile -Path $NaiveHevPidPath -Content ([string]$hev.Id)
    $adapter = Wait-NaiveAdapter -HevProcess $hev
    Add-NaiveRoutes -InterfaceIndex ([int]$adapter.ifIndex)

    $watchdog = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $NaiveWatchdogScript + '"'),
        '-NaivePid', $naive.Id,
        '-HevPid', $hev.Id
    ) -WindowStyle Hidden -PassThru
    Write-PrivateRuntimeFile -Path $NaiveWatchdogPidPath -Content ([string]$watchdog.Id)

    if (-not (Test-ExactProcess -ProcessId $naive.Id -ExpectedPath $NaiveExe) -or
        -not (Test-ExactProcess -ProcessId $hev.Id -ExpectedPath $NaiveHevExe)) {
        throw 'Naive HTTPS preview engine exited during startup.'
    }
    Write-GreenLog "Naive HTTPS preview started ifIndex=$($adapter.ifIndex)"
}

function Wait-DnsttAdapter {
    param([int]$Seconds = 20)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $adapter = Get-NetAdapter -Name $DnsttTunnelName -ErrorAction SilentlyContinue
        if ($null -ne $adapter -and $adapter.Status -eq 'Up') { return $adapter }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    throw 'dnstt preview adapter did not become ready.'
}

function New-DnsttRuntimeConfigs {
    $configText = [IO.File]::ReadAllText($ConfigPath)
    $configSize = [Text.Encoding]::UTF8.GetByteCount($configText)
    if ($configSize -lt 180 -or $configSize -gt 16384) {
        throw 'dnstt config size is invalid.'
    }
    $root = $configText | ConvertFrom-Json
    $rootProperties = @($root.PSObject.Properties.Name)
    $allowedRoot = @('zone', 'publicKey', 'socks', 'resolvers', 'expectedEgress')
    if ($rootProperties.Count -ne $allowedRoot.Count -or
        @($rootProperties | Where-Object { $_ -notin $allowedRoot }).Count -ne 0) {
        throw 'dnstt config fields are invalid.'
    }
    if ([string]$root.zone -ne $DnsttZone -or
        [string]$root.expectedEgress -ne $DnsttExpectedEgress) {
        throw 'dnstt profile is not the guarded canary.'
    }
    $publicKey = [string]$root.publicKey
    if ($publicKey -notmatch '^[0-9a-f]{64}$') {
        throw 'dnstt public key is invalid.'
    }

    $socks = $root.socks
    $socksProperties = @($socks.PSObject.Properties.Name)
    $allowedSocks = @('listen', 'username', 'password')
    if ($socksProperties.Count -ne $allowedSocks.Count -or
        @($socksProperties | Where-Object { $_ -notin $allowedSocks }).Count -ne 0) {
        throw 'dnstt SOCKS fields are invalid.'
    }
    $username = [string]$socks.username
    $password = [string]$socks.password
    if ([string]$socks.listen -ne "127.0.0.1:$DnsttSocksPort" -or
        $username -notmatch '^[A-Za-z0-9_.-]{3,128}$' -or
        $password -notmatch '^[A-Za-z0-9+/=]{16,255}$') {
        throw 'dnstt SOCKS profile is invalid.'
    }

    $resolvers = @($root.resolvers)
    if ($resolvers.Count -lt 1 -or $resolvers.Count -gt 3) {
        throw 'dnstt resolver count is invalid.'
    }
    $allowedResolvers = @(
        'doh|https://1.1.1.1/dns-query',
        'doh|https://8.8.8.8/dns-query',
        'dot|1.1.1.1:853'
    )
    $seenResolvers = @{}
    foreach ($resolver in $resolvers) {
        $resolverProperties = @($resolver.PSObject.Properties.Name)
        if ($resolverProperties.Count -ne 2 -or
            @($resolverProperties | Where-Object { $_ -notin @('mode', 'endpoint') }).Count -ne 0) {
            throw 'dnstt resolver fields are invalid.'
        }
        $resolverKey = "$([string]$resolver.mode)|$([string]$resolver.endpoint)"
        if ($resolverKey -notin $allowedResolvers -or $seenResolvers.ContainsKey($resolverKey)) {
            throw 'dnstt resolver is not allowlisted or is duplicated.'
        }
        $seenResolvers[$resolverKey] = $true
    }
    if ([string]$resolvers[0].mode -ne 'doh' -or
        [string]$resolvers[0].endpoint -ne 'https://1.1.1.1/dns-query') {
        throw 'dnstt primary resolver is not the guarded DoH endpoint.'
    }

    $hevRuntime = @"
tunnel:
  name: $DnsttTunnelName
  mtu: 1400
  ipv4: 198.18.3.1
  ipv6: 'fc00:3::1'
socks5:
  address: 127.0.0.1
  port: $DnsttSocksPort
  username: '$username'
  password: '$password'
  udp: 'tcp'
mapdns:
  address: 198.18.3.2
  port: 53
  network: 100.64.0.0
  netmask: 255.192.0.0
  cache-size: 10000
misc:
  log-file: stderr
  log-level: warn
  task-stack-size: 86016
  connect-timeout: 10000
  tcp-read-write-timeout: 300000
  udp-read-write-timeout: 60000
"@
    Write-PrivateRuntimeFile -Path $DnsttRuntimeConfigPath -Content ($root | ConvertTo-Json -Depth 20)
    Write-PrivateRuntimeFile -Path $DnsttHevRuntimeConfigPath -Content $hevRuntime
}

function Add-DnsttRoutes {
    param([int]$InterfaceIndex)
    $prefixes = @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')
    foreach ($prefix in $prefixes) {
        $family = if ($prefix.Contains(':')) { 'IPv6' } else { 'IPv4' }
        $nextHop = if ($family -eq 'IPv6') { '::' } else { '0.0.0.0' }
        Get-NetRoute -AddressFamily $family -DestinationPrefix $prefix -InterfaceIndex $InterfaceIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.RouteMetric -eq $DnsttRouteMetric } |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        New-NetRoute -AddressFamily $family -DestinationPrefix $prefix -InterfaceIndex $InterfaceIndex `
            -NextHop $nextHop -RouteMetric $DnsttRouteMetric -PolicyStore ActiveStore -ErrorAction Stop | Out-Null
    }
    Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses @('198.18.3.2') -ErrorAction Stop
    [ordered]@{
        interfaceIndex = $InterfaceIndex
        metric = $DnsttRouteMetric
        prefixes = $prefixes
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $DnsttRouteStatePath -Encoding ASCII
    & attrib.exe +H $DnsttRouteStatePath 2>$null | Out-Null
    & icacls.exe $DnsttRouteStatePath /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
}

function Start-DnsttTunnel {
    Assert-DnsttRuntime
    Ensure-EndpointBypassRoute
    New-DnsttRuntimeConfigs

    foreach ($path in @($DnsttStdoutPath, $DnsttStderrPath, $DnsttHevStdoutPath, $DnsttHevStderrPath)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    $profile = Get-Content -LiteralPath $DnsttRuntimeConfigPath -Raw | ConvertFrom-Json
    $resolver = @($profile.resolvers)[0]
    $dnstt = Start-Process -FilePath $DnsttExe -ArgumentList @(
        '-doh', [string]$resolver.endpoint,
        '-pubkey', [string]$profile.publicKey,
        [string]$profile.zone,
        "127.0.0.1:$DnsttSocksPort"
    ) -WorkingDirectory $DnsttToolRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $DnsttStdoutPath -RedirectStandardError $DnsttStderrPath
    foreach ($path in @($DnsttStdoutPath, $DnsttStderrPath)) {
        Protect-PrivateRuntimeFile -Path $path
    }
    Write-PrivateRuntimeFile -Path $DnsttPidPath -Content ([string]$dnstt.Id)
    Wait-LocalTcpPort -Port $DnsttSocksPort

    $hev = Start-Process -FilePath $DnsttHevExe -ArgumentList @($DnsttHevRuntimeConfigPath) `
        -WorkingDirectory $DnsttToolRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $DnsttHevStdoutPath -RedirectStandardError $DnsttHevStderrPath
    foreach ($path in @($DnsttHevStdoutPath, $DnsttHevStderrPath)) {
        Protect-PrivateRuntimeFile -Path $path
    }
    Write-PrivateRuntimeFile -Path $DnsttHevPidPath -Content ([string]$hev.Id)
    $adapter = Wait-DnsttAdapter
    Add-DnsttRoutes -InterfaceIndex ([int]$adapter.ifIndex)

    $watchdog = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $DnsttWatchdogScript + '"'),
        '-DnsttPid', $dnstt.Id,
        '-HevPid', $hev.Id
    ) -WindowStyle Hidden -PassThru
    Write-PrivateRuntimeFile -Path $DnsttWatchdogPidPath -Content ([string]$watchdog.Id)

    if (-not (Test-ExactProcess -ProcessId $dnstt.Id -ExpectedPath $DnsttExe) -or
        -not (Test-ExactProcess -ProcessId $hev.Id -ExpectedPath $DnsttHevExe)) {
        throw 'dnstt preview engine exited during startup.'
    }
    Write-GreenLog "dnstt preview started ifIndex=$($adapter.ifIndex)"
}

function Get-CompetingVpnServices {
    try {
        return @(
            Get-Service -Name @(
                'WireGuardTunnel$*',
                'AmneziaWGTunnel$*',
                'CloudflareWARP'
            ) -ErrorAction SilentlyContinue |
                Where-Object {
                    [string]$_.Status -ne 'Stopped' -and
                    $_.Name -notin @(
                        $WireGuardServiceName,
                        $AmneziaWgServiceName,
                        $StandbyProbeWireGuardServiceName,
                        $StandbyProbeAmneziaServiceName
                    ) -and
                    (
                        $_.Name -like 'WireGuardTunnel$*' -or
                        $_.Name -like 'AmneziaWGTunnel$*' -or
                        $_.Name -eq 'CloudflareWARP'
                    )
                }
        )
    } catch {
        Write-GreenLog 'service competition check failed'
        return @()
    }
}

function Test-AllowedCompetingVpnServiceName {
    param([Parameter(Mandatory=$true)][string]$Name)

    return (
        $Name -ne $WireGuardServiceName -and
        $Name -ne $AmneziaWgServiceName -and
        $Name -ne $StandbyProbeWireGuardServiceName -and
        $Name -ne $StandbyProbeAmneziaServiceName -and
        (
            $Name -like 'WireGuardTunnel$*' -or
            $Name -like 'AmneziaWGTunnel$*' -or
            $Name -eq 'CloudflareWARP'
        )
    )
}

function Save-CompetingVpnState {
    param([Parameter(Mandatory=$true)][object[]]$Services)

    $serviceNames = @(
        $Services |
            ForEach-Object { [string]$_.Name } |
            Where-Object { Test-AllowedCompetingVpnServiceName -Name $_ } |
            Sort-Object -Unique
    )
    if ($serviceNames.Count -eq 0) { return }

    New-Item `
        -ItemType Directory `
        -Force `
        -Path (Split-Path -Parent $CompetingVpnStatePath) |
        Out-Null
    $state = [ordered]@{
        schema = 1
        createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        services = [object[]]$serviceNames
    }
    Write-PrivateRuntimeFile `
        -Path $CompetingVpnStatePath `
        -Content ($state | ConvertTo-Json -Depth 4)
}

function Restore-CompetingVpnTunnels {
    if (-not (Test-Path -LiteralPath $CompetingVpnStatePath -PathType Leaf)) {
        return
    }

    $state = Get-Content -LiteralPath $CompetingVpnStatePath -Raw |
        ConvertFrom-Json
    if ([int]$state.schema -ne 1) {
        throw 'Unsupported competing VPN restore state.'
    }
    $serviceNames = @(
        @($state.services) |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
    foreach ($serviceName in $serviceNames) {
        if (-not (Test-AllowedCompetingVpnServiceName -Name $serviceName)) {
            throw "Unsafe competing VPN restore service name: $serviceName"
        }
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($null -eq $service) { continue }
        if ([string]$service.Status -ne 'Running') {
            Start-Service -Name $serviceName -ErrorAction Stop
            $service.WaitForStatus(
                [System.ServiceProcess.ServiceControllerStatus]::Running,
                [TimeSpan]::FromSeconds(45)
            )
        }
        Write-GreenLog "restored competing VPN service: $serviceName"
    }
    Remove-Item -LiteralPath $CompetingVpnStatePath -Force -ErrorAction Stop
}

function Get-CompetingVpnLabels {
    $labels = New-Object System.Collections.Generic.List[string]
    try {
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Status -eq 'Up' -and $_.Name -notin @($TunnelName, $HysteriaTunnelName, $VlessTunnelName, $NaiveTunnelName, $DnsttTunnelName) -and
                ($_.Name -match '(?i)(wireguard|wintun|amnezia|warp|cloudflare|device[0-9_]+)' -or $_.InterfaceDescription -match '(?i)(wireguard|wintun|amnezia|warp|cloudflare)')
            } | ForEach-Object { $labels.Add("adapter:$($_.Name)") | Out-Null }
    } catch {
        Write-GreenLog 'adapter competition check failed'
    }
    Get-CompetingVpnServices |
        ForEach-Object { $labels.Add("service:$($_.Name)") | Out-Null }
    return @($labels | Sort-Object -Unique)
}

function Stop-CompetingVpnTunnels {
    param(
        [ValidateSet('connect', 'guard')]
        [string]$Reason
    )

    $services = @(Get-CompetingVpnServices)
    if ($services.Count -eq 0) {
        return @(Get-CompetingVpnLabels)
    }

    $script:CompetingVpnTakeoverOccurred = $true
    Save-CompetingVpnState -Services $services
    Write-GreenLog "takeover requested reason=$Reason serviceCount=$($services.Count)"
    foreach ($service in $services) {
        $serviceName = [string]$service.Name
        try {
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
            Write-GreenLog "takeover service stop accepted: $serviceName"
        } catch {
            Write-GreenLog "takeover service stop failed: $serviceName"
        }
    }

    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if (@(Get-CompetingVpnServices).Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    }

    $remainingServices = @(Get-CompetingVpnServices)
    if ($remainingServices.Count -gt 0) {
        $remaining = @($remainingServices | ForEach-Object { "service:$($_.Name)" })
        Write-GreenLog "takeover incomplete reason=$Reason remainingCount=$($remaining.Count)"
        return $remaining
    }

    $remaining = @()
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $remaining = @(Get-CompetingVpnLabels)
        if ($remaining.Count -eq 0) {
            Write-GreenLog "takeover complete reason=$Reason"
            return @()
        }
        Start-Sleep -Milliseconds 100
    }

    Write-GreenLog "takeover incomplete reason=$Reason remainingCount=$($remaining.Count)"
    return $remaining
}

function Test-AdvancedTransportStatePresent {
    foreach ($path in @(
        $HysteriaPidPath,
        $HevPidPath,
        $HysteriaWatchdogPidPath,
        $HysteriaRouteStatePath,
        $XrayPidPath,
        $VlessHevPidPath,
        $VlessWatchdogPidPath,
        $VlessRouteStatePath,
        $NaivePidPath,
        $NaiveHevPidPath,
        $NaiveWatchdogPidPath,
        $NaiveRouteStatePath,
        $DnsttPidPath,
        $DnsttHevPidPath,
        $DnsttWatchdogPidPath,
        $DnsttRouteStatePath
    )) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $true }
    }
    return $false
}

function Stop-OwnTunnel {
    param([switch]$FastNativeSwitch)

    Remove-GreenPrivilegedRuntimeValue -Name 'ActiveRoutingMode'
    $processRouterStopError = $null
    try {
        Stop-GreenProcessRouter
    } catch {
        $processRouterStopError = $_.Exception.Message
        Write-GreenLog "process router stop warning: $processRouterStopError"
    }
    $advancedStatePresent = Test-AdvancedTransportStatePresent
    $managedProcesses = @()
    if (-not $FastNativeSwitch -or $advancedStatePresent) {
        $managedProcesses = @(
            [pscustomobject]@{ pid = Read-ManagedPid -Path $HysteriaPidPath; path = $HysteriaExe },
            [pscustomobject]@{ pid = Read-ManagedPid -Path $HevPidPath; path = $HevExe },
            [pscustomobject]@{ pid = Read-ManagedPid -Path $XrayPidPath; path = $XrayExe },
            [pscustomobject]@{ pid = Read-ManagedPid -Path $VlessHevPidPath; path = $VlessHevExe },
            [pscustomobject]@{ pid = Read-ManagedPid -Path $NaivePidPath; path = $NaiveExe },
            [pscustomobject]@{ pid = Read-ManagedPid -Path $NaiveHevPidPath; path = $NaiveHevExe },
            [pscustomobject]@{ pid = Read-ManagedPid -Path $DnsttPidPath; path = $DnsttExe },
            [pscustomobject]@{ pid = Read-ManagedPid -Path $DnsttHevPidPath; path = $DnsttHevExe }
        )
        Stop-Hysteria2Tunnel
        Stop-VlessRealityTunnel
        Stop-NaiveHttpsTunnel
        Stop-DnsttTunnel
    } else {
        Write-GreenLog 'fast native switch skipped inactive advanced transport cleanup'
    }
    $existingServices = @{}
    $stopRequested = $false
    foreach ($serviceName in @($WireGuardServiceName, $AmneziaWgServiceName)) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($null -eq $service) { continue }
        $existingServices[$serviceName] = $true
        if ([string]$service.Status -eq 'Stopped') {
            continue
        }
        try {
            Invoke-External -FilePath 'sc.exe' -Arguments @('stop', $serviceName) -AllowedExitCodes @(0, 1056, 1060, 1062) | Out-Null
            $stopRequested = $true
        } catch {
            Write-GreenLog "service stop warning: $serviceName"
        }
    }
    if ($stopRequested) {
        Start-Sleep -Milliseconds 500
    }

    if ($existingServices.ContainsKey($WireGuardServiceName)) {
        $wireGuard = Resolve-WireGuardExe
        try { Invoke-External -FilePath $wireGuard -Arguments @('/uninstalltunnelservice', $TunnelName) -AllowedExitCodes @(0, 1) | Out-Null } catch { Write-GreenLog 'WireGuard uninstall warning' }
    }
    if ($existingServices.ContainsKey($AmneziaWgServiceName)) {
        $amneziaWg = Resolve-AmneziaWgExe
        try { Invoke-External -FilePath $amneziaWg -Arguments @('/uninstalltunnelservice', $TunnelName) -AllowedExitCodes @(0, 1) | Out-Null } catch { Write-GreenLog 'AmneziaWG uninstall warning' }
    }
    Remove-EndpointBypassRoute

    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        $runningServices = @(
            Get-Service -Name @($WireGuardServiceName, $AmneziaWgServiceName) -ErrorAction SilentlyContinue |
                Where-Object { [string]$_.Status -ne 'Stopped' }
        )
        $runningProcesses = @(
            $managedProcesses |
                Where-Object { Test-ExactProcess -ProcessId ([int]$_.pid) -ExpectedPath ([string]$_.path) }
        )
        $activeAdapters = @(if (-not $FastNativeSwitch -or $advancedStatePresent) {
                Get-NetAdapter -Name @($HysteriaTunnelName, $VlessTunnelName, $NaiveTunnelName, $DnsttTunnelName) -ErrorAction SilentlyContinue |
                    Where-Object { $_.Status -eq 'Up' }
        })
        if ($runningServices.Count -eq 0 -and $runningProcesses.Count -eq 0 -and $activeAdapters.Count -eq 0) {
            if ($null -ne $processRouterStopError) {
                throw "Tunnel stopped without confirming process router cleanup: $processRouterStopError"
            }
            return
        }
        Start-Sleep -Milliseconds 250
    }
    throw 'Previous Green VPN transport did not stop completely.'
}

function Complete-GreenDisconnectedRuntimeState {
    $transitionGeneration = [uint32](
        Get-GreenRuntimeTransitionGenerationForCleanup
    )
    Stop-OwnTunnel
    Confirm-GreenProcessRouterRuntimeContract -Required $false
    Complete-GreenRuntimeStateTransition `
        -TransitionGeneration $transitionGeneration
    $script:ActiveRuntimeTransitionGeneration = $null
    Write-GreenLog 'disconnected runtime state committed'
}

function Start-OwnTunnel {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config missing: $ConfigPath" }
    $protocol = Get-ManagedProtocol
    Write-GreenLog "connect phase=preflight protocol=$protocol"
    Write-GreenLog 'connect phase=standby-cleanup-start'
    if (-not (Remove-StandbyProbeFallbackArtifacts)) {
        Write-GreenLog 'connect phase=standby-cleanup-failed'
        throw 'Standby probe cleanup did not complete.'
    }
    Write-GreenLog 'connect phase=standby-cleanup-complete'
    $script:ActiveRuntimeTransitionGeneration = [uint32](
        Start-GreenRuntimeStateTransition
    )
    Write-GreenPrivilegedRuntimeValue `
        -Name 'ProcessRouterRequired' `
        -Value 0 `
        -PropertyType DWord
    $competitors = @(Stop-CompetingVpnTunnels -Reason 'connect')
    if ($competitors.Count -gt 0) {
        Write-GreenLog "connect takeover blocked by competitor count=$($competitors.Count)"
        throw 'Competing VPN takeover did not complete.'
    }

    $engine = if ($protocol -eq 'amneziawg') { Resolve-AmneziaWgExe } else { Resolve-WireGuardExe }
    $nativeProtocol = $protocol -in @('wireguard_udp', 'amneziawg')
    Stop-OwnTunnel -FastNativeSwitch:$nativeProtocol
    Write-GreenLog 'connect phase=own-tunnel-stopped'
    $routingMode = Get-GreenRoutingMode
    $routingPolicy = $null
    $applicationPaths = @()
    if ($routingMode -eq 'applications') {
        if ($protocol -notin @('wireguard_udp', 'amneziawg')) {
            throw "Selective application routing is not supported by $protocol."
        }
        $routingPolicy = Get-GreenRoutingPolicy
        $applicationPaths = @(Get-GreenApplicationPaths -Policy $routingPolicy)
        Ensure-GreenApplicationTunnelRoutes -Policy $routingPolicy
    }
    if ($protocol -eq 'hysteria2') {
        Ensure-GreenProgramDataAcl
        Start-Hysteria2Tunnel
        Write-GreenActiveRoutingMode -Mode 'full' -ProcessRouterRequired $false `
            -TransitionGeneration $script:ActiveRuntimeTransitionGeneration
        $script:ActiveRuntimeTransitionGeneration = $null
        return
    }
    if ($protocol -eq 'vless_reality') {
        Ensure-GreenProgramDataAcl
        Start-VlessRealityTunnel
        Write-GreenActiveRoutingMode -Mode 'full' -ProcessRouterRequired $false `
            -TransitionGeneration $script:ActiveRuntimeTransitionGeneration
        $script:ActiveRuntimeTransitionGeneration = $null
        return
    }
    if ($protocol -eq 'naive_https') {
        Ensure-GreenProgramDataAcl
        Start-NaiveHttpsTunnel
        Write-GreenActiveRoutingMode -Mode 'full' -ProcessRouterRequired $false `
            -TransitionGeneration $script:ActiveRuntimeTransitionGeneration
        $script:ActiveRuntimeTransitionGeneration = $null
        return
    }
    if ($protocol -eq 'dnstt') {
        Ensure-GreenProgramDataAcl
        Start-DnsttTunnel
        Write-GreenActiveRoutingMode -Mode 'full' -ProcessRouterRequired $false `
            -TransitionGeneration $script:ActiveRuntimeTransitionGeneration
        $script:ActiveRuntimeTransitionGeneration = $null
        return
    }
    if ([string]::IsNullOrWhiteSpace($engine)) { throw "Engine unavailable for $protocol" }
    if ($routingMode -ne 'applications') {
        Ensure-NativeFullTunnelKillSwitch
    }
    Write-GreenLog "connect phase=route-policy-ready mode=$routingMode"
    if ($script:CompetingVpnTakeoverOccurred) {
        Ensure-EndpointBypassRoute
        Write-GreenLog 'connect phase=endpoint-bypass-ready'
    } else {
        Write-GreenLog 'connect phase=endpoint-bypass-skipped reason=no-competing-vpn'
    }
    try {
        Invoke-External -FilePath $engine -Arguments @('/installtunnelservice', $ConfigPath) | Out-Null
    } catch {
        Write-GreenLog 'native tunnel install failed; validating protected state before one retry'
        Ensure-GreenProgramDataAcl
        Invoke-External -FilePath $engine -Arguments @('/installtunnelservice', $ConfigPath) | Out-Null
    }
    Write-GreenLog 'connect phase=tunnel-service-installed'
    $serviceName = Get-SelectedServiceName -Protocol $protocol
    $service = Get-Service -Name $serviceName -ErrorAction Stop
    if ([string]$service.StartType -ne 'Manual') {
        Set-Service -Name $serviceName -StartupType Manual -ErrorAction Stop
    }
    $service.Refresh()
    if ([string]$service.Status -ne 'Running') {
        Start-Service -Name $serviceName -ErrorAction Stop
        $service.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds(10)
        )
    }
    Write-GreenLog "connect phase=tunnel-service-running service=$serviceName"
    if ($routingMode -eq 'applications' -and $applicationPaths.Count -gt 0) {
        $tunnelReady = $false
        for ($i = 0; $i -lt 20; $i++) {
            $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
            if (
                $null -ne $service -and
                $service.State -eq 'Running' -and
                (Test-GreenTcpEndpoint -HostName $ApplicationProxyHost -Port $ApplicationProxyPort -TimeoutMs 250)
            ) {
                $tunnelReady = $true
                break
            }
            Start-Sleep -Milliseconds 250
        }
        if (-not $tunnelReady) {
            Stop-OwnTunnel
            throw 'The application routing gateway is unavailable through the tunnel.'
        }
        try {
            Start-GreenProcessRouter -ApplicationPaths $applicationPaths
        } catch {
            Stop-OwnTunnel
            throw
        }
    } elseif ($routingMode -eq 'applications') {
        Stop-GreenProcessRouter
        Write-GreenLog 'selective tunnel uses destination routes only; process router not required'
    }
    Write-GreenActiveRoutingMode -Mode $routingMode `
        -ProcessRouterRequired ($routingMode -eq 'applications' -and $applicationPaths.Count -gt 0) `
        -TransitionGeneration $script:ActiveRuntimeTransitionGeneration
    $script:ActiveRuntimeTransitionGeneration = $null
}

function Invoke-GreenGuard {
    $ownRunning = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @($WireGuardServiceName, $AmneziaWgServiceName) -and $_.State -eq 'Running' })
    $hysteriaRunning = (Test-ExactProcess -ProcessId (Read-ManagedPid -Path $HysteriaPidPath) -ExpectedPath $HysteriaExe) -and
        (Test-ExactProcess -ProcessId (Read-ManagedPid -Path $HevPidPath) -ExpectedPath $HevExe)
    $vlessRunning = (Test-ExactProcess -ProcessId (Read-ManagedPid -Path $XrayPidPath) -ExpectedPath $XrayExe) -and
        (Test-ExactProcess -ProcessId (Read-ManagedPid -Path $VlessHevPidPath) -ExpectedPath $VlessHevExe)
    $naiveRunning = (Test-ExactProcess -ProcessId (Read-ManagedPid -Path $NaivePidPath) -ExpectedPath $NaiveExe) -and
        (Test-ExactProcess -ProcessId (Read-ManagedPid -Path $NaiveHevPidPath) -ExpectedPath $NaiveHevExe)
    $dnsttRunning = (Test-ExactProcess -ProcessId (Read-ManagedPid -Path $DnsttPidPath) -ExpectedPath $DnsttExe) -and
        (Test-ExactProcess -ProcessId (Read-ManagedPid -Path $DnsttHevPidPath) -ExpectedPath $DnsttHevExe)
    if ($ownRunning.Count -eq 0 -and -not $hysteriaRunning -and -not $vlessRunning -and -not $naiveRunning -and -not $dnsttRunning) { return }
    if (-not (Test-GreenRuntimeStateStable)) {
        Write-GreenLog 'guard skipped during an incomplete runtime transition'
        return
    }
    if (
        ([int](Read-GreenPrivilegedRuntimeValue -Name 'ProcessRouterRequired') -eq 1) -and
        -not (Test-GreenProcessRouterRunning)
    ) {
        Write-GreenLog 'guard disconnecting application-only tunnel because process router stopped'
        Complete-GreenDisconnectedRuntimeState
        Restore-CompetingVpnTunnels
        return
    }
    $competitorLabels = @(Get-CompetingVpnLabels)
    if ($competitorLabels.Count -eq 0) { return }
    $activeMode = [string](
        Read-GreenPrivilegedRuntimeValue -Name 'ActiveRoutingMode'
    )
    $routerRequired = [int](
        Read-GreenPrivilegedRuntimeValue -Name 'ProcessRouterRequired'
    ) -eq 1
    $script:ActiveRuntimeTransitionGeneration = [uint32](
        Start-GreenRuntimeStateTransition
    )
    $competitors = @(Stop-CompetingVpnTunnels -Reason 'guard')
    if ($competitors.Count -gt 0) {
        Write-GreenLog "guard disconnecting preview because takeover remained incomplete count=$($competitors.Count)"
        Complete-GreenDisconnectedRuntimeState
        Restore-CompetingVpnTunnels
        return
    }
    if ($activeMode -notin @('full', 'applications')) {
        throw 'Guard cannot republish an unknown active routing mode.'
    }
    Write-GreenActiveRoutingMode -Mode $activeMode `
        -ProcessRouterRequired $routerRequired `
        -TransitionGeneration $script:ActiveRuntimeTransitionGeneration
    $script:ActiveRuntimeTransitionGeneration = $null
}

function Remove-StandbyProbeFallbackArtifacts {
    $runtimeNeedle = [IO.Path]::GetFullPath($StandbyProbeRuntimeRoot)
    $allowedProcessNames = @(
        'hysteria-windows-amd64.exe',
        'xray.exe',
        'naive.exe',
        'dnstt-client-windows-amd64.exe',
        'hev-socks5-tunnel.exe'
    )
    foreach ($process in @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                [string]$_.Name -in $allowedProcessNames -and
                -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
                ([string]$_.CommandLine).IndexOf(
                    $runtimeNeedle,
                    [StringComparison]::OrdinalIgnoreCase
                ) -ge 0
            }
    )) {
        try { Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop } catch {}
    }
    foreach ($engine in @(
        $(try { Resolve-WireGuardExe } catch { $null }),
        $(try { Resolve-AmneziaWgExe } catch { $null })
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$engine) -or
            -not (Test-Path -LiteralPath ([string]$engine) -PathType Leaf)) {
            continue
        }
        try {
            & ([string]$engine) /uninstalltunnelservice $StandbyProbeTunnelName |
                Out-Null
        } catch {}
    }
    foreach ($serviceName in @(
        $StandbyProbeWireGuardServiceName,
        $StandbyProbeAmneziaServiceName
    )) {
        try { Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue } catch {}
        try { & sc.exe delete $serviceName 2>$null | Out-Null } catch {}
    }
    try {
        Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                [int]$_.RouteMetric -eq $StandbyProbeEndpointRouteMetric
            } |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try {
            Remove-Item -LiteralPath $StandbyProbeRuntimeRoot -Recurse -Force `
                -ErrorAction SilentlyContinue
        } catch {}
        $servicesGone = @(Get-Service -Name @(
            $StandbyProbeWireGuardServiceName,
            $StandbyProbeAmneziaServiceName
        ) -ErrorAction SilentlyContinue).Count -eq 0
        $adapterGone = @(
            Get-NetAdapter -Name $StandbyProbeTunnelName -ErrorAction SilentlyContinue
        ).Count -eq 0
        $routesGone = @(
            Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object {
                    [int]$_.RouteMetric -eq $StandbyProbeEndpointRouteMetric
                }
        ).Count -eq 0
        if ($servicesGone -and $adapterGone -and $routesGone -and
            -not (Test-Path -LiteralPath $StandbyProbeRuntimeRoot)) {
            return $true
        }
        Start-Sleep -Milliseconds 250
    }
    $servicesGone = @(Get-Service -Name @(
        $StandbyProbeWireGuardServiceName,
        $StandbyProbeAmneziaServiceName
    ) -ErrorAction SilentlyContinue).Count -eq 0
    $adapterGone = @(
        Get-NetAdapter -Name $StandbyProbeTunnelName -ErrorAction SilentlyContinue
    ).Count -eq 0
    $routesGone = @(
        Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                [int]$_.RouteMetric -eq $StandbyProbeEndpointRouteMetric
            }
    ).Count -eq 0
    return $servicesGone -and $adapterGone -and $routesGone -and
        -not (Test-Path -LiteralPath $StandbyProbeRuntimeRoot)
}

function Write-StandbyProbeFallbackResult {
    param(
        [Parameter(Mandatory=$true)][string]$ErrorCode,
        [Parameter(Mandatory=$true)][bool]$CleanupOk
    )
    $requestId = ''
    $routeId = ''
    $protocol = ''
    try {
        $request = Get-Content -LiteralPath $StandbyProbeRequestPath -Raw |
            ConvertFrom-Json
        $requestId = [string]$request.requestId
        $routeId = [string]$request.routeId
        $protocol = [string]$request.protocol
    } catch {}
    $payload = [ordered]@{
        schema = 1
        requestId = $requestId
        routeId = $routeId
        protocol = $protocol
        success = $false
        proofKind = ''
        latencyMs = 0
        youtubeStatus = 0
        egress = ''
        verifiedAt = (Get-Date).ToUniversalTime().ToString('o')
        cleanupOk = $CleanupOk
        cancelled = $false
        errorCode = $ErrorCode
        cleanupErrors = if ($CleanupOk) { @() } else { @('wrapper_cleanup') }
    }
    $json = ($payload | ConvertTo-Json -Depth 6) + [Environment]::NewLine
    $temp = $StandbyProbeResultPath + '.tmp'
    try {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        [IO.File]::WriteAllText($temp, $json, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $StandbyProbeResultPath -Force
    } catch {
        [IO.File]::WriteAllText(
            $StandbyProbeResultPath,
            $json,
            [Text.UTF8Encoding]::new($false)
        )
    }
}

$runtimeMutationMutex = $null
$taskExitCode = 0
try {
    $runtimeMutationMutex = Enter-GreenRuntimeMutationLock
    Write-GreenLog 'started'
    switch ($Action) {
        'Connect' { Start-OwnTunnel }
        'Disconnect' {
            Ensure-GreenProgramDataAcl
            Complete-GreenDisconnectedRuntimeState
            Restore-CompetingVpnTunnels
        }
        'Guard' { Invoke-GreenGuard }
        'ProbeStandby' {
            if (-not (Test-Path -LiteralPath $StandbyProbeScript -PathType Leaf)) {
                throw 'Standby probe script is missing.'
            }
            $probeFailure = $null
            try { & $StandbyProbeScript } catch { $probeFailure = $_ }
            if ($null -ne $probeFailure -or
                -not (Test-Path -LiteralPath $StandbyProbeResultPath -PathType Leaf)) {
                $fallbackCleanupOk = Remove-StandbyProbeFallbackArtifacts
                if (-not (Test-Path -LiteralPath $StandbyProbeResultPath -PathType Leaf)) {
                    Write-StandbyProbeFallbackResult `
                        -ErrorCode 'probe_wrapper_failed' `
                        -CleanupOk $fallbackCleanupOk
                }
                Write-GreenLog "standby probe wrapper fallback cleanupOk=$fallbackCleanupOk"
                if ($null -eq $probeFailure) {
                    throw 'Standby probe completed without a result.'
                }
                throw $probeFailure
            }
        }
    }
    Write-GreenLog 'finished'
} catch {
    $failure = $_
    Write-GreenLog "failed line=$($failure.InvocationInfo.ScriptLineNumber): $($failure.Exception.Message)"
    $mustRecover = $null -ne $runtimeMutationMutex -and (
        $Action -eq 'Connect' -or
        $null -ne $script:ActiveRuntimeTransitionGeneration -or
        -not (Test-GreenRuntimeStateStable)
    )
    if ($mustRecover) {
        try {
            Complete-GreenDisconnectedRuntimeState
        } catch {
            Write-GreenLog "failed tunnel cleanup line=$($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
        }
        try {
            Restore-CompetingVpnTunnels
        } catch {
            Write-GreenLog "failed competitor restore line=$($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
        }
    }
    $taskExitCode = 10
} finally {
    Exit-GreenRuntimeMutationLock -Mutex $runtimeMutationMutex
}
exit $taskExitCode
