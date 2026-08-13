[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedInstallerSha256,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,

    [string]$AmneziaServiceName = 'AmneziaWGTunnel$device20_full',
    [string]$GreenServiceName = 'GreenVPNService',
    [string]$InstallRoot = 'C:\Program Files\Green VPN',
    [string]$ProgramDataRoot = 'C:\ProgramData\BlueVPN',
    [int]$GreenLocalPort = 48737,
    [ValidateRange(45, 300)]
    [int]$FailoverTimeoutSeconds = 150,
    [ValidateRange(60, 1200)]
    [int]$StandbyCycleTimeoutSeconds = 600,
    [ValidateRange(15, 180)]
    [int]$MaxPrevalidatedFailoverSeconds = 90,
    [ValidateRange(5, 60)]
    [int]$FailsafeDelayMinutes = 15,
    [string]$UserStateRoot = '',
    [switch]$RequireStandbyProof,
    [switch]$UseExistingExactInstall,
    [string]$ReportPath = 'C:\BlueVPN_Builds\windows_public_runtime_failover_physical.json',
    [string]$LogPath = 'C:\BlueVPN_Builds\windows_public_runtime_failover_physical.log'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedInstallerHash = $ExpectedInstallerSha256.ToUpperInvariant()
if ($ExpectedVersion -notmatch '^(\d+\.\d+\.\d+)(?:\+(\d+))?$') {
    throw "ExpectedVersion must be x.y.z or x.y.z+build: $ExpectedVersion"
}
$expectedDisplayVersion = [string]$Matches[1]
$resolvedInstaller = [IO.Path]::GetFullPath($InstallerPath)
$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$resolvedProgramDataRoot = [IO.Path]::GetFullPath($ProgramDataRoot).TrimEnd('\')
$tokenPath = Join-Path $resolvedProgramDataRoot 'service_token'
$managedConfigPath = Join-Path $resolvedProgramDataRoot 'BlueVPNDev1.conf'
$protocolPath = "$managedConfigPath.protocol"
$routeIdPath = "$managedConfigPath.route_id"
$pendingActionPath = Join-Path $resolvedProgramDataRoot 'state\pending_vpn_action.txt'
$routingModePath = Join-Path $resolvedProgramDataRoot 'routing_mode'
$routingAppsPath = Join-Path $resolvedProgramDataRoot 'routing_apps.json'
$authLogPath = Join-Path $resolvedProgramDataRoot 'auth.log'
$resolvedUserStateRoot = if ([string]::IsNullOrWhiteSpace($UserStateRoot)) {
    Join-Path $env:APPDATA 'GreenVPN\state'
} else {
    [IO.Path]::GetFullPath($UserStateRoot).TrimEnd('\')
}
$standbyProofPath = Join-Path $resolvedUserStateRoot 'standby_routes.json'
$standbyRuntimeRoot = Join-Path $resolvedProgramDataRoot 'standby-probe-runtime'
$standbyProbeRequestPath = Join-Path $resolvedProgramDataRoot 'standby-probe-request.json'
$standbyProbeResultPath = Join-Path $resolvedProgramDataRoot 'standby-probe-result.json'
$standbyCancelPath = Join-Path $resolvedProgramDataRoot 'standby-probe.cancel'
$appPath = Join-Path $resolvedInstallRoot 'greenvpn.exe'
$taskScriptPath = Join-Path $resolvedInstallRoot 'tools\greenvpn_vpn_task.ps1'
$failSafeTaskName = 'GreenVPNPublicRuntimeFailoverSmokeFailsafe'
$componentStateKeys = @(
    'wireGuardState',
    'amneziaWgState',
    'hysteriaClientState',
    'hysteriaTunState',
    'vlessClientState',
    'vlessTunState',
    'naiveClientState',
    'naiveTunState',
    'dnsttClientState',
    'dnsttTunState',
    'processRouterState'
)
$protocolRank = @{
    wireguard_udp = 0
    amneziawg = 1
    hysteria2 = 2
    vless_reality = 3
    naive_https = 4
    dnstt = 5
}
$standbyConfigTimestampToleranceMilliseconds = 1000

function Write-SmokeLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    $directory = Split-Path -Parent $LogPath
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $safe = $Message -replace '(?i)(token|password|secret|private.?key)\s*=\s*\S+', '$1=[redacted]'
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "[$((Get-Date).ToUniversalTime().ToString('o'))] $safe"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Convert-ToQuotedArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

if (-not (Test-IsAdministrator)) {
    $arguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Convert-ToQuotedArgument $PSCommandPath),
        '-InstallerPath',
        (Convert-ToQuotedArgument $resolvedInstaller),
        '-ExpectedInstallerSha256',
        $expectedInstallerHash,
        '-ExpectedVersion',
        (Convert-ToQuotedArgument $ExpectedVersion),
        '-AmneziaServiceName',
        (Convert-ToQuotedArgument $AmneziaServiceName),
        '-GreenServiceName',
        (Convert-ToQuotedArgument $GreenServiceName),
        '-InstallRoot',
        (Convert-ToQuotedArgument $resolvedInstallRoot),
        '-ProgramDataRoot',
        (Convert-ToQuotedArgument $resolvedProgramDataRoot),
        '-GreenLocalPort',
        $GreenLocalPort,
        '-FailoverTimeoutSeconds',
        $FailoverTimeoutSeconds,
        '-StandbyCycleTimeoutSeconds',
        $StandbyCycleTimeoutSeconds,
        '-MaxPrevalidatedFailoverSeconds',
        $MaxPrevalidatedFailoverSeconds,
        '-FailsafeDelayMinutes',
        $FailsafeDelayMinutes,
        '-UserStateRoot',
        (Convert-ToQuotedArgument $resolvedUserStateRoot),
        '-ReportPath',
        (Convert-ToQuotedArgument ([IO.Path]::GetFullPath($ReportPath))),
        '-LogPath',
        (Convert-ToQuotedArgument ([IO.Path]::GetFullPath($LogPath)))
    )
    if ($UseExistingExactInstall) {
        $arguments += '-UseExistingExactInstall'
    }
    if ($RequireStandbyProof) {
        $arguments += '-RequireStandbyProof'
    }
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -Wait -ArgumentList $arguments
    exit $process.ExitCode
}

function Get-ServiceState {
    param([Parameter(Mandatory = $true)][string]$Name)

    $service = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($null -eq $service) { return 'Missing' }
    return [string]$service.State
}

function Wait-ServiceState {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('Running', 'Stopped', 'Missing')][string]$State,
        [int]$TimeoutSeconds = 45
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if ((Get-ServiceState -Name $Name) -eq $State) { return $true }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Get-LocalToken {
    if (-not (Test-Path -LiteralPath $tokenPath -PathType Leaf)) {
        throw 'Green VPN local service token is missing.'
    }
    $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
    if ($token.Length -lt 24) {
        throw 'Green VPN local service token is invalid.'
    }
    return $token
}

function Invoke-GreenLocal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$TimeoutSeconds = 135
    )

    $headers = @{ 'X-GreenVPN-Local-Token' = (Get-LocalToken) }
    return Invoke-RestMethod -Method $Method -Uri "http://127.0.0.1:$GreenLocalPort$Path" `
        -Headers $headers -TimeoutSec $TimeoutSeconds
}

function Get-GreenStatus {
    return Invoke-GreenLocal -Method GET -Path '/status' -TimeoutSeconds 8
}

function Get-ActiveTransportGroups {
    param([Parameter(Mandatory = $true)]$Status)

    $groups = New-Object System.Collections.Generic.List[string]
    if ([string]$Status.wireGuardState -eq 'running') { $groups.Add('wireguard_udp') }
    if ([string]$Status.amneziaWgState -eq 'running') { $groups.Add('amneziawg') }
    if (
        [string]$Status.hysteriaClientState -eq 'running' -or
        [string]$Status.hysteriaTunState -eq 'running'
    ) { $groups.Add('hysteria2') }
    if (
        [string]$Status.vlessClientState -eq 'running' -or
        [string]$Status.vlessTunState -eq 'running'
    ) { $groups.Add('vless_reality') }
    if (
        [string]$Status.naiveClientState -eq 'running' -or
        [string]$Status.naiveTunState -eq 'running'
    ) { $groups.Add('naive_https') }
    if (
        [string]$Status.dnsttClientState -eq 'running' -or
        [string]$Status.dnsttTunState -eq 'running'
    ) { $groups.Add('dnstt') }
    return @($groups.ToArray())
}

function Test-AllComponentsStopped {
    param([Parameter(Mandatory = $true)]$Status)

    foreach ($key in $componentStateKeys) {
        $state = ([string]$Status.$key).Trim().ToLowerInvariant()
        if ($state -notin @('stopped', 'missing')) { return $false }
    }
    return $true
}

function Test-FileAclAllows {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Sid,
        [Parameter(Mandatory = $true)][Security.AccessControl.FileSystemRights]$RequiredRights
    )

    $securityIdentifier = [Security.Principal.SecurityIdentifier]::new($Sid)
    $rules = (Get-Acl -LiteralPath $Path).GetAccessRules(
        $true,
        $true,
        [Security.Principal.SecurityIdentifier]
    )
    $allowed = [Security.AccessControl.FileSystemRights]0
    foreach ($rule in $rules) {
        if ($rule.IdentityReference.Value -ne $securityIdentifier.Value) { continue }
        if (
            $rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Deny -and
            (($rule.FileSystemRights -band $RequiredRights) -ne 0)
        ) {
            return $false
        }
        if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow) {
            $allowed = $allowed -bor $rule.FileSystemRights
        }
    }
    return (($allowed -band $RequiredRights) -eq $RequiredRights)
}

function Test-NoBroadAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    $broadSids = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545')
    $rules = (Get-Acl -LiteralPath $Path).GetAccessRules(
        $true,
        $true,
        [Security.Principal.SecurityIdentifier]
    )
    foreach ($rule in $rules) {
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) {
            continue
        }
        if ($rule.IdentityReference.Value -in $broadSids) {
            return $false
        }
    }
    return $true
}

function Get-ProtectedProgramDataEvidence {
    $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $paths = @(
        $resolvedProgramDataRoot,
        $tokenPath,
        $managedConfigPath,
        $protocolPath,
        $routingModePath,
        $routingAppsPath
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $broadAccessRemoved = $true
    $inheritanceProtected = $true
    foreach ($path in $paths) {
        if (-not (Test-NoBroadAcl -Path $path)) {
            $broadAccessRemoved = $false
        }
        if (-not (Get-Acl -LiteralPath $path).AreAccessRulesProtected) {
            $inheritanceProtected = $false
        }
    }

    return [ordered]@{
        checkedPaths = $paths.Count
        broadAccessRemoved = $broadAccessRemoved
        inheritanceProtected = $inheritanceProtected
        ownerCanModifyState = Test-FileAclAllows -Path $resolvedProgramDataRoot `
            -Sid $ownerSid -RequiredRights ([Security.AccessControl.FileSystemRights]::Modify)
        ownerCanReadToken = Test-FileAclAllows -Path $tokenPath -Sid $ownerSid `
            -RequiredRights ([Security.AccessControl.FileSystemRights]::Read)
        systemHasFullControl = (
            Test-FileAclAllows -Path $resolvedProgramDataRoot -Sid 'S-1-5-18' `
                -RequiredRights ([Security.AccessControl.FileSystemRights]::FullControl
            )
        )
    }
}

