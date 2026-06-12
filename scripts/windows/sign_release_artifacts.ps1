param(
    [string]$CertificateThumbprint = "",

    [string[]]$Path = @(
        (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'build\windows\x64\runner\Release')
    ),

    [string]$TimestampUrl = 'http://timestamp.digicert.com',

    [string]$ExpectedPublisher = $env:GREENVPN_WINDOWS_CODE_SIGNING_PUBLISHER,

    [string[]]$RequiredLeafName = @(),

    [string]$ReportPath = "",

    [switch]$VerifyOnly,

    [switch]$AllowUnsignedInVerifyOnly,

    [switch]$SkipSignToolVerify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 80)
    Write-Host $Title
    Write-Host ('=' * 80)
}

function Resolve-SignTool {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $kitRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (Test-Path -LiteralPath $kitRoot) {
        $candidate = Get-ChildItem -LiteralPath $kitRoot -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    throw 'signtool.exe was not found. Install Windows SDK or add signtool.exe to PATH.'
}

function Get-SignableFiles {
    param([string[]]$Roots)

    $files = New-Object System.Collections.Generic.List[string]
    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        if (Test-Path -LiteralPath $root -PathType Leaf) {
            $files.Add((Resolve-Path -LiteralPath $root).Path) | Out-Null
            continue
        }

        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            throw "Sign path does not exist: $root"
        }

        Get-ChildItem -LiteralPath $root -Recurse -File |
            Where-Object { $_.Extension -in @('.exe', '.dll', '.msi', '.msix', '.appx') } |
            ForEach-Object { $files.Add($_.FullName) | Out-Null }
    }

    return $files | Sort-Object -Unique
}

function Get-FileSha256 {
    param([string]$File)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $File).Hash.ToUpperInvariant()
}

function Get-SignatureReport {
    param(
        [string]$File,
        [string]$ExpectedPublisherName
    )

    $item = Get-Item -LiteralPath $File
    $signature = Get-AuthenticodeSignature -LiteralPath $File
    $subject = ""
    $issuer = ""
    $thumbprint = ""
    $notAfter = $null
    if ($signature.SignerCertificate) {
        $subject = [string]$signature.SignerCertificate.Subject
        $issuer = [string]$signature.SignerCertificate.Issuer
        $thumbprint = [string]$signature.SignerCertificate.Thumbprint
        $notAfter = $signature.SignerCertificate.NotAfter.ToString("o")
    }
    $publisherMatches = $true
    if (-not [string]::IsNullOrWhiteSpace($ExpectedPublisherName)) {
        $publisherMatches = $subject -like "*$ExpectedPublisherName*"
    }

    return [pscustomobject]@{
        path = $item.FullName
        name = $item.Name
        sizeBytes = $item.Length
        sha256 = Get-FileSha256 -File $item.FullName
        status = [string]$signature.Status
        statusMessage = [string]$signature.StatusMessage
        signed = ($signature.Status -eq 'Valid')
        publisherMatches = [bool]$publisherMatches
        signerSubject = $subject
        signerIssuer = $issuer
        signerThumbprint = $thumbprint
        signerNotAfter = $notAfter
    }
}

function Assert-RequiredLeafNames {
    param(
        [string[]]$Files,
        [string[]]$Required
    )

    $requiredClean = @($Required | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToLowerInvariant() })
    if ($requiredClean.Count -eq 0) {
        return
    }

    $present = @{}
    foreach ($file in $Files) {
        $present[(Split-Path -Leaf $file).ToLowerInvariant()] = $true
    }
    $missing = @($requiredClean | Where-Object { -not $present.ContainsKey($_) })
    if ($missing.Count -gt 0) {
        throw "Required signable artifact(s) missing: $($missing -join ', ')"
    }
}

