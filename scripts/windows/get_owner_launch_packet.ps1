param(
  [Alias("ServerHost")]
  [string]$ControlPlaneHost = "72.56.32.197",
  [string]$ApiBase = "https://api.greenvpn.pro",
  [string]$AdminTokenFile = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Convert-ToJsonLiteral {
  param([string]$Value)
  return ($Value | ConvertTo-Json -Compress)
}

function Assert-NoSecretMarkers {
  param([object]$Packet)

  $payload = $Packet | ConvertTo-Json -Depth 40 -Compress
  $markers = @("secretValue", "adminToken", "privateKey", "passwordHash")
  $matches = @()
  foreach ($marker in $markers) {
    if ($payload.Contains($marker)) {
      $matches += $marker
    }
  }
  if ($matches.Count -gt 0) {
    throw "Owner packet contains forbidden secret marker(s): $($matches -join ', ')"
  }
}

function Invoke-OwnerPacketWithLocalToken {
  param(
    [string]$Base,
    [string]$TokenFile
  )

  if (-not (Test-Path -LiteralPath $TokenFile)) {
    throw "Admin token file not found: $TokenFile"
  }
  $token = (Get-Content -LiteralPath $TokenFile -Raw -Encoding UTF8).Trim()
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw "Admin token file is empty."
  }
  $headers = @{ "X-Admin-Token" = $token; "Accept" = "application/json" }
  $uri = "$($Base.TrimEnd('/'))/api/v1/admin/launch/owner-packet"
  $response = Invoke-WebRequest -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 30
  return ($response.Content | ConvertFrom-Json)
}

function Invoke-OwnerPacketWithServerToken {
  param(
    [string]$HostName,
    [string]$Base
  )

  $baseJson = Convert-ToJsonLiteral $Base
  $remoteScript = @"
import json
import urllib.request
from pathlib import Path

base = $baseJson
token_path = Path(
    "/opt/bluevpn-paid-beta/data/admin_token.txt"
    if "/paid-beta-api" in base
    else "/opt/bluevpn/backend/data/admin_token.txt"
)
token = token_path.read_text(encoding="utf-8").strip()
req = urllib.request.Request(
    base.rstrip("/") + "/api/v1/admin/launch/owner-packet",
    headers={"X-Admin-Token": token, "Accept": "application/json"},
)
with urllib.request.urlopen(req, timeout=20) as response:
    print(response.read().decode("utf-8"))
"@
  if (Get-Command ssh.exe -ErrorAction SilentlyContinue) {
    $raw = $remoteScript | & ssh.exe -o BatchMode=yes -o ConnectTimeout=10 "root@$HostName" python3 -
    if ($LASTEXITCODE -ne 0) {
      throw "Windows OpenSSH owner packet request failed."
    }
  } elseif (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $raw = $remoteScript | wsl ssh "root@$HostName" python3 -
    if ($LASTEXITCODE -ne 0) {
      throw "WSL SSH owner packet request failed."
    }
  } else {
    throw "No SSH client found. Provide -AdminTokenFile to fetch from local Windows instead."
  }
  if ([string]::IsNullOrWhiteSpace($raw)) {
    throw "Owner packet request returned empty response."
  }
  return ($raw | ConvertFrom-Json)
}

function Write-OwnerPacketSummary {
  param([object]$Packet)

  $summary = $Packet.summary
  Write-Output "Green VPN owner launch packet"
  Write-Output "version: $($Packet.version)"
  Write-Output "state: $($summary.state); ready=$($summary.ready); pending=$($summary.pending); ownerBlocked=$($summary.ownerBlocked)"
  Write-Output "commands=$($summary.commands); ownerActions=$($summary.pendingOwnerActions); dnsRecords=$($summary.dnsRecords); safeDefaults=$($summary.safeDefaults)"
  Write-Output "safeNoSecretExposure=$($Packet.safeNoSecretExposure); noSecretValues=$($Packet.policy.noSecretValues)"
  Write-Output ""
  Write-Output "Commands:"
  foreach ($command in @($Packet.commands)) {
    Write-Output "- $($command.code): secret=$($command.secret); mutationFree=$($command.mutationFree)"
    Write-Output "  $($command.command)"
    if (-not [string]::IsNullOrWhiteSpace($command.when)) {
      Write-Output "  when: $($command.when)"
    }
  }
  Write-Output ""
  Write-Output "Launch blockers:"
  foreach ($blocker in @($Packet.ownerBlockers)) {
    Write-Output "- $($blocker.code): $($blocker.title); secretInputExpected=$($blocker.secretInputExpected)"
    if (-not [string]::IsNullOrWhiteSpace($blocker.ownerInput)) {
      Write-Output "  need: $($blocker.ownerInput)"
    }
  }
  Write-Output ""
  Write-Output "Owner actions:"
  foreach ($action in @($Packet.ownerActions)) {
    Write-Output "- $($action.code): $($action.title); secretInputExpected=$($action.secretInputExpected)"
    $inputNames = @($action.ownerInputs | ForEach-Object {
      if ($_.secret) { "$($_.name) (secret)" } else { "$($_.name)" }
    })
    if ($inputNames.Count -gt 0) {
      Write-Output "  inputs: $($inputNames -join ', ')"
    }
  }
}

if ([string]::IsNullOrWhiteSpace($AdminTokenFile)) {
  $packet = Invoke-OwnerPacketWithServerToken -HostName $ControlPlaneHost -Base $ApiBase
} else {
  $packet = Invoke-OwnerPacketWithLocalToken -Base $ApiBase -TokenFile $AdminTokenFile
}

Assert-NoSecretMarkers -Packet $packet

if ($Json) {
  $packet | ConvertTo-Json -Depth 40
} else {
  Write-OwnerPacketSummary -Packet $packet
}
