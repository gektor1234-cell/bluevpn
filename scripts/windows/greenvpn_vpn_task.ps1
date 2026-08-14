param(
    [ValidateSet('Connect', 'Disconnect', 'Guard')]
    [string]$Action = 'Guard'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TunnelName = 'BlueVPNDev1'
$ServiceName = 'WireGuardTunnel$BlueVPNDev1'
$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPN'
$runtimeScope = if ($ProgramDataRoot -match '(?i)BlueVPNBeta$') { 'paid-beta' } else { 'stable' }
$PrivilegedRuntimeRegistryPath = "HKLM:\SOFTWARE\GreenVPN\Runtime\$runtimeScope"
$PrivilegedRuntimeRegistrySubKey = "SOFTWARE\GreenVPN\Runtime\$runtimeScope"
$RuntimeMutationMutexName = 'Global\GreenVPN.RuntimeMutation'
$ConfigPath = Join-Path $ProgramDataRoot 'BlueVPNDev1.conf'
$LogPath = Join-Path $ProgramDataRoot 'backend.log'
$RoutingModePath = Join-Path $ProgramDataRoot 'routing_mode'
$RoutingAppsPath = Join-Path $ProgramDataRoot 'routing_apps.json'
$ProcessRouterRoot = Join-Path $PSScriptRoot 'process-router'
$ProcessRouterExe = Join-Path $ProcessRouterRoot 'ProxyBridge_CLI.exe'
$ProcessRouterProfilePath = Join-Path $ProgramDataRoot 'process-router.pbprofile'
$ProcessRouterStdoutPath = Join-Path $ProgramDataRoot 'process-router.stdout.log'
$ProcessRouterStderrPath = Join-Path $ProgramDataRoot 'process-router.stderr.log'
$CompetingVpnStatePath = Join-Path $ProgramDataRoot 'state\competing-vpn-services.json'
$ApplicationProxyHost = '10.10.0.1'
$ApplicationProxyPort = 1080
$ProcessRouterHashes = @{
    'ProxyBridge_CLI.exe' = '6C215C7975E3CBEE086DE0EE2F3226FAE84F35A7B0A2FFD432FC346EF56A0569'
    'ProxyBridgeCore.dll' = 'FB9543559619969DAA761D16A22441BF10EB497D22EE83BE11847F727E95151D'
    'WinDivert.dll' = 'C1E060EE19444A259B2162F8AF0F3FE8C4428A1C6F694DCE20DE194AC8D7D9A2'
    'WinDivert64.sys' = '8DA085332782708D8767BCACE5327A6EC7283C17CFB85E40B03CD2323A90DDC2'
}
$ActiveRuntimeTransitionGeneration = $null

function Write-GreenLog {
    param([string]$Message)
    try {
        New-Item -ItemType Directory -Force -Path $ProgramDataRoot | Out-Null
        $ts = (Get-Date).ToString('o')
        Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "[$ts] task($Action) $Message"
    } catch {
    }
}

function Invoke-External {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )

    $stdout = Join-Path $env:TEMP ("greenvpn_task_stdout_" + [guid]::NewGuid().ToString('N') + '.txt')
    $stderr = Join-Path $env:TEMP ("greenvpn_task_stderr_" + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $out = ''
        if (Test-Path -LiteralPath $stdout) { $out += (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) }
        if (Test-Path -LiteralPath $stderr) { $out += "`n" + (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) }
        $flat = ($out -replace "`r", ' ' -replace "`n", ' | ').Trim()
        Write-GreenLog "$FilePath $($Arguments -join ' ') exit=$($p.ExitCode) $flat"
        if ($AllowedExitCodes -notcontains $p.ExitCode) {
            throw "$FilePath exited with $($p.ExitCode)"
        }
        return $p.ExitCode
    } finally {
        Remove-Item -LiteralPath $stdout -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Open-GreenPrivilegedRuntimeRegistryKey {
    param([switch]$Writable)

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    try {
        if ($Writable) {
            return $baseKey.CreateSubKey(
                $PrivilegedRuntimeRegistrySubKey,
                [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree
            )
        }
        return $baseKey.OpenSubKey(
            $PrivilegedRuntimeRegistrySubKey,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadSubTree
        )
    } finally {
        $baseKey.Dispose()
    }
}

function Write-GreenPrivilegedRuntimeValue {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('ActiveRoutingMode', 'ProcessRouterPid', 'ProcessRouterRequired', 'RuntimeStateGeneration')][string]$Name,
        [Parameter(Mandatory=$true)][object]$Value,
        [ValidateSet('String', 'DWord')][string]$PropertyType = 'String'
    )

    $registryKey = $null
    try {
        $registryKey = Open-GreenPrivilegedRuntimeRegistryKey -Writable
        if ($null -eq $registryKey) {
            throw 'Privileged runtime registry key could not be opened for writing.'
        }
        $valueKind = if ($PropertyType -eq 'DWord') {
            [Microsoft.Win32.RegistryValueKind]::DWord
        } else {
            [Microsoft.Win32.RegistryValueKind]::String
        }
        $typedValue = if ($PropertyType -eq 'DWord') {
            [BitConverter]::ToInt32(
                [BitConverter]::GetBytes([uint32]$Value),
                0
            )
        } else {
            [string]$Value
        }
        $registryKey.SetValue($Name, $typedValue, $valueKind)
        if ($registryKey.GetValueKind($Name) -ne $valueKind) {
            throw "Privileged runtime value type readback failed: $Name"
        }
    } finally {
        if ($null -ne $registryKey) { $registryKey.Dispose() }
    }
}

function Read-GreenPrivilegedRuntimeValue {
    param([Parameter(Mandatory=$true)][string]$Name)
    $registryKey = $null
    try {
        $registryKey = Open-GreenPrivilegedRuntimeRegistryKey
        if ($null -eq $registryKey) { return $null }
        $value = $registryKey.GetValue(
            $Name,
            $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        )
        if ($null -ne $value -and
                $registryKey.GetValueKind($Name) -eq
                    [Microsoft.Win32.RegistryValueKind]::DWord) {
            return [BitConverter]::ToUInt32(
                [BitConverter]::GetBytes([int]$value),
                0
            )
        }
        return $value
    } finally {
        if ($null -ne $registryKey) { $registryKey.Dispose() }
    }
}

function Get-GreenPrivilegedRuntimeValueKind {
    param([Parameter(Mandatory=$true)][string]$Name)

    $lastError = $null
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $registryKey = $null
        try {
            $registryKey = Open-GreenPrivilegedRuntimeRegistryKey
            if ($null -eq $registryKey) {
                throw 'Privileged runtime registry key is unavailable.'
            }
            return $registryKey.GetValueKind($Name)
        } catch {
            $lastError = $_.Exception.Message
        } finally {
            if ($null -ne $registryKey) { $registryKey.Dispose() }
        }
        if ($attempt -lt 2) { Start-Sleep -Milliseconds 25 }
    }
    throw "Privileged runtime value type is unavailable: $Name ($lastError)"
}

