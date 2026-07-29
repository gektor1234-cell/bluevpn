param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$OutDir = 'C:\BlueVPN_Builds\windows_trusted_release',
    [string]$ProductionVersion = '0.3.19',
    [string]$PaidBetaVersion = '0.3.19-paid-beta.1',
    [ValidateRange(0, 65535)]
    [int]$WindowsBuildNumber = 2914,
    [string]$CertificateThumbprint = '',
    [string]$ExpectedPublisher = '',
    [string]$TimestampUrl = 'http://timestamp.digicert.com',
    [switch]$Apply,
    [switch]$SkipChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$codeSigningOid = '1.3.6.1.5.5.7.3.3'
$normalizedThumbprint = ($CertificateThumbprint -replace '\s+', '').ToUpperInvariant()
if ($normalizedThumbprint -and $normalizedThumbprint -notmatch '^[0-9A-F]{40}$') {
    throw 'CertificateThumbprint must be a 40-character SHA-1 thumbprint.'
}
if ($ProductionVersion -notmatch '^\d+\.\d+\.\d+[A-Za-z0-9._-]*$') {
    throw "Invalid production version: $ProductionVersion"
}
if ($PaidBetaVersion -notmatch '^\d+\.\d+\.\d+[A-Za-z0-9._-]*$') {
    throw "Invalid paid-beta version: $PaidBetaVersion"
}

function Resolve-SignTool {
    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $kitRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (Test-Path -LiteralPath $kitRoot -PathType Container) {
        $candidate = Get-ChildItem -LiteralPath $kitRoot -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }
    return ''
}

