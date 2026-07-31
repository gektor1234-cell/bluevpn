[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\Program Files\Green VPN',
    [string]$AppPath = '',
    [string]$ProgramDataRoot = 'C:\ProgramData\BlueVPN',
    [string]$UserStateRoot = '',
    [int]$LocalServicePort = 48737,
    [ValidateRange(30, 420)]
    [int]$FirstConnectTimeoutSeconds = 150,
    [ValidateRange(20, 180)]
    [int]$SecondConnectTimeoutSeconds = 90,
    [ValidateRange(10, 120)]
    [int]$MaxFirstConnectSeconds = 30,
    [switch]$AllowExistingPreferredRoute,
    [ValidateRange(10, 120)]
    [int]$MaxCachedConnectSeconds = 60,
    [switch]$UseElevatedPendingAction,
    [switch]$UseUiAutomationAction,
    [switch]$TemporarilyStopExternalVpn,
    [switch]$ExpectCompetingVpn,
    [string]$ExternalVpnServiceName = 'AmneziaWGTunnel$device20_full',
    [ValidateRange(3, 30)]
    [int]$FailsafeDelayMinutes = 5,
    [int]$FailsafeProcessId = 0,
    [string]$ReportPath = 'C:\BlueVPN_Builds\windows_connect_latency_physical.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (
    ($UseElevatedPendingAction -or $TemporarilyStopExternalVpn) -and
    -not (Test-IsAdministrator)
) {
    $argList = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        "`"$PSCommandPath`"",
        '-InstallRoot',
        "`"$InstallRoot`"",
        '-AppPath',
        "`"$AppPath`"",
        '-ProgramDataRoot',
        "`"$ProgramDataRoot`"",
        '-UserStateRoot',
        "`"$UserStateRoot`"",
        '-LocalServicePort',
        [string]$LocalServicePort,
        '-FirstConnectTimeoutSeconds',
        [string]$FirstConnectTimeoutSeconds,
        '-SecondConnectTimeoutSeconds',
        [string]$SecondConnectTimeoutSeconds,
        '-MaxFirstConnectSeconds',
        [string]$MaxFirstConnectSeconds,
        '-MaxCachedConnectSeconds',
        [string]$MaxCachedConnectSeconds,
        '-ExternalVpnServiceName',
        "`"$ExternalVpnServiceName`"",
        '-FailsafeDelayMinutes',
        [string]$FailsafeDelayMinutes,
        '-FailsafeProcessId',
        [string]$FailsafeProcessId,
        '-ReportPath',
        "`"$ReportPath`""
    )
    if ($UseElevatedPendingAction) { $argList += '-UseElevatedPendingAction' }
    if ($UseUiAutomationAction) { $argList += '-UseUiAutomationAction' }
    if ($TemporarilyStopExternalVpn) { $argList += '-TemporarilyStopExternalVpn' }
    if ($ExpectCompetingVpn) { $argList += '-ExpectCompetingVpn' }
    if ($AllowExistingPreferredRoute) { $argList += '-AllowExistingPreferredRoute' }

    $process = Start-Process `
        -FilePath 'powershell.exe' `
        -Verb RunAs `
        -WindowStyle Hidden `
        -Wait `
        -PassThru `
        -ArgumentList $argList
    exit $process.ExitCode
}

$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$resolvedProgramDataRoot = [IO.Path]::GetFullPath($ProgramDataRoot).TrimEnd('\')
$resolvedUserStateRoot = if ([string]::IsNullOrWhiteSpace($UserStateRoot)) {
    [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'GreenVPN\state')).TrimEnd('\')
} else {
    [IO.Path]::GetFullPath($UserStateRoot).TrimEnd('\')
}
$resolvedAppPath = if ([string]::IsNullOrWhiteSpace($AppPath)) {
    Join-Path $resolvedInstallRoot 'greenvpn.exe'
} else {
    [IO.Path]::GetFullPath($AppPath)
}
$tokenPath = Join-Path $resolvedProgramDataRoot 'service_token'
$authLogPath = Join-Path $resolvedProgramDataRoot 'auth.log'
$stateRoot = Join-Path $resolvedProgramDataRoot 'state'
$prefsPath = Join-Path $resolvedUserStateRoot 'prefs.json'
$pendingActionPath = Join-Path $stateRoot 'pending_vpn_action.txt'
$taskScriptPath = Join-Path $resolvedInstallRoot 'tools\greenvpn_vpn_task.ps1'
$failsafeTaskName = 'GreenVPNConnectLatencySmokeFailsafe'

function Get-ServiceState {
    param([Parameter(Mandatory = $true)][string]$Name)

    $service = Get-CimInstance Win32_Service `
        -Filter "Name='$Name'" `
        -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        return 'Missing'
    }
    return [string]$service.State
}

function Wait-ServiceState {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Running', 'Stopped', 'Missing')]
        [string]$State,
        [int]$TimeoutSeconds = 45
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if ((Get-ServiceState -Name $Name) -eq $State) {
            return $true
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Get-EgressFingerprint {
    foreach ($url in @('https://api.ipify.org', 'https://ifconfig.me/ip')) {
        try {
            $value = (Invoke-RestMethod -Uri $url -TimeoutSec 15).ToString().Trim()
            if (-not $value) {
                continue
            }
            $bytes = [Text.Encoding]::UTF8.GetBytes($value)
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace(
                    '-',
                    ''
                )
            } finally {
                $sha.Dispose()
                [Array]::Clear($bytes, 0, $bytes.Length)
                $value = $null
            }
        } catch {}
    }
    return ''
}

function Register-RestoreFailsafe {
    $command = (
        "Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue | " +
        "Stop-Process -Force -ErrorAction SilentlyContinue; " +
        "& '$taskScriptPath' -Action Disconnect -ErrorAction SilentlyContinue; " +
        "Start-Service -Name '$ExternalVpnServiceName' -ErrorAction SilentlyContinue"
    )
    $action = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument (
            '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' +
            ($command -replace '"', '\"') +
            '"'
        )
    $trigger = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date).AddMinutes($FailsafeDelayMinutes)
    $principal = New-ScheduledTaskPrincipal `
        -UserId 'SYSTEM' `
        -LogonType ServiceAccount `
        -RunLevel Highest
    Register-ScheduledTask `
        -TaskName $failsafeTaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Force |
        Out-Null
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
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [int]$TimeoutSeconds = 15
    )

    $headers = @{ 'X-GreenVPN-Local-Token' = (Get-LocalToken) }
    return Invoke-RestMethod -Method $Method `
        -Uri "http://127.0.0.1:$LocalServicePort$Path" `
        -Headers $headers `
        -TimeoutSec $TimeoutSeconds
}

