import '../models/social_only_state.dart';
import 'app_prefs_service.dart';
import 'managed_config_service.dart';
import 'vpn_backend_service.dart';

class SocialOnlyApplyResult {
  final bool ok;
  final String message;
  final SocialOnlyState state;

  const SocialOnlyApplyResult({
    required this.ok,
    required this.message,
    required this.state,
  });
}

class SocialOnlyService {
  final AppPrefsService prefsService;
  final ManagedConfigService configService;
  final VpnBackendService backendService;

  SocialOnlyService({
    required this.prefsService,
    required this.configService,
    required this.backendService,
  });

  Future<SocialOnlyState> loadState() {
    return prefsService.loadSocialOnlyState();
  }

  Future<SocialOnlyApplyResult> setEnabled(bool enabled) async {
    final current = await prefsService.loadSocialOnlyState();
    final updated = current.copyWith(enabled: enabled);
    await prefsService.saveSocialOnlyState(updated);
    return _apply(updated);
  }

  Future<SocialOnlyApplyResult> setSelectedApps(List<String> apps) async {
    final current = await prefsService.loadSocialOnlyState();
    final updated = current.copyWith(selectedApps: List<String>.from(apps));
    await prefsService.saveSocialOnlyState(updated);
    return _apply(updated);
  }

  Future<SocialOnlyApplyResult> reapplyCurrent() async {
    final current = await prefsService.loadSocialOnlyState();
    return _apply(current);
  }

  Future<SocialOnlyApplyResult> _apply(SocialOnlyState state) async {
    try {
      final connected = await backendService.isVpnConnected();

      final buildResult = await configService.buildManagedConfig(
        socialOnlyEnabled: state.enabled,
        selectedApps: state.selectedApps,
      );

      final backendResult = await backendService.applyManagedConfig(
        managedConfigPath: buildResult.managedConfigPath,
        restartIfConnected: connected,
      );

      final updatedState = state.copyWith(
        lastAppliedMode: buildResult.mode,
        lastAppliedAllowedIps: buildResult.allowedIps,
        lastAppliedAt: DateTime.now(),
      );

      await prefsService.saveSocialOnlyState(updatedState);

      return SocialOnlyApplyResult(
        ok: backendResult.ok,
        message: backendResult.message,
        state: updatedState,
      );
    } catch (e) {
      final current = await prefsService.loadSocialOnlyState();
      return SocialOnlyApplyResult(
        ok: false,
        message: 'SocialOnly apply failed: $e',
        state: current,
      );
    }
  }
}
