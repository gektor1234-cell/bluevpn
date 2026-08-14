[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedInstallerSha256,
    [Parameter(Mandatory = $true)][long]$ExpectedInstallerSize,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedAppSha256,
    [Parameter(Mandatory = $true)][long]$ExpectedAppSize,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedAppSoSha256,
    [Parameter(Mandatory = $true)][long]$ExpectedAppSoSize,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedServiceSha256,
    [Parameter(Mandatory = $true)][long]$ExpectedServiceSize,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{40}$')]
    [string]$CandidateSourceCommit,
    [Parameter(Mandatory = $true)][string]$ArtifactRoot,
    [string]$InstallRoot = 'C:\Program Files\Green VPN',
    [string]$ProgramDataRoot = 'C:\ProgramData\BlueVPN',
    [int]$LocalServicePort = 48737,
    [string]$ExternalVpnServiceName = 'AmneziaWGTunnel$device20_full',
    [ValidateRange(90, 600)][int]$InitialDelaySeconds = 90,
    [ValidateRange(600, 1800)][int]$DeadmanDelaySeconds = 900,
    [ValidateRange(10, 120)][int]$MaxConnectSeconds = 30,
    [ValidateRange(15, 120)][int]$MaxModeSwitchSeconds = 60,
    [string]$ExpectedApplicationModeEgress = '5.129.216.42'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$restoreScript = Join-Path $repoRoot 'scripts\windows\restore_windows_smoke_network.ps1'
$resolvedInstaller = [IO.Path]::GetFullPath($InstallerPath)
$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$resolvedProgramDataRoot = [IO.Path]::GetFullPath($ProgramDataRoot).TrimEnd('\')
$resolvedArtifactRoot = [IO.Path]::GetFullPath($ArtifactRoot).TrimEnd('\')
$appPath = Join-Path $resolvedInstallRoot 'greenvpn.exe'
$appSoPath = Join-Path $resolvedInstallRoot 'data\app.so'
$servicePath = Join-Path $resolvedInstallRoot 'greenvpn_service.exe'
$tokenPath = Join-Path $resolvedProgramDataRoot 'service_token'
$authLogPath = Join-Path $resolvedProgramDataRoot 'auth.log'
$routingModePath = Join-Path $resolvedProgramDataRoot 'routing_mode'
$routingAppsPath = Join-Path $resolvedProgramDataRoot 'routing_apps.json'
$runtimeRegistryPath = 'HKLM:\SOFTWARE\GreenVPN\Runtime\stable'
$summaryPath = Join-Path $resolvedArtifactRoot 'windows-mode-reconcile-autonomous-summary.json'
$logPath = Join-Path $resolvedArtifactRoot 'windows-mode-reconcile-autonomous.log'
$diagnosticPath = Join-Path $resolvedArtifactRoot 'windows-fusion-ui-state.json'
$runtimeEvidencePath = Join-Path $resolvedArtifactRoot 'windows-mode-runtime-evidence.json'
$recoveryReportPath = Join-Path $resolvedArtifactRoot 'windows-mode-reconcile-final-recovery.json'
$deadmanReportPath = Join-Path $resolvedArtifactRoot 'windows-mode-reconcile-deadman-recovery.json'
$externalScreenshotPath = Join-Path $resolvedArtifactRoot 'windows-mode-external-vpn.png'
$fullScreenshotPath = Join-Path $resolvedArtifactRoot 'windows-mode-full.png'
$selectedScreenshotPath = Join-Path $resolvedArtifactRoot 'windows-mode-selected.png'
$returnedFullScreenshotPath = Join-Path $resolvedArtifactRoot 'windows-mode-returned-full.png'
$originalAppData = $env:APPDATA
$originalUserStateRoot = Join-Path $originalAppData 'GreenVPN\state'
$privateScratchRoot = Join-Path $env:TEMP (
    'GreenVPNModeReconcile_' + [guid]::NewGuid().ToString('N')
)
$isolatedAppDataRoot = Join-Path $privateScratchRoot 'AppData'
$isolatedUserStateRoot = Join-Path $isolatedAppDataRoot 'GreenVPN\state'
$selectedExecutable = Join-Path $env:SystemRoot 'System32\curl.exe'
$directControlExecutable = Join-Path $privateScratchRoot 'probe-lanes\curl-unselected-control.exe'
$applicationProxyHost = '10.10.0.1'
$applicationProxyPort = 1080
$probeRecoveryReserveSeconds = 180
$selectedModeProbeMinimumSeconds = 120
$failsafeTaskNames = @(
    'GreenVPNConnectLatencySmokeFailsafe',
    'GreenVPNPublicRuntimeFailoverSmokeFailsafe',
    'GreenVPNModeReconcileSmokeFailsafe'
)
$managedComponentKeys = @(
    'wireGuardState', 'amneziaWgState', 'hysteriaClientState',
    'hysteriaTunState', 'vlessClientState', 'vlessTunState',
    'naiveClientState', 'naiveTunState', 'dnsttClientState',
    'dnsttTunState', 'processRouterState'
)
$expectedInstallerHash = $ExpectedInstallerSha256.ToUpperInvariant()
$expectedAppHash = $ExpectedAppSha256.ToUpperInvariant()
$expectedAppSoHash = $ExpectedAppSoSha256.ToUpperInvariant()
$expectedServiceHash = $ExpectedServiceSha256.ToUpperInvariant()
$mutex = [Threading.Mutex]::new($false, 'Local\GreenVPNModeReconcileReleaseSmoke')
$mutexAcquired = $false
$deadman = $null
$deadmanDeadlineUtc = $null
$runtimeEvidenceHistory = [Collections.Generic.List[object]]::new()

New-Item -ItemType Directory -Force -Path $resolvedArtifactRoot | Out-Null

function Write-RunnerLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value (
        "[$((Get-Date).ToUniversalTime().ToString('o'))] $Message"
    )
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Get-ServiceState {
    param([Parameter(Mandatory = $true)][string]$Name)
    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $service) { return 'Missing' }
    return [string]$service.Status
}

function Test-HttpStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][int]$ExpectedStatus
    )
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 15
        return [int]$response.StatusCode -eq $ExpectedStatus
    } catch { return $false }
}

function Get-LocalToken {
    if (-not (Test-Path -LiteralPath $tokenPath -PathType Leaf)) { return '' }
    try {
        $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
        return $(if ($token.Length -ge 24) { $token } else { '' })
    } catch { return '' }
}

