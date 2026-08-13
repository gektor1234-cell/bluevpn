param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.." )).Path,
    [string]$OutBase = "C:\BlueVPN_Builds",
    [string]$ReleaseZip = "",
    [string]$InstallerName = "GreenVPN_Setup.exe",
    [string]$AppVersion = "0.2.39-windows-clean-server-ui",
    [string]$WindowsBuildName = "",
    [ValidateRange(0, 65535)]
    [int]$WindowsBuildNumber = 0,
    [string]$ApiBaseUrl = "https://api.greenvpn.pro",
    [string]$ApiFallbackBaseUrls = "https://176-113-81-35.sslip.io",
    [bool]$TrialOnlyNoAdsBuild = $true,
    [bool]$PaidBetaBuild = $false,
    [bool]$PublicProductBuild = $false,
    [bool]$EnableFusionUi = $false,
    [switch]$AllowFusionProductionPromotionCandidate,
    [bool]$EnableTransportCascade = $false,
    [ValidateSet('stable', 'paid-beta')]
    [string]$WindowsRuntimeScope = 'stable',
    [string]$UpdateChannelOverride = '',
    [string]$ProcessRouterRoot = $env:GREENVPN_PROCESS_ROUTER_ROOT,
    [string]$CertificateThumbprint = $env:GREENVPN_WINDOWS_CODE_SIGNING_CERT_THUMBPRINT,
    [string]$CodeSigningExpectedPublisher = $env:GREENVPN_WINDOWS_CODE_SIGNING_PUBLISHER,
    [string]$CodeSigningTimestampUrl = 'http://timestamp.digicert.com',
    [string]$SigningReportDir = '',
    [switch]$RequireCodeSigning,
    [switch]$SkipBuild,
    [switch]$OpenFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$normalizedCertificateThumbprint = ($CertificateThumbprint -replace '\s+', '').ToUpperInvariant()
if (
    -not [string]::IsNullOrWhiteSpace($normalizedCertificateThumbprint) -and
    $normalizedCertificateThumbprint -notmatch '^[0-9A-F]{40}$'
) {
    throw 'CertificateThumbprint must be a 40-character SHA-1 thumbprint.'
}
$codeSigningEnabled = -not [string]::IsNullOrWhiteSpace($normalizedCertificateThumbprint)
if ($RequireCodeSigning -and -not $codeSigningEnabled) {
    throw 'RequireCodeSigning was requested, but no code-signing certificate thumbprint was supplied.'
}
if ($RequireCodeSigning -and [string]::IsNullOrWhiteSpace($CodeSigningExpectedPublisher)) {
    throw 'RequireCodeSigning was requested, but CodeSigningExpectedPublisher is empty.'
}
if ($codeSigningEnabled -and -not [string]::IsNullOrWhiteSpace($ReleaseZip)) {
    throw 'Code signing requires a freshly generated payload; ReleaseZip must be empty.'
}
$signScriptPath = Join-Path $ProjectRoot 'scripts\windows\sign_release_artifacts.ps1'
if ($codeSigningEnabled -and -not (Test-Path -LiteralPath $signScriptPath -PathType Leaf)) {
    throw "Code-signing helper was not found: $signScriptPath"
}

if ([string]::IsNullOrWhiteSpace($ProcessRouterRoot)) {
    $ProcessRouterRoot = Join-Path $ProjectRoot 'third_party\windows\process_router'
}

if ([string]::IsNullOrWhiteSpace($WindowsBuildName)) {
    if ($AppVersion -notmatch '^(\d+)\.(\d+)\.(\d+)') {
        throw "AppVersion must start with a numeric x.y.z version: $AppVersion"
    }
    $WindowsBuildName = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
}
if ($WindowsBuildName -notmatch '^\d+\.\d+\.\d+$') {
    throw "WindowsBuildName must be a numeric x.y.z version: $WindowsBuildName"
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
}

function Invoke-CodeSigningStage {
    param(
        [Parameter(Mandatory=$true)][string[]]$ArtifactPath,
        [Parameter(Mandatory=$true)][string[]]$RequiredLeafName,
        [Parameter(Mandatory=$true)][string]$ReportPath
    )

    if (-not $codeSigningEnabled) {
        return
    }
    & $signScriptPath `
        -CertificateThumbprint $normalizedCertificateThumbprint `
        -Path $ArtifactPath `
        -TimestampUrl $CodeSigningTimestampUrl `
        -ExpectedPublisher $CodeSigningExpectedPublisher `
        -RequiredLeafName $RequiredLeafName `
        -ReportPath $ReportPath
    if (-not $?) {
        throw 'Code-signing stage failed.'
    }
}

function Assert-SafeChildPath {
    param(
        [string]$BasePath,
        [string]$CandidatePath
    )

    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $candidate = [System.IO.Path]::GetFullPath($CandidatePath)
    if (-not $candidate.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe path outside base. Base=$base Candidate=$candidate"
    }
}

function Set-ExeIcon {
    param(
        [string]$ExePath,
        [string]$IconPath
    )

    if (-not (Test-Path -LiteralPath $ExePath)) { return }
    if (-not (Test-Path -LiteralPath $IconPath)) { return }

    if (-not ([System.Management.Automation.PSTypeName]'GreenVpn.IconResourceUpdater').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace GreenVpn {
    public static class IconResourceUpdater {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern IntPtr BeginUpdateResource(string pFileName, bool bDeleteExistingResources);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool UpdateResource(IntPtr hUpdate, IntPtr lpType, IntPtr lpName, ushort wLanguage, byte[] lpData, int cbData);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool EndUpdateResource(IntPtr hUpdate, bool fDiscard);
    }
}
"@
    }

    $iconBytes = [System.IO.File]::ReadAllBytes($IconPath)
    if ($iconBytes.Length -lt 6) { throw "Invalid icon file: $IconPath" }

    $count = [BitConverter]::ToUInt16($iconBytes, 4)
    if ($count -le 0) { throw "Icon has no images: $IconPath" }

    $h = [GreenVpn.IconResourceUpdater]::BeginUpdateResource($ExePath, $false)
    if ($h -eq [IntPtr]::Zero) {
        throw "BeginUpdateResource failed for $ExePath"
    }

    $discard = $true
    try {
        $groupStream = New-Object System.IO.MemoryStream
        $writer = New-Object System.IO.BinaryWriter($groupStream)
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$count)

        for ($i = 0; $i -lt $count; $i++) {
            $entryOffset = 6 + ($i * 16)
            $width = $iconBytes[$entryOffset]
            $height = $iconBytes[$entryOffset + 1]
            $colorCount = $iconBytes[$entryOffset + 2]
            $reserved = $iconBytes[$entryOffset + 3]
            $planes = [BitConverter]::ToUInt16($iconBytes, $entryOffset + 4)
            $bitCount = [BitConverter]::ToUInt16($iconBytes, $entryOffset + 6)
            $bytesInRes = [BitConverter]::ToUInt32($iconBytes, $entryOffset + 8)
            $imageOffset = [BitConverter]::ToUInt32($iconBytes, $entryOffset + 12)
            $resourceId = [UInt16]($i + 1)

            $image = New-Object byte[] $bytesInRes
            [Array]::Copy($iconBytes, [int]$imageOffset, $image, 0, [int]$bytesInRes)

            $ok = [GreenVpn.IconResourceUpdater]::UpdateResource(
                $h,
                [IntPtr]3,
                [IntPtr]$resourceId,
                [UInt16]0,
                $image,
                $image.Length
            )
            if (-not $ok) { throw "UpdateResource RT_ICON failed for $ExePath" }

            $writer.Write([Byte]$width)
            $writer.Write([Byte]$height)
            $writer.Write([Byte]$colorCount)
            $writer.Write([Byte]$reserved)
            $writer.Write([UInt16]$planes)
            $writer.Write([UInt16]$bitCount)
            $writer.Write([UInt32]$bytesInRes)
            $writer.Write([UInt16]$resourceId)
        }

        $groupBytes = $groupStream.ToArray()
        $ok = [GreenVpn.IconResourceUpdater]::UpdateResource(
            $h,
            [IntPtr]14,
            [IntPtr]1,
            [UInt16]0,
            $groupBytes,
            $groupBytes.Length
        )
        if (-not $ok) { throw "UpdateResource RT_GROUP_ICON failed for $ExePath" }
        $discard = $false
    }
    finally {
        [void][GreenVpn.IconResourceUpdater]::EndUpdateResource($h, $discard)
    }
}

function Set-ExeAsInvoker {
    param([Parameter(Mandatory=$true)][string]$ExePath)

    if (-not (Test-Path -LiteralPath $ExePath)) { return }

    if (-not ([System.Management.Automation.PSTypeName]'GreenVpn.IconResourceUpdater').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace GreenVpn {
    public static class IconResourceUpdater {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern IntPtr BeginUpdateResource(string pFileName, bool bDeleteExistingResources);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool UpdateResource(IntPtr hUpdate, IntPtr lpType, IntPtr lpName, ushort wLanguage, byte[] lpData, int cbData);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool EndUpdateResource(IntPtr hUpdate, bool fDiscard);
    }
}
"@
    }

    $manifest = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity version="1.0.0.0" processorArchitecture="*" name="GreenVPN.Setup" type="win32"/>
  <description>Green VPN Installer</description>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
'@

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($manifest)
    $h = [GreenVpn.IconResourceUpdater]::BeginUpdateResource($ExePath, $false)
    if ($h -eq [IntPtr]::Zero) {
        throw "BeginUpdateResource failed for manifest: $ExePath"
    }

    $discard = $true
    try {
        $ok = [GreenVpn.IconResourceUpdater]::UpdateResource(
            $h,
            [IntPtr]24,
            [IntPtr]1,
            [UInt16]0,
            $bytes,
            $bytes.Length
        )
        if (-not $ok) { throw "UpdateResource RT_MANIFEST failed for $ExePath" }
        $discard = $false
    }
    finally {
        [void][GreenVpn.IconResourceUpdater]::EndUpdateResource($h, $discard)
    }
}

if (-not (Get-Command iexpress.exe -ErrorAction SilentlyContinue)) {
    throw "iexpress.exe not found. It is required for the single-file Windows installer."
}

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    throw "ProjectRoot does not exist: $ProjectRoot"
}

