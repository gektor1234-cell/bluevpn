param(
  [string]$Domain = "greenvpn.pro",
  [string]$ApiBase = "https://api.greenvpn.pro",
  [string]$FallbackApiBase = "",
  [Alias("ServerHost")]
  [string]$ControlPlaneHost = "72.56.32.197",
  [string]$VpnEndpointHost = "37.220.85.211",
  [string]$ServerSelfCheckApiBase = "https://api.greenvpn.pro",
  [string]$AdminToken = "",
  [string]$AdminTokenFile = "",
  [switch]$SkipServerSelfCheck,
  [switch]$ServerAdminSelfCheck,
  [switch]$NoWslFallback,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function New-Result {
  param(
    [string]$Name,
    [string]$Status,
    [string]$Message,
    [object]$Details = $null
  )
  [pscustomobject]@{
    name = $Name
    status = $Status
    message = $Message
    details = $Details
  }
}

function Resolve-Record {
  param(
    [string]$Name,
    [string]$Type
  )
  try {
    $records = Resolve-DnsName -Name $Name -Type $Type -ErrorAction Stop
    return @($records)
  } catch {
    return @()
  }
}

function Resolve-HostIps {
  param(
    [string]$HostName
  )
  $hostValue = ""
  if ($null -ne $HostName) {
    $hostValue = $HostName.Trim()
  }
  if (-not $hostValue) { return @() }
  if ($hostValue -match '^\d{1,3}(\.\d{1,3}){3}$') { return @($hostValue) }

  $ips = [System.Collections.Generic.List[string]]::new()
  foreach ($type in @("A", "AAAA")) {
    foreach ($record in @(Resolve-Record -Name $hostValue -Type $type)) {
      $ip = ""
      if ($null -ne $record.IPAddress) {
        $ip = $record.IPAddress.ToString().Trim()
      }
      if ($ip -and -not $ips.Contains($ip)) {
        $ips.Add($ip) | Out-Null
      }
    }
  }
  return @($ips)
}

function Invoke-JsonGet {
  param(
    [string]$Url,
    [hashtable]$Headers = @{}
  )
  try {
    return Invoke-RestMethod -Method Get -Uri $Url -Headers $Headers -TimeoutSec 18
  } catch {
    $nativeError = $_.Exception.Message
    if ($NoWslFallback -or -not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
      throw
    }

    $payload = @{
      url = $Url
      headers = $Headers
    } | ConvertTo-Json -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $pythonSource = @'
import base64
import json
import sys
import urllib.request

try:
    cfg = json.loads(base64.b64decode(sys.stdin.read().strip()).decode("utf-8"))
    request = urllib.request.Request(cfg["url"], headers=cfg.get("headers") or {})
    with urllib.request.urlopen(request, timeout=18) as response:
        sys.stdout.write(response.read().decode("utf-8"))
except Exception as exc:
    sys.stdout.write(json.dumps({"__greenvpn_error": f"{type(exc).__name__}: {exc}"}, ensure_ascii=False))
'@
    $pythonEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pythonSource))
    $python = "import base64; exec(base64.b64decode('$pythonEncoded').decode('utf-8'))"
    $output = $encoded | wsl.exe python3 -c $python 2>$null
    $json = ($output | Out-String).Trim()
    $jsonLike = $json -and ($json.TrimStart().StartsWith("{") -or $json.TrimStart().StartsWith("["))
    if ($LASTEXITCODE -ne 0 -or -not $jsonLike) {
      $wslError = if ($json) { ($json -split "`r?`n" | Select-Object -First 3) -join " " } else { "no output" }
      throw "Native request failed: $nativeError. WSL fallback failed: $wslError"
    }
    $parsed = $json | ConvertFrom-Json
    if ($parsed.__greenvpn_error) {
      throw "Native request failed: $nativeError. WSL fallback failed: $($parsed.__greenvpn_error)"
    }
    return $parsed
  }
}

function Add-DnsCheck {
  param(
    [System.Collections.Generic.List[object]]$Results,
    [string]$Name,
    [string]$Type,
    [string]$Expected = ""
  )
  $records = Resolve-Record -Name $Name -Type $Type
  $expectedDetails = [pscustomobject]@{
    name = $Name
    type = $Type
    expected = $Expected
  }
  if ($records.Count -eq 0) {
    $message = if ($Expected) { "Record not found. Expected: $Expected" } else { "Record not found." }
    $Results.Add((New-Result "DNS $Type $Name" "red" $message $expectedDetails))
    return
  }
  $text = ($records | Out-String).Trim()
  if ($Expected -and ($text -notlike "*$Expected*")) {
    $Results.Add((New-Result "DNS $Type $Name" "yellow" "Record exists, but expected value was not found. Expected: $Expected" ([pscustomobject]@{
      name = $Name
      type = $Type
      expected = $Expected
      observed = $text
    })))
    return
  }
  $Results.Add((New-Result "DNS $Type $Name" "green" "Record found." $text))
}

function Add-ApiEndpointSeparationCheck {
  param(
    [System.Collections.Generic.List[object]]$Results
  )
  try {
    $apiHost = ""
    try {
      $apiUri = [Uri]$ApiBase
      $apiHost = $apiUri.Host
    } catch {}
    if ([string]::IsNullOrWhiteSpace($apiHost)) {
      $apiHost = "api.$Domain"
    }

    $apiIps = @(Resolve-HostIps -HostName $apiHost)
    $endpointIps = @(Resolve-HostIps -HostName $VpnEndpointHost)
    $overlap = @($apiIps | Where-Object { $endpointIps -contains $_ })
    $details = [pscustomobject]@{
      apiHost = $apiHost
      apiIps = $apiIps
      vpnEndpointHost = $VpnEndpointHost
      vpnEndpointIps = $endpointIps
      overlap = $overlap
    }

    if (-not $apiIps -or -not $endpointIps) {
      $Results.Add((New-Result "API/VPN endpoint split" "yellow" "Could not fully resolve API host or VPN endpoint host." $details))
      return
    }

    if ($overlap.Count -gt 0) {
      $Results.Add((New-Result "API/VPN endpoint split" "red" "API/public site shares IP with the VPN endpoint. Full-tunnel WireGuard/Amnezia on Windows can block browser/API access to that same IP; move API/site or VPN endpoint to a separate public IP before public release." $details))
      return
    }

    $Results.Add((New-Result "API/VPN endpoint split" "green" "API/public site IP is separated from the VPN endpoint IP." $details))
  } catch {
    $Results.Add((New-Result "API/VPN endpoint split" "yellow" $_.Exception.Message $null))
  }
}