function Invoke-GreenLocal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$TimeoutSeconds = 30
    )
    $token = Get-LocalToken
    if (-not $token) { throw 'Green VPN local service token is unavailable.' }
    return Invoke-RestMethod -Method $Method `
        -Uri "http://127.0.0.1:$LocalServicePort$Path" `
        -Headers @{ 'X-GreenVPN-Local-Token' = $token } `
        -ContentType 'application/json' `
        -Body $(if ($Method -eq 'POST') { '{}' } else { $null }) `
        -TimeoutSec $TimeoutSeconds
}

function Test-GreenComponentsStopped {
    try {
        $status = Invoke-GreenLocal -Method GET -Path '/status' -TimeoutSeconds 8
        foreach ($key in $managedComponentKeys) {
            if (([string]$status.$key).Trim().ToLowerInvariant() -notin @(
                'missing', 'stopped'
            )) { return $false }
        }
        return $true
    } catch { return $false }
}

function Test-BetaComponentsStopped {
    $root = 'C:\ProgramData\BlueVPNBeta'
    $betaTokenPath = Join-Path $root 'service_token'
    if (-not (Test-Path -LiteralPath $betaTokenPath -PathType Leaf)) { return $true }
    try {
        $token = (Get-Content -LiteralPath $betaTokenPath -Raw).Trim()
        if ($token.Length -lt 24) { return $false }
        $status = Invoke-RestMethod -Method Get `
            -Uri 'http://127.0.0.1:48738/status' `
            -Headers @{ 'X-GreenVPN-Local-Token' = $token } `
            -TimeoutSec 8
        foreach ($key in $managedComponentKeys) {
            if (([string]$status.$key).Trim().ToLowerInvariant() -notin @(
                'missing', 'stopped'
            )) { return $false }
        }
        return $true
    } catch { return $false }
}

function Get-ExactGreenProcesses {
    return @(
        Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    [IO.Path]::GetFullPath([string]$_.Path) -ieq $appPath
                } catch { $false }
            }
    )
}

function Stop-GreenUi {
    if (Test-Path -LiteralPath $appPath -PathType Leaf) {
        try {
            $shutdown = Start-Process -FilePath $appPath `
                -ArgumentList @('--shutdown-existing', '--background') `
                -WorkingDirectory $resolvedInstallRoot -WindowStyle Hidden `
                -PassThru
            [void]$shutdown.WaitForExit(15000)
        } catch {}
    }
    $deadline = (Get-Date).AddSeconds(15)
    do {
        if (@(Get-ExactGreenProcesses).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    foreach ($process in @(Get-ExactGreenProcesses)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
    return @(Get-ExactGreenProcesses).Count -eq 0
}

function Stop-BetaUi {
    $betaPath = 'C:\Program Files\Green VPN Beta\greenvpn_beta.exe'
    $betaProcesses = @(
        Get-Process -Name 'greenvpn_beta' -ErrorAction SilentlyContinue
    )
    if ($betaProcesses.Count -eq 0) { return $true }
    if (Test-Path -LiteralPath $betaPath -PathType Leaf) {
        try {
            $shutdown = Start-Process -FilePath $betaPath `
                -ArgumentList @('--shutdown-existing', '--background') `
                -WorkingDirectory (Split-Path -Parent $betaPath) `
                -WindowStyle Hidden -PassThru
            [void]$shutdown.WaitForExit(15000)
        } catch {}
    }
    Start-Sleep -Milliseconds 500
    foreach ($process in @(
        Get-Process -Name 'greenvpn_beta' -ErrorAction SilentlyContinue
    )) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    return @(Get-Process -Name 'greenvpn_beta' -ErrorAction SilentlyContinue).Count -eq 0
}

function Get-ReadOnlyBaseline {
    return [ordered]@{
        greenComponentsStopped = Test-GreenComponentsStopped
        betaComponentsStopped = Test-BetaComponentsStopped
        externalVpnRunning =
            (Get-ServiceState -Name $ExternalVpnServiceName) -eq 'Running'
        publicHealth = Test-HttpStatus `
            -Url 'https://api.greenvpn.pro/healthz' -ExpectedStatus 200
        youtube = Test-HttpStatus `
            -Url 'https://www.youtube.com/generate_204' -ExpectedStatus 204
        noProbeMetricRoutes = @(
            Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
                [int]$_.RouteMetric -eq 42739
            }
        ).Count -eq 0
        noFailsafes = @(
            $failsafeTaskNames | Where-Object {
                Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue
            }
        ).Count -eq 0
    }
}

function Assert-ReadOnlySafeBaseline {
    param([Parameter(Mandatory = $true)][string]$Label)
    $baseline = Get-ReadOnlyBaseline
    $baseline['success'] = @(
        $baseline.Values | Where-Object { -not [bool]$_ }
    ).Count -eq 0
    if (-not [bool]$baseline.success) {
        throw "$Label failed: $($baseline | ConvertTo-Json -Compress)."
    }
    return $baseline
}

function Assert-MutableSafeBaseline {
    param([Parameter(Mandatory = $true)][string]$Label)
    if (-not (Stop-BetaUi)) { throw "${Label}: Beta UI did not stop." }
    if (-not (Stop-GreenUi)) { throw "${Label}: stable UI did not stop." }
    try { [void](Invoke-GreenLocal -Method POST -Path '/disconnect' -TimeoutSeconds 45) } catch {}
    if (-not (Test-GreenComponentsStopped) -or -not (Test-BetaComponentsStopped)) {
        throw "${Label}: managed Green components are not fully stopped."
    }
    if ((Get-ServiceState -Name $ExternalVpnServiceName) -ne 'Running') {
        throw "${Label}: $ExternalVpnServiceName is not running."
    }
    if (-not (Test-HttpStatus -Url 'https://api.greenvpn.pro/healthz' -ExpectedStatus 200)) {
        throw "${Label}: public API probe failed."
    }
    if (-not (Test-HttpStatus -Url 'https://www.youtube.com/generate_204' -ExpectedStatus 204)) {
        throw "${Label}: YouTube probe failed."
    }
}

function Start-DeadmanRecovery {
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$restoreScript`"",
        '-InstallRoot', "`"$resolvedInstallRoot`"",
        '-ProgramDataRoot', "`"$resolvedProgramDataRoot`"",
        '-LocalServicePort', [string]$LocalServicePort,
        '-ExternalVpnServiceName', "`"$ExternalVpnServiceName`"",
        '-StopGreenUi',
        '-DelaySeconds', [string]$DeadmanDelaySeconds,
        '-ReportPath', "`"$deadmanReportPath`""
    )
    return Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments `
        -WindowStyle Hidden -PassThru
}

function Invoke-FinalRecovery {
    try {
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
            -File $restoreScript `
            -InstallRoot $resolvedInstallRoot `
            -ProgramDataRoot $resolvedProgramDataRoot `
            -LocalServicePort $LocalServicePort `
            -ExternalVpnServiceName $ExternalVpnServiceName `
            -StopGreenUi `
            -ReportPath $recoveryReportPath | Out-Null
    } catch {}
    if (-not (Test-Path -LiteralPath $recoveryReportPath -PathType Leaf)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $recoveryReportPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    } catch { return $null }
}