if (
    $EnableFusionUi -and
    -not $PaidBetaBuild -and
    -not ($PublicProductBuild -and $AllowFusionProductionPromotionCandidate)
) {
    throw "Fusion UI requires isolated paid-beta or an explicit production promotion candidate gate."
}
if ($AllowFusionProductionPromotionCandidate -and (-not $EnableFusionUi -or -not $PublicProductBuild)) {
    throw "Fusion production promotion gate requires EnableFusionUi=true and PublicProductBuild=true."
}

if ($PaidBetaBuild) {
    if ($TrialOnlyNoAdsBuild) {
        throw "Paid beta build cannot also be a Trial-only build."
    }
    if (-not $ApiBaseUrl.Contains('/paid-beta-api')) {
        throw "Paid beta primary API must use the isolated /paid-beta-api contour."
    }
    if (-not $ApiFallbackBaseUrls.Contains('/paid-beta-api')) {
        throw "Paid beta fallback API must use the isolated /paid-beta-api contour."
    }
    if ($WindowsRuntimeScope -ne 'paid-beta') {
        throw "Paid beta Windows build must use the isolated paid-beta runtime scope."
    }
    if ($SkipBuild -or -not [string]::IsNullOrWhiteSpace($ReleaseZip)) {
        throw "Paid beta Windows must be built cleanly from source; reused release payloads are not allowed."
    }
} elseif ($WindowsRuntimeScope -ne 'stable') {
    throw "The paid-beta Windows runtime scope requires PaidBetaBuild=true."
}
if ($PublicProductBuild) {
    if ($TrialOnlyNoAdsBuild -or $PaidBetaBuild) {
        throw "Public product build cannot also be Trial-only or paid-beta."
    }
    if ($WindowsRuntimeScope -ne 'stable') {
        throw "Public product Windows build must use the stable runtime scope."
    }
}
if (
    -not [string]::IsNullOrWhiteSpace($UpdateChannelOverride) -and
    $UpdateChannelOverride -notin @('stable', 'paid-beta', 'preview', 'public-product')
) {
    throw "Unsupported update channel override: $UpdateChannelOverride"
}
$effectiveUpdateChannel = if (-not [string]::IsNullOrWhiteSpace($UpdateChannelOverride)) {
    $UpdateChannelOverride.Trim().ToLowerInvariant()
} elseif ($PaidBetaBuild) {
    'paid-beta'
} elseif ($PublicProductBuild) {
    'public-product'
} else {
    'stable'
}

$runtime = if ($WindowsRuntimeScope -eq 'paid-beta') {
    [ordered]@{
        GREENVPN_WINDOWS_RUNTIME_SCOPE = 'paid-beta'
        GREENVPN_WINDOWS_TUNNEL_NAME = 'GreenVPNBeta'
        GREENVPN_WINDOWS_SERVICE_NAME = 'GreenVPNBetaService'
        GREENVPN_WINDOWS_PROGRAM_DATA_SUBDIR = 'BlueVPNBeta'
        GREENVPN_WINDOWS_USER_DATA_SUBDIR = 'GreenVPNBeta'
        GREENVPN_WINDOWS_LOCAL_SERVICE_PORT = '48738'
        GREENVPN_WINDOWS_INSTANCE_ID = 'GreenVPNBeta'
        GREENVPN_WINDOWS_EXECUTABLE_NAME = 'greenvpn_beta.exe'
        GREENVPN_PRODUCT_NAME = 'Green VPN Beta'
    }
} else {
    [ordered]@{
        GREENVPN_WINDOWS_RUNTIME_SCOPE = 'stable'
        GREENVPN_WINDOWS_TUNNEL_NAME = 'BlueVPNDev1'
        GREENVPN_WINDOWS_SERVICE_NAME = 'GreenVPNService'
        GREENVPN_WINDOWS_PROGRAM_DATA_SUBDIR = 'BlueVPN'
        GREENVPN_WINDOWS_USER_DATA_SUBDIR = 'GreenVPN'
        GREENVPN_WINDOWS_LOCAL_SERVICE_PORT = '48737'
        GREENVPN_WINDOWS_INSTANCE_ID = 'GreenVPN'
        GREENVPN_WINDOWS_EXECUTABLE_NAME = 'bluevpn.exe'
        GREENVPN_PRODUCT_NAME = 'Green VPN'
    }
}

New-Item -ItemType Directory -Force -Path $OutBase | Out-Null

$workRoot = Join-Path $OutBase '_installer_work'
$payloadDir = Join-Path $workRoot 'payload'
$installerPath = Join-Path $OutBase $InstallerName
$signingReportStem = [IO.Path]::GetFileNameWithoutExtension($InstallerName) -replace '[^A-Za-z0-9._-]', '_'
if ([string]::IsNullOrWhiteSpace($SigningReportDir)) {
    $SigningReportDir = Join-Path $OutBase 'signing_reports'
}
if ($codeSigningEnabled) {
    New-Item -ItemType Directory -Force -Path $SigningReportDir | Out-Null
}