function Wait-AllGreenComponentsStopped {
    param([int]$TimeoutSeconds = 45)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            if (Test-AllComponentsStopped -Status (Get-GreenStatus)) { return $true }
        } catch {}
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Get-ManagedRouteId {
    if (-not (Test-Path -LiteralPath $routeIdPath -PathType Leaf)) { return '' }
    return (Get-Content -LiteralPath $routeIdPath -Raw).Trim()
}

function Invoke-ExternalProbe {
    param([Parameter(Mandatory = $true)][string]$Url)

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 20
        return [ordered]@{
            target = ([Uri]$Url).Host
            ok = $response.StatusCode -ge 200 -and $response.StatusCode -lt 400
            statusCode = [int]$response.StatusCode
        }
    } catch {
        $statusCode = $null
        if ($null -ne $_.Exception.Response) {
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
        }
        return [ordered]@{
            target = ([Uri]$Url).Host
            ok = $false
            statusCode = $statusCode
            errorType = $_.Exception.GetType().Name
        }
    }
}

function Get-EgressFingerprint {
    foreach ($url in @('https://api.ipify.org', 'https://ifconfig.me/ip')) {
        try {
            $value = (Invoke-RestMethod -Uri $url -TimeoutSec 15).ToString().Trim()
            if ($value) {
                $bytes = [Text.Encoding]::UTF8.GetBytes($value)
                $sha = [Security.Cryptography.SHA256]::Create()
                try {
                    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
                } finally {
                    $sha.Dispose()
                    [Array]::Clear($bytes, 0, $bytes.Length)
                    $value = $null
                }
            }
        } catch {}
    }
    return ''
}

function Get-EgressIp {
    foreach ($url in @('https://api.ipify.org', 'https://ifconfig.me/ip')) {
        try {
            $value = (Invoke-RestMethod -Uri $url -TimeoutSec 15).ToString().Trim()
            $parsed = $null
            if ($value -and [Net.IPAddress]::TryParse($value, [ref]$parsed)) {
                return $value
            }
        } catch {}
    }
    return ''
}

function Test-ExpectedRouteEgress {
    param([Parameter(Mandatory = $true)][string]$RouteId)

    $expected = ''
    if ($RouteId -eq 'current_wg0') {
        $expected = '37.220.85.211'
    } elseif ($RouteId -eq 'ruvds-2584554-ld8' -or $RouteId -match '^gb1-') {
        $expected = '88.218.250.86'
    } elseif ($RouteId -eq 'tw-7879598-nl1' -or $RouteId -match '^nl2-') {
        $expected = '5.129.216.42'
    } elseif ($RouteId -match '^nl1-') {
        $expected = '37.220.85.211'
    } else {
        throw "No expected egress mapping exists for route $RouteId."
    }

    $actual = Get-EgressIp
    try {
        return $actual -and $actual.Equals($expected, [StringComparison]::Ordinal)
    } finally {
        $actual = $null
        $expected = $null
    }
}

function Get-ProtocolTunnelAlias {
    param([Parameter(Mandatory = $true)][string]$Protocol)

    $alias = switch ($Protocol) {
        'wireguard_udp' { 'BlueVPNDev1' }
        'amneziawg' { 'BlueVPNDev1' }
        'hysteria2' { 'GreenVPNHysteria' }
        'vless_reality' { 'GreenVPNVless' }
        'naive_https' { 'GreenVPNNaive' }
        'dnstt' { 'GreenVPNDnstt' }
        default { throw "Unsupported protocol tunnel alias: $Protocol" }
    }
    return $alias
}

