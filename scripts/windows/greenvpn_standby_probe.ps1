Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'
$RequestPath = Join-Path $ProgramDataRoot 'standby-probe-request.json'
$ResultPath = Join-Path $ProgramDataRoot 'standby-probe-result.json'
$CancelPath = Join-Path $ProgramDataRoot 'standby-probe.cancel'
$ServerCacheRoot = Join-Path $ProgramDataRoot 'server-cache'
$RuntimeRoot = Join-Path $ProgramDataRoot 'standby-probe-runtime'
$DiagnosticPath = Join-Path $ProgramDataRoot 'state\standby-probe.log'
$ProbeTunnelName = 'GreenVPNTransportPreviewStandbyProbe'
$ProbeWireGuardService = 'WireGuardTunnel$' + $ProbeTunnelName
$ProbeAmneziaService = 'AmneziaWGTunnel$' + $ProbeTunnelName
$ProbeTarget = '203.0.113.1'
$ProbeEndpointRouteMetric = 42739
$ProbePorts = @{
    hysteria2 = 21980
    vless_reality = 21981
    naive_https = 21982
    dnstt = 21983
}
$AllowedProtocols = @(
    'wireguard_udp',
    'amneziawg',
    'hysteria2',
    'vless_reality',
    'naive_https',
    'dnstt'
)
$ExpectedHashes = @{
    'amneziawg2\amneziawg.exe' = '5B00905ED02619FE149CEAFC898E79993D4455A0CDFA92072B3BB9AEE7B2D537'
    'amneziawg2\awg.exe' = '26AC0BE14A8353EACF2F933736F6F7912F89EC7C59C4190CC990492934C74537'
    'hysteria2\hysteria-windows-amd64.exe' = 'BCD3865B09BE2E5CC18D117DCF3AD687D1E6E27B0B050376B9CF4EA251B64D6F'
    'vless-reality\xray.exe' = '4B43C5EF596F326B233717B585D31A85DD5CD5F77D8DA872E75F7EBC00E99ACB'
    'naive-https\naive.exe' = '94F99801C665D29FC071624663C6F7BFA59E8D5EFAA84CD08EF5EBB18B46CB62'
    'dnstt\dnstt-client-windows-amd64.exe' = '282995EA68FD13514AC033BC953193AD11CF01F83BB6E3F97929089E5BD85A99'
}

$request = $null
$processes = New-Object System.Collections.Generic.List[System.Diagnostics.Process]
$bypassRoutes = New-Object System.Collections.Generic.List[object]
$result = [ordered]@{
    schema = 1
    requestId = ''
    routeId = ''
    protocol = ''
    success = $false
    proofKind = ''
    latencyMs = 0
    youtubeStatus = 0
    egress = ''
    verifiedAt = ''
    cleanupOk = $false
    cancelled = $false
    errorCode = ''
    cleanupErrors = @()
}

function Write-ProbeLog {
    param([string]$Message)
    try {
        $line = "[$((Get-Date).ToString('o'))] standby-probe $Message"
        Add-Content -LiteralPath (Join-Path $ProgramDataRoot 'backend.log') -Encoding UTF8 -Value $line
    } catch {}
}

function Write-ProbeDiagnostic {
    param([Parameter(Mandatory=$true)][string]$Code)
    try {
        $directory = Split-Path -Parent $DiagnosticPath
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
        $line = "[$((Get-Date).ToUniversalTime().ToString('o'))] $Code"
        Add-Content -LiteralPath $DiagnosticPath -Encoding UTF8 -Value $line
    } catch {}
}

function Test-ProbeCancelled {
    return Test-Path -LiteralPath $CancelPath -PathType Leaf
}

function Assert-ProbeNotCancelled {
    if (Test-ProbeCancelled) {
        throw [OperationCanceledException]::new('standby probe cancelled')
    }
}

