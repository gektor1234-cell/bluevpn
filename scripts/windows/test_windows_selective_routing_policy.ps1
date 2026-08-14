param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tempBoundary = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
$testRoot = Join-Path $env:TEMP ("GreenVpnSelectiveRoutingTest_" + [guid]::NewGuid().ToString('N'))
$resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
$registryTestId = [guid]::NewGuid().ToString('N')
$registryTestSubKey = "Software\GreenVPN\CodexTests\$registryTestId"
if (-not ($resolvedTestRoot + '\').StartsWith($tempBoundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe selective-routing test path: $resolvedTestRoot"
}

New-Item -ItemType Directory -Path $resolvedTestRoot | Out-Null
try {
    $ProgramDataRoot = $resolvedTestRoot
    $ConfigPath = Join-Path $resolvedTestRoot 'test.conf'

    function Ensure-GreenProgramDataAcl {}
    function Write-GreenLog {
        param([string]$Message)
    }

    . (Join-Path $PSScriptRoot 'greenvpn_selective_routing.ps1')

    $projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $processRouterSourcePath = Join-Path $projectRoot `
        'third_party\windows\process_router\source\ProxyBridge.c'
    $processRouterSource = [IO.File]::ReadAllText($processRouterSourcePath)
    foreach ($marker in @(
        'WINDIVERT_LAYER_SOCKET',
        'WINDIVERT_EVENT_SOCKET_CONNECT',
        'addr.Socket.ProcessId',
        'store_socket_port_pid',
        'PROCESS_ATTRIBUTION_WAIT_MS',
        'WinDivertHelperHtonIPv6Address',
        'htonl(addr.Flow.LocalAddr[3])',
        'htonl(addr.Flow.RemoteAddr[3])',
        'htonl(addr.Socket.LocalAddr[3])',
        'htonl(addr.Socket.RemoteAddr[3])'
    )) {
        if (-not $processRouterSource.Contains($marker)) {
            throw "Process-router pre-connect attribution marker is missing: $marker"
        }
    }
    foreach ($invalidIpv4Layout in @(
        '((const UINT8 *)addr.Flow.LocalAddr) + 12',
        'htonl(addr.Flow.LocalAddr[0])',
        'htonl(addr.Flow.RemoteAddr[0])',
        'htonl(addr.Socket.LocalAddr[0])',
        'htonl(addr.Socket.RemoteAddr[0])'
    )) {
        if ($processRouterSource.Contains($invalidIpv4Layout)) {
            throw "Process-router retained invalid IPv4 event address layout: $invalidIpv4Layout"
        }
    }

    $RuntimeMutationMutexName =
        "Global\GreenVPN.RuntimeMutation.Test.$registryTestId"
    $runtimeMutationMutex = Enter-GreenRuntimeMutationLock
    if ($null -eq $runtimeMutationMutex) {
        throw 'Runtime mutation mutex was not acquired.'
    }
    Exit-GreenRuntimeMutationLock -Mutex $runtimeMutationMutex

    $script:simulateRegistryReadFailures = 0
    $script:registryOpenReadAttempts = 0
    function Open-GreenPrivilegedRuntimeRegistryKey {
        param([switch]$Writable)

        if (-not $Writable -and $script:simulateRegistryReadFailures -gt 0) {
            $script:registryOpenReadAttempts++
            if ($script:registryOpenReadAttempts -le
                    $script:simulateRegistryReadFailures) {
                throw 'synthetic transient registry read failure'
            }
        }
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::CurrentUser,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        try {
            if ($Writable) {
                return $baseKey.CreateSubKey(
                    $script:registryTestSubKey,
                    [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree
                )
            }
            return $baseKey.OpenSubKey(
                $script:registryTestSubKey,
                [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadSubTree
            )
        } finally {
            $baseKey.Dispose()
        }
    }

    Write-GreenPrivilegedRuntimeValue `
        -Name 'ProcessRouterRequired' `
        -Value 0 `
        -PropertyType DWord
    $script:simulateRegistryReadFailures = 2
    $script:registryOpenReadAttempts = 0
    $requiredKind = Get-GreenPrivilegedRuntimeValueKind `
        -Name 'ProcessRouterRequired'
    $script:simulateRegistryReadFailures = 0
    if ($requiredKind -ne [Microsoft.Win32.RegistryValueKind]::DWord -or
            $script:registryOpenReadAttempts -ne 3) {
        throw 'REG_DWORD type retry contract was not preserved.'
    }
    Write-GreenPrivilegedRuntimeValue `
        -Name 'ProcessRouterPid' `
        -Value 12345 `
        -PropertyType DWord
    $script:simulateRegistryReadFailures = 2
    $script:registryOpenReadAttempts = 0
    $pidKind = Get-GreenPrivilegedRuntimeValueKind -Name 'ProcessRouterPid'
    $script:simulateRegistryReadFailures = 0
    if ($pidKind -ne [Microsoft.Win32.RegistryValueKind]::DWord -or
            $script:registryOpenReadAttempts -ne 3) {
        throw 'Process-router PID type retry contract was not preserved.'
    }
    Remove-GreenPrivilegedRuntimeValue -Name 'ProcessRouterPid'

    $script:simulateRegistryReadFailures = 3
    $script:registryOpenReadAttempts = 0
    $persistentTypeFailureRejected = $false
    try {
        [void](Get-GreenPrivilegedRuntimeValueKind `
                -Name 'ProcessRouterRequired')
    } catch {
        $persistentTypeFailureRejected = $true
    }
    $script:simulateRegistryReadFailures = 0
    if (-not $persistentTypeFailureRejected) {
        throw 'Persistent registry type failure was not rejected.'
    }

    Write-GreenPrivilegedRuntimeValue `
        -Name 'ProcessRouterRequired' `
        -Value '0' `
        -PropertyType String
    $wrongTypeRejected = $false
    try { Confirm-GreenProcessRouterRuntimeContract -Required $false }
    catch { $wrongTypeRejected = $true }
    Write-GreenPrivilegedRuntimeValue `
        -Name 'ProcessRouterRequired' `
        -Value 1 `
        -PropertyType DWord
    $wrongValueRejected = $false
    try { Confirm-GreenProcessRouterRuntimeContract -Required $false }
    catch { $wrongValueRejected = $true }
    if (-not $wrongTypeRejected -or -not $wrongValueRejected -or
            $null -ne (Read-GreenPrivilegedRuntimeValue `
                -Name 'ActiveRoutingMode')) {
        throw 'Invalid runtime contract did not remain fail-closed.'
    }
    Write-GreenPrivilegedRuntimeValue `
        -Name 'ProcessRouterRequired' `
        -Value 0 `
        -PropertyType DWord

    Write-GreenPrivilegedRuntimeValue `
        -Name 'RuntimeStateGeneration' `
        -Value ([uint32]0) `
        -PropertyType DWord
    $script:ActiveRuntimeTransitionGeneration = $null
    $firstCleanupGeneration = [uint32](
        Get-GreenRuntimeTransitionGenerationForCleanup
    )
    $nestedStartRejected = $false
    try { [void](Start-GreenRuntimeStateTransition) }
    catch { $nestedStartRejected = $true }
    $reusedCleanupGeneration = [uint32](
        Get-GreenRuntimeTransitionGenerationForCleanup
    )
    if ($firstCleanupGeneration -ne 1 -or
            $reusedCleanupGeneration -ne $firstCleanupGeneration -or
            -not $nestedStartRejected -or
            [uint32](Read-GreenPrivilegedRuntimeValue `
                -Name 'RuntimeStateGeneration') -ne 1) {
        throw 'Nested cleanup replaced an active runtime transition.'
    }
    Complete-GreenRuntimeStateTransition `
        -TransitionGeneration $firstCleanupGeneration
    $script:ActiveRuntimeTransitionGeneration = $null
    if ([uint32](Read-GreenPrivilegedRuntimeValue `
            -Name 'RuntimeStateGeneration') -ne 2) {
        throw 'Runtime cleanup did not publish a stable even generation.'
    }
    Write-GreenPrivilegedRuntimeValue `
        -Name 'RuntimeStateGeneration' `
        -Value ([uint32]3) `
        -PropertyType DWord
    Write-GreenPrivilegedRuntimeValue `
        -Name 'ActiveRoutingMode' `
        -Value 'full' `
        -PropertyType String
    $adoptedCleanupGeneration = [uint32](
        Get-GreenRuntimeTransitionGenerationForCleanup
    )
    if ($adoptedCleanupGeneration -ne 3 -or
            $null -ne (Read-GreenPrivilegedRuntimeValue `
                -Name 'ActiveRoutingMode')) {
        throw 'Cleanup did not safely adopt an abandoned odd generation.'
    }
    Complete-GreenRuntimeStateTransition `
        -TransitionGeneration $adoptedCleanupGeneration
    $script:ActiveRuntimeTransitionGeneration = $null
    $nextCleanupGeneration = [uint32](
        Get-GreenRuntimeTransitionGenerationForCleanup
    )
    if ($nextCleanupGeneration -ne 5) {
        throw 'Independent cleanup did not start the next transition.'
    }
    Complete-GreenRuntimeStateTransition `
        -TransitionGeneration $nextCleanupGeneration
    $script:ActiveRuntimeTransitionGeneration = $null

    [IO.File]::WriteAllText(
        $RoutingModePath,
        'applications',
        [Text.UTF8Encoding]::new($false)
    )
    [ordered]@{
        schemaVersion = 2
        proxy = [ordered]@{
            host = '10.10.0.1'
            port = 1080
        }
        applications = @()
        destinationCidrs = @('142.250.0.0/15')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $RoutingAppsPath -Encoding UTF8
    [IO.File]::WriteAllText(
        $ConfigPath,
        "[Peer]`r`nAllowedIPs = 0.0.0.0/0, ::/0`r`n",
        [Text.UTF8Encoding]::new($false)
    )

    $policy = Get-GreenRoutingPolicy
    Ensure-GreenApplicationTunnelRoutes -Policy $policy
    $updated = [IO.File]::ReadAllText($ConfigPath)
    if ($updated -notmatch '(?m)^AllowedIPs = 142\.250\.0\.0/15$') {
        throw 'Selective routing did not keep the requested public destination.'
    }
    if ($updated -match '0\.0\.0\.0/0|0\.0\.0\.0/1|128\.0\.0\.0/1|::/0') {
        throw 'Selective routing retained a default route.'
    }

    [ordered]@{
        schemaVersion = 2
        proxy = [ordered]@{
            host = '10.10.0.1'
            port = 1080
        }
        applications = @()
        destinationCidrs = @('127.0.0.0/8')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $RoutingAppsPath -Encoding UTF8

    $privateCidrRejected = $false
    try {
        $invalidPolicy = Get-GreenRoutingPolicy
        [void](Get-GreenDestinationCidrs -Policy $invalidPolicy)
    }
    catch {
        $privateCidrRejected = $true
    }
    if (-not $privateCidrRejected) {
        throw 'Selective routing accepted a private destination CIDR.'
    }

    $syntheticRouterRoot = Join-Path $resolvedTestRoot 'router'
    New-Item -ItemType Directory -Force -Path $syntheticRouterRoot | Out-Null
    $syntheticRouterExe = Join-Path $syntheticRouterRoot 'ProxyBridge_CLI.exe'
    [IO.File]::WriteAllText($syntheticRouterExe, 'synthetic')
    $selectedApp = Join-Path $resolvedTestRoot 'selected.exe'
    [IO.File]::WriteAllText($selectedApp, 'synthetic')
    $ProcessRouterRoot = $syntheticRouterRoot
    $ProcessRouterExe = $syntheticRouterExe
    $ProcessRouterProfilePath = Join-Path $resolvedTestRoot 'process-router.pbprofile'
    function Stop-GreenProcessRouter {}
    function Assert-GreenProcessRouterPayload {}
    function Test-GreenProcessRouterRunning { return $true }
    function Start-Process {
        param(
            [string]$FilePath,
            [object[]]$ArgumentList,
            [string]$WorkingDirectory,
            [string]$WindowStyle,
            [switch]$PassThru,
            [string]$RedirectStandardOutput,
            [string]$RedirectStandardError
        )
        $script:capturedRouterArguments = @($ArgumentList)
        return [pscustomobject]@{ Id = 4242; HasExited = $false }
    }
    Start-GreenProcessRouter -ApplicationPaths @($selectedApp)
    $profile = [IO.File]::ReadAllText($ProcessRouterProfilePath) |
        ConvertFrom-Json
    $selectedRule = @($profile.ProxyRules | Where-Object {
        [string]$_.ProcessName -eq $selectedApp
    })
    if (
        [string]$profile.Version -ne '1.0' -or
        [bool]$profile.LocalhostViaProxy -or
        [bool]$profile.IsTrafficLoggingEnabled -or
        @($profile.ProxyConfigs).Count -ne 1 -or
        [string]$profile.ProxyConfigs[0].Type -ne 'socks5' -or
        [string]$profile.ProxyConfigs[0].Host -ne '10.10.0.1' -or
        [string]$profile.ProxyConfigs[0].Port -ne '1080' -or
        $selectedRule.Count -ne 1 -or
        [string]$selectedRule[0].TargetHosts -ne '*' -or
        [string]$selectedRule[0].TargetPorts -ne '*' -or
        [string]$selectedRule[0].Protocol -ne 'BOTH' -or
        [string]$selectedRule[0].Action -ne 'PROXY' -or
        -not [bool]$selectedRule[0].IsEnabled -or
        [int]$selectedRule[0].ProxyConfigId -ne 1 -or
        @($profile.ProxyRules).Count -ne 1 -or
        @($script:capturedRouterArguments).Count -ne 4 -or
        [string]$script:capturedRouterArguments[0] -ne '--profile' -or
        [string]$script:capturedRouterArguments[1] -ne $ProcessRouterProfilePath -or
        [string]$script:capturedRouterArguments[2] -ne '--verbose' -or
        [string]$script:capturedRouterArguments[3] -ne '1'
    ) {
        throw 'ProxyBridge v4 profile contract was not preserved.'
    }

    [pscustomobject]@{
        success = $true
        routingMode = Get-GreenRoutingMode
        defaultRoutesRemoved = $true
        privateCidrRejected = $privateCidrRejected
        registryTypeRetryPassed = $true
        runtimeMutationMutexPassed = $true
        invalidRegistryContractRejected = $true
        nestedTransitionStartRejected = $nestedStartRejected
        nestedCleanupGenerationReused = $true
        abandonedGenerationAdopted = $true
        proxyBridgeV4ProfilePassed = $true
        preConnectAttributionContractPassed = $true
    } | ConvertTo-Json
}
finally {
    $registryBaseKey = $null
    try {
        $registryBaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::CurrentUser,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $registryBaseKey.DeleteSubKeyTree($registryTestSubKey, $false)
    } finally {
        if ($null -ne $registryBaseKey) { $registryBaseKey.Dispose() }
    }
    $cleanupTarget = [IO.Path]::GetFullPath($resolvedTestRoot)
    if (($cleanupTarget + '\').StartsWith($tempBoundary, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $cleanupTarget -Recurse -Force -ErrorAction SilentlyContinue
    }
}
