param(
    [switch]$SaveReport
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ('=' * 80) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('=' * 80) -ForegroundColor Cyan
}

function Add-ReportLine {
    param(
        [System.Collections.Generic.List[string]]$Report,
        [string]$Line
    )
    $Report.Add($Line) | Out-Null
}

function Test-Admin {
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-FirstExistingPath {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }
    return $null
}

function Get-FileStatusText {
    param([string]$Path)
    if (Test-Path $Path) {
        return "[OK] $Path"
    }
    return "[MISS] $Path"
}

function Get-ConfigSummary {
    param([string]$Path)

    if (!(Test-Path $Path)) {
        return @("Missing: $Path")
    }

    $wanted = @('Address', 'DNS', 'MTU', 'AllowedIPs', 'Endpoint', 'PersistentKeepalive')
    $lines = Get-Content $Path
    $result = New-Object System.Collections.Generic.List[string]

    foreach ($key in $wanted) {
        $match = $lines | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -First 1
        if ($match) {
            $result.Add($match.Trim()) | Out-Null
        }
    }

    if ($result.Count -eq 0) {
        $result.Add('No summary keys found.') | Out-Null
    }

    return $result
}

function Get-CommandOutput {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    try {
        $output = & $FilePath @Arguments 2>&1 | Out-String
        if ([string]::IsNullOrWhiteSpace($output)) {
            return '[no output]'
        }
        return $output.TrimEnd()
    } catch {
        return "[command failed] $($_.Exception.Message)"
    }
}

function Get-TextTail {
    param(
        [string]$Path,
        [int]$Tail = 40
    )

    if (!(Test-Path $Path)) {
        return @("Missing: $Path")
    }

    try {
        return Get-Content $Path -Tail $Tail
    } catch {
        return @("Could not read: $Path", $_.Exception.Message)
    }
}

$projectRoot = $null
try {
    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
} catch {
    $projectRoot = Join-Path $env:USERPROFILE 'projects\bluevpn'
}

$programDataDir = Join-Path $env:ProgramData 'BlueVPN'
$appDataDir = Join-Path $env:APPDATA 'BlueVPN'
$serviceName = 'WireGuardTunnel$BlueVPN'

$wireguardExe = Get-FirstExistingPath @(
    (Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe')
)

$mainPath = Join-Path $projectRoot 'lib\main.dart'
$confPath = Join-Path $programDataDir 'BlueVPN.conf'
$baseConfPath = Join-Path $programDataDir 'BlueVPN.base.conf'
$backendLogPath = Join-Path $programDataDir 'backend.log'
$prefsPath = Join-Path $appDataDir 'prefs.json'
$sessionPath = Join-Path $appDataDir 'session.json'

$report = New-Object 'System.Collections.Generic.List[string]'

Write-Section 'BLUEVPN DOCTOR'
$headerLines = @(
    "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "Admin: $(Test-Admin)",
    "ProjectRoot: $projectRoot",
    "ProgramDataDir: $programDataDir",
    "AppDataDir: $appDataDir",
    "Tunnel service: $serviceName",
    "WireGuard EXE: $wireguardExe"
)
$headerLines | ForEach-Object { Write-Host $_; Add-ReportLine $report $_ }

Write-Section 'KEY FILES'
$keyFiles = @(
    $mainPath,
    $confPath,
    $baseConfPath,
    $backendLogPath,
    $prefsPath,
    $sessionPath
)
foreach ($file in $keyFiles) {
    $line = Get-FileStatusText $file
    Write-Host $line
    Add-ReportLine $report $line
}

Write-Section 'SERVICE'
$scPath = 'sc.exe'
$qcOutput = Get-CommandOutput -FilePath $scPath -Arguments @('qc', $serviceName)
$queryOutput = Get-CommandOutput -FilePath $scPath -Arguments @('queryex', $serviceName)
Write-Host 'sc qc:'
Write-Host $qcOutput
Write-Host ''
Write-Host 'sc queryex:'
Write-Host $queryOutput
Add-ReportLine $report 'sc qc:'
Add-ReportLine $report $qcOutput
Add-ReportLine $report ''
Add-ReportLine $report 'sc queryex:'
Add-ReportLine $report $queryOutput

Write-Section 'CONFIG SUMMARY'
Write-Host '[BlueVPN.conf]'
Add-ReportLine $report '[BlueVPN.conf]'
foreach ($line in (Get-ConfigSummary -Path $confPath)) {
    Write-Host $line
    Add-ReportLine $report $line
}
Write-Host ''
Write-Host '[BlueVPN.base.conf]'
Add-ReportLine $report ''
Add-ReportLine $report '[BlueVPN.base.conf]'
foreach ($line in (Get-ConfigSummary -Path $baseConfPath)) {
    Write-Host $line
    Add-ReportLine $report $line
}

Write-Section 'PREFS / SESSION'
if (Test-Path $prefsPath) {
    Write-Host '[prefs.json]'
    Add-ReportLine $report '[prefs.json]'
    $prefsRaw = Get-Content $prefsPath -Raw
    Write-Host $prefsRaw
    Add-ReportLine $report $prefsRaw
} else {
    Write-Host 'prefs.json missing'
    Add-ReportLine $report 'prefs.json missing'
}
Write-Host ''
if (Test-Path $sessionPath) {
    Write-Host '[session.json]'
    Add-ReportLine $report ''
    Add-ReportLine $report '[session.json]'
    $sessionRaw = Get-Content $sessionPath -Raw
    Write-Host $sessionRaw
    Add-ReportLine $report $sessionRaw
} else {
    Write-Host 'session.json missing'
    Add-ReportLine $report 'session.json missing'
}

Write-Section 'BACKEND.LOG TAIL'
foreach ($line in (Get-TextTail -Path $backendLogPath -Tail 40)) {
    Write-Host $line
    Add-ReportLine $report $line
}

if ($SaveReport) {
    Write-Section 'SAVE REPORT'

    $desktopPath = Get-FirstExistingPath @(
        (Join-Path $env:USERPROFILE 'OneDrive\Desktop'),
        (Join-Path $env:USERPROFILE 'Desktop')
    )

    if (-not $desktopPath) {
        $desktopPath = $env:TEMP
    }

    $reportName = 'bluevpn_doctor_report_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss')
    $reportPath = Join-Path $desktopPath $reportName

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($reportPath, $report, $utf8NoBom)
        Write-Host "Report saved: $reportPath" -ForegroundColor Green
    } catch {
        Write-Host "Could not save report: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Section 'DONE'
Write-Host 'Check complete.'