function Add-ServerSelfCheck {
  param(
    [System.Collections.Generic.List[object]]$Results
  )

  if ($SkipServerSelfCheck) {
    $Results.Add((New-Result "Server self-check API HTTPS" "yellow" "Skipped by -SkipServerSelfCheck." $null))
    return
  }

  $windowsSsh = Get-Command ssh.exe -ErrorAction SilentlyContinue
  $wslSsh = Get-Command wsl.exe -ErrorAction SilentlyContinue
  if (-not $windowsSsh -and -not $wslSsh) {
    $Results.Add((New-Result "Server self-check API HTTPS" "yellow" "No SSH client found; skipped remote server-side HTTPS check." $null))
    return
  }

  $url = "$($ServerSelfCheckApiBase.TrimEnd('/'))/healthz"
  try {
    if ($windowsSsh) {
      $output = & ssh.exe -T -o BatchMode=yes -o ConnectTimeout=12 "root@$ControlPlaneHost" "curl -fsS --max-time 15 '$url'" 2>&1
    } else {
      $output = & wsl.exe ssh -T -o BatchMode=yes -o ConnectTimeout=12 "root@$ControlPlaneHost" "curl -fsS --max-time 15 '$url'" 2>&1
    }
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($exitCode -ne 0) {
      throw "ssh/curl failed with exit code $exitCode. $text"
    }

    $jsonLine = @($text -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith("{") } | Select-Object -Last 1)
    if (-not $jsonLine) {
      throw "Remote check returned no JSON. $text"
    }

    $payload = ($jsonLine | Select-Object -Last 1) | ConvertFrom-Json
    $Results.Add((New-Result "Server self-check API HTTPS" "green" "Backend HTTPS works from the server side." $payload))
  } catch {
    $Results.Add((New-Result "Server self-check API HTTPS" "yellow" $_.Exception.Message $null))
  }
}

function ConvertTo-ShellSingleQuoted {
  param([string]$Value)
  return "'" + $Value.Replace("'", "'\''") + "'"
}

