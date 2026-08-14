$RoutingModePath = Join-Path $ProgramDataRoot 'routing_mode'
$RoutingAppsPath = Join-Path $ProgramDataRoot 'routing_apps.json'
$runtimeScope = if ($ProgramDataRoot -match '(?i)BlueVPNBeta$') { 'paid-beta' } else { 'stable' }
$PrivilegedRuntimeRegistryPath = "HKLM:\SOFTWARE\GreenVPN\Runtime\$runtimeScope"
$PrivilegedRuntimeRegistrySubKey = "SOFTWARE\GreenVPN\Runtime\$runtimeScope"
$RuntimeMutationMutexName = 'Global\GreenVPN.RuntimeMutation'
$ProcessRouterRoot = Join-Path $PSScriptRoot 'process-router'
$ProcessRouterExe = Join-Path $ProcessRouterRoot 'ProxyBridge_CLI.exe'
$ProcessRouterProfilePath = Join-Path $ProgramDataRoot 'process-router.pbprofile'
$ProcessRouterStdoutPath = Join-Path $ProgramDataRoot 'process-router.stdout.log'
$ProcessRouterStderrPath = Join-Path $ProgramDataRoot 'process-router.stderr.log'
$ApplicationProxyHost = '10.10.0.1'
$ApplicationProxyPort = 1080
$ProcessRouterHashes = @{
    'ProxyBridge_CLI.exe' = '6C215C7975E3CBEE086DE0EE2F3226FAE84F35A7B0A2FFD432FC346EF56A0569'
    'ProxyBridgeCore.dll' = 'AFBD2296022A9CE96884069BBB32FCB1B1E9EC7203C4A219E50E21D7E791ECD2'
    'WinDivert.dll' = 'C1E060EE19444A259B2162F8AF0F3FE8C4428A1C6F694DCE20DE194AC8D7D9A2'
    'WinDivert64.sys' = '8DA085332782708D8767BCACE5327A6EC7283C17CFB85E40B03CD2323A90DDC2'
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