function Install-ExactCandidate {
    $item = Get-Item -LiteralPath $resolvedInstaller -ErrorAction Stop
    $hash = (Get-FileHash -LiteralPath $resolvedInstaller -Algorithm SHA256).Hash
    if ($hash -ne $expectedInstallerHash -or
            [long]$item.Length -ne $ExpectedInstallerSize) {
        throw 'Exact installer SHA-256 or size mismatch.'
    }
    if (-not (Stop-GreenUi)) { throw 'Stable UI did not stop before install.' }
    $oldAutoClose = $env:GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS
    $oldSkipLaunch = $env:GREENVPN_INSTALLER_SKIP_APP_LAUNCH
    try {
        $env:GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS = '1'
        $env:GREENVPN_INSTALLER_SKIP_APP_LAUNCH = '1'
        $installer = Start-Process -FilePath $resolvedInstaller -PassThru -Wait
    } finally {
        $env:GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS = $oldAutoClose
        $env:GREENVPN_INSTALLER_SKIP_APP_LAUNCH = $oldSkipLaunch
    }
    if ($installer.ExitCode -ne 0) {
        throw "Installer returned exit code $($installer.ExitCode)."
    }
    $files = @(
        [pscustomobject]@{
            kind = 'app'; path = $appPath; size = $ExpectedAppSize
            hash = $expectedAppHash
        },
        [pscustomobject]@{
            kind = 'appSo'; path = $appSoPath; size = $ExpectedAppSoSize
            hash = $expectedAppSoHash
        },
        [pscustomobject]@{
            kind = 'service'; path = $servicePath; size = $ExpectedServiceSize
            hash = $expectedServiceHash
        }
    )
    $payload = @()
    foreach ($file in $files) {
        $installed = Get-Item -LiteralPath $file.path -ErrorAction Stop
        $installedHash = (Get-FileHash -LiteralPath $file.path -Algorithm SHA256).Hash
        if ([long]$installed.Length -ne [long]$file.size -or
                $installedHash -ne [string]$file.hash) {
            throw "Installed $($file.kind) identity mismatch."
        }
        $payload += [ordered]@{
            kind = $file.kind
            path = $file.path
            size = [long]$installed.Length
            sha256 = $installedHash
        }
    }
    $app = Get-Item -LiteralPath $appPath
    if ([string]$app.VersionInfo.FileVersion -ne $ExpectedVersion) {
        throw "Installed file version mismatch: $($app.VersionInfo.FileVersion)."
    }
    return [ordered]@{
        path = $resolvedInstaller
        size = [long]$item.Length
        sha256 = $hash
        signatureStatus =
            (Get-AuthenticodeSignature -LiteralPath $resolvedInstaller).Status.ToString()
        installedVersion = [string]$app.VersionInfo.FileVersion
        payload = @($payload)
    }
}

