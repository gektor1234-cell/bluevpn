[CmdletBinding()]
param(
    [string]$OutDir = 'C:\BlueVPN_Builds\fusion_production_promotion_20260813_b4605',
    [string]$AppVersion = '0.4.6',
    [string]$AndroidBuildNumber = '2026081301',
    [ValidateRange(0, 65535)]
    [int]$WindowsBuildNumber = 4605,
    [string]$BackendVersion = '0.9.155-fusion-production-candidate.1',
    [string]$BackendReleaseId = 'public-product-backend-fusion-production-20260813-r1',
    [string]$PaidBetaInstallerPath = 'C:\BlueVPN_Builds\paid_beta_20260813_fusion_acl_fix_v1_0.4.6\GreenVPN_Beta_Setup_0.4.6-paid-beta.2.exe',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedPaidBetaInstallerSha256 = 'B882DB6EEF672C21786608888431126FAFC997EC6D7C5CEADB6CA16DD0AEC4B3',
    [long]$ExpectedPaidBetaInstallerSize = 55497728,
    [string]$PaidBetaSmokeSummaryPath = 'C:\BlueVPN_Builds\fusion_windows_acceptance_20260813_physical_v5_b4602_afeccc7\windows-fusion-paid-beta-autonomous-summary.json',
    [string]$PaidBetaPublicVerificationPath = 'C:\BlueVPN_Builds\fusion_windows_acceptance_20260813_physical_v5_b4602_afeccc7\public-release-verification-4602.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repo

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

$status = @(& git status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw 'Unable to read Git status.' }
if ($status.Count -ne 0) {
    throw 'Fusion production promotion packages require a clean Git worktree.'
}
$head = (& git rev-parse HEAD).Trim()
$branch = (& git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or -not $head) {
    throw 'Unable to resolve source commit.'
}

$allowedRoot = [IO.Path]::GetFullPath('C:\BlueVPN_Builds').TrimEnd('\') + '\'
$resolvedOut = [IO.Path]::GetFullPath($OutDir).TrimEnd('\')
if (-not ($resolvedOut + '\').StartsWith(
        $allowedRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Unsafe promotion output path: $resolvedOut"
}
if (Test-Path -LiteralPath $resolvedOut) {
    throw "Promotion output already exists; use a new immutable path: $resolvedOut"
}

$betaInstaller = Get-Item -LiteralPath $PaidBetaInstallerPath -ErrorAction Stop
$betaHash = (Get-FileHash -LiteralPath $betaInstaller.FullName -Algorithm SHA256).Hash
Assert-True ($betaHash -eq $ExpectedPaidBetaInstallerSha256.ToUpperInvariant()) `
    'Paid-beta installer SHA-256 does not match the accepted Windows candidate.'
Assert-True ([long]$betaInstaller.Length -eq $ExpectedPaidBetaInstallerSize) `
    'Paid-beta installer size does not match the accepted Windows candidate.'

$smoke = Get-Content -LiteralPath $PaidBetaSmokeSummaryPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
Assert-True ([bool]$smoke.success) 'Paid-beta Windows smoke did not succeed.'
Assert-True ([bool]$smoke.initialBaseline.success) `
    'Paid-beta Windows smoke lacks a safe initial baseline.'
Assert-True ([bool]$smoke.fusionUi.success) `
    'Paid-beta Windows smoke lacks a successful Fusion UI audit.'
Assert-True ([bool]$smoke.fusionUi.screenshot.visualContractPassed) `
    'Paid-beta Windows screenshot failed the visual contract.'
Assert-True ([double]$smoke.freshConnect.logSeconds -le 30) `
    'Paid-beta fresh connection exceeded the accepted client log threshold.'
Assert-True ([bool]$smoke.freshConnect.probeConfirmed) `
    'Paid-beta fresh connection lacks a confirmed data-plane probe.'
Assert-True ([bool]$smoke.freshConnect.privilegedTakeoverConfirmed) `
    'Paid-beta fresh connection lacks privileged takeover proof.'
Assert-True ([double]$smoke.cachedConnect.logSeconds -le 30) `
    'Paid-beta cached connection exceeded the accepted client log threshold.'
Assert-True ([bool]$smoke.cachedConnect.cachedRouteConfirmed) `
    'Paid-beta cached connection lacks cached-route proof.'
foreach ($entry in $smoke.cleanup.PSObject.Properties) {
    Assert-True ([bool]$entry.Value) "Paid-beta cleanup check failed: $($entry.Name)"
}
Assert-True (
    [string]$smoke.installer.sha256 -eq $ExpectedPaidBetaInstallerSha256.ToUpperInvariant()
) 'Smoke report is not bound to the exact paid-beta installer.'
Assert-True (
    [long]$smoke.installer.size -eq $ExpectedPaidBetaInstallerSize
) 'Smoke report installer size is not exact.'

$publicVerification = Get-Content -LiteralPath $PaidBetaPublicVerificationPath `
    -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ([bool]$publicVerification.success) `
    'Paid-beta public verification did not succeed.'
Assert-True ([int]$publicVerification.checksPassed -eq 12) `
    'Paid-beta public verification is not the complete 12/12 report.'
Assert-True (
    [string]$publicVerification.paidBetaWindowsVersion -eq '0.4.6-paid-beta.2'
) 'Paid-beta public verification reports the wrong Windows version.'

New-Item -ItemType Directory -Path $resolvedOut | Out-Null
$clientOut = Join-Path $resolvedOut 'clients'
$backendOut = Join-Path $resolvedOut 'backend'

& (Join-Path $PSScriptRoot 'build_public_product.ps1') `
    -Mode both `
    -AppVersion $AppVersion `
    -WindowsAppVersion $AppVersion `
    -WindowsBuildNumber $WindowsBuildNumber `
    -AndroidBuildNumber $AndroidBuildNumber `
    -OutDir $clientOut `
    -EnableTransportCascade $true `
    -EnableFusionUi $true `
    -PrepareFusionProductionPromotionCandidate
if ($LASTEXITCODE -ne 0) {
    throw 'Fusion public-product client build failed.'
}

$backendResult = & (Join-Path $PSScriptRoot 'prepare_public_product_backend_bundle.ps1') `
    -ReleaseId $BackendReleaseId `
    -BackendVersion $BackendVersion `
    -OutDir $backendOut
if ($LASTEXITCODE -ne 0) {
    throw 'Fusion public-product backend bundle failed.'
}
$backendResult = @($backendResult) | Select-Object -Last 1

$clientManifestPath = Join-Path $clientOut 'public-product-artifacts.json'
$clientManifest = Get-Content -LiteralPath $clientManifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
Assert-True (-not [bool]$clientManifest.productionPublished) `
    'Client build unexpectedly reports production publication.'
Assert-True ([bool]$clientManifest.fusionUiEnabled) `
    'Client build does not contain Fusion UI.'
Assert-True ([bool]$clientManifest.fusionProductionPromotionCandidate) `
    'Client build is missing the explicit promotion-candidate marker.'
Assert-True ([bool]$clientManifest.ownerApprovalRequired) `
    'Client build does not retain the owner approval gate.'

$artifacts = @(
    foreach ($entry in @(
        [pscustomobject]@{
            kind = 'android-apk'
            path = ($clientManifest.artifacts | Where-Object {
                $_.platform -eq 'android' -and $_.artifactType -ne 'aab'
            } | Select-Object -First 1).path
        },
        [pscustomobject]@{
            kind = 'windows-installer'
            path = ($clientManifest.artifacts | Where-Object {
                $_.platform -eq 'windows'
            } | Select-Object -First 1).path
        },
        [pscustomobject]@{ kind = 'backend-bundle'; path = $backendResult.archive }
    )) {
        $item = Get-Item -LiteralPath $entry.path -ErrorAction Stop
        [ordered]@{
            kind = $entry.kind
            path = $item.FullName
            sizeBytes = $item.Length
            sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
            signatureStatus = if ($entry.kind -eq 'windows-installer') {
                (Get-AuthenticodeSignature -LiteralPath $item.FullName).Status.ToString()
            }
            else { $null }
        }
    }
)

$manifest = [ordered]@{
    schema = 1
    product = 'Green VPN Fusion'
    releaseClass = 'production-promotion-candidate'
    productionPublished = $false
    deploymentAttempted = $false
    containsSecrets = $false
    source = [ordered]@{
        repository = $repo
        branch = $branch
        commit = $head
        clean = $true
    }
    target = [ordered]@{
        appVersion = $AppVersion
        androidBuildNumber = $AndroidBuildNumber
        windowsBuildNumber = $WindowsBuildNumber
        backendVersion = $BackendVersion
    }
    acceptedPaidBeta = [ordered]@{
        windowsVersion = '0.4.6-paid-beta.2+4602'
        installerSha256 = $betaHash
        installerSize = $betaInstaller.Length
        smokeSummary = $PaidBetaSmokeSummaryPath
        publicVerification = $PaidBetaPublicVerificationPath
        freshConnectLogSeconds = [double]$smoke.freshConnect.logSeconds
        freshConnectWallSeconds = [double]$smoke.freshConnect.wallSeconds
        cachedConnectLogSeconds = [double]$smoke.cachedConnect.logSeconds
        cachedConnectWallSeconds = [double]$smoke.cachedConnect.wallSeconds
        cleanupConfirmed = $true
    }
    productionWindowsSmoke = [ordered]@{
        required = $true
        status = 'pending'
        reason = 'Production runtime bytes differ from the accepted paid-beta installer.'
    }
    ownerApprovalRequired = $true
    requiredOwnerGates = @(
        [ordered]@{ code = 'fusion_ui_acceptance'; status = 'pending' },
        [ordered]@{
            code = 'windows_signature_or_smartscreen_acceptance'
            status = 'pending'
        },
        [ordered]@{ code = 'stable_production_promotion'; status = 'pending' }
    )
    rollout = [ordered]@{
        order = @(
            'backend_fallback_dry_run_and_apply',
            'backend_primary_dry_run_and_apply',
            'verify_backend_and_commercial_fail_closed',
            'clients_fallback_dry_run_and_apply',
            'clients_primary_dry_run_and_apply',
            'verify_four_public_bodies_and_public_surface'
        )
        rollbackRequired = $true
        friendlyLinnetExcluded = '5.129.237.163'
    }
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    artifacts = $artifacts
}
$manifestPath = Join-Path $resolvedOut 'fusion-production-promotion-manifest.json'
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText(
    $manifestPath,
    ($manifest | ConvertTo-Json -Depth 10) + "`n",
    $utf8
)

[pscustomobject]@{
    success = $true
    productionPublished = $false
    sourceCommit = $head
    manifest = $manifestPath
    artifacts = $artifacts
    ownerGates = @($manifest.requiredOwnerGates.code)
}