Assert-SafeChildPath -BasePath $OutBase -CandidatePath $workRoot
if (Test-Path -LiteralPath $workRoot) {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null

if ([string]::IsNullOrWhiteSpace($ReleaseZip)) {
    if (-not $SkipBuild) {
        Write-Section 'BUILD WINDOWS RELEASE'
        $trialOnlyDefine = $TrialOnlyNoAdsBuild.ToString().ToLowerInvariant()
        $paidBetaDefine = $PaidBetaBuild.ToString().ToLowerInvariant()
        $publicProductDefine = $PublicProductBuild.ToString().ToLowerInvariant()
        $fusionUiDefine = $EnableFusionUi.ToString().ToLowerInvariant()
        $fusionProductionPromotionCandidateDefine = (
            $AllowFusionProductionPromotionCandidate.IsPresent
        ).ToString().ToLowerInvariant()
        $transportCascadeDefine = $EnableTransportCascade.ToString().ToLowerInvariant()
        $previousRuntimeEnvironment = @{}
        foreach ($name in $runtime.Keys) {
            $previousRuntimeEnvironment[$name] = [pscustomobject]@{
                existed = Test-Path -LiteralPath "Env:$name"
                value = [Environment]::GetEnvironmentVariable($name, 'Process')
            }
            Set-Item -LiteralPath "Env:$name" -Value $runtime[$name]
        }

        $windowsBuildRoot = Join-Path $ProjectRoot 'build\windows\x64'
        Assert-SafeChildPath -BasePath $ProjectRoot -CandidatePath $windowsBuildRoot
        if (Test-Path -LiteralPath $windowsBuildRoot) {
            Remove-Item -LiteralPath $windowsBuildRoot -Recurse -Force
        }
        Push-Location $ProjectRoot
        try {
            flutter build windows --release -t .\lib\main.dart `
                --build-name="$WindowsBuildName" `
                --build-number="$WindowsBuildNumber" `
                --dart-define="GREENVPN_APP_VERSION=$AppVersion" `
                --dart-define="GREENVPN_TRIAL_ONLY_NO_ADS_BUILD=$trialOnlyDefine" `
                --dart-define="GREENVPN_PAID_BETA_BUILD=$paidBetaDefine" `
                --dart-define="GREENVPN_PUBLIC_PRODUCT_BUILD=$publicProductDefine" `
                --dart-define="GREENVPN_FUSION_UI_ENABLED=$fusionUiDefine" `
                --dart-define="GREENVPN_FUSION_PRODUCTION_PROMOTION_CANDIDATE=$fusionProductionPromotionCandidateDefine" `
                --dart-define="GREENVPN_AWG2_PREVIEW_ENABLED=$transportCascadeDefine" `
                --dart-define="GREENVPN_HYSTERIA2_PREVIEW_ENABLED=$transportCascadeDefine" `
                --dart-define="GREENVPN_VLESS_REALITY_PREVIEW_ENABLED=$transportCascadeDefine" `
                --dart-define="GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED=$transportCascadeDefine" `
                --dart-define="GREENVPN_DNSTT_PREVIEW_ENABLED=$transportCascadeDefine" `
                --dart-define="GREENVPN_UPDATE_CHANNEL=$effectiveUpdateChannel" `
                --dart-define="GREENVPN_WINDOWS_RUNTIME_SCOPE=$($runtime.GREENVPN_WINDOWS_RUNTIME_SCOPE)" `
                --dart-define="GREENVPN_WINDOWS_TUNNEL_NAME=$($runtime.GREENVPN_WINDOWS_TUNNEL_NAME)" `
                --dart-define="GREENVPN_WINDOWS_SERVICE_NAME=$($runtime.GREENVPN_WINDOWS_SERVICE_NAME)" `
                --dart-define="GREENVPN_WINDOWS_PROGRAM_DATA_SUBDIR=$($runtime.GREENVPN_WINDOWS_PROGRAM_DATA_SUBDIR)" `
                --dart-define="GREENVPN_WINDOWS_USER_DATA_SUBDIR=$($runtime.GREENVPN_WINDOWS_USER_DATA_SUBDIR)" `
                --dart-define="GREENVPN_WINDOWS_LOCAL_SERVICE_PORT=$($runtime.GREENVPN_WINDOWS_LOCAL_SERVICE_PORT)" `
                --dart-define="GREENVPN_PRODUCT_NAME=$($runtime.GREENVPN_PRODUCT_NAME)" `
                --dart-define="GREENVPN_YANDEX_REWARDED_ADS_ENABLED=false" `
                --dart-define="BLUEVPN_API_BASE_URL=$ApiBaseUrl" `
                --dart-define="BLUEVPN_API_BASE_URLS=$ApiFallbackBaseUrls"
            if ($LASTEXITCODE -ne 0) {
                throw "flutter build windows failed with exit code $LASTEXITCODE"
            }
        }
        finally {
            Pop-Location
            foreach ($name in $runtime.Keys) {
                $previous = $previousRuntimeEnvironment[$name]
                if ($previous.existed) {
                    Set-Item -LiteralPath "Env:$name" -Value $previous.value
                } else {
                    Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
                }
            }
        }
    }

    $releaseRuntimeDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
    $releaseExe = Join-Path $releaseRuntimeDir 'bluevpn.exe'
    if (-not (Test-Path -LiteralPath $releaseExe)) {
        throw "Release EXE not found: $releaseExe"
    }

    Write-Section 'CREATE FRESH RELEASE ZIP'
    $generatedPackageDir = Join-Path $workRoot 'fresh_release_package'
    $generatedAppDir = Join-Path $generatedPackageDir 'app'
    $generatedDocsDir = Join-Path $generatedPackageDir 'docs'
    $generatedToolsDir = Join-Path $generatedPackageDir 'tools'
    $generatedReleaseZip = Join-Path $workRoot 'GreenVPN_current_release_payload.zip'

    New-Item -ItemType Directory -Force -Path $generatedAppDir | Out-Null
    New-Item -ItemType Directory -Force -Path $generatedDocsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $generatedToolsDir | Out-Null

    Copy-Item -Path (Join-Path $releaseRuntimeDir '*') -Destination $generatedAppDir -Recurse -Force
    $generatedLegacyExe = Join-Path $generatedAppDir 'bluevpn.exe'
    $generatedGreenExe = Join-Path $generatedAppDir $(if ($WindowsRuntimeScope -eq 'paid-beta') { 'greenvpn_beta.exe' } else { 'greenvpn.exe' })
    if (Test-Path -LiteralPath $generatedLegacyExe) {
        Move-Item -LiteralPath $generatedLegacyExe -Destination $generatedGreenExe -Force
    }
    if ($WindowsRuntimeScope -eq 'paid-beta') {
        $generatedServiceExe = Join-Path $generatedAppDir 'greenvpn_service.exe'
        if (-not (Test-Path -LiteralPath $generatedServiceExe)) {
            throw "Paid beta service executable was not built: $generatedServiceExe"
        }
        Move-Item -LiteralPath $generatedServiceExe -Destination (Join-Path $generatedAppDir 'greenvpn_beta_service.exe') -Force
    }

    $readme = Join-Path $ProjectRoot 'docs\README_RELEASE.txt'
    if ($WindowsRuntimeScope -eq 'stable' -and (Test-Path -LiteralPath $readme)) {
        Copy-Item -LiteralPath $readme -Destination (Join-Path $generatedDocsDir 'README_RELEASE.txt') -Force
    }

    if ($WindowsRuntimeScope -eq 'stable') {
        $doctor = Join-Path $ProjectRoot 'scripts\windows\doctor_bluevpn.ps1'
        if (Test-Path -LiteralPath $doctor) {
            Copy-Item -LiteralPath $doctor -Destination (Join-Path $generatedToolsDir 'doctor_greenvpn.ps1') -Force
        }

        $recover = Join-Path $ProjectRoot 'scripts\windows\bluevpn_network_recover.ps1'
        if (Test-Path -LiteralPath $recover) {
            Copy-Item -LiteralPath $recover -Destination (Join-Path $generatedToolsDir 'greenvpn_network_recover.ps1') -Force
        }

        $bootRepair = Join-Path $ProjectRoot 'scripts\windows\greenvpn_boot_repair.ps1'
        if (Test-Path -LiteralPath $bootRepair) {
            Copy-Item -LiteralPath $bootRepair -Destination (Join-Path $generatedToolsDir 'greenvpn_boot_repair.ps1') -Force
        }
    }

    if ($EnableTransportCascade) {
        & (Join-Path $ProjectRoot 'scripts\windows\stage_windows_transport_cascade.ps1') `
            -ProjectRoot $ProjectRoot `
            -DestinationToolsDir $generatedToolsDir `
            -RuntimeScope $WindowsRuntimeScope
        if (-not $?) {
            throw 'Windows transport cascade staging failed.'
        }
    } else {
        $vpnTask = Join-Path $ProjectRoot 'scripts\windows\greenvpn_vpn_task.ps1'
        if (Test-Path -LiteralPath $vpnTask) {
            $packagedVpnTask = Join-Path $generatedToolsDir 'greenvpn_vpn_task.ps1'
            Copy-Item -LiteralPath $vpnTask -Destination $packagedVpnTask -Force
            if ($WindowsRuntimeScope -eq 'paid-beta') {
                $taskContent = Get-Content -LiteralPath $packagedVpnTask -Raw
                $taskContent = $taskContent.Replace('BlueVPNDev1', 'GreenVPNBeta').Replace("'BlueVPN'", "'BlueVPNBeta'")
                Set-Content -LiteralPath $packagedVpnTask -Value $taskContent -Encoding UTF8
            }
        }
    }

    $networkProtection = Join-Path $ProjectRoot 'scripts\windows\check_windows_network_protection.ps1'
    if (Test-Path -LiteralPath $networkProtection) {
        $packagedNetworkProtection = Join-Path $generatedToolsDir 'check_windows_network_protection.ps1'
        Copy-Item -LiteralPath $networkProtection -Destination $packagedNetworkProtection -Force
        if ($WindowsRuntimeScope -eq 'paid-beta') {
            $protectionContent = Get-Content -LiteralPath $packagedNetworkProtection -Raw
            $protectionContent = $protectionContent.Replace('BlueVPNDev1', 'GreenVPNBeta').Replace('BlueVPN\', 'BlueVPNBeta\')
            Set-Content -LiteralPath $packagedNetworkProtection -Value $protectionContent -Encoding UTF8
        }
    }

    if ($WindowsRuntimeScope -eq 'paid-beta') {
        Copy-Item -LiteralPath (Join-Path $ProjectRoot 'scripts\windows\uninstall_paid_beta_side_by_side.ps1') `
            -Destination (Join-Path $generatedToolsDir 'uninstall_greenvpn_beta.ps1') -Force
    }

    $generatedProcessRouterDir = Join-Path $generatedToolsDir 'process-router'
    New-Item -ItemType Directory -Force -Path $generatedProcessRouterDir | Out-Null
    $processRouterHashes = [ordered]@{
        'ProxyBridge_CLI.exe' = '806B3F6326F3D90C3029D179F458F6BF41970D21107A6729A44D7693C580523B'
        'ProxyBridgeCore.dll' = '30E3D20DFD44A06CE52F5F3566863A54D5832C4490FB210704B976D7ED5A2D2F'
        'WinDivert.dll' = 'C1E060EE19444A259B2162F8AF0F3FE8C4428A1C6F694DCE20DE194AC8D7D9A2'
        'WinDivert64.sys' = '8DA085332782708D8767BCACE5327A6EC7283C17CFB85E40B03CD2323A90DDC2'
    }
    foreach ($entry in $processRouterHashes.GetEnumerator()) {
        $sourcePath = Join-Path $ProcessRouterRoot $entry.Key
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Process router payload is missing: $sourcePath"
        }
        $actualHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        if ($actualHash -ne $entry.Value) {
            throw "Process router payload hash mismatch: $($entry.Key)"
        }
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $generatedProcessRouterDir $entry.Key) -Force
    }

    $driverSignature = Get-AuthenticodeSignature -LiteralPath (Join-Path $ProcessRouterRoot 'WinDivert64.sys')
    if ([string]$driverSignature.Status -ne 'Valid') {
        throw "WinDivert64.sys Authenticode signature is not valid: $($driverSignature.Status)"
    }

    $proxyBridgeLicense = Join-Path $ProcessRouterRoot 'PROXYBRIDGE_LICENSE.txt'
    $winDivertLicense = Join-Path $ProcessRouterRoot 'WINDIVERT_LICENSE.txt'
    $processRouterProvenance = Join-Path $ProcessRouterRoot 'PROVENANCE.md'
    if (-not (Test-Path -LiteralPath $proxyBridgeLicense -PathType Leaf)) {
        throw "ProxyBridge license is missing: $proxyBridgeLicense"
    }
    if (-not (Test-Path -LiteralPath $winDivertLicense -PathType Leaf)) {
        throw "WinDivert license is missing: $winDivertLicense"
    }
    if (-not (Test-Path -LiteralPath $processRouterProvenance -PathType Leaf)) {
        throw "Process router provenance is missing: $processRouterProvenance"
    }
    Copy-Item -LiteralPath $proxyBridgeLicense -Destination (Join-Path $generatedProcessRouterDir 'PROXYBRIDGE_LICENSE.txt') -Force
    Copy-Item -LiteralPath $winDivertLicense -Destination (Join-Path $generatedProcessRouterDir 'WINDIVERT_LICENSE.txt') -Force
    Copy-Item -LiteralPath $processRouterProvenance -Destination (Join-Path $generatedProcessRouterDir 'PROVENANCE.md') -Force
    @'
Green VPN Windows application routing uses:

- Green VPN ProxyBridge fork based on v4.0.0 (MIT License)
- WinDivert v2.2.2-A (see WINDIVERT_LICENSE.txt)

The corresponding license texts are distributed in this directory.
'@ | Set-Content -LiteralPath (Join-Path $generatedProcessRouterDir 'THIRD_PARTY_NOTICES.txt') -Encoding UTF8

@"
Green VPN installer payload

