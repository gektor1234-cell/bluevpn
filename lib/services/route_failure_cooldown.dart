class RouteFailureCooldown {
  RouteFailureCooldown({
    this.schedule = const <Duration>[
      Duration(minutes: 1),
      Duration(minutes: 3),
      Duration(minutes: 10),
      Duration(minutes: 30),
    ],
  }) : assert(schedule.isNotEmpty);

  final List<Duration> schedule;
  final Map<String, _RouteFailureState> _states =
      <String, _RouteFailureState>{};

  Duration recordFailure(String key, {DateTime? now}) {
    final normalized = key.trim();
    if (normalized.isEmpty) return Duration.zero;
    final current = _states[normalized];
    final failures = (current?.failures ?? 0) + 1;
    final duration = schedule[(failures - 1).clamp(0, schedule.length - 1)];
    final clock = now ?? DateTime.now();
    _states[normalized] = _RouteFailureState(
      failures: failures,
      until: clock.add(duration),
    );
    return duration;
  }

  void recordSuccess(String key) {
    _states.remove(key.trim());
  }

  bool isCooling(String key, {DateTime? now}) {
    final state = _states[key.trim()];
    if (state == null) return false;
    return state.until.isAfter(now ?? DateTime.now());
  }

  DateTime? coolingUntil(String key, {DateTime? now}) {
    return isCooling(key, now: now) ? _states[key.trim()]?.until : null;
  }

  int compare(String left, String right, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final leftUntil = coolingUntil(left, now: clock);
    final rightUntil = coolingUntil(right, now: clock);
    if (leftUntil == null && rightUntil == null) return 0;
    if (leftUntil == null) return -1;
    if (rightUntil == null) return 1;
    return leftUntil.compareTo(rightUntil);
  }

  int failureCount(String key) => _states[key.trim()]?.failures ?? 0;
}

class _RouteFailureState {
  const _RouteFailureState({required this.failures, required this.until});

  final int failures;
  final DateTime until;
}