function Initialize-IsolatedUserState {
    foreach ($required in @('session.dat', 'prefs.json')) {
        $source = Join-Path $originalUserStateRoot $required
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Authenticated owner state is missing: $required"
        }
    }
    New-Item -ItemType Directory -Force -Path $isolatedUserStateRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $originalUserStateRoot 'session.dat') `
        -Destination (Join-Path $isolatedUserStateRoot 'session.dat') -Force
    $prefs = Get-Content -LiteralPath (Join-Path $originalUserStateRoot 'prefs.json') `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    $prefs.socialOnlyEnabled = $false
    $prefs.socialOnlyWindowsApplications = @($selectedExecutable)
    $prefs.socialOnlyWindowsSites = @()
    $prefs.socialOnlyApps = @('telegram', 'instagram')
    $prefs.vpnPauseUntil = ''
    $prefs | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $isolatedUserStateRoot 'prefs.json') `
            -Encoding UTF8
    return [ordered]@{
        sessionCopied = $true
        prefsSeeded = $true
        selectedExecutable = $selectedExecutable
        originalStateUnmodified = $true
    }
}

function Get-AuthLogLineCount {
    if (-not (Test-Path -LiteralPath $authLogPath -PathType Leaf)) { return 0 }
    return @(Get-Content -LiteralPath $authLogPath -Encoding UTF8).Count
}

function Get-NewAuthLogLines {
    param([Parameter(Mandatory = $true)][int]$AfterLine)
    if (-not (Test-Path -LiteralPath $authLogPath -PathType Leaf)) { return @() }
    $lines = @(Get-Content -LiteralPath $authLogPath -Encoding UTF8)
    if ($lines.Count -le $AfterLine) { return @() }
    return @($lines[$AfterLine..($lines.Count - 1)])
}

function Get-LogTimestamp {
    param([Parameter(Mandatory = $true)][string]$Line)
    if ($Line -notmatch '^\[([^\]]+)\]') { return $null }
    return [datetimeoffset]::Parse($Matches[1])
}

function Get-UiDiagnostic {
    if (-not (Test-Path -LiteralPath $diagnosticPath -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $diagnosticPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    } catch { return $null }
}

function Wait-UiDiagnostic {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Predicate,
        [int]$TimeoutSeconds = 60,
        [string]$Label = 'Fusion UI state'
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $snapshot = Get-UiDiagnostic
        if ($null -ne $snapshot -and (& $Predicate $snapshot)) { return $snapshot }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "$Label was not confirmed within $TimeoutSeconds seconds."
}

function Wait-WindowReady {
    param([Parameter(Mandatory = $true)][Diagnostics.Process]$Process)
    $deadline = (Get-Date).AddSeconds(60)
    do {
        $Process.Refresh()
        if ($Process.HasExited) { throw 'Green VPN exited before window readiness.' }
        if ($Process.MainWindowHandle -ne 0) { return }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw 'Green VPN did not expose its main window.'
}

function Initialize-UiInput {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if (-not ('GreenVpnModeSmokeInput' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class GreenVpnModeSmokeInput {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

    public static bool ClickNormalized(IntPtr hWnd, double x, double y) {
        RECT rect; POINT original;
        if (!GetClientRect(hWnd, out rect) || !GetCursorPos(out original)) return false;
        var point = new POINT {
            X = Math.Max(1, (int)Math.Round((rect.Right - rect.Left) * x)),
            Y = Math.Max(1, (int)Math.Round((rect.Bottom - rect.Top) * y))
        };
        if (!ClientToScreen(hWnd, ref point)) return false;
        ShowWindow(hWnd, 9);
        for (var attempt = 0; attempt < 20; attempt++) {
            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
            if (GetForegroundWindow() == hWnd) break;
            Thread.Sleep(100);
        }
        if (!SetCursorPos(point.X, point.Y)) return false;
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
        SetCursorPos(original.X, original.Y);
        return true;
    }
}
'@
    }
}

function Invoke-NormalizedClick {
    param(
        [Parameter(Mandatory = $true)][Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][double]$X,
        [Parameter(Mandatory = $true)][double]$Y,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $Process.Refresh()
    if ($Process.HasExited -or $Process.MainWindowHandle -eq 0) {
        throw "$Label cannot run because the app window is unavailable."
    }
    $shell = New-Object -ComObject WScript.Shell
    [void]$shell.AppActivate($Process.Id)
    Start-Sleep -Milliseconds 400
    if (-not [GreenVpnModeSmokeInput]::ClickNormalized(
            $Process.MainWindowHandle, $X, $Y
        )) {
        throw "$Label coordinate click failed."
    }
}

function Get-WindowScreenshot {
    param(
        [Parameter(Mandatory = $true)][Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $Process.Refresh()
    $rect = New-Object GreenVpnModeSmokeInput+RECT
    if (-not [GreenVpnModeSmokeInput]::GetWindowRect(
            $Process.MainWindowHandle, [ref]$rect
        )) { throw 'Unable to read the app window rectangle.' }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -lt 900 -or $height -lt 650) {
        throw "Unexpected app window size: ${width}x${height}."
    }
    $bitmap = New-Object Drawing.Bitmap $width, $height
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
        $distinct = [Collections.Generic.HashSet[int]]::new()
        $nonBlack = 0
        for ($x = 0; $x -lt $width; $x += 12) {
            for ($y = 0; $y -lt $height; $y += 12) {
                $color = $bitmap.GetPixel($x, $y)
                [void]$distinct.Add($color.ToArgb())
                if ($color.R -gt 20 -or $color.G -gt 20 -or $color.B -gt 20) {
                    $nonBlack++
                }
            }
        }
        if ($distinct.Count -lt 40 -or $nonBlack -lt 500) {
            throw 'Window screenshot failed the nonblank visual contract.'
        }
        return [ordered]@{
            path = $Path
            width = $width
            height = $height
            distinctColorCount = $distinct.Count
            nonBlackSampleCount = $nonBlack
            visualContractPassed = $true
        }
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Get-EgressFingerprint {
    param(
        [switch]$UseSelectedExecutable,
        [string]$ExecutablePath = '',
        [ValidateSet('Any', 'IPv4', 'IPv6')][string]$AddressFamily = 'Any'
    )
    $familyArgument = switch ($AddressFamily) {
        'IPv4' { '-4' }
        'IPv6' { '-6' }
        default { '' }
    }
    foreach ($url in @('https://api.ipify.org', 'https://ifconfig.me/ip')) {
        $value = ''
        try {
            if ($UseSelectedExecutable -or -not [string]::IsNullOrWhiteSpace($ExecutablePath)) {
                $curlPath = if ($ExecutablePath) { $ExecutablePath } else { $selectedExecutable }
                $arguments = @(
                    '--silent', '--show-error', '--fail', '--http1.1',
                    '--connect-timeout', '8', '--max-time', '15'
                )
                if ($familyArgument) { $arguments += $familyArgument }
                $arguments += $url
                $rawValue = & $curlPath @arguments 2>$null |
                    Select-Object -First 1
                if ($LASTEXITCODE -ne 0 -or $null -eq $rawValue) { continue }
                $value = ([string]$rawValue).Trim()
            } else {
                $value = (Invoke-RestMethod -Uri $url -TimeoutSec 15).ToString().Trim()
            }
            if (-not $value) { continue }
            $address = $null
            if (-not [Net.IPAddress]::TryParse($value, [ref]$address)) { continue }
            if (
                ($AddressFamily -eq 'IPv4' -and
                    $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) -or
                ($AddressFamily -eq 'IPv6' -and
                    $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetworkV6)
            ) { continue }
            $bytes = [Text.Encoding]::UTF8.GetBytes($value)
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
            } finally {
                $sha.Dispose()
                [Array]::Clear($bytes, 0, $bytes.Length)
                $value = $null
            }
        } catch { $value = $null }
    }
    return ''
}

function Get-StringSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Get-SelectedYouTubeProbe {
    try {
        $status = & $selectedExecutable @(
            '--silent', '--show-error', '--output', 'NUL',
            '--write-out', '%{http_code}', '--http1.1',
            '--connect-timeout', '8', '--max-time', '20',
            'https://www.youtube.com/generate_204'
        ) 2>$null
        return $LASTEXITCODE -eq 0 -and ([string]$status).Trim() -eq '204'
    } catch {
        return $false
    }
}

function Test-DirectIpv6Available {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)

    return [bool](Get-EgressFingerprint `
        -ExecutablePath $ExecutablePath -AddressFamily IPv6)
}

