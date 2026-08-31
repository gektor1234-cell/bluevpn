param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('full', 'applications')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$SourceConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$ArtifactRoot,

    [string]$ExpectedApplicationEgress = '',

    [ValidateRange(30, 600)]
    [int]$DeadmanDelaySeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $ArtifactRoot) {
    throw "Diagnostic root already exists: $ArtifactRoot"
}
if (-not (Test-Path -LiteralPath $SourceConfigPath -PathType Leaf)) {
    throw "Source config does not exist: $SourceConfigPath"
}

New-Item -ItemType Directory -Path $ArtifactRoot | Out-Null
$programDataRoot = Join-Path $env:ProgramData 'BlueVPN'
$managedConfigPath = Join-Path $programDataRoot 'BlueVPNDev1.conf'
$routingModePath = Join-Path $programDataRoot 'routing_mode'
$tokenPath = Join-Path $programDataRoot 'service_token'
$savedConfigPath = Join-Path $ArtifactRoot 'BlueVPNDev1.conf.before'
$savedRoutingModePath = Join-Path $ArtifactRoot 'routing_mode.before'
$resultPath = Join-Path $ArtifactRoot 'result.json'
$deadmanStatusPath = Join-Path $ArtifactRoot 'deadman.json'
$deadmanScriptPath = Join-Path $PSScriptRoot 'windows_tunnel_path_diagnostic_deadman.ps1'
$selectedExecutable = Join-Path $env:SystemRoot 'System32\curl.exe'
$directControlExecutable = Join-Path $ArtifactRoot 'curl-unselected-control.exe'

Copy-Item -LiteralPath $managedConfigPath -Destination $savedConfigPath
Copy-Item -LiteralPath $routingModePath -Destination $savedRoutingModePath

$deadman = Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $deadmanScriptPath,
        '-StatusPath',
        $deadmanStatusPath,
        '-ConfigBackupPath',
        $savedConfigPath,
        '-ConfigDestinationPath',
        $managedConfigPath,
        '-RoutingModeBackupPath',
        $savedRoutingModePath,
        '-RoutingModeDestinationPath',
        $routingModePath,
        '-DelaySeconds',
        $DeadmanDelaySeconds
    ) `
    -WindowStyle Hidden `
    -PassThru

$result = [ordered]@{
    schema = 1
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    mode = $Mode
    endpoint = ''
    deadmanPid = $deadman.Id
    connect = $null
    snapshot = $null
    tcpProxyReady = $false
    directEgress = ''
    explicitSocksEgress = ''
    selectedEgress = ''
    selectedYoutubeStatus = 0
    healthStatus = 0
    youtubeStatus = 0
    failure = ''
    cleanup = $null
}

