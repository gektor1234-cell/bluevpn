$RoutingModePath = Join-Path $ProgramDataRoot 'routing_mode'
$RoutingAppsPath = Join-Path $ProgramDataRoot 'routing_apps.json'
$runtimeScope = if ($ProgramDataRoot -match '(?i)BlueVPNBeta$') { 'paid-beta' } else { 'stable' }
$PrivilegedRuntimeRegistryPath = "HKLM:\SOFTWARE\GreenVPN\Runtime\$runtimeScope"
$ProcessRouterRoot = Join-Path $PSScriptRoot 'process-router'
$ProcessRouterExe = Join-Path $ProcessRouterRoot 'ProxyBridge_CLI.exe'
$ProcessRouterRulesPath = Join-Path $ProgramDataRoot 'process-router.rules.json'
$ProcessRouterStdoutPath = Join-Path $ProgramDataRoot 'process-router.stdout.log'
$ProcessRouterStderrPath = Join-Path $ProgramDataRoot 'process-router.stderr.log'
$ApplicationProxyHost = '10.10.0.1'
$ApplicationProxyPort = 1080
$ProcessRouterHashes = @{
    'ProxyBridge_CLI.exe' = '71AE1A872B49F795BB9E341FF910C5B303AFCE0BAB1E54CFC5436032EB7E08C9'
    'ProxyBridgeCore.dll' = '736B75A06AD748254D711446E0D4239189A991C7AABCE739EF7DD7B9CA7EBF7E'
    'WinDivert.dll' = 'C1E060EE19444A259B2162F8AF0F3FE8C4428A1C6F694DCE20DE194AC8D7D9A2'
    'WinDivert64.sys' = '8DA085332782708D8767BCACE5327A6EC7283C17CFB85E40B03CD2323A90DDC2'
}

function Write-GreenPrivilegedRuntimeValue {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('ActiveRoutingMode', 'ProcessRouterPid', 'ProcessRouterRequired', 'RuntimeStateGeneration')][string]$Name,
        [Parameter(Mandatory=$true)][object]$Value,
        [ValidateSet('String', 'DWord')][string]$PropertyType = 'String'
    )

    New-Item -Path $PrivilegedRuntimeRegistryPath -Force | Out-Null
    Remove-ItemProperty `
        -LiteralPath $PrivilegedRuntimeRegistryPath `
        -Name $Name `
        -Force `
        -ErrorAction SilentlyContinue
    New-ItemProperty `
        -Path $PrivilegedRuntimeRegistryPath `
        -Name $Name `
        -PropertyType $PropertyType `
        -Value $Value `
        -Force |
        Out-Null
}

function Read-GreenPrivilegedRuntimeValue {
    param([Parameter(Mandatory=$true)][string]$Name)
    try {
        return (Get-ItemProperty `
            -LiteralPath $PrivilegedRuntimeRegistryPath `
            -Name $Name `
            -ErrorAction Stop).$Name
    } catch {
        return $null
    }
}

function Remove-GreenPrivilegedRuntimeValue {
    param([Parameter(Mandatory=$true)][string]$Name)
    Remove-ItemProperty `
        -LiteralPath $PrivilegedRuntimeRegistryPath `
        -Name $Name `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -ne (Read-GreenPrivilegedRuntimeValue -Name $Name)) {
        throw "Privileged runtime value was not removed: $Name"
    }
}

function Start-GreenRuntimeStateTransition {
    $generationValue = Read-GreenPrivilegedRuntimeValue `
        -Name 'RuntimeStateGeneration'
    $generation = [uint32]0
    $generationKnown = $null -ne $generationValue -and
        [uint32]::TryParse([string]$generationValue, [ref]$generation)
    if (-not $generationKnown -or $generation -ge [uint32]::MaxValue - 2) {
        $transitionGeneration = [uint32]1
    } elseif (($generation % 2) -eq 0) {
        $transitionGeneration = [uint32]($generation + 1)
    } else {
        $transitionGeneration = [uint32]($generation + 2)
    }
    Write-GreenPrivilegedRuntimeValue `
        -Name 'RuntimeStateGeneration' `
        -Value $transitionGeneration `
        -PropertyType DWord
    Remove-GreenPrivilegedRuntimeValue -Name 'ActiveRoutingMode'
    $committed = [uint32]0
    if (-not [uint32]::TryParse(
            [string](Read-GreenPrivilegedRuntimeValue `
                -Name 'RuntimeStateGeneration'),
            [ref]$committed
        ) -or $committed -ne $transitionGeneration -or
            ($committed % 2) -ne 1) {
        throw 'Privileged runtime transition generation was not committed.'
    }
    return $transitionGeneration
}