function Get-RuntimeRegistryEvidence {
    $values = Get-ItemProperty -LiteralPath $runtimeRegistryPath `
        -ErrorAction SilentlyContinue
    $valueNames = if ($null -ne $values) {
        @($values.PSObject.Properties.Name)
    } else {
        @()
    }
    $registryKey = Get-Item -LiteralPath $runtimeRegistryPath `
        -ErrorAction SilentlyContinue
    $processRouterRequiredKind = if (
        $null -ne $registryKey -and
        $valueNames -contains 'ProcessRouterRequired'
    ) {
        [string]$registryKey.GetValueKind('ProcessRouterRequired')
    } else { '' }
    $processRouterPidKind = if (
        $null -ne $registryKey -and
        $valueNames -contains 'ProcessRouterPid'
    ) {
        [string]$registryKey.GetValueKind('ProcessRouterPid')
    } else { '' }
    $runtimeGenerationKind = if (
        $null -ne $registryKey -and
        $valueNames -contains 'RuntimeStateGeneration'
    ) {
        [string]$registryKey.GetValueKind('RuntimeStateGeneration')
    } else { '' }
    $pidValue = 0
    $pidValueParsed = $false
    if ($valueNames -contains 'ProcessRouterPid') {
        $pidValueParsed = [int]::TryParse(
            [string]$values.ProcessRouterPid,
            [ref]$pidValue
        ) -and $pidValue -gt 0
    }
    $requiredValue = 0
    $requiredValueParsed = $false
    if ($valueNames -contains 'ProcessRouterRequired') {
        $requiredValueParsed = [int]::TryParse(
            [string]$values.ProcessRouterRequired,
            [ref]$requiredValue
        )
    }
    $runtimeGeneration = [uint32]0
    $runtimeGenerationParsed = $false
    if ($valueNames -contains 'RuntimeStateGeneration') {
        $runtimeGenerationParsed = [uint32]::TryParse(
            [string]$values.RuntimeStateGeneration,
            [ref]$runtimeGeneration
        )
    }
    $expectedProcessPath = Join-Path $resolvedInstallRoot `
        'tools\process-router\ProxyBridge_CLI.exe'
    $processPath = ''
    if ($pidValue -gt 0) {
        try {
            $processPath = [IO.Path]::GetFullPath(
                [string](Get-Process -Id $pidValue -ErrorAction Stop).Path
            )
        } catch {}
    }
    $exactProcesses = @(
        Get-Process -Name 'ProxyBridge_CLI' -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    [IO.Path]::GetFullPath([string]$_.Path).Equals(
                        [IO.Path]::GetFullPath($expectedProcessPath),
                        [StringComparison]::OrdinalIgnoreCase
                    )
                } catch { $false }
            }
    )
    return [ordered]@{
        activeRoutingMode = if ($valueNames -contains 'ActiveRoutingMode') {
            [string]$values.ActiveRoutingMode
        } else { '' }
        processRouterRequirementKnown =
            $valueNames -contains 'ProcessRouterRequired'
        processRouterRequirementValueKind = $processRouterRequiredKind
        processRouterRequirementValueParsed = $requiredValueParsed
        processRouterRequired = $requiredValue
        processRouterPidKnown = $pidValueParsed
        processRouterPidValuePresent =
            $valueNames -contains 'ProcessRouterPid'
        processRouterPidValueKind = $processRouterPidKind
        processRouterExactProcessCount = $exactProcesses.Count
        processRouterRunning = $exactProcesses.Count -gt 0
        processRouterPidMatchesExactProcess =
            $pidValueParsed -and
            $exactProcesses.Count -eq 1 -and
            [int]$exactProcesses[0].Id -eq $pidValue -and
            [bool]$processPath
        runtimeStateGenerationKnown =
            $valueNames -contains 'RuntimeStateGeneration'
        runtimeStateGenerationValueKind = $runtimeGenerationKind
        runtimeStateGenerationValueParsed = $runtimeGenerationParsed
        runtimeStateGeneration = $runtimeGeneration
        runtimeStateGenerationEven =
            $runtimeGenerationParsed -and ($runtimeGeneration % 2) -eq 0
    }
}

function Capture-RuntimeEvidence {
    param([Parameter(Mandatory = $true)][string]$Label)

    $status = $null
    $statusError = $null
    try {
        $status = Invoke-GreenLocal -Method GET -Path '/status' -TimeoutSeconds 8
    } catch {
        $statusError = $_.Exception.Message
    }
    $evidence = [ordered]@{
        capturedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        label = $Label
        serviceRequestOk = $null -ne $status
        serviceError = $statusError
        service = if ($null -eq $status) { $null } else {
            [ordered]@{
                ok = [bool]$status.ok
                tunnelState = [string]$status.tunnelState
                wireGuardState = [string]$status.wireGuardState
                amneziaWgState = [string]$status.amneziaWgState
                hysteriaClientState = [string]$status.hysteriaClientState
                hysteriaTunState = [string]$status.hysteriaTunState
                vlessClientState = [string]$status.vlessClientState
                vlessTunState = [string]$status.vlessTunState
                naiveClientState = [string]$status.naiveClientState
                naiveTunState = [string]$status.naiveTunState
                dnsttClientState = [string]$status.dnsttClientState
                dnsttTunState = [string]$status.dnsttTunState
                routingMode = [string]$status.routingMode
                processRouterState = [string]$status.processRouterState
                processRouterRequirementKnown =
                    [bool]$status.processRouterRequirementKnown
                processRouterRequired = [bool]$status.processRouterRequired
                runtimeStateGenerationKnown =
                    [bool]$status.runtimeStateGenerationKnown
                runtimeStateGeneration =
                    [uint32]$status.runtimeStateGeneration
                runtimeStateConsistent =
                    [bool]$status.runtimeStateConsistent
                externalVpnStateKnown = [bool]$status.externalVpnStateKnown
                externalVpnActive = [bool]$status.externalVpnActive
            }
        }
        registry = Get-RuntimeRegistryEvidence
        ui = Get-UiDiagnostic
    }
    $runtimeEvidenceHistory.Add($evidence)
    ConvertTo-Json `
        -InputObject ([object[]]$runtimeEvidenceHistory.ToArray()) `
        -Depth 12 |
        Set-Content -LiteralPath $runtimeEvidencePath -Encoding UTF8
    return $evidence
}

function Assert-RuntimeMode {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('full', 'applications')][string]$Mode,
        [Parameter(Mandatory = $true)][bool]$ProcessRouterRequired
    )
    $status = Invoke-GreenLocal -Method GET -Path '/status' -TimeoutSeconds 8
    if ([string]$status.tunnelState -ne 'running' -or
            [string]$status.routingMode -ne $Mode -or
            $status.runtimeStateGenerationKnown -ne $true -or
            $status.runtimeStateConsistent -ne $true -or
            ([uint32]$status.runtimeStateGeneration % 2) -ne 0 -or
            $status.externalVpnStateKnown -ne $true -or
            $status.externalVpnActive -eq $true -or
            $status.processRouterRequirementKnown -ne $true -or
            [bool]$status.processRouterRequired -ne $ProcessRouterRequired) {
        throw "Privileged service did not confirm exact $Mode state."
    }
    $expectedRouterState = if ($ProcessRouterRequired) { 'running' } else { 'missing' }
    if ([string]$status.processRouterState -ne $expectedRouterState) {
        if (-not $ProcessRouterRequired -and
                [string]$status.processRouterState -eq 'stopped') {
            # Stopped is also an exact inactive router state.
        } else {
            throw "Unexpected process router state in ${Mode}: $($status.processRouterState)."
        }
    }
    $registry = Get-RuntimeRegistryEvidence
    if ([string]$registry.activeRoutingMode -ne $Mode -or
            [string]$registry.runtimeStateGenerationValueKind -ne 'DWord' -or
            -not [bool]$registry.runtimeStateGenerationValueParsed -or
            -not [bool]$registry.runtimeStateGenerationEven -or
            [uint32]$registry.runtimeStateGeneration -ne
                [uint32]$status.runtimeStateGeneration -or
            [string]$registry.processRouterRequirementValueKind -ne 'DWord' -or
            -not [bool]$registry.processRouterRequirementValueParsed -or
            [int]$registry.processRouterRequired -notin @(0, 1) -or
            [bool]$registry.processRouterRunning -ne $ProcessRouterRequired -or
            [bool]([int]$registry.processRouterRequired -eq 1) -ne
                $ProcessRouterRequired) {
        throw "HKLM runtime registry did not confirm exact $Mode state."
    }
    if ($ProcessRouterRequired -and (
            [string]$registry.processRouterPidValueKind -ne 'DWord' -or
            -not [bool]$registry.processRouterPidKnown -or
            -not [bool]$registry.processRouterPidMatchesExactProcess
        )) {
        throw "HKLM process router identity did not confirm exact $Mode state."
    }
    if (-not $ProcessRouterRequired -and (
            [bool]$registry.processRouterPidKnown -or
            [bool]$registry.processRouterPidValuePresent
        )) {
        throw "HKLM retained a process router PID in exact $Mode state."
    }
    return [ordered]@{
        tunnelState = [string]$status.tunnelState
        routingMode = [string]$status.routingMode
        runtimeStateGenerationKnown =
            [bool]$status.runtimeStateGenerationKnown
        runtimeStateGeneration = [uint32]$status.runtimeStateGeneration
        runtimeStateConsistent = [bool]$status.runtimeStateConsistent
        externalVpnStateKnown = [bool]$status.externalVpnStateKnown
        externalVpnActive = [bool]$status.externalVpnActive
        processRouterRequirementKnown = [bool]$status.processRouterRequirementKnown
        processRouterRequired = [bool]$status.processRouterRequired
        processRouterState = [string]$status.processRouterState
        registry = $registry
    }
}

function Wait-AuthLogMarker {
    param(
        [Parameter(Mandatory = $true)][int]$AfterLine,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$TimeoutSeconds = 60
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $match = Get-NewAuthLogLines -AfterLine $AfterLine |
            Where-Object { $_ -match $Pattern } |
            Select-Object -First 1
        if ($match) { return [string]$match }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Auth log marker was not observed: $Pattern"
}

function Invoke-ForegroundConnect {
    param([Parameter(Mandatory = $true)][Diagnostics.Process]$Process)
    $afterLine = Get-AuthLogLineCount
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $deadline = (Get-Date).AddSeconds($MaxConnectSeconds)
    Invoke-NormalizedClick -Process $Process -X 0.52 -Y 0.255 `
        -Label 'Fusion connect'
    $requested = Wait-AuthLogMarker -AfterLine $afterLine `
        -Pattern 'UI toggle requested' -TimeoutSeconds 8
    $remainingProbeSeconds = [Math]::Max(
        1,
        [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
    )
    $probe = Wait-AuthLogMarker -AfterLine $afterLine `
        -Pattern 'UI post connect probe .* status=\d+ ok=true' `
        -TimeoutSeconds $remainingProbeSeconds
    $runtime = Assert-RuntimeMode -Mode full -ProcessRouterRequired $false
    $runtimeAfterProbe = Capture-RuntimeEvidence `
        -Label 'foreground_after_data_plane_probe'
    $remainingUiSeconds = [Math]::Max(
        1,
        [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
    )
    $ui = Wait-UiDiagnostic -TimeoutSeconds $remainingUiSeconds `
        -Label 'Full-mode protected UI' `
        -Predicate {
            param($state)
            [string]$state.statusKey -eq 'protected_full' -and
                [bool]$state.protectionActive -and
                [bool]$state.connectedCheckVisible -and
                [bool]$state.windowsFullTunnelDataPlaneConfirmed -and
                -not [bool]$state.socialOnlyEnabled
        }
    $watch.Stop()
    $requestedAt = Get-LogTimestamp -Line $requested
    $probeAt = Get-LogTimestamp -Line $probe
    $logSeconds = if ($requestedAt -and $probeAt) {
        [Math]::Round(($probeAt - $requestedAt).TotalSeconds, 3)
    } else { $null }
    if ($null -eq $logSeconds -or
            [double]$logSeconds -gt $MaxConnectSeconds -or
            $watch.Elapsed.TotalSeconds -gt $MaxConnectSeconds) {
        throw "Foreground connect exceeded $MaxConnectSeconds seconds."
    }
    $candidates = @(
        Get-NewAuthLogLines -AfterLine $afterLine | Where-Object {
            $_ -match 'UI toggle connect candidate \d+/\d+'
        }
    )
    if ($candidates.Count -ne 1) {
        throw "Foreground connect logged $($candidates.Count) candidates; expected one."
    }
    if ((Get-ServiceState -Name $ExternalVpnServiceName) -ne 'Stopped') {
        throw 'Green VPN did not take over from the external VPN service.'
    }
    return [ordered]@{
        wallSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
        logSeconds = $logSeconds
        oneCandidate = $true
        probeConfirmed = $true
        privilegedTakeoverConfirmed = $true
        runtimeAfterProbe = $runtimeAfterProbe
        ui = $ui
        runtime = $runtime
    }
}

function Invoke-ModeSwitch {
    param(
        [Parameter(Mandatory = $true)][Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)]
        [ValidateSet('full', 'applications')][string]$Mode
    )
    $afterLine = Get-AuthLogLineCount
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $deadline = (Get-Date).AddSeconds($MaxModeSwitchSeconds)
    Invoke-NormalizedClick -Process $Process `
        -X $(if ($Mode -eq 'applications') { 0.875 } else { 0.695 }) `
        -Y 0.255 -Label "Fusion mode $Mode"
    $requested = Wait-AuthLogMarker -AfterLine $afterLine `
        -Pattern "routing preference requested .* to=$Mode" `
        -TimeoutSeconds 8
    $remainingConfirmSeconds = [Math]::Max(
        1,
        [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
    )
    $confirmed = Wait-AuthLogMarker -AfterLine $afterLine `
        -Pattern "routing preference confirmed mode=$Mode" `
        -TimeoutSeconds $remainingConfirmSeconds
    $expectedStatusKey = if ($Mode -eq 'applications') {
        'protected_selected'
    } else { 'protected_full' }
    $expectedRouter = $Mode -eq 'applications'
    $runtime = Assert-RuntimeMode -Mode $Mode `
        -ProcessRouterRequired $expectedRouter
    $remainingUiSeconds = [Math]::Max(
        1,
        [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
    )
    $ui = Wait-UiDiagnostic -TimeoutSeconds $remainingUiSeconds `
        -Label "$Mode protected UI" -Predicate {
            param($state)
            [string]$state.statusKey -eq $expectedStatusKey -and
                [bool]$state.protectionActive -and
                [bool]$state.connectedCheckVisible -and
                [bool]$state.socialOnlyEnabled -eq ($Mode -eq 'applications') -and
                [bool]$state.processRouterRequired -eq $expectedRouter
        }
    $runtimeAfterUi = Capture-RuntimeEvidence -Label "${Mode}_after_ui_confirmation"
    $watch.Stop()
    $requestedAt = Get-LogTimestamp -Line $requested
    $confirmedAt = Get-LogTimestamp -Line $confirmed
    $logSeconds = if ($requestedAt -and $confirmedAt) {
        [Math]::Round(($confirmedAt - $requestedAt).TotalSeconds, 3)
    } else { $null }
    if ($null -eq $logSeconds -or
            [double]$logSeconds -gt $MaxModeSwitchSeconds -or
            $watch.Elapsed.TotalSeconds -gt $MaxModeSwitchSeconds) {
        throw "$Mode switch exceeded $MaxModeSwitchSeconds seconds."
    }
    return [ordered]@{
        mode = $Mode
        wallSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
        logSeconds = $logSeconds
        ui = $ui
        runtimeAfterUi = $runtimeAfterUi
        runtime = $runtime
    }
}

$summary = [ordered]@{
    schemaVersion = 1
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    completedAtUtc = $null
    success = $false
    failure = $null
    candidateSourceCommit = $CandidateSourceCommit.ToLowerInvariant()
    initialDelaySeconds = $InitialDelaySeconds
    deadmanDelaySeconds = $DeadmanDelaySeconds
    initialBaseline = $null
    installer = $null
    isolatedState = $null
    externalVpnUi = $null
    foreground = $null
    selectedMode = $null
    returnedFullMode = $null
    failureEvidence = $null
    reports = [ordered]@{
        uiDiagnostic = $diagnosticPath
        runtimeEvidence = $runtimeEvidencePath
        externalScreenshot = $externalScreenshotPath
        fullScreenshot = $fullScreenshotPath
        selectedScreenshot = $selectedScreenshotPath
        returnedFullScreenshot = $returnedFullScreenshotPath
        recovery = $recoveryReportPath
        deadman = $deadmanReportPath
    }
    cleanup = [ordered]@{
        recoverySuccess = $false
        greenUiStopped = $false
        greenComponentsStopped = $false
        betaComponentsStopped = $false
        externalVpnRunning = $false
        publicHealth = $false
        youtube = $false
        noProbeMetricRoutes = $false
        noFailsafes = $false
        scratchRemoved = $false
        originalStateUnmodified = $false
        deadmanStopped = $false
        exactInstallRetained = $false
    }
}

$mutexAcquired = $mutex.WaitOne(0)
if (-not $mutexAcquired) {
    $mutex.Dispose()
    Write-Error 'Another Windows mode reconciliation smoke is already running.'
    exit 2
}

$originalStateHashes = @{}
try {
    if (-not (Test-IsAdministrator)) {
        throw 'Windows mode reconciliation smoke must run elevated.'
    }
    foreach ($required in @(
        $resolvedInstaller, $restoreScript, $selectedExecutable,
        (Join-Path $originalUserStateRoot 'session.dat'),
        (Join-Path $originalUserStateRoot 'prefs.json')
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required mode-smoke file is missing: $required"
        }
    }
    $staleEvidence = @(
        $summaryPath, $diagnosticPath, $recoveryReportPath,
        $runtimeEvidencePath,
        $deadmanReportPath, $externalScreenshotPath, $fullScreenshotPath,
        $selectedScreenshotPath, $returnedFullScreenshotPath
    ) | Where-Object { Test-Path -LiteralPath $_ }
    if (@($staleEvidence).Count -gt 0) {
        throw 'ArtifactRoot contains stale mode-reconciliation evidence; use a new path.'
    }
    $installerItem = Get-Item -LiteralPath $resolvedInstaller
    if ((Get-FileHash -LiteralPath $resolvedInstaller -Algorithm SHA256).Hash -ne
            $expectedInstallerHash -or
            [long]$installerItem.Length -ne $ExpectedInstallerSize) {
        throw 'Exact installer failed the pre-delay identity check.'
    }
    foreach ($name in @('session.dat', 'prefs.json', 'standby_routes.json')) {
        $path = Join-Path $originalUserStateRoot $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $originalStateHashes[$name] =
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }
    }
    $summary.initialBaseline = Assert-ReadOnlySafeBaseline `
        -Label 'Initial read-only baseline'
    Write-RunnerLog "waiting $InitialDelaySeconds seconds before installation or network transitions"
    Start-Sleep -Seconds $InitialDelaySeconds

    $deadman = Start-DeadmanRecovery
    Write-RunnerLog "deadman started pid=$($deadman.Id) delay=$DeadmanDelaySeconds"
    Assert-MutableSafeBaseline -Label 'Delayed mutable baseline'

    $summary.installer = Install-ExactCandidate
    $summary.isolatedState = Initialize-IsolatedUserState
    $env:APPDATA = $isolatedAppDataRoot
    $env:GREENVPN_FUSION_UI_DIAGNOSTIC_PATH = $diagnosticPath
    Remove-Item -LiteralPath $diagnosticPath -Force -ErrorAction SilentlyContinue
    Initialize-UiInput

    $process = Start-Process -FilePath $appPath `
        -WorkingDirectory $resolvedInstallRoot -PassThru
    Wait-WindowReady -Process $process
    $externalUi = Wait-UiDiagnostic -TimeoutSeconds 60 `
        -Label 'External VPN UI state' -Predicate {
            param($state)
            [string]$state.statusKey -eq 'external_vpn' -and
                [bool]$state.externalVpnActive -and
                -not [bool]$state.vpnEnabled -and
                -not [bool]$state.protectionActive -and
                -not [bool]$state.connectedCheckVisible -and
                [bool]$state.paidEntitlement
        }
    $summary.externalVpnUi = [ordered]@{
        ui = $externalUi
        screenshot = Get-WindowScreenshot -Process $process `
            -Path $externalScreenshotPath
    }

    $summary.foreground = Invoke-ForegroundConnect -Process $process
    $summary.foreground['screenshot'] = Get-WindowScreenshot -Process $process `
        -Path $fullScreenshotPath
    $fullFingerprint = Get-EgressFingerprint
    if (-not $fullFingerprint) { throw 'Full-mode egress fingerprint was unavailable.' }

    $summary.selectedMode = Invoke-ModeSwitch -Process $process `
        -Mode applications
    $summary.selectedMode['screenshot'] = Get-WindowScreenshot -Process $process `
        -Path $selectedScreenshotPath
    New-Item -ItemType Directory -Force `
        -Path (Split-Path -Parent $directControlExecutable) | Out-Null
    Copy-Item -LiteralPath $selectedExecutable `
        -Destination $directControlExecutable -Force
    if (
        (Get-FileHash -LiteralPath $selectedExecutable -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $directControlExecutable -Algorithm SHA256).Hash
    ) {
        throw 'Direct-control executable did not preserve the selected executable identity.'
    }
    $directFingerprint = Get-EgressFingerprint `
        -ExecutablePath $directControlExecutable -AddressFamily IPv4
    $selectedFingerprint = Get-EgressFingerprint -UseSelectedExecutable `
        -AddressFamily IPv4
    $summary.selectedMode['egressProbeAttempt'] = [ordered]@{
        directFingerprintCaptured = [bool]$directFingerprint
        selectedExecutableFingerprintCaptured = [bool]$selectedFingerprint
        rawAddressesStored = $false
    }
    if (-not $directFingerprint) {
        throw 'Unselected direct-control egress fingerprint was unavailable.'
    }
    if (-not $selectedFingerprint) {
        throw 'Selected executable egress fingerprint was unavailable.'
    }
    if ($directFingerprint -eq $selectedFingerprint) {
        throw 'Selected executable did not prove a separate VPN egress.'
    }
    $expectedApplicationFingerprint = Get-StringSha256 `
        -Value $ExpectedApplicationModeEgress
    if ($selectedFingerprint -ne $expectedApplicationFingerprint) {
        throw 'Selected executable did not use the dedicated application-routing egress.'
    }
    $selectedYouTube204 = Get-SelectedYouTubeProbe
    if (-not $selectedYouTube204) {
        throw 'Selected executable did not reach YouTube through application routing.'
    }
    $directIpv6Available = Test-DirectIpv6Available `
        -ExecutablePath $directControlExecutable
    $selectedIpv6Fingerprint = Get-EgressFingerprint -UseSelectedExecutable `
        -AddressFamily IPv6
    if ($directIpv6Available -and $selectedIpv6Fingerprint) {
        throw 'Selected executable IPv6 traffic escaped the IPv4-only application route.'
    }
    $summary.selectedMode['egress'] = [ordered]@{
        selectedExecutableFingerprintCaptured = $true
        directFingerprintCaptured = $true
        selectedDiffersFromDirect = $true
        selectedMatchesDedicatedVpn = $true
        selectedYouTube204 = $selectedYouTube204
        directIpv6Available = $directIpv6Available
        selectedIpv6BlockedWhenDirectIpv6Available = (
            -not $directIpv6Available -or -not [bool]$selectedIpv6Fingerprint
        )
        ipv6DirectLeakDetected = $false
        rawAddressesStored = $false
    }

    $summary.returnedFullMode = Invoke-ModeSwitch -Process $process -Mode full
    $summary.returnedFullMode['screenshot'] = Get-WindowScreenshot -Process $process `
        -Path $returnedFullScreenshotPath
    $returnedFullFingerprint = Get-EgressFingerprint
    if (-not $returnedFullFingerprint -or
            $returnedFullFingerprint -ne $fullFingerprint) {
        throw 'Returned full mode did not restore the confirmed VPN egress.'
    }
    $summary.returnedFullMode['egress'] = [ordered]@{
        fingerprintCaptured = $true
        matchesInitialFullVpn = $true
        rawAddressStored = $false
    }
    $summary.success = $true
} catch {
    $summary.failure = $_.Exception.Message
    try {
        $summary.failureEvidence = Capture-RuntimeEvidence `
            -Label 'failure_before_recovery'
    } catch {
        $summary.failureEvidence = [ordered]@{
            captureFailed = $true
            message = $_.Exception.Message
        }
    }
    Write-RunnerLog "failed: $($summary.failure)"
} finally {
    $env:APPDATA = $originalAppData
    Remove-Item Env:GREENVPN_FUSION_UI_DIAGNOSTIC_PATH `
        -ErrorAction SilentlyContinue
    $recovery = Invoke-FinalRecovery
    if ($null -ne $recovery) {
        $summary.cleanup.recoverySuccess = [bool]$recovery.success
        $summary.cleanup.greenUiStopped = [bool]$recovery.greenUiStopped
    }
    $summary.cleanup.greenComponentsStopped = Test-GreenComponentsStopped
    $summary.cleanup.betaComponentsStopped = Test-BetaComponentsStopped
    $summary.cleanup.externalVpnRunning =
        (Get-ServiceState -Name $ExternalVpnServiceName) -eq 'Running'
    $summary.cleanup.publicHealth = Test-HttpStatus `
        -Url 'https://api.greenvpn.pro/healthz' -ExpectedStatus 200
    $summary.cleanup.youtube = Test-HttpStatus `
        -Url 'https://www.youtube.com/generate_204' -ExpectedStatus 204
    $summary.cleanup.noProbeMetricRoutes = @(
        Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
            [int]$_.RouteMetric -eq 42739
        }
    ).Count -eq 0
    foreach ($name in $failsafeTaskNames) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false `
            -ErrorAction SilentlyContinue
    }
    $summary.cleanup.noFailsafes = @(
        $failsafeTaskNames | Where-Object {
            Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue
        }
    ).Count -eq 0
    if (Test-Path -LiteralPath $privateScratchRoot) {
        $resolvedScratch = [IO.Path]::GetFullPath($privateScratchRoot).TrimEnd('\')
        $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        if (($resolvedScratch + '\').StartsWith(
                $resolvedTemp, [StringComparison]::OrdinalIgnoreCase
            )) {
            Remove-Item -LiteralPath $resolvedScratch -Recurse -Force `
                -ErrorAction SilentlyContinue
        }
    }
    $summary.cleanup.scratchRemoved = -not (Test-Path -LiteralPath $privateScratchRoot)
    $originalStateIntact = $true
    foreach ($entry in $originalStateHashes.GetEnumerator()) {
        $path = Join-Path $originalUserStateRoot $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne
                    [string]$entry.Value) {
            $originalStateIntact = $false
        }
    }
    $summary.cleanup.originalStateUnmodified = $originalStateIntact
    if ($summary.cleanup.recoverySuccess -and
            $summary.cleanup.greenUiStopped -and
            $summary.cleanup.greenComponentsStopped -and
            $summary.cleanup.betaComponentsStopped -and
            $summary.cleanup.externalVpnRunning -and
            $summary.cleanup.publicHealth -and
            $summary.cleanup.youtube -and
            $summary.cleanup.noProbeMetricRoutes -and
            $summary.cleanup.noFailsafes -and
            $summary.cleanup.scratchRemoved -and
            $summary.cleanup.originalStateUnmodified -and
            $null -ne $deadman) {
        Stop-Process -Id $deadman.Id -Force -ErrorAction SilentlyContinue
    }
    $summary.cleanup.deadmanStopped =
        $null -eq $deadman -or
        -not [bool](Get-Process -Id $deadman.Id -ErrorAction SilentlyContinue)
    if (Test-Path -LiteralPath $appPath -PathType Leaf) {
        $installed = Get-Item -LiteralPath $appPath
        $summary.cleanup.exactInstallRetained =
            [string]$installed.VersionInfo.FileVersion -eq $ExpectedVersion -and
            [long]$installed.Length -eq $ExpectedAppSize -and
            (Get-FileHash -LiteralPath $appPath -Algorithm SHA256).Hash -eq
                $expectedAppHash
    }
    $cleanupPassed = @(
        $summary.cleanup.Values | Where-Object { -not [bool]$_ }
    ).Count -eq 0
    if (-not $cleanupPassed) {
        $summary.success = $false
        if (-not $summary.failure) {
            $summary.failure = 'Final recovery or cleanup was not fully confirmed.'
        }
    }
    $summary.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-RunnerLog "finished success=$($summary.success)"
    if ($mutexAcquired) { try { $mutex.ReleaseMutex() } catch {} }
    $mutex.Dispose()
}

if (-not $summary.success) { exit 1 }
$summary | ConvertTo-Json -Depth 14
