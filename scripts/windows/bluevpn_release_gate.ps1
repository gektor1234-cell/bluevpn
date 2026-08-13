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

Write-Section "GREEN VPN RELEASE GATE"
Write-Host "ProjectRoot: $ProjectRoot"
if (-not [string]::IsNullOrWhiteSpace($ReleaseZip)) {
    Write-Host "ReleaseZip:  $ReleaseZip"
}

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    throw "ProjectRoot does not exist: $ProjectRoot"
}

$mainPath = Join-Path $ProjectRoot "lib\main.dart"
$releaseContractPath = Join-Path $ProjectRoot "release_contract.json"
$pubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$versionFilePath = Join-Path $ProjectRoot "VERSION.txt"
$finalCandidateBuildPath = Join-Path $ProjectRoot "scripts\windows\build_final_release_candidate.ps1"
$publicProductBuildPath = Join-Path $ProjectRoot "scripts\windows\build_public_product.ps1"
$paidBetaBuildPath = Join-Path $ProjectRoot "scripts\windows\build_paid_beta.ps1"
$windowsSelectiveRoutingPath = Join-Path $ProjectRoot "lib\services\windows_selective_routing_service.dart"
$windowsVpnStatusPolicyPath = Join-Path $ProjectRoot "lib\services\windows_vpn_status_policy.dart"
$fusionConnectionStatusPolicyPath = Join-Path $ProjectRoot "lib\services\fusion_connection_status_policy.dart"
$runtimeConfigPath = Join-Path $ProjectRoot "lib\runtime_config.dart"
$backendPath = Join-Path $ProjectRoot "backend_live\app\main.py"
$installerPath = Join-Path $ProjectRoot "scripts\windows\build_installer.ps1"
$paidBetaWindowsInstallerPath = Join-Path $ProjectRoot "scripts\windows\install_paid_beta_side_by_side.ps1"
$paidBetaWindowsUninstallerPath = Join-Path $ProjectRoot "scripts\windows\uninstall_paid_beta_side_by_side.ps1"
$signScriptPath = Join-Path $ProjectRoot "scripts\windows\sign_release_artifacts.ps1"
$trustedWindowsFinalizerPath = Join-Path $ProjectRoot "scripts\windows\finalize_windows_trusted_release.ps1"
$windowsPublicReleaseInstallerPath = Join-Path $ProjectRoot "scripts\server\install_windows_public_product_release.sh"
$windowsStableReleaseInstallerPath = Join-Path $ProjectRoot "scripts\server\install_windows_stable_release.sh"
$servicePath = Join-Path $ProjectRoot "windows\green_vpn_service\main.cpp"
$runnerPath = Join-Path $ProjectRoot "windows\runner\flutter_window.cpp"
$runnerMainPath = Join-Path $ProjectRoot "windows\runner\main.cpp"
$doctorPath = Join-Path $ProjectRoot "scripts\windows\doctor_bluevpn.ps1"
$recoverPath = Join-Path $ProjectRoot "scripts\windows\bluevpn_network_recover.ps1"
$networkProtectionPath = Join-Path $ProjectRoot "scripts\windows\check_windows_network_protection.ps1"
$networkTransitionSmokePath = Join-Path $ProjectRoot "scripts\windows\run_paid_beta_network_transition_smoke.ps1"
$vpnTaskPath = Join-Path $ProjectRoot "scripts\windows\greenvpn_vpn_task.ps1"
$transportPreviewVpnTaskPath = Join-Path $ProjectRoot "scripts\windows\greenvpn_transport_preview_vpn_task.ps1"
$windowsStandbyProbePath = Join-Path $ProjectRoot "scripts\windows\greenvpn_standby_probe.ps1"
$windowsStandbyResultContractTestPath = Join-Path $ProjectRoot "scripts\windows\test_windows_standby_probe_result_contract.ps1"
$transportSelectiveRoutingPath = Join-Path $ProjectRoot "scripts\windows\greenvpn_selective_routing.ps1"
$transportSelectiveRoutingTestPath = Join-Path $ProjectRoot "scripts\windows\test_windows_selective_routing_policy.ps1"
$windowsRuntimeFailoverPhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_windows_public_runtime_failover_physical.ps1"
$windowsConnectLatencyPhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_windows_connect_latency_physical.ps1"
$windowsFastCacheReleaseSmokePath = Join-Path $ProjectRoot "scripts\windows\run_windows_fast_cache_release_smoke.ps1"
$windowsStandbyTrayReleaseSmokePath = Join-Path $ProjectRoot "scripts\windows\run_windows_standby_tray_release_smoke.ps1"
$windowsStandbyTrayReleaseLauncherPath = Join-Path $ProjectRoot "scripts\windows\launch_windows_standby_tray_release_smoke.ps1"
$windowsSmokeNetworkRestorePath = Join-Path $ProjectRoot "scripts\windows\restore_windows_smoke_network.ps1"
$windowsFusionPaidBetaAcceptanceSmokePath = Join-Path $ProjectRoot "scripts\windows\run_windows_fusion_paid_beta_acceptance_smoke.ps1"
$windowsFusionPaidBetaAcceptanceLauncherPath = Join-Path $ProjectRoot "scripts\windows\launch_windows_fusion_paid_beta_acceptance_smoke.ps1"
$windowsModeReconcileReleaseSmokePath = Join-Path $ProjectRoot "scripts\windows\run_windows_mode_reconcile_release_smoke.ps1"
$windowsModeReconcileReleaseLauncherPath = Join-Path $ProjectRoot "scripts\windows\launch_windows_mode_reconcile_release_smoke.ps1"
$fusionProductionPromotionPath = Join-Path $ProjectRoot "scripts\windows\prepare_fusion_production_promotion.ps1"
$publicProductBackendBundlePath = Join-Path $ProjectRoot "scripts\windows\prepare_public_product_backend_bundle.ps1"
$transportCascadeStagePath = Join-Path $ProjectRoot "scripts\windows\stage_windows_transport_cascade.ps1"
$publicInstallerAuditPath = Join-Path $ProjectRoot "scripts\windows\test_public_installer_package.ps1"
$transportPreviewInstallPath = Join-Path $ProjectRoot "scripts\windows\install_windows_transport_preview.ps1"
$transportPreviewUninstallPath = Join-Path $ProjectRoot "scripts\windows\uninstall_windows_transport_preview.ps1"
$transportPreviewBuildPath = Join-Path $ProjectRoot "scripts\windows\build_windows_awg2_preview.ps1"
$hysteriaWatchdogPath = Join-Path $ProjectRoot "scripts\windows\greenvpn_hysteria2_watchdog.ps1"
$hysteriaPhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_windows_hysteria2_preview_physical.ps1"
$vlessWatchdogPath = Join-Path $ProjectRoot "scripts\windows\greenvpn_vless_reality_watchdog.ps1"
$vlessPhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_windows_vless_reality_preview_physical.ps1"
$naiveWatchdogPath = Join-Path $ProjectRoot "scripts\windows\greenvpn_naive_https_watchdog.ps1"
$naiveClientSmokePath = Join-Path $ProjectRoot "scripts\windows\test_windows_naive_https_client_smoke.ps1"
$managedSocksTunPhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_windows_socks_tun_preview_physical.ps1"
$naivePhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_windows_naive_https_preview_physical.ps1"
$dnsttWatchdogPath = Join-Path $ProjectRoot "scripts\windows\greenvpn_dnstt_watchdog.ps1"
$dnsttPhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_windows_dnstt_preview_physical.ps1"
$transportCascadePhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_windows_transport_preview_cascade_physical.ps1"
$androidSettingsPath = Join-Path $ProjectRoot "android\settings.gradle.kts"
$androidAppBuildPath = Join-Path $ProjectRoot "android\app\build.gradle.kts"
$androidAppManifestPath = Join-Path $ProjectRoot "android\app\src\main\AndroidManifest.xml"
$androidLintConfigPath = Join-Path $ProjectRoot "android\lint.xml"
$androidAppDebugManifestPath = Join-Path $ProjectRoot "android\app\src\debug\AndroidManifest.xml"
$androidTransportContractServicePath = Join-Path $ProjectRoot "android\app\src\debug\kotlin\pro\greenvpn\app\TransportContractDebugService.kt"
$androidTransportContractProbePath = Join-Path $ProjectRoot "scripts\windows\test_android_transport_contract_probe.ps1"
$androidQuickTilePhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_android_quick_tile_cascade_physical.ps1"
$androidMainActivityPath = Join-Path $ProjectRoot "android\app\src\main\kotlin\pro\greenvpn\app\MainActivity.kt"
$androidQuickTilePath = Join-Path $ProjectRoot "android\app\src\main\kotlin\pro\greenvpn\app\GreenVpnQuickTileService.kt"
$androidRouteProbePath = Join-Path $ProjectRoot "android\app\src\main\kotlin\pro\greenvpn\app\GreenVpnRouteProbe.kt"
$androidRouteProbeTestPath = Join-Path $ProjectRoot "android\app\src\test\kotlin\pro\greenvpn\app\GreenVpnRouteProbeTest.kt"
$androidQuickTilePolicyPath = Join-Path $ProjectRoot "android\app\src\main\kotlin\pro\greenvpn\app\GreenVpnQuickTileCascadePolicy.kt"
$androidQuickTilePolicyTestPath = Join-Path $ProjectRoot "android\app\src\test\kotlin\pro\greenvpn\app\GreenVpnQuickTileCascadePolicyTest.kt"
$androidHysteriaBuildPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\build.gradle.kts"
$androidHysteriaManifestPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\AndroidManifest.xml"
$androidHysteriaDebugManifestPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\debug\AndroidManifest.xml"
$androidHysteriaConfigPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\hysteria\Hysteria2Config.kt"
$androidHysteriaControllerPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\hysteria\Hysteria2Controller.kt"
$androidHysteriaServicePath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\hysteria\Hysteria2VpnService.kt"
$androidHysteriaBridgePath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\jni\greenvpn_hysteria_bridge.c"
$androidHysteriaConfigTestPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\test\kotlin\pro\greenvpn\hysteria\Hysteria2ConfigTest.kt"
$androidBuildScriptPath = Join-Path $ProjectRoot "scripts\windows\build_android_apk.ps1"
$androidReleaseSignerPath = Join-Path $ProjectRoot "android\release_signer_sha256.txt"
$androidHysteriaPreparePath = Join-Path $ProjectRoot "scripts\windows\prepare_android_hysteria2_preview.ps1"
$androidHysteriaNativeBuildPath = Join-Path $ProjectRoot "scripts\windows\build_android_hysteria2_native.ps1"
$androidHysteriaNativeManifestPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\HYSTERIA-NATIVE-MANIFEST.json"
$androidHysteriaPhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_android_hysteria2_preview_physical.ps1"
$androidHysteriaApkVerifyPath = Join-Path $ProjectRoot "scripts\windows\verify_android_hysteria2_preview_apk.ps1"
$androidStableIsolationVerifyPath = Join-Path $ProjectRoot "scripts\windows\verify_android_stable_transport_isolation.ps1"
$androidTransportProbeReceiverPath = Join-Path $ProjectRoot "android\transport_probe\src\main\kotlin\pro\greenvpn\transportprobe\TransportProbeReceiver.kt"
$androidVlessConfigPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\vless\VlessRealityConfig.kt"
$androidVlessControllerPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\vless\VlessRealityController.kt"
$androidVlessServicePath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\vless\VlessRealityVpnService.kt"
$androidVlessConfigTestPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\test\kotlin\pro\greenvpn\vless\VlessRealityConfigTest.kt"
$androidVlessPreparePath = Join-Path $ProjectRoot "scripts\windows\prepare_android_vless_reality_preview.ps1"
$androidVlessPhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_android_vless_reality_preview_physical.ps1"
$androidNaiveConfigPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\naive\NaiveHttpsConfig.kt"
$androidNaiveControllerPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\naive\NaiveHttpsController.kt"
$androidNaiveServicePath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\naive\NaiveHttpsVpnService.kt"
$androidNaiveConfigTestPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\test\kotlin\pro\greenvpn\naive\NaiveHttpsConfigTest.kt"
$androidNaivePreparePath = Join-Path $ProjectRoot "scripts\windows\prepare_android_naive_https_preview.ps1"
$androidNaivePhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_android_naive_https_preview_physical.ps1"
$androidDnsttConfigPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\dnstt\DnsttConfig.kt"
$androidDnsttControllerPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\dnstt\DnsttController.kt"
$androidDnsttServicePath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\main\kotlin\pro\greenvpn\dnstt\DnsttVpnService.kt"
$androidDnsttConfigTestPath = Join-Path $ProjectRoot "android\transport_preview\hysteria_tunnel\src\test\kotlin\pro\greenvpn\dnstt\DnsttConfigTest.kt"
$androidDnsttPreparePath = Join-Path $ProjectRoot "scripts\windows\prepare_android_dnstt_preview.ps1"
$androidDnsttPhysicalTestPath = Join-Path $ProjectRoot "scripts\windows\test_android_dnstt_preview_physical.ps1"
$androidDnsttApkVerifyPath = Join-Path $ProjectRoot "scripts\windows\verify_android_dnstt_preview_apk.ps1"
$routeFailureCooldownPath = Join-Path $ProjectRoot "lib\services\route_failure_cooldown.dart"
$routeFailureCooldownTestPath = Join-Path $ProjectRoot "test\route_failure_cooldown_test.dart"
$transportPreviewPolicyPath = Join-Path $ProjectRoot "lib\services\transport_preview_policy.dart"
$transportPreviewPolicyTestPath = Join-Path $ProjectRoot "test\transport_preview_policy_test.dart"
$monitoringProbePath = Join-Path $ProjectRoot "scripts\monitoring\service_probe.py"
$wireguardTcpCanaryPath = Join-Path $ProjectRoot "scripts\server\install_wireguard_tcp_canary.sh"
$transportCanaryPath = Join-Path $ProjectRoot "scripts\server\install_transport_canary_service.sh"
$transportCanaryCheckPath = Join-Path $ProjectRoot "scripts\server\check_transport_canary_readiness.sh"
$transportCanaryRollbackPath = Join-Path $ProjectRoot "scripts\server\remove_transport_canary_service.sh"
$amneziaWg2CanaryBootstrapPath = Join-Path $ProjectRoot "scripts\server\bootstrap_amneziawg2_canary.sh"
$amneziaWg2CanaryPeerAddressPath = Join-Path $ProjectRoot "scripts\server\set_amneziawg2_canary_peer_address.sh"
$hysteria2CanaryBootstrapPath = Join-Path $ProjectRoot "scripts\server\bootstrap_hysteria2_canary.sh"
$hysteria2ContractDeployPath = Join-Path $ProjectRoot "scripts\server\deploy_paid_beta_hysteria2_contract.sh"
$naiveHttpsBootstrapPath = Join-Path $ProjectRoot "scripts\server\bootstrap_naive_https_canary.sh"
$naiveHttpsReadinessPath = Join-Path $ProjectRoot "scripts\server\check_naive_https_canary_readiness.sh"
$naiveHttpsRollbackPath = Join-Path $ProjectRoot "scripts\server\remove_naive_https_canary.sh"
$naiveCertificateSyncPath = Join-Path $ProjectRoot "scripts\server\greenvpn_sync_naive_certificate.sh"
$naiveCertificateSyncInstallerPath = Join-Path $ProjectRoot "scripts\server\install_naive_certificate_sync.sh"
$dnsttBootstrapPath = Join-Path $ProjectRoot "scripts\server\bootstrap_dnstt_canary.sh"
$dnsttDnsFrontendBootstrapPath = Join-Path $ProjectRoot "scripts\server\bootstrap_dnstt_dns_frontend.sh"
$dnsttDnsFrontendRollbackPath = Join-Path $ProjectRoot "scripts\server\remove_dnstt_dns_frontend.sh"
$dnsttReadinessPath = Join-Path $ProjectRoot "scripts\server\check_dnstt_canary_readiness.sh"
$dnsttRollbackPath = Join-Path $ProjectRoot "scripts\server\remove_dnstt_canary.sh"
$naiveDnsttContractDeployPath = Join-Path $ProjectRoot "scripts\server\deploy_paid_beta_naive_dnstt_contract.sh"
$serverSecurityRunbookPath = Join-Path $ProjectRoot "docs\SERVER_SECURITY_CONTOUR_INTEGRATION_RUNBOOK_RU.md"
$projectMapPath = Join-Path $ProjectRoot "docs\PROJECT_MAP_RU.md"
$projectOperationsRunbookPath = Join-Path $ProjectRoot "docs\PROJECT_OPERATIONS_MASTER_RUNBOOK_RU.md"
$fullServerSnapshotPath = Join-Path $ProjectRoot "scripts\server\create_full_restore_snapshot.sh"
$fullProjectCheckpointPath = Join-Path $ProjectRoot "scripts\windows\create_full_project_checkpoint.ps1"
$localRestoreSnapshotPath = Join-Path $ProjectRoot "scripts\windows\create_local_restore_snapshot.ps1"
$repositorySecretScannerPath = Join-Path $ProjectRoot "scripts\security\scan_tracked_secrets.py"
$sqliteStateSyncPath = Join-Path $ProjectRoot "scripts\ops\greenvpn_sqlite_state_sync.py"
$sqliteSnapshotPath = Join-Path $ProjectRoot "scripts\ops\greenvpn_sqlite_snapshot_stdout.py"
$dbSyncShellPath = Join-Path $ProjectRoot "scripts\ops\greenvpn_db_sync_from_peer.sh"
$paidBetaTransportCatalogSyncPath = Join-Path $ProjectRoot "scripts\ops\sync_paid_beta_transport_catalog.py"
$paidBetaTransportParityPath = Join-Path $ProjectRoot "scripts\server\configure_paid_beta_transport_parity.sh"
$paidBetaBackendBundlePath = Join-Path $ProjectRoot "scripts\windows\prepare_paid_beta_backend_bundle.ps1"
$paidBetaBackendInstallerPath = Join-Path $ProjectRoot "scripts\server\install_paid_beta_backend_release.sh"
$releaseRollbackInstallerPath = Join-Path $ProjectRoot "scripts\server\configure_public_release_rollback.sh"
$adminStaticInstallerPath = Join-Path $ProjectRoot "scripts\server\install_admin_app_release.sh"
$externalReadinessPath = Join-Path $ProjectRoot "scripts\windows\check_external_services_readiness.ps1"
$paymentLaunchSafetyPath = Join-Path $ProjectRoot "scripts\windows\check_payment_launch_safety.ps1"
$monitoringProbePlanPath = Join-Path $ProjectRoot "scripts\windows\get_monitoring_probe_plan.ps1"
$ownerLaunchPacketPath = Join-Path $ProjectRoot "scripts\windows\get_owner_launch_packet.ps1"
$configureBackendEnvWindowsPath = Join-Path $ProjectRoot "scripts\windows\configure_backend_env_wsl.ps1"
$deployBackendWindowsPath = Join-Path $ProjectRoot "scripts\windows\deploy_backend_wsl.ps1"
$configureBackendEnvShellPath = Join-Path $ProjectRoot "scripts\configure_backend_env_wsl.sh"
$deployBackendShellPath = Join-Path $ProjectRoot "scripts\deploy_backend_wsl.sh"
$androidLegacyE2ePath = Join-Path $ProjectRoot "scripts\windows\run_android_vpn_e2e.ps1"
$androidRuntimeFailoverServicePath = Join-Path $ProjectRoot "android\app\src\main\kotlin\pro\greenvpn\app\GreenVpnRuntimeFailoverService.kt"
$androidRuntimeFailoverPolicyPath = Join-Path $ProjectRoot "android\app\src\main\kotlin\pro\greenvpn\app\GreenVpnRuntimeFailoverPolicy.kt"
$androidMainActivityPath = Join-Path $ProjectRoot "android\app\src\main\kotlin\pro\greenvpn\app\MainActivity.kt"

