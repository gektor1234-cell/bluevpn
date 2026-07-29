param(
    [string]$Awg2SourceConfig = 'C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_awg2_20260711\client.windows-full.awg.conf',
    [string]$ExpectedCanaryEgress = '5.129.216.42',
    [string]$CompetingServiceName = 'AmneziaWGTunnel$device20_full',
    [string]$ReportRoot = 'C:\Users\gekto\GreenVPN_Checkpoints\windows_transport_preview_cascade_20260729',
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\windows_transport_preview_cascade_physical_20260729.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$previewServiceName = 'GreenVPNTransportPreviewService'
$installRoot = Join-Path $env:ProgramFiles 'Green VPN Transport Preview'
$programDataRoot = Join-Path $env:ProgramData 'BlueVPNTransportPreview'
$tokenPath = Join-Path $programDataRoot 'service_token'
$serviceBase = 'http://127.0.0.1:48739'
$taskSource = Join-Path $PSScriptRoot 'greenvpn_transport_preview_vpn_task.ps1'
$taskInstalled = Join-Path $installRoot 'tools\greenvpn_transport_preview_vpn_task.ps1'
$previewAdapters = @(
    'GreenVPNHysteriaPreview',
    'GreenVPNVlessPreview',
    'GreenVPNNaivePreview',
    'GreenVPNDnsttPreview'
)
$previewTunnelServices = @(
    'WireGuardTunnel$GreenVPNTransportPreview',
    'AmneziaWGTunnel$GreenVPNTransportPreview'
)
$managedStateFiles = @(
    'GreenVPNTransportPreview.conf.endpoint-route.json',
    'hysteria2-routes.json',
    'vless-reality-routes.json',
    'naive-https-routes.json',
    'dnstt-routes.json',
    'hysteria2-client.pid',
    'hysteria2-hev.pid',
    'hysteria2-watchdog.pid',
    'vless-reality-client.pid',
    'vless-reality-hev.pid',
    'vless-reality-watchdog.pid',
    'naive-https-client.pid',
    'naive-https-hev.pid',
    'naive-https-watchdog.pid',
    'dnstt-client.pid',
    'dnstt-hev.pid',
    'dnstt-watchdog.pid'
)

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PublicIp {
    foreach ($uri in @('https://api.ipify.org', 'https://ifconfig.me/ip')) {
        try {
            $value = (Invoke-RestMethod -Uri $uri -TimeoutSec 15).ToString().Trim()
            if ($value -match '^\d{1,3}(?:\.\d{1,3}){3}$') { return $value }
        } catch {
        }
    }
    throw 'Public IPv4 probe failed.'
}

function Wait-ServiceState {
    param([string]$Name, [string]$State, [int]$Seconds = 30)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        $current = if ($null -eq $service) { 'Missing' } else { $service.Status.ToString() }
        if ($current -eq $State) { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Service $Name did not reach $State."
}

function Invoke-PreviewDisconnect {
    if (-not (Test-Path -LiteralPath $tokenPath -PathType Leaf)) { return }
    $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
    if ($token.Length -lt 24) { return }
    try {
        Invoke-WebRequest -UseBasicParsing -Method POST -Uri ($serviceBase + '/disconnect') `
            -Headers @{ 'X-GreenVPN-Local-Token' = $token } -TimeoutSec 130 | Out-Null
    } catch {
    }
}

function Assert-CleanTransitionState {
    param([string]$ExpectedBaselineEgress)
    $previewService = Get-Service -Name $previewServiceName -ErrorAction SilentlyContinue
    if ($null -eq $previewService -or $previewService.Status -ne 'Running') {
        throw 'Transport preview backend service is not running.'
    }
    $competingService = Get-Service -Name $CompetingServiceName -ErrorAction SilentlyContinue
    if ($null -eq $competingService -or $competingService.Status -ne 'Running') {
        throw 'Original VPN service was not restored.'
    }
    $activeAdapters = @(
        Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in $previewAdapters -and $_.Status -ne 'Not Present' }
    )
    if ($activeAdapters.Count -ne 0) {
        throw "Preview adapter residue remains: $($activeAdapters.Name -join ', ')"
    }
    $activeTunnelServices = @(
        Get-Service -Name $previewTunnelServices -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -ne 'Stopped' }
    )
    if ($activeTunnelServices.Count -ne 0) {
        throw "Preview tunnel service residue remains: $($activeTunnelServices.Name -join ', ')"
    }
    $activeRoutes = @(
        Get-NetRoute -ErrorAction SilentlyContinue |
            Where-Object { $_.RouteMetric -in @(42731, 42732, 42733, 42734, 42735) }
    )
    if ($activeRoutes.Count -ne 0) {
        throw 'Managed preview route residue remains.'
    }
    $stateResidue = @(
        $managedStateFiles |
            Where-Object { Test-Path -LiteralPath (Join-Path $programDataRoot $_) }
    )
    if ($stateResidue.Count -ne 0) {
        throw "Managed preview state residue remains: $($stateResidue -join ', ')"
    }
    $toolPrefix = ([IO.Path]::GetFullPath((Join-Path $installRoot 'tools'))).TrimEnd('\') + '\'
    $managedProcesses = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and
                [IO.Path]::GetFullPath([string]$_.ExecutablePath).StartsWith(
                    $toolPrefix,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
    )
    if ($managedProcesses.Count -ne 0) {
        throw 'Managed preview child process residue remains.'
    }
    $egress = Get-PublicIp
    if ($egress -ne $ExpectedBaselineEgress) {
        throw "Original egress was not restored: expected=$ExpectedBaselineEgress actual=$egress"
    }
}

if (-not (Test-IsAdministrator)) { throw 'Administrator token is required.' }
foreach ($path in @($Awg2SourceConfig, $taskSource, $taskInstalled, $tokenPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file is missing: $path" }
}
if ((Get-FileHash -LiteralPath $taskSource -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $taskInstalled -Algorithm SHA256).Hash) {
    throw 'Installed transport task does not match the source under test.'
}

New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
$baselineEgress = Get-PublicIp
$steps = @(
    [ordered]@{
        protocol = 'amneziawg'
        script = Join-Path $PSScriptRoot 'test_windows_awg2_preview_physical.ps1'
        report = Join-Path $ReportRoot '01-amneziawg.json'
        arguments = @('-SourceConfig', $Awg2SourceConfig, '-ExpectedCanaryEgress', $ExpectedCanaryEgress,
            '-CompetingServiceName', $CompetingServiceName, '-TaskScriptSource', $taskSource)
    },
    [ordered]@{
        protocol = 'hysteria2'
        script = Join-Path $PSScriptRoot 'test_windows_hysteria2_preview_physical.ps1'
        report = Join-Path $ReportRoot '02-hysteria2.json'
        arguments = @('-ExpectedCanaryEgress', $ExpectedCanaryEgress, '-CompetingServiceName', $CompetingServiceName)
    },
    [ordered]@{
        protocol = 'vless_reality'
        script = Join-Path $PSScriptRoot 'test_windows_vless_reality_preview_physical.ps1'
        report = Join-Path $ReportRoot '03-vless-reality.json'
        arguments = @('-ExpectedCanaryEgress', $ExpectedCanaryEgress, '-CompetingServiceName', $CompetingServiceName)
    },
    [ordered]@{
        protocol = 'naive_https'
        script = Join-Path $PSScriptRoot 'test_windows_naive_https_preview_physical.ps1'
        report = Join-Path $ReportRoot '04-naive-https.json'
        arguments = @('-ExpectedCanaryEgress', $ExpectedCanaryEgress, '-CompetingServiceName', $CompetingServiceName)
    },
    [ordered]@{
        protocol = 'dnstt'
        script = Join-Path $PSScriptRoot 'test_windows_dnstt_preview_physical.ps1'
        report = Join-Path $ReportRoot '05-dnstt.json'
        arguments = @('-ExpectedCanaryEgress', $ExpectedCanaryEgress, '-CompetingServiceName', $CompetingServiceName)
    }
)

$report = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    installedTaskSha256 = (Get-FileHash -LiteralPath $taskInstalled -Algorithm SHA256).Hash
    baselineEgress = $baselineEgress
    expectedCanaryEgress = $ExpectedCanaryEgress
    order = @($steps | ForEach-Object { $_.protocol })
    results = @()
    cleanAfterEveryTransition = $false
    finalEgress = ''
    success = $false
    error = ''
    finishedAt = $null
}

try {
    Assert-CleanTransitionState -ExpectedBaselineEgress $baselineEgress
    foreach ($step in $steps) {
        if (-not (Test-Path -LiteralPath $step.script -PathType Leaf)) {
            throw "Physical test script is missing: $($step.script)"
        }
        Remove-Item -LiteralPath $step.report -Force -ErrorAction SilentlyContinue
        $arguments = @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', $step.script
        ) + @($step.arguments) + @('-ReportPath', $step.report)
        & (Join-Path $PSHOME 'powershell.exe') @arguments | Out-Null
        $exitCode = $LASTEXITCODE
        if (-not (Test-Path -LiteralPath $step.report -PathType Leaf)) {
            throw "Physical test did not produce a report: $($step.protocol)"
        }
        $stepReport = Get-Content -LiteralPath $step.report -Raw -Encoding UTF8 | ConvertFrom-Json
        $report.results += [ordered]@{
            protocol = $step.protocol
            exitCode = $exitCode
            success = [bool]$stepReport.success
            canaryEgress = [string]$stepReport.canaryEgress
            restoredOriginalEgress = [bool]$stepReport.restoredOriginalEgress
            reportPath = $step.report
            reportSha256 = (Get-FileHash -LiteralPath $step.report -Algorithm SHA256).Hash
        }
        if ($exitCode -ne 0 -or -not [bool]$stepReport.success -or
            [string]$stepReport.canaryEgress -ne $ExpectedCanaryEgress -or
            -not [bool]$stepReport.restoredOriginalEgress) {
            throw "Physical transition failed: $($step.protocol)"
        }
        Assert-CleanTransitionState -ExpectedBaselineEgress $baselineEgress
    }
    $report.cleanAfterEveryTransition = $true
    $report.finalEgress = Get-PublicIp
    $report.success = $report.finalEgress -eq $baselineEgress
} catch {
    $report.error = $_.Exception.Message
} finally {
    Invoke-PreviewDisconnect
    $service = Get-Service -Name $CompetingServiceName -ErrorAction SilentlyContinue
    if ($null -ne $service -and $service.Status -ne 'Running') {
        Start-Service -Name $CompetingServiceName -ErrorAction SilentlyContinue
        try { Wait-ServiceState -Name $CompetingServiceName -State 'Running' } catch {}
    }
    try { $report.finalEgress = Get-PublicIp } catch {}
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

if (-not $report.success) { exit 1 }
