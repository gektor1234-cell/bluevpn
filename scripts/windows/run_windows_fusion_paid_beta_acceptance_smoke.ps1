[CmdletBinding()]
param(
    [string]$InstallerPath = 'C:\BlueVPN_Builds\paid_beta_20260813_fusion_acl_fix_v1_0.4.6\GreenVPN_Beta_Setup_0.4.6-paid-beta.2.exe',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedInstallerSha256 = 'B882DB6EEF672C21786608888431126FAFC997EC6D7C5CEADB6CA16DD0AEC4B3',
    [long]$ExpectedInstallerSize = 55497728,
    [string]$ExpectedFileVersion = '0.4.6+4602',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedAppSha256 = '200838477BCBA22C7AB2CC29A716B56D927249197754C0DC3035E61CC2549F80',
    [long]$ExpectedAppSize = 149504,
    [ValidatePattern('^[0-9A-Fa-f]{40}$')]
    [string]$CandidateSourceCommit = '62f9db7c8d639fed62205d0e82c016609cfe2d45',
    [string]$ArtifactRoot = 'C:\BlueVPN_Builds\fusion_windows_acceptance_20260813_physical_v4_b4602',
    [string]$InstallRoot = 'C:\Program Files\Green VPN Beta',
    [string]$ProgramDataRoot = 'C:\ProgramData\BlueVPNBeta',
    [int]$LocalServicePort = 48738,
    [string]$ExternalVpnServiceName = 'AmneziaWGTunnel$device20_full',
    [ValidateRange(90, 600)]
    [int]$InitialDelaySeconds = 90,
    [ValidateRange(300, 1800)]
    [int]$DeadmanDelaySeconds = 900,
    [ValidateRange(10, 120)]
    [int]$MaxConnectSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$physicalScript = Join-Path $repoRoot 'scripts\windows\test_windows_connect_latency_physical.ps1'
$restoreScript = Join-Path $repoRoot 'scripts\windows\restore_windows_smoke_network.ps1'
$resolvedInstaller = [IO.Path]::GetFullPath($InstallerPath)
$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$resolvedProgramDataRoot = [IO.Path]::GetFullPath($ProgramDataRoot).TrimEnd('\')
$appPath = Join-Path $resolvedInstallRoot 'greenvpn_beta.exe'
$processName = 'greenvpn_beta'
$managedTunnelName = 'GreenVPNBeta'
$localServiceName = 'GreenVPNBetaService'
$stableProgramDataRoot = 'C:\ProgramData\BlueVPN'
$stableLocalServicePort = 48737
$betaFailsafeTaskName = 'GreenVPNBetaConnectLatencySmokeFailsafe'
$summaryPath = Join-Path $ArtifactRoot 'windows-fusion-paid-beta-autonomous-summary.json'
$freshReportPath = Join-Path $ArtifactRoot 'windows-fusion-paid-beta-fresh-connect.json'
$cachedReportPath = Join-Path $ArtifactRoot 'windows-fusion-paid-beta-cached-connect.json'
$recoveryReportPath = Join-Path $ArtifactRoot 'windows-fusion-paid-beta-final-recovery.json'
$deadmanReportPath = Join-Path $ArtifactRoot 'windows-fusion-paid-beta-deadman-recovery.json'
$uiScreenshotPath = Join-Path $ArtifactRoot 'windows-fusion-paid-beta-main.png'
$logPath = Join-Path $ArtifactRoot 'windows-fusion-paid-beta-autonomous.log'
$isolatedAppDataRoot = Join-Path $ArtifactRoot 'isolated-appdata'
$isolatedUserStateRoot = Join-Path $isolatedAppDataRoot 'GreenVPNBeta\state'
$expectedInstallerHash = $ExpectedInstallerSha256.ToUpperInvariant()
$expectedAppHash = $ExpectedAppSha256.ToUpperInvariant()
$originalAppData = $env:APPDATA
$mutex = [Threading.Mutex]::new($false, 'Local\GreenVPNFusionPaidBetaAcceptanceSmoke')
$mutexAcquired = $false
$deadman = $null

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

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
    } catch {
        return $false
    }
}