function Remove-GreenPrivilegedRuntimeValue {
    param([Parameter(Mandatory=$true)][string]$Name)
    $registryKey = $null
    try {
        $registryKey = Open-GreenPrivilegedRuntimeRegistryKey -Writable
        if ($null -ne $registryKey) {
            $registryKey.DeleteValue($Name, $false)
        }
    } finally {
        if ($null -ne $registryKey) { $registryKey.Dispose() }
    }
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
        throw 'A privileged runtime transition is already active.'
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

function Get-GreenRuntimeTransitionGenerationForCleanup {
    $activeVariable = Get-Variable `
        -Name 'ActiveRuntimeTransitionGeneration' `
        -Scope Script `
        -ErrorAction SilentlyContinue
    if ($null -ne $activeVariable -and $null -ne $activeVariable.Value) {
        $activeGeneration = [uint32]$activeVariable.Value
        $currentGeneration = [uint32]0
        if (-not [uint32]::TryParse(
                [string](Read-GreenPrivilegedRuntimeValue `
                    -Name 'RuntimeStateGeneration'),
                [ref]$currentGeneration
            ) -or $currentGeneration -ne $activeGeneration -or
                ($activeGeneration % 2) -ne 1) {
            throw 'Active runtime transition ownership was lost before cleanup.'
        }
        Remove-GreenPrivilegedRuntimeValue -Name 'ActiveRoutingMode'
        return $activeGeneration
    }

    $currentGeneration = [uint32]0
    if ([uint32]::TryParse(
            [string](Read-GreenPrivilegedRuntimeValue `
                -Name 'RuntimeStateGeneration'),
            [ref]$currentGeneration
        ) -and ($currentGeneration % 2) -eq 1) {
        Remove-GreenPrivilegedRuntimeValue -Name 'ActiveRoutingMode'
        $script:ActiveRuntimeTransitionGeneration = $currentGeneration
        return $currentGeneration
    }

    $transitionGeneration = [uint32](Start-GreenRuntimeStateTransition)
    $script:ActiveRuntimeTransitionGeneration = $transitionGeneration
    return $transitionGeneration
}

function Enter-GreenRuntimeMutationLock {
    $mutexSecurity = [Security.AccessControl.MutexSecurity]::new()
    foreach ($sidValue in @('S-1-5-18', 'S-1-5-32-544')) {
        $mutexSecurity.AddAccessRule(
            [Security.AccessControl.MutexAccessRule]::new(
                [Security.Principal.SecurityIdentifier]::new($sidValue),
                [Security.AccessControl.MutexRights]::FullControl,
                [Security.AccessControl.AccessControlType]::Allow
            )
        )
    }
    $createdNew = $false
    $mutex = [Threading.Mutex]::new(
        $false,
        $RuntimeMutationMutexName,
        [ref]$createdNew,
        $mutexSecurity
    )
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds(15))
        } catch [Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            throw 'Another privileged Green VPN runtime mutation is still active.'
        }
        return $mutex
    } catch {
        $mutex.Dispose()
        throw
    }
}

function Exit-GreenRuntimeMutationLock {
    param([Threading.Mutex]$Mutex)
    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
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

function Resolve-WireGuardExe {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe'),
        'C:\Program Files\WireGuard\wireguard.exe',
        'C:\Program Files (x86)\WireGuard\wireguard.exe'
    )

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    return ''
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

    $requiredValueKind = Get-GreenPrivilegedRuntimeValueKind `
        -Name 'ProcessRouterRequired'
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
        $pidValueKind = Get-GreenPrivilegedRuntimeValueKind `
            -Name 'ProcessRouterPid'
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
            ProcessName = $path
            TargetHosts = '*'
            TargetPorts = '*'
            Protocol = 'BOTH'
            Action = 'PROXY'
            IsEnabled = $true
            ProxyConfigId = 1
        })
    }
    $profile = [ordered]@{
        Version = '1.0'
        LocalhostViaProxy = $false
        IsTrafficLoggingEnabled = $false
        ProxyConfigs = @([ordered]@{
            Id = 1
            Type = 'socks5'
            Host = $ApplicationProxyHost
            Port = [string]$ApplicationProxyPort
            Username = ''
            Password = ''
        })
        ProxyRules = @($rules)
    }
    $profileJson = $profile | ConvertTo-Json -Depth 8
    $profileTempPath = $ProcessRouterProfilePath + '.tmp'
    try {
        [IO.File]::WriteAllText(
            $profileTempPath,
            $profileJson,
            [Text.UTF8Encoding]::new($false)
        )
        Move-Item -LiteralPath $profileTempPath `
            -Destination $ProcessRouterProfilePath -Force
    }
    finally {
        Remove-Item -LiteralPath $profileTempPath -Force `
            -ErrorAction SilentlyContinue
    }

    $arguments = @(
        '--profile', $ProcessRouterProfilePath,
        '--verbose', '1'
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

function Ensure-GreenProgramDataAcl {
    New-Item -ItemType Directory -Force -Path $ProgramDataRoot | Out-Null
    try {
        Invoke-External -FilePath 'attrib.exe' -Arguments @('-H', '-S', '-R', $ProgramDataRoot) -AllowedExitCodes @(0, 1) | Out-Null
    } catch {
        Write-GreenLog "attrib dir warning: $($_.Exception.Message)"
    }

    try {
        Invoke-External -FilePath 'icacls.exe' -Arguments @(
            $ProgramDataRoot,
            '/inheritance:e',
            '/grant',
            '*S-1-5-11:(OI)(CI)M',
            '*S-1-5-18:(OI)(CI)F',
            '*S-1-5-32-544:(OI)(CI)F'
        ) -AllowedExitCodes @(0) | Out-Null
    } catch {
        Write-GreenLog "icacls dir warning: $($_.Exception.Message)"
    }

    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            Invoke-External -FilePath 'attrib.exe' -Arguments @('-H', '-S', '-R', $ConfigPath) -AllowedExitCodes @(0, 1) | Out-Null
            Invoke-External -FilePath 'icacls.exe' -Arguments @(
                $ConfigPath,
                '/inheritance:e',
                '/grant',
                '*S-1-5-11:M',
                '*S-1-5-18:F',
                '*S-1-5-32-544:F'
            ) -AllowedExitCodes @(0) | Out-Null
        } catch {
            Write-GreenLog "config acl warning: $($_.Exception.Message)"
        }
    }
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

function Ensure-NativeFullTunnelKillSwitch {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return }

    $configText = [IO.File]::ReadAllText($ConfigPath)
    $match = [regex]::Match($configText, '(?im)^\s*AllowedIPs\s*=\s*(.+?)\s*$')
    if (-not $match.Success) { return }

    $allowedIps = @(
        $match.Groups[1].Value.Split(',') |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $hasSplitIpv4 = $allowedIps -contains '0.0.0.0/1' -and
        $allowedIps -contains '128.0.0.0/1'
    $hasNativeDefault = $allowedIps -contains '0.0.0.0/0' -or
        $allowedIps -contains '::/0'
    if (-not $hasSplitIpv4 -or $hasNativeDefault) { return }

    $preserved = @(
        $allowedIps | Where-Object {
            $_ -notin @('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')
        }
    )
    $normalized = @($preserved + @('0.0.0.0/0', '::/0') | Select-Object -Unique)
    $updated = [regex]::Replace(
        $configText,
        '(?im)^\s*AllowedIPs\s*=.*$',
        ('AllowedIPs = ' + ($normalized -join ', ')),
        1
    )
    if ($updated -eq $configText) { return }

    $tempPath = $ConfigPath + '.killswitch.tmp'
    try {
        [IO.File]::WriteAllText($tempPath, $updated, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tempPath -Destination $ConfigPath -Force
        Ensure-GreenProgramDataAcl
        Write-GreenLog 'normalized Windows full-tunnel routes for native kill switch'
    } finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
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

function Get-OwnService {
    try {
        return Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    } catch {
        return $null
    }
}

function Get-CompetingVpnServices {
    try {
        return @(
            Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.State -ne 'Stopped' -and
                    $_.Name -ne $ServiceName -and
                    (
                        $_.Name -like 'WireGuardTunnel$*' -or
                        $_.Name -like 'AmneziaWGTunnel$*' -or
                        $_.Name -eq 'CloudflareWARP'
                    )
                }
        )
    } catch {
        Write-GreenLog "service competition check warning: $($_.Exception.Message)"
        return @()
    }
}

function Test-AllowedCompetingVpnServiceName {
    param([Parameter(Mandatory=$true)][string]$Name)

    return (
        $Name -ne $ServiceName -and
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

    $stateDirectory = Split-Path -Parent $CompetingVpnStatePath
    New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
    $state = [ordered]@{
        schema = 1
        createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        services = [object[]]$serviceNames
    }
    [IO.File]::WriteAllText(
        $CompetingVpnStatePath,
        ($state | ConvertTo-Json -Depth 4),
        [Text.UTF8Encoding]::new($false)
    )
    & attrib.exe +H $CompetingVpnStatePath 2>$null | Out-Null
    & icacls.exe $CompetingVpnStatePath `
        /inheritance:r `
        /grant:r `
        '*S-1-5-18:F' `
        '*S-1-5-32-544:F' |
        Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to protect competing VPN restore state.'
    }
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
    foreach ($serviceName in @(
        @($state.services) |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )) {
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
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Status -eq 'Up' -and
                $_.Name -ne $TunnelName -and
                (
                    $_.Name -match '(?i)(wireguard|wintun|amnezia|warp|cloudflare|device[0-9_]+)' -or
                    $_.InterfaceDescription -match '(?i)(wireguard|wintun|amnezia|warp|cloudflare)'
                )
            }
        foreach ($adapter in $adapters) {
            $labels.Add("adapter:$($adapter.Name)") | Out-Null
        }
    } catch {
        Write-GreenLog "adapter competition check warning: $($_.Exception.Message)"
    }

    foreach ($service in @(Get-CompetingVpnServices)) {
        $labels.Add("service:$($service.Name)") | Out-Null
    }

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

    Save-CompetingVpnState -Services $services
    Write-GreenLog "takeover requested reason=$Reason serviceCount=$($services.Count)"
    foreach ($service in $services) {
        $serviceName = [string]$service.Name
        try {
            Invoke-External -FilePath 'sc.exe' -Arguments @('stop', $serviceName) `
                -AllowedExitCodes @(0, 1056, 1060, 1062) | Out-Null
        } catch {
            Write-GreenLog "takeover service stop failed: $serviceName"
        }
    }

    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        $remaining = @(Get-CompetingVpnLabels)
        if ($remaining.Count -eq 0) {
            Write-GreenLog "takeover complete reason=$Reason"
            return @()
        }
        Start-Sleep -Milliseconds 250
    }

    $remaining = @(Get-CompetingVpnLabels)
    Write-GreenLog "takeover incomplete reason=$Reason remainingCount=$($remaining.Count)"
    return $remaining
}

