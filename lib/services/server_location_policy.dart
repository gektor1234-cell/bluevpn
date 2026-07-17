String greenVpnServerLocationId({
  required String serverId,
  required String country,
  required String city,
}) {
  final normalizedCountry = country.trim().toUpperCase();
  if (normalizedCountry == 'UK') return 'country:GB';
  if (normalizedCountry.isNotEmpty) return 'country:$normalizedCountry';

  final normalizedCity = city.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '-',
  );
  if (normalizedCity.isNotEmpty) return 'city:$normalizedCity';

  final normalizedServerId = serverId.trim().toLowerCase();
  return normalizedServerId.isEmpty ? 'unknown' : 'server:$normalizedServerId';
}

String greenVpnServerLocationTitle({
  required String serverTitle,
  required String country,
  required String city,
}) {
  switch (country.trim().toUpperCase()) {
    case 'NL':
      return 'Нидерланды';
    case 'GB':
    case 'UK':
      return 'Лондон';
  }

  var title = serverTitle.trim();
  title = title
      .replaceAll(RegExp(r'\s*#\s*\d+\b'), '')
      .replaceAll(RegExp(r'\bRU\s*VDS\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bRUVDS\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bTimeWeb\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bWireGuard\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bAmneziaWG\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bHysteria2\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bVLESS\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bNaive\s*HTTPS\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bdnstt\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bprotected\s+preview\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bpreview\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (title.isNotEmpty) return title;
  if (city.trim().isNotEmpty) return city.trim();
  if (country.trim().isNotEmpty) return country.trim().toUpperCase();
  return 'Локация';
}

String greenVpnPublicLatencyLabel(int? latencyMs) {
  final normalized = latencyMs == null || latencyMs < 0 ? 0 : latencyMs;
  return '$normalized мс';
}

List<T> greenVpnVisibleLocationRepresentatives<T>({
  required Iterable<T> candidates,
  required bool Function(T candidate) isAutomatic,
  required bool Function(T candidate) isReady,
  required String Function(T candidate) locationIdOf,
}) {
  final result = <T>[];
  final seenLocations = <String>{};
  var automaticAdded = false;

  for (final candidate in candidates) {
    if (isAutomatic(candidate)) {
      if (!automaticAdded) {
        result.add(candidate);
        automaticAdded = true;
      }
      continue;
    }
    if (!isReady(candidate)) continue;
    if (seenLocations.add(locationIdOf(candidate))) result.add(candidate);
  }
  return result;
}

List<T> greenVpnInternalCandidatesForLocation<T>({
  required Iterable<T> candidates,
  required bool automatic,
  required String selectedLocationId,
  required String selectedRouteId,
  required String Function(T candidate) locationIdOf,
  required String Function(T candidate) routeIdOf,
}) {
  final ordered = candidates.toList(growable: false);
  if (automatic) return ordered;

  final matching = ordered
      .where((candidate) => locationIdOf(candidate) == selectedLocationId)
      .toList(growable: true);
  final preferredIndex = matching.indexWhere(
    (candidate) => routeIdOf(candidate) == selectedRouteId,
  );
  if (preferredIndex > 0) {
    final preferred = matching.removeAt(preferredIndex);
    matching.insert(0, preferred);
  }
  return matching;
}