function Test-LocalComponentsStopped {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$TunnelName,
        [switch]$AllowMissing
    )
    $tokenPath = Join-Path $Root 'service_token'
    if (-not (Test-Path -LiteralPath $tokenPath -PathType Leaf)) {
        if (-not $AllowMissing) { return $false }
        foreach ($prefix in @('WireGuardTunnel$', 'AmneziaWGTunnel$')) {
            $service = Get-Service -Name ($prefix + $TunnelName) `
                -ErrorAction SilentlyContinue
            if ($null -ne $service -and [string]$service.Status -ne 'Stopped') {
                return $false
            }
        }
        return $true
    }
    try {
        $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
        if ($token.Length -lt 24) { return $false }
        $status = Invoke-RestMethod -Method Get `
            -Uri "http://127.0.0.1:$Port/status" `
            -Headers @{ 'X-GreenVPN-Local-Token' = $token } `
            -TimeoutSec 8
        foreach ($key in @(
            'wireGuardState', 'amneziaWgState', 'hysteriaClientState',
            'hysteriaTunState', 'vlessClientState', 'vlessTunState',
            'naiveClientState', 'naiveTunState', 'dnsttClientState',
            'dnsttTunState', 'processRouterState'
        )) {
            if (([string]$status.$key).Trim().ToLowerInvariant() -notin @(
                'missing', 'stopped'
            )) {
                return $false
            }
        }
        return $true
    } catch {
        return $false
    }
}

function Get-ExactBetaProcesses {
    return @(
        Get-Process -Name $processName -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    [IO.Path]::GetFullPath([string]$_.Path) -ieq $appPath
                } catch {
                    $false
                }
            }
    )
}

function Stop-BetaUi {
    if (Test-Path -LiteralPath $appPath -PathType Leaf) {
        try {
            $shutdown = Start-Process -FilePath $appPath `
                -ArgumentList @('--shutdown-existing', '--background') `
                -WorkingDirectory $resolvedInstallRoot `
                -WindowStyle Hidden -PassThru
            [void]$shutdown.WaitForExit(15000)
        } catch {}
    }
    $deadline = (Get-Date).AddSeconds(15)
    do {
        if (@(Get-ExactBetaProcesses).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    foreach ($process in @(Get-ExactBetaProcesses)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
    return @(Get-ExactBetaProcesses).Count -eq 0
}

function Get-ReadOnlyBaseline {
    param([switch]$BetaMayBeMissing)
    $result = [ordered]@{
        externalVpnRunning =
            (Get-ServiceState -Name $ExternalVpnServiceName) -eq 'Running'
        stableComponentsStopped = Test-LocalComponentsStopped `
            -Root $stableProgramDataRoot -Port $stableLocalServicePort `
            -TunnelName 'BlueVPNDev1'
        betaComponentsStopped = Test-LocalComponentsStopped `
            -Root $resolvedProgramDataRoot -Port $LocalServicePort `
            -TunnelName $managedTunnelName -AllowMissing:$BetaMayBeMissing
        betaUiStopped = @(Get-ExactBetaProcesses).Count -eq 0
        productionApi = Test-HttpStatus `
            -Url 'https://api.greenvpn.pro/healthz' -ExpectedStatus 200
        paidBetaApi = Test-HttpStatus `
            -Url 'https://api.greenvpn.pro/paid-beta-api/healthz' `
            -ExpectedStatus 200
        youtube = Test-HttpStatus `
            -Url 'https://www.youtube.com/generate_204' -ExpectedStatus 204
    }
    $result['success'] = @($result.Values | Where-Object { -not [bool]$_ }).Count -eq 0
    return $result
}

function Assert-ReadOnlyBaseline {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$BetaMayBeMissing
    )
    $baseline = Get-ReadOnlyBaseline -BetaMayBeMissing:$BetaMayBeMissing
    if (-not [bool]$baseline.success) {
        throw "$Label failed: $($baseline | ConvertTo-Json -Compress)."
    }
    return $baseline
}

function Start-DeadmanRecovery {
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', "`"$restoreScript`"",
        '-InstallRoot', "`"$resolvedInstallRoot`"",
        '-AppPath', "`"$appPath`"",
        '-ProcessName', $processName,
        '-ProgramDataRoot', "`"$resolvedProgramDataRoot`"",
        '-LocalServicePort', [string]$LocalServicePort,
        '-ManagedTunnelName', $managedTunnelName,
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
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned `
            -File $restoreScript `
            -InstallRoot $resolvedInstallRoot `
            -AppPath $appPath `
            -ProcessName $processName `
            -ProgramDataRoot $resolvedProgramDataRoot `
            -LocalServicePort $LocalServicePort `
            -ManagedTunnelName $managedTunnelName `
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
    } catch {
        return $null
    }
}

function Install-ExactCandidate {
    $item = Get-Item -LiteralPath $resolvedInstaller -ErrorAction Stop
    $hash = (Get-FileHash -LiteralPath $resolvedInstaller -Algorithm SHA256).Hash
    if ($hash -ne $expectedInstallerHash -or
            [long]$item.Length -ne $ExpectedInstallerSize) {
        throw 'Exact paid-beta installer SHA-256 or size mismatch.'
    }
    if (-not (Stop-BetaUi)) { throw 'Existing beta UI did not stop.' }
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
    $app = Get-Item -LiteralPath $appPath -ErrorAction Stop
    $appHash = (Get-FileHash -LiteralPath $appPath -Algorithm SHA256).Hash
    if ([string]$app.VersionInfo.FileVersion -ne $ExpectedFileVersion) {
        throw "Installed file version mismatch: $($app.VersionInfo.FileVersion)."
    }
    if ($appHash -ne $expectedAppHash) {
        throw 'Installed application SHA-256 does not match the exact payload.'
    }
    if ([long]$app.Length -ne $ExpectedAppSize) {
        throw "Installed application size mismatch: $($app.Length)."
    }
    if ((Get-ServiceState -Name $localServiceName) -ne 'Running') {
        throw 'Green VPN Beta local service is not running after installation.'
    }
    if (-not (Test-LocalComponentsStopped -Root $resolvedProgramDataRoot `
            -Port $LocalServicePort -TunnelName $managedTunnelName)) {
        throw 'Green VPN Beta transports are not stopped after installation.'
    }
    return [ordered]@{
        path = $resolvedInstaller
        size = [long]$item.Length
        sha256 = $hash
        signatureStatus =
            (Get-AuthenticodeSignature -LiteralPath $resolvedInstaller).Status.ToString()
        installedAppPath = $appPath
        installedAppSize = [long]$app.Length
        installedAppSha256 = $appHash
        installedFileVersion = [string]$app.VersionInfo.FileVersion
        localService = $localServiceName
    }
}

