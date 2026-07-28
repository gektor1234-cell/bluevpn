param(
  [string]$ServerHost = "37.220.85.211",
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
  $markers = @(
    "secretValue",
    "adminToken",
    "privateKey",
    "passwordHash",
    "providerPaymentMethodId"
  )
  $matches = @()
  foreach ($marker in $markers) {
    if ($text.Contains($marker)) {
      $matches += $marker
    }
  }
  if ($matches.Count -gt 0) {
    throw "Payment launch safety payload contains forbidden marker(s): $($matches -join ', ')"
  }
}

function Invoke-PaymentSafetyWithLocalToken {
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
    "/api/v1/admin/billing/readiness",
    "/api/v1/admin/billing/payment-smoke/readiness",
    "/api/v1/admin/billing/refunds/readiness",
    "/api/v1/admin/billing/renewals/readiness",
    "/api/v1/admin/subscriptions/expiry-readiness"
  )
  $responses = @{}
  foreach ($path in $paths) {
    $response = Invoke-WebRequest -Uri "$baseUrl$path" -Headers $headers -UseBasicParsing -TimeoutSec 30
    $responses[$path] = ($response.Content | ConvertFrom-Json)
  }
  return Convert-PaymentSafetyPayload -Responses $responses
}

function Invoke-PaymentSafetyWithServerToken {
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
    "/api/v1/admin/billing/readiness",
    "/api/v1/admin/billing/payment-smoke/readiness",
    "/api/v1/admin/billing/refunds/readiness",
    "/api/v1/admin/billing/renewals/readiness",
    "/api/v1/admin/subscriptions/expiry-readiness",
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
      throw "Windows OpenSSH payment readiness request failed."
    }
  } elseif (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $raw = $remoteScript | wsl ssh "root@$HostName" python3 -
    if ($LASTEXITCODE -ne 0) {
      throw "WSL SSH payment readiness request failed."
    }
  } else {
    throw "No SSH client found. Provide -AdminTokenFile to fetch from local Windows instead."
  }
  if ([string]::IsNullOrWhiteSpace($raw)) {
    throw "Payment launch safety request returned empty response."
  }
  $responses = $raw | ConvertFrom-Json
  return Convert-PaymentSafetyPayload -Responses $responses
}

function Convert-PaymentSafetyPayload {
  param([object]$Responses)

  $payment = $Responses."/api/v1/admin/billing/readiness"
  $smoke = $Responses."/api/v1/admin/billing/payment-smoke/readiness"
  $refunds = $Responses."/api/v1/admin/billing/refunds/readiness"
  $renewals = $Responses."/api/v1/admin/billing/renewals/readiness"
  $expiry = $Responses."/api/v1/admin/subscriptions/expiry-readiness"

  $smokeSummary = $smoke.summary
  $renewalSummary = $renewals.summary
  $expirySummary = $expiry.summary

  $payload = [ordered]@{
    ok = $true
    version = $smoke.version
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    productionPaymentReady = [bool]$smoke.productionPaymentReady
    safeToRunSmoke = [bool]$smoke.safeToRunSmoke
    smokeCompleted = [bool]$smoke.smokeCompleted
    refundProductionReady = [bool]$refunds.productionReady
    refundExecutionEnabled = [bool]$refunds.policy.executionEnabled
    refundBillingPrimary = [bool]$refunds.policy.billingPrimary
    renewalSafeToEnableCharges = [bool]$renewals.safeToEnableAutoRenewalCharges
    renewalPaymentSmokeReady = [bool]$renewals.paymentSmokeReady
    renewalRequiresPaymentSmoke = [bool]$renewals.policy.requiresPaymentSmoke
    expirySafeToEnableEnforcement = [bool]$expiry.safeToEnableExpiryEnforcement
    expiryPaymentSmokeReady = [bool]$expiry.paymentSmokeReady
    expiryRequiresPaymentSmoke = [bool]$expiry.policy.requiresPaymentSmoke
    safeForAutomaticBilling = (
      [bool]$smoke.productionReady -and
      [bool]$refunds.productionReady -and
      [bool]$renewals.safeToEnableAutoRenewalCharges -and
      [bool]$expiry.safeToEnableExpiryEnforcement
    )
    summary = [ordered]@{
      smokeState = $smokeSummary.state
      smokeMessage = $smokeSummary.message
      yookassaOrdersTotal = $smokeSummary.yookassaOrdersTotal
      successfulSmokeCandidates = $smokeSummary.successfulSmokeCandidates
      renewalMessage = $renewalSummary.message
      renewalDueWithinWindow = $renewalSummary.dueWithinWindow
      renewalPendingOrderConflicts = $renewalSummary.pendingOrderConflicts
      expiryMessage = $expirySummary.message
      expiryExpiringWithinWindow = $expirySummary.expiringWithinWindow
      expiryBlockedExpiring = $expirySummary.blockedExpiring
    }
    policy = [ordered]@{
      noSecretValues = $true
      noProviderPaymentMethodIds = $true
      requiresPaymentSmokeBeforeAutoRenewal = $true
      requiresPaymentSmokeBeforeExpiryEnforcement = $true
      requiresOwnerConfirmedFullRefundSmoke = $true
    }
  }

  return [pscustomobject]$payload
}

function Write-PaymentSafetySummary {
  param([object]$Payload)

  Write-Output "Green VPN payment launch safety"
  Write-Output "version: $($Payload.version)"
  Write-Output "productionPaymentReady=$($Payload.productionPaymentReady); safeToRunSmoke=$($Payload.safeToRunSmoke); smokeCompleted=$($Payload.smokeCompleted)"
  Write-Output "refundProductionReady=$($Payload.refundProductionReady); refundExecutionEnabled=$($Payload.refundExecutionEnabled); refundBillingPrimary=$($Payload.refundBillingPrimary)"
  Write-Output "renewalSafeToEnableCharges=$($Payload.renewalSafeToEnableCharges); renewalPaymentSmokeReady=$($Payload.renewalPaymentSmokeReady); renewalRequiresPaymentSmoke=$($Payload.renewalRequiresPaymentSmoke)"
  Write-Output "expirySafeToEnableEnforcement=$($Payload.expirySafeToEnableEnforcement); expiryPaymentSmokeReady=$($Payload.expiryPaymentSmokeReady); expiryRequiresPaymentSmoke=$($Payload.expiryRequiresPaymentSmoke)"
  Write-Output "safeForAutomaticBilling=$($Payload.safeForAutomaticBilling)"
  Write-Output ""
  Write-Output "Summary:"
  Write-Output "- smoke: $($Payload.summary.smokeState); $($Payload.summary.smokeMessage)"
  Write-Output "- renewals: $($Payload.summary.renewalMessage)"
  Write-Output "- expiry: $($Payload.summary.expiryMessage)"
}

if ([string]::IsNullOrWhiteSpace($AdminTokenFile)) {
  $payload = Invoke-PaymentSafetyWithServerToken -HostName $ServerHost -Base $ApiBase
} else {
  $payload = Invoke-PaymentSafetyWithLocalToken -Base $ApiBase -TokenFile $AdminTokenFile
}

Assert-NoSensitiveMarkers -Payload $payload

if ($Json) {
  $payload | ConvertTo-Json -Depth 30
} else {
  Write-PaymentSafetySummary -Payload $payload
}
