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
$runtimeConfigPath = Join-Path $ProjectRoot "lib\runtime_config.dart"
$backendPath = Join-Path $ProjectRoot "backend_live\app\main.py"
$installerPath = Join-Path $ProjectRoot "scripts\windows\build_installer.ps1"
$signScriptPath = Join-Path $ProjectRoot "scripts\windows\sign_release_artifacts.ps1"
$servicePath = Join-Path $ProjectRoot "windows\green_vpn_service\main.cpp"
$doctorPath = Join-Path $ProjectRoot "scripts\windows\doctor_bluevpn.ps1"
$recoverPath = Join-Path $ProjectRoot "scripts\windows\bluevpn_network_recover.ps1"
$networkProtectionPath = Join-Path $ProjectRoot "scripts\windows\check_windows_network_protection.ps1"
$networkTransitionSmokePath = Join-Path $ProjectRoot "scripts\windows\run_paid_beta_network_transition_smoke.ps1"
$vpnTaskPath = Join-Path $ProjectRoot "scripts\windows\greenvpn_vpn_task.ps1"
$wireguardTcpCanaryPath = Join-Path $ProjectRoot "scripts\server\install_wireguard_tcp_canary.sh"
$transportCanaryPath = Join-Path $ProjectRoot "scripts\server\install_transport_canary_service.sh"
$transportCanaryCheckPath = Join-Path $ProjectRoot "scripts\server\check_transport_canary_readiness.sh"
$transportCanaryRollbackPath = Join-Path $ProjectRoot "scripts\server\remove_transport_canary_service.sh"
$amneziaWg2CanaryBootstrapPath = Join-Path $ProjectRoot "scripts\server\bootstrap_amneziawg2_canary.sh"

$main = Read-Text $mainPath
$runtimeConfig = Read-Text $runtimeConfigPath
$backend = Read-Text $backendPath
$installer = Read-Text $installerPath
$signScript = Read-Text $signScriptPath
$serviceSource = Read-Text $servicePath
$doctorScript = Read-Text $doctorPath
$networkProtectionScript = Read-Text $networkProtectionPath
$networkTransitionSmokeScript = Read-Text $networkTransitionSmokePath
$vpnTaskScript = Read-Text $vpnTaskPath
$wireguardTcpCanaryScript = Read-Text $wireguardTcpCanaryPath
$transportCanaryScript = Read-Text $transportCanaryPath
$transportCanaryCheckScript = Read-Text $transportCanaryCheckPath
$transportCanaryRollbackScript = Read-Text $transportCanaryRollbackPath
$amneziaWg2CanaryBootstrapScript = Read-Text $amneziaWg2CanaryBootstrapPath

Write-Section "CLIENT SAFETY CHECKS"
$forbiddenClientPatterns = @(
    "Remove-NetRoute",
    "Remove-NetIPAddress",
    "Disable-NetAdapter",
    "taskkill /PID",
    "taskkill.exe",
    "schtasks"
)

foreach ($pattern in $forbiddenClientPatterns) {
    if ($main -match [regex]::Escape($pattern)) {
        Add-Error "Forbidden network/driver cleanup pattern in lib/main.dart: $pattern"
    }
    else {
        Add-Pass "No forbidden pattern in lib/main.dart: $pattern"
    }
}