Build time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Release exe timestamp: $((Get-Item -LiteralPath $releaseExe).LastWriteTime)
"@ | Set-Content -LiteralPath (Join-Path $generatedDocsDir 'BUILD_INFO.txt') -Encoding UTF8

    if ($codeSigningEnabled) {
        $ownedPayloadBinaries = @($generatedGreenExe)
        $requiredPayloadLeafNames = @((Split-Path -Leaf $generatedGreenExe))
        $generatedServiceExe = if ($WindowsRuntimeScope -eq 'paid-beta') {
            Join-Path $generatedAppDir 'greenvpn_beta_service.exe'
        } else {
            Join-Path $generatedAppDir 'greenvpn_service.exe'
        }
        if (-not (Test-Path -LiteralPath $generatedServiceExe -PathType Leaf)) {
            throw "Green VPN service executable is missing before signing: $generatedServiceExe"
        }
        $ownedPayloadBinaries += $generatedServiceExe
        $requiredPayloadLeafNames += (Split-Path -Leaf $generatedServiceExe)
        Invoke-CodeSigningStage `
            -ArtifactPath $ownedPayloadBinaries `
            -RequiredLeafName $requiredPayloadLeafNames `
            -ReportPath (Join-Path $SigningReportDir "$signingReportStem-payload.json")
    }

    Compress-Archive -Path (Join-Path $generatedPackageDir '*') -DestinationPath $generatedReleaseZip -Force
    $ReleaseZip = $generatedReleaseZip
}

if (-not (Test-Path -LiteralPath $ReleaseZip)) {
    throw "Release zip not found: $ReleaseZip. Build release first."
}

Write-Section 'PREPARE INSTALLER PAYLOAD'
$payloadZip = Join-Path $payloadDir 'GreenVPN_payload.zip'
Copy-Item -LiteralPath $ReleaseZip -Destination $payloadZip -Force

$payloadIcon = Join-Path $payloadDir 'app_icon.ico'
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'windows\runner\resources\app_icon.ico') -Destination $payloadIcon -Force

$installPs1 = Join-Path $payloadDir 'install_greenvpn.ps1'
$installUiPs1 = Join-Path $payloadDir 'install_ui.ps1'
$installBootstrapExe = Join-Path $payloadDir 'install_bootstrap.exe'

@'
param(
    [string]$PayloadZip = "",
    [string]$InstallDir = "$env:ProgramFiles\Green VPN",
    [string]$OwnerSid = "",
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$productVersion = '__GREENVPN_APP_VERSION__'
$installLog = Join-Path $env:TEMP 'GreenVPN_Setup.log'
$installErrorLog = Join-Path $env:TEMP 'GreenVPN_Setup_error.log'
Remove-Item -LiteralPath $installErrorLog -Force -ErrorAction SilentlyContinue
try { Start-Transcript -Path $installLog -Append -Force | Out-Null } catch {}

function Write-Step {
    param([string]$Text)
    Write-Host "[Green VPN] $Text"
}

function Stop-BlueVpnTunnel {
    $managedTask = Join-Path $env:ProgramFiles 'Green VPN\tools\greenvpn_vpn_task.ps1'
    if (Test-Path -LiteralPath $managedTask -PathType Leaf) {
        try {
            $powershell = Join-Path $PSHOME 'powershell.exe'
            $process = Start-Process -FilePath $powershell -ArgumentList @(
                '-NoProfile',
                '-NonInteractive',
                '-ExecutionPolicy', 'RemoteSigned',
                '-File', ('"' + $managedTask + '"'),
                '-Action', 'Disconnect'
            ) -WindowStyle Hidden -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                return
            }
            Write-Step "Системный контроллер вернул код $($process.ExitCode); применяем резервную остановку."
        } catch {
            Write-Step "Не удалось вызвать системный контроллер остановки: $($_.Exception.Message)"
        }
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe')
    )

    foreach ($wg in $candidates) {
        if ([string]::IsNullOrWhiteSpace($wg)) { continue }
        if (Test-Path -LiteralPath $wg) {
            try {
                & $wg /uninstalltunnelservice BlueVPNDev1 | Out-Null
            } catch {
                Write-Step "Could not stop Green VPN tunnel automatically: $($_.Exception.Message)"
            }
            return
        }
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-InstallingUserSid {
    param([string]$CandidateSid)

    $value = $CandidateSid.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    }
    try {
        $sid = [Security.Principal.SecurityIdentifier]::new($value)
    } catch {
        throw "Invalid Windows account SID supplied to the installer."
    }
    if (-not $sid.IsAccountSid() -or $sid.Value -in @(
        'S-1-1-0',
        'S-1-5-11',
        'S-1-5-18',
        'S-1-5-32-544',
        'S-1-5-32-545'
    )) {
        throw "The installer owner must be an individual Windows account."
    }
    return $sid.Value
}

function Remove-CallerLegacyInstall {
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    foreach ($valueName in @('GreenVPN', 'Green VPN', 'BlueVPN', 'Blue VPN')) {
        Remove-ItemProperty -Path $runKey -Name $valueName -Force -ErrorAction SilentlyContinue
    }

    foreach ($shortcut in @(
        (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Green VPN.lnk'),
        (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'BlueVPN.lnk')
    )) {
        Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
    }

    foreach ($path in @(
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'Green VPN'),
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'BlueVPN'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Green VPN'),
        (Join-Path $env:LOCALAPPDATA 'Programs\BlueVPN')
    )) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-GreenVpnProgramDataAcl {
    param([Parameter(Mandatory=$true)][string]$UserSid)

    $root = Join-Path $env:ProgramData 'BlueVPN'
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    attrib -H -S -R $root 2>$null | Out-Null
    & takeown.exe /F $root /A /R /D Y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to take ownership of existing Green VPN state.' }

    & icacls.exe $root /grant:r `
        ('*' + $UserSid + ':(OI)(CI)M') `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to seed protected Green VPN state ACLs.' }

    & icacls.exe $root /inheritance:r | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to disable inherited Green VPN state ACLs.' }

    & icacls.exe $root /remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to remove broad Green VPN state access.' }

    & icacls.exe $root /grant:r `
        ('*' + $UserSid + ':(OI)(CI)M') `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to apply protected Green VPN state ACLs.' }

    if (Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue) {
        & icacls.exe (Join-Path $root '*') /reset /T /C | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Failed to restore inherited Green VPN child state ACLs.' }
    }

    & icacls.exe $root /setowner ('*' + $UserSid) /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to bind Green VPN state to the installing Windows account.' }
}

function Ensure-GreenVpnServiceToken {
    param([Parameter(Mandatory=$true)][string]$UserSid)

    $root = Join-Path $env:ProgramData 'BlueVPN'
    $tokenPath = Join-Path $root 'service_token'
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    $existing = ''
    if (Test-Path -LiteralPath $tokenPath) {
        try {
            $existing = (Get-Content -LiteralPath $tokenPath -Raw -ErrorAction Stop).Trim()
        } catch {
            $existing = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace($existing) -or $existing.Length -lt 24) {
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $bytes = New-Object byte[] 32
            $rng.GetBytes($bytes)
            [Convert]::ToBase64String($bytes) | Set-Content -LiteralPath $tokenPath -NoNewline -Encoding ASCII
        } finally {
            $rng.Dispose()
        }
    }

    attrib +H $tokenPath 2>$null | Out-Null
    & icacls.exe $tokenPath /inheritance:r /remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to remove broad Green VPN service token access.' }
    & icacls.exe $tokenPath /grant:r `
        '*S-1-5-18:F' `
        '*S-1-5-32-544:F' `
        ('*' + $UserSid + ':R') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to protect the Green VPN service token.' }
}

function Unregister-GreenVpnTasks {
    foreach ($taskName in @('GreenVPNConnect', 'GreenVPNDisconnect', 'GreenVPNGuard')) {
        try {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        } catch {
        }
        try {
            if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            }
        } catch {
        }
    }
}

function Remove-GreenVpnService {
    $serviceName = 'GreenVPNService'
    try {
        & sc.exe stop $serviceName | Out-Null
    } catch {
    }

    for ($i = 0; $i -lt 20; $i++) {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
        if ($null -eq $svc -or $svc.State -ne 'Running') { break }
        Start-Sleep -Milliseconds 250
    }

    try {
        & sc.exe delete $serviceName | Out-Null
    } catch {
    }

    for ($i = 0; $i -lt 20; $i++) {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
        if ($null -eq $svc) { return }
        Start-Sleep -Milliseconds 250
    }
}

function Install-GreenVpnService {
    param(
        [Parameter(Mandatory=$true)][string]$ServiceExe,
        [Parameter(Mandatory=$true)][string]$TaskScript
    )

    if (-not (Test-Path -LiteralPath $ServiceExe)) {
        throw "Green VPN service executable not found: $ServiceExe"
    }
    if (-not (Test-Path -LiteralPath $TaskScript)) {
        throw "Green VPN privileged task script not found: $TaskScript"
    }

    Remove-GreenVpnService

    $serviceName = 'GreenVPNService'
    $binPath = '"' + $ServiceExe + '" --task-script "' + $TaskScript + '"'
    try {
        New-Service -Name $serviceName -BinaryPathName $binPath -DisplayName 'Green VPN Service' -StartupType Automatic | Out-Null
    } catch {
        throw "Failed to create Green VPN service: $($_.Exception.Message)"
    }

    & sc.exe description $serviceName 'Green VPN local system service for secure connection control.' | Out-Null
    & sc.exe start $serviceName | Out-Null

    for ($i = 0; $i -lt 30; $i++) {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.State -eq 'Running') { return }
        Start-Sleep -Milliseconds 300
    }

    throw "Green VPN service was created but did not reach Running state."
}