function Stop-GreenTunnel {
    Remove-GreenPrivilegedRuntimeValue -Name 'ActiveRoutingMode'
    $processRouterStopError = $null
    try {
        Stop-GreenProcessRouter
    } catch {
        $processRouterStopError = $_.Exception.Message
        Write-GreenLog "process router stop warning: $processRouterStopError"
    }
    $svc = Get-OwnService
    if ($null -ne $svc) {
        try {
            Invoke-External -FilePath 'sc.exe' -Arguments @('stop', $ServiceName) -AllowedExitCodes @(0, 1056, 1060, 1062) | Out-Null
            Start-Sleep -Milliseconds 700
        } catch {
            Write-GreenLog "sc stop warning: $($_.Exception.Message)"
        }
    }

    $wg = Resolve-WireGuardExe
    if ([string]::IsNullOrWhiteSpace($wg)) {
        Write-GreenLog 'WireGuard executable not found while stopping tunnel'
        if ($null -ne $processRouterStopError) {
            throw "Tunnel stopped without confirming process router cleanup: $processRouterStopError"
        }
        return
    }

    try {
        Invoke-External -FilePath $wg -Arguments @('/uninstalltunnelservice', $TunnelName) -AllowedExitCodes @(0, 1) | Out-Null
    } catch {
        Write-GreenLog "wireguard uninstall warning: $($_.Exception.Message)"
    }
    if ($null -ne $processRouterStopError) {
        throw "Tunnel stopped without confirming process router cleanup: $processRouterStopError"
    }
}