function Protect-PrivatePath {
    param([Parameter(Mandatory=$true)][string]$Path, [switch]$Directory)
    if ($Directory) {
        & icacls.exe $Path /inheritance:r /grant:r `
            '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    } else {
        & icacls.exe $Path /inheritance:r /grant:r `
            '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw 'standby runtime ACL failed' }
}

function Write-PrivateText {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
    Protect-PrivatePath -Path $Path
}

function Assert-VerifiedRuntime {
    param([Parameter(Mandatory=$true)][string]$RelativePath)
    $expected = $ExpectedHashes[$RelativePath]
    if ([string]::IsNullOrWhiteSpace([string]$expected)) {
        throw 'standby runtime is not allowlisted'
    }
    $path = Join-Path $PSScriptRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'standby runtime is missing'
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) {
        throw 'standby runtime hash mismatch'
    }
    return $path
}

function Resolve-WireGuardExe {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe'),
        'C:\Program Files\WireGuard\wireguard.exe',
        'C:\Program Files (x86)\WireGuard\wireguard.exe'
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    throw 'WireGuard engine is missing'
}

function Resolve-WireGuardCli {
    $engine = Resolve-WireGuardExe
    $candidate = Join-Path (Split-Path -Parent $engine) 'wg.exe'
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw 'WireGuard CLI is missing'
    }
    return $candidate
}

function Stop-NativeProbe {
    foreach ($entry in @(
        [pscustomobject]@{ service = $ProbeWireGuardService; engine = $(try { Resolve-WireGuardExe } catch { '' }) },
        [pscustomobject]@{ service = $ProbeAmneziaService; engine = $(try { Assert-VerifiedRuntime 'amneziawg2\amneziawg.exe' } catch { '' }) }
    )) {
        $service = Get-Service -Name ([string]$entry.service) -ErrorAction SilentlyContinue
        if ($null -ne $service -and
            -not [string]::IsNullOrWhiteSpace([string]$entry.engine)) {
            try {
                $p = Start-Process -FilePath $entry.engine -ArgumentList @(
                    '/uninstalltunnelservice', $ProbeTunnelName
                ) -WindowStyle Hidden -PassThru
                if (-not $p.WaitForExit(8000)) {
                    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                    $p.WaitForExit(3000) | Out-Null
                    Write-ProbeLog "native cleanup timed out service=$($entry.service)"
                } elseif ($p.ExitCode -notin @(0, 1)) {
                    Write-ProbeLog "native cleanup returned exit=$($p.ExitCode)"
                }
            } catch {}
        }
        try { Stop-Service -Name $entry.service -Force -ErrorAction SilentlyContinue } catch {}
        try { & sc.exe delete $entry.service | Out-Null } catch {}
    }
}

function Stop-ProbeProcesses {
    foreach ($process in @($processes)) {
        try {
            $process.Refresh()
            if (-not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                $process.WaitForExit(5000) | Out-Null
            }
        } catch {}
    }
}

function Stop-StaleProbeProcesses {
    $runtimeNeedle = [IO.Path]::GetFullPath($RuntimeRoot)
    $allowedNames = @(
        'hysteria-windows-amd64.exe',
        'xray.exe',
        'naive.exe',
        'dnstt-client-windows-amd64.exe'
    )
    foreach ($process in @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                [string]$_.Name -in $allowedNames -and
                -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
                ([string]$_.CommandLine).IndexOf(
                    $runtimeNeedle,
                    [StringComparison]::OrdinalIgnoreCase
                ) -ge 0
            }
    )) {
        try { Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop } catch {}
    }
}

function Test-PhysicalAdapter {
    param([Parameter(Mandatory=$true)][int]$InterfaceIndex)

    $adapter = Get-NetAdapter -InterfaceIndex $InterfaceIndex -ErrorAction SilentlyContinue
    if ($null -eq $adapter -or [string]$adapter.Status -ne 'Up') { return $false }
    $identity = "$( [string]$adapter.Name ) $( [string]$adapter.InterfaceDescription )"
    return $identity -notmatch '(?i)(wireguard|wintun|amnezia|warp|cloudflare|green\s*vpn|bluevpn|hysteria|vless|dnstt|tun\d*)'
}