function Get-CodeSigningCertificates {
    $now = Get-Date
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($storePath in @('Cert:\CurrentUser\My', 'Cert:\LocalMachine\My')) {
        Get-ChildItem -LiteralPath $storePath -ErrorAction SilentlyContinue |
            Where-Object {
                $_.HasPrivateKey -and
                $_.NotBefore -le $now -and
                $_.NotAfter -gt $now -and
                @($_.EnhancedKeyUsageList | ForEach-Object { [string]$_.ObjectId }) -contains $codeSigningOid
            } |
            ForEach-Object {
                $candidates.Add([pscustomobject]@{
                    certificate = $_
                    storePath = $storePath
                    thumbprint = $_.Thumbprint.ToUpperInvariant()
                    subject = $_.Subject
                    issuer = $_.Issuer
                    notAfter = $_.NotAfter
                    simpleName = $_.GetNameInfo(
                        [System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName,
                        $false
                    )
                }) | Out-Null
            }
    }
    return @($candidates | Sort-Object notAfter -Descending)
}

function Save-Json {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$Payload
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $Payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$signTool = Resolve-SignTool
$allCandidates = @(Get-CodeSigningCertificates)
$matchingCandidates = @($allCandidates)
if ($normalizedThumbprint) {
    $matchingCandidates = @($matchingCandidates | Where-Object { $_.thumbprint -eq $normalizedThumbprint })
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedPublisher)) {
    $matchingCandidates = @(
        $matchingCandidates |
            Where-Object { $_.subject -like "*$ExpectedPublisher*" -or $_.simpleName -like "*$ExpectedPublisher*" }
    )
}
$selected = $matchingCandidates | Select-Object -First 1
$preflightPath = Join-Path $OutDir 'windows-code-signing-preflight.json'
$preflight = [ordered]@{
    ok = [bool]($signTool -and $selected)
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    applyRequested = [bool]$Apply
    signToolAvailable = [bool]$signTool
    signToolPath = $signTool
    validCodeSigningCertificateCount = $allCandidates.Count
    matchingCodeSigningCertificateCount = $matchingCandidates.Count
    selectedCertificate = if ($selected) {
        [ordered]@{
            storePath = $selected.storePath
            thumbprint = $selected.thumbprint
            subject = $selected.subject
            issuer = $selected.issuer
            notAfter = $selected.notAfter.ToUniversalTime().ToString('o')
        }
    } else {
        $null
    }
    ownerAction = if ($selected) {
        $null
    } else {
        'Obtain and install a valid Authenticode code-signing certificate with its private key.'
    }
}
Save-Json -Path $preflightPath -Payload $preflight

if (-not $Apply) {
    $preflight | ConvertTo-Json -Depth 8
    Write-Host "preflight: $preflightPath"
    return
}
if (-not $signTool) {
    throw 'signtool.exe is unavailable. Install the Windows SDK signing tools.'
}
if (-not $selected) {
    throw 'No matching valid code-signing certificate with a private key was found.'
}

$effectivePublisher = $ExpectedPublisher.Trim()
if ([string]::IsNullOrWhiteSpace($effectivePublisher)) {
    $effectivePublisher = $selected.simpleName.Trim()
}
if ([string]::IsNullOrWhiteSpace($effectivePublisher)) {
    throw 'Unable to derive the expected Windows publisher from the selected certificate.'
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$productionOut = Join-Path $OutDir 'production'
$paidBetaOut = Join-Path $OutDir 'paid-beta'
$auditOut = Join-Path $OutDir 'audit'
New-Item -ItemType Directory -Force -Path $productionOut, $paidBetaOut, $auditOut | Out-Null

if (-not $SkipChecks) {
    & (Join-Path $ProjectRoot 'scripts\windows\bluevpn_release_gate.ps1') -ProjectRoot $ProjectRoot
    if (-not $?) {
        throw 'Release gate failed.'
    }
}

& (Join-Path $ProjectRoot 'scripts\windows\build_public_product.ps1') `
    -Mode windows `
    -WindowsAppVersion $ProductionVersion `
    -WindowsBuildNumber $WindowsBuildNumber `
    -OutDir $productionOut `
    -WindowsCodeSigningCertificateThumbprint $selected.thumbprint `
    -WindowsCodeSigningPublisher $effectivePublisher `
    -WindowsCodeSigningTimestampUrl $TimestampUrl `
    -RequireWindowsCodeSigning `
    -SkipChecks:$SkipChecks
if (-not $?) {
    throw 'Signed production Windows build failed.'
}

& (Join-Path $ProjectRoot 'scripts\windows\build_paid_beta.ps1') `
    -Mode windows `
    -WindowsAppVersion $PaidBetaVersion `
    -WindowsBuildNumber $WindowsBuildNumber `
    -OutDir $paidBetaOut `
    -WindowsCodeSigningCertificateThumbprint $selected.thumbprint `
    -WindowsCodeSigningPublisher $effectivePublisher `
    -WindowsCodeSigningTimestampUrl $TimestampUrl `
    -RequireWindowsCodeSigning `
    -SkipChecks
if (-not $?) {
    throw 'Signed paid-beta Windows build failed.'
}

$productionInstaller = Join-Path $productionOut "GreenVPN_Setup_$ProductionVersion.exe"
$safePaidBetaVersion = $PaidBetaVersion -replace '[^A-Za-z0-9._-]', '_'
$paidBetaInstaller = Join-Path $paidBetaOut "GreenVPN_Beta_Setup_$safePaidBetaVersion.exe"
$productionSigningReport = Join-Path $productionOut "signing_reports\GreenVPN_Setup_$ProductionVersion-installer.json"
$paidBetaSigningReport = Join-Path $paidBetaOut "signing_reports\GreenVPN_Beta_Setup_$safePaidBetaVersion-installer.json"
foreach ($requiredPath in @(
    $productionInstaller,
    $paidBetaInstaller,
    $productionSigningReport,
    $paidBetaSigningReport
)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Expected signed release artifact is missing: $requiredPath"
    }
}

& (Join-Path $ProjectRoot 'scripts\windows\test_public_installer_package.ps1') `
    -InstallerPath $productionInstaller `
    -Channel production `
    -ReportPath (Join-Path $auditOut 'production-installer-package.json')
if (-not $?) {
    throw 'Production installer package audit failed.'
}
& (Join-Path $ProjectRoot 'scripts\windows\test_public_installer_package.ps1') `
    -InstallerPath $paidBetaInstaller `
    -Channel paid-beta `
    -ReportPath (Join-Path $auditOut 'paid-beta-installer-package.json')
if (-not $?) {
    throw 'Paid-beta installer package audit failed.'
}

$release = [ordered]@{
    ok = $true
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    readyForPhysicalSmoke = $true
    publisher = $effectivePublisher
    certificateThumbprint = $selected.thumbprint
    certificateNotAfter = $selected.notAfter.ToUniversalTime().ToString('o')
    timestampUrl = $TimestampUrl
    buildNumber = $WindowsBuildNumber
    production = [ordered]@{
        version = $ProductionVersion
        path = $productionInstaller
        sizeBytes = (Get-Item -LiteralPath $productionInstaller).Length
        sha256 = (Get-FileHash -LiteralPath $productionInstaller -Algorithm SHA256).Hash
        signatureReport = $productionSigningReport
    }
    paidBeta = [ordered]@{
        version = $PaidBetaVersion
        path = $paidBetaInstaller
        sizeBytes = (Get-Item -LiteralPath $paidBetaInstaller).Length
        sha256 = (Get-FileHash -LiteralPath $paidBetaInstaller -Algorithm SHA256).Hash
        signatureReport = $paidBetaSigningReport
    }
    ownerActions = @()
    internalNextSteps = @(
        'Run reversible paid-beta physical smoke.',
        'Run reversible production physical smoke.',
        'Publish exact signed hashes to both control planes with rollback.',
        'Verify public downloads, manifests, signatures, update and rollback.'
    )
}
$releasePath = Join-Path $OutDir 'windows-trusted-release.json'
Save-Json -Path $releasePath -Payload $release
$release | ConvertTo-Json -Depth 10
Write-Host "release: $releasePath"
