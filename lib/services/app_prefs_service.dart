import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/social_only_state.dart';

class AppPrefsService {
  static const String _socialOnlyStateKey = 'bluevpn_social_only_state';

  Future<SocialOnlyState> loadSocialOnlyState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_socialOnlyStateKey);

    if (raw == null || raw.trim().isEmpty) {
      return SocialOnlyState.initial();
    }

    try {
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
      return SocialOnlyState.fromJson(jsonMap);
    } catch (_) {
      return SocialOnlyState.initial();
    }
  }

  Future<void> saveSocialOnlyState(SocialOnlyState state) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(state.toJson());
    await prefs.setString(_socialOnlyStateKey, raw);
  }

  Future<void> setSocialOnlyEnabled(bool enabled) async {
    final current = await loadSocialOnlyState();
    await saveSocialOnlyState(current.copyWith(enabled: enabled));
  }

  Future<void> setSelectedSocialApps(List<String> apps) async {
    final current = await loadSocialOnlyState();
    await saveSocialOnlyState(
      current.copyWith(selectedApps: List<String>.from(apps)),
    );
  }

  Future<void> setLastApplied({
    required String mode,
    required List<String> allowedIps,
  }) async {
    final current = await loadSocialOnlyState();
    await saveSocialOnlyState(
      current.copyWith(
        lastAppliedMode: mode,
        lastAppliedAllowedIps: List<String>.from(allowedIps),
        lastAppliedAt: DateTime.now(),
      ),
    );
  }

  Future<void> resetSocialOnly() async {
    await saveSocialOnlyState(SocialOnlyState.initial());
  }
}
