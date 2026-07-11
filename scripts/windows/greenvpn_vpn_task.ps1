param(
    [ValidateSet('Connect', 'Disconnect', 'Guard')]
    [string]$Action = 'Guard'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TunnelName = 'BlueVPNDev1'
$ServiceName = 'WireGuardTunnel$BlueVPNDev1'
$ProgramDataRoot = Join-Path $env:ProgramData 'BlueVPN'
$ConfigPath = Join-Path $ProgramDataRoot 'BlueVPNDev1.conf'
$LogPath = Join-Path $ProgramDataRoot 'backend.log'

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

function Get-OwnService {
    try {
        return Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    } catch {
        return $null
    }
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

    try {
        $services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -eq 'Running' -and
                (
                    ($_.Name -like 'WireGuardTunnel$*' -and $_.Name -ne $ServiceName) -or
                    ($_.Name -like 'AmneziaWGTunnel$*') -or
                    ($_.Name -match '(?i)(CloudflareWARP|Cloudflare WARP)')
                )
            }
        foreach ($service in $services) {
            $labels.Add("service:$($service.Name)") | Out-Null
        }
    } catch {
        Write-GreenLog "service competition check warning: $($_.Exception.Message)"
    }

    return @($labels | Sort-Object -Unique)
}

function Stop-GreenTunnel {
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
        return
    }

    try {
        Invoke-External -FilePath $wg -Arguments @('/uninstalltunnelservice', $TunnelName) -AllowedExitCodes @(0, 1) | Out-Null
    } catch {
        Write-GreenLog "wireguard uninstall warning: $($_.Exception.Message)"
    }
}

function Start-GreenTunnel {
    Ensure-GreenProgramDataAcl

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-GreenLog "config missing: $ConfigPath"
        exit 3
    }

    $competitors = @(Get-CompetingVpnLabels)
    if ($competitors.Count -gt 0) {
        Write-GreenLog "connect blocked because another VPN is active: $($competitors -join ', ')"
        Stop-GreenTunnel
        exit 2
    }

    Ensure-NativeFullTunnelKillSwitch

    $wg = Resolve-WireGuardExe
    if ([string]::IsNullOrWhiteSpace($wg)) {
        Write-GreenLog 'WireGuard executable not found'
        exit 4
    }

    Stop-GreenTunnel
    Ensure-GreenProgramDataAcl

    Invoke-External -FilePath $wg -Arguments @('/installtunnelservice', $ConfigPath) -AllowedExitCodes @(0) | Out-Null
    Invoke-External -FilePath 'sc.exe' -Arguments @('config', $ServiceName, 'start=', 'demand') -AllowedExitCodes @(0) | Out-Null
    Invoke-External -FilePath 'sc.exe' -Arguments @('start', $ServiceName) -AllowedExitCodes @(0, 1056) | Out-Null
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

    $competitors = @(Get-CompetingVpnLabels)
    if ($competitors.Count -gt 0) {
        Write-GreenLog "guard disconnecting Green VPN because another VPN is active: $($competitors -join ', ')"
        Stop-GreenTunnel
    }
}

try {
    Write-GreenLog 'started'
    switch ($Action) {
        'Connect' { Start-GreenTunnel }
        'Disconnect' { Ensure-GreenProgramDataAcl; Stop-GreenTunnel }
        'Guard' { Invoke-GreenGuard }
    }
    Write-GreenLog 'finished'
    exit 0
} catch {
    Write-GreenLog "failed: $($_.Exception.Message)"
    exit 10
}
