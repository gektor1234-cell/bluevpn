param(
    [string]$PrimarySiteBaseUrl = "https://greenvpn.pro",
    [string]$FallbackSiteBaseUrl = "https://176-113-81-35.sslip.io",
    [Parameter(Mandatory = $true)][string]$ProductionAndroidSha256,
    [Parameter(Mandatory = $true)][string]$TestAndroidSha256,
    [Parameter(Mandatory = $true)][string]$ProductionWindowsSha256,
    [Parameter(Mandatory = $true)][string]$TestWindowsSha256,
    [string[]]$IncludeName = @(),
    [ValidateRange(30, 600)][int]$TimeoutSec = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch "^[0-9A-Fa-f]{64}$") {
        throw "Expected SHA-256 value is invalid."
    }
    return $Value.ToUpperInvariant()
}

$primary = $PrimarySiteBaseUrl.TrimEnd("/")
$fallback = $FallbackSiteBaseUrl.TrimEnd("/")
$productionAndroid = Assert-Sha256 $ProductionAndroidSha256
$testAndroid = Assert-Sha256 $TestAndroidSha256
$productionWindows = Assert-Sha256 $ProductionWindowsSha256
$testWindows = Assert-Sha256 $TestWindowsSha256

$items = @(
    [pscustomobject]@{ name = "android-production-primary"; url = "$primary/downloads/GreenVPN_Android.apk"; sha256 = $productionAndroid }
    [pscustomobject]@{ name = "android-production-fallback"; url = "$fallback/downloads/GreenVPN_Android.apk"; sha256 = $productionAndroid }
    [pscustomobject]@{ name = "android-test-primary"; url = "$primary/paid-beta/downloads/GreenVPN_Android.apk"; sha256 = $testAndroid }
    [pscustomobject]@{ name = "android-test-fallback"; url = "$fallback/paid-beta/downloads/GreenVPN_Android.apk"; sha256 = $testAndroid }
    [pscustomobject]@{ name = "windows-production-primary"; url = "$primary/downloads/GreenVPN_Setup.exe"; sha256 = $productionWindows }
    [pscustomobject]@{ name = "windows-production-fallback"; url = "$fallback/downloads/GreenVPN_Setup.exe"; sha256 = $productionWindows }
    [pscustomobject]@{ name = "windows-test-primary"; url = "$primary/paid-beta/downloads/GreenVPN_Setup.exe"; sha256 = $testWindows }
    [pscustomobject]@{ name = "windows-test-fallback"; url = "$fallback/paid-beta/downloads/GreenVPN_Setup.exe"; sha256 = $testWindows }
)

if ($IncludeName.Count -gt 0) {
    $unknownNames = @($IncludeName | Where-Object { $_ -notin @($items.name) })
    if ($unknownNames.Count -gt 0) {
        throw "Unknown public release artifact name: $($unknownNames -join ', ')"
    }
    $items = @($items | Where-Object { $_.name -in $IncludeName })
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("greenvpn-public-hash-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$results = New-Object System.Collections.Generic.List[object]

try {
    foreach ($item in $items) {
        $extension = [IO.Path]::GetExtension(([Uri]$item.url).AbsolutePath)
        $target = Join-Path $tempRoot ($item.name + $extension)
        Invoke-WebRequest -Uri $item.url -OutFile $target -TimeoutSec $TimeoutSec
        $file = Get-Item -LiteralPath $target
        $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToUpperInvariant()
        $result = [pscustomobject]@{
            name = $item.name
            ok = $actual -eq $item.sha256
            sizeBytes = $file.Length
            sha256 = $actual
        }
        $results.Add($result)
        Write-Host ("public_download={0} ok={1} size={2}" -f $result.name, $result.ok, $result.sizeBytes)
        Remove-Item -LiteralPath $target -Force
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$failed = @($results | Where-Object { -not $_.ok })
if ($failed.Count -gt 0) {
    throw "Public release body hash verification failed for $($failed.Count) file(s)."
}

Write-Host "Public release body hashes passed: $($results.Count)/$($results.Count)"