$main = Read-Text $mainPath
$releaseContractText = Read-Text $releaseContractPath
$pubspec = Read-Text $pubspecPath
$versionFile = Read-Text $versionFilePath
$finalCandidateBuildScript = Read-Text $finalCandidateBuildPath
$publicProductBuildScript = Read-Text $publicProductBuildPath
$paidBetaBuildScript = Read-Text $paidBetaBuildPath
$androidRuntimeFailoverService = Read-Text $androidRuntimeFailoverServicePath
$androidRuntimeFailoverPolicy = Read-Text $androidRuntimeFailoverPolicyPath
$androidMainActivity = Read-Text $androidMainActivityPath
$windowsSelectiveRouting = Read-Text $windowsSelectiveRoutingPath
$windowsVpnStatusPolicy = Read-Text $windowsVpnStatusPolicyPath
$fusionConnectionStatusPolicy = Read-Text $fusionConnectionStatusPolicyPath
$runtimeConfig = Read-Text $runtimeConfigPath
$backend = Read-Text $backendPath
$installer = Read-Text $installerPath
$paidBetaWindowsInstaller = Read-Text $paidBetaWindowsInstallerPath
$paidBetaWindowsUninstaller = Read-Text $paidBetaWindowsUninstallerPath
$signScript = Read-Text $signScriptPath
$trustedWindowsFinalizer = Read-Text $trustedWindowsFinalizerPath
$windowsPublicReleaseInstaller = Read-Text $windowsPublicReleaseInstallerPath
$windowsStableReleaseInstaller = Read-Text $windowsStableReleaseInstallerPath
$serviceSource = Read-Text $servicePath
$doctorScript = Read-Text $doctorPath
$networkProtectionScript = Read-Text $networkProtectionPath
$networkTransitionSmokeScript = Read-Text $networkTransitionSmokePath
$vpnTaskScript = Read-Text $vpnTaskPath
$transportPreviewVpnTaskScript = Read-Text $transportPreviewVpnTaskPath
$windowsStandbyProbeScript = Read-Text $windowsStandbyProbePath
$transportSelectiveRoutingScript = Read-Text $transportSelectiveRoutingPath
$transportSelectiveRoutingTestScript = Read-Text $transportSelectiveRoutingTestPath
$windowsRuntimeFailoverPhysicalTestScript = Read-Text $windowsRuntimeFailoverPhysicalTestPath
$windowsConnectLatencyPhysicalTestScript = Read-Text $windowsConnectLatencyPhysicalTestPath
$windowsFastCacheReleaseSmokeScript = Read-Text $windowsFastCacheReleaseSmokePath
$windowsStandbyTrayReleaseSmokeScript = Read-Text $windowsStandbyTrayReleaseSmokePath
$windowsStandbyTrayReleaseLauncherScript = Read-Text $windowsStandbyTrayReleaseLauncherPath
$windowsSmokeNetworkRestoreScript = Read-Text $windowsSmokeNetworkRestorePath
$windowsFusionPaidBetaAcceptanceSmokeScript = Read-Text $windowsFusionPaidBetaAcceptanceSmokePath
$windowsFusionPaidBetaAcceptanceLauncherScript = Read-Text $windowsFusionPaidBetaAcceptanceLauncherPath
$windowsModeReconcileReleaseSmokeScript = Read-Text $windowsModeReconcileReleaseSmokePath
$windowsModeReconcileReleaseLauncherScript = Read-Text $windowsModeReconcileReleaseLauncherPath
$fusionProductionPromotionScript = Read-Text $fusionProductionPromotionPath
$publicProductBackendBundleScript = Read-Text $publicProductBackendBundlePath
$transportCascadeStageScript = Read-Text $transportCascadeStagePath
$publicInstallerAuditScript = Read-Text $publicInstallerAuditPath
$transportPreviewInstallScript = Read-Text $transportPreviewInstallPath
$transportPreviewUninstallScript = Read-Text $transportPreviewUninstallPath
$transportPreviewBuildScript = Read-Text $transportPreviewBuildPath
$hysteriaWatchdogScript = Read-Text $hysteriaWatchdogPath
$hysteriaPhysicalTestScript = Read-Text $hysteriaPhysicalTestPath
$vlessWatchdogScript = Read-Text $vlessWatchdogPath
$vlessPhysicalTestScript = Read-Text $vlessPhysicalTestPath
$naiveWatchdogScript = Read-Text $naiveWatchdogPath
$naiveClientSmokeScript = Read-Text $naiveClientSmokePath
$managedSocksTunPhysicalTestScript = Read-Text $managedSocksTunPhysicalTestPath
$naivePhysicalTestScript = Read-Text $naivePhysicalTestPath
$dnsttWatchdogScript = Read-Text $dnsttWatchdogPath
$dnsttPhysicalTestScript = Read-Text $dnsttPhysicalTestPath
$transportCascadePhysicalTestScript = Read-Text $transportCascadePhysicalTestPath
$androidSettings = Read-Text $androidSettingsPath
$androidAppBuild = Read-Text $androidAppBuildPath
$androidAppManifest = Read-Text $androidAppManifestPath
$androidLintConfig = Read-Text $androidLintConfigPath
$androidAppDebugManifest = Read-Text $androidAppDebugManifestPath
$androidTransportContractService = Read-Text $androidTransportContractServicePath
$androidTransportContractProbe = Read-Text $androidTransportContractProbePath
$androidQuickTilePhysicalTest = Read-Text $androidQuickTilePhysicalTestPath
$androidMainActivity = Read-Text $androidMainActivityPath
$androidQuickTile = Read-Text $androidQuickTilePath
$androidRouteProbe = Read-Text $androidRouteProbePath
$androidRouteProbeTest = Read-Text $androidRouteProbeTestPath
$androidQuickTilePolicy = Read-Text $androidQuickTilePolicyPath
$androidQuickTilePolicyTest = Read-Text $androidQuickTilePolicyTestPath
$androidHysteriaBuild = Read-Text $androidHysteriaBuildPath
$androidHysteriaManifest = Read-Text $androidHysteriaManifestPath
$androidHysteriaDebugManifest = Read-Text $androidHysteriaDebugManifestPath
$androidHysteriaConfig = Read-Text $androidHysteriaConfigPath
$androidHysteriaController = Read-Text $androidHysteriaControllerPath
$androidHysteriaService = Read-Text $androidHysteriaServicePath
$androidHysteriaBridge = Read-Text $androidHysteriaBridgePath
$androidHysteriaConfigTest = Read-Text $androidHysteriaConfigTestPath
$androidBuildScript = Read-Text $androidBuildScriptPath
$androidReleaseSigner = (Read-Text $androidReleaseSignerPath).Trim().ToLowerInvariant()
$androidHysteriaPrepareScript = Read-Text $androidHysteriaPreparePath
$androidHysteriaNativeBuildScript = Read-Text $androidHysteriaNativeBuildPath
$androidHysteriaNativeManifestText = Read-Text $androidHysteriaNativeManifestPath
$androidHysteriaPhysicalTestScript = Read-Text $androidHysteriaPhysicalTestPath
$androidHysteriaApkVerifyScript = Read-Text $androidHysteriaApkVerifyPath
$androidStableIsolationVerifyScript = Read-Text $androidStableIsolationVerifyPath
$androidTransportProbeReceiver = Read-Text $androidTransportProbeReceiverPath
$androidVlessConfig = Read-Text $androidVlessConfigPath
$androidVlessController = Read-Text $androidVlessControllerPath
$androidVlessService = Read-Text $androidVlessServicePath
$androidVlessConfigTest = Read-Text $androidVlessConfigTestPath
$androidVlessPrepareScript = Read-Text $androidVlessPreparePath
$androidVlessPhysicalTestScript = Read-Text $androidVlessPhysicalTestPath
$androidNaiveConfig = Read-Text $androidNaiveConfigPath
$androidNaiveController = Read-Text $androidNaiveControllerPath
$androidNaiveService = Read-Text $androidNaiveServicePath
$androidNaiveConfigTest = Read-Text $androidNaiveConfigTestPath
$androidNaivePrepareScript = Read-Text $androidNaivePreparePath
$androidNaivePhysicalTestScript = Read-Text $androidNaivePhysicalTestPath
$androidDnsttConfig = Read-Text $androidDnsttConfigPath
$androidDnsttController = Read-Text $androidDnsttControllerPath
$androidDnsttService = Read-Text $androidDnsttServicePath
$androidDnsttConfigTest = Read-Text $androidDnsttConfigTestPath
$androidDnsttPrepareScript = Read-Text $androidDnsttPreparePath
$androidDnsttPhysicalTestScript = Read-Text $androidDnsttPhysicalTestPath
$androidDnsttApkVerifyScript = Read-Text $androidDnsttApkVerifyPath
$routeFailureCooldown = Read-Text $routeFailureCooldownPath
$routeFailureCooldownTest = Read-Text $routeFailureCooldownTestPath
$transportPreviewPolicy = Read-Text $transportPreviewPolicyPath
$transportPreviewPolicyTest = Read-Text $transportPreviewPolicyTestPath
$monitoringProbe = Read-Text $monitoringProbePath
$wireguardTcpCanaryScript = Read-Text $wireguardTcpCanaryPath
$transportCanaryScript = Read-Text $transportCanaryPath
$transportCanaryCheckScript = Read-Text $transportCanaryCheckPath
$transportCanaryRollbackScript = Read-Text $transportCanaryRollbackPath
$amneziaWg2CanaryBootstrapScript = Read-Text $amneziaWg2CanaryBootstrapPath
$amneziaWg2CanaryPeerAddressScript = Read-Text $amneziaWg2CanaryPeerAddressPath
$hysteria2CanaryBootstrapScript = Read-Text $hysteria2CanaryBootstrapPath
$hysteria2ContractDeployScript = Read-Text $hysteria2ContractDeployPath
$naiveHttpsBootstrapScript = Read-Text $naiveHttpsBootstrapPath
$naiveHttpsReadinessScript = Read-Text $naiveHttpsReadinessPath
$naiveHttpsRollbackScript = Read-Text $naiveHttpsRollbackPath
$naiveCertificateSyncScript = Read-Text $naiveCertificateSyncPath
$naiveCertificateSyncInstallerScript = Read-Text $naiveCertificateSyncInstallerPath
$dnsttBootstrapScript = Read-Text $dnsttBootstrapPath
$dnsttDnsFrontendBootstrapScript = Read-Text $dnsttDnsFrontendBootstrapPath
$dnsttDnsFrontendRollbackScript = Read-Text $dnsttDnsFrontendRollbackPath
$dnsttReadinessScript = Read-Text $dnsttReadinessPath
$dnsttRollbackScript = Read-Text $dnsttRollbackPath
$naiveDnsttContractDeployScript = Read-Text $naiveDnsttContractDeployPath
$serverSecurityRunbook = Read-Text $serverSecurityRunbookPath
$projectMap = Read-Text $projectMapPath
$projectOperationsRunbook = Read-Text $projectOperationsRunbookPath
$fullServerSnapshotScript = Read-Text $fullServerSnapshotPath
$fullProjectCheckpointScript = Read-Text $fullProjectCheckpointPath
$localRestoreSnapshotScript = Read-Text $localRestoreSnapshotPath
$repositorySecretScanner = Read-Text $repositorySecretScannerPath
$sqliteStateSyncScript = Read-Text $sqliteStateSyncPath
$sqliteSnapshotScript = Read-Text $sqliteSnapshotPath
$dbSyncShellScript = Read-Text $dbSyncShellPath
$paidBetaTransportCatalogSyncScript = Read-Text $paidBetaTransportCatalogSyncPath
$paidBetaTransportParityScript = Read-Text $paidBetaTransportParityPath
$paidBetaBackendBundleScript = Read-Text $paidBetaBackendBundlePath
$paidBetaBackendInstallerScript = Read-Text $paidBetaBackendInstallerPath
$releaseRollbackInstallerScript = Read-Text $releaseRollbackInstallerPath
$adminStaticInstallerScript = Read-Text $adminStaticInstallerPath
$externalReadinessScript = Read-Text $externalReadinessPath
$paymentLaunchSafetyScript = Read-Text $paymentLaunchSafetyPath
$monitoringProbePlanScript = Read-Text $monitoringProbePlanPath
$ownerLaunchPacketScript = Read-Text $ownerLaunchPacketPath
$configureBackendEnvWindowsScript = Read-Text $configureBackendEnvWindowsPath
$deployBackendWindowsScript = Read-Text $deployBackendWindowsPath
$configureBackendEnvShellScript = Read-Text $configureBackendEnvShellPath
$deployBackendShellScript = Read-Text $deployBackendShellPath
$androidLegacyE2eScript = Read-Text $androidLegacyE2ePath

Write-Section "RELEASE IDENTITY AND REPRODUCIBILITY CHECKS"
$releaseContract = $null
try {
    $releaseContract = $releaseContractText | ConvertFrom-Json
}
catch {
    Add-Error "release_contract.json is not valid JSON: $($_.Exception.Message)"
}
if ($null -ne $releaseContract) {
    $requiredContractProperties = @(
        'schema',
        'appVersion',
        'androidBuildNumber',
        'windowsBuildNumber',
        'backendVersion',
        'paidBeta',
        'api',
        'billing',
        'publication'
    )
    $missingContractProperties = @(
        $requiredContractProperties |
            Where-Object { $releaseContract.PSObject.Properties.Name -notcontains $_ }
    )
    if ($missingContractProperties.Count -gt 0) {
        Add-Error "Release contract is incomplete: $($missingContractProperties -join ', ')"
    }
    else {
        if ([int]$releaseContract.schema -eq 1) {
            Add-Pass 'Release contract schema is supported'
        }
        else {
            Add-Error "Unsupported release contract schema: $($releaseContract.schema)"
        }

        $appVersion = [string]$releaseContract.appVersion
        $androidBuildNumber = [string]$releaseContract.androidBuildNumber
        $windowsBuildNumber = [int]$releaseContract.windowsBuildNumber
        $backendVersion = [string]$releaseContract.backendVersion
        $paidBetaVersion = [string]$releaseContract.paidBeta.appVersion
        $paidBetaWindowsVersion = if (
            $releaseContract.paidBeta.PSObject.Properties.Name -contains 'windowsAppVersion'
        ) {
            [string]$releaseContract.paidBeta.windowsAppVersion
        }
        else {
            $paidBetaVersion
        }
        $paidBetaAndroidBuildNumber = [string]$releaseContract.paidBeta.androidBuildNumber
        $paidBetaWindowsBuildNumber = [int]$releaseContract.paidBeta.windowsBuildNumber

        $releaseIdentityChecks = [ordered]@{
            'pubspec version' = @($pubspec, "version: $appVersion+$androidBuildNumber")
            'VERSION product version' = @($versionFile, "Green VPN $appVersion")
            'VERSION Android build' = @($versionFile, "Android build: $androidBuildNumber")
            'VERSION Windows build' = @($versionFile, "Windows build: $windowsBuildNumber")
            'VERSION backend source' = @($versionFile, "Source backend: $backendVersion")
            'Backend source default' = @($backend, "`"$backendVersion`"")
            'Final candidate app version' = @($finalCandidateBuildScript, "[string]`$AppVersion = '$appVersion'")
            'Final candidate Android build' = @($finalCandidateBuildScript, "[string]`$AndroidBuildNumber = '$androidBuildNumber'")
            'Final candidate Windows build' = @($finalCandidateBuildScript, "[int]`$WindowsBuildNumber = $windowsBuildNumber")
            'Public product app version' = @($publicProductBuildScript, "[string]`$AppVersion = `"$appVersion`"")
            'Public product Windows app version' = @($publicProductBuildScript, "[string]`$WindowsAppVersion = `"$appVersion`"")
            'Public product Android build' = @($publicProductBuildScript, "[string]`$AndroidBuildNumber = `"$androidBuildNumber`"")
            'Public product Windows build' = @($publicProductBuildScript, "[int]`$WindowsBuildNumber = $windowsBuildNumber")
            'Paid-beta app version' = @($paidBetaBuildScript, "[string]`$AppVersion = `"$paidBetaVersion`"")
            'Paid-beta Windows app version' = @($paidBetaBuildScript, "[string]`$WindowsAppVersion = `"$paidBetaWindowsVersion`"")
            'Paid-beta Android build' = @($paidBetaBuildScript, "[string]`$AndroidBuildNumber = `"$paidBetaAndroidBuildNumber`"")
            'Paid-beta Windows build' = @($paidBetaBuildScript, "[int]`$WindowsBuildNumber = $paidBetaWindowsBuildNumber")
            'Trusted Windows finalizer build' = @($trustedWindowsFinalizer, "[int]`$WindowsBuildNumber = $windowsBuildNumber")
        }
        foreach ($check in $releaseIdentityChecks.GetEnumerator()) {
            if (([string]$check.Value[0]).Contains([string]$check.Value[1])) {
                Add-Pass "$($check.Key) matches the release contract"
            }
            else {
                Add-Error "$($check.Key) does not match the release contract"
            }
        }

        if (
            $releaseContract.api.primary -eq 'https://api.greenvpn.pro' -and
            @($releaseContract.api.fallbacks).Count -eq 1 -and
            @($releaseContract.api.fallbacks)[0] -eq 'https://176-113-81-35.sslip.io' -and
            $releaseContract.api.paidBetaPath -eq '/paid-beta-api'
        ) {
            Add-Pass 'Release API roots match the canonical dual-control-plane contract'
        }
        else {
            Add-Error 'Release API roots do not match the canonical dual-control-plane contract'
        }

        if (
            $releaseContract.billing.paidSalesEnabled -eq $false -and
            $releaseContract.billing.refundExecutionEnabled -eq $false -and
            $releaseContract.billing.autoRenewEnabled -eq $false -and
            $releaseContract.billing.rewardedAdsEnabled -eq $false -and
            $releaseContract.publication.productionPublished -eq $false -and
            $releaseContract.publication.ownerApprovalRequired -eq $true
        ) {
            Add-Pass 'Release contract remains fail-closed for money, ads, and publication'
        }
        else {
            Add-Error 'Release contract must remain fail-closed until explicit owner approval'
        }
    }
}

$androidHysteriaNativeManifest = $null
try {
    $androidHysteriaNativeManifest = $androidHysteriaNativeManifestText |
        ConvertFrom-Json
}
catch {
    Add-Error "Hysteria2 native manifest is not valid JSON: $($_.Exception.Message)"
}
if ($null -ne $androidHysteriaNativeManifest) {
    if (
        $androidHysteriaNativeManifest.hysteriaVersion -eq 'app/v2.9.3' -and
        $androidHysteriaNativeManifest.sourceCommit -eq '2d973f9513ef661d1922d6d14acb37945caef47d' -and
        $androidHysteriaNativeManifest.goVersion -eq 'go1.25.1' -and
        $androidHysteriaNativeManifest.ndkRevision -eq '28.2.13676358' -and
        [int]$androidHysteriaNativeManifest.androidApi -eq 26 -and
        [int]$androidHysteriaNativeManifest.pageSizeBytes -eq 16384 -and
        [int]$androidHysteriaNativeManifest.reproducibilityPasses -ge 2
    ) {
        Add-Pass 'Hysteria2 native manifest satisfies the pinned 16 KB reproducibility contract'
    }
    else {
        Add-Error 'Hysteria2 native manifest violates the pinned 16 KB reproducibility contract'
    }

    foreach ($row in @($androidHysteriaNativeManifest.files)) {
        $binaryPath = Join-Path $ProjectRoot (
            "android\transport_preview\hysteria_tunnel\src\main\jniLibs\" +
            "$($row.abi)\$($row.file)"
        )
        if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf)) {
            Add-Error "Tracked Hysteria2 binary is missing: $binaryPath"
            continue
        }
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $binaryPath).Hash
        if ($actualHash -eq ([string]$row.sha256).ToUpperInvariant()) {
            Add-Pass "Hysteria2 tracked binary hash matches: $($row.abi)"
        }
        else {
            Add-Error "Hysteria2 tracked binary hash mismatch: $($row.abi)"
        }
    }
}

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

$runnerSource = Read-Text $runnerPath
$runnerMainSource = Read-Text $runnerMainPath
$windowsParityFragments = @(
    'greenVpnShouldOpenSavedSessionDirectly',
    'ReadLocalServiceToken',
    'X-GreenVPN-Local-Token',
    '\u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0438\u0442\u044c VPN',
    'const <String>[]',
    'mode: ProcessStartMode.detached',
    'kTrayTaskResultMessage',
    'uri.scheme == ''https'''
)
$windowsParitySource = $main + "`n" + $runnerSource
foreach ($fragment in $windowsParityFragments) {
    if ($windowsParitySource.Contains($fragment)) {
        Add-Pass "Windows product parity marker present: $fragment"
    }
    else {
        Add-Error "Windows product parity marker missing: $fragment"
    }
}

if ($runnerSource -match 'case\s+kTrayMenuExit:\s*RequestDisconnectAndExit\(\);') {
    Add-Pass "Windows tray exit disconnects before process exit"
}
else {
    Add-Error "Windows tray exit must call RequestDisconnectAndExit before process exit."
}

$fusionIsolationChecks = [ordered]@{
    'Flutter Fusion compile-time gate' = @($main, 'kPublicProductBuild && kFusionProductionPromotionCandidate')
    'Windows Fusion build gate' = @($installer, 'Fusion production promotion gate requires EnableFusionUi=true and PublicProductBuild=true.')
    'Public-product Fusion orchestrator gate' = @($publicProductBuildScript, 'Fusion production build requires PrepareFusionProductionPromotionCandidate.')
    'Fusion promotion clean-source gate' = @($fusionProductionPromotionScript, 'git status --porcelain=v1')
    'Fusion promotion exact smoke gate' = @($fusionProductionPromotionScript, 'Paid-beta Windows smoke did not succeed.')
    'Fusion promotion owner gate' = @($fusionProductionPromotionScript, 'stable_production_promotion')
    'Fusion promotion no-deploy marker' = @($fusionProductionPromotionScript, 'deploymentAttempted = $false')
    'Public-product backend bundle contour' = @($publicProductBackendBundleScript, "contour = 'public-product'")
    'Paid-beta orchestrator Fusion gate' = @($paidBetaBuildScript, 'Fusion UI is allowed only in the isolated paid-beta product.')
    'Android scheduled-resume marker' = @($androidRuntimeFailoverService, 'KEY_RESUME_SCHEDULED')
    'Android scheduled-resume cancellation policy' = @($androidRuntimeFailoverPolicy, 'shouldCancelScheduledResume')
    'Android cancellation waits for transition idle' = @($androidMainActivity, 'GreenVpnConnectionOperationGate.awaitIdle()')
    'Flutter cancels abandoned Android resume' = @($main, 'android pause resume UI polling stopped after five minutes')
}
foreach ($check in $fusionIsolationChecks.GetEnumerator()) {
    if ($check.Value[0].Contains($check.Value[1])) {
        Add-Pass "$($check.Key) marker present"
    }
    else {
        Add-Error "$($check.Key) marker missing: $($check.Value[1])"
    }
}