function Get-SafePhysicalDefaultRoute {
    $routes = @(
        Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' `
            -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.NextHop) -and
                [string]$_.NextHop -ne '0.0.0.0' -and
                (Test-PhysicalAdapter -InterfaceIndex ([int]$_.InterfaceIndex))
            } |
            Sort-Object -Property @{ Expression = {
                $interface = Get-NetIPInterface -AddressFamily IPv4 `
                    -InterfaceIndex ([int]$_.InterfaceIndex) -ErrorAction SilentlyContinue
                [int]$_.RouteMetric + [int]($interface.InterfaceMetric)
            } }
    )
    return $routes | Select-Object -First 1
}

function Add-ProbeEndpointBypassRoute {
    param([Parameter(Mandatory=$true)][string]$Endpoint)

    $address = $null
    if (-not [Net.IPAddress]::TryParse($Endpoint, [ref]$address) -or
        $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'standby endpoint bypass requires an IPv4 literal'
    }
    $route = Get-SafePhysicalDefaultRoute
    if ($null -eq $route) { throw 'standby physical default route is unavailable' }
    $prefix = "$Endpoint/32"
    $existing = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $prefix `
        -InterfaceIndex ([int]$route.InterfaceIndex) -ErrorAction SilentlyContinue |
        Where-Object { [string]$_.NextHop -eq [string]$route.NextHop } |
        Select-Object -First 1
    $created = $false
    if ($null -eq $existing) {
        New-NetRoute -AddressFamily IPv4 -DestinationPrefix $prefix `
            -InterfaceIndex ([int]$route.InterfaceIndex) `
            -NextHop ([string]$route.NextHop) `
            -RouteMetric $ProbeEndpointRouteMetric `
            -PolicyStore ActiveStore -ErrorAction Stop | Out-Null
        $created = $true
    }
    $bypassRoutes.Add([pscustomobject]@{
        endpoint = $Endpoint
        prefix = $prefix
        interfaceIndex = [int]$route.InterfaceIndex
        nextHop = [string]$route.NextHop
        created = $created
    })
    Write-ProbeLog "endpoint bypass ready endpoint=$Endpoint ifIndex=$($route.InterfaceIndex) created=$created"
}

function Remove-ProbeEndpointBypassRoutes {
    foreach ($route in [object[]]$bypassRoutes) {
        if ($route.created -ne $true) { continue }
        try {
            Get-NetRoute -AddressFamily IPv4 `
                -DestinationPrefix ([string]$route.prefix) `
                -InterfaceIndex ([int]$route.interfaceIndex) `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    [string]$_.NextHop -eq [string]$route.nextHop -and
                    [int]$_.RouteMetric -eq $ProbeEndpointRouteMetric
                } |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        } catch {}
    }
}

function Remove-AllProbeEndpointBypassRoutes {
    try {
        Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.RouteMetric -eq $ProbeEndpointRouteMetric } |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
}

function Test-ProbeEndpointBypassRoutesRemoved {
    foreach ($route in [object[]]$bypassRoutes) {
        if ($route.created -ne $true) { continue }
        $remaining = Get-NetRoute -AddressFamily IPv4 `
            -DestinationPrefix ([string]$route.prefix) `
            -InterfaceIndex ([int]$route.interfaceIndex) `
            -ErrorAction SilentlyContinue |
            Where-Object {
                [string]$_.NextHop -eq [string]$route.nextHop -and
                [int]$_.RouteMetric -eq $ProbeEndpointRouteMetric
            } |
            Select-Object -First 1
        if ($null -ne $remaining) { return $false }
    }
    return $true
}

function Test-AllProbeEndpointBypassRoutesRemoved {
    return @(
        Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.RouteMetric -eq $ProbeEndpointRouteMetric }
    ).Count -eq 0
}

function Remove-ProbeRuntime {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $RuntimeRoot -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
        if (-not (Test-Path -LiteralPath $RuntimeRoot)) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Wait-LocalTcpPort {
    param(
        [Parameter(Mandatory=$true)][int]$Port,
        [Parameter(Mandatory=$true)][System.Diagnostics.Process]$Process,
        [int]$Seconds = 12
    )
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        Assert-ProbeNotCancelled
        $Process.Refresh()
        if ($Process.HasExited) { throw 'standby client exited during startup' }
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
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    throw 'standby loopback listener timeout'
}

function Invoke-CurlText {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    Assert-ProbeNotCancelled
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (-not (Test-Path -LiteralPath $curl -PathType Leaf)) { throw 'curl is missing' }
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $text = (& $curl @Arguments 2>$null | Out-String).Trim()
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($exitCode -ne 0) { throw "standby curl failed exit=$exitCode" }
    return $text
}

function Invoke-SocksDataPlaneProbe {
    param(
        [Parameter(Mandatory=$true)][int]$Port,
        [Parameter(Mandatory=$true)][string]$ExpectedEgress,
        [string]$CurlConfig = ''
    )
    $base = @(
        '-4', '--silent', '--show-error', '--max-time', '10',
        '--socks5-hostname', "127.0.0.1:$Port"
    )
    if (-not [string]::IsNullOrWhiteSpace($CurlConfig)) {
        $base += @('--config', $CurlConfig)
    }
    $egress = Invoke-CurlText -Arguments @($base + @('https://api.ipify.org'))
    if ($egress -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$' -or
        $egress -ne $ExpectedEgress) {
        throw 'standby egress mismatch'
    }
    $statusText = Invoke-CurlText -Arguments @(
        $base + @(
            '--output', 'NUL', '--write-out', '%{http_code}',
            'https://www.youtube.com/generate_204'
        )
    )
    $status = 0
    if (-not [int]::TryParse($statusText, [ref]$status) -or
        $status -lt 200 -or $status -ge 400) {
        throw 'standby YouTube probe failed'
    }
    $script:result.egress = $egress
    $script:result.youtubeStatus = $status
    $script:result.proofKind = 'proxyYoutube'
}

function Start-TrackedProcess {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $stdout = Join-Path $RuntimeRoot "$Name.stdout.log"
    $stderr = Join-Path $RuntimeRoot "$Name.stderr.log"
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments `
        -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $process.PriorityClass = [Diagnostics.ProcessPriorityClass]::BelowNormal
    $processes.Add($process)
    return $process
}

function Invoke-NativeHandshakeProbe {
    param(
        [Parameter(Mandatory=$true)][string]$Protocol,
        [Parameter(Mandatory=$true)][string]$ConfigPath
    )
    Stop-NativeProbe
    $raw = [IO.File]::ReadAllText($ConfigPath)
    foreach ($required in @(
        '(?im)^\s*\[Interface\]\s*$',
        '(?im)^\s*PrivateKey\s*=\s*\S+',
        '(?im)^\s*\[Peer\]\s*$',
        '(?im)^\s*PublicKey\s*=\s*\S+',
        '(?im)^\s*Endpoint\s*=\s*\d{1,3}(?:\.\d{1,3}){3}:\d+'
    )) {
        if ($raw -notmatch $required) { throw 'native standby config contract failed' }
    }
    if ($raw -match '(?im)^\s*(PreUp|PostUp|PreDown|PostDown)\s*=') {
        throw 'native standby config contains commands'
    }
    $endpoint = [regex]::Match(
        $raw,
        '(?im)^\s*Endpoint\s*=\s*(\d{1,3}(?:\.\d{1,3}){3}):\d+\s*$'
    ).Groups[1].Value
    Add-ProbeEndpointBypassRoute -Endpoint $endpoint
    $probeConfig = $raw `
        -replace '(?im)^\s*DNS\s*=.*(?:\r?\n|$)', '' `
        -replace '(?im)^\s*Table\s*=.*(?:\r?\n|$)', '' `
        -replace '(?im)^\s*BlockUntunneledTraffic\s*=.*(?:\r?\n|$)', ''
    if ($probeConfig -match '(?im)^\s*AllowedIPs\s*=') {
        $probeConfig = $probeConfig -replace '(?im)^\s*AllowedIPs\s*=.*$', "AllowedIPs = $ProbeTarget/32"
    } else {
        $probeConfig = $probeConfig -replace '(?im)^\s*\[Peer\]\s*$', "[Peer]`r`nAllowedIPs = $ProbeTarget/32"
    }
    $runtimeConfig = Join-Path $RuntimeRoot "$ProbeTunnelName.conf"
    Write-PrivateText -Path $runtimeConfig -Content $probeConfig

    $engine = if ($Protocol -eq 'amneziawg') {
        Assert-VerifiedRuntime 'amneziawg2\amneziawg.exe'
    } else {
        Resolve-WireGuardExe
    }
    $cli = if ($Protocol -eq 'amneziawg') {
        Assert-VerifiedRuntime 'amneziawg2\awg.exe'
    } else {
        Resolve-WireGuardCli
    }
    $serviceName = if ($Protocol -eq 'amneziawg') {
        $ProbeAmneziaService
    } else {
        $ProbeWireGuardService
    }
    $install = Start-Process -FilePath $engine -ArgumentList @(
        '/installtunnelservice', ('"' + $runtimeConfig + '"')
    ) -WindowStyle Hidden -PassThru
    if (-not $install.WaitForExit(12000)) {
        Stop-Process -Id $install.Id -Force -ErrorAction SilentlyContinue
        $install.WaitForExit(3000) | Out-Null
        throw 'native standby service install timed out'
    }
    if ($install.ExitCode -ne 0) { throw 'native standby service install failed' }

    $deadline = (Get-Date).AddSeconds(12)
    do {
        Assert-ProbeNotCancelled
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($null -ne $service -and [string]$service.Status -eq 'Running') { break }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    if ($null -eq $service -or [string]$service.Status -ne 'Running') {
        throw 'native standby service did not start'
    }

    & ping.exe -n 1 -w 1500 $ProbeTarget | Out-Null
    $handshakeOk = $false
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Assert-ProbeNotCancelled
        $rawHandshakes = (& $cli show $ProbeTunnelName latest-handshakes 2>$null | Out-String)
        $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        foreach ($match in [regex]::Matches($rawHandshakes, '(?<!\d)(\d{9,})(?!\d)')) {
            $epoch = [int64]$match.Groups[1].Value
            if ($epoch -gt 0 -and ($nowEpoch - $epoch) -le 120) {
                $handshakeOk = $true
                break
            }
        }
        if ($handshakeOk) { break }
        & ping.exe -n 1 -w 750 $ProbeTarget | Out-Null
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    if (-not $handshakeOk) { throw 'native standby handshake timeout' }
    $script:result.proofKind = 'nativeHandshake'
}

function Invoke-HysteriaProbe {
    param([Parameter(Mandatory=$true)][string]$ConfigPath)
    $exe = Assert-VerifiedRuntime 'hysteria2\hysteria-windows-amd64.exe'
    $raw = [IO.File]::ReadAllText($ConfigPath)
    if ($raw -match '(?im)^\s*(socks5|http|tun|tcpForwarding|udpForwarding)\s*:') {
        throw 'Hysteria standby config contains a listener'
    }
    $endpointMatch = [regex]::Match($raw, '(?im)^\s*server\s*:\s*(\d{1,3}(?:\.\d{1,3}){3}):\d+\s*$')
    if (-not $endpointMatch.Success -or
        $raw -notmatch '(?im)^\s*auth\s*:\s*\S.+' -or
        $raw -notmatch '(?im)^\s*insecure\s*:\s*false\s*$') {
        throw 'Hysteria standby config contract failed'
    }
    Add-ProbeEndpointBypassRoute -Endpoint $endpointMatch.Groups[1].Value
    $port = [int]$ProbePorts.hysteria2
    $runtimeConfig = Join-Path $RuntimeRoot 'hysteria2.yaml'
    Write-PrivateText -Path $runtimeConfig -Content (
        $raw.TrimEnd() + "`r`nsocks5:`r`n  listen: 127.0.0.1:$port`r`n"
    )
    $process = Start-TrackedProcess -FilePath $exe -Arguments @(
        'client', '--disable-update-check', '--log-level', 'error',
        '--config', ('"' + $runtimeConfig + '"')
    ) -WorkingDirectory (Split-Path -Parent $exe) -Name 'hysteria2'
    Wait-LocalTcpPort -Port $port -Process $process
    Invoke-SocksDataPlaneProbe -Port $port -ExpectedEgress $endpointMatch.Groups[1].Value
}

function Invoke-VlessProbe {
    param([Parameter(Mandatory=$true)][string]$ConfigPath)
    $exe = Assert-VerifiedRuntime 'vless-reality\xray.exe'
    $root = [IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
    if (@($root.inbounds).Count -ne 1 -or
        [string]$root.inbounds[0].protocol -ne 'socks' -or
        [string]$root.inbounds[0].listen -ne '127.0.0.1' -or
        [string]$root.outbounds[0].protocol -ne 'vless' -or
        [string]$root.outbounds[0].streamSettings.security -ne 'reality' -or
        [string]$root.outbounds[0].streamSettings.network -ne 'xhttp') {
        throw 'VLESS standby config contract failed'
    }
    $endpoint = [string]$root.outbounds[0].settings.vnext[0].address
    if ($endpoint -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$') {
        throw 'VLESS standby endpoint is invalid'
    }
    Add-ProbeEndpointBypassRoute -Endpoint $endpoint
    $port = [int]$ProbePorts.vless_reality
    $root.inbounds[0].port = $port
    $runtimeConfig = Join-Path $RuntimeRoot 'vless.json'
    Write-PrivateText -Path $runtimeConfig -Content ($root | ConvertTo-Json -Depth 100)
    $validation = Start-Process -FilePath $exe -ArgumentList @(
        'run', '-test', '-config', ('"' + $runtimeConfig + '"')
    ) -WorkingDirectory (Split-Path -Parent $exe) -WindowStyle Hidden -Wait -PassThru
    if ($validation.ExitCode -ne 0) { throw 'VLESS standby config validation failed' }
    $process = Start-TrackedProcess -FilePath $exe -Arguments @(
        'run', '-config', ('"' + $runtimeConfig + '"')
    ) -WorkingDirectory (Split-Path -Parent $exe) -Name 'vless'
    Wait-LocalTcpPort -Port $port -Process $process
    Invoke-SocksDataPlaneProbe -Port $port -ExpectedEgress $endpoint
}

function Invoke-NaiveProbe {
    param([Parameter(Mandatory=$true)][string]$ConfigPath)
    $exe = Assert-VerifiedRuntime 'naive-https\naive.exe'
    $root = [IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
    $proxy = [Uri][string]$root.proxy
    $endpoint = [string]$root.endpointIp
    if ($proxy.Scheme -ne 'https' -or
        $endpoint -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$' -or
        [string]$root.listen -notlike 'socks://127.0.0.1:*') {
        throw 'Naive standby config contract failed'
    }
    Add-ProbeEndpointBypassRoute -Endpoint $endpoint
    $port = [int]$ProbePorts.naive_https
    $root.listen = "socks://127.0.0.1:$port"
    $root.PSObject.Properties.Remove('endpointIp')
    $root | Add-Member -NotePropertyName 'host-resolver-rules' `
        -NotePropertyValue "MAP $($proxy.Host) $endpoint" -Force
    $runtimeConfig = Join-Path $RuntimeRoot 'naive.json'
    Write-PrivateText -Path $runtimeConfig -Content ($root | ConvertTo-Json -Depth 20)
    $process = Start-TrackedProcess -FilePath $exe -Arguments @(
        ('"' + $runtimeConfig + '"')
    ) -WorkingDirectory (Split-Path -Parent $exe) -Name 'naive'
    Wait-LocalTcpPort -Port $port -Process $process
    Invoke-SocksDataPlaneProbe -Port $port -ExpectedEgress $endpoint
}

function Invoke-DnsttProbe {
    param([Parameter(Mandatory=$true)][string]$ConfigPath)
    $exe = Assert-VerifiedRuntime 'dnstt\dnstt-client-windows-amd64.exe'
    $root = [IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
    $resolver = @($root.resolvers)[0]
    $username = [string]$root.socks.username
    $password = [string]$root.socks.password
    $endpoint = [string]$root.expectedEgress
    if ([string]$resolver.mode -ne 'doh' -or
        [string]$resolver.endpoint -ne 'https://1.1.1.1/dns-query' -or
        [string]$root.publicKey -notmatch '^[0-9a-f]{64}$' -or
        [string]$root.zone -notmatch '^[a-z0-9.-]+$' -or
        $username -notmatch '^[A-Za-z0-9_.-]{3,128}$' -or
        $password -notmatch '^[A-Za-z0-9+/=]{16,255}$' -or
        $endpoint -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$') {
        throw 'dnstt standby config contract failed'
    }
    Add-ProbeEndpointBypassRoute -Endpoint '1.1.1.1'
    $port = [int]$ProbePorts.dnstt
    $process = Start-TrackedProcess -FilePath $exe -Arguments @(
        '-doh', [string]$resolver.endpoint,
        '-pubkey', [string]$root.publicKey,
        [string]$root.zone,
        "127.0.0.1:$port"
    ) -WorkingDirectory (Split-Path -Parent $exe) -Name 'dnstt'
    Wait-LocalTcpPort -Port $port -Process $process
    $curlConfig = Join-Path $RuntimeRoot 'dnstt-curl.conf'
    Write-PrivateText -Path $curlConfig -Content (
        "proxy-user = `"$username`:$password`"`r`n"
    )
    Invoke-SocksDataPlaneProbe -Port $port -ExpectedEgress $endpoint -CurlConfig $curlConfig
}

function Read-ValidatedRequest {
    if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) {
        throw 'standby request is missing'
    }
    $item = Get-Item -LiteralPath $RequestPath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $item.Length -lt 40 -or $item.Length -gt 4096) {
        throw 'standby request file is invalid'
    }
    $value = [IO.File]::ReadAllText($RequestPath) | ConvertFrom-Json
    $requestId = ([string]$value.requestId).Trim().ToLowerInvariant()
    $routeId = ([string]$value.routeId).Trim()
    $protocol = ([string]$value.protocol).Trim().ToLowerInvariant()
    if ([int]$value.schema -ne 1 -or
        $requestId -notmatch '^[0-9a-f]{32}$' -or
        $routeId.Length -gt 160 -or
        $routeId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.:-]*$' -or
        $protocol -notin $AllowedProtocols) {
        throw 'standby request contract failed'
    }
    $safeKey = $routeId.ToLowerInvariant() -replace '[^a-z0-9_.-]+', '_'
    $configPath = Join-Path $ServerCacheRoot "$safeKey.base.conf"
    $fullCacheRoot = [IO.Path]::GetFullPath($ServerCacheRoot).TrimEnd('\') + '\'
    $fullConfigPath = [IO.Path]::GetFullPath($configPath)
    if (-not $fullConfigPath.StartsWith($fullCacheRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $fullConfigPath -PathType Leaf)) {
        throw 'standby config is missing'
    }
    $configItem = Get-Item -LiteralPath $fullConfigPath -Force
    if (($configItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $configItem.Length -lt 64 -or $configItem.Length -gt 65536) {
        throw 'standby config file is invalid'
    }
    return [pscustomobject]@{
        requestId = $requestId
        routeId = $routeId
        protocol = $protocol
        configPath = $fullConfigPath
    }
}

function Write-ProbeResult {
    $result.verifiedAt = (Get-Date).ToUniversalTime().ToString('o')
    $temp = $ResultPath + '.tmp'
    $json = ($result | ConvertTo-Json -Depth 6) + [Environment]::NewLine
    $lastFailure = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            [IO.File]::WriteAllText(
                $temp,
                $json,
                [Text.UTF8Encoding]::new($false)
            )
            Move-Item -LiteralPath $temp -Destination $ResultPath -Force
            return
        } catch {
            $lastFailure = $_
            Start-Sleep -Milliseconds 100
        }
    }
    try {
        [IO.File]::WriteAllText(
            $ResultPath,
            $json,
            [Text.UTF8Encoding]::new($false)
        )
        return
    } catch {
        if ($null -ne $lastFailure) { throw $lastFailure }
        throw
    }
}

function Add-CleanupError {
    param([Parameter(Mandatory=$true)][string]$Code)
    $cleanupErrors.Add($Code)
    Write-ProbeDiagnostic -Code "cleanup_error:$Code"
}

$stage = 'request'
$watch = [Diagnostics.Stopwatch]::StartNew()
$failure = $null
$cleanupErrors = New-Object System.Collections.Generic.List[string]
try {
    Stop-ProbeProcesses
    Stop-StaleProbeProcesses
    Stop-NativeProbe
    Remove-AllProbeEndpointBypassRoutes
    if (-not (Remove-ProbeRuntime)) {
        throw 'standby probe startup cleanup failed'
    }
    New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null
    Protect-PrivatePath -Path $RuntimeRoot -Directory

    $request = Read-ValidatedRequest
    $result.requestId = $request.requestId
    $result.routeId = $request.routeId
    $result.protocol = $request.protocol
    Assert-ProbeNotCancelled
    $stage = $request.protocol
    switch ($request.protocol) {
        'wireguard_udp' {
            Invoke-NativeHandshakeProbe -Protocol $request.protocol -ConfigPath $request.configPath
        }
        'amneziawg' {
            Invoke-NativeHandshakeProbe -Protocol $request.protocol -ConfigPath $request.configPath
        }
        'hysteria2' { Invoke-HysteriaProbe -ConfigPath $request.configPath }
        'vless_reality' { Invoke-VlessProbe -ConfigPath $request.configPath }
        'naive_https' { Invoke-NaiveProbe -ConfigPath $request.configPath }
        'dnstt' { Invoke-DnsttProbe -ConfigPath $request.configPath }
    }
    Assert-ProbeNotCancelled
    $result.success = $true
} catch {
    $failure = $_
    $result.cancelled = $_.Exception -is [OperationCanceledException]
    $result.errorCode = if ($result.cancelled) { 'cancelled' } else { "${stage}_failed" }
    Write-ProbeLog "failed stage=$stage cancelled=$($result.cancelled)"
    Write-ProbeDiagnostic -Code "probe_failed:${stage}:$($_.Exception.GetType().Name)"
} finally {
    try { $watch.Stop() } catch { Add-CleanupError -Code 'stopwatch' }
    try { $result.latencyMs = [int]$watch.ElapsedMilliseconds } catch {
        Add-CleanupError -Code 'latency'
    }
    try { Stop-ProbeProcesses } catch { Add-CleanupError -Code 'tracked_processes' }
    try { Stop-StaleProbeProcesses } catch { Add-CleanupError -Code 'stale_processes' }
    try { Stop-NativeProbe } catch { Add-CleanupError -Code 'native_services' }
    try { Remove-ProbeEndpointBypassRoutes } catch {
        Add-CleanupError -Code 'tracked_bypass_routes'
    }
    try { Remove-AllProbeEndpointBypassRoutes } catch {
        Add-CleanupError -Code 'all_bypass_routes'
    }
    $runtimeGone = $false
    try { $runtimeGone = Remove-ProbeRuntime } catch {
        Add-CleanupError -Code 'runtime'
    }
    $nativeGone = $false
    try {
        $nativeGone = @(Get-Service -Name @(
            $ProbeWireGuardService, $ProbeAmneziaService
        ) -ErrorAction SilentlyContinue).Count -eq 0
    } catch { Add-CleanupError -Code 'native_verification' }
    $processesGone = $false
    try {
        $processesGone = @($processes | Where-Object {
            try { $_.Refresh(); -not $_.HasExited } catch { $false }
        }).Count -eq 0
    } catch { Add-CleanupError -Code 'process_verification' }
    $bypassRoutesGone = $false
    try {
        $bypassRoutesGone = (Test-ProbeEndpointBypassRoutesRemoved) -and
            (Test-AllProbeEndpointBypassRoutesRemoved)
    } catch { Add-CleanupError -Code 'bypass_verification' }
    $result.cleanupOk = $nativeGone -and $processesGone -and $bypassRoutesGone -and
        $runtimeGone -and $cleanupErrors.Count -eq 0
    $result.cleanupErrors = @($cleanupErrors)
    if (-not $result.cleanupOk) {
        $result.success = $false
        $result.errorCode = 'cleanup_failed'
    }
    try { Write-ProbeResult } catch {
        Write-ProbeDiagnostic -Code "result_write_failed:$($_.Exception.GetType().Name)"
    }
    try { Remove-Item -LiteralPath $CancelPath -Force -ErrorAction SilentlyContinue } catch {}
}

if (-not $result.success) { throw 'standby probe failed' }
Write-ProbeLog "passed route=$($result.routeId) protocol=$($result.protocol) proof=$($result.proofKind) ms=$($result.latencyMs)"