function Complete-GreenDisconnectedRuntimeState {
    $transitionGeneration = [uint32](
        Get-GreenRuntimeTransitionGenerationForCleanup
    )
    Stop-GreenTunnel
    Confirm-GreenProcessRouterRuntimeContract -Required $false
    Complete-GreenRuntimeStateTransition `
        -TransitionGeneration $transitionGeneration
    $script:ActiveRuntimeTransitionGeneration = $null
    Write-GreenLog 'disconnected runtime state committed'
}

function Start-GreenTunnel {
    Ensure-GreenProgramDataAcl

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-GreenLog "config missing: $ConfigPath"
        throw "Config missing: $ConfigPath"
    }

    $wg = Resolve-WireGuardExe
    if ([string]::IsNullOrWhiteSpace($wg)) {
        throw 'WireGuard executable not found.'
    }

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

    $routingMode = Get-GreenRoutingMode
    $routingPolicy = $null
    $applicationPaths = @()
    if ($routingMode -eq 'applications') {
        $routingPolicy = Get-GreenRoutingPolicy
        $applicationPaths = @(Get-GreenApplicationPaths -Policy $routingPolicy)
        Ensure-GreenApplicationTunnelRoutes -Policy $routingPolicy
    } else {
        Ensure-NativeFullTunnelKillSwitch
    }

    Stop-GreenTunnel
    Ensure-GreenProgramDataAcl

    Invoke-External -FilePath $wg -Arguments @('/installtunnelservice', $ConfigPath) -AllowedExitCodes @(0) | Out-Null
    Invoke-External -FilePath 'sc.exe' -Arguments @('config', $ServiceName, 'start=', 'demand') -AllowedExitCodes @(0) | Out-Null
    Invoke-External -FilePath 'sc.exe' -Arguments @('start', $ServiceName) -AllowedExitCodes @(0, 1056) | Out-Null

    if ($routingMode -eq 'applications' -and $applicationPaths.Count -gt 0) {
        $tunnelReady = $false
        for ($i = 0; $i -lt 20; $i++) {
            $svc = Get-OwnService
            if (
                $null -ne $svc -and
                $svc.State -eq 'Running' -and
                (Test-GreenTcpEndpoint -HostName $ApplicationProxyHost -Port $ApplicationProxyPort -TimeoutMs 250)
            ) {
                $tunnelReady = $true
                break
            }
            Start-Sleep -Milliseconds 250
        }
        if (-not $tunnelReady) {
            Stop-GreenTunnel
            throw 'The application routing gateway is unavailable through the tunnel.'
        }
        try {
            Start-GreenProcessRouter -ApplicationPaths $applicationPaths
        } catch {
            Stop-GreenTunnel
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
    Ensure-GreenProgramDataAcl
    $svc = Get-OwnService
    if ($null -eq $svc) { return }

    if ($svc.StartMode -eq 'Auto') {
        try {
            Invoke-External -FilePath 'sc.exe' -Arguments @('config', $ServiceName, 'start=', 'demand') -AllowedExitCodes @(0) | Out-Null
        } catch {
            Write-GreenLog "guard manual-start warning: $($_.Exception.Message)"
        }
    }

    if ($svc.State -ne 'Running') { return }

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
        Write-GreenLog "guard disconnecting Green VPN because takeover remained incomplete count=$($competitors.Count)"
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

$runtimeMutationMutex = $null
$taskExitCode = 0
try {
    $runtimeMutationMutex = Enter-GreenRuntimeMutationLock
    Write-GreenLog 'started'
    switch ($Action) {
        'Connect' { Start-GreenTunnel }
        'Disconnect' {
            Ensure-GreenProgramDataAcl
            Complete-GreenDisconnectedRuntimeState
            Restore-CompetingVpnTunnels
        }
        'Guard' { Invoke-GreenGuard }
    }
    Write-GreenLog 'finished'
} catch {
    Write-GreenLog "failed: $($_.Exception.Message)"
    $mustRecover = $null -ne $runtimeMutationMutex -and (
        $Action -eq 'Connect' -or
        $null -ne $script:ActiveRuntimeTransitionGeneration -or
        -not (Test-GreenRuntimeStateStable)
    )
    if ($mustRecover) {
        try {
            Complete-GreenDisconnectedRuntimeState
        } catch {
            Write-GreenLog "failed tunnel cleanup: $($_.Exception.Message)"
        }
        try {
            Restore-CompetingVpnTunnels
        } catch {
            Write-GreenLog "failed competitor restore: $($_.Exception.Message)"
        }
    }
    $taskExitCode = 10
} finally {
    Exit-GreenRuntimeMutationLock -Mutex $runtimeMutationMutex
}
exit $taskExitCode