function Get-WindowScreenshot {
    param(
        [Parameter(Mandatory = $true)][Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][string]$Path
    )
    Add-Type -AssemblyName System.Drawing
    if (-not ('GreenVpnFusionWindowCapture' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GreenVpnFusionWindowCapture {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@
    }
    $rect = New-Object GreenVpnFusionWindowCapture+RECT
    [void][GreenVpnFusionWindowCapture]::ShowWindow($Process.MainWindowHandle, 9)
    [void][GreenVpnFusionWindowCapture]::SetForegroundWindow($Process.MainWindowHandle)
    Start-Sleep -Milliseconds 700
    if (-not [GreenVpnFusionWindowCapture]::GetWindowRect(
            $Process.MainWindowHandle, [ref]$rect)) {
        throw 'Could not read the Fusion window bounds.'
    }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -lt 200 -or $height -lt 200) {
        throw 'Fusion window bounds are implausibly small.'
    }
    $bitmap = [System.Drawing.Bitmap]::new($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $sampleStep = 8
    $sampledPixels = 0
    $greenPixels = 0
    $darkPixels = 0
    $lightPixels = 0
    $distinctColors = [Collections.Generic.HashSet[int]]::new()
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        for ($y = 0; $y -lt $height; $y += $sampleStep) {
            for ($x = 0; $x -lt $width; $x += $sampleStep) {
                $color = $bitmap.GetPixel($x, $y)
                $sampledPixels++
                [void]$distinctColors.Add($color.ToArgb())
                $average = (
                    [int]$color.R + [int]$color.G + [int]$color.B
                ) / 3
                if (
                    [int]$color.G -gt ([int]$color.R + 15) -and
                    [int]$color.G -gt ([int]$color.B + 5) -and
                    [int]$color.G -gt 70
                ) {
                    $greenPixels++
                }
                if ($average -lt 90) { $darkPixels++ }
                if ($average -gt 180) { $lightPixels++ }
            }
        }
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
    $visualContractPassed =
        $width -ge 900 -and
        $height -ge 650 -and
        $sampledPixels -ge 5000 -and
        $distinctColors.Count -ge 50 -and
        $greenPixels -ge 100 -and
        $darkPixels -ge 100 -and
        $lightPixels -ge 100
    return [ordered]@{
        width = $width
        height = $height
        path = $Path
        sampleStep = $sampleStep
        sampledPixels = $sampledPixels
        distinctColorCount = $distinctColors.Count
        greenPixelCount = $greenPixels
        darkPixelCount = $darkPixels
        lightPixelCount = $lightPixels
        visualContractPassed = $visualContractPassed
    }
}

function Invoke-FusionUiAudit {
    if (-not (Stop-BetaUi)) { throw 'Beta UI did not stop before UI audit.' }
    $process = Start-Process -FilePath $appPath -WorkingDirectory $resolvedInstallRoot `
        -PassThru
    try {
        $deadline = (Get-Date).AddSeconds(60)
        do {
            $process.Refresh()
            if ($process.HasExited) { throw 'Beta UI exited during Fusion audit.' }
            if ($process.MainWindowHandle -ne 0) { break }
            Start-Sleep -Milliseconds 250
        } while ((Get-Date) -lt $deadline)
        if ($process.MainWindowHandle -eq 0) {
            throw 'Beta UI did not expose a main window for Fusion audit.'
        }
        Start-Sleep -Seconds 3
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        $window = [System.Windows.Automation.AutomationElement]::FromHandle(
            $process.MainWindowHandle
        )
        if ($null -eq $window) {
            throw 'Fusion window is unavailable to UI Automation.'
        }
        $nodes = $window.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition
        )
        $semanticEntries = @(
            foreach ($node in $nodes) {
                try {
                    [ordered]@{
                        name = [string]$node.Current.Name
                        controlType =
                            [string]$node.Current.ControlType.ProgrammaticName
                        automationId = [string]$node.Current.AutomationId
                    }
                } catch {}
            }
        )
        $windowTitle = [string]$window.Current.Name
        $capture = Get-WindowScreenshot -Process $process -Path $uiScreenshotPath
        if ($windowTitle -ne 'Green VPN Beta') {
            throw "Unexpected Fusion window title: $windowTitle"
        }
        if (-not [bool]$capture.visualContractPassed) {
            throw 'Fusion screenshot failed the nonblank visual contract.'
        }
        return [ordered]@{
            windowTitle = $windowTitle
            uiAutomationNodeCount = $semanticEntries.Count
            uiAutomationEntries = @($semanticEntries)
            flutterViewOnly =
                $semanticEntries.Count -eq 1 -and
                [string]$semanticEntries[0].name -eq 'FLUTTERVIEW'
            screenshot = $capture
            manualVisualReviewRequired = $true
            success = $true
        }
    } finally {
        if (-not (Stop-BetaUi)) {
            throw 'Beta UI did not stop after UI audit.'
        }
    }
}

function Invoke-PhysicalConnect {
    param(
        [Parameter(Mandatory = $true)][string]$ReportPath,
        [switch]$RequireCachedRoute
    )
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', "`"$physicalScript`"",
        '-InstallRoot', "`"$resolvedInstallRoot`"",
        '-AppPath', "`"$appPath`"",
        '-ProcessName', $processName,
        '-ProgramDataRoot', "`"$resolvedProgramDataRoot`"",
        '-UserStateRoot', "`"$isolatedUserStateRoot`"",
        '-LocalServicePort', [string]$LocalServicePort,
        '-UseUiAutomationAction',
        '-ExpectCompetingVpn',
        '-ExternalVpnServiceName', "`"$ExternalVpnServiceName`"",
        '-FirstConnectTimeoutSeconds', '120',
        '-MaxFirstConnectSeconds', [string]$MaxConnectSeconds,
        '-MaxCachedConnectSeconds', [string]$MaxConnectSeconds,
        '-FailsafeDelayMinutes', '8',
        '-FailsafeTaskName', $betaFailsafeTaskName,
        '-ReportPath', "`"$ReportPath`""
    )
    if ($RequireCachedRoute) { $arguments += '-AllowExistingPreferredRoute' }
    $physical = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments `
        -WindowStyle Hidden -Wait -PassThru
    if ($physical.ExitCode -ne 0 -or
            -not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
        throw "Physical connect smoke failed with exit code $($physical.ExitCode)."
    }
    $report = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $takeover = $report.competingVpnTakeover
    $candidates = @($takeover.candidates)
    $cachedRouteConfirmed =
        $null -ne $takeover.PSObject.Properties['cachedRouteConfirmed'] -and
        [bool]$takeover.cachedRouteConfirmed
    if (-not [bool]$report.success -or
            $candidates.Count -ne 1 -or
            -not [bool]$takeover.probeConfirmed -or
            -not [bool]$takeover.privilegedTakeoverConfirmed -or
            [double]$takeover.logSeconds -gt $MaxConnectSeconds -or
            [string]$takeover.uiAutomationAction -notin @(
                'uia_invoke', 'coordinate_click'
            ) -or
            -not [bool]$report.cleanup.allManagedComponentsStopped -or
            -not [bool]$report.cleanup.externalVpnRestored -or
            -not [bool]$report.cleanup.originalEgressRestored -or
            -not [bool]$report.cleanup.publicHealth -or
            -not [bool]$report.cleanup.restoreFailsafeRemoved) {
        throw "Physical connect contract failed: $($report.failure)"
    }
    if ($RequireCachedRoute -and -not $cachedRouteConfirmed) {
        throw 'Cached physical connect did not confirm the persisted route.'
    }
    return [ordered]@{
        logSeconds = [double]$takeover.logSeconds
        wallSeconds = [double]$takeover.wallSeconds
        candidate = $candidates[0]
        uiAutomationAction = [string]$takeover.uiAutomationAction
        probeConfirmed = $true
        privilegedTakeoverConfirmed = $true
        cachedRouteConfirmed = $cachedRouteConfirmed
        cleanupConfirmed = $true
    }
}

$summary = [ordered]@{
    schemaVersion = 1
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    completedAtUtc = $null
    success = $false
    failure = $null
    initialDelaySeconds = $InitialDelaySeconds
    deadmanDelaySeconds = $DeadmanDelaySeconds
    candidateSourceCommit = $CandidateSourceCommit.ToLowerInvariant()
    initialBaseline = $null
    installer = $null
    fusionUi = $null
    freshConnect = $null
    cachedConnect = $null
    reports = [ordered]@{
        fresh = $freshReportPath
        cached = $cachedReportPath
        recovery = $recoveryReportPath
        deadman = $deadmanReportPath
        screenshot = $uiScreenshotPath
    }
    cleanup = [ordered]@{
        recoverySuccess = $false
        betaUiStopped = $false
        betaComponentsStopped = $false
        stableComponentsStopped = $false
        externalVpnRunning = $false
        productionApi = $false
        paidBetaApi = $false
        youtube = $false
        failsafesRemoved = $false
        deadmanStopped = $false
        exactInstallRetained = $false
    }
}

$mutexAcquired = $mutex.WaitOne(0)
if (-not $mutexAcquired) {
    $mutex.Dispose()
    Write-Error 'Another Fusion paid-beta acceptance smoke is already running.'
    exit 2
}

try {
    if (-not (Test-IsAdministrator)) {
        throw 'Fusion paid-beta acceptance smoke must run elevated.'
    }
    foreach ($required in @($resolvedInstaller, $physicalScript, $restoreScript)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required file is missing: $required"
        }
    }
    $staleEvidencePaths = @(
        $summaryPath,
        $freshReportPath,
        $cachedReportPath,
        $recoveryReportPath,
        $deadmanReportPath,
        $uiScreenshotPath,
        $isolatedAppDataRoot
    )
    $staleEvidence = @(
        $staleEvidencePaths | Where-Object { Test-Path -LiteralPath $_ }
    )
    if ($staleEvidence.Count -gt 0) {
        throw 'ArtifactRoot contains stale acceptance evidence; use a new unique path.'
    }
    New-Item -ItemType Directory -Force -Path $isolatedUserStateRoot | Out-Null
    $item = Get-Item -LiteralPath $resolvedInstaller
    $hash = (Get-FileHash -LiteralPath $resolvedInstaller -Algorithm SHA256).Hash
    if ($hash -ne $expectedInstallerHash -or
            [long]$item.Length -ne $ExpectedInstallerSize) {
        throw 'Exact installer failed the pre-delay identity check.'
    }
    $summary.initialBaseline = Assert-ReadOnlyBaseline `
        -Label 'Initial read-only baseline' -BetaMayBeMissing
    Write-RunnerLog "waiting $InitialDelaySeconds seconds before installation or network transitions"
    Start-Sleep -Seconds $InitialDelaySeconds

    $deadman = Start-DeadmanRecovery
    Write-RunnerLog "deadman started pid=$($deadman.Id) delay=$DeadmanDelaySeconds"
    [void](Assert-ReadOnlyBaseline -Label 'Delayed read-only baseline' `
        -BetaMayBeMissing)

    $summary.installer = Install-ExactCandidate
    $env:APPDATA = $isolatedAppDataRoot
    $summary.fusionUi = Invoke-FusionUiAudit
    $summary.freshConnect = Invoke-PhysicalConnect -ReportPath $freshReportPath
    [void](Assert-ReadOnlyBaseline -Label 'Between fresh and cached smokes')
    $summary.cachedConnect = Invoke-PhysicalConnect `
        -ReportPath $cachedReportPath -RequireCachedRoute
    $summary.success = $true
} catch {
    $summary.failure = $_.Exception.Message
    Write-RunnerLog "failed: $($summary.failure)"
} finally {
    $env:APPDATA = $originalAppData
    $recovery = Invoke-FinalRecovery
    if ($null -ne $recovery) {
        $summary.cleanup.recoverySuccess = [bool]$recovery.success
    }
    $summary.cleanup.betaUiStopped = @(Get-ExactBetaProcesses).Count -eq 0
    $summary.cleanup.betaComponentsStopped = Test-LocalComponentsStopped `
        -Root $resolvedProgramDataRoot -Port $LocalServicePort `
        -TunnelName $managedTunnelName -AllowMissing
    $summary.cleanup.stableComponentsStopped = Test-LocalComponentsStopped `
        -Root $stableProgramDataRoot -Port $stableLocalServicePort `
        -TunnelName 'BlueVPNDev1'
    $summary.cleanup.externalVpnRunning =
        (Get-ServiceState -Name $ExternalVpnServiceName) -eq 'Running'
    $summary.cleanup.productionApi = Test-HttpStatus `
        -Url 'https://api.greenvpn.pro/healthz' -ExpectedStatus 200
    $summary.cleanup.paidBetaApi = Test-HttpStatus `
        -Url 'https://api.greenvpn.pro/paid-beta-api/healthz' -ExpectedStatus 200
    $summary.cleanup.youtube = Test-HttpStatus `
        -Url 'https://www.youtube.com/generate_204' -ExpectedStatus 204
    $summary.cleanup.failsafesRemoved = -not [bool](
        Get-ScheduledTask -TaskName $betaFailsafeTaskName `
            -ErrorAction SilentlyContinue
    )
    if ($summary.cleanup.recoverySuccess -and $null -ne $deadman) {
        Stop-Process -Id $deadman.Id -Force -ErrorAction SilentlyContinue
    }
    $summary.cleanup.deadmanStopped =
        $null -eq $deadman -or
        -not [bool](Get-Process -Id $deadman.Id -ErrorAction SilentlyContinue)
    if (Test-Path -LiteralPath $appPath -PathType Leaf) {
        $installed = Get-Item -LiteralPath $appPath
        $summary.cleanup.exactInstallRetained =
            [string]$installed.VersionInfo.FileVersion -eq $ExpectedFileVersion -and
            [long]$installed.Length -eq $ExpectedAppSize -and
            (Get-FileHash -LiteralPath $appPath -Algorithm SHA256).Hash -eq
                $expectedAppHash
    }
    $cleanupPassed = @($summary.cleanup.Values | Where-Object {
        -not [bool]$_
    }).Count -eq 0
    if (-not $cleanupPassed) {
        $summary.success = $false
        if (-not $summary.failure) {
            $summary.failure = 'Final recovery or cleanup was not fully confirmed.'
        }
    }
    $summary.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $summary | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-RunnerLog "finished success=$($summary.success)"
    if ($mutexAcquired) { try { $mutex.ReleaseMutex() } catch {} }
    $mutex.Dispose()
}

if (-not $summary.success) { exit 1 }
$summary | ConvertTo-Json -Depth 12