function Add-ServerAdminSelfCheck {
  param(
    [System.Collections.Generic.List[object]]$Results
  )

  if (-not $ServerAdminSelfCheck) {
    return
  }

  $windowsSsh = Get-Command ssh.exe -ErrorAction SilentlyContinue
  $wslSsh = Get-Command wsl.exe -ErrorAction SilentlyContinue
  if (-not $windowsSsh -and -not $wslSsh) {
    $Results.Add((New-Result "Server admin self-check" "yellow" "No SSH client found; skipped protected server-side admin checks." $null))
    return
  }

  $pythonSource = @'
import json
import urllib.request
from pathlib import Path

base = "https://api.greenvpn.pro"
token_path = Path("/opt/bluevpn/backend/data/admin_token.txt")
if not token_path.exists() or not token_path.read_text(encoding="utf-8").strip():
    print(json.dumps({"ok": False, "error": "admin_token_file_missing"}, ensure_ascii=False))
    raise SystemExit(0)

token = token_path.read_text(encoding="utf-8").strip()
paths = [
    "/api/v1/admin/readiness",
    "/api/v1/admin/launch/readiness",
    "/api/v1/admin/launch/advertising-readiness",
    "/api/v1/admin/launch/closure-plan",
    "/api/v1/admin/launch/owner-packet",
    "/api/v1/admin/site/readiness",
    "/api/v1/admin/network/readiness",
    "/api/v1/admin/network/split-plan",
    "/api/v1/admin/auth/user-flow/readiness",
    "/api/v1/admin/auth/2fa/readiness",
    "/api/v1/admin/email/readiness",
    "/api/v1/admin/billing/readiness",
    "/api/v1/admin/external-actions",
    "/api/v1/admin/alerts/readiness",
    "/api/v1/admin/analytics/summary",
    "/api/v1/admin/staff",
    "/api/v1/admin/monitoring/targets",
    "/api/v1/admin/monitoring/readiness",
    "/api/v1/admin/billing/reconciliation",
    "/api/v1/admin/billing/payment-smoke/readiness",
    "/api/v1/admin/billing/refunds/readiness",
    "/api/v1/admin/billing/promos/readiness",
    "/api/v1/admin/billing/renewals/readiness",
    "/api/v1/admin/subscriptions/expiry-readiness",
    "/api/v1/admin/support/sla",
    "/api/v1/admin/updates/readiness",
    "/api/v1/admin/windows/trust-readiness",
    "/api/v1/admin/server-catalog/publication-readiness",
    "/api/v1/admin/server-catalog/provisioning-readiness",
    "/api/v1/admin/server-health",
    "/api/v1/admin/support/actions/workflow",
    "/api/v1/admin/auth/events?limit=1",
    "/api/v1/admin/incidents/assignees",
    "/api/v1/admin/alerts/events?limit=5",
]
summary = {"ok": True, "checks": {}}
first_staff_id = None

def contains_forbidden_key(value, forbidden):
    if isinstance(value, dict):
        return any(
            str(key).strip().lower() in forbidden
            or contains_forbidden_key(item, forbidden)
            for key, item in value.items()
        )
    if isinstance(value, list):
        return any(contains_forbidden_key(item, forbidden) for item in value)
    return False

for path in paths:
    req = urllib.request.Request(base + path, headers={"X-Admin-Token": token})
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            data = json.loads(response.read().decode("utf-8"))
        item = {"http": 200}
        if path.endswith("/admin/readiness"):
            item.update({
                "productionReady": data.get("productionReady"),
                "summary": (data.get("summary") or {}).get("message"),
                "checks": len(data.get("checks") or []),
            })
        elif path.endswith("/launch/readiness"):
            launch_summary = data.get("summary") or {}
            item.update({
                "publicLaunchReady": data.get("publicLaunchReady"),
                "productionReady": data.get("productionReady"),
                "state": data.get("state"),
                "critical": launch_summary.get("critical"),
                "warnings": launch_summary.get("warnings"),
                "ready": launch_summary.get("ready"),
                "total": launch_summary.get("total"),
                "gates": len(data.get("gates") or []),
                "criticalBlockers": len(data.get("criticalBlockers") or []),
                "warningItems": len(data.get("warnings") or []),
                "summary": launch_summary.get("message"),
            })
        elif path.endswith("/launch/advertising-readiness"):
            advertising_summary = data.get("summary") or {}
            item.update({
                "state": data.get("state"),
                "mode": data.get("mode"),
                "publicAdvertisingReady": data.get("publicAdvertisingReady"),
                "paidTrafficReady": data.get("paidTrafficReady"),
                "privateDemoReady": data.get("privateDemoReady"),
                "cashCollectionReady": data.get("cashCollectionReady"),
                "publicAdBlockers": advertising_summary.get("publicAdBlockers"),
                "paidTrafficBlockers": advertising_summary.get("paidTrafficBlockers"),
                "privateDemoBlockers": advertising_summary.get("privateDemoBlockers"),
                "summary": advertising_summary.get("message"),
                "nextAction": advertising_summary.get("nextAction"),
            })
        elif path.endswith("/launch/closure-plan"):
            closure_summary = data.get("summary") or {}
            payload_text = json.dumps(data, ensure_ascii=False)
            item.update({
                "productionReady": data.get("productionReady"),
                "publicLaunchReady": data.get("publicLaunchReady"),
                "state": data.get("state"),
                "canContinueAutonomously": data.get("canContinueAutonomously"),
                "safeNoSecretExposure": data.get("safeNoSecretExposure"),
                "ready": closure_summary.get("ready"),
                "total": closure_summary.get("total"),
                "pending": closure_summary.get("pending"),
                "ownerBlocked": closure_summary.get("ownerBlocked"),
                "codeOwned": closure_summary.get("codeOwned"),
                "operationalReview": closure_summary.get("operationalReview"),
                "finalHandoffOnly": closure_summary.get("finalHandoffOnly"),
                "ownerInputsNeeded": len(data.get("ownerInputsNeeded") or []),
                "nextAutonomousActions": len(data.get("nextAutonomousActions") or []),
                "secretValuesExposed": any(marker in payload_text for marker in ["secretValue", "adminToken", "privateKey", "passwordHash"]),
            })
            if item.get("secretValuesExposed") or not item.get("safeNoSecretExposure"):
                summary["ok"] = False
        elif path.endswith("/launch/owner-packet"):
            packet_summary = data.get("summary") or {}
            payload_text = json.dumps(data, ensure_ascii=False)
            commands = data.get("commands") or []
            owner_actions = data.get("ownerActions") or []
            item.update({
                "productionReady": data.get("productionReady"),
                "publicLaunchReady": data.get("publicLaunchReady"),
                "safeNoSecretExposure": data.get("safeNoSecretExposure"),
                "noSecretValues": (data.get("policy") or {}).get("noSecretValues"),
                "commands": len(commands),
                "mutationFreeCommands": len([x for x in commands if x.get("mutationFree")]),
                "secretInputCommands": len([x for x in commands if x.get("secret")]),
                "ownerActions": len(owner_actions),
                "ownerBlockers": len(data.get("ownerBlockers") or []),
                "dnsRecords": packet_summary.get("dnsRecords"),
                "safeDefaults": packet_summary.get("safeDefaults"),
                "hasSplitPreflight": bool(data.get("splitPreflight")),
                "hasPaymentLaunchSafety": any(x.get("code") == "payment_launch_safety" for x in commands),
                "hasMonitoringProbePlan": any(x.get("code") == "monitoring_probe_plan" for x in commands),
                "afterApplyChecks": len(data.get("afterApplyChecks") or []),
                "secretValuesExposed": any(marker in payload_text for marker in ["secretValue", "adminToken", "privateKey", "passwordHash"]),
            })
            if (
                item.get("secretValuesExposed")
                or not item.get("safeNoSecretExposure")
                or not item.get("noSecretValues")
                or item.get("commands", 0) < 2
                or not item.get("hasSplitPreflight")
                or not item.get("hasPaymentLaunchSafety")
                or not item.get("hasMonitoringProbePlan")
            ):
                summary["ok"] = False
        elif path.endswith("/site/readiness"):
            site_summary = data.get("summary") or {}
            downloads = data.get("downloadTargets") or {}
            item.update({
                "productionReady": data.get("productionReady"),
                "publicSiteReady": data.get("publicSiteReady"),
                "siteUrl": data.get("siteUrl"),
                "green": site_summary.get("green"),
                "yellow": site_summary.get("yellow"),
                "checks": len(data.get("checks") or []),
                "bannedPhraseMatches": len(data.get("bannedPhraseMatches") or []),
                "windowsDownloadConfigured": downloads.get("windowsConfigured"),
                "androidDownloadConfigured": downloads.get("androidConfigured"),
                "iosDownloadConfigured": downloads.get("iosConfigured"),
                "summary": site_summary.get("message"),
            })
        elif path.endswith("/auth/user-flow/readiness"):
            auth_summary = data.get("summary") or {}
            code_policy = data.get("codePolicy") or {}
            payload_text = json.dumps(data, ensure_ascii=False)
            item.update({
                "productionReady": data.get("productionReady"),
                "publicAuthReady": data.get("publicAuthReady"),
                "primaryMethod": data.get("primaryMethod"),
                "fallbackMethod": data.get("fallbackMethod"),
                "green": auth_summary.get("green"),
                "yellow": auth_summary.get("yellow"),
                "usersTotal": auth_summary.get("usersTotal"),
                "verified24h": auth_summary.get("verified24h"),
                "problem24h": auth_summary.get("problem24h"),
                "methods": len(data.get("methods") or []),
                "checks": len(data.get("checks") or []),
                "recentProblemEvents": len(data.get("recentProblemEvents") or []),
                "devCodesEnabled": code_policy.get("devCodesEnabled"),
                "codesExposed": '"devCode"' in payload_text or '"oneTimeCode"' in payload_text,
                "tokensExposed": "accessToken" in payload_text or "refreshToken" in payload_text,
            })
            if item.get("codesExposed") or item.get("tokensExposed"):
                summary["ok"] = False
        elif path.endswith("/email/readiness"):
            item.update({
                "provider": data.get("provider"),
                "required": data.get("required"),
                "productionReady": data.get("productionReady"),
                "checks": len(data.get("checks") or []),
                "requiredActions": len(data.get("requiredActions") or []),
            })
        elif path.endswith("/sms/readiness"):
            delivery_issue = data.get("lastDeliveryIssue") or {}
            item.update({
                "provider": data.get("provider"),
                "deliveryReady": data.get("deliveryReady"),
                "productionReady": data.get("productionReady"),
                "testMode": data.get("testMode"),
                "hasLastDeliveryIssue": bool(delivery_issue),
                "lastDeliveryIssueCode": delivery_issue.get("code"),
                "lastDeliveryIssueAt": delivery_issue.get("lastFailedAt"),
                "checks": len(data.get("checks") or []),
                "requiredActions": len(data.get("requiredActions") or []),
            })
        elif path.endswith("/billing/readiness"):
            item.update({
                "provider": data.get("provider"),
                "productionReady": data.get("productionReady"),
                "checks": len(data.get("checks") or []),
                "requiredActions": len(data.get("requiredActions") or []),
                "secretValuesExposed": contains_forbidden_key(
                    data,
                    {
                        "secretkey",
                        "secret_key",
                        "paymentmethodid",
                        "payment_method_id",
                        "providerpaymentmethodid",
                    },
                ),
            })
            if item.get("secretValuesExposed"):
                summary["ok"] = False
        elif path.endswith("/external-actions"):
            actions = data.get("actions", [])
            setup_bundle = data.get("setupBundle") or {}
            policy = data.get("ownerActionPolicy") or {}
            blocking = data.get("blockingSummary") or {}
            actions_with_owner_inputs = len([x for x in actions if x.get("ownerInputs")])
            actions_with_verify_steps = len([x for x in actions if x.get("verifySteps")])
            actions_with_apply_steps = len([x for x in actions if x.get("applySteps")])
            item.update({
                "actions": len(actions),
                "ready": len([x for x in actions if x.get("status") == "ready"]),
                "pending": len([x for x in actions if x.get("status") != "ready"]),
                "hasSetupBundle": bool(setup_bundle),
                "actionsWithOwnerInputs": actions_with_owner_inputs,
                "actionsWithVerifySteps": actions_with_verify_steps,
                "actionsWithApplySteps": actions_with_apply_steps,
                "dnsRecords": len(setup_bundle.get("dnsRecords") or []),
                "hasOwnerActionPolicy": bool(policy),
                "noteRequiredStatuses": len(policy.get("noteRequiredStatuses") or []),
                "ownerNoteServerEnforced": bool(policy.get("serverEnforced")),
                "blockedNotePatterns": len(policy.get("blockedNotePatternCodes") or []),
                "hasBlockingSummary": bool(blocking),
                "doneButBackendNotReady": len(blocking.get("doneButBackendNotReadyCodes") or []),
                "missingOwnerNotes": len(blocking.get("missingOwnerNoteCodes") or []),
            })
            if (
                not setup_bundle
                or actions_with_owner_inputs < len(actions)
                or actions_with_verify_steps < len(actions)
                or not policy
                or not policy.get("serverEnforced")
                or not policy.get("blockedNotePatternCodes")
                or not blocking
            ):
                summary["ok"] = False
        elif path.endswith("/network/readiness"):
            item.update({
                "productionReady": data.get("productionReady"),
                "publicApiHosts": data.get("publicApiHosts"),
                "vpnEndpointHost": data.get("vpnEndpointHost"),
                "overlapIps": data.get("overlapIps"),
                "hasMigrationPlan": bool(data.get("migrationPlan")),
                "requiredActions": len(data.get("requiredActions") or []),
            })
        elif path.endswith("/network/split-plan"):
            migration_plan = data.get("migrationPlan") or {}
            target = migration_plan.get("targetArchitecture") or {}
            preflight = migration_plan.get("preflight") or {}
            preflight_command = str(preflight.get("command") or "")
            item.update({
                "productionReady": data.get("productionReady"),
                "requiresOwnerAction": migration_plan.get("requiresOwnerAction"),
                "phases": len(migration_plan.get("phases") or []),
                "dnsRecords": len(migration_plan.get("dnsRecords") or []),
                "publicApiHost": target.get("publicApiHost"),
                "vpnEndpointHost": target.get("vpnEndpointHost"),
                "hasPreflight": bool(preflight),
                "preflightMutationFree": bool(preflight.get("mutationFree")),
                "preflightUsesScript": "check_api_vpn_split_preflight.ps1" in preflight_command,
                "preflightJsonReady": "-Json" in preflight_command,
            })
            if not preflight or not item.get("preflightMutationFree") or not item.get("preflightUsesScript") or not item.get("preflightJsonReady"):
                summary["ok"] = False
        elif path.endswith("/alerts/readiness"):
            item.update({
                "provider": data.get("provider"),
                "productionReady": data.get("productionReady"),
                "summary": (data.get("summary") or {}).get("message"),
            })
        elif path.endswith("/analytics/summary"):
            item.update({
                "users": ((data.get("business") or {}).get("users") or {}).get("total"),
                "devices": ((data.get("business") or {}).get("devices") or {}).get("total"),
                "openSupportReports": ((data.get("support") or {}).get("reports") or {}).get("open"),
            })
        elif path.endswith("/admin/staff"):
            staff = data.get("staff") or []
            first_staff_id = staff[0].get("id") if staff else None
            item.update({
                "staff": len(staff),
                "activeSessions": sum(int(x.get("activeSessionCount") or 0) for x in staff),
                "hasSessionCounters": all("activeSessionCount" in x for x in staff),
            })
        elif path.endswith("/monitoring/targets"):
            targets = data.get("targets", [])
            item.update({
                "targets": len(targets),
                "active": len([x for x in targets if x.get("status") == "active"]),
            })
        elif path.endswith("/monitoring/readiness"):
            readiness = data.get("readiness") or {}
            install_bundle = readiness.get("installBundle") or {}
            item.update({
                "productionReady": readiness.get("productionReady"),
                "probeAgentsTotal": readiness.get("probeAgentsTotal"),
                "coveredRequiredTargets": readiness.get("coveredRequiredTargets"),
                "requiredTargetIds": len(readiness.get("requiredTargetIds") or []),
                "hasInstallBundle": bool(install_bundle),
                "installCommandUsesTokenStdin": "--token-stdin" in str(install_bundle.get("installCommand") or ""),
                "installCommandUsesServerHealth": "--server-health" in str(install_bundle.get("installCommand") or ""),
                "installCommandUsesRouteHealth": "--route-health" in str(install_bundle.get("installCommand") or ""),
                "installBundleRequiredTargets": len(install_bundle.get("requiredTargetIds") or []),
                "summary": (readiness.get("summary") or {}).get("message"),
            })
            if (
                not install_bundle
                or "--token-stdin" not in str(install_bundle.get("installCommand") or "")
                or "--server-health" not in str(install_bundle.get("installCommand") or "")
                or "--route-health" not in str(install_bundle.get("installCommand") or "")
            ):
                summary["ok"] = False
        elif path.endswith("/updates/readiness"):
            manifest = data.get("manifest") or {}
            rollback = data.get("rollbackReadiness") or ((data.get("latestReleaseReadiness") or {}).get("rollbackReadiness") or {})
            item.update({
                "productionReady": data.get("productionReady"),
                "latestVersion": manifest.get("latestVersion"),
                "fileReady": manifest.get("fileReady"),
                "publicHttpsReady": manifest.get("publicHttpsReady"),
                "releaseBlocked": manifest.get("releaseBlocked"),
                "hasRollbackReadiness": bool(rollback),
                "rollbackReady": rollback.get("rollbackReady"),
                "rollbackSource": rollback.get("source"),
                "rollbackRequiredForPublication": rollback.get("requiredForPublication"),
                "summary": (data.get("summary") or {}).get("message"),
            })
            if "rollbackReadiness" not in data:
                summary["ok"] = False
        elif path.endswith("/windows/trust-readiness"):
            trust_summary = data.get("summary") or {}
            policy = data.get("policy") or {}
            item.update({
                "productionReady": data.get("productionReady"),
                "green": trust_summary.get("green"),
                "yellow": trust_summary.get("yellow"),
                "warnings": trust_summary.get("warnings"),
                "checks": len(data.get("checks") or []),
                "requiredActions": len(data.get("requiredActions") or []),
                "currentUnsignedBuildIsTemporary": policy.get("currentUnsignedBuildIsTemporary"),
                "sslCertificatesDoNotSignExe": policy.get("sslCertificatesDoNotSignExe"),
                "summary": trust_summary.get("message"),
            })
        elif path.endswith("/billing/reconciliation"):
            reconciliation_summary = data.get("summary") or {}
            item.update({
                "requiresAttention": data.get("requiresAttention"),
                "ordersWithAttention": reconciliation_summary.get("ordersWithAttention"),
                "high": reconciliation_summary.get("high"),
                "medium": reconciliation_summary.get("medium"),
                "hasManualActivationPolicy": bool(data.get("manualActivationPolicy")),
            })
        elif path.endswith("/billing/payment-smoke/readiness"):
            smoke_summary = data.get("summary") or {}
            policy = data.get("policy") or {}
            item.update({
                "productionPaymentReady": data.get("productionPaymentReady"),
                "safeToRunSmoke": data.get("safeToRunSmoke"),
                "smokeCompleted": data.get("smokeCompleted"),
                "requiresOwnerAction": data.get("requiresOwnerAction"),
                "state": smoke_summary.get("state"),
                "yookassaOrdersTotal": smoke_summary.get("yookassaOrdersTotal"),
                "pendingWithPaymentUrl": smoke_summary.get("pendingWithPaymentUrl"),
                "successfulSmokeCandidates": smoke_summary.get("successfulSmokeCandidates"),
                "checks": len(data.get("checks") or []),
                "steps": len(data.get("smokeSteps") or []),
                "methodIdsExposed": "providerPaymentMethodId" in json.dumps(data),
                "policy": {
                    "noSyntheticActivation": policy.get("noSyntheticActivation"),
                    "activationSource": policy.get("activationSource"),
                },
            })
            if item.get("methodIdsExposed"):
                summary["ok"] = False
        elif path.endswith("/billing/refunds/readiness"):
            refund_policy = data.get("policy") or {}
            item.update({
                "productionReady": data.get("productionReady"),
                "mode": data.get("mode"),
                "executionEnabled": refund_policy.get("executionEnabled"),
                "billingPrimary": refund_policy.get("billingPrimary"),
                "workflowConfirmed": refund_policy.get("workflowConfirmed"),
                "checks": len(data.get("checks") or []),
                "requiredActions": len(data.get("requiredActions") or []),
            })
        elif path.endswith("/billing/promos/readiness"):
            promo_summary = data.get("summary") or {}
            policy = data.get("policy") or {}
            item.update({
                "safeToRunLaunchCampaign": data.get("safeToRunLaunchCampaign"),
                "requiresAttention": data.get("requiresAttention"),
                "total": promo_summary.get("total"),
                "active": promo_summary.get("active"),
                "launchReady": promo_summary.get("launchReady"),
                "activeRisky": promo_summary.get("activeRisky"),
                "recommendedCode": promo_summary.get("recommendedCode"),
                "draftEndpoint": policy.get("recommendedDraftEndpoint"),
                "recommendedCampaigns": len(data.get("recommendedCampaigns") or []),
            })
        elif path.endswith("/billing/renewals/readiness"):
            renewal_summary = data.get("summary") or {}
            policy = data.get("policy") or {}
            item.update({
                "productionPaymentReady": data.get("productionPaymentReady"),
                "paymentSmokeCompleted": data.get("paymentSmokeCompleted"),
                "paymentSmokeReady": data.get("paymentSmokeReady"),
                "safeToEnableAutoRenewalCharges": data.get("safeToEnableAutoRenewalCharges"),
                "requiresAttention": data.get("requiresAttention"),
                "dueWithinWindow": renewal_summary.get("dueWithinWindow"),
                "missingPaymentMethod": renewal_summary.get("missingPaymentMethod"),
                "chargeEligibleDryRun": renewal_summary.get("chargeEligibleDryRun"),
                "requiresPaymentSmoke": policy.get("requiresPaymentSmoke"),
                "automaticChargeExecution": policy.get("automaticChargeExecution"),
                "methodIdsExposed": "providerPaymentMethodId" in json.dumps(data),
            })
            if item.get("methodIdsExposed") or (
                item.get("safeToEnableAutoRenewalCharges")
                and not item.get("paymentSmokeReady")
            ):
                summary["ok"] = False
        elif path.endswith("/subscriptions/expiry-readiness"):
            expiry_summary = data.get("summary") or {}
            policy = data.get("policy") or {}
            item.update({
                "subscriptionEnforcementCurrentlyEnabled": data.get("subscriptionEnforcementCurrentlyEnabled"),
                "paymentSmokeCompleted": data.get("paymentSmokeCompleted"),
                "paymentSmokeReady": data.get("paymentSmokeReady"),
                "safeToEnableExpiryEnforcement": data.get("safeToEnableExpiryEnforcement"),
                "requiresAttention": data.get("requiresAttention"),
                "expiringWithinWindow": expiry_summary.get("expiringWithinWindow"),
                "expired": expiry_summary.get("expired"),
                "blockedExpiring": expiry_summary.get("blockedExpiring"),
                "missingRetentionContact": expiry_summary.get("missingRetentionContact"),
                "mode": policy.get("mode"),
                "requiresPaymentSmoke": policy.get("requiresPaymentSmoke"),
                "methodIdsExposed": "providerPaymentMethodId" in json.dumps(data),
            })
            if item.get("methodIdsExposed") or (
                item.get("safeToEnableExpiryEnforcement")
                and not item.get("paymentSmokeReady")
            ):
                summary["ok"] = False
        elif path.endswith("/support/sla"):
            sla_summary = data.get("summary") or {}
            item.update({
                "attentionRequired": data.get("attentionRequired"),
                "open": sla_summary.get("open"),
                "overdue": sla_summary.get("overdue"),
                "dueSoon": sla_summary.get("dueSoon"),
                "firstResponseMissing": sla_summary.get("firstResponseMissing"),
                "reviewPending": sla_summary.get("reviewPending"),
                "hasAttentionQueue": "attentionQueue" in data,
            })
        elif path.endswith("/server-catalog/publication-readiness"):
            item.update({
                "canPublishManagedEndpoints": data.get("canPublishManagedEndpoints"),
                "publicCatalogUnchanged": data.get("publicCatalogUnchanged"),
                "blockedManagedEntries": len(data.get("blockedManagedEntries") or []),
                "eligibleManagedEntries": len(data.get("eligibleManagedEntries") or []),
            })
        elif path.endswith("/server-catalog/provisioning-readiness"):
            contract = data.get("clientConfigContract") or {}
            onboarding = data.get("newServerOnboardingPlan") or {}
            examples = onboarding.get("recommendedExamples") or []
            item.update({
                "safeForCurrentClient": data.get("safeForCurrentClient"),
                "currentEndpointConfigReady": data.get("currentEndpointConfigReady"),
                "multiEndpointProvisioningReady": data.get("multiEndpointProvisioningReady"),
                "newVpsOnboardingReady": data.get("newVpsOnboardingReady"),
                "safeToCreateInternalDraft": onboarding.get("safeToCreateInternalDraft"),
                "draftCreationEndpoint": onboarding.get("draftCreationEndpoint"),
                "safeDraftPayloadExampleServerId": (onboarding.get("safeDraftPayloadExample") or {}).get("serverId"),
                "onboardingPhases": len(onboarding.get("phases") or []),
                "onboardingBlockedUntil": len(onboarding.get("blockedUntil") or []),
                "recommendedFirstHostname": (examples[0] or {}).get("hostname") if examples else None,
                "acceptedServerIds": contract.get("acceptedServerIds"),
                "managedCatalogClientVisible": contract.get("managedCatalogClientVisible"),
            })
            if "newServerOnboardingPlan" not in data:
                summary["ok"] = False
        elif path.endswith("/server-health"):
            health_summary = data.get("summary") or {}
            external = health_summary.get("externalProbeReadiness") or {}
            operator_plan = external.get("operatorPlan") or {}
            run_once_commands = operator_plan.get("runOnceCommands") or external.get("runOnceCommands") or []
            run_once_text = json.dumps(run_once_commands, ensure_ascii=False)
            item.update({
                "endpointsObserved": health_summary.get("endpointsObserved"),
                "healthyEndpoints": health_summary.get("healthyEndpoints"),
                "problemEndpoints": health_summary.get("problemEndpoints"),
                "serverHealthProbeAgentsTotal": health_summary.get("serverHealthProbeAgentsTotal"),
                "externalServerHealthProbeAgents": health_summary.get("externalServerHealthProbeAgents"),
                "externalProductionReady": external.get("productionReady"),
                "requiredEndpointIds": external.get("requiredEndpointIds"),
                "coveredEndpointIds": external.get("coveredEndpointIds"),
                "missingEndpointIds": external.get("missingEndpointIds"),
                "hasOperatorPlan": bool(operator_plan),
                "runOnceCommands": len(run_once_commands),
                "runOnceUsesServerHealth": "--server-health" in run_once_text or "-ServerHealth" in run_once_text,
                "runOnceUsesRouteHealth": "--route-health" in run_once_text or "-RouteHealth" in run_once_text,
                "runOnceUsesStdin": "--admin-token-stdin" in run_once_text or "-AdminTokenFromStdin" in run_once_text,
                "missingCoverageActions": len(external.get("missingCoverageActions") or []),
                "externalProbeSummary": (external.get("summary") or {}).get("message"),
            })
            if external and (not operator_plan or not item.get("runOnceUsesServerHealth") or not item.get("runOnceUsesRouteHealth") or not item.get("runOnceUsesStdin")):
                summary["ok"] = False
        elif path.endswith("/support/actions/workflow"):
            actions = data.get("actions") or []
            item.update({
                "actions": len(actions),
                "dangerous": len([x for x in actions if x.get("danger")]),
                "reasonRequired": len([x for x in actions if x.get("requiresReason")]),
            })
        elif path.startswith("/api/v1/admin/auth/events"):
            item.update({
                "events": len(data.get("events") or []),
                "filters": sorted((data.get("filters") or {}).keys()),
            })
        elif path.endswith("/incidents/assignees"):
            assignees = data.get("assignees") or []
            item.update({
                "assignees": len(assignees),
                "hasStaffIds": all("id" in assignee for assignee in assignees),
                "rawTokenExposed": "token" in json.dumps(data).lower(),
            })
        elif path.startswith("/api/v1/admin/alerts/events"):
            events = data.get("events") or []
            item.update({
                "events": len(events),
                "rawTokenExposed": "token" in json.dumps(data).lower(),
            })
        summary["checks"][path] = item
    except Exception as exc:
        summary["ok"] = False
        summary["checks"][path] = {
            "error": type(exc).__name__,
            "message": str(exc)[:180],
        }

if first_staff_id:
    staff_sessions_path = f"/api/v1/admin/staff/{first_staff_id}/sessions"
    req = urllib.request.Request(base + staff_sessions_path, headers={"X-Admin-Token": token})
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            data = json.loads(response.read().decode("utf-8"))
        summary["checks"][staff_sessions_path] = {
            "http": 200,
            "staffId": first_staff_id,
            "sessions": len(data.get("sessions") or []),
            "rawTokenExposed": any("token" in item for item in data.get("sessions") or []),
        }
    except Exception as exc:
        summary["ok"] = False
        summary["checks"][staff_sessions_path] = {
            "error": type(exc).__name__,
            "message": str(exc)[:180],
        }
else:
    summary["checks"]["/api/v1/admin/staff/{staff_id}/sessions"] = {
        "http": "skipped",
        "reason": "no staff records",
    }

try:
    req = urllib.request.Request(base + "/openapi.json")
    with urllib.request.urlopen(req, timeout=15) as response:
        openapi = json.loads(response.read().decode("utf-8"))
    routes = openapi.get("paths") or {}
    required_staff_session_routes = [
        "/api/v1/admin/auth/sessions",
        "/api/v1/admin/auth/password/change",
        "/api/v1/admin/auth/sessions/revoke",
        "/api/v1/admin/auth/sessions/revoke-others",
        "/api/v1/admin/staff/{staff_id}/sessions",
        "/api/v1/admin/staff/{staff_id}/sessions/revoke",
        "/api/v1/admin/staff/{staff_id}/sessions/revoke-all",
        "/api/v1/admin/incidents/assignees",
        "/api/v1/admin/alerts/events",
        "/api/v1/admin/launch/readiness",
        "/api/v1/admin/launch/advertising-readiness",
        "/api/v1/admin/launch/closure-plan",
        "/api/v1/admin/launch/owner-packet",
        "/api/v1/admin/site/readiness",
        "/api/v1/admin/auth/user-flow/readiness",
        "/api/v1/admin/email/readiness",
        "/api/v1/admin/billing/readiness",
        "/api/v1/admin/server-catalog/provisioning-readiness",
        "/api/v1/admin/server-catalog/draft-from-plan",
        "/api/v1/admin/network/readiness",
        "/api/v1/admin/network/split-plan",
        "/api/v1/admin/support/reports/{report_id}/review",
        "/api/v1/admin/billing/payment-smoke/readiness",
        "/api/v1/admin/billing/refunds/readiness",
        "/api/v1/admin/billing/orders/{order_id}/refund-full",
        "/api/v1/admin/billing/orders/{order_id}/cancel-stale",
        "/api/v1/admin/billing/promos/readiness",
        "/api/v1/admin/billing/promos/draft-start-campaign",
        "/api/v1/admin/billing/renewals/readiness",
        "/api/v1/admin/subscriptions/expiry-readiness",
        "/api/v1/admin/server-health",
    ]
    missing_routes = [path for path in required_staff_session_routes if path not in routes]
    summary["checks"]["staff_session_route_inventory"] = {
        "http": 200,
        "routesPresent": not missing_routes,
        "missingRoutes": missing_routes,
    }
    if missing_routes:
        summary["ok"] = False
except Exception as exc:
    summary["ok"] = False
    summary["checks"]["staff_session_route_inventory"] = {
        "error": type(exc).__name__,
        "message": str(exc)[:180],
    }

print(json.dumps(summary, ensure_ascii=False))
'@

  $adminBaseLiteral = ($ApiBase.TrimEnd('/') | ConvertTo-Json -Compress)
  $adminTokenPath = if ($ApiBase -match '/paid-beta-api(?:/|$)') {
    '/opt/bluevpn-paid-beta/data/admin_token.txt'
  } else {
    '/opt/bluevpn/backend/data/admin_token.txt'
  }
  $adminTokenPathLiteral = ($adminTokenPath | ConvertTo-Json -Compress)
  $pythonSource = $pythonSource.Replace('base = "https://api.greenvpn.pro"', "base = $adminBaseLiteral")
  $pythonSource = $pythonSource.Replace('token_path = Path("/opt/bluevpn/backend/data/admin_token.txt")', "token_path = Path($adminTokenPathLiteral)")

  try {
    if ($windowsSsh) {
      $output = $pythonSource | & ssh.exe -T -o BatchMode=yes -o ConnectTimeout=12 "root@$ControlPlaneHost" "python3 -" 2>&1
    } else {
      $output = $pythonSource | & wsl.exe ssh -T -o BatchMode=yes -o ConnectTimeout=12 "root@$ControlPlaneHost" "python3 -" 2>&1
    }
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($exitCode -ne 0) {
      throw "ssh/python failed with exit code $exitCode. $text"
    }
    $jsonLine = @($text -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith("{") } | Select-Object -Last 1)
    if (-not $jsonLine) {
      throw "Remote admin check returned no JSON. $text"
    }
    $payload = ($jsonLine | Select-Object -Last 1) | ConvertFrom-Json
    $status = if ($payload.ok) { "green" } else { "yellow" }
    $message = if ($payload.ok) { "Protected admin endpoints responded from the server side without exposing admin token." } else { "Protected admin self-check did not complete fully." }
    $Results.Add((New-Result "Server admin self-check" $status $message $payload))
  } catch {
    $Results.Add((New-Result "Server admin self-check" "yellow" $_.Exception.Message $null))
  }
}

