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

function Assert-NoSensitiveMarkers {
  param([object]$Payload)

  $text = $Payload | ConvertTo-Json -Depth 50 -Compress
  $markers = @("secretValue", "adminToken", "privateKey", "passwordHash")
  $matches = @()
  foreach ($marker in $markers) {
    if ($text.Contains($marker)) {
      $matches += $marker
    }
  }
  if ($matches.Count -gt 0) {
    throw "Monitoring probe plan contains forbidden marker(s): $($matches -join ', ')"
  }
}

function Invoke-MonitoringPlanWithLocalToken {
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
  $baseUrl = $Base.TrimEnd("/")
  $paths = @(
    "/api/v1/admin/monitoring/readiness",
    "/api/v1/admin/server-health"
  )
  $responses = @{}
  foreach ($path in $paths) {
    $response = Invoke-WebRequest -Uri "$baseUrl$path" -Headers $headers -UseBasicParsing -TimeoutSec 30
    $responses[$path] = ($response.Content | ConvertFrom-Json)
  }
  return Convert-MonitoringPlanPayload -Responses $responses
}

function Invoke-MonitoringPlanWithServerToken {
  param(
    [string]$HostName,
    [string]$Base
  )

  $baseJson = Convert-ToJsonLiteral $Base
  $remoteScript = @"
import json
import urllib.request
from pathlib import Path

base = $baseJson.rstrip("/")
token_path = Path(
    "/opt/bluevpn-paid-beta/data/admin_token.txt"
    if "/paid-beta-api" in base
    else "/opt/bluevpn/backend/data/admin_token.txt"
)
token = token_path.read_text(encoding="utf-8").strip()
paths = [
    "/api/v1/admin/monitoring/readiness",
    "/api/v1/admin/server-health",
]
responses = {}
for path in paths:
    req = urllib.request.Request(
        base + path,
        headers={"X-Admin-Token": token, "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=20) as response:
        responses[path] = json.loads(response.read().decode("utf-8"))
print(json.dumps(responses, ensure_ascii=False))
"@
  if (Get-Command ssh.exe -ErrorAction SilentlyContinue) {
    $raw = $remoteScript | & ssh.exe -o BatchMode=yes -o ConnectTimeout=10 "root@$HostName" python3 -
    if ($LASTEXITCODE -ne 0) {
      throw "Windows OpenSSH monitoring plan request failed."
    }
  } elseif (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $raw = $remoteScript | & wsl.exe ssh -o BatchMode=yes -o ConnectTimeout=10 "root@$HostName" python3 -
    if ($LASTEXITCODE -ne 0) {
      throw "WSL SSH monitoring plan request failed."
    }
  } else {
    throw "No SSH client found. Provide -AdminTokenFile to fetch from local Windows instead."
  }
  if ([string]::IsNullOrWhiteSpace($raw)) {
    throw "Monitoring probe plan request returned empty response."
  }
  $responses = $raw | ConvertFrom-Json
  return Convert-MonitoringPlanPayload -Responses $responses
}

function Convert-MonitoringPlanPayload {
  param([object]$Responses)

  $monitoring = $Responses."/api/v1/admin/monitoring/readiness"
  $serverHealth = $Responses."/api/v1/admin/server-health"
  $readiness = $monitoring.readiness
  $installBundle = $readiness.installBundle
  $serverSummary = $serverHealth.summary
  $externalProbe = $serverSummary.externalProbeReadiness
  $operatorPlan = $externalProbe.operatorPlan
  $installCommand = [string]($installBundle.installCommand)
  $operatorInstallCommand = [string]($operatorPlan.systemdInstallCommand)
  $runOnceCommands = @($operatorPlan.runOnceCommands | ForEach-Object { $_.command })
  $commandText = (@($installCommand, $operatorInstallCommand) + $runOnceCommands) -join "`n"
  $safeToProceed = (
    [bool]$readiness.productionReady -and
    [bool]$externalProbe.productionReady
  )

  $payload = [ordered]@{
    ok = $true
    version = $monitoring.version
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    monitoringProductionReady = [bool]$readiness.productionReady
    externalServerHealthProductionReady = [bool]$externalProbe.productionReady
    probeAgentsTotal = $readiness.probeAgentsTotal
    coveredRequiredTargets = $readiness.coveredRequiredTargets
    requiredTargetIds = @($readiness.requiredTargetIds)
    requiredEndpointIds = @($externalProbe.requiredEndpointIds)
    missingEndpointIds = @($externalProbe.missingEndpointIds)
    installCommandUsesTokenStdin = (
      $commandText.Contains("--token-stdin") -or
      $commandText.Contains("--admin-token-stdin") -or
      $commandText.Contains("-AdminTokenFromStdin")
    )
    installCommandUsesServerHealth = (
      $commandText.Contains("--server-health") -or
      $commandText.Contains("-ServerHealth")
    )
    installCommandUsesRouteHealth = (
      $commandText.Contains("--route-health") -or
      $commandText.Contains("-RouteHealth")
    )
    hasOperatorPlan = [bool]$operatorPlan
    runOnceCommands = $runOnceCommands
    installCommand = $(if ($operatorInstallCommand) { $operatorInstallCommand } else { $installCommand })
    verifySteps = @($installBundle.verifySteps)
    safeToProceed = $safeToProceed
    summary = [ordered]@{
      monitoring = $readiness.summary.message
      serverHealth = $externalProbe.summary.message
      missingCoverageActions = @($externalProbe.missingCoverageActions)
    }
    policy = [ordered]@{
      noSecretValues = $true
      tokenInput = "Admin token must be entered only on the probe host through stdin or a local token file."
      ownerAction = $(if ($safeToProceed) {
        "No additional monitoring host is required while current probe coverage remains green."
      } else {
        "Provision or repair a separate monitoring VPS/probe host until required coverage is green."
      })
    }
  }

  return [pscustomobject]$payload
}

function Write-MonitoringPlanSummary {
  param([object]$Payload)

  Write-Output "Green VPN monitoring probe plan"
  Write-Output "version: $($Payload.version)"
  Write-Output "monitoringProductionReady=$($Payload.monitoringProductionReady); externalServerHealthProductionReady=$($Payload.externalServerHealthProductionReady)"
  Write-Output "probeAgentsTotal=$($Payload.probeAgentsTotal); coveredRequiredTargets=$($Payload.coveredRequiredTargets)"
  Write-Output "requiredTargetIds=$(@($Payload.requiredTargetIds) -join ', ')"
  Write-Output "requiredEndpointIds=$(@($Payload.requiredEndpointIds) -join ', ')"
  Write-Output "missingEndpointIds=$(@($Payload.missingEndpointIds) -join ', ')"
  Write-Output "installCommandUsesTokenStdin=$($Payload.installCommandUsesTokenStdin); installCommandUsesServerHealth=$($Payload.installCommandUsesServerHealth); installCommandUsesRouteHealth=$($Payload.installCommandUsesRouteHealth)"
  Write-Output "safeToProceed=$($Payload.safeToProceed)"
  Write-Output ""
  Write-Output "Run once commands:"
  foreach ($command in @($Payload.runOnceCommands)) {
    Write-Output "- $command"
  }
  Write-Output ""
  Write-Output "Install command:"
  Write-Output $Payload.installCommand
  Write-Output ""
  Write-Output "Summary:"
  Write-Output "- monitoring: $($Payload.summary.monitoring)"
  Write-Output "- server-health: $($Payload.summary.serverHealth)"
}

if ([string]::IsNullOrWhiteSpace($AdminTokenFile)) {
  $payload = Invoke-MonitoringPlanWithServerToken -HostName $ControlPlaneHost -Base $ApiBase
} else {
  $payload = Invoke-MonitoringPlanWithLocalToken -Base $ApiBase -TokenFile $AdminTokenFile
}

Assert-NoSensitiveMarkers -Payload $payload

if ($Json) {
  $payload | ConvertTo-Json -Depth 40
} else {
  Write-MonitoringPlanSummary -Payload $payload
}
