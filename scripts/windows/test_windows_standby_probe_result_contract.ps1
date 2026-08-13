param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$ReportPath = '',
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$project = [IO.Path]::GetFullPath($ProjectRoot)
$sourcePath = Join-Path $project 'scripts\windows\greenvpn_standby_probe.ps1'
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Standby probe source is missing: $sourcePath"
}

$testRoot = Join-Path $env:TEMP (
    'green-vpn-standby-result-contract-' + [guid]::NewGuid().ToString('N')
)
$dataRoot = Join-Path $testRoot 'data'
$testScript = Join-Path $testRoot 'standby-probe-contract-test.ps1'
$resultPath = Join-Path $dataRoot 'standby-probe-result.json'
$report = [ordered]@{
    startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    completedAtUtc = ''
    childExitCode = $null
    resultExists = $false
    resultSuccess = $null
    cleanupOk = $null
    errorCode = ''
    cleanupErrors = @()
    transientChildExitCode = $null
    transientCleanupOk = $null
    transientErrorCode = ''
    transientCleanupErrors = @()
    success = $false
    failure = ''
}

try {
    New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
    $baseSource = [IO.File]::ReadAllText(
        $sourcePath,
        [Text.UTF8Encoding]::new($true)
    )
    if ($baseSource.Contains('@($bypassRoutes)') -or
        ([regex]::Matches(
            $baseSource,
            'foreach \(\$route in \[object\[\]\]\$bypassRoutes\)'
        )).Count -lt 2) {
        throw 'Standby route cleanup must safely enumerate List[object] on Windows PowerShell 5.'
    }
    $quotedRoot = $dataRoot.Replace("'", "''")
    $source = $baseSource
    $source = $source.Replace(
        '$ProgramDataRoot = Join-Path $env:ProgramData ''BlueVPNTransportPreview''',
        ('$ProgramDataRoot = ''' + $quotedRoot + '''')
    )
    $source = $source.Replace(
        '$ProbeTunnelName = ''GreenVPNTransportPreviewStandbyProbe''',
        '$ProbeTunnelName = ''GreenVPNStandbyProbeContractTest'''
    )
    $source = $source.Replace(
        '    Protect-PrivatePath -Path $RuntimeRoot -Directory',
        '    # The disposable contract runtime stays accessible to both child runs.'
    )
    $injection = @'
function Stop-ProbeProcesses { throw 'injected cleanup failure' }
function Stop-StaleProbeProcesses {}
function Stop-NativeProbe {}
function Remove-ProbeEndpointBypassRoutes {}
function Remove-AllProbeEndpointBypassRoutes {}
'@
    $source = $source.Replace(
        '$stage = ''request''',
        ($injection + [Environment]::NewLine + '$stage = ''request''')
    )
    [IO.File]::WriteAllText(
        $testScript,
        $source,
        [Text.UTF8Encoding]::new($false)
    )

    $child = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $testScript + '"')
    ) -WindowStyle Hidden -Wait -PassThru
    $report.childExitCode = [int]$child.ExitCode
    $report.resultExists = Test-Path -LiteralPath $resultPath -PathType Leaf
    if (-not $report.resultExists) {
        throw 'Injected cleanup failure did not produce a standby result.'
    }
    $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $report.resultSuccess = $result.success
    $report.cleanupOk = $result.cleanupOk
    $report.errorCode = [string]$result.errorCode
    $report.cleanupErrors = @($result.cleanupErrors)
    if ($child.ExitCode -eq 0 -or
        $result.success -ne $false -or
        $result.cleanupOk -ne $false -or
        [string]$result.errorCode -ne 'cleanup_failed' -or
        'tracked_processes' -notin @($result.cleanupErrors)) {
        throw 'Standby result did not preserve the injected cleanup failure.'
    }

    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    $source = $baseSource
    $source = $source.Replace(
        '$ProgramDataRoot = Join-Path $env:ProgramData ''BlueVPNTransportPreview''',
        ('$ProgramDataRoot = ''' + $quotedRoot + '''')
    )
    $source = $source.Replace(
        '$ProbeTunnelName = ''GreenVPNTransportPreviewStandbyProbe''',
        '$ProbeTunnelName = ''GreenVPNStandbyProbeContractTest'''
    )
    $source = $source.Replace(
        '    Protect-PrivatePath -Path $RuntimeRoot -Directory',
        '    # The disposable contract runtime stays accessible to both child runs.'
    )
    $transientInjection = @'
$transientCleanupCallCount = 0
function Stop-ProbeProcesses {
    $script:transientCleanupCallCount++
    if ($script:transientCleanupCallCount -eq 2) {
        throw 'injected transient cleanup failure'
    }
}
function Stop-StaleProbeProcesses {}
function Stop-NativeProbe {}
function Remove-ProbeEndpointBypassRoutes {}
function Remove-AllProbeEndpointBypassRoutes {}
'@
    $source = $source.Replace(
        '$stage = ''request''',
        ($transientInjection + [Environment]::NewLine + '$stage = ''request''')
    )
    [IO.File]::WriteAllText(
        $testScript,
        $source,
        [Text.UTF8Encoding]::new($false)
    )
    $transientChild = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'RemoteSigned',
        '-File', ('"' + $testScript + '"')
    ) -WindowStyle Hidden -Wait -PassThru
    $report.transientChildExitCode = [int]$transientChild.ExitCode
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw 'Transient cleanup failure did not produce a standby result.'
    }
    $transientResult = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $report.transientCleanupOk = $transientResult.cleanupOk
    $report.transientErrorCode = [string]$transientResult.errorCode
    $report.transientCleanupErrors = @($transientResult.cleanupErrors)
    if ($transientResult.cleanupOk -ne $true -or
        [string]$transientResult.errorCode -eq 'cleanup_failed' -or
        'tracked_processes' -in @($transientResult.cleanupErrors)) {
        throw 'Standby cleanup did not recover from a transient cleanup race.'
    }
    $report.success = $true
} catch {
    $report.failure = $_.Exception.Message
} finally {
    $report.completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        $fullReportPath = [IO.Path]::GetFullPath($ReportPath)
        New-Item -ItemType Directory -Force -Path (
            Split-Path -Parent $fullReportPath
        ) | Out-Null
        [IO.File]::WriteAllText(
            $fullReportPath,
            ($report | ConvertTo-Json -Depth 6) + [Environment]::NewLine,
            [Text.UTF8Encoding]::new($false)
        )
    }
    if (-not $KeepArtifacts) {
        $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        if (-not $resolvedTestRoot.StartsWith(
            $resolvedTemp,
            [StringComparison]::OrdinalIgnoreCase
        ) -or (Split-Path -Leaf $resolvedTestRoot) -notlike
            'green-vpn-standby-result-contract-*') {
            throw 'Refusing to remove an unsafe standby contract test path.'
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force `
            -ErrorAction SilentlyContinue
    }
}

if (-not $report.success) {
    throw $report.failure
}
Write-Output 'Windows standby result contract test passed.'