function Test-GreenVpnInstalledRoot {
    param([Parameter(Mandatory=$true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $false
    }

    foreach ($requiredPath in @(
        (Join-Path $Root 'greenvpn.exe'),
        (Join-Path $Root 'greenvpn_service.exe'),
        (Join-Path $Root 'tools\greenvpn_vpn_task.ps1'),
        (Join-Path $Root 'tools\greenvpn_standby_probe.ps1'),
        (Join-Path $Root 'tools\process-router\ProxyBridge_CLI.exe'),
        (Join-Path $Root 'tools\process-router\ProxyBridgeCore.dll'),
        (Join-Path $Root 'tools\process-router\WinDivert.dll'),
        (Join-Path $Root 'tools\process-router\WinDivert64.sys'),
        (Join-Path $Root 'uninstall_greenvpn.cmd')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            return $false
        }
    }

    return Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN'
}

function Remove-CorruptInstallRoot {
    param([Parameter(Mandatory=$true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) { return }

    # Older installers could leave child files without an effective Administrators ACE.
    & takeown.exe /F $Root /A /R /D Y | Out-Null
    & icacls.exe $Root /inheritance:e /grant:r `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' /T /C /Q | Out-Null
    & icacls.exe $Root /reset /T /C /Q | Out-Null
    Remove-Item -LiteralPath $Root -Recurse -Force
    if (Test-Path -LiteralPath $Root) {
        throw "Failed to remove an incomplete Green VPN installation: $Root"
    }
}

function Move-DirectoryWithRetry {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [int]$Attempts = 30
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            Move-Item -LiteralPath $Source -Destination $Destination -Force
            return
        } catch {
            $lastError = $_
            if ($attempt -lt $Attempts) {
                Stop-GreenVpnUiGracefully -Root $Source
                Start-Sleep -Milliseconds 300
            }
        }
    }
    throw $lastError
}

function Get-GreenVpnUiProcesses {
    param([Parameter(Mandatory=$true)][string]$Root)

    $expectedPath = [IO.Path]::GetFullPath((Join-Path $Root 'greenvpn.exe'))
    return @(
        Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    $_.Path -and
                        [IO.Path]::GetFullPath([string]$_.Path).Equals(
                            $expectedPath,
                            [StringComparison]::OrdinalIgnoreCase
                        )
                } catch {
                    $false
                }
            }
    )
}

function Stop-GreenVpnUiGracefully {
    param([Parameter(Mandatory=$true)][string]$Root)

    $appPath = Join-Path $Root 'greenvpn.exe'
    $running = @(Get-GreenVpnUiProcesses -Root $Root)
    if ($running.Count -eq 0) { return }

    if (Test-Path -LiteralPath $appPath -PathType Leaf) {
        try {
            $shutdown = Start-Process -FilePath $appPath `
                -ArgumentList @('--shutdown-existing', '--background') `
                -WorkingDirectory $Root `
                -WindowStyle Hidden `
                -PassThru
            $shutdown.WaitForExit(15000) | Out-Null
        } catch {
            Write-Step "Штатное завершение Green VPN не сработало: $($_.Exception.Message)"
        }
    }

    $deadline = (Get-Date).AddSeconds(12)
    do {
        $running = @(Get-GreenVpnUiProcesses -Root $Root)
        if ($running.Count -eq 0) { return }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    Write-Step 'Green VPN не завершился штатно; применяем аварийную остановку.'
    foreach ($process in $running) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}

function Test-FileAclAllows {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Sid,
        [Parameter(Mandatory=$true)][Security.AccessControl.FileSystemRights]$RequiredRights
    )

    $securityIdentifier = [Security.Principal.SecurityIdentifier]::new($Sid)
    $rules = (Get-Acl -LiteralPath $Path).GetAccessRules(
        $true,
        $true,
        [Security.Principal.SecurityIdentifier]
    )
    $allowed = [Security.AccessControl.FileSystemRights]0
    foreach ($rule in $rules) {
        if ($rule.IdentityReference.Value -ne $securityIdentifier.Value) { continue }
        if (
            $rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Deny -and
            (($rule.FileSystemRights -band $RequiredRights) -ne 0)
        ) {
            return $false
        }
        if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow) {
            $allowed = $allowed -bor $rule.FileSystemRights
        }
    }
    return (($allowed -band $RequiredRights) -eq $RequiredRights)
}

if ([string]::IsNullOrWhiteSpace($PayloadZip)) {
    $PayloadZip = Join-Path $PSScriptRoot 'GreenVPN_payload.zip'
}

if (-not (Test-Path -LiteralPath $PayloadZip)) {
    throw "Payload zip not found: $PayloadZip"
}

if (-not (Test-IsAdministrator)) {
    Write-Step "Запрашиваем права администратора для установки Green VPN..."
    $launchAfterInstall = -not $NoLaunch -and
        $env:GREENVPN_INSTALLER_SKIP_APP_LAUNCH -ne '1'
    $callerSid = Resolve-InstallingUserSid -CandidateSid $OwnerSid
    $argList = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'RemoteSigned',
        '-File',
        "`"$PSCommandPath`"",
        '-PayloadZip',
        "`"$PayloadZip`"",
        '-InstallDir',
        "`"$InstallDir`"",
        '-OwnerSid',
        "`"$callerSid`"",
        '-NoLaunch'
    )
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList $argList
    if ($p.ExitCode -eq 0) {
        Remove-CallerLegacyInstall
        if ($launchAfterInstall) {
            $installedExe = Join-Path ([System.IO.Path]::GetFullPath($InstallDir)) 'greenvpn.exe'
            if (-not (Test-Path -LiteralPath $installedExe)) {
                throw "Green VPN installation succeeded but the application is missing: $installedExe"
            }
            Start-Process -FilePath $installedExe -WorkingDirectory (Split-Path -Parent $installedExe)
        }
    }
    exit $p.ExitCode
}

$installingUserSid = Resolve-InstallingUserSid -CandidateSid $OwnerSid
$installRoot = [System.IO.Path]::GetFullPath($InstallDir)
$programFilesRoot = [System.IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\') + '\'
$installCandidate = $installRoot.TrimEnd('\') + '\'
if (-not $installCandidate.StartsWith($programFilesRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "InstallDir must stay under Program Files: $programFilesRoot"
}

$desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
$legacyDesktopShortcut = Join-Path $desktop 'BlueVPN.lnk'
$startPrograms = [Environment]::GetFolderPath('CommonPrograms')
$legacyStartMenuDir = Join-Path $startPrograms 'BlueVPN'

$tmp = Join-Path $env:TEMP ("GreenVPNInstall_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$swapId = [System.Guid]::NewGuid().ToString('N')
$stagingRoot = "$installRoot.staging-$swapId"
$backupRoot = "$installRoot.backup-$swapId"
$installSwapped = $false
$installCompleted = $false
$runtimeStopped = $false
$existingRootBackedUp = $false
$existingInstallValid = Test-GreenVpnInstalledRoot -Root $installRoot
$uninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN'
$runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$previousUninstallValues = @{}
$previousRunValue = $null
if ($existingInstallValid) {
    $existingUninstall = Get-ItemProperty -LiteralPath $uninstallKey -ErrorAction SilentlyContinue
    foreach ($name in @(
        'DisplayName',
        'DisplayVersion',
        'DisplayIcon',
        'Publisher',
        'InstallLocation',
        'UninstallString',
        'QuietUninstallString',
        'URLInfoAbout',
        'InstallDate',
        'EstimatedSize',
        'NoModify',
        'NoRepair'
    )) {
        if ($null -ne $existingUninstall -and $null -ne $existingUninstall.$name) {
            $previousUninstallValues[$name] = $existingUninstall.$name
        }
    }
    $existingRun = Get-ItemProperty -LiteralPath $runKey -Name 'GreenVPN' -ErrorAction SilentlyContinue
    if ($null -ne $existingRun -and $null -ne $existingRun.PSObject.Properties['GreenVPN']) {
        $previousRunValue = [string]$existingRun.GreenVPN
    }
}

try {
    Write-Step "Распаковываем приложение..."
    Expand-Archive -LiteralPath $PayloadZip -DestinationPath $tmp -Force

    $appSource = Join-Path $tmp 'app'
    foreach ($requiredSource in @(
        (Join-Path $appSource 'greenvpn.exe'),
        (Join-Path $appSource 'greenvpn_service.exe'),
        (Join-Path $tmp 'tools\greenvpn_vpn_task.ps1'),
        (Join-Path $tmp 'tools\greenvpn_standby_probe.ps1'),
        (Join-Path $tmp 'tools\process-router\ProxyBridge_CLI.exe'),
        (Join-Path $tmp 'tools\process-router\ProxyBridgeCore.dll'),
        (Join-Path $tmp 'tools\process-router\WinDivert.dll'),
        (Join-Path $tmp 'tools\process-router\WinDivert64.sys'),
        (Join-Path $tmp 'tools\process-router\PROVENANCE.md'),
        (Join-Path $tmp 'tools\process-router\THIRD_PARTY_NOTICES.txt')
    )) {
        if (-not (Test-Path -LiteralPath $requiredSource)) {
            throw "Invalid Green VPN package: required file is missing: $requiredSource"
        }
    }

    Write-Step "Подготавливаем проверенную копию Green VPN..."
    New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null
    Get-ChildItem -LiteralPath $appSource -Force |
        Copy-Item -Destination $stagingRoot -Recurse -Force

    $docsSource = Join-Path $tmp 'docs'
    if (Test-Path -LiteralPath $docsSource) {
        Copy-Item -LiteralPath $docsSource -Destination (Join-Path $stagingRoot 'docs') -Recurse -Force
    }

    $toolsSource = Join-Path $tmp 'tools'
    if (Test-Path -LiteralPath $toolsSource) {
        Copy-Item -LiteralPath $toolsSource -Destination (Join-Path $stagingRoot 'tools') -Recurse -Force
    }

    & icacls.exe $stagingRoot /inheritance:r /grant:r `
        '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-32-544:(OI)(CI)F' `
        '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to protect the Green VPN installation root.'
    }
    & icacls.exe (Join-Path $stagingRoot '*') /reset /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to inherit Green VPN application and service file permissions.'
    }

    foreach ($requiredStaged in @(
        (Join-Path $stagingRoot 'greenvpn.exe'),
        (Join-Path $stagingRoot 'greenvpn_service.exe'),
        (Join-Path $stagingRoot 'tools\greenvpn_vpn_task.ps1'),
        (Join-Path $stagingRoot 'tools\greenvpn_standby_probe.ps1'),
        (Join-Path $stagingRoot 'tools\process-router\ProxyBridge_CLI.exe'),
        (Join-Path $stagingRoot 'tools\process-router\ProxyBridgeCore.dll'),
        (Join-Path $stagingRoot 'tools\process-router\WinDivert.dll'),
        (Join-Path $stagingRoot 'tools\process-router\WinDivert64.sys'),
        (Join-Path $stagingRoot 'tools\process-router\PROVENANCE.md'),
        (Join-Path $stagingRoot 'tools\process-router\THIRD_PARTY_NOTICES.txt')
    )) {
        if (-not (Test-Path -LiteralPath $requiredStaged)) {
            throw "Green VPN staging postcondition failed: $requiredStaged was not created."
        }
        if (-not (Test-FileAclAllows -Path $requiredStaged -Sid 'S-1-5-18' -RequiredRights ([Security.AccessControl.FileSystemRights]::FullControl))) {
            throw "Green VPN staging ACL postcondition failed for SYSTEM: $requiredStaged"
        }
        if (-not (Test-FileAclAllows -Path $requiredStaged -Sid 'S-1-5-32-545' -RequiredRights ([Security.AccessControl.FileSystemRights]::ReadAndExecute))) {
            throw "Green VPN staging ACL postcondition failed for Users: $requiredStaged"
        }
    }

    Write-Step "Останавливаем текущее подключение Green VPN..."
    Stop-BlueVpnTunnel

    Write-Step "Закрываем предыдущую версию Green VPN..."
    Get-Process -Name 'bluevpn' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-GreenVpnUiGracefully -Root $installRoot
    $runtimeStopped = $true

    Write-Step "Обновляем системную службу Green VPN..."
    Remove-GreenVpnService

    if (Test-Path -LiteralPath $installRoot) {
        if ($existingInstallValid) {
            Move-DirectoryWithRetry -Source $installRoot -Destination $backupRoot
            $existingRootBackedUp = $true
        } else {
            Write-Step "Удаляем остатки незавершённой прежней установки..."
            Remove-CorruptInstallRoot -Root $installRoot
        }
    }
    Move-Item -LiteralPath $stagingRoot -Destination $installRoot -Force
    $installSwapped = $true

    $exe = Join-Path $installRoot 'greenvpn.exe'
    $taskScript = Join-Path $installRoot 'tools\greenvpn_vpn_task.ps1'
    $serviceExe = Join-Path $installRoot 'greenvpn_service.exe'

    $wsh = New-Object -ComObject WScript.Shell

    $desktopShortcut = Join-Path $desktop 'Green VPN.lnk'
    Remove-Item -LiteralPath $desktopShortcut -Force -ErrorAction SilentlyContinue
    $shortcut = $wsh.CreateShortcut($desktopShortcut)
    $shortcut.TargetPath = $exe
    $shortcut.WorkingDirectory = $installRoot
    $shortcut.IconLocation = "$exe,0"
    $shortcut.Save()

    $startMenuDir = Join-Path $startPrograms 'Green VPN'
    New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null
    $startShortcut = Join-Path $startMenuDir 'Green VPN.lnk'
    Remove-Item -LiteralPath $startShortcut -Force -ErrorAction SilentlyContinue
    $shortcut = $wsh.CreateShortcut($startShortcut)
    $shortcut.TargetPath = $exe
    $shortcut.WorkingDirectory = $installRoot
    $shortcut.IconLocation = "$exe,0"
    $shortcut.Save()

    foreach ($requiredPath in @($exe, $desktopShortcut, $startShortcut)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Green VPN installation postcondition failed: $requiredPath was not created."
        }
    }

    foreach ($shortcutPath in @($desktopShortcut, $startShortcut)) {
        $installedShortcut = $wsh.CreateShortcut($shortcutPath)
        if (-not [System.IO.Path]::GetFullPath($installedShortcut.TargetPath).Equals(
            [System.IO.Path]::GetFullPath($exe),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Green VPN installation postcondition failed: $shortcutPath points to an unexpected target."
        }
    }

    Write-Step "Настраиваем запуск Green VPN в трее..."
    $runKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $runKey -Force | Out-Null
    foreach ($valueName in @('GreenVPN', 'Green VPN', 'BlueVPN', 'Blue VPN')) {
        Remove-ItemProperty -Path $runKey -Name $valueName -Force -ErrorAction SilentlyContinue
    }
    New-ItemProperty -Path $runKey -Name 'GreenVPN' -PropertyType String -Value ('"' + $exe + '" --background') -Force | Out-Null

    @"
param(
    [string]`$InstallRoot = "$installRoot",
    [switch]`$FromTemp,
    [switch]`$KeepProgramData
)

Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]`$Text)
    Write-Host "[Green VPN uninstall] `$Text"
}

function Test-IsAdministrator {
    `$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    `$principal = [Security.Principal.WindowsPrincipal]::new(`$identity)
    return `$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-FromTemp {
    `$source = `$PSCommandPath
    if ([string]::IsNullOrWhiteSpace(`$source) -or -not (Test-Path -LiteralPath `$source)) {
        throw "Cannot locate uninstall script."
    }

    `$tempDir = Join-Path `$env:TEMP ("GreenVPN_Uninstall_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path `$tempDir | Out-Null
    `$tempScript = Join-Path `$tempDir 'uninstall_greenvpn.ps1'
    Copy-Item -LiteralPath `$source -Destination `$tempScript -Force

    `$argList = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'RemoteSigned',
        '-File',
        ('"' + `$tempScript + '"'),
        '-InstallRoot',
        ('"' + `$InstallRoot + '"'),
        '-FromTemp'
    )
    if (`$KeepProgramData) { `$argList += '-KeepProgramData' }

    `$startArgs = @{
        FilePath = 'powershell.exe'
        ArgumentList = `$argList
        Wait = `$true
        PassThru = `$true
        WindowStyle = 'Hidden'
    }
    if (-not (Test-IsAdministrator)) {
        `$startArgs['Verb'] = 'RunAs'
    }

    `$p = Start-Process @startArgs
    Remove-Item -LiteralPath `$tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit `$p.ExitCode
}

function Remove-PathSafe {
    param(
        [Parameter(Mandatory=`$true)][string]`$Path,
        [Parameter(Mandatory=`$true)][string[]]`$AllowedRoots,
        [switch]`$Recurse
    )

    if ([string]::IsNullOrWhiteSpace(`$Path)) { return }
    if (-not (Test-Path -LiteralPath `$Path)) { return }

    `$full = [System.IO.Path]::GetFullPath(`$Path)
    `$isAllowed = `$false
    foreach (`$root in `$AllowedRoots) {
        if ([string]::IsNullOrWhiteSpace(`$root)) { continue }
        `$rootFull = [System.IO.Path]::GetFullPath(`$root).TrimEnd('\') + '\'
        if ((`$full + '\').StartsWith(`$rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or `$full.Equals(`$rootFull.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            `$isAllowed = `$true
            break
        }
    }

    if (-not `$isAllowed) {
        Write-Step "Skip unsafe path: `$full"
        return
    }

    if (`$Recurse) {
        Remove-Item -LiteralPath `$full -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Remove-Item -LiteralPath `$full -Force -ErrorAction SilentlyContinue
    }
}

if (-not `$FromTemp) {
    Start-FromTemp
}

if (-not (Test-IsAdministrator)) {
    throw "Uninstaller must run as Administrator."
}

Set-Location `$env:TEMP
Write-Step "Stopping Green VPN processes..."
Get-Process -Name 'bluevpn' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name 'greenvpn' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Step "Removing Green VPN service..."
try { sc.exe stop GreenVPNService | Out-Null } catch {}
Start-Sleep -Milliseconds 700
try { sc.exe delete GreenVPNService | Out-Null } catch {}
for (`$i = 0; `$i -lt 20; `$i++) {
    `$svc = Get-CimInstance Win32_Service -Filter "Name='GreenVPNService'" -ErrorAction SilentlyContinue
    if (`$null -eq `$svc) { break }
    Start-Sleep -Milliseconds 250
}

Write-Step "Removing Green VPN scheduled tasks..."
foreach (`$taskName in @('GreenVPNConnect', 'GreenVPNDisconnect', 'GreenVPNGuard', 'BlueVPNConnect', 'BlueVPNDisconnect', 'BlueVPNGuard')) {
    try { Stop-ScheduledTask -TaskName `$taskName -ErrorAction SilentlyContinue } catch {}
    try {
        if (Get-ScheduledTask -TaskName `$taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName `$taskName -Confirm:`$false -ErrorAction SilentlyContinue
        }
    } catch {}
}

