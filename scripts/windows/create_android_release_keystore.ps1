param(
    [string]$KeystorePath = "android\app\greenvpn-upload-keystore.jks",
    [string]$PropertiesPath = "android\key.properties",
    [string]$Alias = "greenvpn-upload",
    [int]$ValidityDays = 10000,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $repo

$jdkDir = "C:\Program Files\Android\openjdk\jdk-21.0.8"
$keytool = Join-Path $jdkDir "bin\keytool.exe"
if (-not (Test-Path -LiteralPath $keytool)) {
    throw "keytool.exe not found: $keytool"
}

$resolvedKeystorePath = Join-Path $repo $KeystorePath
$resolvedPropertiesPath = Join-Path $repo $PropertiesPath
$keystoreDir = Split-Path -Parent $resolvedKeystorePath
$propertiesDir = Split-Path -Parent $resolvedPropertiesPath
New-Item -ItemType Directory -Force -Path $keystoreDir | Out-Null
New-Item -ItemType Directory -Force -Path $propertiesDir | Out-Null

if (((Test-Path -LiteralPath $resolvedKeystorePath) -or (Test-Path -LiteralPath $resolvedPropertiesPath)) -and -not $Force) {
    Write-Host "Android release keystore already exists."
    Write-Host "Keystore: $resolvedKeystorePath"
    Write-Host "Properties: $resolvedPropertiesPath"
    Write-Host "No secret values were printed."
    exit 0
}

if ($Force) {
    Remove-Item -LiteralPath $resolvedKeystorePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $resolvedPropertiesPath -Force -ErrorAction SilentlyContinue
}

function New-SecretPassword {
    $alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789_-"
    $bytes = New-Object byte[] 40
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return -join ($bytes | ForEach-Object { $alphabet[[int]$_ % $alphabet.Length] })
}

$storePassword = New-SecretPassword
$keyPassword = $storePassword

& $keytool `
    -genkeypair `
    -v `
    -keystore $resolvedKeystorePath `
    -storetype PKCS12 `
    -storepass $storePassword `
    -keypass $keyPassword `
    -alias $Alias `
    -keyalg RSA `
    -keysize 2048 `
    -validity $ValidityDays `
    -dname "CN=Green VPN, OU=Green VPN, O=Green VPN, L=Moscow, ST=Moscow, C=RU" | Out-Host

if ($LASTEXITCODE -ne 0) {
    throw "keytool failed with exit code $LASTEXITCODE"
}

$storeFileForGradle = $KeystorePath.Replace("\", "/").Replace("android/", "")
$properties = @"
storePassword=$storePassword
keyPassword=$keyPassword
keyAlias=$Alias
storeFile=$storeFileForGradle
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($resolvedPropertiesPath, $properties, $utf8NoBom)

Write-Host "Android release keystore created."
Write-Host "Keystore: $resolvedKeystorePath"
Write-Host "Properties: $resolvedPropertiesPath"
Write-Host "These files are ignored by git. Keep them backed up privately; no secret values were printed."
