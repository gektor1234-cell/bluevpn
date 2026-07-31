param(
    [Parameter(Mandatory=$true)][string]$InstallerPath,
    [ValidateSet('production', 'paid-beta')][string]$Channel = 'production',
    [string]$ReportPath = '',
    [string]$KeepExtractedPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Utf8Bom {
    param([Parameter(Mandatory=$true)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    return $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
}

function New-UnicodeString {
    param([Parameter(Mandatory=$true)][int[]]$CodePoints)
    return -join @($CodePoints | ForEach-Object { [char]$_ })
}

$resolvedInstaller = (Resolve-Path -LiteralPath $InstallerPath).Path
$root = Join-Path $env:TEMP ("GreenVpnPackageAudit_" + [guid]::NewGuid().ToString('N'))
$errors = New-Object System.Collections.Generic.List[string]

try {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $process = Start-Process -FilePath $resolvedInstaller -ArgumentList @('/Q', "/T:$root", '/C') -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(30000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw 'IExpress extraction did not finish within 30 seconds.'
    }
    if ($process.ExitCode -ne 0) {
        throw "IExpress extraction failed with exit code $($process.ExitCode)."
    }

    $requiredFiles = @(
        'install_bootstrap.exe',
        'install_ui.ps1',
        'install_greenvpn.ps1',
        'GreenVPN_payload.zip',
        'app_icon.ico'
    )
    foreach ($name in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $name))) {
            $errors.Add("Missing extracted installer file: $name") | Out-Null
        }
    }

    $uiPath = Join-Path $root 'install_ui.ps1'
    $installPath = Join-Path $root 'install_greenvpn.ps1'
    foreach ($scriptPath in @($uiPath, $installPath)) {
        if ((Test-Path -LiteralPath $scriptPath) -and -not (Test-Utf8Bom -Path $scriptPath)) {
            $errors.Add("Installer script is not UTF-8 BOM safe: $([IO.Path]::GetFileName($scriptPath))") | Out-Null
        }
    }

    if ((Test-Path -LiteralPath $uiPath) -and (Test-Path -LiteralPath $installPath)) {
        $ui = [IO.File]::ReadAllText($uiPath, [Text.UTF8Encoding]::new($true))
        $install = [IO.File]::ReadAllText($installPath, [Text.UTF8Encoding]::new($true))
        $mojibakeMarkers = @(
            (New-UnicodeString -CodePoints @(0x0420, 0x0408)),
            (New-UnicodeString -CodePoints @(0x0420, 0x2014)),
            (New-UnicodeString -CodePoints @(0x0421, 0x0453))
        )
        foreach ($marker in $mojibakeMarkers) {
            if ($ui.Contains($marker) -or $install.Contains($marker)) {
                $errors.Add('Installer contains corrupted localized text.') | Out-Null
                break
            }
        }
        foreach ($fragment in @(
            'GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS',
            '$form.Close()'
        )) {
            if (-not $ui.Contains($fragment)) {
                $errors.Add("Installer UI smoke contract missing: $fragment") | Out-Null
            }
        }
        if (-not $install.Contains('GREENVPN_INSTALLER_SKIP_APP_LAUNCH')) {
            $errors.Add('Installer execution smoke contract missing: GREENVPN_INSTALLER_SKIP_APP_LAUNCH') |
                Out-Null
        }

        if ($Channel -eq 'production') {
            foreach ($fragment in @(
                '[string]$InstallDir = "$env:ProgramFiles\Green VPN"',
                'CommonDesktopDirectory',
                'CommonPrograms',
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN",
                "'*S-1-5-32-545:(OI)(CI)RX'",
                "(Join-Path `$stagingRoot '*') /reset /T /C",
                'Test-FileAclAllows',
                'function Remove-CorruptInstallRoot',
                'takeown.exe /F $Root /A /R /D Y',
                'Remove-CorruptInstallRoot -Root $installRoot',
                'function Move-DirectoryWithRetry',
                '$runtimeStopped = $true',
                '$existingRootBackedUp = $true',
                'Green VPN installation postcondition failed',
                '$stagingRoot = "$installRoot.staging-$swapId"',
                '$existingInstallValid = Test-GreenVpnInstalledRoot -Root $installRoot',
                'if (-not $installCompleted -and ($runtimeStopped -or $existingRootBackedUp -or $installSwapped))',
                "`$installErrorLog = Join-Path `$env:TEMP 'GreenVPN_Setup_error.log'",
                '$launchAfterInstall = -not $NoLaunch',
                'Resolve-InstallingUserSid',
                '[string]$OwnerSid = ""',
                '-OwnerSid',
                "/remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' /T /C",
                "Ensure-GreenVpnProgramDataAcl -UserSid `$installingUserSid",
                "Ensure-GreenVpnServiceToken -UserSid `$installingUserSid"
            )) {
                if (-not $install.Contains($fragment)) {
                    $errors.Add("Production install contract missing: $fragment") | Out-Null
                }
            }
            foreach ($forbiddenFragment in @('$legacyInstallRoot', '$legacyGreenInstallRoot')) {
                if ($install.Contains($forbiddenFragment)) {
                    $errors.Add("Production install contract contains an undefined legacy path: $forbiddenFragment") | Out-Null
                }
            }
        }
        else {
            foreach ($fragment in @(
                '[string]$InstallDir = "$env:ProgramFiles\Green VPN Beta"',
                'CommonDesktopDirectory',
                'CommonPrograms',
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN Beta",
                "'*S-1-5-32-545:(OI)(CI)RX'",
                "(Join-Path `$stagingRoot '*') /reset /T /C",
                'Test-FileAclAllows',
                'function Remove-CorruptInstallRoot',
                'takeown.exe /F $Root /A /R /D Y',
                'Remove-CorruptInstallRoot -Root $installRoot',
                'function Move-DirectoryWithRetry',
                '$runtimeStopped = $true',
                '$existingRootBackedUp = $true',
                '$legacyInstallValid',
                'Green VPN Beta installation postcondition failed',
                '$stagingRoot = "$installRoot.staging-$swapId"',
                '$existingInstallValid = Test-BetaInstalledRoot -Root $installRoot',
                'if (-not $installCompleted -and ($runtimeStopped -or $existingRootBackedUp -or $installSwapped))',
                'restoring the previous beta version',
                "`$installErrorLog = Join-Path `$env:TEMP 'GreenVPN_Beta_Setup_error.log'",
                '$launchAfterInstall = -not $NoLaunch',
                'Resolve-InstallingUserSid',
                '[string]$OwnerSid = ""',
                '-OwnerSid',
                "/remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' /T /C",
                "Ensure-BetaProgramData -UserSid `$installingUserSid"
            )) {
                if (-not $install.Contains($fragment)) {
                    $errors.Add("Beta install contract missing: $fragment") | Out-Null
                }
            }
        }
        foreach ($forbiddenFragment in @(
            "'*S-1-5-11:(OI)(CI)M'",
            "'*S-1-5-11:R'"
        )) {
            if ($install.Contains($forbiddenFragment)) {
                $errors.Add("Installer grants broad machine-state access: $forbiddenFragment") | Out-Null
            }
        }
    }

    $payloadPath = Join-Path $root 'GreenVPN_payload.zip'
    $entryNames = @()
    if (Test-Path -LiteralPath $payloadPath) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($payloadPath)
        try {
            $entryNames = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/').ToLowerInvariant() })
        }
        finally {
            $zip.Dispose()
        }
        $processRouterPayload = @(
            'tools/process-router/proxybridge_cli.exe',
            'tools/process-router/proxybridgecore.dll',
            'tools/process-router/windivert.dll',
            'tools/process-router/windivert64.sys',
            'tools/process-router/provenance.md',
            'tools/process-router/third_party_notices.txt',
            'tools/process-router/proxybridge_license.txt',
            'tools/process-router/windivert_license.txt'
        )
        $requiredPayload = if ($Channel -eq 'production') {
            @(
                'app/greenvpn.exe',
                'app/greenvpn_service.exe',
                'tools/greenvpn_vpn_task.ps1',
                'tools/greenvpn_selective_routing.ps1'
            ) + $processRouterPayload
        }
        else {
            @(
                'app/greenvpn_beta.exe',
                'app/greenvpn_beta_service.exe',
                'tools/greenvpn_vpn_task.ps1',
                'tools/greenvpn_selective_routing.ps1',
                'tools/uninstall_greenvpn_beta.ps1'
            ) + $processRouterPayload
        }
        foreach ($entry in $requiredPayload) {
            if ($entryNames -notcontains $entry) {
                $errors.Add("Payload entry missing: $entry") | Out-Null
            }
        }

        $zip = [IO.Compression.ZipFile]::OpenRead($payloadPath)
        try {
            $vpnTaskEntry = $zip.Entries | Where-Object {
                $_.FullName.Replace('\', '/').ToLowerInvariant() -eq 'tools/greenvpn_vpn_task.ps1'
            } | Select-Object -First 1
            if ($null -eq $vpnTaskEntry) {
                $errors.Add('Packaged Windows VPN task entry is missing.') | Out-Null
            }
            else {
                $reader = [IO.StreamReader]::new($vpnTaskEntry.Open())
                try {
                    $vpnTaskText = $reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                }
                $selectiveEntry = $zip.Entries | Where-Object {
                    $_.FullName.Replace('\', '/').ToLowerInvariant() -eq 'tools/greenvpn_selective_routing.ps1'
                } | Select-Object -First 1
                $selectiveText = ''
                if ($null -ne $selectiveEntry) {
                    $selectiveReader = [IO.StreamReader]::new($selectiveEntry.Open())
                    try {
                        $selectiveText = $selectiveReader.ReadToEnd()
                    }
                    finally {
                        $selectiveReader.Dispose()
                    }
                }
                $combinedTaskText = $vpnTaskText + "`n" + $selectiveText
                foreach ($marker in @(
                    'greenvpn_selective_routing.ps1',
                    'Get-GreenRoutingPolicy',
                    'destinationCidrs',
                    'Get-GreenDestinationCidrs',
                    'process router not required',
                    "Selective application routing is not supported by `$protocol.",
                    'function Get-CompetingVpnServices',
                    'function Stop-CompetingVpnTunnels',
                    "Stop-CompetingVpnTunnels -Reason 'connect'",
                    "Stop-CompetingVpnTunnels -Reason 'guard'",
                    'takeover complete reason=$Reason',
                    'function Get-SafePhysicalEndpointRoute',
                    'physical gateway settled after takeover'
                )) {
                    if (-not $combinedTaskText.Contains($marker)) {
                        $errors.Add("Packaged Windows VPN task marker missing: $marker") | Out-Null
                    }
                }
            }
        }
        finally {
            $zip.Dispose()
        }
    }

    $report = [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        success = $errors.Count -eq 0
        channel = $Channel
        installerSha256 = (Get-FileHash -LiteralPath $resolvedInstaller -Algorithm SHA256).Hash
        installerSizeBytes = (Get-Item -LiteralPath $resolvedInstaller).Length
        extractedFileCount = @(Get-ChildItem -LiteralPath $root -File).Count
        payloadEntryCount = $entryNames.Count
        errors = @($errors)
    }
    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        $parent = Split-Path -Parent $ReportPath
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    }
    if (-not [string]::IsNullOrWhiteSpace($KeepExtractedPath)) {
        Remove-Item -LiteralPath $KeepExtractedPath -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $KeepExtractedPath -Force | Out-Null
        Get-ChildItem -LiteralPath $root -Force | Copy-Item -Destination $KeepExtractedPath -Recurse -Force
    }
    $report | ConvertTo-Json -Depth 5
    if ($errors.Count -gt 0) {
        throw "Public installer package audit failed with $($errors.Count) error(s)."
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