function Get-RouteProtectionEvidence {
    param([Parameter(Mandatory = $true)][string]$TunnelAlias)

    function Get-BestRouteAlias {
        param(
            [Parameter(Mandatory = $true)][ValidateSet('IPv4', 'IPv6')][string]$Family,
            [Parameter(Mandatory = $true)][string]$Prefix
        )

        $route = @(
            Get-NetRoute -AddressFamily $Family -DestinationPrefix $Prefix -ErrorAction SilentlyContinue |
                Where-Object { $_.State -ne 'Dead' } |
                Sort-Object RouteMetric, InterfaceMetric
        ) | Select-Object -First 1
        if ($null -eq $route) { return '' }
        return [string]$route.InterfaceAlias
    }

    $ipv4Default = Get-BestRouteAlias -Family IPv4 -Prefix '0.0.0.0/0'
    $ipv4Lower = Get-BestRouteAlias -Family IPv4 -Prefix '0.0.0.0/1'
    $ipv4Upper = Get-BestRouteAlias -Family IPv4 -Prefix '128.0.0.0/1'
    $ipv4DefaultProtected = $ipv4Default -eq $TunnelAlias
    $ipv4SplitProtected = $ipv4Lower -eq $TunnelAlias -and $ipv4Upper -eq $TunnelAlias

    $ipv6Default = Get-BestRouteAlias -Family IPv6 -Prefix '::/0'
    $ipv6Lower = Get-BestRouteAlias -Family IPv6 -Prefix '::/1'
    $ipv6Upper = Get-BestRouteAlias -Family IPv6 -Prefix '8000::/1'
    $ipv6DefaultProtected = $ipv6Default -eq $TunnelAlias
    $ipv6SplitProtected = $ipv6Lower -eq $TunnelAlias -and $ipv6Upper -eq $TunnelAlias
    $ipv6RouteAbsent = -not $ipv6Default -and -not $ipv6Lower -and -not $ipv6Upper

    return [ordered]@{
        ipv4Protected = $ipv4DefaultProtected -or $ipv4SplitProtected
        ipv4Mode = if ($ipv4DefaultProtected) {
            'default'
        } elseif ($ipv4SplitProtected) {
            'split_default'
        } else {
            'missing'
        }
        ipv6Protected = $ipv6DefaultProtected -or $ipv6SplitProtected -or $ipv6RouteAbsent
        ipv6Mode = if ($ipv6DefaultProtected) {
            'default'
        } elseif ($ipv6SplitProtected) {
            'split_default'
        } elseif ($ipv6RouteAbsent) {
            'no_route'
        } else {
            'unprotected'
        }
    }
}

function Invoke-DirectDnsLeakProbe {
    param([Parameter(Mandatory = $true)][string]$TunnelAlias)

    $attempted = 0
    $reachableOutsideTunnel = 0
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Status -eq 'Up' -and
            $_.Name -ne $TunnelAlias -and
            $_.Name -notmatch '(?i)(loopback|isatap|teredo)' -and
            $_.InterfaceDescription -notmatch '(?i)(wireguard|wintun|amnezia|warp|cloudflare)'
        }

    foreach ($adapter in $adapters) {
        $dnsRows = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -ErrorAction SilentlyContinue
        foreach ($serverValue in @(
            $dnsRows |
                ForEach-Object { $_.ServerAddresses } |
                ForEach-Object { $_ } |
                Where-Object { $_ }
        )) {
            $serverForParse = ([string]$serverValue -split '%', 2)[0]
            $ipAddress = $null
            if (-not [Net.IPAddress]::TryParse($serverForParse, [ref]$ipAddress)) { continue }
            if ($ipAddress.ToString() -match '^(?i)fec0:0:0:ffff::[1-3]$') { continue }

            $routeAlias = ''
            try {
                $route = @(
                    Find-NetRoute -RemoteIPAddress $serverForParse -ErrorAction SilentlyContinue |
                        Where-Object { $_.CimClass.CimClassName -eq 'MSFT_NetRoute' }
                ) | Select-Object -First 1
                if ($null -ne $route) { $routeAlias = [string]$route.InterfaceAlias }
            } catch {}
            if ($routeAlias -eq $TunnelAlias) { continue }

            $attempted += 1
            try {
                $answers = @(
                    Resolve-DnsName 'www.youtube.com' -Server ([string]$serverValue) `
                        -DnsOnly -QuickTimeout -ErrorAction Stop
                )
                if ($answers.Count -gt 0) { $reachableOutsideTunnel += 1 }
            } catch {}
        }
    }

    return [ordered]@{
        attempted = $attempted
        reachableOutsideTunnel = $reachableOutsideTunnel
        blockedOrUnreachable = $attempted - $reachableOutsideTunnel
        leakDetected = $reachableOutsideTunnel -gt 0
    }
}

function Get-NetworkProtectionEvidence {
    param([Parameter(Mandatory = $true)][string]$Protocol)

    $dnsResolutionOk = $false
    $dnsAnswerCount = 0
    try {
        $dnsAnswers = @(Resolve-DnsName 'www.youtube.com' -DnsOnly -ErrorAction Stop)
        $dnsAnswerCount = $dnsAnswers.Count
        $dnsResolutionOk = $dnsAnswerCount -gt 0
    } catch {}

    $tunnelAlias = Get-ProtocolTunnelAlias -Protocol $Protocol
    return [ordered]@{
        dnsResolution = [ordered]@{
            ok = $dnsResolutionOk
            answerCount = $dnsAnswerCount
        }
        directDnsLeak = Invoke-DirectDnsLeakProbe -TunnelAlias $tunnelAlias
        routes = Get-RouteProtectionEvidence -TunnelAlias $tunnelAlias
    }
}

function Stop-GreenApp {
    if (Test-Path -LiteralPath $appPath -PathType Leaf) {
        try {
            $shutdown = Start-Process -FilePath $appPath `
                -ArgumentList @('--shutdown-existing', '--background') `
                -WorkingDirectory $resolvedInstallRoot `
                -WindowStyle Hidden `
                -PassThru
            $shutdown.WaitForExit(15000) | Out-Null
        } catch {}
    }
    $deadline = (Get-Date).AddSeconds(12)
    do {
        $running = @(
            Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue |
                Where-Object {
                    try {
                        $_.Path -and
                            [IO.Path]::GetFullPath([string]$_.Path).Equals(
                                $appPath,
                                [StringComparison]::OrdinalIgnoreCase
                            )
                    } catch { $false }
                }
        )
        if ($running.Count -eq 0) { return }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    foreach ($process in $running) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 700
}

function Start-GreenApp {
    if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) {
        throw 'Installed Green VPN executable is missing.'
    }
    return Start-Process -FilePath $appPath -WorkingDirectory $resolvedInstallRoot -PassThru
}

function Wait-GreenRoute {
    param(
        [string]$DifferentFromRouteId = '',
        [int]$TimeoutSeconds = 120,
        [scriptblock]$OnSample = $null
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $status = Get-GreenStatus
            if ($null -ne $OnSample) { & $OnSample $status }
            $routeId = Get-ManagedRouteId
            if (
                $status.ok -eq $true -and
                [string]$status.tunnelState -eq 'running' -and
                $routeId -and
                (-not $DifferentFromRouteId -or $routeId -ne $DifferentFromRouteId)
            ) {
                return [pscustomobject]@{ status = $status; routeId = $routeId }
            }
        } catch {}
        Start-Sleep -Milliseconds $(if ($null -ne $OnSample) { 100 } else { 500 })
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Get-AuthLogLineCount {
    if (-not (Test-Path -LiteralPath $authLogPath -PathType Leaf)) { return 0 }
    return @(Get-Content -LiteralPath $authLogPath -ErrorAction SilentlyContinue).Count
}

function Wait-LogMarker {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$AfterLine = 0,
        [int]$TimeoutSeconds = 45
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $authLogPath -PathType Leaf) {
            $lines = @(Get-Content -LiteralPath $authLogPath -ErrorAction SilentlyContinue)
            $newLines = if ($lines.Count -lt $AfterLine) {
                $lines
            } elseif ($lines.Count -eq $AfterLine) {
                @()
            } else {
                @($lines[$AfterLine..($lines.Count - 1)])
            }
            if (($newLines -join "`n") -match $Pattern) { return $true }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Get-NewAuthLogLines {
    param([int]$AfterLine = 0)

    if (-not (Test-Path -LiteralPath $authLogPath -PathType Leaf)) {
        return @()
    }
    $lines = @(Get-Content -LiteralPath $authLogPath -ErrorAction SilentlyContinue)
    if ($lines.Count -le $AfterLine) { return @() }
    return @($lines[$AfterLine..($lines.Count - 1)])
}

function Get-StandbyCleanupEvidence {
    $probeServices = @(
        'WireGuardTunnel$GreenVPNTransportPreviewStandbyProbe',
        'AmneziaWGTunnel$GreenVPNTransportPreviewStandbyProbe'
    )
    $activeProbeServices = @(
        $probeServices | Where-Object {
            (Get-ServiceState -Name $_) -notin @('Missing', 'Stopped')
        }
    )
    $bypassRoutes = @(
        Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
            [int]$_.RouteMetric -eq 42739
        }
    )
    $listeners = @(
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.LocalPort -in @(21980, 21981, 21982, 21983) }
    )
    $runtimeNeedle = [IO.Path]::GetFullPath($standbyRuntimeRoot)
    $probeProcessNames = @(
        'hysteria-windows-amd64.exe',
        'xray.exe',
        'naive.exe',
        'dnstt-client-windows-amd64.exe',
        'hev-socks5-tunnel.exe'
    )
    $activeProbeProcesses = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                [string]$_.Name -in $probeProcessNames -and
                -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
                ([string]$_.CommandLine).IndexOf(
                    $runtimeNeedle,
                    [StringComparison]::OrdinalIgnoreCase
                ) -ge 0
            } |
            Select-Object Name, ProcessId
    )
    $lastResultExists = $false
    $lastResultCleanupOk = $true
    $lastResultCleanupErrors = @()
    if (Test-Path -LiteralPath $standbyProbeResultPath -PathType Leaf) {
        $lastResultExists = $true
        try {
            $lastResult = Get-Content -LiteralPath $standbyProbeResultPath -Raw -Encoding UTF8 |
                ConvertFrom-Json
            $lastResultCleanupOk = [bool]$lastResult.cleanupOk
            $lastResultCleanupErrors = @($lastResult.cleanupErrors)
        } catch {
            $lastResultCleanupOk = $false
            $lastResultCleanupErrors = @('result_parse_failed')
        }
    }
    $physicalArtifactsClean =
        -not (Test-Path -LiteralPath $standbyRuntimeRoot) -and
        $activeProbeServices.Count -eq 0 -and
        $activeProbeProcesses.Count -eq 0 -and
        $bypassRoutes.Count -eq 0 -and
        $listeners.Count -eq 0 -and
        -not (Test-Path -LiteralPath $standbyCancelPath)
    return [pscustomobject]@{
        runtimeRootAbsent = -not (Test-Path -LiteralPath $standbyRuntimeRoot)
        activeProbeServices = @($activeProbeServices)
        activeProbeProcesses = @($activeProbeProcesses)
        bypassRouteCount = $bypassRoutes.Count
        probeListenerCount = $listeners.Count
        requestAbsent = -not (Test-Path -LiteralPath $standbyProbeRequestPath)
        cancelMarkerAbsent = -not (Test-Path -LiteralPath $standbyCancelPath)
        physicalArtifactsClean = $physicalArtifactsClean
        lastResultExists = $lastResultExists
        lastResultCleanupOk = $lastResultCleanupOk
        lastResultCleanupErrors = @($lastResultCleanupErrors)
        lastResultOverriddenByPhysicalEvidence = $false
        cleanupOk = $physicalArtifactsClean -and
            -not (Test-Path -LiteralPath $standbyProbeRequestPath) -and
            $lastResultCleanupOk
    }
}