function Complete-GreenRuntimeStateTransition {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateRange(1, 4294967294)][uint32]$TransitionGeneration
    )

    if (($TransitionGeneration % 2) -ne 1) {
        throw 'Runtime transition generation must be odd.'
    }
    $current = [uint32]0
    if (-not [uint32]::TryParse(
            [string](Read-GreenPrivilegedRuntimeValue `
                -Name 'RuntimeStateGeneration'),
            [ref]$current
        ) -or $current -ne $TransitionGeneration) {
        throw 'Privileged runtime transition generation changed unexpectedly.'
    }
    $stableGeneration = [uint32]($TransitionGeneration + 1)
    Write-GreenPrivilegedRuntimeValue `
        -Name 'RuntimeStateGeneration' `
        -Value $stableGeneration `
        -PropertyType DWord
    $committed = [uint32]0
    if (-not [uint32]::TryParse(
            [string](Read-GreenPrivilegedRuntimeValue `
                -Name 'RuntimeStateGeneration'),
            [ref]$committed
        ) -or $committed -ne $stableGeneration -or
            ($committed % 2) -ne 0) {
        throw 'Privileged stable runtime generation was not committed.'
    }
}

function Test-GreenRuntimeStateStable {
    $generation = [uint32]0
    return [uint32]::TryParse(
        [string](Read-GreenPrivilegedRuntimeValue `
            -Name 'RuntimeStateGeneration'),
        [ref]$generation
    ) -and ($generation % 2) -eq 0
}

function Get-GreenRoutingMode {
    if (-not (Test-Path -LiteralPath $RoutingModePath -PathType Leaf)) {
        return 'full'
    }
    $mode = ([IO.File]::ReadAllText($RoutingModePath)).Trim().ToLowerInvariant()
    if ($mode -eq 'applications') { return $mode }
    return 'full'
}

function Test-GreenTcpEndpoint {
    param(
        [Parameter(Mandatory=$true)][string]$HostName,
        [Parameter(Mandatory=$true)][int]$Port,
        [int]$TimeoutMs = 1500
    )

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $pending = $client.ConnectAsync($HostName, $Port)
        if (-not $pending.Wait($TimeoutMs)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Test-GreenProcessRouterRunning {
    $pidText = [string](Read-GreenPrivilegedRuntimeValue -Name 'ProcessRouterPid')
    $routerPid = 0
    if (-not [int]::TryParse($pidText, [ref]$routerPid) -or $routerPid -le 0) {
        return $false
    }
    $process = Get-Process -Id $routerPid -ErrorAction SilentlyContinue
    if ($null -eq $process -or $process.HasExited) { return $false }
    try {
        return [IO.Path]::GetFullPath($process.Path).Equals(
            [IO.Path]::GetFullPath($ProcessRouterExe),
            [StringComparison]::OrdinalIgnoreCase
        )
    } catch {
        return $false
    }
}

function Get-GreenProcessRouterProcesses {
    $expectedPath = [IO.Path]::GetFullPath($ProcessRouterExe)
    return @(
        Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($ProcessRouterExe)) `
            -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    [IO.Path]::GetFullPath([string]$_.Path).Equals(
                        $expectedPath,
                        [StringComparison]::OrdinalIgnoreCase
                    )
                } catch {
                    $false
                }
            }
    )
}

function Stop-GreenProcessRouter {
    Write-GreenPrivilegedRuntimeValue `
        -Name 'ProcessRouterRequired' `
        -Value 0 `
        -PropertyType DWord
    foreach ($process in @(Get-GreenProcessRouterProcesses)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    for ($i = 0; $i -lt 20; $i++) {
        if (@(Get-GreenProcessRouterProcesses).Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    }
    if (@(Get-GreenProcessRouterProcesses).Count -ne 0) {
        throw 'Process router did not stop completely.'
    }
    Remove-GreenPrivilegedRuntimeValue -Name 'ProcessRouterPid'
}

function Confirm-GreenProcessRouterRuntimeContract {
    param([Parameter(Mandatory=$true)][bool]$Required)

    try {
        $requiredValueKind = (
            Get-Item -LiteralPath $PrivilegedRuntimeRegistryPath `
                -ErrorAction Stop
        ).GetValueKind('ProcessRouterRequired')
    } catch {
        throw 'Privileged process router requirement type is unavailable.'
    }
    if ($requiredValueKind -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
        throw 'Privileged process router requirement is not a REG_DWORD.'
    }
    $requiredValue = Read-GreenPrivilegedRuntimeValue -Name 'ProcessRouterRequired'
    $expectedRequiredValue = if ($Required) { 1 } else { 0 }
    if ($null -eq $requiredValue -or
            [int]$requiredValue -ne $expectedRequiredValue) {
        throw 'Privileged process router requirement was not committed.'
    }

    $processes = @(Get-GreenProcessRouterProcesses)
    $pidValue = Read-GreenPrivilegedRuntimeValue -Name 'ProcessRouterPid'
    $routerPid = 0
    $pidKnown = $null -ne $pidValue -and
        [int]::TryParse([string]$pidValue, [ref]$routerPid) -and
        $routerPid -gt 0
    if ($Required) {
        try {
            $pidValueKind = (
                Get-Item -LiteralPath $PrivilegedRuntimeRegistryPath `
                    -ErrorAction Stop
            ).GetValueKind('ProcessRouterPid')
        } catch {
            throw 'Required process router PID type is unavailable.'
        }
        if ($pidValueKind -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
            throw 'Required process router PID is not a REG_DWORD.'
        }
        if ($processes.Count -ne 1 -or -not $pidKnown -or
                [int]$processes[0].Id -ne $routerPid) {
            throw 'Required process router identity was not committed.'
        }
        return
    }

    if ($processes.Count -ne 0) {
        throw 'A stale process router is still running.'
    }
    if ($null -ne $pidValue) {
        Remove-GreenPrivilegedRuntimeValue -Name 'ProcessRouterPid'
        if ($null -ne (Read-GreenPrivilegedRuntimeValue -Name 'ProcessRouterPid')) {
            throw 'A stale process router PID is still published.'
        }
    }
}

function Assert-GreenProcessRouterPayload {
    foreach ($entry in $ProcessRouterHashes.GetEnumerator()) {
        $path = Join-Path $ProcessRouterRoot $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Process router payload is missing: $($entry.Key)"
        }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($actual -ne $entry.Value) {
            throw "Process router payload hash mismatch: $($entry.Key)"
        }
    }
}

function Test-GreenPublicIpv4Cidr {
    param([string]$Value)

    $parts = $Value.Trim().Split('/')
    if ($parts.Count -ne 2) { return $false }
    $prefix = 0
    if (-not [int]::TryParse($parts[1], [ref]$prefix) -or $prefix -lt 8 -or $prefix -gt 32) {
        return $false
    }
    $address = $null
    if (-not [Net.IPAddress]::TryParse($parts[0], [ref]$address)) { return $false }
    if ($address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    $bytes = $address.GetAddressBytes()
    $a = [int]$bytes[0]
    $b = [int]$bytes[1]
    $c = [int]$bytes[2]
    if ($a -eq 0 -or $a -eq 10 -or $a -eq 127 -or $a -ge 224) { return $false }
    if ($a -eq 100 -and $b -ge 64 -and $b -le 127) { return $false }
    if ($a -eq 169 -and $b -eq 254) { return $false }
    if ($a -eq 172 -and $b -ge 16 -and $b -le 31) { return $false }
    if ($a -eq 192 -and $b -eq 168) { return $false }
    if ($a -eq 192 -and $b -eq 0 -and $c -in @(0, 2)) { return $false }
    if ($a -eq 198 -and $b -in @(18, 19)) { return $false }
    if ($a -eq 198 -and $b -eq 51 -and $c -eq 100) { return $false }
    if ($a -eq 203 -and $b -eq 0 -and $c -eq 113) { return $false }
    return $true
}

function Get-GreenRoutingPolicy {
    if (-not (Test-Path -LiteralPath $RoutingAppsPath -PathType Leaf)) {
        throw 'Windows selective routing policy is missing.'
    }
    $policy = [IO.File]::ReadAllText($RoutingAppsPath) | ConvertFrom-Json
    if ($null -eq $policy -or [int]$policy.schemaVersion -notin @(1, 2)) {
        throw 'Unsupported Windows selective routing policy.'
    }
    if (
        [string]$policy.proxy.host -ne $ApplicationProxyHost -or
        [int]$policy.proxy.port -ne $ApplicationProxyPort
    ) {
        throw 'Windows selective routing proxy policy is invalid.'
    }
    return $policy
}

function Get-GreenApplicationPaths {
    param([Parameter(Mandatory=$true)]$Policy)

    $paths = [Collections.Generic.List[string]]::new()
    foreach ($raw in @($Policy.applications)) {
        $candidate = ([string]$raw).Trim()
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (
            $candidate.Length -gt 1024 -or
            -not [IO.Path]::IsPathRooted($candidate) -or
            -not $candidate.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase) -or
            $candidate.Contains(',') -or
            $candidate.Contains(';') -or
            -not (Test-Path -LiteralPath $candidate -PathType Leaf)
        ) {
            throw 'Windows selective routing policy contains an invalid executable path.'
        }
        $fullPath = [IO.Path]::GetFullPath($candidate)
        if (-not $paths.Contains($fullPath)) { $paths.Add($fullPath) }
    }
    if ($paths.Count -gt 64) {
        throw 'Windows selective routing policy contains too many applications.'
    }
    return @($paths)
}

function Get-GreenDestinationCidrs {
    param([Parameter(Mandatory=$true)]$Policy)

    $cidrs = [Collections.Generic.List[string]]::new()
    if ($Policy.PSObject.Properties.Name -contains 'destinationCidrs') {
        foreach ($raw in @($Policy.destinationCidrs)) {
            $candidate = ([string]$raw).Trim()
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if (-not (Test-GreenPublicIpv4Cidr -Value $candidate)) {
                throw 'Windows selective routing policy contains an invalid destination.'
            }
            if (-not $cidrs.Contains($candidate)) { $cidrs.Add($candidate) }
        }
    }
    if ($cidrs.Count -gt 512) {
        throw 'Windows selective routing policy contains too many destinations.'
    }
    return @($cidrs)
}

function Start-GreenProcessRouter {
    param([Parameter(Mandatory=$true)][string[]]$ApplicationPaths)

    Stop-GreenProcessRouter
    Assert-GreenProcessRouterPayload
    if ($ApplicationPaths.Count -lt 1 -or $ApplicationPaths.Count -gt 64) {
        throw 'Windows process router requires between 1 and 64 applications.'
    }

    $rules = [Collections.Generic.List[object]]::new()
    foreach ($path in $ApplicationPaths) {
        $rules.Add([ordered]@{
            processNames = $path
            targetHosts = '*'
            targetPorts = '*'
            protocol = 'BOTH'
            action = 'PROXY'
            enabled = $true
        })
    }
    $rules.Add([ordered]@{
        processNames = 'svchost.exe'
        targetHosts = '*'
        targetPorts = '53'
        protocol = 'BOTH'
        action = 'PROXY'
        enabled = $true
    })
    $rules | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ProcessRouterRulesPath -Encoding UTF8

    $arguments = @(
        '--proxy', "socks5://${ApplicationProxyHost}:$ApplicationProxyPort",
        '--rule-file', $ProcessRouterRulesPath
    )
    $process = Start-Process -FilePath $ProcessRouterExe -ArgumentList $arguments `
        -WorkingDirectory $ProcessRouterRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $ProcessRouterStdoutPath `
        -RedirectStandardError $ProcessRouterStderrPath
    Start-Sleep -Milliseconds 1500
    if ($process.HasExited) {
        throw "Process router exited during startup with code $($process.ExitCode)."
    }
    Write-GreenPrivilegedRuntimeValue `
        -Name 'ProcessRouterPid' `
        -Value $process.Id `
        -PropertyType DWord
    if (-not (Test-GreenProcessRouterRunning)) {
        throw 'Process router startup could not be verified.'
    }
    Write-GreenPrivilegedRuntimeValue `
        -Name 'ProcessRouterRequired' `
        -Value 1 `
        -PropertyType DWord
    Write-GreenLog "process router started pid=$($process.Id) apps=$($ApplicationPaths.Count)"
}

function Ensure-GreenApplicationTunnelRoutes {
    param([Parameter(Mandatory=$true)]$Policy)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return }
    $applicationPaths = @(Get-GreenApplicationPaths -Policy $Policy)
    $destinationCidrs = @(Get-GreenDestinationCidrs -Policy $Policy)
    $allowedIps = [Collections.Generic.List[string]]::new()
    if ($applicationPaths.Count -gt 0) {
        $allowedIps.Add("${ApplicationProxyHost}/32")
    }
    foreach ($cidr in $destinationCidrs) {
        if (-not $allowedIps.Contains($cidr)) { $allowedIps.Add($cidr) }
    }
    if ($allowedIps.Count -lt 1) {
        throw 'Windows selective routing policy is empty.'
    }

    $configText = [IO.File]::ReadAllText($ConfigPath)
    if (-not [regex]::IsMatch($configText, '(?im)^\s*AllowedIPs\s*=')) {
        throw 'Managed tunnel config has no AllowedIPs field.'
    }
    $updated = [regex]::Replace(
        $configText,
        '(?im)^\s*AllowedIPs\s*=.*$',
        ('AllowedIPs = ' + ($allowedIps -join ', ')),
        1
    )
    if ([regex]::IsMatch($updated, '(?im)^\s*AllowedIPs\s*=.*(?:0\.0\.0\.0/0|0\.0\.0\.0/1|128\.0\.0\.0/1|::/0)')) {
        throw 'Application-only config unexpectedly contains a default route.'
    }
    [IO.File]::WriteAllText(
        $ConfigPath,
        $updated,
        [Text.UTF8Encoding]::new($false)
    )
    Ensure-GreenProgramDataAcl
    Write-GreenLog "validated selective tunnel routes apps=$($applicationPaths.Count) destinations=$($destinationCidrs.Count)"
}
