class SocialOnlyState {
  final bool enabled;
  final List<String> selectedApps;
  final String lastAppliedMode; // "full_tunnel" | "social_only"
  final List<String> lastAppliedAllowedIps;
  final DateTime? lastAppliedAt;

  const SocialOnlyState({
    required this.enabled,
    required this.selectedApps,
    required this.lastAppliedMode,
    required this.lastAppliedAllowedIps,
    required this.lastAppliedAt,
  });

  factory SocialOnlyState.initial() {
    return const SocialOnlyState(
      enabled: false,
      selectedApps: [],
      lastAppliedMode: 'full_tunnel',
      lastAppliedAllowedIps: [],
      lastAppliedAt: null,
    );
  }

  SocialOnlyState copyWith({
    bool? enabled,
    List<String>? selectedApps,
    String? lastAppliedMode,
    List<String>? lastAppliedAllowedIps,
    DateTime? lastAppliedAt,
  }) {
    return SocialOnlyState(
      enabled: enabled ?? this.enabled,
      selectedApps: selectedApps ?? this.selectedApps,
      lastAppliedMode: lastAppliedMode ?? this.lastAppliedMode,
      lastAppliedAllowedIps:
          lastAppliedAllowedIps ?? this.lastAppliedAllowedIps,
      lastAppliedAt: lastAppliedAt ?? this.lastAppliedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'selectedApps': selectedApps,
      'lastAppliedMode': lastAppliedMode,
      'lastAppliedAllowedIps': lastAppliedAllowedIps,
      'lastAppliedAt': lastAppliedAt?.toIso8601String(),
    };
  }

  factory SocialOnlyState.fromJson(Map<String, dynamic> json) {
    return SocialOnlyState(
      enabled: (json['enabled'] as bool?) ?? false,
      selectedApps: (json['selectedApps'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      lastAppliedMode: (json['lastAppliedMode'] as String?) ?? 'full_tunnel',
      lastAppliedAllowedIps: (json['lastAppliedAllowedIps'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      lastAppliedAt: json['lastAppliedAt'] != null
          ? DateTime.tryParse(json['lastAppliedAt'].toString())
          : null,
    );
  }
}