if (
    $main -match "const String kTunnelName = greenVpnTunnelName;" -and
    $runtimeConfig -match "defaultValue: 'BlueVPNDev1'"
) {
    Add-Pass "Stable tunnel name defaults to BlueVPNDev1 through runtime config"
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

$localServiceClientFragments = @(
    'greenVpnServiceTokenPathSync',
    'X-GreenVPN-Local-Token',
    '_requiresLocalToken',
    '_readLocalToken',
    'service_token'
)
$localServiceClientSource = $main + "`n" + $runtimeConfig

foreach ($fragment in $localServiceClientFragments) {
    if ($localServiceClientSource.Contains($fragment)) {
        Add-Pass "Client local service token support present: $fragment"
    }
    else {
        Add-Error "Client local service token support missing: $fragment"
    }
}

$publicProductClientFragments = @(
    'GREENVPN_PUBLIC_PRODUCT_BUILD',
    '_buildFixedPublicProduct(',
    'green_90d',
    'green_180d'
)
foreach ($fragment in $publicProductClientFragments) {
    if ($main.Contains($fragment)) {
        Add-Pass "Public product client flow present: $fragment"
    }
    else {
        Add-Error "Public product client flow missing: $fragment"
    }
}

$sessionPersistenceFragments = @(
    'session storage migration skipped type=',
    'session read failed type=',
    'A best-effort storage migration must not invalidate a session',
    'preparePrivateFileForWrite',
    'Add-Type -AssemblyName System.Security',
    'DataProtectionScope]::LocalMachine',
    "'-h'",
    "'-s'",
    "'-r'"
)
foreach ($fragment in $sessionPersistenceFragments) {
    if ($main.Contains($fragment)) {
        Add-Pass "Session persistence guard present: $fragment"
    }
    else {
        Add-Error "Session persistence guard missing: $fragment"
    }
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
    '@app.get("/api/v1/catalog/resilience")',
    '@app.get("/api/v1/monitoring/status")',
    '@app.get("/api/v1/monitoring/services")',
    '@app.get("/payment/return"',
    '@app.post("/api/v1/billing/orders")',
    '@app.get("/api/v1/billing/orders")',
    '@app.get("/api/v1/billing/orders/{order_id}")',
    '@app.post("/api/v1/subscription/auto-renew/cancel")',
    '@app.get("/api/v1/admin/launch/advertising-readiness")',
    '@app.get("/api/v1/admin/billing/readiness")',
    '@app.get("/api/v1/admin/billing/reconciliation")',
    '@app.get("/api/v1/admin/billing/promos/readiness")',
    '@app.post("/api/v1/admin/billing/promos/draft-start-campaign")',
    '@app.get("/api/v1/admin/billing/renewals/readiness")',
    '@app.post("/api/v1/admin/billing/renewals/run")',
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
    '@app.get("/api/v1/admin/resilience/routes")',
    '@app.get("/api/v1/admin/resilience/route-observations")',
    '@app.post("/api/v1/admin/resilience/route-observations")',
    '@app.post("/api/v1/client/route-events")',
    '@app.get("/api/v1/admin/resilience/client-route-events")',
    '@app.get("/api/v1/admin/resilience/target-matrix")',
    '@app.get("/api/v1/admin/resilience/transport-rollout")',
    '@app.get("/api/v1/admin/updates/readiness")',
    '@app.get("/api/v1/admin/windows/trust-readiness")',
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
    'def windows_distribution_trust_readiness(',
    'GREENVPN_WINDOWS_CODE_SIGNING_PROVIDER',
    'public_download_trusted',
    'def build_advertising_readiness(',
    'PUBLIC_ADVERTISING_REQUIRED_CODES',
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
    'note_required and not note',
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
    '--route-health',
    '--route-candidate',
    '/etc/greenvpn-monitoring/admin_token',
    'def server_health_external_probe_readiness(',
    'external_endpoint_probe_readiness',
    'externalProbeReadiness',
    'def sync_server_health_observation_incident(',
    'server-health:',
    'server_health_observation',
    'def billing_reconciliation_payload(',
    'GREENVPN_PAID_BETA_BILLING_PRIMARY',
    'paid_beta_billing_primary_required',
    'GREENVPN_PUBLIC_PRODUCT_ENABLED',
    'GREENVPN_PUBLIC_PRODUCT_BILLING_PRIMARY',
    'PUBLIC_PRODUCT_PRICE_RUB = 249',
    '"green_90d"',
    '"green_180d"',
    '"pricingModel": "fixed_term_plans"',
    'GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED',
    'def execute_due_auto_renewals(',
    'order_kind',
    'renewal_key',
    'def billing_order_requires_attention(',
    'paid_not_activated',
    'status"] or "").strip().lower() in {"failed", "canceled", "cancelled"}',
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
    'safePlanCodes',
    'SERVER_PROTOCOL_ROLLOUT_ORDER',
    'SERVER_CLIENT_READY_PROTOCOLS',
    'SERVER_DEFAULT_CLIENT_PROTOCOLS',
    'SERVER_TRANSPORT_ROLLOUT_STAGES',
    'def normalize_client_supported_protocols(',
    'def server_visible_to_client(',
    'negotiatedClientProtocols',
    'no_available_vpn_nodes',
    'resilience_route_observations',
    'AdminResilienceRouteObservationIn',
    'client_route_events',
    'ClientRouteEventIn',
    'def create_client_route_event(',
    'def client_route_event_summary(',
    'clientFeedbackSignal',
    'client_feedback',
    'targetSpecificRouteAwareness',
    'def build_resilience_target_route_matrix(',
    'targetRouteMatrix',
    'def sync_resilience_route_observation_incident(',
    'resilience_route_observation',
    'RESILIENCE_TRANSPORT_ROLLOUT_PROFILES',
    'def build_resilience_transport_rollout_readiness(',
    'guarded_transport_rollout',
    'safeToExposePlannedTransports',
    'install_transport_canary_service.sh',
    'canaryScript',
    'validationScript',
    'doNotPublishWithoutClientEngine',
    'doNotPublishWithoutServerDaemon',
    'doNotPublishWithoutRouteProbe',
    'def build_resilience_policy(',
    'def build_resilience_route_decision(',
    'best_healthy_config_ready',
    'server_side_adaptive_routing',
    'lightest_healthy_client_ready_layer',
    'heavierLayersUsedOnlyWhenLighterLayerFails',
    'clientConfigReady',
    'managedCatalog'
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
    $subscriptionApplyDisabled = (
        $backend.Contains("Direct tariff activation is disabled") -or
        $backend.Contains("status_code=402")
    )
    $subscriptionApplyUsesBillingGuard = (
        $backend.Contains("status_code=402") -and
        $backend.Contains("billing order")
    )
    if ($subscriptionApplyDisabled -and $subscriptionApplyUsesBillingGuard) {
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
    'Future<String> _buildSupportReportCode() async',
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

Write-Section "WINDOWS AUTO ROUTE CHECKS"
$requiredAutoRouteClientFragments = @(
    '_adaptiveRouteServerId',
    '_adaptiveRouteProtocol',
    '_adaptiveRouteScore',
    "res.data!['resilience']",
    "resilienceMap['routeDecision']",
    'selectedRouteMap',
    's.isAuto || s.isCurrentClientReady',
    "const List<String> kSupportedVpnProtocols = <String>['wireguard_udp']",
    "'X-GreenVPN-Supported-Protocols'",
    "'supportedProtocols': kSupportedVpnProtocols"
)

foreach ($fragment in $requiredAutoRouteClientFragments) {
    if ($main.Contains($fragment)) {
        Add-Pass "Windows adaptive route client marker present: $fragment"
    }
    else {
        Add-Error "Windows adaptive route client marker missing: $fragment"
    }
}

Write-Section "SERVER TRANSPORT CANARY CHECKS"
$requiredCanaryFragments = @(
    'Green VPN WireGuard TCP canary installer',
    '--apply',
    '--allow-current-vpn-host',
    '--expected-public-ip',
    'Refusing to install canary wrapper on protected Green VPN host',
    'Use a separate test-only canary node',
    'Dry-run only',
    'does not edit WireGuard peers',
    'udp2raw',
    'greenvpn-wg-tcp-canary',
    'NoNewPrivileges=true',
    'safeToExposePlannedTransports'
)

foreach ($fragment in $requiredCanaryFragments) {
    if ($wireguardTcpCanaryScript.Contains($fragment) -or $backend.Contains($fragment)) {
        Add-Pass "WireGuard TCP canary safety marker present: $fragment"
    }
    else {
        Add-Error "WireGuard TCP canary safety marker missing: $fragment"
    }
}

$requiredTransportCanaryFragments = @(
    'Green VPN guarded transport canary service installer',
    'amneziawg|openvpn_tcp|shadowsocks|hysteria2|trojan_tls|vless_reality|masque_udp',
    '--apply',
    '--allow-current-vpn-host',
    '--expected-public-ip',
    'Refusing to install canary service on protected Green VPN host',
    'Owner-approved narrow NL2 AmneziaWG canary exception accepted',
    'SERVICE_TYPE="oneshot"',
    'REMAIN_AFTER_EXIT="yes"',
    'trusted/pinned',
    'requires a root-owned config file',
    'Config file must be root-only',
    'Config file must not be a symbolic link',
    'does not edit WireGuard peers',
    'catalog_publication=not_changed',
    'NoNewPrivileges=true',
    'PrivateTmp=true'
)

foreach ($fragment in $requiredTransportCanaryFragments) {
    if ($transportCanaryScript.Contains($fragment) -or $backend.Contains($fragment)) {
        Add-Pass "Generic transport canary safety marker present: $fragment"
    }
    else {
        Add-Error "Generic transport canary safety marker missing: $fragment"
    }
}

$requiredTransportCanaryCheckFragments = @(
    'Green VPN guarded transport canary readiness checker',
    'wireguard_tcp|amneziawg|openvpn_tcp|shadowsocks|hysteria2|trojan_tls|vless_reality|masque_udp',
    'does not read or print transport secrets',
    'does not edit WireGuard peers',
    'protected_production_host_refused',
    '--approved-existing-host',
    'binary_missing_or_not_executable',
    'config_not_root_owned',
    'config_not_root_only',
    'config_symlink_refused',
    'amneziawg2_required_fields_missing',
    'amneziawg2_headers_invalid',
    'service_not_active',
    'route_candidate=',
    '--json'
)

foreach ($fragment in $requiredTransportCanaryCheckFragments) {
    if ($transportCanaryCheckScript.Contains($fragment) -or $backend.Contains($fragment)) {
        Add-Pass "Transport canary readiness marker present: $fragment"
    }
    else {
        Add-Error "Transport canary readiness marker missing: $fragment"
    }
}

$requiredTransportCanaryRollbackFragments = @(
    'Green VPN guarded transport canary rollback',
    '--expected-public-ip',
    'Refusing canary rollback mutation on protected Green VPN host',
    'Owner-approved narrow NL2 AmneziaWG rollback exception accepted',
    'Refusing non-canary service name',
    'config_keys_binaries=preserved',
    'public_catalog=not_changed',
    'Dry-run only'
)

foreach ($fragment in $requiredTransportCanaryRollbackFragments) {
    if ($transportCanaryRollbackScript.Contains($fragment)) {
        Add-Pass "Transport canary rollback safety marker present: $fragment"
    }
    else {
        Add-Error "Transport canary rollback safety marker missing: $fragment"
    }
}

$requiredAmneziaWg2BootstrapFragments = @(
    'Green VPN pinned AmneziaWG 2 canary bootstrap',
    'CANARY_HOST="5.129.216.42"',
    'CANARY_INTERFACE="awgcanary0"',
    'CANARY_PORT="1443"',
    'AWG_GO_COMMIT="c1e9bb3758e71bb1adc402598465565bfc9663fd"',
    'AWG_TOOLS_TAG="v1.0.20260618-2"',
    'sha256sum -c',
    'existing_wg0=active_untouched',
    'public_catalog=not_changed',
    'The interface was not started'
)

foreach ($fragment in $requiredAmneziaWg2BootstrapFragments) {
    if ($amneziaWg2CanaryBootstrapScript.Contains($fragment)) {
        Add-Pass "AmneziaWG 2 bootstrap safety marker present: $fragment"
    }
    else {
        Add-Error "AmneziaWG 2 bootstrap safety marker missing: $fragment"
    }
}

Write-Section "INSTALLER CHECKS"
if ($installer.Contains("/uninstalltunnelservice BlueVPNDev1")) {
    Add-Pass "Installer/uninstaller stops only BlueVPNDev1 via WireGuard"
}
else {
    Add-Error "Installer/uninstaller does not explicitly uninstall BlueVPNDev1 tunnel."
}

$installerTrustForbiddenPatterns = @(
    "install.vbs",
    "wscript.exe",
    "New-ScheduledTaskAction"
)

foreach ($pattern in $installerTrustForbiddenPatterns) {
    if ($installer -match [regex]::Escape($pattern)) {
        Add-Error "Installer still contains suspicious packaging/runtime pattern: $pattern"
    }
    else {
        Add-Pass "Installer does not contain suspicious pattern: $pattern"
    }
}

if ($installer -match "(?<!Un)Register-ScheduledTask") {
    Add-Error "Installer still creates scheduled tasks at install time."
}
else {
    Add-Pass "Installer does not create scheduled tasks at install time"
}

if ($installer -match "-ExecutionPolicy\s+['""]?Bypass") {
    Add-Error "Installer still launches PowerShell with ExecutionPolicy Bypass."
}
else {
    Add-Pass "Installer does not launch PowerShell with ExecutionPolicy Bypass"
}

if ($installer.Contains("AppLaunched=powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File install_ui.ps1")) {
    Add-Pass "Installer bootstrap starts the branded installer UI without a visible PowerShell console"
}
else {
    Add-Warning "Installer bootstrap entry point was not recognized."
}

if ($installer -match "-Verb\s+RunAs\s+-WindowStyle\s+Normal|WindowStyle\s*=\s*['""]Normal['""]") {
    Add-Error "Installer still contains a visible elevated PowerShell launch."
}
else {
    Add-Pass "Installer elevation paths do not request a visible PowerShell window"
}

$installerTokenFragments = @(
    'function Ensure-GreenVpnServiceToken',
    'service_token',
    'RandomNumberGenerator',
    '*S-1-5-11:R',
    'Ensure-GreenVpnServiceToken'
)

foreach ($fragment in $installerTokenFragments) {
    if ($installer.Contains($fragment)) {
        Add-Pass "Installer local service token setup present: $fragment"
    }
    else {
        Add-Error "Installer missing local service token setup marker: $fragment"
    }
}

if ($installer.Contains("check_windows_network_protection.ps1") -and $installer.Contains("`$networkProtection")) {
    Add-Pass "Installer packages Windows network protection checker"
}
else {
    Add-Error "Installer does not package check_windows_network_protection.ps1."
}

Write-Section "WINDOWS LOCAL SERVICE CHECKS"
$serviceFragments = @(
    'kLocalTokenPath',
    'kLocalTokenHeader',
    'ReadLocalServiceToken',
    'AuthorizeLocalRequest',
    'RequireLocalToken',
    'connect requires POST',
    'disconnect requires POST',
    'local service token missing',
    'unauthorized local request'
)

foreach ($fragment in $serviceFragments) {
    if ($serviceSource.Contains($fragment)) {
        Add-Pass "Local service hardening present: $fragment"
    }
    else {
        Add-Error "Local service hardening missing required marker: $fragment"
    }
}

if ($serviceSource -match 'get\s+/connect' -or $serviceSource -match 'get\s+/disconnect') {
    Add-Error "Local service still appears to accept GET for mutating VPN actions."
}
else {
    Add-Pass "Local service mutating VPN actions do not use GET handlers"
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

Write-Section "DOCTOR PRIVACY CHECKS"
$doctorPrivacyFragments = @(
    'function Redact-SensitiveText',
    'PrivateKey = <hidden>',
    'service_token',
    'check_windows_network_protection.ps1',
    'NETWORK PROTECTION',
    'GreenVPNService'
)

foreach ($fragment in $doctorPrivacyFragments) {
    if ($doctorScript.Contains($fragment)) {
        Add-Pass "Doctor privacy/support marker present: $fragment"
    }
    else {
        Add-Error "Doctor missing privacy/support marker: $fragment"
    }
}

if ($doctorScript -match 'Get-Content\s+\$sessionPath\s+-Raw(?!\))' -or $doctorScript -match 'Get-Content\s+\$prefsPath\s+-Raw(?!\))') {
    Add-Error "Doctor still appears to print prefs/session without redaction."
}
else {
    Add-Pass "Doctor redacts prefs/session output before display/report"
}

Write-Section "WINDOWS NETWORK PROTECTION CHECKS"
$networkProtectionFragments = @(
    'check_windows_network_protection',
    'full_tunnel_ipv4',
    '0.0.0.0/1',
    '128.0.0.0/1',
    'ownsSplitDefault',
    'full_tunnel_ipv6',
    'config_dns_present',
    'active_tunnel_dns',
    'non_vpn_dns_visible',
    'Find-NetRoute',
    'allThroughTunnel',
    'ignoredPlaceholders',
    'nativeKillSwitchConfigured',
    'nativeKillSwitch',
    'competing_vpn',
    'PrivateKey = <hidden>',
    'productionReady'
)

foreach ($fragment in $networkProtectionFragments) {
    if ($networkProtectionScript.Contains($fragment)) {
        Add-Pass "Network protection checker supports: $fragment"
    }
    else {
        Add-Error "Network protection checker missing marker: $fragment"
    }
}

if (Test-Path -LiteralPath $networkProtectionPath) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($networkProtectionPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Add-Error "Network protection checker has PowerShell parser errors: $($parseErrors[0].ToString())"
    }
    else {
        Add-Pass "Network protection checker PowerShell parser check passed"
    }
}

$vpnTaskKillSwitchFragments = @(
    'Ensure-NativeFullTunnelKillSwitch',
    "'0.0.0.0/0'",
    "'::/0'",
    "'0.0.0.0/1'",
    "'128.0.0.0/1'",
    'normalized Windows full-tunnel routes for native kill switch',
    'Ensure-GreenProgramDataAcl'
)

foreach ($fragment in $vpnTaskKillSwitchFragments) {
    if ($vpnTaskScript.Contains($fragment)) {
        Add-Pass "Windows VPN task supports: $fragment"
    }
    else {
        Add-Error "Windows VPN task missing kill-switch marker: $fragment"
    }
}

if (Test-Path -LiteralPath $vpnTaskPath) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($vpnTaskPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Add-Error "Windows VPN task has PowerShell parser errors: $($parseErrors[0].ToString())"
    }
    else {
        Add-Pass 'Windows VPN task PowerShell parser check passed'
    }
}

$networkTransitionSmokeFragments = @(
    'GreenVPNBetaNetworkSmokeFailsafe',
    'AmneziaWGTunnel$device20_full',
    "'/connect'",
    "'/disconnect'",
    'handshakeFresh',
    'trafficPresent',
    'Invoke-DirectDnsLeakProbe',
    'leakDetected',
    'restoring $AmneziaServiceName',
    'finally'
)

foreach ($fragment in $networkTransitionSmokeFragments) {
    if ($networkTransitionSmokeScript.Contains($fragment)) {
        Add-Pass "Network transition smoke supports: $fragment"
    }
    else {
        Add-Error "Network transition smoke missing safety marker: $fragment"
    }
}

if (Test-Path -LiteralPath $networkTransitionSmokePath) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($networkTransitionSmokePath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Add-Error "Network transition smoke has PowerShell parser errors: $($parseErrors[0].ToString())"
    }
    else {
        Add-Pass "Network transition smoke PowerShell parser check passed"
    }
}

Write-Section "SIGNING TOOLING CHECKS"
$signingToolFragments = @(
    'CertificateThumbprint',
    'TimestampUrl',
    'ExpectedPublisher',
    'RequiredLeafName',
    'ReportPath',
    'VerifyOnly',
    'AllowUnsignedInVerifyOnly',
    'SkipSignToolVerify',
    'Get-AuthenticodeSignature',
    'signtoolVerifySkipped',
    'certificateThumbprint',
    'sha256'
)

foreach ($fragment in $signingToolFragments) {
    if ($signScript.Contains($fragment)) {
        Add-Pass "Signing script supports: $fragment"
    }
    else {
        Add-Error "Signing script missing required capability marker: $fragment"
    }
}

if (Test-Path -LiteralPath $signScriptPath) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($signScriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Add-Error "Signing script has PowerShell parser errors: $($parseErrors[0].ToString())"
    }
    else {
        Add-Pass "Signing script PowerShell parser check passed"
    }
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
