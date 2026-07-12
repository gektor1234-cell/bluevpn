import 'package:bluevpn_ui/services/route_failure_cooldown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'route failures use bounded exponential cooldown and success clears it',
    () {
      final cooldown = RouteFailureCooldown();
      final now = DateTime.utc(2026, 7, 12, 12);

      expect(
        cooldown.recordFailure('nl2|vless', now: now),
        const Duration(minutes: 1),
      );
      expect(cooldown.isCooling('nl2|vless', now: now), isTrue);
      expect(cooldown.failureCount('nl2|vless'), 1);
      expect(
        cooldown.recordFailure('nl2|vless', now: now),
        const Duration(minutes: 3),
      );
      expect(
        cooldown.recordFailure('nl2|vless', now: now),
        const Duration(minutes: 10),
      );
      expect(
        cooldown.recordFailure('nl2|vless', now: now),
        const Duration(minutes: 30),
      );
      expect(
        cooldown.recordFailure('nl2|vless', now: now),
        const Duration(minutes: 30),
      );

      cooldown.recordSuccess('nl2|vless');
      expect(cooldown.isCooling('nl2|vless', now: now), isFalse);
      expect(cooldown.failureCount('nl2|vless'), 0);
    },
  );

  test('healthy candidates sort before cooling candidates', () {
    final cooldown = RouteFailureCooldown();
    final now = DateTime.utc(2026, 7, 12, 12);
    cooldown.recordFailure('wg', now: now);

    expect(cooldown.compare('vless', 'wg', now: now), lessThan(0));
    expect(cooldown.compare('wg', 'vless', now: now), greaterThan(0));
    expect(
      cooldown.compare('wg', 'vless', now: now.add(const Duration(minutes: 2))),
      0,
    );
  });
}