$results = [System.Collections.Generic.List[object]]::new()

Add-DnsCheck -Results $results -Name $Domain -Type "A"
Add-DnsCheck -Results $results -Name "www.$Domain" -Type "A"
Add-DnsCheck -Results $results -Name "api.$Domain" -Type "A"
Add-DnsCheck -Results $results -Name $Domain -Type "MX" -Expected "mx.yandex.net"
Add-DnsCheck -Results $results -Name $Domain -Type "TXT" -Expected "v=spf1"
Add-DnsCheck -Results $results -Name "_dmarc.$Domain" -Type "TXT" -Expected "v=DMARC1"
Add-DnsCheck -Results $results -Name "mail._domainkey.$Domain" -Type "TXT" -Expected "v=DKIM1"

Add-ApiEndpointSeparationCheck -Results $results
Add-ServerSelfCheck -Results $results
Add-ServerAdminSelfCheck -Results $results

foreach ($base in @($ApiBase, $FallbackApiBase)) {
  if ([string]::IsNullOrWhiteSpace($base)) {
    continue
  }
  try {
    $health = Invoke-JsonGet -Url "$($base.TrimEnd('/'))/healthz"
    $results.Add((New-Result "API health $base" "green" "Backend responded." $health))
  } catch {
    $status = "red"
    $message = $_.Exception.Message
    $serverSideApiGreen = @(
      $results | Where-Object {
        ($_.name -eq "Server self-check API HTTPS" -or $_.name -eq "Server admin self-check") -and
        $_.status -eq "green"
      }
    ).Count -gt 0
    if ($base.TrimEnd('/') -eq $ApiBase.TrimEnd('/') -and $serverSideApiGreen) {
      $status = "yellow"
      $message = "Local Windows/WSL API health failed, but server-side HTTPS/admin checks are green. Local error: $message"
    }
    $results.Add((New-Result "API health $base" $status $message $null))
  }
}