function Save-JsonReport {
    param(
        [string]$OutputPath,
        [object]$Payload
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        return
    }

    $fullPath = [System.IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path -Parent $fullPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fullPath -Encoding UTF8
    Write-Host "report:     $fullPath"
}

$thumbprint = ($CertificateThumbprint -replace '\s+', '').ToUpperInvariant()
if (-not $VerifyOnly) {
    if ($thumbprint -notmatch '^[0-9A-F]{40}$') {
        throw 'CertificateThumbprint must be a 40-character SHA-1 thumbprint from the Windows certificate store.'
    }
}
elseif ($thumbprint -and $thumbprint -notmatch '^[0-9A-F]{40}$') {
    throw 'CertificateThumbprint must be a 40-character SHA-1 thumbprint when provided.'
}

if ($VerifyOnly -and $SkipSignToolVerify) {
    $signTool = ""
}
else {
    $signTool = Resolve-SignTool
}
$files = @(Get-SignableFiles -Roots $Path)
if ($files.Count -eq 0) {
    throw 'No signable files were found.'
}
Assert-RequiredLeafNames -Files $files -Required $RequiredLeafName

Write-Section 'SIGNING INPUT'
$modeText = if ($VerifyOnly) { 'verify-only' } else { 'sign-and-verify' }
$signToolText = if ($signTool) { $signTool } else { 'not used' }
$thumbprintText = if ($thumbprint) { $thumbprint } else { 'not provided' }
$publisherText = if ($ExpectedPublisher) { $ExpectedPublisher } else { 'not enforced' }
Write-Host "mode:       $modeText"
Write-Host "signtool:   $signToolText"
Write-Host "thumbprint: $thumbprintText"
Write-Host "publisher:  $publisherText"
Write-Host "timestamp:  $TimestampUrl"
Write-Host "files:      $($files.Count)"

$reports = New-Object System.Collections.Generic.List[object]
foreach ($file in $files) {
    if ($VerifyOnly) {
        Write-Host "[verify] $file"
    }
    else {
        Write-Host "[sign]   $file"
        & $signTool sign /sha1 $thumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 /v $file
        if ($LASTEXITCODE -ne 0) {
            throw "signtool sign failed for $file"
        }
    }

    $signToolExit = 0
    if ($signTool) {
        & $signTool verify /pa /v $file
        $signToolExit = $LASTEXITCODE
    }
    $report = Get-SignatureReport -File $file -ExpectedPublisherName $ExpectedPublisher
    $reports.Add($report) | Out-Null

    if ($signToolExit -ne 0 -and -not ($VerifyOnly -and $AllowUnsignedInVerifyOnly)) {
        throw "signtool verify failed for $file"
    }
    if (-not $report.signed -and -not ($VerifyOnly -and $AllowUnsignedInVerifyOnly)) {
        throw "Authenticode signature is not valid for ${file}: $($report.status)"
    }
    if (-not $report.publisherMatches) {
        throw "Signer publisher does not match '$ExpectedPublisher' for ${file}: $($report.signerSubject)"
    }
}

$unsigned = @($reports | Where-Object { -not $_.signed })
$publisherMismatch = @($reports | Where-Object { -not $_.publisherMatches })
$signToolReport = if ($signTool) { $signTool } else { '' }
$payload = [pscustomobject]@{
    ok = ($unsigned.Count -eq 0 -and $publisherMismatch.Count -eq 0)
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    mode = $modeText
    signtool = $signToolReport
    signtoolVerifySkipped = [bool]($VerifyOnly -and $SkipSignToolVerify)
    timestampUrl = $TimestampUrl
    expectedPublisher = $ExpectedPublisher
    certificateThumbprint = $thumbprint
    fileCount = $reports.Count
    unsignedCount = $unsigned.Count
    publisherMismatchCount = $publisherMismatch.Count
    files = $reports.ToArray()
}
Save-JsonReport -OutputPath $ReportPath -Payload $payload

Write-Section 'DONE'
if ($unsigned.Count -gt 0 -and $VerifyOnly -and $AllowUnsignedInVerifyOnly) {
    Write-Host "Verification completed with unsigned files allowed: $($unsigned.Count)"
}
else {
    Write-Host 'All artifacts are signed and verified.'
}
