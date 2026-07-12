param(
    [ValidateSet('Connect', 'Disconnect', 'Guard')]
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
$LogPath = Join-Path $ProgramDataRoot 'backend.log'

$ExpectedHysteriaRuntimeHashes = @{
    'hysteria-windows-amd64.exe' = 'BCD3865B09BE2E5CC18D117DCF3AD687D1E6E27B0B050376B9CF4EA251B64D6F'
    'hev-socks5-tunnel.exe' = '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E'
    'msys-2.0.dll' = '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18'
    'wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
}

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

function Get-ManagedProtocol {
    if (-not (Test-Path -LiteralPath $ProtocolPath)) { return 'wireguard_udp' }
    $value = (Get-Content -LiteralPath $ProtocolPath -Raw -ErrorAction Stop).Trim().ToLowerInvariant()
    if ($value -notin @('wireguard_udp', 'amneziawg', 'hysteria2')) {
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
    foreach ($path in @($ProgramDataRoot, $ConfigPath, $ProtocolPath)) {
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
    $configText = [IO.File]::ReadAllText($ConfigPath)
    $protocol = Get-ManagedProtocol
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

function Get-CompetingVpnLabels {
    $labels = New-Object System.Collections.Generic.List[string]
    try {
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Status -eq 'Up' -and $_.Name -notin @($TunnelName, $HysteriaTunnelName) -and
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
    Stop-Hysteria2Tunnel
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
    Stop-OwnTunnel
    if ($protocol -eq 'hysteria2') {
        Start-Hysteria2Tunnel
        return
    }
    if ([string]::IsNullOrWhiteSpace($engine)) { throw "Engine unavailable for $protocol" }
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
    $hysteriaRunning = (Test-ExactProcess -ProcessId (Read-ManagedPid -Path $HysteriaPidPath) -ExpectedPath $HysteriaExe) -and
        (Test-ExactProcess -ProcessId (Read-ManagedPid -Path $HevPidPath) -ExpectedPath $HevExe)
    if ($ownRunning.Count -eq 0 -and -not $hysteriaRunning) { return }
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
    if ($Action -eq 'Connect') { Stop-OwnTunnel }
    exit 10
}