if (-not $AdminToken -and $AdminTokenFile) {
  if (Test-Path -LiteralPath $AdminTokenFile) {
    $AdminToken = (Get-Content -LiteralPath $AdminTokenFile -Raw).Trim()
  }
}

if ($AdminToken) {
  $headers = @{ "X-Admin-Token" = $AdminToken }
  $adminPaths = @(
    "/api/v1/admin/readiness",
    "/api/v1/admin/launch/readiness",
    "/api/v1/admin/launch/advertising-readiness",
    "/api/v1/admin/launch/closure-plan",
    "/api/v1/admin/launch/owner-packet",
    "/api/v1/admin/site/readiness",
    "/api/v1/admin/network/readiness",
    "/api/v1/admin/network/split-plan",
    "/api/v1/admin/auth/user-flow/readiness",
    "/api/v1/admin/auth/2fa/readiness",
    "/api/v1/admin/external-actions",
    "/api/v1/admin/staff",
    "/api/v1/admin/auth/events?limit=1",
    "/api/v1/admin/email/readiness",
    "/api/v1/admin/billing/readiness",
    "/api/v1/admin/billing/reconciliation",
    "/api/v1/admin/billing/payment-smoke/readiness",
    "/api/v1/admin/billing/refunds/readiness",
    "/api/v1/admin/billing/promos/readiness",
    "/api/v1/admin/billing/renewals/readiness",
    "/api/v1/admin/subscriptions/expiry-readiness",
    "/api/v1/admin/support/sla",
    "/api/v1/admin/alerts/readiness",
    "/api/v1/admin/monitoring/readiness",
    "/api/v1/admin/updates/readiness",
    "/api/v1/admin/server-catalog/publication-readiness",
    "/api/v1/admin/server-catalog/provisioning-readiness",
    "/api/v1/admin/support/actions/workflow",
    "/api/v1/admin/incidents/assignees",
    "/api/v1/admin/alerts/events?limit=5"
  )
  foreach ($path in $adminPaths) {
    try {
      $payload = Invoke-JsonGet -Url "$($ApiBase.TrimEnd('/'))$path" -Headers $headers
      $ready = $payload.productionReady -or $payload.ok
      $status = if ($ready) { "green" } else { "yellow" }
      $message = if ($payload.message) { $payload.message } elseif ($payload.summary.message) { $payload.summary.message } else { "Endpoint responded." }
      $results.Add((New-Result "Admin $path" $status $message $payload))
    } catch {
      $results.Add((New-Result "Admin $path" "red" $_.Exception.Message $null))
    }
  }
} elseif (-not $ServerAdminSelfCheck) {
  $results.Add((New-Result "Admin readiness" "yellow" "Admin token not provided; skipped protected readiness endpoints." $null))
}

$summary = [pscustomobject]@{
  ok = -not ($results | Where-Object { $_.status -eq "red" })
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  domain = $Domain
  apiBase = $ApiBase
  green = @($results | Where-Object { $_.status -eq "green" }).Count
  yellow = @($results | Where-Object { $_.status -eq "yellow" }).Count
  red = @($results | Where-Object { $_.status -eq "red" }).Count
  results = $results
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 10
} else {
  Write-Host "[Green VPN readiness] $($summary.green) green, $($summary.yellow) yellow, $($summary.red) red"
  $results | Select-Object name, status, message | Format-Table -AutoSize
}
