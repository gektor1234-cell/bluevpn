param([string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.ServiceProcess

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message actual=$Actual expected=$Expected" }
}

# Only extracted functions and the dispatcher execute. Every service/route
# dependency below is a mock; the live task scripts are never dot-sourced.
foreach ($file in @('greenvpn_vpn_task.ps1', 'greenvpn_transport_preview_vpn_task.ps1')) {
    & {
        $path = Join-Path $ProjectRoot "scripts\windows\$file"
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw ($errors | Out-String) }
        foreach ($name in @('Save-CompetingVpnState', 'Restore-CompetingVpnTunnels')) {
            $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            if ($null -ne $fn) { throw "Forbidden external VPN restoration function: $name" }
        }
        foreach ($name in @('Complete-CompetingVpnTakeover', 'Stop-CompetingVpnTunnels', 'Invoke-GreenGuard')) {
            $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($fn.Extent.Text))
        }
        $dispatcher = $ast.Find({ param($node) $node -is [Management.Automation.Language.TryStatementAst] -and $node.Body.Extent.Text.Contains('switch ($Action)') }, $false)
        if ($null -eq $dispatcher) { throw 'Task dispatcher missing' }
        $run = [scriptblock]::Create($dispatcher.Extent.Text)
        $script:ActiveRuntimeTransitionGeneration = $null
        $script:started = 0
        $script:stopped = 0
        $script:cleanup = 0
        $script:deleted = 0
        $script:competitorRunning = $true
        $script:failConnect = $false
        $script:failCleanup = $false
        $script:snapshotExists = $true
        $script:ownRunning = $true
        $script:routerRequired = 0
        $script:routerRunning = $true
        $script:snapshotName = 'WireGuardTunnel$ExternalTest'
        $CompetingVpnStatePath = 'mock:competing-vpn-state'
        $WireGuardServiceName = 'WireGuardTunnel$OwnTest'
        $AmneziaWgServiceName = 'AmneziaWGTunnel$OwnTest'
        $ServiceName = $WireGuardServiceName
        foreach ($name in @('HysteriaPidPath','HevPidPath','HysteriaExe','HevExe','XrayPidPath','VlessHevPidPath','XrayExe','VlessHevExe','NaivePidPath','NaiveHevPidPath','NaiveExe','NaiveHevExe','DnsttPidPath','DnsttHevPidPath','DnsttExe','DnsttHevExe')) { Set-Variable $name 'mock:unused' }
        function Write-GreenLog { param($Message) }
        function Ensure-GreenProgramDataAcl {}
        function Enter-GreenRuntimeMutationLock { return 'mock:lock' }
        function Exit-GreenRuntimeMutationLock { param($Mutex) }
        function Test-GreenRuntimeStateStable { return $true }
        function Write-GreenConnectFailureSnapshot { param($FailureRecord) }
        function Complete-GreenDisconnectedRuntimeState {
            if ($script:failCleanup) { throw 'mock:cleanup-failed' }
            $script:cleanup++
        }
        function Test-Path { param($LiteralPath, $PathType) return $script:snapshotExists }
        function Remove-Item { param($LiteralPath, [switch]$Force, $ErrorAction) $script:snapshotExists = $false; $script:deleted++ }
        function Get-Content { param($LiteralPath, [switch]$Raw) return (@{schema=1; services=@($script:snapshotName)} | ConvertTo-Json) }
        function Get-CompetingVpnServices {
            if ($script:competitorRunning) { [pscustomobject]@{Name='WireGuardTunnel$ExternalTest'} }
        }
        function Get-CompetingVpnLabels { if ($script:competitorRunning) { 'service:external' } }
        function Stop-Service { param($Name, [switch]$Force, $ErrorAction) $script:stopped++; $script:competitorRunning=$false }
        function Invoke-External { param($FilePath, $Arguments, $AllowedExitCodes) $script:stopped++; $script:competitorRunning=$false }
        function Start-Service { param($Name, $ErrorAction) $script:started++; $script:competitorRunning=$true }
        function Get-Service {
            param($Name, $ErrorAction)
            $svc = [pscustomobject]@{ Status='Stopped' }
            $svc | Add-Member ScriptMethod WaitForStatus { param($state, $timeout) }
            return $svc
        }
        function Get-OwnService { return [pscustomobject]@{Name=$ServiceName; State='Running'; StartMode='Manual'} }
        function Get-CimInstance { param($ClassName, $ErrorAction) return (Get-OwnService) }
        function Test-ExactProcess { param($ProcessId, $ExpectedPath) return $false }
        function Read-ManagedPid { param($Path) return 0 }
        function Read-GreenPrivilegedRuntimeValue { param($Name) return $script:routerRequired }
        function Test-GreenProcessRouterRunning { return $script:routerRunning }
        function Start-Sleep { param($Milliseconds) }
        function Start-GreenTunnel {
            $remaining = @(Stop-CompetingVpnTunnels -Reason 'connect')
            if ($remaining.Count -gt 0) { throw 'mock:competing-vpn-active' }
            if ($script:failConnect) { throw 'mock:connect-failed' }
        }
        function Start-OwnTunnel { Start-GreenTunnel }

        Complete-CompetingVpnTakeover
        Assert-Equal $script:started 0 'Stale snapshot must not restart a VPN'
        $Action = 'Connect'
        $taskExitCode = 0
        . $run
        Assert-Equal $taskExitCode 0 'Successful takeover'
        Assert-Equal $script:stopped 1 'Connect stops external VPN once'
        Assert-Equal $script:snapshotExists $false 'Successful takeover does not retain a restore journal'
        $Action = 'Disconnect'
        . $run
        Assert-Equal $script:started 0 'Disconnect must not restore a previous VPN'

        $script:competitorRunning = $true
        $script:failConnect = $true
        $Action = 'Connect'
        . $run
        Assert-Equal $taskExitCode 10 'Failed takeover reports failure'
        Assert-Equal $script:started 0 'Failed initial takeover must leave external VPN stopped'
        Complete-CompetingVpnTakeover
        Assert-Equal $script:started 0 'Cleanup never starts another VPN'

        $script:failCleanup = $true
        . $run
        Assert-Equal $script:started 0 'Unconfirmed cleanup must not start a competing tunnel'
        $script:failCleanup = $false
        Complete-CompetingVpnTakeover
        $script:competitorRunning = $true
        $beforeStop = $script:stopped
        $beforeCleanup = $script:cleanup
        $Action = 'Guard'
        . $run
        Assert-Equal $script:stopped $beforeStop 'Guard must not seize another VPN'
        Assert-Equal $script:cleanup ($beforeCleanup + 1) 'Guard yields own tunnel'
        Assert-Equal $script:started 0 'Guard must not restore old snapshot'

        $script:competitorRunning = $false
        $script:routerRequired = 1
        $script:routerRunning = $false
        $beforeCleanup = $script:cleanup
        . $run
        Assert-Equal $script:cleanup ($beforeCleanup + 1) 'Router loss remains fail closed'
        Assert-Equal $script:started 0 'Router loss must not restore old VPN'

        $script:failConnect = $false
        $script:routerRequired = 0
        $script:competitorRunning = $true
        $beforeStop = $script:stopped
        $Action = 'Reconnect'
        . $run
        Assert-Equal $taskExitCode 10 'Recovery rejects an external VPN activated after the UI check'
        Assert-Equal $script:stopped $beforeStop 'Recovery never stops another VPN'
        Assert-Equal $script:started 0 'Recovery never restores another VPN'
        $script:competitorRunning = $false
        $taskExitCode = 0
        . $run
        Assert-Equal $taskExitCode 0 'Recovery can connect when no external VPN owns the network'

        $script:competitorRunning = $true
        $beforeStop = $script:stopped
        $beforeCleanup = $script:cleanup
        $Action = 'PrepareUpdate'
        . $run
        Assert-Equal $taskExitCode 0 'Update preparation succeeds'
        Assert-Equal $script:stopped ($beforeStop + 1) 'Update preparation stops supported external VPN'
        Assert-Equal $script:cleanup ($beforeCleanup + 1) 'Update preparation stops Green VPN first'
        Assert-Equal $script:started 0 'Update preparation never restores a VPN'
        Write-Output "$file ownership behavior passed"
    }
}
