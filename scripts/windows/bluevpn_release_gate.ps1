param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\.." )).Path,
    [string]$ReleaseZip = "",
    [switch]$StrictPaymentGate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
}

function Add-Error {
    param([string]$Message)
    $errors.Add($Message) | Out-Null
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Add-Warning {
    param([string]$Message)
    $warnings.Add($Message) | Out-Null
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Add-Pass {
    param([string]$Message)
    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

function Read-Text {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Error "Missing required file: $Path"
        return ""
    }
    return Get-Content -LiteralPath $Path -Raw
}

Write-Section "BLUEVPN RELEASE GATE"
Write-Host "ProjectRoot: $ProjectRoot"
if (-not [string]::IsNullOrWhiteSpace($ReleaseZip)) {
    Write-Host "ReleaseZip:  $ReleaseZip"
}

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    throw "ProjectRoot does not exist: $ProjectRoot"
}

$mainPath = Join-Path $ProjectRoot "lib\main.dart"
$backendPath = Join-Path $ProjectRoot "backend_live\app\main.py"
$installerPath = Join-Path $ProjectRoot "scripts\windows\build_installer.ps1"
$doctorPath = Join-Path $ProjectRoot "scripts\windows\doctor_bluevpn.ps1"
$recoverPath = Join-Path $ProjectRoot "scripts\windows\bluevpn_network_recover.ps1"

$main = Read-Text $mainPath
$backend = Read-Text $backendPath
$installer = Read-Text $installerPath

Write-Section "CLIENT SAFETY CHECKS"
$forbiddenClientPatterns = @(
    "Remove-NetRoute",
    "Remove-NetIPAddress",
    "Disable-NetAdapter",
    "taskkill /PID",
    "taskkill.exe"
)

foreach ($pattern in $forbiddenClientPatterns) {
    if ($main -match [regex]::Escape($pattern)) {
        Add-Error "Forbidden network/driver cleanup pattern in lib/main.dart: $pattern"
    }
    else {
        Add-Pass "No forbidden pattern in lib/main.dart: $pattern"
    }
}

if ($main -match "const String kTunnelName = 'BlueVPNDev1';") {
    Add-Pass "Tunnel name remains BlueVPNDev1"
}
else {
    Add-Error "Tunnel name invariant was changed or could not be verified."
}

if ($main -match "37\.220\.85\.211") {
    Add-Pass "Development server host is present: 37.220.85.211"
}
else {
    Add-Error "Development server host 37.220.85.211 not found in client."
}

if ($main -match "kBuildMarker") {
    Add-Pass "Build marker is present"
}
else {
    Add-Warning "Build marker not found. Support logs will be harder to map to a build."
}

Write-Section "BACKEND API CHECKS"
$requiredBackendFragments = @(
    '@app.post("/api/v1/auth/register")',
    '@app.post("/api/v1/auth/login")',
    '@app.post("/api/v1/auth/challenge/start")',
    '@app.post("/api/v1/auth/challenge/verify")',
    '@app.get("/api/v1/auth/email/status")',
    '@app.post("/api/v1/auth/email/resend")',
    '@app.get("/api/v1/auth/email/verify"',
    '@app.get("/api/v1/auth/phone/status")',
    '@app.post("/api/v1/auth/phone/start")',
    '@app.post("/api/v1/auth/phone/verify")',
    '@app.post("/api/v1/client/bootstrap")',
    '@app.post("/api/v1/client/config")',
    '@app.post("/api/v1/support/reports")',
    '@app.get("/api/v1/admin/support/sla")',
    '@app.post("/api/v1/admin/support/reports/{report_id}/review")',
    '@app.get("/api/v1/subscription/me")',
    '@app.post("/api/v1/subscription/quote")',
    '@app.get("/api/v1/catalog/servers")',
    '@app.get("/api/v1/monitoring/status")',
    '@app.get("/api/v1/monitoring/services")',
    '@app.get("/payment/return"',
    '@app.post("/api/v1/billing/orders")',
    '@app.get("/api/v1/billing/orders")',
    '@app.get("/api/v1/billing/orders/{order_id}")',
    '@app.post("/api/v1/subscription/auto-renew/cancel")',
    '@app.get("/api/v1/admin/billing/readiness")',
    '@app.get("/api/v1/admin/billing/reconciliation")',
    '@app.get("/api/v1/admin/billing/promos/readiness")',
    '@app.post("/api/v1/admin/billing/promos/draft-start-campaign")',
    '@app.get("/api/v1/admin/billing/renewals/readiness")',
    '@app.get("/api/v1/admin/subscriptions/expiry-readiness")',
    '@app.get("/api/v1/admin/email/readiness")',
    '@app.get("/api/v1/admin/sms/readiness")',
    '@app.get("/api/v1/admin/auth/events")',
    '@app.get("/api/v1/admin/server-catalog")',
    '@app.get("/api/v1/admin/server-catalog/publication-readiness")',
    '@app.get("/api/v1/admin/server-catalog/provisioning-readiness")',
    '@app.post("/api/v1/admin/server-catalog/draft-from-plan")',
    '@app.post("/api/v1/admin/server-catalog/seed-current")',
    '@app.get("/api/v1/admin/server-health")',
    '@app.post("/api/v1/admin/server-health/observations")',
    '@app.post("/api/v1/admin/server-health/probe-current")',
    '@app.get("/api/v1/admin/monitoring/targets")',
    '@app.post("/api/v1/admin/monitoring/targets/seed-defaults")',
    '@app.get("/api/v1/admin/monitoring/service-observations")',
    '@app.get("/api/v1/admin/monitoring/probes")',
    '@app.get("/api/v1/admin/monitoring/readiness")',
    '@app.get("/api/v1/admin/updates/readiness")',
    '@app.get("/api/v1/admin/updates/releases")',
    '@app.get("/api/v1/admin/support/actions/workflow")',
    '@app.post("/api/v1/admin/users/{user_id}/support-actions")',
    '@app.get("/api/v1/admin/support/reports/{report_id}/decoded")',
    '@app.get("/api/v1/admin/incidents/assignees")',
    '@app.get("/api/v1/admin/alerts/events")',
    '@app.get("/api/v1/admin/auth/sessions")',
    '@app.post("/api/v1/admin/auth/password/change")',
    '@app.post("/api/v1/admin/auth/sessions/revoke")',
    '@app.post("/api/v1/admin/auth/sessions/revoke-others")',
    '@app.get("/api/v1/admin/staff/{staff_id}/sessions")',
    '@app.post("/api/v1/admin/staff/{staff_id}/sessions/revoke")',
    '@app.post("/api/v1/admin/staff/{staff_id}/sessions/revoke-all")'
)

foreach ($fragment in $requiredBackendFragments) {
    if ($backend.Contains($fragment)) {
        Add-Pass "Backend endpoint present: $fragment"
    }
    else {
        Add-Error "Backend endpoint missing: $fragment"
    }
}

Write-Section "BACKEND SAFETY GUARD CHECKS"
$requiredBackendSafetyFragments = @(
    'def apply_update_artifact_guard(',
    'required_update_without_artifact',
    'stable_requires_public_https',
    'grant_support_trial_3d',
    'paidSubscriptionPreserved',
    'SUPPORT_ACTIONS_REQUIRING_REASON',
    'def redact_support_report_value(value, depth: int = 0):',
    'is_sensitive_telemetry_key(safe_key)',
    'SENSITIVE_TELEMETRY_VALUE_PATTERNS',
    'decode_support_report_code(report["report"])',
    'def review_support_report(',
    'support_report_reviewed',
    'reviewedAt',
    'AUTH_CODE_MAX_VERIFY_ATTEMPTS',
    'locked_until',
    'too_many_attempts',
    'def record_auth_code_failed_attempt(',
    'SERVER_PUBLIC_AUTO_PAUSE_ENABLED',
    'def maybe_pause_public_server_candidate(',
    'server_catalog_public_candidate_auto_paused',
    'publication_paused_reason',
    'def reissue_device_keys_and_ip(device_uid: str) -> dict:',
    'support_config_refresh_applied_at',
    'support_config_refresh_applied',
    'supportConfigRefreshApplied',
    'def revoke_staff_admin_session_by_public_id(',
    'def revoke_all_staff_admin_sessions(',
    'def change_current_admin_password(',
    'admin_password_changed',
    'revokedOtherSessions',
    'admin_staff_session_revoked',
    'admin_staff_sessions_revoked',
    'def suggest_incident_runbooks(',
    'suggestedRunbooks',
    'assigneeStaffId',
    'def list_incident_assignees(',
    'admin_alert_events',
    'def list_admin_alert_events(',
    'def app_release_publication_readiness(',
    'def app_release_rollback_readiness(',
    'releaseReadiness',
    'latestReleaseReadiness',
    'rollbackReadiness',
    'rollback_artifact_missing',
    'GREENVPN_ROLLBACK_URL',
    'rollback_plan',
    'def build_server_provisioning_readiness(',
    'clientConfigContract',
    'managed_entries_not_client_visible',
    'multiEndpointProvisioningReady',
    'def external_owner_setup_bundle(',
    'setupBundle',
    'ownerInputs',
    'verifySteps',
    'OWNER_ACTION_NOTE_REQUIRED_STATUSES',
    'ownerActionPolicy',
    'blockingSummary',
    'doneButBackendNotReadyCodes',
    'Owner note is required for this external action status.',
    'def build_support_sla_dashboard(',
    'def backfill_support_report_workflow_fields(',
    'support_report_sla_status',
    'firstResponseMissing',
    'attentionQueue',
    'GREENVPN_AUTH_CODE_LOCKOUT_MINUTES',
    'v=DMARC1; p=none',
    'def service_monitoring_probe_install_bundle(',
    'installBundle',
    '--token-stdin',
    '--server-health',
    '/etc/greenvpn-monitoring/admin_token',
    'def server_health_external_probe_readiness(',
    'external_endpoint_probe_readiness',
    'externalProbeReadiness',
    'def sync_server_health_observation_incident(',
    'server-health:',
    'server_health_observation',
    'def billing_reconciliation_payload(',
    'def billing_order_requires_attention(',
    'paid_not_activated',
    'Failed or canceled billing order cannot be activated manually.',
    'def billing_promo_launch_readiness_payload(',
    'def create_launch_promo_draft(',
    'PROMO_LAUNCH_RECOMMENDED_CODE',
    'def billing_renewal_readiness_payload(',
    'dry_run_readiness_only',
    'safeToEnableAutoRenewalCharges',
    'hasProviderPaymentMethod',
    'def subscription_expiry_readiness_payload(',
    'expiry_readiness_only',
    'safeToEnableExpiryEnforcement',
    'BLUEVPN_DATA_DIR',
    'def backfill_expired_non_paid_subscriptions(',
    'safePlanCodes'
)

foreach ($fragment in $requiredBackendSafetyFragments) {
    if ($backend.Contains($fragment)) {
        Add-Pass "Backend safety guard present: $fragment"
    }
    else {
        Add-Error "Backend safety guard missing: $fragment"
    }
}

if ($backend.Contains('@app.post("/api/v1/subscription/apply")')) {
    if ($backend.Contains("Direct tariff activation is disabled")) {
        Add-Pass "Public subscription/apply endpoint is disabled and cannot activate paid tariff directly"
    }
    else {
        $msg = "Direct subscription apply endpoint can still activate tariffs. Public paid release must use billing orders only."
        if ($StrictPaymentGate) {
            Add-Error $msg
        }
        else {
            Add-Warning $msg
        }
    }
}
else {
    Add-Pass "No public subscription/apply endpoint found"
}

Write-Section "SUPPORT REPORT CLIENT FLOW CHECKS"
$requiredSupportReportClientFragments = @(
    'Future<ApiResult<Map<String, dynamic>>> sendSupportReport',
    "path: '/api/v1/support/reports'",
    'String _buildSupportReportCode()',
    "return 'GVPN1.",
    'Future<void> _sendReport()',
    '_fallbackReportCode = result.ok ? null : reportCode',
    'Future<void> _copyFallbackReportCode()'
)

foreach ($fragment in $requiredSupportReportClientFragments) {
    if ($main.Contains($fragment)) {
        Add-Pass "Support report client flow present: $fragment"
    }
    else {
        Add-Error "Support report client flow missing: $fragment"
    }
}

Write-Section "INSTALLER CHECKS"
if ($installer.Contains("/uninstalltunnelservice BlueVPNDev1")) {
    Add-Pass "Installer/uninstaller stops only BlueVPNDev1 via WireGuard"
}
else {
    Add-Error "Installer/uninstaller does not explicitly uninstall BlueVPNDev1 tunnel."
}

if (Test-Path -LiteralPath $doctorPath) {
    Add-Pass "Doctor script present"
}
else {
    Add-Warning "Doctor script missing from source tree."
}

if (Test-Path -LiteralPath $recoverPath) {
    Add-Pass "Network recovery script present"
}
else {
    Add-Warning "Network recovery script missing from source tree."
}

if (-not [string]::IsNullOrWhiteSpace($ReleaseZip)) {
    Write-Section "PACKAGE CONTENT CHECKS"
    if (-not (Test-Path -LiteralPath $ReleaseZip)) {
        Add-Error "Release zip not found: $ReleaseZip"
    }
    else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ReleaseZip)
        try {
            $entries = $zip.Entries | ForEach-Object { $_.FullName }
            $forbiddenZipPatterns = @(
                "BlueVPNDev1.conf",
                "BlueVPNDev1.base.conf",
                "admin_token",
                "session.dat",
                "device_id.txt",
                "ProgramData"
            )

            foreach ($pattern in $forbiddenZipPatterns) {
                $matches = $entries | Where-Object { $_ -like "*$pattern*" }
                if ($matches) {
                    Add-Error "Release zip contains forbidden sensitive/config entry matching '$pattern': $($matches -join ', ')"
                }
                else {
                    Add-Pass "Release zip does not contain: $pattern"
                }
            }

            if ($entries | Where-Object {
                    $entry = $_.Replace('\', '/')
                    $entry -eq "app/greenvpn.exe" -or
                    $entry -eq "greenvpn.exe" -or
                    $entry.EndsWith("/app/greenvpn.exe", [System.StringComparison]::OrdinalIgnoreCase) -or
                    $entry.EndsWith("/greenvpn.exe", [System.StringComparison]::OrdinalIgnoreCase) -or
                    $entry -eq "app/bluevpn.exe" -or
                    $entry -eq "bluevpn.exe" -or
                    $entry.EndsWith("/app/bluevpn.exe", [System.StringComparison]::OrdinalIgnoreCase) -or
                    $entry.EndsWith("/bluevpn.exe", [System.StringComparison]::OrdinalIgnoreCase)
                }) {
                Add-Pass "Release zip contains Green VPN app executable"
            }
            else {
                Add-Error "Release zip does not contain Green VPN app executable in expected location."
            }
        }
        finally {
            $zip.Dispose()
        }
    }
}

Write-Section "SUMMARY"
Write-Host "Warnings: $($warnings.Count)"
Write-Host "Errors:   $($errors.Count)"

if ($errors.Count -gt 0) {
    throw "BlueVPN release gate failed with $($errors.Count) error(s)."
}

Write-Host "BlueVPN release gate passed." -ForegroundColor Green