$fusionAuthoritativeStatusSource =
    $main + "`n" + $runtimeConfig + "`n" + $fusionConnectionStatusPolicy
$fusionAuthoritativeStatusFragments = @(
    'greenVpnFusionConnectionPresentation',
    'GREENVPN_FUSION_UI_DIAGNOSTIC_PATH',
    '_writeFusionUiDiagnostic',
    'windowsProtectionConfirmed',
    'windowsFullTunnelDataPlaneConfirmed',
    'processRouterRequired',
    'connectedCheckVisible',
    "statusKey = socialOnlyEnabled ? 'protected_selected' : 'protected_full'",
    "statusKey = vpnConflict ? 'vpn_conflict' : 'external_vpn'",
    'routing preference confirmed mode='
)
foreach ($fragment in $fusionAuthoritativeStatusFragments) {
    if ($fusionAuthoritativeStatusSource.Contains($fragment)) {
        Add-Pass "Fusion authoritative connection status marker present: $fragment"
    }
    else {
        Add-Error "Fusion authoritative connection status marker missing: $fragment"
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
    '@app.post("/api/v1/auth/guest")',
    '@app.post("/api/v1/auth/challenge/start")',
    '@app.post("/api/v1/auth/challenge/verify")',
    '@app.post("/api/v1/auth/checkout/email/start")',
    '@app.post("/api/v1/auth/checkout/email/verify")',
    '@app.get("/api/v1/auth/email/status")',
    '@app.post("/api/v1/auth/email/resend")',
    '@app.get("/api/v1/auth/email/verify"',
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
    '@app.post("/api/v1/admin/billing/orders/{order_id}/cancel-stale")',
    '@app.get("/api/v1/admin/billing/reconciliation")',
    '@app.get("/api/v1/admin/billing/promos/readiness")',
    '@app.post("/api/v1/admin/billing/promos/draft-start-campaign")',
    '@app.get("/api/v1/admin/billing/renewals/readiness")',
    '@app.post("/api/v1/admin/billing/renewals/run")',
    '@app.get("/api/v1/admin/subscriptions/expiry-readiness")',
    '@app.get("/api/v1/admin/email/readiness")',
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
    'def node_local_update_artifact(',
    'database_node_mirror',
    'releaseReadiness',
    'latestReleaseReadiness',
    'rollbackReadiness',
    'rollback_artifact_missing',
    'GREENVPN_ROLLBACK_URL',
    'GREENVPN_ANDROID_ROLLBACK_URL',
    'GREENVPN_ANDROID_PAID_BETA_ROLLBACK_URL',
    'GREENVPN_WINDOWS_PAID_BETA_ROLLBACK_URL',
    'rollback_plan',
    'def windows_distribution_trust_readiness(',
    'GREENVPN_WINDOWS_CODE_SIGNING_PROVIDER',
    'public_download_trusted',
    'def build_advertising_readiness(',
    'PUBLIC_ADVERTISING_REQUIRED_CODES',
    'GREENVPN_FREE_AD_TEST_WEB_ENABLED',
    'legacy_name="GREENVPN_AD_TEST_WEB_ENABLED"',
    'def free_ad_reward_provider_for_platform(',
    'def yandex_web_rewarded_configured(',
    'def build_server_provisioning_readiness(',
    'clientConfigContract',
    'managed_public_entries_pass_gate',
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
    'GREENVPN_REFUND_EXECUTION_ENABLED',
    'GREENVPN_REFUND_BILLING_PRIMARY',
    'def execute_full_refund_for_order(',
    'refund_entitlement_snapshot_missing',
    '/api/v1/admin/billing/refunds/readiness',
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
    'managedCatalog',
    'GREENVPN_HYSTERIA2_CLIENT_CONFIG_ENABLED',
    'GREENVPN_HYSTERIA2_CANARY_SERVER_IDS',
    'GREENVPN_HYSTERIA2_CANARY_SNI',
    'GREENVPN_HYSTERIA2_CANARY_SNIS',
    'static_hysteria2_canary',
    'def hysteria2_client_config_check(',
    'hysteria2_config_not_root_owned',
    'hysteria2_config_not_root_only',
    'hysteria2_config_symlink_refused',
    'hysteria2_insecure_tls_refused',
    'hysteria2_base_config_contains_local_mode',
    'GREENVPN_NAIVE_HTTPS_CANARY_ENDPOINTS',
    'naive_https_endpoint_ip_not_allowlisted',
    'configFormat": "hysteria2-yaml"',
    'def server_protocol_preference_rank(',
    'SERVER_PROTOCOL_ROLLOUT_ORDER.index(protocol)'
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
    'server.isAuto || server.isCurrentClientReady',
    'const bool kAwg2PreviewEnabled = bool.fromEnvironment(',
    "'GREENVPN_AWG2_PREVIEW_ENABLED'",
    'defaultValue: false',
    "'wireguard_udp'",
    "if (kAwg2PreviewEnabled) 'amneziawg'",
    'const bool kHysteria2PreviewEnabled = bool.fromEnvironment(',
    "'GREENVPN_HYSTERIA2_PREVIEW_ENABLED'",
    "if (kHysteria2PreviewEnabled) 'hysteria2'",
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
    'Owner-approved data-plane ${PROTOCOL} canary tuple accepted.',
    'greenvpn-hysteria2-canary',
    '/etc/greenvpn-transport/hysteria2-canary.yaml',
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
    'hysteria2_required_fields_missing',
    'hysteria2_insecure_tls_refused',
    'hysteria2_obfuscation_missing',
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
    'Owner-approved data-plane ${PROTOCOL} rollback tuple accepted.',
    'greenvpn-hysteria2-canary',
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

$requiredAmneziaWg2PeerAddressFragments = @(
    'Assign a unique address to one existing AmneziaWG 2 canary peer',
    'CANARY_HOST="5.129.216.42"',
    'CANARY_INTERFACE="awgcanary0"',
    '--peer-fingerprint',
    '--client-address',
    'Requested client address is already assigned to another peer',
    'syncconf "$CANARY_INTERFACE"',
    'rollback',
    'Stable wg0 invariant changed',
    'wg0=active_unchanged',
    'mode=dry-run'
)

foreach ($fragment in $requiredAmneziaWg2PeerAddressFragments) {
    if ($amneziaWg2CanaryPeerAddressScript.Contains($fragment)) {
        Add-Pass "AmneziaWG 2 peer-address safety marker present: $fragment"
    }
    else {
        Add-Error "AmneziaWG 2 peer-address safety marker missing: $fragment"
    }
}

$requiredHysteria2BootstrapFragments = @(
    'Bootstrap the owner-approved Hysteria2 canary on a Green VPN data plane.',
    'CANARY_HOST="5.129.216.42"',
    'CANARY_DOMAIN="nl2.vpn.greenvpn.pro"',
    'CANARY_PORT="2443"',
    'SERVICE_NAME="greenvpn-hysteria2-canary"',
    'HYSTERIA_VERSION="2.9.3"',
    '66dbdb0608f25f3057b433afe975a9fc1af2ca8e512479e294988b3ef363d6c1',
    'sha256sum -c',
    'type: salamander',
    'insecure: false',
    'CLIENT_BASE_CONFIG_FILE=',
    'chmod 0600 "${CLIENT_BASE_CONFIG_FILE}"',
    'chmod 0600 "${CLIENT_CONFIG_FILE}"',
    'stable_wireguard=not_changed',
    'amneziawg_canary=not_changed',
    'public_catalog=not_changed'
)

foreach ($fragment in $requiredHysteria2BootstrapFragments) {
    if ($hysteria2CanaryBootstrapScript.Contains($fragment)) {
        Add-Pass "Hysteria2 bootstrap safety marker present: $fragment"
    }
    else {
        Add-Error "Hysteria2 bootstrap safety marker missing: $fragment"
    }
}

$requiredHysteria2ContractDeployFragments = @(
    'Deploy the guarded Hysteria2 config contract',
    'EXPECTED_CURRENT_RELEASE=',
    'RELEASE_ID=',
    'BACKEND_VERSION="0.9.110-transport-preview.4"',
    'Role/public IP mismatch; refusing deploy',
    'sha256sum -c',
    'Staged Hysteria2 config must be root:root 0600',
    'production_changed=false',
    'stable_catalog_changed=false',
    'source.backup(target)',
    'rollback_on_error',
    'GREENVPN_HYSTERIA2_CLIENT_CONFIG_ENABLED',
    'static_hysteria2_canary',
    'is_public, planned_bandwidth_mbps',
    'legacy_hysteria_count=0',
    'preview_hysteria_count=1',
    'preview_default_protocol=wireguard_udp'
)

foreach ($fragment in $requiredHysteria2ContractDeployFragments) {
    if ($hysteria2ContractDeployScript.Contains($fragment)) {
        Add-Pass "Hysteria2 contract deploy safety marker present: $fragment"
    }
    else {
        Add-Error "Hysteria2 contract deploy safety marker missing: $fragment"
    }
}

Write-Section "NAIVE HTTPS CANARY CHECKS"
$naiveHttpsChecks = [ordered]@{
    'Naive HTTPS guarded bootstrap' = @($naiveHttpsBootstrapScript, 'CANARY_HOST="5.129.216.42"', 'CANARY_PORT="8443"', 'CADDY_VERSION="v2.11.4"', 'XCADDY_VERSION="v0.4.5"', 'FORWARDPROXY_COMMIT="d62c80d3dd2c706b6b87579844d2397bddd18317"', 'NAIVE_VERSION="v150.0.7871.63-1"', 'pinned_binaries=reused_after_build_metadata_verification', 'stable_transports=verified_unchanged')
    'Naive HTTPS secret-safe readiness' = @($naiveHttpsReadinessScript, 'ready=true', 'credentials=not_printed', 'tls_camouflage_http=404', 'egress=', 'unexpected_udp_listener')
    'Naive HTTPS exact-host rollback' = @($naiveHttpsRollbackScript, 'Refusing Naive HTTPS rollback outside exact NL2 host', '--approved-existing-host', 'rm -rf -- "${CONFIG_FILE}" "${INSTALL_ROOT}"', 'stable_transports=active', 'Dry-run only')
    'Naive certificate synchronization is guarded and reversible' = @($naiveCertificateSyncScript, 'EXPECTED_HOST="5.129.216.42"', 'openssl x509 -in "${certificate}" -noout -checkend 604800', 'copy_needed=', 'rollback_on_error', 'greenvpn-naive-https-canary.service', 'entries[4:]', 'secrets_printed=false')
    'Naive certificate synchronization timer is isolated' = @($naiveCertificateSyncInstallerScript, 'Default mode validates', 'greenvpn-naive-certificate-sync.timer', 'ReadWritePaths=/etc/greenvpn-naive-https-canary /var/lib/greenvpn-naive-cert-sync', 'rollback_on_error', 'systemctl is-active --quiet greenvpn-naive-https-canary.service')
}
foreach ($check in $naiveHttpsChecks.GetEnumerator()) {
    $source = [string]$check.Value[0]
    $missing = @($check.Value[1..($check.Value.Count - 1)] | Where-Object { -not $source.Contains([string]$_) })
    if ($missing.Count -eq 0) {
        Add-Pass "$($check.Key) markers present"
    }
    else {
        Add-Error "$($check.Key) missing marker(s): $($missing -join ', ')"
    }
}

foreach ($scriptPath in @(
    $naiveHttpsBootstrapPath,
    $naiveHttpsReadinessPath,
    $naiveHttpsRollbackPath,
    $naiveCertificateSyncPath,
    $naiveCertificateSyncInstallerPath
)) {
    if (Test-Path -LiteralPath $scriptPath) {
        $gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
        $bashCommand = if (Test-Path -LiteralPath $gitBash) { $gitBash } else { 'bash' }
        & $bashCommand -n $scriptPath
        if ($LASTEXITCODE -eq 0) {
            Add-Pass "Naive HTTPS Bash parser check passed: $scriptPath"
        }
        else {
            Add-Error "Naive HTTPS Bash parser check failed: $scriptPath"
        }
    }
}

Write-Section "INSTALLER CHECKS"
$localizedWindowsPowerShellScripts = @(
    $installerPath,
    (Join-Path $ProjectRoot "scripts\bluevpn_social_only.ps1")
)
foreach ($localizedScriptPath in $localizedWindowsPowerShellScripts) {
    if (-not (Test-Path -LiteralPath $localizedScriptPath)) {
        Add-Error "Missing localized Windows PowerShell script: $localizedScriptPath"
        continue
    }
    $localizedScriptBytes = [IO.File]::ReadAllBytes($localizedScriptPath)
    $hasUtf8Bom = $localizedScriptBytes.Length -ge 3 -and
        $localizedScriptBytes[0] -eq 0xEF -and
        $localizedScriptBytes[1] -eq 0xBB -and
        $localizedScriptBytes[2] -eq 0xBF
    if ($hasUtf8Bom) {
        Add-Pass "Localized Windows PowerShell script is UTF-8 BOM safe: $localizedScriptPath"
    }
    else {
        Add-Error "Localized Windows PowerShell script must use UTF-8 BOM for Windows PowerShell 5.1: $localizedScriptPath"
    }
}

$protectedInstallerContracts = [ordered]@{
    'Production installer uses Program Files' = @($installer, '[string]$InstallDir = "$env:ProgramFiles\Green VPN"')
    'Production installer creates common desktop shortcuts' = @($installer, "CommonDesktopDirectory")
    'Production installer creates common Start Menu shortcuts' = @($installer, "CommonPrograms")
    'Production installer protects machine binaries' = @($installer, "'*S-1-5-32-545:(OI)(CI)RX'")
    'Production installer registers machine-wide uninstall' = @($installer, "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN")
    'Production installer registers machine-wide startup' = @($installer, "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
    'Production installer stages files before replacing the live installation' = @($installer, '$stagingRoot = "$installRoot.staging-$swapId"')
    'Production installer restores the previous installation on failure' = @($installer, 'if (-not $installCompleted -and ($runtimeStopped -or $existingRootBackedUp -or $installSwapped))')
    'Production installer launches in the original user context after UAC' = @($installer, '$launchAfterInstall = -not $NoLaunch')
    'Beta installer uses Program Files' = @($paidBetaWindowsInstaller, '[string]$InstallDir = "$env:ProgramFiles\Green VPN Beta"')
    'Beta installer creates common desktop shortcuts' = @($paidBetaWindowsInstaller, "CommonDesktopDirectory")
    'Beta installer creates common Start Menu shortcuts' = @($paidBetaWindowsInstaller, "CommonPrograms")
    'Beta installer protects machine binaries' = @($paidBetaWindowsInstaller, "'*S-1-5-32-545:(OI)(CI)RX'")
    'Beta installer registers machine-wide uninstall' = @($paidBetaWindowsInstaller, "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Green VPN Beta")
    'Beta installer stages files before replacing the live installation' = @($paidBetaWindowsInstaller, '$stagingRoot = "$installRoot.staging-$swapId"')
    'Beta installer restores the previous installation on failure' = @($paidBetaWindowsInstaller, 'restoring the previous beta version')
    'Beta installer launches in the original user context after UAC' = @($paidBetaWindowsInstaller, '$launchAfterInstall = -not $NoLaunch')
    'Beta uninstaller accepts protected Program Files root' = @($paidBetaWindowsUninstaller, '$programFiles = [System.IO.Path]::GetFullPath($env:ProgramFiles)')
}
foreach ($contract in $protectedInstallerContracts.GetEnumerator()) {
    if ($contract.Value[0].Contains($contract.Value[1])) {
        Add-Pass $contract.Key
    }
    else {
        Add-Error $contract.Key
    }
}

foreach ($scriptContract in @(
    [pscustomobject]@{ Name = 'Beta Windows installer'; Path = $paidBetaWindowsInstallerPath },
    [pscustomobject]@{ Name = 'Beta Windows uninstaller'; Path = $paidBetaWindowsUninstallerPath }
)) {
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($scriptContract.Path, [ref]$null, [ref]$parseErrors) | Out-Null
    if (@($parseErrors).Count -eq 0) {
        Add-Pass "$($scriptContract.Name) PowerShell parser check passed"
    }
    else {
        Add-Error "$($scriptContract.Name) PowerShell parser check failed"
    }
}
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

if ($installer.Contains("AppLaunched=install_bootstrap.exe") -and $installer.Contains("installer_bootstrap.cs")) {
    Add-Pass "Installer uses the native MOTW-safe bootstrap for the branded installer UI"
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

if ($installer.Contains('<requestedExecutionLevel level="asInvoker"') -and
    $installer.Contains('Set-ExeAsInvoker')) {
    Add-Pass 'Installer captures the original user before the privileged install stage'
}
else {
    Add-Error 'Installer must run its UI asInvoker and elevate only the inner install stage.'
}

foreach ($fragment in @(
    'GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS',
    'GREENVPN_INSTALLER_SKIP_APP_LAUNCH',
    '$form.Close()'
)) {
    if ($installer.Contains($fragment)) {
        Add-Pass "Installer physical-smoke UI marker present: $fragment"
    }
    else {
        Add-Error "Installer physical-smoke UI marker missing: $fragment"
    }
}

$installerTokenFragments = @(
    'function Ensure-GreenVpnServiceToken',
    'service_token',
    'RandomNumberGenerator',
    'Resolve-InstallingUserSid',
    '-OwnerSid',
    "('*' + `$UserSid + ':R')",
    "Ensure-GreenVpnServiceToken -UserSid `$installingUserSid"
)

foreach ($fragment in $installerTokenFragments) {
    if ($installer.Contains($fragment)) {
        Add-Pass "Installer local service token setup present: $fragment"
    }
    else {
        Add-Error "Installer missing local service token setup marker: $fragment"
    }
}

foreach ($check in @(
    [pscustomobject]@{ Name = 'production'; Source = $installer },
    [pscustomobject]@{ Name = 'paid-beta'; Source = $paidBetaWindowsInstaller }
)) {
    foreach ($forbidden in @(
        "'*S-1-5-11:(OI)(CI)M'",
        "'*S-1-5-11:R'"
    )) {
        if ($check.Source.Contains($forbidden)) {
            Add-Error "$($check.Name) installer still grants broad ProgramData access: $forbidden"
        }
        else {
            Add-Pass "$($check.Name) installer excludes broad ProgramData marker: $forbidden"
        }
    }
    foreach ($required in @(
        'Resolve-InstallingUserSid',
        '-OwnerSid',
        "/remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545'",
        "('*' + `$UserSid + ':(OI)(CI)M')"
    )) {
        if ($check.Source.Contains($required)) {
            Add-Pass "$($check.Name) protected ProgramData marker present: $required"
        }
        else {
            Add-Error "$($check.Name) protected ProgramData marker missing: $required"
        }
    }
}

foreach ($check in @(
    [pscustomobject]@{
        Name = 'production'
        Source = $installer
        ChildReset = "(Join-Path `$root '*') /reset /T /C"
    },
    [pscustomobject]@{
        Name = 'paid-beta'
        Source = $paidBetaWindowsInstaller
        ChildReset = "(Join-Path `$programDataRoot '*') /reset /T /C"
    }
)) {
    if ($check.Source.Contains($check.ChildReset)) {
        Add-Pass "$($check.Name) installer resets child ACLs to inherit the protected root"
    }
    else {
        Add-Error "$($check.Name) installer does not reset child ACLs to inherit the protected root"
    }
}

if ($installer.Contains("check_windows_network_protection.ps1") -and $installer.Contains("`$networkProtection")) {
    Add-Pass "Installer packages Windows network protection checker"
}
else {
    Add-Error "Installer does not package check_windows_network_protection.ps1."
}

$processRouterInstallerFragments = @(
    'tools\process-router\ProxyBridge_CLI.exe',
    'ProxyBridgeCore.dll',
    'WinDivert64.sys',
    'THIRD_PARTY_NOTICES.txt',
    'Get-AuthenticodeSignature'
)
foreach ($fragment in $processRouterInstallerFragments) {
    if ($installer.Contains($fragment)) {
        Add-Pass "Installer process-router marker present: $fragment"
    }
    else {
        Add-Error "Installer process-router marker missing: $fragment"
    }
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
    'unauthorized local request',
    'kHysteriaPidPath',
    'QueryPidFileProcessState',
    'QueryFullProcessImageNameW',
    'GreenVPNHysteria2Preview',
    'ProcessRouterGuardThread',
    'processRouterState',
    'routingMode'
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

$vpnPriorityTakeoverFragments = @(
    'function Get-CompetingVpnServices',
    'function Stop-CompetingVpnTunnels',
    "Stop-CompetingVpnTunnels -Reason 'connect'",
    "Stop-CompetingVpnTunnels -Reason 'guard'",
    '-AllowedExitCodes @(0, 1056, 1060, 1062)',
    'takeover complete reason=$Reason',
    'connect takeover blocked by competitor count=',
    'function Get-SafePhysicalEndpointRoute',
    'physical gateway settled after takeover'
)
foreach ($fragment in $vpnPriorityTakeoverFragments) {
    if ($fragment -notin @(
        'function Get-SafePhysicalEndpointRoute',
        'physical gateway settled after takeover'
    )) {
        if ($vpnTaskScript.Contains($fragment)) {
            Add-Pass "Windows VPN task priority-takeover marker present: $fragment"
        }
        else {
            Add-Error "Windows VPN task priority-takeover marker missing: $fragment"
        }
    }
    if ($transportPreviewVpnTaskScript.Contains($fragment)) {
        Add-Pass "Windows transport cascade priority-takeover marker present: $fragment"
    }
    else {
        Add-Error "Windows transport cascade priority-takeover marker missing: $fragment"
    }
}

if ($main.Contains('=== CONNECT TAKEOVER: competing VPN active')) {
    Add-Pass 'Windows client delegates competing-VPN takeover to the privileged service'
}
else {
    Add-Error 'Windows client still blocks before the privileged competing-VPN takeover'
}

foreach ($fragment in @(
    'Future<String> resolveWireGuardEndpointToIpv4(',
    'immediate cached connect normalized endpoint',
    'immediate cached connect restored exact server cache',
    'reason=route_config_mismatch',
    'native service fast-path ping',
    'privileged task confirmed tunnel service running; deep verification moved to background',
    'windows foreground connect selected single primary',
    'windows background recovery retained ordered candidates=',
    'return BlueVpnLocalPaths.userStateDir();',
    'await WindowsLocalSecurity.preparePrivateFileForWrite(f.path);',
    'await _recordRouteSuccess(server);',
    'greenVpnShouldBlockForegroundForPostConnectProbe',
    'initialChecksSeconds=2,5',
    'ensure config endpoint preparation failed'
)) {
    if ($main.Contains($fragment)) {
        Add-Pass "Windows fast-connect endpoint normalization marker present: $fragment"
    }
    else {
        Add-Error "Windows fast-connect endpoint normalization marker missing: $fragment"
    }
}

if ($main.Contains("candidate.protocolCode.trim().toLowerCase() != 'wireguard_udp'")) {
    Add-Error 'Windows immediate cache is still restricted to WireGuard instead of the exact confirmed route'
}
else {
    Add-Pass 'Windows immediate cache accepts the exact confirmed route across supported protocols'
}

$nativeFastAcceptIndex = $main.IndexOf(
    '=== CONNECT OK: privileged task confirmed tunnel service running; deep verification moved to background ==='
)
$nativeDeepVerificationIndex = $main.IndexOf('final ok = await waitRunning(loops: 60);')
if (
    $nativeFastAcceptIndex -ge 0 -and
    $nativeDeepVerificationIndex -ge 0 -and
    $nativeFastAcceptIndex -lt $nativeDeepVerificationIndex
) {
    Add-Pass 'Windows native service returns before deep tunnel verification'
}
else {
    Add-Error 'Windows native service fast return must remain before deep tunnel verification'
}

$competingServicesStart = $transportPreviewVpnTaskScript.IndexOf('function Get-CompetingVpnServices {')
$competingServicesEnd = $transportPreviewVpnTaskScript.IndexOf(
    'function Get-CompetingVpnLabels {',
    $competingServicesStart
)
if ($competingServicesStart -ge 0 -and $competingServicesEnd -gt $competingServicesStart) {
    $competingServicesBody = $transportPreviewVpnTaskScript.Substring(
        $competingServicesStart,
        $competingServicesEnd - $competingServicesStart
    )
    if (
        $competingServicesBody.Contains('Get-Service -Name @(') -and
        -not $competingServicesBody.Contains('Get-CimInstance Win32_Service')
    ) {
        Add-Pass 'Windows takeover uses targeted service lookup instead of a full CIM scan'
    }
    else {
        Add-Error 'Windows takeover must keep targeted service lookup on the connect hot path'
    }
}
else {
    Add-Error 'Windows takeover service lookup function could not be inspected'
}

$startOwnTunnelStart = $transportPreviewVpnTaskScript.IndexOf('function Start-OwnTunnel {')
$startOwnTunnelEnd = $transportPreviewVpnTaskScript.IndexOf(
    'function Invoke-GreenGuard {',
    $startOwnTunnelStart
)
if ($startOwnTunnelStart -ge 0 -and $startOwnTunnelEnd -gt $startOwnTunnelStart) {
    $startOwnTunnelBody = $transportPreviewVpnTaskScript.Substring(
        $startOwnTunnelStart,
        $startOwnTunnelEnd - $startOwnTunnelStart
    )
    if ($startOwnTunnelBody -notmatch 'function Start-OwnTunnel \{\s*Ensure-GreenProgramDataAcl') {
        Add-Pass 'Windows native connect does not perform an unconditional ACL scan at startup'
    }
    else {
        Add-Error 'Windows native connect must not perform an unconditional ACL scan at startup'
    }
    foreach ($fragment in @(
        'Stop-OwnTunnel -FastNativeSwitch:$nativeProtocol',
        'if ($script:CompetingVpnTakeoverOccurred)',
        'native tunnel install failed; validating protected state before one retry'
    )) {
        if ($startOwnTunnelBody.Contains($fragment)) {
            Add-Pass "Windows native connect hot-path contract present: $fragment"
        }
        else {
            Add-Error "Windows native connect hot-path contract missing: $fragment"
        }
    }
}
else {
    Add-Error 'Windows native connect function could not be inspected'
}

$stopOwnTunnelStart = $transportPreviewVpnTaskScript.IndexOf('function Stop-OwnTunnel {')
$stopOwnTunnelEnd = $transportPreviewVpnTaskScript.IndexOf(
    'function Start-OwnTunnel {',
    $stopOwnTunnelStart
)
if ($stopOwnTunnelStart -ge 0 -and $stopOwnTunnelEnd -gt $stopOwnTunnelStart) {
    $stopOwnTunnelBody = $transportPreviewVpnTaskScript.Substring(
        $stopOwnTunnelStart,
        $stopOwnTunnelEnd - $stopOwnTunnelStart
    )
    if (
        $stopOwnTunnelBody.Contains('$activeAdapters = @(if (') -and
        -not $stopOwnTunnelBody.Contains('$activeAdapters = if (')
    ) {
        Add-Pass 'Windows transport cleanup preserves an empty adapter result as an array'
    }
    else {
        Add-Error 'Windows transport cleanup must not dereference Count on a null adapter result'
    }
}
else {
    Add-Error 'Windows transport cleanup function could not be inspected'
}

foreach ($fragment in @(
    'function Ensure-DiagnosticLogAccess',
    'function Test-AdvancedTransportStatePresent',
    'SetAccessRuleProtection($false, $true)',
    'takeover service stop accepted:',
    'fast native switch skipped inactive advanced transport cleanup',
    'connect phase=endpoint-bypass-skipped reason=no-competing-vpn',
    'native tunnel install failed; validating protected state before one retry',
    'Set-Service -Name $serviceName -StartupType Manual',
    'connect phase=tunnel-service-running'
)) {
    if ($transportPreviewVpnTaskScript.Contains($fragment)) {
        Add-Pass "Windows fast-takeover task marker present: $fragment"
    }
    else {
        Add-Error "Windows fast-takeover task marker missing: $fragment"
    }
}


$vpnTaskApplicationRoutingFragments = @(
    'Start-GreenProcessRouter',
    'Ensure-GreenApplicationTunnelRoutes',
    'Get-GreenRoutingPolicy',
    'destinationCidrs',
    'selective tunnel uses destination routes only; process router not required',
    'routing_apps.json',
    'ProxyBridge_CLI.exe',
    '$PrivilegedRuntimeRegistryPath',
    'Write-GreenPrivilegedRuntimeValue',
    'ProcessRouterRequired',
    'Confirm-GreenProcessRouterRuntimeContract',
    'Get-GreenProcessRouterProcesses',
    'ApplicationProxyPort = 1080'
)
foreach ($fragment in $vpnTaskApplicationRoutingFragments) {
    if ($vpnTaskScript.Contains($fragment)) {
        Add-Pass "Windows VPN task application-routing marker present: $fragment"
    }
    else {
        Add-Error "Windows VPN task application-routing marker missing: $fragment"
    }
}

$windowsSelectiveUiFragments = @(
    'SocialApp.vk',
    'socialOnlyWindowsSites',
    '_openWindowsInstalledAppsPicker',
    '_openWindowsSitePicker',
    'normalizeWindowsVpnSite',
    'listWindowsLaunchableApps',
    'resolveWindowsVpnSites'
)
foreach ($fragment in $windowsSelectiveUiFragments) {
    if ($main.Contains($fragment) -or $windowsSelectiveRouting.Contains($fragment)) {
        Add-Pass "Windows selective-routing UI marker present: $fragment"
    }
    else {
        Add-Error "Windows selective-routing UI marker missing: $fragment"
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

$transportPreviewRouteFragments = @(
    'Get-ManagedIpv4Endpoint',
    'Ensure-EndpointBypassRoute',
    'Remove-EndpointBypassRoute',
    'Save-CompetingVpnState',
    'Restore-CompetingVpnTunnels',
    '$CompetingVpnStatePath',
    '$endpoint/32',
    'Find-NetRoute -RemoteIPAddress $endpoint',
    "-PolicyStore ActiveStore",
    '$EndpointBypassRouteMetric = 42731',
    '/inheritance:r',
    "'*S-1-5-18:F'",
    "'*S-1-5-32-544:F'",
    "'MSFT_NetRoute'",
    'No physical gateway route is available',
    'endpoint bypass route ready',
    '$mustRecover = $Action -eq ''Connect'' -or',
    '$null -ne $script:ActiveRuntimeTransitionGeneration',
    'failed competitor restore line=',
    'Broad write ACL is forbidden for transport preview state',
    "@('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545')",
    '[IO.FileAttributes]::ReparsePoint',
    'Protected transport preview state directory is missing',
    'Start-Hysteria2Tunnel',
    'Stop-Hysteria2Tunnel',
    'Assert-HysteriaRuntime',
    '$HysteriaRouteMetric = 42732',
    "@('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')",
    'Hysteria2 base config must not contain local listener or forwarding sections',
    'greenvpn_hysteria2_watchdog.ps1'
    'Start-NaiveHttpsTunnel',
    'Stop-NaiveHttpsTunnel',
    'Assert-NaiveRuntime',
    '$NaiveRouteMetric = 42734',
    '$NaiveSocksPort = 1982',
    '$NaiveCanaryPort = 8443',
    '$guardedEndpoints = @{',
    '''nl1.vpn.greenvpn.pro'' = ''37.220.85.211''',
    '''88-218-250-86.sslip.io'' = ''88.218.250.86''',
    '$root.PSObject.Properties.Remove(''endpointIp'')',
    'host-resolver-rules',
    'Get-SafeHevDiagnostic',
    '[IO.File]::ReadAllText($Path)',
    'Wait-NaiveAdapter -HevProcess $hev',
    'Protect-PrivateRuntimeFile -Path $path',
    "mapdns:",
    "udp: 'tcp'",
    'greenvpn_naive_https_watchdog.ps1'
    'greenvpn_selective_routing.ps1'
    'Stop-GreenProcessRouter'
    'Selective application routing is not supported by $protocol.'
    'guard disconnecting application-only tunnel because process router stopped'
)

foreach ($fragment in $transportPreviewRouteFragments) {
    if ($transportPreviewVpnTaskScript.Contains($fragment)) {
        Add-Pass "Windows transport preview route guard present: $fragment"
    }
    else {
        Add-Error "Windows transport preview route guard missing: $fragment"
    }
}

$transportPreviewUdpModeChecks = [ordered]@{
    'VLESS REALITY standard SOCKS5 UDP relay' =
        "(?s)function New-VlessRuntimeConfigs.*?udp:\s*'udp'.*?function Add-VlessRoutes"
    'Naive HTTPS UDP-over-TCP relay' =
        "(?s)function New-NaiveRuntimeConfigs.*?udp:\s*'tcp'.*?function Add-NaiveRoutes"
    'dnstt UDP-over-TCP relay' =
        "(?s)function New-DnsttRuntimeConfigs.*?udp:\s*'tcp'.*?function Add-DnsttRoutes"
}
foreach ($check in $transportPreviewUdpModeChecks.GetEnumerator()) {
    if ($transportPreviewVpnTaskScript -match $check.Value) {
        Add-Pass "Windows transport preview UDP mode is explicit: $($check.Key)"
    }
    else {
        Add-Error "Windows transport preview UDP mode is invalid: $($check.Key)"
    }
}

$transportPreviewHevStackChecks = [ordered]@{
    'Hysteria2 HEV task stack' =
        '(?s)function New-HysteriaRuntimeConfigs.*?task-stack-size:\s*86016.*?function Add-HysteriaRoutes'
    'VLESS REALITY HEV task stack' =
        '(?s)function New-VlessRuntimeConfigs.*?task-stack-size:\s*86016.*?function Add-VlessRoutes'
    'Naive HTTPS HEV task stack' =
        '(?s)function New-NaiveRuntimeConfigs.*?task-stack-size:\s*86016.*?function Add-NaiveRoutes'
    'dnstt HEV task stack' =
        '(?s)function New-DnsttRuntimeConfigs.*?task-stack-size:\s*86016.*?function Add-DnsttRoutes'
}
foreach ($check in $transportPreviewHevStackChecks.GetEnumerator()) {
    if ($transportPreviewVpnTaskScript -match $check.Value) {
        Add-Pass "Windows transport preview HEV stack is explicit: $($check.Key)"
    }
    else {
        Add-Error "Windows transport preview HEV stack is invalid: $($check.Key)"
    }
}

$unsafePrecreatedRedirectPattern = '(?s)function Start-(?:NaiveHttps|Dnstt)Tunnel.*?Write-PrivateRuntimeFile\s+-Path\s+\$path\s+-Content\s+''''.*?function'
if ($transportPreviewVpnTaskScript -match $unsafePrecreatedRedirectPattern) {
    Add-Error 'Windows SOCKS/TUN transports precreate hidden redirect files before Start-Process.'
}
else {
    Add-Pass 'Windows SOCKS/TUN redirect files are protected only after Start-Process creates them.'
}

$transportPreviewVlessRuntimeFragments = @(
    '-NotePropertyName packetEncoding -NotePropertyValue ''xudp''',
    '-NotePropertyName mode -NotePropertyValue ''stream-up''',
    'maxConnections = 1',
    'cMaxReuseTimes = ''128-256''',
    'hMaxRequestTimes = ''1000-2000''',
    'hMaxReusableSecs = ''600-900''',
    'hKeepAlivePeriod = 30',
    'protocol = ''dns''',
    'tag = ''dns-out''',
    'https://1.1.1.1/dns-query',
    'address: 198.18.1.2',
    'Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses @(''198.18.1.2'')'
)
foreach ($fragment in $transportPreviewVlessRuntimeFragments) {
    if ($transportPreviewVpnTaskScript.Contains($fragment)) {
        Add-Pass "Windows VLESS full-tunnel hardening marker present: $fragment"
    }
    else {
        Add-Error "Windows VLESS full-tunnel hardening marker missing: $fragment"
    }
}

$transportSelectiveRoutingChecks = [ordered]@{
    'Windows cascade selective helper' = @(
        $transportSelectiveRoutingScript,
        'Get-GreenRoutingPolicy',
        'Get-GreenDestinationCidrs',
        'Ensure-GreenApplicationTunnelRoutes',
        'Start-GreenProcessRouter',
        'Application-only config unexpectedly contains a default route.'
    )
    'Windows cascade stages selective helper' = @(
        $transportCascadeStageScript,
        'greenvpn_selective_routing.ps1'
    )
    'Windows public installer audits selective helper' = @(
        $publicInstallerAuditScript,
        'tools/greenvpn_selective_routing.ps1',
        'tools/greenvpn_standby_probe.ps1',
        'Selective application routing is not supported by `$protocol.'
    )
    'Windows selective policy test is bounded and fail-closed' = @(
        $transportSelectiveRoutingTestScript,
        'GreenVpnSelectiveRoutingTest_',
        'Unsafe selective-routing test path',
        'privateCidrRejected',
        'defaultRoutesRemoved'
    )
}
foreach ($check in $transportSelectiveRoutingChecks.GetEnumerator()) {
    $source = [string]$check.Value[0]
    $missing = @(
        $check.Value[1..($check.Value.Count - 1)] |
            Where-Object { -not $source.Contains([string]$_) }
    )
    if ($missing.Count -eq 0) {
        Add-Pass "$($check.Key) markers present"
    }
    else {
        Add-Error "$($check.Key) missing marker(s): $($missing -join ', ')"
    }
}

foreach ($scriptPath in @(
    $transportPreviewVpnTaskPath,
    $windowsStandbyProbePath,
    $windowsStandbyResultContractTestPath,
    $transportSelectiveRoutingPath,
    $transportSelectiveRoutingTestPath,
    $transportCascadeStagePath,
    $publicInstallerAuditPath
)) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Add-Error "Windows cascade parser errors in ${scriptPath}: $($parseErrors[0].ToString())"
    }
    else {
        Add-Pass "Windows cascade parser check passed: $scriptPath"
    }
}

try {
    & $windowsStandbyResultContractTestPath -ProjectRoot $ProjectRoot | Out-Null
    Add-Pass 'Windows standby probe fails closed and recovers from transient cleanup races'
}
catch {
    Add-Error "Windows standby result contract test failed: $($_.Exception.Message)"
}

$windowsRuntimeFailoverChecks = [ordered]@{
    'Windows runtime failover policy' = @(
        $transportPreviewPolicy,
        'greenVpnRuntimeFailoverFailureThreshold = 2',
        '(isAndroid || isWindows)',
        'greenVpnNextRuntimeFailoverFailureCount',
        'greenVpnShouldTriggerRuntimeFailover',
        'greenVpnShouldRecoverUnexpectedWindowsDisconnect'
    )
    'Windows runtime failover tests' = @(
        $transportPreviewPolicyTest,
        'runtime failover requires two consecutive unhealthy checks',
        'Windows unexpected tunnel loss stays armed for runtime recovery',
        'persisted runtime route ids are strictly normalized',
        'Windows foreground connect prefers an exact cached route',
        "candidateProtocol: 'amneziawg'",
        'isWindows: true'
    )
    'Windows background standby policy and tests' = @(
        ($transportPreviewPolicy + "`n" + $transportPreviewPolicyTest),
        'greenVpnStandbyConfigTtl = Duration(hours: 6)',
        'greenVpnStandbyProbeTtl = Duration(minutes: 10)',
        'greenVpnStandbyConfigTimestampTolerance = Duration(seconds: 1)',
        'GreenVpnStandbyRouteProof',
        'isFreshForPreparedConfig',
        'greenVpnWindowsRecoveryCandidates',
        'verifiedNotAfter:',
        'Windows recovery uses only candidates proven before the cutoff',
        'fresh standby proof leads only when caller opts into recovery order',
        'standby config refresh is bounded by a six hour TTL'
    )
    'Windows background standby lifecycle is post-connect only' = @(
        $main,
        '_runWindowsStandbyCycle',
        'unawaited(_runWindowsStandbyCycle(server, epoch))',
        '_windowsRuntimeRecoveryRunning &&',
        'leftHasFreshStandbyProof:',
        '_cancelWindowsStandbyProbe',
        "stage: 'standby_probe'"
    )
    'Windows privileged standby endpoint is authenticated and cancellable' = @(
        ($serviceSource + "`n" + $main + "`n" + $runtimeConfig),
        'path == "/standby/probe"',
        'path == "/standby/cancel"',
        'RequestStandbyProbeCancellation',
        'CancelStandbyProbeAndWait',
        'RunTaskAction(L"ProbeStandby", 60000, true)',
        'probeStandby()',
        'cancelStandbyProbe()',
        'standby-probe-request.json'
    )
    'Windows local service stays responsive during long privileged actions' = @(
        $serviceSource,
        'DWORD WINAPI HttpClientThread',
        'DispatchClientRequest(client)',
        'CreateThread(nullptr, 0, HttpClientThread',
        'InterlockedIncrement(&g_active_client_workers)',
        'kMaxConcurrentLocalClients = 32',
        'SO_RCVTIMEO',
        'SO_SNDTIMEO'
    )
    'Windows standby probe is route-isolated and fully reversible' = @(
        $windowsStandbyProbeScript,
        '$ProbeEndpointRouteMetric = 42739',
        "-DestinationPrefix '0.0.0.0/0'",
        'Add-ProbeEndpointBypassRoute',
        'Remove-ProbeEndpointBypassRoutes',
        'Remove-AllProbeEndpointBypassRoutes',
        'Test-ProbeEndpointBypassRoutesRemoved',
        'Test-AllProbeEndpointBypassRoutesRemoved',
        'foreach ($route in [object[]]$bypassRoutes)',
        'Stop-StaleProbeProcesses',
        'Get-Service -Name ([string]$entry.service)',
        '$p.WaitForExit(8000)',
        '$install.WaitForExit(12000)',
        "AllowedIPs = `$ProbeTarget/32",
        'latest-handshakes',
        'https://www.youtube.com/generate_204',
        '$result.cleanupOk',
        '$result.cleanupErrors',
        '$cleanupAttempt -le 4',
        'cleanup retry attempt=',
        'try { Write-ProbeResult } catch',
        'finally'
    )
    'Windows standby wrapper guarantees failure accounting and cleanup' = @(
        $transportPreviewVpnTaskScript,
        'Remove-StandbyProbeFallbackArtifacts',
        'Write-StandbyProbeFallbackResult',
        "-ErrorCode 'probe_wrapper_failed'",
        '$StandbyProbeEndpointRouteMetric = 42739',
        'standby probe wrapper fallback cleanupOk='
    )
    'Windows installer packages standby probe and closes tray gracefully' = @(
        $installer,
        'tools\greenvpn_standby_probe.ps1',
        'Stop-GreenVpnUiGracefully',
        "@('--shutdown-existing', '--background')"
    )
    'Windows tray identity is stable and restart-safe' = @(
        ($runnerSource + "`n" + $runnerMainSource),
        'NIF_GUID',
        'kTrayIconGuid',
        'TaskbarCreated',
        'Shell_NotifyIconW(NIM_DELETE',
        'Shell_NotifyIconW(NIM_ADD',
        'GREENVPN_TRAY_DIAGNOSTIC_PATH',
        'WriteTrayDiagnostic("add"',
        'WriteTrayDiagnostic("delete_shutdown"',
        'tray_stale_cleanup_done_',
        'kTrayRetryTimerId',
        'kTrayRetryDelayMs = 1000',
        'kTrayRetryMaxAttempts = 15',
        'ScheduleTrayIconRetry',
        'KillTimer',
        'CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName)',
        'WaitForSingleObject(single_instance_mutex, 0)',
        'WAIT_ABANDONED',
        'owns_single_instance_mutex',
        '--shutdown-existing',
        'kGreenVpnShutdownMessage'
    )
    'Windows runtime failover lifecycle' = @(
        $main,
        '_pollWindowsRuntimeFailover',
        '_greenVpnAuthLogWriteTail',
        'appendGreenVpnAuthLogLine',
        "appendGreenVpnAuthLogLine('UI `$message')",
        'reason=runtime_failover_armed',
        'windows runtime failover clean-down confirmed',
        'disconnectResult?.ok == true && !stillConnected',
        '_disarmWindowsRuntimeFailover(reason: ''user_disconnect'')',
        'starting ordered reconnect'
    )
    'Windows runtime failover restart restore' = @(
        $main,
        'writeManagedRouteId',
        'readManagedRouteId',
        '_restoreWindowsRuntimeFailoverIfPossible',
        'missing_route_metadata',
        '_socialOnlyPreferenceRequested'
    )
    'Windows cached fallback keeps route metadata aligned' = @(
        $main,
        'await _cfg.writeManagedProtocol(effectiveServer.protocolCode)',
        'effectiveServer.isAuto ? '''' : effectiveServer.id'
    )
    'Windows all-transport clean-down' = @(
        $main,
        '_waitForServiceCleanDown',
        'dnsttClientState',
        'componentStateKeys'
    )
    'Windows status exposes every managed transport' = @(
        $serviceSource,
        'hysteriaClientState',
        'vlessClientState',
        'naiveClientState',
        'dnsttClientState',
        'processRouterState'
    )
    'Windows routing mode UI is authoritative and fail-closed' = @(
        ($main + "`n" + $windowsVpnStatusPolicy),
        'greenVpnWindowsRoutingModeIsConfirmed',
        'greenVpnAuthoritativeActiveRoutingMode',
        'externalVpnStateKnown',
        '_restoreRoutingPreferenceAfterFailure',
        '_failClosedRoutingPreference',
        'greenVpnWindowsUiProtectionIsConfirmed',
        '_windowsFullTunnelDataPlaneConfirmed',
        'windowsProtectionConfirmed'
    )
    'Windows service reports active mode and competing VPN state' = @(
        $serviceSource,
        'kRuntimeRegistryPath',
        'ReadRuntimeRegistryDword',
        'QueryRunningCompetingVpnState',
        'GREENVPN_RUNTIME_TUNNEL_NAME_W L"StandbyProbe"',
        'externalVpnActive',
        'externalVpnStateKnown',
        'processRouterRequired',
        'processRouterRequirementKnown',
        'RuntimeStateGeneration',
        'runtimeStateConsistent'
    )
    'Windows privileged tasks commit a protected active mode marker' = @(
        ($vpnTaskScript + "`n" + $transportPreviewVpnTaskScript + "`n" + $transportSelectiveRoutingScript),
        'Write-GreenActiveRoutingMode',
        'Write-GreenPrivilegedRuntimeValue',
        'Remove-ItemProperty',
        '$PrivilegedRuntimeRegistryPath',
        'HKLM:\SOFTWARE\GreenVPN\Runtime',
        'ProcessRouterPid',
        'ProcessRouterRequired',
        'Confirm-GreenProcessRouterRuntimeContract',
        'Start-GreenRuntimeStateTransition',
        'Complete-GreenRuntimeStateTransition',
        'RuntimeStateGeneration',
        "Remove-GreenPrivilegedRuntimeValue -Name 'ActiveRoutingMode'",
        "ValidateSet('full', 'applications')",
        'Remove-GreenPrivilegedRuntimeValue'
    )
    'Windows runtime failover physical proof is reversible' = @(
        $windowsRuntimeFailoverPhysicalTestScript,
        'GreenVPNPublicRuntimeFailoverSmokeFailsafe',
        'Test-InstalledPayload',
        'UseExistingExactInstall',
        '$expectedDisplayVersion',
        'Installed file version mismatch:',
        'Installed display version mismatch:',
        "tools\greenvpn_vpn_task.ps1",
        'windows runtime failover restored source=',
        'Stop-ActiveTransportEngine',
        'Wait-AllGreenComponentsStopped',
        'processRouterState',
        'AfterLine',
        'Test-ExpectedRouteEgress',
        'Get-RouteProtectionEvidence',
        'Invoke-DirectDnsLeakProbe',
        'Get-ProtectedProgramDataEvidence',
        'Test-NoBroadAcl',
        'protectedProgramData',
        'overlapObserved',
        'prevalidatedStandbyUsed',
        'allEligibleAccounted',
        '$standbyConfigTimestampToleranceMilliseconds = 1000',
        'configTimestampDeltaMs',
        '$Matches.ContainsKey(''protocol'')',
        'failureLocation',
        'standbyArtifactsClean',
        'standbyCancelAccepted',
        'function Wait-StandbyCleanupEvidence',
        'standbyCleanupEvidence',
        'requestRemovedByHarness',
        "Invoke-GreenLocal -Method POST -Path '/standby/cancel'",
        'Wait-StandbyCleanupEvidence -TimeoutSeconds 30',
        'originalEgressRestored',
        'finally'
    )
    'Windows fast-cache latency proof uses private state and stop-before-disconnect cleanup' = @(
        $windowsConnectLatencyPhysicalTestScript,
        '$UserStateRoot',
        '$ProcessName',
        '$FailsafeTaskName',
        '$resolvedProcessName',
        "Join-Path `$env:APPDATA 'GreenVPN\state'",
        'lastSuccessfulRouteProtocol',
        'lastSuccessfulRouteAt',
        'Stop-GreenApp',
        'UIAutomationClient',
        'Invoke-GreenConnectAutomationElement',
        'Wait-GreenConnectAcknowledgement',
        'GetForegroundWindow() == hWnd',
        'BringWindowToTop(hWnd)',
        'ChildWindowFromPointEx',
        'PostCoordinateClick',
        "'uia_invoke'",
        "'coordinate_click'",
        'Cached connection exceeded',
        'Second connection did not prioritize the exact last successful route'
    )
    'Windows autonomous fast-cache release smoke has exact artifact and recovery gates' = @(
        $windowsFastCacheReleaseSmokeScript,
        '$ExpectedSha256',
        '$ExpectedSizeBytes',
        '$ExpectedFileVersion',
        '-UseUiAutomationAction',
        '-ExpectCompetingVpn',
        '-StopGreenUi',
        '$DeadmanProcessId',
        'deadmanStopped',
        'installedTaskContractConfirmed',
        'privilegedTakeoverConfirmed',
        'exact-route timing contract'
    )
    'Windows autonomous standby and tray release smoke has exact, delayed, and reversible gates' = @(
        $windowsStandbyTrayReleaseSmokeScript,
        '$ExpectedInstallerSha256',
        '$ExpectedInstallerSize',
        '$InitialDelaySeconds = 90',
        'Assert-ReadOnlySafeBaseline',
        'Write-RunnerLog "waiting $InitialDelaySeconds seconds before installation or network transitions"',
        'Start-DeadmanRecovery',
        'RequireStandbyProof',
        'prevalidatedStandbyUsed',
        '$trayDiagnosticsPath',
        '$env:GREENVPN_TRAY_DIAGNOSTIC_PATH',
        'Assert-TrayProcessLifecycle',
        'successful NIM_ADD events; expected exactly one.',
        'forcedPredecessorRecoveryConfirmed',
        'standbyBypassRoutesAbsent',
        'Invoke-FinalRecovery',
        'deadmanStopped'
    )
    'Windows standby and tray launcher requests one exact elevated detached runner' = @(
        $windowsStandbyTrayReleaseLauncherScript,
        '$ExpectedInstallerSha256',
        '$ExpectedInstallerSize',
        '$ExpectedVersion',
        '$InitialDelaySeconds = 90',
        'windows-standby-tray-launcher-status.json',
        "Write-LauncherStatus -Phase 'uac_requested'",
        "-Verb RunAs",
        "Write-LauncherStatus -Phase 'runner_started'",
        'Exact installer SHA-256 or size mismatch.'
    )
    'Windows emergency smoke recovery stops UI before disconnect' = @(
        $windowsSmokeNetworkRestoreScript,
        '[switch]$StopGreenUi',
        '$AppPath',
        '$ProcessName',
        '$ProgramDataRoot',
        '$LocalServicePort',
        '$ManagedTunnelName',
        'Stop-GreenVpnUi',
        'greenUiStopped',
        'greenComponentsStopped',
        'standbyProbeServicesStopped',
        'standbyBypassRoutesAbsent',
        'externalVpnRunning',
        'youtube'
    )
    'Windows Fusion paid-beta acceptance is exact, isolated, delayed, and reversible' = @(
        $windowsFusionPaidBetaAcceptanceSmokeScript,
        '$ExpectedInstallerSha256',
        '$ExpectedInstallerSize',
        '$ExpectedAppSha256',
        '$ExpectedAppSize',
        '$CandidateSourceCommit',
        '$InitialDelaySeconds = 90',
        "'-ExecutionPolicy', 'RemoteSigned'",
        "'C:\Program Files\Green VPN Beta'",
        "'C:\ProgramData\BlueVPNBeta'",
        '$LocalServicePort = 48738',
        "'greenvpn_beta'",
        "'GreenVPNBetaConnectLatencySmokeFailsafe'",
        'Assert-ReadOnlyBaseline',
        'waiting $InitialDelaySeconds seconds before installation or network transitions',
        'Start-DeadmanRecovery',
        'Invoke-FusionUiAudit',
        'visualContractPassed',
        'distinctColorCount',
        'greenPixelCount',
        'manualVisualReviewRequired',
        "[string]`$semanticEntries[0].name -eq 'FLUTTERVIEW'",
        'windows-fusion-paid-beta-main.png',
        'ArtifactRoot contains stale acceptance evidence; use a new unique path.',
        'Invoke-PhysicalConnect -ReportPath $freshReportPath',
        "PSObject.Properties['cachedRouteConfirmed']",
        '-RequireCachedRoute',
        'privilegedTakeoverConfirmed',
        'exactInstallRetained',
        'Invoke-FinalRecovery',
        'deadmanStopped'
    )
    'Windows Fusion paid-beta launcher requests one elevated delayed runner' = @(
        $windowsFusionPaidBetaAcceptanceLauncherScript,
        'run_windows_fusion_paid_beta_acceptance_smoke.ps1',
        '$InitialDelaySeconds = 90',
        'windows-fusion-paid-beta-launcher-status.json',
        "Write-Status -Phase 'uac_requested'",
        '-Verb RunAs',
        "'-ExecutionPolicy', 'RemoteSigned'",
        "Write-Status -Phase 'runner_started'",
        'A Fusion paid-beta acceptance runner is already active.'
    )
    'Windows Fusion mode reconciliation is exact, isolated, delayed, and reversible' = @(
        $windowsModeReconcileReleaseSmokeScript,
        '$ExpectedInstallerSha256',
        '$ExpectedInstallerSize',
        '$ExpectedAppSha256',
        '$ExpectedAppSoSha256',
        '$ExpectedServiceSha256',
        '$CandidateSourceCommit',
        '$InitialDelaySeconds = 90',
        'Assert-ReadOnlySafeBaseline',
        'waiting $InitialDelaySeconds seconds before installation or network transitions',
        'Start-DeadmanRecovery',
        'Initialize-IsolatedUserState',
        '$env:GREENVPN_FUSION_UI_DIAGNOSTIC_PATH',
        "[string]`$state.statusKey -eq 'external_vpn'",
        "[string]`$state.statusKey -eq 'protected_full'",
        "'protected_selected'",
        'processRouterRequired',
        'Assert-RuntimeMode',
        'Capture-RuntimeEvidence',
        'windows-mode-runtime-evidence.json',
        'processRouterRequirementValueKind',
        'runtimeStateGenerationValueKind',
        'runtimeStateGenerationEven',
        'runtimeStateConsistent',
        'processRouterPidValueKind',
        'Get-EgressFingerprint',
        'originalStateUnmodified',
        'exactInstallRetained',
        'Invoke-FinalRecovery',
        'deadmanStopped',
        'windows-mode-reconcile-autonomous-summary.json'
    )
    'Windows Fusion mode reconciliation launcher requests one exact elevated runner' = @(
        $windowsModeReconcileReleaseLauncherScript,
        'run_windows_mode_reconcile_release_smoke.ps1',
        '$ExpectedInstallerSha256',
        '$ExpectedAppSoSha256',
        '$ExpectedServiceSha256',
        '$InitialDelaySeconds = 90',
        'windows-mode-reconcile-launcher-status.json',
        "Write-LauncherStatus -Phase 'uac_requested'",
        '-Verb RunAs',
        "Write-LauncherStatus -Phase 'runner_started'",
        'The exact mode runner is already active'
    )
    'Windows dnstt service status' = @(
        $serviceSource,
        'kDnsttPidPath',
        'tools\\dnstt\\dnstt-client-windows-amd64.exe',
        'managed_protocol == "dnstt"',
        'dnsttClientState',
        'dnsttTunState'
    )
}
foreach ($check in $windowsRuntimeFailoverChecks.GetEnumerator()) {
    $source = [string]$check.Value[0]
    $missing = @(
        $check.Value[1..($check.Value.Count - 1)] |
            Where-Object { -not $source.Contains([string]$_) }
    )
    if ($missing.Count -eq 0) {
        Add-Pass "$($check.Key) markers present"
    }
    else {
        Add-Error "$($check.Key) missing marker(s): $($missing -join ', ')"
    }
}
if ($runnerSource.Contains('Shell_NotifyIconGetRect')) {
    Add-Error 'Windows tray lifecycle must not infer registration from icon geometry.'
} else {
    Add-Pass 'Windows tray lifecycle trusts NIM_ADD and does not loop on icon geometry'
}
if ($windowsStandbyTrayReleaseSmokeScript.Contains('Shell_NotifyIconGetRect')) {
    Add-Error 'Windows tray smoke must use app-owned lifecycle diagnostics, not icon geometry.'
} else {
    Add-Pass 'Windows tray smoke uses app-owned lifecycle diagnostics'
}

$standbyInitialReadOnlyIndex = $windowsStandbyTrayReleaseSmokeScript.LastIndexOf(
    "Assert-ReadOnlySafeBaseline -Label 'Initial read-only baseline'"
)
$standbyInitialDelayIndex = $windowsStandbyTrayReleaseSmokeScript.LastIndexOf(
    'Start-Sleep -Seconds $InitialDelaySeconds'
)
$standbyDeadmanStartIndex = $windowsStandbyTrayReleaseSmokeScript.LastIndexOf(
    '$deadman = Start-DeadmanRecovery'
)
$standbyFirstMutableBaselineIndex = $windowsStandbyTrayReleaseSmokeScript.LastIndexOf(
    "Assert-SafeBaseline -Label 'Delayed baseline'"
)
if (
    $standbyInitialReadOnlyIndex -lt 0 -or
    $standbyInitialDelayIndex -le $standbyInitialReadOnlyIndex -or
    $standbyDeadmanStartIndex -le $standbyInitialDelayIndex -or
    $standbyFirstMutableBaselineIndex -le $standbyDeadmanStartIndex
) {
    Add-Error 'Windows standby/tray release smoke must delay before mutation and start deadman before its first mutable baseline.'
}
if ($windowsStandbyTrayReleaseSmokeScript -match '(?<!@)\(Get-ExactAppProcesses\)\.Count') {
    Add-Error 'Windows standby/tray release smoke must array-wrap process enumeration before reading Count.'
} else {
    Add-Pass 'Windows standby/tray release smoke array-wraps process enumeration before reading Count'
}

$fusionPaidBetaInitialReadOnlyIndex =
    $windowsFusionPaidBetaAcceptanceSmokeScript.LastIndexOf(
        "-Label 'Initial read-only baseline'"
    )
$fusionPaidBetaInitialDelayIndex =
    $windowsFusionPaidBetaAcceptanceSmokeScript.LastIndexOf(
        'Start-Sleep -Seconds $InitialDelaySeconds'
    )
$fusionPaidBetaDeadmanStartIndex =
    $windowsFusionPaidBetaAcceptanceSmokeScript.LastIndexOf(
        '$deadman = Start-DeadmanRecovery'
    )
$fusionPaidBetaInstallIndex =
    $windowsFusionPaidBetaAcceptanceSmokeScript.LastIndexOf(
        '$summary.installer = Install-ExactCandidate'
    )
if (
    $fusionPaidBetaInitialReadOnlyIndex -lt 0 -or
    $fusionPaidBetaInitialDelayIndex -le $fusionPaidBetaInitialReadOnlyIndex -or
    $fusionPaidBetaDeadmanStartIndex -le $fusionPaidBetaInitialDelayIndex -or
    $fusionPaidBetaInstallIndex -le $fusionPaidBetaDeadmanStartIndex
) {
    Add-Error 'Windows Fusion paid-beta smoke must delay before mutation and start deadman before installation.'
} else {
    Add-Pass 'Windows Fusion paid-beta smoke delays before mutation and starts deadman before installation'
}
if ($windowsFusionPaidBetaAcceptanceSmokeScript.Contains('-FailsafeProcessId')) {
    Add-Error 'Windows Fusion paid-beta smoke must keep its independent deadman alive through child physical tests.'
} else {
    Add-Pass 'Windows Fusion paid-beta smoke keeps its independent deadman outside child physical tests'
}

$modeReconcileInitialReadOnlyIndex =
    $windowsModeReconcileReleaseSmokeScript.LastIndexOf(
        'Assert-ReadOnlySafeBaseline `'
    )
$modeReconcileInitialDelayIndex =
    $windowsModeReconcileReleaseSmokeScript.LastIndexOf(
        'Start-Sleep -Seconds $InitialDelaySeconds'
    )
$modeReconcileDeadmanStartIndex =
    $windowsModeReconcileReleaseSmokeScript.LastIndexOf(
        '$deadman = Start-DeadmanRecovery'
    )
$modeReconcileFirstMutableIndex =
    $windowsModeReconcileReleaseSmokeScript.LastIndexOf(
        "Assert-MutableSafeBaseline -Label 'Delayed mutable baseline'"
    )
if (
    $modeReconcileInitialReadOnlyIndex -lt 0 -or
    $modeReconcileInitialDelayIndex -le $modeReconcileInitialReadOnlyIndex -or
    $modeReconcileDeadmanStartIndex -le $modeReconcileInitialDelayIndex -or
    $modeReconcileFirstMutableIndex -le $modeReconcileDeadmanStartIndex
) {
    Add-Error 'Windows Fusion mode reconciliation must delay before mutation and start deadman before its first mutable baseline.'
}
else {
    Add-Pass 'Windows Fusion mode reconciliation delays before mutation and starts deadman before its first mutable baseline'
}

foreach ($parserCheck in @(
    [pscustomobject]@{
        Label = 'Windows runtime failover physical test'
        Path = $windowsRuntimeFailoverPhysicalTestPath
    },
    [pscustomobject]@{
        Label = 'Windows connect latency physical test'
        Path = $windowsConnectLatencyPhysicalTestPath
    },
    [pscustomobject]@{
        Label = 'Windows autonomous fast-cache release smoke'
        Path = $windowsFastCacheReleaseSmokePath
    },
    [pscustomobject]@{
        Label = 'Windows autonomous standby and tray release smoke'
        Path = $windowsStandbyTrayReleaseSmokePath
    },
    [pscustomobject]@{
        Label = 'Windows standby and tray release launcher'
        Path = $windowsStandbyTrayReleaseLauncherPath
    },
    [pscustomobject]@{
        Label = 'Windows emergency smoke recovery'
        Path = $windowsSmokeNetworkRestorePath
    },
    [pscustomobject]@{
        Label = 'Windows Fusion paid-beta acceptance smoke'
        Path = $windowsFusionPaidBetaAcceptanceSmokePath
    },
    [pscustomobject]@{
        Label = 'Windows Fusion paid-beta acceptance launcher'
        Path = $windowsFusionPaidBetaAcceptanceLauncherPath
    },
    [pscustomobject]@{
        Label = 'Windows Fusion mode reconciliation smoke'
        Path = $windowsModeReconcileReleaseSmokePath
    },
    [pscustomobject]@{
        Label = 'Windows Fusion mode reconciliation launcher'
        Path = $windowsModeReconcileReleaseLauncherPath
    },
    [pscustomobject]@{
        Label = 'Fusion production promotion preparer'
        Path = $fusionProductionPromotionPath
    },
    [pscustomobject]@{
        Label = 'Public-product backend bundle preparer'
        Path = $publicProductBackendBundlePath
    }
)) {
    if (Test-Path -LiteralPath $parserCheck.Path) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $parserCheck.Path,
            [ref]$tokens,
            [ref]$parseErrors
        ) | Out-Null
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Add-Error "$($parserCheck.Label) has parser errors: $($parseErrors[0].ToString())"
        }
        else {
            Add-Pass "$($parserCheck.Label) PowerShell parser check passed"
        }
    }
}

if ($transportPreviewVpnTaskScript.Contains("'*S-1-5-11:(OI)(CI)M'")) {
    Add-Error 'Windows transport preview task must not grant broad Authenticated Users write access'
}
else {
    Add-Pass 'Windows transport preview task does not grant broad Authenticated Users write access'
}

foreach ($fragment in @(
    '$RoutingModePath',
    '$RoutingAppsPath'
)) {
    if ($transportPreviewVpnTaskScript.Contains($fragment)) {
        Add-Pass "Windows privileged routing input ACL marker present: $fragment"
    }
    else {
        Add-Error "Windows privileged routing input ACL marker missing: $fragment"
    }
}

foreach ($forbidden in @(
    "'*S-1-5-11:(OI)(CI)(M)'",
    "'*S-1-5-11:(M)'",
    "'*S-1-5-11:(OI)(CI)M'",
    "'*S-1-5-11:M'"
)) {
    if ($main.Contains($forbidden)) {
        Add-Error "Windows client still grants broad shared-state write access: $forbidden"
    }
    else {
        Add-Pass "Windows client excludes broad shared-state write marker: $forbidden"
    }
}

foreach ($fragment in @(
    '_prepareProtectedSharedPath',
    "'*S-1-1-0'",
    "'*S-1-5-11'",
    "'*S-1-5-32-545'",
    "'*`$userSid:(OI)(CI)M'",
    "'*`$userSid:M'",
    'repairSharedStateFileAcl',
    'on FileSystemException',
    "WindowsLocalSecurity.prepareSharedConfigDirectory(f.parent.path)",
    "WindowsLocalSecurity.prepareSharedConfigFile(f.path)"
)) {
    if ($main.Contains($fragment)) {
        Add-Pass "Windows protected client ACL marker present: $fragment"
    }
    else {
        Add-Error "Windows protected client ACL marker missing: $fragment"
    }
}

foreach ($fragment in @(
    "ExpectedEgress = '5.129.216.42'",
    "--socks5-hostname",
    'routeSignatureUnchanged',
    'warpServiceStateUnchanged',
    'listenerRemoved',
    '94F99801C665D29FC071624663C6F7BFA59E8D5EFAA84CD08EF5EBB18B46CB62'
)) {
    if ($naiveClientSmokeScript.Contains($fragment)) {
        Add-Pass "Windows Naive HTTPS non-disruptive smoke marker present: $fragment"
    }
    else {
        Add-Error "Windows Naive HTTPS non-disruptive smoke marker missing: $fragment"
    }
}

if (Test-Path -LiteralPath $transportPreviewVpnTaskPath) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($transportPreviewVpnTaskPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Add-Error "Windows transport preview task has PowerShell parser errors: $($parseErrors[0].ToString())"
    }
    else {
        Add-Pass 'Windows transport preview task PowerShell parser check passed'
    }
}

$transportPreviewInstallFragments = @(
    "Join-Path `$env:ProgramFiles 'Green VPN Transport Preview'",
    "Join-Path `$env:LOCALAPPDATA 'Programs\Green VPN Transport Preview'",
    "'*S-1-5-18:(OI)(CI)F'",
    "'*S-1-5-32-544:(OI)(CI)F'",
    "'*S-1-5-32-545:(OI)(CI)RX'",
    "/remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' /T /C",
    "('*' + `$UserSid + ':(OI)(CI)M')",
    "'tools\hysteria2\hysteria-windows-amd64.exe'",
    "'tools\hysteria2\hev-socks5-tunnel.exe'",
    "'tools\greenvpn_hysteria2_watchdog.ps1'",
    "'tools\greenvpn_naive_https_watchdog.ps1'",
    "'tools\naive-https\naive.exe'",
    "'tools\naive-https\hev-socks5-tunnel.exe'",
    '-Action Disconnect',
    "Set-PreviewAcl -UserSid `$installingUserSid",
    'Remove-PreviewDirectoryWithRetry -Path $LegacyInstallRoot',
    'Stop-ExitedPreviewServiceProcess'
)
foreach ($fragment in $transportPreviewInstallFragments) {
    if ($transportPreviewInstallScript.Contains($fragment)) {
        Add-Pass "Windows transport preview protected install marker present: $fragment"
    }
    else {
        Add-Error "Windows transport preview protected install marker missing: $fragment"
    }
}

if ($transportPreviewInstallScript.Contains("`$InstallRoot = Join-Path `$env:LOCALAPPDATA")) {
    Add-Error 'Windows transport preview privileged service must not run from a user-writable LocalAppData path'
}
else {
    Add-Pass 'Windows transport preview privileged service is not installed under LocalAppData'
}

foreach ($scriptPath in @($transportPreviewInstallPath, $transportPreviewUninstallPath)) {
    if (Test-Path -LiteralPath $scriptPath) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Add-Error "Windows transport preview installer parser errors in $scriptPath`: $($parseErrors[0].ToString())"
        }
        else {
            Add-Pass "Windows transport preview installer parser check passed: $scriptPath"
        }
    }
}

foreach ($fragment in @(
    'GREENVPN_HYSTERIA2_PREVIEW_ENABLED=true',
    'BCD3865B09BE2E5CC18D117DCF3AD687D1E6E27B0B050376B9CF4EA251B64D6F',
    '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E',
    '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18',
    'HYSTERIA_APP_MIT.txt',
    'HEV_SOCKS5_TUNNEL_MIT.txt',
    'HEV_LWIP_BSD.txt',
    'HEV_WINTUN_PREBUILT_BINARY_LICENSE.txt'
)) {
    if ($transportPreviewBuildScript.Contains($fragment)) {
        Add-Pass "Windows Hysteria2 preview build marker present: $fragment"
    }
    else {
        Add-Error "Windows Hysteria2 preview build marker missing: $fragment"
    }
}

foreach ($fragment in @(
    'GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED=true',
    '94F99801C665D29FC071624663C6F7BFA59E8D5EFAA84CD08EF5EBB18B46CB62',
    'NAIVEPROXY_BSD_3_CLAUSE.txt',
    'naiveproxy/releases/tag/v150.0.7871.63-1',
    "Join-Path `$toolsDir 'naive-https'",
    'greenvpn_naive_https_watchdog.ps1'
)) {
    if ($transportPreviewBuildScript.Contains($fragment)) {
        Add-Pass "Windows Naive HTTPS preview build marker present: $fragment"
    }
    else {
        Add-Error "Windows Naive HTTPS preview build marker missing: $fragment"
    }
}

foreach ($fragment in @(
    'greenvpn_selective_routing.ps1',
    "Join-Path `$toolsDir 'process-router'",
    'ProxyBridge_CLI.exe',
    'ProxyBridgeCore.dll',
    'WinDivert.dll',
    'WinDivert64.sys',
    'PROXYBRIDGE_LICENSE.txt',
    'WINDIVERT_LICENSE.txt',
    'THIRD_PARTY_NOTICES.txt'
)) {
    if ($transportPreviewBuildScript.Contains($fragment)) {
        Add-Pass "Windows transport preview dependency marker present: $fragment"
    }
    else {
        Add-Error "Windows transport preview dependency marker missing: $fragment"
    }
}

foreach ($fragment in @(
    'Test-ExactProcess',
    '$RouteMetric = 42734',
    '$EndpointRouteMetric = 42731',
    "[string]`$state.endpoint -match '^\d{1,3}(?:\.\d{1,3}){3}$'",
    'Remove-ManagedRoutes',
    'Remove-ManagedEndpointRoute',
    'naive-https-client.runtime.json',
    'naive-https-hev.runtime.yaml'
)) {
    if ($naiveWatchdogScript.Contains($fragment)) {
        Add-Pass "Windows Naive HTTPS watchdog marker present: $fragment"
    }
    else {
        Add-Error "Windows Naive HTTPS watchdog marker missing: $fragment"
    }
}

foreach ($fragment in @(
    'kNaivePidPath',
    'kNaiveHevPidPath',
    'tools\\naive-https\\naive.exe',
    'managed_protocol == "naive_https"',
    'GreenVPNNaiveHttpsPreview',
    'naiveClientState',
    'naiveTunState'
)) {
    if ($serviceSource.Contains($fragment)) {
        Add-Pass "Windows Naive HTTPS service status marker present: $fragment"
    }
    else {
        Add-Error "Windows Naive HTTPS service status marker missing: $fragment"
    }
}

foreach ($fragment in @(
    'Test-ExactProcess',
    'ExecutablePath',
    '$RouteMetric = 42732',
    '$EndpointRouteMetric = 42731',
    "@('0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1')",
    'Remove-ManagedRoutes',
    'Remove-ManagedEndpointRoute'
)) {
    if ($hysteriaWatchdogScript.Contains($fragment)) {
        Add-Pass "Windows Hysteria2 watchdog marker present: $fragment"
    }
    else {
        Add-Error "Windows Hysteria2 watchdog marker missing: $fragment"
    }
}

foreach ($fragment in @(
    "ExpectedCanaryEgress = '5.129.216.42'",
    "CompetingServiceName = 'AmneziaWGTunnel`$device20_full'",
    "Wait-HysteriaState -Running `$true",
    'endpoint route recursed into the preview adapter',
    'watchdogCleanupPassed',
    'restoredOriginalEgress',
    "Invoke-PreviewApi -Method POST -Path '/disconnect'"
)) {
    if ($hysteriaPhysicalTestScript.Contains($fragment)) {
        Add-Pass "Windows Hysteria2 physical smoke marker present: $fragment"
    }
    else {
        Add-Error "Windows Hysteria2 physical smoke marker missing: $fragment"
    }
}

foreach ($check in @(
    [pscustomobject]@{
        Label = 'VLESS REALITY watchdog'
        Source = $vlessWatchdogScript
        Fragments = @('Test-ExactProcess', '$RouteMetric = 42733', 'Remove-ManagedRoutes', 'Remove-ManagedEndpointRoute')
    },
    [pscustomobject]@{
        Label = 'VLESS REALITY physical smoke'
        Source = $vlessPhysicalTestScript
        Fragments = @("ExpectedCanaryEgress = '5.129.216.42'", 'localSocksEgress', 'watchdogCleanupPassed', 'restoredOriginalEgress')
    },
    [pscustomobject]@{
        Label = 'Naive and dnstt full-tunnel physical smoke'
        Source = $managedSocksTunPhysicalTestScript
        Fragments = @(
            "[ValidateSet('naive_https', 'dnstt')]",
            "CompetingServiceName = 'AmneziaWGTunnel`$device20_full'",
            'endpoint route recursed into the preview adapter',
            'localSocksEgress',
            'Failed to protect the temporary dnstt curl config.',
            'dnsProbeOk',
            'watchdogCleanupPassed',
            'restoredOriginalEgress'
        )
    },
    [pscustomobject]@{
        Label = 'Naive HTTPS physical smoke wrapper'
        Source = $naivePhysicalTestScript
        Fragments = @('-Protocol naive_https', 'transport_canary_naive_20260712', 'ExpectedCanaryEgress')
    },
    [pscustomobject]@{
        Label = 'dnstt watchdog'
        Source = $dnsttWatchdogScript
        Fragments = @('Test-ExactProcess', '$RouteMetric = 42735', 'Remove-ManagedRoutes', 'Remove-ManagedEndpointRoute')
    },
    [pscustomobject]@{
        Label = 'dnstt physical smoke wrapper'
        Source = $dnsttPhysicalTestScript
        Fragments = @('-Protocol dnstt', 'transport_canary_dnstt_20260712', 'ExpectedCanaryEgress')
    },
    [pscustomobject]@{
        Label = 'transport cascade physical smoke'
        Source = $transportCascadePhysicalTestScript
        Fragments = @(
            'test_windows_awg2_preview_physical.ps1',
            'test_windows_hysteria2_preview_physical.ps1',
            'test_windows_vless_reality_preview_physical.ps1',
            'test_windows_naive_https_preview_physical.ps1',
            'test_windows_dnstt_preview_physical.ps1',
            'cleanAfterEveryTransition',
            'Assert-CleanTransitionState',
            'restoredOriginalEgress'
        )
    }
)) {
    foreach ($fragment in $check.Fragments) {
        if ($check.Source.Contains($fragment)) {
            Add-Pass "Windows $($check.Label) marker present: $fragment"
        }
        else {
            Add-Error "Windows $($check.Label) marker missing: $fragment"
        }
    }
}

foreach ($scriptPath in @(
    $transportPreviewBuildPath,
    $hysteriaWatchdogPath,
    $hysteriaPhysicalTestPath,
    $vlessWatchdogPath,
    $vlessPhysicalTestPath,
    $naiveWatchdogPath,
    $naiveClientSmokePath,
    $managedSocksTunPhysicalTestPath,
    $naivePhysicalTestPath,
    $dnsttWatchdogPath,
    $dnsttPhysicalTestPath,
    $transportCascadePhysicalTestPath
)) {
    if (Test-Path -LiteralPath $scriptPath) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Add-Error "Windows transport preview parser errors in ${scriptPath}: $($parseErrors[0].ToString())"
        }
        else {
            Add-Pass "Windows transport preview parser check passed: $scriptPath"
        }
    }
}

Write-Section "ANDROID HYSTERIA2 PREVIEW CHECKS"

foreach ($fragment in @('<issue id="PropertyEscape">', '<ignore path="local.properties" />')) {
    if ($androidLintConfig.Contains($fragment)) {
        Add-Pass "Android generated local.properties lint guard present: $fragment"
    }
    else {
        Add-Error "Android generated local.properties lint guard missing: $fragment"
    }
}
$androidHysteriaSourceChecks = [ordered]@{
    'Android settings conditional module' = @($androidSettings, 'GREENVPN_ANDROID_HYSTERIA2_PREVIEW_ENABLED', 'include(":hysteria_tunnel_preview")')
    'Android app conditional dependency' = @($androidAppBuild, 'GREENVPN_HYSTERIA2_PREVIEW_ENABLED', 'implementation(project(":hysteria_tunnel_preview"))')
    'Android Hysteria2 library build' = @($androidHysteriaBuild, 'jniLibs.keepDebugSymbols', 'testImplementation("junit:junit:4.13.2")')
    'Android Hysteria2 protected VPN service manifest' = @($androidHysteriaManifest, 'android.permission.FOREGROUND_SERVICE_SPECIAL_USE', 'android.permission.BIND_VPN_SERVICE', 'android:exported="false"', 'android:foregroundServiceType="specialUse"')
    'Android Hysteria2 debug-only receiver permission' = @($androidHysteriaDebugManifest, 'Hysteria2DebugReceiver', 'android.permission.DUMP')
    'Android Hysteria2 structured config validator' = @($androidHysteriaConfig, 'SafeConstructor(loaderOptions)', 'maxAliasesForCollections = 0', 'nestingDepthLimit = 24', 'Hysteria2 insecure TLS is forbidden', 'Hysteria2 Salamander obfuscation is required')
    'Android Hysteria2 managed lifecycle' = @($androidHysteriaService, 'context.noBackupFilesDir', 'source.delete()', 'nativeRunFdControl(fdSocket.canonicalPath)', 'addRoute("0.0.0.0", 0)', 'addRoute("::", 0)', 'process.destroyForcibly()', 'failClosed("Hysteria2 process stopped")', 'fun requestDisconnect(context: Context)', 'val preserveFailure = shouldPreserveFailure()')
    'Android Hysteria2 reconnect state reset' = @($androidHysteriaController, 'Hysteria2VpnService.prepareForConnect(context)', 'waitForState(context, "up", 25_000L)', 'state == "error" && expected != "down"')
    'Android Hysteria2 clean down wait' = @($androidHysteriaController, 'Hysteria2VpnService.requestDisconnect(context)', 'state == "error" && expected != "down"')
    'Android Hysteria2 FD protection bridge' = @($androidHysteriaBridge, 'SCM_RIGHTS', 'FD_CLOEXEC', 'chmod(path, 0600)', 'protectSocket')
    'Android Hysteria2 config unit tests' = @($androidHysteriaConfigTest, 'base config cannot define any local listener', 'insecure TLS is rejected', 'yaml aliases are rejected')
    'Android Hysteria2 audited dependency preparation' = @($androidHysteriaPrepareScript, 'HYSTERIA-NATIVE-MANIFEST.json', 'build_android_hysteria2_native.ps1', '$arguments.VerifyOnly = $true')
    'Android Hysteria2 reproducible native builder' = @($androidHysteriaNativeBuildScript, '$PinnedVersion = "app/v2.9.3"', '$PinnedCommit = "2d973f9513ef661d1922d6d14acb37945caef47d"', '$PinnedGoVersion = "go1.25.1"', '$PinnedNdkVersion = "28.2.13676358"', '"-Wl,-z,max-page-size=16384"', 'reproducibilityPasses = $ReproducibilityPasses')
    'Android Hysteria2 isolated build flag' = @($androidBuildScript, 'EnableHysteria2Preview', 'GREENVPN_ANDROID_HYSTERIA2_PREVIEW_ENABLED', 'GREENVPN_HYSTERIA2_PREVIEW_ENABLED=true')
    'Android Hysteria2 physical watchdog smoke' = @($androidHysteriaPhysicalTestScript, "ExpectedEgress = '5.129.216.42'", 'watchdogState', 'finalState', 'plaintextConfigRemoved')
    'Android Hysteria2 APK verifier' = @($androidHysteriaApkVerifyScript, 'HYSTERIA-NATIVE-MANIFEST.json', '$packagedAbis = @(''arm64-v8a'', ''x86_64'')', 'GREENVPN_HYSTERIA2_PREVIEW_ENABLED:Z = true', 'zipalign', 'apksigner')
    'Android post-transition probe binds active network' = @($androidTransportProbeReceiver, 'connectivity.activeNetwork', 'network.openConnection(URL(uri))', 'connection.disconnect()')
    'Android stable transport isolation verifier' = @($androidStableIsolationVerifyScript, 'Stable APK contains transport preview payload', 'GREENVPN_HYSTERIA2_PREVIEW_ENABLED', 'pro.greenvpn.hysteria.Hysteria2VpnService')
}
foreach ($check in $androidHysteriaSourceChecks.GetEnumerator()) {
    $source = [string]$check.Value[0]
    $missing = @($check.Value[1..($check.Value.Count - 1)] | Where-Object { -not $source.Contains([string]$_) })
    if ($missing.Count -eq 0) {
        Add-Pass "$($check.Key) markers present"
    }
    else {
        Add-Error "$($check.Key) missing marker(s): $($missing -join ', ')"
    }
}

if ($androidHysteriaManifest.Contains('Hysteria2DebugReceiver')) {
    Add-Error 'Android Hysteria2 debug receiver leaked into the main manifest'
}
else {
    Add-Pass 'Android Hysteria2 debug receiver is isolated from the main manifest'
}

foreach ($scriptPath in @(
    $androidBuildScriptPath,
    $androidHysteriaPreparePath,
    $androidHysteriaNativeBuildPath,
    $androidHysteriaPhysicalTestPath,
    $androidHysteriaApkVerifyPath,
    $androidStableIsolationVerifyPath
)) {
    if (Test-Path -LiteralPath $scriptPath) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Add-Error "Android Hysteria2 PowerShell parser errors in ${scriptPath}: $($parseErrors[0].ToString())"
        }
        else {
            Add-Pass "Android Hysteria2 PowerShell parser check passed: $scriptPath"
        }
    }
}

Write-Section "ANDROID VLESS REALITY PREVIEW AND FALLBACK CHECKS"
$androidVlessSourceChecks = [ordered]@{
    'Android VLESS guarded config' = @($androidVlessConfig, 'guardedEndpoints = mapOf(', '"37.220.85.211" to 443', '"88.218.250.86" to 9443', 'stream-up', 'maxConnections', 'https://1.1.1.1/dns-query', 'outboundTag", "dns-out"')
    'Android VLESS persistent fail-closed state' = @($androidVlessService, 'context.noBackupFilesDir', 'STATE_FILE = "state.json"', 'fun prepareForConnect(context: Context)', 'VPN service stopped unexpectedly', 'process.destroyForcibly()', 'cleanup("down", "")')
    'Android VLESS reconnect state reset' = @($androidVlessController, 'VlessRealityVpnService.prepareForConnect(context)', 'waitForState(context, "up", 30_000L)', 'state == "error" && expected != "down"')
    'Android VLESS config tests' = @($androidVlessConfigTest, 'rejectsServerPrivateMaterial', 'rejectsUnknownEndpoint', 'rejectsGuardedEndpointOnWrongPort', 'rejectsSniDrift')
    'Android VLESS pinned preparation' = @($androidVlessPrepareScript, 'v26.7.11', 'EA227CFB125FA093257F1A8227B5C6E30D93301D05F2E6AB8B79152F7AFF8CDB', 'source notice is bundled from docs/licenses')
    'Android VLESS physical watchdog and reconnect' = @($androidVlessPhysicalTestScript, "ExpectedEgress = '5.129.216.42'", 'watchdogState', 'reconnectState', 'reconnectEgress', 'plaintextConfigRemoved')
    'Canary-only route cooldown' = @($main, 'kTransportPreviewFallbackEnabled', '_recordRouteFailure', '_recordRouteSuccess', 'greenVpnCompareTransportPreviewCandidates(', '_routeFailureCooldown.coolingUntil(')
    'Bounded cooldown implementation' = @($routeFailureCooldown, 'Duration(minutes: 1)', 'Duration(minutes: 3)', 'Duration(minutes: 10)', 'Duration(minutes: 30)', 'recordSuccess')
    'Cooldown unit tests' = @($routeFailureCooldownTest, 'bounded exponential cooldown', 'healthy candidates sort before cooling candidates')
    'Route monitoring is control-plane-only by default' = @($monitoringProbe, 'routeSignalKind": "control_plane_reachability"', 'automationEligible": False', 'egressVerified": False')
    'Backend accepts only verified data-plane automation' = @($backend, 'def route_observation_automation_eligible(', '"tunnel_data_plane", "proxy_data_plane"', 'details.get("egressVerified") is True', 'ignoredControlPlaneOnly')
}
foreach ($check in $androidVlessSourceChecks.GetEnumerator()) {
    $source = [string]$check.Value[0]
    $missing = @($check.Value[1..($check.Value.Count - 1)] | Where-Object { -not $source.Contains([string]$_) })
    if ($missing.Count -eq 0) {
        Add-Pass "$($check.Key) markers present"
    }
    else {
        Add-Error "$($check.Key) missing marker(s): $($missing -join ', ')"
    }
}

foreach ($scriptPath in @($androidVlessPreparePath, $androidVlessPhysicalTestPath)) {
    if (Test-Path -LiteralPath $scriptPath) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Add-Error "Android VLESS PowerShell parser errors in ${scriptPath}: $($parseErrors[0].ToString())"
        }
        else {
            Add-Pass "Android VLESS PowerShell parser check passed: $scriptPath"
        }
    }
}

Write-Section "ANDROID NAIVE HTTPS PREVIEW CHECKS"
$androidNaiveSourceChecks = [ordered]@{
    'Android Naive guarded config' = @($androidNaiveConfig, 'guardedEndpoints = mapOf(', '"nl1.vpn.greenvpn.pro" to "37.220.85.211"', '"88-218-250-86.sslip.io" to "88.218.250.86"', 'CANARY_PORT = 8443', 'host-resolver-rules', 'allowedKeys', 'endpointIp')
    'Android Naive mapdns full tunnel' = @($androidNaiveService, '.addDnsServer("198.18.2.2")', 'mapdns:', "udp: 'tcp'", 'val routeExclusions = NaiveHttpsConfig.routeExclusions(baseConfig)', 'Ipv4RouteExclusions.routesExcluding(routeExclusions)', 'builder.addRoute(route.address, route.prefixLength)')
    'Android Naive persistent fail-closed state' = @($androidNaiveService, 'context.noBackupFilesDir', 'STATE_FILE = "state.json"', 'fun prepareForConnect(context: Context)', 'process.destroyForcibly()', 'cleanup("down", "")')
    'Android Naive reconnect state reset' = @($androidNaiveController, 'NaiveHttpsVpnService.prepareForConnect(context)', 'waitForState(context, "up", 30_000L)', 'state == "error" && expected != "down"')
    'Android Naive config tests' = @($androidNaiveConfigTest, 'rejectsWrongEndpoint', 'rejectsPlainHttp', 'rejectsMissingCredentials', 'rejectsLoggingFields')
    'Android Naive pinned preparation' = @($androidNaivePrepareScript, 'v150.0.7871.63-1', '733FBBBEBB383A91F42036992C21CFD19B99E089AC3D15D7C077DF79FC471A89', '55B64ADBDA9FC09F4137800D74AC6772B797F96E224C12F69A8E001886BB82EB', 'BSD-3-Clause')
    'Android Naive physical watchdog and reconnect' = @($androidNaivePhysicalTestScript, "ExpectedEgress = '5.129.216.42'", 'watchdogState', 'reconnectState', 'reconnectEgress', 'plaintextConfigRemoved')
    'Naive capability remains preview-only' = @($main, 'kNaiveHttpsPreviewEnabled', "if (kNaiveHttpsPreviewEnabled) 'naive_https'", 'kTransportPreviewFallbackEnabled')
}
foreach ($check in $androidNaiveSourceChecks.GetEnumerator()) {
    $source = [string]$check.Value[0]
    $missing = @($check.Value[1..($check.Value.Count - 1)] | Where-Object { -not $source.Contains([string]$_) })
    if ($missing.Count -eq 0) { Add-Pass "$($check.Key) markers present" }
    else { Add-Error "$($check.Key) missing marker(s): $($missing -join ', ')" }
}
foreach ($scriptPath in @($androidNaivePreparePath, $androidNaivePhysicalTestPath)) {
    if (Test-Path -LiteralPath $scriptPath) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Add-Error "Android Naive PowerShell parser errors in ${scriptPath}: $($parseErrors[0].ToString())"
        }
        else { Add-Pass "Android Naive PowerShell parser check passed: $scriptPath" }
    }
}

Write-Section "ANDROID DNSTT LAST-RESORT PREVIEW CHECKS"
$androidDnsttSourceChecks = [ordered]@{
    'Android dnstt guarded profile' = @($androidDnsttConfig, 'ZONE = "t.greenvpn.pro"', 'EXPECTED_EGRESS = "5.129.216.42"', 'https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query', 'LISTEN = "127.0.0.1:$SOCKS_PORT"')
    'Android dnstt mapdns full tunnel' = @($androidDnsttService, '.addDnsServer("198.18.3.2")', 'mapdns:', "udp: 'tcp'", 'Ipv4RouteExclusions.routesExcluding(DnsttConfig.routeExclusions(profile))', 'builder.addRoute(route.address, route.prefixLength)')
    'Android dnstt persistent fail-closed state' = @($androidDnsttService, 'context.noBackupFilesDir', 'STATE_FILE = "state.json"', 'process.destroyForcibly()', 'failClosed("Transport engine stopped")', 'cleanup("down", "")')
    'Android dnstt reconnect state reset' = @($androidDnsttController, 'DnsttVpnService.prepareForConnect(context)', 'waitForState(context, "up", 30_000L)', 'state == "error" && expected != "down"')
    'Android dnstt config tests' = @($androidDnsttConfigTest, 'rejectsWrongZone', 'rejectsInvalidPublicKey', 'rejectsNonLoopbackListener', 'rejectsUnapprovedResolver', 'rejectsLoggingOrUnknownFields')
    'Android dnstt pinned preparation' = @($androidDnsttPrepareScript, 'dnstt 20260501', 'AAE616C0888DB31A61555CA4FE91B578E2A6734B7CEF7497B6FE30FFCDA1FDC5', 'AD1AB35C674DF572FBCE8B0A6BC758CBC11F6276', 'public-domain software')
    'Android dnstt isolated build flag' = @($androidBuildScript, 'EnableDnsttPreview', 'GREENVPN_ANDROID_DNSTT_PREVIEW_ENABLED', 'GREENVPN_DNSTT_PREVIEW_ENABLED=true')
    'Android dnstt physical watchdog and reconnect' = @($androidDnsttPhysicalTestScript, "ExpectedEgress = '5.129.216.42'", "resolverMode = 'doh'", 'watchdogState', 'reconnectState', 'reconnectEgress', 'plaintextConfigRemoved')
    'Android dnstt APK verifier' = @($androidDnsttApkVerifyScript, 'lib/arm64-v8a/libdnstt_client.so', 'GREENVPN_DNSTT_PREVIEW_ENABLED:Z = true', 'zipalign', 'apksigner')
    'dnstt server bootstrap is isolated' = @($dnsttBootstrapScript, 'CANARY_HOST="5.129.216.42"', 'CANARY_ZONE="t.greenvpn.pro"', 'registrar_dns=not_changed', 'stable_transports=verified_unchanged', 'client_profile=root_only')
    'dnstt authoritative DNS frontend is guarded' = @($dnsttDnsFrontendBootstrapScript, 'DNSDIST_VERSION="2.1.0-1pdns.ubuntu24.04"', 'BACKEND_PORT="5353"', 'healthCheckMode="up"', 'TasksMax=8192', 'LimitNOFILE=16384', 'authoritative_ns_soa=ready', 'restore_direct_listener', 'stable_transports=verified_unchanged')
    'dnstt authoritative DNS frontend rollback is host-guarded' = @($dnsttDnsFrontendRollbackScript, 'EXPECTED_PUBLIC_IP', 'APPROVED_EXISTING_HOST', 'direct_dnstt_listener=restored', 'stable_transports=active')
    'dnstt readiness proves delegation and data plane' = @($dnsttReadinessScript, '--require-delegation', 'server_data_plane_ready=', 'doh_delegation_ready=', 'secrets_printed=false')
    'dnstt rollback is host-guarded' = @($dnsttRollbackScript, 'EXPECTED_PUBLIC_IP', 'APPROVED_EXISTING_HOST', 'registrar_dns=not_changed', 'stable_transports=active')
    'Reusable server security contour runbook' = @($serverSecurityRunbook, 'change_id:', 'stable.before.sha256', 'base64 -d | bash -s --', 'clientConfigReady=true', 'payment data', 'Git bundle')
    'Stable APK isolation covers all preview engines' = @($androidStableIsolationVerifyScript, 'libdnstt_client', 'pro.greenvpn.dnstt.DnsttVpnService', 'GREENVPN_DNSTT_PREVIEW_ENABLED', 'GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED', 'GREENVPN_VLESS_REALITY_PREVIEW_ENABLED')
    'Six-stage preview cascade policy' = @($transportPreviewPolicy, "'wireguard_udp'", "'amneziawg'", "'hysteria2'", "'vless_reality'", "'naive_https'", "'dnstt'", 'greenVpnTransportPreviewRank', 'greenVpnTransportRequiresFullTunnel')
    'Six-stage preview cascade tests' = @($transportPreviewPolicyTest, 'preview cascade keeps the guarded transport order', 'proxy transports are restricted to full-tunnel mode', 'cooldown demotes a failed route without changing cascade order', "'wireguard_udp'")
    'Dart selector advertises and orders dnstt' = @($main, 'kDnsttPreviewEnabled', "if (kDnsttPreviewEnabled) 'dnstt'", 'greenVpnCompareTransportPreviewCandidates(', 'greenVpnTransportRequiresFullTunnel(')
    'Android app lifecycle integrates dnstt' = @($androidMainActivity, 'protocol == "dnstt"', 'GreenVpnDnsttPreview.validateConfig', 'GreenVpnDnsttPreview.connect', 'GreenVpnDnsttPreview.disconnect', 'BuildConfig.GREENVPN_DNSTT_PREVIEW_ENABLED')
    'Android quick tile integrates dnstt' = @($androidQuickTile, 'BuildConfig.GREENVPN_DNSTT_PREVIEW_ENABLED', 'GreenVpnDnsttPreview.validateConfig', 'GreenVpnDnsttPreview.connect', 'GreenVpnDnsttPreview.disconnect')
    'Android quick tile uses the dynamic guarded cascade' = @($androidQuickTile, 'BuildConfig.GREENVPN_RELEASE_CHANNEL', 'BuildConfig.GREENVPN_CLIENT_MARKER', '/api/v1/catalog/servers?channel=', 'fetchCatalogCandidates(', 'GreenVpnQuickTileCascadePolicy.sort(', 'recordRouteFailure(', 'clearRouteFailure(', 'probeConnectedRoute(fetched.protocol)')
    'Android quick tile executor survives service rebinds' = @($androidQuickTile, 'val TILE_EXECUTOR = Executors.newSingleThreadExecutor()', 'TILE_EXECUTOR.execute {')
    'Android proxy route probe follows local SOCKS data plane' = @($androidRouteProbe, '"hysteria2" -> 1980', '"vless_reality" -> 1981', '"naive_https" -> 1982', '"dnstt" -> 1983', 'probeHttpsViaSocks(', 'endpointIdentificationAlgorithm = "HTTPS"')
    'Android proxy route probe has protocol mapping tests' = @($androidRouteProbeTest, 'proxyTransportsRequireTheirDedicatedLoopbackSocksPortsAfterSystemRoute', 'tunnelProtocolsUseTheSystemVpnRoute')
    'Flutter Android post-connect probe uses native route' = @($main, "invokeMethod<Object?>('probeConnectedRoute'", "'protocol': server.protocolCode")
    'Android quick tile cascade policy is strict and bounded' = @($androidQuickTilePolicy, 'listOf(', '"wireguard_udp"', '"amneziawg"', '"hysteria2"', '"vless_reality"', '"naive_https"', '"dnstt"', '60_000L', '1_800_000L')
    'Android quick tile cascade tests cover order and cooldown' = @($androidQuickTilePolicyTest, 'strictTransportOrderIsPreserved', 'coolingCandidateIsDemotedWithoutChangingBaseOrder', 'cooldownScheduleIsBounded')
    'Android quick tile physical proof is reversible' = @($androidQuickTilePhysicalTest, "'wireguard_udp', 'amneziawg', 'hysteria2', 'vless_reality', 'naive_https', 'dnstt'", "Wait-Route -ExpectedProtocol 'wireguard_udp'", 'cooledRouteCount', 'Get-VpnRecordCount', 'Get-TransportEngineProcessCount', 'Invoke-ExternalProbe', 'youtubeProbeRequiredBeforeSuccessMarker', 'Set-TileList -Value $originalTiles', "Invoke-DebugCommand -Command 'disconnect_all'", "Invoke-DebugCommand -Command 'clear_tile_cooldown'")
    'Android quick tile debug controls stay sanitized' = @($androidTransportContractService, '"set_tile_cooldown"', '"clear_tile_cooldown"', '"disconnect_all"', 'lastRouteSuccess', 'activeProtocols')
    'Android preview build binds native paid-beta identity' = @($androidAppBuild, 'GREENVPN_ANDROID_RELEASE_CHANNEL', 'GREENVPN_ANDROID_CLIENT_MARKER', 'GREENVPN_RELEASE_CHANNEL', 'GREENVPN_CLIENT_MARKER')
    'Android build script binds the requested native release identity' = @(
        $androidBuildScript,
        "GREENVPN_ANDROID_RELEASE_CHANNEL = if (`$PublicProductCandidate) { 'public-product' } else { 'paid-beta' }",
        "GREENVPN_ANDROID_CLIENT_MARKER = if (`$PublicProductCandidate)",
        "'green-vpn-public-product-v1'",
        "'green-vpn-paid-beta-v1'",
        'Public product candidate primary API must not use /paid-beta-api.',
        'AWG2 preview primary API must use /paid-beta-api.'
    )
    'Backend guarded Naive and dnstt contracts' = @($backend, 'static_naive_https_canary', 'static_dnstt_canary', 'guarded_json_client_profile_file(', 'load_naive_https_client_config(', 'load_dnstt_client_config(', 'GREENVPN_DNSTT_CLIENT_CONFIG_ENABLED', 'GREENVPN_NAIVE_HTTPS_CLIENT_CONFIG_ENABLED')
    'Paid-beta Naive/dnstt deploy is atomic and isolated' = @($naiveDnsttContractDeployScript, 'EXPECTED_CURRENT_RELEASE="paid-beta-0.3.0-paid-beta.6-2026071106-r17-vless-contract"', 'production_changed=false', 'stable_catalog_changed=false', 'bluevpn.db.before.sqlite', 'rollback_on_error', 'legacy_naive_dnstt_count=0', 'preview_naive_dnstt_count=2')
    'Android ten-contract debug probe' = @($androidTransportContractService, 'TransportContractDebugService', 'nl2-awg2-canary', 'nl2-hysteria2-canary', 'nl2-vless-reality-xhttp-canary', 'nl2-naive-https-canary', 'nl2-dnstt-canary', '"primary"', '"fallback"', 'checks.length() == bases.size * CANDIDATES.size')
    'Android contract probe report is sanitized' = @($androidTransportContractProbe, 'checks = @($report.checks)', 'checks.Count -ne $ExpectedCheckCount', 'run-as $Package rm -f $resultFile')
}
foreach ($check in $androidDnsttSourceChecks.GetEnumerator()) {
    $source = [string]$check.Value[0]
    $missing = @($check.Value[1..($check.Value.Count - 1)] | Where-Object { -not $source.Contains([string]$_) })
    if ($missing.Count -eq 0) { Add-Pass "$($check.Key) markers present" }
    else { Add-Error "$($check.Key) missing marker(s): $($missing -join ', ')" }
}
if ($androidHysteriaManifest.Contains('DnsttDebugReceiver')) {
    Add-Error 'Android dnstt debug receiver leaked into the main manifest'
}
elseif (-not $androidHysteriaDebugManifest.Contains('DnsttDebugReceiver') -or
    -not $androidHysteriaDebugManifest.Contains('android.permission.DUMP')) {
    Add-Error 'Android dnstt debug receiver is not protected in the debug manifest'
}
else { Add-Pass 'Android dnstt debug receiver is debug-only and DUMP-protected' }

if ($androidAppManifest.Contains('TransportContractDebugService')) {
    Add-Error 'Android transport contract debug service leaked into the main manifest'
}
elseif (-not $androidAppDebugManifest.Contains('TransportContractDebugService') -or
    -not $androidAppDebugManifest.Contains('android.permission.DUMP')) {
    Add-Error 'Android transport contract debug service is not DUMP-protected in the debug manifest'
}
elseif ($androidTransportContractService -match '\.put\("(accessToken|deviceId|configText)"') {
    Add-Error 'Android transport contract debug report may expose a credential or config payload'
}
else { Add-Pass 'Android transport contract probe is debug-only, DUMP-protected, and sanitized' }

foreach ($scriptPath in @($androidDnsttPreparePath, $androidDnsttPhysicalTestPath, $androidDnsttApkVerifyPath, $androidTransportContractProbePath, $androidQuickTilePhysicalTestPath)) {
    if (Test-Path -LiteralPath $scriptPath) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Add-Error "Android dnstt PowerShell parser errors in ${scriptPath}: $($parseErrors[0].ToString())"
        }
        else { Add-Pass "Android dnstt PowerShell parser check passed: $scriptPath" }
    }
}

Write-Section "RELEASE INTEGRITY CHECKS"

$readOnlyControlPlaneHelpers = [ordered]@{
    'External readiness' = $externalReadinessScript
    'Payment launch safety' = $paymentLaunchSafetyScript
    'Monitoring probe plan' = $monitoringProbePlanScript
    'Owner launch packet' = $ownerLaunchPacketScript
}
foreach ($helper in $readOnlyControlPlaneHelpers.GetEnumerator()) {
    if ($helper.Value.Contains('ControlPlaneHost = "72.56.32.197"') -and
        -not $helper.Value.Contains('ServerHost = "37.220.85.211"')) {
        Add-Pass "$($helper.Key) defaults to the primary control plane"
    }
    else {
        Add-Error "$($helper.Key) has a stale or missing control-plane default"
    }
}
if ($externalReadinessScript.Contains('VpnEndpointHost = "37.220.85.211"') -and
    $externalReadinessScript.Contains('root@$ControlPlaneHost') -and
    -not $externalReadinessScript.Contains('root@$ServerHost')) {
    Add-Pass 'External readiness separates the control plane from the NL1 VPN endpoint'
}
else {
    Add-Error 'External readiness conflates the control plane with the VPN endpoint'
}

$mutatingPowerShellHelpers = [ordered]@{
    'Backend env Windows wrapper' = $configureBackendEnvWindowsScript
    'Legacy backend deploy Windows wrapper' = $deployBackendWindowsScript
}
foreach ($helper in $mutatingPowerShellHelpers.GetEnumerator()) {
    if ($helper.Value.Contains('ServerHost = ""') -and
        $helper.Value.Contains('72.56.32.197') -and
        $helper.Value.Contains('176.113.81.35') -and
        $helper.Value.Contains('non-control-plane host')) {
        Add-Pass "$($helper.Key) requires an explicit allowlisted control plane"
    }
    else {
        Add-Error "$($helper.Key) can select an unsafe implicit server target"
    }
}

$mutatingShellHelpers = [ordered]@{
    'Backend env shell helper' = $configureBackendEnvShellScript
    'Legacy backend deploy shell helper' = $deployBackendShellScript
}
foreach ($helper in $mutatingShellHelpers.GetEnumerator()) {
    if ($helper.Value.Contains('SERVER_HOST="${1:-}"') -and
        $helper.Value.Contains('72.56.32.197|176.113.81.35') -and
        $helper.Value.Contains('non-control-plane host')) {
        Add-Pass "$($helper.Key) requires an explicit allowlisted control plane"
    }
    else {
        Add-Error "$($helper.Key) can select an unsafe implicit server target"
    }
}

if ($androidLegacyE2eScript.Contains('[switch]$EnableServerCleanup') -and
    $androidLegacyE2eScript.Contains('-not $EnableServerCleanup') -and
    $androidLegacyE2eScript.Contains('ControlPlaneHost = ""') -and
    -not $androidLegacyE2eScript.Contains('ServerHost = "37.220.85.211"')) {
    Add-Pass 'Legacy Android server cleanup is explicit and fail-closed'
}
else {
    Add-Error 'Legacy Android server cleanup can target a server implicitly'
}

if ($backend.Contains('configure_backend_env_wsl.ps1 -ServerHost 72.56.32.197') -and
    $backend.Contains('"serverHost": "72.56.32.197"') -and
    $backend.Contains('"controlPlaneHost": "72.56.32.197"') -and
    $backend.Contains('"fallbackControlPlaneHost": "176.113.81.35"') -and
    $backend.Contains('"vpnEndpointHost": "37.220.85.211"')) {
    Add-Pass 'Owner setup bundle separates explicit control-plane and VPN endpoint roles'
}
else {
    Add-Error 'Owner setup bundle contains a stale or ambiguous server target'
}
if ($monitoringProbePlanScript.Contains('No additional monitoring host is required') -and
    $monitoringProbePlanScript.Contains('Provision or repair a separate monitoring VPS') -and
    $backend.Contains('monitoring readiness') -and
    $backend.Contains('missing coverage')) {
    Add-Pass 'Monitoring owner guidance follows current readiness instead of requiring a redundant VPS'
}
else {
    Add-Error 'Monitoring owner guidance still requires a redundant probe host unconditionally'
}

$androidReleaseSigningFragments = @(
    'releaseTaskRequested',
    'android/key.properties is missing',
    'A release APK must never fall back to the debug certificate',
    'requiredSigningKeys',
    'configuredStore.isFile'
)
foreach ($fragment in $androidReleaseSigningFragments) {
    if ($androidAppBuild.Contains($fragment)) {
        Add-Pass "Android release signing invariant present: $fragment"
    }
    else {
        Add-Error "Android release signing invariant missing: $fragment"
    }
}
if ($androidAppBuild.Contains('signingConfigs.getByName("debug")')) {
    Add-Error 'Android release build still has a debug-signing fallback'
}
else {
    Add-Pass 'Android release build has no debug-signing fallback'
}
if ($androidReleaseSigner -match '^[0-9a-f]{64}$') {
    Add-Pass 'Android release signer SHA-256 is pinned'
}
else {
    Add-Error 'Android release signer SHA-256 pin is missing or invalid'
}
foreach ($fragment in @(
    'release_signer_sha256.txt',
    'apksigner verify --print-certs',
    'certificate SHA-256 digest',
    'Unexpected Android release signer'
)) {
    if ($androidBuildScript.Contains($fragment)) {
        Add-Pass "Android build verifies release signer: $fragment"
    }
    else {
        Add-Error "Android build signer verification missing: $fragment"
    }
}

foreach ($fragment in @(
    'billing_payment_smoke_candidate',
    'providerPaymentMethodSaved',
    'PUBLIC_PRODUCT_PLAN_CODE',
    'expected_amount',
    'autoRenew'
)) {
    if ($backend.Contains($fragment)) {
        Add-Pass "Payment smoke strictness marker present: $fragment"
    }
    else {
        Add-Error "Payment smoke strictness marker missing: $fragment"
    }
}

foreach ($fragment in @(
    'replication_tombstones',
    'record_replication_tombstone',
    'GREENVPN_SQLITE_NODE_ID_BASE',
    'GREENVPN_REPLICATION_NODE_ID'
)) {
    if ($backend.Contains($fragment)) {
        Add-Pass "Backend replication safety marker present: $fragment"
    }
    else {
        Add-Error "Backend replication safety marker missing: $fragment"
    }
}
foreach ($fragment in @(
    'replication_tombstones',
    '_build_id_maps',
    'ID_REFERENCE_COLUMNS',
    '_remap_replication_tombstone',
    'not source_has_table and not target_has_table',
    'deleted'
)) {
    if ($sqliteStateSyncScript.Contains($fragment)) {
        Add-Pass "SQLite state sync safety marker present: $fragment"
    }
    else {
        Add-Error "SQLite state sync safety marker missing: $fragment"
    }
}

foreach ($fragment in @(
    'GREENVPN_SNAPSHOT_COMPRESSION',
    'gzip.GzipFile',
    'compresslevel=1',
    'mtime=0'
)) {
    if ($sqliteSnapshotScript.Contains($fragment)) {
        Add-Pass "SQLite snapshot compression marker present: $fragment"
    }
    else {
        Add-Error "SQLite snapshot compression marker missing: $fragment"
    }
}
foreach ($fragment in @(
    'GREENVPN_DB_SYNC_SNAPSHOT_COMPRESSION',
    'gzip -t',
    'gzip -dc',
    'TRANSFER_TMP',
    'trap cleanup EXIT'
)) {
    if ($dbSyncShellScript.Contains($fragment)) {
        Add-Pass "DB sync compressed-transfer marker present: $fragment"
    }
    else {
        Add-Error "DB sync compressed-transfer marker missing: $fragment"
    }
}
foreach ($fragment in @(
    'TRANSPORT_SERVER_IDS = (',
    'EXPECTED_ROUTE_PASSPORTS = {',
    'BUSINESS_TABLES = ("users", "subscriptions", "billing_orders")',
    'apply mode requires an explicit backup path',
    '_create_online_backup(',
    'ON CONFLICT(server_id) DO UPDATE SET',
    'businessCountsUnchanged',
    '"secretsPrinted": False'
)) {
    if ($paidBetaTransportCatalogSyncScript.Contains($fragment)) {
        Add-Pass "Paid-beta transport catalog sync safety marker present: $fragment"
    }
    else {
        Add-Error "Paid-beta transport catalog sync safety marker missing: $fragment"
    }
}
foreach ($fragment in @(
    'TRANSPORT_SERVER_IDS="nl1-awg2-canary',
    'dangerous_gates_enabled=false',
    'GREENVPN_PREVIEW_SERVER_IDS',
    'GREENVPN_SERVER_CATALOG_VERSION',
    'rollback_on_error',
    'catalog_routes=16',
    'client_artifacts_changed=false',
    'production_contour_changed=false'
)) {
    if ($paidBetaTransportParityScript.Contains($fragment)) {
        Add-Pass "Paid-beta transport parity safety marker present: $fragment"
    }
    else {
        Add-Error "Paid-beta transport parity safety marker missing: $fragment"
    }
}
if (Test-Path -LiteralPath $paidBetaTransportCatalogSyncPath) {
    & python -c "import ast,pathlib,sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))" $paidBetaTransportCatalogSyncPath
    if ($LASTEXITCODE -eq 0) {
        Add-Pass 'Paid-beta transport catalog sync Python parser check passed'
    }
    else {
        Add-Error 'Paid-beta transport catalog sync Python parser check failed'
    }
}
if (Test-Path -LiteralPath $paidBetaTransportParityPath) {
    $gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
    $bashCommand = if (Test-Path -LiteralPath $gitBash) { $gitBash } else { 'bash' }
    & $bashCommand -n $paidBetaTransportParityPath
    if ($LASTEXITCODE -eq 0) {
        Add-Pass 'Paid-beta transport parity Bash parser check passed'
    }
    else {
        Add-Error 'Paid-beta transport parity Bash parser check failed'
    }
}
foreach ($fragment in @(
    'changesClientArtifacts = $false',
    'changesSite = $false',
    'backend-release-manifest.json',
    'client_artifacts_changed=false'
)) {
    if ($paidBetaBackendBundleScript.Contains($fragment)) {
        Add-Pass "Backend-only bundle isolation marker present: $fragment"
    }
    else {
        Add-Error "Backend-only bundle isolation marker missing: $fragment"
    }
}
foreach ($fragment in @(
    'GREENVPN_REPLICATION_NODE_ID',
    'GREENVPN_SQLITE_NODE_ID_BASE',
    'replication_tombstones_ready',
    'client_artifacts_changed=false',
    'site_changed=false',
    'rollback_on_error'
)) {
    if ($paidBetaBackendInstallerScript.Contains($fragment)) {
        Add-Pass "Backend-only installer safety marker present: $fragment"
    }
    else {
        Add-Error "Backend-only installer safety marker missing: $fragment"
    }
}
foreach ($fragment in @(
    'GREENVPN_ANDROID_ROLLBACK',
    'GREENVPN_ANDROID_PAID_BETA_ROLLBACK',
    'GREENVPN_WINDOWS_PAID_BETA_ROLLBACK',
    'Public rollback SHA256 mismatch',
    'rollback_on_error'
)) {
    if ($releaseRollbackInstallerScript.Contains($fragment)) {
        Add-Pass "Public rollback installer safety marker present: $fragment"
    }
    else {
        Add-Error "Public rollback installer safety marker missing: $fragment"
    }
}
foreach ($fragment in @(
    'greenvpn-admin-static-backups',
    'cancelStaleBillingOrder',
    'Protected admin surface returned HTTP',
    'rollback_on_error'
)) {
    if ($adminStaticInstallerScript.Contains($fragment)) {
        Add-Pass "Admin static installer safety marker present: $fragment"
    }
    else {
        Add-Error "Admin static installer safety marker missing: $fragment"
    }
}

if (Test-Path -LiteralPath $paidBetaBackendBundlePath) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $paidBetaBackendBundlePath,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Add-Error "Backend-only bundle script has PowerShell parser errors: $($parseErrors[0].ToString())"
    }
    else {
        Add-Pass 'Backend-only bundle script PowerShell parser check passed'
    }
}

$operationsFiles = [ordered]@{
    'Project map' = $projectMap
    'Operations master runbook' = $projectOperationsRunbook
    'Server restore snapshot script' = $fullServerSnapshotScript
    'Full project checkpoint script' = $fullProjectCheckpointScript
    'Local restore snapshot script' = $localRestoreSnapshotScript
    'Repository secret scanner' = $repositorySecretScanner
}
foreach ($entry in $operationsFiles.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
        Add-Error "$($entry.Key) is missing or empty"
    }
    else {
        Add-Pass "$($entry.Key) is present"
    }
}

if (Test-Path -LiteralPath $fullProjectCheckpointPath) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $fullProjectCheckpointPath,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Add-Error "Full checkpoint script has PowerShell parser errors: $($parseErrors[0].ToString())"
    }
    else {
        Add-Pass 'Full checkpoint script PowerShell parser check passed'
    }
}

if (-not $fullProjectCheckpointScript.Contains('create_local_restore_snapshot.ps1')) {
    Add-Error 'Full checkpoint does not invoke the encrypted local-state snapshot'
}
else {
    Add-Pass 'Full checkpoint invokes the encrypted local-state snapshot'
}

foreach ($fragment in @(
    'Set-RestrictedCheckpointAcl',
    "'icacls.exe'",
    "'/reset'",
    "'/inheritance:r'",
    "'*S-1-5-18:(OI)(CI)F'",
    "'*S-1-5-32-544:(OI)(CI)F'",
    "'-O', '-q'"
)) {
    if ($fullProjectCheckpointScript.Contains($fragment)) {
        Add-Pass "Full checkpoint hardening marker present: $fragment"
    }
    else {
        Add-Error "Full checkpoint hardening marker missing: $fragment"
    }
}

foreach ($fragment in @(
    'Set-RestrictedCheckpointAcl',
    "'icacls.exe'",
    "'/reset'",
    "'/inheritance:r'",
    "'*S-1-5-18:(OI)(CI)F'",
    "'*S-1-5-32-544:(OI)(CI)F'"
)) {
    if ($localRestoreSnapshotScript.Contains($fragment)) {
        Add-Pass "Local checkpoint hardening marker present: $fragment"
    }
    else {
        Add-Error "Local checkpoint hardening marker missing: $fragment"
    }
}

if (Test-Path -LiteralPath $localRestoreSnapshotPath) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $localRestoreSnapshotPath,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Add-Error "Local restore snapshot script has PowerShell parser errors: $($parseErrors[0].ToString())"
    }
    else {
        Add-Pass 'Local restore snapshot script PowerShell parser check passed'
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

$trustedWindowsSigningChecks = [ordered]@{
    'Installer signs owned payload before archive and final EXE after resource updates' = @(
        $installer,
        'Invoke-CodeSigningStage',
        '$ownedPayloadBinaries',
        '-payload.json',
        '-bootstrap.json',
        '-installer.json',
        'RequireCodeSigning'
    )
    'Trusted Windows finalizer auto-detects a valid local signing identity' = @(
        $trustedWindowsFinalizer,
        '1.3.6.1.5.5.7.3.3',
        'Get-CodeSigningCertificates',
        'HasPrivateKey',
        'RequireWindowsCodeSigning',
        'readyForPhysicalSmoke',
        'ownerActions = @()'
    )
    'Windows publication binds signature reports to exact installer hashes' = @(
        $windowsPublicReleaseInstaller,
        '--production-signature-report',
        '--test-signature-report',
        'signature report does not match the exact trusted artifact',
        'GREENVPN_WINDOWS_CODE_SIGNING_PROVIDER',
        'GREENVPN_WINDOWS_SIGNED_INSTALLER_SHA256',
        '"signed": signed_release == "1"'
    )
}
foreach ($check in $trustedWindowsSigningChecks.GetEnumerator()) {
    $source = [string]$check.Value[0]
    $missing = @(
        $check.Value[1..($check.Value.Count - 1)] |
            Where-Object { -not $source.Contains([string]$_) }
    )
    if ($missing.Count -eq 0) {
        Add-Pass "$($check.Key) markers present"
    }
    else {
        Add-Error "$($check.Key) missing marker(s): $($missing -join ', ')"
    }
}

if (Test-Path -LiteralPath $trustedWindowsFinalizerPath) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $trustedWindowsFinalizerPath,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        Add-Error "Trusted Windows finalizer has PowerShell parser errors: $($parseErrors[0].ToString())"
    }
    else {
        Add-Pass 'Trusted Windows finalizer PowerShell parser check passed'
    }
}

if (Test-Path -LiteralPath $windowsPublicReleaseInstallerPath) {
    $gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
    $bashCommand = if (Test-Path -LiteralPath $gitBash) { $gitBash } else { 'bash' }
    & $bashCommand -n $windowsPublicReleaseInstallerPath
    if ($LASTEXITCODE -eq 0) {
        Add-Pass 'Windows signed publication Bash parser check passed'
    }
    else {
        Add-Error 'Windows signed publication Bash parser check failed'
    }
}

if (Test-Path -LiteralPath $windowsStableReleaseInstallerPath) {
    $gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
    $bashCommand = if (Test-Path -LiteralPath $gitBash) { $gitBash } else { 'bash' }
    & $bashCommand -n $windowsStableReleaseInstallerPath
    if ($LASTEXITCODE -eq 0) {
        Add-Pass 'Windows stable-only publication Bash parser check passed'
    }
    else {
        Add-Error 'Windows stable-only publication Bash parser check failed'
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

            $appExecutableEntries = @($entries | Where-Object {
                    $entry = $_.Replace('\', '/')
                    $entry -eq "app/greenvpn.exe" -or
                    $entry -eq "greenvpn.exe" -or
                    $entry.EndsWith("/app/greenvpn.exe", [System.StringComparison]::OrdinalIgnoreCase) -or
                    $entry.EndsWith("/greenvpn.exe", [System.StringComparison]::OrdinalIgnoreCase) -or
                    $entry -eq "app/bluevpn.exe" -or
                    $entry -eq "bluevpn.exe" -or
                    $entry.EndsWith("/app/bluevpn.exe", [System.StringComparison]::OrdinalIgnoreCase) -or
                    $entry.EndsWith("/bluevpn.exe", [System.StringComparison]::OrdinalIgnoreCase) -or
                    $entry -eq "app/greenvpn_transport_preview.exe" -or
                    $entry.EndsWith("/app/greenvpn_transport_preview.exe", [System.StringComparison]::OrdinalIgnoreCase)
                })
            if ($appExecutableEntries.Count -gt 0) {
                Add-Pass "Release zip contains Green VPN app executable"
            }
            else {
                Add-Error "Release zip does not contain Green VPN app executable in expected location."
            }

            $previewExecutableEntries = @($appExecutableEntries | Where-Object {
                $_.Replace('\', '/').EndsWith('app/greenvpn_transport_preview.exe', [System.StringComparison]::OrdinalIgnoreCase)
            })
            if ($previewExecutableEntries.Count -gt 0) {
                $normalizedEntries = @($entries | ForEach-Object { $_.Replace('\', '/') })
                foreach ($requiredEntry in @(
                    'app/tools/hysteria2/hysteria-windows-amd64.exe',
                    'app/tools/hysteria2/hev-socks5-tunnel.exe',
                    'app/tools/hysteria2/msys-2.0.dll',
                    'app/tools/hysteria2/wintun.dll',
                    'app/tools/greenvpn_hysteria2_watchdog.ps1',
                    'app/tools/greenvpn_selective_routing.ps1',
                    'app/tools/process-router/ProxyBridge_CLI.exe',
                    'app/tools/process-router/ProxyBridgeCore.dll',
                    'app/tools/process-router/WinDivert.dll',
                    'app/tools/process-router/WinDivert64.sys',
                    'app/tools/process-router/PROVENANCE.md',
                    'app/tools/process-router/THIRD_PARTY_NOTICES.txt',
                    'HYSTERIA2_CLIENT_ENGINE_LICENSE_AND_DESIGN_2026_07_12.md',
                    'HYSTERIA_APP_MIT.txt',
                    'HEV_SOCKS5_TUNNEL_MIT.txt',
                    'HEV_LWIP_BSD.txt',
                    'HEV_WINTUN_PREBUILT_BINARY_LICENSE.txt'
                    'app/tools/naive-https/naive.exe',
                    'app/tools/naive-https/hev-socks5-tunnel.exe',
                    'app/tools/naive-https/msys-2.0.dll',
                    'app/tools/naive-https/wintun.dll',
                    'app/tools/greenvpn_naive_https_watchdog.ps1',
                    'NAIVEPROXY_BSD_3_CLAUSE.txt'
                )) {
                    if ($normalizedEntries -contains $requiredEntry) {
                        Add-Pass "Transport preview zip contains: $requiredEntry"
                    }
                    else {
                        Add-Error "Transport preview zip missing required Hysteria2 artifact: $requiredEntry"
                    }
                }

                $expectedPackagedHashes = @{
                    'app/tools/hysteria2/hysteria-windows-amd64.exe' = 'BCD3865B09BE2E5CC18D117DCF3AD687D1E6E27B0B050376B9CF4EA251B64D6F'
                    'app/tools/hysteria2/hev-socks5-tunnel.exe' = '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E'
                    'app/tools/hysteria2/msys-2.0.dll' = '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18'
                    'app/tools/hysteria2/wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
                    'app/tools/naive-https/naive.exe' = '94F99801C665D29FC071624663C6F7BFA59E8D5EFAA84CD08EF5EBB18B46CB62'
                    'app/tools/naive-https/hev-socks5-tunnel.exe' = '46167DBA51A2C3DD5F2E3478B0D8A30CAD03392D388DC1330D55246492F48C1E'
                    'app/tools/naive-https/msys-2.0.dll' = '6C0DE43EFC0F14D871CC9F3FA803B9BD1E74802F45B3C8AFFE3DACC21B2EEA18'
                    'app/tools/naive-https/wintun.dll' = 'E5DA8447DC2C320EDC0FC52FA01885C103DE8C118481F683643CACC3220DAFCE'
                }
                foreach ($expected in $expectedPackagedHashes.GetEnumerator()) {
                    $entry = @($zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq $expected.Key })
                    if ($entry.Count -ne 1) { continue }
                    $stream = $entry[0].Open()
                    $sha = [Security.Cryptography.SHA256]::Create()
                    try {
                        $actualHash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
                    } finally {
                        $sha.Dispose()
                        $stream.Dispose()
                    }
                    if ($actualHash -eq $expected.Value) {
                        Add-Pass "Packaged transport runtime hash valid: $($expected.Key)"
                    }
                    else {
                        Add-Error "Packaged transport runtime hash mismatch: $($expected.Key)"
                    }
                }

                $previewInstallerEntries = @($zip.Entries | Where-Object {
                    [IO.Path]::GetFileName($_.FullName.Replace('/', '\')).Equals('install_windows_transport_preview.ps1', [System.StringComparison]::OrdinalIgnoreCase)
                })
                if ($previewInstallerEntries.Count -ne 1) {
                    Add-Error "Transport preview zip must contain exactly one protected installer; found $($previewInstallerEntries.Count)"
                }
                else {
                    $reader = [IO.StreamReader]::new($previewInstallerEntries[0].Open())
                    try { $packagedPreviewInstaller = $reader.ReadToEnd() } finally { $reader.Dispose() }
                    foreach ($fragment in @(
                        "`$InstallRoot = Join-Path `$env:ProgramFiles 'Green VPN Transport Preview'",
                        "'*S-1-5-18:(OI)(CI)F'",
                        "'*S-1-5-32-544:(OI)(CI)F'",
                        "'*S-1-5-32-545:(OI)(CI)RX'",
                        "/remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' /T /C",
                        "('*' + `$UserSid + ':(OI)(CI)M')",
                        'Remove-PreviewDirectoryWithRetry -Path $LegacyInstallRoot',
                        'Stop-ExitedPreviewServiceProcess'
                    )) {
                        if ($packagedPreviewInstaller.Contains($fragment)) {
                            Add-Pass "Packaged transport preview installer marker present: $fragment"
                        }
                        else {
                            Add-Error "Packaged transport preview installer marker missing: $fragment"
                        }
                    }
                    if ($packagedPreviewInstaller.Contains("`$InstallRoot = Join-Path `$env:LOCALAPPDATA")) {
                        Add-Error 'Packaged transport preview service must not run from LocalAppData'
                    }
                    else {
                        Add-Pass 'Packaged transport preview service is installed under a protected machine path'
                    }
                }
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