Write-Step "Removing Green VPN startup entries..."
foreach (`$runKey in @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)) {
    if (Test-Path `$runKey) {
        foreach (`$valueName in @('GreenVPN', 'Green VPN', 'BlueVPN', 'Blue VPN')) {
            Remove-ItemProperty -Path `$runKey -Name `$valueName -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Step "Останавливаем защищённое подключение Green VPN..."
`$serviceName = 'WireGuardTunnel`$BlueVPNDev1'
sc.exe stop `$serviceName 2>`$null | Out-Null
Start-Sleep -Milliseconds 700
`$wgCandidates = @(
    (Join-Path `$env:ProgramFiles 'WireGuard\wireguard.exe'),
    (Join-Path `${env:ProgramFiles(x86)} 'WireGuard\wireguard.exe'),
    'C:\Program Files\WireGuard\wireguard.exe',
    'C:\Program Files (x86)\WireGuard\wireguard.exe'
)
foreach (`$wg in `$wgCandidates) {
    if ([string]::IsNullOrWhiteSpace(`$wg)) { continue }
    if (Test-Path -LiteralPath `$wg) {
        try { & `$wg /uninstalltunnelservice BlueVPNDev1 | Out-Null } catch {}
        break
    }
}
sc.exe delete `$serviceName 2>`$null | Out-Null

Write-Step "Removing shortcuts..."
`$desktop = [Environment]::GetFolderPath('DesktopDirectory')
`$commonDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
`$programs = [Environment]::GetFolderPath('Programs')
`$commonPrograms = [Environment]::GetFolderPath('CommonPrograms')
foreach (`$shortcutPath in @(
    "$desktopShortcut",
    (Join-Path `$desktop 'Green VPN.lnk'),
    (Join-Path `$desktop 'BlueVPN.lnk'),
    (Join-Path `$commonDesktop 'Green VPN.lnk'),
    (Join-Path `$commonDesktop 'BlueVPN.lnk')
)) {
    Remove-Item -LiteralPath `$shortcutPath -Force -ErrorAction SilentlyContinue
}
foreach (`$shortcutDir in @(
    "$startMenuDir",
    "$legacyStartMenuDir",
    (Join-Path `$programs 'Green VPN'),
    (Join-Path `$programs 'BlueVPN'),
    (Join-Path `$commonPrograms 'Green VPN'),
    (Join-Path `$commonPrograms 'BlueVPN')
)) {
    Remove-Item -LiteralPath `$shortcutDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step "Removing installed files and local state..."
`$localPrograms = [System.IO.Path]::GetFullPath((Join-Path `$env:LOCALAPPDATA 'Programs'))
`$programFiles = [System.IO.Path]::GetFullPath(`$env:ProgramFiles)
`$localAppData = [System.IO.Path]::GetFullPath(`$env:LOCALAPPDATA)
`$appData = [System.IO.Path]::GetFullPath(`$env:APPDATA)
`$programData = [System.IO.Path]::GetFullPath(`$env:ProgramData)
`$allowedUserRoots = @(`$localPrograms, `$localAppData, `$appData)
foreach (`$path in @(
    `$InstallRoot,
    (Join-Path `$localPrograms 'Green VPN'),
    (Join-Path `$localPrograms 'Blue VPN'),
    (Join-Path `$localPrograms 'GreenVPN'),
    (Join-Path `$localPrograms 'BlueVPN')
)) {
    Remove-PathSafe -Path `$path -AllowedRoots @(`$localPrograms, `$programFiles) -Recurse
}
foreach (`$path in @(
    (Join-Path `$localAppData 'Green VPN'),
    (Join-Path `$localAppData 'GreenVPN'),
    (Join-Path `$localAppData 'BlueVPN'),
    (Join-Path `$appData 'Green VPN'),
    (Join-Path `$appData 'GreenVPN'),
    (Join-Path `$appData 'BlueVPN')
)) {
    Remove-PathSafe -Path `$path -AllowedRoots `$allowedUserRoots -Recurse
}

Remove-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN' -Recurse -Force -ErrorAction SilentlyContinue

