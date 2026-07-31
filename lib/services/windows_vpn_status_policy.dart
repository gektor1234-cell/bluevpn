enum GreenVpnWindowsManagedTunnelState { connected, disconnected, unknown }

const List<String> _greenVpnWindowsSingleProcessStateKeys = <String>[
  'wireGuardState',
  'amneziaWgState',
];

const List<List<String>> _greenVpnWindowsPairedProcessStateKeys =
    <List<String>>[
      <String>['hysteriaClientState', 'hysteriaTunState'],
      <String>['vlessClientState', 'vlessTunState'],
      <String>['naiveClientState', 'naiveTunState'],
      <String>['dnsttClientState', 'dnsttTunState'],
    ];

const Set<String> _greenVpnWindowsStoppedStates = <String>{
  'missing',
  'stopped',
};

String _greenVpnWindowsStatusValue(Object? value) =>
    (value ?? '').toString().trim().toLowerCase();

GreenVpnWindowsManagedTunnelState greenVpnClassifyWindowsManagedTunnelStatus({
  required bool requestOk,
  required Map<String, dynamic> data,
}) {
  if (!requestOk || data['ok'] != true) {
    return GreenVpnWindowsManagedTunnelState.unknown;
  }

  if (_greenVpnWindowsStatusValue(data['tunnelState']) == 'running') {
    return GreenVpnWindowsManagedTunnelState.connected;
  }
  for (final key in _greenVpnWindowsSingleProcessStateKeys) {
    if (_greenVpnWindowsStatusValue(data[key]) == 'running') {
      return GreenVpnWindowsManagedTunnelState.connected;
    }
  }
  for (final pair in _greenVpnWindowsPairedProcessStateKeys) {
    if (pair.every(
      (key) => _greenVpnWindowsStatusValue(data[key]) == 'running',
    )) {
      return GreenVpnWindowsManagedTunnelState.connected;
    }
  }

  final componentKeys = <String>{
    'tunnelState',
    ..._greenVpnWindowsSingleProcessStateKeys,
    for (final pair in _greenVpnWindowsPairedProcessStateKeys) ...pair,
  };
  final componentStates = componentKeys
      .where(data.containsKey)
      .map((key) => _greenVpnWindowsStatusValue(data[key]))
      .where((state) => state.isNotEmpty)
      .toList(growable: false);
  if (componentStates.isEmpty) {
    return GreenVpnWindowsManagedTunnelState.unknown;
  }
  if (componentStates.every(_greenVpnWindowsStoppedStates.contains)) {
    return GreenVpnWindowsManagedTunnelState.disconnected;
  }
  return GreenVpnWindowsManagedTunnelState.unknown;
}
