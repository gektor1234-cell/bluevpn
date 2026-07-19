import 'package:flutter_test/flutter_test.dart';
import 'package:greenvpn/services/server_location_policy.dart';

void main() {
  test('all physical routes in one country share one public location', () {
    final stable = greenVpnServerLocationId(
      serverId: 'tw-7879598-nl1',
      country: 'NL',
      city: 'Amsterdam',
    );
    final protected = greenVpnServerLocationId(
      serverId: 'nl2-hysteria2-canary',
      country: 'nl',
      city: 'Amsterdam',
    );

    expect(stable, 'country:NL');
    expect(protected, stable);
    expect(
      greenVpnServerLocationTitle(
        serverTitle: 'Netherlands #2',
        country: 'NL',
        city: 'Amsterdam',
      ),
      'Нидерланды',
    );
  });

  test('different countries stay separate and transport names stay hidden', () {
    expect(
      greenVpnServerLocationId(
        serverId: 'ruvds-2584554-ld8',
        country: 'GB',
        city: 'London',
      ),
      'country:GB',
    );
    expect(
      greenVpnServerLocationTitle(
        serverTitle: 'RUVDS London #1 WireGuard',
        country: 'GB',
        city: 'London',
      ),
      'Лондон',
    );
    expect(
      greenVpnServerLocationId(
        serverId: 'another-london-route',
        country: 'UK',
        city: 'London',
      ),
      'country:GB',
    );
  });

  test('unknown countries use a clean server supplied title', () {
    expect(
      greenVpnServerLocationTitle(
        serverTitle: 'Sweden #6 Hysteria2 Preview',
        country: 'SE',
        city: 'Stockholm',
      ),
      'Sweden',
    );
  });

  test('every public location has a numeric latency label', () {
    expect(greenVpnPublicLatencyLabel(null), '0 мс');
    expect(greenVpnPublicLatencyLabel(-1), '0 мс');
    expect(greenVpnPublicLatencyLabel(0), '0 мс');
    expect(greenVpnPublicLatencyLabel(27), '27 мс');
  });

  test('legacy catalog entries default to free while premium stays locked', () {
    expect(greenVpnNormalizeServerAccessTier(null), 'free');
    expect(greenVpnNormalizeServerAccessTier('PREMIUM'), 'premium');
    expect(
      greenVpnServerAllowedForSubscription(
        rawTier: 'premium',
        hasPaidSubscription: false,
      ),
      isFalse,
    );
    expect(
      greenVpnServerAllowedForSubscription(
        rawTier: 'premium',
        hasPaidSubscription: true,
      ),
      isTrue,
    );
  });

  test('picker shows one ready representative per location', () {
    const candidates = <({String id, String location, bool auto, bool ready})>[
      (id: 'auto', location: 'auto', auto: true, ready: true),
      (id: 'nl-fast', location: 'country:NL', auto: false, ready: true),
      (id: 'nl-reserve', location: 'country:NL', auto: false, ready: false),
      (id: 'gb-unpaid', location: 'country:GB', auto: false, ready: false),
    ];

    final visible = greenVpnVisibleLocationRepresentatives(
      candidates: candidates,
      isAutomatic: (candidate) => candidate.auto,
      isReady: (candidate) => candidate.ready,
      locationIdOf: (candidate) => candidate.location,
    );

    expect(visible.map((candidate) => candidate.id), <String>[
      'auto',
      'nl-fast',
    ]);
  });

  test('manual location never falls through to a different country', () {
    const routes = <({String id, String location})>[
      (id: 'nl-fast', location: 'country:NL'),
      (id: 'gb-primary', location: 'country:GB'),
      (id: 'gb-reserve', location: 'country:GB'),
      (id: 'nl-reserve', location: 'country:NL'),
    ];

    final manual = greenVpnInternalCandidatesForLocation(
      candidates: routes,
      automatic: false,
      selectedLocationId: 'country:GB',
      selectedRouteId: 'gb-reserve',
      locationIdOf: (route) => route.location,
      routeIdOf: (route) => route.id,
    );
    expect(manual.map((route) => route.id), <String>[
      'gb-reserve',
      'gb-primary',
    ]);

    final automatic = greenVpnInternalCandidatesForLocation(
      candidates: routes,
      automatic: true,
      selectedLocationId: 'country:GB',
      selectedRouteId: 'gb-reserve',
      locationIdOf: (route) => route.location,
      routeIdOf: (route) => route.id,
    );
    expect(automatic, routes);
  });
}