if (-not `$KeepProgramData) {
    Write-Step "Removing machine state in ProgramData..."
    Remove-Item -LiteralPath 'HKLM:\SOFTWARE\GreenVPN\Runtime\stable' -Recurse -Force -ErrorAction SilentlyContinue
    foreach (`$path in @(
        (Join-Path `$programData 'BlueVPN'),
        (Join-Path `$programData 'GreenVPN'),
        (Join-Path `$programData 'Green VPN')
    )) {
        Remove-PathSafe -Path `$path -AllowedRoots @(`$programData) -Recurse
    }
}

Write-Step "Green VPN удалён. Другие сетевые приложения не изменялись."
"@ | Set-Content -LiteralPath (Join-Path $installRoot 'uninstall_greenvpn.ps1') -Encoding UTF8

@"
@echo off
setlocal
pushd "%TEMP%" >nul 2>nul
powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "%~dp0uninstall_greenvpn.ps1"
popd >nul 2>nul
exit /b %ERRORLEVEL%
"@ | Set-Content -LiteralPath (Join-Path $installRoot 'uninstall_greenvpn.cmd') -Encoding ASCII

    $uninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN'
    New-Item -Path $uninstallKey -Force | Out-Null
    $uninstallCommand = '"' + (Join-Path $installRoot 'uninstall_greenvpn.cmd') + '"'
    $estimatedSizeKb = [Math]::Max(1, [int]([Math]::Ceiling((
        (Get-ChildItem -LiteralPath $installRoot -File -Recurse | Measure-Object -Property Length -Sum).Sum
    ) / 1KB)))
    $uninstallValues = [ordered]@{
        DisplayName = 'Green VPN'
        DisplayVersion = $productVersion
        DisplayIcon = (Join-Path $installRoot 'greenvpn.exe')
        Publisher = 'Green VPN'
        InstallLocation = $installRoot
        UninstallString = $uninstallCommand
        QuietUninstallString = $uninstallCommand
        URLInfoAbout = 'https://greenvpn.pro/'
        InstallDate = (Get-Date -Format 'yyyyMMdd')
    }
    foreach ($entry in $uninstallValues.GetEnumerator()) {
        New-ItemProperty -Path $uninstallKey -Name $entry.Key -PropertyType String -Value $entry.Value -Force | Out-Null
    }
    New-ItemProperty -Path $uninstallKey -Name 'EstimatedSize' -PropertyType DWord -Value $estimatedSizeKb -Force | Out-Null
    New-ItemProperty -Path $uninstallKey -Name 'NoModify' -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $uninstallKey -Name 'NoRepair' -PropertyType DWord -Value 1 -Force | Out-Null

    $unShortcut = Join-Path $startMenuDir 'Удалить Green VPN.lnk'
    $shortcut = $wsh.CreateShortcut($unShortcut)
    $shortcut.TargetPath = Join-Path $installRoot 'uninstall_greenvpn.cmd'
    $shortcut.Arguments = ''
    $shortcut.WorkingDirectory = $installRoot
    $shortcut.Save()

    Write-Step "Удаляем устаревшие системные задачи Green VPN..."
    Ensure-GreenVpnProgramDataAcl -UserSid $installingUserSid
    Ensure-GreenVpnServiceToken -UserSid $installingUserSid
    Unregister-GreenVpnTasks

    Write-Step "Устанавливаем системную службу Green VPN..."
    Install-GreenVpnService -ServiceExe $serviceExe -TaskScript $taskScript

    foreach ($requiredPath in @($exe, $desktopShortcut, $startShortcut, $uninstallKey)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Green VPN installation postcondition failed: $requiredPath was not created."
        }
    }

    Write-Step "Установка завершена."
    $installCompleted = $true
    Remove-Item -LiteralPath $installErrorLog -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-CallerLegacyInstall
    if (
        -not $NoLaunch -and
        $env:GREENVPN_INSTALLER_SKIP_APP_LAUNCH -ne '1'
    ) {
        Write-Step "Запускаем Green VPN..."
        Start-Process -FilePath $exe -WorkingDirectory $installRoot
    }
} catch {
    $installError = $_
    try {
        $installError.Exception.ToString() | Set-Content -LiteralPath $installErrorLog -Encoding UTF8 -Force
    } catch {
    }
    if (-not $installCompleted -and ($runtimeStopped -or $existingRootBackedUp -or $installSwapped)) {
        Write-Step "Установка не завершилась; возвращаем предыдущую версию..."
        try { Remove-GreenVpnService } catch {}
        Stop-GreenVpnUiGracefully -Root $installRoot
        if ($installSwapped -or $existingRootBackedUp) {
            try { Remove-CorruptInstallRoot -Root $installRoot } catch {}
        }
        if (Test-Path -LiteralPath $backupRoot) {
            Move-DirectoryWithRetry -Source $backupRoot -Destination $installRoot
        }
        if ($existingInstallValid -and (Test-Path -LiteralPath $installRoot)) {
            $oldServiceExe = Join-Path $installRoot 'greenvpn_service.exe'
            $oldTaskScript = Join-Path $installRoot 'tools\greenvpn_vpn_task.ps1'
            if ((Test-Path -LiteralPath $oldServiceExe) -and (Test-Path -LiteralPath $oldTaskScript)) {
                try { Install-GreenVpnService -ServiceExe $oldServiceExe -TaskScript $oldTaskScript } catch {}
            }
            Remove-Item -LiteralPath $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
            if ($previousUninstallValues.Count -gt 0) {
                New-Item -Path $uninstallKey -Force | Out-Null
                foreach ($entry in $previousUninstallValues.GetEnumerator()) {
                    $propertyType = if ($entry.Key -in @('EstimatedSize', 'NoModify', 'NoRepair')) { 'DWord' } else { 'String' }
                    New-ItemProperty -Path $uninstallKey -Name $entry.Key -PropertyType $propertyType -Value $entry.Value -Force | Out-Null
                }
            }
            Remove-ItemProperty -Path $runKey -Name 'GreenVPN' -Force -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace([string]$previousRunValue)) {
                New-Item -Path $runKey -Force | Out-Null
                New-ItemProperty -Path $runKey -Name 'GreenVPN' -PropertyType String -Value $previousRunValue -Force | Out-Null
            }
        } else {
            Remove-Item -LiteralPath (Join-Path $desktop 'Green VPN.lnk') -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $startPrograms 'Green VPN') -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $runKey -Name 'GreenVPN' -Force -ErrorAction SilentlyContinue
        }
    }
    throw $installError
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}
'@ | Set-Content -LiteralPath $installPs1 -Encoding UTF8

if ($WindowsRuntimeScope -eq 'paid-beta') {
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'scripts\windows\install_paid_beta_side_by_side.ps1') `
        -Destination $installPs1 -Force
}

$installScriptText = [IO.File]::ReadAllText($installPs1, [Text.UTF8Encoding]::new($true))
$installScriptText = $installScriptText.Replace('__GREENVPN_APP_VERSION__', $AppVersion)
[IO.File]::WriteAllText($installPs1, $installScriptText, [Text.UTF8Encoding]::new($true))

@'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptDir = Split-Path -Parent $PSCommandPath
$installPs1 = Join-Path $scriptDir 'install_greenvpn.ps1'
$payloadZip = Join-Path $scriptDir 'GreenVPN_payload.zip'
$iconPath = Join-Path $scriptDir 'app_icon.ico'
$logPath = Join-Path $env:TEMP 'GreenVPN_Setup.log'

$brandGreen = [System.Drawing.ColorTranslator]::FromHtml('#12A36F')
$brandGreenDeep = [System.Drawing.ColorTranslator]::FromHtml('#08785D')
$brandGreenSoft = [System.Drawing.ColorTranslator]::FromHtml('#E7F7EF')
$brandBlue = [System.Drawing.ColorTranslator]::FromHtml('#1FA9D8')
$brandText = [System.Drawing.ColorTranslator]::FromHtml('#101828')
$brandMuted = [System.Drawing.ColorTranslator]::FromHtml('#667085')
$brandBg = [System.Drawing.ColorTranslator]::FromHtml('#F4F7F5')
$brandDanger = [System.Drawing.ColorTranslator]::FromHtml('#E5484D')

function New-Font {
    param(
        [float]$Size,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )
    return [System.Drawing.Font]::new('Segoe UI', $Size, $Style)
}

function Set-UiText {
    param(
        [string]$Title,
        [string]$Detail,
        [System.Drawing.Color]$Accent = $brandGreen
    )
    if ($script:titleLabel -ne $null) { $script:titleLabel.Text = $Title }
    if ($script:detailLabel -ne $null) { $script:detailLabel.Text = $Detail }
    if ($script:logoPanel -ne $null) { $script:logoPanel.BackColor = $Accent }
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'Установка Green VPN'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ClientSize = [System.Drawing.Size]::new(500, 320)
$form.BackColor = $brandBg
$script:appIcon = $null
if (Test-Path -LiteralPath $iconPath) {
    try {
        $script:appIcon = [System.Drawing.Icon]::new($iconPath)
        $form.Icon = $script:appIcon
    } catch {
        $script:appIcon = $null
    }
}

$card = [System.Windows.Forms.Panel]::new()
$card.Location = [System.Drawing.Point]::new(24, 24)
$card.Size = [System.Drawing.Size]::new(452, 238)
$card.BackColor = [System.Drawing.Color]::White
$card.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($card)

$script:logoPanel = [System.Windows.Forms.Panel]::new()
$script:logoPanel.Location = [System.Drawing.Point]::new(22, 22)
$script:logoPanel.Size = [System.Drawing.Size]::new(56, 56)
$script:logoPanel.BackColor = $brandGreen
$card.Controls.Add($script:logoPanel)

$script:logoPanel.Add_Paint({
    param($sender, $eventArgs)

    $g = $eventArgs.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear($sender.BackColor)

    $whiteBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $cutoutBrush = [System.Drawing.SolidBrush]::new($sender.BackColor)
    $keyPen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, 4)
    try {
        $keyPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $keyPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

        $g.FillEllipse($whiteBrush, 12, 22, 15, 15)
        $g.FillEllipse($cutoutBrush, 17, 27, 5, 5)
        $g.DrawLine($keyPen, 26, 30, 43, 30)
        $g.DrawLine($keyPen, 36, 30, 36, 37)
        $g.DrawLine($keyPen, 43, 30, 43, 35)
    } finally {
        $whiteBrush.Dispose()
        $cutoutBrush.Dispose()
        $keyPen.Dispose()
    }
})

$script:titleLabel = [System.Windows.Forms.Label]::new()
$script:titleLabel.Text = 'Установка Green VPN'
$script:titleLabel.Location = [System.Drawing.Point]::new(96, 20)
$script:titleLabel.Size = [System.Drawing.Size]::new(324, 28)
$script:titleLabel.ForeColor = $brandText
$script:titleLabel.Font = New-Font 15 ([System.Drawing.FontStyle]::Bold)
$card.Controls.Add($script:titleLabel)

$script:detailLabel = [System.Windows.Forms.Label]::new()
$script:detailLabel.Text = 'Подготавливаем приложение и службу Green VPN.'
$script:detailLabel.Location = [System.Drawing.Point]::new(98, 52)
$script:detailLabel.Size = [System.Drawing.Size]::new(320, 42)
$script:detailLabel.ForeColor = $brandMuted
$script:detailLabel.Font = New-Font 9.5 ([System.Drawing.FontStyle]::Bold)
$card.Controls.Add($script:detailLabel)

$blueLine = [System.Windows.Forms.Panel]::new()
$blueLine.Location = [System.Drawing.Point]::new(22, 100)
$blueLine.Size = [System.Drawing.Size]::new(408, 3)
$blueLine.BackColor = $brandBlue
$card.Controls.Add($blueLine)

$progress = [System.Windows.Forms.ProgressBar]::new()
$progress.Location = [System.Drawing.Point]::new(22, 126)
$progress.Size = [System.Drawing.Size]::new(408, 14)
$progress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
$progress.MarqueeAnimationSpeed = 34
$card.Controls.Add($progress)

$stageLabel = [System.Windows.Forms.Label]::new()
$stageLabel.Text = 'Запуск установки...'
$stageLabel.Location = [System.Drawing.Point]::new(22, 156)
$stageLabel.Size = [System.Drawing.Size]::new(408, 24)
$stageLabel.ForeColor = $brandText
$stageLabel.Font = New-Font 10 ([System.Drawing.FontStyle]::Bold)
$card.Controls.Add($stageLabel)

$hintLabel = [System.Windows.Forms.Label]::new()
$hintLabel.Text = 'Права администратора нужны один раз для системной службы Green VPN.'
$hintLabel.Location = [System.Drawing.Point]::new(22, 184)
$hintLabel.Size = [System.Drawing.Size]::new(408, 40)
$hintLabel.ForeColor = $brandMuted
$hintLabel.Font = New-Font 8.5 ([System.Drawing.FontStyle]::Regular)
$card.Controls.Add($hintLabel)

$okButton = [System.Windows.Forms.Button]::new()
$okButton.Text = 'Готово'
$okButton.Enabled = $false
$okButton.Location = [System.Drawing.Point]::new(348, 274)
$okButton.Size = [System.Drawing.Size]::new(128, 32)
$okButton.BackColor = $brandGreen
$okButton.ForeColor = [System.Drawing.Color]::White
$okButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$okButton.Font = New-Font 9.5 ([System.Drawing.FontStyle]::Bold)
$okButton.Add_Click({ $form.Close() })
$form.Controls.Add($okButton)

$queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$script:exitCode = 1
$script:processStarted = $false
$script:processFinished = $false
$script:installerProcess = $null

$timer = [System.Windows.Forms.Timer]::new()
$timer.Interval = 180
$timer.Add_Tick({
    $line = $null
    while ($queue.TryDequeue([ref]$line)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\[Green VPN\]\s*(.+)$') {
            $stageLabel.Text = $Matches[1]
        } elseif ($line -match 'Transcript started') {
            $stageLabel.Text = 'Подготавливаем журнал установки...'
        }
    }

    if ($script:processStarted -and -not $script:processFinished -and $script:installerProcess.HasExited) {
        $script:processFinished = $true
        $script:exitCode = $script:installerProcess.ExitCode
        $timer.Stop()
        $progress.MarqueeAnimationSpeed = 0
        $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
        $progress.Value = 100
        $okButton.Enabled = $true

        if ($script:exitCode -eq 0) {
            Set-UiText -Title 'Green VPN установлен' -Detail 'Приложение и служба Green VPN готовы к работе.' -Accent $brandGreen
            $stageLabel.Text = 'Установка успешно завершена.'
            $hintLabel.Text = 'Green VPN уже запущен. Это окно можно закрыть.'
            $okButton.Text = 'Готово'
            if ($env:GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS -eq '1') {
                $form.Close()
                return
            }
        } else {
            Set-UiText -Title 'Установка не завершена' -Detail "Код ошибки: $script:exitCode. Журнал: $logPath" -Accent $brandDanger
            $stageLabel.Text = 'Проверьте журнал установки.'
            $hintLabel.Text = "Install log: $logPath"
            $okButton.Text = 'Закрыть'
        }
    }
})

$form.Add_Shown({
    try {
        if (-not (Test-Path -LiteralPath $installPs1)) {
            throw "install_greenvpn.ps1 not found"
        }
        if (-not (Test-Path -LiteralPath $payloadZip)) {
            throw "GreenVPN_payload.zip not found"
        }

        $stageLabel.Text = 'Распаковываем и устанавливаем Green VPN...'
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "' + $installPs1 + '" -PayloadZip "' + $payloadZip + '"'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $script:installerProcess = [System.Diagnostics.Process]::new()
        $script:installerProcess.StartInfo = $psi
        $script:installerProcess.EnableRaisingEvents = $true

        Register-ObjectEvent -InputObject $script:installerProcess -EventName OutputDataReceived -SourceIdentifier GreenVpnInstallerOut -MessageData $queue -Action {
            if (-not [string]::IsNullOrWhiteSpace($EventArgs.Data)) {
                $Event.MessageData.Enqueue($EventArgs.Data)
            }
        } | Out-Null
        Register-ObjectEvent -InputObject $script:installerProcess -EventName ErrorDataReceived -SourceIdentifier GreenVpnInstallerErr -MessageData $queue -Action {
            if (-not [string]::IsNullOrWhiteSpace($EventArgs.Data)) {
                $Event.MessageData.Enqueue($EventArgs.Data)
            }
        } | Out-Null

        [void]$script:installerProcess.Start()
        $script:installerProcess.BeginOutputReadLine()
        $script:installerProcess.BeginErrorReadLine()
        $script:processStarted = $true
        $timer.Start()
    } catch {
        $script:exitCode = 1
        $progress.MarqueeAnimationSpeed = 0
        $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
        $progress.Value = 100
        Set-UiText -Title 'Не удалось начать установку' -Detail $_.Exception.Message -Accent $brandDanger
        $stageLabel.Text = 'Установщик не запустился.'
        $hintLabel.Text = "Log: $logPath"
        $okButton.Enabled = $true
    }
})

$form.Add_FormClosed({
    try { Unregister-Event -SourceIdentifier GreenVpnInstallerOut -ErrorAction SilentlyContinue } catch {}
    try { Unregister-Event -SourceIdentifier GreenVpnInstallerErr -ErrorAction SilentlyContinue } catch {}
    try { $timer.Stop() } catch {}
    if ($script:installerProcess -ne $null -and -not $script:installerProcess.HasExited) {
        try { $script:installerProcess.Kill() } catch {}
    }
})

[void][System.Windows.Forms.Application]::Run($form)
exit $script:exitCode
'@ | Set-Content -LiteralPath $installUiPs1 -Encoding UTF8

$bootstrapSource = Join-Path $ProjectRoot 'scripts\windows\installer_bootstrap.cs'
if (-not (Test-Path -LiteralPath $bootstrapSource)) {
    throw "Installer bootstrap source not found: $bootstrapSource"
}
$compiler = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($compiler)) {
    throw 'The .NET Framework C# compiler was not found.'
}
& $compiler /nologo /target:winexe /optimize+ /platform:anycpu /reference:System.Windows.Forms.dll "/win32icon:$payloadIcon" "/out:$installBootstrapExe" $bootstrapSource
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $installBootstrapExe)) {
    throw "Installer bootstrap compilation failed with exit code $LASTEXITCODE."
}
Invoke-CodeSigningStage `
    -ArtifactPath @($installBootstrapExe) `
    -RequiredLeafName @('install_bootstrap.exe') `
    -ReportPath (Join-Path $SigningReportDir "$signingReportStem-bootstrap.json")

if ($WindowsRuntimeScope -eq 'paid-beta') {
    $uiContent = Get-Content -LiteralPath $installUiPs1 -Raw
    $uiContent = $uiContent.Replace('Green VPN', 'Green VPN Beta')
    Set-Content -LiteralPath $installUiPs1 -Value $uiContent -Encoding UTF8
}

Write-Section 'CREATE IEXPRESS SED'
$sedPath = Join-Path $workRoot 'greenvpn_installer.sed'
$targetEscaped = $installerPath
$payloadEscaped = $payloadDir
$installerFriendlyName = if ($WindowsRuntimeScope -eq 'paid-beta') { 'Green VPN Beta Installer' } else { 'Green VPN Installer' }

@"
[Version]
Class=IEXPRESS
SEDVersion=3

[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$targetEscaped
FriendlyName=$installerFriendlyName
AppLaunched=install_bootstrap.exe
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles

[Strings]
FILE0="install_bootstrap.exe"
FILE1="install_ui.ps1"
FILE2="install_greenvpn.ps1"
FILE3="GreenVPN_payload.zip"
FILE4="app_icon.ico"

[SourceFiles]
SourceFiles0=$payloadEscaped

[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
%FILE3%=
%FILE4%=
"@ | Set-Content -LiteralPath $sedPath -Encoding ASCII

Write-Section 'BUILD INSTALLER EXE'
if (Test-Path -LiteralPath $installerPath) {
    Remove-Item -LiteralPath $installerPath -Force
}

$p = Start-Process -FilePath 'iexpress.exe' -ArgumentList @('/N', '/Q', $sedPath) -Wait -PassThru -WindowStyle Hidden
if ($p.ExitCode -ne 0) {
    throw "IExpress failed with exit code $($p.ExitCode)"
}

if (-not (Test-Path -LiteralPath $installerPath)) {
    throw "Installer was not created: $installerPath"
}

try {
    $installerIcon = Join-Path $ProjectRoot 'windows\runner\resources\app_icon.ico'
    Set-ExeIcon -ExePath $installerPath -IconPath $installerIcon
    Set-ExeAsInvoker -ExePath $installerPath
} catch {
    if ($RequireCodeSigning) {
        throw "Installer resource update failed before signing: $($_.Exception.Message)"
    }
    Write-Warning "Installer resource update failed: $($_.Exception.Message)"
}

Invoke-CodeSigningStage `
    -ArtifactPath @($installerPath) `
    -RequiredLeafName @((Split-Path -Leaf $installerPath)) `
    -ReportPath (Join-Path $SigningReportDir "$signingReportStem-installer.json")

$latestAliasName = if ($WindowsRuntimeScope -eq 'paid-beta') { 'GreenVPN_Beta_Setup_LATEST.exe' } else { 'GreenVPN_Setup_LATEST.exe' }
$latestAliasPath = Join-Path $OutBase $latestAliasName
Copy-Item -LiteralPath $installerPath -Destination $latestAliasPath -Force

Write-Section 'DONE'
Get-Item -LiteralPath $installerPath | Select-Object FullName,Length,LastWriteTime | Format-List

if ($OpenFolder) {
    explorer /select,"$installerPath"
}