function Wait-StandbyCleanupEvidence {
    param(
        [int]$TimeoutSeconds = 30,
        [int]$PollMilliseconds = 250
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $requestRemovedByHarness = $false
    $stablePhysicalCleanupSince = $null
    do {
        $evidence = Get-StandbyCleanupEvidence
        if ([bool]$evidence.cleanupOk) {
            $watch.Stop()
            $evidence | Add-Member -NotePropertyName waitedMilliseconds `
                -NotePropertyValue ([math]::Round($watch.Elapsed.TotalMilliseconds))
            $evidence | Add-Member -NotePropertyName requestRemovedByHarness `
                -NotePropertyValue $requestRemovedByHarness
            return $evidence
        }
        $probeQuiescent = [bool]$evidence.physicalArtifactsClean
        if ($probeQuiescent -and -not [bool]$evidence.requestAbsent) {
            Remove-Item -LiteralPath $standbyProbeRequestPath -Force `
                -ErrorAction SilentlyContinue
            $requestRemovedByHarness =
                -not (Test-Path -LiteralPath $standbyProbeRequestPath)
        }
        $stablePhysicalCleanup =
            $probeQuiescent -and
            -not (Test-Path -LiteralPath $standbyProbeRequestPath)
        if ($stablePhysicalCleanup) {
            if ($null -eq $stablePhysicalCleanupSince) {
                $stablePhysicalCleanupSince = Get-Date
            } elseif (((Get-Date) - $stablePhysicalCleanupSince).TotalSeconds -ge 2) {
                $evidence = Get-StandbyCleanupEvidence
                if (
                    [bool]$evidence.physicalArtifactsClean -and
                    [bool]$evidence.requestAbsent
                ) {
                    $watch.Stop()
                    $evidence.lastResultOverriddenByPhysicalEvidence =
                        -not [bool]$evidence.lastResultCleanupOk
                    $evidence.cleanupOk = $true
                    $evidence | Add-Member -NotePropertyName waitedMilliseconds `
                        -NotePropertyValue ([math]::Round($watch.Elapsed.TotalMilliseconds))
                    $evidence | Add-Member -NotePropertyName requestRemovedByHarness `
                        -NotePropertyValue $requestRemovedByHarness
                    return $evidence
                }
            }
        } else {
            $stablePhysicalCleanupSince = $null
        }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds)

    $watch.Stop()
    $evidence = Get-StandbyCleanupEvidence
    $evidence | Add-Member -NotePropertyName waitedMilliseconds `
        -NotePropertyValue ([math]::Round($watch.Elapsed.TotalMilliseconds))
    $evidence | Add-Member -NotePropertyName requestRemovedByHarness `
        -NotePropertyValue $requestRemovedByHarness
    return $evidence
}

function Get-StandbyCycleEvidence {
    param(
        [Parameter(Mandatory = $true)][int]$AfterLine,
        [Parameter(Mandatory = $true)][datetime]$StartedAtUtc
    )

    $lines = @(Get-NewAuthLogLines -AfterLine $AfterLine)
    $startMatch = $null
    $completeMatch = $null
    foreach ($line in $lines) {
        if ($line -match 'windows standby cycle started active=(?<active>\S+) eligible=(?<eligible>.*)$') {
            $startMatch = $Matches.Clone()
        }
        if ($line -match 'windows standby cycle complete active=(?<active>\S+) checked=(?<checked>\d+) fresh=(?<fresh>\d+) candidates=(?<candidates>\d+)') {
            $completeMatch = $Matches.Clone()
        }
    }

    $eligible = @()
    if ($null -ne $startMatch -and -not [string]::IsNullOrWhiteSpace([string]$startMatch.eligible)) {
        $eligible = @(
            ([string]$startMatch.eligible).Split(',') |
                ForEach-Object { $_.Trim().ToLowerInvariant() } |
                Where-Object { $_ }
        )
    }

    $outcomes = @{}
    foreach ($line in $lines) {
        if ($line -match 'windows standby probe (?<status>confirmed|failed) server=(?<route>[^ ]+) protocol=(?<protocol>[^ ]+)') {
            $key = "$($Matches.route.ToLowerInvariant())/$($Matches.protocol.ToLowerInvariant())"
            $outcomes[$key] = [string]$Matches.status
        } elseif ($line -match 'windows standby config (?<status>refresh failed|rejected) (?:server|requested)=(?<route>[^ /]+)(?:/(?<protocol>[^ ]+))?') {
            $route = [string]$Matches.route
            $protocol = if ($Matches.ContainsKey('protocol')) {
                [string]$Matches.protocol
            } else {
                ''
            }
            $matchingEligible = @($eligible | Where-Object {
                $_ -eq "$($route.ToLowerInvariant())/$($protocol.ToLowerInvariant())" -or
                $_ -like "$($route.ToLowerInvariant())/*"
            })
            foreach ($key in $matchingEligible) {
                $outcomes[$key] = ([string]$Matches.status).Replace(' ', '_')
            }
        }
    }

    $proofs = @()
    if (Test-Path -LiteralPath $standbyProofPath -PathType Leaf) {
        try {
            $root = Get-Content -LiteralPath $standbyProofPath -Raw -Encoding UTF8 |
                ConvertFrom-Json
            if ([int]$root.schema -eq 1) {
                foreach ($proof in @($root.proofs)) {
                    $routeId = ([string]$proof.routeId).Trim().ToLowerInvariant()
                    $protocol = ([string]$proof.protocol).Trim().ToLowerInvariant()
                    $preparedAt = [datetime]::Parse([string]$proof.preparedAt).ToUniversalTime()
                    $verifiedAt = [datetime]::Parse([string]$proof.verifiedAt).ToUniversalTime()
                    $configPath = Join-Path (
                        Join-Path $resolvedProgramDataRoot 'server-cache'
                    ) "$routeId.base.conf"
                    $configModifiedAt = $null
                    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
                        $configModifiedAt = (Get-Item -LiteralPath $configPath).LastWriteTimeUtc
                    }
                    $configTimestampDeltaMilliseconds = if ($null -ne $configModifiedAt) {
                        [math]::Abs(
                            ($preparedAt - $configModifiedAt).TotalMilliseconds
                        )
                    } else {
                        $null
                    }
                    # Dart exposes Windows file timestamps at whole-second precision.
                    $configBound =
                        $null -ne $configTimestampDeltaMilliseconds -and
                        $configTimestampDeltaMilliseconds -lt
                            $standbyConfigTimestampToleranceMilliseconds
                    $age = ((Get-Date).ToUniversalTime() - $verifiedAt).TotalSeconds
                    $fresh =
                        $verifiedAt -ge $StartedAtUtc.ToUniversalTime() -and
                        $age -ge 0 -and
                        $age -le 600 -and
                        $configBound
                    $proofs += [pscustomobject]@{
                        key = "$routeId/$protocol"
                        routeId = $routeId
                        protocol = $protocol
                        kind = [string]$proof.kind
                        preparedAt = $preparedAt.ToString('o')
                        verifiedAt = $verifiedAt.ToString('o')
                        latencyMs = [int]$proof.latencyMs
                        configModifiedAt = if ($null -ne $configModifiedAt) {
                            $configModifiedAt.ToString('o')
                        } else {
                            $null
                        }
                        configTimestampDeltaMs = $configTimestampDeltaMilliseconds
                        configTimestampToleranceMs =
                            $standbyConfigTimestampToleranceMilliseconds
                        configBound = $configBound
                        fresh = $fresh
                    }
                }
            }
        } catch {}
    }
    $freshProofs = @($proofs | Where-Object { $_.fresh })
    foreach ($proof in $freshProofs) {
        $outcomes[[string]$proof.key] = 'confirmed'
    }
    $unaccounted = @($eligible | Where-Object { -not $outcomes.ContainsKey($_) })
    $cleanup = Get-StandbyCleanupEvidence
    return [pscustomobject]@{
        cycleStarted = $null -ne $startMatch
        cycleCompleted = $null -ne $completeMatch
        active = if ($null -ne $completeMatch) { [string]$completeMatch.active } else { $null }
        checked = if ($null -ne $completeMatch) { [int]$completeMatch.checked } else { 0 }
        freshReported = if ($null -ne $completeMatch) { [int]$completeMatch.fresh } else { 0 }
        candidateCount = if ($null -ne $completeMatch) { [int]$completeMatch.candidates } else { 0 }
        eligibleRoutes = @($eligible)
        outcomes = [pscustomobject]$outcomes
        proofs = @($proofs)
        freshProofs = @($freshProofs)
        unaccountedRoutes = @($unaccounted)
        allEligibleAccounted = $unaccounted.Count -eq 0
        cleanup = $cleanup
    }
}

function Wait-StandbyCycleEvidence {
    param(
        [Parameter(Mandatory = $true)][int]$AfterLine,
        [Parameter(Mandatory = $true)][datetime]$StartedAtUtc,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $evidence = Get-StandbyCycleEvidence `
            -AfterLine $AfterLine `
            -StartedAtUtc $StartedAtUtc
        if ($evidence.cycleCompleted) { return $evidence }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    return Get-StandbyCycleEvidence `
        -AfterLine $AfterLine `
        -StartedAtUtc $StartedAtUtc
}

function Stop-ActiveTransportEngine {
    param([Parameter(Mandatory = $true)]$Status)

    $protocol = [string]$Status.protocol
    if ($protocol -eq 'wireguard_udp') {
        $name = 'WireGuardTunnel$BlueVPNDev1'
        if ((Get-ServiceState -Name $name) -ne 'Running') {
            throw 'Selected WireGuard service was not running before injection.'
        }
        Stop-Service -Name $name -Force -ErrorAction Stop
        return 'tunnel_service'
    }
    if ($protocol -eq 'amneziawg') {
        $name = 'AmneziaWGTunnel$BlueVPNDev1'
        if ((Get-ServiceState -Name $name) -ne 'Running') {
            throw 'Selected AmneziaWG service was not running before injection.'
        }
        Stop-Service -Name $name -Force -ErrorAction Stop
        return 'tunnel_service'
    }

    $pidFileName = switch ($protocol) {
        'hysteria2' { 'hysteria2-client.pid' }
        'vless_reality' { 'vless-reality-client.pid' }
        'naive_https' { 'naive-https-client.pid' }
        'dnstt' { 'dnstt-client.pid' }
        default { throw "Unsupported active protocol for injection: $protocol" }
    }
    $expectedLeaf = switch ($protocol) {
        'hysteria2' { 'hysteria-windows-amd64.exe' }
        'vless_reality' { 'xray.exe' }
        'naive_https' { 'naive.exe' }
        'dnstt' { 'dnstt-client-windows-amd64.exe' }
    }
    $pidPath = Join-Path $resolvedProgramDataRoot $pidFileName
    if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) {
        throw "Managed PID file is missing for $protocol."
    }
    $pidValue = 0
    if (-not [int]::TryParse((Get-Content -LiteralPath $pidPath -Raw).Trim(), [ref]$pidValue)) {
        throw "Managed PID file is invalid for $protocol."
    }
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$pidValue" -ErrorAction Stop
    if (
        -not $process.ExecutablePath -or
        -not [IO.Path]::GetFileName([string]$process.ExecutablePath).Equals(
            $expectedLeaf,
            [StringComparison]::OrdinalIgnoreCase
        ) -or
        -not [IO.Path]::GetFullPath([string]$process.ExecutablePath).StartsWith(
            "$resolvedInstallRoot\tools\",
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw "Managed process identity mismatch for $protocol."
    }
    Stop-Process -Id $pidValue -Force -ErrorAction Stop
    return 'engine_process'
}

function Register-RestoreFailsafe {
    $command = "& '$taskScriptPath' -Action Disconnect -ErrorAction SilentlyContinue; Start-Service -Name '$AmneziaServiceName' -ErrorAction SilentlyContinue"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
        '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' +
        ($command -replace '"', '\"') +
        '"'
    )
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(
        $FailsafeDelayMinutes
    )
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $failSafeTaskName -Action $action -Trigger $trigger `
        -Principal $principal -Force | Out-Null
}

function Test-InstalledPayload {
    $auditRoot = Join-Path ([IO.Path]::GetTempPath()) (
        'GreenVpnPhysicalPayload_' + [guid]::NewGuid().ToString('N')
    )
    $packageRoot = Join-Path $auditRoot 'package'
    try {
        New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null
        $extract = Start-Process -FilePath $resolvedInstaller -ArgumentList @(
            '/Q',
            "/T:$auditRoot",
            '/C'
        ) -PassThru
        if (-not $extract.WaitForExit(30000)) {
            Stop-Process -Id $extract.Id -Force -ErrorAction SilentlyContinue
            throw 'Exact installer payload extraction timed out.'
        }
        if ($extract.ExitCode -ne 0) {
            throw "Exact installer payload extraction returned $($extract.ExitCode)."
        }

        $payloadZip = Join-Path $auditRoot 'GreenVPN_payload.zip'
        if (-not (Test-Path -LiteralPath $payloadZip -PathType Leaf)) {
            throw 'Exact installer payload archive is missing.'
        }
        Expand-Archive -LiteralPath $payloadZip -DestinationPath $packageRoot -Force

        $stagedFiles = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse)
        if ($stagedFiles.Count -lt 1) {
            throw 'Exact installer payload is empty.'
        }
        foreach ($source in $stagedFiles) {
            $relative = $source.FullName.Substring($packageRoot.Length).TrimStart('\')
            $target = if ($relative.StartsWith('app\', [StringComparison]::OrdinalIgnoreCase)) {
                Join-Path $resolvedInstallRoot $relative.Substring(4)
            } elseif ($relative.StartsWith('tools\', [StringComparison]::OrdinalIgnoreCase)) {
                Join-Path (Join-Path $resolvedInstallRoot 'tools') $relative.Substring(6)
            } elseif ($relative.StartsWith('docs\', [StringComparison]::OrdinalIgnoreCase)) {
                Join-Path (Join-Path $resolvedInstallRoot 'docs') $relative.Substring(5)
            } else {
                throw 'Exact installer payload has an unexpected root.'
            }

            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                throw "Installed payload file is missing: $relative"
            }
            $expected = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
            $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            if ($actual -ne $expected) {
                throw "Installed payload hash mismatch: $relative"
            }
        }

        $installedAppPath = Join-Path $resolvedInstallRoot 'greenvpn.exe'
        $installedApp = Get-Item -LiteralPath $installedAppPath -ErrorAction Stop
        if ([string]$installedApp.VersionInfo.FileVersion -ne $ExpectedVersion) {
            throw (
                'Installed file version mismatch: ' +
                [string]$installedApp.VersionInfo.FileVersion
            )
        }

        $entry = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN' `
            -ErrorAction Stop
        if ([string]$entry.DisplayVersion -ne $expectedDisplayVersion) {
            throw "Installed display version mismatch: $($entry.DisplayVersion)"
        }
        return $stagedFiles.Count
    } finally {
        Remove-Item -LiteralPath $auditRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$reportDirectory = Split-Path -Parent $ReportPath
if ($reportDirectory) {
    New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
}

$amneziaWasRunning = $false
$baselineEgressFingerprint = ''
$failSafeRegistered = $false
$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    completedAt = $null
    success = $false
    failure = $null
    failureLocation = $null
    installer = [ordered]@{
        version = $ExpectedVersion
        displayVersion = $expectedDisplayVersion
        sha256 = $expectedInstallerHash
        signatureStatus = $null
        executedThisRun = -not [bool]$UseExistingExactInstall
        criticalPayloadFilesVerified = 0
    }
    baseline = [ordered]@{
        amneziaRunning = $false
        connectivityReady = $false
    }
    preflight = [ordered]@{
        fullTunnelMode = $false
        allGreenComponentsStopped = $false
        protectedProgramData = $null
    }
    firstRoute = $null
    standby = [ordered]@{
        required = [bool]$RequireStandbyProof
        userStateRoot = $resolvedUserStateRoot
        proofPath = $standbyProofPath
        cycleStarted = $false
        cycleCompleted = $false
        eligibleRoutes = @()
        outcomes = $null
        proofs = @()
        freshProofs = @()
        allEligibleAccounted = $false
        cleanup = $null
    }
    restartRestore = [ordered]@{
        tunnelSurvivedAppExit = $false
        monitorRestored = $false
    }
    injection = [ordered]@{
        kind = $null
        protocol = $null
        overlapObserved = $false
        maxActiveTransportGroups = 0
        recoverySeconds = $null
        prevalidatedStandbyUsed = $false
    }
    recoveredRoute = $null
    probes = @()
    cleanup = [ordered]@{
        allGreenComponentsStopped = $false
        standbyCancelAccepted = $false
        standbyArtifactsClean = $false
        standbyCleanupEvidence = $null
        amneziaRestored = $false
        originalEgressRestored = $false
        failsafeRemoved = $false
    }
}

try {
    Write-SmokeLog 'starting exact Windows installer and runtime failover smoke'
    if (-not (Test-Path -LiteralPath $resolvedInstaller -PathType Leaf)) {
        throw 'Expected installer is missing.'
    }
    $actualInstallerHash = (Get-FileHash -LiteralPath $resolvedInstaller -Algorithm SHA256).Hash
    if ($actualInstallerHash -ne $expectedInstallerHash) {
        throw 'Installer SHA-256 mismatch.'
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $resolvedInstaller
    $report.installer.signatureStatus = $signature.Status.ToString()

    $amneziaWasRunning = (Get-ServiceState -Name $AmneziaServiceName) -eq 'Running'
    if (-not $amneziaWasRunning) {
        throw "$AmneziaServiceName must be running before the smoke."
    }
    $report.baseline.amneziaRunning = $true
    $baselineEgressFingerprint = Get-EgressFingerprint
    $baselineProbe = Invoke-ExternalProbe -Url 'https://api.greenvpn.pro/healthz'
    if (-not $baselineEgressFingerprint -or -not $baselineProbe.ok) {
        throw 'Baseline connectivity could not be confirmed.'
    }
    $report.baseline.connectivityReady = $true

    if (-not $UseExistingExactInstall) {
        Stop-GreenApp
        Write-SmokeLog 'launching exact installer'
        $previousInstallerAutoClose = [Environment]::GetEnvironmentVariable(
            'GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS',
            [EnvironmentVariableTarget]::Process
        )
        $previousInstallerSkipAppLaunch = [Environment]::GetEnvironmentVariable(
            'GREENVPN_INSTALLER_SKIP_APP_LAUNCH',
            [EnvironmentVariableTarget]::Process
        )
        try {
            [Environment]::SetEnvironmentVariable(
                'GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS',
                '1',
                [EnvironmentVariableTarget]::Process
            )
            [Environment]::SetEnvironmentVariable(
                'GREENVPN_INSTALLER_SKIP_APP_LAUNCH',
                '1',
                [EnvironmentVariableTarget]::Process
            )
            $installer = Start-Process -FilePath $resolvedInstaller -PassThru -Wait
        } finally {
            [Environment]::SetEnvironmentVariable(
                'GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS',
                $previousInstallerAutoClose,
                [EnvironmentVariableTarget]::Process
            )
            [Environment]::SetEnvironmentVariable(
                'GREENVPN_INSTALLER_SKIP_APP_LAUNCH',
                $previousInstallerSkipAppLaunch,
                [EnvironmentVariableTarget]::Process
            )
        }
        if ($installer.ExitCode -ne 0) {
            throw "Installer returned exit code $($installer.ExitCode)."
        }
    } else {
        Write-SmokeLog 'using already installed exact payload after completed installer run'
    }
    Stop-GreenApp
    if ((Get-ServiceState -Name $GreenServiceName) -ne 'Running') {
        throw "$GreenServiceName is not running after installation."
    }
    $report.installer.criticalPayloadFilesVerified = Test-InstalledPayload
    $report.preflight.protectedProgramData = Get-ProtectedProgramDataEvidence
    if (
        -not $report.preflight.protectedProgramData.broadAccessRemoved -or
        -not $report.preflight.protectedProgramData.inheritanceProtected -or
        -not $report.preflight.protectedProgramData.ownerCanModifyState -or
        -not $report.preflight.protectedProgramData.ownerCanReadToken -or
        -not $report.preflight.protectedProgramData.systemHasFullControl
    ) {
        throw 'Installed Green VPN ProgramData ACL contract is not protected.'
    }

    $routingMode = if (Test-Path -LiteralPath $routingModePath -PathType Leaf) {
        (Get-Content -LiteralPath $routingModePath -Raw).Trim().ToLowerInvariant()
    } else {
        'full'
    }
    if ($routingMode -ne 'full') {
        throw 'Physical runtime failover smoke requires full-tunnel routing mode.'
    }
    $report.preflight.fullTunnelMode = $true

    if ($RequireStandbyProof) {
        if ([string]::IsNullOrWhiteSpace($UserStateRoot)) {
            throw 'Standby proof smoke requires an explicit isolated UserStateRoot.'
        }
        New-Item -ItemType Directory -Force -Path $resolvedUserStateRoot | Out-Null
        if (Test-Path -LiteralPath $standbyProofPath -PathType Leaf) {
            throw 'Standby proof smoke requires an empty isolated proof store.'
        }
    }

    if (-not (Wait-AllGreenComponentsStopped -TimeoutSeconds 5)) {
        [void](Invoke-GreenLocal -Method POST -Path '/disconnect')
    }
    if (-not (Wait-AllGreenComponentsStopped -TimeoutSeconds 45)) {
        throw 'Green VPN components were not fully stopped before touching the external VPN.'
    }
    $report.preflight.allGreenComponentsStopped = $true

    Register-RestoreFailsafe
    $failSafeRegistered = $true
    Write-SmokeLog 'registered network restore failsafe'

    Stop-Service -Name $AmneziaServiceName -Force -ErrorAction Stop
    if (-not (Wait-ServiceState -Name $AmneziaServiceName -State Stopped)) {
        throw "$AmneziaServiceName did not stop."
    }

    $pendingDirectory = Split-Path -Parent $pendingActionPath
    New-Item -ItemType Directory -Force -Path $pendingDirectory | Out-Null
    Set-Content -LiteralPath $pendingActionPath -Encoding ASCII -NoNewline -Value 'connect'
    $initialArmLogLine = Get-AuthLogLineCount
    $standbyCycleStartedAtUtc = (Get-Date).ToUniversalTime()
    $appProcess = Start-GreenApp

    $first = Wait-GreenRoute -TimeoutSeconds 150
    if ($null -eq $first) {
        throw 'Green VPN did not establish the first route.'
    }
    $firstProtocol = [string]$first.status.protocol
    if (-not $protocolRank.ContainsKey($firstProtocol)) {
        throw "Unknown first protocol: $firstProtocol"
    }
    $firstStatusProperties = @($first.status.PSObject.Properties.Name)
    foreach ($key in $componentStateKeys) {
        if ($key -notin $firstStatusProperties) {
            throw "System service status omitted component key: $key"
        }
    }
    $firstGroups = @(Get-ActiveTransportGroups -Status $first.status)
    if ($firstGroups.Count -ne 1) {
        throw "Expected exactly one active transport group, found $($firstGroups.Count)."
    }
    if (-not (
        Wait-LogMarker -Pattern 'windows runtime failover armed' `
            -AfterLine $initialArmLogLine -TimeoutSeconds 45
    )) {
        throw 'Windows runtime failover monitor was not armed.'
    }
    $firstEgressVerified = Test-ExpectedRouteEgress -RouteId $first.routeId
    if (-not $firstEgressVerified) {
        throw "Initial route egress did not match route $($first.routeId)."
    }
    $firstNetworkProtection = Get-NetworkProtectionEvidence -Protocol $firstProtocol
    if (-not $firstNetworkProtection.dnsResolution.ok) {
        throw 'DNS resolution failed through the initial Green VPN route.'
    }
    if ($firstNetworkProtection.directDnsLeak.leakDetected) {
        throw 'A DNS server outside the initial Green VPN route answered a direct probe.'
    }
    if (
        -not $firstNetworkProtection.routes.ipv4Protected -or
        -not $firstNetworkProtection.routes.ipv6Protected
    ) {
        throw 'Initial Green VPN route did not protect the expected IP route families.'
    }
    $report.firstRoute = [ordered]@{
        protocol = $firstProtocol
        routeId = $first.routeId
        activeTransportGroups = $firstGroups
        egressVerified = $firstEgressVerified
        networkProtection = $firstNetworkProtection
    }
    $initialProbes = @(
        Invoke-ExternalProbe -Url 'https://api.greenvpn.pro/healthz'
        Invoke-ExternalProbe -Url 'https://176-113-81-35.sslip.io/healthz'
        Invoke-ExternalProbe -Url 'https://www.youtube.com/generate_204'
    )
    if (@($initialProbes | Where-Object { -not $_.ok }).Count -gt 0) {
        throw 'Initial Green VPN route failed an external probe.'
    }

    $standbyEvidence = if ($RequireStandbyProof) {
        Wait-StandbyCycleEvidence `
            -AfterLine $initialArmLogLine `
            -StartedAtUtc $standbyCycleStartedAtUtc `
            -TimeoutSeconds $StandbyCycleTimeoutSeconds
    } else {
        Get-StandbyCycleEvidence `
            -AfterLine $initialArmLogLine `
            -StartedAtUtc $standbyCycleStartedAtUtc
    }
    $report.standby.cycleStarted = [bool]$standbyEvidence.cycleStarted
    $report.standby.cycleCompleted = [bool]$standbyEvidence.cycleCompleted
    $report.standby.eligibleRoutes = @($standbyEvidence.eligibleRoutes)
    $report.standby.outcomes = $standbyEvidence.outcomes
    $report.standby.proofs = @($standbyEvidence.proofs)
    $report.standby.freshProofs = @($standbyEvidence.freshProofs)
    $report.standby.allEligibleAccounted = [bool]$standbyEvidence.allEligibleAccounted
    $report.standby.cleanup = $standbyEvidence.cleanup
    if ($RequireStandbyProof) {
        if (-not $standbyEvidence.cycleStarted -or -not $standbyEvidence.cycleCompleted) {
            throw 'Background standby cycle did not complete while the active route stayed online.'
        }
        if (@($standbyEvidence.eligibleRoutes).Count -lt 1) {
            throw 'Background standby cycle exposed no alternate route candidates.'
        }
        if (-not $standbyEvidence.allEligibleAccounted) {
            throw "Background standby cycle left routes unaccounted: $(@($standbyEvidence.unaccountedRoutes) -join ', ')"
        }
        if (@($standbyEvidence.freshProofs).Count -lt 1) {
            throw 'Background standby cycle produced no fresh config-bound standby proof.'
        }
        if (-not [bool]$standbyEvidence.cleanup.cleanupOk) {
            throw 'Background standby probe did not fully clean temporary routes, services, ports, or files.'
        }
    }
    $prevalidatedStandbyKeys = @(
        $standbyEvidence.freshProofs | ForEach-Object {
            ([string]$_.key).ToLowerInvariant()
        }
    )

    Stop-GreenApp
    $statusAfterAppExit = Get-GreenStatus
    $report.restartRestore.tunnelSurvivedAppExit =
        [string]$statusAfterAppExit.tunnelState -eq 'running'
    if (-not $report.restartRestore.tunnelSurvivedAppExit) {
        throw 'Tunnel did not survive the deliberate app restart.'
    }
    $restartLogLine = Get-AuthLogLineCount
    $appProcess = Start-GreenApp
    if (-not (
        Wait-LogMarker -Pattern 'windows runtime failover restored source=' `
            -AfterLine $restartLogLine -TimeoutSeconds 45
    )) {
        throw 'Runtime failover monitor was not restored after app restart.'
    }
    $report.restartRestore.monitorRestored = $true

    $beforeInjection = Wait-GreenRoute -TimeoutSeconds 20
    if ($null -eq $beforeInjection) {
        throw 'Active route disappeared before failure injection.'
    }
    $injectedProtocol = [string]$beforeInjection.status.protocol
    if (-not $protocolRank.ContainsKey($injectedProtocol)) {
        throw "Unknown injected protocol: $injectedProtocol"
    }
    $failoverLogLine = Get-AuthLogLineCount
    $failoverWatch = [Diagnostics.Stopwatch]::StartNew()
    $report.injection.kind = Stop-ActiveTransportEngine -Status $beforeInjection.status
    $report.injection.protocol = $injectedProtocol
    Write-SmokeLog "injected active transport failure protocol=$injectedProtocol"

    $script:maxActiveGroups = 0
    $script:overlapObserved = $false
    $onSample = {
        param($status)
        $groups = @(Get-ActiveTransportGroups -Status $status)
        if ($groups.Count -gt $script:maxActiveGroups) {
            $script:maxActiveGroups = $groups.Count
        }
        if ($groups.Count -gt 1) {
            $script:overlapObserved = $true
        }
    }
    $recovered = Wait-GreenRoute -DifferentFromRouteId $beforeInjection.routeId `
        -TimeoutSeconds $FailoverTimeoutSeconds -OnSample $onSample
    $failoverWatch.Stop()
    $report.injection.recoverySeconds = [math]::Round($failoverWatch.Elapsed.TotalSeconds, 3)
    $report.injection.maxActiveTransportGroups = $script:maxActiveGroups
    $report.injection.overlapObserved = $script:overlapObserved
    if ($null -eq $recovered) {
        throw 'Automatic runtime failover was not observed.'
    }
    if ($script:overlapObserved) {
        throw 'More than one managed transport group was active during failover.'
    }
    $recoveredProtocol = [string]$recovered.status.protocol
    $recoveredStandbyKey = (
        ([string]$recovered.routeId).Trim().ToLowerInvariant() + '/' +
        $recoveredProtocol.Trim().ToLowerInvariant()
    )
    $report.injection.prevalidatedStandbyUsed =
        $recoveredStandbyKey -in $prevalidatedStandbyKeys
    if (
        $RequireStandbyProof -and
        -not $report.injection.prevalidatedStandbyUsed
    ) {
        throw "Runtime failover selected a route without a fresh standby proof: $recoveredStandbyKey"
    }
    if (
        $RequireStandbyProof -and
        [double]$report.injection.recoverySeconds -gt $MaxPrevalidatedFailoverSeconds
    ) {
        throw "Prevalidated failover exceeded $MaxPrevalidatedFailoverSeconds seconds."
    }
    if (
        -not $protocolRank.ContainsKey($recoveredProtocol) -or
        $protocolRank[$recoveredProtocol] -lt $protocolRank[$injectedProtocol]
    ) {
        throw "Recovered protocol violated cascade order: $injectedProtocol -> $recoveredProtocol"
    }
    $recoveredRoutePattern =
        'windows runtime failover armed server=' + [regex]::Escape([string]$recovered.routeId)
    if (-not (
        Wait-LogMarker -Pattern $recoveredRoutePattern `
            -AfterLine $failoverLogLine -TimeoutSeconds 45
    )) {
        throw 'Runtime failover monitor was not rearmed after recovery.'
    }
    $recoveredGroups = @(Get-ActiveTransportGroups -Status $recovered.status)
    if ($recoveredGroups.Count -ne 1) {
        throw "Recovered route has $($recoveredGroups.Count) active transport groups."
    }
    $recoveredEgressVerified = Test-ExpectedRouteEgress -RouteId $recovered.routeId
    if (-not $recoveredEgressVerified) {
        throw "Recovered route egress did not match route $($recovered.routeId)."
    }
    $recoveredNetworkProtection = Get-NetworkProtectionEvidence -Protocol $recoveredProtocol
    if (-not $recoveredNetworkProtection.dnsResolution.ok) {
        throw 'DNS resolution failed through the recovered Green VPN route.'
    }
    if ($recoveredNetworkProtection.directDnsLeak.leakDetected) {
        throw 'A DNS server outside the recovered Green VPN route answered a direct probe.'
    }
    if (
        -not $recoveredNetworkProtection.routes.ipv4Protected -or
        -not $recoveredNetworkProtection.routes.ipv6Protected
    ) {
        throw 'Recovered Green VPN route did not protect the expected IP route families.'
    }
    $report.recoveredRoute = [ordered]@{
        protocol = $recoveredProtocol
        routeId = $recovered.routeId
        routeChanged = $recovered.routeId -ne $beforeInjection.routeId
        activeTransportGroups = $recoveredGroups
        egressVerified = $recoveredEgressVerified
        prevalidatedStandby = [bool]$report.injection.prevalidatedStandbyUsed
        networkProtection = $recoveredNetworkProtection
    }
    $report.probes = @(
        Invoke-ExternalProbe -Url 'https://api.greenvpn.pro/healthz'
        Invoke-ExternalProbe -Url 'https://176-113-81-35.sslip.io/healthz'
        Invoke-ExternalProbe -Url 'https://www.youtube.com/generate_204'
    )
    if (@($report.probes | Where-Object { -not $_.ok }).Count -gt 0) {
        throw 'Recovered Green VPN route failed an external probe.'
    }

    $report.success = $true
    Write-SmokeLog 'runtime failover smoke passed before cleanup'
} catch {
    $caught = $_
    $invocation = $caught.InvocationInfo
    $report.failure = $caught.Exception.Message
    $report.failureLocation = [ordered]@{
        script = $(if ($null -ne $invocation) { [string]$invocation.ScriptName } else { '' })
        line = $(if ($null -ne $invocation) { [int]$invocation.ScriptLineNumber } else { 0 })
        command = $(if ($null -ne $invocation) { [string]$invocation.MyCommand.Name } else { '' })
    }
    Write-SmokeLog (
        "smoke failed type=$($caught.Exception.GetType().Name) " +
        "line=$($report.failureLocation.line) command=$($report.failureLocation.command)"
    )
} finally {
    Stop-GreenApp
    Remove-Item -LiteralPath $pendingActionPath -Force -ErrorAction SilentlyContinue

    try {
        $standbyCancel = Invoke-GreenLocal -Method POST -Path '/standby/cancel'
        $report.cleanup.standbyCancelAccepted = [bool]$standbyCancel.ok
    } catch {}

    try {
        if ((Get-ServiceState -Name $GreenServiceName) -eq 'Running') {
            [void](Invoke-GreenLocal -Method POST -Path '/disconnect')
        }
    } catch {
        try {
            if (Test-Path -LiteralPath $taskScriptPath -PathType Leaf) {
                & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                    -File $taskScriptPath -Action Disconnect 2>$null | Out-Null
            }
        } catch {}
    }

    try {
        $report.cleanup.allGreenComponentsStopped =
            Wait-AllGreenComponentsStopped -TimeoutSeconds 45
    } catch {}
    try {
        $standbyCleanupEvidence = Wait-StandbyCleanupEvidence -TimeoutSeconds 30
        $report.cleanup.standbyCleanupEvidence = $standbyCleanupEvidence
        $report.cleanup.standbyArtifactsClean =
            [bool]$standbyCleanupEvidence.cleanupOk
    } catch {}

    if ($amneziaWasRunning) {
        try {
            Start-Service -Name $AmneziaServiceName -ErrorAction Stop
            $report.cleanup.amneziaRestored = Wait-ServiceState -Name $AmneziaServiceName `
                -State Running -TimeoutSeconds 45
        } catch {}
    }
    Start-Sleep -Seconds 3

    try {
        $restoredFingerprint = Get-EgressFingerprint
        $restoreProbe = Invoke-ExternalProbe -Url 'https://api.greenvpn.pro/healthz'
        $report.cleanup.originalEgressRestored =
            $baselineEgressFingerprint -and
            $restoredFingerprint -eq $baselineEgressFingerprint -and
            $restoreProbe.ok
    } catch {}

    if ($failSafeRegistered) {
        try {
            Unregister-ScheduledTask -TaskName $failSafeTaskName -Confirm:$false -ErrorAction Stop
            $report.cleanup.failsafeRemoved = $true
        } catch {}
    }

    if (
        -not $report.cleanup.allGreenComponentsStopped -or
        -not $report.cleanup.standbyArtifactsClean -or
        -not $report.cleanup.amneziaRestored -or
        -not $report.cleanup.originalEgressRestored -or
        ($failSafeRegistered -and -not $report.cleanup.failsafeRemoved)
    ) {
        $report.success = $false
        if (-not $report.failure) {
            $report.failure = 'Cleanup or original network restoration was not fully confirmed.'
        }
    }

    $report.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-SmokeLog "finished success=$($report.success)"
}

if (-not $report.success) {
    throw "Windows runtime failover smoke failed. See $ReportPath and $LogPath"
}

$report | ConvertTo-Json -Depth 8