try {
    $sourceText = [IO.File]::ReadAllText($SourceConfigPath)
    $endpointMatch = [regex]::Match(
        $sourceText,
        '(?im)^\s*Endpoint\s*=\s*(\d{1,3}(?:\.\d{1,3}){3}):\d+\s*$'
    )
    if (-not $endpointMatch.Success) {
        throw 'Source config has no IPv4-literal endpoint.'
    }
    $result.endpoint = $endpointMatch.Groups[1].Value

    Copy-Item -LiteralPath $SourceConfigPath -Destination $managedConfigPath -Force
    [IO.File]::WriteAllText(
        $routingModePath,
        "$Mode`r`n",
        [Text.Encoding]::ASCII
    )

    $token = (Get-Content -LiteralPath $tokenPath -Raw -Encoding ASCII).Trim()
    $connect = Invoke-RestMethod `
        -Method Post `
        -Uri 'http://127.0.0.1:48737/connect' `
        -Headers @{ 'X-GreenVPN-Local-Token' = $token } `
        -TimeoutSec 120
    $result.connect = $connect
    Start-Sleep -Seconds 4

    $routesToProxy = @(
        Find-NetRoute -RemoteIPAddress '10.10.0.1' -ErrorAction SilentlyContinue |
            Where-Object { $_.CimClass.CimClassName -eq 'MSFT_NetRoute' } |
            ForEach-Object {
                [ordered]@{
                    prefix = [string]$_.DestinationPrefix
                    nextHop = [string]$_.NextHop
                    ifIndex = [int]$_.InterfaceIndex
                    routeMetric = [int]$_.RouteMetric
                    interfaceAlias = [string]$_.InterfaceAlias
                }
            }
    )
    $routesToEndpoint = @(
        Find-NetRoute -RemoteIPAddress $result.endpoint -ErrorAction SilentlyContinue |
            Where-Object { $_.CimClass.CimClassName -eq 'MSFT_NetRoute' } |
            ForEach-Object {
                [ordered]@{
                    prefix = [string]$_.DestinationPrefix
                    nextHop = [string]$_.NextHop
                    ifIndex = [int]$_.InterfaceIndex
                    routeMetric = [int]$_.RouteMetric
                    interfaceAlias = [string]$_.InterfaceAlias
                }
            }
    )
    $adapters = @(
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '(?i)(BlueVPN|GreenVPN|WireGuard|Amnezia|maxim)' -or
                $_.InterfaceDescription -match '(?i)(WireGuard|Amnezia|Wintun)'
            } |
            ForEach-Object {
                [ordered]@{
                    name = [string]$_.Name
                    status = [string]$_.Status
                    ifIndex = [int]$_.ifIndex
                    description = [string]$_.InterfaceDescription
                }
            }
    )
    $services = @(
        Get-Service `
            -Name 'WireGuardTunnel$BlueVPNDev1',
                  'AmneziaWGTunnel$maxim_pc_full',
                  'GreenVPNService' `
            -ErrorAction SilentlyContinue |
            ForEach-Object {
                [ordered]@{
                    name = [string]$_.Name
                    status = [string]$_.Status
                }
            }
    )
    $result.snapshot = [ordered]@{
        routesToProxy = [object[]]$routesToProxy
        routesToEndpoint = [object[]]$routesToEndpoint
        adapters = [object[]]$adapters
        services = [object[]]$services
    }

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $connectTask = $client.ConnectAsync('10.10.0.1', 1080)
        if ($connectTask.Wait(5000) -and $client.Connected) {
            $result.tcpProxyReady = $true
        }
    } finally {
        $client.Dispose()
    }

    Copy-Item -LiteralPath $selectedExecutable `
        -Destination $directControlExecutable -Force
    if (
        (Get-FileHash -LiteralPath $selectedExecutable -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $directControlExecutable -Algorithm SHA256).Hash
    ) {
        throw 'Direct-control executable identity was not preserved.'
    }
    try {
        $result.directEgress = (& $directControlExecutable `
            --silent `
            --show-error `
            --fail `
            --http1.1 `
            --connect-timeout 5 `
            --max-time 12 `
            'https://api.ipify.org').Trim()
    } catch {
    }
    try {
        $result.explicitSocksEgress = (& $directControlExecutable `
            --silent `
            --show-error `
            --fail `
            --http1.1 `
            --socks5-hostname '10.10.0.1:1080' `
            --connect-timeout 5 `
            --max-time 12 `
            'https://api.ipify.org').Trim()
    } catch {
    }
    try {
        $result.selectedEgress = (& $selectedExecutable `
            --silent `
            --show-error `
            --fail `
            --http1.1 `
            --connect-timeout 5 `
            --max-time 12 `
            'https://api.ipify.org').Trim()
    } catch {
    }
    try {
        $result.selectedYoutubeStatus = [int]((& $selectedExecutable `
            --silent `
            --show-error `
            --output 'NUL' `
            --write-out '%{http_code}' `
            --http1.1 `
            --connect-timeout 5 `
            --max-time 15 `
            'https://www.youtube.com/generate_204').Trim())
    } catch {
    }
    if ($Mode -eq 'applications' -and $ExpectedApplicationEgress) {
        if (-not $result.tcpProxyReady) {
            throw 'Application proxy TCP listener was unavailable.'
        }
        if ($result.explicitSocksEgress -ne $ExpectedApplicationEgress) {
            throw 'Explicit SOCKS probe did not use the expected egress.'
        }
        if ($result.selectedEgress -ne $ExpectedApplicationEgress) {
            throw 'Selected executable did not use the expected egress.'
        }
        if ($result.directEgress -eq $result.selectedEgress) {
            throw 'Selected executable did not prove a separate egress.'
        }
        if ($result.selectedYoutubeStatus -ne 204) {
            throw 'Selected executable did not reach YouTube with HTTP 204.'
        }
    }
    try {
        $result.healthStatus = [int](
            Invoke-WebRequest `
                -UseBasicParsing `
                -Uri 'https://api.greenvpn.pro/healthz' `
                -TimeoutSec 10
        ).StatusCode
    } catch {
    }
    try {
        $result.youtubeStatus = [int](
            Invoke-WebRequest `
                -UseBasicParsing `
                -Uri 'https://www.youtube.com/generate_204' `
                -TimeoutSec 10
        ).StatusCode
    } catch {
    }
} catch {
    $result.failure = $_.Exception.Message
} finally {
    $disconnect = $null
    try {
        $token = (Get-Content -LiteralPath $tokenPath -Raw -Encoding ASCII).Trim()
        $disconnect = Invoke-RestMethod `
            -Method Post `
            -Uri 'http://127.0.0.1:48737/disconnect' `
            -Headers @{ 'X-GreenVPN-Local-Token' = $token } `
            -TimeoutSec 120
    } catch {
        $disconnect = [ordered]@{
            ok = $false
            message = $_.Exception.Message
        }
    }

    Copy-Item -LiteralPath $savedConfigPath -Destination $managedConfigPath -Force
    Copy-Item -LiteralPath $savedRoutingModePath -Destination $routingModePath -Force
    Start-Sleep -Seconds 3

    $external = Get-Service -Name 'AmneziaWGTunnel$maxim_pc_full' -ErrorAction SilentlyContinue
    $green = Get-Service -Name 'WireGuardTunnel$BlueVPNDev1' -ErrorAction SilentlyContinue
    $externalStatus = if ($null -eq $external) { 'missing' } else { [string]$external.Status }
    $greenStatus = if ($null -eq $green) { 'missing' } else { [string]$green.Status }
    $apiStatus = 0
    $youtubeStatus = 0
    try {
        $apiStatus = [int](
            Invoke-WebRequest `
                -UseBasicParsing `
                -Uri 'https://api.greenvpn.pro/healthz' `
                -TimeoutSec 10
        ).StatusCode
    } catch {
    }
    try {
        $youtubeStatus = [int](
            Invoke-WebRequest `
                -UseBasicParsing `
                -Uri 'https://www.youtube.com/generate_204' `
                -TimeoutSec 10
        ).StatusCode
    } catch {
    }
    $result.cleanup = [ordered]@{
        disconnect = $disconnect
        externalStatus = $externalStatus
        greenStatus = $greenStatus
        apiStatus = $apiStatus
        youtubeStatus = $youtubeStatus
        configRestored = (
            (Get-FileHash -Algorithm SHA256 -LiteralPath $managedConfigPath).Hash -eq
            (Get-FileHash -Algorithm SHA256 -LiteralPath $savedConfigPath).Hash
        )
        routingModeRestored = (
            (Get-FileHash -Algorithm SHA256 -LiteralPath $routingModePath).Hash -eq
            (Get-FileHash -Algorithm SHA256 -LiteralPath $savedRoutingModePath).Hash
        )
    }

    if (Get-Process -Id $deadman.Id -ErrorAction SilentlyContinue) {
        Stop-Process -Id $deadman.Id -Force -ErrorAction SilentlyContinue
    }
    $result.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $result | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $resultPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 10