function Get-GreenStatus {
    return Invoke-GreenLocal -Method GET -Path '/status' -TimeoutSeconds 8
}

function Test-AllManagedComponentsStopped {
    param([Parameter(Mandatory = $true)]$Status)

    $stateKeys = @(
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
    foreach ($key in $stateKeys) {
        $value = ([string]$Status.$key).Trim().ToLowerInvariant()
        if ($value -notin @('stopped', 'missing')) {
            return $false
        }
    }
    return $true
}

function Wait-AllManagedComponentsStopped {
    param([int]$TimeoutSeconds = 45)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            if (Test-AllManagedComponentsStopped -Status (Get-GreenStatus)) {
                return $true
            }
        } catch {}
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Stop-GreenApp {
    Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(8)
    do {
        if (-not (Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue)) {
            return
        }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    throw 'Green VPN application did not stop.'
}

function Invoke-GreenConnectButton {
    param(
        [Parameter(Mandatory = $true)][Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][int]$AfterLogLine
    )

    Add-Type -AssemblyName System.Windows.Forms
    if (-not ('GreenVpnSmokeInput' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class GreenVpnSmokeInput {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern bool GetClientRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    private static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern void mouse_event(
        uint flags,
        uint dx,
        uint dy,
        uint data,
        UIntPtr extraInfo
    );

    public static bool ClickConnect(IntPtr hWnd) {
        RECT rect;
        POINT original;
        if (!GetClientRect(hWnd, out rect) || !GetCursorPos(out original)) {
            return false;
        }

        var point = new POINT {
            X = Math.Max(1, (rect.Right - rect.Left) / 2),
            Y = Math.Max(1, (int)Math.Round((rect.Bottom - rect.Top) * 0.255))
        };
        if (!ClientToScreen(hWnd, ref point)) {
            return false;
        }

        SetForegroundWindow(hWnd);
        if (!SetCursorPos(point.X, point.Y)) {
            return false;
        }
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
        SetCursorPos(original.X, original.Y);
        return true;
    }
}
'@
    }

    $deadline = (Get-Date).AddSeconds(45)
    $windowReady = $false
    do {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw 'Green VPN exited before its connect button became available.'
        }
        $lines = @(Get-NewAuthLogLines -AfterLine $AfterLogLine)
        $startupReady = [bool](
            $lines |
                Where-Object { $_ -match 'UI main startupReady=true' } |
                Select-Object -First 1
        )
        $catalogReady = [bool](
            $lines |
                Where-Object {
                    $_ -match 'API GET /api/v1/catalog/servers\?.* status=200'
                } |
                Select-Object -First 1
        )
        if ($Process.MainWindowHandle -ne 0 -and $startupReady -and $catalogReady) {
            $windowReady = $true
            break
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    if (-not $windowReady) {
        throw 'Green VPN window did not become ready for the connect action.'
    }

    $shell = New-Object -ComObject WScript.Shell
    if (-not $shell.AppActivate($Process.Id)) {
        throw 'Green VPN window could not be activated for the connect action.'
    }
    Start-Sleep -Milliseconds 500
    if (-not [GreenVpnSmokeInput]::ClickConnect($Process.MainWindowHandle)) {
        throw 'Green VPN connect button could not be clicked.'
    }

    $clickDeadline = (Get-Date).AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 150
        $lines = @(Get-NewAuthLogLines -AfterLine $AfterLogLine)
        if (
            $lines |
                Where-Object { $_ -match 'UI toggle requested' } |
                Select-Object -First 1
        ) {
            return
        }
    } while ((Get-Date) -lt $clickDeadline)

    throw 'Green VPN did not acknowledge the automated connect click.'
}

function Get-AuthLogLineCount {
    if (-not (Test-Path -LiteralPath $authLogPath -PathType Leaf)) {
        return 0
    }
    return @(Get-Content -LiteralPath $authLogPath -Encoding UTF8).Count
}

function Get-NewAuthLogLines {
    param([Parameter(Mandatory = $true)][int]$AfterLine)

    if (-not (Test-Path -LiteralPath $authLogPath -PathType Leaf)) {
        return @()
    }
    $lines = @(Get-Content -LiteralPath $authLogPath -Encoding UTF8)
    if ($lines.Count -le $AfterLine) {
        return @()
    }
    return @($lines[$AfterLine..($lines.Count - 1)])
}

function Get-LogTimestamp {
    param([Parameter(Mandatory = $true)][string]$Line)

    if ($Line -notmatch '^\[([^\]]+)\]') {
        return $null
    }
    return [datetimeoffset]::Parse($Matches[1])
}

function Get-ConnectEvidence {
    param(
        [Parameter(Mandatory = $true)][string[]]$Lines,
        [Parameter(Mandatory = $true)][timespan]$WallDuration
    )

    $requestedLine = $Lines |
        Where-Object { $_ -match 'UI toggle requested' } |
        Select-Object -First 1
    $acceptedLine = $Lines |
        Where-Object {
            $_ -match 'UI post connect checks accepted tunnel' -or
            $_ -match 'UI foreground connect accepted system-service tunnel'
        } |
        Select-Object -First 1
    $successfulProbeLine = $Lines |
        Where-Object {
            $_ -match 'UI post connect probe .* status=\d+ ok=true'
        } |
        Select-Object -First 1
    $completionLine = if ($successfulProbeLine) {
        $successfulProbeLine
    } else {
        $acceptedLine
    }

    $logSeconds = $null
    if ($requestedLine -and $completionLine) {
        $requestedAt = Get-LogTimestamp -Line $requestedLine
        $completedAt = Get-LogTimestamp -Line $completionLine
        if ($requestedAt -and $completedAt) {
            $logSeconds = [Math]::Round(($completedAt - $requestedAt).TotalSeconds, 3)
        }
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($line in $Lines) {
        if (
            $line -match
                'UI toggle connect candidate (\d+)/(\d+) id=([^ ]+) protocol=([^ ]+)'
        ) {
            $candidates.Add([ordered]@{
                index = [int]$Matches[1]
                total = [int]$Matches[2]
                id = $Matches[3]
                protocol = $Matches[4]
            })
        }
    }

    $backendStarts = @{}
    $backendDurations = New-Object System.Collections.Generic.List[object]
    foreach ($line in $Lines) {
        if (
            $line -match '^\[([^\]]+)\].*UI toggle connect backend start server=([^ ]+)'
        ) {
            $backendStarts[$Matches[2]] = [datetimeoffset]::Parse($Matches[1])
            continue
        }
        if (
            $line -match '^\[([^\]]+)\].*UI toggle connect backend server=([^ ]+) ok=(true|false)'
        ) {
            $routeId = $Matches[2]
            if (-not $backendStarts.ContainsKey($routeId)) {
                continue
            }
            $backendDurations.Add([ordered]@{
                ok = $Matches[3] -eq 'true'
                seconds = [Math]::Round(
                    ([datetimeoffset]::Parse($Matches[1]) - $backendStarts[$routeId]).TotalSeconds,
                    3
                )
            })
        }
    }

    return [ordered]@{
        uiAccepted = [bool]$acceptedLine
        probeConfirmed = [bool]$successfulProbeLine
        takeoverRequested = [bool](
            $Lines |
                Where-Object { $_ -match 'CONNECT TAKEOVER: competing VPN active' } |
                Select-Object -First 1
        )
        completionMarker = if ($acceptedLine) { 'ui_accepted' } else { 'network_probe' }
        wallSeconds = [Math]::Round($WallDuration.TotalSeconds, 3)
        logSeconds = $logSeconds
        candidates = @($candidates.ToArray())
        backendDurations = @($backendDurations.ToArray())
    }
}

function Invoke-ConnectMeasurement {
    param(
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Stop-GreenApp
    if ($UseElevatedPendingAction) {
        New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
        Set-Content -LiteralPath $pendingActionPath `
            -Encoding ASCII `
            -NoNewline `
            -Value 'connect'
    }
    $afterLine = Get-AuthLogLineCount
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $resolvedAppPath `
        -WorkingDirectory (Split-Path -Parent $resolvedAppPath) `
        -PassThru
    if ($UseUiAutomationAction) {
        Invoke-GreenConnectButton -Process $process -AfterLogLine $afterLine
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lines = @()
    do {
        Start-Sleep -Milliseconds 250
        $lines = @(Get-NewAuthLogLines -AfterLine $afterLine)
        if (
            ($UseElevatedPendingAction -or $UseUiAutomationAction) -and
            (
                $lines |
                    Where-Object {
                        $_ -match 'UI post connect probe .* status=\d+ ok=true'
                    }
            )
        ) {
            break
        }
        if (
            -not ($UseElevatedPendingAction -or $UseUiAutomationAction) -and
            (
                $lines |
                    Where-Object {
                        $_ -match 'UI post connect checks accepted tunnel' -or
                        $_ -match 'UI foreground connect accepted system-service tunnel'
                    }
            )
        ) {
            break
        }
        if (
            $lines |
                Where-Object {
                    $_ -match 'UI toggle connect (exhausted|error)|UI toggle connect failed'
                }
        ) {
            throw "$Label connect failed before acceptance."
        }
    } while ((Get-Date) -lt $deadline)
    $stopwatch.Stop()

    $evidence = Get-ConnectEvidence -Lines $lines -WallDuration $stopwatch.Elapsed
    $systemCompletionObserved = if (
        $UseElevatedPendingAction -or $UseUiAutomationAction
    ) {
        $evidence.probeConfirmed
    } else {
        $evidence.uiAccepted
    }
    if (-not $systemCompletionObserved) {
        throw "$Label connect timed out after $TimeoutSeconds seconds."
    }
    $status = Get-GreenStatus
    if ([string]$status.tunnelState -ne 'running') {
        throw "$Label completed its probe but the system tunnel is not running."
    }
    $evidence.systemTunnelConfirmed = $true
    $evidence.activeProtocol = [string]$status.protocol
    $evidence.appProcessId = $process.Id
    return $evidence
}

function Invoke-CompetingVpnTakeoverMeasurement {
    param([int]$TimeoutSeconds = 150)

    $evidence = Invoke-ConnectMeasurement `
        -TimeoutSeconds $TimeoutSeconds `
        -Label 'Competing-VPN takeover'

    if (
        -not (
            Wait-ServiceState `
                -Name $ExternalVpnServiceName `
                -State 'Stopped' `
                -TimeoutSeconds 15
        )
    ) {
        throw 'Green VPN connected without stopping the active external tunnel service.'
    }

    $evidence.externalVpnStopped = $true
    $evidence.privilegedTakeoverConfirmed = $true
    $evidence.takeoverEvidence =
        'external_service_stopped_and_green_status_running'
    return $evidence
}

function Get-PreferenceEvidence {
    if (-not (Test-Path -LiteralPath $prefsPath -PathType Leaf)) {
        return [ordered]@{
            routePresent = $false
            protocolPresent = $false
            timestampPresent = $false
            routeId = $null
            protocol = $null
            timestamp = $null
        }
    }
    $prefs = Get-Content -LiteralPath $prefsPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $names = @($prefs.PSObject.Properties.Name)
    return [ordered]@{
        routePresent = $names -contains 'lastSuccessfulRouteId'
        protocolPresent = $names -contains 'lastSuccessfulRouteProtocol'
        timestampPresent = $names -contains 'lastSuccessfulRouteAt'
        routeId = if ($names -contains 'lastSuccessfulRouteId') {
            [string]$prefs.lastSuccessfulRouteId
        } else {
            $null
        }
        protocol = if ($names -contains 'lastSuccessfulRouteProtocol') {
            [string]$prefs.lastSuccessfulRouteProtocol
        } else {
            $null
        }
        timestamp = if ($names -contains 'lastSuccessfulRouteAt') {
            [string]$prefs.lastSuccessfulRouteAt
        } else {
            $null
        }
    }
}

function Wait-PreferenceEvidence {
    param([int]$TimeoutSeconds = 30)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $evidence = Get-PreferenceEvidence
        if (
            $evidence.routePresent -and
            $evidence.protocolPresent -and
            $evidence.timestampPresent
        ) {
            return $evidence
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    return Get-PreferenceEvidence
}

function Test-PublicHealth {
    try {
        return (Invoke-WebRequest -UseBasicParsing `
            -Uri 'https://api.greenvpn.pro/healthz' `
            -TimeoutSec 12).StatusCode -eq 200
    } catch {
        return $false
    }
}

if (-not (Test-Path -LiteralPath $resolvedAppPath -PathType Leaf)) {
    throw "Green VPN application is missing: $resolvedAppPath"
}
if ($UseElevatedPendingAction -and $UseUiAutomationAction) {
    throw 'Choose either UseElevatedPendingAction or UseUiAutomationAction.'
}
if (
    $ExpectCompetingVpn -and
    -not ($UseElevatedPendingAction -or $UseUiAutomationAction)
) {
    throw 'ExpectCompetingVpn requires an explicit connect action.'
}
if ($ExpectCompetingVpn -and $TemporarilyStopExternalVpn) {
    throw 'ExpectCompetingVpn cannot temporarily stop the external VPN.'
}
if ($UseElevatedPendingAction -or $TemporarilyStopExternalVpn) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (
        -not $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    ) {
        throw 'The selected physical test options require an elevated process.'
    }
}

$reportDirectory = Split-Path -Parent $ReportPath
if ($reportDirectory) {
    New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
}

$report = [ordered]@{
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    completedAtUtc = $null
    mode = if ($ExpectCompetingVpn) { 'competing_vpn_takeover' } else { 'connect_latency' }
    success = $false
    failure = $null
    baseline = [ordered]@{
        publicHealth = $false
        allManagedComponentsStopped = $false
        preferredRouteInitiallyPresent = $false
        preferredRoute = $null
        userStateRoot = $resolvedUserStateRoot
        externalVpnWasRunning = $false
        egressFingerprintCaptured = $false
        restoreFailsafeRegistered = $false
    }
    firstConnect = $null
    storedPreference = $null
    secondConnect = $null
    competingVpnTakeover = $null
    cleanup = [ordered]@{
        allManagedComponentsStopped = $false
        publicHealth = $false
        failsafeStopped = $false
        externalVpnRestored = $false
        originalEgressRestored = $false
        restoreFailsafeRemoved = $false
    }
}

$externalVpnWasRunning = $false
$baselineEgressFingerprint = ''
$restoreFailsafeRegistered = $false

try {
    $report.baseline.publicHealth = Test-PublicHealth
    if (-not $report.baseline.publicHealth) {
        throw 'Public connectivity baseline failed.'
    }

    Stop-GreenApp
    try {
        [void](Invoke-GreenLocal -Method POST -Path '/disconnect' -TimeoutSeconds 30)
    } catch {}
    $report.baseline.allManagedComponentsStopped =
        Wait-AllManagedComponentsStopped -TimeoutSeconds 45
    if (-not $report.baseline.allManagedComponentsStopped) {
        throw 'Managed Green VPN components were active before the latency test.'
    }

    $initialPreference = Get-PreferenceEvidence
    $report.baseline.preferredRouteInitiallyPresent =
        [bool]$initialPreference.routePresent
    $report.baseline.preferredRoute = $initialPreference
    if (
        -not $ExpectCompetingVpn -and
        -not $AllowExistingPreferredRoute -and
        $initialPreference.routePresent
    ) {
        throw 'The latency test requires a clean preferred-route state for its first run.'
    }
    if (
        -not $ExpectCompetingVpn -and
        $AllowExistingPreferredRoute -and
        (
            -not $initialPreference.routePresent -or
            -not $initialPreference.protocolPresent -or
            -not $initialPreference.timestampPresent
        )
    ) {
        throw 'The cached-route latency test requires complete preferred-route metadata.'
    }

    if ($TemporarilyStopExternalVpn) {
        $externalVpnWasRunning =
            (Get-ServiceState -Name $ExternalVpnServiceName) -eq 'Running'
        $report.baseline.externalVpnWasRunning = $externalVpnWasRunning
        if (-not $externalVpnWasRunning) {
            throw "$ExternalVpnServiceName must be running before the smoke."
        }
        $baselineEgressFingerprint = Get-EgressFingerprint
        $report.baseline.egressFingerprintCaptured =
            [bool]$baselineEgressFingerprint
        if (-not $baselineEgressFingerprint) {
            throw 'The original egress fingerprint could not be captured.'
        }

        Register-RestoreFailsafe
        $restoreFailsafeRegistered = $true
        $report.baseline.restoreFailsafeRegistered = $true

        Stop-Service -Name $ExternalVpnServiceName -Force -ErrorAction Stop
        if (
            -not (
                Wait-ServiceState `
                    -Name $ExternalVpnServiceName `
                    -State 'Stopped' `
                    -TimeoutSeconds 45
            )
        ) {
            throw "$ExternalVpnServiceName did not stop for the smoke."
        }
        if (-not (Test-PublicHealth)) {
            throw 'Direct connectivity failed after pausing the external VPN.'
        }
    } elseif ($ExpectCompetingVpn) {
        $externalVpnWasRunning =
            (Get-ServiceState -Name $ExternalVpnServiceName) -eq 'Running'
        $report.baseline.externalVpnWasRunning = $externalVpnWasRunning
        if (-not $externalVpnWasRunning) {
            throw "$ExternalVpnServiceName must be running for the competing-VPN smoke."
        }
        $baselineEgressFingerprint = Get-EgressFingerprint
        $report.baseline.egressFingerprintCaptured =
            [bool]$baselineEgressFingerprint
        if (-not $baselineEgressFingerprint) {
            throw 'The original egress fingerprint could not be captured.'
        }
        if (Test-IsAdministrator) {
            Register-RestoreFailsafe
            $restoreFailsafeRegistered = $true
            $report.baseline.restoreFailsafeRegistered = $true
        } else {
            $report.cleanup.restoreFailsafeRemoved = $true
        }
    } else {
        $report.cleanup.externalVpnRestored = $true
        $report.cleanup.originalEgressRestored = $true
        $report.cleanup.restoreFailsafeRemoved = $true
    }

    if ($ExpectCompetingVpn) {
        $report.competingVpnTakeover =
            Invoke-CompetingVpnTakeoverMeasurement -TimeoutSeconds $FirstConnectTimeoutSeconds
        $report.storedPreference = Wait-PreferenceEvidence -TimeoutSeconds 30
        if (
            -not $report.storedPreference.routePresent -or
            -not $report.storedPreference.protocolPresent -or
            -not $report.storedPreference.timestampPresent
        ) {
            throw 'The takeover route was not persisted after the confirmed probe.'
        }
        $takeoverCandidates = @($report.competingVpnTakeover.candidates)
        if ($takeoverCandidates.Count -lt 1) {
            throw 'Competing-VPN takeover did not log its route order.'
        }
        if (
            $null -eq $report.competingVpnTakeover.logSeconds -or
            [double]$report.competingVpnTakeover.logSeconds -gt $MaxFirstConnectSeconds
        ) {
            throw "Competing-VPN takeover exceeded $MaxFirstConnectSeconds seconds."
        }
        if ($AllowExistingPreferredRoute) {
            if (
                $takeoverCandidates.Count -ne 1 -or
                [string]$takeoverCandidates[0].id -ne
                    [string]$initialPreference.routeId -or
                [string]$takeoverCandidates[0].protocol -ne
                    [string]$initialPreference.protocol
            ) {
                throw 'Cached takeover did not use one exact preferred route.'
            }
            $report.competingVpnTakeover.cachedRouteConfirmed = $true
        }
        $report.success = $true
    } else {
        $report.firstConnect = Invoke-ConnectMeasurement `
            -TimeoutSeconds $FirstConnectTimeoutSeconds `
            -Label 'First'

        $report.storedPreference = Wait-PreferenceEvidence -TimeoutSeconds 30
        if (
            -not $report.storedPreference.routePresent -or
            -not $report.storedPreference.protocolPresent -or
            -not $report.storedPreference.timestampPresent
        ) {
            throw 'The successful Windows route was not persisted after the first connection.'
        }

        Stop-GreenApp
        [void](Invoke-GreenLocal -Method POST -Path '/disconnect' -TimeoutSeconds 45)
        if (-not (Wait-AllManagedComponentsStopped -TimeoutSeconds 45)) {
            throw 'Green VPN did not disconnect cleanly between latency measurements.'
        }

        $report.secondConnect = Invoke-ConnectMeasurement `
            -TimeoutSeconds $SecondConnectTimeoutSeconds `
            -Label 'Second'

        $secondCandidates = @($report.secondConnect.candidates)
        if ($secondCandidates.Count -lt 1) {
            throw 'Second connection did not log its route order.'
        }
        if (
            [string]$secondCandidates[0].protocol -ne
            [string]$report.storedPreference.protocol
        ) {
            throw 'Second connection did not prioritize the last successful protocol.'
        }
        if (
            [string]$secondCandidates[0].id -ne
            [string]$report.storedPreference.routeId
        ) {
            throw 'Second connection did not prioritize the exact last successful route.'
        }
        if (
            $null -eq $report.firstConnect.logSeconds -or
            [double]$report.firstConnect.logSeconds -gt $MaxFirstConnectSeconds
        ) {
            throw "First connection exceeded $MaxFirstConnectSeconds seconds."
        }
        if (
            $null -eq $report.secondConnect.logSeconds -or
            [double]$report.secondConnect.logSeconds -gt $MaxCachedConnectSeconds
        ) {
            throw "Cached connection exceeded $MaxCachedConnectSeconds seconds."
        }
        if ($AllowExistingPreferredRoute) {
            $firstCandidates = @($report.firstConnect.candidates)
            if ($firstCandidates.Count -lt 1) {
                throw 'First cached connection did not log its route order.'
            }
            if (
                [string]$firstCandidates[0].id -ne
                    [string]$initialPreference.routeId -or
                [string]$firstCandidates[0].protocol -ne
                    [string]$initialPreference.protocol
            ) {
                throw 'First cached connection did not use the exact seeded route first.'
            }
        }
        if ($AllowExistingPreferredRoute) {
            $report.firstConnect.cachedRouteConfirmed = $true
            $report.secondConnect.cachedRouteConfirmed = $true
        }

        $report.success = $true
    }
} catch {
    $report.failure = $_.Exception.Message
} finally {
    Remove-Item -LiteralPath $pendingActionPath -Force -ErrorAction SilentlyContinue
    Stop-GreenApp
    try {
        [void](Invoke-GreenLocal -Method POST -Path '/disconnect' -TimeoutSeconds 45)
    } catch {}
    try {
        $report.cleanup.allManagedComponentsStopped =
            Wait-AllManagedComponentsStopped -TimeoutSeconds 45
    } catch {}
    if ($TemporarilyStopExternalVpn -and $externalVpnWasRunning) {
        try {
            Start-Service -Name $ExternalVpnServiceName -ErrorAction Stop
            $report.cleanup.externalVpnRestored =
                Wait-ServiceState `
                    -Name $ExternalVpnServiceName `
                    -State 'Running' `
                    -TimeoutSeconds 45
        } catch {}
        Start-Sleep -Seconds 3
        try {
            $restoredEgressFingerprint = Get-EgressFingerprint
            $report.cleanup.originalEgressRestored =
                $baselineEgressFingerprint -and
                $restoredEgressFingerprint -eq $baselineEgressFingerprint
        } catch {}
    } elseif ($ExpectCompetingVpn -and $externalVpnWasRunning) {
        try {
            if (
                (Get-ServiceState -Name $ExternalVpnServiceName) -ne 'Running' -and
                (Test-IsAdministrator)
            ) {
                Start-Service -Name $ExternalVpnServiceName -ErrorAction Stop
            }
            $report.cleanup.externalVpnRestored =
                Wait-ServiceState `
                    -Name $ExternalVpnServiceName `
                    -State 'Running' `
                    -TimeoutSeconds 45
        } catch {}
        Start-Sleep -Seconds 3
        try {
            $restoredEgressFingerprint = Get-EgressFingerprint
            $report.cleanup.originalEgressRestored =
                $baselineEgressFingerprint -and
                $restoredEgressFingerprint -eq $baselineEgressFingerprint
        } catch {}
    }
    $report.cleanup.publicHealth = Test-PublicHealth

    if ($restoreFailsafeRegistered) {
        try {
            Unregister-ScheduledTask `
                -TaskName $failsafeTaskName `
                -Confirm:$false `
                -ErrorAction Stop
            $report.cleanup.restoreFailsafeRemoved = $true
        } catch {}
    }

    if ($FailsafeProcessId -gt 0) {
        try {
            Stop-Process -Id $FailsafeProcessId -Force -ErrorAction Stop
            $report.cleanup.failsafeStopped = $true
        } catch {
            $report.cleanup.failsafeStopped =
                -not [bool](Get-Process -Id $FailsafeProcessId -ErrorAction SilentlyContinue)
        }
    } else {
        $report.cleanup.failsafeStopped = $true
    }

    if (
        -not $report.cleanup.allManagedComponentsStopped -or
        -not $report.cleanup.publicHealth -or
        -not $report.cleanup.failsafeStopped -or
        -not $report.cleanup.externalVpnRestored -or
        -not $report.cleanup.originalEgressRestored -or
        -not $report.cleanup.restoreFailsafeRemoved
    ) {
        $report.success = $false
        if (-not $report.failure) {
            $report.failure = 'Cleanup or ordinary connectivity restoration was not confirmed.'
        }
    }

    $report.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $report | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) {
    throw "Windows connection latency smoke failed. See $ReportPath"
}

$report | ConvertTo-Json -Depth 8
